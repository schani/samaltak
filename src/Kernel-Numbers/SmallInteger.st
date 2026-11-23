Integer immediateSubclass: #SmallInteger
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

SmallInteger comment: 'I am a 63-bit two''s complement integer encoded in the object pointer itself (tag bit 1), so I have no instances in memory. My arithmetic primitives fail on overflow or non-SmallInteger arguments; the fallback code in Integer then computes the exact (Large) result or coerces the argument.'!

!SmallInteger methodsFor: 'arithmetic'!
+ aNumber
	<primitive: 'intAdd'>
	^super + aNumber
!
- aNumber
	<primitive: 'intSub'>
	^super - aNumber
!
* aNumber
	<primitive: 'intMul'>
	^super * aNumber
!
/ aNumber
	"Exact division answers an Integer; otherwise a Fraction."
	<primitive: 'intDiv'>
	^super / aNumber
!
// aNumber
	<primitive: 'intFloorDiv'>
	^super // aNumber
!
\\ aNumber
	<primitive: 'intMod'>
	^super \\ aNumber
!
quo: aNumber
	<primitive: 'intQuo'>
	^super quo: aNumber
!
rem: aNumber
	<primitive: 'intRem'>
	^super rem: aNumber
!
negated
	^0 - self
!
abs
	self < 0 ifTrue: [^0 - self].
	^self
! !

!SmallInteger methodsFor: 'comparing'!
< aNumber
	<primitive: 'intLess'>
	^super < aNumber
!
> aNumber
	<primitive: 'intGreater'>
	^super > aNumber
!
<= aNumber
	<primitive: 'intLessEq'>
	^super <= aNumber
!
>= aNumber
	<primitive: 'intGreaterEq'>
	^super >= aNumber
!
= aNumber
	<primitive: 'intEq'>
	^super = aNumber
!
~= aNumber
	<primitive: 'intNotEq'>
	^super ~= aNumber
!
hash
	^self
!
identityHash
	^self
!
hashMultiply
	"Answer a 28-bit scramble of me, for combining hashes: the bits above 28 folded into the low 28, times 1664525 modulo 2^28."
	^((self bitShift: -28) + (self bitAnd: 16rFFFFFFF) bitAnd: 16rFFFFFFF) * 1664525 bitAnd: 16rFFFFFFF
! !

!SmallInteger methodsFor: 'bit manipulation'!
bitAnd: anInteger
	<primitive: 'intBitAnd'>
	^super bitAnd: anInteger
!
bitOr: anInteger
	<primitive: 'intBitOr'>
	^super bitOr: anInteger
!
bitXor: anInteger
	<primitive: 'intBitXor'>
	^super bitXor: anInteger
!
bitShift: anInteger
	<primitive: 'intBitShift'>
	^super bitShift: anInteger
!
highBit
	"Answer the index of the most significant 1 bit; 0 for 0."
	| n bit |
	self < 0 ifTrue: [^self error: 'highBit is not defined for negative integers'].
	n := self.
	bit := 0.
	[n > 16rFF] whileTrue: [n := n bitShift: -8. bit := bit + 8].
	[n > 0] whileTrue: [n := n bitShift: -1. bit := bit + 1].
	^bit
!
highBitOfMagnitude
	self < 0 ifTrue: [^self = SmallInteger minVal ifTrue: [63] ifFalse: [self negated highBit]].
	^self highBit
!
lowBit
	| n bit |
	self = 0 ifTrue: [^0].
	n := self.
	bit := 1.
	[(n bitAnd: 1) = 0] whileTrue: [n := n bitShift: -1. bit := bit + 1].
	^bit
!
even
	^(self bitAnd: 1) = 0
!
odd
	^(self bitAnd: 1) = 1
! !

!SmallInteger methodsFor: 'converting'!
asFloat
	<primitive: 'intAsFloat'>
	^super asFloat
!
asCharacter
	^Character value: self
! !

!SmallInteger methodsFor: 'testing'!
negative
	^self < 0
!
isZero
	^self = 0
! !

!SmallInteger methodsFor: 'printing'!
printString: base
	"Answer the digits in base, with a leading minus sign if negative."
	| n s i |
	self = 0 ifTrue: [^'0'].
	n := self.
	s := String new: 65.
	i := 65.
	[n = 0] whileFalse: [
		s at: i put: (Character digitValue: (n rem: base) abs).
		i := i - 1.
		n := n quo: base].
	self < 0 ifTrue: [s at: i put: $-. i := i - 1].
	^s copyFrom: i + 1 to: 65
!
printOn: aStream
	aStream nextPutAll: (self printString: 10)
!
printOn: aStream base: base
	aStream nextPutAll: (self printString: base)
! !

!SmallInteger methodsFor: 'copying'!
shallowCopy
	^self
!
deepCopy
	^self
! !

!SmallInteger methodsFor: 'private'!
generality
	^20
!
digitLength
	"Answer the number of bytes of the magnitude."
	| value length |
	length := 1.
	value := self.
	value >= 0
		ifTrue: [[value > 255] whileTrue: [value := value bitShift: -8. length := length + 1]]
		ifFalse: [[value < -255] whileTrue: [value := value bitShift: -8. length := length + 1]].
	^length
!
digitAt: n
	"Answer byte n of the magnitude, computed without negating (which could overflow for minVal)."
	n = 1 ifTrue: [
		^self < 0
			ifTrue: [-256 - self bitAnd: 255]
			ifFalse: [self bitAnd: 255]].
	^self < 0
		ifTrue: [(-256 - self bitShift: -8) + 1 digitAt: n - 1]
		ifFalse: [(self bitShift: 8 - (n bitShift: 3)) bitAnd: 255]
! !

!SmallInteger class methodsFor: 'constants'!
maxVal
	"Answer the largest SmallInteger, 2^62 - 1."
	^16r3FFFFFFFFFFFFFFF
!
minVal
	"Answer the smallest SmallInteger, -2^62."
	^16r3FFFFFFFFFFFFFFF negated - 1
! !

!SmallInteger class methodsFor: 'instance creation'!
new
	^self error: 'SmallIntegers are created by arithmetic'
!
basicNew
	^self error: 'SmallIntegers are created by arithmetic'
! !
