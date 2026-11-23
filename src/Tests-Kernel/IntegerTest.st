TestCase subclass: #IntegerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

IntegerTest comment: 'Tests SmallInteger and LargeInteger arithmetic, printing, bit operations and number theory.'!

!IntegerTest methodsFor: 'tests'!
testSmallIntegerArithmetic
	self assert: 3 + 4 = 7.
	self assert: 3 - 4 = -1.
	self assert: 6 * 7 = 42.
	self assert: 12 / 4 = 3.
	self assert: (12 / 4) class == SmallInteger.
	self assert: 7 // 2 = 3.
	self assert: -7 // 2 = -4.
	self assert: 7 \\ 2 = 1.
	self assert: -7 \\ 2 = 1.
	self assert: 7 \\ -2 = -1.
	self assert: (-7 quo: 2) = -3.
	self assert: (-7 rem: 2) = -1.
	self assert: 5 negated = -5.
	self assert: -5 abs = 5.
	self assert: (3 max: 9) = 9.
	self assert: (3 between: 1 and: 3).
	self assert: 10 sqrt = 10 sqrt.
	self assert: 16 sqrt = 4.
	self assert: (2 raisedTo: 10) = 1024.
	self assert: (2 ** 3) = 8
!
testOverflowIntoLargeIntegers
	| max min |
	max := SmallInteger maxVal.
	min := SmallInteger minVal.
	self assert: max = 4611686018427387903.
	self assert: (max + 1) class == LargePositiveInteger.
	self assert: (min - 1) class == LargeNegativeInteger.
	self assert: max + 1 - 1 = max.
	self assert: (max + 1 - 1) class == SmallInteger.
	self assert: min negated class == LargePositiveInteger.
	self assert: min negated negated = min.
	self assert: (min negated negated) class == SmallInteger.
	self assert: (max * max) // max = max.
	self assert: (max + 1) printString = '4611686018427387904'.
	self assert: (min - 1) printString = '-4611686018427387905'.
	self assert: max + 1 > max.
	self assert: min - 1 < min.
	self assert: (max + 1) hash = (max + 1) hash.
	self assert: (2 raisedTo: 64) - (2 raisedTo: 64) = 0.
	self assert: ((2 raisedTo: 64) - (2 raisedTo: 64)) class == SmallInteger
!
testLargeArithmetic
	| a b |
	a := 12345678901234567890123456789.
	b := 98765432109876543210.
	self assert: (a + b) printString = '12345678999999999999999999999'.
	self assert: (a - a) = 0.
	self assert: (a * b) // b = a.
	self assert: (a * b) \\ b = 0.
	self assert: (a * b + 17) \\ b = 17.
	self assert: (a quo: b) = 124999998.
	self assert: (a rem: b) = (a - (124999998 * b)).
	self assert: (a negated // b) = -124999999.
	self assert: (a negated \\ b) = (b - (a rem: b)).
	self assert: (a gcd: a * 3) = a.
	self assert: ((2 raisedTo: 100) sqrtFloor) = (2 raisedTo: 50).
	self assert: (2 raisedTo: 100) printString = '1267650600228229401496703205376'.
	self assert: ((2 raisedTo: 100) / (2 raisedTo: 98)) = 4.
	self assert: ((2 raisedTo: 100) / 3) class == Fraction.
	self assert: (10 raisedTo: 30) / (10 raisedTo: 28) = 100
!
testDivisionIdentity
	"x = (x // y) * y + (x \\ y) and |x \\ y| < |y| for many sizes and signs."
	| random |
	random := Random seed: 42.
	1 to: 60 do: [:i |
		| x y q r |
		x := (random nextInt: 1000000000) * (10 raisedTo: (random nextInt: 40)) + (random nextInt: 1000).
		y := (random nextInt: 1000000) * (10 raisedTo: (random nextInt: 25)) + 1.
		i odd ifTrue: [x := x negated].
		i \\ 3 = 0 ifTrue: [y := y negated].
		q := x // y.
		r := x \\ y.
		self assert: q * y + r = x.
		self assert: r abs < y abs.
		self assert: (r = 0 or: [r negative = y negative]).
		self assert: (x quo: y) * y + (x rem: y) = x]
!
testFactorial
	self assert: 0 factorial = 1.
	self assert: 20 factorial = 2432902008176640000.
	self assert: 100 factorial printString = '93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000'.
	self assert: 1000 factorial printString size = 2568.
	self assert: 100 factorial / 98 factorial = 9900.
	self assert: (1000 factorial // 999 factorial) = 1000.
	"factorial multiplies by binary splitting; one factor at a time agrees"
	self assert: 700 factorial = ((1 to: 700) inject: 1 into: [:product :each | product * each]).
	self assert: (2 raisedTo: 333) * 16rFFFFFF = ((2 raisedTo: 333) * (16rFFFFFF * (2 raisedTo: 100)) bitShift: -100)
!
testLimbBoundaries
	"Carries and borrows across whole 32-bit limbs, shifts by limb and byte amounts, printing chunks."
	#(1 2 3 7 8 9 31 32 33) do: [:k | | p |
		p := 2 raisedTo: 32 * k.
		self assert: (p - 1) + 1 = p.
		self assert: p - 1 + p = ((p bitShift: 1) - 1).
		self assert: (p + 1) - 2 = (p - 1).
		self assert: p - (p - 1) = 1.
		self assert: ((p - 1) bitShift: 8) = (p * 256 - 256).
		self assert: ((p - 1) bitShift: -8) = (p // 256 - 1).
		self assert: ((p - 1) * 16r3FFFFFFF) // 16r3FFFFFFF = (p - 1).
		self assert: ((p - 1) * 16r3FFFFFFF) \\ (p - 1) = 0.
		self assert: (p * 1000000000) printString = (p printString , '000000000').
		self assert: (p - 1) negated printString = ('-' , (p - 1) printString)].
	self assert: (10 raisedTo: 36) printString = ('1' , (String new: 36 withAll: $0)).
	self assert: ((10 raisedTo: 36) - 1) printString = (String new: 36 withAll: $9)
!
testLimbBoundaries64
	"The primitives' 64-bit limbs: carries and borrows across whole limbs, one-limb LargeIntegers between the SmallInteger range and 2^64 (both signs), shifts by about one and two limbs, products and quotients of all-ones limbs."
	| m |
	#(1 2 3 7 8 9) do: [:k | | p |
		p := 2 raisedTo: 64 * k.
		self assert: (p - 1) + 1 = p.
		self assert: p - 1 + p = ((p bitShift: 1) - 1).
		self assert: p - (p - 1) = 1.
		self assert: (p - 1) * (p - 1) = ((p * p) - (p bitShift: 1) + 1).
		self assert: (p - 1) * (p + 1) // (p + 1) = (p - 1).
		self assert: ((p - 1) * (p + 1)) \\ (p - 1) = 0.
		#(63 64 65 127 128 129) do: [:s |
			self assert: (((p - 1) bitShift: s) bitShift: s negated) = (p - 1).
			self assert: ((p - 1) bitShift: s) = ((p - 1) * (1 bitShift: s))]].
	m := SmallInteger maxVal.
	#(1 2 3) do: [:d |
		self assert: (m + d) - d = m.
		self assert: ((m + d) - d) class = SmallInteger.
		self assert: (m + d) class ~= SmallInteger.
		self assert: (m + d) negated + d = (m negated).
		self assertNormalized: (m + d) - d].
	self assert: (16rFFFFFFFFFFFFFFFF + 1) = (1 bitShift: 64).
	self assert: (1 bitShift: 64) - 1 = 16rFFFFFFFFFFFFFFFF.
	self assert: 16rFFFFFFFFFFFFFFFF * 16rFFFFFFFFFFFFFFFF = ((1 bitShift: 128) - (1 bitShift: 65) + 1).
	self assert: 16rFFFFFFFFFFFFFFFF negated - 1 = (1 bitShift: 64) negated.
	self assert: (16rFFFFFFFFFFFFFFFF bitAnd: 16rFFFFFFFFFFFFFFFF negated) = 1
!
testKnuthDivision64
	"With 64-bit limbs: u = (2^64 - 1) * 2^e by v = 2^e + 1 (128 <= e < 192) takes the step that adds the divisor back; u = 2^64 * v - 1 has a top limb equal to the divisor's (the largest quotient limb, estimated without dividing); divisors whose top limb has 0 to 63 leading zero bits."
	128 to: 191 do: [:e | | u v |
		u := 16rFFFFFFFFFFFFFFFF bitShift: e.
		v := (1 bitShift: e) + 1.
		self assert: u // v = 16rFFFFFFFFFFFFFFFE.
		self assert: u \\ v = ((1 bitShift: e) - 16rFFFFFFFFFFFFFFFE).
		self assert: (u negated quo: v) = -16rFFFFFFFFFFFFFFFE.
		self assert: (u negated rem: v) = (u \\ v) negated].
	#(64 65 100 127 128 129 191 192 300) do: [:bits | | v u |
		v := (1 bitShift: bits) + 16r123456789ABCDEF.
		u := (v bitShift: 64) - 1.
		self assert: u // v = 16rFFFFFFFFFFFFFFFF.
		self assert: u \\ v = (v - 1).
		u := (v bitShift: 128) + v - 1.
		self assert: u // v = (1 bitShift: 128).
		self assert: u // v * v + (u \\ v) = u].
	0 to: 63 do: [:z | | v q |
		v := (1 bitShift: 191 - z) + 12345.
		q := (1 bitShift: 200) - 3.
		self assert: q * v + 7 // v = q.
		self assert: q * v + 7 \\ v = 7]
!
testLargeProducts
	"Balanced and lopsided products, all-ones limbs (the largest carries), squares."
	#(#(1 1) #(2 1) #(59 59) #(61 75) #(64 300) #(300 64) #(250 250)) do: [:sizes | | a b |
		a := (1 bitShift: 32 * sizes first) - 1.
		b := (1 bitShift: 32 * sizes last) - 1.
		self assert: a * b = ((1 bitShift: 32 * (sizes first + sizes last)) - a - b - 1).
		self assert: a negated * b = (a * b) negated.
		self assert: (a + 1) * (b + 1) = (1 bitShift: 32 * (sizes first + sizes last))].
	self assert: (2 raisedTo: 9000) - 1 * ((2 raisedTo: 7000) + 1) = ((2 raisedTo: 16000) + (2 raisedTo: 9000) - (2 raisedTo: 7000) - 1).
	self assert: (10 raisedTo: 400) * (10 raisedTo: 300) = (10 raisedTo: 700).
	self assert: ((10 raisedTo: 300) + 1) squared printString = ('1' , (String new: 299 withAll: $0) , '2' , (String new: 299 withAll: $0) , '1')
!
testRandomIdentities
	"Random operands of up to 300 bytes and both signs: both divisions' identities and remainder signs, products, sums, comparisons; results in the SmallInteger range are SmallIntegers."
	| random |
	random := Random seed: 7.
	1 to: 400 do: [:i | | a b q r |
		a := self randomInteger: (i \\ 10 = 0 ifTrue: [300] ifFalse: [40]) from: random.
		b := self randomInteger: (i \\ 7 = 0 ifTrue: [150] ifFalse: [30]) from: random.
		b = 0 ifTrue: [b := -1].
		q := a // b.
		r := a \\ b.
		self assert: q * b + r = a.
		self assert: r abs < b abs.
		self assert: (r = 0 or: [r negative = b negative]).
		self assertNormalized: q; assertNormalized: r.
		q := a quo: b.
		r := a rem: b.
		self assert: q * b + r = a.
		self assert: r abs < b abs.
		self assert: (r = 0 or: [r negative = a negative]).
		self assertNormalized: q; assertNormalized: r.
		self assert: a * b // b = a.
		self assert: a * b \\ b = 0.
		self assert: a * b = (b * a).
		self assert: (a + b) * (a - b) = (a * a - (b * b)).
		self assert: a + b - b = a.
		self assert: a - b = (b - a) negated.
		self assert: (a < b) = (a - b) negative.
		self assert: (a >= b) = (a - b) negative not.
		self assert: (a = b) = (a - b = 0).
		self assertNormalized: a + b; assertNormalized: a - b; assertNormalized: a * b]
!
testKnuthDivision
	"Divisors of several limbs whose top limb has 0 to 31 leading zero bits; u = (2^32 - 1) * 2^e by v = 2^e + 1 (64 <= e < 96) takes the rare step that adds the divisor back; quotients of all-ones limbs."
	64 to: 95 do: [:e | | u v |
		u := 16rFFFFFFFF bitShift: e.
		v := (1 bitShift: e) + 1.
		self assert: u // v = 16rFFFFFFFE.
		self assert: u \\ v = ((1 bitShift: e) - 16rFFFFFFFE).
		self assert: u negated // v = -16rFFFFFFFF.
		self assert: u negated \\ v = (v - (u \\ v)).
		self assert: (u negated quo: v) = -16rFFFFFFFE.
		self assert: (u negated rem: v) = (u \\ v) negated].
	#(1 31 32 33 63 64 65 95 96 127 128 200) do: [:bits | | v q |
		v := (1 bitShift: bits) + 16r123456789.
		q := (1 bitShift: 320) - 1.
		self assert: q * v + v - 1 // v = q.
		self assert: q * v + v - 1 \\ v = (v - 1).
		self assert: (q * v) negated - 1 // v = (q + 1) negated.
		self assert: (q * v) negated - 1 \\ v = (v - 1)]
!
testBitShiftRoundTrips
	"Left then right shifts give the receiver back; right shifts round toward negative infinity as // does."
	| random |
	random := Random seed: 11.
	1 to: 200 do: [:i | | a k |
		a := self randomInteger: 50 from: random.
		k := random nextInt: 300.
		self assert: ((a bitShift: k) bitShift: k negated) = a.
		self assert: (a bitShift: k) = (a * (1 bitShift: k)).
		self assert: (a bitShift: k negated) = (a // (1 bitShift: k)).
		self assertNormalized: (a bitShift: k negated)].
	self assert: ((1 bitShift: 100) negated bitShift: -101) = -1.
	self assert: (-1 bitShift: -1000) = -1.
	self assert: ((1 bitShift: 100) bitShift: (1 bitShift: 70) negated) = 0.
	self assert: ((1 bitShift: 100) negated bitShift: (1 bitShift: 70) negated) = -1.
	self assert: (0 bitShift: (1 bitShift: 70)) = 0.
	self should: [1 bitShift: (1 bitShift: 40)] raise: OutOfMemory
!
testLargeBitOperations
	"Two's complement semantics for operands of both signs and all sizes."
	| random |
	random := Random seed: 13.
	1 to: 200 do: [:i | | a b |
		a := self randomInteger: 30 from: random.
		b := self randomInteger: 30 from: random.
		self assert: (a bitAnd: b) + (a bitOr: b) = (a + b).
		self assert: (a bitXor: b) = ((a bitOr: b) - (a bitAnd: b)).
		self assert: (a bitAnd: b) bitInvert = (a bitInvert bitOr: b bitInvert).
		self assert: (a bitXor: a) = 0.
		self assert: (a bitAnd: a bitInvert) = 0.
		self assert: (a bitOr: a bitInvert) = -1.
		self assert: (a bitAnd: 16rFF) = (a \\ 256)].
	self assert: ((-1 bitShift: 64) bitAnd: (1 bitShift: 70) - 1) = ((1 bitShift: 70) - (1 bitShift: 64)).
	self assert: ((1 bitShift: 64) negated bitOr: 1) = ((1 bitShift: 64) negated + 1).
	self assert: ((1 bitShift: 64) negated bitXor: -1) = ((1 bitShift: 64) - 1).
	self assert: (SmallInteger minVal bitXor: (1 bitShift: 64) negated) = ((1 bitShift: 64) - (1 bitShift: 62)).
	self should: [(1 bitShift: 70) bitAnd: 1.5] raise: Error
!
testPrintParseRoundTrips
	| random |
	random := Random seed: 17.
	1 to: 100 do: [:i | | a |
		a := self randomInteger: 60 from: random.
		self assert: (Integer readFrom: a printString) = a.
		#(2 10 16 36) do: [:base | self assert: (Number readFrom: (a printStringRadix: base)) = a]].
	self assert: (2 raisedTo: 64) printString = '18446744073709551616'.
	self assert: ((2 raisedTo: 64) - 1) negated printString = '-18446744073709551615'.
	self assert: ((2 raisedTo: 128) - 1) printStringHex = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'.
	self assert: 30 factorial = 265252859812191058636308480000000.
	self assert: 1000 factorial \\ 1000000007 = 641419708
!
testSmallIntegerBounds
	"Results just inside the SmallInteger range are SmallIntegers, just outside LargeIntegers, whatever the operation."
	| max min |
	max := SmallInteger maxVal.
	min := SmallInteger minVal.
	self assert: (min - 1 + 1) class == SmallInteger.
	self assert: (max + 1) negated == min.
	self assert: min negated = (max + 1).
	self assert: min // -1 = (max + 1).
	self assert: (min quo: -1) = (max + 1).
	self assert: (min rem: -1) = 0.
	self assert: min * -1 = (max + 1).
	self assert: (max + 1) // -1 == min.
	self assert: (max + 1) - 1 == max.
	self assert: ((max + 1) bitShift: -1) class == SmallInteger.
	self assert: (min bitShift: 1) class == LargeNegativeInteger.
	self assert: ((max + 1) * 2 bitAnd: max) == 0.
	self assert: ((max + 1) bitXor: (max + 1)) == 0.
	self assert: (1 bitShift: 64) - 1 + 1 = (1 bitShift: 64).
	self assert: (1 bitShift: 64) negated - 1 // (1 bitShift: 64) = -2.
	self assert: (1 bitShift: 64) * (1 bitShift: 64) = (1 bitShift: 128).
	self assert: (1 bitShift: 64) * 0.5 = 9223372036854775808.0.
	self assert: (1 bitShift: 64) * (1 / 3) * 3 = (1 bitShift: 64)
!
testPrinting
	self assert: 0 printString = '0'.
	self assert: -42 printString = '-42'.
	self assert: (255 printString: 16) = 'FF'.
	self assert: (255 radix: 16) = 'FF'.
	self assert: (255 printStringRadix: 16) = '16rFF'.
	self assert: (-255 printStringRadix: 2) = '-2r11111111'.
	self assert: (5 printPaddedWith: $0 to: 3) = '005'.
	self assert: SmallInteger minVal printString = '-4611686018427387904'.
	self assert: ((2 raisedTo: 70) printString: 16) = '400000000000000000'.
	self assert: 1234567 asStringWithCommas = '1,234,567'.
	self assert: 16rFF = 255.
	self assert: 2r1010 = 10.
	self assert: 36rZZ = 1295
!
testNumberTheory
	self assert: (12 gcd: 18) = 6.
	self assert: (12 lcm: 18) = 36.
	self assert: (-12 gcd: 18) = 6.
	self assert: 97 isPrime.
	self deny: 91 isPrime.
	self deny: 1 isPrime.
	self assert: 2 isPrime.
	self assert: 17 sqrtFloor = 4.
	self assert: 16 sqrtFloor = 4.
	self assert: 4 even.
	self assert: 5 odd.
	self assert: (SmallInteger maxVal + 1) even.
	self assert: (3 raisedTo: 200 modulo: 1000) = ((3 raisedTo: 200) \\ 1000)
!
testBitOperations
	self assert: (12 bitAnd: 10) = 8.
	self assert: (12 bitOr: 10) = 14.
	self assert: (12 bitXor: 10) = 6.
	self assert: (1 bitShift: 10) = 1024.
	self assert: (1024 bitShift: -10) = 1.
	self assert: (-1 bitShift: -5) = -1.
	self assert: (-16 bitShift: -2) = -4.
	self assert: (1 bitShift: 100) = (2 raisedTo: 100).
	self assert: ((1 bitShift: 100) bitShift: -100) = 1.
	self assert: ((2 raisedTo: 100) negated bitShift: -99) = -2.
	self assert: (((2 raisedTo: 100) + 5) bitAnd: 16rFF) = 5.
	self assert: ((2 raisedTo: 100) bitOr: 1) = ((2 raisedTo: 100) + 1).
	self assert: (-1 bitAnd: (2 raisedTo: 80)) = (2 raisedTo: 80).
	self assert: ((2 raisedTo: 80) negated bitAnd: 16rFFFF) = 0.
	self assert: (((2 raisedTo: 80) - 1) bitXor: ((2 raisedTo: 80) - 1)) = 0.
	self assert: (5 bitAt: 1) = 1.
	self assert: (5 bitAt: 2) = 0.
	self assert: 255 highBit = 8.
	self assert: (2 raisedTo: 100) highBit = 101.
	self assert: 12 lowBit = 3.
	self assert: 0 bitInvert = -1
!
testIteration
	| count sum |
	count := 0.
	5 timesRepeat: [count := count + 1].
	self assert: count = 5.
	sum := 0.
	1 to: 10 do: [:i | sum := sum + i].
	self assert: sum = 55.
	sum := 0.
	10 to: 1 by: -2 do: [:i | sum := sum + i].
	self assert: sum = 30.
	sum := 0.
	1 perform: #to:do: with: 4 with: [:i | sum := sum + i].
	self assert: sum = 10.
	count := 0.
	3 perform: #timesRepeat: with: [count := count + 1].
	self assert: count = 3.
	self assert: (1 to: 5) asArray = #(1 2 3 4 5)
!
testConversion
	self assert: 3 asFloat = 3.0.
	self assert: 3 asFloat class == SmallFloat64.
	self assert: (2 raisedTo: 70) asFloat = 1180591620717411303424.0.
	self assert: ((2 raisedTo: 70) + 1) asFloat = (2 raisedTo: 70) asFloat.
	self assert: 65 asCharacter = $A.
	self assert: '42' asNumber = 42.
	self assert: '-17' asInteger = -17.
	self assert: 'abc' asNumber isNil.
	self assert: (Integer readFrom: '123') = 123.
	self assert: (Number readFrom: '16r1F') = 31.
	self assert: (Number readFrom: '3/4') = (3 / 4).
	self assert: '123456789012345678901234567890' asNumber = 123456789012345678901234567890
!
testDivisionByZero
	self should: [1 / 0] raise: ZeroDivide.
	self should: [1 // 0] raise: ZeroDivide.
	self should: [1 \\ 0] raise: ZeroDivide.
	self should: [(2 raisedTo: 100) // 0] raise: ZeroDivide.
	self assert: ([1 / 0] on: ZeroDivide do: [:e | e return: e dividend]) = 1.
	self assert: ([1 / 0] on: ZeroDivide do: [:e | e resume: 7]) = 7
!
testComparisonWithOtherNumbers
	self assert: 1 = 1.0.
	self assert: 1 < 1.5.
	self assert: 2 > (3 / 2).
	self assert: (2 raisedTo: 70) > 1.0.
	self assert: (2 raisedTo: 70) = (2 raisedTo: 70) asFloat.
	self deny: 1 = 'one'.
	self deny: 1 = nil.
	self assert: 1 ~= 'one'
! !

!IntegerTest methodsFor: 'private'!
randomInteger: maxBytes from: random
	"Up to maxBytes random bytes and a random sign; bytes 0 and 255 are frequent, for long carries and borrows."
	| n |
	n := 0.
	(random nextInt: maxBytes) timesRepeat: [
		n := (n bitShift: 8) + ((random nextInt: 4) = 1 ifTrue: [#(0 255) at: (random nextInt: 2)] ifFalse: [(random nextInt: 256) - 1])].
	^(random nextInt: 2) = 1 ifTrue: [n negated] ifFalse: [n]
!
assertNormalized: anInteger
	"A SmallInteger exactly when it fits one; a LargeInteger without leading zero bytes."
	self assert: anInteger class == SmallInteger equals: (anInteger between: SmallInteger minVal and: SmallInteger maxVal).
	anInteger class == SmallInteger ifFalse: [self assert: (anInteger digitAt: anInteger digitLength) ~= 0]
! !
