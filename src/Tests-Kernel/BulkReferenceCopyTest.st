TestCase subclass: #BulkReferenceCopyTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

WeakArray weakSubclass: #BulkReferenceWeakArray
	instanceVariableNames: 'tag'
	classVariableNames: ''
	package: 'Tests-Kernel'!

ArrayedCollection variableDoubleWordSubclass: #BulkReferenceWordArray
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

!BulkReferenceWeakArray methodsFor: 'accessing'!
tag
	^tag
!
tag: anObject
	tag := anObject
! !

!BulkReferenceCopyTest methodsFor: 'tests'!
testReplaceKeepsYoungObjectsReachableFromOldArray
	| old source |
	old := #(left nil nil nil right) copy.
	Smalltalk vm garbageCollect.
	source := {#skip. Array with: 11. 7. Array with: 22}.
	old replaceFrom: 2 to: 4 with: source startingAt: 2.
	source := nil.
	"The copied slots are now the only strong references to the two young Arrays."
	Smalltalk vm scavenge.
	self assert: old equals: #(left (11) 7 (22) right).
	Smalltalk vm garbageCollect.
	self assert: old equals: #(left (11) 7 (22) right)
!
testOverlappingSelfReplaceInBothDirections
	| array |
	array := {#left. Array with: 1. Array with: 2. Array with: 3. Array with: 4. #right}.
	array replaceFrom: 3 to: 5 with: array startingAt: 2.
	Smalltalk vm scavenge.
	self assert: array equals: #(left (1) (1) (2) (3) right).
	array replaceFrom: 2 to: 4 with: array startingAt: 3.
	Smalltalk vm garbageCollect.
	self assert: array equals: #(left (1) (2) (3) (3) right)
!
testReplaceIntoOldWeakArray
	| old source kept |
	old := WeakArray new: 3.
	Smalltalk vm garbageCollect.
	kept := Array with: #kept.
	source := BulkReferenceWeakArray new: 3.
	source tag: #notAnElement; at: 1 put: (Array with: #dead); at: 2 put: kept; at: 3 put: 42.
	old replaceFrom: 1 to: 3 with: source startingAt: 1.
	source := nil.
	Smalltalk vm scavenge; scavenge.
	self assert: (old at: 1) isNil.
	self assert: (old at: 2) == kept.
	self assert: (old at: 3) equals: 42.
	kept := nil.
	Smalltalk vm garbageCollect.
	self assert: (old at: 2) isNil
!
testShallowCopyKeepsFixedFieldStrongAndIndexedFieldsWeak
	| source clone |
	source := BulkReferenceWeakArray new: 2.
	source tag: (Array with: #strong).
	source replaceFrom: 1 to: 2 with: {source tag. Array with: #dead} startingAt: 1.
	clone := source shallowCopy.
	self deny: clone == source.
	source := nil.
	Smalltalk vm scavenge.
	self assert: clone class == BulkReferenceWeakArray.
	self assert: clone tag equals: #(strong).
	self assert: (clone at: 1) == clone tag.
	self assert: (clone at: 2) isNil.
	clone tag: nil.
	Smalltalk vm garbageCollect.
	self assert: (clone at: 1) isNil
!
testRawDoubleWordReplaceAndShallowCopy
	| source target clone words |
	words := #(16rFFFFFFFFFFFFFFFF 16r0123456789ABCDEF).
	source := BulkReferenceWordArray with: 1 with: words first with: words last.
	target := BulkReferenceWordArray with: 2 with: 3 with: 4 with: 5.
	target replaceFrom: 2 to: 3 with: source startingAt: 2.
	clone := target shallowCopy.
	target at: 2 put: 0.
	Smalltalk vm garbageCollect.
	self assert: clone class == BulkReferenceWordArray.
	self assert: clone asArray equals: #(2 16rFFFFFFFFFFFFFFFF 16r0123456789ABCDEF 5)
! !
