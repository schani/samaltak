/* Drive the real scheduler with a ticker request on either side of its
 * acknowledgment. The platform-poll wrapper is the synchronization point. */
#include "samaltak.h"
#include <assert.h>
#include <pthread.h>

static bool request_during_poll;
static unsigned polls;

static void *request(void *unused)
{
    (void)unused;
    tick_fired(TICK_POLL);
    return NULL;
}

static void ticker_request(void)
{
    pthread_t thread;
    int err = pthread_create(&thread, NULL, request, NULL);
    assert(err == 0);
    err = pthread_join(thread, NULL);
    assert(err == 0);
}

void __wrap_platform_interface_poll(void)
{
    ++polls;
    assert(atomic_load(&interrupt_pending[0]) == 0);
    if (request_during_poll)
        ticker_request();
}

int __wrap_main(void)
{
    assert(atomic_is_lock_free(&interrupt_pending[0]));
    assert(sizeof interrupt_pending[0] == 4);
    ticker_request();
    request_interrupt_check(); /* Coalesces with the ticker request. */
    assert(atomic_load(&interrupt_pending[0]) == 1);

    request_during_poll = true;
    handle_interrupts();
    assert(polls == 1 && atomic_load(&interrupt_pending[0]) == 1);

    request_during_poll = false;
    handle_interrupts();
    assert(polls == 2 && atomic_load(&interrupt_pending[0]) == 0);
    puts("jit-poll: request during handling survived");
    return 0;
}
