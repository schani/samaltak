TestCase subclass: #BecomeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

BecomeTest comment: 'Tests becomeForward: (the target takes over the identity hash). Most objects become forwarders (lazily): references to them reach the target through sends, ==, class, primitives that retry, blocks and the collector; classes, methods, Contexts and the other kinds the VM reads directly are replaced by a heap scan at once.'!

Object subclass: #BecomeTestSubject
	instanceVariableNames: 'value'
	classVariableNames: ''
	package: 'Tests-Kernel'!

BecomeTestSubject comment: 'I am what BecomeTest forwards: a value, and a block that answers it.'!

!BecomeTestSubject class methodsFor: 'instance creation'!
value: anObject
	^self new setValue: anObject
! !

!BecomeTestSubject methodsFor: 'accessing'!
setValue: anObject
	value := anObject
!
value
	^value
!
valueBlock
	^[value]
! !

!BecomeTest methodsFor: 'tests'!
testHeapReferences
	| a b holder |
	a := Array with: 1.
	b := Array with: 2.
	holder := Array with: a with: a.
	a becomeForward: b.
	self assert: (holder at: 1) first = 2.
	self assert: (holder at: 2) == b.
	self assert: a == b
!
testIdentity
	| x y holder |
	x := Object new.
	y := Object new.
	holder := Array with: x.
	x becomeForward: y.
	self assert: holder first == y.
	self deny: holder first ~~ y.
	self assert: y == holder first.
	self assert: (holder first == holder first).
	self assert: (holder includes: y)
!
testIdentityHash
	| x y hash set |
	x := Object new.
	y := Object new.
	hash := x identityHash.
	set := IdentitySet with: x.
	x becomeForward: y.
	self assert: y identityHash = hash.
	self assert: (set includes: y).
	self assert: (set includes: x)
!
testIdentityHashEager
	| a b hash dict |
	a := #a -> 1.
	b := #b -> 2.
	hash := a identityHash.
	dict := IdentityDictionary new.
	dict at: a put: #found.
	a becomeForward: b.
	self assert: b identityHash = hash.
	self assert: (dict at: b ifAbsent: [nil]) = #found
!
testClassAndSends
	| x y holder |
	x := OrderedCollection with: 1.
	y := Set with: 7 with: 8.
	holder := Array with: x.
	x becomeForward: y.
	self assert: holder first class == Set.
	self assert: holder first size = 2.
	self assert: (holder first includes: 8).
	self assert: (holder first perform: #size) = 2.
	self assert: (holder first respondsTo: #remove:)
!
testPrimitiveArguments
	| s t holder target |
	s := 'abc' copy.
	t := 'xyz' copy.
	holder := Array with: s.
	s becomeForward: t.
	self assert: 'xyz' = holder first.
	self assert: holder first = 'xyz'.
	target := String new: 3.
	target replaceFrom: 1 to: 3 with: holder first startingAt: 1.
	self assert: target = 'xyz'
!
testBlockReceiver
	| a b blk |
	a := BecomeTestSubject value: 1.
	b := BecomeTestSubject value: 2.
	blk := a valueBlock.
	a becomeForward: b.
	self assert: blk value = 2
!
testChain
	| a b c holder |
	a := Array with: 1.
	b := Array with: 2.
	c := Array with: 3.
	holder := Array with: a with: b.
	a becomeForward: b.
	b becomeForward: c.
	self assert: (holder at: 1) first = 3.
	self assert: (holder at: 1) == (holder at: 2).
	self assert: (holder at: 1) == c
!
testOldObjects
	| a b holder |
	a := Array with: 1.
	holder := Array with: a.
	Smalltalk vm garbageCollect.
	b := Array with: 2.
	a becomeForward: b.
	self assert: holder first first = 2.
	Smalltalk vm scavenge.
	self assert: holder first first = 2.
	self assert: holder first == b.
	Smalltalk vm garbageCollect.
	self assert: holder first first = 2.
	self assert: holder first == b
!
testAcrossCollections
	| a b holder |
	a := Array with: 1.
	b := Array with: 2.
	holder := Array with: a.
	a becomeForward: b.
	Smalltalk vm scavenge.
	self assert: holder first == b.
	Smalltalk vm garbageCollect.
	self assert: holder first == b.
	self assert: holder first first = 2
!
testWeakReferences
	| a b weak |
	a := Array with: 1.
	b := Array with: 2.
	weak := WeakArray with: a.
	a becomeForward: b.
	Smalltalk vm scavenge.
	self assert: weak first == b.
	Smalltalk vm garbageCollect.
	self assert: weak first == b
!
testManyInALoop
	| holders sum |
	holders := (1 to: 200) collect: [:i | Array with: i].
	holders do: [:h | h becomeForward: (Array with: h first * 2)].
	sum := 0.
	holders do: [:h | sum := sum + h first].
	self assert: sum = (((1 to: 200) inject: 0 into: [:s :i | s + i]) * 2)
!
testReceiverInItsMethod
	| s holder |
	s := 'abc' copy.
	holder := Array with: s.
	s at: 2 put: (Character value: 955).
	self assert: holder first class == WideString.
	self assert: holder first = (String with: $a with: (Character value: 955) with: $c)
!
testOptimizedFrameHoldingIt
	"Optimized code knows the class of what it allocated: after the become it must not read the Array's fields."
	1 to: 3000 do: [:i | self assert: self allocateForwardAndRead = 11]
!
allocateForwardAndRead
	| a |
	a := Array with: 1 with: 2.
	a becomeForward: (OrderedCollection with: 10).
	^a first + a size
!
testEagerKinds
	| assoc holder |
	assoc := #a -> 1.
	holder := Array with: assoc.
	assoc becomeForward: #b -> 2.
	self assert: holder first key == #b.
	self assert: holder first value = 2
! !
