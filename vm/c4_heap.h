#ifndef SAMALTAK_C4_HEAP_H
#define SAMALTAK_C4_HEAP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__linux__) && defined(__x86_64__) && !defined(SAMALTAK_UEFI) && \
    (defined(SAMALTAK_NO_PLATFORM) || defined(SAMALTAK_C4_PLATFORM_FILES))
#define SAMALTAK_C4_SUPPORTED 1
#else
#define SAMALTAK_C4_SUPPORTED 0
#endif

static inline bool c4_heap_platform_files(void)
{
#ifdef SAMALTAK_C4_PLATFORM_FILES
    return true;
#else
    return false;
#endif
}

/* weak_start is the validated fixed count for F_WEAK, otherwise C4_NO_WEAK. */
#define C4_NO_WEAK UINT32_MAX
#define C4_ENUM_LIMIT 4096

enum c4_lane { C4_PINNED, C4_PLAIN, C4_INTERVAL };

#if SAMALTAK_C4_SUPPORTED

/* All entry points are called by the sole mutator. The arena remains owned by
 * the VM and must stay mapped/writable for the process lifetime. */
bool c4_heap_supported(void);
bool c4_heap_init(void *base, size_t capacity);
bool c4_heap_init_moving(void *base, size_t capacity);
bool c4_heap_prepare_interval(size_t image_bytes);
size_t c4_heap_pinned_capacity(void);
/* The two-slot lane uses image identities captured at startup. */
void c4_heap_set_plain_classes(uint64_t point, uint64_t message, uint64_t association);
bool c4_heap_plain_class(uint64_t cls);
/* Optional exact three-slot class, validated by the boot image loader. */
void c4_heap_set_interval_class(uint64_t cls);
bool c4_heap_interval_class(uint64_t cls);
bool c4_heap_is_imported(uint64_t obj);
/* Configure the relocated image nil before importing weak objects. */
void c4_heap_set_nil(uint64_t nil);
bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t weak_start);
void c4_heap_set_threshold(size_t bytes);
void c4_heap_set_context_class(uint64_t cls);
void c4_heap_set_method_class(uint64_t cls);
/* Mutator-only cache lease; changes before close ACK or forward publication. */
extern uint64_t c4_heap_cache_generation;
void c4_heap_invalidate_cache(void);
void c4_heap_use_cached_method(uint64_t method);
bool c4_heap_start(void);

/* Returns logical oop; init_addr is private storage until publish.
 * A full moving bank falls back only to C4's pinned lane.
 * Initialize privately, then publish before any safepoint.
 * No fit returns zero; allocation does not collect or wait for a cycle. refs
 * is the full slot count for pointer formats 1–4, zero for raw formats. */
uint64_t c4_heap_reserve(size_t bytes, enum c4_lane lane, uint64_t *init_addr);
/* All ref slots must be initialized to nil except the fixed Context stackp.
 * Arbitrary initialized edges are supported at startup (import) only. */
void c4_heap_publish_nil(uint64_t obj, uint32_t refs, uint32_t weak_start);
#ifdef SAMALTAK_C4_TEST
void c4_heap_publish(uint64_t obj, uint32_t refs, uint32_t weak_start);
#endif
/* Configure exact pinned ByteString and WideString classes before start.
 * The classes are roots. Omit to disable forwarding. The target header
 * (including its identity hash) is unchanged. */
void c4_heap_set_forward_classes(uint64_t bytes, uint64_t wide);
bool c4_heap_become_forward(uint64_t from, uint64_t to);
/* Sticky fast guard. Canonicalization gives a logical oop, not a body view.
 * Trace a raw alias unless the actual root slot has been normalized. */
bool c4_heap_has_forwarding(void);
uint64_t c4_heap_canonical(uint64_t obj);
/* A live pinned object with a borrowed raw view cannot become until reused.
 * Do not pass an already-forwarded raw source here. */
void c4_heap_forbid_become(uint64_t obj);
/* Lifetime marker for pinned compiled bytecodes. Not a root. */
void c4_heap_note_code_bytes(uint64_t obj);
bool c4_heap_is_code_bytes(uint64_t obj);
/* Non-nesting synchronous raw read on the sole mutator. Enter before
 * getting interior pointers, leave before any dispatch/idle poll or
 * forwarding. The caller must already keep owners live in VM roots;
 * this neither roots nor pins anything and does not permit pointer escape.
 * The VM's raw body accessors still reject movable owners. */
void c4_heap_enter_raw_read(void);
void c4_heap_leave_raw_read(void);
/* Class word and body slot writes, respectively. Neither is a post-store hook. */
void c4_heap_store_class(uint64_t owner, uint64_t value);
void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value);
/* Shadow is authoritative for weak slots, even between cycles. The load
 * shades weak referents before close ACK, and hides white ones after ACK.
 * Heals one alias on read. Respect Context's live-prefix rule. */
uint64_t c4_heap_load_ref(uint64_t obj, uint32_t index);
uint32_t c4_heap_weak_start(uint64_t obj);

/* Queue one exact view, armed by the next successful begin(). Reclamation
 * remains off until finish; publish/root the result before calling it. */
bool c4_heap_enum_request(uint64_t cls, uint32_t max_roots, uint64_t exclude_a, uint64_t exclude_b);
/* -2: pending, -1: failed, otherwise number of canonical IDs. Recheck
 * before publication: forwarding of ByteStrings can invalidate a view. */
int32_t c4_heap_enum_count(void);
uint64_t c4_heap_enum_at(uint32_t index);
void c4_heap_enum_finish(void);

/* Start root snapshot, enqueue scalar roots and displaced unpublished roots,
 * and seal after all root slices. The collector cannot sweep before the seal.
 * A root must not be merely cached outside the managed graph or VM root set. */
bool c4_heap_begin(void);
void c4_heap_root(uint64_t value);
void c4_heap_end_roots(void);
/* Mutator-only; resolve a live oop. No movable view may cross this poll.
 * The poll runs only at dispatch, never at scheduler idle or on allocation. */
uint64_t c4_heap_address(uint64_t obj);
bool c4_heap_movable(uint64_t obj);
void c4_heap_move_poll(void);
/* Bounded close handshake at each authoritative interpreter checkpoint. */
void c4_heap_finish_poll(void);
/* Drain the worker's successful clears. Only the mutator signals the VM's
 * finalization semaphore; also poll around bounded scheduler idle waits. */
uint64_t c4_heap_take_weak_clears(void);
/* Worker cycle status only; dispatch relocation may remain pending. */
bool c4_heap_busy(void);
bool c4_heap_should_collect(void);
/* High-water mark, NOT an iterator over live objects. */
uint64_t c4_heap_top(void);
void c4_heap_stats(void);

#else

static inline bool c4_heap_supported(void) { return false; }
static inline bool c4_heap_init(void *base, size_t capacity)
{ (void)base; (void)capacity; return false; }
static inline bool c4_heap_init_moving(void *base, size_t capacity)
{ (void)base; (void)capacity; return false; }
static inline bool c4_heap_prepare_interval(size_t image_bytes)
{ (void)image_bytes; return false; }
static inline size_t c4_heap_pinned_capacity(void) { return 0; }
static inline void c4_heap_set_plain_classes(uint64_t point, uint64_t message, uint64_t association)
{ (void)point; (void)message; (void)association; }
static inline bool c4_heap_plain_class(uint64_t cls) { (void)cls; return false; }
static inline void c4_heap_set_interval_class(uint64_t cls) { (void)cls; }
static inline bool c4_heap_interval_class(uint64_t cls) { (void)cls; return false; }
static inline bool c4_heap_is_imported(uint64_t obj) { (void)obj; return false; }
static inline void c4_heap_set_nil(uint64_t nil) { (void)nil; }
static inline bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t weak_start)
{ (void)obj; (void)bytes; (void)refs; (void)weak_start; return false; }
static inline void c4_heap_set_threshold(size_t bytes) { (void)bytes; }
static inline void c4_heap_set_context_class(uint64_t cls) { (void)cls; }
static inline void c4_heap_set_method_class(uint64_t cls) { (void)cls; }
#define c4_heap_cache_generation UINT64_C(0)
static inline void c4_heap_invalidate_cache(void) { }
static inline void c4_heap_use_cached_method(uint64_t method) { (void)method; }
static inline bool c4_heap_start(void) { return false; }
static inline uint64_t c4_heap_reserve(size_t bytes, enum c4_lane lane, uint64_t *init_addr)
{ (void)bytes; (void)lane; *init_addr = 0; return 0; }
static inline void c4_heap_publish_nil(uint64_t obj, uint32_t refs, uint32_t weak_start)
{ (void)obj; (void)refs; (void)weak_start; }
static inline void c4_heap_set_forward_classes(uint64_t bytes, uint64_t wide)
{ (void)bytes; (void)wide; }
static inline bool c4_heap_become_forward(uint64_t from, uint64_t to)
{ (void)from; (void)to; return false; }
static inline bool c4_heap_has_forwarding(void) { return false; }
static inline uint64_t c4_heap_canonical(uint64_t obj) { return obj; }
static inline void c4_heap_forbid_become(uint64_t obj) { (void)obj; }
static inline void c4_heap_note_code_bytes(uint64_t obj) { (void)obj; }
static inline bool c4_heap_is_code_bytes(uint64_t obj) { (void)obj; return false; }
static inline void c4_heap_enter_raw_read(void) { }
static inline void c4_heap_leave_raw_read(void) { }
static inline void c4_heap_store_class(uint64_t obj, uint64_t value)
{ ((uint64_t *)(uintptr_t)obj)[1] = value; }
static inline void c4_heap_store_ref(uint64_t obj, uint32_t index, uint64_t value)
{ ((uint64_t *)(uintptr_t)obj)[2 + (size_t)index] = value; }
static inline uint64_t c4_heap_load_ref(uint64_t obj, uint32_t index)
{ return ((const uint64_t *)(uintptr_t)obj)[2 + (size_t)index]; }
static inline uint32_t c4_heap_weak_start(uint64_t obj) { (void)obj; return C4_NO_WEAK; }
static inline bool c4_heap_enum_request(uint64_t cls, uint32_t max_roots, uint64_t exclude_a, uint64_t exclude_b)
{ (void)cls; (void)max_roots; (void)exclude_a; (void)exclude_b; return false; }
static inline int32_t c4_heap_enum_count(void) { return -2; }
static inline uint64_t c4_heap_enum_at(uint32_t index) { (void)index; return 0; }
static inline void c4_heap_enum_finish(void) { }
static inline bool c4_heap_begin(void) { return false; }
static inline void c4_heap_root(uint64_t value) { (void)value; }
static inline void c4_heap_end_roots(void) { }
static inline uint64_t c4_heap_address(uint64_t obj) { return obj; }
static inline bool c4_heap_movable(uint64_t obj) { (void)obj; return false; }
static inline void c4_heap_move_poll(void) { }
static inline void c4_heap_finish_poll(void) { }
static inline uint64_t c4_heap_take_weak_clears(void) { return 0; }
static inline bool c4_heap_busy(void) { return false; }
static inline bool c4_heap_should_collect(void) { return false; }
static inline uint64_t c4_heap_top(void) { return 0; }
static inline void c4_heap_stats(void) { }

#endif

static inline uint64_t c4_heap_cache_gen(void) { return c4_heap_cache_generation; }

#endif
