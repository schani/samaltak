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
import: obj bytes: bytes refs: refs
	<c: 'bool c4_heap_import(uint64_t obj, size_t bytes, uint32_t refs)'>
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
publish: obj refs: refs
	<c: 'void c4_heap_publish(uint64_t obj, uint32_t refs)'>
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
