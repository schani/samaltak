TestCase subclass: #HashingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

HashingTest comment: 'Tests hash consistency, the hashed collections (Set, IdentitySet, Dictionary, IdentityDictionary) under growth and removal, and how common keys spread over the slots: every element should lie close to its home slot, hash \\ capacity + 1.'!

!HashingTest methodsFor: 'tests'!
testEqualObjectsHaveEqualHashes
	self assert: 'abc' hash = 'abc' copy hash.
	self assert: 'abc' hash = #abc hash.
	self assert: (String with: (Character value: 955)) hash = (String with: (Character value: 955)) asWideString hash.
	self assert: 3 hash = 3.0 hash.
	self assert: (1 / 2) hash = 0.5 hash.
	self assert: (2 raisedTo: 80) hash = ((2 raisedTo: 80) + 1 - 1) hash.
	self assert: (2 raisedTo: 80) hash = (2 raisedTo: 80) asFloat hash.
	self assert: #(1 2 3) hash = (Array with: 1 with: 2 with: 3) hash.
	self assert: (1 -> 2) hash = (1 -> 2) hash.
	self assert: (3 @ 4) hash = (3 @ 4) hash.
	self assert: (1 @ 2) hash = (1.0 @ 2.0) hash.
	self assert: (1 to: 3) hash = #(1 2 3) hash.
	self assert: (1 @ 2 corner: 3 @ 4) hash = (1 @ 2 corner: 3 @ 4) hash.
	self assert: 1.5 hash = (3 / 2) hash.
	self assert: -0.375 hash = (-3 / 8) hash.
	self assert: 0.0 hash = -0.0 hash.
	self assert: 0.0 hash = 0 hash.
	self assert: (2 raisedTo: 80) negated hash = (2 raisedTo: 80) negated asFloat hash.
	self assert: (2 raisedTo: 1000) hash = (2 raisedTo: 1000) asFloat hash.
	self assert: (2 raisedTo: -1000) hash = (2 raisedTo: -1000) asFloat hash.
	self assert: (Set withAll: #(1 2)) hash = (Set withAll: #(2 1)) hash
!
testStringHash
	"String>>hash (the primitive) is its definition in Smalltalk (its fallback, the image builder's): of more than 8 code points all below 256 8 to a 64-bit word, else FNV-1a; equal for a ByteString, a WideString holding the same code points and a Symbol, every size to 40; and spread over the low bits, which hashed collections use."
	| def strings low |
	def := [:str | | m h w k |
		(str size <= 8 or: [str anySatisfy: [:c | c value > 255]])
			ifTrue: [
				h := 2166136261.
				str do: [:c | h := ((h bitXor: c value) * 16777619) bitAnd: 16rFFFFFFFF].
				h bitAnd: 16r3FFFFFFF]
			ifFalse: [
				m := 16rFFFFFFFFFFFFFFFF.
				h := str size.
				w := 0.
				k := 0.
				str do: [:c |
					w := w bitOr: (c value bitShift: 8 * k).
					k := k + 1.
					k = 8 ifTrue: [
						h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m.
						w := 0.
						k := 0]].
				k > 0 ifTrue: [h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m].
				h := h bitXor: (h bitShift: -32).
				h := (h * 16r2545F4914F6CDD1D) bitAnd: m.
				h := h bitXor: (h bitShift: -29).
				h bitAnd: 16r3FFFFFFF]].
	strings := (0 to: 40) collect: [:n | (String new: n) collect: [:x | Character value: 200 + n \\ 50]].
	strings := strings , ((0 to: 40) collect: [:n | String withAll: ((1 to: n) collect: [:i | Character value: 97 + (i * 7 \\ 26)])]).
	strings := strings , {String with: (Character value: 955). (String new: 9 withAll: $a) , (String with: (Character value: 300))}.
	strings do: [:str |
		self assert: str hash equals: (def value: str).
		self assert: str asWideString hash equals: str hash.
		self assert: str asSymbol hash equals: str hash].
	low := (1 to: 4096) collect: [:i | i printString hash bitAnd: 4095].
	self assert: low asSet size > 2400
!
testSet
	| s |
	s := Set new.
	1 to: 1000 do: [:i | s add: i printString].
	self assert: s size = 1000.
	self assert: (s includes: '500').
	self assert: (s includes: #'500').
	s add: '500'.
	self assert: s size = 1000.
	1 to: 1000 by: 2 do: [:i | s remove: i printString].
	self assert: s size = 500.
	self deny: (s includes: '1').
	2 to: 1000 by: 2 do: [:i | self assert: (s includes: i printString)].
	self assert: (s collect: [:x | x size]) = (Set withAll: #(1 2 3 4)).
	self should: [s add: nil] raise: Error.
	self assert: (Set withAll: #(1 2 3)) = (Set withAll: #(3 2 1))
!
testIdentitySet
	| s a b |
	a := 'x' copy.
	b := 'x' copy.
	s := IdentitySet new.
	s add: a; add: b.
	self assert: s size = 2.
	self assert: (s includes: a).
	self deny: (s includes: 'x' copy)
!
testDictionary
	| d |
	d := Dictionary new.
	1 to: 500 do: [:i | d at: i put: i * i].
	self assert: d size = 500.
	self assert: (d at: 20) = 400.
	self assert: (d at: 1000 ifAbsent: [#none]) = #none.
	1 to: 500 by: 3 do: [:i | d removeKey: i].
	self assert: d size = 333.
	self assert: (d includesKey: 2).
	self deny: (d includesKey: 1).
	2 to: 500 by: 3 do: [:i | self assert: (d at: i) = (i * i)].
	self assert: (d keyAtValue: 4) = 2.
	self assert: (d includes: 4).
	self should: [d at: 1] raise: KeyNotFound.
	self should: [d removeKey: 1] raise: KeyNotFound
!
testDictionaryProtocol
	| d |
	d := Dictionary new.
	d at: #a put: 1; at: #b put: 2.
	self assert: (d at: #c ifAbsentPut: [3]) = 3.
	self assert: (d at: #c ifAbsentPut: [4]) = 3.
	self assert: (d at: #a ifPresent: [:v | v * 10]) = 10.
	self assert: (d at: #z ifPresent: [:v | v]) isNil.
	self assert: d keys asSortedCollection asArray = #(#a #b #c).
	self assert: d values asSortedCollection asArray = #(1 2 3).
	self assert: (d collect: [:v | v * 2]) = (Dictionary new at: #a put: 2; at: #b put: 4; at: #c put: 6; yourself).
	self assert: (d select: [:v | v > 1]) size = 2.
	self assert: (d inject: 0 into: [:a :v | a + v]) = 6.
	self assert: (d associationAt: #a) key == #a.
	self assert: (d keysAndValuesDo: [:k :v | ]) == d.
	self assert: d copy = d.
	self deny: d copy == d.
	self assert: (Dictionary new at: #a put: 1; yourself) printString = 'a Dictionary(#a->1 )'.
	self assert: (Dictionary newFromPairs: #(1 2 3 4)) size = 2
!
testIdentityDictionary
	| d k1 k2 |
	k1 := 'key' copy.
	k2 := 'key' copy.
	d := IdentityDictionary new.
	d at: k1 put: 1; at: k2 put: 2.
	self assert: d size = 2.
	self assert: (d at: k1) = 1.
	self assert: (d at: k2) = 2.
	self assert: (d at: 'key' ifAbsent: [0]) = 0
!
testMixedKeys
	| d |
	d := Dictionary new.
	d at: 1 put: #int; at: 1.5 put: #float; at: 'one' put: #string; at: #sym put: #symbol; at: (1/3) put: #fraction; at: nil put: #nil.
	self assert: (d at: 1) == #int.
	self assert: (d at: 1.0) == #int.
	self assert: (d at: 3/2) == #float.
	self assert: (d at: #sym) == #symbol.
	self assert: (d at: 'one' copy) == #string.
	self assert: (d at: (2/6)) == #fraction.
	self assert: (d at: nil) == #nil
!
testRemovalAgainstAModel
	"Random adds and removes checked against an Array of flags, also with every key homed at the last slot so that clusters wrap around."
	| rnd |
	rnd := Random new seed: 4711.
	{Set. IdentitySet. Dictionary. IdentityDictionary} do: [:class | | capacity |
		capacity := class new capacity.
		self check: class with: rnd keys: ((1 to: capacity // 2) collect: [:i | capacity * i + capacity - 1]) operations: 2000.
		self check: class with: rnd keys: (1 to: 300) asArray operations: 5000]
!
testFloatHash
	"The primitive answers the fallback's function: murmur3's fmix64 of the bits, 30 of them; NaN and the infinities hash to constants."
	| rnd |
	self assert: Float nan hash = 16r7FF8.
	self assert: Float infinity hash = 16r7FF0.
	self assert: Float negativeInfinity hash = -16r7FF0.
	self assert: 3.0 hash = 3.
	self assert: 1.0e20 hash = 1.0e20 asExactFraction hash.
	rnd := Random new seed: 99.
	(#(0.1 -0.1 2.5 1.0e-300 -1.0e-310 123456.789) , ((1 to: 200) collect: [:i | rnd next * (10 raisedTo: i \\ 20)]))
		do: [:x | x fractionPart = 0.0 ifFalse: [self assert: x hash = (self fmix64: x asIEEEBits)]]
!
testHashMultiply
	self assert: 0 hashMultiply = 0.
	self assert: 1 hashMultiply = 1664525.
	self assert: 2 hashMultiply = (1664525 * 2).
	{-1. 16rFFFFFFF. 16r10000000. SmallInteger maxVal. SmallInteger minVal. 2 raisedTo: 100. (2 raisedTo: 100) negated} do: [:n |
		self assert: (n hashMultiply between: 0 and: 16rFFFFFFF)].
	self deny: 1 hashMultiply = (1 + (1 bitShift: 28)) hashMultiply.
	self deny: 1 hashMultiply = (1 + (1 bitShift: 40)) hashMultiply
! !

!HashingTest methodsFor: 'distribution'!
testCapacities
	| capacities |
	capacities := HashedCollection capacities.
	capacities do: [:p |
		self assert: p isPrime.
		1 to: 8 do: [:k | | r |
			r := (256 raisedTo: k) \\ p.
			p > 288 ifTrue: [self assert: (r > 32 and: [r < (p - 32)])].
			(p > 1024 and: [(256 raisedTo: 2 * k) >= p]) ifTrue: [
				self assert: (self shortestSquared: r modulo: p) * 4 >= p]]].
	2 to: capacities size do: [:i |
		self assert: (capacities at: i) > (capacities at: i - 1).
		self assert: (capacities at: i) * 5 <= ((capacities at: i - 1) * 8)].
	self assert: capacities last > (2 raisedTo: 31).
	self assert: (HashedCollection capacityAtLeast: 0) = capacities first.
	self assert: (HashedCollection capacityAtLeast: 12) = (capacities detect: [:p | p >= 12]).
	self assert: (HashedCollection capacityAtLeast: capacities last + 1) odd.
	self assert: (Set new: 100) capacity >= 200.
	self assert: Set new capacity = capacities first.
	self assert: Dictionary new capacity = capacities first
!
testConsecutiveIntegersStayHome
	| s |
	s := Set new.
	1 to: 300000 do: [:i | s add: i].
	self assert: (self displacementsOf: s) = #(0 0)
!
testAlignedIntegers
	| s d |
	s := Set new.
	d := Dictionary new.
	1 to: 20000 do: [:i | s add: i * 4096. d at: i * 4096 put: i].
	self assertSpread: s.
	self assertSpread: d
!
testPackedIntegers
	| s d |
	s := Set new.
	d := Dictionary new.
	0 to: 149 do: [:x | 0 to: 149 do: [:y | s add: x * 65536 + y. d at: x * 65536 + y put: x]].
	self assertSpread: s.
	self assertSpread: d
!
testHighBits
	"SmallIntegers that differ only in their high bits, alone or packed with low ones, of either sign or next to the ends of the range."
	#(31 32 40 47) do: [:shift | | s |
		s := Set new.
		1 to: 5000 do: [:i | s add: (i bitShift: shift); add: (i bitShift: shift) negated].
		self assertSpread: s].
	{32. 40} do: [:shift | | d |
		d := Dictionary new.
		0 to: 99 do: [:x | 0 to: 99 do: [:y | d at: (x bitShift: shift) + y put: x]].
		self assertSpread: d].
	self assertSpread: (Set withAll: ((1 to: 5000) collect: [:i | SmallInteger maxVal - (i bitShift: 33)])).
	self assertSpread: (Set withAll: ((1 to: 5000) collect: [:i | SmallInteger minVal + (i bitShift: 40)]))
!
testExtremeKeys
	"Negative keys, the ends of the SmallInteger range and the LargeIntegers next to them: found after growth, gone after removal."
	| keys s d |
	keys := {0. 1. -1. 16rFFFFFFFF. 16r100000000. -16r100000000. SmallInteger maxVal. SmallInteger minVal. SmallInteger maxVal + 1. SmallInteger minVal - 1. 2 raisedTo: 100. (2 raisedTo: 100) negated}.
	s := Set new.
	d := Dictionary new.
	keys do: [:k | s add: k. d at: k put: k negated].
	1 to: 1000 do: [:i | s add: i * 7919. d at: i * 7919 put: i].
	keys do: [:k |
		self assert: (s includes: k).
		self assert: (d at: k) = k negated].
	keys do: [:k | s remove: k. d removeKey: k].
	keys do: [:k |
		self deny: (s includes: k).
		self deny: (d includesKey: k)].
	self assert: s size = 1000.
	self assert: d size = 1000
!
testLargeIntegers
	| s base |
	s := Set new.
	base := 1 bitShift: 64.
	1 to: 20000 do: [:i | s add: base + (i * 1000003); add: (i bitShift: 70); add: (i bitShift: 70) negated].
	self assertSpread: s
!
testStrings
	| s |
	s := Set new.
	1 to: 20000 do: [:i | s add: i printString; add: 'key', i printString; add: (i printString: 16) asSymbol].
	self assertSpread: s
!
testIdentityHashes
	| s |
	s := IdentitySet new.
	10000 timesRepeat: [s add: Object new].
	self assertSpread: s
!
testFloats
	| rnd s |
	rnd := Random new seed: 777.
	s := Set new.
	50000 timesRepeat: [s add: (rnd nextInt: 5000000) + 0.5 / 100.0].
	self assertSpread: s
!
testFractions
	| s |
	s := Set new.
	1 to: 20000 do: [:i |
		i \\ 7 = 0 ifFalse: [s add: i / 7].
		i odd ifTrue: [s add: i / 1024]].
	self assertSpread: s
!
testPoints
	| d |
	d := Dictionary new.
	0 to: 119 do: [:x | 0 to: 119 do: [:y | d at: x @ y put: x * y]].
	self assertSpread: d
!
testArrays
	| d |
	d := Dictionary new.
	0 to: 99 do: [:x | 0 to: 99 do: [:y | d at: {x. y} put: x * y]].
	self assertSpread: d
! !

!HashingTest methodsFor: 'private'!
check: aClass with: aRandom keys: keys operations: n
	| c present isDictionary |
	c := aClass new.
	isDictionary := c isDictionary.
	present := Array new: keys size withAll: false.
	n timesRepeat: [| i k |
		i := aRandom nextInt: keys size.
		k := keys at: i.
		(aRandom nextInt: 2) = 1
			ifTrue: [
				isDictionary ifTrue: [c at: k put: k negated] ifFalse: [c add: k].
				present at: i put: true]
			ifFalse: [
				isDictionary ifTrue: [c removeKey: k ifAbsent: [nil]] ifFalse: [c remove: k ifAbsent: [nil]].
				present at: i put: false].
		self assert: c size = (present count: [:each | each]).
		keys doWithIndex: [:each :j |
			isDictionary
				ifTrue: [self assert: (c at: each ifAbsent: [nil]) = ((present at: j) ifTrue: [each negated] ifFalse: [nil])]
				ifFalse: [self assert: (c includes: each) = (present at: j)]]]
!
displacementsOf: aHashedCollection
	"Answer the average and the largest distance of an element from its home slot."
	| array size identity total max |
	array := aHashedCollection array.
	size := array size.
	identity := (aHashedCollection isKindOf: IdentitySet) or: [aHashedCollection isKindOf: IdentityDictionary].
	total := max := 0.
	1 to: size do: [:i | | key d |
		key := array at: i.
		key isNil ifFalse: [
			aHashedCollection isDictionary ifTrue: [key := key key].
			d := i - 1 - ((identity ifTrue: [key identityHash] ifFalse: [key hash]) \\ size) \\ size.
			total := total + d.
			max := max max: d]].
	^Array with: total / (aHashedCollection size max: 1) with: max
!
fmix64: bits
	| h |
	h := bits.
	h := h bitXor: (h bitShift: -33).
	h := h * 16rFF51AFD7ED558CCD bitAnd: 16rFFFFFFFFFFFFFFFF.
	h := h bitXor: (h bitShift: -33).
	h := h * 16rC4CEB9FE1A85EC53 bitAnd: 16rFFFFFFFFFFFFFFFF.
	h := h bitXor: (h bitShift: -33).
	^h bitAnd: 16r3FFFFFFF
!
shortestSquared: r modulo: p
	"Answer the squared length of the shortest nonzero (c, a) with c * r = a (mod p), by Gauss's lattice reduction."
	| u1 u2 v1 v2 n m t |
	u1 := 1. u2 := r. v1 := 0. v2 := p.
	[(v1 * v1) + (v2 * v2) < ((u1 * u1) + (u2 * u2)) ifTrue: [
		t := u1. u1 := v1. v1 := t.
		t := u2. u2 := v2. v2 := t].
	 n := (u1 * u1) + (u2 * u2).
	 m := (u1 * v1) + (u2 * v2) + (n // 2) // n.
	 m = 0] whileFalse: [
		v1 := v1 - (m * u1).
		v2 := v2 - (m * u2)].
	^n
!
assertSpread: aHashedCollection
	| displacements |
	displacements := self displacementsOf: aHashedCollection.
	self assert: displacements first <= 2.
	self assert: displacements last <= 32
! !
