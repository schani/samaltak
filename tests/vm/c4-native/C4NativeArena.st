CLibrary subclass: #C4NativeCalls
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'C4-NativeTests'!

!C4NativeCalls class methodsFor: 'declaring'!
headers
	^#('<pthread.h>' '<time.h>')
!
typedefs
	^#((pthread_t uintptr_t) (pthread_attr_t opaque))
! !

!C4NativeCalls methodsFor: 'native only'!
load: p order: order
	<c: 'uint64_t __atomic_load_n(const uint64_t *p, int order)'>
!
store: p value: v order: order
	<c: 'void __atomic_store_n(uint64_t *p, uint64_t v, int order)'>
!
lockFree: bytes pointer: ptr
	<c: 'bool __atomic_always_lock_free(size_t bytes, void *ptr)'>
!
create: p attributes: a start: entry argument: arg
	<c: 'int pthread_create(pthread_t *p, const pthread_attr_t *a, void *(*entry)(void *), void *arg)'>
!
join: thread result: result
	<c: 'int pthread_join(pthread_t thread, void **result)'>
!
sleep: duration remaining: remaining
	<c: 'int nanosleep(const struct timespec *duration, struct timespec *remaining)'>
!
firstBit: mask
	<c: 'int __builtin_ctzll(uint64_t mask)'>
! !

VMStruct subclass: #C4NativeCell
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'C4-NativeTests'!

!C4NativeCell class methodsFor: 'declaring'!
fields
	^#((edge0 uint64_t) (edge1 uint64_t) (scalar uint32_t))
! !

VMModule subclass: #C4NativeArena
	instanceVariableNames: 'native thread opened active epoch liveMask freeMask reusable generations roots cells bankMask request initialMask inserted garbage held stop'
	classVariableNames: 'CAPACITY ROOTS SLOTS RELAXED ACQUIRE RELEASE REQUESTED PARKED DONE'
	package: 'C4-NativeTests'!

!C4NativeArena class methodsFor: 'declaring'!
initialize
	CAPACITY := 64.
	ROOTS := 8.
	SLOTS := 2.
	RELAXED := 0.
	ACQUIRE := 2.
	RELEASE := 3.
	REQUESTED := 1.
	PARKED := 2.
	DONE := 3
!
declarations
	^#((native C4NativeCalls) (thread 'pthread_t[1]') (opened bool) (active bool)
		(epoch uint32_t) (liveMask uint64_t) (freeMask uint64_t)
		(reusable uint64_t 16rFFFFFFFFFFFFFFFF) (generations 'uint32_t[CAPACITY]')
		(roots 'uint64_t[ROOTS]') (cells 'C4NativeCell[128]')
		(bankMask uint64_t) (request 'uint64_t[1]') (initialMask uint64_t)
		(inserted uint64_t) (garbage uint64_t) (held 'uint64_t[1]') (stop 'uint64_t[1]'))
!
isSimulated
	^false
! !

!C4NativeArena methodsFor: 'lifecycle'!
open
	<function>
	<returns: 'uint32_t'>
	(opened or: [(native lockFree: 8 pointer: self null) not]) ifTrue: [^0].
	active := false.
	epoch := 0.
	liveMask := 0.
	bankMask := 0.
	freeMask := reusable.
	0 to: ROOTS - 1 do: [:i | native store: roots + i value: 0 order: RELAXED].
	native store: held value: 0 order: RELAXED.
	native store: stop value: 0 order: RELAXED.
	native store: request value: 0 order: RELAXED.
	(native create: thread attributes: self null start: (self functionPointer: #worker:) argument: self null) ~= 0 ifTrue: [^0].
	opened := true.
	^1
!
close
	<function>
	<returns: 'uint32_t'>
	opened ifFalse: [^0].
	native store: stop value: 1 order: RELEASE.
	(native join: (thread at: 0) result: self null) ~= 0 ifTrue: [^0].
	opened := false.
	^1
!
holdWorker: flag
	<function>
	<var: #flag type: 'uint32_t'>
	<returns: 'uint32_t'>
	opened ifFalse: [^0].
	native store: held value: flag order: RELEASE.
	^1
!
workerParked
	<function>
	<returns: 'uint32_t'>
	(opened and: [active and: [(native load: request order: ACQUIRE) = PARKED]]) ifTrue: [^1].
	^0
!
workerDone
	<function>
	<returns: 'uint32_t'>
	(opened and: [active and: [(native load: request order: ACQUIRE) = DONE]]) ifTrue: [^1].
	^0
!
nearEpochLimit
	"Test only: before the first cycle, there are no previous stamped words."
	<function>
	<returns: 'uint32_t'>
	(opened and: [epoch = 0]) ifFalse: [^0].
	epoch := 16rFFFFFFFE.
	^1
! !

!C4NativeArena methodsFor: 'mutator'!
capacity
	^CAPACITY
!
rootCount
	^ROOTS
!
slotCount
	^SLOTS
!
begin
	<function>
	<returns: 'uint32_t'>
	(opened not or: [active or: [epoch = 16rFFFFFFFF]]) ifTrue: [^0].
	initialMask := liveMask.
	inserted := 0.
	epoch := epoch + 1.
	active := true.
	native store: request value: REQUESTED order: RELEASE.
	^1
!
finish
	<function>
	<returns: 'uint32_t'>
	| dead |
	(opened and: [active and: [(native load: request order: ACQUIRE) = DONE]]) ifFalse: [^0].
	dead := garbage.
	"A client may try to resurrect a snapshot-white alias. Do not retire any of its possible descendants."
	(dead bitAnd: inserted) = 0 ifTrue: [
		liveMask := liveMask bitClear: dead.
		freeMask := freeMask bitOr: (dead bitAnd: reusable)].
	active := false.
	^1
!
allocationStatus
	"0 available, 1 no free cell now, 2 generation space spent, 3 closed."
	<function>
	<returns: 'uint32_t'>
	opened ifFalse: [^3].
	freeMask ~= 0 ifTrue: [^0].
	reusable = 0 ifTrue: [^2].
	^1
!
allocate: value
	<function>
	<var: #value type: 'uint32_t'>
	<returns: 'uint32_t'>
	| i bit g p |
	(opened not or: [freeMask = 0]) ifTrue: [^0].
	i := native firstBit: freeMask.
	bit := self bit: i.
	freeMask := freeMask bitClear: bit.
	g := (generations at: i) + 1.
	generations at: i put: g.
	g = 1023 ifTrue: [reusable := reusable bitClear: bit].
	p := self cell: i.
	p scalar: value.
	native store: (p fieldAddress: #edge0) value: 0 order: RELAXED.
	native store: (p fieldAddress: #edge1) value: 0 order: RELAXED.
	liveMask := liveMask bitOr: bit.
	^g * CAPACITY + i
!
live: ref
	<function>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	| i |
	(opened not or: [ref < CAPACITY or: [ref > 65535]]) ifTrue: [^0].
	i := self index: ref.
	((liveMask bitAnd: (self bit: i)) ~= 0 and: [(generations at: i) = (ref >> 6)])
		ifTrue: [^1].
	^0
!
rootAt: i
	<function>
	<var: #i type: 'uint32_t'>
	<returns: 'uint32_t'>
	(opened and: [i < ROOTS]) ifFalse: [^0].
	^self current: roots + i
!
rootAt: i put: ref
	<function>
	<var: #i type: 'uint32_t'>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	(opened and: [i < ROOTS]) ifFalse: [^0].
	^self write: roots + i ref: ref
!
slotAt: j of: owner
	<function>
	<var: #j type: 'uint32_t'>
	<var: #owner type: 'uint32_t'>
	<returns: 'uint32_t'>
	(j < SLOTS and: [(self live: owner) ~= 0]) ifFalse: [^0].
	^self current: (self slotWord: j index: (self index: owner))
!
slotAt: j of: owner put: ref
	<function>
	<var: #j type: 'uint32_t'>
	<var: #owner type: 'uint32_t'>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	(j < SLOTS and: [(self live: owner) ~= 0]) ifFalse: [^0].
	^self write: (self slotWord: j index: (self index: owner)) ref: ref
!
payloadOf: ref
	<function>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	(self live: ref) = 0 ifTrue: [^0].
	^(self cell: (self index: ref)) scalar
!
payloadOf: ref put: value
	<function>
	<var: #ref type: 'uint32_t'>
	<var: #value type: 'uint32_t'>
	<returns: 'uint32_t'>
	(self live: ref) = 0 ifTrue: [^0].
	(self cell: (self index: ref)) scalar: value.
	^1
! !

!C4NativeArena methodsFor: 'relocation'!
cellIndexOf: ref
	"Opaque physical ordinal for tests, never an address."
	<function>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	(self live: ref) = 0 ifTrue: [^0].
	^(self physicalIndex: (self index: ref)) + 1
!
relocate: ref
	<function>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	| i from to |
	(active or: [(self live: ref) = 0]) ifTrue: [^0].
	i := self physicalIndex: (self index: ref).
	from := cells + i.
	to := cells + (i bitXor: CAPACITY).
	to scalar: from scalar.
	native store: (to fieldAddress: #edge0) value: (self current: (from fieldAddress: #edge0)) order: RELAXED.
	native store: (to fieldAddress: #edge1) value: (self current: (from fieldAddress: #edge1)) order: RELAXED.
	bankMask := bankMask bitXor: (self bit: (self index: ref)).
	native store: (from fieldAddress: #edge0) value: 0 order: RELAXED.
	native store: (from fieldAddress: #edge1) value: 0 order: RELAXED.
	from scalar: 0.
	^1
! !

!C4NativeArena methodsFor: 'barriers'!
index: ref
	^ref bitAnd: 63
!
bit: i
	^16r8000000000000000 >> (63 - i)
!
physicalIndex: i
	^(bankMask bitAnd: (self bit: i)) = 0 ifTrue: [i] ifFalse: [i + CAPACITY]
!
cell: i
	^cells + (self physicalIndex: i)
!
slotWord: j index: i
	| p |
	p := self cell: i.
	^j = 0 ifTrue: [p fieldAddress: #edge0] ifFalse: [p fieldAddress: #edge1]
!
current: p
	^(native load: p order: RELAXED) bitAnd: 65535
!
write: p ref: ref
	<function>
	<var: #p type: 'uint64_t *'>
	<var: #ref type: 'uint32_t'>
	<returns: 'uint32_t'>
	| before old |
	(ref ~= 0 and: [(self live: ref) = 0]) ifTrue: [^0].
	active ifFalse: [
		native store: p value: ref order: RELAXED.
		^1].
	ref ~= 0 ifTrue: [inserted := inserted bitOr: (self bit: (self index: ref))].
	before := native load: p order: RELAXED.
	old := (before >> 32) = epoch
		ifTrue: [before bitAnd: 16rFFFFFFFFFFFF0000]
		ifFalse: [(epoch asUInt64 << 32) bitOr: ((before bitAnd: 65535) << 16)].
	native store: p value: (old bitOr: ref) order: RELAXED.
	^1
! !

!C4NativeArena methodsFor: 'collector'!
worker: unused
	<function>
	<var: #unused type: 'void *'>
	<returns: 'void *'>
	| delay state |
	delay := self local: 'struct timespec'.
	delay tv_nsec: 100000.
	[(native load: stop order: ACQUIRE) = 0] whileTrue: [
		state := native load: request order: ACQUIRE.
		(state = REQUESTED or: [state = PARKED]) ifTrue: [
			(native load: held order: ACQUIRE) = 0
				ifTrue: [
					garbage := self trace.
					native store: request value: DONE order: RELEASE]
				ifFalse: [state = REQUESTED ifTrue: [native store: request value: PARKED order: RELEASE]]].
		native sleep: delay remaining: self null].
	^self null
!
snapshotBit: p
	<function>
	<var: #p type: 'uint64_t *'>
	<returns: 'uint64_t'>
	| w ref i bit |
	w := native load: p order: RELAXED.
	ref := (((w >> 32) = epoch) ifTrue: [w >> 16] ifFalse: [w]) bitAnd: 65535.
	ref = 0 ifTrue: [^0].
	i := self index: ref.
	bit := self bit: i.
	"Only generation entries in the initial population may be read by the worker."
	((initialMask bitAnd: bit) ~= 0 and: [(generations at: i) = (ref >> 6)]) ifTrue: [^bit].
	^0
!
trace
	<function>
	<returns: 'uint64_t'>
	| pending seen i |
	pending := 0 asUInt64.
	seen := 0 asUInt64.
	0 to: ROOTS - 1 do: [:r | pending := pending bitOr: (self snapshotBit: roots + r)].
	[pending ~= 0] whileTrue: [
		i := native firstBit: pending.
		seen := seen bitOr: (self bit: i).
		pending := (pending bitOr: (self snapshotBit: (self slotWord: 0 index: i)))
			bitOr: (self snapshotBit: (self slotWord: 1 index: i)).
		pending := pending bitClear: seen].
	^initialMask bitClear: seen
! !
