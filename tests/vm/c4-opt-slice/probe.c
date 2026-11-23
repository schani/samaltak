/* Link-only probes. The VM binaries under test do not contain these hooks. */
#include "samaltak.h"
#include "c4_heap.h"
#include <inttypes.h>
#include <assert.h>

int32_t __real_replay_slice(jit_method *, frame *, int32_t, uint64_t *, bool);
bool __real_c4_heap_should_collect(void);
bool __real_c4_heap_begin(void);
void __real_c4_heap_root(uint64_t);
void __real_c4_heap_end_roots(void);
void __real_c4_heap_move_poll(void);

/* Trap both the ordinary tier-up stub target and its optimizer callee. */
uint64_t __wrap_jit_runtime_tier_up(frame *f, int64_t loop)
{
    (void)f;
    (void)loop;
    fputs("slice probe: ordinary JIT tier-up called\n", stderr);
    abort();
}

uint64_t __wrap_opt_runtime_tier_up(frame *f, int64_t loop)
{
    return __wrap_jit_runtime_tier_up(f, loop);
}

static uint64_t watched, before;
static unsigned want_cycle, collecting, moved, roots, chunks, fresh, code_seen;
static unsigned expected_code;
static uint64_t slots[65];

int32_t __wrap_replay_slice(jit_method *h, frame *f, int32_t k,
                            uint64_t *dump, bool trace)
{
    assert(getenv("OPT_SLICE_EXPECT_NATIVE"));
    assert(jit_mode == JIT_NONE && !stat_compiled && !stat_entries);
    assert(!rt_stat_opt_compiled && !rt_stat_opt_failed && !rt_stat_opt_osr);
    assert(h->mode == -1 && !f->code && !h->lower && !h->opt && !h->entry && !h->uentry);
    assert(!state_block->base_record && !root_count);
    assert(k >= 0 && (unsigned)k < h->sp_count && (uint64_t)k == dump[31]);
    const int32_t *r = h->meta + h->sp_table[k];
    fprintf(stderr, "slice probe: native return reason=%d\n", r[0]);
    if (!getenv("OPT_SLICE_WITNESS")) return __real_replay_slice(h, f, k, dump, trace);
    uint64_t candidate = 0;
    if (r[0] == 3 && r[2] == 4) {
        int32_t loc = r[5]; /* receiver first; argument 1 at word 5 */
        assert(loc == 17); /* LOC_REG, allocatable GPR index 2. */
        candidate = dump[loc >> 3];
        assert(candidate && c4_heap_movable(candidate));
    }
    int32_t why = __real_replay_slice(h, f, k, dump, trace);
    if (!candidate) return why;
    assert(f->fp[1] == candidate);
    assert(!state_block->base_record && !root_count);
    if (!watched) {
        watched = candidate;
        before = c4_heap_address(watched);
        expected_code = 1 + h->pool_count;
        assert(expected_code == (unsigned)oop_slot_count && h->pool_count);
        slots[0] = (uint64_t)&h->method;
        for (unsigned i = 1; i < expected_code; ++i)
            slots[i] = h->code_start + h->pool_offset + 8*(i-1);
        for (unsigned i = 0; i < expected_code; ++i) assert(oop_slots[i] == slots[i]);
        want_cycle = 1;
        fprintf(stderr, "opt-slice witness physical=%d value=%" PRIx64 " code_roots=%u\n", r[5], watched, expected_code);
    } else if (moved && !fresh) {
        assert(watched == candidate);
        fresh = 1;
        fprintf(stderr, "opt-slice witness fresh reentry after move\n");
    }
    return why;
}

bool __wrap_c4_heap_should_collect(void)
{
    return want_cycle || __real_c4_heap_should_collect();
}

bool __wrap_c4_heap_begin(void)
{
    bool started = __real_c4_heap_begin();
    if (want_cycle) {
        assert(started);
        assert(!state_block->base_record && !root_count);
        want_cycle = 0;
        collecting = 1;
    }
    return started;
}

void __wrap_c4_heap_root(uint64_t v)
{
    if (collecting) {
        roots += v == watched;
        if (c4_frame_next == c4_frame_limit && c4_stack_next == c4_stack_limit &&
            c4_code_next < c4_code_limit) {
            unsigned i = c4_code_next;
            assert(i == code_seen++ && oop_slots[i] == slots[i]);
            assert(v == *(uint64_t *)slots[i]);
        }
    }
    __real_c4_heap_root(v);
}

void __wrap_c4_heap_end_roots(void)
{
    if (collecting) {
        collecting = 0;
        assert(roots == 1 && code_seen == expected_code && chunks > 0);
        fprintf(stderr, "opt-slice witness sealed watched_roots=%u code_roots=%u partial=%u\n",
                roots, code_seen, chunks);
    }
    __real_c4_heap_end_roots();
}

void __wrap_c4_heap_move_poll(void)
{
    if (collecting) {
        ++chunks;
        assert(c4_code_next < c4_code_limit);
        assert((unsigned)oop_slot_count == expected_code);
        for (unsigned i = 0; i < expected_code; ++i) assert(oop_slots[i] == slots[i]);
    }
    __real_c4_heap_move_poll();
    if (watched && !collecting && !want_cycle && !moved) {
        uint64_t now = c4_heap_address(watched);
        if (now != before) {
            moved = 1;
            fprintf(stderr, "opt-slice witness relocated %" PRIx64 " -> %" PRIx64 "\n", before, now);
        }
    }
}
