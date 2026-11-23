Set subclass: #IdentitySet
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

IdentitySet comment: 'I am a Set that compares elements by identity (==, identityHash).'!

!IdentitySet methodsFor: 'private'!
scanFor: anObject
	| index size element |
	size := array size.
	index := anObject identityHash \\ size + 1.
	[(element := array at: index) isNil or: [element == anObject]]
		whileFalse: [(index := index + 1) > size ifTrue: [index := 1]].
	^index
! !

!IdentitySet methodsFor: 'enumerating'!
collect: aBlock
	| result |
	result := IdentitySet new: self size.
	self do: [:each | result add: (aBlock value: each)].
	^result
! !

!IdentitySet methodsFor: 'accessing'!
like: anObject
	^(self includes: anObject) ifTrue: [anObject] ifFalse: [nil]
! !
