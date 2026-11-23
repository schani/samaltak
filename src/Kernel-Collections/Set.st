HashedCollection subclass: #Set
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Set comment: 'I am an unordered collection without duplicates; elements are compared with = and hash. I cannot hold nil.'!

!Set methodsFor: 'adding'!
add: newObject
	| index |
	newObject isNil ifTrue: [^self error: 'A Set cannot hold nil'].
	index := self scanFor: newObject.
	(array at: index) isNil ifTrue: [self atNewIndex: index put: newObject].
	^newObject
! !

!Set methodsFor: 'removing'!
remove: oldObject ifAbsent: aBlock
	| index |
	oldObject isNil ifTrue: [^aBlock value].
	index := self scanFor: oldObject.
	(array at: index) isNil ifTrue: [^aBlock value].
	self removeIndex: index.
	^oldObject
! !

!Set methodsFor: 'testing'!
includes: anObject
	anObject isNil ifTrue: [^false].
	^(array at: (self scanFor: anObject)) notNil
!
occurrencesOf: anObject
	^(self includes: anObject) ifTrue: [1] ifFalse: [0]
! !

!Set methodsFor: 'accessing'!
like: anObject
	"Answer my element equal to anObject (compared as anObject = element), or nil."
	| index size element |
	size := array size.
	index := anObject hash \\ size + 1.
	[(element := array at: index) isNil] whileFalse: [
		anObject = element ifTrue: [^element].
		(index := index + 1) > size ifTrue: [index := 1]].
	^nil
! !

!Set methodsFor: 'enumerating'!
do: aBlock
	1 to: array size do: [:i |
		| element |
		element := array at: i.
		element isNil ifFalse: [aBlock value: element]]
!
collect: aBlock
	| result |
	result := Set new: self size.
	self do: [:each | result add: (aBlock value: each)].
	^result
! !

!Set methodsFor: 'comparing'!
= aSet
	self == aSet ifTrue: [^true].
	(self class == aSet class and: [self size = aSet size]) ifFalse: [^false].
	^self allSatisfy: [:each | aSet includes: each]
!
hash
	| h |
	h := self size.
	self do: [:each | h := h bitXor: each hash].
	^h
! !

!Set methodsFor: 'private'!
scanFor: anObject
	| index size element |
	size := array size.
	index := anObject hash \\ size + 1.
	[(element := array at: index) isNil or: [element = anObject]]
		whileFalse: [(index := index + 1) > size ifTrue: [index := 1]].
	^index
! !
