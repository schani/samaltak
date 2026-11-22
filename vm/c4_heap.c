#include "c4_heap.h"

#if SAMALTAK_C4_SUPPORTED

#include "samaltak.h"
#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <linux/futex.h>
#include <unistd.h>

/* Single mutator; worker traces/sweeps only side metadata and the atomic
 * shadow graph. The mutator never waits for the worker, runs its work, or
 * has to flush a bounded buffer. */
_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LONG_LOCK_FREE == 2 &&
    ATOMIC_LLONG_LOCK_FREE == 2, "C4 requires native word atomics");

enum c4_phase { C4_IDLE, C4_ROOTS, C4_MARK, C4_CLOSE, C4_SWEEP };
#define C4_FREE UINT32_MAX
#define C4_RESERVED (UINT32_MAX - 1u)

#define relaxed(p) atomic_load_explicit((p), memory_order_relaxed)
#define acquire(p) atomic_load_explicit((p), memory_order_acquire)
#define put_relaxed(p, v) atomic_store_explicit((p), (v), memory_order_relaxed)
#define release(p, v) atomic_store_explicit((p), (v), memory_order_release)

/* Index by floor(word_offset / 2): object starts are >=2 words apart. The
 * low span bit distinguishes two candidate offsets in the same cell. A
 * published span never changes. Links are word offsets + 1 (0 is null). */
typedef struct {
    _Atomic uint32_t span;           /* (words << 1) | (offset & 1) */
    _Atomic uint32_t refs;           /* pointer slot count or FREE/RESERVED */
    _Atomic uint32_t seen;
    _Atomic uint32_t context_limit;  /* saved cycle-start prefix + 1, or 0 */
    uint32_t mark_link;
    uint32_t bin_link;
} c4_cell;

static struct {
    uintptr_t base;
    uint32_t capacity;              /* words */
    uint64_t context_class;
    _Atomic uint32_t *bins;         /* exact size in words */
    c4_cell *cells;
    _Atomic uint64_t *shadow;

    _Atomic uint32_t phase, epoch;
    _Atomic uint32_t inbox;         /* mutator push / worker exchange */
    _Atomic uint32_t top, occupied; /* words */
    _Atomic uint32_t wake;

    /* Mutator-owned, apart from explicitly atomic publication above. */
    size_t threshold, since_begin;  /* bytes */
    bool started, pressure;
    uint64_t imports, cycles_started, closed, close_retries, allocated, reused, failed;

    /* Worker-owned; reports are cumulative as of the last completed sweep. */
    _Atomic uint64_t cycles_completed, marked, traced_edges, reclaimed, reclaimed_bytes;
} heap;

static void bad_contract(const char *what)
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

static c4_cell *cell_at(uint32_t at)
{
    c4_cell *cell = heap.cells + at / 2;
    uint32_t span = relaxed(&cell->span);
    return span && (span & 1) == (at & 1) ? cell : NULL;
}

static bool marking(unsigned phase)
{
    return phase == C4_ROOTS || phase == C4_MARK || phase == C4_CLOSE;
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
    if (!offset(value, at) || *at >= acquire(&heap.top)) return NULL;
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
    return refs >= CTX_FIXED && heap.context_class &&
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
                uint32_t limit = is_context(at, refs)
                    ? context_snapshot_limit(at, cell, refs) : refs;
                ++marked;
                edges += (uint64_t)limit + 1;
                for (uint32_t f = 0; f <= limit; ++f)
                    shade_worker(acquire(&heap.shadow[at + 1 + f]), &local);
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
        } else if (phase == C4_SWEEP) {
            if (acquire(&heap.inbox) || local || inbound) bad_contract("close with mark work");
            uint32_t limit = acquire(&heap.top);
            for (uint32_t at = 0; at < limit; )
                at += sweep_one(at, &reclaimed, &bytes);
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

/* Real object access is mutator-only and occurs in private reserved blocks
 * or during import. Weak objects are unsupported, even without weak slots. */
static bool mirror(uint32_t at, uint32_t words, uint32_t refs, bool shade_edges)
{
    const uint64_t *obj = (const uint64_t *)(heap.base + (size_t)at * 8);
    uint64_t header = obj[0];
    unsigned format = (header >> H_FMT_SHIFT) & H_FMT_MASK;
    if (format == F_WEAK || (uint32_t)header != words - 2 ||
        refs != (format >= F_FIXED && format <= F_FIXVAR ? words - 2 : 0))
        return false;
    for (uint32_t i = 0; i <= refs; ++i) {
        uint64_t value = obj[1 + i];
        put_relaxed(&heap.shadow[at + 1 + i], value);
        if (shade_edges) shade_mutator(value);
    }
    return true;
}

bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs)
{
    uint32_t at, words;
    if (heap.started || !offset(obj, &at) || at != relaxed(&heap.top) ||
        !object_size(bytes, &words) || words > heap.capacity - at ||
        !mirror(at, words, refs, false))
        return false;

    c4_cell *cell = heap.cells + at / 2;
    put_relaxed(&cell->span, (words << 1) | (at & 1));
    put_relaxed(&cell->refs, refs);
    put_relaxed(&heap.top, at + words);
    atomic_fetch_add_explicit(&heap.occupied, words, memory_order_relaxed);
    ++heap.imports;
    return true;
}

bool c4_heap_start(void)
{
    if (!heap.base || heap.started) return false;
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

uint64_t c4_heap_alloc(size_t bytes)
{
    uint32_t words;
    if (!heap.started) return 0;
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
            heap.since_begin = bytes <= SIZE_MAX - heap.since_begin
                ? heap.since_begin + bytes : SIZE_MAX;
            ++heap.allocated;
            return heap.base + (size_t)at * 8;
        }
    }
    heap.pressure = true;
    ++heap.failed;
    return 0;
}

void c4_heap_publish(uint64_t obj, uint32_t refs)
{
    uint32_t at;
    if (!offset(obj, &at) || at >= relaxed(&heap.top)) bad_contract("publish outside heap");
    c4_cell *cell = cell_at(at);
    if (!cell || relaxed(&cell->refs) != C4_RESERVED) bad_contract("publish without reserve");
    /* New objects are black. During marking publish their initial edges,
     * not the object: allocating garbage must not keep reopening closure.
     * Only this mutator can leave CLOSE for SWEEP, at a later checkpoint. */
    bool shade_edges = marking(acquire(&heap.phase));
    if (!mirror(at, relaxed(&cell->span) >> 1, refs, shade_edges))
        bad_contract("unsupported format or bad extent");
    release(&cell->refs, refs);
}

void c4_heap_store(uint64_t *slot, uint64_t value)
{
    uint32_t at;
    if (!offset((uintptr_t)slot, &at) || !at || at >= relaxed(&heap.top))
        bad_contract("class store outside heap");
    c4_cell *cell = cell_at(at - 1);
    if (!cell || relaxed(&cell->refs) >= C4_RESERVED)
        bad_contract("class store without live owner");
    uint64_t old = relaxed(&heap.shadow[at]);
    if (heap.context_class && ((old == heap.context_class) != (value == heap.context_class)))
        bad_contract("Context class reassignment");
    if (marking(acquire(&heap.phase))) {
        shade_mutator(old);
        shade_mutator(value);
    }
    release(&heap.shadow[at], value);
    *slot = value;
}

void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value)
{
    uint32_t at;
    if (!offset(obj, &at) || at >= relaxed(&heap.top)) bad_contract("body store outside heap");
    c4_cell *cell = cell_at(at);
    uint32_t refs = cell ? relaxed(&cell->refs) : C4_FREE;
    if (refs >= C4_RESERVED || index >= refs) bad_contract("body store without live reference slot");
    uint32_t field = at + 2 + index;
    if (marking(acquire(&heap.phase))) {
        if (!is_context(at, refs)) {
            shade_mutator(relaxed(&heap.shadow[field]));
        } else {
            uint32_t limit = context_snapshot_limit(at, cell, refs);
            if (index == CTX_STACKP) release(&cell->context_limit, limit + 1);
            if (index < limit) shade_mutator(relaxed(&heap.shadow[field]));
        }
        shade_mutator(value);
    }
    release(&heap.shadow[field], value);
    ((uint64_t *)(uintptr_t)obj)[2 + (size_t)index] = value;
}

bool c4_heap_begin(void)
{
    if (!heap.started || acquire(&heap.phase) != C4_IDLE) return false;
    put_relaxed(&heap.epoch, !relaxed(&heap.epoch));
    heap.since_begin = 0;
    heap.pressure = false;
    ++heap.cycles_started;
    release(&heap.phase, C4_ROOTS);
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
        release(&heap.phase, C4_SWEEP);
    }
    wake_worker();
}

bool c4_heap_busy(void)
{
    return acquire(&heap.phase) != C4_IDLE;
}

bool c4_heap_should_collect(void)
{
    if (!heap.started || c4_heap_busy()) return false;
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
    static const char *const phases[] = { "idle", "roots", "mark", "close", "sweep" };
    unsigned phase = acquire(&heap.phase);
    fprintf(stderr,
        "c4: phase=%s imported=%" PRIu64 " cycles_started=%" PRIu64
        " cycles_completed=%" PRIu64 " closed=%" PRIu64 " close_retries=%" PRIu64
        " marked=%" PRIu64 " traced_edges=%" PRIu64 " reclaimed=%" PRIu64
        " reclaimed_bytes=%" PRIu64
        " allocated=%" PRIu64 " reused=%" PRIu64 " failed=%" PRIu64
        " high_water_bytes=%" PRIu64 " in_use_bytes=%" PRIu64 "\n",
        phases[phase], heap.imports, heap.cycles_started, relaxed(&heap.cycles_completed),
        heap.closed, heap.close_retries, relaxed(&heap.marked), relaxed(&heap.traced_edges), relaxed(&heap.reclaimed),
        relaxed(&heap.reclaimed_bytes), heap.allocated, heap.reused, heap.failed,
        (uint64_t)relaxed(&heap.top) * 8, (uint64_t)relaxed(&heap.occupied) * 8);
}

#endif
