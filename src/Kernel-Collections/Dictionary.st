HashedCollection subclass: #Dictionary
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Dictionary comment: 'I map keys to values. I store Associations in my hash table, at the slot of their key (compared with = and hash); associationAt: answers the stored Association itself, which compiled methods share for globals and class variables. Enumeration (do:, collect:, select:) is over the values.'!

!Dictionary methodsFor: 'accessing'!
at: key
	^self at: key ifAbsent: [self errorKeyNotFound: key]
!
at: key ifAbsent: aBlock
	| assoc |
	assoc := array at: (self scanFor: key).
	assoc isNil ifTrue: [^aBlock value].
	^assoc value
!
at: key put: anObject
	| index assoc |
	index := self scanFor: key.
	assoc := array at: index.
	assoc isNil
		ifTrue: [self atNewIndex: index put: (Association key: key value: anObject)]
		ifFalse: [assoc value: anObject].
	^anObject
!
at: key ifAbsentPut: aBlock
	^self at: key ifAbsent: [self at: key put: aBlock value]
!
at: key ifPresent: aBlock
	| assoc |
	assoc := array at: (self scanFor: key).
	assoc isNil ifTrue: [^nil].
	^aBlock cull: assoc value
!
at: key ifPresent: presentBlock ifAbsent: absentBlock
	| assoc |
	assoc := array at: (self scanFor: key).
	assoc isNil ifTrue: [^absentBlock value].
	^presentBlock cull: assoc value
!
associationAt: key
	^self associationAt: key ifAbsent: [self errorKeyNotFound: key]
!
associationAt: key ifAbsent: aBlock
	| assoc |
	assoc := array at: (self scanFor: key).
	assoc isNil ifTrue: [^aBlock value].
	^assoc
!
keyAtValue: value
	^self keyAtValue: value ifAbsent: [nil]
!
keyAtValue: value ifAbsent: aBlock
	self associationsDo: [:assoc | value = assoc value ifTrue: [^assoc key]].
	^aBlock value
!
keys
	"Answer an Array of my keys."
	| result i |
	result := Array new: tally.
	i := 0.
	self keysDo: [:k | result at: (i := i + 1) put: k].
	^result
!
values
	| result i |
	result := Array new: tally.
	i := 0.
	self valuesDo: [:v | result at: (i := i + 1) put: v].
	^result
!
associations
	| result i |
	result := Array new: tally.
	i := 0.
	self associationsDo: [:a | result at: (i := i + 1) put: a].
	^result
!
keysSortedSafely
	^self keys asSortedCollection asArray
!
anyOne
	self do: [:each | ^each].
	^self errorEmptyCollection
! !

!Dictionary methodsFor: 'adding'!
add: anAssociation
	"Store anAssociation itself (if its key is new)."
	| index element |
	index := self scanFor: anAssociation key.
	element := array at: index.
	element isNil
		ifTrue: [self atNewIndex: index put: anAssociation]
		ifFalse: [element value: anAssociation value].
	^anAssociation
!
addAll: aCollection
	aCollection isDictionary
		ifTrue: [aCollection associationsDo: [:assoc | self at: assoc key put: assoc value]]
		ifFalse: [aCollection do: [:assoc | self add: assoc]].
	^aCollection
! !

!Dictionary methodsFor: 'removing'!
removeKey: key
	^self removeKey: key ifAbsent: [self errorKeyNotFound: key]
!
removeKey: key ifAbsent: aBlock
	| index assoc |
	index := self scanFor: key.
	assoc := array at: index.
	assoc isNil ifTrue: [^aBlock value].
	self removeIndex: index.
	^assoc value
!
remove: anObject ifAbsent: aBlock
	^self shouldNotImplement
!
removeAll
	self init: (self class capacityAtLeast: 0)
! !

!Dictionary methodsFor: 'testing'!
includesKey: key
	^(array at: (self scanFor: key)) notNil
!
includes: anObject
	self do: [:each | anObject = each ifTrue: [^true]].
	^false
!
isDictionary
	^true
! !

!Dictionary methodsFor: 'enumerating'!
associationsDo: aBlock
	1 to: array size do: [:i |
		| assoc |
		assoc := array at: i.
		assoc isNil ifFalse: [aBlock value: assoc]]
!
keysDo: aBlock
	self associationsDo: [:assoc | aBlock value: assoc key]
!
valuesDo: aBlock
	self associationsDo: [:assoc | aBlock value: assoc value]
!
do: aBlock
	self valuesDo: aBlock
!
keysAndValuesDo: aBlock
	self associationsDo: [:assoc | aBlock value: assoc key value: assoc value]
!
collect: aBlock
	"Answer a Dictionary with the same keys and the results of aBlock on my values."
	| result |
	result := self species new: self size.
	self associationsDo: [:assoc | result at: assoc key put: (aBlock value: assoc value)].
	^result
!
select: aBlock
	"Answer a Dictionary of the associations whose value satisfies aBlock."
	| result |
	result := self species new.
	self associationsDo: [:assoc |
		(aBlock value: assoc value) ifTrue: [result at: assoc key put: assoc value]].
	^result
!
reject: aBlock
	^self select: [:each | (aBlock value: each) == false]
!
associationsSelect: aBlock
	| result |
	result := self species new.
	self associationsDo: [:assoc | (aBlock value: assoc) ifTrue: [result add: assoc]].
	^result
!
keysSelect: aBlock
	| result |
	result := self species new.
	self associationsDo: [:assoc | (aBlock value: assoc key) ifTrue: [result at: assoc key put: assoc value]].
	^result
! !

!Dictionary methodsFor: 'comparing'!
= aDictionary
	self == aDictionary ifTrue: [^true].
	(self class == aDictionary class and: [self size = aDictionary size]) ifFalse: [^false].
	self associationsDo: [:assoc |
		(aDictionary at: assoc key ifAbsent: [^false]) = assoc value ifFalse: [^false]].
	^true
!
hash
	| h |
	h := self size.
	self keysDo: [:k | h := h bitXor: k hash].
	^h
! !

!Dictionary methodsFor: 'copying'!
postCopy
	"Copy the associations too, so the copy does not share them."
	array := array collect: [:assoc | assoc isNil ifTrue: [nil] ifFalse: [assoc copy]]
! !

!Dictionary methodsFor: 'printing'!
printElementsOn: aStream
	aStream nextPut: $(.
	self associationsDo: [:assoc | aStream print: assoc; space].
	aStream nextPut: $)
! !

!Dictionary methodsFor: 'private'!
keyOf: anAssociation
	^anAssociation key
!
scanFor: key
	| index size element |
	size := array size.
	index := key hash \\ size + 1.
	[(element := array at: index) isNil or: [element key = key]]
		whileFalse: [(index := index + 1) > size ifTrue: [index := 1]].
	^index
! !

!Dictionary class methodsFor: 'instance creation'!
newFrom: aCollection
	^self new addAll: aCollection; yourself
!
newFromPairs: anArray
	| d |
	d := self new: anArray size // 2.
	1 to: anArray size - 1 by: 2 do: [:i | d at: (anArray at: i) put: (anArray at: i + 1)].
	^d
! !
