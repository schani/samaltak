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

enum c4_phase { C4_IDLE, C4_ROOTS, C4_MARK, C4_CLOSE, C4_CLEAR, C4_SWEEP };
#define C4_FREE UINT32_MAX
#define C4_RESERVED (UINT32_MAX - 1u)

#define relaxed(p) atomic_load_explicit((p), memory_order_relaxed)
#define acquire(p) atomic_load_explicit((p), memory_order_acquire)
#define put_relaxed(p, v) atomic_store_explicit((p), (v), memory_order_relaxed)
#define release(p, v) atomic_store_explicit((p), (v), memory_order_release)

/* Index by floor(word_offset / 2): object starts are >=2 words apart. The
 * low span bit distinguishes two candidate offsets in the same cell. A
 * published span never changes. Mark links are logical keys + 1 (0 is null). */
typedef struct {
    _Atomic uint32_t span;           /* (words << 1) | (offset & 1) */
    _Atomic uint32_t refs;           /* pointer slot count or FREE/RESERVED */
    _Atomic uint32_t seen;
    _Atomic uint32_t context_limit;  /* saved cycle-start prefix + 1, or 0 */
    uint32_t weak_start;            /* immutable while refs is published */
    uint32_t mark_link;
    uint32_t bin_link;
} c4_cell;

enum {
    POINT_BYTES = 32, REGION_BYTES = 16 * 1024, REGION_COUNT = 4,
    REGION_SLOTS = REGION_BYTES / POINT_BYTES,
    POINT_IDS = (REGION_COUNT - 1) * REGION_SLOTS,
    MOVE_INSPECTIONS = 64, MOVE_BYTES = 4096,
    NO_REGION = REGION_COUNT
};

typedef struct {
    c4_cell trace;
    _Atomic uint64_t shadow[3];   /* class, x, y: no physical addresses */
    uintptr_t addr;               /* mutator only */
    uint32_t next_free;
} c4_point;

typedef struct {
    uint32_t used, high_water;
    uint32_t ids[REGION_SLOTS];    /* initialized prefix; immutable while sealed */
} c4_region;

typedef struct {
    uintptr_t tokens, pool;
    uint64_t point_class;
    c4_point points[POINT_IDS];
    c4_region region[REGION_COUNT];
    _Atomic uint32_t occupied;    /* logical bodies; excludes evacuation aliases */

    /* Source selection published by ROOTS; the worker only reads this
     * descriptor during SWEEP and writes source_live before publishing IDLE.
     * All remaining plan fields (including the address table) are mutator-only. */
    uint32_t source, source_live, reserve, next_source, cursor;
    uint32_t free_ids, retired_head, retired_tail;
    uint32_t peak, body_slots, body_peak, max_inspected, max_copied;
    uint64_t moved, inspected, released, dense, source_reused, fallback;
} c4_move_lane;

static struct {
    uintptr_t base;
    uint32_t capacity;              /* words */
    uint64_t context_class, nil;
    _Atomic uint32_t *bins;         /* exact size in words */
    c4_cell *cells;
    _Atomic uint64_t *shadow;
    c4_move_lane *moving;

    _Atomic uint32_t phase, epoch;
    _Atomic uint32_t inbox;         /* mutator push / worker exchange */
    _Atomic uint32_t top, occupied; /* words */
    _Atomic uint32_t wake, has_weak;
    _Atomic uint64_t weak_pending, weak_cleared;

    /* Mutator-owned, apart from explicitly atomic publication above. */
    size_t threshold, since_begin;  /* bytes */
    bool started, pressure;
    uint64_t unpublished;         /* sole private reserve; cannot cross a poll */
    uint64_t imports, cycles_started, closed, close_retries, allocated, reused, failed;

    /* Worker-owned; reports are cumulative as of the last completed sweep. */
    _Atomic uint64_t cycles_completed, marked, traced_edges, reclaimed, reclaimed_bytes;
} heap;

static _Noreturn void bad_contract(const char *what)
{
    fprintf(stderr, "C4 heap invariant: %s\n", what);
    abort();
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
    if ((delta & 7) || delta / 8 >= POINT_IDS) return false;
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
    uint32_t id;
    if (!token_id(obj, &id)) return obj;
    c4_point *point = &heap.moving->points[id];
    if (relaxed(&point->trace.refs) >= C4_RESERVED || !point->addr)
        bad_contract("resolve without live Point");
    return point->addr;
}

/* Pinned keys are word offsets. Point keys occupy a disjoint dense tail. */
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
        heap.moving->points[at - heap.capacity].shadow;
}

static c4_cell *cell_at(uint32_t at)
{
    if (at >= heap.capacity) return &heap.moving->points[at - heap.capacity].trace;
    c4_cell *cell = heap.cells + at / 2;
    uint32_t span = relaxed(&cell->span);
    return span && (span & 1) == (at & 1) ? cell : NULL;
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
    return cell && acquire(&cell->refs) < C4_RESERVED &&
        relaxed(&cell->seen) == relaxed(&heap.epoch);
}

static c4_cell *body_owner(uint64_t obj, uint32_t *at, uint32_t *refs)
{
    if (!key_of(obj, at))
        bad_contract("body access outside heap");
    c4_cell *cell = cell_at(*at);
    *refs = cell ? relaxed(&cell->refs) : C4_FREE;
    if (*refs >= C4_RESERVED) bad_contract("body access without live owner");
    return cell;
}

static void wake_worker(void)
{
    atomic_fetch_add_explicit(&heap.wake, 1, memory_order_release);
    syscall(SYS_futex, &heap.wake, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
}

/* Atomic claim permits at most one queue entry per object per cycle.
 * Successful caller owns its mark_link for the rest of this cycle. */
static c4_cell *claim(uint64_t value, uint32_t *at)
{
    if (!key_of(value, at)) return NULL;
    c4_cell *cell = cell_at(*at);
    if (!cell || acquire(&cell->refs) >= C4_RESERVED) return NULL;
    uint32_t epoch = relaxed(&heap.epoch);
    if (relaxed(&cell->seen) == epoch ||
        atomic_exchange_explicit(&cell->seen, epoch, memory_order_relaxed) == epoch)
        return NULL;
    return cell;
}

static void shade_mutator(uint64_t value)
{
    uint32_t at;
    c4_cell *cell = claim(value, &at);
    if (!cell) return;
    uint32_t head = relaxed(&heap.inbox);
    cell->mark_link = head;
    if (!atomic_compare_exchange_strong_explicit(&heap.inbox, &head, at + 1,
            memory_order_release, memory_order_relaxed)) {
        /* No other producer. The worker can only exchange head for zero,
         * so the second attempt cannot lose, even if worker is descheduled. */
        cell->mark_link = 0;
        if (head || !atomic_compare_exchange_strong_explicit(&heap.inbox,
                &head, at + 1, memory_order_release, memory_order_relaxed))
            bad_contract("inbox has multiple producers");
    }
    if (!head) wake_worker();
}

static void shade_worker(uint64_t value, uint32_t *work)
{
    uint32_t at;
    c4_cell *cell = claim(value, &at);
    if (!cell) return;
    cell->mark_link = *work;
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
        if (!cell) bad_contract("missing clear cell");
        uint32_t refs = acquire(&cell->refs);
        if (refs < C4_RESERVED && relaxed(&cell->seen) == epoch) {
            for (uint32_t i = cell->weak_start; i < refs; ++i) {
                _Atomic uint64_t *slot = &heap.shadow[at + 2 + i];
                uint64_t prev = acquire(slot);
                if (post_close_live(prev)) continue;
#ifdef SAMALTAK_C4_TEST
                extern void c4_heap_test_before_weak_cas(uint64_t obj, uint32_t i, uint64_t prev);
                c4_heap_test_before_weak_cas(heap.base + (size_t)at * 8, i, prev);
#endif
                if (atomic_compare_exchange_strong_explicit(slot, &prev, heap.nil,
                        memory_order_acq_rel, memory_order_relaxed))
                    ++cleared;
                /* A racing overwrite cannot have installed another white oop. */
            }
        }
        at += relaxed(&cell->span) >> 1;
    }
    return cleared;
}

static uint32_t sweep_one(uint32_t at, uint64_t *reclaimed, uint64_t *bytes)
{
    c4_cell *cell = cell_at(at);
    if (!cell) bad_contract("missing sweep cell");
    uint32_t words = relaxed(&cell->span) >> 1;
    uint32_t refs = acquire(&cell->refs);
    /* Do not modify cells that might already be available for allocation. */
    if (refs < C4_RESERVED) {
        put_relaxed(&cell->context_limit, 0);
        if (relaxed(&cell->seen) != relaxed(&heap.epoch)) {
            put_relaxed(&cell->refs, C4_FREE);
            atomic_fetch_sub_explicit(&heap.occupied, words, memory_order_relaxed);
            uint32_t head = relaxed(&heap.bins[words]);
            do {
                cell->bin_link = head;
            } while (!atomic_compare_exchange_weak_explicit(&heap.bins[words],
                &head, at + 1, memory_order_release, memory_order_relaxed));
            ++*reclaimed;
            *bytes += (uint64_t)words * 8;
        }
    }
    return words;
}

static void sweep_points(uint64_t *reclaimed, uint64_t *bytes)
{
    c4_move_lane *m = heap.moving;
    if (!m) return;
    uint32_t epoch = relaxed(&heap.epoch);
    for (uint32_t id = 0; id < POINT_IDS; ++id) {
        c4_cell *cell = &m->points[id].trace;
        if (acquire(&cell->refs) < C4_RESERVED && relaxed(&cell->seen) != epoch) {
            put_relaxed(&cell->refs, C4_FREE);
            atomic_fetch_sub_explicit(&m->occupied, 1, memory_order_relaxed);
            ++*reclaimed;
            *bytes += POINT_BYTES;
        }
    }
    /* IDs are not available for reuse. Entries in a sealed region remain
     * immutable from the cycle's root publication through this pass. */
    if (m->source != NO_REGION) {
        c4_region *src = &m->region[m->source];
        uint32_t live = 0;
        for (uint32_t i = 0; i < src->used; ++i)
            live += relaxed(&m->points[src->ids[i]].trace.refs) != C4_FREE;
        m->source_live = live;
    }
}

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
                *source = cell->mark_link;
                uint32_t refs = relaxed(&cell->refs);
                uint32_t limit = cell->weak_start != C4_NO_WEAK ? cell->weak_start :
                    is_context(at, refs) ? context_snapshot_limit(at, cell, refs) : refs;
                ++marked;
                edges += (uint64_t)limit + 1;
                for (uint32_t f = 0; f <= limit; ++f)
                    shade_worker(acquire(&shadow_row(at)[f]), &local);
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
            for (uint32_t at = 0; at < limit; )
                at += sweep_one(at, &reclaimed, &bytes);
            sweep_points(&reclaimed, &bytes);
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
    heap.bins = calloc(words + 1, sizeof *heap.bins);
    heap.cells = calloc((words + 1) / 2, sizeof *heap.cells);
    heap.shadow = calloc(words, sizeof *heap.shadow);
    if (!heap.bins || !heap.cells || !heap.shadow) {
        free(heap.bins);
        free(heap.cells);
        free(heap.shadow);
        heap.bins = NULL;
        heap.cells = NULL;
        heap.shadow = NULL;
        return false;
    }
    heap.base = (uintptr_t)base;
    heap.capacity = (uint32_t)words;
    heap.threshold = 1024 * 1024;
    return true;
}

bool c4_heap_init_moving(void *base, size_t capacity)
{
    size_t pool_bytes = REGION_COUNT * REGION_BYTES;
    if (capacity < pool_bytes + 16 || (capacity & 7) ||
        capacity > UINTPTR_MAX - (uintptr_t)base ||
        (capacity - pool_bytes) / 8 > UINT32_MAX - POINT_IDS)
        return false;
    c4_move_lane *m = calloc(1, sizeof *m);
    if (!m) return false;
    /* Reserve, not commit: accidental token-as-address reads must fault. */
    size_t token_bytes = (size_t)POINT_IDS * 8;
    void *tokens = mmap(NULL, token_bytes, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (tokens == MAP_FAILED || !c4_heap_init(base, capacity - pool_bytes)) {
        if (tokens != MAP_FAILED) munmap(tokens, token_bytes);
        free(m);
        return false;
    }
    m->tokens = (uintptr_t)tokens;
    m->pool = (uintptr_t)base + capacity - pool_bytes;
    m->source = NO_REGION;
    m->reserve = REGION_COUNT - 1;
    for (uint32_t id = 0; id < POINT_IDS; ++id) {
        put_relaxed(&m->points[id].trace.refs, C4_FREE);
        m->points[id].next_free = id + 1 < POINT_IDS ? id + 2 : 0;
    }
    m->free_ids = 1;
    heap.moving = m;
    return true;
}

size_t c4_heap_pinned_capacity(void)
{
    return (size_t)heap.capacity * 8;
}

void c4_heap_set_point_class(uint64_t cls)
{
    if (heap.started) bad_contract("Point class after start");
    if (heap.moving) heap.moving->point_class = cls;
}

void c4_heap_set_threshold(size_t bytes)
{
    if (heap.started) bad_contract("threshold after start");
    heap.threshold = bytes ? bytes : 1;
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

/* Real object access is mutator-only and occurs in private reserved blocks
 * or during import. weak_start comes from the validated class format. */
static bool mirror(uint32_t at, uint64_t addr, uint32_t words, uint32_t refs,
    uint32_t weak_start, unsigned phase)
{
    const uint64_t *obj = (const uint64_t *)(uintptr_t)addr;
    uint64_t header = obj[0];
    unsigned format = (header >> H_FMT_SHIFT) & H_FMT_MASK;
    if (c4_heap_movable(obj[1]) ||
        (at >= heap.capacity && (format != F_FIXED || refs != 2 ||
            obj[1] != heap.moving->point_class)) ||
        (uint32_t)header != words - 2 ||
        refs != (format >= F_FIXED && format <= F_WEAK ? words - 2 : 0) ||
        ((format == F_WEAK) != (weak_start != C4_NO_WEAK)) ||
        (format == F_WEAK && (!heap.nil || weak_start > refs ||
            (heap.context_class && obj[1] == heap.context_class))))
        return false;
    bool shade_edges = marking(phase);
    bool closed = phase == C4_CLEAR || phase == C4_SWEEP;
    for (uint32_t i = 0; i <= refs; ++i) {
        uint64_t value = obj[1 + i];
        /* i == 0 is the class word. The fixed prefix is strong. */
        if (i <= weak_start) {
            if (shade_edges) shade_mutator(value);
        } else if (closed && !post_close_live(value)) {
            value = heap.nil;
        }
        put_relaxed(&shadow_row(at)[i], value);
    }
    return true;
}

static void publish_layout(c4_cell *cell, uint32_t refs, uint32_t weak_start)
{
    cell->weak_start = weak_start;
    release(&cell->refs, refs);
    if (weak_start < refs && !relaxed(&heap.has_weak))
        release(&heap.has_weak, 1);
}

bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t weak_start)
{
    uint32_t at, words;
    if (heap.started || !offset(obj, &at) || at != relaxed(&heap.top) ||
        !object_size(bytes, &words) || words > heap.capacity - at ||
        !mirror(at, obj, words, refs, weak_start, C4_IDLE))
        return false;

    c4_cell *cell = heap.cells + at / 2;
    put_relaxed(&cell->span, (words << 1) | (at & 1));
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
        if (!cell || relaxed(&cell->refs) >= C4_RESERVED) return false;
    }
    if (heap.moving) {
        uint32_t at;
        if (!offset(heap.moving->point_class, &at) || at >= relaxed(&heap.top)) return false;
        c4_cell *cell = cell_at(at);
        if (!cell || relaxed(&cell->refs) >= C4_RESERVED) return false;
    }
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

/* Worker can only push; sole mutator pops. The worker never re-pushes a
 * popped object in the same sweep, so the head cannot ABA mid-pop. */
static uint32_t try_bin(uint32_t words)
{
    uint32_t head = acquire(&heap.bins[words]);
    for (unsigned retry = 0; head && retry < 2; ++retry) {
        c4_cell *cell = cell_at(head - 1);
        if (!cell || relaxed(&cell->refs) != C4_FREE || relaxed(&cell->span) >> 1 != words)
            bad_contract("bad exact-size bin");
        uint32_t next = cell->bin_link;
        if (atomic_compare_exchange_strong_explicit(&heap.bins[words], &head, next,
                memory_order_acquire, memory_order_acquire))
            return head;
    }
    return 0;
}

static uintptr_t region_address(c4_move_lane *m, uint32_t region, uint32_t slot)
{
    return m->pool + (size_t)region * REGION_BYTES + (size_t)slot * POINT_BYTES;
}

static uintptr_t take_slot(c4_move_lane *m, uint32_t region, uint32_t id)
{
    c4_region *r = &m->region[region];
    if (r->used >= REGION_SLOTS) bad_contract("Point region overflow");
    uint32_t slot = r->used++;
    if (r->used <= r->high_water) {
        if (r->ids[slot] != id) ++m->source_reused;
    } else {
        r->high_water = r->used;
    }
    r->ids[slot] = id;
    if (++m->body_slots > m->body_peak) m->body_peak = m->body_slots;
    return region_address(m, region, slot);
}

static uint64_t reserve_point(void)
{
    c4_move_lane *m = heap.moving;
    if (!m->free_ids) return 0;
    for (uint32_t i = 0; i < REGION_COUNT; ++i) {
        if (i == m->source || i == m->reserve || m->region[i].used == REGION_SLOTS)
            continue;
        uint32_t id = m->free_ids - 1;
        c4_point *point = &m->points[id];
        if (point->addr || relaxed(&point->trace.refs) != C4_FREE)
            bad_contract("recycling live Point");
        m->free_ids = point->next_free;
        point->addr = take_slot(m, i, id);
        put_relaxed(&point->trace.seen, relaxed(&heap.epoch));
        put_relaxed(&point->trace.refs, C4_RESERVED);
        uint32_t occupied = atomic_fetch_add_explicit(&m->occupied, 1, memory_order_relaxed) + 1;
        if (occupied > m->peak) m->peak = occupied;
        return m->tokens + (size_t)id * 8;
    }
    return 0;
}

static uint64_t reserve_pinned(size_t bytes)
{
    uint32_t words;
    if (object_size(bytes, &words)) {
        uint32_t top = relaxed(&heap.top);
        uint32_t head = try_bin(words);
        if (head || words <= heap.capacity - top) {
            uint32_t at = head ? head - 1 : top;
            c4_cell *cell = heap.cells + at / 2;
            uint32_t epoch = relaxed(&heap.epoch);
            put_relaxed(&cell->seen, epoch);
            put_relaxed(&cell->refs, C4_RESERVED);
            if (head) {
                ++heap.reused;
            } else {
                put_relaxed(&cell->span, (words << 1) | (at & 1));
                release(&heap.top, at + words);
            }
            atomic_fetch_add_explicit(&heap.occupied, words, memory_order_relaxed);
            return heap.base + (size_t)at * 8;
        }
    }
    return 0;
}

uint64_t c4_heap_reserve(size_t bytes, enum c4_lane lane, uint64_t *init_addr)
{
    *init_addr = 0;
    if (!heap.started) return 0;
    if (heap.unpublished) bad_contract("nested private reserve");
    uint64_t obj = 0;
    if (lane == C4_PLAIN && heap.moving) {
        if (bytes != POINT_BYTES) bad_contract("non-Point extent in Point lane");
        obj = reserve_point();
        if (!obj) {
            ++heap.moving->fallback;
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
    *init_addr = token_id(obj, &id) ? heap.moving->points[id].addr : obj;
    heap.unpublished = obj;
    heap.since_begin = bytes <= SIZE_MAX - heap.since_begin
        ? heap.since_begin + bytes : SIZE_MAX;
    ++heap.allocated;
    return obj;
}

void c4_heap_publish(uint64_t obj, uint32_t refs, uint32_t weak_start)
{
    uint32_t at;
    if (!obj || obj != heap.unpublished || !key_of(obj, &at))
        bad_contract("publish outside private reserve");
    c4_cell *cell = cell_at(at);
    if (!cell || relaxed(&cell->refs) != C4_RESERVED) bad_contract("publish without reserve");
    /* New objects are black. During marking publish their initial edges,
     * not the object: allocating garbage must not keep reopening closure.
     * Only this mutator can ACK at a later checkpoint. */
    unsigned phase = acquire(&heap.phase);
    bool point = at >= heap.capacity;
    uint64_t addr = point ? heap.moving->points[at - heap.capacity].addr : obj;
    uint32_t words = point ? POINT_BYTES / 8 : relaxed(&cell->span) >> 1;
    if (!mirror(at, addr, words, refs, weak_start, phase))
        bad_contract("unsupported format, extent or weak layout");
    publish_layout(cell, refs, weak_start);
    heap.unpublished = 0;
}

void c4_heap_store_class(uint64_t obj, uint64_t value)
{
    uint32_t at, refs;
    c4_cell *cell = body_owner(obj, &at, &refs);
    _Atomic uint64_t *slot = shadow_row(at);
    uint64_t old = relaxed(slot);
    if (c4_heap_movable(value) || (at >= heap.capacity && value != old))
        bad_contract("invalid movable role in class store");
    if (cell->weak_start != C4_NO_WEAK && value != old)
        bad_contract("weak class reassignment");
    if (heap.context_class && ((old == heap.context_class) != (value == heap.context_class)))
        bad_contract("Context class reassignment");
    if (marking(acquire(&heap.phase))) {
        shade_mutator(old);
        shade_mutator(value);
    }
    release(slot, value);
    ((uint64_t *)(uintptr_t)c4_heap_address(obj))[1] = value;
}

uint32_t c4_heap_weak_start(uint64_t obj)
{
    uint32_t at, refs;
    return body_owner(obj, &at, &refs)->weak_start;
}

uint64_t c4_heap_load_ref(uint64_t obj, uint32_t index)
{
    uint32_t at, refs;
    c4_cell *cell = body_owner(obj, &at, &refs);
    if (index >= refs) bad_contract("body load outside reference slots");
    if (index < cell->weak_start) return acquire(&shadow_row(at)[1 + index]);

    /* Observe the phase first: an IDLE load must be ordered after CLEAR,
     * not sample stale shadow just before the worker publishes IDLE. */
    unsigned phase = acquire(&heap.phase);
    uint64_t value = acquire(&shadow_row(at)[1 + index]);
#ifdef SAMALTAK_C4_TEST
    extern void c4_heap_test_after_weak_load(uint64_t obj, uint32_t i, uint64_t value);
    c4_heap_test_after_weak_load(obj, index, value);
#endif
    if (marking(phase)) shade_mutator(value);
    else if ((phase == C4_CLEAR || phase == C4_SWEEP) && !post_close_live(value))
        return heap.nil;
    return value;
}

void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value)
{
    uint32_t at, refs;
    c4_cell *cell = body_owner(obj, &at, &refs);
    if (index >= refs) bad_contract("body store outside reference slots");
    _Atomic uint64_t *field = &shadow_row(at)[1 + index];
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
    release(field, value);
    ((uint64_t *)(uintptr_t)c4_heap_address(obj))[2 + (size_t)index] = value;
}

void c4_heap_move_poll(void)
{
    c4_move_lane *m = heap.moving;
    if (!m || m->source == NO_REGION || acquire(&heap.phase) != C4_IDLE) return;
    if (heap.unpublished) bad_contract("private reserve at move poll");
    uint32_t source = m->source;
    c4_region *src = &m->region[source];
    /* Don't copy a densely occupied log. Its dead IDs remain tombstones
     * until a future profitable cycle selects this region again. */
    if (m->source_live * 8 > src->used * 7) {
        ++m->dense;
        m->source = NO_REGION;
        return;
    }

    uint32_t copied = 0, inspected = 0;
    for (; m->cursor < src->used && inspected < MOVE_INSPECTIONS &&
            copied + POINT_BYTES <= MOVE_BYTES; ++m->cursor, ++inspected) {
        uint32_t id = src->ids[m->cursor];
        c4_point *point = &m->points[id];
        uintptr_t old = region_address(m, source, m->cursor);
        if (point->addr != old)
            bad_contract("Point source ownership changed");
        uint32_t refs = relaxed(&point->trace.refs);
        if (refs == C4_FREE) {
            point->addr = 0;
            if (!m->retired_head) m->retired_tail = id + 1;
            point->next_free = m->retired_head;
            m->retired_head = id + 1;
        } else {
            if (refs != 2 || relaxed(&point->trace.seen) != relaxed(&heap.epoch))
                bad_contract("unmarked or unpublished Point in source");
            uintptr_t dest = take_slot(m, m->reserve, id);
            memcpy((void *)dest, (const void *)old, POINT_BYTES);
            point->addr = dest;
            copied += POINT_BYTES;
            ++m->moved;
        }
#ifdef SAMALTAK_C4_TEST
        memset((void *)old, 0xdd, POINT_BYTES);
#endif
    }
    m->inspected += inspected;
    if (inspected > m->max_inspected) m->max_inspected = inspected;
    if (copied > m->max_copied) m->max_copied = copied;
    if (m->cursor != src->used) return;

    if (m->region[m->reserve].used != m->source_live)
        bad_contract("incomplete Point evacuation");
    if (m->retired_head) {
        m->points[m->retired_tail - 1].next_free = m->free_ids;
        m->free_ids = m->retired_head;
        m->retired_head = m->retired_tail = 0;
    }
    m->body_slots -= src->used;
    src->used = 0;
    /* An empty source needs no destination. Otherwise the empty source is
     * the next exclusive reserve, and the old destination joins the bank. */
    if (m->source_live) m->reserve = source;
    m->cursor = 0;
    m->source = NO_REGION;
    ++m->released;
}

bool c4_heap_begin(void)
{
    if (!heap.started || acquire(&heap.phase) != C4_IDLE) return false;
    if (heap.unpublished) bad_contract("private reserve at cycle start");
    c4_move_lane *m = heap.moving;
    if (m) {
        if (m->source != NO_REGION) return false;
        if (m->region[m->reserve].used) bad_contract("occupied Point reserve");
        for (uint32_t n = 0; n < REGION_COUNT; ++n) {
            uint32_t i = (m->next_source + n) % REGION_COUNT;
            if (i == m->reserve || !m->region[i].used) continue;
            m->source = i;
            m->next_source = (i + 1) % REGION_COUNT;
            break;
        }
    }
    put_relaxed(&heap.epoch, !relaxed(&heap.epoch));
    heap.since_begin = 0;
    heap.pressure = false;
    ++heap.cycles_started;
    release(&heap.phase, C4_ROOTS);
    if (heap.nil) shade_mutator(heap.nil);
    if (m) shade_mutator(m->point_class);
    wake_worker();
    return true;
}

void c4_heap_root(uint64_t value)
{
    if (acquire(&heap.phase) != C4_ROOTS) bad_contract("root outside publication");
    shade_mutator(value);
}

void c4_heap_end_roots(void)
{
    if (acquire(&heap.phase) != C4_ROOTS) bad_contract("seal outside publication");
    release(&heap.phase, C4_MARK);
    wake_worker();
}

void c4_heap_finish_poll(void)
{
    if (acquire(&heap.phase) != C4_CLOSE) return;
    /* Only we can publish inbox work, and no barrier can straddle this
     * checkpoint. Worker is parked and cannot drain until phase changes. */
    if (acquire(&heap.inbox)) {
        ++heap.close_retries;
        release(&heap.phase, C4_MARK);
    } else {
        ++heap.closed;
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
    if (!heap.started || c4_heap_busy() ||
        (heap.moving && heap.moving->source != NO_REGION)) return false;
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
    static const char *const phases[] = { "idle", "roots", "mark", "close", "clear", "sweep" };
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
    c4_move_lane *m = heap.moving;
    if (m) fprintf(stderr,
        "c4-moving: pool_bytes=%u reserve_bytes=%u ids=%u metadata_bytes=%zu"
        " live_bytes=%u peak_live_bytes=%u body_bytes=%u peak_body_bytes=%u pinned_fallback=%" PRIu64
        " moved=%" PRIu64 " inspected=%" PRIu64 " released=%" PRIu64
        " dense=%" PRIu64 " source_reused=%" PRIu64
        " max_inspected=%u max_copied=%u\n",
        REGION_COUNT * REGION_BYTES, REGION_BYTES, POINT_IDS, sizeof *m,
        relaxed(&m->occupied) * POINT_BYTES, m->peak * POINT_BYTES,
        m->body_slots * POINT_BYTES, m->body_peak * POINT_BYTES, m->fallback,
        m->moved, m->inspected, m->released, m->dense, m->source_reused,
        m->max_inspected, m->max_copied);
}

#endif
