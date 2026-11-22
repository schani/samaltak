#include "c4_heap.h"

#if SAMALTAK_C4_SUPPORTED

#include "samaltak.h"
#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#include <unistd.h>

/* Single mutator; worker traces/sweeps only side metadata and the atomic
 * shadow graph. The mutator never waits for the worker, runs its work, or
 * has to flush a bounded buffer. */
_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LONG_LOCK_FREE == 2 &&
    ATOMIC_LLONG_LOCK_FREE == 2, "C4 requires native word atomics");

enum c4_phase {
    C4_IDLE, C4_ROOTS, C4_MARK, C4_CLOSE, C4_CLEAR, C4_SWEEP,
    C4_ENUM_ROOTS, C4_ENUM_TRACE, C4_ENUM_READY
};
#define C4_FREE UINT32_MAX
#define C4_RESERVED (UINT32_MAX - 1u)
#define C4_FORBID 1u
#define C4_CODE_BYTES 2u

#define relaxed(p) atomic_load_explicit((p), memory_order_relaxed)
#define acquire(p) atomic_load_explicit((p), memory_order_acquire)
#define put_relaxed(p, v) atomic_store_explicit((p), (v), memory_order_relaxed)
#define release(p, v) atomic_store_explicit((p), (v), memory_order_release)

/* Starts are >=2 words apart, so each pair of words shares one cell.
 * Publish extent, start parity and ref count together: splitting a free
 * run may reuse a cell at the opposite parity. Links encode keys + 1. */
typedef struct {
    _Atomic uint64_t layout;        /* words:31, start parity:1, refs:32 */
    _Atomic uint32_t seen;
    _Atomic uint32_t context_limit; /* saved cycle-start prefix + 1, or 0 */
    uint32_t weak_start;           /* immutable while live */
    uint32_t link;                 /* mark queue while live, bin while free */
} c4_cell;

static uint64_t layout_for(uint32_t at, uint32_t words, uint32_t refs)
{
    return ((uint64_t)words << 33) | ((uint64_t)(at & 1) << 32) | refs;
}

static uint32_t layout_words(uint64_t layout)
{
    return (uint32_t)(layout >> 33);
}

static bool layout_at(uint64_t layout, uint32_t at)
{
    return layout_words(layout) && ((layout >> 32) & 1) == (at & 1);
}

enum { SHADOW_CHUNK = 64 }; /* arena words; aligned independently of object starts */

enum { BIN_GROUPS = 4, BINS = BIN_GROUPS * 64 };

typedef struct {
    _Atomic uint32_t swept[BINS]; /* single worker pushes; mutator pops */
    _Atomic uint64_t swept_mask[BIN_GROUPS];
    uint32_t split[BINS];         /* mutator-only split remainders */
    uint64_t split_mask[BIN_GROUPS];
} c4_bins;

enum {
    SMALL_BYTES = 32, INTERVAL_BYTES = 48,
    REGION_BYTES = 16 * 1024, REGION_COUNT = 4, BANKS = 2,
    SMALL_SLOTS = REGION_BYTES / SMALL_BYTES,
    INTERVAL_SLOTS = REGION_BYTES / INTERVAL_BYTES,
    SMALL_IDS = (REGION_COUNT - 1) * SMALL_SLOTS,
    INTERVAL_IDS = (REGION_COUNT - 1) * INTERVAL_SLOTS,
    MOVE_IDS = SMALL_IDS + INTERVAL_IDS,
    MOVE_INSPECTIONS = 64, MOVE_BYTES = 4096, MOVE_VIEW_STRIDE = 5,
    NO_REGION = REGION_COUNT
};

enum plain_kind { PLAIN_POINT, PLAIN_MESSAGE, PLAIN_ASSOCIATION, PLAIN_INTERVAL, PLAIN_KINDS };

typedef struct {
    c4_cell trace;
    _Atomic uint64_t shadow[4];   /* class and up to three logical oops */
    uintptr_t addr;               /* mutator only */
    uint32_t next_free;
} c4_handle;

typedef struct {
    uint32_t used, high_water;
    uint32_t ids[SMALL_SLOTS];    /* initialized prefix; immutable while sealed */
} c4_region;

typedef struct {
    uintptr_t pool;
    uint32_t stride, refs, slots, first_id, end_id;
    c4_region region[REGION_COUNT];
    _Atomic uint32_t occupied;    /* logical bodies; excludes evacuation aliases */

    /* ROOTS publishes the sealed source. The worker reads this descriptor
     * during SWEEP and reports source_live before publishing IDLE. */
    uint32_t source, source_live, reserve, next_source, cursor;
    uint32_t free_ids, retired_head, retired_tail;
    uint32_t peak, body_slots, body_peak;
    uint64_t moved, inspected, released, dense, source_reused, fallback;
} c4_move_bank;

typedef struct {
    uintptr_t tokens;
    uint64_t plain_classes[PLAIN_KINDS];
    c4_handle handles[MOVE_IDS];
    c4_move_bank bank[BANKS];
    uint32_t bank_count, first_bank, max_inspected, max_copied;
    uint64_t moved_kind[PLAIN_KINDS];
} c4_move_state;

/* One versioned view at a time. First writes preserve the old shadow
 * value. The version release precedes the corresponding shadow release. */
typedef struct {
    _Atomic uint64_t tag, old;     /* view version, then shadow word index */
} c4_view_word;

enum { VIEW_LOG_ENTRIES = 1 << 16, VIEW_LOG_PROBES = 8 };

static struct {
    c4_view_word *words;            /* fixed bounded first-write log */
    _Atomic uint64_t *visited;      /* epoch with seen/born low bit */
    _Atomic uint32_t overflow;
    uint32_t version;
    uint64_t cls, exclude_a, exclude_b;
    uint64_t *roots;                /* filled in interpreter root slices */
    uint32_t nroots, max_roots;
    bool bytes_invalid;             /* mutator only */
    int32_t count;                  /* published with ENUM_READY; -1 on overflow */
    uint64_t ids[C4_ENUM_LIMIT];
} view;

static struct {
    uintptr_t base;
    uint32_t capacity;              /* words */
    uint64_t context_class, method_class, nil, bytes_class, wide_class;
    c4_bins bins;
    c4_cell *cells;
    _Atomic uint64_t *shadow;
    _Atomic uint64_t *chunk_tags;
    c4_move_state *moving;

    _Atomic uint32_t phase, epoch;
    _Atomic uint32_t inbox;         /* mutator push / worker exchange */
    _Atomic uint32_t top, occupied; /* words */
    _Atomic uint32_t wake, has_weak, has_forwarding;
    _Atomic uint64_t weak_pending, weak_cleared;

    /* Mutator-owned, apart from explicitly atomic publication above. */
    size_t threshold, since_begin;  /* bytes */
    bool started, pressure, raw_read;
    uint64_t unpublished;         /* sole private reserve; cannot cross a poll */
    uint32_t unpublished_words;   /* exact body size, excluding extent padding */
    uint64_t imports, cycles_started, closed, close_retries, allocated, reused, failed;

    uint64_t shadow_tag, chunk_inits;
    uint32_t max_publish_refs, max_chunk_init_refs;

    /* Worker-owned; reports are cumulative as of the last completed sweep. */
    _Atomic uint64_t cycles_completed, marked, traced_edges, reclaimed, reclaimed_bytes;
} heap;

static _Noreturn void bad_contract(const char *what)
{
    fprintf(stderr, "C4 heap invariant: %s\n", what);
    abort();
}

void c4_heap_enter_raw_read(void)
{
    if (!heap.started || heap.unpublished || heap.raw_read)
        bad_contract("invalid synchronous raw read entry");
    heap.raw_read = true;
}

void c4_heap_leave_raw_read(void)
{
    if (!heap.raw_read) bad_contract("unbalanced synchronous raw read exit");
    heap.raw_read = false;
}

static inline void require_raw_read_quiescence(const char *what)
{
    if (heap.raw_read) bad_contract(what);
}

static bool object_size(size_t bytes, uint32_t *words)
{
    if (bytes < 16 || (bytes & 7) || bytes / 8 > heap.capacity) return false;
    *words = (uint32_t)(bytes / 8);
    return true;
}

static bool offset(uint64_t oop_value, uint32_t *at)
{
    uint64_t delta = oop_value - heap.base;
    if ((delta & 7) || delta / 8 >= heap.capacity) return false;
    *at = (uint32_t)(delta / 8);
    return true;
}

static bool token_id(uint64_t value, uint32_t *id)
{
    if (!heap.moving) return false;
    uint64_t delta = value - heap.moving->tokens;
    if ((delta & 7) || delta / 8 >= (heap.moving->bank_count == 2 ? MOVE_IDS : SMALL_IDS)) return false;
    *id = (uint32_t)(delta / 8);
    return true;
}

bool c4_heap_movable(uint64_t obj)
{
    uint32_t id;
    return token_id(obj, &id);
}

uint64_t c4_heap_address(uint64_t obj)
{
    obj = c4_heap_canonical(obj);
    uint32_t id;
    if (!token_id(obj, &id)) return obj;
    c4_handle *handle = &heap.moving->handles[id];
    if ((uint32_t)relaxed(&handle->trace.layout) >= C4_RESERVED || !handle->addr)
        bad_contract("resolve without live moving handle");
    return handle->addr;
}

/* Pinned keys are word offsets. Both banks share one disjoint handle tail. */
static bool key_of(uint64_t value, uint32_t *at)
{
    uint32_t id;
    if (token_id(value, &id)) {
        *at = heap.capacity + id;
        return true;
    }
    return offset(value, at) && *at < acquire(&heap.top);
}

static _Atomic uint64_t *shadow_row(uint32_t at)
{
    return at < heap.capacity ? &heap.shadow[at + 1] :
        heap.moving->handles[at - heap.capacity].shadow;
}

static c4_cell *cell_at(uint32_t at)
{
    if (at >= heap.capacity) return &heap.moving->handles[at - heap.capacity].trace;
    return heap.cells + at / 2;
}

static uint32_t refs_at(uint64_t layout, uint32_t at)
{
    return at >= heap.capacity || layout_at(layout, at) ? (uint32_t)layout : C4_FREE;
}

/* Pinned shadow headers are zero, a forwarding target, a raw borrow marker,
 * or an odd lazy-shadow incarnation tag (> C4_FORBID).
 * A weak reader may sample a slot just before CLEAR rewrites it, so keep
 * the marker and cell start through sweep. Only private reserve resets it. */
static uint64_t forward_target(uint64_t marker)
{
    return (marker & 7) ? 0 : marker;
}

static uint64_t forward_at(uint32_t at)
{
    return forward_target(acquire(&heap.shadow[at]));
}

bool c4_heap_has_forwarding(void)
{
    return acquire(&heap.has_forwarding) != 0;
}

static uint64_t canonical(uint64_t obj)
{
    uint32_t at;
    if (offset(obj, &at) && at < acquire(&heap.top) &&
            layout_at(acquire(&cell_at(at)->layout), at)) {
        uint64_t target = forward_at(at);
        if (target) return target;
    }
    return obj;
}

uint64_t c4_heap_canonical(uint64_t obj)
{
    return c4_heap_has_forwarding() ? canonical(obj) : obj;
}

static bool viewing(unsigned phase)
{
    return phase == C4_ENUM_ROOTS || phase == C4_ENUM_TRACE;
}

static uint32_t view_row(uint32_t at)
{
    return at < heap.capacity ? at : heap.capacity + MOVE_VIEW_STRIDE * (at - heap.capacity);
}

static _Atomic uint64_t *view_stamp(uint32_t at)
{
    size_t i = at < heap.capacity ? at / 2 :
        ((size_t)heap.capacity + 1) / 2 + at - heap.capacity;
    return &view.visited[i];
}

static uint64_t view_seen(void) { return (uint64_t)view.version << 1; }
static uint64_t view_born(void) { return view_seen() | 1; }

static c4_view_word *view_word(uint32_t key, bool insert)
{
    uint32_t hash = key;
    hash ^= hash >> 16;
    hash *= UINT32_C(0x7feb352d);
    hash ^= hash >> 15;
    hash *= UINT32_C(0x846ca68b);
    hash ^= hash >> 16;
    for (unsigned n = 0; n < VIEW_LOG_PROBES; ++n) {
        c4_view_word *word = &view.words[(hash + n) & (VIEW_LOG_ENTRIES - 1)];
        uint64_t tag = acquire(&word->tag);
        if ((uint32_t)(tag >> 32) != view.version)
            return insert ? word : NULL;
        if ((uint32_t)tag == key) return word;
    }
    return NULL;
}

static void preserve_word(uint32_t at, uint32_t key, _Atomic uint64_t *slot)
{
    /* New births cannot appear in the cut. Do not spend version budget
     * on the initialization or later stores to such an owner. */
    if (relaxed(&view.overflow) || relaxed(view_stamp(at)) == view_born()) return;
    c4_view_word *word = view_word(key, true);
    if (!word) {
        release(&view.overflow, 1);
        return;
    }
    uint64_t tag = ((uint64_t)view.version << 32) | key;
    if (relaxed(&word->tag) == tag) return;
    put_relaxed(&word->old, relaxed(slot));
    release(&word->tag, tag);
}

static uint64_t read_view(uint32_t key, _Atomic uint64_t *slot)
{
    const c4_view_word *word = view_word(key, false);
    if (word) return relaxed(&word->old);
    uint64_t value = acquire(slot);
    /* An acquired new store orders its preceding version publication.
     * Exhaustion poisons the whole result before the corresponding store. */
    word = view_word(key, false);
    return word ? relaxed(&word->old) : value;
}

static bool marking(unsigned phase)
{
    return phase == C4_ROOTS || phase == C4_MARK || phase == C4_CLOSE;
}

/* Used only after ACK, while this cycle's epoch is still current. Only
 * the mutator can allocate, so a load/filter cannot straddle address reuse.
 * The worker filters before exposing any current-cycle white addresses. */
static bool post_close_live(uint64_t value)
{
    if ((value & 7) || value == heap.nil) return true;
    uint32_t at;
    if (!key_of(value, &at)) return false;
    c4_cell *cell = cell_at(at);
    return refs_at(acquire(&cell->layout), at) < C4_RESERVED &&
        relaxed(&cell->seen) == relaxed(&heap.epoch);
}

static c4_cell *body_owner(uint64_t obj, uint32_t *at, uint32_t *refs)
{
    if (!key_of(obj, at))
        bad_contract("body access outside heap");
    c4_cell *cell = cell_at(*at);
    *refs = refs_at(relaxed(&cell->layout), *at);
    if (*refs >= C4_RESERVED) bad_contract("body access without live owner");
    return cell;
}

static void wake_worker(void)
{
    atomic_fetch_add_explicit(&heap.wake, 1, memory_order_release);
    syscall(SYS_futex, &heap.wake, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
}

/* Atomic claim permits at most one queue entry per object per cycle.
 * Successful caller owns its link for the rest of this cycle. */
static c4_cell *claim(uint64_t value, uint32_t *at)
{
    if (!key_of(value, at)) return NULL;
    c4_cell *cell = cell_at(*at);
    if (refs_at(acquire(&cell->layout), *at) >= C4_RESERVED) return NULL;
    uint32_t epoch = relaxed(&heap.epoch);
    if (relaxed(&cell->seen) == epoch ||
        atomic_exchange_explicit(&cell->seen, epoch, memory_order_acq_rel) == epoch)
        return NULL;
    return cell;
}

static void shade_mutator(uint64_t value)
{
    uint32_t at;
    c4_cell *cell = claim(value, &at);
    if (!cell) return;
    uint32_t head = relaxed(&heap.inbox);
    cell->link = head;
    if (!atomic_compare_exchange_strong_explicit(&heap.inbox, &head, at + 1,
            memory_order_release, memory_order_relaxed)) {
        /* No other producer. The worker can only exchange head for zero,
         * so the second attempt cannot lose, even if worker is descheduled. */
        cell->link = 0;
        if (head || !atomic_compare_exchange_strong_explicit(&heap.inbox,
                &head, at + 1, memory_order_release, memory_order_relaxed))
            bad_contract("inbox has multiple producers");
    }
    if (!head) wake_worker();
}

static c4_cell *live_pinned(uint64_t obj, uint32_t *at)
{
    if (!offset(obj, at) || *at >= acquire(&heap.top)) return NULL;
    c4_cell *cell = cell_at(*at);
    return refs_at(acquire(&cell->layout), *at) < C4_RESERVED ? cell : NULL;
}

void c4_heap_forbid_become(uint64_t obj)
{
    uint32_t at;
    if (!heap.started || !live_pinned(obj, &at) || forward_at(at))
        bad_contract("raw borrow without live unforwarded pinned owner");
    uint64_t marker = relaxed(&heap.shadow[at]);
    if (marker == C4_CODE_BYTES) return;
    if (marker > C4_FORBID) bad_contract("raw borrow with lazy reference shadow");
    put_relaxed(&heap.shadow[at], C4_FORBID);
}

/* Monotone within the body incarnation. Keeping an old mark after code
 * retirement can only cause an unnecessary invalidation, not retain an oop. */
void c4_heap_note_code_bytes(uint64_t obj)
{
    uint32_t at;
    if (!heap.started || !live_pinned(obj, &at) ||
            (uint32_t)relaxed(&cell_at(at)->layout) != 0)
        bad_contract("code storage must be a live pinned raw body");
    uint64_t marker = relaxed(&heap.shadow[at]);
    if (marker > C4_CODE_BYTES) bad_contract("invalid code storage marker");
    put_relaxed(&heap.shadow[at], C4_CODE_BYTES);
}

bool c4_heap_is_code_bytes(uint64_t obj)
{
    require_raw_read_quiescence("byte write during synchronous raw read");
    uint32_t at;
    if (!live_pinned(c4_heap_canonical(obj), &at)) return false;
    return relaxed(&heap.shadow[at]) == C4_CODE_BYTES;
}

/* Mutator only. Tags start at zero; no generation can repeat. */
uint64_t c4_heap_cache_generation = 1;

void c4_heap_invalidate_cache(void)
{
    if (++c4_heap_cache_generation == 0) bad_contract("dispatch cache generation exhausted");
}

void c4_heap_use_cached_method(uint64_t method)
{
    /* A hit can introduce a frame or primitive root absent from the
     * arm-time snapshot. CLOSE still accepts work and must retry. */
    if (marking(acquire(&heap.phase))) shade_mutator(method);
}

bool c4_heap_become_forward(uint64_t from, uint64_t to)
{
    require_raw_read_quiescence("forwarding during synchronous raw read");
    uint32_t src, dst;
    if (!heap.started || !heap.bytes_class || from == to || from == heap.nil ||
        from == heap.context_class || from == heap.bytes_class ||
        from == heap.wide_class || to == heap.nil || to == heap.context_class ||
        to == heap.bytes_class || to == heap.wide_class ||
        c4_heap_plain_class(from) || c4_heap_plain_class(to))
        return false;

    unsigned phase = acquire(&heap.phase);
    /* After ACK only current-cycle live operands are eligible. While marking
     * the worker cannot reclaim before this call finishes. */
    if ((phase == C4_CLEAR || phase == C4_SWEEP) &&
            (!post_close_live(from) || !post_close_live(to))) return false;
    c4_cell *source = live_pinned(from, &src);
    if (!source || !live_pinned(to, &dst) ||
        relaxed(&heap.shadow[src]) || forward_at(dst) ||
        relaxed(shadow_row(src)) != heap.bytes_class ||
        relaxed(shadow_row(dst)) != heap.wide_class) return false;

    unsigned sf = (*(const uint64_t *)(uintptr_t)from >> H_FMT_SHIFT) & H_FMT_MASK;
    unsigned tf = (*(const uint64_t *)(uintptr_t)to >> H_FMT_SHIFT) & H_FMT_MASK;
    if (sf < F_BYTES || sf > F_BYTES + 7 || (tf != F_W32 && tf != F_W32 + 1))
        return false;

    c4_heap_invalidate_cache();
    if (!relaxed(&heap.has_forwarding)) release(&heap.has_forwarding, 1);
    if (viewing(phase)) preserve_word(src, view_row(src), &heap.shadow[src]);
    if (view.cls == heap.bytes_class) view.bytes_invalid = true;
    release(&heap.shadow[src], to);
    if (marking(phase)) {
        /* RMW against claim(): if it already claimed the source, shade the
         * inserted edge; otherwise its acquire claim observes publication.
         * The original class edge is independently rooted. A white source
         * does not keep its target alive merely by acquiring forwarding. */
        uint32_t seen = atomic_fetch_or_explicit(&source->seen, 0, memory_order_acq_rel);
        if (seen == relaxed(&heap.epoch)) shade_mutator(to);
    }
    return true;
}

/* Keep the class and at least CTX_FIXED slots eager, including Context
 * stackp. The lazy suffix starts on an absolute chunk boundary. Each tag
 * belongs to at most one live owner: the next object's prefix is eager,
 * even if its header lands in a previous object's final partial chunk. */
static uint32_t lazy_start(uint32_t at)
{
    return (at + 2 + CTX_FIXED + SHADOW_CHUNK - 1) & ~(SHADOW_CHUNK - 1u);
}

static uint64_t lazy_tag(uint32_t at)
{
    if (at >= heap.capacity) return 0;
    uint64_t tag = relaxed(&heap.shadow[at]);
    return (tag & 1) && tag > C4_FORBID ? tag : 0;
}

/* A mismatched tag means implicit nil, including after splits or reuse.
 * The worker never initializes a chunk. A concurrent first store publishes
 * its initialized chunk before the edge store; the insertion barrier
 * covers marking, and after ACK weak stores cannot insert a white edge. */
static _Atomic uint64_t *shadow_field(uint32_t at, uint32_t i, uint32_t refs, bool write)
{
    if (at >= heap.capacity) return &shadow_row(at)[1 + i];
    uint32_t word = at + 2 + i;
    if (word >= lazy_start(at)) {
        uint64_t tag = lazy_tag(at);
        if (tag) {
            _Atomic uint64_t *entry = &heap.chunk_tags[word / SHADOW_CHUNK];
            if (acquire(entry) != tag) {
                if (!write) return NULL;
                uint32_t first = word & ~(SHADOW_CHUNK - 1u);
                uint32_t end = first + SHADOW_CHUNK;
                if (end > at + 2 + refs) end = at + 2 + refs;
                uint32_t j = first;
                for (; j < end; ++j) put_relaxed(&heap.shadow[j], heap.nil);
                if (j - first > heap.max_chunk_init_refs) heap.max_chunk_init_refs = j - first;
                ++heap.chunk_inits;
                release(entry, tag);
            }
        }
    }
    return &heap.shadow[word];
}

static void shade_worker(uint64_t value, uint32_t *work)
{
    uint32_t at;
    c4_cell *cell = claim(value, &at);
    if (!cell) return;
    cell->link = *work;
    *work = at + 1;
}

static bool is_context(uint32_t at, uint32_t refs)
{
    return at < heap.capacity && refs >= CTX_FIXED && heap.context_class &&
        relaxed(&heap.shadow[at + 1]) == heap.context_class;
}

static uint32_t context_snapshot_limit(uint32_t at, c4_cell *cell, uint32_t refs)
{
    /* Read stackp first. Observing a post-snapshot stackp implies observing
     * the saved bound that the mutator published before changing stackp. */
    uint64_t sp = acquire(&heap.shadow[at + 2 + CTX_STACKP]);
    uint32_t saved = acquire(&cell->context_limit);
    if (saved) return saved - 1;
    /* As in the moving collector, scan all slots for malformed stackp. */
    uint64_t n = sp >> 1;
    return (sp & 1) && n <= refs - CTX_FIXED ? CTX_FIXED + (uint32_t)n : refs;
}

/* No current-cycle white address can be reused until this whole pass ends.
 * New black owners omitted by the top snapshot cannot contain white edges. */
static uint64_t clear_weak(uint32_t limit)
{
    if (!acquire(&heap.has_weak)) return 0;
    uint32_t epoch = relaxed(&heap.epoch);
    uint64_t cleared = 0;
    for (uint32_t at = 0; at < limit; ) {
        c4_cell *cell = cell_at(at);
        uint64_t layout = acquire(&cell->layout);
        if (!layout_at(layout, at)) bad_contract("missing clear cell");
        uint32_t refs = (uint32_t)layout;
        if (refs < C4_RESERVED && relaxed(&cell->seen) == epoch) {
            for (uint32_t i = cell->weak_start; i < refs; ++i) {
                _Atomic uint64_t *slot = shadow_field(at, i, refs, false);
                if (!slot) continue;
                uint64_t prev = acquire(slot);
                uint64_t next = c4_heap_canonical(prev);
                if (!post_close_live(next)) next = heap.nil;
                if (next == prev) continue;
#ifdef SAMALTAK_C4_TEST
                extern void c4_heap_test_before_weak_cas(uint64_t obj, uint32_t i, uint64_t prev);
                c4_heap_test_before_weak_cas(heap.base + (size_t)at * 8, i, prev);
#endif
                if (atomic_compare_exchange_strong_explicit(slot, &prev, next,
                        memory_order_acq_rel, memory_order_relaxed) && next == heap.nil)
                    ++cleared;
                /* A racing overwrite cannot have installed another white oop. */
            }
        }
        at += layout_words(layout);
    }
    return cleared;
}

/* Exact for small blocks, then eight buckets per power of two. */
static unsigned bin_for(uint32_t words)
{
    if (words < 8) return words;
    unsigned shift = (31 - __builtin_clz(words)) - 3;
    return shift * 8 + (words >> shift);
}

static void offer_swept(uint32_t at, uint32_t words)
{
    unsigned bin = bin_for(words);
    c4_cell *cell = cell_at(at);
    put_relaxed(&cell->layout, layout_for(at, words, C4_FREE));
    atomic_fetch_sub_explicit(&heap.occupied, words, memory_order_relaxed);
    uint32_t head = relaxed(&heap.bins.swept[bin]);
    do {
        cell->link = head;
    } while (!atomic_compare_exchange_weak_explicit(&heap.bins.swept[bin],
        &head, at + 1, memory_order_release, memory_order_relaxed));
    atomic_fetch_or_explicit(&heap.bins.swept_mask[bin / 64],
        UINT64_C(1) << (bin % 64), memory_order_release);
}

static void sweep_pinned(uint32_t limit, uint64_t *reclaimed, uint64_t *bytes)
{
    uint32_t epoch = relaxed(&heap.epoch);
    uint32_t start = 0, run = 0;
    for (uint32_t at = 0; at < limit; ) {
        c4_cell *cell = cell_at(at);
        uint64_t layout = acquire(&cell->layout);
        uint32_t words = layout_words(layout);
        if (!layout_at(layout, at)) bad_contract("missing sweep cell");
        bool live = (uint32_t)layout < C4_RESERVED;
        if (live) put_relaxed(&cell->context_limit, 0);
        if (live && relaxed(&cell->seen) != epoch) {
            /* CLEAR is complete. Retire every old start before offering a
             * combined extent. We never withdraw runs already in bins. */
            put_relaxed(&cell->layout, layout_for(at, words, C4_FREE));
            if (!run) start = at;
            run += words;
            ++*reclaimed;
            *bytes += (uint64_t)words * 8;
        } else if (run) {
            offer_swept(start, run);
            run = 0;
        }
        /* One layout snapshot. If it precedes a concurrent split we skip
         * only free space and current-epoch (black) allocations. */
        at += words;
    }
    if (run) offer_swept(start, run);
}

static void sweep_bank(c4_move_state *m, c4_move_bank *b, uint64_t *reclaimed, uint64_t *bytes)
{
    uint32_t epoch = relaxed(&heap.epoch);
    for (uint32_t id = b->first_id; id < b->end_id; ++id) {
        c4_cell *cell = &m->handles[id].trace;
        if ((uint32_t)acquire(&cell->layout) < C4_RESERVED && relaxed(&cell->seen) != epoch) {
            put_relaxed(&cell->layout, C4_FREE);
            atomic_fetch_sub_explicit(&b->occupied, 1, memory_order_relaxed);
            ++*reclaimed;
            *bytes += b->stride;
        }
    }
    /* Retired IDs are not recyclable until their owning source is released.
     * These sealed entries cannot change from ROOTS through SWEEP. */
    if (b->source != NO_REGION) {
        c4_region *src = &b->region[b->source];
        uint32_t live = 0;
        for (uint32_t i = 0; i < src->used; ++i)
            live += (uint32_t)relaxed(&m->handles[src->ids[i]].trace.layout) != C4_FREE;
        b->source_live = live;
    }
}

static void sweep_moving(uint64_t *reclaimed, uint64_t *bytes)
{
    c4_move_state *m = heap.moving;
    if (!m) return;
    sweep_bank(m, &m->bank[0], reclaimed, bytes);
    if (m->plain_classes[PLAIN_INTERVAL]) sweep_bank(m, &m->bank[1], reclaimed, bytes);
}

/* No sweep, relocation or retirement while the view is outstanding.
 * Only starts reached by the cut's roots and preserved strong edges enter
 * this stack. New allocations can only reuse spans/IDs already free at cut. */
static void view_push(uint64_t value, uint32_t *work)
{
    uint32_t at;
    if (!key_of(value, &at)) return;
    c4_cell *cell = cell_at(at);
    if (refs_at(acquire(&cell->layout), at) >= C4_RESERVED) return;
    _Atomic uint64_t *stamp = view_stamp(at);
    uint64_t version = relaxed(stamp);
    if (version == view_born() || version == view_seen()) return;
    put_relaxed(stamp, view_seen());
    /* GC is idle and working cells are live, never allocator bin links. */
    cell->link = *work;
    *work = at + 1;
}

static uint64_t view_ref(uint32_t at, uint32_t i, uint32_t refs, uint32_t word)
{
    _Atomic uint64_t *slot = shadow_field(at, i, refs, false);
#ifdef SAMALTAK_C4_TEST
    extern void c4_heap_test_enum_field(uint32_t at, uint32_t i, bool materialized);
    c4_heap_test_enum_field(at, i, slot != NULL);
#endif
    /* A tag mismatch at the read means the cut slot was nil: a cut-live
     * owner cannot lose its chunk during a view. If we acquire a chunk
     * published after the cut, its initial value is nil, and the first
     * store preserves that nil before releasing its new slot value. */
    return slot ? read_view(word, slot) : heap.nil;
}

static int32_t enumerate_view(void)
{
    uint32_t work = 0;
    int32_t count = 0;
    for (uint32_t i = 0; i < view.nroots; ++i)
        view_push(view.roots[i], &work);
    while (work) {
        if (acquire(&view.overflow)) return -1;
        uint32_t at = work - 1;
        c4_cell *cell = cell_at(at);
        work = cell->link;
        uint32_t row = view_row(at);
        bool pinned = at < heap.capacity;
        if (pinned) {
            uint64_t target = forward_target(read_view(row, &heap.shadow[at]));
            if (target) {
                view_push(target, &work);
                continue; /* never emit a forwarding source */
            }
        }
        uint32_t refs = (uint32_t)relaxed(&cell->layout);
        _Atomic uint64_t *shadow = shadow_row(at);
        uint64_t cls = read_view(row + 1, shadow);
        if (cls == view.cls) {
            uint64_t id = pinned ? heap.base + (size_t)at * 8 :
                heap.moving->tokens + (size_t)(at - heap.capacity) * 8;
            if (id != view.exclude_a && id != view.exclude_b) {
                if (count == C4_ENUM_LIMIT) return -1;
                view.ids[count++] = id;
            }
        }
        view_push(cls, &work);
        uint32_t limit = refs;
        if (cell->weak_start != C4_NO_WEAK) {
            limit = cell->weak_start;
        } else if (pinned && cls == heap.context_class && refs >= CTX_FIXED) {
            uint64_t sp = read_view(row + 2 + CTX_STACKP, shadow + 1 + CTX_STACKP);
            uint64_t n = sp >> 1;
            if (!(sp & 1) || n > refs - CTX_FIXED) return -1;
            limit = CTX_FIXED + (uint32_t)n;
        }
        for (uint32_t i = 0; i < limit; ++i) {
            if ((i & 63) == 0 && acquire(&view.overflow)) return -1;
            view_push(view_ref(at, i, refs, row + 2 + i), &work);
        }
    }
    return count;
}

#ifdef SAMALTAK_C4_TEST
/* The blocked-file test must not wait for CLOSE before root slices seal. */
bool c4_heap_test_roots_sealed(void)
{
    return acquire(&heap.phase) == C4_MARK;
}
#endif

static void *worker(void *unused)
{
    (void)unused;
    uint32_t local = 0, inbound = 0;
    uint64_t marked = 0, edges = 0, reclaimed = 0, bytes = 0;

    for (;;) {
        /* Snapshot wake before testing work; futex wait cannot miss a wake
         * racing this test. Only the worker ever waits. */
        uint32_t wake = acquire(&heap.wake);
        unsigned phase = acquire(&heap.phase);
        if (phase == C4_ROOTS || phase == C4_MARK) {
            if (!inbound) inbound = atomic_exchange_explicit(&heap.inbox, 0,
                memory_order_acquire);
            if (local || inbound) {
                uint32_t *source = local ? &local : &inbound;
                uint32_t at = *source - 1;
                c4_cell *cell = cell_at(at);
                *source = cell->link;
                ++marked;
                uint64_t target = at < heap.capacity && c4_heap_has_forwarding()
                    ? forward_at(at) : 0;
                if (target) {
                    ++edges;
                    shade_worker(target, &local);
                    continue;
                }
                uint32_t refs = (uint32_t)relaxed(&cell->layout);
                uint32_t limit = cell->weak_start != C4_NO_WEAK ? cell->weak_start :
                    is_context(at, refs) ? context_snapshot_limit(at, cell, refs) : refs;
                edges += (uint64_t)limit + 1;
                uint32_t eager = limit;
                uint64_t tag = 0;
                if (refs > CTX_FIXED + SHADOW_CHUNK - 1 && limit > CTX_FIXED) {
                    tag = lazy_tag(at);
                    if (tag) {
                        uint32_t prefix = lazy_start(at) - (at + 2);
                        if (prefix < eager) eager = prefix;
                    }
                }
                _Atomic uint64_t *row = shadow_row(at);
                for (uint32_t f = 0; f <= eager; ++f)
                    shade_worker(acquire(&row[f]), &local);

                /* A matching acquire publishes the initialized fields. On
                 * mismatch the whole span is implicit nil at this read.
                 * A racing first strong store shades its value in MARK or
                 * CLOSE; the mutator cannot ACK before publishing that work. */
                uint32_t end = at + 2 + limit;
                for (uint32_t word = at + 2 + eager; word < end; word += SHADOW_CHUNK) {
                    bool materialized = acquire(&heap.chunk_tags[word / SHADOW_CHUNK]) == tag;
#ifdef SAMALTAK_C4_TEST
                    extern void c4_heap_test_mark_chunk(uint32_t at, uint32_t word, bool materialized);
                    c4_heap_test_mark_chunk(at, word, materialized);
#endif
                    if (!materialized) continue;
                    uint32_t stop = word + SHADOW_CHUNK;
                    if (stop > end) stop = end;
                    for (uint32_t j = word; j < stop; ++j)
                        shade_worker(acquire(&heap.shadow[j]), &local);
                }
                continue;
            }
            if (phase == C4_MARK) {
                /* Stop consuming inbox until the mutator replies. A mark
                 * claim not yet enqueued is still on the mutator's stack;
                 * its dispatch checkpoint cannot ack until it has enqueued. */
                release(&heap.phase, C4_CLOSE);
#ifdef SAMALTAK_C4_TEST
                extern void c4_heap_test_after_close(void);
                c4_heap_test_after_close();
#endif
                continue;
            }
        } else if (phase == C4_ENUM_TRACE) {
#ifdef SAMALTAK_C4_TEST
            extern void c4_heap_test_before_enum(void);
            c4_heap_test_before_enum();
#endif
            view.count = enumerate_view();
            release(&heap.phase, C4_ENUM_READY);
            continue;
        } else if (phase == C4_CLEAR) {
            if (acquire(&heap.inbox) || local || inbound) bad_contract("close with mark work");
            uint64_t cleared = clear_weak(acquire(&heap.top));
            if (cleared) {
                atomic_fetch_add_explicit(&heap.weak_cleared, cleared, memory_order_relaxed);
                atomic_fetch_add_explicit(&heap.weak_pending, cleared, memory_order_release);
            }
            release(&heap.phase, C4_SWEEP);
            continue;
        } else if (phase == C4_SWEEP) {
            uint32_t limit = acquire(&heap.top);
            sweep_pinned(limit, &reclaimed, &bytes);
            sweep_moving(&reclaimed, &bytes);
            put_relaxed(&heap.marked, marked);
            put_relaxed(&heap.traced_edges, edges);
            put_relaxed(&heap.reclaimed, reclaimed);
            put_relaxed(&heap.reclaimed_bytes, bytes);
            atomic_fetch_add_explicit(&heap.cycles_completed, 1, memory_order_relaxed);
            release(&heap.phase, C4_IDLE);
            continue;
        }

        syscall(SYS_futex, &heap.wake, FUTEX_WAIT_PRIVATE, wake, NULL, NULL, 0);
    }
    return NULL;
}

bool c4_heap_supported(void)
{
    return true;
}

bool c4_heap_init(void *base, size_t capacity)
{
    if (heap.base || !base || ((uintptr_t)base & 7) ||
        capacity < 16 || capacity / 8 > UINT32_MAX / 2 ||
        capacity > UINTPTR_MAX - (uintptr_t)base)
        return false;

    size_t words = capacity / 8;
    heap.cells = calloc((words + 1) / 2, sizeof *heap.cells);
    heap.shadow = calloc(words, sizeof *heap.shadow);
    /* Demand-zero tags. Reserving capacity must not touch all its chunks. */
    size_t tag_bytes = ((words + SHADOW_CHUNK - 1) / SHADOW_CHUNK) * sizeof *heap.chunk_tags;
    heap.chunk_tags = mmap(NULL, tag_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (!heap.cells || !heap.shadow || heap.chunk_tags == MAP_FAILED) {
        free(heap.cells);
        free(heap.shadow);
        if (heap.chunk_tags != MAP_FAILED) munmap(heap.chunk_tags, tag_bytes);
        heap.cells = NULL;
        heap.shadow = NULL;
        heap.chunk_tags = NULL;
        return false;
    }
    heap.base = (uintptr_t)base;
    heap.capacity = (uint32_t)words;
    heap.threshold = 1024 * 1024;
    return true;
}

static void init_bank(c4_move_state *m, unsigned index, uintptr_t pool,
    uint32_t stride, uint32_t refs, uint32_t first, uint32_t count)
{
    c4_move_bank *b = &m->bank[index];
    b->pool = pool;
    b->stride = stride;
    b->refs = refs;
    b->slots = REGION_BYTES / stride;
    b->first_id = first;
    b->end_id = first + count;
    b->source = NO_REGION;
    b->reserve = REGION_COUNT - 1;
    for (uint32_t id = first; id < b->end_id; ++id) {
        put_relaxed(&m->handles[id].trace.layout, C4_FREE);
        m->handles[id].next_free = id + 1 < b->end_id ? id + 2 : 0;
    }
    b->free_ids = first + 1;
}

bool c4_heap_init_moving(void *base, size_t capacity)
{
    const size_t bank_bytes = REGION_COUNT * REGION_BYTES;
    const size_t pool_bytes = bank_bytes;
    if (capacity < pool_bytes + 16 || (capacity & 7) ||
        capacity > UINTPTR_MAX - (uintptr_t)base ||
        (capacity - pool_bytes) / 8 > UINT32_MAX - MOVE_VIEW_STRIDE * MOVE_IDS)
        return false;
    c4_move_state *m = calloc(1, sizeof *m);
    if (!m) return false;
    /* Reserve, not commit: accidental token-as-address reads must fault. */
    size_t token_bytes = (size_t)MOVE_IDS * 8;
    void *tokens = mmap(NULL, token_bytes, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (tokens == MAP_FAILED || !c4_heap_init(base, capacity - pool_bytes)) {
        if (tokens != MAP_FAILED) munmap(tokens, token_bytes);
        free(m);
        return false;
    }
    m->tokens = (uintptr_t)tokens;
    uintptr_t pool = (uintptr_t)base + capacity - pool_bytes;
    init_bank(m, 0, pool, SMALL_BYTES, 2, 0, SMALL_IDS);
    m->bank[1].source = NO_REGION;
    m->bank_count = 1;
    heap.moving = m;
    return true;
}

bool c4_heap_prepare_interval(size_t image_bytes)
{
    c4_move_state *m = heap.moving;
    const uint32_t extra = REGION_COUNT * REGION_BYTES / 8;
    if (!m || heap.started || relaxed(&heap.top) || m->bank_count != 1 ||
        heap.capacity < extra + 2 || image_bytes > (size_t)(heap.capacity - extra) * 8)
        return false;
    /* The pinned side mappings already cover this shorter prefix. Charge
     * the second bank (including to-space) before importing any objects. */
    heap.capacity -= extra;
    init_bank(m, 1, heap.base + (size_t)heap.capacity * 8,
        INTERVAL_BYTES, 3, SMALL_IDS, INTERVAL_IDS);
    m->bank_count = 2;
    return true;
}

size_t c4_heap_pinned_capacity(void)
{
    return (size_t)heap.capacity * 8;
}

void c4_heap_set_plain_classes(uint64_t point, uint64_t message, uint64_t association)
{
    if (heap.started) bad_contract("plain classes after start");
    c4_move_state *m = heap.moving;
    if (!m) return;
    m->plain_classes[PLAIN_POINT] = point;
    m->plain_classes[PLAIN_MESSAGE] = message;
    m->plain_classes[PLAIN_ASSOCIATION] = association;
}

static enum plain_kind plain_kind(const c4_move_state *m, uint64_t cls)
{
    if (m && cls)
        for (unsigned i = 0; i < PLAIN_KINDS; ++i)
            if (m->plain_classes[i] == cls) return i;
    return PLAIN_KINDS;
}

bool c4_heap_plain_class(uint64_t cls)
{
    return plain_kind(heap.moving, cls) < PLAIN_INTERVAL;
}

void c4_heap_set_interval_class(uint64_t cls)
{
    if (heap.started) bad_contract("Interval class after start");
    if (cls && (!heap.moving || heap.moving->bank_count != 2))
        bad_contract("Interval class without arena bank");
    if (heap.moving) heap.moving->plain_classes[PLAIN_INTERVAL] = cls;
}

bool c4_heap_interval_class(uint64_t cls)
{
    return plain_kind(heap.moving, cls) == PLAIN_INTERVAL;
}

bool c4_heap_is_imported(uint64_t obj)
{
    uint32_t at;
    return !heap.started && live_pinned(obj, &at);
}

static bool bank_class(uint32_t bank, uint64_t cls)
{
    return bank ? c4_heap_interval_class(cls) : c4_heap_plain_class(cls);
}

void c4_heap_set_threshold(size_t bytes)
{
    if (heap.started) bad_contract("threshold after start");
    heap.threshold = bytes ? bytes : 1;
}

void c4_heap_set_method_class(uint64_t cls)
{
    heap.method_class = cls;
}

void c4_heap_set_context_class(uint64_t cls)
{
    if (heap.started) bad_contract("Context class after start");
    heap.context_class = cls;
}

void c4_heap_set_nil(uint64_t nil)
{
    uint32_t at;
    if (heap.started || !nil || !offset(nil, &at)) bad_contract("invalid image nil");
    heap.nil = nil;
}

void c4_heap_set_forward_classes(uint64_t bytes, uint64_t wide)
{
    if (heap.started || !bytes || !wide || bytes == wide)
        bad_contract("invalid forwarding classes");
    heap.bytes_class = bytes;
    heap.wide_class = wide;
}

/* Real object access is mutator-only and occurs in private reserved blocks
 * or during import. weak_start comes from the validated class format. */
static bool mirror(uint32_t at, uint64_t addr, uint32_t words, uint32_t refs,
    uint32_t weak_start, unsigned phase, bool nil_filled)
{
    uint64_t *obj = (uint64_t *)(uintptr_t)addr;
    uint64_t header = obj[0];
    unsigned format = (header >> H_FMT_SHIFT) & H_FMT_MASK;
    if (at >= heap.capacity) {
        uint32_t bank = at - heap.capacity >= SMALL_IDS;
        if (format != F_FIXED || refs != heap.moving->bank[bank].refs ||
            !bank_class(bank, obj[1])) return false;
    }
    if (c4_heap_movable(obj[1]) ||
        (uint32_t)header != words - 2 ||
        refs != (format >= F_FIXED && format <= F_WEAK ? words - 2 : 0) ||
        ((format == F_WEAK) != (weak_start != C4_NO_WEAK)) ||
        (format == F_WEAK && (!heap.nil || weak_start > refs ||
            (heap.context_class && obj[1] == heap.context_class))))
        return false;
    if (heap.method_class && obj[1] == heap.method_class &&
        ((CM_LITERALS < refs && c4_heap_movable(obj[2 + CM_LITERALS])) ||
         (CM_BYTECODES < refs && c4_heap_movable(obj[2 + CM_BYTECODES]))))
        return false;
    bool shade_edges = marking(phase);
    bool closed = phase == C4_CLEAR || phase == C4_SWEEP;
    bool normalize = c4_heap_has_forwarding();
    uint32_t eager = refs;
    if (nil_filled && at < heap.capacity && refs > CTX_FIXED + SHADOW_CHUNK - 1) {
        uint32_t prefix = lazy_start(at) - (at + 2);
        if (refs > prefix) {
            eager = prefix;
            /* Never reuse a tag, even across mark epochs or split extents.
             * Exhaustion would require 2^63 large allocations. */
            if (heap.shadow_tag >= UINT64_MAX - 1) bad_contract("shadow tag exhausted");
            heap.shadow_tag = (heap.shadow_tag + 2) | 1;
            put_relaxed(&heap.shadow[at], heap.shadow_tag);
        }
    }
    for (uint32_t i = 0; i <= eager; ++i) {
        uint64_t value = obj[1 + i];
        if (i && normalize) {
            uint64_t next = canonical(value);
            if (next != value) obj[1 + i] = value = next;
        }
        /* i == 0 is the class word. The fixed prefix is strong. */
        if (i <= weak_start) {
            if (shade_edges) shade_mutator(value);
        } else if (closed && !post_close_live(value)) {
            value = heap.nil;
        }
        put_relaxed(&shadow_row(at)[i], value);
    }
    if (heap.started && eager > heap.max_publish_refs) heap.max_publish_refs = eager;
    return true;
}

static void publish_layout(c4_cell *cell, uint32_t refs, uint32_t weak_start)
{
    cell->weak_start = weak_start;
    release(&cell->layout, (relaxed(&cell->layout) & ~UINT64_C(0xffffffff)) | refs);
    if (weak_start < refs && !relaxed(&heap.has_weak))
        release(&heap.has_weak, 1);
}

bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t weak_start)
{
    uint32_t at, words;
    if (heap.started || !offset(obj, &at) || at != relaxed(&heap.top) ||
        !object_size(bytes, &words) || words > heap.capacity - at ||
        !mirror(at, obj, words, refs, weak_start, C4_IDLE, false))
        return false;

    c4_cell *cell = heap.cells + at / 2;
    put_relaxed(&cell->layout, layout_for(at, words, C4_RESERVED));
    publish_layout(cell, refs, weak_start);
    put_relaxed(&heap.top, at + words);
    atomic_fetch_add_explicit(&heap.occupied, words, memory_order_relaxed);
    ++heap.imports;
    return true;
}

bool c4_heap_start(void)
{
    if (!heap.base || heap.started) return false;
    if (heap.nil) {
        uint32_t at;
        if (!offset(heap.nil, &at) || at >= relaxed(&heap.top)) return false;
        c4_cell *cell = cell_at(at);
        if (refs_at(relaxed(&cell->layout), at) >= C4_RESERVED) return false;
    }
    if (heap.moving) {
        if (!heap.moving->plain_classes[PLAIN_POINT]) return false;
        for (unsigned i = 0; i < PLAIN_KINDS; ++i) {
            uint64_t cls = heap.moving->plain_classes[i];
            if (!cls) continue;
            uint32_t at;
            if (cls == heap.context_class || !live_pinned(cls, &at) ||
                plain_kind(heap.moving, cls) != i) return false;
        }
    }
    uint32_t at;
    if (heap.bytes_class && (!live_pinned(heap.bytes_class, &at) ||
            !live_pinned(heap.wide_class, &at))) return false;
    pthread_attr_t attr;
    if (pthread_attr_init(&attr)) return false;
    if (pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED)) {
        pthread_attr_destroy(&attr);
        return false;
    }
    pthread_t thread;
    int error = pthread_create(&thread, &attr, worker, NULL);
    pthread_attr_destroy(&attr);
    if (error) return false;
    heap.started = true;
    return true;
}

static uint32_t bin_words(uint32_t key, unsigned bin)
{
    uint32_t at = key - 1;
    uint64_t layout = relaxed(&cell_at(at)->layout);
    uint32_t words = layout_words(layout);
    if (!layout_at(layout, at) || (uint32_t)layout != C4_FREE || bin_for(words) != bin)
        bad_contract("invalid pinned bin");
    return words;
}

/* The worker only pushes. In one pop it cannot re-push any popped run.
 * Leave stale availability bits alone except when their head is empty;
 * repair a concurrent push with a head recheck after clearing the bit. */
static uint32_t take_swept(unsigned bin, uint32_t words, uint32_t *available)
{
    _Atomic uint32_t *list = &heap.bins.swept[bin];
    uint32_t head = acquire(list);
    uint32_t taken = 0;
    for (unsigned retry = 0; head && retry < 2; ++retry) {
        uint32_t span = bin_words(head, bin);
        if (span < words) return 0;
        uint32_t next = cell_at(head - 1)->link;
        if (atomic_compare_exchange_strong_explicit(list, &head, next,
                memory_order_acquire, memory_order_acquire)) {
            *available = span;
            if (next) return head;
            taken = head;
            break;
        }
    }
    if (!head || taken) {
        _Atomic uint64_t *mask = &heap.bins.swept_mask[bin / 64];
        uint64_t bit = UINT64_C(1) << (bin % 64);
        atomic_fetch_and_explicit(mask, ~bit, memory_order_acq_rel);
        if (acquire(list)) atomic_fetch_or_explicit(mask, bit, memory_order_release);
    }
    return taken;
}

static uint32_t take_run(uint32_t words, uint32_t *available)
{
    unsigned bin = bin_for(words);
    for (unsigned group = bin / 64; group < BIN_GROUPS; ++group) {
        uint64_t swept = acquire(&heap.bins.swept_mask[group]);
        uint64_t split = heap.bins.split_mask[group];
        uint64_t candidates = (swept | split) & (UINT64_MAX << (bin % 64));
        for (; candidates; candidates &= candidates - 1) {
            unsigned i = __builtin_ctzll(candidates);
            uint64_t bit = UINT64_C(1) << i;
            unsigned trial = group * 64 + i;
            if (split & bit) {
                uint32_t head = heap.bins.split[trial];
                uint32_t span = bin_words(head, trial);
                if (span >= words) {
                    uint32_t next = cell_at(head - 1)->link;
                    heap.bins.split[trial] = next;
                    if (!next) heap.bins.split_mask[group] &= ~bit;
                    *available = span;
                    return head;
                }
            }
            /* Only a head in the request's coarse bucket can be too small.
             * Do not walk a free list on the mutator. */
            if (swept & bit) {
                uint32_t head = take_swept(trial, words, available);
                if (head) return head;
            }
        }
        bin = 0; /* all later groups are above the request */
    }
    return 0;
}

static void offer_split(uint32_t at, uint32_t words)
{
    unsigned bin = bin_for(words);
    c4_cell *cell = cell_at(at);
    /* Interior shadow words need not be zero; this new boundary has
     * never forwarded. Prior-cycle aliases are no longer in weak slots. */
    put_relaxed(&heap.shadow[at], 0);
    release(&cell->layout, layout_for(at, words, C4_FREE));
    cell->link = heap.bins.split[bin];
    heap.bins.split[bin] = at + 1;
    heap.bins.split_mask[bin / 64] |= UINT64_C(1) << (bin % 64);
}

static uintptr_t region_address(const c4_move_bank *b, uint32_t region, uint32_t slot)
{
    return b->pool + (size_t)region * REGION_BYTES + (size_t)slot * b->stride;
}

static uintptr_t take_slot(c4_move_bank *b, uint32_t region, uint32_t id)
{
    c4_region *r = &b->region[region];
    if (r->used >= b->slots) bad_contract("moving region overflow");
    uint32_t slot = r->used++;
    if (r->used <= r->high_water) {
        if (r->ids[slot] != id) ++b->source_reused;
    } else {
        r->high_water = r->used;
    }
    r->ids[slot] = id;
    if (++b->body_slots > b->body_peak) b->body_peak = b->body_slots;
    return region_address(b, region, slot);
}

static uint64_t reserve_moving(c4_move_state *m, c4_move_bank *b)
{
    if (!b->free_ids) return 0;
    for (uint32_t i = 0; i < REGION_COUNT; ++i) {
        if (i == b->source || i == b->reserve || b->region[i].used == b->slots)
            continue;
        uint32_t id = b->free_ids - 1;
        c4_handle *handle = &m->handles[id];
        if (handle->addr || (uint32_t)relaxed(&handle->trace.layout) != C4_FREE)
            bad_contract("recycling live moving handle");
        b->free_ids = handle->next_free;
        handle->addr = take_slot(b, i, id);
        put_relaxed(&handle->trace.seen, relaxed(&heap.epoch));
        put_relaxed(&handle->trace.layout, C4_RESERVED);
        uint32_t occupied = atomic_fetch_add_explicit(&b->occupied, 1, memory_order_relaxed) + 1;
        if (occupied > b->peak) b->peak = occupied;
        return m->tokens + (size_t)id * 8;
    }
    return 0;
}

static uint64_t reserve_pinned(size_t bytes)
{
    uint32_t words;
    if (!object_size(bytes, &words)) return 0;
    uint32_t top = relaxed(&heap.top);
    uint32_t available = 0;
    uint32_t head = take_run(words, &available);
    if (!head && words > heap.capacity - top) return 0;
    uint32_t at = head ? head - 1 : top;
    c4_cell *cell = cell_at(at);
    if (head) {
        ++heap.reused;
        if (available - words >= 2) {
            /* Publish a new boundary before shortening the old span.
             * Sweep/clear can safely walk either layout. */
            offer_split(at + words, available - words);
        } else {
            words = available; /* cannot index a one-word remainder */
        }
    }
    put_relaxed(&heap.shadow[at], 0);
    put_relaxed(&cell->seen, relaxed(&heap.epoch));
    release(&cell->layout, layout_for(at, words, C4_RESERVED));
    if (!head) release(&heap.top, at + words);
    atomic_fetch_add_explicit(&heap.occupied, words, memory_order_relaxed);
    return heap.base + (size_t)at * 8;
}

uint64_t c4_heap_reserve(size_t bytes, enum c4_lane lane, uint64_t *init_addr)
{
    *init_addr = 0;
    if (!heap.started) return 0;
    if (heap.unpublished) bad_contract("nested private reserve");
    uint64_t obj = 0;
    if (heap.moving && (lane == C4_PLAIN ||
            (lane == C4_INTERVAL && heap.moving->plain_classes[PLAIN_INTERVAL]))) {
        c4_move_bank *b = &heap.moving->bank[lane == C4_INTERVAL];
        if (bytes != 16 + 8 * b->refs) bad_contract("invalid extent in moving lane");
        obj = reserve_moving(heap.moving, b);
        if (!obj) {
            ++b->fallback;
            heap.pressure = true;
        }
    }
    if (!obj) obj = reserve_pinned(bytes);
    if (!obj) {
        heap.pressure = true;
        ++heap.failed;
        return 0;
    }
    uint32_t id;
    *init_addr = token_id(obj, &id) ? heap.moving->handles[id].addr : obj;
    heap.unpublished = obj;
    heap.unpublished_words = (uint32_t)(bytes / 8);
    heap.since_begin = bytes <= SIZE_MAX - heap.since_begin
        ? heap.since_begin + bytes : SIZE_MAX;
    ++heap.allocated;
    return obj;
}

static void publish(uint64_t obj, uint32_t refs, uint32_t weak_start, bool nil_filled)
{
    uint32_t at;
    if (!obj || obj != heap.unpublished || !key_of(obj, &at))
        bad_contract("publish outside private reserve");
    c4_cell *cell = cell_at(at);
    if (refs_at(relaxed(&cell->layout), at) != C4_RESERVED) bad_contract("publish without reserve");
    /* New objects are black. During marking publish their initial edges,
     * not the object: allocating garbage must not keep reopening closure.
     * Only this mutator can ACK at a later checkpoint. */
    unsigned phase = acquire(&heap.phase);
    bool moving = at >= heap.capacity;
    uint64_t addr = moving ? heap.moving->handles[at - heap.capacity].addr : obj;
    if (!mirror(at, addr, heap.unpublished_words, refs, weak_start, phase, nil_filled))
        bad_contract("unsupported format, extent or weak layout");
    if (viewing(phase)) put_relaxed(view_stamp(at), view_born());
    publish_layout(cell, refs, weak_start);
    heap.unpublished = 0;
}

void c4_heap_publish_nil(uint64_t obj, uint32_t refs, uint32_t weak_start)
{
    publish(obj, refs, weak_start, true);
}

#ifdef SAMALTAK_C4_TEST
void c4_heap_publish(uint64_t obj, uint32_t refs, uint32_t weak_start)
{
    publish(obj, refs, weak_start, false);
}
#endif

void c4_heap_store_class(uint64_t obj, uint64_t value)
{
    uint32_t at, refs;
    obj = c4_heap_canonical(obj);
    c4_cell *cell = body_owner(obj, &at, &refs);
    _Atomic uint64_t *slot = shadow_row(at);
    uint64_t old = relaxed(slot);
    if (c4_heap_movable(value) || (at >= heap.capacity && value != old))
        bad_contract("invalid movable role in class store");
    if (cell->weak_start != C4_NO_WEAK && value != old)
        bad_contract("weak class reassignment");
    if (heap.bytes_class && value != old &&
        (old == heap.bytes_class || old == heap.wide_class ||
         value == heap.bytes_class || value == heap.wide_class))
        bad_contract("forwarding class reassignment");
    if (heap.context_class && ((old == heap.context_class) != (value == heap.context_class)))
        bad_contract("Context class reassignment");
    unsigned phase = acquire(&heap.phase);
    if (marking(phase)) {
        shade_mutator(old);
        shade_mutator(value);
    }
    if (value != old && viewing(phase)) preserve_word(at, view_row(at) + 1, slot);
    release(slot, value);
    ((uint64_t *)(uintptr_t)c4_heap_address(obj))[1] = value;
}

uint32_t c4_heap_weak_start(uint64_t obj)
{
    uint32_t at, refs;
    return body_owner(c4_heap_canonical(obj), &at, &refs)->weak_start;
}

uint64_t c4_heap_load_ref(uint64_t obj, uint32_t index)
{
    uint32_t at, refs;
    obj = c4_heap_canonical(obj);
    c4_cell *cell = body_owner(obj, &at, &refs);
    if (index >= refs) bad_contract("body load outside reference slots");
    _Atomic uint64_t *field;
    if (index < cell->weak_start) {
        field = shadow_field(at, index, refs, false);
        uint64_t raw = field ? acquire(field) : heap.nil;
        uint64_t value = c4_heap_canonical(raw);
        if (value != raw) c4_heap_store_ref(obj, index, value);
        return value;
    }

    /* Observe the phase first: an IDLE load must be ordered after CLEAR,
     * not sample stale shadow just before the worker publishes IDLE. */
    unsigned phase = acquire(&heap.phase);
    field = shadow_field(at, index, refs, false);
    uint64_t raw = field ? acquire(field) : heap.nil;
#ifdef SAMALTAK_C4_TEST
    extern void c4_heap_test_after_weak_load(uint64_t obj, uint32_t i, uint64_t value);
    c4_heap_test_after_weak_load(obj, index, raw);
#endif
    uint64_t value = c4_heap_canonical(raw);
    if (marking(phase)) shade_mutator(value);
    else if ((phase == C4_CLEAR || phase == C4_SWEEP) && !post_close_live(value))
        return heap.nil;
    /* Only weak shadow is authoritative. Do not restore a worker clear. */
    if (field && value != raw)
        atomic_compare_exchange_strong_explicit(field, &raw, value,
            memory_order_acq_rel, memory_order_relaxed);
    return value;
}

void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value)
{
    uint32_t at, refs;
    obj = c4_heap_canonical(obj);
    value = c4_heap_canonical(value);
    c4_cell *cell = body_owner(obj, &at, &refs);
    if (index >= refs) bad_contract("body store outside reference slots");
    if ((index == CM_LITERALS || index == CM_BYTECODES) && c4_heap_movable(value) &&
        heap.method_class && relaxed(shadow_row(at)) == heap.method_class)
        bad_contract("moving handle in raw method storage");
    _Atomic uint64_t *field = shadow_field(at, index, refs, true);
    unsigned phase = acquire(&heap.phase);
    if (index >= cell->weak_start) {
        /* No SATB or insertion barrier for weak edges. After ACK even a
         * raw stale oop passed by a caller must not enter a weak slot. */
        if ((phase == C4_CLEAR || phase == C4_SWEEP) && !post_close_live(value))
            value = heap.nil;
    } else if (marking(phase)) {
        if (!is_context(at, refs)) {
            shade_mutator(relaxed(field));
        } else {
            uint32_t limit = context_snapshot_limit(at, cell, refs);
            if (index == CTX_STACKP) release(&cell->context_limit, limit + 1);
            if (index < limit) shade_mutator(relaxed(field));
        }
        shade_mutator(value);
    }
    if (index < cell->weak_start && viewing(phase))
        preserve_word(at, view_row(at) + 2 + index, field);
    release(field, value);
    if (index >= CM_LITERALS && index <= CM_PRIMITIVE &&
            relaxed(shadow_row(at)) == heap.method_class)
        c4_heap_invalidate_cache();
    ((uint64_t *)(uintptr_t)c4_heap_address(obj))[2 + (size_t)index] = value;
}

static bool move_pending(const c4_move_state *m)
{
    return m && (m->bank[0].source != NO_REGION || m->bank[1].source != NO_REGION);
}

static void move_bank(c4_move_state *m, unsigned index, uint32_t *inspected, uint32_t *copied)
{
    c4_move_bank *b = &m->bank[index];
    if (b->source == NO_REGION) return;
    uint32_t source = b->source;
    c4_region *src = &b->region[source];
    /* Dense sources remain sealed only for this cycle; their dead IDs
     * remain tombstones until a later profitable selection. */
    if (b->source_live * 8 > src->used * 7) {
        ++b->dense;
        b->source = NO_REGION;
        return;
    }

    uint32_t initial = *inspected;
    for (; b->cursor < src->used && *inspected < MOVE_INSPECTIONS &&
            *copied + b->stride <= MOVE_BYTES; ++b->cursor, ++*inspected) {
        uint32_t id = src->ids[b->cursor];
        c4_handle *handle = &m->handles[id];
        uintptr_t old = region_address(b, source, b->cursor);
        if (handle->addr != old)
            bad_contract("moving source ownership changed");
        uint32_t refs = (uint32_t)relaxed(&handle->trace.layout);
        if (refs == C4_FREE) {
            handle->addr = 0;
            if (!b->retired_head) b->retired_tail = id + 1;
            handle->next_free = b->retired_head;
            b->retired_head = id + 1;
        } else {
            if (refs != b->refs || relaxed(&handle->trace.seen) != relaxed(&heap.epoch))
                bad_contract("unmarked or unpublished handle in source");
            enum plain_kind kind = plain_kind(m, relaxed(&handle->shadow[0]));
            if (kind == PLAIN_KINDS || (kind == PLAIN_INTERVAL) != index)
                bad_contract("unregistered movable class");
            uintptr_t dest = take_slot(b, b->reserve, id);
            /* The 48-byte slot has 8 bytes of inaccessible padding.
             * Charge the entire stride, copy only the initialized body. */
            memcpy((void *)dest, (const void *)old, 16 + 8 * b->refs);
            handle->addr = dest;
            *copied += b->stride;
            ++b->moved;
            ++m->moved_kind[kind];
        }
#ifdef SAMALTAK_C4_TEST
        memset((void *)old, 0xdd, b->stride);
#endif
    }
    b->inspected += *inspected - initial;
    if (b->cursor != src->used) return;

    if (b->region[b->reserve].used != b->source_live)
        bad_contract("incomplete moving evacuation");
    if (b->retired_head) {
        m->handles[b->retired_tail - 1].next_free = b->free_ids;
        b->free_ids = b->retired_head;
        b->retired_head = b->retired_tail = 0;
    }
    b->body_slots -= src->used;
    src->used = 0;
    /* An empty source needs no destination. Otherwise it becomes the
     * exclusive reserve for this bank; the old reserve joins this bank. */
    if (b->source_live) b->reserve = source;
    b->cursor = 0;
    b->source = NO_REGION;
    ++b->released;
}

void c4_heap_move_poll(void)
{
    require_raw_read_quiescence("relocation poll during synchronous raw read");
    c4_move_state *m = heap.moving;
    if (!move_pending(m) || acquire(&heap.phase) != C4_IDLE) return;
    if (heap.unpublished) bad_contract("private reserve at move poll");
    uint32_t inspected = 0, copied = 0;
    /* Alternate first choice so one full source cannot starve the other.
     * Both banks debit the same fixed visit budget. */
    move_bank(m, m->first_bank, &inspected, &copied);
    move_bank(m, m->first_bank ^ 1u, &inspected, &copied);
    if (m->bank_count == 2) m->first_bank ^= 1u;
    if (inspected > m->max_inspected) m->max_inspected = inspected;
    if (copied > m->max_copied) m->max_copied = copied;
}

bool c4_heap_enum_request(uint64_t cls, uint32_t max_roots, uint64_t exclude_a, uint64_t exclude_b)
{
    if (!heap.started || !cls || view.cls || view.version == UINT32_MAX ||
        max_roots < 4 + PLAIN_INTERVAL + (unsigned)(heap.moving && heap.moving->plain_classes[PLAIN_INTERVAL]) || (view.roots && max_roots != view.max_roots))
        return false;
    if (!view.words) {
        size_t handles = !heap.moving ? 0 : heap.moving->bank_count == 2 ? MOVE_IDS : SMALL_IDS;
        size_t words = VIEW_LOG_ENTRIES * sizeof *view.words;
        size_t visited = (((size_t)heap.capacity + 1) / 2 + handles) * sizeof *view.visited;
        size_t roots = (size_t)max_roots * sizeof *view.roots;
        void *mem = mmap(NULL, words + visited + roots, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (mem == MAP_FAILED) return false;
        view.words = mem;
        view.visited = (void *)((char *)mem + words);
        view.roots = (void *)((char *)mem + words + visited);
        view.max_roots = max_roots;
    }
    view.cls = cls;
    view.exclude_a = exclude_a;
    view.exclude_b = exclude_b;
    return true;
}

static void enum_root(uint64_t value)
{
    if (view.nroots == view.max_roots) bad_contract("enumeration root capacity");
    view.roots[view.nroots++] = value;
}

int32_t c4_heap_enum_count(void)
{
    if (acquire(&heap.phase) != C4_ENUM_READY) return -2;
    return (view.bytes_invalid || acquire(&view.overflow)) ? -1 : view.count;
}

uint64_t c4_heap_enum_at(uint32_t index)
{
    int32_t count = c4_heap_enum_count();
    if (count < 0 || index >= (uint32_t)count) bad_contract("enumeration result index");
    return view.ids[index];
}

void c4_heap_enum_finish(void)
{
    if (acquire(&heap.phase) != C4_ENUM_READY) bad_contract("enumeration not ready");
    view.cls = 0;
    release(&heap.phase, C4_IDLE);
}

bool c4_heap_begin(void)
{
    require_raw_read_quiescence("cycle start during synchronous raw read");
    if (!heap.started || acquire(&heap.phase) != C4_IDLE) return false;
    if (heap.unpublished) bad_contract("private reserve at cycle start");
    c4_move_state *m = heap.moving;
    if (view.cls) {
        ++view.version;
        put_relaxed(&view.overflow, 0);
        view.bytes_invalid = false;
        view.nroots = 0;
        enum_root(view.cls);
        enum_root(heap.nil);
        if (m)
            for (unsigned i = 0; i < PLAIN_KINDS; ++i)
                if (m->plain_classes[i]) enum_root(m->plain_classes[i]);
        if (heap.bytes_class) {
            enum_root(heap.bytes_class);
            enum_root(heap.wide_class);
        }
        release(&heap.phase, C4_ENUM_ROOTS);
        return true;
    }
    if (move_pending(m)) return false;
    if (m) for (unsigned bank = 0; bank < m->bank_count; ++bank) {
        c4_move_bank *b = &m->bank[bank];
        if (b->region[b->reserve].used) bad_contract("occupied moving reserve");
        for (uint32_t n = 0; n < REGION_COUNT; ++n) {
            uint32_t i = (b->next_source + n) % REGION_COUNT;
            if (i == b->reserve || !b->region[i].used) continue;
            b->source = i;
            b->next_source = (i + 1) % REGION_COUNT;
            break;
        }
    }

    put_relaxed(&heap.epoch, !relaxed(&heap.epoch));
    heap.since_begin = 0;
    heap.pressure = false;
    ++heap.cycles_started;
    release(&heap.phase, C4_ROOTS);
    if (heap.nil) shade_mutator(heap.nil);
    if (m)
        for (unsigned i = 0; i < PLAIN_KINDS; ++i)
            if (m->plain_classes[i]) shade_mutator(m->plain_classes[i]);
    if (heap.bytes_class) {
        shade_mutator(heap.bytes_class);
        shade_mutator(heap.wide_class);
    }
    wake_worker();
    return true;
}

void c4_heap_root(uint64_t value)
{
    unsigned phase = acquire(&heap.phase);
    if (phase == C4_ENUM_ROOTS) return enum_root(value);
    if (phase != C4_ROOTS) bad_contract("root outside publication");
    shade_mutator(value);
}

void c4_heap_end_roots(void)
{
    unsigned phase = acquire(&heap.phase);
    if (phase == C4_ENUM_ROOTS) {
        release(&heap.phase, C4_ENUM_TRACE);
    } else {
        if (phase != C4_ROOTS) bad_contract("seal outside publication");
        release(&heap.phase, C4_MARK);
    }
    wake_worker();
}

void c4_heap_finish_poll(void)
{
    require_raw_read_quiescence("close poll during synchronous raw read");
    if (acquire(&heap.phase) != C4_CLOSE) return;
    /* Only we can publish inbox work, and no barrier can straddle this
     * checkpoint. Worker is parked and cannot drain until phase changes. */
    if (acquire(&heap.inbox)) {
        ++heap.close_retries;
        release(&heap.phase, C4_MARK);
    } else {
        ++heap.closed;
        /* No cache-only oop can escape after this point. Publish the ACK
         * only after invalidating, including on the scheduler idle path. */
        c4_heap_invalidate_cache();
        release(&heap.phase, C4_CLEAR);
    }
    wake_worker();
}

uint64_t c4_heap_take_weak_clears(void)
{
    if (!relaxed(&heap.weak_pending)) return 0;
    return atomic_exchange_explicit(&heap.weak_pending, 0, memory_order_acquire);
}

bool c4_heap_busy(void)
{
    return acquire(&heap.phase) != C4_IDLE;
}

bool c4_heap_should_collect(void)
{
    if (!heap.started || c4_heap_busy()) return false;
    if (view.cls) return true;
    if (move_pending(heap.moving)) return false;
    size_t headroom = (size_t)(heap.capacity - relaxed(&heap.occupied)) * 8;
    size_t budget = headroom / 4;
    if (budget < 4096) budget = 4096;
    if (budget > heap.threshold) budget = heap.threshold;
    return heap.pressure || heap.since_begin >= budget;
}

uint64_t c4_heap_top(void)
{
    return heap.base + (size_t)relaxed(&heap.top) * 8;
}

void c4_heap_stats(void)
{
    static const char *const phases[] = {
        "idle", "roots", "mark", "close", "clear", "sweep",
        "enum-roots", "enum-trace", "enum-ready"
    };
    unsigned phase = acquire(&heap.phase);
    fprintf(stderr,
        "c4: phase=%s imported=%" PRIu64 " cycles_started=%" PRIu64
        " cycles_completed=%" PRIu64 " closed=%" PRIu64 " close_retries=%" PRIu64
        " marked=%" PRIu64 " traced_edges=%" PRIu64 " reclaimed=%" PRIu64
        " reclaimed_bytes=%" PRIu64 " weak_cleared=%" PRIu64
        " allocated=%" PRIu64 " reused=%" PRIu64 " failed=%" PRIu64
        " high_water_bytes=%" PRIu64 " in_use_bytes=%" PRIu64 "\n",
        phases[phase], heap.imports, heap.cycles_started, relaxed(&heap.cycles_completed),
        heap.closed, heap.close_retries, relaxed(&heap.marked), relaxed(&heap.traced_edges), relaxed(&heap.reclaimed),
        relaxed(&heap.reclaimed_bytes), relaxed(&heap.weak_cleared),
        heap.allocated, heap.reused, heap.failed,
        (uint64_t)relaxed(&heap.top) * 8, (uint64_t)relaxed(&heap.occupied) * 8);
    fprintf(stderr, "c4-publish: max_refs=%u max_chunk_init_refs=%u chunk_inits=%" PRIu64 "\n",
        heap.max_publish_refs, heap.max_chunk_init_refs, heap.chunk_inits);
    c4_move_state *m = heap.moving;
    if (!m) return;
    if (m->bank_count == 1) fprintf(stderr, "c4-interval: enabled=0\n");
    for (unsigned i = 0; i < m->bank_count; ++i) {
        c4_move_bank *b = &m->bank[i];
        fprintf(stderr,
            "%s pool_bytes=%u reserve_bytes=%u ids=%u"
            " live_bytes=%u peak_live_bytes=%u body_bytes=%u peak_body_bytes=%u pinned_fallback=%" PRIu64
            " moved=%" PRIu64 " inspected=%" PRIu64 " released=%" PRIu64
            " dense=%" PRIu64 " source_reused=%" PRIu64,
            i ? "c4-interval:" : "c4-moving:",
            REGION_COUNT * REGION_BYTES, REGION_BYTES, b->end_id - b->first_id,
            relaxed(&b->occupied) * b->stride, b->peak * b->stride,
            b->body_slots * b->stride, b->body_peak * b->stride, b->fallback,
            b->moved, b->inspected, b->released, b->dense, b->source_reused);
        if (i) fprintf(stderr, " enabled=%u\n", !!m->plain_classes[PLAIN_INTERVAL]);
        else fprintf(stderr,
            " moved_point=%" PRIu64 " moved_message=%" PRIu64 " moved_association=%" PRIu64
            " max_inspected=%u max_copied=%u metadata_bytes=%zu\n",
            m->moved_kind[PLAIN_POINT], m->moved_kind[PLAIN_MESSAGE],
            m->moved_kind[PLAIN_ASSOCIATION], m->max_inspected, m->max_copied, sizeof *m);
    }
}

#endif
