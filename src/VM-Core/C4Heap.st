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
threshold: bytes
	<c: 'void c4_heap_set_threshold(size_t bytes)'>
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
alloc: bytes
	<c: 'uint64_t c4_heap_alloc(size_t bytes)'>
	^0
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
store: slot value: o
	<c: 'void c4_heap_store(uint64_t *slot, uint64_t o)'>
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
