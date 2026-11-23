/* These hooks are linked only into the qualification binary. */
#include "samaltak.h"
#include "c4_heap.h"
#include <assert.h>
#include <inttypes.h>
#include <time.h>

bool __real_c4_heap_should_collect(void);
bool __real_c4_heap_begin(void);
void __real_c4_heap_root(uint64_t);
void __real_c4_heap_end_roots(void);
void __real_c4_heap_finish_poll(void);
int32_t __real_replay_slice(jit_method *, frame *, int32_t, uint64_t *, bool);

uint64_t __wrap_jit_runtime_tier_up(frame *f, int64_t loop)
{
    (void)f; (void)loop;
    abort();
}

uint64_t __wrap_opt_runtime_tier_up(frame *f, int64_t loop)
{
    return __wrap_jit_runtime_tier_up(f, loop);
}

static enum { INITIAL, ARM, PUBLISH, SEALED, POLLED, REENTERED } phase;
static frame *target;
static uint64_t point, address, code[65];
static unsigned ncode, seen, copies;
static bool moving;
static int64_t native_entry_i;

bool __real_try_slice_loop(frame *);
bool __wrap_try_slice_loop(frame *f)
{
    if (f->sp == 10) native_entry_i = (int64_t)f->fp[8] >> 1;
    return __real_try_slice_loop(f);
}

static bool publishing(void)
{
    return c4_frame_next < c4_frame_limit || c4_stack_next < c4_stack_limit || c4_code_next < c4_code_limit;
}

static void assert_code(void)
{
    assert((unsigned)oop_slot_count == ncode);
    for (unsigned i = 0; i < ncode; ++i) assert(oop_slots[i] == code[i]);
}

int32_t __wrap_replay_slice(jit_method *h, frame *f, int32_t k,
                           uint64_t *dump, bool trace)
{
    assert(getenv("OPT_LOOP_PROBE"));
    assert(jit_mode == JIT_NONE && !stat_compiled && !stat_entries);
    assert(!rt_stat_opt_compiled && !rt_stat_opt_failed && !rt_stat_opt_osr);
    assert(h->mode == -1 && h->osr_pc == 6 && !h->entry && !h->uentry && !h->lower && !f->code);
    assert(!state_block->base_record && !root_count && !publishing());
    const int32_t *r = h->meta + h->sp_table[k];
    if (r[0] == 4) {
        assert(r[1] == 22 && r[2] == 10);
        unsigned regs = 0, spills = 0;
        for (int j = 0; j <= r[2]; ++j) {
            int loc = r[3+j];
            regs += (loc & 7) == LOC_REG;
            spills += (loc & 7) == LOC_SLOT;
        }
        assert(regs && spills);
    }
    int32_t why = __real_replay_slice(h, f, k, dump, trace);
    if (why != 4) return why;
    assert(f->pc == 22 && f->sp == 10);
    /* Tagged recurrence, independent of the physical map and interpreter. */
    const int64_t n = (int64_t)f->fp[0] >> 1;
    const int64_t seed = (int64_t)f->fp[1] >> 1;
    const int64_t now = (int64_t)f->fp[8] >> 1;
    int64_t fuel = state_block->stress;
    assert(fuel >= 0 && fuel <= 4);
    assert(native_entry_i - now == 4 - fuel + (fuel != 0));
    assert(now >= 0 && ((int64_t)f->fp[9] >> 1) == seed + n - now);
    for (int i = 3; i < 8; ++i) assert(f->fp[i] == 2 * (uint64_t)(68 + i) + 1);
    if (n == 13)
        fprintf(stderr, "loop probe wheel: remaining=%" PRId64 " budget=%" PRId64 "\n",
                now, state_block->stress);
    if (n != 1024 || !getenv("OPT_LOOP_GC")) return why;
    if (phase == INITIAL && state_block->stress == 0 && !c4_heap_busy()) {
        target = f;
        point = f->fp[2];
        assert(point != 0 && point != state_block->nil_oop);
        moving = c4_heap_movable(point);
        assert(moving == !!getenv("OPT_LOOP_MOVING"));
        address = c4_heap_address(point);
        ncode = 1 + h->pool_count;
        code[0] = (uint64_t)&h->method;
        for (unsigned i = 1; i < ncode; ++i)
            code[i] = h->code_start + h->pool_offset + 8*(i-1);
        assert_code();
        phase = ARM;
        fprintf(stderr, "loop probe: arm backedge pc=22 depth=10 keep_loc=%d code_roots=%u\n", r[6], ncode);
    } else if (phase == POLLED) {
        assert(f == target && f->fp[2] == point);
        phase = REENTERED;
        fputs("loop probe: same activation reentered after GC\n", stderr);
    } else if (phase == PUBLISH) {
        abort(); /* No native launch while resumable code roots are frozen. */
    }
    return why;
}

bool __wrap_c4_heap_should_collect(void)
{
    return phase == ARM || __real_c4_heap_should_collect();
}

bool __wrap_c4_heap_begin(void)
{
    bool started = __real_c4_heap_begin();
    if (phase == ARM) {
        assert(started && !state_block->base_record && !root_count);
        phase = PUBLISH;
    }
    return started;
}

void __wrap_c4_heap_root(uint64_t v)
{
    if (phase == PUBLISH) {
        copies += v == point;
        if (c4_frame_next == c4_frame_limit && c4_stack_next == c4_stack_limit &&
            c4_code_next < c4_code_limit) {
            assert_code();
            assert(c4_code_next == seen && v == *(uint64_t *)code[seen]);
            ++seen;
        }
    }
    __real_c4_heap_root(v);
}

void __wrap_c4_heap_end_roots(void)
{
    if (phase == PUBLISH) {
        assert_code();
        assert(copies == 1 && seen == ncode);
        phase = SEALED;
        fprintf(stderr, "loop probe: sealed point_roots=%u code_roots=%u\n", copies, seen);
    }
    __real_c4_heap_end_roots();
}

void __wrap_c4_heap_finish_poll(void)
{
    if (phase != SEALED) { __real_c4_heap_finish_poll(); return; }
    assert(!state_block->base_record && !root_count && !publishing());
    assert(target == frames + nframes - 1 && target->fp[2] == point);
    /* Fixed wheel, at a real dispatch checkpoint; no other mutator, no
       fabricated roots or publication. Process-level timeout bounds this too. */
    const struct timespec tick = { .tv_nsec = 2 * 1000 * 1000 };
    for (unsigned i = 0; i < 48; ++i) {
        __real_c4_heap_finish_poll();
        if (moving) c4_heap_move_poll();
        nanosleep(&tick, NULL);
    }
    assert(!c4_heap_busy());
    assert((c4_heap_address(point) != address) == moving);
    phase = POLLED;
    fprintf(stderr, "loop probe: 48x2ms polls, actual %s %" PRIx64 " -> %" PRIx64 "\n",
            moving ? "relocation" : "pinned GC", address, c4_heap_address(point));
}
