#include "c4_heap.h"
#include "samaltak.h"

#include <assert.h>
#include <sched.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>

static _Atomic bool stall_close, at_close;
static _Atomic unsigned proposals;
static _Atomic bool stall_cas, at_cas;
static oop race_owner, race_prev;
static uint32_t race_slot;
static bool finish_during_load;

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
    assert(alloc(cls, F_VAR, 2) != branch);
    assert(alloc(cls, F_VAR, 3) != child);
    assert(alloc(cls, F_VAR, 4) == dead);
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
    assert(alloc(cls, F_VAR, 1) != live_stack);
    assert(alloc(cls, F_VAR, 2) == stale_tail);
    assert(alloc(cls, F_VAR, 3) != old_edge);

    assert(c4_heap_begin());
    c4_heap_root(ctx);
    c4_heap_root(root);
    c4_heap_end_roots();
    finish_cycle();
    oop a = alloc(cls, F_VAR, 1);
    oop b = alloc(cls, F_VAR, 1);
    assert(a == live_stack || b == live_stack);
    a = alloc(cls, F_VAR, 3);
    b = alloc(cls, F_VAR, 3);
    assert(a == old_edge || b == old_edge);
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
    assert(reserve_pinned(extent(1)) == 0);
    assert(reserve_pinned(extent(2)) == 0);
    assert(reserve_pinned(extent(6)) == 0);
    assert(alloc(nil, F_VAR, 3) == dying);
    assert(alloc(nil, F_VAR, 4) == raced);
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
    oop nodes[NODES];
    unsigned edges[NODES][LINKS];
    size_t size = extent(0);
    for (unsigned i = 0; i < NODES; ++i) size += extent(slots_for(i));
    arena(size);
    assert(c4_heap_start());
    oop cls = alloc(1, F_EMPTY, 0);
    for (unsigned i = 0; i < NODES; ++i) nodes[i] = alloc(cls, F_VAR, slots_for(i));

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
        for (unsigned shape = 0; shape < SHAPES; ++shape) {
            uint32_t slots = slots_for(shape);
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
    c4_heap_set_point_class(cls);
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

static void moving(void)
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

int main(int argc, char **argv)
{
    assert(argc == 2);
    if (!strcmp(argv[1], "close")) hostile_close();
    else if (!strcmp(argv[1], "shadow")) shadow_snapshot();
    else if (!strcmp(argv[1], "oracle")) oracle();
    else if (!strcmp(argv[1], "weak-close")) weak_close();
    else if (!strcmp(argv[1], "weak-shadow")) weak_shadow();
    else if (!strcmp(argv[1], "weak-idle")) weak_idle_transition();
    else if (!strcmp(argv[1], "moving")) moving();
    else if (!strcmp(argv[1], "moving-saturated")) moving_saturated();
    else return 2;
    return 0;
}
