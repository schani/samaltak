Number subclass: #Integer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Integer comment: 'I am the abstract class of integers. SmallIntegers are immediate; LargePositiveInteger and LargeNegativeInteger hold the magnitude as little-endian bytes (no leading zero bytes) and are only used outside the SmallInteger range.

Arithmetic, comparison, shifts and bit operations are VM primitives (LargeIntegerPrimitives: 32-bit limbs, schoolbook multiplication, Knuth''s algorithm D) that take SmallIntegers too, so SmallInteger primitives fall back to me on overflow; results that fit are SmallIntegers. They fail only for arguments that are no Integers, zero divisors and results too large for memory. The rest (printing, hashing, highBit, asFloat) reads the magnitude through digitAt: and digitLength, which SmallInteger implements too.'!

!Integer methodsFor: 'arithmetic'!
+ aNumber
	<primitive: 'largeAdd'>
	aNumber isInteger ifFalse: [^self retry: #+ coercing: aNumber].
	^self primitiveFailed
!
- aNumber
	<primitive: 'largeSub'>
	aNumber isInteger ifFalse: [^self retry: #- coercing: aNumber].
	^self primitiveFailed
!
* aNumber
	<primitive: 'largeMul'>
	aNumber isInteger ifFalse: [^self retry: #* coercing: aNumber].
	^OutOfMemory signalForClass: LargePositiveInteger size: self digitLength + aNumber digitLength
!
/ aNumber
	"Answer an Integer if the division is exact, else a Fraction."
	aNumber isInteger ifFalse: [^self retry: #/ coercing: aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^(Fraction numerator: self denominator: aNumber) reduced
!
quo: aNumber
	"Answer the quotient truncated toward zero."
	<primitive: 'largeQuo'>
	aNumber isInteger ifFalse: [^super quo: aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^self primitiveFailed
!
rem: aNumber
	"Answer the remainder of truncated division; it has the receiver's sign."
	<primitive: 'largeRem'>
	aNumber isInteger ifFalse: [^super rem: aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^self primitiveFailed
!
// aNumber
	"Answer the quotient truncated toward negative infinity."
	<primitive: 'largeFloorDiv'>
	aNumber isInteger ifFalse: [^super // aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^self primitiveFailed
!
\\ aNumber
	"Answer the modulo; it has the sign of aNumber."
	<primitive: 'largeMod'>
	aNumber isInteger ifFalse: [^super \\ aNumber].
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^self primitiveFailed
!
negated
	^0 - self
!
abs
	^self negative ifTrue: [self negated] ifFalse: [self]
! !

!Integer methodsFor: 'comparing'!
< aNumber
	aNumber isInteger ifFalse: [^self retry: #< coercing: aNumber].
	^(self compareInteger: aNumber) < 0
!
> aNumber
	aNumber isInteger ifFalse: [^self retry: #> coercing: aNumber].
	^(self compareInteger: aNumber) > 0
!
<= aNumber
	aNumber isInteger ifFalse: [^self retry: #<= coercing: aNumber].
	^(self compareInteger: aNumber) <= 0
!
>= aNumber
	aNumber isInteger ifFalse: [^self retry: #>= coercing: aNumber].
	^(self compareInteger: aNumber) >= 0
!
= aNumber
	aNumber isNumber ifFalse: [^false].
	aNumber isInteger ifFalse: [^aNumber = self].
	^(self compareInteger: aNumber) = 0
!
~= aNumber
	^(self = aNumber) not
!
hash
	"FNV-1a over the magnitude bytes, as ByteArray>>hash, complemented if negative; SmallInteger overrides with itself."
	| h |
	h := 2166136261.
	1 to: self digitLength do: [:i | h := ((h bitXor: (self digitAt: i)) * 16777619) bitAnd: 16rFFFFFFFF].
	h := h bitAnd: 16r3FFFFFFF.
	^self negative ifTrue: [h bitXor: 16r3FFFFFFF] ifFalse: [h]
!
hashMultiply
	"See SmallInteger>>hashMultiply; of me, only the low 60 bits count."
	^(self bitAnd: 16rFFFFFFFFFFFFFFF) hashMultiply
!
compareInteger: anInteger
	"Answer -1, 0 or 1 comparing the receiver with anInteger."
	<primitive: 'largeCompare'>
	^self primitiveFailed
! !

!Integer methodsFor: 'testing'!
isInteger
	^true
!
isLarge
	^false
!
even
	^((self digitAt: 1) bitAnd: 1) = 0
!
odd
	^((self digitAt: 1) bitAnd: 1) = 1
!
isZero
	^self = 0
!
isPrime
	"Answer whether the receiver is a prime number (trial division)."
	| i |
	self <= 1 ifTrue: [^false].
	self <= 3 ifTrue: [^true].
	self even ifTrue: [^false].
	i := 3.
	[i * i <= self] whileTrue: [
		(self \\ i) = 0 ifTrue: [^false].
		i := i + 2].
	^true
!
isPowerOfTwo
	^self > 0 and: [(self bitAnd: self - 1) = 0]
!
sign
	self negative ifTrue: [^-1].
	self = 0 ifTrue: [^0].
	^1
! !

!Integer methodsFor: 'mathematical functions'!
factorial
	"Answer the factorial of the receiver."

	self < 0 ifTrue: [^self error: 'Not valid for negative integers'].
	^Integer productFrom: 1 to: self
!
gcd: anInteger
	| a b |
	a := self abs.
	b := anInteger abs.
	[b = 0] whileFalse: [| r | r := a \\ b. a := b. b := r].
	^a
!
lcm: anInteger
	"Answer the least common multiple."
	(self = 0 or: [anInteger = 0]) ifTrue: [^0].
	^(self // (self gcd: anInteger) * anInteger) abs
!
sqrtFloor
	"Answer the largest integer whose square is <= the receiver (Newton's method)."
	| x y |
	self < 0 ifTrue: [^ArithmeticError new signal: 'sqrtFloor of a negative number'].
	self < 2 ifTrue: [^self].
	x := 1 bitShift: self highBit + 1 // 2.
	[y := x + (self // x) // 2. y < x] whileTrue: [x := y].
	^x
!
sqrt
	| root |
	self negative ifTrue: [^self asFloat sqrt].
	root := self sqrtFloor.
	root * root = self ifTrue: [^root].
	^self asFloat sqrt
!
isSquare
	| root |
	self < 0 ifTrue: [^false].
	root := self sqrtFloor.
	^root * root = self
!
raisedTo: aNumber modulo: m
	| result base n |
	result := 1.
	base := self \\ m.
	n := aNumber.
	[n > 0] whileTrue: [
		(n bitAnd: 1) = 1 ifTrue: [result := result * base \\ m].
		n := n bitShift: -1.
		base := base * base \\ m].
	^result
!
numberOfDigitsInBase: base
	^(self abs printString: base) size
! !

!Integer methodsFor: 'enumerating'!
timesRepeat: aBlock
	"Evaluate aBlock the receiver number of times."
	| count |
	count := 1.
	[count <= self] whileTrue: [
		aBlock value.
		count := count + 1]
! !

!Integer methodsFor: 'bit manipulation'!
bitAnd: anInteger
	<primitive: 'largeBitAnd'>
	anInteger isInteger ifFalse: [^self error: 'bit operations need Integers'].
	^self primitiveFailed
!
bitOr: anInteger
	<primitive: 'largeBitOr'>
	anInteger isInteger ifFalse: [^self error: 'bit operations need Integers'].
	^self primitiveFailed
!
bitXor: anInteger
	<primitive: 'largeBitXor'>
	anInteger isInteger ifFalse: [^self error: 'bit operations need Integers'].
	^self primitiveFailed
!
bitInvert
	^-1 - self
!
bitClear: mask
	^(self bitOr: mask) bitXor: mask
!
bitAt: index
	"Answer the bit (0 or 1) at index, 1 being the least significant (two's complement)."
	^(self bitShift: 1 - index) bitAnd: 1
!
bitAt: index put: bit
	| mask |
	mask := 1 bitShift: index - 1.
	^bit = 0 ifTrue: [self bitClear: mask] ifFalse: [self bitOr: mask]
!
allMask: mask
	^(self bitAnd: mask) = mask
!
anyMask: mask
	^(self bitAnd: mask) ~= 0
!
noMask: mask
	^(self bitAnd: mask) = 0
!
bitShift: shift
	"Shift left (positive shift) or right (negative shift, rounding toward negative infinity)."
	<primitive: 'largeBitShift'>
	shift isInteger ifFalse: [^self error: 'bitShift: needs an Integer'].
	^OutOfMemory signalForClass: LargePositiveInteger size: self digitLength + (shift // 8)
!
<< shift
	^self bitShift: shift
!
>> shift
	^self bitShift: shift negated
!
highBit
	"Answer the index of the most significant 1 bit of the (non-negative) receiver; 0 for 0."
	self negative ifTrue: [^self error: 'highBit is not defined for negative integers'].
	^self highBitOfMagnitude
!
highBitOfMagnitude
	| len |
	len := self digitLength.
	[len > 0 and: [(self digitAt: len) = 0]] whileTrue: [len := len - 1].
	len = 0 ifTrue: [^0].
	^(len - 1) * 8 + (self digitAt: len) highBit
!
lowBit
	"Answer the index of the least significant 1 bit; 0 for 0."
	| i d |
	self = 0 ifTrue: [^0].
	i := 1.
	[(d := self digitAt: i) = 0] whileTrue: [i := i + 1].
	^(i - 1) * 8 + d lowBit
! !

!Integer methodsFor: 'truncation and rounding'!
truncated
	^self
!
rounded
	^self
!
floor
	^self
!
ceiling
	^self
!
numerator
	^self
!
denominator
	^1
! !

!Integer methodsFor: 'converting'!
asInteger
	^self
!
asCharacter
	^Character value: self
!
asFraction
	^self
!
asExactFraction
	^self
!
asFloat
	"Convert, rounding to nearest even (SmallInteger uses a primitive)."
	| h excess q low half |
	self negative ifTrue: [^self negated asFloat negated].
	h := self highBit.
	h <= 53 ifTrue: [^self asFloatExact].
	excess := h - 53.
	q := self bitShift: excess negated.
	low := self - (q bitShift: excess).
	half := 1 bitShift: excess - 1.
	(low > half or: [low = half and: [q odd]]) ifTrue: [q := q + 1].
	^q asFloatExact timesTwoPower: excess
!
asFloatExact
	"The receiver has at most 53 significant bits: convert digit by digit."
	| f |
	f := 0.0.
	self digitLength to: 1 by: -1 do: [:i | f := f * 256.0 + (self digitAt: i) asFloat].
	^f
! !

!Integer methodsFor: 'printing'!
printOn: aStream base: base
	aStream nextPutAll: (self printString: base)
!
printString
	^self printString: 10
!
printString: base
	"Answer the digits of the receiver in base (2..36), with a leading minus if negative."
	^self subclassResponsibility
!
radix: base
	"Answer the digits in base without a radix prefix (255 radix: 16 = 'FF')."
	^self printString: base
!
printStringRadix: base
	"Answer the receiver with a radix prefix: 16rFF."
	| s |
	s := self abs printString: base.
	^String new: s size + 4 streamContents: [:stream |
		self negative ifTrue: [stream nextPut: $-].
		stream print: base; nextPut: $r; nextPutAll: s]
!
storeString: base
	^self printStringRadix: base
!
storeOn: aStream base: base
	aStream nextPutAll: (self printStringRadix: base)
!
printOn: aStream base: base nDigits: n
	aStream nextPutAll: ((self printString: base) padLeftTo: n with: $0)
!
printPaddedWith: aCharacter to: width
	"Answer the decimal digits padded on the left to width with aCharacter."
	| s |
	s := self abs printString.
	s := s padLeftTo: (self negative ifTrue: [width - 1] ifFalse: [width]) with: aCharacter.
	^self negative ifTrue: ['-', s] ifFalse: [s]
!
printStringHex
	^self printString: 16
!
hex
	^self printStringRadix: 16
!
printStringBase: base
	^self printString: base
!
asStringWithCommas
	| s result count |
	s := self abs printString.
	result := WriteStream on: (String new: s size * 4 // 3 + 2).
	self negative ifTrue: [result nextPut: $-].
	count := s size.
	s do: [:c |
		result nextPut: c.
		count := count - 1.
		(count > 0 and: [count \\ 3 = 0]) ifTrue: [result nextPut: $,]].
	^result contents
!
isLiteral
	^true
! !

!Integer methodsFor: 'private'!
generality
	^self subclassResponsibility
!
coerce: aNumber
	^aNumber
!
negative
	^self subclassResponsibility
!
digitAt: index
	"Answer byte index (1 = least significant) of the magnitude."
	^self subclassResponsibility
!
digitLength
	^self subclassResponsibility
! !

!Integer class methodsFor: 'instance creation'!
readFrom: aStringOrStream
	^(NumberParser parse: aStringOrStream) asInteger
!
readFrom: aString base: base
	^NumberParser parse: aString base: base
! !

!Integer class methodsFor: 'mathematical functions'!
productFrom: low to: high
	"Answer low * (low + 1) * ... * high by binary splitting, so that big products multiply numbers of similar size. Short ranges collect factors in a SmallInteger below 2^30 before multiplying it in, as a large integer times such a SmallInteger takes one pass over its 32-bit limbs."
	| result factor mid |
	high - low < 16 ifTrue: [
		result := 1.
		factor := 1.
		low to: high do: [:i |
			factor * i < 16r40000000
				ifTrue: [factor := factor * i]
				ifFalse: [result := result * factor. factor := i]].
		^result * factor].
	mid := low + high // 2.
	^(self productFrom: low to: mid) * (self productFrom: mid + 1 to: high)
! !
