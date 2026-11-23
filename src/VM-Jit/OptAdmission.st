OptModule subclass: #OptAdmission
	instanceVariableNames: 'ir builder passes adSeen adAlias adSmi adParams adSlots adLive adReceiver adNil adArgs adLocals adCapacity adDepth adRemaining adNode adArith adPrefixNodes adReplayState'
	classVariableNames: ''
	package: 'VM-Jit'!

OptAdmission comment: 'Admission only, read-only over cleaned optimizer IR. A two-block linear prefix starts in a fresh method and ends before its O_RETURN, which a future emitter must turn into an unconditional outside-native replay exit. Every failing guard and checked arithmetic operation has its own verified bytecode state. A normal optimizer return, interrupt path or deopt stub is not a C4 implementation of this contract.'!

!OptAdmission class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (builder OptBuilder) (passes OptPasses)
		(adSeen 'uint8_t[128]') (adAlias 'int32_t[128]') (adSmi 'uint8_t[128]')
		(adParams 'int32_t[17]') (adSlots 'int32_t[16]') (adLive 'uint32_t[64]')
		(adReceiver int32_t) (adNil int32_t) (adArgs int32_t) (adLocals int32_t) (adCapacity int32_t)
		(adDepth int32_t) (adRemaining int32_t) (adNode int32_t)
		(adArith int32_t) (adPrefixNodes int32_t) (adReplayState int32_t))
! !

!OptAdmission methodsFor: 'certificate'!
arithmetic
	^adArith
!
prefixNodes
	^adPrefixNodes
!
replayState
	"The certificate is valid only after successful verify, until IR or bytecode mutation."
	^adReplayState
!
replayPc
	^(ir state: adReplayState) pc
!
replayDepth
	^(ir state: adReplayState) depth
! !

!OptAdmission methodsFor: 'admission'!
verify: m
	"0 success; otherwise: 1 budget, 2 non-method/OSR, 3 activation,
	4 CFG, 5 checkpoint, 6 float/raw, 7 send, 8 allocation,
	9 unsupported node, 10 bytecodes, 11 source, 12 replay state,
	13 no arithmetic, 14 arithmetic form, 15 primitive.
	No frame or code pointer is retained; the certificate is for this IR only."
	<function>
	| ac size frame entry body e result prim |
	adReplayState := -1.
	size := self methodSize: m.
	(ir full or: [size <= 0 or: [size > 64 or: [ir nodeCount > 128 or: [ir blockCount > 16 or: [ir edgeCount > 32 or: [ir stateCount > 64 or: [ir operandCount > 512]]]]]]]) ifTrue: [^1].
	(builder isMethodUnit not or: [ir osrEntry ~= -1 or: [ir osrState ~= -1]]) ifTrue: [^2].
	ir actCount = 1 ifFalse: [^3].
	ac := ir act: 0.
	(ac method = m and: [ac home = 0 and: [ac parent = -1 and: [ac outer = -1 and: [ac closure = -1 and: [ac startpc = 0 and: [ac endpc = size]]]]]]) ifFalse: [^3].
	prim := self loadRef: m at: CM_PRIMITIVE.
	(prim = memory nilOop or: [(self isInt: prim) and: [(self intVal: prim) = 0]]) ifFalse: [^15].
	adArgs := ac numArgs.
	adLocals := adArgs + ac numTemps.
	frame := self intVal: (self loadRef: m at: CM_FRAMESIZE).
	(adArgs < 0 or: [ac numTemps < 0 or: [adLocals > 16 or: [frame < adLocals or: [frame > 16]]]]) ifTrue: [^1].
	adCapacity := frame asInt32.
	(builder paramSlots = adArgs and: [builder validSlots = adLocals]) ifFalse: [^3].

	"Even an optimized-away loop header is out. Check all live nodes by
	bounded array index first (also supplies specific rejection reasons)."
	0 to: ir blockCount - 1 do: [:i |
		((ir block: i) flags bitAnd: BF_LOOP) ~= 0 ifTrue: [^4]].
	0 to: ir nodeCount - 1 do: [:i |
		(ir node: i) block >= 0 ifTrue: [
			result := self nodeForm: (ir node: i).
			result ~= 0 ifTrue: [^result]]].

	ir blockCount = 2 ifFalse: [^4].
	passes orderCount = 2 ifFalse: [^4].
	entry := builder entryBlock.
	body := 1 - entry.
	(entry < 0 or: [entry > 1]) ifTrue: [^4].
	((passes orderAt: 0) = entry and: [(passes orderAt: 1) = body]) ifFalse: [^4].
	((ir block: entry) succ0 = body and: [(ir block: entry) npreds = 0 and: [(ir block: entry) preds = -1 and: [(ir block: body) succ0 = -1 and: [(ir block: body) npreds = 1]]]]) ifFalse: [^4].
	e := (ir block: body) preds.
	(e >= 0 and: [e < ir edgeCount and: [(ir edge: e) from = entry and: [(ir edge: e) next = -1]]]) ifFalse: [^4].
	0 to: 1 do: [:i |
		((ir block: i) succ1 = -1 and: [(ir block: i) entryState = -1]) ifFalse: [^5]].
	libc memset: adSeen value: 0 size: 128.
	(self suffixLiveness: (self methodBytecodes: m) size: size) ifFalse: [^10].
	adRemaining := ir nodeCount.
	adArith := 0.
	adPrefixNodes := 0.
	result := self entry: entry.
	result ~= 0 ifTrue: [^result].
	result := self body: body method: m size: size.
	result ~= 0 ifTrue: [^result].
	0 to: ir nodeCount - 1 do: [:i |
		((ir node: i) block >= 0 and: [(adSeen at: i) = 0]) ifTrue: [adReplayState := -1. ^4]].
	adArith = 0 ifTrue: [adReplayState := -1. ^13].
	^0
!
nodeForm: nd
	<var: #nd type: 'OptNode *'>
	| op rep |
	op := nd op asInt32.
	rep := nd rep asInt32.
	(rep = R_INT or: [rep = R_DBL or: [nd tkind asInt32 = T_FLOAT or: [op = O_BOXF or: [op = O_UNBOXF]]]]) ifTrue: [^6].
	(op = O_SEND or: [op = O_CALL]) ifTrue: [^7].
	(op = O_MKARRAY or: [op = O_CLOSURE or: [(nd flags bitAnd: NF_ALLOC) ~= 0]]) ifTrue: [^8].
	(op = O_CHECKINT and: [nd aux ~= SP_ENTRY]) ifTrue: [^5].
	(nd fwd ~= -1 or: [nd nargs ~= 0 or: [nd args ~= -1 or: [nd c ~= -1 or: [nd bcact ~= 0]]]]) ifTrue: [^9].
	(op = O_PARAM or: [op = O_CONST or: [op = O_GUARDINT or: [op = O_IADD or: [op = O_ISUB]]]]) ifTrue: [
		rep = R_OOP ifFalse: [^11].
		^0].
	(op = O_CHECKINT or: [op = O_GOTO or: [op = O_RETURN]]) ifTrue: [
		rep = R_NONE ifFalse: [^9].
		^0].
	^9
!
take: i block: b previous: prev
	"Read each linked list with explicit index/link/cycle checks and shared fuel."
	<function>
	| nd |
	(i < 0 or: [i >= ir nodeCount or: [adRemaining <= 0 or: [(adSeen at: i) ~= 0]]]) ifTrue: [^false].
	nd := ir node: i.
	(nd block = b and: [nd prev = prev]) ifFalse: [^false].
	adRemaining := adRemaining - 1.
	adPrefixNodes := adPrefixNodes + 1.
	adSeen at: i put: adPrefixNodes asUInt8.
	adAlias at: i put: i.
	adSmi at: i put: 0.
	^true
!
entry: b
	<function>
	| n prev nd op i check |
	0 to: adArgs do: [:k | adParams at: k put: -1].
	n := (ir block: b) first.
	prev := -1.
	check := -1.
	[n >= 0] whileTrue: [
		(self take: n block: b previous: prev) ifFalse: [^4].
		nd := ir node: n.
		(nd a ~= -1 or: [nd b ~= -1]) ifTrue: [^11].
		op := nd op asInt32.
		op = O_PARAM ifTrue: [
			(check >= 0 or: [nd aux < -1 or: [nd aux >= adArgs or: [nd flags ~= 0 or: [nd state ~= -1]]]]) ifTrue: [^11].
			i := nd aux asInt32 + 1.
			(adParams at: i) = -1 ifFalse: [^11].
			adParams at: i put: n].
		op = O_CONST ifTrue: [
			((self constantAllowed: nd aux asUInt64) and: [nd flags = NF_PURE and: [nd state = -1]]) ifFalse: [^11].
			(self isInt: nd aux asUInt64) ifTrue: [adSmi at: n put: 1]].
		op = O_CHECKINT ifTrue: [
			(check = -1 and: [nd flags = 0 and: [nd bcpc = 0]]) ifFalse: [^5].
			check := n].
		op = O_GOTO ifTrue: [
			(n = (ir block: b) last and: [nd next = -1 and: [nd flags = 0 and: [nd state = -1]]]) ifFalse: [^4]].
		(op = O_PARAM or: [op = O_CONST or: [op = O_CHECKINT or: [op = O_GOTO]]]) ifFalse: [^9].
		prev := n.
		n := nd next].
	(prev < 0 or: [n ~= -1 or: [prev ~= (ir block: b) last or: [(ir node: prev) op asInt32 ~= O_GOTO]]]) ifTrue: [^4].
	check < 0 ifTrue: [^5].
	adReceiver := adParams at: 0.
	(adReceiver >= 0 and: [adReceiver = (ir act: 0) receiver]) ifFalse: [^11].
	adNil := self constantId: memory nilOop.
	0 to: adArgs - 1 do: [:k |
		i := adParams at: k + 1.
		i < 0 ifTrue: [^11].
		adSlots at: k put: i].
	adArgs to: adLocals - 1 do: [:k | adSlots at: k put: adNil].
	adDepth := adLocals.
	(self state: (ir node: check) state at: 0 before: check) ifFalse: [^12].
	^0
!
constantAllowed: v
	<var: #v type: 'oop'>
	"Exactly the encoded SmallInteger or one of these three VM root sources."
	^(self isInt: v) or: [v = memory nilOop or: [v = memory trueOop or: [v = memory falseOop]]]
!
constantId: v
	<var: #v type: 'oop'>
	"-2 means no definition survived cleanup (fine unless a map/operation needs it)."
	0 to: ir nodeCount - 1 do: [:i |
		((adSeen at: i) ~= 0 and: [(ir node: i) op asInt32 = O_CONST and: [(ir node: i) aux asUInt64 = v]]) ifTrue: [^i]].
	^-2
!
available: v
	^v >= 0 and: [v < ir nodeCount and: [(adSeen at: v) ~= 0 and: [(adSeen at: v) < (adSeen at: adNode) and: [(ir node: v) rep asInt32 = R_OOP]]]]
!
state: s at: pc before: stop
	"Check the actual map, including dominance and the exact symbolic value
	of each bytecode slot. No forwarding walks. A nil substitution for a
	temp is allowed only if the independent suffix scan proves it dead."
	<function>
	| st base v saved |
	(s >= 0 and: [s < ir stateCount]) ifFalse: [^false].
	st := ir state: s.
	(st act = 0 and: [st parent = -1 and: [st flags = 0 and: [st pc = pc and: [st depth = adDepth]]]]) ifFalse: [^false].
	base := st vals.
	(base >= 0 and: [base < (ir operandCount - adDepth)]) ifFalse: [^false].
	saved := adNode.
	adNode := stop asInt32.
	v := ir operand: base.
	((self available: v) and: [v = adReceiver]) ifFalse: [adNode := saved. ^false].
	0 to: adDepth - 1 do: [:k |
		v := ir operand: base + k + 1.
		((self available: v) and: [
			(adAlias at: v) = (adSlots at: k) or: [
				v = adNil and: [k >= adArgs and: [k < adLocals and: [((adLive at: pc) bitAnd: 1 asUInt64 << k) = 0]]]]]) ifFalse: [adNode := saved. ^false]].
	adNode := saved.
	^true
! !

!OptAdmission methodsFor: 'bytecode proof'!
isFused: op
	^op = 16r9A or: [op = 16r9B or: [op = 16rF0 or: [op = 16rF1 or: [op = 16rF6 or: [op = 16rF7]]]]]
!
lengthOf: op
	(op = 16r80 or: [op = 16r82 or: [op = 16r84 or: [op = 16r87]]]) ifTrue: [^2].
	(op = 16r93 or: [self isFused: op]) ifTrue: [^3].
	^1
!
suffixLiveness: p size: size
	"Backward transfer on decoded instruction starts. Only accepted
	bytecodes can use this information: body: rejects all others."
	<function>
	<var: #p type: 'uint8_t *'>
	| offsets pc n op len live k |
	offsets := self local: 'uint8_t[64]'.
	pc := 0.
	n := 0.
	[pc < size] whileTrue: [
		len := self lengthOf: (p at: pc).
		pc + len > size ifTrue: [^false].
		offsets at: n put: pc asUInt8.
		n := n + 1.
		pc := pc + len].
	live := 0 asUInt64.
	n - 1 to: 0 by: -1 do: [:i |
		pc := (offsets at: i) asInt32.
		op := (p at: pc) asInt32.
		(op < 16r10 or: [op = 16r80]) ifTrue: [
			k := op = 16r80 ifTrue: [(p at: pc + 1) asInt32] ifFalse: [op].
			k < 16 ifTrue: [live := live bitOr: 1 asUInt64 << k]].
		(self isFused: op) ifTrue: [
			k := (p at: pc + 1) asInt32.
			k < 16 ifTrue: [live := live bitOr: 1 asUInt64 << k].
			op < 16rA0 ifTrue: [
				k := (p at: pc + 2) asInt32.
				k < 16 ifTrue: [live := live bitOr: 1 asUInt64 << k]]].
		((op >= 16r60 and: [op < 16r68]) or: [op = 16r84 or: [op = 16r87]]) ifTrue: [
			k := op < 16r68 ifTrue: [op - 16r60] ifFalse: [(p at: pc + 1) asInt32].
			k < 16 ifTrue: [live := live bitClear: 1 asUInt64 << k]].
		adLive at: pc put: live asUInt32].
	^true
!
push: v
	<function>
	adSlots at: adDepth put: v.
	adDepth := adDepth + 1
!
body: b method: m size: size
	"Decode a linear instruction stream from pc zero. Symbolically execute
	only frame/stack moves, and match each arithmetic bytecode against the
	next IR group. The terminal replay PC is the return instruction itself."
	<function>
	| pc op len idx nd prev p v lits x y arithOp fused |
	p := self methodBytecodes: m.
	lits := self loadRef: m at: CM_LITERALS.
	pc := 0.
	prev := -1.
	adNode := (ir block: b) first.
	[pc < size] whileTrue: [
		(builder isStart: pc act: 0) ifFalse: [^10].
		(builder depthAt: pc act: 0) = adDepth ifFalse: [^12].
		op := (p at: pc) asInt32.
		len := self lengthOf: op.
		pc + len > size ifTrue: [^10].
		(op = 16r79 or: [op = 16r7A]) ifTrue: [
			pc + 1 = size ifFalse: [^10].
			v := adReceiver.
			op = 16r79 ifTrue: [
				adDepth = (adLocals + 1) ifFalse: [^12].
				v := adSlots at: adDepth - 1].
			(op = 16r7A and: [adDepth ~= adLocals]) ifTrue: [^12].
			(self take: adNode block: b previous: prev) ifFalse: [^4].
			nd := ir node: adNode.
			(nd op asInt32 = O_RETURN and: [nd next = -1 and: [adNode = (ir block: b) last and: [nd bcpc = pc and: [nd b = -1 and: [nd flags = 0]]]]]) ifFalse: [^4].
			((self available: nd a) and: [(adAlias at: nd a) = v]) ifFalse: [^11].
			(self state: nd state at: pc before: adNode) ifFalse: [^12].
			adReplayState := nd state.
			^0].
		fused := self isFused: op.
		(fused or: [op = 16rA0 or: [op = 16rA1]]) ifTrue: [
			arithOp := (op = 16rA0 or: [op = 16r9A or: [op = 16rF0 or: [op = 16rF6]]]) ifTrue: [O_IADD] ifFalse: [O_ISUB].
			fused
				ifTrue: [
					adDepth + 2 > adCapacity ifTrue: [^12].
					idx := (p at: pc + 1) asInt32.
					idx >= adLocals ifTrue: [^10].
					x := adSlots at: idx.
					idx := (p at: pc + 2) asInt32.
					op < 16rA0
						ifTrue: [
							idx >= adLocals ifTrue: [^10].
							y := adSlots at: idx]
						ifFalse: [
							op < 16rF6
								ifTrue: [y := (self literalId: idx of: lits) asInt32]
								ifFalse: [y := self constantId: (self intOop: idx asInt8)]].
					y = -1 ifTrue: [^10]]
				ifFalse: [
					adDepth < (adLocals + 2) ifTrue: [^12].
					x := adSlots at: adDepth - 2.
					y := adSlots at: adDepth - 1].
			prev := self arithmetic: arithOp pc: pc block: b previous: prev left: x right: y.
			prev < 0 ifTrue: [^0 - prev].
			fused ifFalse: [adDepth := adDepth - 2].
			self push: prev]
		ifFalse: [
			(op = 16r78 or: [op = 16r84 or: [op = 16r87 or: [op >= 16r60 and: [op < 16r68]]]]) ifTrue: [
				adDepth <= adLocals ifTrue: [^12].
				op ~= 16r78 ifTrue: [
					idx := len = 1 ifTrue: [op - 16r60] ifFalse: [(p at: pc + 1) asInt32].
					(idx < adArgs or: [idx >= adLocals]) ifTrue: [^10].
					adSlots at: idx put: (adSlots at: adDepth - 1)].
				op ~= 16r84 ifTrue: [adDepth := adDepth - 1]]
			ifFalse: [
				adDepth >= adCapacity ifTrue: [^12].
				v := (self pushValue: op bytes: p pc: pc literals: lits) asInt32.
				v = -1 ifTrue: [^10].
				self push: v]].
		pc := pc + len].
	^10
!
pushValue: op bytes: p pc: pc literals: lits
	"Resolve a permitted push. -1: not in the language; -2: dead constant."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #lits type: 'oop'>
	| k |
	(op < 16r10 or: [op = 16r80]) ifTrue: [
		k := op = 16r80 ifTrue: [(p at: pc + 1) asInt32] ifFalse: [op].
		k >= adLocals ifTrue: [^-1].
		^adSlots at: k].
	op = 16r70 ifTrue: [^adReceiver].
	op = 16r71 ifTrue: [^self constantId: memory trueOop].
	op = 16r72 ifTrue: [^self constantId: memory falseOop].
	op = 16r73 ifTrue: [^adNil].
	op = 16r74 ifTrue: [^self constantId: (self intOop: 0)].
	op = 16r75 ifTrue: [^self constantId: (self intOop: 1)].
	op = 16r77 ifTrue: [
		adDepth <= adLocals ifTrue: [^-1].
		^adSlots at: adDepth - 1].
	op = 16r93 ifTrue: [
		k := ((p at: pc + 1) bitOr: (p at: pc + 2) asInt64 << 8) asInt16 asInt32.
		^self constantId: (self intOop: k)].
	((op >= 16r20 and: [op < 16r40]) or: [op = 16r82]) ifTrue: [
		k := op = 16r82 ifTrue: [(p at: pc + 1) asInt32] ifFalse: [op - 16r20].
		^self literalId: k of: lits].
	^-1
!
literalId: k of: lits
	<var: #lits type: 'oop'>
	| v |
	k asUInt32 >= (self numSlots: lits) ifTrue: [^-1].
	v := self loadRef: lits at: k.
	(self constantAllowed: v) ifFalse: [^-1].
	^self constantId: v
!
arithmetic: op pc: pc block: b previous: prev left: x right: y
	"An add/sub and at most two tag guards at its bytecode PC. Proof of
	tagging comes from dominating checked definitions, not tkind or ranges."
	<function>
	| nd v last |
	last := prev.
	0 to: 2 do: [:i |
		(self take: adNode block: b previous: last) ifFalse: [^-4].
		nd := ir node: adNode.
		nd bcpc = pc ifFalse: [^-14].
		(self available: nd a) ifFalse: [^-11].
		nd op asInt32 = O_GUARDINT
			ifTrue: [
				(i = 2 or: [nd flags ~= NF_GUARD or: [nd b ~= -1]]) ifTrue: [^-14].
				v := adAlias at: nd a.
				(v = x or: [v = y]) ifFalse: [^-11].
				(self state: nd state at: pc before: adNode) ifFalse: [^-12].
				adAlias at: adNode put: v.
				adSmi at: adNode put: 1.
				last := adNode.
				adNode := nd next]
			ifFalse: [
				(nd op asInt32 = op and: [nd flags = 0 and: [nd aux = 0]]) ifFalse: [^-14].
				(self available: nd b) ifFalse: [^-11].
				((adAlias at: nd a) = x and: [(adAlias at: nd b) = y and: [(adSmi at: nd a) ~= 0 and: [(adSmi at: nd b) ~= 0]]]) ifFalse: [^-11].
				(self state: nd state at: pc before: adNode) ifFalse: [^-12].
				adSmi at: adNode put: 1.
				adArith := adArith + 1.
				last := adNode.
				adNode := nd next.
				^last]].
	^-14
! !

!OptAdmission methodsFor: 'bounded build envelope'!
buildEnvelope: m
	"Before ordinary analysis/build: no branch, send, inlining, loop,
	foreign activation or variable size operand. This is a work bound,
	not the IR/replay proof."
	<function>
	| p pc n op len locals args cap depth i j |
	args := self intVal: (self loadRef: m at: CM_NUMARGS).
	locals := args + (self intVal: (self loadRef: m at: CM_NUMTEMPS)).
	cap := self intVal: (self loadRef: m at: CM_FRAMESIZE).
	p := self methodBytecodes: m.
	n := self methodSize: m.
	pc := 0.
	depth := locals.
	[pc < n] whileTrue: [
		op := (p at: pc) asInt32.
		len := self lengthOf: op.
		pc + len > n ifTrue: [^false].
		(op = 16r79 or: [op = 16r7A]) ifTrue: [
			^pc + 1 = n and: [depth = (locals + (op = 16r79 ifTrue: [1] ifFalse: [0]))]].
		i := len > 1 ifTrue: [(p at: pc + 1) asInt32] ifFalse: [0].
		(self isFused: op)
			ifTrue: [
				(i >= locals or: [depth + 2 > cap]) ifTrue: [^false].
				j := (p at: pc + 2) asInt32.
				(op < 16rA0 and: [j >= locals]) ifTrue: [^false].
				((op = 16rF0 or: [op = 16rF1]) and: [(self boundedLiteral: j method: m) not]) ifTrue: [^false].
				depth := depth + 1]
			ifFalse: [
				(op = 16rA0 or: [op = 16rA1])
					ifTrue: [depth < (locals + 2) ifTrue: [^false]. depth := depth - 1]
					ifFalse: [
						(op = 16r78 or: [op = 16r84 or: [op = 16r87 or: [op between: 16r60 and: 16r67]]])
							ifTrue: [
								depth <= locals ifTrue: [^false].
								op ~= 16r78 ifTrue: [
									op < 16r68 ifTrue: [i := op - 16r60].
									(i < args or: [i >= locals]) ifTrue: [^false]].
								op ~= 16r84 ifTrue: [depth := depth - 1]]
							ifFalse: [
								(op < 16r10 or: [op = 16r80])
									ifTrue: [
										op < 16r10 ifTrue: [i := op].
										i >= locals ifTrue: [^false]]
									ifFalse: [
										(op = 16r82 or: [op between: 16r20 and: 16r3F])
											ifTrue: [
												op < 16r40 ifTrue: [i := op - 16r20].
												(self boundedLiteral: i method: m) ifFalse: [^false]]
											ifFalse: [
												(op = 16r77 and: [depth > locals]) ifFalse: [
													(op = 16r93 or: [op between: 16r70 and: 16r75]) ifFalse: [^false]]]].
								depth >= cap ifTrue: [^false].
								depth := depth + 1]]].
		pc := pc + len].
	^false
!
boundedLiteral: i method: m
	| lits |
	lits := self loadRef: m at: CM_LITERALS.
	^i asUInt32 < (self numSlots: lits) and: [self constantAllowed: (self loadRef: lits at: i)]
! !
