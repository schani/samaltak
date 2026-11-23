Number subclass: #Float
	instanceVariableNames: ''
	classVariableNames: 'E Epsilon Infinity Ln10 NaN NegativeInfinity Pi'
	package: 'Kernel-Numbers'!

Float comment: 'I am the abstract class of IEEE 754 double precision floating point numbers. Most floats are SmallFloat64 immediates; values with extreme exponents, infinities and NaNs are BoxedFloat64 objects. The VM''s float primitives accept both and also SmallInteger arguments; other arguments make them fail and the operation is retried with coercion. Comparison with exact numbers (Fractions, LargeIntegers) is exact, and hash is consistent with it.'!

!Float methodsFor: 'arithmetic'!
+ aNumber
	<primitive: 'floatAdd'>
	^self retry: #+ coercing: aNumber
!
- aNumber
	<primitive: 'floatSub'>
	^self retry: #- coercing: aNumber
!
* aNumber
	<primitive: 'floatMul'>
	^self retry: #* coercing: aNumber
!
/ aNumber
	<primitive: 'floatDiv'>
	aNumber = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	^self retry: #/ coercing: aNumber
!
negated
	^self * -1.0
!
abs
	<primitive: 'floatAbs'>
	self < 0.0 ifTrue: [^self negated].
	^self
!
reciprocal
	^1.0 / self
! !

!Float methodsFor: 'comparing'!
< aNumber
	<primitive: 'floatLess'>
	^self retry: #< coercing: aNumber
!
> aNumber
	<primitive: 'floatGreater'>
	^self retry: #> coercing: aNumber
!
<= aNumber
	<primitive: 'floatLessEq'>
	^self retry: #<= coercing: aNumber
!
>= aNumber
	<primitive: 'floatGreaterEq'>
	^self retry: #>= coercing: aNumber
!
= aNumber
	<primitive: 'floatEq'>
	aNumber isNumber ifFalse: [^false].
	aNumber isFloat ifTrue: [^false].
	self isFinite ifFalse: [^false].
	^self asExactFraction = aNumber
!
~= aNumber
	^(self = aNumber) not
!
hash
	"Equal numbers have equal hashes: integral floats hash like the integer; others answer murmur3's fmix64 of their IEEE bits, 30 bits of it, as Fractions a Float represents exactly do (Fraction>>hash). The primitive fails for integral floats."
	<primitive: 'floatHash'>
	| h |
	self isFinite ifFalse: [^self isNaN ifTrue: [16r7FF8] ifFalse: [self sign * 16r7FF0]].
	self fractionPart = 0.0 ifTrue: [^self abs < 1.0e18 ifTrue: [self truncated hash] ifFalse: [self asExactFraction hash]].
	h := self asIEEEBits.
	h := h bitXor: (h bitShift: -33).
	h := h * 16rFF51AFD7ED558CCD bitAnd: 16rFFFFFFFFFFFFFFFF.
	h := h bitXor: (h bitShift: -33).
	h := h * 16rC4CEB9FE1A85EC53 bitAnd: 16rFFFFFFFFFFFFFFFF.
	h := h bitXor: (h bitShift: -33).
	^h bitAnd: 16r3FFFFFFF
! !

!Float methodsFor: 'truncation and rounding'!
truncated
	"Answer the integer part, toward zero."
	<primitive: 'floatTruncated'>
	self isFinite ifFalse: [^ArithmeticError new signal: 'Cannot truncate ', self printString].
	^self asExactFraction truncated
!
fractionPart
	<primitive: 'floatFractionPart'>
	^self - self truncated asFloat
!
integerPart
	^self - self fractionPart
!
rounded
	"Answer the nearest integer, halves away from zero."
	| t |
	t := self truncated.
	(self - t) abs >= 0.5 ifTrue: [^t + self sign].
	^t
!
floor
	| t |
	t := self truncated.
	(self < 0.0 and: [t asFloat ~= self]) ifTrue: [^t - 1].
	^t
!
ceiling
	| t |
	t := self truncated.
	(self > 0.0 and: [t asFloat ~= self]) ifTrue: [^t + 1].
	^t
!
roundTo: quantum
	^(self / quantum) rounded * quantum
! !

!Float methodsFor: 'mathematical functions'!
exponent
	"Answer the power of two of the receiver's binary exponent (1.0 exponent = 0, 3.0 exponent = 1)."
	<primitive: 'floatExponent'>
	^self primitiveFailed
!
timesTwoPower: anInteger
	<primitive: 'floatTimesTwoPower'>
	anInteger isInteger ifFalse: [^self error: 'timesTwoPower: needs an Integer'].
	anInteger abs <= 1000 ifTrue: [^self primitiveFailed].
	anInteger > 0
		ifTrue: [^(self timesTwoPower: anInteger - 1000) timesTwoPower: 1000]
		ifFalse: [^(self timesTwoPower: anInteger + 1000) timesTwoPower: -1000]
!
sqrt
	<primitive: 'floatSqrt'>
	^Float nan
!
sin
	<primitive: 'floatSin'>
	^self primitiveFailed
!
cos
	<primitive: 'floatCos'>
	^self primitiveFailed
!
tan
	^self sin / self cos
!
arcTan
	<primitive: 'floatArcTan'>
	^self primitiveFailed
!
arcSin
	self abs > 1.0 ifTrue: [^Float nan].
	self abs = 1.0 ifTrue: [^Float pi / 2.0 * self].
	^(self / (1.0 - (self * self)) sqrt) arcTan
!
arcCos
	^Float pi / 2.0 - self arcSin
!
arcTan: denominator
	"Answer the angle of the point (denominator, self), in (-pi, pi]."
	denominator = 0.0 ifTrue: [
		self > 0.0 ifTrue: [^Float pi / 2.0].
		self < 0.0 ifTrue: [^Float pi / -2.0].
		^0.0].
	denominator > 0.0 ifTrue: [^(self / denominator) arcTan].
	self >= 0.0 ifTrue: [^(self / denominator) arcTan + Float pi].
	^(self / denominator) arcTan - Float pi
!
ln
	<primitive: 'floatLn'>
	^self primitiveFailed
!
log
	^self ln / Ln10
!
exp
	<primitive: 'floatExp'>
	^self primitiveFailed
!
raisedTo: aNumber
	aNumber isInteger ifTrue: [^self raisedToInteger: aNumber].
	self = 0.0 ifTrue: [^0.0].
	self < 0.0 ifTrue: [^ArithmeticError new signal: 'Negative number raised to a non-integer power'].
	^(aNumber asFloat * self ln) exp
!
unity
	^1.0
! !

!Float methodsFor: 'testing'!
isFloat
	^true
!
isNaN
	^self ~= self
!
isInfinite
	^self = Infinity or: [self = NegativeInfinity]
!
isFinite
	^self isNaN not and: [self isInfinite not]
!
isZero
	^self = 0.0
!
negative
	^self < 0.0
!
sign
	self > 0.0 ifTrue: [^1].
	self < 0.0 ifTrue: [^-1].
	^0
!
isLiteral
	^self isFinite
! !

!Float methodsFor: 'converting'!
asFloat
	^self
!
asExactFraction
	"Answer the exact value of the receiver as an Integer or Fraction."
	| exp mantissa |
	self isFinite ifFalse: [^ArithmeticError new signal: 'Cannot convert ', self printString, ' to a fraction'].
	self = 0.0 ifTrue: [^0].
	exp := self exponent.
	mantissa := (self timesTwoPower: 52 - exp) truncated.
	exp >= 52 ifTrue: [^mantissa bitShift: exp - 52].
	^mantissa / (1 bitShift: 52 - exp)
!
asTrueFraction
	^self asExactFraction
!
asExactNumber
	^self asExactFraction
!
asFraction
	^self asExactFraction
!
asIEEEBits
	"Answer the 64 IEEE bits as a non-negative Integer."
	<primitive: 'floatAsIEEEBits'>
	^self primitiveFailed
! !

!Float methodsFor: 'printing'!
printOn: aStream
	self isNaN ifTrue: [^aStream nextPutAll: 'Float nan'].
	self = Infinity ifTrue: [^aStream nextPutAll: 'Float infinity'].
	self = NegativeInfinity ifTrue: [^aStream nextPutAll: 'Float negativeInfinity'].
	aStream nextPutAll: self primPrintString
!
printOn: aStream base: base
	base = 10 ifFalse: [^self error: 'Floats print in base 10 only'].
	self printOn: aStream
!
primPrintString
	"Answer the shortest decimal representation that reads back as the receiver."
	<primitive: 'floatPrintString'>
	^self primitiveFailed
!
printString
	^String new: 24 streamContents: [:s | self printOn: s]
!
storeOn: aStream
	self printOn: aStream
! !

!Float methodsFor: 'copying'!
shallowCopy
	^self
!
deepCopy
	^self
! !

!Float methodsFor: 'private'!
generality
	^80
!
coerce: aNumber
	^aNumber asFloat
! !

!Float class methodsFor: 'class initialization'!
initialize
	Pi := 3.141592653589793.
	E := 2.718281828459045.
	Ln10 := 2.302585092994046.
	Epsilon := 2.220446049250313e-16.
	Infinity := 1.0e308 * 10.0.
	NegativeInfinity := Infinity * -1.0.
	NaN := Infinity - Infinity
! !

!Float class methodsFor: 'constants'!
pi
	^Pi
!
e
	^E
!
infinity
	^Infinity
!
negativeInfinity
	^NegativeInfinity
!
nan
	^NaN
!
epsilon
	^Epsilon
!
fmax
	^1.7976931348623157e308
!
fminNormalized
	^2.2250738585072014e-308
! !

!Float class methodsFor: 'instance creation'!
fromIEEEBits: anInteger
	<primitive: 'floatFromIEEEBits'>
	^self primitiveFailed
!
readFrom: aStringOrStream
	^(NumberParser parse: aStringOrStream) asFloat
! !
