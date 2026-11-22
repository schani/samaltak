CLibrary subclass: #C4Heap
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

!C4Heap class methodsFor: 'declaring'!
headers
	^#('"c4_heap.h"')
! !

!C4Heap methodsFor: 'lifecycle'!
supported
	<c: 'bool c4_heap_supported(void)'>
	^false
!
init: base capacity: bytes
	<c: 'bool c4_heap_init(void *base, size_t bytes)'>
	^false
!
initMoving: base capacity: bytes
	<c: 'bool c4_heap_init_moving(void *base, size_t bytes)'>
	^false
!
pinnedCapacity
	<c: 'size_t c4_heap_pinned_capacity(void)'>
	^0
!
pointClass: cls
	<c: 'void c4_heap_set_point_class(uint64_t cls)'>
!
threshold: bytes
	<c: 'void c4_heap_set_threshold(size_t bytes)'>
!
forwardByteClass: bytes wideClass: wide
	<c: 'void c4_heap_set_forward_classes(uint64_t bytes, uint64_t wide)'>
!
contextClass: cls
	<c: 'void c4_heap_set_context_class(uint64_t cls)'>
!
nilOop: obj
	<c: 'void c4_heap_set_nil(uint64_t obj)'>
!
import: obj bytes: bytes refs: refs weakStart: first
	<c: 'bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs, uint32_t first)'>
	^false
!
start
	<c: 'bool c4_heap_start(void)'>
	^false
!
report
	<c: 'void c4_heap_stats(void)'>
! !

!C4Heap methodsFor: 'allocation and stores'!
reserve: bytes plain: lane into: address
	<c: 'uint64_t c4_heap_reserve(size_t bytes, int lane, uint64_t *address)'>
	^0
!
address: obj
	<c: 'uint64_t c4_heap_address(uint64_t obj)'>
	^0
!
hasForwarding
	<c: 'bool c4_heap_has_forwarding(void)'>
	^false
!
canonical: obj
	<c: 'uint64_t c4_heap_canonical(uint64_t obj)'>
	^obj
!
becomeForward: from to: to
	<c: 'bool c4_heap_become_forward(uint64_t from, uint64_t to)'>
	^false
!
forbidBecome: obj
	<c: 'void c4_heap_forbid_become(uint64_t obj)'>
!
movable: obj
	<c: 'bool c4_heap_movable(uint64_t obj)'>
	^false
!
publish: obj refs: refs weakStart: first
	<c: 'void c4_heap_publish(uint64_t obj, uint32_t refs, uint32_t first)'>
!
loadRef: obj at: i
	<c: 'uint64_t c4_heap_load_ref(uint64_t obj, uint32_t i)'>
	^0
!
weakStart: obj
	<c: 'uint32_t c4_heap_weak_start(uint64_t obj)'>
	^0
!
storeClass: obj value: o
	<c: 'void c4_heap_store_class(uint64_t obj, uint64_t o)'>
!
storeRef: obj at: i put: o
	<c: 'void c4_heap_store_ref(uint64_t obj, uint32_t i, uint64_t o)'>

!
top
	<c: 'uint64_t c4_heap_top(void)'>
	^0
! !

!C4Heap methodsFor: 'cycles'!
beginCycle
	<c: 'bool c4_heap_begin(void)'>
	^false
!
root: o
	<c: 'void c4_heap_root(uint64_t o)'>
!
endRoots
	<c: 'void c4_heap_end_roots(void)'>
!
takeWeakClears
	<c: 'uint64_t c4_heap_take_weak_clears(void)'>
	^0
!
movePoll
	<c: 'void c4_heap_move_poll(void)'>
!
finishPoll
	<c: 'void c4_heap_finish_poll(void)'>
!
busy
	<c: 'bool c4_heap_busy(void)'>
	^false
!
shouldCollect
	<c: 'bool c4_heap_should_collect(void)'>
	^false
! !
