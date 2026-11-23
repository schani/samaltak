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

static void cache_close(void)
{
    arena(32 * 1024);
    assert(c4_heap_start());
    oop cls = alloc(1, F_EMPTY, 0);
    c4_heap_set_method_class(cls);
    oop method = alloc(cls, F_FIXED, CM_PRIMITIVE + 1);
    oop code = alloc(1, F_BYTES, 4);
    oop dead = alloc(cls, F_FIXED, 11);
    oop guard = alloc(1, F_EMPTY, 0);
    c4_heap_store_ref(method, CM_BYTECODES, code);
    uint64_t generation = c4_heap_cache_gen();
    c4_heap_store_ref(method, CM_FRAMESIZE, 7);
    assert(c4_heap_cache_gen() != generation);
    generation = c4_heap_cache_gen();

    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(cls);
    c4_heap_root(guard);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();

    /* Both methods are now white: they only have untraced cache aliases.
     * Hit one after the close proposal, before the frame is installed. */
    assert(c4_heap_cache_gen() == generation);
    c4_heap_use_cached_method(method);
    c4_heap_finish_poll();
    assert(c4_heap_cache_gen() == generation); /* retry, not ACK */
    atomic_store(&stall_close, false);
    finish_cycle();

    /* The cached borrow keeps its body. An untouched cache alias does not
     * survive ACK (independently of whether its address has been reused). */
    assert(atomic_load(&proposals) >= 2);
    assert(c4_heap_cache_gen() != generation);
    assert(c4_heap_load_ref(method, CM_BYTECODES) == code);
    assert(alloc(cls, F_FIXED, 11) == dead);

    generation = c4_heap_cache_gen();
    atomic_store(&at_close, false);
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(cls);
    c4_heap_root(guard);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    c4_heap_finish_poll();
    assert(c4_heap_cache_gen() != generation); /* worker still parked */
    assert(c4_heap_busy());
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(alloc(cls, F_FIXED, CM_PRIMITIVE + 1) == method);
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

#ifdef SAMALTAK_C4_BIN_TEST
extern void c4_heap_test_bin_work(uint32_t *groups, uint32_t *nodes);
static _Atomic bool stall_bin, at_bin;
static bool publish_sibling;
static _Atomic uint32_t stall_group_at, reached_group_at;

void c4_heap_test_before_bin_group_publish(uint32_t words)
{
    if (atomic_load(&stall_group_at) != words) return;
    atomic_store(&reached_group_at, words);
    while (atomic_load(&stall_group_at) == words) sched_yield();
}

void c4_heap_test_before_bin_publish(uint32_t words)
{
    if (words != 127 || !atomic_load(&stall_bin)) return;
    atomic_store(&at_bin, true);
    while (atomic_load(&stall_bin)) sched_yield();
}

void c4_heap_test_after_bin_group_clear(unsigned bin)
{
    if (bin != 126 || !publish_sibling) return;
    assert(atomic_load(&at_bin));
    atomic_store(&stall_bin, false);
    while (c4_heap_busy()) sched_yield();
    publish_sibling = false;
}

static void assert_bin_work(uint32_t wanted_nodes)
{
    uint32_t groups, nodes;
    c4_heap_test_bin_work(&groups, &nodes);
    assert(groups <= 2 && nodes == wanted_nodes);
}
#else
static void assert_bin_work(uint32_t wanted_nodes) { (void)wanted_nodes; }
#endif

static void pinned_stranded(bool splits)
{
    /* Both 120 and 127 were in the same coarse bin. Put a long chain of
     * short runs in front of every fitting run, with live separators and
     * no bump space. Repeat independently for swept runs and splits. */
    enum { N = 8192, SMALL = 120, FIT = 127, PARENT = 256, GUARD = 3 };
    size_t full = 8 * (2 + N * (2 * GUARD + (splits ? 2 * PARENT : SMALL + FIT)));
    oop nil = import_nil(arena(full));
    assert(c4_heap_start());
    oop guards = nil;
    oop fit[N];
    for (uint32_t i = 0; i < 2 * N; ++i) {
        uint32_t words = splits ? PARENT : (i < N ? FIT : SMALL);
        oop obj = alloc(nil, F_BYTES, words - 2);
        if (!splits && i < N) fit[i] = obj;
        oop guard = alloc(nil, F_FIXED, 1);
        c4_heap_store_ref(guard, 0, guards);
        guards = guard;
    }
    assert(c4_heap_top() == nil + full);
    assert(c4_heap_begin());
    c4_heap_root(guards);
    c4_heap_end_roots();
    finish_cycle();

    if (splits) {
        for (uint32_t i = 0; i < 2 * N; ++i) {
            uint32_t used = PARENT - (i < N ? FIT : SMALL);
            oop prefix = alloc(nil, F_BYTES, used - 2);
            if (i < N) fit[i] = prefix + 8 * used;
        }
    }
    /* Genuine no-fit: millions of free bytes, none contiguous enough. */
    assert(reserve_pinned(8 * (FIT + 1)) == 0);
    assert_bin_work(0);
    for (uint32_t i = N; i; --i) {
        oop obj = reserve_pinned(8 * FIT);
        if (!obj)
            fprintf(stderr, "pinned-stranded: %s: %u fitting spans (%u usable bytes) inaccessible\n",
                splits ? "split" : "swept", i, i * 8 * FIT);
        assert(obj && obj == fit[i - 1]);
        assert_bin_work(1);
        publish(obj, nil, F_BYTES, FIT - 2);
    }
    /* A full chain in the same bitmap group must not cost a walk. */
    for (uint32_t i = 0; i < N; ++i) {
        assert(reserve_pinned(8 * FIT) == 0);
        assert_bin_work(0);
    }
    for (uint32_t i = 0; i < N; ++i) {
        alloc(nil, F_BYTES, SMALL - 2);
        assert_bin_work(1);
    }
    assert(reserve_pinned(16) == 0 && c4_heap_top() == nil + full);
    for (uint32_t i = 0; i < 2 * N; ++i) {
        assert(guards != nil);
        guards = c4_heap_load_ref(guards, 0);
    }
    assert(guards == nil);
}

static void pinned_rounded(void)
{
    /* An imported extent need not be at a class boundary. Splitting at a
     * rounded size leaves a real remainder, not part of the logical body.
     * The sum of charged extents must be reclaimed at the next sweep. */
    enum { RUN = 4097, REQUEST = 2049, ROUNDED = 2080, TAIL = RUN - ROUNDED };
    size_t full = 8 * (2 + RUN);
    oop nil = import_nil(arena(full));
    oop start = nil + 16;
    initialize(start, nil, F_BYTES, RUN - 2);
    assert(c4_heap_import(start, 8 * RUN, 0, C4_NO_WEAK));
    assert(c4_heap_start());
    for (unsigned i = 0; i < 3; ++i) {
        assert(c4_heap_begin());
        c4_heap_end_roots();
        finish_cycle();
        assert(reserve_pinned(8 * RUN) == 0); /* rounds beyond cap */
        assert(alloc(nil, F_BYTES, REQUEST - 2) == start);
        assert(alloc(nil, F_BYTES, TAIL - 2) == start + 8 * ROUNDED);
        assert(reserve_pinned(16) == 0 && c4_heap_top() == nil + full);
    }
}

#ifdef SAMALTAK_C4_BIN_TEST
static void pinned_bin_publish(void)
{
    /* Earlier batch remains available while a new batch is unpublished.
     * A reserve must neither wait nor disturb the delayed publication. */
    enum { FIRST = 126, SECOND = 127 };
    oop nil = import_nil(arena(8 * (2 + FIRST + SECOND + 3)));
    assert(c4_heap_start());
    oop first = alloc(nil, F_BYTES, FIRST - 2);
    oop guard = alloc(nil, F_FIXED, 1);
    oop second = alloc(nil, F_BYTES, SECOND - 2);
    atomic_store(&stall_bin, true);
    assert(c4_heap_begin());
    c4_heap_root(guard);
    c4_heap_end_roots();
    while (!atomic_load(&at_bin)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    assert(reserve_pinned(8 * SECOND) == 0);
    assert_bin_work(0);
    /* Force the worker to publish the sibling between the two bitmap
     * clears. The worker sees a nonempty group; the mutator must repair. */
    publish_sibling = true;
    assert(alloc(nil, F_BYTES, FIRST - 2) == first);
    assert_bin_work(1);
    assert(!publish_sibling && !c4_heap_busy());
    assert(alloc(nil, F_BYTES, SECOND - 2) == second);
    assert_bin_work(1);
}

static void pinned_bin_group_publish(void)
{
    /* Three initially empty swept groups. Each has a strictly higher
     * private fit in the same group. Pause after publishing the swept
     * mask but before publishing the group bit. */
    enum { N = 3, FIRST = 126, STRIDE = 64, PREFIX = 320 };
    size_t words = 2;
    for (unsigned i = 0; i < N; ++i) {
        unsigned low = FIRST + i * STRIDE;
        words += low + 3 + PREFIX + low + 1 + 3;
    }
    size_t full = 8 * words;
    oop nil = import_nil(arena(full));
    assert(c4_heap_start());
    oop low[N], high[N], prefixes[N], guards = nil;
    for (unsigned i = 0; i < N; ++i) {
        unsigned size = FIRST + i * STRIDE;
        low[i] = alloc(nil, F_BYTES, size - 2);
        oop guard = alloc(nil, F_FIXED, 1);
        c4_heap_store_ref(guard, 0, guards);
        alloc(nil, F_BYTES, PREFIX + size + 1 - 2);
        guards = alloc(nil, F_FIXED, 1);
        c4_heap_store_ref(guards, 0, guard);
    }
    assert(c4_heap_top() == nil + full);
    assert(c4_heap_begin());
    c4_heap_root(guards);
    for (unsigned i = 0; i < N; ++i) c4_heap_root(low[i]);
    c4_heap_end_roots();
    finish_cycle();
    for (unsigned i = 0; i < N; ++i) {
        prefixes[i] = alloc(nil, F_BYTES, PREFIX - 2);
        high[i] = prefixes[i] + 8 * PREFIX;
    }

    atomic_store(&stall_group_at, FIRST);
    assert(c4_heap_begin());
    c4_heap_root(guards);
    for (unsigned i = 0; i < N; ++i) c4_heap_root(prefixes[i]);
    c4_heap_end_roots();
    unsigned early = 0;
    for (unsigned i = 0; i < N; ++i) {
        unsigned size = FIRST + i * STRIDE;
        while (atomic_load(&reached_group_at) != size) {
            c4_heap_finish_poll();
            sched_yield();
        }
        oop obj = alloc(nil, F_BYTES, size - 2);
        assert_bin_work(1);
        if (obj == low[i]) {
            /* Drain the private fit as well so the broken implementation
             * exposes the stale summaries on the next lookup. */
            ++early;
            assert(alloc(nil, F_BYTES, size + 1 - 2) == high[i]);
        } else {
            assert(obj == high[i]);
        }
        atomic_store(&stall_group_at, i + 1 == N ? 0 : size + STRIDE);
    }
    finish_cycle();

    oop obj = reserve_pinned(8 * FIRST);
    uint32_t groups, nodes;
    c4_heap_test_bin_work(&groups, &nodes);
    fprintf(stderr, "pinned-bin-group-publish: early=%u probes=%u nodes=%u\n",
        early, groups, nodes);
    assert(groups == 1 && nodes == 1 && !early && obj == low[0]);
    publish(obj, nil, F_BYTES, FIRST - 2);
    for (unsigned i = 1; i < N; ++i)
        assert(alloc(nil, F_BYTES, FIRST + i * STRIDE - 2) == low[i]);
    assert(reserve_pinned(16) == 0);
    c4_heap_test_bin_work(&groups, &nodes);
    assert(!groups && !nodes && c4_heap_top() == nil + full);
}
#endif

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

static void code_bytes(void)
{
    oop bc, wc;
    oop nil = forward_start(extent(1) + extent(2), &bc, &wc);
    oop bytes = alloc(bc, F_BYTES, 1);
    oop wide = alloc(wc, F_W32, 2);
    assert(!c4_heap_is_code_bytes(bytes));
    c4_heap_note_code_bytes(bytes);
    c4_heap_forbid_become(bytes);
    assert(c4_heap_is_code_bytes(bytes));
    assert(c4_heap_canonical(bytes) == bytes);
    assert(!c4_heap_become_forward(bytes, wide));
    assert(c4_heap_begin());
    c4_heap_root(nil);
    c4_heap_root(wide);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(bc, F_BYTES, 1) == bytes);
    assert(!c4_heap_is_code_bytes(bytes));
    assert(c4_heap_become_forward(bytes, wide));
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
    uint64_t generation = c4_heap_cache_gen();
    assert(!c4_heap_become_forward(white, to));
    assert(c4_heap_cache_gen() == generation);
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_cache_gen() != generation);
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

static oop pointer_start(size_t extra, oop *pc, oop *mc, oop *ac, bool moving, bool forwarding)
{
    oop nil;
    if (moving) {
        size_t size = 64 * 1024 + 4 * extent(0) + extra;
        void *base = mmap(NULL, size, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        assert(base != MAP_FAILED && c4_heap_init_moving(base, size));
        if (forwarding) assert(c4_heap_enable_moving_forward());
        nil = import_nil(base);
    } else {
        nil = import_nil(arena(4 * extent(0) + extra));
    }
    *pc = nil + extent(0);
    *mc = *pc + extent(0);
    *ac = *mc + extent(0);
    for (oop cls = *pc; cls <= *ac; cls += extent(0)) {
        initialize(cls, nil, F_EMPTY, 0);
        assert(c4_heap_import(cls, extent(0), 0, C4_NO_WEAK));
    }
    c4_heap_set_pointer_forward_classes(*pc, *mc, *ac);
    if (moving) c4_heap_set_plain_classes(*pc, *mc, *ac);
    assert(c4_heap_start());
    return nil;
}

static void pointer_shape(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(4096, &pc, &mc, &ac, true, false);
    oop borrowed = alloc(pc, F_FIXED, 2);
    c4_heap_note_pinned_view(borrowed);
    oop fresh = alloc(pc, F_FIXED, 2), wrong = alloc(pc, F_FIXED, 3);
    oop var = alloc(pc, F_VAR, 2), unrelated = alloc(nil, F_FIXED, 2);
    oop weak = weak_owner(pc, 2);
    uint64_t gen = c4_heap_cache_gen();
    assert(!c4_heap_become_forward(fresh, borrowed));
    assert(!c4_heap_become_forward(borrowed, fresh));
    assert(!c4_heap_become_forward(fresh, wrong));
    assert(!c4_heap_become_forward(var, fresh));
    assert(!c4_heap_become_forward(fresh, weak));
    assert(!c4_heap_become_forward(unrelated, fresh));
    assert(!c4_heap_become_forward(fresh, pc));
    assert(!c4_heap_become_forward(pc, fresh));
    assert(!c4_heap_become_forward(nil, fresh));
    assert(!c4_heap_become_forward(7, fresh));
    assert(!c4_heap_become_forward(fresh, fresh));
    assert(!c4_heap_become_forward(fresh, point(pc, true)));
    assert(!c4_heap_become_forward(point(pc, true), fresh));
    assert(!c4_heap_has_forwarding() && c4_heap_cache_gen() == gen);

    for (oop cls = pc; cls <= ac; cls += extent(0)) {
        oop from = alloc(cls, F_FIXED, 2), to = alloc(cls, F_FIXED, 2);
        oop extra = alloc(cls, F_FIXED, 2), third = alloc(cls, F_FIXED, 2);
        c4_heap_store_ref(to, 0, 91);
        c4_heap_store_ref(from, 0, 25);
        ((oop *)(uintptr_t)to)[0] |= UINT64_C(991) << H_HASH_SHIFT;
        uint64_t header = body(to)[0];
        assert(!c4_heap_become_forward(from, alloc(cls == pc ? mc : pc, F_FIXED, 2)));
        gen = c4_heap_cache_gen();
        assert(c4_heap_become_forward(from, to) && c4_heap_cache_gen() != gen);
        assert(c4_heap_canonical(from) == to && c4_heap_address(from) == to);
        assert(c4_heap_load_ref(from, 0) == 91 && body(to)[0] == header);
        c4_heap_store_ref(from, 0, 99);
        assert(c4_heap_load_ref(to, 0) == 99 && ((const oop *)(uintptr_t)from)[2] == 25);
        gen = c4_heap_cache_gen();
        assert(!c4_heap_become_forward(to, third));   /* target as source */
        assert(!c4_heap_become_forward(extra, from)); /* raw alias as target */
        assert(!c4_heap_become_forward(from, third)); /* raw alias as source */
        assert(c4_heap_cache_gen() == gen);
        assert(c4_heap_become_forward(extra, to));    /* fan-in, not a chain */
        assert(c4_heap_canonical(extra) == to);
        c4_heap_note_pinned_view(to);
        assert(!c4_heap_become_forward(third, to));
    }
}

static void pointer_satb(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(extent(4) + 4 * extent(2) + 2 * extent(1), &pc, &mc, &ac, false, false);
    oop weak = weak_owner(nil, 4);
    oop from = alloc(pc, F_FIXED, 2), to = alloc(pc, F_FIXED, 2);
    oop white_from = alloc(pc, F_FIXED, 2), white_to = alloc(pc, F_FIXED, 2);
    oop old_child = alloc(nil, F_VAR, 1), dead = alloc(nil, F_VAR, 1);
    c4_heap_store_ref(from, 0, old_child);
    c4_heap_store_ref(white_from, 0, dead);
    c4_heap_store_ref(weak, 0, from);
    c4_heap_store_ref(weak, 1, old_child);
    c4_heap_store_ref(weak, 2, white_from);
    c4_heap_store_ref(weak, 3, dead);
    assert(c4_heap_begin());
    /* Neither source has been claimed yet. Only the subsequently claimed
     * source may retain the SATB edges, and only for this mark epoch. */
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_become_forward(white_from, white_to));
    c4_heap_root(weak);
    c4_heap_root(from);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_load_ref(weak, 0) == to);
    assert(c4_heap_load_ref(weak, 1) == old_child);
    assert(c4_heap_load_ref(weak, 2) == nil && c4_heap_load_ref(weak, 3) == nil);
    assert(c4_heap_take_weak_clears() == 2);
    assert(alloc(pc, F_FIXED, 2) == white_from);
    assert(alloc(pc, F_FIXED, 2) == white_to);
    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_root(from);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_load_ref(weak, 0) == to);
    assert(c4_heap_load_ref(weak, 1) == nil);
}

static void pointer_claimed(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(extent(1) + 2 * extent(2) + extent(3), &pc, &mc, &ac, false, false);
    oop holder = alloc(nil, F_VAR, 1);
    oop from = alloc(mc, F_FIXED, 2), to = alloc(mc, F_FIXED, 2);
    oop child = alloc(nil, F_VAR, 3);
    c4_heap_store_ref(holder, 0, from);
    c4_heap_store_ref(to, 1, child);
    c4_heap_store_ref(child, 1, 73);

    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(holder);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_load_ref(holder, 0) == to); /* heal but SATB holds donor */
    for (unsigned i = 0; i < 1024; ++i) {
        c4_heap_finish_poll();
        assert(c4_heap_busy());
        assert(!reserve_pinned(extent(2)));
    }
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(atomic_load(&proposals) >= 2);
    assert(c4_heap_load_ref(c4_heap_load_ref(holder, 0), 1) == child);
    assert(c4_heap_load_ref(child, 1) == 73);
    assert(!reserve_pinned(extent(2)));
    assert(c4_heap_begin());
    c4_heap_root(holder);
    c4_heap_end_roots();
    finish_cycle();
    assert(alloc(mc, F_FIXED, 2) == from);
    assert(!c4_heap_become_forward(to, from)); /* even after alias retirement */
}

static void pointer_after_ack(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(extent(2) + 4 * extent(2), &pc, &mc, &ac, false, false);
    oop owner = weak_owner(nil, 2);
    oop to = alloc(ac, F_FIXED, 2), white = alloc(ac, F_FIXED, 2);
    oop from = alloc(ac, F_FIXED, 2), other = alloc(ac, F_FIXED, 2);
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
    c4_heap_root(other);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    /* CLEAR has seen slot 0 but not yet cleared slot 1. */
    uint64_t gen = c4_heap_cache_gen();
    assert(!c4_heap_become_forward(white, to));
    assert(!c4_heap_become_forward(from, white));
    assert(c4_heap_cache_gen() == gen);
    c4_heap_store_ref(owner, 1, other); /* defeats worker's parked CAS */
    assert(c4_heap_become_forward(from, to));
    atomic_store(&stall_cas, false);
    finish_cycle();
    assert(c4_heap_load_ref(owner, 1) == other);
    assert(!c4_heap_take_weak_clears());
    assert(alloc(ac, F_FIXED, 2) == white);

    race_slot = 0;
    race_prev = from;
    atomic_store(&at_cas, false);
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(to);
    c4_heap_root(other);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) {
        c4_heap_finish_poll();
        sched_yield();
    }
    finish_during_load = true;
    assert(c4_heap_load_ref(owner, 0) == to); /* raw marker survives sweep */
    finish_during_load = false;
    assert(!c4_heap_busy());
    assert(alloc(ac, F_FIXED, 2) == white);
    assert(alloc(ac, F_FIXED, 2) == from);
    assert(!c4_heap_become_forward(to, other)); /* source retired, guard stays */

    assert(c4_heap_begin());
    c4_heap_root(owner);
    c4_heap_root(white); /* prevent coalescing past target */
    c4_heap_root(from);  /* keep reincarnated donor out of the free bin */
    c4_heap_root(other);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_load_ref(owner, 0) == nil);
    assert(alloc(ac, F_FIXED, 2) == to);
    assert(c4_heap_become_forward(to, other)); /* new incarnation */
}

static void pointer_enum(bool moving)
{
    oop pc, mc, ac;
    oop nil = pointer_start(4096, &pc, &mc, &ac, moving, moving);
    oop root = alloc(nil, F_VAR, 4);
    oop from = point(mc, moving), to = point(mc, moving);
    oop from2 = point(mc, moving), from3 = point(mc, moving);
    oop before = point(ac, moving), after = point(ac, moving);
    c4_heap_store_ref(from, 0, before);
    c4_heap_store_ref(to, 0, after);
    c4_heap_store_ref(root, 0, from);
    enum_begin(ac, root);
    atomic_store(&stall_enum, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum)) sched_yield();
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_load_ref(root, 0) == to); /* preserve raw edge before healing */
    c4_heap_store_ref(from, 0, nil);         /* only target changes */
    atomic_store(&stall_enum, false);
    assert(enum_count() == 1 && c4_heap_enum_at(0) == before);
    c4_heap_enum_finish();

    c4_heap_store_ref(root, 1, from2);
    c4_heap_store_ref(root, 2, from3);
    enum_begin(mc, root);
    c4_heap_root(from);
    c4_heap_end_roots();
    assert(enum_count() == 3);
    assert(c4_heap_become_forward(from2, to)); /* READY, before handoff */
    assert(c4_heap_enum_count() == -1);
    c4_heap_enum_finish();
    enum_begin(mc, root);
    c4_heap_root(from);
    assert(c4_heap_become_forward(from3, to)); /* ENUM_ROOTS */
    c4_heap_end_roots();
    assert(enum_count() == -1);
    c4_heap_enum_finish();
    enum_begin(mc, root);
    c4_heap_root(from);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == to);
    c4_heap_enum_finish();
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

static void enumeration_log_limit(void)
{
    enum { LENGTH = 70654 }; /* 70656-word extent: an exact upper-bin boundary */
    size_t room = 2 * extent(LENGTH) + 4 * extent(0);
    oop nil = (oop)(uintptr_t)arena(room);
    initialize(nil, nil, F_EMPTY, 0);
    c4_heap_set_nil(nil);
    assert(c4_heap_import(nil, extent(0), 0, C4_NO_WEAK));
    assert(c4_heap_start());
    oop cls = alloc(nil, F_EMPTY, 0);
    oop old = alloc_nil(cls, F_VAR, LENGTH, C4_NO_WEAK, nil);

    enum_begin(cls, old);
    atomic_store(&stall_enum, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum)) sched_yield();
    oop born = alloc_nil(cls, F_VAR, LENGTH, C4_NO_WEAK, nil);
    for (uint32_t i = 0; i < LENGTH; ++i) c4_heap_store_ref(born, i, 3);
    c4_heap_store_ref(old, 0, born);
    atomic_store(&stall_enum, false);
    assert(enum_count() == 1 && c4_heap_enum_at(0) == old);
    c4_heap_enum_finish();

    atomic_store(&at_enum, false);
    enum_begin(cls, old);
    atomic_store(&stall_enum, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum)) sched_yield();
    for (uint32_t i = 0; i < LENGTH; ++i) c4_heap_store_ref(old, i, 5);
    assert(c4_heap_load_ref(old, LENGTH - 1) == 5);
    atomic_store(&stall_enum, false);
    assert(enum_count() == -1);
    c4_heap_enum_finish();

    enum_begin(cls, old);
    c4_heap_end_roots();
    assert(enum_count() == 1 && c4_heap_enum_at(0) == old);
    c4_heap_enum_finish();
}

static void moving_oracle(void)
{
    enum { COUNT = 130, GROUP = 13, LAST_SLOT = 129 };
    oop cls = init_moving(16384);
    oop nodes[COUNT], old_body[COUNT];
    unsigned edges[COUNT][2];
    bool expected[COUNT] = {false}, enumerated[COUNT] = {false};
    unsigned queue[COUNT], head = 0, tail = 0;
    oop weak = weak_owner(cls, COUNT);
    oop root = alloc_nil(cls, F_VAR, LAST_SLOT + 1, C4_NO_WEAK, cls);
    const unsigned seeds[] = {1, 5 * GROUP + 1, 8 * GROUP + 1};
    for (unsigned i = 0; i < COUNT; ++i) {
        nodes[i] = point(cls, true);
        old_body[i] = c4_heap_address(nodes[i]);
    }
    for (unsigned i = 0; i < COUNT; ++i) {
        const unsigned base = i / GROUP * GROUP;
        edges[i][0] = base + rand32() % GROUP;
        edges[i][1] = base + (i + 1) % GROUP; /* ring through the last slot */
        c4_heap_store_ref(nodes[i], 0, nodes[edges[i][0]]);
        c4_heap_store_ref(nodes[i], 1, nodes[edges[i][1]]);
        c4_heap_store_ref(weak, i, nodes[i]);
    }
    for (unsigned s = 0; s < sizeof seeds / sizeof *seeds; ++s) {
        expected[seeds[s]] = true;
        queue[tail++] = seeds[s];
        c4_heap_store_ref(root, LAST_SLOT - s, nodes[seeds[s]]);
    }
    /* Ground truth uses only graph construction, not engine state/loads. */
    while (head < tail) {
        unsigned i = queue[head++];
        for (unsigned e = 0; e < 2; ++e) {
            unsigned k = edges[i][e];
            if (!expected[k]) {
                expected[k] = true;
                queue[tail++] = k;
            }
        }
    }
    assert(tail == 3 * GROUP && !expected[COUNT - 1]);

    /* This class also owns the pinned fixture objects: exclude only those.
     * Stall ENUM_TRACE and overwrite the same versioned last-slot index
     * in adjacent handle rows, plus a materialized lazy pinned field. */
    assert(c4_heap_enum_request(cls, 32, root, weak));
    assert(c4_heap_begin());
    c4_heap_root(root);
    c4_heap_root(weak);
    atomic_store(&stall_enum, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum)) sched_yield();
    for (unsigned i = 1; i <= 2; ++i)
        c4_heap_store_ref(nodes[i], 1, nodes[COUNT - 1]);
    c4_heap_store_ref(root, LAST_SLOT, nodes[COUNT - 1]);
    atomic_store(&stall_enum, false);
    /* nil is also its own class in init_moving. */
    assert(enum_count() == (int32_t)tail + 1);
    unsigned nils = 0;
    for (unsigned n = 0; n < tail + 1; ++n) {
        oop obj = c4_heap_enum_at(n);
        if (obj == cls) {
            ++nils;
            continue;
        }
        unsigned i = 0;
        while (i < COUNT && nodes[i] != obj) ++i;
        assert(i < COUNT && expected[i] && !enumerated[i]);
        enumerated[i] = true;
    }
    assert(nils == 1);
    for (unsigned i = 0; i < COUNT; ++i) assert(enumerated[i] == expected[i]);
    c4_heap_enum_finish();
    for (unsigned i = 1; i <= 2; ++i)
        c4_heap_store_ref(nodes[i], 1, nodes[edges[i][1]]);
    c4_heap_store_ref(root, LAST_SLOT, nodes[seeds[0]]);

    assert(c4_heap_begin());
    c4_heap_root(root);
    c4_heap_root(weak);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_take_weak_clears() == COUNT - tail);
    for (unsigned i = 0; i < COUNT; ++i) {
        assert(c4_heap_load_ref(weak, i) == (expected[i] ? nodes[i] : cls));
        if (expected[i]) assert(c4_heap_address(nodes[i]) == old_body[i]);
    }
    for (unsigned poll = 1; poll <= 3; ++poll) {
        c4_heap_move_poll();
        for (unsigned i = 0; i < COUNT; ++i) {
            if (!expected[i]) continue;
            assert((c4_heap_address(nodes[i]) != old_body[i]) == (i < poll * 64));
            for (unsigned e = 0; e < 2; ++e) {
                assert(c4_heap_load_ref(nodes[i], e) == nodes[edges[i][e]]);
                assert(body(nodes[i])[2 + e] == nodes[edges[i][e]]);
            }
        }
        if (poll < 3) {
            assert(!c4_heap_begin());
            oop fresh = point(cls, true);
            for (unsigned i = 0; i < COUNT; ++i) assert(fresh != nodes[i]);
        }
    }
    assert(point(cls, true) == nodes[COUNT - 1]);
    assert(c4_heap_load_ref(weak, COUNT - 1) == cls);
}

static oop two_bank_start(size_t pinned, oop *interval_cls, oop *method_cls)
{
    const size_t bank = 4 * 16384;
    size_t cap = pinned + 2 * bank;
    void *base = mmap(NULL, cap, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(base != MAP_FAILED && c4_heap_init_moving(base, cap));
    assert(c4_heap_pinned_capacity() == pinned + bank);
    assert(!c4_heap_prepare_interval(pinned + 1));
    assert(c4_heap_prepare_interval(3 * 16));
    assert(c4_heap_pinned_capacity() == pinned);
    oop cls = (oop)(uintptr_t)base;
    *interval_cls = cls + 16;
    *method_cls = cls + 32;
    for (oop o = cls; o <= *method_cls; o += 16) {
        initialize(o, cls, F_EMPTY, 0);
        assert(c4_heap_import(o, 16, 0, C4_NO_WEAK));
    }
    assert(c4_heap_is_imported(*interval_cls));
    assert(!c4_heap_is_imported(*interval_cls + 8));
    c4_heap_set_plain_classes(cls, 0, 0);
    c4_heap_set_interval_class(*interval_cls);
    c4_heap_set_method_class(*method_cls);
    c4_heap_set_nil(cls);
    assert(c4_heap_start());
    assert(c4_heap_plain_class(cls) && !c4_heap_plain_class(*interval_cls));
    assert(c4_heap_interval_class(*interval_cls) && !c4_heap_interval_class(cls));
    return cls;
}

static oop interval(oop cls, bool expect_handle)
{
    oop address;
    oop obj = c4_heap_reserve(40, C4_INTERVAL, &address);
    assert(obj && c4_heap_movable(obj) == expect_handle);
    initialize(address, cls, F_FIXED, 3);
    c4_heap_publish(obj, 3, C4_NO_WEAK);
    assert(c4_heap_address(obj) == address);
    return obj;
}

static void interval_oracle(void)
{
    enum { N = 130, GROUP = 13, TOTAL = N * 2 };
    oop interval_cls, method_cls;
    oop cls = two_bank_start(16384, &interval_cls, &method_cls);
    oop nodes[TOTAL], old[TOTAL], headers[TOTAL];
    unsigned edges[TOTAL][2];
    bool expected[TOTAL] = {false};
    unsigned queue[TOTAL], head = 0, tail = 0;
    oop weak = weak_owner(cls, TOTAL);
    oop root = alloc_nil(cls, F_VAR, 130, C4_NO_WEAK, cls);
    for (unsigned i = 0; i < TOTAL; ++i) {
        nodes[i] = (i & 1) ? interval(interval_cls, true) : point(cls, true);
        old[i] = c4_heap_address(nodes[i]);
        headers[i] = body(nodes[i])[0] | H_IMMUTABLE | ((oop)(i + 1) << H_HASH_SHIFT);
        ((oop *)(uintptr_t)old[i])[0] = headers[i];
        for (unsigned j = 0; j < i; ++j) assert(nodes[j] != nodes[i] && old[j] != old[i]);
    }
    assert(old[2] - old[0] == 32 && old[3] - old[1] == 48);
    for (unsigned i = 0; i < TOTAL; ++i) {
        unsigned offset = i / 2 % GROUP, base = i / 2 / GROUP * (2 * GROUP);
        edges[i][0] = base + 2 * (rand32() % GROUP) + (i & 1);
        /* The ring cannot traverse an Interval without using its third slot. */
        edges[i][1] = base + (i & 1 ? 2 * ((offset + 1) % GROUP) : 2 * offset + 1);
        c4_heap_store_ref(nodes[i], 0, nodes[edges[i][0]]);
        c4_heap_store_ref(nodes[i], 1 + (i & 1), nodes[edges[i][1]]);
        c4_heap_store_ref(weak, i, nodes[i]);
    }
    const unsigned seeds[] = {0, 2 * GROUP, 4 * GROUP, 6 * GROUP, 8 * GROUP, 14 * GROUP};
    for (unsigned i = 0; i < sizeof seeds / sizeof *seeds; ++i) {
        expected[seeds[i]] = true;
        queue[tail++] = seeds[i];
        c4_heap_store_ref(root, 129 - i, nodes[seeds[i]]);
    }
    /* Oracle never reads heap slots or collector metadata. */
    while (head < tail) {
        unsigned i = queue[head++];
        for (unsigned e = 0; e < 2; ++e) {
            unsigned j = edges[i][e];
            if (!expected[j]) {
                expected[j] = true;
                queue[tail++] = j;
            }
        }
    }
    assert(tail == 12 * GROUP && !expected[TOTAL - 1]);

    for (unsigned bank = 0; bank < 2; ++bank) {
        bool seen[TOTAL] = {false};
        oop filter = bank ? interval_cls : cls;
        atomic_store(&stall_enum, true);
        atomic_store(&at_enum, false);
        assert(c4_heap_enum_request(filter, 32, root, weak) && c4_heap_begin());
        c4_heap_root(root);
        c4_heap_root(weak);
        c4_heap_root(nodes[1]); /* duplicate path, not a duplicate result */
        c4_heap_end_roots();
        while (!atomic_load(&at_enum)) sched_yield();
        for (unsigned i = 0; i < 6; ++i)
            c4_heap_store_ref(nodes[i], 1 + (i & 1), nodes[TOTAL - 1]);
        c4_heap_store_ref(root, 129, nodes[TOTAL - 1]);
        c4_heap_move_poll(); /* must not move or reuse during the cut */
        atomic_store(&stall_enum, false);
        int32_t count = enum_count();
        assert(count == (int32_t)(tail / 2 + 2 * !bank));
        unsigned nils = 0;
        for (int32_t k = 0; k < count; ++k) {
            oop obj = c4_heap_enum_at(k);
            if (obj == cls || obj == interval_cls) { ++nils; continue; }
            unsigned i = bank;
            while (i < TOTAL && nodes[i] != obj) i += 2;
            assert(i < TOTAL && expected[i] && !seen[i]);
            seen[i] = true;
        }
        assert(nils == 2u * !bank);
        for (unsigned i = bank; i < TOTAL; i += 2) assert(seen[i] == expected[i]);
        c4_heap_enum_finish();
        for (unsigned i = 0; i < 6; ++i)
            c4_heap_store_ref(nodes[i], 1 + (i & 1), nodes[edges[i][1]]);
        c4_heap_store_ref(root, 129, nodes[seeds[0]]);
    }

    assert(c4_heap_begin());
    c4_heap_root(root); /* pinned lazy tail is the only strong root entry */
    c4_heap_root(weak);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_take_weak_clears() == TOTAL - tail);
    for (unsigned i = 0; i < TOTAL; ++i) {
        assert(c4_heap_load_ref(weak, i) == (expected[i] ? nodes[i] : cls));
        if (expected[i]) assert(c4_heap_address(nodes[i]) == old[i]);
    }
    bool moved[TOTAL] = {false};
    for (unsigned visit = 0; visit < 5; ++visit) {
        assert(!c4_heap_begin());
        c4_heap_move_poll();
        unsigned copies[2] = {0};
        for (unsigned i = 0; i < TOTAL; ++i) {
            if (!expected[i]) continue;
            if (!moved[i] && c4_heap_address(nodes[i]) != old[i]) {
                moved[i] = true;
                ++copies[i & 1];
                assert(*(const oop *)(uintptr_t)old[i] == UINT64_C(0xdddddddddddddddd));
            }
            assert(body(nodes[i])[0] == headers[i]);
            assert(body(nodes[i])[1] == ((i & 1) ? interval_cls : cls));
            assert(body(nodes[i])[2] == nodes[edges[i][0]]);
            assert(body(nodes[i])[3 + (i & 1)] == nodes[edges[i][1]]);
            assert(c4_heap_load_ref(nodes[i], 1 + (i & 1)) == nodes[edges[i][1]]);
        }
        assert(copies[0] + copies[1] <= 64 && 32 * copies[0] + 48 * copies[1] <= 4096);
        /* Both selected prefixes are wholly live. One shared budget, and
         * the other bank gets the next full visit without starving. */
        if (visit < 2) assert(copies[visit] == 64 && copies[1 - visit] == 0);
        if (visit < 4) {
            oop fresh = interval(interval_cls, true);
            for (unsigned i = 1; i < TOTAL; i += 2) assert(fresh != nodes[i]);
        }
    }
    for (unsigned i = 0; i < TOTAL; ++i) assert(moved[i] == expected[i]);
    assert(interval(interval_cls, true) == nodes[TOTAL - 1]);
    assert(point(cls, true) == nodes[TOTAL - 2]);
    assert(c4_heap_load_ref(weak, TOTAL - 1) == cls && c4_heap_load_ref(weak, TOTAL - 2) == cls);
    c4_heap_stats();
}

static void interval_saturated(void)
{
    enum { P = 512, I = 341 };
    oop ic, mc;
    oop cls = two_bank_start(48 + 40, &ic, &mc);
    oop p[P], in[I];
    for (unsigned i = 0; i < P; ++i) p[i] = point(cls, true);
    for (unsigned i = 0; i < I; ++i) in[i] = interval(ic, true);
    oop first = c4_heap_address(in[0]);
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    for (unsigned i = 0; i < P; ++i) c4_heap_root(p[i]);
    for (unsigned i = 0; i < I; ++i) c4_heap_root(in[i]);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    oop next = c4_heap_address(interval(ic, true));
    for (unsigned i = 1; i < 2 * I; ++i) interval(ic, true);
    assert(c4_heap_address(interval(ic, false)) == cls + 48);
    oop addr;
    assert(!c4_heap_reserve(40, C4_INTERVAL, &addr) && !addr);
    /* A full 48-byte bank cannot steal capacity from the other bank. */
    for (unsigned i = 0; i < 2 * P; ++i) point(cls, true);
    assert(!c4_heap_reserve(32, C4_PLAIN, &addr) && !addr);
    c4_heap_move_poll();
    assert(c4_heap_address(in[0]) == first);
    atomic_store(&stall_close, false);
    finish_cycle();
    c4_heap_move_poll();  /* both dense first regions stay in place */
    assert(c4_heap_address(in[0]) == first);

    assert(c4_heap_begin());
    c4_heap_end_roots();
    finish_cycle();
    for (unsigned i = 0; i < 14; ++i) c4_heap_move_poll();
    assert(c4_heap_address(interval(ic, true)) == next);
    c4_heap_stats();
}

static void interval_reject(const char *test)
{
    oop ic, mc;
    oop cls = two_bank_start(16384, &ic, &mc);
    oop obj = interval(ic, true);
    if (!strcmp(test, "class"))
        c4_heap_store_class(alloc(cls, F_FIXED, 3), obj);
    else if (!strcmp(test, "literals"))
        c4_heap_store_ref(alloc(mc, F_FIXED, 8), CM_LITERALS, obj);
    else if (!strcmp(test, "bytes"))
        c4_heap_store_ref(alloc(mc, F_FIXED, 8), CM_BYTECODES, obj);
    else if (!strcmp(test, "borrow"))
        c4_heap_note_code_bytes(obj);
    else if (!strcmp(test, "wrong-class"))
        interval(cls, true);
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
    enum { SLOTS = 65534, PREFIX_WORDS = 512 }; /* split on an upper-bin boundary */
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
    assert(alloc(nil, F_VAR, PREFIX_WORDS - 2) == strong);
    oop tail = alloc_nil(nil, F_VAR, SLOTS - PREFIX_WORDS, C4_NO_WEAK, nil);
    assert(tail == strong + 8 * PREFIX_WORDS);
    assert(c4_heap_load_ref(tail, SLOTS - PREFIX_WORDS - 1) == nil);
    c4_heap_store_ref(tail, SLOTS - PREFIX_WORDS - 1, kept);

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
    oop nil = (oop)(uintptr_t)arena(5 * extent(SLOTS) + 8192);
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

/* The private semaphore/carrier stand-ins are roots, not result candidates.
 * Borrowing a method during the view must not change its graph or enqueue
 * collector work that survives into the next ordinary cycle. */
static void cache_enumeration(void)
{
    oop nil = import_nil(arena(128 * 1024));
    assert(c4_heap_start());
    oop cls = alloc(nil, F_EMPTY, 0);
    oop sem = alloc(cls, F_FIXED, 1), carrier = alloc(cls, F_FIXED, 1);
    oop a = alloc(cls, F_EMPTY, 0), b = alloc(cls, F_EMPTY, 0);
    oop method = alloc(nil, F_FIXED, 1), dead = alloc(cls, F_EMPTY, 0);
    oop weak = weak_owner(nil, 1);
    c4_heap_store_ref(sem, 0, a);
    c4_heap_store_ref(carrier, 0, b);
    c4_heap_store_ref(method, 0, dead);
    c4_heap_store_ref(weak, 0, dead);

    uint64_t generation = c4_heap_cache_gen();
    assert(c4_heap_enum_request(cls, 32, sem, carrier));
    assert(c4_heap_begin());
    c4_heap_root(sem);
    c4_heap_root(carrier);
    c4_heap_root(weak);
    c4_heap_use_cached_method(method);
    atomic_store(&stall_enum, true);
    c4_heap_end_roots();
    while (!atomic_load(&at_enum)) sched_yield();
    c4_heap_use_cached_method(method);
    c4_heap_finish_poll();
    atomic_store(&stall_enum, false);
    assert(enum_count() == 2);
    oop first = c4_heap_enum_at(0), second = c4_heap_enum_at(1);
    assert((first == a && second == b) || (first == b && second == a));
    c4_heap_enum_finish();
    assert(c4_heap_cache_gen() == generation);

    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_cache_gen() != generation);
    assert(c4_heap_load_ref(weak, 0) == nil);
}

extern uint64_t c4_heap_test_weak_raw(uint64_t obj, uint32_t i);

static void mforward_disabled(void)
{
    oop ic, mc;
    oop pc = two_bank_start(4096, &ic, &mc);
    oop a = point(pc, true), b = point(pc, true);
    assert(!c4_heap_moving_forward_enabled());
    assert(!c4_heap_enable_moving_forward()); /* not a runtime switch */
    assert(!c4_heap_become_forward(a, b) && !c4_heap_has_forwarding());
}

static void mforward_roles(void)
{
    oop pc, mc, ac;
    pointer_start(4096, &pc, &mc, &ac, true, true);
    assert(c4_heap_moving_forward_enabled());
    for (oop cls = pc; cls <= ac; cls += extent(0)) {
        oop from = point(cls, true), to = point(cls, true);
        oop other = point(cls, true), pinned = alloc(cls, F_FIXED, 2);
        uint64_t gen = c4_heap_cache_gen();
        assert(!c4_heap_become_forward(pinned, to));
        assert(!c4_heap_become_forward(from, pinned));
        assert(!c4_heap_become_forward(from, point(cls == pc ? mc : pc, true)));
        assert(!c4_heap_become_forward(c4_heap_address(from), to));
        assert(gen == c4_heap_cache_gen());
        c4_heap_store_ref(from, 0, 25);
        c4_heap_store_ref(to, 0, 91);
        *(oop *)(uintptr_t)c4_heap_address(to) |= UINT64_C(991) << H_HASH_SHIFT;
        uint64_t h = body(to)[0], old_from = c4_heap_address(from);
        assert(c4_heap_become_forward(from, to) && gen != c4_heap_cache_gen());
        assert(c4_heap_canonical(from) == to && c4_heap_address(from) == c4_heap_address(to));
        assert(c4_heap_load_ref(from, 0) == 91 && body(from)[0] == h);
        c4_heap_store_ref(from, 0, 99);
        assert(c4_heap_load_ref(to, 0) == 99 && ((const oop *)(uintptr_t)old_from)[2] == 25);
        assert(!c4_heap_become_forward(to, other));
        assert(!c4_heap_become_forward(other, from));
        assert(!c4_heap_become_forward(from, other));
        assert(c4_heap_become_forward(other, to)); /* bounded fan-in */
    }
}

static void mforward_satb(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(4096, &pc, &mc, &ac, true, true);
    oop weak = weak_owner(nil, 6);
    oop from = point(pc, true), to = point(pc, true);
    oop white_from = point(pc, true), white_to = point(pc, true);
    oop old_last = point(pc, true), dead = point(pc, true);
    oop target_child = point(pc, true);
    oop pinnedi = alloc(pc, F_FIXED, 2);
    assert(!c4_heap_become_forward(pinnedi, from));
    assert(!c4_heap_become_forward(from, pinnedi));
    assert(!c4_heap_become_forward(from, point(mc, true)));
    oop old_from = c4_heap_address(from), old_to = c4_heap_address(to);

    c4_heap_store_ref(from, 1, old_last);
    c4_heap_store_ref(white_from, 1, dead);
    c4_heap_store_ref(to, 1, target_child);
    oop watched[] = {from, old_last, white_from, dead, white_to, target_child};
    for (unsigned i = 0; i < 6; ++i) c4_heap_store_ref(weak, i, watched[i]);
    assert(c4_heap_begin());
    /* Install before either source is claimed. The worker must read the
     * new marker, trace the target and retain the old second slot. */
    assert(c4_heap_become_forward(from, to));
    assert(c4_heap_become_forward(white_from, white_to));
    c4_heap_root(weak);
    c4_heap_root(from);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_test_weak_raw(weak, 0) == to);
    assert(c4_heap_test_weak_raw(weak, 1) == old_last);
    for (unsigned i = 2; i < 5; ++i) assert(c4_heap_test_weak_raw(weak, i) == nil);
    assert(c4_heap_test_weak_raw(weak, 5) == target_child);
    assert(c4_heap_take_weak_clears() == 3);
    c4_heap_move_poll();
    assert(c4_heap_address(from) == c4_heap_address(to) && c4_heap_address(to) != old_to);
    assert(*(const oop *)(uintptr_t)old_from == UINT64_C(0xdddddddddddddddd));
    assert(c4_heap_load_ref(from, 1) == target_child);

    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_root(from);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_test_weak_raw(weak, 1) == nil); /* old edges for one cycle only */
    assert(c4_heap_test_weak_raw(weak, 5) == target_child);
}

static void mforward_claimed(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(4096, &pc, &mc, &ac, true, true);
    oop root = alloc(nil, F_VAR, 1), weak = weak_owner(nil, 2);
    oop from = point(pc, true), to = point(pc, true);
    oop first = point(pc, true), second = point(pc, true);
    c4_heap_store_ref(root, 0, from);
    c4_heap_store_ref(from, 1, first);
    c4_heap_store_ref(to, 1, second);
    c4_heap_store_ref(weak, 0, first);
    c4_heap_store_ref(weak, 1, second);
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(root);
    c4_heap_root(weak);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();
    uint64_t gen = c4_heap_cache_gen();
    assert(c4_heap_become_forward(from, to) && c4_heap_cache_gen() != gen);
    /* Do not heal the referring slot here: its insertion barrier would
     * accidentally shade the target even with a broken claim handshake. */
    c4_heap_finish_poll();
    assert(c4_heap_busy() && atomic_load(&proposals) == 1);
    atomic_store(&stall_close, false);
    finish_cycle();
    assert(atomic_load(&proposals) >= 2);
    assert(c4_heap_test_weak_raw(weak, 0) == first && c4_heap_test_weak_raw(weak, 1) == second);
    c4_heap_move_poll();
    assert(c4_heap_load_ref(root, 0) == to && c4_heap_load_ref(to, 1) == second);
}

static void mforward_weak_aba(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(4096, &pc, &mc, &ac, true, true);
    oop weak = weak_owner(nil, 3);
    oop healed = point(pc, true), keeper = point(pc, true);
    oop dead = point(pc, true), dead_target = point(pc, true);
    c4_heap_store_ref(weak, 0, healed);
    c4_heap_store_ref(weak, 1, dead);
    c4_heap_store_ref(weak, 2, dead_target);
    assert(c4_heap_become_forward(healed, keeper));
    assert(c4_heap_become_forward(dead, dead_target));

    race_owner = weak; race_slot = 0; race_prev = healed;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_root(keeper);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) { c4_heap_finish_poll(); sched_yield(); }
    assert(c4_heap_test_weak_raw(weak, 0) == healed);
    assert(c4_heap_test_weak_raw(weak, 1) == dead);
    for (unsigned i = 0; i < 128; ++i) c4_heap_move_poll();
    oop newborn = point(pc, true);
    assert(newborn != healed && newborn != dead && newborn != dead_target);
    assert(!c4_heap_become_forward(newborn, dead_target)); /* white after ACK */
    finish_during_load = true;
    assert(c4_heap_load_ref(weak, 0) == keeper); /* local raw alias across sweep */
    finish_during_load = false;
    assert(c4_heap_test_weak_raw(weak, 0) == keeper);
    assert(c4_heap_test_weak_raw(weak, 1) == nil && c4_heap_test_weak_raw(weak, 2) == nil);
    assert(c4_heap_take_weak_clears() == 2);

    c4_heap_move_poll();
    assert(!c4_heap_become_forward(keeper, newborn)); /* no target downgrade */
    oop reinc_target = point(pc, true), reinc_dead = point(pc, true);
    oop reinc_healed = point(pc, true);
    assert(reinc_target == dead_target && reinc_dead == dead && reinc_healed == healed);
    assert(c4_heap_canonical(reinc_dead) == reinc_dead && c4_heap_canonical(reinc_healed) == reinc_healed);
    assert(c4_heap_become_forward(reinc_target, reinc_healed)); /* old target guard gone */
    assert(c4_heap_become_forward(reinc_dead, reinc_healed)); /* old alias guard gone */
    assert(c4_heap_load_ref(weak, 0) == keeper && c4_heap_load_ref(weak, 1) == nil &&
        c4_heap_load_ref(weak, 2) == nil);
}

static void mforward_late(void)
{
    oop pc, mc, ac;
    oop nil = pointer_start(4096, &pc, &mc, &ac, true, true);
    oop weak = weak_owner(nil, 2);
    oop late = point(pc, true), late_to = point(pc, true), white = point(pc, true);
    oop from = point(pc, true), to = point(pc, true);
    c4_heap_store_ref(weak, 0, late);
    c4_heap_store_ref(weak, 1, from);
    assert(c4_heap_become_forward(from, to));
    race_owner = weak; race_slot = 1; race_prev = from;
    atomic_store(&stall_cas, true);
    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_root(late);
    c4_heap_root(late_to);
    c4_heap_root(to);
    c4_heap_end_roots();
    while (!atomic_load(&at_cas)) { c4_heap_finish_poll(); sched_yield(); }
    /* CLEAR has already visited slot 0. Its raw alias may remain only
     * because both endpoints are live in this cycle. CAS #1 must lose. */
    assert(!c4_heap_become_forward(late, white));
    assert(!c4_heap_become_forward(white, late_to));
    assert(c4_heap_become_forward(late, late_to));
    c4_heap_store_ref(weak, 1, late);
    atomic_store(&stall_cas, false);
    finish_cycle();
    assert(c4_heap_test_weak_raw(weak, 0) == late && c4_heap_test_weak_raw(weak, 1) == late_to);
    c4_heap_move_poll();
    assert(point(pc, true) == from);
    assert(point(pc, true) == white);
    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_end_roots();
    finish_cycle();
    assert(c4_heap_test_weak_raw(weak, 0) == nil && c4_heap_test_weak_raw(weak, 1) == nil);
    c4_heap_move_poll();
    /* Round-robin sealed the previous newborn's region first. The two
     * dead aliases are tombstones until their own region releases. */
    assert(c4_heap_begin());
    c4_heap_root(weak);
    c4_heap_end_roots();
    finish_cycle();
    c4_heap_move_poll();
    assert(point(pc, true) == to);
    assert(point(pc, true) == late_to);
    assert(point(pc, true) == late);
}

static void mforward_saturated(void)
{
    enum { SLOTS = 512 };
    oop pc, mc, ac;
    pointer_start(2 * extent(2), &pc, &mc, &ac, true, true);
    oop src = point(pc, true), dst = point(pc, true);
    assert(c4_heap_become_forward(src, dst));
    oop old = c4_heap_address(dst);
    for (unsigned i = 2; i < SLOTS; ++i) point(pc, true);
    atomic_store(&stall_close, true);
    assert(c4_heap_begin());
    c4_heap_root(src);
    c4_heap_end_roots();
    while (!atomic_load(&at_close)) sched_yield();

    /* The only spill space is these two exact pinned extents; the
     * evacuation reserve stays unavailable to the mutator. */
    for (unsigned i = 0; i < 2 * SLOTS; ++i) point(pc, true);
    oop a = point(pc, false), b = point(pc, false);
    uint64_t addr;
    assert(!c4_heap_reserve(32, C4_PLAIN, &addr) && !addr);
    assert(!c4_heap_become_forward(a, dst) && !c4_heap_become_forward(dst, b));
    assert(c4_heap_become_forward(a, b));
    c4_heap_move_poll();
    assert(c4_heap_address(src) == old);
    atomic_store(&stall_close, false);
    finish_cycle();
    for (unsigned i = 0; i < SLOTS / 64; ++i) c4_heap_move_poll();
    assert(c4_heap_canonical(src) == dst && c4_heap_address(src) != old);
    assert(point(pc, true) != src);
    c4_heap_stats();
}

static void mforward_budget(void)
{
    enum { SLOTS = 128, LIVE = 66 };
    oop ic, pc;
    const size_t cap = (4 + 2 * 64) * 1024;
    void *base = mmap(NULL, cap, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(base != MAP_FAILED && c4_heap_init_moving(base, cap));
    assert(c4_heap_enable_moving_forward() && c4_heap_prepare_interval(48));
    oop nil = import_nil(base);
    pc = nil + 16;
    ic = nil + 32;
    for (oop cls = pc; cls <= ic; cls += 16) {
        initialize(cls, nil, F_EMPTY, 0);
        assert(c4_heap_import(cls, 16, 0, C4_NO_WEAK));
    }
    c4_heap_set_plain_classes(pc, 0, 0);
    c4_heap_set_pointer_forward_classes(pc, 0, 0);
    c4_heap_set_interval_class(ic);
    assert(c4_heap_start());
    oop ids[2][SLOTS], prev[2][SLOTS];
    for (unsigned i = 0; i < SLOTS; ++i) {
        ids[0][i] = point(pc, true);
        ids[1][i] = interval(ic, true);
        for (unsigned b = 0; b < 2; ++b) prev[b][i] = c4_heap_address(ids[b][i]);
    }
    assert(!c4_heap_become_forward(ids[0][0], ids[1][0]));
    assert(!c4_heap_become_forward(ids[1][0], ids[0][0]));
    for (unsigned i = 0; i < LIVE; i += 2) {
        assert(c4_heap_become_forward(ids[0][i], ids[0][i + 1]));
        assert(!c4_heap_become_forward(ids[1][i], ids[1][i + 1]));
    }
    assert(c4_heap_begin());
    for (unsigned i = 0; i < LIVE; ++i) {
        if (!(i & 1)) c4_heap_root(ids[0][i]);
        c4_heap_root(ids[1][i]);
    }
    c4_heap_end_roots();
    finish_cycle();
    for (unsigned poll = 0; poll < 4; ++poll) {
        assert(!c4_heap_begin());
        c4_heap_move_poll();
        for (unsigned b = 0; b < 2; ++b) {
            for (unsigned i = 0; i < LIVE; i += 2) {
                bool moved = poll >= b && (i < 64 || poll >= b + 2);
                uint32_t terminal = i + (b == 0);
                assert((c4_heap_address(ids[b][i]) != prev[b][terminal]) == moved);
                assert(c4_heap_canonical(ids[b][i]) == ids[b][terminal]);
                if (moved) assert(*(const oop *)(uintptr_t)prev[b][i] == UINT64_C(0xdddddddddddddddd));
            }
        }
    }
    c4_heap_stats(); /* verifies copy and withheld capacity counters in the runner */
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    if (!strcmp(argv[1], "close")) hostile_close();
    else if (!strcmp(argv[1], "cache-close")) cache_close();
    else if (!strcmp(argv[1], "shadow")) shadow_snapshot();
    else if (!strcmp(argv[1], "oracle")) oracle();
    else if (!strcmp(argv[1], "weak-close")) weak_close();
    else if (!strcmp(argv[1], "weak-shadow")) weak_shadow();
    else if (!strcmp(argv[1], "lazy-publish")) lazy_publish();
    else if (!strcmp(argv[1], "lazy-mark")) lazy_mark();
    else if (!strcmp(argv[1], "lazy-enumeration")) lazy_enumeration();
    else if (!strcmp(argv[1], "weak-idle")) weak_idle_transition();
    else if (!strcmp(argv[1], "code-bytes")) code_bytes();
    else if (!strcmp(argv[1], "forward-strong")) forward_strong();
    else if (!strcmp(argv[1], "forward-claimed")) forward_claimed();
    else if (!strcmp(argv[1], "forward-weak")) forward_weak();
    else if (!strcmp(argv[1], "forward-weak-read")) forward_weak_read();
    else if (!strcmp(argv[1], "forward-after-ack")) forward_after_ack();
    else if (!strcmp(argv[1], "forward-pinned-overlap")) forward_pinned_overlap();
    else if (!strcmp(argv[1], "pinned-fit")) pinned_fit();
    else if (!strcmp(argv[1], "pinned-stranded-swept")) pinned_stranded(false);
    else if (!strcmp(argv[1], "pinned-stranded-split")) pinned_stranded(true);
    else if (!strcmp(argv[1], "pinned-rounded")) pinned_rounded();
#ifdef SAMALTAK_C4_BIN_TEST
    else if (!strcmp(argv[1], "pinned-bin-publish")) pinned_bin_publish();
    else if (!strcmp(argv[1], "pinned-bin-group-publish")) pinned_bin_group_publish();
#endif
    else if (!strcmp(argv[1], "pinned-clear-split")) pinned_clear_split();
    else if (!strcmp(argv[1], "moving")) moving(false);
    else if (!strcmp(argv[1], "raw-read-move")) moving(true);
    else if (!strncmp(argv[1], "raw-read-", 9)) raw_read(argv[1] + 9);
    else if (!strcmp(argv[1], "moving-general")) moving_general();
    else if (!strcmp(argv[1], "moving-oracle")) moving_oracle();
    else if (!strcmp(argv[1], "moving-saturated")) moving_saturated();
    else if (!strcmp(argv[1], "interval-oracle")) interval_oracle();
    else if (!strcmp(argv[1], "interval-saturated")) interval_saturated();
    else if (!strncmp(argv[1], "interval-reject-", 16)) interval_reject(argv[1] + 16);
    else if (!strcmp(argv[1], "pointer-shape")) pointer_shape();
    else if (!strcmp(argv[1], "pointer-satb")) pointer_satb();
    else if (!strcmp(argv[1], "pointer-claimed")) pointer_claimed();
    else if (!strcmp(argv[1], "pointer-after-ack")) pointer_after_ack();
    else if (!strcmp(argv[1], "pointer-enum")) pointer_enum(false);
    else if (!strcmp(argv[1], "mforward-disabled")) mforward_disabled();
    else if (!strcmp(argv[1], "mforward-roles")) mforward_roles();
    else if (!strcmp(argv[1], "mforward-satb")) mforward_satb();
    else if (!strcmp(argv[1], "mforward-claimed")) mforward_claimed();
    else if (!strcmp(argv[1], "mforward-weak-aba")) mforward_weak_aba();
    else if (!strcmp(argv[1], "mforward-late")) mforward_late();
    else if (!strcmp(argv[1], "mforward-enum")) pointer_enum(true);
    else if (!strcmp(argv[1], "mforward-budget")) mforward_budget();
    else if (!strcmp(argv[1], "mforward-saturated")) mforward_saturated();
    else if (!strcmp(argv[1], "enumeration")) enumeration();
    else if (!strcmp(argv[1], "enumeration-limit")) enumeration_limit();
    else if (!strcmp(argv[1], "enumeration-log-limit")) enumeration_log_limit();
    else if (!strcmp(argv[1], "cache-enumeration")) cache_enumeration();
    else return 2;
    return 0;
}
