#include "c4_heap.h"
#include "samaltak.h"

#include <assert.h>
#include <sched.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>

static _Atomic bool stall_close, at_close;
static _Atomic unsigned proposals;

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
    c4_heap_publish(obj, fmt >= F_FIXED && fmt <= F_FIXVAR ? slots : 0);
}

static oop alloc(oop cls, unsigned fmt, uint32_t slots)
{
    oop obj = c4_heap_alloc(extent(slots));
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
        assert(c4_heap_alloc(size) == 0);
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
    assert(!c4_heap_import(cls, extent(0), 0));
    initialize(cls, cls, F_EMPTY, 0);
    assert(c4_heap_import(cls, extent(0), 0));
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
            while ((result = c4_heap_alloc(extent(slots)))) {
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

int main(int argc, char **argv)
{
    assert(argc == 2);
    if (!strcmp(argv[1], "close")) hostile_close();
    else if (!strcmp(argv[1], "shadow")) shadow_snapshot();
    else if (!strcmp(argv[1], "oracle")) oracle();
    else return 2;
    return 0;
}
