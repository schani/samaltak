VMCoreModule subclass: #VMPrimitiveModule
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

VMPrimitiveModule comment: 'I am the abstract class of the modules that implement primitives (<vmPrimitive: number name: ''name''>, a void function each). My inline helpers read the arguments and answer results through the interpreter''s primitive plumbing.'!

!VMPrimitiveModule class methodsFor: 'declaring'!
isAbstractModule
	^self == VMPrimitiveModule
! !

!VMPrimitiveModule methodsFor: 'arguments'!
receiver
	^interpreter primReceiver
!
argCount
	^interpreter primArgc
!
arg: i
	^interpreter primArg: i
!
arg0
	^interpreter primArgc > 0 ifTrue: [interpreter primArg: 0] ifFalse: [memory nilOop]
!
indexOf: o limit: n
	"The 0-based index of the 1-based SmallInteger index o if it is at most n, else -1."
	((self isInt: o) and: [(self intVal: o) >= 1 and: [(self intVal: o) asUInt64 <= n]]) ifFalse: [^-1].
	^(self intVal: o) - 1
!
element: o at: i
	"Field i of an argument's object o (an Array, a Point...): followed if a forwarder (becomeForward:); a failing primitive's retry follows only its arguments themselves."
	| v |
	v := self loadRef: o at: i.
	(self unlikely: gc forwardersExist) ifTrue: [v := memory follow: v].
	^v
! !

!VMPrimitiveModule methodsFor: 'results'!
answer: v
	interpreter primReturn: v
!
fail
	interpreter primFail
!
failCode: code
	interpreter primFailCode: code
!
answerInt: v
	(self intFits: v)
		ifTrue: [interpreter primReturn: (self intOop: v)]
		ifFalse: [interpreter primFail]
!
answerBool: aBoolean
	interpreter primReturn: (self bool: aBoolean)
!
answerFloat: d
	interpreter primReturn: (memory floatOop: d)
! !
