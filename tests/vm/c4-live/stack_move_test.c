#include <assert.h>
#include "samaltak.h"
#include "stack_move_impl.inc"

static const oop poison = UINT64_C(0xdeaddeaddeaddead);

static oop raw_word(size_t i)
{
    /* Cover raw pointer-shaped IDs (including would-be forwarding aliases)
     * and immediates; this move must copy/save both without interpreting them. */
    return UINT64_C(0x123400) + 8 * i + (i & 1);
}

enum { WIDTH = 12 };

static void run_case(size_t base, size_t dst, size_t src, size_t count,
                     size_t next, size_t limit, bool presaved)
{
    oop expected[WIDTH];
    for (size_t i = 0; i < WIDTH; ++i) {
        cstack[base + i] = expected[i] = raw_word(base + i);
        c4_saved_stack_bits[base + i] =
            presaved && next <= i && i < limit && i % 2 == 0;
        c4_saved_stack[base + i] = poison;
    }
    c4_stack_next = base + next;
    c4_stack_limit = base + limit;
    memmove(expected + dst, expected + src, count * sizeof(oop));

    move_stack_down(cstack + base + dst, cstack + base + src, count);
    assert(!memcmp(cstack + base, expected, sizeof(expected)));
    assert(c4_stack_next == base + next && c4_stack_limit == base + limit);
    for (size_t i = 0; i < WIDTH; ++i) {
        bool in_cut = next <= i && i < limit;
        bool had_note = presaved && in_cut && i % 2 == 0;
        bool needs_note = in_cut && dst <= i && i < dst + count;
        assert(c4_saved_stack_bits[base + i] == (had_note || needs_note));
        assert(c4_saved_stack[base + i] ==
               (needs_note && !had_note ? raw_word(base + i) : poison));
    }
}

static void repeated_overlap(void)
{
    for (size_t i = 0; i < WIDTH; ++i) {
        cstack[i] = raw_word(i);
        c4_saved_stack_bits[i] = false;
    }
    c4_stack_next = 2;
    c4_stack_limit = 8;
    move_stack_down(cstack + 3, cstack + 5, 5);
    move_stack_down(cstack + 1, cstack + 3, 6);
    for (size_t i = 2; i < 8; ++i) {
        assert(c4_saved_stack_bits[i]);
        assert(c4_saved_stack[i] == raw_word(i));
    }
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    /* Every cut position, both overlapping and disjoint downward copies,
     * including an empty cut and the final slot of the real stack. */
    const size_t bases[] = {0, CSTACK_SLOTS - WIDTH};
    for (size_t b = 0; b < sizeof(bases) / sizeof(bases[0]); ++b)
        for (size_t src = 1; src < WIDTH; ++src)
            for (size_t dst = 0; dst < src; ++dst)
                for (size_t n = 1; n <= WIDTH - src; ++n)
                    for (size_t next = 0; next <= WIDTH; ++next)
                        for (size_t limit = next; limit <= WIDTH; ++limit) {
                            run_case(bases[b], dst, src, n, next, limit, false);
                            run_case(bases[b], dst, src, n, next, limit, true);
                        }
    repeated_overlap();
    puts("c4-stack-move: downward overlap and first-write root preservation passed");
}
