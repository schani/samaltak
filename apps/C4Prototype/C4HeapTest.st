TestCase subclass: #C4HeapTest
	instanceVariableNames: 'heap'
	classVariableNames: ''
	package: 'C4Prototype'!

C4HeapTest comment: 'Deterministic mutator schedules against the cooperative collector.

	tests/st_suite.sh build/runtime.image -- C4HeapTest --load apps/C4Prototype'!

!C4HeapTest methodsFor: 'fixtures'!
setUp
	heap := C4Heap new
!
advanceTo: goal within: limit
	| steps |
	steps := 0.
	[heap phase ~= goal and: [steps < limit]] whileTrue: [
		self assert: heap step description: ['Collector became idle before ', goal printString].
		steps := steps + 1].
	self assert: heap phase = goal description: ['Collector did not reach ', goal printString].
	^steps
!
collect
	heap startCycle.
	self advanceTo: #idle within: 1000.
	self deny: heap step
!
assertCurrent: ref
	self assert: ref epoch equals: heap epoch.
	self assert: (heap resolve: ref) equals: ref
!
assertCycleWithSharing
	| a b c alias |
	a := heap rootAt: #a.
	b := heap at: a slot: 1.
	c := heap at: a slot: 2.
	alias := heap at: b slot: 2.
	self assertCurrent: a.
	self assertCurrent: b.
	self assertCurrent: c.
	self deny: a = b.
	self deny: b = c.
	self deny: a = c.
	self assert: (heap at: b slot: 1) equals: a.
	self assert: alias equals: c.
	self assert: alias hash equals: c hash.
	self assert: ({c} asSet includes: alias).
	self assert: (heap at: c slot: 1) equals: c.
	self assert: (heap at: c slot: 2) isNil
! !

!C4HeapTest methodsFor: 'tests'!
testEmptyCyclesAndInvalidReferences
	| local foreign |
	self assert: heap phase equals: #idle.
	self assert: heap epoch equals: 0.
	self deny: heap step.
	self assert: (heap resolve: nil) isNil.
	self assert: (heap rootAt: #missing) isNil.
	2 timesRepeat: [self collect].
	self assert: heap epoch equals: 2.
	self assert: heap objectCount equals: 0.

	local := heap allocate: 1.
	foreign := C4Heap new allocate: 1.
	self assert: (heap at: local slot: 1) isNil.
	self should: [heap allocate: -1] raise: Error.
	self should: [heap at: local slot: 0] raise: Error.
	self should: [heap at: local slot: 2 put: nil] raise: Error.
	self should: [heap resolve: foreign] raise: Error.
	self should: [heap rootAt: #foreign put: foreign] raise: Error.
	self should: [heap at: local slot: 1 put: foreign] raise: Error.
	self assert: (heap at: local slot: 1) isNil.
	self assert: (heap rootAt: #foreign) isNil.
	self assert: heap objectCount equals: 1
!
testCyclesSharingAndReclamation
	| a b c dead1 dead2 hashA hashC root shared |
	a := heap allocate: 2.
	b := heap allocate: 2.
	c := heap allocate: 2.
	heap rootAt: #a put: a.
	heap at: a slot: 1 put: b.
	heap at: a slot: 2 put: c.
	heap at: b slot: 1 put: a.
	heap at: b slot: 2 put: c.
	heap at: c slot: 1 put: c.
	dead1 := heap allocate: 1.
	dead2 := heap allocate: 1.
	heap at: dead1 slot: 1 put: dead2.
	heap at: dead2 slot: 1 put: dead1.

	hashA := heap identityHashOf: a.
	hashC := heap identityHashOf: c.
	self assert: heap objectCount equals: 5.
	5 timesRepeat: [
		self collect.
		self assert: heap objectCount equals: 3.
		self assertCycleWithSharing.
		root := heap rootAt: #a.
		shared := heap at: root slot: 2.
		self assert: (heap identityHashOf: root) equals: hashA.
		self assert: (heap identityHashOf: shared) equals: hashC].
	self should: [heap resolve: dead1] raise: Error.
	self should: [heap resolve: dead2] raise: Error.

	heap removeRoot: #a.
	self assert: (heap rootAt: #a) isNil.
	self collect.
	self assert: heap objectCount equals: 0
!
testReusedAddressesRejectOldIncarnations
	| retired fresh old reused |
	retired := Dictionary new.
	reused := false.
	12 timesRepeat: [
		fresh := Array new: 6.
		1 to: fresh size do: [:index |
			old := heap allocate: 1.
			fresh at: index put: old.
			retired at: old address ifPresent: [:previous |
				reused := true.
				self deny: old = previous.
				self should: [heap resolve: previous] raise: Error.
				self should: [heap at: previous slot: 1 put: old] raise: Error].
			self assert: (heap at: old slot: 1) isNil].
		self assert: heap objectCount equals: fresh size.
		self collect.
		self assert: heap objectCount equals: 0.
		fresh do: [:dead |
			self should: [heap resolve: dead] raise: Error.
			retired at: dead address put: dead]].
	self assert: reused description: 'Addresses were never recycled'
!
testInsertingEdgesIntoPartiallyScannedObject
	| head left right leaf current |
	head := heap allocate: 64.
	left := heap allocate: 1.
	right := heap allocate: 1.
	leaf := heap allocate: 0.
	heap at: left slot: 1 put: leaf.
	heap at: right slot: 1 put: leaf.
	heap rootAt: #head put: head.

	heap startCycle.
	32 timesRepeat: [self assert: heap step].
	self assert: heap phase equals: #mark.
	"Write into both ends of the object, straddling the marking cursor."
	heap at: head slot: 1 put: left.
	heap at: head slot: 64 put: right.
	self advanceTo: #idle within: 1000.

	current := heap rootAt: #head.
	left := heap at: current slot: 1.
	right := heap at: current slot: 64.
	self deny: left = right.
	leaf := heap at: left slot: 1.
	self assertCurrent: leaf.
	self assert: (heap at: right slot: 1) equals: leaf.
	self assert: heap objectCount equals: 4
!
testAllocationsSurviveOnlyTheirActiveCycle
	| head markNew moveNew healNew retireNew |
	head := heap allocate: 16.
	heap rootAt: #head put: head.
	heap startCycle.
	markNew := heap allocate: 1.
	self advanceTo: #move within: 1000.
	moveNew := heap allocate: 1.
	self advanceTo: #heal within: 1000.
	healNew := heap allocate: 1.
	self advanceTo: #retire within: 1000.
	retireNew := heap allocate: 1.
	self advanceTo: #idle within: 1000.

	self assert: heap objectCount equals: 5.
	{markNew. moveNew. healNew. retireNew} do: [:ref |
		self assert: (heap at: ref slot: 1) isNil].
	self collect.
	self assert: heap objectCount equals: 1.
	{markNew. moveNew. healNew. retireNew} do: [:ref |
		self should: [heap resolve: ref] raise: Error]
!
testLateBarriersKeepLiveNodesAndRejectWhiteOnes
	| head live dead stored root child |
	head := heap allocate: 1.
	live := heap allocate: 1.
	dead := heap allocate: 1.
	heap rootAt: #head put: head.
	heap rootAt: #live put: live.

	heap startCycle.
	self advanceTo: #move within: 1000.
	"Reinsert a marked node, but do not resurrect white objects after marking."
	heap removeRoot: #live.
	self assert: (heap at: head slot: 1 put: live) equals: (heap resolve: live).
	self should: [heap rootAt: #head put: dead] raise: Error.
	self should: [heap at: head slot: 1 put: dead] raise: Error.
	self should: [heap at: dead slot: 1] raise: Error.
	self should: [heap at: dead slot: 1 put: live] raise: Error.
	self should: [heap identityHashOf: dead] raise: Error.
	self should: [heap resolve: dead] raise: Error.
	self assert: heap objectCount equals: 3.

	self advanceTo: #heal within: 1000.
	"Remove the pending root before the collector visits it; publish through an old alias."
	heap removeRoot: #head.
	stored := heap rootAt: #replacement put: head.
	self assertCurrent: stored.
	self deny: stored = head.

	self advanceTo: #retire within: 1000.
	heap removeRoot: #replacement.
	heap rootAt: #final put: head.
	self assert: (heap at: live slot: 1 put: head) equals: stored.
	self advanceTo: #idle within: 1000.
	self assert: (heap rootAt: #head) isNil.
	self assert: (heap rootAt: #replacement) isNil.
	root := heap rootAt: #final.
	self assert: root equals: stored.
	child := heap at: root slot: 1.
	self assertCurrent: child.
	self assert: (heap at: child slot: 1) equals: root.
	self assert: heap objectCount equals: 2.
	heap removeRoot: #final.
	self collect.
	self assert: heap objectCount equals: 0
!
testLoadsFollowForwardingBeforeHealing
	| a b hashA hashB movedA movedB old new receiver key oldHash steps |
	a := heap allocate: 1.
	b := heap allocate: 1.
	heap at: a slot: 1 put: b.
	heap at: b slot: 1 put: a.
	heap rootAt: #a put: a.
	heap rootAt: #b put: b.
	hashA := heap identityHashOf: a.
	hashB := heap identityHashOf: b.

	heap startCycle.
	self advanceTo: #move within: 1000.
	movedA := a.
	movedB := b.
	steps := 0.
	[movedA = a and: [movedB = b and: [steps < 100]]] whileTrue: [
		self assert: heap step.
		movedA := heap resolve: a.
		movedB := heap resolve: b.
		steps := steps + 1].
	self assert: heap phase equals: #move.
	movedA = a
		ifTrue: [old := b. new := movedB. receiver := a. key := #b. oldHash := hashB]
		ifFalse: [old := a. new := movedA. receiver := b. key := #a. oldHash := hashA].
	self deny: old = new.
	self assert: (heap resolve: receiver) equals: receiver.
	self assert: (heap rootAt: key) equals: new.
	self assert: (heap at: receiver slot: 1) equals: new.
	self assert: (heap at: old slot: 1) equals: receiver.
	self assert: (heap identityHashOf: old) equals: oldHash.
	self assert: (heap identityHashOf: new) equals: oldHash.
	self advanceTo: #idle within: 1000
!
testForwardingExpiresOnReuseAndNextCycle
	| a b movedA movedB newA newB current |
	a := heap allocate: 1.
	b := heap allocate: 1.
	heap at: a slot: 1 put: b.
	heap at: b slot: 1 put: a.
	heap rootAt: #a put: a.
	self collect.

	movedA := heap resolve: a.
	movedB := heap resolve: b.
	self assertCurrent: movedA.
	self assertCurrent: movedB.
	self deny: a = movedA.
	self deny: b = movedB.

	"Recycle both source addresses before any mutator reads the managed roots or slots."
	newA := heap allocate: 1.
	newB := heap allocate: 1.
	self assert: ({newA address. newB address} asSet) equals: ({a address. b address} asSet).
	self should: [heap resolve: a] raise: Error.
	self should: [heap resolve: b] raise: Error.
	self assert: (heap rootAt: #a) equals: movedA.
	self assert: (heap at: movedA slot: 1) equals: movedB.
	self assert: (heap at: movedB slot: 1) equals: movedA.
	self assert: (heap at: newA slot: 1) isNil.
	self assert: (heap at: newB slot: 1) isNil.

	self collect.
	current := heap rootAt: #a.
	self assert: (heap resolve: movedA) equals: current.
	self assert: heap objectCount equals: 2.
	heap startCycle.
	self should: [heap resolve: movedA] raise: Error.
	self advanceTo: #idle within: 1000.
	self assert: heap objectCount equals: 2
!
testLargeObjectStepsAndWritesAcrossCopyCursor
	| width half limit head target markSteps moveSteps healSteps current |
	width := 4096.
	half := width // 2.
	limit := width * 2.
	head := heap allocate: width.
	target := heap allocate: 0.
	1 to: width do: [:index | heap at: head slot: index put: head].
	heap rootAt: #head put: head.
	heap rootAt: #target put: target.

	heap startCycle.
	markSteps := self advanceTo: #move within: limit.
	self assert: markSteps >= width description: 'Marking batched slots'.
	half timesRepeat: [self assert: heap step].
	self assert: heap phase equals: #move.
	self assert: (heap resolve: head) equals: head.
	"Overwrite a copied slot and a slot that still lives in the source."
	heap at: head slot: 1 put: nil.
	heap at: head slot: width put: target.
	self assert: (heap at: head slot: 1) isNil.
	self assert: (heap at: head slot: width) equals: (heap resolve: target).
	moveSteps := half + (self advanceTo: #heal within: limit - half).
	self assert: moveSteps >= width description: 'Moving batched slots'.

	current := heap resolve: head.
	self assertCurrent: current.
	self deny: current = head.
	half timesRepeat: [self assert: heap step].
	self assert: heap phase equals: #heal.
	heap at: head slot: 2 put: target.
	heap at: current slot: width - 1 put: nil.
	healSteps := half + (self advanceTo: #retire within: limit - half).
	self assert: healSteps >= width description: 'Healing batched slots'.
	self advanceTo: #idle within: 1000.

	target := heap rootAt: #target.
	self assert: (heap rootAt: #head) equals: current.
	self assert: (heap at: current slot: 1) isNil.
	self assert: (heap at: current slot: 2) equals: target.
	3 to: width - 2 do: [:index |
		self assert: (heap at: current slot: index) equals: current].
	self assert: (heap at: current slot: width - 1) isNil.
	self assert: (heap at: current slot: width) equals: target.
	self assert: heap objectCount equals: 2
! !
