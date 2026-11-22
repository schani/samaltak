TestCase subclass: #C4MarkTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'C4-MarkTests'!

WeakArray weakSubclass: #C4MarkWeak
	instanceVariableNames: 'strong'
	classVariableNames: ''
	package: 'C4-MarkTests'!

ArrayedCollection variableDoubleWordSubclass: #C4MarkWords
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'C4-MarkTests'!

!C4MarkWeak methodsFor: 'accessing'!
strong
	^strong
!
strong: anObject
	strong := anObject
! !

!C4MarkTest methodsFor: 'tests'!
testContextStrongPrefix
	| ctx refs |
	ctx := Context basicNew: 4.
	ctx stackp: 1.
	ctx basicAt: 1 put: (Array with: #live).
	Smalltalk vm scavenge.
	ctx basicAt: 4 put: (Array with: #stale).
	refs := WeakArray new: 2.
	refs at: 1 put: (ctx basicAt: 1); at: 2 put: (ctx basicAt: 4).
	Smalltalk vm garbageCollect.
	self assert: (ctx basicAt: 1) equals: #(live).
	self assert: (refs at: 1) == (ctx basicAt: 1).
	self assert: (refs at: 2) isNil.
	self assert: (ctx basicAt: 4) isNil
!
testWeakNamedFieldAndScalarWord
	| refs words |
	refs := C4MarkWeak new: 2.
	refs strong: (Array with: #strong).
	refs at: 1 put: refs strong; at: 2 put: (Array with: #weak).
	words := C4MarkWords new: 1.
	words basicAt: 1 put: 16r1000.
	Smalltalk vm garbageCollect.
	self assert: refs strong equals: #(strong).
	self assert: (refs at: 1) == refs strong.
	self assert: (refs at: 2) isNil.
	self assert: (words basicAt: 1) equals: 16r1000
! !

JitRuntimeTest subclass: #C4MarkBaselineTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'C4-MarkTests'!

!C4MarkBaselineTest class methodsFor: 'accessing'!
testSelectors
	^#(testBecomeOfAnEmbeddedLiteral)
! !

JitOptRuntimeTest subclass: #C4MarkOptTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'C4-MarkTests'!

!C4MarkOptTest class methodsFor: 'accessing'!
testSelectors
	^#(testDoublesAcrossSendsThatCollect)
! !
