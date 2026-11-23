Number subclass: #Fraction
	instanceVariableNames: 'numerator denominator'
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Fraction comment: 'I am an exact rational number numerator/denominator. Arithmetic results are always normalized: the denominator is positive and greater than 1, and numerator and denominator are coprime; results that are integral are answered as Integers. Integer>>/ creates me when the division is not exact.'!

!Fraction methodsFor: 'accessing'!
numerator
	^numerator
!
denominator
	^denominator
! !

!Fraction methodsFor: 'private'!
setNumerator: n denominator: d
	numerator := n.
	denominator := d
!
generality
	^60
!
coerce: aNumber
	"Answer aNumber (an Integer) as an unnormalized Fraction."
	^Fraction numerator: aNumber denominator: 1
!
reduced
	"Answer the normalized value of the receiver."
	| gcd n d |
	numerator = 0 ifTrue: [^0].
	gcd := numerator gcd: denominator.
	n := numerator // gcd.
	d := denominator // gcd.
	d < 0 ifTrue: [n := n negated. d := d negated].
	d = 1 ifTrue: [^n].
	^Fraction numerator: n denominator: d
! !

!Fraction methodsFor: 'arithmetic'!
+ aNumber
	"Knuth, TAOCP 2, 4.5.1: the operands are normalized, so the gcds needed are of the denominators and of that with the sum's numerator, not of the products; coprime denominators need no other."
	| n d n2 d2 g |
	aNumber isInteger ifTrue: [
		^Fraction numerator: numerator + (aNumber * denominator) denominator: denominator].
	aNumber isFraction ifFalse: [^self retry: #+ coercing: aNumber].
	n2 := aNumber numerator.
	d2 := aNumber denominator.
	g := denominator gcd: d2.
	g = 1 ifTrue: [
		^Fraction numerator: (numerator * d2) + (n2 * denominator) denominator: denominator * d2].
	d2 := d2 // g.
	n := (numerator * d2) + (n2 * (denominator // g)).
	d := denominator.
	g := n gcd: g.
	g = 1 ifFalse: [
		n := n // g.
		d := d // g].
	d := d * d2.
	d = 1 ifTrue: [^n].
	^Fraction numerator: n denominator: d
!
- aNumber
	| n d n2 d2 g |
	aNumber isInteger ifTrue: [
		^Fraction numerator: numerator - (aNumber * denominator) denominator: denominator].
	aNumber isFraction ifFalse: [^self retry: #- coercing: aNumber].
	n2 := aNumber numerator.
	d2 := aNumber denominator.
	g := denominator gcd: d2.
	g = 1 ifTrue: [
		^Fraction numerator: (numerator * d2) - (n2 * denominator) denominator: denominator * d2].
	d2 := d2 // g.
	n := (numerator * d2) - (n2 * (denominator // g)).
	d := denominator.
	g := n gcd: g.
	g = 1 ifFalse: [
		n := n // g.
		d := d // g].
	d := d * d2.
	d = 1 ifTrue: [^n].
	^Fraction numerator: n denominator: d
!
* aNumber
	"Knuth, TAOCP 2, 4.5.1: each numerator's common factors with the other denominator cancel before multiplying."
	| n d n2 d2 g |
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^self retry: #* coercing: aNumber].
	n := numerator.
	d := denominator.
	n2 := aNumber numerator.
	d2 := aNumber denominator.
	g := d2 gcd: n.
	g = 1 ifFalse: [
		n := n // g.
		d2 := d2 // g].
	g := d gcd: n2.
	g = 1 ifFalse: [
		n2 := n2 // g.
		d := d // g].
	n := n * n2.
	d := d * d2.
	d = 1 ifTrue: [^n].
	^Fraction numerator: n denominator: d
!
/ aNumber
	"As * by the reciprocal; the denominator takes the divisor's sign."
	| n d n2 d2 g |
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^self retry: #/ coercing: aNumber].
	n := numerator.
	d := denominator.
	n2 := aNumber denominator.
	d2 := aNumber numerator.
	d2 = 0 ifTrue: [^ZeroDivide new dividend: self; signal].
	g := n gcd: d2.
	g = 1 ifFalse: [
		n := n // g.
		d2 := d2 // g].
	g := n2 gcd: d.
	g = 1 ifFalse: [
		n2 := n2 // g.
		d := d // g].
	n := n * n2.
	d := d * d2.
	d < 0 ifTrue: [
		n := n negated.
		d := d negated].
	d = 1 ifTrue: [^n].
	^Fraction numerator: n denominator: d
!
negated
	^Fraction numerator: numerator negated denominator: denominator
!
reciprocal
	numerator = 0 ifTrue: [^ZeroDivide new dividend: 1; signal].
	numerator abs = 1 ifTrue: [^denominator * numerator].
	numerator < 0 ifTrue: [^Fraction numerator: denominator negated denominator: numerator negated].
	^Fraction numerator: denominator denominator: numerator
!
abs
	numerator < 0 ifTrue: [^self negated].
	^self
! !

!Fraction methodsFor: 'comparing'!
< aNumber
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^self retry: #< coercing: aNumber].
	^numerator * aNumber denominator < (aNumber numerator * denominator)
!
> aNumber
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^self retry: #> coercing: aNumber].
	^numerator * aNumber denominator > (aNumber numerator * denominator)
!
<= aNumber
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^self retry: #<= coercing: aNumber].
	^numerator * aNumber denominator <= (aNumber numerator * denominator)
!
>= aNumber
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^self retry: #>= coercing: aNumber].
	^numerator * aNumber denominator >= (aNumber numerator * denominator)
!
= aNumber
	aNumber isNumber ifFalse: [^false].
	aNumber isFloat ifTrue: [^aNumber = self].
	(aNumber isInteger or: [aNumber isFraction]) ifFalse: [^false].
	^numerator * aNumber denominator = (aNumber numerator * denominator)
!
hash
	"Equal numbers have equal hashes: if a Float equals me, I hash like it."
	| f |
	denominator isPowerOfTwo ifTrue: [
		f := self asFloat.
		(f isFinite and: [f = self]) ifTrue: [^f hash]].
	^(numerator hash hashMultiply + denominator hash) hashMultiply
! !

!Fraction methodsFor: 'truncation and rounding'!
truncated
	^numerator quo: denominator
! !

!Fraction methodsFor: 'testing'!
isFraction
	^true
!
negative
	^numerator < 0
!
isZero
	^numerator = 0
! !

!Fraction methodsFor: 'converting'!
asFloat
	"Answer the nearest Float (round half to even)."
	| n d shift q r h excess low half |
	numerator = 0 ifTrue: [^0.0].
	numerator < 0 ifTrue: [^(Fraction numerator: numerator negated denominator: denominator) asFloat negated].
	n := numerator.
	d := denominator.
	shift := 55 - (n highBit - d highBit).
	shift >= 0
		ifTrue: [n := n bitShift: shift]
		ifFalse: [d := d bitShift: shift negated].
	q := n // d.
	r := n \\ d.
	h := q highBit.
	excess := h - 53.
	excess > 0 ifTrue: [
		low := q bitAnd: (1 bitShift: excess) - 1.
		half := 1 bitShift: excess - 1.
		q := q bitShift: excess negated.
		(low > half or: [low = half and: [r ~= 0 or: [q odd]]]) ifTrue: [q := q + 1].
		^q asFloat timesTwoPower: excess - shift].
	^q asFloat timesTwoPower: shift negated
!
asExactFraction
	^self
!
asFraction
	^self
! !

!Fraction methodsFor: 'printing'!
printOn: aStream
	aStream nextPut: $(; print: numerator; nextPut: $/; print: denominator; nextPut: $)
!
printOn: aStream base: base
	aStream nextPut: $(; nextPutAll: (numerator printString: base); nextPut: $/; nextPutAll: (denominator printString: base); nextPut: $)
!
storeOn: aStream
	self printOn: aStream
!
isLiteral
	^false
! !

!Fraction class methodsFor: 'instance creation'!
numerator: n denominator: d
	"Answer an unnormalized Fraction; send reduced to normalize."
	^self basicNew setNumerator: n denominator: d
! !
