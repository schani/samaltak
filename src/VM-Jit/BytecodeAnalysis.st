VMCoreModule subclass: #BytecodeAnalysis
	instanceVariableNames: 'anaBcs anaLits bcSize numArgs numTemps numLits anaFrameSize primIndex primError hasClosures anaDepths anaFlags anaWork workCount maxDepth anaLive'
	classVariableNames: 'ANA_BLOCK ANA_INTERIOR ANA_LOOP ANA_MAX ANA_MAX_DEPTH ANA_RESUME ANA_START ANA_TARGET'
	package: 'VM-Jit'!

BytecodeAnalysis comment: 'What every compiler needs to know about a method before it emits code (analyze:): for each reachable pc the instruction''s length and the stack depth before it (slots used from fp: arguments, temps and operands, so every operand has a static frame offset), jump targets and loop heads (targets of backward jumps), block bodies (0x8F) with their own depth base (their arguments and temps), and resumption points: where the interpreter may hand a frame back to machine code (pc 0 and block starts, the continuation after each send, loop heads, conditional jumps, which a mustBeBoolean send returns to). Methods with unknown bytecodes, inconsistent anaDepths or jumps into instructions are rejected. The method is not a GC root: analysis and compilation do not allocate.'!

!BytecodeAnalysis class methodsFor: 'declaring'!
declarations
	^#((anaBcs 'uint8_t *') (anaLits 'oop *') (bcSize int32_t) (numArgs int32_t) (numTemps int32_t) (numLits int32_t) (anaFrameSize int32_t) (primIndex int32_t) (primError bool) (hasClosures bool)
		(anaDepths 'int16_t[ANA_MAX]') (anaFlags 'uint8_t[ANA_MAX]') (anaWork 'int32_t[ANA_MAX]') (workCount int32_t) (maxDepth int32_t)
		(anaLive 'uint64_t[ANA_MAX]'))
!
initialize
	ANA_MAX := 32768.
	ANA_MAX_DEPTH := 1024.
	ANA_START := 1.
	ANA_INTERIOR := 2.
	ANA_TARGET := 4.
	ANA_LOOP := 8.
	ANA_RESUME := 16.
	ANA_BLOCK := 32
! !

!BytecodeAnalysis methodsFor: 'queries'!
size
	^bcSize
!
byteAt: pc
	^anaBcs at: pc
!
bytecodes
	^anaBcs
!
numArgs
	^numArgs
!
numTemps
	^numTemps
!
numLiterals
	^numLits
!
frameSize
	"The method's frameSize, at least its arguments and temps."
	^anaFrameSize
!
primitive
	"The method's primitive (0: none)."
	^primIndex
!
primitiveHasErrorCode
	"A failing primitive leaves its error code in the first temp."
	^primError
!
hasClosures
	^hasClosures
!
literalAt: i
	^anaLits at: i
!
maxDepth
	^maxDepth
!
maxDepthLimit
	"No method or block uses more slots."
	^ANA_MAX_DEPTH
!
depthAt: pc
	"Slots in use before the instruction at pc."
	^(anaDepths at: pc) asInt32
!
isStart: pc
	"An instruction starts at pc and is reachable."
	^((anaFlags at: pc) bitAnd: ANA_START) ~= 0
!
isTarget: pc
	^((anaFlags at: pc) bitAnd: ANA_TARGET) ~= 0
!
isLoopHead: pc
	^((anaFlags at: pc) bitAnd: ANA_LOOP) ~= 0
!
isResume: pc
	^((anaFlags at: pc) bitAnd: ANA_RESUME) ~= 0
!
isBlockStart: pc
	^((anaFlags at: pc) bitAnd: ANA_BLOCK) ~= 0
!
lengthAt: pc
	^self lengthOf: (anaBcs at: pc)
!
int16At: pc
	"The little-endian signed 16-bit operand at pc."
	^((anaBcs at: pc) bitOr: (anaBcs at: pc + 1) asInt64 << 8) asInt16 asInt32
!
jumpTargetAt: pc
	"The target of the jump (0x90-0x92) at pc."
	^(pc + 3 + (self int16At: pc + 1)) asInt32
!
lengthOf: op
	"The length of the instruction with opcode op, 0 if op is not a bytecode."
	op < 16r68 ifTrue: [^1].
	op < 16r70 ifTrue: [^0].
	op < 16r7D ifTrue: [^1].
	op < 16r80 ifTrue: [^0].
	op < 16r8A ifTrue: [^2].
	op < 16r8F ifTrue: [^3].
	op = 16r8F ifTrue: [^6].
	op < 16r94 ifTrue: [^3].
	op = 16r94 ifTrue: [^2].
	op < 16r97 ifTrue: [^0].
	op < 16r9A ifTrue: [^4].
	op < 16rA0 ifTrue: [^3].
	op < 16rF0 ifTrue: [^1].
	op < 16rFC ifTrue: [^3].
	^0
!
specialArgc: k
	"Arguments of special selector k (0-31)."
	^(k = 19 or: [k = 20]) ifTrue: [1] ifFalse: [interpreter specialArgcAt: k]
!
specialInlinesIntegers: k
	"Special selector k (0-31) is one machine code takes inline for SmallIntegers, without a send (so without feedback): + - * // \\ bitShift: bitAnd: bitOr: and the comparisons."
	^k <= 8 or: [k = 10 or: [k >= 12 and: [k <= 15]]]
!
sendArgcOf: p
	"Arguments of the send the instruction at p makes (a send, a special selector or a superinstruction)."
	| op |
	op := p at: 0.
	(op = 16r8D or: [op = 16r8E]) ifTrue: [^(p at: 2) asInt32].
	op >= 16rC0 ifTrue: [^op < 16rF0 ifTrue: [((op - 16rC0) >> 4) asInt32] ifFalse: [1]].
	op >= 16rA0 ifTrue: [^self specialArgc: op - 16rA0].
	op >= 16r9A ifTrue: [^1].
	(op >= 16r97 and: [op <= 16r99]) ifTrue: [^self specialArgc: (p at: 3) - 16rA0].
	^0
!
pushesOf: p
	"Operands a superinstruction pushes before its send (2), else 0."
	| op |
	op := p at: 0.
	^((op >= 16r97 and: [op <= 16r9F]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [2] ifFalse: [0]
!
specialIndexOf: p
	"The special selector (0-31) the instruction at p sends: 0xA0-0xBF, or the operation of a superinstruction; -1 if none."
	| op |
	op := p at: 0.
	(op >= 16rA0 and: [op < 16rC0]) ifTrue: [^(op - 16rA0) asInt32].
	(op >= 16r97 and: [op <= 16r99]) ifTrue: [^((p at: 3) - 16rA0) asInt32].
	(op >= 16r9A and: [op < 16rA0]) ifTrue: [^(op - 16r9A) asInt32].
	(op >= 16rF0 and: [op < 16rFC]) ifTrue: [^((op - 16rF0) rem: 6) asInt32].
	^-1
! !

!BytecodeAnalysis methodsFor: 'analysis'!
analyze: m
	"Analyze method m; answer whether it can be compiled."
	<function>
	| bc lo pc d op len ok next t k |
	bc := self bytecodesOf: m.
	lo := self literalsOf: m.
	((self isPtr: bc) and: [(memory formatOf: bc) >= F_BYTES and: [(self isPtr: lo) and: [(self isInt: (self loadRef: m at: CM_NUMARGS)) and: [self isInt: (self loadRef: m at: CM_NUMTEMPS)]]]]) ifFalse: [^false].
	(memory byteSize: bc) >= ANA_MAX ifTrue: [^false].
	anaBcs := self bytesOf: bc.
	anaLits := self slotsOf: lo.
	bcSize := (memory byteSize: bc) asInt32.
	numLits := (self numSlots: lo) asInt32.
	numArgs := (self intVal: (self loadRef: m at: CM_NUMARGS)) asInt32.
	numTemps := (self intVal: (self loadRef: m at: CM_NUMTEMPS)) asInt32.
	(numArgs < 0 or: [numTemps < 0 or: [numArgs + numTemps > ANA_MAX_DEPTH]]) ifTrue: [^false].
	anaFrameSize := (self isInt: (self loadRef: m at: CM_FRAMESIZE)) ifTrue: [(self intVal: (self loadRef: m at: CM_FRAMESIZE)) asInt32] ifFalse: [0].
	anaFrameSize < (numArgs + numTemps) ifTrue: [anaFrameSize := numArgs + numTemps].
	primIndex := ((interpreter methodPrim: m) bitAnd: CM_PRIM_MASK) asInt32.
	primError := ((interpreter methodPrim: m) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0 and: [numTemps > 0].
	hasClosures := false.
	0 to: bcSize - 1 do: [:i |
		anaDepths at: i put: -1.
		anaFlags at: i put: 0].
	workCount := 0.
	maxDepth := numArgs + numTemps.
	(self flowTo: 0 depth: numArgs + numTemps) ifFalse: [^false].
	anaFlags at: 0 put: ((anaFlags at: 0) bitOr: ANA_RESUME).
	[workCount > 0] whileTrue: [
		workCount := workCount - 1.
		pc := anaWork at: workCount.
		d := (anaDepths at: pc) asInt32.
		op := anaBcs at: pc.
		len := self lengthOf: op.
		(len = 0 or: [pc + len > bcSize]) ifTrue: [^false].
		((anaFlags at: pc) bitAnd: ANA_INTERIOR) ~= 0 ifTrue: [^false].
		anaFlags at: pc put: ((anaFlags at: pc) bitOr: ANA_START).
		1 to: len - 1 do: [:i |
			((anaFlags at: pc + i) bitAnd: (ANA_START bitOr: ANA_TARGET)) ~= 0 ifTrue: [^false].
			anaFlags at: pc + i put: ((anaFlags at: pc + i) bitOr: ANA_INTERIOR)].
		next := pc + len.
		ok := true.
		(op >= 16r79 and: [op <= 16r7C])
			ifTrue: [(op ~= 16r7A and: [d < 1]) ifTrue: [^false]]
			ifFalse: [
				op = 16r8F
					ifTrue: [
						hasClosures := true.
						t := next + (((anaBcs at: pc + 4) asInt64 << 8) bitOr: (anaBcs at: pc + 5)).
						t > bcSize ifTrue: [^false].
						(self flowTo: next depth: (anaBcs at: pc + 1) asInt32 + (anaBcs at: pc + 2) asInt32) ifFalse: [^false].
						anaFlags at: next put: ((anaFlags at: next) bitOr: (ANA_BLOCK bitOr: ANA_RESUME)).
						ok := self flowTo: t depth: d + 1]
					ifFalse: [
						(op >= 16r90 and: [op <= 16r92])
							ifTrue: [
								k := op = 16r90 ifTrue: [0] ifFalse: [1].
								d < k ifTrue: [^false].
								t := self jumpTargetAt: pc.
								(t < 0 or: [t >= bcSize]) ifTrue: [^false].
								(self flowTo: t depth: d - k) ifFalse: [^false].
								anaFlags at: t put: ((anaFlags at: t) bitOr: (t <= pc ifTrue: [ANA_TARGET bitOr: (ANA_LOOP bitOr: ANA_RESUME)] ifFalse: [ANA_TARGET])).
								k = 1 ifTrue: [
									anaFlags at: pc put: ((anaFlags at: pc) bitOr: ANA_RESUME).
									ok := self flowTo: next depth: d - 1]]
							ifFalse: [
								t := self effectOf: pc depth: d.
								t < -1000 ifTrue: [^false].
								ok := self flowTo: next depth: d + t.
								(ok and: [self sends: pc]) ifTrue: [
									next < bcSize ifTrue: [anaFlags at: next put: ((anaFlags at: next) bitOr: ANA_RESUME)]]]]].
		ok ifFalse: [^false]].
	^true
!
flowTo: pc depth: d
	"Control reaches pc with d slots in use: queue it, or check that d agrees."
	(pc < 0 or: [pc >= bcSize or: [d < 0 or: [d > ANA_MAX_DEPTH]]]) ifTrue: [^false].
	(anaDepths at: pc) < 0 ifTrue: [
		anaDepths at: pc put: d asInt16.
		d > maxDepth ifTrue: [maxDepth := d asInt32].
		anaWork at: workCount put: pc.
		workCount := workCount + 1.
		^true].
	^(anaDepths at: pc) asInt32 = d
!
sends: pc
	"The instruction at pc may send (its continuation is a resumption point)."
	| op |
	op := anaBcs at: pc.
	^op = 16r8D or: [op = 16r8E or: [(op >= 16r97 and: [op <= 16rFB]) or: [op = 16r85 or: [op = 16r88]]]]
!
effectOf: pc depth: d
	"The stack effect of the (non-jump, non-return, non-closure) instruction at pc; < -1000 if it is invalid at depth d."
	| op n |
	op := anaBcs at: pc.
	(op < 16r60 or: [(op >= 16r70 and: [op <= 16r77]) or: [op = 16r93 or: [op = 16r8A or: [op >= 16r80 and: [op <= 16r83]]]]]) ifTrue: [
		(op = 16r77 and: [d < 1]) ifTrue: [^-2000].
		^1].
	(op < 16r68 or: [op = 16r78 or: [op = 16r87 or: [op = 16r89 or: [op = 16r8C]]]]) ifTrue: [^d < 1 ifTrue: [-2000] ifFalse: [-1]].
	((op >= 16r84 and: [op <= 16r86]) or: [op = 16r88 or: [op = 16r8B]]) ifTrue: [^d < 1 ifTrue: [-2000] ifFalse: [0]].
	op = 16r94 ifTrue: [
		n := (anaBcs at: pc + 1) asInt32.
		^d < n ifTrue: [-2000] ifFalse: [1 - n]].
	((op >= 16r97 and: [op <= 16r9F]) or: [op >= 16rF0]) ifTrue: [
		(op <= 16r99 and: [(anaBcs at: pc + 3) < 16rA0 or: [(anaBcs at: pc + 3) >= 16rC0 or: [(self sendArgcOf: anaBcs + pc) ~= 1]]]) ifTrue: [^-2000].
		^1].
	n := self sendArgcOf: anaBcs + pc.
	n < 0 ifTrue: [^-2000].
	^d < (n + 1) ifTrue: [-2000] ifFalse: [n negated]
! !

!BytecodeAnalysis methodsFor: 'liveness'!
analyzeLiveness
	"After analyze: (the optimizing tier asks): for each reachable pc the slots 0-63 of its frame (the method's, or its block's) that an instruction from there on may read before storing them, on some path (liveSlotsAt:). A slot an outer-temp instruction (0x8A-0x8C) names anywhere in the method counts as read everywhere, as does every slot of a method with a primitive (its error code; unwind markers) or with thisContext (its Context is read)."
	<function>
	<var: #keep type: 'uint64_t'>
	<var: #all type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	| keep all changed pc op t |
	all := 16rFFFFFFFFFFFFFFFF asUInt64.
	keep := (primIndex ~= 0 or: [primError]) ifTrue: [all] ifFalse: [0 asUInt64].
	0 to: bcSize - 1 do: [:p |
		((anaFlags at: p) bitAnd: ANA_START) ~= 0
			ifTrue: [
				anaLive at: p put: 0 asUInt64.
				op := anaBcs at: p.
				(op >= 16r8A and: [op <= 16r8C]) ifTrue: [keep := keep bitOr: (self slotBit: (anaBcs at: p + 2))].
				op = 16r76 ifTrue: [keep := all]]
			ifFalse: [anaLive at: p put: all]].
	changed := true.
	[changed] whileTrue: [
		changed := false.
		pc := bcSize - 1.
		[pc >= 0] whileTrue: [
			((anaFlags at: pc) bitAnd: ANA_START) ~= 0 ifTrue: [
				t := (self liveBefore: pc after: (self liveAfter: pc)) bitOr: keep.
				t ~= (anaLive at: pc) ifTrue: [
					anaLive at: pc put: t.
					changed := true]].
			pc := pc - 1]]
!
liveSlotsAt: pc
	"The slots (0-63) an instruction from pc on may read before storing them (analyzeLiveness); all of them where no instruction starts."
	<returns: 'uint64_t'>
	(pc < 0 or: [pc >= bcSize]) ifTrue: [^16rFFFFFFFFFFFFFFFF asUInt64].
	^anaLive at: pc
!
liveAfter: pc
	"The slots live after the instruction at pc: live before one of its successors (none after a return; after 0x8F the instruction after the body, which runs in a frame of its own)."
	<returns: 'uint64_t'>
	| op next |
	op := anaBcs at: pc.
	(op >= 16r79 and: [op <= 16r7C]) ifTrue: [^0 asUInt64].
	next := (pc + (self lengthOf: op)) asInt32.
	op = 16r8F ifTrue: [^self liveSlotsAt: (next + (((anaBcs at: pc + 4) asInt64 << 8) bitOr: (anaBcs at: pc + 5))) asInt32].
	op = 16r90 ifTrue: [^self liveSlotsAt: (self jumpTargetAt: pc)].
	(op = 16r91 or: [op = 16r92]) ifTrue: [^(self liveSlotsAt: (self jumpTargetAt: pc)) bitOr: (self liveSlotsAt: next)].
	^self liveSlotsAt: next
!
liveBefore: pc after: lo
	"The slots live before the instruction at pc, lo those live after it: the temps it reads (a superinstruction its pushes), and those live after it that it does not store (Interpreter's bytecodes). Any instruction not listed reads every slot."
	<var: #lo type: 'uint64_t'>
	<returns: 'uint64_t'>
	| op |
	op := anaBcs at: pc.
	op < 16r10 ifTrue: [^lo bitOr: (self slotBit: op)].
	op < 16r60 ifTrue: [^lo].
	op < 16r68 ifTrue: [^lo bitClear: (self slotBit: op - 16r60)].
	(op >= 16r70 and: [op <= 16r7C and: [op ~= 16r76]]) ifTrue: [^lo].
	op = 16r80 ifTrue: [^lo bitOr: (self slotBit: (anaBcs at: pc + 1))].
	(op = 16r84 or: [op = 16r87]) ifTrue: [^lo bitClear: (self slotBit: (anaBcs at: pc + 1))].
	((op >= 16r81 and: [op <= 16r86]) or: [op >= 16r89 and: [op <= 16r94]]) ifTrue: [^lo].
	(op = 16r97 or: [op >= 16r9A and: [op <= 16r9F]]) ifTrue: [^(lo bitOr: (self slotBit: (anaBcs at: pc + 1))) bitOr: (self slotBit: (anaBcs at: pc + 2))].
	((op >= 16r98 and: [op <= 16r99]) or: [op >= 16rF0 and: [op <= 16rFB]]) ifTrue: [^lo bitOr: (self slotBit: (anaBcs at: pc + 1))].
	(op >= 16rA0 and: [op <= 16rEF]) ifTrue: [^lo].
	^16rFFFFFFFFFFFFFFFF asUInt64
!
slotBit: i
	"Slot i's bit in a liveness mask (none from 64 on)."
	<returns: 'uint64_t'>
	i < 64 ifTrue: [^1 asUInt64 << i].
	^0 asUInt64
! !
