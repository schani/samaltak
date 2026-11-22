/* Test only. The mutator's file read waits on an OS pipe; only the marker
 * can release it, after tracing from a middle-of-mark checkpoint to CLOSE. */
#include <assert.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>

static int go[2], done[2];
enum { INITIAL, MARK_PAUSED, READ_WAITING, PROVED };
static atomic_int state;

__attribute__((constructor))
static void init(void)
{
    assert(pipe(go) == 0 && pipe(done) == 0);
}

bool c4_heap_test_roots_sealed(void);
ssize_t __real_read(int fd, void *buf, size_t count);
ssize_t __wrap_read(int fd, void *buf, size_t count)
{
    int expected = MARK_PAUSED;
    if (count == 253 && c4_heap_test_roots_sealed() &&
            atomic_compare_exchange_strong(&state, &expected, READ_WAITING)) {
        char ack;
        assert(write(go[1], "g", 1) == 1);
        assert(__real_read(done[0], &ack, 1) == 1 && ack == 'd');
        static const char proof[] = "C4 worker reached close during file read\n";
        assert(write(STDERR_FILENO, proof, sizeof proof - 1) == sizeof proof - 1);
    }
    return __real_read(fd, buf, count);
}

void c4_heap_test_mark_chunk(uint32_t at, uint32_t word, bool materialized)
{
    int expected = INITIAL;
    if (atomic_compare_exchange_strong(&state, &expected, MARK_PAUSED)) {
        char ack;
        assert(__real_read(go[0], &ack, 1) == 1 && ack == 'g');
    }
}

void c4_heap_test_after_close(void)
{
    int expected = READ_WAITING;
    if (atomic_compare_exchange_strong(&state, &expected, PROVED))
        assert(write(done[1], "d", 1) == 1);
}

void c4_heap_test_before_weak_cas(uint64_t obj, uint32_t i, uint64_t prev) {}
void c4_heap_test_after_weak_load(uint64_t obj, uint32_t i, uint64_t value) {}
void c4_heap_test_enum_field(uint32_t at, uint32_t i, bool materialized) {}
void c4_heap_test_before_enum(void) {}
