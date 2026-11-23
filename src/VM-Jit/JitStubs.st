JitCompiler subclass: #JitStubs
	instanceVariableNames: 'exitPlainAddr interruptStub entryInterruptStub closureStub contextStub contextFieldStub makeArrayStub widowStub barrierStub tierUpStub optDeoptStub optDeoptReturnStub optStackFullStub optMakeArrayStub optReturnStub blEnter blExitSync blMiss blBlock blMega blPerform blEntrySlow blPrim blRemember blReturnSlow blBox blSent blCopy blStrHash blStrCmp blStrEq symbolAddrs symbolNames symbolCount'
	classVariableNames: 'STUB_MAX_SYMBOLS'
	package: 'VM-Jit'!

JitStubs comment: 'The code every compiled method shares, generated into the code cache when it is opened (it survives flushes):

jit_enter(frame, address): int64_t (the interpreter''s way into machine code) saves the callee-saved registers, sets x19-x22 from frame and x23-x25 (nil, true, false), remembers the first Frame, its native record and the native stack pointer in the JitState, pushes x29/x30 as a compiled method''s prologue would and branches to address. A compiled method returning from that first activation lands back here, its result into the receiver''s slot, and answers its caller''s Frame + 1. exitSync (machine code stored the frame''s pc and sp; the frames below become canonical) answers the frame; exitPlain (the runtime made the state canonical) answers 0. Both reset the native stack to jit_enter''s and return to the interpreter (JitRuntime>>run:at:).

One stub per runtime function (ldr x16, =function; br x16), so that compiled code reaches it with bl; the disassembler names them.'!

!JitStubs class methodsFor: 'declaring'!
declarations
	^#((exitPlainAddr uint64_t)
		(interruptStub uint64_t) (entryInterruptStub uint64_t) (closureStub uint64_t) (contextStub uint64_t) (contextFieldStub uint64_t) (makeArrayStub uint64_t)
		(widowStub uint64_t) (barrierStub uint64_t) (tierUpStub uint64_t) (optDeoptStub uint64_t) (optDeoptReturnStub uint64_t) (optStackFullStub uint64_t) (optMakeArrayStub uint64_t) (optReturnStub uint64_t)
		(blEnter uint64_t) (blExitSync uint64_t) (blMiss uint64_t) (blBlock uint64_t) (blMega uint64_t) (blPerform uint64_t) (blEntrySlow uint64_t) (blPrim uint64_t) (blRemember uint64_t) (blReturnSlow uint64_t) (blBox uint64_t) (blSent uint64_t) (blCopy uint64_t) (blStrHash uint64_t) (blStrCmp uint64_t) (blStrEq uint64_t)
		(symbolAddrs 'uint64_t[STUB_MAX_SYMBOLS]') (symbolNames 'const char *[STUB_MAX_SYMBOLS]') (symbolCount int32_t))
!
initialize
	STUB_MAX_SYMBOLS := 48
! !

!JitStubs methodsFor: 'accessing'!
blEnterAddress
	^blEnter
!
blExitSyncAddress
	^blExitSync
!
exitPlainAddress
	^exitPlainAddr
!
interruptStub
	^interruptStub
!
entryInterruptStub
	^entryInterruptStub
!
closureStub
	^closureStub
!
contextStub
	^contextStub
!
contextFieldStub
	^contextFieldStub
!
makeArrayStub
	^makeArrayStub
!
widowStub
	^widowStub
!
barrierStub
	^barrierStub
!
tierUpStub
	^tierUpStub
!
optDeoptStub
	^optDeoptStub
!
optReturnStub
	^optReturnStub
!
optDeoptReturnStub
	^optDeoptReturnStub
!
optStackFullStub
	^optStackFullStub
!
optMakeArrayStub
	^optMakeArrayStub
!
blMissStub
	^blMiss
!
blBlockStub
	^blBlock
!
blMegaStub
	^blMega
!
blPerformStub
	^blPerform
!
blEntrySlowStub
	^blEntrySlow
!
blPrimStub
	^blPrim
!
blRememberStub
	^blRemember
!
blCopyStub
	^blCopy
!
blStringHashStub
	^blStrHash
!
blStringCompareStub
	^blStrCmp
!
blStringEqualStub
	^blStrEq
!
copyCountRegister
	"The copy stub's byte count: the code generators' first scratch register (x14; on x86 x10, r14)."
	^asm isX64 ifTrue: [X10] ifFalse: [X14]
!
copyTempRegister
	^asm isX64 ifTrue: [X11] ifFalse: [X15]
!
blReturnSlowStub
	^blReturnSlow
!
blBoxStub
	^blBox
!
blSentStub
	"A ret: where a call continues whose send the runtime completed (the result in the receiver's slot, which the miss and entry stubs load into x0)."
	^blSent
!
symbolCount
	^symbolCount
!
symbolAddressAt: i
	^symbolAddrs at: i
!
symbolNameAt: i
	^symbolNames at: i
! !

!JitStubs methodsFor: 'layout'!
baseFrameOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #baseFrame) to: 'int64_t'
!
baseRecordOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #baseRecord) to: 'int64_t'
!
tagClassesOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #tagClasses) to: 'int64_t'
!
megaCacheOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #megaCache) to: 'int64_t'
!
blockCacheOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #blockCache) to: 'int64_t'
!
resultOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #result) to: 'int64_t'
!
primRetOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #primRet) to: 'int64_t'
!
emitReloadPinned
	"Baseline code keeps nil, true and false in x23, x24, x25."
	asm ldp: X23 with: X24 base: X22 offset: self nilOffset.
	asm ldr: X25 base: X22 offset: self falseOffset
! !

!JitStubs methodsFor: 'generating'!
generate
	"Generate the trampolines and stubs at the code cache's top; answer whether they fit."
	<function>
	| start restore exit |
	asm isX64 ifTrue: [^self generateX64].
	start := cache top.
	symbolCount := 0.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: false.
	restore := asm newLabel.
	exit := asm newLabel.
	blEnter := self symbol: 'jit_enter'.
	self emitEnter: restore.
	blExitSync := self symbol: 'exit (sync)'.
	"the frames below become canonical before the native stack goes"
	asm mov: X0 with: X19.
	asm mov: X16 imm64: runtime exitSyncFunction.
	asm blr: X16.
	asm mov: X0 with: X19.
	asm b: exit.
	exitPlainAddr := self symbol: 'exit'.
	asm mov: X0 imm: 0.
	asm bind: exit.
	asm ldr: X16 base: X22 offset: self exitSpOffset.
	asm mov: SP with: X16.
	asm bind: restore.
	asm ldp: D14 with: D15 base: SP offset: 144.
	asm ldp: D12 with: D13 base: SP offset: 128.
	asm ldp: D10 with: D11 base: SP offset: 112.
	asm ldp: D8 with: D9 base: SP offset: 96.
	asm ldp: X27 with: X28 base: SP offset: 80.
	asm ldp: X25 with: X26 base: SP offset: 64.
	asm ldp: X23 with: X24 base: SP offset: 48.
	asm ldp: X21 with: X22 base: SP offset: 32.
	asm ldp: X19 with: X20 base: SP offset: 16.
	asm ldp: X29 with: X30 base: SP postIndex: 160.
	asm ret.
	interruptStub := self stub: runtime interruptFunction named: 'interrupt check'.
	entryInterruptStub := self stub: runtime interruptAtEntryFunction named: 'interrupt check at entry'.
	closureStub := self stub: runtime closureFunction named: 'closure'.
	contextStub := self stub: runtime contextFunction named: 'thisContext'.
	contextFieldStub := self stub: runtime contextFieldFunction named: 'married Context field'.
	makeArrayStub := self stub: runtime makeArrayFunction named: 'make array'.
	widowStub := self stub: runtime widowFunction named: 'widow'.
	barrierStub := self stub: runtime writeBarrierFunction named: 'write barrier'.
	self generateBaseline.
	tierUpStub := self stub: runtime tierUpFunction named: 'tier up'.
	optDeoptReturnStub := self stub: runtime optDeoptReturnFunction named: 'deoptimize after a send'.
	optStackFullStub := self stub: runtime optStackFullFunction named: 'no room for the frame'.
	optMakeArrayStub := self stub: runtime optMakeArrayFunction named: 'make an Array'.
	optDeoptStub := self dumpingStub: runtime optDeoptFunction named: 'deoptimize'.
	optReturnStub := self dumpingStub: runtime optReturnFunction named: 'return from the bottom frame'.
	asm finish = ASM_OK ifFalse: [^false].
	cache allocate: asm codeSize.
	cache endWritingFrom: start size: asm codeSize.
	^true
!
generateX64
	"The x86 trampolines and stubs (as generate's): jit_enter saves SysV's callee-saved registers and, for the code, asmRegs' x26-x28 (callee-saved on arm64); the native record of an activation is the return address its call pushed; a stub that calls C aligns the stack and keeps xmm8-xmm15 (Amd64Assembler>>callC:)."
	<function>
	<arch: #x86_64>
	| start restore exit push |
	start := cache top.
	symbolCount := 0.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: false.
	restore := asm newLabel.
	exit := asm newLabel.
	push := asm newLabel.
	blEnter := self symbol: 'jit_enter'.
	"rdi (x0) the frame, rsi (x1) the address"
	"rbx, rbp, r12-r15"
	asm pushX64: 3.
	asm pushX64: 5.
	asm pushX64: 12.
	asm pushX64: 13.
	asm pushX64: 14.
	asm pushX64: 15.
	asm push: X26.
	asm push: X27.
	asm push: X28.
	asm mov: X19 with: X0.
	asm ldr: X20 base: X19 offset: self fpOffset.
	asm ldr: X21 base: X20 offset: -8.
	asm str: X19 base: X22 offset: self baseFrameOffset.
	asm mov: X16 with: SP.
	asm str: X16 base: X22 offset: self exitSpOffset.
	asm bl: push.
	"the first activation returned: x19 is its caller's frame, x0 the result, x20 the returning frame's fp"
	asm stur: X0 base: X20 offset: -8.
	asm add: X9 with: X19 imm: 1.
	asm b: restore.
	asm bind: push.
	asm mov: X16 with: SP.
	asm str: X16 base: X22 offset: self baseRecordOffset.
	asm br: X1.
	blExitSync := self symbol: 'exit (sync)'.
	"the frames below become canonical before the native stack goes"
	asm mov: X0 with: X19.
	asm callC: runtime exitSyncFunction.
	asm mov: X9 with: X19.
	asm b: exit.
	exitPlainAddr := self symbol: 'exit'.
	asm mov: X9 imm: 0.
	asm bind: exit.
	asm ldr: X16 base: X22 offset: self exitSpOffset.
	asm mov: SP with: X16.
	asm bind: restore.
	asm pop: X28.
	asm pop: X27.
	asm pop: X26.
	asm popX64: 15.
	asm popX64: 14.
	asm popX64: 13.
	asm popX64: 12.
	asm popX64: 5.
	asm popX64: 3.
	asm ret.
	interruptStub := self stubX64: runtime interruptFunction named: 'interrupt check'.
	entryInterruptStub := self stubX64: runtime interruptAtEntryFunction named: 'interrupt check at entry'.
	closureStub := self stubX64: runtime closureFunction named: 'closure'.
	contextStub := self stubX64: runtime contextFunction named: 'thisContext'.
	contextFieldStub := self stubX64: runtime contextFieldFunction named: 'married Context field'.
	makeArrayStub := self stubX64: runtime makeArrayFunction named: 'make array'.
	widowStub := self stubX64: runtime widowFunction named: 'widow'.
	barrierStub := self stubX64: runtime writeBarrierFunction named: 'write barrier'.
	self generateBaselineX64.
	tierUpStub := self stubX64: runtime tierUpFunction named: 'tier up'.
	optDeoptReturnStub := self stubX64: runtime optDeoptReturnFunction named: 'deoptimize after a send'.
	optStackFullStub := self stubX64: runtime optStackFullFunction named: 'no room for the frame'.
	optMakeArrayStub := self stubX64: runtime optMakeArrayFunction named: 'make an Array'.
	optDeoptStub := self dumpingStubX64: runtime optDeoptFunction named: 'deoptimize'.
	optReturnStub := self dumpingStubX64: runtime optReturnFunction named: 'return from the bottom frame'.
	asm finish = ASM_OK ifFalse: [^false].
	cache allocate: asm codeSize.
	cache endWritingFrom: start size: asm codeSize.
	^true
!
stubX64: function named: name
	"x86: the C function with the arguments the code put in x0-x3, its result into x0."
	<arch: #x86_64>
	| a |
	a := self symbol: name.
	asm callC: function.
	asm ret.
	^a
!
dumpingStubX64: fn named: name
	"x86: as dumpingStub:named:, the registers by their arm64 numbers (the words of those without an x86 register, xmm0-xmm15 as d0-d15)."
	<arch: #x86_64>
	| a dump |
	a := self symbol: name.
	dump := self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #dump) to: 'int64_t'.
	0 to: 28 do: [:i | (i between: 22 and: 25) ifFalse: [asm str: i base: X22 offset: dump + (8 * i)]].
	0 to: 15 do: [:i | asm str: D0 + i base: X22 offset: dump + 256 + (8 * i)].
	asm mov: X0 with: X19.
	asm mov: W1 with: W17.
	asm callC: fn.
	asm b: (asm labelAt: exitPlainAddr).
	^a
!
generateBaselineX64
	"generateBaseline's stubs on x86: the return address is on the native stack where arm64 has x30."
	<arch: #x86_64>
	| exit imm have miss lnot |
	exit := asm labelAt: exitPlainAddr.
	blMiss := self symbol: 'baseline miss'.
	"x0 the receiver, back to the send on the stack, x19 the sender's frame, x20 the callee's fp"
	self emitFollowMissReceiver.
	asm mov: X1 with: X0.
	asm loadReturnAddress: X2.
	asm mov: X0 with: X19.
	asm callC: brt missFunction.
	self emitContinueOrExit: exit.
	miss := asm labelAt: blMiss.
	blMega := self symbol: 'baseline megamorphic'.
	"x0 the receiver, x9 the selector: probe the megamorphic cache by class and selector"
	imm := asm newLabel.
	have := asm newLabel.
	asm tst: X0 imm: 7.
	asm b: imm if: COND_NE.
	asm ldr: X16 base: X0 offset: 8.
	asm bind: have.
	asm eor: X10 with: X16 with: X9.
	asm lsr: X10 with: X10 imm: 3.
	asm and: X10 with: X10 imm: brt megaMask.
	asm lsl: X10 with: X10 imm: 5.
	asm ldr: X11 base: X22 offset: self megaCacheOffset.
	asm add: X11 with: X11 with: X10.
	asm ldr: X17 base: X11 offset: 0.
	asm cmp: X17 with: X16.
	asm b: miss if: COND_NE.
	asm ldr: X17 base: X11 offset: 8.
	asm cmp: X17 with: X9.
	asm b: miss if: COND_NE.
	asm ldr: X16 base: X11 offset: 16.
	asm br: X16.
	asm bind: imm.
	asm and: X16 with: X0 imm: 7.
	asm add: X17 with: X22 imm: self tagClassesOffset.
	asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
	asm b: have.
	blBlock := self symbol: 'baseline block value'.
	"x0 a closure with the right argument count: its code by home method and startpc in the block cache"
	lnot := asm newLabel.
	asm ldr: X16 base: X0 offset: (self fieldOffset: BC_OUTER).
	asm ldr: X16 base: X16 offset: (self fieldOffset: CTX_METHOD).
	asm ldr: X17 base: X0 offset: (self fieldOffset: BC_STARTPC).
	asm lsr: X10 with: X16 imm: 3.
	asm eor: X10 with: X10 with: X17.
	asm and: X10 with: X10 imm: brt blockMask.
	asm lsl: X10 with: X10 imm: 5.
	asm ldr: X11 base: X22 offset: self blockCacheOffset.
	asm add: X11 with: X11 with: X10.
	asm ldr: X9 base: X11 offset: 0.
	asm cmp: X9 with: X16.
	asm b: lnot if: COND_NE.
	asm ldr: X9 base: X11 offset: 8.
	asm cmp: X9 with: X17.
	asm b: lnot if: COND_NE.
	asm ldr: X16 base: X11 offset: 16.
	asm br: X16.
	asm bind: lnot.
	asm mov: X1 with: X0.
	asm loadReturnAddress: X2.
	asm mov: X0 with: X19.
	asm callC: brt blockFunction.
	self emitContinueOrExit: exit.
	blPerform := self symbol: 'baseline perform'.
	"x0 the receiver, x1 the perform method's argument count (| 256: perform:withArguments:), x10 where its body starts (r14: C keeps it), back to the send on the stack"
	have := asm newLabel.
	asm mov: X3 with: X1.
	asm mov: X1 with: X0.
	asm loadReturnAddress: X2.
	asm mov: X0 with: X19.
	asm callC: brt performFunction.
	asm cbnz: X0 to: have.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	asm bind: have.
	self emitContinueOrExit: exit.
	blEntrySlow := self symbol: 'baseline entry slow path'.
	"x10 where to retry, x11 the callee's header (1: a block's entry), back to the send on the stack"
	have := asm newLabel.
	asm mov: X2 with: X11.
	asm loadReturnAddress: X1.
	asm mov: X0 with: X19.
	asm callC: brt entrySlowFunction.
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm cbz: X0 to: have.
	asm mov: X10 with: X0.
	asm bind: have.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	blPrim := self symbol: 'baseline primitive'.
	"x2 the primitive's function, x3 its argument count | leaf << 8, x10 where a failure continues, back to the send on the stack"
	lnot := asm newLabel.
	asm loadReturnAddress: X16.
	asm str: X16 base: X22 offset: self primRetOffset.
	asm mov: X1 with: X20.
	asm mov: X0 with: X19.
	asm callCFromSend: brt primFunction.
	asm cbnz: X0 to: lnot.
	asm ldr: X0 base: X22 offset: self resultOffset.
	asm ret.
	asm bind: lnot.
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	blRemember := self symbol: 'baseline remember'.
	"x16 an old object, x17 the young value stored into it: every register but x16, x17 preserved (C keeps rbx rbp r12-r15, callC xmm8-xmm15)"
	0 to: 5 do: [:r | asm push: r].
	asm push: X9.
	asm mov: X0 with: X16.
	asm mov: X1 with: X17.
	asm callC: runtime writeBarrierFunction.
	asm pop: X9.
	5 to: 0 by: -1 do: [:r | asm pop: r].
	asm ret.
	blReturnSlow := self stubX64: brt returnSlowFunction named: 'baseline return slow path'.
	blBox := self stubX64: brt boxFunction named: 'baseline box Float'.
	blSent := self symbol: 'sent by the runtime'.
	asm ret.
	self emitCopyStub.
	self emitStringStubs
!
emitCopyStub
	"memmove of x16 := the destination, x17 := the source and the count register's bytes (not 0; copyCountRegister, copyTempRegister): x16, x17, those two, the flags and the d registers C does not keep change, nothing else. Up to 16 bytes with two loads (the first and the last 8, 4, 2 bytes, overlapping), then two stores; up to 64 bytes in words (32 bytes a turn while they last), then the rest, from the end down if the destination overlaps the source from above; longer copies call memmove (its callers are primitives, entered by sends, and optimized code's calls, whose doubles are loaded again after it: on x86-64 xmm8-xmm15 are not kept either)."
	| c t back long fwd32 fwd bwd32 bwd fwdTail backTail f2 f1 b2 b1 done medium |
	c := self copyCountRegister.
	t := self copyTempRegister.
	medium := asm newLabel.
	back := asm newLabel.
	long := asm newLabel.
	fwd32 := asm newLabel.
	fwd := asm newLabel.
	bwd32 := asm newLabel.
	bwd := asm newLabel.
	fwdTail := asm newLabel.
	backTail := asm newLabel.
	f2 := asm newLabel.
	f1 := asm newLabel.
	b2 := asm newLabel.
	b1 := asm newLabel.
	done := asm newLabel.
	blCopy := self symbol: 'copy'.
	asm cmp: c imm: 16.
	asm b: medium if: COND_HI.
	self emitSmallCopy.
	asm bind: medium.
	asm cmp: c imm: 64.
	asm b: long if: COND_HI.
	asm sub: t with: X16 with: X17.
	asm cmp: t with: c.
	asm b: back if: COND_LO.
	asm add: c with: X17 with: c.
	asm bind: fwd32.
	asm sub: t with: c with: X17.
	asm cmp: t imm: 32.
	asm b: fwd if: COND_LO.
	0 to: 3 do: [:i |
		asm ldr: t base: X17 offset: 8 * i.
		asm str: t base: X16 offset: 8 * i].
	asm add: X17 with: X17 imm: 32.
	asm add: X16 with: X16 imm: 32.
	asm b: fwd32.
	asm bind: fwd.
	asm sub: t with: c with: X17.
	asm cmp: t imm: 8.
	asm b: fwdTail if: COND_LO.
	asm ldr: t base: X17 postIndex: 8.
	asm str: t base: X16 postIndex: 8.
	asm b: fwd.
	asm bind: fwdTail.
	asm tbz: t bit: 2 to: f2.
	asm ldr: (c bitOr: REG_W) base: X17 postIndex: 4.
	asm str: (c bitOr: REG_W) base: X16 postIndex: 4.
	asm bind: f2.
	asm tbz: t bit: 1 to: f1.
	asm ldrh: (c bitOr: REG_W) base: X17 offset: 0.
	asm strh: (c bitOr: REG_W) base: X16 offset: 0.
	asm add: X17 with: X17 imm: 2.
	asm add: X16 with: X16 imm: 2.
	asm bind: f1.
	asm tbz: t bit: 0 to: done.
	asm ldrb: (c bitOr: REG_W) base: X17 offset: 0.
	asm strb: (c bitOr: REG_W) base: X16 offset: 0.
	asm b: done.
	asm bind: back.
	asm mov: t with: X17.
	asm add: X17 with: X17 with: c.
	asm add: X16 with: X16 with: c.
	asm mov: c with: t.
	asm bind: bwd32.
	asm sub: t with: X17 with: c.
	asm cmp: t imm: 32.
	asm b: bwd if: COND_LO.
	1 to: 4 do: [:i |
		asm ldr: t base: X17 offset: -8 * i.
		asm str: t base: X16 offset: -8 * i].
	asm sub: X17 with: X17 imm: 32.
	asm sub: X16 with: X16 imm: 32.
	asm b: bwd32.
	asm bind: bwd.
	asm sub: t with: X17 with: c.
	asm cmp: t imm: 8.
	asm b: backTail if: COND_LO.
	asm ldr: t base: X17 preIndex: -8.
	asm str: t base: X16 preIndex: -8.
	asm b: bwd.
	asm bind: backTail.
	asm tbz: t bit: 2 to: b2.
	asm ldr: (c bitOr: REG_W) base: X17 preIndex: -4.
	asm str: (c bitOr: REG_W) base: X16 preIndex: -4.
	asm bind: b2.
	asm tbz: t bit: 1 to: b1.
	asm sub: X17 with: X17 imm: 2.
	asm sub: X16 with: X16 imm: 2.
	asm ldrh: (c bitOr: REG_W) base: X17 offset: 0.
	asm strh: (c bitOr: REG_W) base: X16 offset: 0.
	asm bind: b1.
	asm tbz: t bit: 0 to: done.
	asm ldurb: (c bitOr: REG_W) base: X17 offset: -1.
	asm sturb: (c bitOr: REG_W) base: X16 offset: -1.
	asm bind: done.
	asm ret.
	asm bind: long.
	asm isX64
		ifTrue: [
			"C keeps rbx, rbp, r12-r15 (x17, x10, x11 among them)"
			0 to: 5 do: [:r | asm push: r].
			asm push: X9.
			asm mov: X0 with: X16.
			asm mov: X1 with: X17.
			asm mov: X2 with: c.
			asm callCFromSend: runtime moveFunction.
			asm pop: X9.
			5 to: 0 by: -1 do: [:r | asm pop: r]]
		ifFalse: [
			asm stp: X29 with: X30 base: SP preIndex: -128.
			0 to: 6 do: [:i | asm stp: 2 * i with: 2 * i + 1 base: SP offset: 16 + (16 * i)].
			asm mov: X0 with: X16.
			asm mov: X1 with: X17.
			asm mov: X2 with: c.
			asm mov: X16 imm64: runtime moveFunction.
			asm blr: X16.
			0 to: 6 do: [:i | asm ldp: 2 * i with: 2 * i + 1 base: SP offset: 16 + (16 * i)].
			asm ldp: X29 with: X30 base: SP postIndex: 128].
	asm ret
!
emitSmallCopy
	"The copy stub's 1 to 16 bytes: the first and the last 8 (4, 2) bytes, which may overlap, loaded before either is stored (memmove's semantics whatever the overlap); one byte alone."
	| c t lt8 lt4 one |
	c := self copyCountRegister.
	t := self copyTempRegister.
	lt8 := asm newLabel.
	lt4 := asm newLabel.
	one := asm newLabel.
	asm cmp: c imm: 8.
	asm b: lt8 if: COND_LO.
	asm ldr: t base: X17 offset: 0.
	asm add: X17 with: X17 with: c.
	asm ldr: X17 base: X17 offset: -8.
	asm str: t base: X16 offset: 0.
	asm add: X16 with: X16 with: c.
	asm str: X17 base: X16 offset: -8.
	asm ret.
	asm bind: lt8.
	asm cmp: c imm: 4.
	asm b: lt4 if: COND_LO.
	asm ldr: (t bitOr: REG_W) base: X17 offset: 0.
	asm add: X17 with: X17 with: c.
	asm ldr: (X17 bitOr: REG_W) base: X17 offset: -4.
	asm str: (t bitOr: REG_W) base: X16 offset: 0.
	asm add: X16 with: X16 with: c.
	asm str: (X17 bitOr: REG_W) base: X16 offset: -4.
	asm ret.
	asm bind: lt4.
	asm cmp: c imm: 2.
	asm b: one if: COND_LO.
	asm ldrh: (t bitOr: REG_W) base: X17 offset: 0.
	asm add: X17 with: X17 with: c.
	asm ldrh: (X17 bitOr: REG_W) base: X17 offset: -2.
	asm strh: (t bitOr: REG_W) base: X16 offset: 0.
	asm add: X16 with: X16 with: c.
	asm strh: (X17 bitOr: REG_W) base: X16 offset: -2.
	asm ret.
	asm bind: one.
	asm ldrb: (t bitOr: REG_W) base: X17 offset: 0.
	asm strb: (t bitOr: REG_W) base: X16 offset: 0.
	asm ret
!
emitStringStubs
	"String>>hash and compareWith: of byte objects (their primitives' work) for optimized code (O_STRHASH, O_STRCMP): x16 the receiver, x17 the argument, the result in x16 (a SmallInteger); x16, x17, the copy stub's two registers and the flags change, nothing else (compare keeps x0 and x9 on the stack)."
	| c t loop done words tail sizes fnv |
	c := self copyCountRegister.
	t := self copyTempRegister.
	loop := asm newLabel.
	done := asm newLabel.
	tail := asm newLabel.
	words := asm newLabel.
	fnv := asm newLabel.
	blStrHash := self symbol: 'string hash'.
	asm comment: 'ObjectMemory>>stringHash: of the bytes: up to 8 FNV-1a, a byte at a time'.
	self emitBytesOf: X16 into: c temp: t.
	asm cmp: c imm: 8.
	asm b: words if: COND_HI.
	asm add: X17 with: X16 imm: 16.
	asm mov: t imm: 2166136261.
	asm cbz: c to: done.
	asm bind: fnv.
	asm ldrb: (X16 bitOr: REG_W) base: X17 postIndex: 1.
	asm eor: (t bitOr: REG_W) with: (t bitOr: REG_W) with: (X16 bitOr: REG_W).
	asm mov: X16 imm: 16777619.
	asm mul: (t bitOr: REG_W) with: (t bitOr: REG_W) with: (X16 bitOr: REG_W).
	asm subs: c with: c imm: 1.
	asm b: fnv if: COND_NE.
	asm b: done.
	asm bind: words.
	asm comment: 'more: from h := their count, h := (h ^ word) * K1 8 bytes at a time, then the last word without its unused bytes, then h ^= h >> 32, h *= K2, h ^= h >> 29'.
	asm mov: t with: c.
	asm add: X16 with: X16 imm: 16.
	asm bind: loop.
	asm ldr: X17 base: X16 postIndex: 8.
	asm eor: t with: t with: X17.
	asm mov: X17 imm: 16r5851F42D4C957F2D.
	asm mul: t with: t with: X17.
	asm sub: c with: c imm: 8.
	asm cmp: c imm: 8.
	asm b: loop if: COND_HS.
	asm cbz: c to: tail.
	asm comment: 'the last word: its count bytes (the slot holds them)'.
	asm ldr: X17 base: X16 offset: 0.
	asm lsl: c with: c imm: 3.
	asm mov: X16 imm: 1.
	asm lsl: X16 with: X16 with: c.
	asm sub: X16 with: X16 imm: 1.
	asm and: X17 with: X17 with: X16.
	asm eor: t with: t with: X17.
	asm mov: X17 imm: 16r5851F42D4C957F2D.
	asm mul: t with: t with: X17.
	asm bind: tail.
	asm lsr: X17 with: t imm: 32.
	asm eor: t with: t with: X17.
	asm mov: X17 imm: 16r2545F4914F6CDD1D.
	asm mul: t with: t with: X17.
	asm lsr: X17 with: t imm: 29.
	asm eor: t with: t with: X17.
	asm bind: done.
	asm and: t with: t imm: 16r3FFFFFFF.
	asm add: X16 with: t with: t.
	asm orr: X16 with: X16 imm: 1.
	asm ret.
	words := asm newLabel.
	tail := asm newLabel.
	sizes := asm newLabel.
	done := asm newLabel.
	blStrCmp := self symbol: 'string compare'.
	asm comment: '-1, 0 or 1 by the first different byte (8 at a time while they last), then by size'.
	asm isX64
		ifTrue: [
			asm push: X0.
			asm push: X9]
		ifFalse: [asm stp: X0 with: X9 base: SP preIndex: -16].
	self emitBytesOf: X16 into: c temp: t.
	self emitBytesOf: X17 into: t temp: X9.
	asm sub: X0 with: c with: t.
	asm cmp: c with: t.
	asm csel: c with: c with: t cond: COND_LO.
	asm add: X16 with: X16 imm: 16.
	asm add: X17 with: X17 imm: 16.
	asm bind: words.
	asm cmp: c imm: 8.
	asm b: tail if: COND_LO.
	asm ldr: t base: X16 offset: 0.
	asm ldr: X9 base: X17 offset: 0.
	asm cmp: t with: X9.
	asm b: tail if: COND_NE.
	asm add: X16 with: X16 imm: 8.
	asm add: X17 with: X17 imm: 8.
	asm sub: c with: c imm: 8.
	asm b: words.
	asm bind: tail.
	asm cbz: c to: sizes.
	asm ldrb: (t bitOr: REG_W) base: X16 postIndex: 1.
	asm ldrb: (X9 bitOr: REG_W) base: X17 postIndex: 1.
	asm sub: c with: c imm: 1.
	asm cmp: t with: X9.
	asm b: tail if: COND_EQ.
	asm comment: 'a byte differs: 1, or -1 if the receiver''s is lower'.
	asm cset: t cond: COND_LO.
	asm lsl: t with: t imm: 2.
	asm mov: X16 imm: 3.
	asm sub: X16 with: X16 with: t.
	asm b: done.
	asm bind: sizes.
	asm comment: 'the common bytes are equal: by size'.
	asm cmp: X0 imm: 0.
	asm cset: t cond: COND_GT.
	asm cset: X9 cond: COND_LT.
	asm sub: t with: t with: X9.
	asm add: X16 with: t with: t.
	asm orr: X16 with: X16 imm: 1.
	asm bind: done.
	asm isX64
		ifTrue: [
			asm pop: X9.
			asm pop: X0]
		ifFalse: [asm ldp: X0 with: X9 base: SP postIndex: 16].
	asm ret.
	self emitStringEqualStub
!
emitStringEqualStub
	"compareWith: of two byte objects where only = 0 matters (NF_EQONLY): x16 1 (0) if their bytes are equal, else 3 (1). The headers' slot counts and unused bytes, then the slots but the last, 8 bytes at a time from the end (x9 kept on the stack), then the last one without its unused bytes (the high ones); x16, x17, the copy stub's two registers and the flags change, nothing else."
	| c t words last equal different differentPop |
	c := self copyCountRegister.
	t := self copyTempRegister.
	words := asm newLabel.
	last := asm newLabel.
	equal := asm newLabel.
	different := asm newLabel.
	differentPop := asm newLabel.
	blStrEq := self symbol: 'string equal'.
	asm comment: 'the same slot count and unused bytes (header bits 0-34)'.
	asm ldr: c base: X16 offset: 0.
	asm ldr: t base: X17 offset: 0.
	asm eor: c with: c with: t.
	asm lsl: c with: c imm: 29.
	asm cbnz: c to: different.
	asm ldr: (c bitOr: REG_W) base: X16 offset: 0.
	asm cbz: c to: equal.
	asm sub: c with: c imm: 1.
	asm cbz: c to: last.
	asm comment: 'the slots but the last'.
	asm isX64
		ifTrue: [asm push: X9]
		ifFalse: [asm str: X9 base: SP preIndex: -16].
	asm add: X16 with: X16 imm: 16.
	asm add: X17 with: X17 imm: 16.
	asm bind: words.
	asm sub: c with: c imm: 1.
	asm ldr: t base: X16 index: c extend: EXT_LSL shift: 3.
	asm ldr: X9 base: X17 index: c extend: EXT_LSL shift: 3.
	asm cmp: t with: X9.
	asm b: differentPop if: COND_NE.
	asm cbnz: c to: words.
	asm isX64
		ifTrue: [asm pop: X9]
		ifFalse: [asm ldr: X9 base: SP postIndex: 16].
	asm sub: X16 with: X16 imm: 16.
	asm sub: X17 with: X17 imm: 16.
	asm bind: last.
	asm comment: 'the last slot without the unused bytes'.
	asm ldr: (c bitOr: REG_W) base: X16 offset: 0.
	asm add: t with: X16 with: c shift: SHIFT_LSL amount: 3.
	asm ldr: t base: t offset: 8.
	asm add: X17 with: X17 with: c shift: SHIFT_LSL amount: 3.
	asm ldr: X17 base: X17 offset: 8.
	asm eor: t with: t with: X17.
	asm ldrb: (c bitOr: REG_W) base: X16 offset: 4.
	asm and: c with: c imm: 7.
	asm lsl: c with: c imm: 3.
	asm lsl: t with: t with: c.
	asm cbnz: t to: different.
	asm bind: equal.
	asm mov: X16 imm: 1.
	asm ret.
	asm bind: differentPop.
	asm isX64
		ifTrue: [asm pop: X9]
		ifFalse: [asm ldr: X9 base: SP postIndex: 16].
	asm bind: different.
	asm mov: X16 imm: 3.
	asm ret
!
emitBytesOf: x into: r temp: t
	"r := the number of bytes of x, a byte object (its slots' bytes less the format's unused ones)."
	asm ldr: (r bitOr: REG_W) base: x offset: 0.
	asm lsl: r with: r imm: 3.
	asm ldrb: (t bitOr: REG_W) base: x offset: 4.
	asm and: t with: t imm: 7.
	asm sub: r with: r with: t
!
dumpingStub: fn named: name
	"Optimized code branches here with a safepoint in w17 (a guard failed, the bottom frame returns): the registers into the JitState's dump, then the runtime function fn(frame, safepoint) does the rest, then the interpreter continues."
	| a dump lit |
	a := self symbol: name.
	dump := self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #dump) to: 'int64_t'.
	asm add: X16 with: X22 imm: dump.
	0 to: 14 do: [:i | asm stp: 2 * i with: 2 * i + 1 base: X16 offset: 16 * i].
	0 to: 15 do: [:i | asm stp: D0 + (2 * i) with: D0 + (2 * i) + 1 base: X16 offset: 256 + (16 * i)].
	asm mov: X0 with: X19.
	asm mov: W1 with: W17.
	lit := asm newLabel.
	asm ldr: X16 label: lit.
	asm blr: X16.
	asm b: (asm labelAt: exitPlainAddr).
	asm bind: lit.
	asm emit64: fn.
	^a
!
emitEnter: restore
	"jit_enter: nil, true and false pinned, the first Frame and native record remembered, the first activation's result stored."
	| push |
	asm stp: X29 with: X30 base: SP preIndex: -160.
	asm mov: X29 with: SP.
	asm stp: X19 with: X20 base: SP offset: 16.
	asm stp: X21 with: X22 base: SP offset: 32.
	asm stp: X23 with: X24 base: SP offset: 48.
	asm stp: X25 with: X26 base: SP offset: 64.
	asm stp: X27 with: X28 base: SP offset: 80.
	asm stp: D8 with: D9 base: SP offset: 96.
	asm stp: D10 with: D11 base: SP offset: 112.
	asm stp: D12 with: D13 base: SP offset: 128.
	asm stp: D14 with: D15 base: SP offset: 144.
	asm mov: X19 with: X0.
	asm mov: X22 imm64: runtime stateAddress.
	asm ldr: X20 base: X19 offset: self fpOffset.
	asm ldr: X21 base: X20 offset: -8.
	self emitReloadPinned.
	asm str: X19 base: X22 offset: self baseFrameOffset.
	asm mov: X16 with: SP.
	asm str: X16 base: X22 offset: self exitSpOffset.
	push := asm newLabel.
	asm bl: push.
	"the first activation returned: x19 is its caller's frame, x0 the result, x20 the returning frame's fp"
	asm stur: X0 base: X20 offset: -8.
	asm orr: X0 with: X19 imm: 1.
	asm b: restore.
	asm bind: push.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm mov: X16 with: SP.
	asm str: X16 base: X22 offset: self baseRecordOffset.
	asm br: X1
!
generateBaseline
	"The baseline compiler's stubs (JitBaselineCompiler, JitBaselineRuntime)."
	| exit imm have miss lnot |
	exit := asm labelAt: exitPlainAddr.
	blMiss := self symbol: 'baseline miss'.
	"x0 the receiver, x30 back to the send, x19 the sender's frame, x20 the callee's fp"
	self emitFollowMissReceiver.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm mov: X1 with: X0.
	asm mov: X2 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt missFunction.
	asm blr: X16.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	self emitContinueOrExit: exit.
	miss := asm labelAt: blMiss.
	blMega := self symbol: 'baseline megamorphic'.
	"x0 the receiver, x9 the selector: probe the megamorphic cache by class and selector"
	imm := asm newLabel.
	have := asm newLabel.
	asm and: X16 with: X0 imm: 7.
	asm cbnz: X16 to: imm.
	asm ldr: X16 base: X0 offset: 8.
	asm bind: have.
	asm eor: X10 with: X16 with: X9.
	asm lsr: X10 with: X10 imm: 3.
	asm ldr: X11 base: X22 offset: self megaCacheOffset.
	asm and: X10 with: X10 imm: brt megaMask.
	asm add: X11 with: X11 with: X10 shift: SHIFT_LSL amount: 5.
	asm ldp: X12 with: X13 base: X11 offset: 0.
	asm cmp: X12 with: X16.
	asm b: miss if: COND_NE.
	asm cmp: X13 with: X9.
	asm b: miss if: COND_NE.
	asm ldr: X16 base: X11 offset: 16.
	asm br: X16.
	asm bind: imm.
	asm add: X17 with: X22 imm: self tagClassesOffset.
	asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
	asm b: have.
	blBlock := self symbol: 'baseline block value'.
	"x0 a closure with the right argument count: its code by home method and startpc in the block cache"
	lnot := asm newLabel.
	asm ldr: X16 base: X0 offset: (self fieldOffset: BC_OUTER).
	asm ldr: X16 base: X16 offset: (self fieldOffset: CTX_METHOD).
	asm ldr: X17 base: X0 offset: (self fieldOffset: BC_STARTPC).
	asm eor: X10 with: X17 with: X16 shift: SHIFT_LSR amount: 3.
	asm ldr: X11 base: X22 offset: self blockCacheOffset.
	asm and: X10 with: X10 imm: brt blockMask.
	asm add: X11 with: X11 with: X10 shift: SHIFT_LSL amount: 5.
	asm ldp: X12 with: X13 base: X11 offset: 0.
	asm cmp: X12 with: X16.
	asm b: lnot if: COND_NE.
	asm cmp: X13 with: X17.
	asm b: lnot if: COND_NE.
	asm ldr: X16 base: X11 offset: 16.
	asm br: X16.
	asm bind: lnot.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm mov: X1 with: X0.
	asm mov: X2 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt blockFunction.
	asm blr: X16.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	self emitContinueOrExit: exit.
	blPerform := self symbol: 'baseline perform'.
	"x0 the receiver, x1 the perform method's argument count (| 256: perform:withArguments:), x10 where its body starts, x30 back to the send: the runtime answers 0 (the primitive failed), 1 (leave) or where the send continues (the target's unchecked entry, the arguments in place; for a sender in optimized code what the runtime's send answers)"
	have := asm newLabel.
	asm stp: X10 with: X30 base: SP preIndex: -16.
	asm mov: X3 with: X1.
	asm mov: X1 with: X0.
	asm mov: X2 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt performFunction.
	asm blr: X16.
	asm ldp: X10 with: X30 base: SP postIndex: 16.
	asm cbnz: X0 to: have.
	self emitReloadPinned.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	asm bind: have.
	self emitContinueOrExit: exit.
	blEntrySlow := self symbol: 'baseline entry slow path'.
	"x10 where to retry, x11 the callee's header (1: a block's entry), x30 back to the send: the stack is full or an interrupt is pending; the runtime answers 0 (retry), 1 (leave) or where the call continues (a sender in optimized code)"
	have := asm newLabel.
	asm stp: X10 with: X30 base: SP preIndex: -16.
	asm mov: X2 with: X11.
	asm mov: X1 with: X30.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt entrySlowFunction.
	asm blr: X16.
	asm ldp: X10 with: X30 base: SP postIndex: 16.
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm cbz: X0 to: have.
	asm mov: X10 with: X0.
	asm bind: have.
	self emitReloadPinned.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	blPrim := self symbol: 'baseline primitive'.
	"x2 the primitive's function, x3 its argument count | leaf << 8, x10 where a failure continues, x30 back to the send"
	lnot := asm newLabel.
	asm stp: X10 with: X30 base: SP preIndex: -16.
	asm str: X30 base: X22 offset: self primRetOffset.
	asm mov: X1 with: X20.
	asm mov: X0 with: X19.
	asm mov: X16 imm64: brt primFunction.
	asm blr: X16.
	asm ldp: X10 with: X30 base: SP postIndex: 16.
	self emitReloadPinned.
	asm cbnz: X0 to: lnot.
	asm ldr: X0 base: X22 offset: self resultOffset.
	asm ret.
	asm bind: lnot.
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X10.
	blRemember := self symbol: 'baseline remember'.
	"x16 an old object, x17 the young value stored into it: every register but x16, x17 preserved"
	asm stp: X0 with: X1 base: SP preIndex: -144.
	asm stp: X2 with: X3 base: SP offset: 16.
	asm stp: X4 with: X5 base: SP offset: 32.
	asm stp: X6 with: X7 base: SP offset: 48.
	asm stp: X8 with: X9 base: SP offset: 64.
	asm stp: X10 with: X11 base: SP offset: 80.
	asm stp: X12 with: X13 base: SP offset: 96.
	asm stp: X14 with: X15 base: SP offset: 112.
	asm stp: X29 with: X30 base: SP offset: 128.
	asm mov: X0 with: X16.
	asm mov: X1 with: X17.
	asm mov: X16 imm64: runtime writeBarrierFunction.
	asm blr: X16.
	asm ldp: X29 with: X30 base: SP offset: 128.
	asm ldp: X14 with: X15 base: SP offset: 112.
	asm ldp: X12 with: X13 base: SP offset: 96.
	asm ldp: X10 with: X11 base: SP offset: 80.
	asm ldp: X8 with: X9 base: SP offset: 64.
	asm ldp: X6 with: X7 base: SP offset: 48.
	asm ldp: X4 with: X5 base: SP offset: 32.
	asm ldp: X2 with: X3 base: SP offset: 16.
	asm ldp: X0 with: X1 base: SP postIndex: 144.
	asm ret.
	blReturnSlow := self stub: brt returnSlowFunction named: 'baseline return slow path'.
	blBox := self stub: brt boxFunction named: 'baseline box Float'.
	blSent := self symbol: 'sent by the runtime'.
	asm ret.
	self emitCopyStub.
	self emitStringStubs
!
emitFollowMissReceiver
	"A forwarder (becomeForward:) misses every class check: the send goes to its target (x0 and the receiver's slot below x20)."
	| go |
	go := asm newLabel.
	self emitNoForwardersTestTo: go.
	self emitFollow: X0.
	asm stur: X0 base: X20 offset: -8.
	asm bind: go
!
emitContinueOrExit: exit
	"x0: 1 leave, else the code to continue at with the receiver in x0 again (x30 back to the send)."
	asm cmp: X0 imm: 1.
	asm b: exit if: COND_EQ.
	asm mov: X16 with: X0.
	self emitReloadPinned.
	asm ldur: X0 base: X20 offset: -8.
	asm br: X16
!
symbol: name
	"The address of the next instruction, named name in disassemblies."
	symbolCount < STUB_MAX_SYMBOLS ifTrue: [
		symbolAddrs at: symbolCount put: asm pc.
		symbolNames at: symbolCount put: name.
		symbolCount := symbolCount + 1].
	^asm pc
!
stub: function named: name
	"ldr x16, =function; br x16"
	| lit a |
	a := self symbol: name.
	lit := asm newLabel.
	asm ldr: X16 label: lit.
	asm br: X16.
	asm bind: lit.
	asm emit64: function.
	^a
! !
