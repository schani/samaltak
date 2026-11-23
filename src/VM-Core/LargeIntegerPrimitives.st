VMPrimitiveModule subclass: #LargeIntegerPrimitives
	instanceVariableNames: 'scratch scratchLimbs'
	classVariableNames: ''
	package: 'VM-Core'!

LargeIntegerPrimitives comment: 'Integer arithmetic beyond SmallIntegers, after Squeak''s LargeIntegersPlugin: add, subtract, compare, multiply (schoolbook), divide (Knuth''s algorithm D), shifts and two''s complement bit operations. Operands are SmallIntegers and LargePositive/NegativeIntegers, read as 64-bit limbs (a LargeInteger''s magnitude bytes are little-endian, its slots the limbs) with 128-bit intermediates (mul64:by:plus:plus:high:, div128:low:by:remainder:). A result is computed into a scratch buffer kept between calls, then answered as a SmallInteger if it fits, else as a new LargeInteger without leading zero bytes. The primitives fail on other operands, on a zero divisor, and with PRIM_ERR_NO_MEMORY for results that can never fit the heap.'!

!LargeIntegerPrimitives class methodsFor: 'declaring'!
declarations
	^#((scratch 'uint64_t *') (scratchLimbs int64_t))
! !

!LargeIntegerPrimitives methodsFor: 'operands'!
operand: o into: x
	"x := the Integer o: its magnitude as 64-bit limbs, least significant first (o's slots, whose bytes past its size are zero; or x's own one for a SmallInteger), their number without leading zero limbs, and its sign (never negative for zero). False if o is no Integer."
	<function>
	| v c p n |
	(self isInt: o) ifTrue: [
		v := self intVal: o.
		x small at: 0 put: (v < 0 ifTrue: [(0 - v) asUInt64] ifFalse: [v asUInt64]).
		x limbs: x small.
		x count: (v = 0 ifTrue: [0] ifFalse: [1]).
		x neg: v < 0.
		^true].
	((self isPtr: o) and: [(self formatOf: o) >= F_BYTES]) ifFalse: [^false].
	c := self rawClass: o.
	(c = (memory special: SO_LARGEPOS) or: [c = (memory special: SO_LARGENEG)]) ifFalse: [^false].
	p := self cCoerce: o + 16 to: 'uint64_t *'.
	n := ((memory byteSize: o) + 7 quo: 8) asInt64.
	[n > 0 and: [(p at: n - 1) = 0]] whileTrue: [n := n - 1].
	x limbs: p.
	x count: n.
	x neg: (n > 0 and: [c = (memory special: SO_LARGENEG)]).
	^true
!
operands: a and: b
	"Fill a and b with the receiver and the argument; false if either is no Integer."
	^(self operand: self receiver into: a) and: [self operand: self arg0 into: b]
!
scratch: n
	"At least n limbs of scratch memory, kept for the next primitive; NULL if they cannot be had."
	<function>
	| cap |
	n > scratchLimbs ifTrue: [
		cap := n > (scratchLimbs * 2) ifTrue: [n] ifFalse: [scratchLimbs * 2].
		libc free: scratch.
		scratch := self cCoerce: (libc malloc: cap asUInt64 * 8) to: 'uint64_t *'.
		scratchLimbs := scratch isNull ifTrue: [0] ifFalse: [cap]].
	^scratch
!
fits: n
	"Whether a result of n limbs could fit the heap."
	^n * 8 <= gc maxHeapBytes asInt64
!
answer: r count: n negative: neg
	"Answer the Integer with the magnitude r (n limbs) and sign neg: a SmallInteger if it fits, else a new LargeInteger without leading zero bytes (its slots r's limbs, the top one's bytes past them zero; made without zeroing them first)."
	<function>
	<var: #m type: 'uint64_t'>
	<var: #top type: 'uint64_t'>
	| k m top used o |
	k := n.
	[k > 0 and: [(r at: k - 1) = 0]] whileTrue: [k := k - 1].
	k <= 1 ifTrue: [
		m := k = 0 ifTrue: [0] ifFalse: [r at: 0].
		m <= (neg ifTrue: [VM_INT_MAX asUInt64 + 1] ifFalse: [VM_INT_MAX asUInt64]) ifTrue: [
			^self answer: (self intOop: (neg ifTrue: [(0 - m) asInt64] ifFalse: [m asInt64]))]].
	top := r at: k - 1.
	used := 1.
	[used < 8 and: [(top >> (8 * used)) ~= 0]] whileTrue: [used := used + 1].
	o := memory
		allocUnfilledTry: (memory special: (neg ifTrue: [SO_LARGENEG] ifFalse: [SO_LARGEPOS]))
		format: F_BYTES + (8 - used) asInt32
		slots: k asUInt64.
	o = 0 ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	libc memcpy: (self bytesOf: o) from: r size: (k * 8) asUInt64.
	self answer: o
! !

!LargeIntegerPrimitives methodsFor: 'magnitudes'!
compare: a count: na with: b count: nb
	"-1, 0 or 1: the magnitude a against b (no leading zero limbs)."
	<function>
	| i |
	na ~= nb ifTrue: [^na < nb ifTrue: [-1] ifFalse: [1]].
	i := na - 1.
	[i >= 0 and: [(a at: i) = (b at: i)]] whileTrue: [i := i - 1].
	i < 0 ifTrue: [^0].
	^(a at: i) < (b at: i) ifTrue: [-1] ifFalse: [1]
!
sum: a count: na plus: b count: nb into: r
	"r := a + b (na >= nb); answer its limbs (na + 1 at most)."
	<function>
	<var: #carry type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	<var: #u type: 'uint64_t'>
	| carry x t u |
	carry := 0.
	0 to: nb - 1 do: [:i |
		x := a at: i.
		t := (x + (b at: i)) asUInt64.
		u := (t + carry) asUInt64.
		carry := (t < x or: [u < t]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64].
		r at: i put: u].
	nb to: na - 1 do: [:i |
		x := a at: i.
		u := (x + carry) asUInt64.
		carry := u < x ifTrue: [1 asUInt64] ifFalse: [0 asUInt64].
		r at: i put: u].
	r at: na put: carry.
	^na + 1
!
difference: a count: na minus: b count: nb into: r
	"r := a - b (a >= b, na >= nb); answer its limbs (na at most)."
	<function>
	<var: #borrow type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<var: #y type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	| borrow x y t |
	borrow := 0.
	0 to: nb - 1 do: [:i |
		x := a at: i.
		y := b at: i.
		t := (x - y) asUInt64.
		r at: i put: (t - borrow) asUInt64.
		borrow := (x < y or: [t < borrow]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
	nb to: na - 1 do: [:i |
		x := a at: i.
		r at: i put: (x - borrow) asUInt64.
		borrow := x < borrow ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
	^na
!
product: a count: na times: b count: nb into: r
	"r (na + nb limbs) := a * b, schoolbook: a row per limb of a (na >= 1), so a short a makes few passes over b; the first row writes r, the others add to it; each step a 64 x 64 bit product with what it adds (mul64:by:plus:plus:high:)."
	<function>
	<var: #ai type: 'uint64_t'>
	<var: #carry type: 'uint64_t'>
	| ai carry hi |
	hi := self local: 'uint64_t'.
	ai := a at: 0.
	carry := 0.
	0 to: nb - 1 do: [:j |
		r at: j put: (self mul64: ai by: (b at: j) plus: carry plus: 0 high: hi).
		carry := hi value].
	r at: nb put: carry.
	1 to: na - 1 do: [:i |
		ai := a at: i.
		carry := 0.
		0 to: nb - 1 do: [:j |
			r at: i + j put: (self mul64: ai by: (b at: j) plus: carry plus: (r at: i + j) high: hi).
			carry := hi value].
		r at: i + nb put: carry]
!
estimate: qhat times: v exceeds: rhat low: u
	"Whether qhat * v exceeds rhat * 2^64 + u (algorithm D's test of a quotient limb)."
	<function>
	<var: #qhat type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	<var: #rhat type: 'uint64_t'>
	<var: #u type: 'uint64_t'>
	<var: #lo type: 'uint64_t'>
	| lo hi |
	hi := self local: 'uint64_t'.
	lo := self mul64: qhat by: v plus: 0 plus: 0 high: hi.
	^hi value > rhat or: [hi value = rhat and: [lo > u]]
!
divide: a count: na by: b count: nb quotient: q remainder: r work: w
	"q (na - nb + 1 limbs) := a quo: b and r (nb limbs) := a rem: b, for a >= b > 0 without leading zero limbs: short division by one limb, else Knuth's algorithm D (TAOCP 4.3.1) on a copy of a (w: na + 1 limbs) and b as they are: each quotient limb estimated from the top limbs of both shifted so that b's top bit is set (normalized: limb:of:shiftedBy:), 128 by 64 bits (div128:low:by:remainder:); subtracting its multiple of b from the remainder is the shifted subtraction scaled back, borrow and all, so neither number is shifted, nor the remainder back."
	<function>
	<var: #d type: 'uint64_t'>
	<var: #vTop type: 'uint64_t'>
	<var: #vNext type: 'uint64_t'>
	<var: #top type: 'uint64_t'>
	<var: #qhat type: 'uint64_t'>
	<var: #rhat type: 'uint64_t'>
	<var: #carry type: 'uint64_t'>
	<var: #borrow type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	<var: #u type: 'uint64_t'>
	<var: #p type: 'uint64_t'>
	| d rem hi s un vTop vNext top qhat rhat big carry borrow x t u p |
	rem := self local: 'uint64_t'.
	hi := self local: 'uint64_t'.
	nb = 1 ifTrue: [
		d := b at: 0.
		rem value: 0.
		na - 1 to: 0 by: -1 do: [:i | q at: i put: (self div128: rem value low: (a at: i) by: d remainder: rem)].
		r at: 0 put: rem value.
		^self].
	s := self leadingZeros: (b at: nb - 1).
	un := w.
	libc memcpy: un from: a size: (na * 8) asUInt64.
	un at: na put: 0.
	vTop := self limb: nb - 1 of: b shiftedBy: s.
	vNext := self limb: nb - 2 of: b shiftedBy: s.
	na - nb to: 0 by: -1 do: [:j |
		"the quotient limb estimated from the top two limbs, at most 2 too large; corrected with the next one"
		top := self limb: j + nb of: un shiftedBy: s.
		top >= vTop
			ifTrue: [
				"(the top limb is vTop then) the largest limb; a remainder estimate past 2^64 tests nothing"
				qhat := 16rFFFFFFFFFFFFFFFF.
				rhat := ((self limb: j + nb - 1 of: un shiftedBy: s) + vTop) asUInt64.
				big := rhat < vTop]
			ifFalse: [
				qhat := self div128: top low: (self limb: j + nb - 1 of: un shiftedBy: s) by: vTop remainder: rem.
				rhat := rem value.
				big := false].
		[big not and: [self estimate: qhat times: vNext exceeds: rhat low: (self limb: j + nb - 2 of: un shiftedBy: s)]] whileTrue: [
			qhat := qhat - 1.
			t := (rhat + vTop) asUInt64.
			big := t < rhat.
			rhat := t].
		"un[j .. j + nb] -= qhat * b"
		carry := 0.
		borrow := 0.
		0 to: nb - 1 do: [:i |
			p := self mul64: qhat by: (b at: i) plus: carry plus: 0 high: hi.
			carry := hi value.
			x := un at: i + j.
			t := (x - p) asUInt64.
			un at: i + j put: (t - borrow) asUInt64.
			borrow := (x < p or: [t < borrow]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
		x := un at: j + nb.
		t := (x - carry) asUInt64.
		un at: j + nb put: (t - borrow) asUInt64.
		(x < carry or: [t < borrow]) ifTrue: [
			"rarely, qhat was still one too large: add b back"
			qhat := qhat - 1.
			carry := 0.
			0 to: nb - 1 do: [:i |
				x := un at: i + j.
				t := (x + (b at: i)) asUInt64.
				u := (t + carry) asUInt64.
				un at: i + j put: u.
				carry := (t < x or: [u < t]) ifTrue: [1 asUInt64] ifFalse: [0 asUInt64]].
			un at: j + nb put: ((un at: j + nb) + carry) asUInt64].
		q at: j put: qhat].
	0 to: nb - 1 do: [:i | r at: i put: (un at: i)]
!
limb: i of: x shiftedBy: s
	"Limb i of x << s (s < 64): x's limb i shifted, below it what limb i - 1 shifts out (limb 0 has none below)."
	<function>
	<returns: 'uint64_t'>
	(s = 0 or: [i = 0]) ifTrue: [^((x at: i) << s) asUInt64].
	^((x at: i) << s) asUInt64 bitOr: (x at: i - 1) >> (64 - s)
!
leadingZeros: x
	"The number of leading zero bits of the nonzero 64-bit x."
	<var: #x type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	| v n |
	v := x.
	n := 0.
	[(v >> 63) = 0] whileTrue: [
		v := (v << 1) asUInt64.
		n := n + 1].
	^n
!
shift: x count: n left: k into: r
	"r (n + (k quo: 64) + 1 limbs) := x << k."
	<function>
	<var: #carry type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	| limbs bits carry v |
	limbs := k quo: 64.
	bits := k rem: 64.
	0 to: limbs - 1 do: [:i | r at: i put: 0].
	bits = 0 ifTrue: [
		0 to: n - 1 do: [:i | r at: limbs + i put: (x at: i)].
		r at: limbs + n put: 0.
		^self].
	carry := 0.
	0 to: n - 1 do: [:i |
		v := x at: i.
		r at: limbs + i put: ((v << bits) asUInt64 bitOr: carry).
		carry := v >> (64 - bits)].
	r at: limbs + n put: carry
!
shift: x count: n right: k into: r
	"r (n - (k quo: 64) limbs, k < 64 n) := x >> k; answer whether 1 bits were shifted out."
	<function>
	<var: #next type: 'uint64_t'>
	| limbs bits lost next |
	limbs := k quo: 64.
	bits := k rem: 64.
	lost := bits > 0 and: [((x at: limbs) << (64 - bits)) asUInt64 ~= 0].
	0 to: limbs - 1 do: [:i | (x at: i) ~= 0 ifTrue: [lost := true]].
	limbs to: n - 1 do: [:i |
		bits = 0
			ifTrue: [r at: i - limbs put: (x at: i)]
			ifFalse: [
				next := i + 1 < n ifTrue: [x at: i + 1] ifFalse: [0].
				r at: i - limbs put: (((x at: i) >> bits) bitOr: (next << (64 - bits)) asUInt64)]].
	^lost
!
increment: x count: n
	"x := x + 1 (room for n + 1 limbs); answer its limbs."
	<function>
	| i |
	i := 0.
	[i < n and: [(x at: i) = 16rFFFFFFFFFFFFFFFF]] whileTrue: [
		x at: i put: 0.
		i := i + 1].
	i = n ifTrue: [
		x at: n put: 1.
		^n + 1].
	x at: i put: ((x at: i) + 1) asUInt64.
	^n
!
lowest: x count: n
	"The index of x's lowest nonzero limb; n if there is none."
	<function>
	| i |
	i := 0.
	[i < n and: [(x at: i) = 0]] whileTrue: [i := i + 1].
	^i
!
limb: i of: x lowest: z
	"Limb i of x in two's complement (z: the index of x's lowest nonzero limb): for a negative x, ~(|x| - 1)."
	<function>
	<returns: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	| v |
	v := i < x count ifTrue: [x limbs at: i] ifFalse: [0].
	x neg ifFalse: [^v].
	i < z ifTrue: [^0].
	i = z ifTrue: [^(0 - v) asUInt64].
	^v bitInvert64
! !

!LargeIntegerPrimitives methodsFor: 'operations'!
add: subtract
	"The receiver plus the argument (minus it if subtract): magnitudes added if the signs agree, else the smaller subtracted from the larger."
	<function>
	| a b bneg r n |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	bneg := b neg ~= subtract.
	r := self scratch: (a count > b count ifTrue: [a count] ifFalse: [b count]) + 1.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	a neg = bneg ifTrue: [
		n := a count >= b count
			ifTrue: [self sum: a limbs count: a count plus: b limbs count: b count into: r]
			ifFalse: [self sum: b limbs count: b count plus: a limbs count: a count into: r].
		^self answer: r count: n negative: a neg].
	(self compare: a limbs count: a count with: b limbs count: b count) >= 0
		ifTrue: [self answer: r count: (self difference: a limbs count: a count minus: b limbs count: b count into: r) negative: a neg]
		ifFalse: [self answer: r count: (self difference: b limbs count: b count minus: a limbs count: a count into: r) negative: bneg]
!
divide: mode
	"The receiver divided by the argument: mode 0 quo:, 1 rem: (truncated), 2 //, 3 \\ (floored). Fails on a zero divisor."
	<function>
	| a b na nb w q rem qn rn neg floored |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	na := a count.
	nb := b count.
	nb = 0 ifTrue: [^self fail].
	w := self scratch: 2 * (na + nb) + 4.
	w isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	"q: na + 2 limbs, rem: nb, then the work area of na + nb + 2"
	q := w.
	rem := w + (na + 2).
	(self compare: a limbs count: na with: b limbs count: nb) < 0
		ifTrue: [
			q at: 0 put: 0.
			qn := 1.
			0 to: na - 1 do: [:i | rem at: i put: (a limbs at: i)].
			rn := na]
		ifFalse: [
			self divide: a limbs count: na by: b limbs count: nb quotient: q remainder: rem work: rem + nb.
			qn := na - nb + 1.
			rn := nb].
	neg := a neg ~= b neg.
	mode = 0 ifTrue: [^self answer: q count: qn negative: neg].
	mode = 1 ifTrue: [^self answer: rem count: rn negative: a neg].
	"floored: with differing signs and a remainder, the quotient is one less and the remainder the divisor's complement"
	floored := neg and: [(self lowest: rem count: rn) < rn].
	mode = 2 ifTrue: [^self answer: q count: (floored ifTrue: [self increment: q count: qn] ifFalse: [qn]) negative: neg].
	floored ifTrue: [^self answer: rem + nb count: (self difference: b limbs count: nb minus: rem count: rn into: rem + nb) negative: b neg].
	self answer: rem count: rn negative: a neg
!
bitOp: op
	"The receiver op the argument in two's complement (op 1 bitAnd:, 2 bitOr:, 3 bitXor:), on one more limb than the longer magnitude, so that the top limb holds the sign."
	<function>
	| a b n r za zb x y |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	n := (a count > b count ifTrue: [a count] ifFalse: [b count]) + 1.
	r := self scratch: n.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	za := self lowest: a limbs count: a count.
	zb := self lowest: b limbs count: b count.
	0 to: n - 1 do: [:i |
		x := self limb: i of: a lowest: za.
		y := self limb: i of: b lowest: zb.
		r at: i put: (op = 1 ifTrue: [x bitAnd: y] ifFalse: [op = 2 ifTrue: [x bitOr: y] ifFalse: [x bitXor: y]])].
	((r at: n - 1) >> 63) = 0 ifTrue: [^self answer: r count: n negative: false].
	"negative: the magnitude is the two's complement of r"
	za := self lowest: r count: n.
	r at: za put: (0 - (r at: za)) asUInt64.
	za + 1 to: n - 1 do: [:i | r at: i put: (r at: i) bitInvert64].
	self answer: r count: n negative: true
! !

!LargeIntegerPrimitives methodsFor: 'primitives'!
primLargeAdd
	<vmPrimitive: 20 name: 'largeAdd'>
	self add: false
!
primLargeSub
	<vmPrimitive: 21 name: 'largeSub'>
	self add: true
!
primLargeMul
	<vmPrimitive: 22 name: 'largeMul'>
	| a b n r |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	(a count = 0 or: [b count = 0]) ifTrue: [^self answer: (self intOop: 0)].
	n := a count + b count.
	(self fits: n) ifFalse: [^self failCode: PRIM_ERR_NO_MEMORY].
	r := self scratch: n.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	a count <= b count
		ifTrue: [self product: a limbs count: a count times: b limbs count: b count into: r]
		ifFalse: [self product: b limbs count: b count times: a limbs count: a count into: r].
	self answer: r count: n negative: a neg ~= b neg
!
primLargeQuo
	<vmPrimitive: 23 name: 'largeQuo'>
	self divide: 0
!
primLargeRem
	<vmPrimitive: 24 name: 'largeRem'>
	self divide: 1
!
primLargeFloorDiv
	<vmPrimitive: 25 name: 'largeFloorDiv'>
	self divide: 2
!
primLargeMod
	<vmPrimitive: 26 name: 'largeMod'>
	self divide: 3
!
primLargeCompare
	"-1, 0 or 1: the receiver compared with the argument."
	<vmPrimitive: 27 name: 'largeCompare'>
	<leaf>
	| a b c |
	a := self local: 'LargeOperand'.
	b := self local: 'LargeOperand'.
	(self operands: a and: b) ifFalse: [^self fail].
	a neg ~= b neg ifTrue: [^self answer: (self intOop: (a neg ifTrue: [-1] ifFalse: [1]))].
	c := self compare: a limbs count: a count with: b limbs count: b count.
	self answer: (self intOop: (a neg ifTrue: [0 - c] ifFalse: [c]))
!
primLargeBitAnd
	<vmPrimitive: 28 name: 'largeBitAnd'>
	self bitOp: 1
!
primLargeBitOr
	<vmPrimitive: 29 name: 'largeBitOr'>
	self bitOp: 2
!
primLargeBitXor
	<vmPrimitive: 30 name: 'largeBitXor'>
	self bitOp: 3
!
primLargeBitShift
	"Left for a positive argument; right for a negative one, rounding toward negative infinity: a negative magnitude that loses 1 bits gains one. Shifts beyond 2^40 bits never fit the heap (left) or leave nothing (right)."
	<vmPrimitive: 31 name: 'largeBitShift'>
	| a s m k n r |
	a := self local: 'LargeOperand'.
	s := self local: 'LargeOperand'.
	(self operands: a and: s) ifFalse: [^self fail].
	m := s count = 0 ifTrue: [0 asUInt64] ifFalse: [s limbs at: 0].
	(s count > 1 or: [m > 16r10000000000]) ifTrue: [m := 16r10000000000 asUInt64].
	k := m asInt64.
	a count = 0 ifTrue: [^self answer: (self intOop: 0)].
	s neg ifFalse: [
		n := a count + (k quo: 64) + 1.
		(self fits: n) ifFalse: [^self failCode: PRIM_ERR_NO_MEMORY].
		r := self scratch: n.
		r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
		self shift: a limbs count: a count left: k into: r.
		^self answer: r count: n negative: a neg].
	(k quo: 64) >= a count ifTrue: [^self answer: (self intOop: (a neg ifTrue: [-1] ifFalse: [0]))].
	n := a count - (k quo: 64).
	r := self scratch: n + 1.
	r isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	((self shift: a limbs count: a count right: k into: r) and: [a neg]) ifTrue: [n := self increment: r count: n].
	self answer: r count: n negative: a neg
! !

VMStruct subclass: #LargeOperand
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

LargeOperand comment: 'An Integer operand of LargeIntegerPrimitives: its magnitude as count 64-bit limbs at limbs (least significant first; small holds the one of a SmallInteger) and its sign.'!

!LargeOperand class methodsFor: 'declaring'!
fields
	^#((limbs 'uint64_t *') (count int64_t) (neg bool) (small 'uint64_t[1]'))
! !
