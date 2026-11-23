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
testFoldedConstant
	"Optimized code that folded a literal's class sees the class of what the literal was forwarded to."
	| subject literal |
	BecomeTestSubject compile: 'literalsClass ^#(1 2) class' classified: 'tests'.
	[subject := BecomeTestSubject new.
	1 to: 3000 do: [:i | subject literalsClass].
	literal := (BecomeTestSubject >> #literalsClass) literals detect: [:each | each class == Array].
	literal becomeForward: (OrderedCollection with: 1).
	self assert: subject literalsClass == OrderedCollection]
		ensure: [BecomeTestSubject removeSelector: #literalsClass]
!
testPolymorphicSendToIt
	"Optimized code that switches on the receiver's class must not take a forwarder for an instance of its target's class."
	| holder |
	1 to: 3000 do: [:i | self sizeOf: (i odd ifTrue: ['abc' copy] ifFalse: ['abc' asWideString])].
	holder := Array with: 'ab' copy.
	holder first becomeForward: 'abcde' asWideString.
	self assert: (self sizeOf: holder first) = 5
!
sizeOf: x
	"x lives longest: optimized code keeps it in its slot, from where each switch on its class reads it."
	| a b c |
	a := self identityHash.
	b := a + 1.
	c := a + 2.
	^x size + a + b + c - (a + b + c) + (x size * 0)
!
testEqualityWithIt
	"Optimized code follows a forwarder to compare it with ==, but what it holds afterwards is still the forwarder: String>>= checks == first, then sends size to its argument."
	| wide holder |
	wide := 'abcdef' asWideString.
	1 to: 5000 do: [:i |
		self is: (i \\ 3 = 0 ifTrue: ['abcdef' copy] ifFalse: [wide])
			equalTo: (i odd ifTrue: ['abcdef' asWideString] ifFalse: [i \\ 4 = 0 ifTrue: ['abcdef' copy] ifFalse: [#abcdef]])].
	holder := Array with: 'abcdef' asWideString.
	holder first becomeForward: 'abcdef' asWideString.
	self assert: (self is: wide equalTo: holder first)
!
is: a equalTo: b
	^a = b
!
testForwardedLiteralArray
	"A method's literal Array forwarded: cached quick and ordinary activations of the method answer the new literals (in the interpreter: machine code keeps the literals it embedded)."
	| subject mode literals |
	mode := Smalltalk vm jitMode: #none.
	BecomeTestSubject compile: 'quickLiteral ^#old' classified: 'tests'.
	BecomeTestSubject compile: 'literal ^#(#old) first' classified: 'tests'.
	BecomeTestSubject compile: 'quickInteger ^40000' classified: 'tests'.
	[subject := BecomeTestSubject new.
	3 timesRepeat: [subject quickLiteral. subject literal. subject quickInteger].
	#(#quickLiteral #literal #quickInteger) do: [:sel |
		literals := (BecomeTestSubject >> sel) literals.
		literals becomeForward: (literals collect: [:each |
			each == #old ifTrue: [#new] ifFalse: [each = #(#old) ifTrue: [#(#new)] ifFalse: [each = 40000 ifTrue: [40001] ifFalse: [each]]]])].
	self assert: subject quickLiteral == #new.
	self assert: subject literal == #new.
	self assert: subject quickInteger = 40001]
		ensure: [
			BecomeTestSubject removeSelector: #quickLiteral; removeSelector: #literal; removeSelector: #quickInteger.
			Smalltalk vm jitMode: mode]
!
testEagerKinds
	| assoc holder |
	assoc := #a -> 1.
	holder := Array with: assoc.
	assoc becomeForward: #b -> 2.
	self assert: holder first key == #b.
	self assert: holder first value = 2
! !
