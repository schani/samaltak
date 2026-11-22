#include "c4_heap.h"
#include "samaltak.h"

#include <assert.h>
#include <sched.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>

static _Atomic bool stall_close, at_close, stall_enum, at_enum;
static _Atomic unsigned proposals;
static _Atomic bool stall_cas, at_cas;
static oop race_owner, race_prev;
static uint32_t race_slot;
static bool finish_during_load;
static _Atomic bool stall_enum_field, at_enum_field;
static uint32_t enum_owner_word, enum_slot;
static _Atomic bool stall_mark_chunk, at_mark_chunk;
static uint32_t mark_owner_word, mark_chunk_word;

/* Runs on the mutator after the shadow read. Force the worker to finish
 * while that read still holds the pre-CAS bits in a local. */
void c4_heap_test_after_weak_load(uint64_t obj, uint32_t i, uint64_t value)
{
    if (!finish_during_load) return;
    assert(obj == race_owner && i == race_slot && value == race_prev);
    assert(atomic_load(&at_cas));
    atomic_store(&stall_cas, false);
    while (c4_heap_busy()) sched_yield();
}

/* The release of the close ACK publishes the configured race tuple. */
void c4_heap_test_before_weak_cas(uint64_t obj, uint32_t i, uint64_t prev)
{
    if (!atomic_load(&stall_cas) || obj != race_owner || i != race_slot) return;
    assert(prev == race_prev);
    atomic_store(&at_cas, true);
    while (atomic_load(&stall_cas)) sched_yield();
}

/* Runs on the worker after it releases the close proposal. */
void c4_heap_test_after_close(void)
{
    atomic_fetch_add(&proposals, 1);
    if (!atomic_load(&stall_close)) return;
    atomic_store(&at_close, true);
    while (atomic_load(&stall_close)) sched_yield();
}

void c4_heap_test_before_enum(void)
{
    atomic_store(&at_enum, true);
    while (atomic_load(&stall_enum)) sched_yield();
}

/* Park the worker after it observes an implicit-nil slot. The adjacent
 * slot in the same chunk will then take the materialized/version path. */
void c4_heap_test_enum_field(uint32_t at, uint32_t i, bool materialized)
{
    if (!atomic_load(&stall_enum_field) || at != enum_owner_word || i != enum_slot) return;
    assert(!materialized);
    atomic_store(&at_enum_field, true);
    while (atomic_load(&stall_enum_field)) sched_yield();
}

/* Stop after the tag load, before the worker acts on the mismatch. */
void c4_heap_test_mark_chunk(uint32_t at, uint32_t word, bool materialized)
{
    if (!atomic_load(&stall_mark_chunk) || at != mark_owner_word || word != mark_chunk_word) return;
    assert(!materialized);
    atomic_store(&at_mark_chunk, true);
    while (atomic_load(&stall_mark_chunk)) sched_yield();
}

static void *arena(size_t size)
{
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(p != MAP_FAILED);
    assert(c4_heap_supported() && c4_heap_init(p, size));
    return p;
}

static oop reserve_pinned(size_t bytes)
{
    oop addr;
    oop obj = c4_heap_reserve(bytes, C4_PINNED, &addr);
    assert(obj == addr);
    return obj;
}

static size_t extent(uint32_t slots)
{
    return (2 + (size_t)slots) * sizeof(oop);
}

static void initialize(oop obj, oop cls, unsigned fmt, uint32_t slots)
{
    oop *p = (oop *)(uintptr_t)obj;
    p[0] = ((oop)fmt << H_FMT_SHIFT) | slots;
    p[1] = cls;
    for (uint32_t i = 0; i < slots; ++i) p[2 + i] = 1;
}

static void publish(oop obj, oop cls, unsigned fmt, uint32_t slots)
{
    initialize(obj, cls, fmt, slots);
    c4_heap_publish(obj, fmt >= F_FIXED && fmt <= F_FIXVAR ? slots : 0, C4_NO_WEAK);
}

static oop alloc(oop cls, unsigned fmt, uint32_t slots)
{
    oop obj = reserve_pinned(extent(slots));
    assert(obj);
    publish(obj, cls, fmt, slots);
    return obj;
}

static void finish_cycle(void)
{
    /* The shell timeout bounds the test, not the engine. A real mutator
     * keeps interpreting while the worker progresses. */
    while (c4_heap_busy()) {
        c4_heap_finish_poll();
        sched_yield();
    }
}

static void hostile_close(void)
{
    size_t size = 32 * 1024;
    arena(size);
    assert(c4_heap_start());
    oop cls = alloc(1, F_EMPTY, 0);
    oop root = alloc(cls, F_FIXED, 1);
    oop branch = alloc(cls, F_VAR, 2);
    oop child = alloc(cls, F_VAR, 3);
    oop dead = alloc(cls, F_VAR, 4);
    c4_heap_store_ref(branch, 0, child);

    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(root);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();

    /* Inject white work after the close proposal; unpublished work must
     * force another tracing pass, not race with sweep. */
    c4_heap_store_ref(root, 0, branch);
    alloc(cls, F_EMPTY, 0);
    for (unsigned i = 0; i < 100000; ++i) {
        c4_heap_store_ref(root, 0, branch);
        c4_heap_finish_poll();
        assert(c4_heap_busy());
        assert(!c4_heap_should_collect());
        assert(reserve_pinned(size) == 0);
    }
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(atomic_load(&proposals) >= 2);
    assert(alloc(cls, F_VAR, 4) == dead);
    assert(alloc(cls, F_VAR, 2) != branch);
    assert(alloc(cls, F_VAR, 3) != child);
}

static void shadow_snapshot(void)
{
    const size_t size = 4096;
    void *base = arena(size);
    oop cls = (oop)(uintptr_t)base;
    initialize(cls, cls, F_WEAK, 0);
    assert(!c4_heap_import(cls, extent(0), 0, C4_NO_WEAK));
    initialize(cls, cls, F_EMPTY, 0);
    assert(c4_heap_import(cls, extent(0), 0, C4_NO_WEAK));
    c4_heap_set_context_class(cls + extent(0));
    assert(c4_heap_start());
    oop ctx_cls = alloc(cls, F_EMPTY, 0);
    oop ctx = alloc(ctx_cls, F_FIXVAR, CTX_FIXED + 2);
    oop live_stack = alloc(cls, F_VAR, 1);
    oop stale_tail = alloc(cls, F_VAR, 2);
    oop root = alloc(cls, F_VAR, 1);
    oop old_edge = alloc(cls, F_VAR, 3);

    c4_heap_store_ref(ctx, CTX_STACKP, 3); /* SmallInteger 1 */
    c4_heap_store_ref(ctx, CTX_FIXED, live_stack);
    c4_heap_store_ref(ctx, CTX_FIXED + 1, stale_tail);
    c4_heap_store_ref(root, 0, old_edge);
    assert(c4_heap_begin());
    c4_heap_store_ref(ctx, CTX_STACKP, 1); /* shrink to zero */
    c4_heap_store_ref(ctx, CTX_FIXED + 1, 1);
    c4_heap_store_ref(root, 0, 1);
    c4_heap_root(ctx);
    for (unsigned i = 0; i < 50; ++i) {
        c4_heap_finish_poll();
        assert(c4_heap_busy());
        sched_yield();
    }
    assert(atomic_load(&proposals) == 0);
    c4_heap_root(root);

    /* Marking and sweeping must work with the real arena unreadable. */
    assert(mprotect(base, size, PROT_NONE) == 0);
    c4_heap_end_roots();
    finish_cycle();
    assert(mprotect(base, size, PROT_READ | PROT_WRITE) == 0);
    oop recycled = alloc(cls, F_VAR, 2);
    assert(recycled == stale_tail);
    oop stack_probe = alloc(cls, F_VAR, 1);
    oop edge_probe = alloc(cls, F_VAR, 3);
    assert(stack_probe != live_stack && edge_probe != old_edge);

    assert(c4_heap_begin());
    c4_heap_root(ctx);
    c4_heap_root(root);
    c4_heap_root(recycled);
    c4_heap_root(stack_probe);
    c4_heap_root(edge_probe);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(cls, F_VAR, 3) == old_edge);
    assert(alloc(cls, F_VAR, 1) == live_stack);
}

static oop import_nil(void *base)
{
    oop nil = (oop)(uintptr_t)base;
    c4_heap_set_nil(nil);
    initialize(nil, nil, F_EMPTY, 0);
    assert(c4_heap_import(nil, extent(0), 0, C4_NO_WEAK));
    return nil;
}

static void weak_close(void)
{
    /* Room for one new owner, then every allocation needs a swept cell. */
    size_t size = extent(0) + extent(1) + extent(2) + extent(3) + extent(4) +
        2 * extent(6) + extent(7);
    oop nil = import_nil(arena(size));
    oop owner = nil + extent(0);
    initialize(owner, nil, F_WEAK, 6);
    assert(!c4_heap_import(owner, extent(6), 6, C4_NO_WEAK));
    assert(!c4_heap_import(owner, extent(6), 0, 1));
    assert(!c4_heap_import(owner, extent(6), 6, 7));
    assert(c4_heap_import(owner, extent(6), 6, 1));
    assert(c4_heap_start());

    oop prefix = alloc(nil, F_VAR, 1);
    oop survivor = alloc(nil, F_VAR, 2);
    oop dying = alloc(nil, F_VAR, 3);
    oop raced = alloc(nil, F_VAR, 4);
    oop child = alloc(nil, F_VAR, 6);
    c4_heap_store_ref(survivor, 0, child);
    c4_heap_store_ref(owner, 0, prefix);
    c4_heap_store_ref(owner, 1, survivor);
    c4_heap_store_ref(owner, 2, dying);
    c4_heap_store_ref(owner, 3, raced);
    c4_heap_store_ref(owner, 4, 6); /* Tagged immediate */
    assert(c4_heap_weak_start(owner) == 1);
    assert(c4_heap_load_ref(owner, 2) == dying);

    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    /* The two pre-ACK weak stores must not shade old or new edges. */
    c4_heap_store_ref(owner, 2, raced);
    c4_heap_store_ref(owner, 2, dying);
    assert(c4_heap_load_ref(owner, 1) == survivor);
    c4_heap_finish_poll(); /* Weak read must reopen CLOSE. */
    race_owner = owner;
    race_slot = 3;
    race_prev = raced;
    atomic_store(&stall_cas, true);
    atomic_store(&stall_close, false);
    while (atomic_load(&proposals) < 2) {
        c4_heap_finish_poll();
        sched_yield();
    }
    /* Hold CAS after reading the exact white value in slot 3. At this
     * point slot 2 has already been cleared but neither cell is reusable. */
    c4_heap_finish_poll();
    while (!atomic_load(&at_cas)) sched_yield();
    assert(c4_heap_load_ref(owner, 0) == prefix);
    assert(c4_heap_load_ref(owner, 1) == survivor);
    assert(c4_heap_load_ref(owner, 2) == nil);
    assert(c4_heap_load_ref(owner, 3) == nil); /* Before CAS. */
    assert(c4_heap_load_ref(owner, 4) == 6);
    c4_heap_store_ref(owner, 3, prefix);
    /* Allocated above CLEAR's high-water snapshot, so publication itself
     * must reject white weak edges. This owner cannot be visited in CLEAR. */
    oop post_ack_owner = reserve_pinned(extent(7));
    assert(post_ack_owner);
    initialize(post_ack_owner, nil, F_WEAK, 7);
    ((oop *)(uintptr_t)post_ack_owner)[2] = raced;
    ((oop *)(uintptr_t)post_ack_owner)[3] = prefix;
    c4_heap_publish(post_ack_owner, 7, 0);
    c4_heap_store_ref(owner, 5, raced); /* Simulate a stale caller after ACK. */
    assert(c4_heap_load_ref(owner, 5) == nil);
    for (unsigned i = 0; i < 10000; ++i) {
        c4_heap_store_ref(owner, 3, prefix);
        assert(c4_heap_load_ref(owner, 3) == prefix);
        c4_heap_finish_poll();
        assert(c4_heap_busy() && !c4_heap_should_collect());
        assert(reserve_pinned(extent(3)) == 0);
        assert(reserve_pinned(extent(4)) == 0);
    }
    atomic_store(&stall_cas, false);
    finish_cycle();

    assert(c4_heap_take_weak_clears() == 1);
    assert(c4_heap_take_weak_clears() == 0);
    assert(reserve_pinned(extent(3) + extent(4) + 8) == 0);
    assert(alloc(nil, F_VAR, 3) == dying);
    assert(alloc(nil, F_VAR, 4) == raced);
    assert(reserve_pinned(extent(0)) == 0);
    assert(((const oop *)(uintptr_t)owner)[2 + 2] == dying); /* Raw stays stale. */
    assert(c4_heap_load_ref(owner, 2) == nil); /* No address ABA in IDLE. */
    assert(c4_heap_load_ref(owner, 3) == prefix);
    assert(c4_heap_load_ref(post_ack_owner, 0) == nil);
    assert(c4_heap_load_ref(post_ack_owner, 1) == prefix);
}

static void weak_shadow(void)
{
    /* Logical arena is deliberately full, although the mapping is rounded. */
    size_t size = extent(0) + extent(1) + 3 * extent(2) + extent(3) +
        extent(4) + extent(5);
    void *base = arena(size);
    oop nil = import_nil(base);
    assert(c4_heap_start());
    oop read = alloc(nil, F_VAR, 1);
    oop white = alloc(nil, F_VAR, 2);
    oop displaced = alloc(nil, F_VAR, 2);
    oop fixed = alloc(nil, F_VAR, 2);
    oop dead_owner = reserve_pinned(extent(3));
    initialize(dead_owner, nil, F_WEAK, 3);
    ((oop *)(uintptr_t)dead_owner)[2] = white;
    c4_heap_publish(dead_owner, 3, 0);
    oop owner = reserve_pinned(extent(4));
    initialize(owner, nil, F_WEAK, 4);
    ((oop *)(uintptr_t)owner)[2] = read;
    ((oop *)(uintptr_t)owner)[3] = displaced;
    c4_heap_publish(owner, 4, 0);

    assert(c4_heap_begin());
    c4_heap_root(owner);
    assert(c4_heap_load_ref(owner, 0) == read); /* ROOTS shades. */
    c4_heap_store_ref(owner, 1, white); /* Neither old nor new may be shaded. */
    oop fresh = reserve_pinned(extent(5));
    initialize(fresh, nil, F_WEAK, 5);
    ((oop *)(uintptr_t)fresh)[2] = fixed;
    ((oop *)(uintptr_t)fresh)[3] = displaced;
    c4_heap_publish(fresh, 5, 1); /* Black; shade fixed field, not tail. */

    /* Mutator weak loads and all worker work run without real oop words. */
    assert(mprotect(base, size, PROT_NONE) == 0);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_load_ref(owner, 0) == read);
    assert(c4_heap_load_ref(owner, 1) == nil);
    assert(c4_heap_load_ref(fresh, 0) == fixed);
    assert(c4_heap_load_ref(fresh, 1) == nil);
    assert(c4_heap_take_weak_clears() == 2);
    assert(c4_heap_take_weak_clears() == 0);
    assert(mprotect(base, size, PROT_READ | PROT_WRITE) == 0);

    /* dead_owner reuses its address as a strong object. On reuse, the
     * recorded layout must not retain the previous weak prefix. */
    oop replacement = alloc(nil, F_VAR, 3);
    assert(replacement == dead_owner);
    assert(c4_heap_weak_start(replacement) == C4_NO_WEAK);
    c4_heap_store_ref(replacement, 1, read);
    c4_heap_store_ref(owner, 1, fixed);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(replacement);
    c4_heap_end_roots();
    assert(mprotect(base, size, PROT_NONE) == 0);
    finish_cycle();
    assert(c4_heap_load_ref(owner, 0) == read);
    assert(c4_heap_load_ref(owner, 1) == nil);
    assert(c4_heap_take_weak_clears() == 1);
    assert(c4_heap_take_weak_clears() == 0);
    assert(mprotect(base, size, PROT_READ | PROT_WRITE) == 0);
}

static void weak_idle_transition(void)
{
    void *base = arena(extent(0) + extent(1) + extent(2));
    oop nil = import_nil(base);
    assert(c4_heap_start());
    oop owner = reserve_pinned(extent(1));
    initialize(owner, nil, F_WEAK, 1);
    c4_heap_publish(owner, 1, 0);
    oop white = alloc(nil, F_VAR, 2);
    c4_heap_store_ref(owner, 0, white);

    race_owner = owner;
    race_slot = 0;
    race_prev = white;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }

    finish_during_load = true;
    assert(c4_heap_load_ref(owner, 0) == nil);
    finish_during_load = false;
    assert(!c4_heap_busy());
    assert(c4_heap_take_weak_clears() == 1);
    assert(alloc(nil, F_VAR, 2) == white);
    assert(c4_heap_load_ref(owner, 0) == nil);
}

enum { NODES = 768, SHAPES = 4, LINKS = 2 };

static uint32_t rand32(void)
{
    static uint32_t state = 0x52aa3c9b;
    state ^= state << 13;
    state ^= state >> 17;
    return state ^= state << 5;
}

static uint32_t slots_for(unsigned i)
{
    return LINKS + i % SHAPES;
}

static void oracle(void)
{
    oop nodes[NODES], guards[NODES];
    unsigned edges[NODES][LINKS];
    size_t size = (NODES + 1) * extent(0);
    for (unsigned i = 0; i < NODES; ++i) size += extent(slots_for(i));
    arena(size);
    assert(c4_heap_start());
    oop cls = alloc(1, F_EMPTY, 0);
    for (unsigned i = 0; i < NODES; ++i) {
        nodes[i] = alloc(cls, F_VAR, slots_for(i));
        /* Isolate individual extents so this graph oracle can recover each
         * white object exactly. The pinned tests exercise merged runs. */
        guards[i] = alloc(cls, F_EMPTY, 0);
    }

    for (unsigned round = 0; round < 32; ++round) {
        bool live[NODES] = {false}, recovered[NODES] = {false};
        unsigned todo[NODES], head = 0, tail = 0;

        /* Random cycles and disconnected components, with varying roots. */
        unsigned group_size = 16 + rand32() % 128;
        for (unsigned i = 0; i < NODES; ++i) {
            unsigned base = i / group_size * group_size;
            unsigned span = NODES - base < group_size ? NODES - base : group_size;
            for (unsigned e = 0; e < LINKS; ++e) {
                edges[i][e] = base + rand32() % span;
                c4_heap_store_ref(nodes[i], e, nodes[edges[i][e]]);
            }
        }
        assert(c4_heap_begin());
        for (unsigned i = 0; i < NODES; ++i) c4_heap_root(guards[i]);
        unsigned roots = 1 + rand32() % 12;
        for (unsigned r = 0; r < roots; ++r) {
            unsigned i = rand32() % NODES;
            c4_heap_root(nodes[i]);
            if (!live[i]) {
                live[i] = true;
                todo[tail++] = i;
            }
        }
        c4_heap_end_roots();

        /* Independent graph traversal, not based on collector state. */
        while (head < tail) {
            unsigned i = todo[head++];
            for (unsigned e = 0; e < LINKS; ++e) {
                unsigned j = edges[i][e];
                if (!live[j]) {
                    live[j] = true;
                    todo[tail++] = j;
                }
            }
        }
        finish_cycle();

        /* Arena has no bump room. Every alloc is a nonmoving sweep result. */
        for (unsigned shape = SHAPES; shape > 0; --shape) {
            uint32_t slots = slots_for(shape - 1);
            oop result;
            while ((result = reserve_pinned(extent(slots)))) {
                unsigned i = 0;
                while (i < NODES && nodes[i] != result) ++i;
                assert(i < NODES && !live[i] && !recovered[i] && slots == slots_for(i));
                recovered[i] = true;
                publish(result, cls, F_VAR, slots);
            }
        }
        for (unsigned i = 0; i < NODES; ++i) assert(recovered[i] != live[i]);
    }
}

static void pinned_fit(void)
{
    /* Fill the arena with unlike extents. Reclaim two adjacent objects
     * across a bin boundary, split to different sizes, and retain the
     * odd-word tail of another run as padding, not as logical body. */
    size_t full = extent(0) + extent(19) + extent(13) + extent(1) + extent(6) + extent(1);
    oop nil = import_nil(arena(full));
    assert(c4_heap_start());
    oop left = alloc(nil, F_VAR, 19);
    alloc(nil, F_VAR, 13);
    oop guard = alloc(nil, F_VAR, 1);
    oop tail = alloc(nil, F_VAR, 6);
    oop end = alloc(nil, F_VAR, 1);
    assert(c4_heap_top() == nil + full && reserve_pinned(extent(0)) == 0);
    c4_heap_store_ref(guard, 0, end);
    c4_heap_store_ref(end, 0, 17);

    for (unsigned round = 0; round < 3; ++round) {
        assert(c4_heap_begin());
        c4_heap_root(guard);
        c4_heap_end_roots();
        finish_cycle();
        /* No fit across the live guard; then consume both free runs. */
        assert(reserve_pinned(extent(35)) == 0);
        assert(alloc(nil, F_VAR, 27) == left);
        assert(alloc(nil, F_VAR, 5) == left + extent(27));
        assert(alloc(nil, F_VAR, 5) == tail); /* one trailing word */
        assert(reserve_pinned(extent(0)) == 0);
        assert(c4_heap_top() == nil + full);
        assert(c4_heap_load_ref(guard, 0) == end && c4_heap_load_ref(end, 0) == 17);
    }
}

static void pinned_clear_split(void)
{
    /* A prior free run borders a current white run. Split the former at
     * different parity while CLEAR is stalled on a weak reference into the
     * latter. The worker must see safe old or new boundaries, never ABA. */
    size_t full = extent(0) + extent(1) + extent(2) + extent(6) + extent(4) + extent(1);
    oop nil = import_nil(arena(full));
    assert(c4_heap_start());
    oop owner = reserve_pinned(extent(1));
    initialize(owner, nil, F_WEAK, 1);
    c4_heap_publish(owner, 1, 0);
    oop prior = alloc(nil, F_VAR, 2);
    oop old_start = alloc(nil, F_VAR, 6);
    oop white = alloc(nil, F_VAR, 4);
    oop guard = alloc(nil, F_VAR, 1);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(white);
    c4_heap_root(guard);
    c4_heap_end_roots();
    finish_cycle();

    c4_heap_store_ref(owner, 0, white);
    race_owner = owner;
    race_slot = 0;
    race_prev = white;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(guard);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    assert(alloc(nil, F_VAR, 1) == prior);
    /* The new start is one word before the old start, at another parity. */
    oop replacement = alloc(nil, F_VAR, 7);
    assert(replacement + 8 == old_start);
    c4_heap_store_ref(replacement, 6, guard);
    assert(c4_heap_load_ref(owner, 0) == nil && reserve_pinned(extent(0)) == 0);
    atomic_store(&stall_cas, false);
    finish_cycle();
    assert(c4_heap_take_weak_clears() == 1);
    assert(alloc(nil, F_VAR, 4) == white);
    assert(c4_heap_load_ref(owner, 0) == nil);
    assert(c4_heap_load_ref(replacement, 6) == guard);
}

static oop init_moving(size_t pinned_bytes)
{
    /* Deliberately exact cap: four 16 KiB regions, plus pinned bytes. */
    size_t cap = pinned_bytes + 4 * 16384;
    void *p = mmap(NULL, cap, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(p != MAP_FAILED);
    assert(c4_heap_init_moving(p, cap));
    assert(c4_heap_pinned_capacity() == pinned_bytes);
    oop cls = (oop)(uintptr_t)p;
    initialize(cls, cls, F_FIXED, 0);
    assert(c4_heap_import(cls, 16, 0, C4_NO_WEAK));
    c4_heap_set_plain_classes(cls, 0, 0);
    c4_heap_set_nil(cls);
    assert(c4_heap_start());
    return cls;
}

static oop point(oop cls, bool expect_handle)
{
    oop address, obj = c4_heap_reserve(32, C4_PLAIN, &address);
    assert(obj && c4_heap_movable(obj) == expect_handle);
    assert((address != obj) == expect_handle && !c4_heap_movable(address));
    initialize(address, cls, F_FIXED, 2);
    c4_heap_publish(obj, 2, C4_NO_WEAK);
    assert(c4_heap_address(obj) == address);
    return obj;
}

static const oop *body(oop obj)
{
    return (const oop *)(uintptr_t)c4_heap_address(obj);
}

static void moving(bool leak_read)
{
    enum { SLOTS = 512 };
    oop cls = init_moving(16384);
    oop p[SLOTS], old[SLOTS];
    for (unsigned i = 0; i < SLOTS; ++i) {
        p[i] = point(cls, true);
        old[i] = c4_heap_address(p[i]);
    }
    /* A direct root enters the cycle p[0] -> p[1] -> p[2] -> p[0].
     * The other evens are reachable solely from a pinned object's shadow,
     * which itself is reachable only as another pinned object's class. */
    c4_heap_store_ref(p[0], 0, p[1]);
    c4_heap_store_ref(p[1], 0, p[2]);
    c4_heap_store_ref(p[2], 0, p[0]);
    oop links = alloc(cls, F_VAR, SLOTS / 2);
    for (unsigned i = 4; i < SLOTS; i += 2)
        c4_heap_store_ref(links, i / 2, p[i]);
    oop class_edge = alloc(cls, F_FIXED, 0);
    c4_heap_store_class(class_edge, links);
    oop weak = reserve_pinned(40);
    initialize(weak, cls, F_WEAK, 3);
    c4_heap_publish(weak, 3, 0);
    c4_heap_store_ref(weak, 0, p[1]);
    c4_heap_store_ref(weak, 1, p[SLOTS - 1]);
    oop header = body(p[0])[0] | H_IMMUTABLE | ((oop)123 << H_HASH_SHIFT);
    ((oop *)(uintptr_t)old[0])[0] = header;

    race_owner = weak;
    race_slot = 1;
    race_prev = p[SLOTS - 1];
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(p[0]);
    c4_heap_root(weak);
    c4_heap_root(class_edge);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    assert(c4_heap_load_ref(weak, 1) == cls);
    c4_heap_store_ref(weak, 2, p[SLOTS - 1]);
    assert(c4_heap_load_ref(weak, 2) == cls);
    atomic_store(&stall_cas, false);
    finish_cycle();
    assert(c4_heap_take_weak_clears() == 1);
    assert(c4_heap_load_ref(weak, 1) == cls);
    assert(c4_heap_address(p[0]) == old[0]);  /* sweep does not relocate */
    assert(!c4_heap_begin());               /* also blocks epoch re-arm */
    c4_heap_enter_raw_read();
    assert(body(p[0])[0] == header);
    if (!leak_read) c4_heap_leave_raw_read();
    for (unsigned poll = 0; poll < 8; ++poll) {
        unsigned before = poll * 64;
        c4_heap_move_poll();
        for (unsigned i = 0; i < SLOTS; i += 2)
            assert((c4_heap_address(p[i]) != old[i]) == (i < before + 64));
    }
    assert(body(p[0])[0] == header && body(p[0])[1] == cls && body(p[0])[2] == p[1]);
    assert(body(class_edge)[1] == links && body(links)[4] == p[4]);
    assert(c4_heap_load_ref(weak, 0) == p[1] && c4_heap_address(p[1]) != old[1]);
    assert(body(p[1])[2] == p[2] && body(p[2])[2] == p[0]);

    oop fresh = point(cls, true);
    assert(fresh == p[SLOTS - 1]);  /* logical id reused only after weak clear + retirement */
    assert(c4_heap_load_ref(weak, 1) == cls);
    c4_heap_store_ref(p[1], 1, fresh);
    assert(body(p[1])[3] == fresh);
    for (unsigned i = 0; i < 100; ++i) point(cls, true);

    assert(c4_heap_begin());
    c4_heap_root(p[0]);
    c4_heap_root(weak);
    c4_heap_root(class_edge);
    c4_heap_end_roots();
    finish_cycle();
    c4_heap_move_poll();
    assert(!c4_heap_begin());
    c4_heap_move_poll();
    /* Reuses a precisely identified old source address with another id. */
    assert(fresh != p[0] && c4_heap_address(fresh) == old[0]);
    assert(c4_heap_address(p[0]) != old[0] && body(p[0])[0] == header);
    assert(c4_heap_load_ref(weak, 0) == p[1] && c4_heap_load_ref(p[1], 1) == fresh);
    c4_heap_stats();
}

static void moving_general(void)
{
    size_t cap = 5 * 16384;
    void *base = mmap(NULL, cap, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(base != MAP_FAILED && c4_heap_init_moving(base, cap));
    oop cls = (oop)(uintptr_t)base, msg_class = cls + 16, assoc_class = cls + 32;
    for (oop o = cls; o <= assoc_class; o += 16) {
        initialize(o, cls, F_FIXED, 0);
        assert(c4_heap_import(o, 16, 0, C4_NO_WEAK));
    }
    c4_heap_set_nil(cls);
    c4_heap_set_plain_classes(cls, msg_class, assoc_class);
    assert(c4_heap_start());
    assert(c4_heap_plain_class(cls) && c4_heap_plain_class(msg_class) &&
        c4_heap_plain_class(assoc_class) && !c4_heap_plain_class(0));

    oop assoc = point(assoc_class, true), message = point(msg_class, true);
    oop dead_assoc = point(assoc_class, true), dead_message = point(msg_class, true);
    oop literals = alloc(cls, F_VAR, 2), weak = reserve_pinned(40);
    initialize(weak, cls, F_WEAK, 3);
    c4_heap_publish(weak, 3, 0);
    c4_heap_store_ref(literals, 0, assoc);
    c4_heap_store_ref(assoc, 1, message);
    c4_heap_store_ref(message, 1, assoc);
    c4_heap_store_ref(weak, 0, message);
    c4_heap_store_ref(weak, 1, dead_assoc);
    c4_heap_store_ref(weak, 2, dead_message);

    /* Frame-like borrow into a pinned container; entries are oops,
     * not addresses of the two-slot bodies. */
    const oop *lits = body(literals) + 2;
    uintptr_t old_assoc = (uintptr_t)body(assoc), old_message = (uintptr_t)body(message);
    assert(c4_heap_begin());
    c4_heap_root(literals);
    c4_heap_root(weak);
    c4_heap_end_roots();
    finish_cycle();
    c4_heap_move_poll();

    assert(lits == body(literals) + 2 && lits[0] == assoc);
    assert((uintptr_t)body(lits[0]) != old_assoc);
    assert((uintptr_t)body(message) != old_message);
    assert(*(const oop *)old_assoc == UINT64_C(0xdddddddddddddddd));
    assert(*(const oop *)old_message == UINT64_C(0xdddddddddddddddd));
    assert(body(assoc)[1] == assoc_class && body(message)[1] == msg_class);
    assert(body(lits[0])[3] == message && body(message)[3] == lits[0]);
    assert(c4_heap_load_ref(weak, 0) == message);
    assert(c4_heap_load_ref(weak, 1) == cls && c4_heap_load_ref(weak, 2) == cls);
    assert(c4_heap_take_weak_clears() == 2);

    c4_heap_store_ref(lits[0], 1, (oop)199);
    assert(body(assoc)[3] == (oop)199 && c4_heap_load_ref(assoc, 1) == (oop)199);
    c4_heap_stats();
}

static void moving_saturated(void)
{
    enum { SLOTS = 512 };
    oop cls = init_moving(16 + 32);
    oop p[SLOTS];
    for (unsigned i = 0; i < SLOTS; ++i) p[i] = point(cls, true);
    oop first = c4_heap_address(p[0]);
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    for (unsigned i = 0; i < SLOTS; ++i) c4_heap_root(p[i]);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();

    /* Both other alloc regions can be filled with the worker stalled.
     * Neither the sealed source nor the independent reserve is available. */
    oop next = c4_heap_address(point(cls, true));
    for (unsigned i = 1; i < 2 * SLOTS; ++i) point(cls, true);
    point(cls, false);
    oop addr;
    assert(!c4_heap_reserve(32, C4_PLAIN, &addr) && !addr);
    c4_heap_move_poll();
    assert(c4_heap_address(p[0]) == first);
    atomic_store(&stall_close, false);
    finish_cycle();
    c4_heap_move_poll();  /* dense source skipped */
    assert(c4_heap_address(p[0]) == first);

    assert(c4_heap_begin());
    c4_heap_end_roots();
    finish_cycle();
    for (unsigned poll = 0; poll < 8; ++poll) c4_heap_move_poll();
    assert(c4_heap_address(point(cls, true)) == next);  /* empty source reclaimed */
}

static oop forward_start(size_t extra, oop *bytes_class, oop *wide_class)
{
    oop nil = import_nil(arena(3 * extent(0) + extra));
    *bytes_class = nil + extent(0);
    *wide_class = *bytes_class + extent(0);
    initialize(*bytes_class, nil, F_EMPTY, 0);
    initialize(*wide_class, nil, F_EMPTY, 0);
    assert(c4_heap_import(*bytes_class, extent(0), 0, C4_NO_WEAK));
    assert(c4_heap_import(*wide_class, extent(0), 0, C4_NO_WEAK));
    c4_heap_set_forward_classes(*bytes_class, *wide_class);
    assert(c4_heap_start());
    assert(!c4_heap_has_forwarding());
    return nil;
}

static void raw_read(const char *op)
{
    oop bc, wc;
    forward_start(2 * extent(1), &bc, &wc);
    oop from = alloc(bc, F_BYTES + 7, 1);
    oop to = alloc(wc, F_W32 + 1, 1);
    if (!strcmp(op, "unpaired")) c4_heap_leave_raw_read();

    if (strcmp(op, "start")) {
        assert(c4_heap_begin());
        c4_heap_root(from);
        c4_heap_root(to);
        c4_heap_end_roots();
        while (!atomic_load(&proposals)) sched_yield();
    }

    c4_heap_enter_raw_read();
    assert(body(from)[2] == 1);
    if (!strcmp(op, "nest")) c4_heap_enter_raw_read();
    if (!strcmp(op, "start")) c4_heap_begin();
    if (!strcmp(op, "close")) c4_heap_finish_poll();
    if (!strcmp(op, "forward")) c4_heap_become_forward(from, to);
    c4_heap_leave_raw_read();

    assert(!strcmp(op, "ok"));
    finish_cycle();
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_address(from) == to);
}

static oop weak_owner(oop cls, uint32_t slots)
{
    oop obj = reserve_pinned(extent(slots));
    assert(obj);
    initialize(obj, cls, F_WEAK, slots);
    c4_heap_publish(obj, slots, 0);
    return obj;
}

static void forward_strong(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(1) + extent(2) + extent(3) +
        extent(4) + extent(5) + extent(6), &bc, &wc);
    oop holder = alloc(nil, F_VAR, 1);
    oop from = alloc(bc, F_BYTES + 4, 2);
    oop to = alloc(wc, F_W32 + 1, 3);
    oop forbidden = alloc(bc, F_BYTES, 4);
    oop other_wide = alloc(wc, F_W32, 5);
    oop *from_words = (oop *)(uintptr_t)from;
    oop *to_words = (oop *)(uintptr_t)to;
    from_words[0] |= (oop)42 << H_HASH_SHIFT;
    to_words[0] |= (oop)123 << H_HASH_SHIFT;
    c4_heap_forbid_become(forbidden);

    assert(!c4_heap_become_forward(from, forbidden));
    assert(!c4_heap_become_forward(to, other_wide));
    assert(!c4_heap_become_forward(to, from));
    assert(!c4_heap_become_forward(from, from));
    assert(!c4_heap_become_forward(from, nil));
    assert(!c4_heap_become_forward(from, 3));
    assert(!c4_heap_become_forward(forbidden, to));
    assert(!c4_heap_has_forwarding());

    c4_heap_store_ref(holder, 0, from);
    assert(c4_heap_become_forward(from, to));
    assert(!c4_heap_become_forward(from, other_wide));
    assert(c4_heap_has_forwarding());
    assert(c4_heap_canonical(from) == to && c4_heap_canonical(to) == to);
    assert(c4_heap_canonical(3) == 3);
    const oop *resolved = (const oop *)(uintptr_t)c4_heap_address(from);
    assert(resolved == to_words);
    assert((resolved[0] >> H_HASH_SHIFT & H_HASH_MASK) == 123);
    assert((from_words[0] >> H_HASH_SHIFT & H_HASH_MASK) == 42);

    oop new_holder = reserve_pinned(extent(6));
    assert(new_holder);
    initialize(new_holder, nil, F_VAR, 6);
    ((oop *)(uintptr_t)new_holder)[2] = from;
    c4_heap_publish(new_holder, 6, C4_NO_WEAK);
    assert(((oop *)(uintptr_t)new_holder)[2] == to);
    c4_heap_store_ref(new_holder, 1, from);
    assert(((oop *)(uintptr_t)new_holder)[3] == to);

    assert(c4_heap_begin());
    c4_heap_root(holder);
    c4_heap_root(other_wide);
    c4_heap_end_roots();
    finish_cycle();
    /* Only these two ranges are white. Consume them to verify the alias
     * and target were retained, now that smaller fits can split them. */
    assert(alloc(bc, F_BYTES, 4) == forbidden);
    assert(alloc(nil, F_VAR, 6) == new_holder);
    assert(!reserve_pinned(extent(2)));
    assert(!reserve_pinned(extent(3)));
    assert(((oop *)(uintptr_t)holder)[2] == from);
    assert(c4_heap_load_ref(holder, 0) == to);
    assert(((oop *)(uintptr_t)holder)[2] == to);

    assert(c4_heap_begin());
    c4_heap_root(holder);
    c4_heap_root(other_wide);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(bc, F_BYTES, 2) == from);
    assert(c4_heap_canonical(from) == from);
    assert(alloc(bc, F_BYTES, 4) == forbidden);
    assert(c4_heap_become_forward(forbidden, to)); /* Forbid reset on reuse. */
    assert(c4_heap_become_forward(from, to));
}

static void forward_claimed(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(1) + extent(2) + extent(3), &bc, &wc);
    oop holder = alloc(nil, F_VAR, 1);
    oop from = alloc(bc, F_BYTES, 2);
    oop to = alloc(wc, F_W32, 3);
    c4_heap_store_ref(holder, 0, from);

    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(holder);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    /* The source has already been traced as an ordinary ByteString. */
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_load_ref(holder, 0) == to);
    c4_heap_finish_poll();
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(atomic_load(&proposals) >= 2);
    assert(!reserve_pinned(extent(2))); /* SATB keeps the displaced raw alias. */
    assert(!reserve_pinned(extent(3)));

    assert(c4_heap_begin());
    c4_heap_root(holder);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(bc, F_BYTES, 2) == from);
    assert(!reserve_pinned(extent(3)));
}

static void forward_weak(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(2) + extent(3) + extent(4) +
        extent(5) + extent(6), &bc, &wc);
    oop owner = weak_owner(nil, 2);
    oop from_live = alloc(bc, F_BYTES, 3);
    oop to_live = alloc(wc, F_W32, 4);
    oop from_dead = alloc(bc, F_BYTES, 5);
    oop to_dead = alloc(wc, F_W32, 6);
    c4_heap_store_ref(owner, 0, from_live);
    c4_heap_store_ref(owner, 1, from_dead);

    /* Both sources are white and only weakly referenced at publication. */
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(to_live);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    assert(c4_heap_become_forward(from_live, to_live));
    assert(c4_heap_become_forward(from_dead, to_dead));

    race_owner = owner;
    race_slot = 0;
    race_prev = from_live;
    atomic_store(&stall_cas, true);
    atomic_store(&stall_close, false);
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    /* Read races CLEAR and returns the live target even after source sweep. */
    finish_during_load = true;
    assert(c4_heap_load_ref(owner, 0) == to_live);
    finish_during_load = false;
    assert(!c4_heap_busy());
    assert(c4_heap_take_weak_clears() == 1);
    assert(alloc(nil, F_VAR, 3) == from_live);
    assert(alloc(nil, F_VAR, 5) == from_dead);
    assert(alloc(nil, F_VAR, 6) == to_dead);
    assert(c4_heap_load_ref(owner, 0) == to_live);
    assert(c4_heap_load_ref(owner, 1) == nil);
    assert(((oop *)(uintptr_t)owner)[2] == from_live); /* Ignore raw weak bytes. */
}

static void forward_weak_read(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(1) + extent(2) + extent(3), &bc, &wc);
    oop owner = weak_owner(nil, 1);
    oop from = alloc(bc, F_BYTES, 2);
    oop to = alloc(wc, F_W32, 3);
    c4_heap_store_ref(owner, 0, from);
    assert(c4_heap_become_forward(from, to));

    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    assert(c4_heap_load_ref(owner, 0) == to);
    c4_heap_finish_poll();
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(atomic_load(&proposals) >= 2);
    assert(c4_heap_take_weak_clears() == 0);
    assert(alloc(nil, F_VAR, 2) == from); /* Weak read marked only canonical target. */
    assert(!reserve_pinned(extent(3)));
    assert(c4_heap_load_ref(owner, 0) == to);
}

static void forward_after_ack(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(2) + extent(3) + extent(4) + extent(5), &bc, &wc);
    oop owner = weak_owner(nil, 2);
    oop from = alloc(bc, F_BYTES, 3);
    oop to = alloc(wc, F_W32, 4);
    oop white = alloc(bc, F_BYTES, 5);
    c4_heap_store_ref(owner, 0, from);
    c4_heap_store_ref(owner, 1, white);
    race_owner = owner;
    race_slot = 1;
    race_prev = white;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(from);
    c4_heap_root(to);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    /* Worker has passed slot 0. The old alias must survive this sweep. */
    assert(!c4_heap_become_forward(white, to));
    assert(c4_heap_become_forward(from, to));
    atomic_store(&stall_cas, false);
    finish_cycle();
    assert(alloc(nil, F_VAR, 5) == white);
    assert(!reserve_pinned(extent(3)));

    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(to);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(nil, F_VAR, 3) == from);
    assert(c4_heap_load_ref(owner, 0) == to);
}

static void forward_pinned_overlap(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(1) + extent(5) + extent(2) + extent(3), &bc, &wc);
    oop owner = weak_owner(nil, 1);
    oop prefix = alloc(nil, F_VAR, 5);
    oop from = alloc(bc, F_BYTES, 2);
    oop to = alloc(wc, F_W32, 3);
    c4_heap_store_ref(prefix, 1, to); /* Old shadow at the future split boundary. */
    c4_heap_store_ref(owner, 0, from);
    assert(c4_heap_become_forward(from, to));

    race_owner = owner;
    race_slot = 0;
    race_prev = from;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(to);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    assert(!reserve_pinned(extent(0)));
    /* A weak reader can hold the pre-CAS alias in its local through
     * sweep. Its forwarding marker survives inside a merged free run. */
    finish_during_load = true;
    assert(c4_heap_load_ref(owner, 0) == to);
    finish_during_load = false;
    assert(!c4_heap_busy());
    assert(c4_heap_take_weak_clears() == 0);

    assert(alloc(nil, F_VAR, 1) == prefix);
    oop remainder = prefix + extent(1);
    /* Creating a boundary must not turn the old shadow ref into a
     * forwarding marker, even before the remainder is reserved. */
    assert(c4_heap_canonical(remainder) == remainder);
    assert(alloc(bc, F_BYTES, 6) == remainder);
    assert(c4_heap_canonical(remainder) == remainder);
    assert(c4_heap_become_forward(remainder, to));
    assert(c4_heap_load_ref(owner, 0) == to);
    assert(!reserve_pinned(extent(0)));
}

static void enum_begin(oop cls, oop root)
{
    assert(c4_heap_enum_request(cls, 32, 0, 0));
    assert(!c4_heap_enum_request(cls, 32, 0, 0));
    assert(c4_heap_should_collect());
    assert(c4_heap_begin());
    c4_heap_root(root);
}

static int32_t enum_count(void)
{
    int32_t n;
    while ((n = c4_heap_enum_count()) == -2) sched_yield();
    return n;
}

static void enumeration(void)
{
    const size_t size = (128 + 64) * 1024;
    void *base = mmap(NULL, size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(base != MAP_FAILED && c4_heap_init_moving(base, size));
    oop nil = import_nil(base);
    oop bc = nil + extent(0), wc = bc + extent(0), pc = wc + extent(0);
    oop cc = pc + extent(0);
    oop mc = cc + extent(0), ac = mc + extent(0);
    for (oop cls = bc; cls <= ac; cls += extent(0)) {
        initialize(cls, nil, F_EMPTY, 0);
        assert(c4_heap_import(cls, extent(0), 0, C4_NO_WEAK));
    }
    c4_heap_set_plain_classes(pc, mc, ac);
    c4_heap_set_forward_classes(bc, wc);
    c4_heap_set_context_class(cc);
    assert(c4_heap_start());
    oop root = alloc(nil, F_VAR, 5);
    oop ctx = alloc(cc, F_FIXVAR, CTX_FIXED + 2);
    oop weak = weak_owner(nil, 2);
    oop keeper = point(pc, true);
    oop other = point(pc, true);
    oop weak_only = point(pc, true);
    oop alias = alloc(bc, F_BYTES, 1), alias2 = alloc(bc, F_BYTES, 1);
    oop wide = alloc(wc, F_W32, 1);
    oop msg = point(mc, true), assoc = point(ac, true);
    c4_heap_store_ref(msg, 0, assoc);
    c4_heap_store_ref(root, 4, msg);
    assert(c4_heap_become_forward(alias, wide));
    c4_heap_store_ref(root, 0, weak);
    c4_heap_store_ref(root, 1, ctx);
    c4_heap_store_ref(root, 2, wide);
    /* Keep a raw forwarding source in the root stream, too. */
    c4_heap_store_ref(root, 3, alias2);
    c4_heap_store_ref(weak, 0, weak_only);
    c4_heap_store_ref(ctx, CTX_STACKP, 3); /* one live slot */
    c4_heap_store_ref(ctx, CTX_FIXED, keeper);
    c4_heap_store_ref(ctx, CTX_FIXED + 1, other); /* inactive Context tail */

    enum_begin(pc, root);
    c4_heap_root(alias);
    c4_heap_store_ref(ctx, CTX_STACKP, 5);
    c4_heap_store_ref(ctx, CTX_FIXED, other);
    c4_heap_store_ref(root, 1, nil);
    atomic_store(&stall_enum, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum)) sched_yield();
    oop fresh = point(pc, true);
    c4_heap_store_ref(root, 1, fresh);
    c4_heap_store_ref(ctx, CTX_FIXED, fresh);
    for (unsigned i = 0; i < 100; ++i) {
        c4_heap_finish_poll();
        c4_heap_move_poll();
        assert(c4_heap_busy() && c4_heap_enum_count() == -2);
        assert(!c4_heap_begin());
    }
    atomic_store(&stall_enum, false);
    assert(enum_count() == 1 && c4_heap_enum_at(0) == keeper);
    c4_heap_enum_finish();
    enum_begin(pc, root);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == fresh);
    c4_heap_enum_finish();

    /* Mid-view forwarding must not introduce an edge into this cut. The
     * already-forwarded alias and direct reference must deduplicate. */
    enum_begin(wc, root);
    c4_heap_root(alias);
    oop wide2 = alloc(wc, F_W32, 1);
    assert(c4_heap_become_forward(alias2, wide2));
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == wide);
    c4_heap_enum_finish();

    enum_begin(bc, root);
    c4_heap_end_roots();
    assert(enum_count() == 0);
    c4_heap_enum_finish();
    oop alias3 = alloc(bc, F_BYTES, 1);
    enum_begin(bc, root);
    c4_heap_root(alias3);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == alias3);
    assert(c4_heap_become_forward(alias3, wide2));
    assert(c4_heap_enum_count() == -1);
    c4_heap_enum_finish();

    enum_begin(mc, root);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == msg);
    c4_heap_enum_finish();
    enum_begin(ac, root);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == assoc);
    c4_heap_enum_finish();

    /* Transfer to a strong slot before releasing the view. GC can run
     * immediately; it must preserve only the published result. */
    enum_begin(pc, root);
    c4_heap_store_ref(root, 1, nil);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == fresh);
    c4_heap_store_ref(root, 1, c4_heap_enum_at(0));
    c4_heap_enum_finish();
    assert(c4_heap_begin());
    c4_heap_root(root);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_load_ref(root, 1) == fresh);
    assert(c4_heap_load_ref(weak, 0) == nil);
    assert(c4_heap_address(fresh) != fresh);
}

static void enumeration_limit(void)
{
    arena(256 * 1024);
    assert(c4_heap_start());
    oop cls = alloc(1, F_EMPTY, 0);
    oop root = alloc(1, F_VAR, C4_ENUM_LIMIT + 1);
    for (uint32_t i = 0; i <= C4_ENUM_LIMIT; ++i)
        c4_heap_store_ref(root, i, alloc(cls, F_EMPTY, 0));
    enum_begin(cls, root);
    c4_heap_end_roots();
    assert(enum_count() == -1);
    c4_heap_enum_finish();
    c4_heap_store_ref(root, C4_ENUM_LIMIT, 1);
    enum_begin(cls, root);
    c4_heap_end_roots();
    assert(enum_count() == C4_ENUM_LIMIT);
    c4_heap_enum_finish();

    oop excluded = c4_heap_load_ref(root, 0);
    assert(c4_heap_enum_request(cls, 32, excluded, c4_heap_load_ref(root, 1)));
    assert(c4_heap_begin());
    c4_heap_root(root);
    c4_heap_end_roots();
    assert(enum_count() == C4_ENUM_LIMIT - 2);
    c4_heap_enum_finish();
}

static oop alloc_nil(oop cls, unsigned fmt, uint32_t slots, uint32_t weak_start, oop nil)
{
    oop obj = reserve_pinned(extent(slots));
    assert(obj);
    oop *p = (oop *)(uintptr_t)obj;
    p[0] = ((oop)fmt << H_FMT_SHIFT) | slots;
    p[1] = cls;
    for (uint32_t i = 0; i < slots; ++i) p[2 + i] = nil;
    c4_heap_publish_nil(obj, slots, weak_start);
    return obj;
}

static void lazy_mark(void)
{
    enum { SLOTS = 1025, FIRST_WORD = 512 };
    oop nil = (oop)(uintptr_t)arena(extent(0) + extent(SLOTS) + 5 * extent(1));
    initialize(nil, nil, F_EMPTY, 0);
    c4_heap_set_nil(nil);
    assert(c4_heap_import(nil, extent(0), 0, C4_NO_WEAK));
    assert(c4_heap_start());
    oop old = alloc_nil(nil, F_VAR, SLOTS, C4_NO_WEAK, nil);
    uint32_t first = FIRST_WORD - (old - nil) / 8 - 2;
    oop stale = alloc(nil, F_VAR, 1);
    c4_heap_store_ref(old, first + 1, stale);
    c4_heap_store_ref(old, first - 256, stale); /* this old tag stays mismatched */
    assert(c4_heap_begin());
    c4_heap_root(stale);
    c4_heap_end_roots();
    finish_cycle();

    oop owner = alloc_nil(nil, F_VAR, SLOTS, C4_NO_WEAK, nil);
    assert(owner == old);
    oop branch = alloc(nil, F_VAR, 1);
    oop child = alloc(nil, F_VAR, 1);
    oop tail = alloc(nil, F_VAR, 1);
    oop at_ack = alloc(nil, F_VAR, 1);
    c4_heap_store_ref(branch, 0, child);
    c4_heap_store_ref(owner, SLOTS - 1, tail); /* materialized final partial chunk */

    mark_owner_word = (owner - nil) / 8;
    mark_chunk_word = FIRST_WORD;
    unsigned before = atomic_load(&proposals);
    atomic_store(&stall_mark_chunk, true);
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_end_roots();
    while (!atomic_load(&at_mark_chunk)) sched_yield();
    c4_heap_store_ref(owner, first, branch); /* first store after the skip decision */
    assert(c4_heap_load_ref(owner, first + 1) == nil);
    atomic_store(&stall_mark_chunk, false);
    while (!atomic_load(&at_close)) sched_yield();
    c4_heap_store_ref(owner, first + 256, at_ack); /* first store while CLOSE is proposed */
    c4_heap_finish_poll(); /* must retry, not ACK */
    atomic_store(&stall_close, false);
    finish_cycle();

    assert(atomic_load(&proposals) >= before + 2);
    assert(c4_heap_load_ref(branch, 0) == child);
    assert(c4_heap_load_ref(child, 0) == 1);
    assert(c4_heap_load_ref(tail, 0) == 1);
    assert(c4_heap_load_ref(at_ack, 0) == 1);
    assert(alloc(nil, F_VAR, 1) == stale);
}

static void lazy_publish(void)
{
    enum { SLOTS = 65536 };
    size_t room = extent(0) + 2 * extent(SLOTS) + 2 * extent(1);
    oop nil = (oop)(uintptr_t)arena(room);
    initialize(nil, nil, F_EMPTY, 0);
    c4_heap_set_nil(nil);
    assert(c4_heap_import(nil, extent(0), 0, C4_NO_WEAK));
    assert(c4_heap_start());
    oop strong = alloc_nil(nil, F_VAR, SLOTS, C4_NO_WEAK, nil);
    oop weak = alloc_nil(nil, F_WEAK, SLOTS, 0, nil);
    oop kept = alloc(nil, F_VAR, 1);
    oop dead = alloc(nil, F_VAR, 1);
    c4_heap_store_ref(strong, SLOTS - 1, kept);
    c4_heap_store_ref(weak, SLOTS - 1, kept);
    c4_heap_store_ref(weak, SLOTS - 2, dead);
    c4_heap_store_ref(weak, SLOTS - 3, dead);
    assert(c4_heap_load_ref(strong, SLOTS - 2) == nil);
    assert(c4_heap_load_ref(weak, SLOTS - 4) == nil);

    /* Pause the worker during the clear. Materialize a previously untouched
     * chunk in the mutator, after ACK: a dead edge still must not enter it. */
    race_owner = weak;
    race_slot = SLOTS - 2;
    race_prev = dead;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(strong);
    c4_heap_root(weak);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    c4_heap_store_ref(weak, SLOTS - 2, 45); /* make the pending CLEAR CAS lose */
    c4_heap_store_ref(weak, SLOTS / 2, dead);
    c4_heap_store_ref(weak, SLOTS / 2 + 1, 41);
    assert(c4_heap_load_ref(weak, SLOTS / 2) == nil);
    atomic_store(&stall_cas, false);
    finish_cycle();
    assert(c4_heap_take_weak_clears() == 1);
    assert(c4_heap_load_ref(weak, SLOTS - 3) == nil);
    assert(c4_heap_load_ref(weak, SLOTS - 2) == 45);
    assert(c4_heap_load_ref(weak, SLOTS - 1) == kept);
    assert(c4_heap_load_ref(weak, SLOTS / 2 + 1) == 41);

    /* Reuse the same large extent. Physical shadow still has kept in the
     * old incarnation's tag; it must not look like a fresh edge. */
    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_root(kept);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(nil, F_VAR, 3) == strong);
    oop tail = alloc_nil(nil, F_VAR, SLOTS - 5, C4_NO_WEAK, nil);
    assert(tail == strong + extent(3));
    assert(c4_heap_load_ref(tail, SLOTS - 6) == nil);
    c4_heap_store_ref(tail, SLOTS - 6, kept);

    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_root(kept);
    c4_heap_end_roots();
    finish_cycle();
    oop reused = alloc_nil(nil, F_WEAK, SLOTS, 0, nil);
    assert(reused == strong);
    assert(c4_heap_load_ref(reused, SLOTS - 1) == nil);
    c4_heap_store_ref(reused, SLOTS - 2, 43);
    assert(c4_heap_load_ref(reused, SLOTS - 1) == nil);
    assert(c4_heap_load_ref(reused, SLOTS - 2) == 43);
}


static void lazy_enumeration(void)
{
    enum { SLOTS = 8192, RACE_SLOT = SLOTS / 2 };
    oop nil = (oop)(uintptr_t)arena(5 * extent(SLOTS) + 4096);
    initialize(nil, nil, F_EMPTY, 0);
    c4_heap_set_nil(nil);
    assert(c4_heap_import(nil, extent(0), 0, C4_NO_WEAK));
    oop cls = nil + extent(0);
    initialize(cls, nil, F_EMPTY, 0);
    assert(c4_heap_import(cls, extent(0), 0, C4_NO_WEAK));
    oop imported_item = cls + extent(0);
    initialize(imported_item, cls, F_EMPTY, 0);
    assert(c4_heap_import(imported_item, extent(0), 0, C4_NO_WEAK));
    oop imported = imported_item + extent(0);
    initialize(imported, nil, F_VAR, SLOTS);
    ((oop *)(uintptr_t)imported)[SLOTS + 1] = imported_item;
    assert(c4_heap_import(imported, extent(SLOTS), SLOTS, C4_NO_WEAK));
    assert(c4_heap_start());
    oop owner = alloc_nil(nil, F_VAR, SLOTS, C4_NO_WEAK, nil);
    oop weak = alloc_nil(nil, F_WEAK, SLOTS, 1, nil);
    oop kept = alloc(cls, F_EMPTY, 0);
    oop fixed = alloc(cls, F_EMPTY, 0);
    oop weak_only = alloc(cls, F_EMPTY, 0);
    c4_heap_store_ref(owner, SLOTS - 1, kept);
    c4_heap_store_ref(weak, 0, fixed);
    c4_heap_store_ref(weak, SLOTS - 1, weak_only);

    enum_begin(cls, owner);
    c4_heap_root(imported);
    c4_heap_root(weak);
    c4_heap_store_ref(imported, SLOTS - 1, nil);
    c4_heap_store_ref(owner, SLOTS - 1, nil);
    c4_heap_store_ref(weak, 0, nil);
    enum_owner_word = (owner - nil) / 8;
    enum_slot = RACE_SLOT;
    atomic_store(&stall_enum_field, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum_field)) sched_yield();
    oop fresh = alloc_nil(cls, F_VAR, SLOTS, C4_NO_WEAK, nil);
    c4_heap_store_ref(owner, RACE_SLOT, fresh);
    c4_heap_store_ref(owner, RACE_SLOT + 1, fresh);
    c4_heap_store_ref(weak, SLOTS - 2, fresh);
    assert(c4_heap_load_ref(owner, RACE_SLOT + 2) == nil);
    atomic_store(&stall_enum_field, false);

    assert(enum_count() == 3);
    unsigned found = 0;
    for (uint32_t i = 0; i < 3; ++i) {
        oop result = c4_heap_enum_at(i);
        found |= result == imported_item ? 1 : result == kept ? 2 : result == fixed ? 4 : 0;
    }
    assert(found == 7);
    c4_heap_enum_finish();

    enum_begin(cls, owner);
    c4_heap_root(imported);
    c4_heap_root(weak);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == fresh);
    c4_heap_enum_finish();

    /* The marker has already finished scanning the rooted old owner. An
     * insertion into an untouched chunk and stores on a fresh black owner
     * must reopen marking and retain both white targets. */
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(weak);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    c4_heap_store_ref(owner, SLOTS / 4, kept);
    oop black = alloc_nil(cls, F_VAR, SLOTS, C4_NO_WEAK, nil);
    c4_heap_store_ref(owner, SLOTS / 4 + 1, black);
    c4_heap_store_ref(black, SLOTS - 1, weak_only);
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(atomic_load(&proposals) >= 2);

    enum_begin(cls, owner);
    c4_heap_end_roots();
    assert(enum_count() == 4); /* fresh, kept, black and weak_only */
    c4_heap_enum_finish();
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    if (!strcmp(argv[1], "close")) hostile_close();
    else if (!strcmp(argv[1], "shadow")) shadow_snapshot();
    else if (!strcmp(argv[1], "oracle")) oracle();
    else if (!strcmp(argv[1], "weak-close")) weak_close();
    else if (!strcmp(argv[1], "weak-shadow")) weak_shadow();
    else if (!strcmp(argv[1], "lazy-publish")) lazy_publish();
    else if (!strcmp(argv[1], "lazy-mark")) lazy_mark();
    else if (!strcmp(argv[1], "lazy-enumeration")) lazy_enumeration();
    else if (!strcmp(argv[1], "weak-idle")) weak_idle_transition();
    else if (!strcmp(argv[1], "forward-strong")) forward_strong();
    else if (!strcmp(argv[1], "forward-claimed")) forward_claimed();
    else if (!strcmp(argv[1], "forward-weak")) forward_weak();
    else if (!strcmp(argv[1], "forward-weak-read")) forward_weak_read();
    else if (!strcmp(argv[1], "forward-after-ack")) forward_after_ack();
    else if (!strcmp(argv[1], "forward-pinned-overlap")) forward_pinned_overlap();
    else if (!strcmp(argv[1], "pinned-fit")) pinned_fit();
    else if (!strcmp(argv[1], "pinned-clear-split")) pinned_clear_split();
    else if (!strcmp(argv[1], "moving")) moving(false);
    else if (!strcmp(argv[1], "raw-read-move")) moving(true);
    else if (!strncmp(argv[1], "raw-read-", 9)) raw_read(argv[1] + 9);
    else if (!strcmp(argv[1], "moving-general")) moving_general();
    else if (!strcmp(argv[1], "moving-saturated")) moving_saturated();
    else if (!strcmp(argv[1], "enumeration")) enumeration();
    else if (!strcmp(argv[1], "enumeration-limit")) enumeration_limit();
    else return 2;
    return 0;
}
