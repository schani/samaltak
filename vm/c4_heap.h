#ifndef SAMALTAK_C4_HEAP_H
#define SAMALTAK_C4_HEAP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__linux__) && defined(__x86_64__) && defined(SAMALTAK_NO_PLATFORM) && !defined(SAMALTAK_UEFI)
#define SAMALTAK_C4_SUPPORTED 1
#else
#define SAMALTAK_C4_SUPPORTED 0
#endif

/* weak_start is the validated fixed count for F_WEAK, otherwise C4_NO_WEAK. */
#define C4_NO_WEAK UINT32_MAX

#if SAMALTAK_C4_SUPPORTED

/* All entry points are called by the sole mutator. The arena remains owned by
 * the VM and must stay mapped/writable for the process lifetime. */
bool c4_heap_supported(void);
bool c4_heap_init(void *base, size_t capacity);
/* Configure the relocated image nil before importing weak objects. */
void c4_heap_set_nil(uint64_t nil);
bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t weak_start);
void c4_heap_set_threshold(size_t bytes);
void c4_heap_set_context_class(uint64_t cls);
bool c4_heap_start(void);

/* Reserve raw memory; initialize privately, then publish before any safepoint.
 * No fit returns zero; allocation does not collect or wait for a cycle. refs
 * is the full slot count for pointer formats 1–4, zero for raw formats. */
uint64_t c4_heap_alloc(size_t bytes);
void c4_heap_publish(uint64_t obj, uint32_t refs, uint32_t weak_start);
/* Class word and body slot writes, respectively. Neither is a post-store hook. */
void c4_heap_store(uint64_t *slot, uint64_t value);
void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value);
/* Shadow is authoritative for weak slots, even between cycles. The load
 * shades weak referents before close ACK, and hides white ones after ACK.
 * Nonweak callers must still respect Context's live-prefix rule. */
uint64_t c4_heap_load_ref(uint64_t obj, uint32_t index);
uint32_t c4_heap_weak_start(uint64_t obj);

/* Start root snapshot, enqueue scalar roots and displaced unpublished roots,
 * and seal after all root slices. The collector cannot sweep before the seal.
 * A root must not be merely cached outside the managed graph or VM root set. */
bool c4_heap_begin(void);
void c4_heap_root(uint64_t value);
void c4_heap_end_roots(void);
/* Bounded close handshake at each authoritative interpreter checkpoint. */
void c4_heap_finish_poll(void);
/* Drain the worker's successful clears. Only the mutator signals the VM's
 * finalization semaphore; also poll around bounded scheduler idle waits. */
uint64_t c4_heap_take_weak_clears(void);
bool c4_heap_busy(void);
bool c4_heap_should_collect(void);
/* High-water mark, NOT an iterator over live objects. */
uint64_t c4_heap_top(void);
void c4_heap_stats(void);

#else

static inline bool c4_heap_supported(void) { return false; }
static inline bool c4_heap_init(void *base, size_t capacity)
{ (void)base; (void)capacity; return false; }
static inline void c4_heap_set_nil(uint64_t nil) { (void)nil; }
static inline bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t weak_start)
{ (void)obj; (void)bytes; (void)refs; (void)weak_start; return false; }
static inline void c4_heap_set_threshold(size_t bytes) { (void)bytes; }
static inline void c4_heap_set_context_class(uint64_t cls) { (void)cls; }
static inline bool c4_heap_start(void) { return false; }
static inline uint64_t c4_heap_alloc(size_t bytes) { (void)bytes; return 0; }
static inline void c4_heap_publish(uint64_t obj, uint32_t refs, uint32_t weak_start)
{ (void)obj; (void)refs; (void)weak_start; }
static inline void c4_heap_store(uint64_t *slot, uint64_t value) { *slot = value; }
static inline void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value)
{ ((uint64_t *)(uintptr_t)obj)[2 + (size_t)index] = value; }
static inline uint64_t c4_heap_load_ref(uint64_t obj, uint32_t index)
{ return ((const uint64_t *)(uintptr_t)obj)[2 + (size_t)index]; }
static inline uint32_t c4_heap_weak_start(uint64_t obj) { (void)obj; return C4_NO_WEAK; }
static inline bool c4_heap_begin(void) { return false; }
static inline void c4_heap_root(uint64_t value) { (void)value; }
static inline void c4_heap_end_roots(void) { }
static inline void c4_heap_finish_poll(void) { }
static inline uint64_t c4_heap_take_weak_clears(void) { return 0; }
static inline bool c4_heap_busy(void) { return false; }
static inline bool c4_heap_should_collect(void) { return false; }
static inline uint64_t c4_heap_top(void) { return 0; }
static inline void c4_heap_stats(void) { }

#endif
#endif
