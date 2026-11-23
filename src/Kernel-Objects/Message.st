Object subclass: #Message
	instanceVariableNames: 'selector arguments'
	classVariableNames: ''
	package: 'Kernel-Objects'!

Message comment: 'I am a message send reified: a selector and its arguments. The VM builds me for doesNotUnderstand:. My field order (selector arguments) is fixed by the VM.'!

!Message methodsFor: 'accessing'!
selector
	^selector
!
selector: aSymbol
	selector := aSymbol
!
arguments
	^arguments
!
arguments: anArray
	arguments := anArray
!
argument
	^arguments first
!
numArgs
	^arguments size
! !

!Message methodsFor: 'sending'!
sendTo: receiver
	"Send the receiver message to receiver."
	^receiver perform: selector withArguments: arguments
!
sentTo: receiver
	^self sendTo: receiver
! !

!Message methodsFor: 'comparing'!
= anObject
	^self class == anObject class
		and: [selector == anObject selector and: [arguments = anObject arguments]]
!
hash
	^(selector hash hashMultiply + arguments hash) hashMultiply
! !

!Message methodsFor: 'printing'!
printOn: aStream
	| keywords |
	selector isNil ifTrue: [^super printOn: aStream].
	(arguments isNil or: [arguments isEmpty]) ifTrue: [^aStream nextPutAll: selector].
	keywords := selector keywords.
	keywords size = arguments size
		ifFalse: [^aStream nextPutAll: selector; space; print: arguments].
	1 to: keywords size do: [:i |
		i > 1 ifTrue: [aStream space].
		aStream nextPutAll: (keywords at: i); space; print: (arguments at: i)]
! !

!Message class methodsFor: 'instance creation'!
selector: aSymbol
	^self selector: aSymbol arguments: #()
!
selector: aSymbol argument: anObject
	^self selector: aSymbol arguments: {anObject}
!
selector: aSymbol arguments: anArray
	^self basicNew selector: aSymbol; arguments: anArray; yourself
! !
