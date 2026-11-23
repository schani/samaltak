Object subclass: #C4Heap
	instanceVariableNames: 'owner epoch phase roots rootHead rootCursor objects count cycleHead objectCursor slotCursor gray tracing free pending pendingTail highAddress'
	classVariableNames: ''
	package: 'C4Prototype'!

C4Heap comment: 'An explicit, cooperative C4-style heap. Use only my public allocation, barrier and cycle messages. Smalltalk locals are not roots. See README.md for the interleaving and forwarding rules.'!

!C4Heap methodsFor: 'initialization'!
initialize
	super initialize.
	owner := Object new.
	epoch := highAddress := count := 0.
	phase := #idle.
	roots := Dictionary new
! !

!C4Heap methodsFor: 'allocation'!
allocate: slotCount
	| entry |
	(slotCount isInteger and: [slotCount >= 0]) ifFalse: [self error: 'Invalid slot count'].
	entry := C4Object new initializeSlots: slotCount.
	entry mark: epoch.
	entry insertBefore: objects.
	objects := entry.
	count := count + 1.
	^self locate: entry
! !

!C4Heap methodsFor: 'barriers'!
resolve: ref
	"Validate the incarnation, follow forwarding, and shade during marking."
	ref isNil ifTrue: [^nil].
	^(self entryFor: ref) reference
!
identityHashOf: ref
	"Hash the logical resident, not its changing colored address."
	^(self entryFor: ref) identityHash
!
at: ref slot: index
	| entry value healed |
	entry := self entryFor: ref.
	value := entry slotAt: index.
	healed := self resolve: value.
	healed == value ifFalse: [entry slotAt: index put: healed].
	^healed
!
at: ref slot: index put: value
	| entry |
	entry := self entryFor: ref.
	^entry slotAt: index put: (self resolve: value)
!
rootAt: key
	| root healed |
	root := roots at: key ifAbsent: [^nil].
	healed := self resolve: root value.
	root value: healed.
	^healed
!
rootAt: key put: value
	| root canonical |
	value isNil ifTrue: [^self removeRoot: key].
	canonical := self resolve: value.
	root := roots at: key ifAbsentPut: [
		| newRoot |
		newRoot := C4Root new.
		newRoot insertBefore: rootHead.
		rootHead := newRoot].
	root value: canonical.
	^canonical
!
removeRoot: key
	| root |
	root := roots removeKey: key ifAbsent: [^nil].
	root == rootCursor ifTrue: [rootCursor := root next].
	root == rootHead ifTrue: [rootHead := root next].
	root unlink.
	^nil
! !

!C4Heap methodsFor: 'cycling'!
epoch
	^epoch
!
phase
	^phase
!
objectCount
	^count
!
startCycle
	phase == #idle ifFalse: [self error: 'Collection already active'].
	epoch := epoch + 1.
	cycleHead := objects.
	rootCursor := rootHead.
	phase := #mark
!
step
	"Inspect or transfer at most one logical slot (a root counts as a slot)."
	phase == #idle ifTrue: [^false].
	phase == #mark ifTrue: [self markStep. ^true].
	phase == #move ifTrue: [self moveStep. ^true].
	phase == #heal ifTrue: [self healStep. ^true].
	self retireStep.
	^true
! !

!C4Heap methodsFor: 'private - addressing'!
locate: entry
	| location |
	free isNil
		ifTrue: [
			highAddress := highAddress + 1.
			location := C4Location new address: highAddress owner: owner]
		ifFalse: [
			location := free.
			free := free nextFree].
	^location install: entry epoch: epoch
!
entryFor: ref
	| location entry |
	ref class == C4Ref ifFalse: [self error: 'Expected a C4 reference'].
	location := ref location.
	location owner == owner ifFalse: [self error: 'Foreign C4 reference'].
	entry := location entryFor: ref epoch: epoch.
	entry isNil ifTrue: [self error: 'Stale C4 reference'].
	phase == #mark
		ifTrue: [self shade: entry]
		ifFalse: [
			(phase ~= #idle and: [entry mark ~= epoch]) ifTrue: [
				self error: 'Unreachable C4 reference after marking']].
	^entry
!
quarantine: location
	"Keep sources unavailable for reuse until all managed slots are healed."
	pending isNil ifTrue: [pendingTail := location].
	location nextFree: pending.
	pending := location
! !

!C4Heap methodsFor: 'private - steps'!
shade: entry
	entry mark = epoch ifTrue: [^self].
	entry mark: epoch.
	entry grayNext: gray.
	gray := entry
!
markStep
	rootCursor notNil ifTrue: [
		self resolve: rootCursor value.
		rootCursor := rootCursor next.
		^self].
	tracing notNil ifTrue: [
		slotCursor <= tracing size
			ifTrue: [
				self resolve: (tracing slotAt: slotCursor).
				slotCursor := slotCursor + 1]
			ifFalse: [tracing := nil].
		^self].
	gray notNil ifTrue: [
		tracing := gray.
		gray := tracing grayNext.
		tracing grayNext: nil.
		slotCursor := 1.
		^self].
	objectCursor := cycleHead.
	phase := #move
!
moveStep
	| oldRef newRef |
	objectCursor isNil ifTrue: [
		objectCursor := objects.
		rootCursor := rootHead.
		slotCursor := 1.
		phase := #heal.
		^self].
	objectCursor mark = epoch ifTrue: [
		objectCursor copyComplete ifFalse: [objectCursor copySlot. ^self].
		oldRef := objectCursor reference.
		objectCursor finishCopy.
		newRef := self locate: objectCursor.
		oldRef location forward: oldRef to: newRef.
		self quarantine: oldRef location].
	objectCursor := objectCursor next
!
healStep
	| value healed |
	rootCursor notNil ifTrue: [
		rootCursor value: (self resolve: rootCursor value).
		rootCursor := rootCursor next.
		^self].
	objectCursor isNil ifTrue: [
		objectCursor := cycleHead.
		phase := #retire.
		^self].
	(objectCursor mark = epoch and: [slotCursor <= objectCursor size]) ifTrue: [
		value := objectCursor slotAt: slotCursor.
		healed := self resolve: value.
		healed == value ifFalse: [objectCursor slotAt: slotCursor put: healed].
		slotCursor := slotCursor + 1.
		^self].
	objectCursor := objectCursor next.
	slotCursor := 1
!
retireStep
	| entry location |
	objectCursor isNil ifTrue: [
		pending notNil ifTrue: [
			pendingTail nextFree: free.
			free := pending.
			pending := pendingTail := nil].
		cycleHead := nil.
		phase := #idle.
		^self].
	entry := objectCursor.
	objectCursor := entry next.
	entry mark = epoch ifFalse: [
		entry == objects ifTrue: [objects := entry next].
		entry unlink.
		location := entry reference location.
		location discard.
		self quarantine: location.
		count := count - 1]
! !
