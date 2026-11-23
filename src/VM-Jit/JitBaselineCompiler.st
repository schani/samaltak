JitCompiler subclass: #JitBaselineCompiler
	instanceVariableNames: 'codeStart pcLabels pcMerge ssKind ssVal ssReg ssInSlot ssTop ssBase regOwner selfValid curArgs curTemps curFrameSize regionEnds regionArgs regionTemps regionSizes regionCount slKind slPc slDepth slLabel slCont slTarget slA slB slC slR slX slY slInfo slCount siteBl siteLit siteInfo sitePc siteDepth siteCount retOff retPc retDepth retInfo retCount poolLabels blockPcs blockLabels blockCount headerLabel missLabel blockLabel megaLabel performLabel exitSyncLabel exitPlainLabel interruptLabel closureLabel makeArrayLabel entrySlowLabel primLabel rememberLabel returnSlowLabel boxLabel fusedTarget uentryOffset dead curPc dregRefs tempD slDA slDB slSavedStart slSavedCount saved savedCount loopActive loopEnd loopId loopTable slLoop plainEntry tierUpLabel counterAddr curMethod'
	classVariableNames: 'BL_MAX_BLOCKS BL_MAX_REGIONS BL_MAX_RETS BL_MAX_SITES BL_MAX_SLOW BL_PIC_CASE_X64 BL_PIC_HEAD_X64 BL_PIC_JMP_X64 BL_UENTRY SL_ACCESS SL_BARRIER SL_CLASS SL_ENTRY_IMM SL_ENTRY_SLOW SL_FLOAT SL_FUSED SL_INTERRUPT SL_MUSTBEBOOLEAN SL_RESUME SL_RETURN SL_SEND SL_START SL_TIERUP SL_BOX SL_DOUBLES BL_MAX_SAVED BL_MAX_LOOPS SS_DREG SS_CONST SS_LIT SS_MAX SS_PINNED SS_REG SS_SELF SS_SLOT SS_TEMP'
	package: 'VM-Jit'!

JitBaselineCompiler comment: 'The baseline compiler (--jit baseline), after Cog''s StackToRegisterMappingCogit: one pass over the bytecodes with a simulated operand stack (ssKind: in its slot, in a register, a constant, nil/true/false, self, a temp or a literal not loaded yet), so values go from producer to consumer in registers (x0-x8, x12-x15) and constants become immediates; the stack is written to its slots only at sends, calls into the runtime and merge points (jump targets, which start with everything in its slot). Before an instruction that may send or call the runtime everything below its operands is written back (as Cog), so its slow path only stores the operands.

Sends: the receiver in x0, receiver and arguments in their slots, x20 advanced to the callee''s fp, x9 the inline cache''s class (a literal next to the code), bl to the site''s target: the miss stub while unlinked, a compiled method''s checked entry (its class check against x9, then its unchecked entry 20 bytes on) while monomorphic, a polymorphic inline cache (up to 6 classes) or the megamorphic stub (x9 then holds the selector). JitBaselineRuntime links and relinks. The callee pushes its frame in machine code (x19, the Frame''s method, code, closure, ctx, fp and a zero pc and sp, the native frame record x29/x30, nil temps, the stack limit and interrupt checks) and answers its result in x0; the caller restores x20 with one sub. Frames are canonical lazily: pc and sp of a frame suspended in a send are derived from its return address when the runtime needs them (JitBaselineRuntime>>canonicalizeBelow:, the return map). Quick methods (^ivar, ^constant, ^self, setters) run without a frame; primitives run before the frame is built, inline (basicNew, closure value, perform: through the megamorphic cache...) or through their C function.

Inline: SmallInteger + - * // \\ bitAnd: bitOr: bitShift: and comparisons (tag checks, overflow branches, immediates, folding, compare and branch), Floats (SmallFloat64 and boxed operands, SmallFloat64 results; others are boxed by the runtime), == ~~ class, at: at:put: on Arrays, Strings, Symbols, ByteArrays (size is sent: user classes define it too), value value: value:value: of closures (class and argument count checked, then the block''s entry through a cache in the block stub). Closures are made in eden (and the frame''s Context with the first), Arrays (0x94) by the runtime, non-local returns by the interpreter. The ablation flags (JitRuntime) switch each off.

Layout: checked entry, unchecked entry, the method''s frame code, its bytecodes in pc order (block bodies inside, each with its entry), then the slow paths, the resumption stubs, the literals (the method''s literals as the runtime registers them for the collector, the inline caches'' classes) and the JitMethod header right after (adr reaches it: method and code for the frame).

Under --jit opt (the optimizing tier''s lower tier) the code also counts method and block entries and backward jumps toward optimization (emitTierUp:depth:loop:, the tier-up stub), marks a Float seen by an inline Float path (emitFloatFeedback:), and has the prologue (emitPrologue) before each start''s resumption point: optimized code calls it with the frame pushed.'!

!JitBaselineCompiler class methodsFor: 'declaring'!
declarations
	^#((codeStart uint64_t) (pcLabels 'int32_t[ANA_MAX]') (pcMerge 'uint8_t[ANA_MAX]')
		(ssKind 'uint8_t[SS_MAX]') (ssVal 'int64_t[SS_MAX]') (ssReg 'int8_t[SS_MAX]') (ssInSlot 'uint8_t[SS_MAX]') (ssTop int32_t) (ssBase int32_t)
		(regOwner 'int32_t[32]') (selfValid bool)
		(curArgs int32_t) (curTemps int32_t) (curFrameSize int32_t)
		(regionEnds 'int32_t[BL_MAX_REGIONS]') (regionArgs 'int32_t[BL_MAX_REGIONS]') (regionTemps 'int32_t[BL_MAX_REGIONS]') (regionSizes 'int32_t[BL_MAX_REGIONS]') (regionCount int32_t)
		(slKind 'uint8_t[BL_MAX_SLOW]') (slPc 'int32_t[BL_MAX_SLOW]') (slDepth 'int32_t[BL_MAX_SLOW]') (slLabel 'int32_t[BL_MAX_SLOW]') (slCont 'int32_t[BL_MAX_SLOW]') (slTarget 'int32_t[BL_MAX_SLOW]')
		(slA 'int8_t[BL_MAX_SLOW]') (slB 'int8_t[BL_MAX_SLOW]') (slC 'int8_t[BL_MAX_SLOW]') (slR 'int8_t[BL_MAX_SLOW]') (slX 'int64_t[BL_MAX_SLOW]') (slY 'int64_t[BL_MAX_SLOW]') (slInfo 'int64_t[BL_MAX_SLOW]') (slCount int32_t)
		(siteBl 'uint32_t[BL_MAX_SITES]') (siteLit 'int32_t[BL_MAX_SITES]') (siteInfo 'uint32_t[BL_MAX_SITES]') (sitePc 'uint16_t[BL_MAX_SITES]') (siteDepth 'uint16_t[BL_MAX_SITES]') (siteCount int32_t)
		(retOff 'uint32_t[BL_MAX_RETS]') (retPc 'uint16_t[BL_MAX_RETS]') (retDepth 'uint16_t[BL_MAX_RETS]') (retInfo 'uint32_t[BL_MAX_RETS]') (retCount int32_t)
		(poolLabels 'int32_t[256]') (blockPcs 'int32_t[BL_MAX_BLOCKS]') (blockLabels 'int32_t[BL_MAX_BLOCKS]') (blockCount int32_t)
		(headerLabel int32_t) (missLabel int32_t) (blockLabel int32_t) (megaLabel int32_t) (performLabel int32_t) (exitSyncLabel int32_t) (exitPlainLabel int32_t) (interruptLabel int32_t)
		(closureLabel int32_t) (makeArrayLabel int32_t) (entrySlowLabel int32_t) (primLabel int32_t) (rememberLabel int32_t) (returnSlowLabel int32_t) (fusedTarget int32_t)
		(boxLabel int32_t) (uentryOffset int32_t) (dead bool) (curPc int32_t)
		(dregRefs 'int8_t[16]') (tempD 'int8_t[SS_MAX]') (slDA 'int8_t[BL_MAX_SLOW]') (slDB 'int8_t[BL_MAX_SLOW]')
		(slSavedStart 'int32_t[BL_MAX_SLOW]') (slSavedCount 'int16_t[BL_MAX_SLOW]') (saved 'int16_t[BL_MAX_SAVED]') (savedCount int32_t)
		(loopActive bool) (loopEnd int32_t) (loopId int32_t) (loopTable 'int32_t[BL_MAX_LOOPS]') (slLoop 'int16_t[BL_MAX_SLOW]') (plainEntry bool) (tierUpLabel int32_t) (counterAddr uint64_t) (curMethod oop))
!
initialize
	SS_MAX := 1100.
	BL_MAX_REGIONS := 256.
	BL_MAX_SLOW := 8192.
	BL_MAX_SITES := 8192.
	BL_MAX_RETS := 8192.
	BL_MAX_BLOCKS := 1024.
	"the unchecked entry follows the checked one: tst, b.ne, ldr, cmp, b.ne"
	BL_UENTRY := 20.
	"x86 PICs: test, jnz, mov before the cases; each case cmp (7 bytes), jne rel8, jmp rel32 (its displacement 10 bytes in)"
	BL_PIC_HEAD_X64 := 14.
	BL_PIC_CASE_X64 := 14.
	BL_PIC_JMP_X64 := 10.
	"simulated stack entries"
	SS_SLOT := 0.
	SS_REG := 1.
	SS_CONST := 2.
	SS_PINNED := 3.
	SS_SELF := 4.
	SS_TEMP := 5.
	SS_LIT := 6.
	"an unboxed Float in d8-d15 (C calls preserve them; sends do not: everything is boxed before one)"
	SS_DREG := 7.
	BL_MAX_SAVED := 65536.
	"loops with temps in x26-x28: 4 words each (count, temps)"
	BL_MAX_LOOPS := 4096.
	"slow paths"
	SL_INTERRUPT := 1.
	SL_SEND := 2.
	SL_MUSTBEBOOLEAN := 3.
	SL_RETURN := 4.
	SL_BARRIER := 5.
	SL_CLASS := 6.
	SL_ENTRY_IMM := 7.
	SL_ENTRY_SLOW := 8.
	SL_START := 9.
	SL_RESUME := 10.
	SL_BOX := 11.
	SL_TIERUP := 12.
	"SL_SEND flags (slInfo bits 32-)"
	SL_FUSED := 16r100000000.
	SL_FLOAT := 16r200000000.
	SL_ACCESS := 16r400000000.
	"the operation was compiled Float first: its result is unboxed (a send's result is unboxed or leaves)"
	SL_DOUBLES := 16r800000000
! !

!JitBaselineCompiler methodsFor: 'accessing'!
uentryDistance
	^BL_UENTRY
!
uentryOffset
	"Where the method's code continues without a class check (from polymorphic caches, the megamorphic stub, super sends)."
	^uentryOffset
!
siteCount
	^siteCount
!
retCount
	^retCount
!
blockCount
	^blockCount
!
plainEntry
	"The unchecked entry starts with the frame's code (no quick method or primitive first)."
	^plainEntry
! !

!JitBaselineCompiler methodsFor: 'compiling'!
compile: m
	"Emit m's code at the assembler's pc (BytecodeAnalysis has analyzed m); answer whether every reachable bytecode got code."
	<function>
	| n pc op |
	codeStart := asm pc.
	n := analysis size.
	analysis frameSize > analysis maxDepthLimit ifTrue: [^false].
	0 to: n - 1 do: [:i |
		pcLabels at: i put: -1.
		pcMerge at: i put: 0].
	0 to: 255 do: [:i | poolLabels at: i put: -1].
	slCount := 0.
	siteCount := 0.
	retCount := 0.
	blockCount := 0.
	regionCount := 0.
	headerLabel := asm newLabel.
	exitSyncLabel := asm newLabel.
	exitPlainLabel := asm newLabel.
	missLabel := asm labelAt: stubs blMissStub.
	blockLabel := asm labelAt: stubs blBlockStub.
	megaLabel := asm labelAt: stubs blMegaStub.
	performLabel := asm labelAt: stubs blPerformStub.
	interruptLabel := asm labelAt: stubs interruptStub.
	closureLabel := asm labelAt: stubs closureStub.
	makeArrayLabel := asm labelAt: stubs makeArrayStub.
	entrySlowLabel := asm labelAt: stubs blEntrySlowStub.
	primLabel := asm labelAt: stubs blPrimStub.
	rememberLabel := asm labelAt: stubs blRememberStub.
	returnSlowLabel := asm labelAt: stubs blReturnSlowStub.
	boxLabel := asm labelAt: stubs blBoxStub.
	tierUpLabel := asm labelAt: stubs tierUpStub.
	counterAddr := runtime counterAddressFor: m.
	curMethod := m.
	savedCount := 0.
	loopActive := false.
	loopId := -1.
	curArgs := analysis numArgs.
	curTemps := analysis numTemps.
	curFrameSize := analysis frameSize.
	(self emitMethodEntry) ifFalse: [^false].
	dead := false.
	pc := 0.
	[pc < n] whileTrue: [
		(analysis isStart: pc)
			ifTrue: [
				[regionCount > 0 and: [pc >= (regionEnds at: regionCount - 1)]] whileTrue: [self popRegion].
				(self emitAt: pc asInt32) ifFalse: [^false].
				pc := pc + (analysis lengthAt: pc)]
			ifFalse: [pc := pc + 1]].
	asm failed ifTrue: [^false].
	(self emitSlowPaths) ifFalse: [^false].
	asm comment: 'leave to the interpreter at the stored pc'.
	asm bind: exitSyncLabel.
	asm b: (asm labelAt: stubs blExitSyncAddress).
	asm comment: 'leave to the interpreter (the runtime made the frames canonical)'.
	asm bind: exitPlainLabel.
	asm b: (asm labelAt: stubs exitPlainAddress).
	self emitLiterals.
	^asm failed not
!
emitAt: pc
	"The code of the instruction at pc, with the simulated stack as the previous instruction left it."
	<function>
	| op d |
	op := analysis byteAt: pc.
	d := analysis depthAt: pc.
	curPc := pc.
	(loopActive and: [pc > loopEnd]) ifTrue: [loopActive := false].
	"a conditional jump fused with the comparison before it"
	(pcMerge at: pc) = 2 ifTrue: [^true].
	(analysis isBlockStart: pc)
		ifTrue: [
			(self emitBlockEntry: pc) ifFalse: [^false].
			(analysis isTarget: pc) ifTrue: [selfValid := false].
			(analysis isLoopHead: pc) ifTrue: [self headCheck: pc]]
		ifFalse: [
			pc = 0
				ifTrue: [
					asm bind: (self labelFor: 0).
					(analysis isTarget: 0) ifTrue: [selfValid := false].
					(analysis isLoopHead: 0) ifTrue: [self headCheck: 0]]
				ifFalse: [
					((analysis isTarget: pc) or: [(pcMerge at: pc) = 1]) ifTrue: [
						(dead not and: [self canThreadInto: pc]) ifTrue: [self threadInto: pc].
						dead ifFalse: [self ssFlushAll].
						((analysis isLoopHead: pc) and: [dead not and: [loopActive not]]) ifTrue: [self beginLoopAt: pc].
						asm bind: (self labelFor: pc).
						self ssReset: d.
						selfValid := false.
						dead := false.
						(analysis isLoopHead: pc) ifTrue: [
							self noteLoopResume: pc.
							self headCheck: pc]]]].
	dead ifTrue: [^true].
	ssTop = d ifFalse: [^false].
	asm bytecode: pc.
	runtime regs ifFalse: [self ssFlushAll].
	(runtime c4Baseline and: [self c4HeapBytecode: op]) ifTrue: [^self exitAt: pc].
	op < 16r10 ifTrue: [^self pushTemp: op].
	op < 16r20 ifTrue: [^self pushInstVar: op - 16r10].
	op < 16r40 ifTrue: [^self pushLiteral: op - 16r20].
	op < 16r60 ifTrue: [^self pushLiteralVariable: op - 16r40].
	op < 16r68 ifTrue: [^self popStoreTemp: op - 16r60].
	op = 16r70 ifTrue: [^self ssPush: SS_SELF val: 0 reg: -1].
	op = 16r71 ifTrue: [^self ssPush: SS_PINNED val: X24 reg: -1].
	op = 16r72 ifTrue: [^self ssPush: SS_PINNED val: X25 reg: -1].
	op = 16r73 ifTrue: [^self ssPush: SS_PINNED val: X23 reg: -1].
	op = 16r74 ifTrue: [^self ssPush: SS_CONST val: 1 reg: -1].
	op = 16r75 ifTrue: [^self ssPush: SS_CONST val: 3 reg: -1].
	op = 16r76 ifTrue: [
		self ssFlushAll.
		asm comment: 'thisContext: the runtime marries this frame'.
		self emitRuntimeCall: (asm labelAt: stubs contextStub) pc: pc depth: ssTop.
		^self ssPush: SS_SLOT val: 0 reg: -1].
	op = 16r77 ifTrue: [^self dup].
	op = 16r78 ifTrue: [
		self ssPop: 1.
		^true].
	(op = 16r79 or: [op = 16r7B]) ifTrue: [^self return: pc self: false].
	op = 16r7A ifTrue: [^self return: pc self: true].
	op = 16r7C ifTrue: [^self nonLocalReturn: pc].
	op = 16r80 ifTrue: [^self pushTemp: (analysis byteAt: pc + 1)].
	op = 16r81 ifTrue: [
		(analysis byteAt: pc + 1) <= CTX_STACKP ifTrue: [^self pushContextField: (analysis byteAt: pc + 1) pc: pc].
		^self pushInstVar: (analysis byteAt: pc + 1)].
	op = 16r82 ifTrue: [^self pushLiteral: (analysis byteAt: pc + 1)].
	op = 16r83 ifTrue: [^self pushLiteralVariable: (analysis byteAt: pc + 1)].
	op = 16r84 ifTrue: [^self storeTemp: (analysis byteAt: pc + 1) pop: false].
	(op = 16r85 or: [op = 16r88]) ifTrue: [^self storeInstVar: (analysis byteAt: pc + 1) pc: pc context: op = 16r88].
	(op = 16r86 or: [op = 16r89]) ifTrue: [^self storeLiteralVariable: (analysis byteAt: pc + 1) pop: op = 16r89].
	op = 16r87 ifTrue: [^self storeTemp: (analysis byteAt: pc + 1) pop: true].
	(op >= 16r8A and: [op <= 16r8C]) ifTrue: [^self outerTemp: pc].
	(op = 16r8D or: [op = 16r8E]) ifTrue: [
		^self send: pc kind: (op = 16r8E ifTrue: [1] ifFalse: [0]) selector: (analysis byteAt: pc + 1) argc: (analysis byteAt: pc + 2) pushes: 0].
	(op >= 16rC0 and: [op < 16rF0]) ifTrue: [
		^self send: pc kind: 0 selector: (op bitAnd: 15) argc: ((op - 16rC0) >> 4) asInt32 pushes: 0].
	op = 16r8F ifTrue: [^self closure: pc].
	op = 16r90 ifTrue: [^self jump: pc].
	(op = 16r91 or: [op = 16r92]) ifTrue: [^self conditionalJump: pc].
	op = 16r93 ifTrue: [^self ssPush: SS_CONST val: (((analysis int16At: pc + 1) asInt64 << 1) bitOr: 1) reg: -1].
	op = 16r94 ifTrue: [^self makeArray: pc].
	((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [^self superinstruction: pc].
	(op >= 16rA0 and: [op < 16rC0]) ifTrue: [^self special: op - 16rA0 pc: pc pushes: 0].
	^false
!
c4HeapBytecode: op
	"Checked interpreter bytecodes: ivars, associations, and outer slots."
	^(op >= 16r10 and: [op < 16r20]) or: [(op >= 16r40 and: [op < 16r60]) or: [
		op = 16r81 or: [op = 16r83 or: [op = 16r85 or: [op = 16r86 or: [
		op >= 16r88 and: [op <= 16r8C]]]]]]]
!
labelFor: pc
	(pcLabels at: pc) < 0 ifTrue: [pcLabels at: pc put: asm newLabel].
	^pcLabels at: pc
!
pushRegion: end args: na temps: nt size: fs
	regionCount >= BL_MAX_REGIONS ifTrue: [^false].
	regionEnds at: regionCount put: end.
	regionArgs at: regionCount put: curArgs.
	regionTemps at: regionCount put: curTemps.
	regionSizes at: regionCount put: curFrameSize.
	regionCount := regionCount + 1.
	curArgs := na.
	curTemps := nt.
	curFrameSize := fs.
	^true
!
popRegion
	"Leaving a block body: the enclosing code's shape again."
	regionCount := regionCount - 1.
	curArgs := regionArgs at: regionCount.
	curTemps := regionTemps at: regionCount.
	curFrameSize := regionSizes at: regionCount
! !

!JitBaselineCompiler methodsFor: 'loop temps'!
beginLoopAt: head
	"An innermost loop from head that makes no closures, Arrays or thisContext, entered only by falling in and by its back jumps: its most used temps (up to 3, each used more often than the loop sends) live in x26-x28 too, stored through to their slots. Loaded here, on the way in, and again after every call out of the loop (sends, slow paths: the callee and the collector change them)."
	<function>
	| end n p op t k best bestCount c sends |
	"x86: x26-x28 have no x86 registers (Amd64Assembler)"
	asm isX64 ifTrue: [^self].
	"a jump threaded into the loop's head would skip the loads below"
	(pcMerge at: head) = 1 ifTrue: [^self].
	n := analysis size.
	end := -1 asInt32.
	p := head.
	[p < n] whileTrue: [
		(analysis isStart: p) ifTrue: [
			op := analysis byteAt: p.
			((op >= 16r90 and: [op <= 16r92]) and: [(analysis jumpTargetAt: p) = head]) ifTrue: [end := p].
			p := (p + (analysis lengthAt: p)) asInt32]
			ifFalse: [p := (p + 1) asInt32]].
	end < 0 ifTrue: [^self].
	"what the loop does, and who jumps into it"
	sends := 0.
	p := 0 asInt32.
	[p < n] whileTrue: [
		(analysis isStart: p) ifTrue: [
			op := analysis byteAt: p.
			(p >= head and: [p <= end])
				ifTrue: [
					(p ~= head and: [analysis isLoopHead: p]) ifTrue: [^self].
					(op = 16r8F or: [op = 16r76 or: [op = 16r94]]) ifTrue: [^self].
					(op = 16r8D or: [op = 16r8E or: [op >= 16rC0 and: [op < 16rF0]]]) ifTrue: [sends := sends + 1].
					(op >= 16rA0 and: [op < 16rC0]) ifTrue: [
						(self specialSends: op - 16rA0) ifTrue: [sends := sends + 1]].
					((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [
						k := analysis specialIndexOf: analysis bytecodes + p.
						(self specialSends: k) ifTrue: [sends := sends + 1]]]
				ifFalse: [
					((op >= 16r90 and: [op <= 16r92]) and: [(analysis jumpTargetAt: p) >= head and: [(analysis jumpTargetAt: p) <= end]]) ifTrue: [^self]].
			p := (p + (analysis lengthAt: p)) asInt32]
			ifFalse: [p := (p + 1) asInt32]].
	loopId + 1 >= (BL_MAX_LOOPS quo: 4) ifTrue: [^self].
	"the most used temps"
	c := 0.
	1 to: 3 do: [:round |
		best := -1.
		bestCount := sends max: 1.
		0 to: curArgs + curTemps - 1 do: [:tt |
			(self isLoopTemp: tt among: c) ifFalse: [
				t := self uses: tt from: head to: end.
				t > bestCount ifTrue: [
					best := tt.
					bestCount := t]]].
		best >= 0 ifTrue: [
			loopTable at: 4 * (loopId + 1) + 1 + c put: best.
			c := c + 1]].
	c = 0 ifTrue: [^self].
	loopId := loopId + 1.
	loopTable at: 4 * loopId put: c.
	loopActive := true.
	loopEnd := end asInt32.
	asm comment: 'the loop''s temps into x26-x28'.
	self emitLoadLoopTemps: loopId
!
isLoopTemp: t among: c
	0 to: c - 1 do: [:i | (loopTable at: 4 * (loopId + 1) + 1 + i) = t ifTrue: [^true]].
	^false
!
uses: t from: head to: end
	"Pushes of and stores into temp t in [head, end]."
	| p op c n |
	c := 0.
	p := head.
	[p <= end] whileTrue: [
		(analysis isStart: p) ifTrue: [
			op := analysis byteAt: p.
			n := -1.
			op < 16r10 ifTrue: [n := op].
			(op >= 16r60 and: [op < 16r68]) ifTrue: [n := op - 16r60].
			(op = 16r80 or: [op = 16r84 or: [op = 16r87]]) ifTrue: [n := analysis byteAt: p + 1].
			n = t ifTrue: [c := c + 1].
			((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [
				(analysis byteAt: p + 1) = t ifTrue: [c := c + 1].
				((op = 16r97 or: [op >= 16r9A and: [op < 16rA0]]) and: [(analysis byteAt: p + 2) = t]) ifTrue: [c := c + 1]].
			p := (p + (analysis lengthAt: p)) asInt32]
			ifFalse: [p := (p + 1) asInt32]].
	^c
!
specialSends: k
	"Special selector k compiles to a send (with the flags as they are), not to inline code whose slow paths reload the loop temps."
	(k = 19 or: [k = 20 or: [k = 29]]) ifTrue: [^false].
	(k = 23 or: [k = 24]) ifTrue: [^(runtime prims and: [brt nilTestsInlinable]) not].
	(k <= 8 or: [k = 10 or: [k >= 12 and: [k <= 15]]]) ifTrue: [^runtime arith not].
	k = 9 ifTrue: [^runtime float not].
	(k = 16 or: [k = 17]) ifTrue: [^runtime access not].
	^true
!
loopRegOf: t
	"The register holding temp t in the current loop, -1 if none."
	| c |
	loopActive ifFalse: [^-1 asInt32].
	c := loopTable at: 4 * loopId.
	0 to: c - 1 do: [:i | (loopTable at: 4 * loopId + 1 + i) = t ifTrue: [^(X26 + i) asInt32]].
	^-1 asInt32
!
emitLoadLoopTemps: id
	"Loop id's temps from their slots into x26-x28 (entering, or after a call)."
	<function>
	id < 0 ifTrue: [^self].
	0 to: (loopTable at: 4 * id) - 1 do: [:i |
		asm comment: 'x%d := temp %d' with: 26 + i.
		asm ldr: X26 + i base: X20 offset: (self slot: (loopTable at: 4 * id + 1 + i))]
!
noteLoopResume: pc
	"The interpreter may continue at a loop head: through a stub that loads the loop's temps if it has some."
	| s |
	loopActive ifFalse: [^runtime noteResume: pc at: asm pc - codeStart].
	s := self slow: SL_RESUME pc: pc depth: (analysis depthAt: pc).
	s < 0 ifTrue: [^self].
	slR at: s put: -1.
	slCont at: s put: (self labelFor: pc)
! !

!JitBaselineCompiler methodsFor: 'simulated stack'!
ssReset: d
	"Control merges at a label: every entry is in its slot, no register holds anything."
	<function>
	0 to: d - 1 do: [:i | ssKind at: i put: SS_SLOT].
	ssTop := d.
	ssBase := d.
	0 to: 31 do: [:r | regOwner at: r put: -1].
	self dropDoubles
!
dropDoubles
	"No d register holds anything (a merge, a call)."
	<function>
	0 to: 15 do: [:r | dregRefs at: r put: 0].
	0 to: SS_MAX - 1 do: [:t | tempD at: t put: -1]
!
dAlloc
	"A free d register of d8-d15 (owned once by the caller); temps' cached values are evicted first, then the deepest unboxed entry is boxed."
	<function>
	8 to: 15 do: [:r | (dregRefs at: r) = 0 ifTrue: [
		dregRefs at: r put: 1.
		^r]].
	0 to: curArgs + curTemps - 1 do: [:t | (tempD at: t) >= 0 ifTrue: [
		self dRelease: (tempD at: t).
		tempD at: t put: -1]].
	8 to: 15 do: [:r | (dregRefs at: r) = 0 ifTrue: [
		dregRefs at: r put: 1.
		^r]].
	ssBase to: ssTop - 1 do: [:i | (ssKind at: i) = SS_DREG ifTrue: [
		self ssSpill: i.
		^self dAlloc]].
	asm fail: ASM_ERR_OPERAND.
	^8
!
hasDoubles
	0 to: ssTop - 1 do: [:i | (ssKind at: i) = SS_DREG ifTrue: [^true]].
	0 to: curArgs + curTemps - 1 do: [:t | (tempD at: t) >= 0 ifTrue: [^true]].
	^false
!
dRelease: r
	r >= 8 ifTrue: [dregRefs at: r put: ((dregRefs at: r) - 1) asInt8]
!
dRetain: r
	dregRefs at: r put: ((dregRefs at: r) + 1) asInt8
!
dreg: r
	"The D register code of d register r."
	^D0 + r
!
tempDouble: t
	"The d register caching temp t's value unboxed, -1 if none."
	(t < 0 or: [t >= (curArgs + curTemps)]) ifTrue: [^-1].
	^(tempD at: t) asInt32
!
setTemp: t double: r
	"Temp t's value is now (also) unboxed in d register r (-1: not)."
	(t < 0 or: [t >= (curArgs + curTemps)]) ifTrue: [^self].
	(tempD at: t) >= 0 ifTrue: [self dRelease: (tempD at: t)].
	tempD at: t put: r asInt8.
	r >= 0 ifTrue: [self dRetain: r]
!
ssPush: kind val: v reg: r
	<function>
	<var: #kind type: 'int32_t'>
	ssTop >= SS_MAX ifTrue: [^false].
	ssKind at: ssTop put: kind asUInt8.
	ssVal at: ssTop put: v.
	ssReg at: ssTop put: r asInt8.
	ssInSlot at: ssTop put: 0.
	(kind = SS_REG and: [r >= 0]) ifTrue: [regOwner at: r put: ssTop].
	ssTop := ssTop + 1.
	^true
!
ssPushReg: r
	^self ssPush: SS_REG val: 0 reg: r
!
ssPop: n
	"Drop the top n entries (their registers become free)."
	<function>
	| i |
	1 to: n do: [:k |
		ssTop := ssTop - 1.
		i := ssTop.
		(ssKind at: i) = SS_REG ifTrue: [regOwner at: (ssReg at: i) put: -1].
		(ssKind at: i) = SS_DREG ifTrue: [self dRelease: (ssReg at: i)]].
	ssBase > ssTop ifTrue: [ssBase := ssTop]
!
isPoolReg: r
	"x0-x8, x12-x15; on x86 x0-x5 (the others have no x86 register: Amd64Assembler)"
	^asm isX64
		ifTrue: [r >= 0 and: [r <= 5]]
		ifFalse: [(r >= 0 and: [r <= 8]) or: [r >= 12 and: [r <= 15]]]
!
freeReg: r
	r >= 0 ifTrue: [(self isPoolReg: r) ifTrue: [regOwner at: r put: -1]]
!
allocReg
	"A free register of the pool (x0-x8, x12-x15), spilling the deepest entry in a register if there is none."
	<function>
	0 to: 15 do: [:r | ((self isPoolReg: r) and: [(regOwner at: r) < 0]) ifTrue: [
		regOwner at: r put: SS_MAX.
		^r]].
	ssBase to: ssTop - 1 do: [:i | (ssKind at: i) = SS_REG ifTrue: [
		self ssSpill: i.
		^self allocReg]].
	^X0
!
ssSpill: i
	"Store entry i into its slot."
	<function>
	| k |
	k := ssKind at: i.
	k = SS_SLOT ifTrue: [^self].
	k = SS_REG ifTrue: [
		(ssInSlot at: i) = 0 ifTrue: [
			asm comment: 'spill: stack slot %d' with: i.
			asm str: (ssReg at: i) base: X20 offset: (self slot: i)].
		regOwner at: (ssReg at: i) put: -1].
	k = SS_PINNED ifTrue: [
		asm comment: 'spill nil, true or false: stack slot %d' with: i.
		asm str: (ssVal at: i) base: X20 offset: (self slot: i)].
	k = SS_CONST ifTrue: [
		asm comment: 'spill a constant: stack slot %d' with: i.
		asm mov: X16 imm: (ssVal at: i).
		asm str: X16 base: X20 offset: (self slot: i)].
	k = SS_SELF ifTrue: [
		asm comment: 'spill self: stack slot %d' with: i.
		asm str: self selfReg base: X20 offset: (self slot: i)].
	k = SS_TEMP ifTrue: [
		asm comment: 'spill temp %d' with: (ssVal at: i).
		(self loopRegOf: (ssVal at: i) asInt32) >= 0
			ifTrue: [asm str: (self loopRegOf: (ssVal at: i) asInt32) base: X20 offset: (self slot: i)]
			ifFalse: [
				asm ldr: X16 base: X20 offset: (self slot: (ssVal at: i)).
				asm str: X16 base: X20 offset: (self slot: i)]].
	k = SS_LIT ifTrue: [
		asm comment: 'spill literal %d' with: (ssVal at: i).
		self loadLiteral: (ssVal at: i) into: X16.
		asm str: X16 base: X20 offset: (self slot: i)].
	k = SS_DREG ifTrue: [
		asm comment: 'spill an unboxed Float: box it into stack slot %d' with: i.
		ssKind at: i put: SS_SLOT.
		self emitBox: (ssReg at: i) into: X17.
		asm str: X17 base: X20 offset: (self slot: i).
		self dRelease: (ssReg at: i)].
	ssKind at: i put: SS_SLOT
!
ssFlushTo: n
	"Entries below n go to their slots (adjacent registers with one stp)."
	<function>
	| i |
	i := ssBase.
	[i < n] whileTrue: [
		((i + 1 < n and: [(ssKind at: i) = SS_REG and: [(ssKind at: i + 1) = SS_REG and: [(ssInSlot at: i) = 0 and: [(ssInSlot at: i + 1) = 0 and: [i < 63]]]]]))
			ifTrue: [
				asm comment: 'spill: stack slots %d and the next' with: i.
				asm stp: (ssReg at: i) with: (ssReg at: i + 1) base: X20 offset: (self slot: i).
				regOwner at: (ssReg at: i) put: -1.
				regOwner at: (ssReg at: i + 1) put: -1.
				ssKind at: i put: SS_SLOT.
				ssKind at: i + 1 put: SS_SLOT.
				i := i + 2]
			ifFalse: [
				self ssSpill: i.
				i := i + 1]].
	n > ssBase ifTrue: [ssBase := n]
!
ssFlushAll
	self ssFlushTo: ssTop
!
ssFlushKeepingDoublesTo: n
	"As ssFlushTo:, but unboxed Floats stay in their d registers (the slow path that follows boxes and reloads them around its send)."
	<function>
	<var: #low type: 'int32_t'>
	| low |
	low := -1.
	ssBase to: n - 1 do: [:i |
		(ssKind at: i) = SS_DREG
			ifTrue: [low < 0 ifTrue: [low := i]]
			ifFalse: [self ssSpill: i]].
	low < 0 ifTrue: [low := n].
	n > ssBase ifTrue: [ssBase := low]
!
selfReg
	"x21, the receiver (loaded after a call)."
	selfValid ifFalse: [
		asm comment: 'self (x21 is stale after a call)'.
		asm ldr: X21 base: X20 offset: -8.
		selfValid := true].
	^X21
!
ssMaterialize: i
	"A register holding entry i's value (x21 for self, x23-x25 for nil, true and false); entries loaded here stay in their register."
	<function>
	<returns: 'int32_t'>
	| k r |
	k := ssKind at: i.
	k = SS_REG ifTrue: [^ssReg at: i].
	k = SS_PINNED ifTrue: [^(ssVal at: i) asInt32].
	k = SS_SELF ifTrue: [^self selfReg].
	(k = SS_TEMP and: [(self loopRegOf: (ssVal at: i) asInt32) >= 0]) ifTrue: [^self loopRegOf: (ssVal at: i) asInt32].
	r := self allocReg.
	k = SS_DREG ifTrue: [
		asm comment: 'box an unboxed Float'.
		self emitBox: (ssReg at: i) into: r.
		self dRelease: (ssReg at: i).
		ssInSlot at: i put: 0].
	k = SS_SLOT ifTrue: [
		asm comment: 'load stack slot %d' with: i.
		asm ldr: r base: X20 offset: (self slot: i).
		ssInSlot at: i put: 1].
	k = SS_CONST ifTrue: [
		asm comment: 'the constant'.
		asm mov: r imm: (ssVal at: i).
		ssInSlot at: i put: 0].
	k = SS_TEMP ifTrue: [
		asm comment: 'load temp %d' with: (ssVal at: i).
		asm ldr: r base: X20 offset: (self slot: (ssVal at: i)).
		ssInSlot at: i put: 0].
	k = SS_LIT ifTrue: [
		self loadLiteral: (ssVal at: i) into: r.
		ssInSlot at: i put: 0].
	ssKind at: i put: SS_REG.
	ssReg at: i put: r asInt8.
	regOwner at: r put: i.
	i < ssBase ifTrue: [ssBase := i].
	^r
!
ssMaterialize: i into: r
	"Entry i's value in register r (claimed by the caller)."
	<function>
	| k |
	k := ssKind at: i.
	k = SS_REG ifTrue: [
		(ssReg at: i) ~= r ifTrue: [
			asm comment: 'move'.
			asm mov: r with: (ssReg at: i)].
		^self].
	k = SS_PINNED ifTrue: [
		asm comment: 'nil, true or false'.
		^asm mov: r with: (ssVal at: i)].
	k = SS_SELF ifTrue: [
		selfValid
			ifTrue: [
				asm comment: 'self'.
				asm mov: r with: X21]
			ifFalse: [
				asm comment: 'self'.
				asm ldur: r base: X20 offset: -8].
		^self].
	k = SS_SLOT ifTrue: [
		asm comment: 'load stack slot %d' with: i.
		^asm ldr: r base: X20 offset: (self slot: i)].
	k = SS_CONST ifTrue: [
		asm comment: 'the constant'.
		^asm mov: r imm: (ssVal at: i)].
	k = SS_TEMP ifTrue: [
		(self loopRegOf: (ssVal at: i) asInt32) >= 0 ifTrue: [
			asm comment: 'temp %d (its loop register)' with: (ssVal at: i).
			^asm mov: r with: (self loopRegOf: (ssVal at: i) asInt32)].
		asm comment: 'load temp %d' with: (ssVal at: i).
		^asm ldr: r base: X20 offset: (self slot: (ssVal at: i))].
	k = SS_LIT ifTrue: [^self loadLiteral: (ssVal at: i) into: r].
	k = SS_DREG ifTrue: [
		asm comment: 'box an unboxed Float'.
		self emitBox: (ssReg at: i) into: r]
!
ssIsSmallInt: i
	"Entry i is a SmallInteger constant."
	^(ssKind at: i) = SS_CONST and: [((ssVal at: i) bitAnd: 1) ~= 0]
!
ssTempChanging: t
	"Temp t is about to change: entries that read it lazily load it now."
	<function>
	| r |
	ssBase to: ssTop - 1 do: [:i |
		((ssKind at: i) = SS_TEMP and: [(ssVal at: i) = t]) ifTrue: [
			(self loopRegOf: t) >= 0
				ifTrue: [
					"its loop register changes too: a copy"
					r := self allocReg.
					asm mov: r with: (self loopRegOf: t).
					ssKind at: i put: SS_REG.
					ssReg at: i put: r asInt8.
					ssInSlot at: i put: 0.
					regOwner at: r put: i.
					i < ssBase ifTrue: [ssBase := i]]
				ifFalse: [self ssMaterialize: i]]]
!
ssDropRegsAfterCall
	"A call clobbered the scratch registers, x21 and the d registers (every entry is in its slot)."
	0 to: 31 do: [:r | regOwner at: r put: -1].
	self dropDoubles.
	selfValid := false
! !

!JitBaselineCompiler methodsFor: 'literals'!
literalLabel: i
	"The label of the pool word holding literal i (the runtime keeps it current for the collector)."
	(poolLabels at: i) < 0 ifTrue: [poolLabels at: i put: asm newLabel].
	^poolLabels at: i
!
loadLiteral: i into: r
	<function>
	(i < 0 or: [i >= analysis numLiterals or: [i > 255]]) ifTrue: [^asm fail: ASM_ERR_RANGE].
	runtime c4Baseline ifTrue: [
		"CM_LITERALS is a validated pinned strong array; load its current oop,
		not a copied literal or resolved body address. A forwarded raw alias
		can be copied as an oop, but native code must not inspect its identity."
		asm adr: r label: headerLabel.
		asm ldr: r base: r offset: 0.
		asm ldr: r base: r offset: (self fieldOffset: CM_LITERALS).
		^asm ldr: r base: r offset: (self fieldOffset: i)].
	asm comment: 'literal %d (pool)' with: i.
	asm ldr: r label: (self literalLabel: i asInt32)
!
emitLiterals
	"The pool: the method's literals, then the inline caches' classes; the JitMethod header follows (8-aligned)."
	<function>
	asm isX64
		ifTrue: [asm alignTo: 8]
		ifFalse: [(asm pc bitAnd: 7) ~= 0 ifTrue: [asm nop]].
	0 to: 255 do: [:i | (poolLabels at: i) >= 0 ifTrue: [
		asm comment: 'literal %d' with: i.
		asm bind: (poolLabels at: i).
		asm emit64: (analysis literalAt: i)]].
	0 to: siteCount - 1 do: [:i |
		asm comment: 'inline cache %d: its class (the selector once megamorphic)' with: i.
		asm bind: (siteLit at: i).
		asm emit64: 0].
	asm bind: headerLabel
! !

!JitBaselineCompiler methodsFor: 'layout'!
methodOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #method) to: 'int64_t'
!
codeOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #code) to: 'int64_t'
!
headerModeOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitMethod *') fieldAddress: #mode) to: 'int64_t'
!
stackLimitNormalOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #stackLimitNormal) to: 'int64_t'
!
megaCacheOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #megaCache) to: 'int64_t'
!
tagClassesOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #tagClasses) to: 'int64_t'
!
blockClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #blockClass) to: 'int64_t'
!
byteStringClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #byteStringClass) to: 'int64_t'
!
byteSymbolClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #byteSymbolClass) to: 'int64_t'
!
byteArrayClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #byteArrayClass) to: 'int64_t'
!
boxedFloatClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #boxedFloatClass) to: 'int64_t'
!
contextClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #contextClass) to: 'int64_t'
!
edenBoxOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #edenBox) to: 'int64_t'
!
hashBoxOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #hashBox) to: 'int64_t'
!
lcgOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #lcgMul) to: 'int64_t'
!
ecodeOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #ecode) to: 'int64_t'
!
intOop: v
	^(v asInt64 << 1) bitOr: 1
! !

!JitBaselineCompiler methodsFor: 'entries'!
emitMethodEntry
	"Checked entry, unchecked entry, the quick method or primitive, the stack check, the frame; then the bytecodes from pc 0. Resumption at pc 0 (a frame the interpreter pushed) checks for interrupts out of line."
	<function>
	| s p |
	runtime c4Baseline
		ifTrue: [
			"Unused by C4 sends: the miss helper resolves the receiver's class."
			asm b: missLabel.
			uentryOffset := (asm pc - codeStart) asInt32]
		ifFalse: [self emitCheckedEntry].
	asm failed ifTrue: [^false].
	asm comment: 'unchecked entry (polymorphic caches, the megamorphic stub, super sends)'.
	p := asm pc.
	(runtime quick and: [analysis primitive = 0]) ifTrue: [self emitQuickMethod].
	(runtime c4Baseline not and: [analysis primitive ~= 0]) ifTrue: [(self emitPrimitive) ifFalse: [^false]].
	plainEntry := asm pc = p.
	(self emitStackCheck: 0) ifFalse: [^false].
	self emitFrameFor: false args: curArgs temps: curTemps.
	(runtime c4Baseline not and: [analysis primitiveHasErrorCode]) ifTrue: [
		asm comment: 'the primitive''s error code (or nil) into the first temp'.
		asm ldr: X16 base: X22 offset: self ecodeOffset.
		asm str: X16 base: X20 offset: (self slot: curArgs)].
	(self emitTierUp: 0 depth: curArgs + curTemps loop: 0) ifFalse: [^false].
	self ssReset: curArgs + curTemps.
	selfValid := true.
	s := self slow: SL_START pc: 0 depth: curArgs + curTemps.
	s < 0 ifTrue: [^false].
	slCont at: s put: (self labelFor: 0).
	^true
!
emitCheckedEntry
	| imm s uentry |
	asm comment: 'checked entry: x0 the receiver, x9 the class the inline cache expects, x20 our fp, x30 back to the send'.
	imm := asm newLabel.
	uentry := asm newLabel.
	asm tst: X0 imm: 7.
	asm b: imm if: COND_NE.
	asm comment: 'an object: its class word'.
	asm isX64
		ifTrue: [asm cmp: X9 withWordAt: X0 offset: 8]
		ifFalse: [
			asm ldr: X16 base: X0 offset: 8.
			asm cmp: X16 with: X9].
	s := self slow: SL_ENTRY_IMM pc: 0 depth: 0.
	s < 0 ifTrue: [^asm fail: ASM_ERR_LABEL].
	slLabel at: s put: imm.
	slCont at: s put: uentry.
	slTarget at: s put: asm newLabel.
	asm comment: 'not the cached class: the miss handler relinks'.
	asm b: (slTarget at: s) if: COND_NE.
	asm isX64 ifFalse: [asm pc - codeStart = BL_UENTRY ifFalse: [^asm fail: ASM_ERR_RANGE]].
	uentryOffset := (asm pc - codeStart) asInt32.
	asm bind: uentry.
!
emitStackCheck: pc
	"x20 is the callee's fp: at or above the limit (or with an interrupt pending) the entry's slow path runs and then retries."
	<function>
	| check s |
	check := asm newLabel.
	asm bind: check.
	s := self slow: SL_ENTRY_SLOW pc: pc depth: 0.
	s < 0 ifTrue: [^false].
	slCont at: s put: check.
	asm comment: 'stack check'.
	asm isX64
		ifTrue: [asm cmp: X20 withStateWordAt: self stackLimitNormalOffset]
		ifFalse: [
			asm ldr: X16 base: X22 offset: self stackLimitNormalOffset.
			asm cmp: X20 with: X16].
	asm b: (slLabel at: s) if: COND_HS.
	asm comment: 'entry: interrupt check'.
	self emitBaselinePollTo: (slLabel at: s).
	runtime c4Baseline ifTrue: [
		check := asm newLabel.
		asm bind: check.
		slCont at: s put: check].
	^true
!
emitBaselinePollTo: aLabel
	"The ticker word is still consumed only by Scheduler. The C4 countdown
	is mutator-owned and also reaches the slow path with no ticker armed."
	runtime c4Baseline ifTrue: [
		asm ldr: X16 base: X22 offset: (self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #c4Budget) to: 'int64_t').
		asm subs: X16 with: X16 imm: 1.
		asm str: X16 base: X22 offset: (self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #c4Budget) to: 'int64_t').
		asm b: aLabel if: COND_EQ].
	self emitInterruptTestTo: aLabel
!
emitFrameFor: isBlock args: na temps: nt
	"Push the Frame and the native frame record: x0 the receiver (a block: the closure), x20 the fp."
	<function>
	| i |
	asm isX64 ifTrue: [^self emitFrameForX64: isBlock args: na temps: nt].
	asm comment: 'native frame record (x29, x30; x29 stays the C frame of jit_enter)'.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm comment: 'x19 := our Frame: code (the header after the code; the runtime sets method from it), closure, ctx nil, fp, pc and sp 0 (lazy: derived from return addresses)'.
	asm add: X19 with: X19 imm: self frameBytes.
	asm adr: X17 label: headerLabel.
	asm str: X17 base: X19 offset: self codeOffset.
	isBlock
		ifTrue: [asm stp: X0 with: X23 base: X19 offset: self closureOffset]
		ifFalse: [asm stp: X23 with: X23 base: X19 offset: self closureOffset].
	asm stp: X20 with: XZR base: X19 offset: self fpOffset.
	isBlock
		ifTrue: [
			asm comment: 'the receiver: the outer context''s, into the closure''s slot'.
			asm ldr: X16 base: X0 offset: (self fieldOffset: BC_OUTER).
			asm ldr: X21 base: X16 offset: (self fieldOffset: CTX_RECEIVER).
			asm stur: X21 base: X20 offset: -8]
		ifFalse: [
			asm comment: 'x21 := the receiver'.
			asm mov: X21 with: X0].
	nt > 0 ifTrue: [asm comment: 'temps := nil'].
	i := na.
	[i < (na + nt)] whileTrue: [
		(i + 1 < (na + nt) and: [i < 63])
			ifTrue: [
				asm stp: X23 with: X23 base: X20 offset: (self slot: i).
				i := i + 2]
			ifFalse: [
				asm str: X23 base: X20 offset: (self slot: i).
				i := i + 1]]
!
emitFrameForX64: isBlock args: na temps: nt
	"x86: the call pushed the native frame record (the return address); nil is a word of the JitState, loaded into x16 once."
	<arch: #x86_64>
	asm comment: 'native frame record: the return address the call pushed; x19 := our Frame: code (the header after the code; the runtime sets method from it), closure, ctx nil, fp, pc and sp 0 (lazy: derived from return addresses)'.
	asm add: X19 with: X19 imm: self frameBytes.
	asm adr: X17 label: headerLabel.
	asm str: X17 base: X19 offset: self codeOffset.
	asm ldr: X16 base: X22 offset: self nilOffset.
	asm str: (isBlock ifTrue: [X0] ifFalse: [X16]) base: X19 offset: self closureOffset.
	asm str: X16 base: X19 offset: self ctxOffset.
	asm str: X20 base: X19 offset: self fpOffset.
	asm str: XZR base: X19 offset: self pcOffset.
	isBlock
		ifTrue: [
			asm comment: 'the receiver: the outer context''s, into the closure''s slot'.
			asm ldr: X17 base: X0 offset: (self fieldOffset: BC_OUTER).
			asm ldr: X21 base: X17 offset: (self fieldOffset: CTX_RECEIVER).
			asm stur: X21 base: X20 offset: -8]
		ifFalse: [
			asm comment: 'x21 := the receiver'.
			asm mov: X21 with: X0].
	nt > 0 ifTrue: [asm comment: 'temps := nil'].
	na to: na + nt - 1 do: [:i | asm str: X16 base: X20 offset: (self slot: i)]
!
emitBlockEntry: pc
	"The block whose body starts at pc (after its 0x8F): entered from the block stub with x0 the closure and x20 the fp (args in place)."
	<function>
	| p na nt fs size entry s |
	p := pc - 6.
	na := (analysis byteAt: p + 1) asInt32.
	nt := (analysis byteAt: p + 2) asInt32.
	fs := (analysis byteAt: p + 3) asInt32.
	size := (((analysis byteAt: p + 4) asInt64 << 8) bitOr: (analysis byteAt: p + 5)) asInt32.
	fs < (na + nt) ifTrue: [fs := na + nt].
	(self pushRegion: pc + size args: na temps: nt size: fs) ifFalse: [^false].
	blockCount >= BL_MAX_BLOCKS ifTrue: [^false].
	entry := asm newLabel.
	asm bind: entry.
	blockPcs at: blockCount put: pc.
	blockLabels at: blockCount put: entry.
	blockCount := blockCount + 1.
	asm comment: 'block entry: x0 the closure, x20 our fp, x30 back to the value send'.
	(self emitStackCheck: pc) ifFalse: [^false].
	self emitFrameFor: true args: na temps: nt.
	(self emitTierUp: pc depth: na + nt loop: 0) ifFalse: [^false].
	self ssReset: na + nt.
	selfValid := true.
	dead := false.
	s := self slow: SL_START pc: pc depth: na + nt.
	s < 0 ifTrue: [^false].
	slCont at: s put: (self labelFor: pc).
	asm bind: (self labelFor: pc).
	^true
!
emitQuickMethod
	"^ivar, ^self, ^nil/true/false/0/1, ^literal, ^SmallInteger, setters: without a frame; anything else falls through. A pending interrupt takes the frame's path: sends are safepoints."
	<function>
	| b0 b1 n ok s framed |
	(self isQuickMethod) ifFalse: [^self].
	framed := asm newLabel.
	asm comment: 'quick method: interrupt check (with a frame if pending)'.
	self emitInterruptTestTo: framed.
	self emitQuickBody.
	asm bind: framed
!
isQuickMethod
	| b0 n ok |
	n := analysis size.
	b0 := analysis byteAt: 0.
	n = 1 ifTrue: [^b0 = 16r7A].
	(n = 2 and: [(analysis byteAt: 1) = 16r79]) ifTrue: [
		^(b0 >= 16r10 and: [b0 <= 16r1F]) or: [(b0 >= 16r71 and: [b0 <= 16r75]) or: [b0 >= 16r20 and: [b0 <= 16r3F]]]].
	(n = 4 and: [b0 = 16r93 and: [(analysis byteAt: 3) = 16r79]]) ifTrue: [^true].
	(curTemps = 0 and: [curArgs >= 1 and: [curArgs <= 4 and: [n = (4 * curArgs + 1)]]]) ifFalse: [^false].
	(analysis byteAt: 4 * curArgs) = 16r7A ifFalse: [^false].
	ok := true.
	0 to: curArgs - 1 do: [:k |
		ok := ok and: [(analysis byteAt: 4 * k) = k and: [(analysis byteAt: 4 * k + 1) = 16r85 and: [(analysis byteAt: 4 * k + 3) = 16r78]]]].
	^ok
!
emitQuickBody
	| b0 b1 n s |
	n := analysis size.
	b0 := analysis byteAt: 0.
	n = 1 ifTrue: [
		b0 = 16r7A ifTrue: [
			asm comment: 'quick: ^self'.
			asm ret].
		^self].
	b1 := analysis byteAt: 1.
	(n = 2 and: [b1 = 16r79]) ifTrue: [
		(b0 >= 16r10 and: [b0 <= 16r1F]) ifTrue: [
			asm comment: 'quick: ^inst var %d' with: b0 - 16r10.
			asm ldr: X0 base: X0 offset: (self fieldOffset: b0 - 16r10).
			^asm ret].
		(b0 >= 16r71 and: [b0 <= 16r73]) ifTrue: [
			asm comment: 'quick: ^true, ^false or ^nil'.
			asm mov: X0 with: (b0 = 16r71 ifTrue: [X24] ifFalse: [b0 = 16r72 ifTrue: [X25] ifFalse: [X23]]).
			^asm ret].
		(b0 = 16r74 or: [b0 = 16r75]) ifTrue: [
			asm comment: 'quick: ^0 or ^1'.
			asm mov: X0 imm: (self intOop: b0 - 16r74).
			^asm ret].
		(b0 >= 16r20 and: [b0 <= 16r3F]) ifTrue: [
			asm comment: 'quick: ^literal'.
			self loadLiteral: b0 - 16r20 into: X0.
			^asm ret].
		^self].
	(n = 4 and: [b0 = 16r93 and: [(analysis byteAt: 3) = 16r79]]) ifTrue: [
		asm comment: 'quick: ^SmallInteger'.
		asm mov: X0 imm: (self intOop: (analysis int16At: 1)).
		^asm ret].
	"setters: push temp k, store inst var i, pop for each argument k, then ^self"
	s := asm newLabel.
	asm comment: 'quick setter: an immutable receiver takes the frame''s path'.
	asm ldr: X11 base: X0 offset: 0.
	asm tbnz: X11 bit: 59 to: s.
	0 to: curArgs - 1 do: [:k |
		asm comment: 'inst var %d := argument' with: (analysis byteAt: 4 * k + 2).
		asm ldr: X10 base: X20 offset: (self slot: k).
		asm str: X10 base: X0 offset: (self fieldOffset: (analysis byteAt: 4 * k + 2)).
		self barrier: X0 header: X11 value: X10].
	asm comment: 'answer self'.
	asm ret.
	asm bind: s
! !

!JitBaselineCompiler methodsFor: 'primitives'!
emitPrimitive
	"The method's primitive before its frame: inline machine code for the common ones, then its C function. Success returns to the sender; failure falls through to the frame and the body."
	<function>
	| k fail info |
	k := brt primKindOf: analysis primitive.
	k = brt pkPerform ifTrue: [^self emitPerformPrimitive].
	fail := asm newLabel.
	runtime prims ifTrue: [
		k = brt pkBasicNew ifTrue: [self emitBasicNewFail: fail].
		k = brt pkBasicNewSize ifTrue: [self emitBasicNewSizeFail: fail].
		k = brt pkIdentical ifTrue: [self emitIdenticalPrimitive].
		k = brt pkClass ifTrue: [self emitClassPrimitive].
		k = brt pkClosureValue ifTrue: [self emitClosureValuePrimitive: fail].
		k = brt pkIntOp ifTrue: [self emitIntPrimitive: (brt primOpOf: analysis primitive) fail: fail].
		k = brt pkFloatOp ifTrue: [self emitFloatPrimitive: (brt primOpOf: analysis primitive) fail: fail].
		k = brt pkCharValue ifTrue: [self emitCharValuePrimitive: fail].
		k = brt pkCharFromValue ifTrue: [self emitCharFromValuePrimitive: fail].
		(k = brt pkAt or: [k = brt pkAtPut or: [k = brt pkBasicSize]]) ifTrue: [self emitIndexedPrimitive: k fail: fail].
		(k = brt pkUint32At or: [k = brt pkUint32AtPut]) ifTrue: [self emitUint32Primitive: k = brt pkUint32AtPut fail: fail].
		(k = brt pkStringAt and: [curArgs = 1]) ifTrue: [self emitStringPrimitive: false fail: fail].
		(k = brt pkStringAtPut and: [curArgs = 2]) ifTrue: [self emitStringPrimitive: true fail: fail].
		k = brt pkStringCompare ifTrue: [self emitStringComparePrimitive: fail].
		k = brt pkHash ifTrue: [self emitHashPrimitive: fail].
		(k = brt pkReplace and: [curArgs = 4]) ifTrue: [self emitReplacePrimitive: fail]].
	k = brt pkMarker ifTrue: [^true].
	asm bind: fail.
	(runtime prims and: [brt isLeafPrimitive: analysis primitive]) ifTrue: [^self emitLeafPrimitiveCall].
	asm comment: 'the primitive''s C function: success returns to the sender, failure continues here'.
	info := asm newLabel.
	asm adr: X10 label: info.
	asm mov: X2 imm64: (brt primFunctionOf: analysis primitive).
	asm mov: X3 imm: ((curArgs bitOr: ((brt isLeafPrimitive: analysis primitive) ifTrue: [256] ifFalse: [0])) bitOr: (analysis primitiveHasErrorCode ifTrue: [512] ifFalse: [0])).
	asm b: primLabel.
	asm bind: info.
	^true
!
emitLeafPrimitiveCall
	"A leaf primitive's C function, called directly (JitBaselineRuntime>>leafPrim:fn:argc:: nothing to make canonical, no safepoint): its result returns to the sender; failure (0) continues into the frame with the receiver in x0 again."
	<function>
	| failed |
	failed := asm newLabel.
	asm comment: 'the leaf primitive''s C function, called directly: its result (0 if it failed) back to the sender'.
	asm isX64 ifFalse: [asm str: X30 base: SP preIndex: -16].
	asm mov: X0 with: X20.
	asm mov: X1 imm: (brt primFunctionOf: analysis primitive).
	asm mov: X2 imm: curArgs.
	asm isX64
		ifTrue: [asm callCFromSend: brt leafPrimFunction]
		ifFalse: [
			asm mov: X16 imm: brt leafPrimFunction.
			asm blr: X16.
			asm ldr: X30 base: SP postIndex: 16].
	asm cbz: X0 to: failed.
	asm ret.
	asm bind: failed.
	asm ldur: X0 base: X20 offset: -8.
	^true
!
emitPerformPrimitive
	"perform:, perform:with:... (the selector, then n - 1 arguments) and perform:withArguments: (an Array): the target megamorphic sends of the selector to the receiver's class would take, from their table, if its argument count (the entry's fourth word) fits; the arguments one slot down, over the selector; its unchecked entry (x30 still returns to the send). Else the runtime, which fills the table, answers that the primitive failed (the frame and the body follow) or leaves."
	<function>
	| n withArgs imm have go slow fail room loop second found |
	n := curArgs.
	withArgs := (brt primOpOf: analysis primitive) = 1.
	slow := asm newLabel.
	fail := asm newLabel.
	(runtime prims and: [withArgs ifTrue: [n = 2] ifFalse: [n >= 1]]) ifTrue: [
		imm := asm newLabel.
		have := asm newLabel.
		go := asm newLabel.
		second := asm newLabel.
		found := asm newLabel.
		asm comment: 'primitive perform: the megamorphic table''s target for the receiver''s class and the selector'.
		asm ldr: X9 base: X20 offset: (self slot: 0).
		asm and: X16 with: X0 imm: 7.
		asm cbnz: X16 to: imm.
		asm ldr: X16 base: X0 offset: 8.
		asm bind: have.
		asm eor: X10 with: X16 with: X9.
		asm lsr: X10 with: X10 imm: 3.
		asm ldr: X11 base: X22 offset: self megaCacheOffset.
		asm and: X10 with: X10 imm: brt megaMask.
		asm add: X11 with: X11 with: X10 shift: SHIFT_LSL amount: 6.
		asm ldp: X12 with: X13 base: X11 offset: 0.
		asm cmp: X12 with: X16.
		asm b: second if: COND_NE.
		asm cmp: X13 with: X9.
		asm b: found if: COND_EQ.
		asm bind: second.
		asm comment: 'the set''s second entry'.
		asm ldp: X12 with: X13 base: X11 offset: 32.
		asm cmp: X12 with: X16.
		asm b: slow if: COND_NE.
		asm cmp: X13 with: X9.
		asm b: slow if: COND_NE.
		asm add: X11 with: X11 imm: 32.
		asm bind: found.
		asm comment: 'its unchecked entry and argument count (-1: a perform method); room for its frame'.
		asm ldp: X16 with: X17 base: X11 offset: 16.
		asm isX64
			ifTrue: [asm cmp: X20 withStateWordAt: self stackLimitNormalOffset]
			ifFalse: [
				asm ldr: X12 base: X22 offset: self stackLimitNormalOffset.
				asm cmp: X20 with: X12].
		asm b: slow if: COND_HS.
		withArgs
			ifTrue: [
				asm comment: 'an Array of as many elements: they replace the selector and the Array'.
				asm ldr: X9 base: X20 offset: (self slot: 1).
				asm tst: X9 imm: 7.
				asm b: slow if: COND_NE.
				asm ldr: X10 base: X9 offset: 8.
				asm ldr: X11 base: X22 offset: self arrayClassOffset.
				asm cmp: X10 with: X11.
				asm b: slow if: COND_NE.
				asm ldr: W10 base: X9 offset: 0.
				asm cmp: X17 with: X10.
				asm b: slow if: COND_NE.
				asm comment: 'a married sender (not optimized) whose Context would not hold the arguments (a C primitive target may flush the frames): the runtime'.
				room := asm newLabel.
				asm ldr: X10 base: X19 offset: self ctxOffset.
				asm cmp: X10 with: X23.
				asm b: room if: COND_EQ.
				asm ldr: X11 base: X19 offset: self codeOffset.
				asm ldr: W11 base: X11 offset: self headerModeOffset.
				asm cmp: X11 imm: runtime optMode.
				asm b: room if: COND_EQ.
				asm ldr: W10 base: X10 offset: 0.
				asm sub: X10 with: X10 imm: CTX_FIXED.
				asm ldr: X11 base: X19 offset: self fpOffset.
				asm sub: X11 with: X20 with: X11.
				asm lsr: X11 with: X11 imm: 3.
				asm add: X11 with: X11 with: X17.
				asm cmp: X11 with: X10.
				asm b: slow if: COND_HI.
				asm bind: room.
				asm cbz: X17 to: go.
				asm add: X9 with: X9 imm: (self fieldOffset: 0).
				asm mov: X11 with: X20.
				loop := asm newLabel.
				asm bind: loop.
				asm ldr: X10 base: X9 postIndex: 8.
				asm str: X10 base: X11 postIndex: 8.
				asm subs: X17 with: X17 imm: 1.
				asm b: loop if: COND_NE]
			ifFalse: [
				asm cmp: X17 imm: n - 1.
				asm b: slow if: COND_NE.
				n > 1 ifTrue: [asm comment: 'the arguments one slot down, over the selector'].
				1 to: n - 1 do: [:i |
					asm ldr: X12 base: X20 offset: (self slot: i).
					asm str: X12 base: X20 offset: (self slot: i - 1)]].
		asm bind: go.
		asm br: X16.
		asm bind: imm.
		asm add: X17 with: X22 imm: self tagClassesOffset.
		asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
		asm b: have].
	asm bind: slow.
	asm comment: 'the runtime: the table filled, the primitive failed (the frame and the body follow) or leave'.
	asm mov: X1 imm: (n bitOr: (withArgs ifTrue: [256] ifFalse: [0])).
	asm adr: X10 label: fail.
	asm b: performLabel.
	asm bind: fail.
	^true
!
emitIntPrimitive: op fail: fail
	"SmallInteger arithmetic, bit operations, comparisons and divisions of the receiver (x0) and the argument (slot 0); anything else (overflow, other classes, division by zero) the C function."
	<function>
	| right exact |
	asm comment: 'SmallInteger primitive: receiver and argument SmallIntegers'.
	asm tbz: X0 bit: 0 to: fail.
	asm ldr: X1 base: X20 offset: (self slot: 0).
	asm tbz: X1 bit: 0 to: fail.
	op = 0 ifTrue: [
		asm sub: X16 with: X1 imm: 1.
		asm adds: X16 with: X0 with: X16.
		asm b: fail if: COND_VS.
		asm mov: X0 with: X16].
	op = 1 ifTrue: [
		asm sub: X16 with: X1 imm: 1.
		asm subs: X16 with: X0 with: X16.
		asm b: fail if: COND_VS.
		asm mov: X0 with: X16].
	op = 2 ifTrue: [
		asm asr: X16 with: X0 imm: 1.
		asm sub: X17 with: X1 imm: 1.
		asm isX64
			ifTrue: [
				asm muls: X9 with: X16 with: X17.
				asm b: fail if: COND_VS]
			ifFalse: [
				asm mul: X9 with: X16 with: X17.
				asm smulh: X10 with: X16 with: X17.
				asm cmp: X10 with: X9 shift: SHIFT_ASR amount: 63.
				asm b: fail if: COND_NE].
		asm orr: X0 with: X9 imm: 1].
	op = 4 ifTrue: [asm and: X0 with: X0 with: X1].
	op = 5 ifTrue: [asm orr: X0 with: X0 with: X1].
	op = 6 ifTrue: [
		asm eor: X0 with: X0 with: X1.
		asm orr: X0 with: X0 imm: 1].
	op = 7 ifTrue: [
		right := asm newLabel.
		asm comment: 'bitShift: left if the count is not negative (nothing may be lost), else right'.
		asm asr: X16 with: X1 imm: 1.
		asm tbnz: X16 bit: 63 to: right.
		asm cmp: X16 imm: 62.
		asm b: fail if: COND_HS.
		asm sub: X17 with: X0 imm: 1.
		asm lsl: X9 with: X17 with: X16.
		asm asr: X10 with: X9 with: X16.
		asm cmp: X10 with: X17.
		asm b: fail if: COND_NE.
		asm orr: X0 with: X9 imm: 1.
		asm ret.
		asm bind: right.
		asm neg: X16 with: X16.
		asm mov: X17 imm: 63.
		asm cmp: X16 with: X17.
		asm csel: X16 with: X16 with: X17 cond: COND_LO.
		asm asr: X0 with: X0 with: X16.
		asm orr: X0 with: X0 imm: 1].
	(op >= 8 and: [op <= 13]) ifTrue: [
		asm cmp: X0 with: X1.
		asm csel: X0 with: X24 with: X25 cond: (self conditionOf: op - 6)].
	op >= 16 ifTrue: [
		asm comment: (op = 16 ifTrue: ['quo:'] ifFalse: [op = 17 ifTrue: ['rem:'] ifFalse: [op = 18 ifTrue: ['//'] ifFalse: ['\\']]]).
		asm asr: X16 with: X0 imm: 1.
		asm asr: X17 with: X1 imm: 1.
		asm cbz: X17 to: fail.
		asm sdiv: X9 with: X16 with: X17.
		op ~= 16 ifTrue: [asm msub: X10 with: X9 with: X17 sub: X16].
		op >= 18 ifTrue: [
			asm comment: 'floored: a remainder whose sign differs from the divisor''s corrects quotient and remainder'.
			exact := asm newLabel.
			asm cbz: X10 to: exact.
			asm eor: X11 with: X10 with: X17.
			asm tbz: X11 bit: 63 to: exact.
			asm sub: X9 with: X9 imm: 1.
			asm add: X10 with: X10 with: X17.
			asm bind: exact].
		(op = 17 or: [op = 19]) ifTrue: [asm mov: X9 with: X10].
		asm comment: 'a SmallInteger (minVal // -1 is not)'.
		asm add: X10 with: X9 with: X9.
		asm cmp: X9 with: X10 shift: SHIFT_ASR amount: 1.
		asm b: fail if: COND_NE.
		asm orr: X0 with: X10 imm: 1].
	asm ret
!
emitFloatPrimitive: op fail: fail
	"Float arithmetic, comparisons, sqrt and truncated of the receiver (x0) and the argument (slot 0), SmallFloat64 or boxed, into SmallFloat64 results. Anything else: the C function."
	<function>
	| done |
	asm comment: 'Float primitive: the receiver (and the argument) as doubles'.
	self emitToDouble: X0 into: D0 fail: fail.
	op < 14 ifTrue: [
		asm ldr: X1 base: X20 offset: (self slot: 0).
		self emitToDouble: X1 into: D1 fail: fail].
	op >= 8 ifTrue: [
		op = 15 ifTrue: [
			asm comment: 'truncated: a SmallInteger (else the C function)'.
			asm fcmp: D0 with: D0.
			asm b: fail if: COND_VS.
			asm fcvtzs: X16 with: D0.
			asm add: X17 with: X16 with: X16.
			asm cmp: X16 with: X17 shift: SHIFT_ASR amount: 1.
			asm b: fail if: COND_NE.
			asm orr: X0 with: X17 imm: 1.
			^asm ret].
		op <= 13 ifTrue: [
			asm fcmp: D0 with: D1.
			asm csel: X0 with: X24 with: X25 cond: (self floatConditionOf: op - 6).
			^asm ret]].
	op = 0 ifTrue: [asm fadd: D0 with: D0 with: D1].
	op = 1 ifTrue: [asm fsub: D0 with: D0 with: D1].
	op = 2 ifTrue: [asm fmul: D0 with: D0 with: D1].
	op = 3 ifTrue: [
		asm fcmpZero: D1.
		asm b: fail if: COND_EQ.
		asm fdiv: D0 with: D0 with: D1].
	op = 14 ifTrue: [asm fsqrt: D0 with: D0].
	done := asm newLabel.
	self emitBox: D0 into: X0 cont: done fail: fail.
	asm bind: done.
	asm ret
!
emitCharValuePrimitive: fail
	asm comment: 'primitive charValue: a Character''s code'.
	asm and: X16 with: X0 imm: 7.
	asm cmp: X16 imm: 2.
	asm b: fail if: COND_NE.
	asm lsr: X16 with: X0 imm: 3.
	asm lsl: X0 with: X16 imm: 1.
	asm orr: X0 with: X0 imm: 1.
	asm ret
!
emitIndexedPrimitive: k fail: fail
	"at:, at:put: and basicSize of indexable pointers without fixed fields, 32-bit words and bytes: a SmallInteger index (slot 0) within the size, a word or byte value in range, a receiver not immutable; anything else the C function."
	<function>
	| bytes words |
	bytes := asm newLabel.
	words := asm newLabel.
	asm comment: (k = brt pkAt ifTrue: ['primitive at:'] ifFalse: [k = brt pkAtPut ifTrue: ['primitive at:put:'] ifFalse: ['primitive basicSize']]).
	asm tst: X0 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X11 base: X0 offset: 0.
	asm ubfx: X9 with: X11 lsb: H_FMT_SHIFT width: 5.
	asm ubfx: X10 with: X11 lsb: 0 width: 32.
	k ~= brt pkBasicSize ifTrue: [
		asm comment: 'the index: a SmallInteger, zero-based in x16'.
		asm ldr: X1 base: X20 offset: (self slot: 0).
		asm tbz: X1 bit: 0 to: fail.
		asm asr: X16 with: X1 imm: 1.
		asm sub: X16 with: X16 imm: 1].
	k = brt pkAtPut ifTrue: [
		asm comment: 'not immutable'.
		asm tbnz: X11 bit: 59 to: fail.
		asm ldr: X2 base: X20 offset: (self slot: 1)].
	asm add: X17 with: X0 imm: 16.
	asm cmp: X9 imm: F_VAR.
	asm b: bytes if: COND_NE.
	asm comment: 'pointers: the slot count'.
	self emitIndexed: k size: X10 fail: fail.
	k = brt pkAt ifTrue: [asm ldr: X0 base: X17 index: X16 extend: EXT_LSL shift: 3].
	k = brt pkAtPut ifTrue: [
		asm str: X2 base: X17 index: X16 extend: EXT_LSL shift: 3.
		self barrier: X0 header: X11 value: X2.
		asm mov: X0 with: X2].
	asm ret.
	asm bind: bytes.
	asm cmp: X9 imm: F_BYTES.
	asm b: words if: COND_LO.
	asm comment: 'bytes: slots * 8 - (format - 16)'.
	asm lsl: X10 with: X10 imm: 3.
	asm sub: X10 with: X10 with: X9.
	asm add: X10 with: X10 imm: F_BYTES.
	self emitIndexed: k size: X10 fail: fail.
	k = brt pkAt ifTrue: [asm ldrb: W0 base: X17 index: X16].
	k = brt pkAtPut ifTrue: [
		asm tbz: X2 bit: 0 to: fail.
		asm asr: X9 with: X2 imm: 1.
		asm cmp: X9 imm: 255.
		asm b: fail if: COND_HI.
		asm strb: W9 base: X17 index: X16].
	self emitIndexedResult: k.
	asm bind: words.
	asm cmp: X9 imm: F_W32.
	asm b: fail if: COND_LO.
	asm cmp: X9 imm: F_W32 + 1.
	asm b: fail if: COND_HI.
	asm comment: '32-bit words: slots * 2 - (format - 10)'.
	asm lsl: X10 with: X10 imm: 1.
	asm sub: X10 with: X10 with: X9.
	asm add: X10 with: X10 imm: F_W32.
	self emitIndexed: k size: X10 fail: fail.
	k = brt pkAt ifTrue: [asm ldr: W0 base: X17 index: X16 extend: EXT_LSL shift: 2].
	k = brt pkAtPut ifTrue: [
		asm tbz: X2 bit: 0 to: fail.
		asm asr: X9 with: X2 imm: 1.
		asm lsr: X11 with: X9 imm: 32.
		asm cbnz: X11 to: fail.
		asm str: W9 base: X17 index: X16 extend: EXT_LSL shift: 2].
	self emitIndexedResult: k
!
emitIndexed: k size: r fail: fail
	"basicSize answers r; at: and at:put: check the index in x16 against it."
	k = brt pkBasicSize ifTrue: [
		asm add: X0 with: r with: r.
		asm orr: X0 with: X0 imm: 1.
		^asm ret].
	asm cmp: X16 with: r.
	asm b: fail if: COND_HS
!
emitIndexedResult: k
	"at: answers the element loaded into x0 as a SmallInteger, at:put: the value."
	k = brt pkAt ifTrue: [
		asm lsl: X0 with: X0 imm: 1.
		asm orr: X0 with: X0 imm: 1].
	k = brt pkAtPut ifTrue: [asm mov: X0 with: X2].
	asm ret
!
emitStringPrimitive: isPut fail: fail
	"stringAt and stringAtPut: at: and at:put: of a String, bytes or 32-bit words: a SmallInteger index (slot 0) within the size; a Character answered, or stored (a byte's into bytes) into a receiver not immutable. Anything else the C function."
	<function>
	| words |
	words := asm newLabel.
	asm comment: (isPut ifTrue: ['primitive stringAtPut'] ifFalse: ['primitive stringAt']).
	asm tst: X0 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X11 base: X0 offset: 0.
	asm ubfx: X9 with: X11 lsb: H_FMT_SHIFT width: 5.
	asm ubfx: X10 with: X11 lsb: 0 width: 32.
	asm comment: 'the index: a SmallInteger, zero-based in x16'.
	asm ldr: X1 base: X20 offset: (self slot: 0).
	asm tbz: X1 bit: 0 to: fail.
	asm asr: X16 with: X1 imm: 1.
	asm sub: X16 with: X16 imm: 1.
	isPut ifTrue: [
		asm comment: 'not immutable; a Character, its code in x12'.
		asm tbnz: X11 bit: 59 to: fail.
		asm ldr: X2 base: X20 offset: (self slot: 1).
		asm and: X12 with: X2 imm: 7.
		asm cmp: X12 imm: 2.
		asm b: fail if: COND_NE.
		asm lsr: X12 with: X2 imm: 3].
	asm add: X17 with: X0 imm: 16.
	asm cmp: X9 imm: F_BYTES.
	asm b: words if: COND_LO.
	asm comment: 'bytes: slots * 8 - (format - 16)'.
	asm lsl: X10 with: X10 imm: 3.
	asm sub: X10 with: X10 with: X9.
	asm add: X10 with: X10 imm: F_BYTES.
	asm cmp: X16 with: X10.
	asm b: fail if: COND_HS.
	isPut
		ifTrue: [
			asm cmp: X12 imm: 255.
			asm b: fail if: COND_HI.
			asm strb: W12 base: X17 index: X16.
			asm mov: X0 with: X2]
		ifFalse: [
			asm ldrb: W0 base: X17 index: X16.
			asm lsl: X0 with: X0 imm: 3.
			asm orr: X0 with: X0 imm: 2].
	asm ret.
	asm bind: words.
	asm comment: '32-bit words: slots * 2 - (format - 10)'.
	asm cmp: X9 imm: F_W32.
	asm b: fail if: COND_LO.
	asm cmp: X9 imm: F_W32 + 1.
	asm b: fail if: COND_HI.
	asm lsl: X10 with: X10 imm: 1.
	asm sub: X10 with: X10 with: X9.
	asm add: X10 with: X10 imm: F_W32.
	asm cmp: X16 with: X10.
	asm b: fail if: COND_HS.
	isPut
		ifTrue: [
			asm str: W12 base: X17 index: X16 extend: EXT_LSL shift: 2.
			asm mov: X0 with: X2]
		ifFalse: [
			asm ldr: W0 base: X17 index: X16 extend: EXT_LSL shift: 2.
			asm lsl: X0 with: X0 imm: 3.
			asm orr: X0 with: X0 imm: 2].
	asm ret
!
emitUint32Primitive: isPut fail: fail
	"uint32At: and uint32At:put: of bytes at a 1-based byte offset (slot 0), unaligned; anything else the C function."
	<function>
	asm comment: (isPut ifTrue: ['primitive uint32At:put: of bytes'] ifFalse: ['primitive uint32At: of bytes']).
	asm tst: X0 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X11 base: X0 offset: 0.
	asm ubfx: X9 with: X11 lsb: H_FMT_SHIFT width: 5.
	asm cmp: X9 imm: F_BYTES.
	asm b: fail if: COND_LO.
	isPut ifTrue: [asm tbnz: X11 bit: 59 to: fail].
	asm ubfx: X10 with: X11 lsb: 0 width: 32.
	asm lsl: X10 with: X10 imm: 3.
	asm sub: X10 with: X10 with: X9.
	asm add: X10 with: X10 imm: F_BYTES.
	asm comment: 'offset - 1 + 4 within the bytes'.
	asm ldr: X1 base: X20 offset: (self slot: 0).
	asm tbz: X1 bit: 0 to: fail.
	asm asr: X16 with: X1 imm: 1.
	asm sub: X16 with: X16 imm: 1.
	asm tbnz: X16 bit: 63 to: fail.
	asm add: X9 with: X16 imm: 4.
	asm cmp: X9 with: X10.
	asm b: fail if: COND_HI.
	asm add: X17 with: X0 imm: 16.
	isPut ifFalse: [
		asm ldr: W0 base: X17 index: X16 extend: EXT_LSL shift: 0.
		asm lsl: X0 with: X0 imm: 1.
		asm orr: X0 with: X0 imm: 1.
		^asm ret].
	asm ldr: X2 base: X20 offset: (self slot: 1).
	asm tbz: X2 bit: 0 to: fail.
	asm asr: X9 with: X2 imm: 1.
	asm lsr: X11 with: X9 imm: 32.
	asm cbnz: X11 to: fail.
	asm str: W9 base: X17 index: X16 extend: EXT_LSL shift: 0.
	asm mov: X0 with: X2.
	asm ret
!
emitStringComparePrimitive: fail
	"compareWith: of two byte strings: -1, 0 or 1 by bytes, then by size; anything else (wide strings) the C function."
	<function>
	| loop differ sizes |
	loop := asm newLabel.
	differ := asm newLabel.
	sizes := asm newLabel.
	asm comment: 'primitive stringCompare: two byte objects, their sizes in x10 and x14'.
	asm ldr: X1 base: X20 offset: (self slot: 0).
	asm orr: X16 with: X0 with: X1.
	asm tst: X16 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X11 base: X0 offset: 0.
	asm ubfx: X9 with: X11 lsb: H_FMT_SHIFT width: 5.
	asm cmp: X9 imm: F_BYTES.
	asm b: fail if: COND_LO.
	asm ldr: X12 base: X1 offset: 0.
	asm ubfx: X13 with: X12 lsb: H_FMT_SHIFT width: 5.
	asm cmp: X13 imm: F_BYTES.
	asm b: fail if: COND_LO.
	asm ubfx: X10 with: X11 lsb: 0 width: 32.
	asm lsl: X10 with: X10 imm: 3.
	asm sub: X10 with: X10 with: X9.
	asm add: X10 with: X10 imm: F_BYTES.
	asm ubfx: X14 with: X12 lsb: 0 width: 32.
	asm lsl: X14 with: X14 imm: 3.
	asm sub: X14 with: X14 with: X13.
	asm add: X14 with: X14 imm: F_BYTES.
	asm cmp: X10 with: X14.
	asm csel: X15 with: X10 with: X14 cond: COND_LO.
	asm add: X16 with: X0 imm: 16.
	asm add: X17 with: X1 imm: 16.
	asm comment: 'the common bytes'.
	asm bind: loop.
	asm cbz: X15 to: sizes.
	asm ldrb: W9 base: X16 postIndex: 1.
	asm ldrb: W13 base: X17 postIndex: 1.
	asm sub: X15 with: X15 imm: 1.
	asm cmp: X9 with: X13.
	asm b: loop if: COND_EQ.
	asm bind: differ.
	asm comment: '-1 or 1 by the first different byte'.
	asm mov: X0 imm: (self intOop: 1).
	asm mov: X9 imm: (self intOop: -1).
	asm csel: X0 with: X9 with: X0 cond: COND_LO.
	asm ret.
	asm bind: sizes.
	asm comment: 'equal so far: -1, 0 or 1 by the sizes'.
	asm mov: X0 imm: (self intOop: 0).
	asm cmp: X10 with: X14.
	asm b: differ if: COND_NE.
	asm ret
!
emitReplacePrimitive: fail
	"replaceFrom:to:with:startingAt: (start, stop, the replacement and its start in slots 0-3) of bytes, 32-bit words or indexable pointers without fixed fields from an object of the same kind, within both: the copy stub (memmove's semantics). An immutable receiver, an old pointer receiver not remembered yet (the C function remembers it), anything else: the C function."
	<function>
	| words ptrs |
	words := asm newLabel.
	ptrs := asm newLabel.
	asm comment: 'primitive replaceFrom:to:with:startingAt: the receiver not immutable, the replacement an object'.
	asm tst: X0 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X9 base: X0 offset: 0.
	asm tbnz: X9 bit: 59 to: fail.
	asm ldr: X1 base: X20 offset: (self slot: 2).
	asm tst: X1 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X2 base: X1 offset: 0.
	asm comment: 'start, stop and the replacement''s start: SmallIntegers (x3, x4, x5)'.
	asm ldr: X3 base: X20 offset: (self slot: 0).
	asm tbz: X3 bit: 0 to: fail.
	asm ldr: X4 base: X20 offset: (self slot: 1).
	asm tbz: X4 bit: 0 to: fail.
	asm ldr: X5 base: X20 offset: (self slot: 3).
	asm tbz: X5 bit: 0 to: fail.
	asm asr: X3 with: X3 imm: 1.
	asm asr: X4 with: X4 imm: 1.
	asm asr: X5 with: X5 imm: 1.
	asm comment: 'formats (x10, x11) and sizes (x9, x2) of both'.
	asm ubfx: X10 with: X9 lsb: H_FMT_SHIFT width: 5.
	asm ubfx: X11 with: X2 lsb: H_FMT_SHIFT width: 5.
	asm ubfx: X9 with: X9 lsb: 0 width: 32.
	asm ubfx: X2 with: X2 lsb: 0 width: 32.
	asm cmp: X10 imm: F_BYTES.
	asm b: words if: COND_LO.
	asm comment: 'bytes from bytes: slots * 8 - (format - 16)'.
	asm cmp: X11 imm: F_BYTES.
	asm b: fail if: COND_LO.
	asm lsl: X9 with: X9 imm: 3.
	asm sub: X9 with: X9 with: X10.
	asm add: X9 with: X9 imm: F_BYTES.
	asm lsl: X2 with: X2 imm: 3.
	asm sub: X2 with: X2 with: X11.
	asm add: X2 with: X2 imm: F_BYTES.
	self emitReplaceShift: 0 fail: fail.
	asm bind: words.
	asm cmp: X10 imm: F_W32.
	asm b: ptrs if: COND_LO.
	asm cmp: X10 imm: F_W32 + 1.
	asm b: fail if: COND_HI.
	asm comment: '32-bit words from 32-bit words: slots * 2 - (format - 10)'.
	asm cmp: X11 imm: F_W32.
	asm b: fail if: COND_LO.
	asm cmp: X11 imm: F_W32 + 1.
	asm b: fail if: COND_HI.
	asm lsl: X9 with: X9 imm: 1.
	asm sub: X9 with: X9 with: X10.
	asm add: X9 with: X9 imm: F_W32.
	asm lsl: X2 with: X2 imm: 1.
	asm sub: X2 with: X2 with: X11.
	asm add: X2 with: X2 imm: F_W32.
	self emitReplaceShift: 2 fail: fail.
	asm bind: ptrs.
	asm comment: 'pointers from pointers, no fixed fields'.
	asm cmp: X10 imm: F_VAR.
	asm b: fail if: COND_NE.
	asm cmp: X11 imm: F_VAR.
	asm b: fail if: COND_NE.
	stubs emitBulkRefCopyGuardFor: X0 header: -1 slow: fail.
	self emitReplaceShift: 3 fail: fail
!
emitReplaceShift: s fail: fail
	"The rest of replaceFrom:to:with:startingAt: for elements of 1 << s bytes: start, stop and the replacement's start in x3, x4, x5, the sizes of receiver and replacement in x9, x2."
	| done |
	done := asm newLabel.
	asm comment: 'start >= 1; n := stop - start + 1 (x16): none, done; fewer, the C function'.
	asm cmp: X3 imm: 1.
	asm b: fail if: COND_LT.
	asm sub: X16 with: X4 with: X3.
	asm add: X16 with: X16 imm: 1.
	asm cbz: X16 to: done.
	asm tbnz: X16 bit: 63 to: fail.
	asm comment: 'stop within the receiver, the replacement''s n from its start within it'.
	asm cmp: X4 with: X9.
	asm b: fail if: COND_GT.
	asm cmp: X5 imm: 1.
	asm b: fail if: COND_LT.
	asm add: X17 with: X5 with: X16.
	asm sub: X17 with: X17 imm: 1.
	asm cmp: X17 with: X2.
	asm b: fail if: COND_GT.
	asm comment: 'the copy stub: x16 the destination, x17 the source, n << %d bytes' with: s.
	s = 0
		ifTrue: [asm mov: stubs copyCountRegister with: X16]
		ifFalse: [asm lsl: stubs copyCountRegister with: X16 imm: s].
	asm sub: X3 with: X3 imm: 1.
	asm add: X16 with: X0 with: X3 shift: SHIFT_LSL amount: s.
	asm add: X16 with: X16 imm: 16.
	asm sub: X5 with: X5 imm: 1.
	asm add: X17 with: X1 with: X5 shift: SHIFT_LSL amount: s.
	asm add: X17 with: X17 imm: 16.
	asm str: X30 base: SP preIndex: -16.
	asm bl: (asm labelAt: stubs blCopyStub).
	asm ldr: X30 base: SP postIndex: 16.
	asm bind: done.
	asm ret
!
emitCharFromValuePrimitive: fail
	asm comment: 'primitive charFromValue: the Character of a code point (0 to 16r10FFFF)'.
	asm ldr: X1 base: X20 offset: (self slot: 0).
	asm tbz: X1 bit: 0 to: fail.
	asm asr: X16 with: X1 imm: 1.
	asm mov: X17 imm: CHAR_VALUE_MAX.
	asm cmp: X16 with: X17.
	asm b: fail if: COND_HI.
	asm lsl: X0 with: X16 imm: 3.
	asm orr: X0 with: X0 imm: 2.
	asm ret
!
emitHashPrimitive: fail
	asm comment: 'primitive identityHash: an object''s header hash'.
	asm tst: X0 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X16 base: X0 offset: 0.
	asm ubfx: X16 with: X16 lsb: H_HASH_SHIFT width: 22.
	asm lsl: X0 with: X16 imm: 1.
	asm orr: X0 with: X0 imm: 1.
	asm ret
!
emitIdenticalPrimitive
	asm comment: 'primitive ==: the receiver and the argument'.
	asm ldr: X16 base: X20 offset: (self slot: 0).
	asm cmp: X0 with: X16.
	asm csel: X0 with: X24 with: X25 cond: COND_EQ.
	asm ret
!
emitClassPrimitive
	| imm |
	imm := asm newLabel.
	asm comment: 'primitive class: an object''s class word, an immediate''s by its tag'.
	asm tst: X0 imm: 7.
	asm b: imm if: COND_NE.
	asm ldr: X0 base: X0 offset: 8.
	asm ret.
	asm bind: imm.
	asm and: X16 with: X0 imm: 7.
	asm add: X17 with: X22 imm: self tagClassesOffset.
	asm ldr: X0 base: X17 index: X16 extend: EXT_LSL shift: 3.
	asm ret
!
emitClosureValuePrimitive: fail
	"value, value: ... of a BlockClosure: the block stub enters its code (x0 the closure, x20 the fp with the arguments); valueWithArguments: (op 1) first copies the Array's elements over it, if there is room for the block's frame."
	| loop go |
	asm comment: 'primitive closure value: a BlockClosure with as many arguments'.
	asm tst: X0 imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X16 base: X0 offset: 8.
	asm ldr: X17 base: X22 offset: self blockClassOffset.
	asm cmp: X16 with: X17.
	asm b: fail if: COND_NE.
	asm ldr: X16 base: X0 offset: (self fieldOffset: BC_NUMARGS).
	(brt primOpOf: analysis primitive) = 1
		ifTrue: [
			asm comment: 'an Array of as many elements; room for the block''s frame'.
			asm ldr: X9 base: X20 offset: (self slot: 0).
			asm tst: X9 imm: 7.
			asm b: fail if: COND_NE.
			asm ldr: X17 base: X9 offset: 8.
			asm ldr: X10 base: X22 offset: self arrayClassOffset.
			asm cmp: X17 with: X10.
			asm b: fail if: COND_NE.
			asm ldr: W17 base: X9 offset: 0.
			asm lsr: X16 with: X16 imm: 1.
			asm cmp: X16 with: X17.
			asm b: fail if: COND_NE.
			asm isX64
				ifTrue: [asm cmp: X20 withStateWordAt: self stackLimitNormalOffset]
				ifFalse: [
					asm ldr: X10 base: X22 offset: self stackLimitNormalOffset.
					asm cmp: X20 with: X10].
			asm b: fail if: COND_HS.
			asm comment: 'the elements replace the Array'.
			loop := asm newLabel.
			go := asm newLabel.
			asm cbz: X17 to: go.
			asm add: X9 with: X9 imm: (self fieldOffset: 0).
			asm mov: X11 with: X20.
			asm bind: loop.
			asm ldr: X10 base: X9 postIndex: 8.
			asm str: X10 base: X11 postIndex: 8.
			asm subs: X17 with: X17 imm: 1.
			asm b: loop if: COND_NE.
			asm bind: go]
		ifFalse: [
			asm cmp: X16 imm: (self intOop: curArgs).
			asm b: fail if: COND_NE].
	asm comment: 'the block''s code (x30 still returns to the send)'.
	asm b: blockLabel
!
emitAllocDynamic: bytesReg fail: fail
	"x9 := a new object of bytesReg bytes in eden (bytesReg preserved); its header word without the hash and its class were pushed on the native stack and are popped here. Uses x11, x12, x16, x17."
	| full after |
	full := asm newLabel.
	after := asm newLabel.
	asm comment: 'allocate in eden: bump the top unless it passes the limit'.
	asm ldr: X16 base: X22 offset: self edenBoxOffset.
	asm ldp: X9 with: X17 base: X16 offset: 0.
	asm add: X11 with: X9 with: bytesReg.
	asm cmp: X11 with: X17.
	asm b: full if: COND_HI.
	asm str: X11 base: X16 offset: 0.
	asm comment: 'the identity hash: the next value of the VM''s generator (never 0)'.
	asm ldr: X16 base: X22 offset: self hashBoxOffset.
	asm ldr: X11 base: X16 offset: 0.
	asm ldp: X12 with: X17 base: X22 offset: self lcgOffset.
	asm madd: X11 with: X11 with: X12 add: X17.
	asm str: X11 base: X16 offset: 0.
	asm ubfx: X11 with: X11 lsb: 40 width: 22.
	asm cmp: X11 imm: 0.
	asm csinc: X11 with: X11 with: XZR cond: COND_NE.
	asm comment: 'header (with the hash) and class'.
	asm ldp: X12 with: X17 base: SP postIndex: 16.
	asm orr: X12 with: X12 with: X11 shift: SHIFT_LSL amount: H_HASH_SHIFT.
	asm stp: X12 with: X17 base: X9 offset: 0.
	asm b: after.
	asm bind: full.
	asm comment: 'eden is full: the C function (it collects)'.
	asm add: SP with: SP imm: 16.
	asm b: fail.
	asm bind: after
!
emitAlloc: n format: fmt classOffset: clsOff fail: fail
	"x9 := a new object of n slots (not initialized), format fmt, its class at clsOff in the JitState, in eden; x10 := its bytes. Uses x11, x12, x16, x17."
	asm mov: X16 imm: (n asInt64 bitOr: fmt asInt64 << H_FMT_SHIFT).
	asm ldr: X17 base: X22 offset: clsOff.
	asm stp: X16 with: X17 base: SP preIndex: -16.
	asm mov: X10 imm: 16 + (8 * n).
	self emitAllocDynamic: X10 fail: fail
!
emitFill: value from: startReg to: endReg
	"Store value into the words from startReg up to endReg (x16, x17 changed)."
	| loop done |
	loop := asm newLabel.
	done := asm newLabel.
	asm add: X16 with: startReg imm: 16.
	asm add: X17 with: startReg with: endReg.
	asm bind: loop.
	asm cmp: X16 with: X17.
	asm b: done if: COND_HS.
	asm str: value base: X16 postIndex: 8.
	asm b: loop.
	asm bind: done
!
emitBasicNewFail: fail
	"basicNew of a class with up to 64 fixed fields."
	asm comment: 'primitive basicNew: the class''s format (spec << 16 | inst size) says fixed fields'.
	asm ldr: X10 base: X0 offset: (self fieldOffset: BEH_FORMAT).
	asm lsr: X16 with: X10 imm: 17.
	asm cmp: X16 imm: 1.
	asm b: fail if: COND_HI.
	asm ubfx: X10 with: X10 lsb: 1 width: 16.
	asm cmp: X10 imm: 64.
	asm b: fail if: COND_HI.
	asm comment: 'the header word: inst size slots, format F_FIXED (F_EMPTY if none)'.
	asm mov: X16 imm: (F_FIXED asInt64 << H_FMT_SHIFT).
	asm cmp: X10 imm: 0.
	asm csel: X16 with: X16 with: XZR cond: COND_NE.
	asm orr: X16 with: X10 with: X16.
	asm stp: X16 with: X0 base: SP preIndex: -16.
	asm lsl: X10 with: X10 imm: 3.
	asm add: X10 with: X10 imm: 16.
	self emitAllocDynamic: X10 fail: fail.
	asm comment: 'fields := nil'.
	self emitFill: X23 from: X9 to: X10.
	asm mov: X0 with: X9.
	asm ret
!
emitBasicNewSizeFail: fail
	"basicNew: of a class of indexable pointers without fixed fields (up to 1024) or of bytes (up to 8191)."
	| bytes |
	asm comment: 'primitive basicNew: a SmallInteger size from 0 to 8191'.
	asm ldr: X16 base: X20 offset: (self slot: 0).
	asm tbz: X16 bit: 0 to: fail.
	asm asr: X16 with: X16 imm: 1.
	asm mov: X17 imm: 8191.
	asm cmp: X16 with: X17.
	asm b: fail if: COND_HI.
	asm ldr: X10 base: X0 offset: (self fieldOffset: BEH_FORMAT).
	asm comment: 'indexable pointers without fixed fields (spec 2, inst size 0)'.
	asm mov: X17 imm: (self intOop: 2 << CLS_SPEC_SHIFT).
	asm cmp: X10 with: X17.
	bytes := asm newLabel.
	asm b: bytes if: COND_NE.
	asm cmp: X16 imm: 1024.
	asm b: fail if: COND_HI.
	asm mov: X10 imm: (F_VAR asInt64 << H_FMT_SHIFT).
	asm orr: X10 with: X10 with: X16.
	asm stp: X10 with: X0 base: SP preIndex: -16.
	asm lsl: X10 with: X16 imm: 3.
	asm add: X10 with: X10 imm: 16.
	self emitAllocDynamic: X10 fail: fail.
	asm comment: 'slots := nil'.
	self emitFill: X23 from: X9 to: X10.
	asm mov: X0 with: X9.
	asm ret.
	asm bind: bytes.
	asm comment: 'bytes (spec 16, inst size 0): format 16 + unused bytes, zeroed'.
	asm mov: X17 imm: (self intOop: 16 << CLS_SPEC_SHIFT).
	asm cmp: X10 with: X17.
	asm b: fail if: COND_NE.
	asm add: X10 with: X16 imm: 7.
	asm lsr: X10 with: X10 imm: 3.
	asm lsl: X17 with: X10 imm: 3.
	asm sub: X17 with: X17 with: X16.
	asm add: X17 with: X17 imm: F_BYTES.
	asm orr: X17 with: X10 with: X17 shift: SHIFT_LSL amount: H_FMT_SHIFT.
	asm stp: X17 with: X0 base: SP preIndex: -16.
	asm lsl: X10 with: X10 imm: 3.
	asm add: X10 with: X10 imm: 16.
	self emitAllocDynamic: X10 fail: fail.
	asm comment: 'bytes := 0'.
	self emitFill: XZR from: X9 to: X10.
	asm mov: X0 with: X9.
	asm ret
! !

!JitBaselineCompiler methodsFor: 'pushes and stores'!
pushTemp: t
	^self ssPush: SS_TEMP val: t reg: -1
!
pushLiteral: i
	"A SmallInteger or Character literal is an immediate; anything else is loaded from the pool when used."
	| v |
	i >= analysis numLiterals ifTrue: [^false].
	runtime c4Baseline ifTrue: [^self ssPush: SS_LIT val: i reg: -1].
	v := analysis literalAt: i.
	(v bitAnd: 7) ~= 0 ifTrue: [^self ssPush: SS_CONST val: v asInt64 reg: -1].
	^self ssPush: SS_LIT val: i reg: -1
!
pushInstVar: i
	| r |
	r := self allocReg.
	asm comment: 'push inst var %d' with: i.
	asm ldr: r base: self selfReg offset: (self fieldOffset: i).
	^self ssPushReg: r
!
pushContextField: i pc: pc
	"0x81 i, i <= 2 (Context's methods read sender, pc and stackp so): the field, unless the receiver is a married Context (its sender a SmallInteger): then the runtime answers it from the frame."
	| married done |
	self ssFlushAll.
	married := asm newLabel.
	done := asm newLabel.
	asm comment: 'push inst var %d of a Context: married?' with: i.
	asm ldr: X9 base: self selfReg offset: (self fieldOffset: CTX_SENDER).
	asm tbnz: X9 bit: 0 to: married.
	asm ldr: X9 base: X21 offset: (self fieldOffset: i).
	asm str: X9 base: X20 offset: (self slot: ssTop).
	asm b: done.
	asm bind: married.
	asm comment: 'married: its frame answers'.
	self emitRuntimeCall: (asm labelAt: stubs contextFieldStub) pc: pc depth: ssTop.
	loopActive ifTrue: [self emitLoadLoopTemps: loopId].
	asm bind: done.
	^self ssPush: SS_SLOT val: 0 reg: -1
!
pushLiteralVariable: i
	| r |
	r := self allocReg.
	self loadLiteral: i into: r.
	asm comment: 'its value'.
	asm ldr: r base: r offset: (self fieldOffset: ASSOC_VALUE).
	^self ssPushReg: r
!
dup
	| i r |
	i := ssTop - 1.
	((ssKind at: i) = SS_SLOT or: [(ssKind at: i) = SS_DREG]) ifTrue: [self ssMaterialize: i].
	(ssKind at: i) = SS_REG ifTrue: [
		r := self allocReg.
		asm comment: 'dup'.
		asm mov: r with: (ssReg at: i).
		^self ssPushReg: r].
	^self ssPush: (ssKind at: i) val: (ssVal at: i) reg: -1
!
storeTemp: t pop: pop
	"temp t := the top (popped if pop)."
	| i k |
	i := ssTop - 1.
	k := ssKind at: i.
	(k = SS_TEMP and: [(ssVal at: i) = t]) ifTrue: [
		pop ifTrue: [self ssPop: 1].
		^true].
	self ssTempChanging: t.
	(self loopRegOf: t) >= 0 ifTrue: [^self storeLoopTemp: t pop: pop].
	k = SS_DREG ifTrue: [
		asm comment: 'temp %d := an unboxed Float, boxed (it stays unboxed in its d register too)' with: t.
		self emitBox: (ssReg at: i) into: X17.
		asm str: X17 base: X20 offset: (self slot: t).
		self setTemp: t double: (ssReg at: i).
		pop ifTrue: [self ssPop: 1].
		^true].
	self setTemp: t double: (k = SS_TEMP ifTrue: [self tempDouble: (ssVal at: i) asInt32] ifFalse: [-1]).
	asm comment: 'temp %d := top' with: t.
	k = SS_REG ifTrue: [asm str: (ssReg at: i) base: X20 offset: (self slot: t)].
	k = SS_PINNED ifTrue: [asm str: (ssVal at: i) base: X20 offset: (self slot: t)].
	k = SS_SELF ifTrue: [asm str: self selfReg base: X20 offset: (self slot: t)].
	(k = SS_CONST or: [k = SS_TEMP or: [k = SS_LIT or: [k = SS_SLOT]]]) ifTrue: [
		pop
			ifTrue: [
				self ssMaterialize: i into: X16.
				asm str: X16 base: X20 offset: (self slot: t)]
			ifFalse: [asm str: (self ssMaterialize: i) base: X20 offset: (self slot: t)]].
	pop ifTrue: [self ssPop: 1].
	^true
!
popStoreTemp: t
	^self storeTemp: t pop: true
!
storeLoopTemp: t pop: pop
	"temp t (in loop register r) := the top: into r and its slot."
	| i k r |
	i := ssTop - 1.
	k := ssKind at: i.
	r := (self loopRegOf: t) asInt32.
	asm comment: 'temp %d := top (its loop register and its slot)' with: t.
	k = SS_DREG
		ifTrue: [
			"boxing may call the runtime, which reloads the loop registers: r after it"
			self emitBox: (ssReg at: i) into: X17.
			asm str: X17 base: X20 offset: (self slot: t).
			asm mov: r with: X17.
			self setTemp: t double: (ssReg at: i)]
		ifFalse: [
			self setTemp: t double: (k = SS_TEMP ifTrue: [self tempDouble: (ssVal at: i) asInt32] ifFalse: [-1]).
			self ssMaterialize: i into: r.
			asm str: r base: X20 offset: (self slot: t)].
	pop ifTrue: [self ssPop: 1].
	^true
!
needsBarrier: i
	"A store of entry i may need the generational barrier (not for immediates nor nil, true, false)."
	| k |
	k := ssKind at: i.
	^(k = SS_CONST or: [k = SS_PINNED]) not
!
storeInstVar: i pc: pc context: isContext
	"inst var i := top (not popped); an immutable receiver leaves to the interpreter, which sends attemptToAssign:withIndex:. isContext (0x88, Context's methods): so does a married Context, whose frames the interpreter flushes first."
	| v s top |
	top := ssTop - 1.
	self ssFlushTo: top.
	v := self ssMaterialize: top.
	asm comment: 'store into inst var %d: is the receiver immutable?' with: i.
	asm ldr: X11 base: self selfReg offset: 0.
	s := self slow: SL_MUSTBEBOOLEAN pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slA at: s put: v asInt8.
	self ifBitSet: X11 bit: 59 to: (slLabel at: s).
	isContext ifTrue: [
		asm comment: 'a married Context (its sender a SmallInteger)?'.
		asm ldr: X9 base: X21 offset: (self fieldOffset: CTX_SENDER).
		asm tbnz: X9 bit: 0 to: (slLabel at: s)].
	asm str: v base: X21 offset: (self fieldOffset: i).
	(self needsBarrier: top) ifTrue: [self barrier: X21 header: X11 value: v].
	^true
!
storeLiteralVariable: i pop: pop
	| v top |
	top := ssTop - 1.
	self ssFlushTo: top.
	v := self ssMaterialize: top.
	self loadLiteral: i into: X10.
	asm comment: 'store into its value'.
	asm str: v base: X10 offset: (self fieldOffset: ASSOC_VALUE).
	(self needsBarrier: top) ifTrue: [
		asm ldr: X11 base: X10 offset: 0.
		self barrier: X10 header: X11 value: v].
	pop ifTrue: [self ssPop: 1].
	^true
!
barrier: obj header: hdr value: v
	"The generational barrier after storing v into obj (hdr: obj's header): an old, unremembered obj and a young v call the remember stub (which preserves the registers). Uses x9, x16, x17."
	<function>
	| done s |
	runtime barrier ifFalse: [
		asm comment: 'store barrier: the remember stub'.
		asm mov: X16 with: obj.
		asm mov: X17 with: v.
		asm str: X30 base: SP preIndex: -16.
		asm bl: rememberLabel.
		asm ldr: X30 base: SP postIndex: 16.
		^self].
	done := asm newLabel.
	s := self slow: SL_BARRIER pc: 0 depth: 0.
	s < 0 ifTrue: [^asm fail: ASM_ERR_LABEL].
	slA at: s put: obj asInt8.
	slB at: s put: v asInt8.
	slCont at: s put: done.
	asm comment: 'store barrier: an immediate needs nothing'.
	asm tst: v imm: 7.
	asm b: done if: COND_NE.
	asm comment: 'nor an old value'.
	asm ldp: X16 with: X17 base: X22 offset: self youngLoOffset.
	asm sub: X9 with: v with: X16.
	asm sub: X17 with: X17 with: X16.
	asm cmp: X9 with: X17.
	asm b: done if: COND_HS.
	asm comment: 'nor a young object or a remembered one'.
	asm sub: X9 with: obj with: X16.
	asm cmp: X9 with: X17.
	asm b: done if: COND_LO.
	asm tst: hdr imm: H_REMEMBERED.
	asm b: (slLabel at: s) if: COND_EQ.
	asm bind: done
! !

!JitBaselineCompiler methodsFor: 'branches'!
ifBitClear: r bit: b to: label
	"tbz reaches 32 KB only: slow paths after a large method need b.cond's 1 MB."
	asm tst: r imm: (1 asUInt64 << b).
	asm b: label if: COND_EQ
!
ifBitSet: r bit: b to: label
	asm tst: r imm: (1 asUInt64 << b).
	asm b: label if: COND_NE
! !

!JitBaselineCompiler methodsFor: 'sends'!
addFp: off
	"x20 += off (the callee's fp)."
	off <= 4095
		ifTrue: [asm add: X20 with: X20 imm: off]
		ifFalse: [
			asm mov: X16 imm: off.
			asm add: X20 with: X20 with: X16]
!
subFp: off
	off <= 4095
		ifTrue: [asm sub: X20 with: X20 imm: off]
		ifFalse: [
			asm mov: X16 imm: off.
			asm sub: X20 with: X20 with: X16]
!
noteRet: pc depth: d info: info
	"The return address just emitted (after a bl to a callee): the frame's pc and sp while the callee runs."
	<function>
	retCount >= BL_MAX_RETS ifTrue: [^asm fail: ASM_ERR_LABEL].
	retOff at: retCount put: (asm pc - codeStart) asUInt32.
	retPc at: retCount put: pc asUInt16.
	retDepth at: retCount put: d asUInt16.
	retInfo at: retCount put: info.
	retCount := retCount + 1
!
sendInfo: pc argc: n selector: sel kind: kind pushes: pushes
	"argc | instruction length << 8 | selector (literal index or special selector) << 16 | kind << 24 (0 literal, 1 super, 2 special) | operands a superinstruction pushed << 26"
	^(((((n asUInt64 bitOr: (analysis lengthAt: pc) asUInt64 << 8) bitOr: (sel asUInt64 bitAnd: 255) << 16) bitOr: kind asUInt64 << 24) bitOr: pushes asUInt64 << 26)) asUInt32
!
emitSiteCall: pc info: info receiver: ri
	"The inline cache's call: receiver and arguments in their slots, the receiver in x0 (entry ri at the slot below the callee's fp)."
	<function>
	| site off |
	siteCount >= BL_MAX_SITES ifTrue: [^asm fail: ASM_ERR_LABEL].
	site := siteCount.
	siteCount := siteCount + 1.
	siteLit at: site put: asm newLabel.
	siteInfo at: site put: info.
	sitePc at: site put: pc asUInt16.
	siteDepth at: site put: (analysis depthAt: pc) asUInt16.
	off := 8 * (ri + 1).
	asm comment: 'x20 := the callee''s fp'.
	self addFp: off.
	asm comment: 'x9 := inline cache %d''s class' with: site.
	asm ldr: X9 label: (siteLit at: site).
	asm comment: 'call the inline cache''s target (the miss stub while unlinked)'.
	asm isX64
		ifTrue: [siteBl at: site put: (asm pc + 1 - codeStart) asUInt32]
		ifFalse: [siteBl at: site put: (asm pc - codeStart) asUInt32].
	asm bl: missLabel.
	self noteRet: pc depth: (analysis depthAt: pc) info: info.
	asm comment: 'back: x0 the result, x20 our fp again'.
	self subFp: off
!
loadReceiver: ri kind: k reg: r val: v
	"x0 := the receiver (entry ri, which was k (r, v) before the stack went to its slots)."
	<function>
	<var: #k type: 'int32_t'>
	<var: #r type: 'int32_t'>
	asm comment: 'x0 := the receiver'.
	k = SS_REG ifTrue: [
		r ~= X0 ifTrue: [asm mov: X0 with: r].
		^self].
	k = SS_PINNED ifTrue: [^asm mov: X0 with: v].
	(k = SS_SELF and: [selfValid]) ifTrue: [^asm mov: X0 with: X21].
	k = SS_CONST ifTrue: [^asm mov: X0 imm: v].
	asm ldr: X0 base: X20 offset: (self slot: ri)
!
prepareSend: ri
	"Every entry to its slot, the receiver (entry ri) also in x0."
	| k r v owner |
	k := ssKind at: ri.
	(k = SS_TEMP or: [k = SS_LIT or: [k = SS_SLOT or: [k = SS_CONST]]]) ifTrue: [
		"load it into x0 right away (then it is stored from there)"
		owner := regOwner at: X0.
		(owner >= 0 and: [owner < SS_MAX]) ifTrue: [self ssSpill: owner].
		self ssMaterialize: ri into: X0.
		ssInSlot at: ri put: (k = SS_SLOT ifTrue: [1] ifFalse: [0]).
		ssKind at: ri put: SS_REG.
		ssReg at: ri put: X0 asInt8.
		regOwner at: X0 put: ri.
		ri < ssBase ifTrue: [ssBase := ri].
		k := SS_REG].
	r := ssReg at: ri.
	v := ssVal at: ri.
	self ssFlushAll.
	self loadReceiver: ri kind: k reg: r val: v
!
finishSend: n pc: pc
	"The send's receiver and n arguments are gone, its result is in x0; the loop's temps again."
	self ssPop: n + 1.
	self ssDropRegsAfterCall.
	loopActive ifTrue: [self emitLoadLoopTemps: loopId].
	self noteContinuation: pc result: X0.
	^self ssPushReg: X0
!
send: pc kind: kind selector: sel argc: n pushes: pushes
	| ri |
	ri := ssTop - n - 1.
	self prepareSend: ri.
	self emitSiteCall: pc info: (self sendInfo: pc argc: n selector: sel kind: kind pushes: pushes) receiver: ri.
	^self finishSend: n pc: pc
! !

!JitBaselineCompiler methodsFor: 'control'!
exitAt: pc
	"Leave to the interpreter, which executes the instruction at pc."
	self ssFlushAll.
	self emitSync: pc depth: ssTop.
	asm b: exitSyncLabel.
	dead := true.
	^true
!
headCheck: h
	"A loop's head, where every turn of the loop passes: the interrupt flag's check (inline), its slow path out of line."
	<function>
	| s |
	s := self slow: SL_INTERRUPT pc: h depth: (analysis depthAt: h).
	s < 0 ifTrue: [^asm fail: ASM_ERR_LABEL].
	slCont at: s put: (self labelFor: h).
	asm comment: 'loop head: interrupt check'.
	self emitBaselinePollTo: (slLabel at: s)
!
backJump: t
	"A backward jump to the loop head t (which checks for interrupts), counting down toward optimization first (--jit opt); answer its label."
	<function>
	| l |
	l := asm newLabel.
	asm bind: l.
	(self emitTierUp: t depth: (analysis depthAt: t) loop: 1) ifFalse: [asm fail: ASM_ERR_LABEL].
	asm comment: 'jump back'.
	asm b: (self labelFor: t).
	^l
!
jump: pc
	| t |
	t := analysis jumpTargetAt: pc.
	(self canThreadInto: t) ifTrue: [^self threadInto: t].
	self ssFlushAll.
	(analysis isLoopHead: t)
		ifTrue: [self backJump: t]
		ifFalse: [
			asm comment: 'jump'.
			asm b: (self labelFor: t)].
	dead := true.
	^true
!
canThreadInto: j
	"Control goes to the conditional jump at j with its condition on top: it can branch right here (as and: or: ifTrue: values do)."
	| op |
	(runtime fuse and: [runtime regs]) ifFalse: [^false].
	(j < curPc or: [j + 3 >= analysis size]) ifTrue: [^false].
	op := analysis byteAt: j.
	(op = 16r91 or: [op = 16r92]) ifFalse: [^false].
	(analysis isLoopHead: j) ifTrue: [^false].
	ssTop >= 1 ifFalse: [^false].
	ssTop = (analysis depthAt: j) ifFalse: [^false].
	^(ssKind at: ssTop - 1) = SS_PINNED or: [(ssKind at: ssTop - 1) = SS_REG]
!
threadInto: j
	"The conditional jump at j, here; then on to the instruction after it."
	| after |
	asm comment: 'jump threading: the conditional jump at pc %d, here' with: j.
	after := (j + 3) asInt32.
	(self conditionalJump: j) ifFalse: [^false].
	dead ifFalse: [
		self ssFlushAll.
		asm b: (self labelFor: after).
		pcMerge at: after put: 1].
	dead := true.
	^true
!
branch: cond to: t
	"Branch to t if cond (the stack is in its slots); a backward branch counts down toward optimization first (--jit opt). Answer the label slow paths branch to for the same jump."
	<function>
	| skip check |
	((analysis isLoopHead: t) and: [counterAddr ~= 0]) ifFalse: [
		asm b: (self labelFor: t) if: cond.
		^self labelFor: t].
	skip := asm newLabel.
	asm b: skip if: (cond bitXor: 1).
	check := self backJump: t.
	asm bind: skip.
	^check
!
conditionalJump: pc
	"Pop the top; jump if it is true (0x91) or false (0x92); anything else leaves for mustBeBoolean."
	| top k r t ifTrue s |
	top := ssTop - 1.
	t := analysis jumpTargetAt: pc.
	ifTrue := (analysis byteAt: pc) = 16r91.
	k := ssKind at: top.
	(k = SS_PINNED and: [(ssVal at: top) ~= X23]) ifTrue: [
		self ssPop: 1.
		((ssVal at: top) = X24) = ifTrue ifTrue: [
			self ssFlushAll.
			asm comment: 'the condition is constant: jump'.
			(analysis isLoopHead: t)
				ifTrue: [self backJump: t]
				ifFalse: [asm b: (self labelFor: t)].
			dead := true].
		^true].
	self ssFlushTo: top.
	r := self ssMaterialize: top.
	self ssPop: 1.
	asm comment: (ifTrue ifTrue: ['pop, jump if true'] ifFalse: ['pop, jump if false']).
	asm cmp: r with: (ifTrue ifTrue: [X24] ifFalse: [X25]).
	self branch: COND_EQ to: t.
	s := self slow: SL_MUSTBEBOOLEAN pc: pc depth: ssTop + 1.
	s < 0 ifTrue: [^false].
	slA at: s put: r asInt8.
	asm comment: 'neither true nor false: the interpreter sends mustBeBoolean'.
	asm cmp: r with: (ifTrue ifTrue: [X25] ifFalse: [X24]).
	asm b: (slLabel at: s) if: COND_NE.
	^true
!
return: pc self: isSelf
	"Pop the frame and the native record, answer x0. A married frame (or frame 0, married when entered) takes the slow path first."
	| s ret |
	isSelf
		ifTrue: [
			asm comment: 'return self'.
			selfValid
				ifTrue: [asm mov: X0 with: X21]
				ifFalse: [asm ldr: X0 base: X20 offset: -8]]
		ifFalse: [
			asm comment: 'return top'.
			self ssMaterialize: ssTop - 1 into: X0].
	ret := asm newLabel.
	s := self slow: SL_RETURN pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slCont at: s put: ret.
	slInfo at: s put: (isSelf ifTrue: [1] ifFalse: [0]).
	asm comment: 'a married frame leaves its slots to its Context'.
	asm ldr: X16 base: X19 offset: self ctxOffset.
	asm cmp: X16 with: X23.
	asm b: (slLabel at: s) if: COND_NE.
	asm bind: ret.
	asm comment: 'pop the frame and the record, return'.
	asm sub: X19 with: X19 imm: self frameBytes.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret.
	dead := true.
	^true
!
nonLocalReturn: pc
	"^ in a block: to the home's sender. The interpreter does it."
	asm comment: 'non-local return: the interpreter unwinds'.
	^self exitAt: pc
!
closure: pc
	"0x8F: a BlockClosure on this frame's (married) Context, both made in eden (eden full: by the runtime); its body is skipped."
	| after slow |
	after := pc + 6 + (((analysis byteAt: pc + 4) asInt64 << 8) bitOr: (analysis byteAt: pc + 5)).
	self ssFlushAll.
	runtime c4Baseline ifFalse: [
		slow := asm newLabel.
		self emitInlineClosure: pc fail: slow.
		asm str: X9 base: X20 offset: (self slot: ssTop).
		asm b: (self labelFor: after asInt32).
		asm bind: slow].
	asm comment: 'eden is full: the runtime makes it (and collects)'.
	self emitRuntimeCall: closureLabel pc: pc depth: ssTop.
	self ssPush: SS_SLOT val: 0 reg: -1.
	asm comment: 'skip the block''s code'.
	asm b: (self labelFor: after asInt32).
	pcMerge at: after put: 1.
	dead := true.
	^true
!
emitInlineClosure: pc fail: fail
	"x9 := the BlockClosure of the 0x8F at pc, made in eden on the frame's Context; a frame without one is married to a Context made in eden (as Interpreter>>marry:). fail: eden is full. Uses x10-x17."
	<function>
	| have n |
	have := asm newLabel.
	asm comment: 'the frame''s Context; none: marry the frame (sender its index, stackp 0, method, closure, receiver, the rest nil)'.
	asm ldr: X13 base: X19 offset: self ctxOffset.
	asm cmp: X13 with: X23.
	asm b: have if: COND_NE.
	n := CTX_FIXED + curFrameSize + CTX_SLACK.
	self emitAlloc: n format: F_FIXVAR classOffset: self contextClassOffset fail: fail.
	self emitFill: X23 from: X9 to: X10.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm sub: X16 with: X19 with: X16.
	asm lsr: X16 with: X16 imm: 5.
	asm orr: X16 with: X16 imm: 1.
	asm str: X16 base: X9 offset: (self fieldOffset: CTX_SENDER).
	asm mov: X16 imm: (self intOop: 0).
	asm adr: X17 label: headerLabel.
	asm ldr: X17 base: X17 offset: 0.
	asm stp: X16 with: X17 base: X9 offset: (self fieldOffset: CTX_STACKP).
	asm ldr: X16 base: X19 offset: self closureOffset.
	asm ldur: X17 base: X20 offset: -8.
	asm stp: X16 with: X17 base: X9 offset: (self fieldOffset: CTX_CLOSURE).
	asm str: X9 base: X19 offset: self ctxOffset.
	asm mov: X13 with: X9.
	asm bind: have.
	n := brt blockInstSize asInt32 max: BC_FRAMESIZE + 1.
	asm comment: 'the closure: outerContext, startpc, numArgs, numTemps, frameSize, the rest nil'.
	self emitAlloc: n format: F_FIXED classOffset: self blockClassOffset fail: fail.
	asm mov: X16 imm: (self intOop: pc + 6).
	asm stp: X13 with: X16 base: X9 offset: (self fieldOffset: BC_OUTER).
	asm mov: X16 imm: (self intOop: (analysis byteAt: pc + 1) asInt64).
	asm mov: X17 imm: (self intOop: (analysis byteAt: pc + 2) asInt64).
	asm stp: X16 with: X17 base: X9 offset: (self fieldOffset: BC_NUMARGS).
	asm mov: X16 imm: (self intOop: (analysis byteAt: pc + 3) asInt64).
	asm str: X16 base: X9 offset: (self fieldOffset: BC_FRAMESIZE).
	BC_FRAMESIZE + 1 to: n - 1 do: [:i | asm str: X23 base: X9 offset: (self fieldOffset: i)]
!
emitRuntimeCall: stubLabel pc: pc depth: d
	"A call of a runtime function that may allocate or switch: pc and sp stored, every entry in its slot; it answers 0 to continue, 1 to leave."
	<function>
	self emitSync: pc depth: d.
	asm mov: X0 with: X19.
	asm bl: stubLabel.
	asm cbnz: X0 to: exitPlainLabel.
	self emitReloadPinned.
	self ssDropRegsAfterCall
!
emitReloadPinned
	asm comment: 'nil, true, false again (a GC may have moved them)'.
	asm ldp: X23 with: X24 base: X22 offset: self nilOffset.
	asm ldr: X25 base: X22 offset: self falseOffset
!
makeArray: pc
	"0x94 n: the top n entries into a new Array, made in eden (young: no store barrier) if n is at most 64; eden full or more: the runtime."
	| n slow done loop |
	n := (analysis byteAt: pc + 1) asInt32.
	self ssFlushAll.
	done := asm newLabel.
	(runtime c4Baseline not and: [n <= 64]) ifTrue: [
		slow := asm newLabel.
		asm comment: 'make an Array in eden, the entries its elements'.
		self emitAlloc: n format: F_VAR classOffset: self arrayClassOffset fail: slow.
		n <= 4
			ifTrue: [
				0 to: n - 1 do: [:i |
					asm ldr: X10 base: X20 offset: (self slot: ssTop - n + i).
					asm str: X10 base: X9 offset: (self fieldOffset: i)]]
			ifFalse: [
				asm add: X11 with: X20 imm: (self slot: ssTop - n).
				asm add: X16 with: X9 imm: (self fieldOffset: 0).
				asm mov: X17 imm: n.
				loop := asm newLabel.
				asm bind: loop.
				asm ldr: X10 base: X11 postIndex: 8.
				asm str: X10 base: X16 postIndex: 8.
				asm subs: X17 with: X17 imm: 1.
				asm b: loop if: COND_NE].
		asm str: X9 base: X20 offset: (self slot: ssTop - n).
		asm b: done.
		asm bind: slow].
	asm comment: 'make an Array: call the runtime'.
	self emitRuntimeCall: makeArrayLabel pc: pc depth: ssTop.
	asm bind: done.
	self ssPop: n.
	^self ssPush: SS_SLOT val: 0 reg: -1
!
outerTemp: pc
	"push (8A), store (8B), pop and store (8C) temp i of the Context depth levels out: in its frame if it is married (sender = the frame's index), else in the Context."
	| op depth i married done v r top |
	op := analysis byteAt: pc.
	depth := analysis byteAt: pc + 1.
	i := analysis byteAt: pc + 2.
	top := ssTop - 1.
	op ~= 16r8A ifTrue: [
		self ssFlushTo: top.
		v := self ssMaterialize: top].
	r := op = 16r8A ifTrue: [self allocReg] ifFalse: [v].
	asm comment: (op = 16r8A ifTrue: ['push outer temp %d'] ifFalse: ['store outer temp %d']) with: i.
	asm ldr: X10 base: X19 offset: self closureOffset.
	asm ldr: X10 base: X10 offset: (self fieldOffset: BC_OUTER).
	2 to: depth do: [:k |
		asm ldr: X9 base: X10 offset: (self fieldOffset: CTX_CLOSURE).
		asm ldr: X10 base: X9 offset: (self fieldOffset: BC_OUTER)].
	asm ldr: X9 base: X10 offset: (self fieldOffset: CTX_SENDER).
	married := asm newLabel.
	done := asm newLabel.
	asm tbnz: X9 bit: 0 to: married.
	asm comment: 'a Context: its slot'.
	op = 16r8A
		ifTrue: [asm ldr: r base: X10 offset: (self fieldOffset: CTX_FIXED + i)]
		ifFalse: [
			asm str: v base: X10 offset: (self fieldOffset: CTX_FIXED + i).
			(self needsBarrier: top) ifTrue: [
				asm ldr: X11 base: X10 offset: 0.
				self barrier: X10 header: X11 value: v]].
	asm b: done.
	asm bind: married.
	asm comment: 'married: the slot in its frame'.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm asr: X9 with: X9 imm: 1.
	asm add: X16 with: X16 with: X9 shift: SHIFT_LSL amount: 6.
	asm ldr: X16 base: X16 offset: self fpOffset.
	op = 16r8A
		ifTrue: [asm ldr: r base: X16 offset: (self slot: i)]
		ifFalse: [asm str: v base: X16 offset: (self slot: i)].
	asm bind: done.
	op = 16r8A ifTrue: [^self ssPushReg: r].
	op = 16r8C ifTrue: [self ssPop: 1].
	^true
!
superinstruction: pc
	"push temp a, push temp / literal / SmallInteger b, then a special selector."
	| op b |
	op := analysis byteAt: pc.
	b := analysis byteAt: pc + 2.
	self pushTemp: (analysis byteAt: pc + 1).
	(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]])
		ifTrue: [self pushTemp: b]
		ifFalse: [
			(op = 16r98 or: [op >= 16rF0 and: [op < 16rF6]])
				ifTrue: [(self pushLiteral: b) ifFalse: [^false]]
				ifFalse: [self ssPush: SS_CONST val: (self intOop: b asInt8) reg: -1]].
	^self special: (analysis specialIndexOf: analysis bytecodes + pc) pc: pc pushes: 2
! !

!JitBaselineCompiler methodsFor: 'special selectors'!
special: k pc: pc pushes: pushes
	"Special selector k (operands on the simulated stack): inline where it applies, else a send through an inline cache."
	<function>
	(k = 19 or: [k = 20]) ifTrue: [
		"Forwarding can make two different oop bit patterns identical."
		runtime c4Baseline ifTrue: [^self sendSpecial: k pc: pc pushes: pushes].
		^self identical: k pc: pc].
	(runtime c4Baseline not and: [k = 29]) ifTrue: [^self classOf: pc].
	((k = 23 or: [k = 24]) and: [runtime c4Baseline not and: [runtime prims and: [brt nilTestsInlinable]]]) ifTrue: [^self nilTest: k - 22 pc: pc].
	(self inlinesIntegers: k) ifTrue: [^self arith: k pc: pc pushes: pushes].
	(runtime float and: [k = 9]) ifTrue: [^self arith: k pc: pc pushes: pushes].
	(runtime access and: [k = 16 or: [k = 17]]) ifTrue: [^self access: k pc: pc pushes: pushes].
	(runtime blocks and: [k = 21 or: [k = 22 or: [k = 30]]]) ifTrue: [^self value: k pc: pc pushes: pushes].
	^self sendSpecial: k pc: pc pushes: pushes
!
inlinesIntegers: k
	"Special selector k has an inline SmallInteger path (arith:pc:pushes:); what it does not take is sent."
	^runtime arith and: [analysis specialInlinesIntegers: k]
!
sendSpecial: k pc: pc pushes: pushes
	| n ri |
	n := analysis specialArgc: k.
	ri := ssTop - n - 1.
	self prepareSend: ri.
	self emitSiteCall: pc info: (self sendInfo: pc argc: n selector: k kind: 2 pushes: pushes) receiver: ri.
	^self finishSend: n pc: pc
!
fusedJumpAfter: pc
	"The pc of a conditional jump that consumes the Boolean of the comparison at pc, -1 if none."
	| next op |
	runtime fuse ifFalse: [^-1].
	next := pc + (analysis lengthAt: pc).
	next >= analysis size ifTrue: [^-1].
	(analysis isStart: next) ifFalse: [^-1].
	((analysis isTarget: next) or: [(pcMerge at: next) = 1]) ifTrue: [^-1].
	op := analysis byteAt: next.
	(op = 16r91 or: [op = 16r92]) ifFalse: [^-1].
	^next
!
conditionOf: k
	"The condition of SmallInteger comparison k (< > <= >= = ~= == ~~) after cmp."
	^k caseOf: {
		[2] -> [COND_LT]. [3] -> [COND_GT]. [4] -> [COND_LE]. [5] -> [COND_GE].
		[6] -> [COND_EQ]. [7] -> [COND_NE]. [19] -> [COND_EQ]}
		otherwise: [COND_NE]
!
floatConditionOf: k
	"After fcmp: false for unordered operands (NaN), except ~=."
	^k caseOf: {
		[2] -> [COND_MI]. [3] -> [COND_GT]. [4] -> [COND_LS]. [5] -> [COND_GE].
		[6] -> [COND_EQ]}
		otherwise: [COND_NE]
!
emitCompareResult: cond pc: pc into: rr
	"rr := true or false by cond, or (fused) branch on cond to the jump's target; answer the jump's pc if fused (its code is consumed), else -1."
	| j t taken ifTrue |
	j := self fusedJumpAfter: pc.
	j < 0 ifTrue: [
		asm comment: 'the Boolean'.
		asm csel: rr with: X24 with: X25 cond: cond.
		^-1].
	t := analysis jumpTargetAt: j.
	ifTrue := (analysis byteAt: j) = 16r91.
	taken := ifTrue ifTrue: [cond] ifFalse: [cond bitXor: 1].
	asm comment: 'compare and branch (fused with the conditional jump)'.
	fusedTarget := self branch: taken to: t.
	pcMerge at: j put: 2.
	^j
!
identical: k pc: pc
	"== and ~~ never send."
	| a b ra rr j |
	a := ssTop - 2.
	b := ssTop - 1.
	self ssFlushTo: a.
	ra := self ssMaterialize: a.
	asm comment: (k = 19 ifTrue: ['=='] ifFalse: ['~~']).
	((ssKind at: b) = SS_CONST and: [(ssVal at: b) >= 0 and: [(ssVal at: b) < 4096]])
		ifTrue: [asm cmp: ra imm: (ssVal at: b)]
		ifFalse: [asm cmp: ra with: (self ssMaterialize: b)].
	rr := self allocReg.
	self ssPop: 2.
	j := self emitCompareResult: (self conditionOf: k) pc: pc into: rr.
	j >= 0 ifTrue: [
		self freeReg: rr.
		^true].
	^self ssPushReg: rr
!
nilTest: t pc: pc
	"isNil (t 1) and notNil (t 2) when only UndefinedObject and ProtoObject define them: a comparison with nil."
	| a ra rr j |
	a := ssTop - 1.
	self ssFlushTo: a.
	ra := self ssMaterialize: a.
	asm comment: (t = 1 ifTrue: ['isNil: == nil'] ifFalse: ['notNil: ~~ nil']).
	asm cmp: ra with: X23.
	rr := self allocReg.
	self ssPop: 1.
	j := self emitCompareResult: (t = 1 ifTrue: [COND_EQ] ifFalse: [COND_NE]) pc: pc into: rr.
	j >= 0 ifTrue: [
		self freeReg: rr.
		^true].
	^self ssPushReg: rr
!
classOf: pc
	"class: an object's class word, an immediate's by its tag (out of line)."
	| a ra rr s |
	a := ssTop - 1.
	self ssFlushTo: a.
	ra := self ssMaterialize: a.
	rr := self allocReg.
	s := self slow: SL_CLASS pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slA at: s put: ra asInt8.
	slR at: s put: rr asInt8.
	slCont at: s put: asm newLabel.
	asm comment: 'class: an immediate''s by its tag (out of line)'.
	asm tst: ra imm: 7.
	asm b: (slLabel at: s) if: COND_NE.
	asm ldr: rr base: ra offset: 8.
	asm bind: (slCont at: s).
	self ssPop: 1.
	^self ssPushReg: rr
!
isCertainFloat: i
	"Entry i is a Float for sure: unboxed, a temp with its unboxed value, a Float constant."
	| k |
	k := ssKind at: i.
	k = SS_DREG ifTrue: [^true].
	(k = SS_TEMP and: [(self tempDouble: (ssVal at: i) asInt32) >= 0]) ifTrue: [^true].
	^k = SS_CONST and: [((ssVal at: i) bitAnd: 7) = 4]
!
loadDouble: bits into: d
	asm comment: 'a Float constant'.
	asm mov: X16 imm: bits.
	asm fmov: d with: X16
!
doubleOf: i scratch: d fail: fail
	"The D register holding entry i's value as a double (d if it has to be decoded or loaded); fail if it is not a number."
	<function>
	<returns: 'int32_t'>
	| k t r |
	k := ssKind at: i.
	k = SS_DREG ifTrue: [^self dreg: (ssReg at: i)].
	k = SS_TEMP ifTrue: [
		t := self tempDouble: (ssVal at: i) asInt32.
		t >= 0 ifTrue: [^self dreg: t]].
	(k = SS_CONST and: [((ssVal at: i) bitAnd: 1) ~= 0 or: [((ssVal at: i) bitAnd: 7) = 4]]) ifTrue: [
		self loadDouble: (self constantDouble: (ssVal at: i)) into: d.
		^d].
	r := self ssMaterialize: i.
	asm comment: 'as a double'.
	self emitToDouble: r into: d fail: fail.
	^d
!
operand: i for: s a: isA
	"How the slow path s finds operand i: a register, a constant (-2, its value in slX or slY), an unboxed Float (-3, in slDA or slDB), or in its slot (-1)."
	| k |
	k := ssKind at: i.
	k = SS_DREG ifTrue: [
		isA
			ifTrue: [
				slA at: s put: -3.
				slDA at: s put: (ssReg at: i)]
			ifFalse: [
				slB at: s put: -3.
				slDB at: s put: (ssReg at: i)].
		^self].
	(k = SS_TEMP and: [(self tempDouble: (ssVal at: i) asInt32) >= 0]) ifTrue: [
		isA
			ifTrue: [
				slA at: s put: -4.
				slX at: s put: (ssVal at: i)]
			ifFalse: [
				slB at: s put: -4.
				slY at: s put: (ssVal at: i)].
		^self].
	(k = SS_PINNED or: [k = SS_SELF]) ifTrue: [
		isA
			ifTrue: [slA at: s put: (k = SS_SELF ifTrue: [X21] ifFalse: [(ssVal at: i) asInt32])]
			ifFalse: [slB at: s put: (k = SS_SELF ifTrue: [X21] ifFalse: [(ssVal at: i) asInt32])].
		^self].
	"a temp in the loop's register: ssMaterialize: answered that register and left the entry a temp (not in the operand's slot)"
	(k = SS_TEMP and: [(self loopRegOf: (ssVal at: i) asInt32) >= 0]) ifTrue: [
		isA
			ifTrue: [slA at: s put: (self loopRegOf: (ssVal at: i) asInt32) asInt8]
			ifFalse: [slB at: s put: (self loopRegOf: (ssVal at: i) asInt32) asInt8].
		^self].
	k = SS_CONST ifTrue: [
		isA
			ifTrue: [
				slA at: s put: -2.
				slX at: s put: (ssVal at: i)]
			ifFalse: [
				slB at: s put: -2.
				slY at: s put: (ssVal at: i)].
		^self].
	isA
		ifTrue: [slA at: s put: ((ssKind at: i) = SS_REG ifTrue: [ssReg at: i] ifFalse: [-1 asInt8])]
		ifFalse: [slB at: s put: ((ssKind at: i) = SS_REG ifTrue: [ssReg at: i] ifFalse: [-1 asInt8])]
!
noteDoublesBelow: a for: s
	"The unboxed Floats below the operands: slow path s boxes them into their slots before its send and unboxes them after."
	<function>
	slSavedStart at: s put: savedCount.
	slSavedCount at: s put: 0.
	ssBase to: a - 1 do: [:i | (ssKind at: i) = SS_DREG ifTrue: [
		savedCount + 2 > BL_MAX_SAVED ifTrue: [^asm fail: ASM_ERR_LABEL].
		saved at: savedCount put: i asInt16.
		saved at: savedCount + 1 put: (ssReg at: i) asInt16.
		savedCount := savedCount + 2.
		slSavedCount at: s put: ((slSavedCount at: s) + 1) asInt16]].
	0 to: curArgs + curTemps - 1 do: [:t | (tempD at: t) >= 0 ifTrue: [
		savedCount + 2 > BL_MAX_SAVED ifTrue: [^asm fail: ASM_ERR_LABEL].
		saved at: savedCount put: (-1 - t) asInt16.
		saved at: savedCount + 1 put: (tempD at: t) asInt16.
		savedCount := savedCount + 2.
		slSavedCount at: s put: ((slSavedCount at: s) + 1) asInt16]]
!
noteLiveRegsFor: s except: r
	"The registers holding stack entries now: slow path s (a call that may collect) stores and reloads them."
	<function>
	slSavedStart at: s put: savedCount.
	slSavedCount at: s put: 0.
	ssBase to: ssTop - 1 do: [:i | ((ssKind at: i) = SS_REG and: [(ssReg at: i) ~= r]) ifTrue: [
		savedCount + 2 > BL_MAX_SAVED ifTrue: [^asm fail: ASM_ERR_LABEL].
		saved at: savedCount put: i asInt16.
		saved at: savedCount + 1 put: ((ssReg at: i) asInt64 bitOr: ((ssInSlot at: i) asInt64 << 8)) asInt16.
		savedCount := savedCount + 2.
		slSavedCount at: s put: ((slSavedCount at: s) + 1) asInt16]]
!
emitBox: d into: r
	"r := the Float in d register d, boxed: a SmallFloat64 if its exponent fits, else (out of line) a BoxedFloat64 from the runtime, with the stack's registers saved around the call. Uses x9-x11, x16, x17."
	<function>
	<var: #d type: 'int32_t'>
	<var: #r type: 'int32_t'>
	| s |
	s := self slow: SL_BOX pc: curPc depth: ssTop.
	s < 0 ifTrue: [^asm fail: ASM_ERR_LABEL].
	slA at: s put: d asInt8.
	slR at: s put: r asInt8.
	slCont at: s put: asm newLabel.
	self noteLiveRegsFor: s except: r.
	self emitBoxFast: s
!
emitBoxFast: s
	| d r |
	d := self dreg: (slA at: s).
	r := slR at: s.
	asm comment: 'box: a SmallFloat64 if its exponent fits (zero, other exponents out of line)'.
	asm fmov: X16 with: d.
	asm lsl: X17 with: X16 imm: 1.
	asm cbz: X17 to: (slLabel at: s).
	asm ubfx: X9 with: X16 lsb: 52 width: 11.
	asm sub: X9 with: X9 imm: 897.
	asm cmp: X9 imm: 253.
	asm b: (slLabel at: s) if: COND_HI.
	asm ror: X17 with: X16 imm: 63.
	asm mov: X9 imm: 16r7000000000000000.
	asm sub: X17 with: X17 with: X9.
	asm lsl: r with: X17 imm: 3.
	asm orr: r with: r imm: 4.
	asm bind: (slCont at: s)
!
emitBoxInSlowPath: d into: r pc: pc depth: depth
	"emitBox:into: where no stack entry is in a register (a slow path)."
	<function>
	| s |
	s := self slow: SL_BOX pc: pc depth: depth.
	s < 0 ifTrue: [^asm fail: ASM_ERR_LABEL].
	slA at: s put: d asInt8.
	slR at: s put: r asInt8.
	slCont at: s put: asm newLabel.
	slSavedStart at: s put: savedCount.
	slSavedCount at: s put: 0.
	self emitBoxFast: s
!
floatArith: k pc: pc pushes: pushes
	"An operand is a Float for sure: decode the other (SmallFloat64, BoxedFloat64, SmallInteger), compute in d registers; the result stays unboxed (comparisons branch or answer a Boolean). Not a number: the slow path sends."
	<function>
	| a b s da db dr rr j compare |
	a := ssTop - 2.
	b := ssTop - 1.
	compare := k >= 2 and: [k <= 7].
	self ssFlushKeepingDoublesTo: a.
	s := self slow: SL_SEND pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slInfo at: s put: ((self sendInfo: pc argc: 1 selector: k kind: 2 pushes: pushes) asInt64 bitOr: SL_DOUBLES).
	self noteDoublesBelow: a for: s.
	asm comment: 'Floats (an operand is one for sure): both as doubles'.
	da := self doubleOf: a scratch: D0 fail: (slLabel at: s).
	db := self doubleOf: b scratch: D1 fail: (slLabel at: s).
	self operand: a for: s a: true.
	self operand: b for: s a: false.
	compare ifTrue: [
		asm fcmp: da with: db.
		rr := self allocReg.
		slR at: s put: rr asInt8.
		self ssPop: 2.
		j := self emitCompareResult: (self floatConditionOf: k) pc: pc into: rr.
		slCont at: s put: asm newLabel.
		j >= 0 ifTrue: [
			slInfo at: s put: (((slInfo at: s) bitOr: SL_FUSED) bitClear: SL_DOUBLES).
			slX at: s put: j.
			slTarget at: s put: fusedTarget.
			asm bind: (slCont at: s).
			self freeReg: rr.
			^true].
		slInfo at: s put: ((slInfo at: s) bitClear: SL_DOUBLES).
		asm bind: (slCont at: s).
		^self ssPushReg: rr].
	k = 9 ifTrue: [
		asm fcmpZero: db.
		asm b: (slLabel at: s) if: COND_EQ].
	self ssPop: 2.
	dr := self dAlloc.
	slR at: s put: dr asInt8.
	asm comment: (k = 0 ifTrue: ['+'] ifFalse: [k = 1 ifTrue: ['-'] ifFalse: [k = 8 ifTrue: ['*'] ifFalse: ['/']]]).
	k = 0 ifTrue: [asm fadd: (self dreg: dr) with: da with: db].
	k = 1 ifTrue: [asm fsub: (self dreg: dr) with: da with: db].
	k = 8 ifTrue: [asm fmul: (self dreg: dr) with: da with: db].
	k = 9 ifTrue: [asm fdiv: (self dreg: dr) with: da with: db].
	slCont at: s put: asm newLabel.
	asm bind: (slCont at: s).
	^self ssPush: SS_DREG val: 0 reg: dr
!
foldable: k a: a b: b
	"Both operands are SmallInteger constants and k folds without overflow."
	| x y r |
	((self ssIsSmallInt: a) and: [self ssIsSmallInt: b]) ifFalse: [^false].
	x := (ssVal at: a) >> 1.
	y := (ssVal at: b) >> 1.
	(k = 0 or: [k = 1]) ifTrue: [
		r := k = 0 ifTrue: [x + y] ifFalse: [x - y].
		^r >= -16r1000000000000000 and: [r < 16r1000000000000000]].
	(k >= 2 and: [k <= 7]) ifTrue: [^true].
	^k = 14 or: [k = 15]
!
fold: k a: a b: b
	| x y c |
	x := (ssVal at: a) >> 1.
	y := (ssVal at: b) >> 1.
	self ssPop: 2.
	(k >= 2 and: [k <= 7]) ifTrue: [
		c := k caseOf: {
			[2] -> [x < y]. [3] -> [x > y]. [4] -> [x <= y]. [5] -> [x >= y]. [6] -> [x = y]}
			otherwise: [x ~= y].
		^self ssPush: SS_PINNED val: (c ifTrue: [X24] ifFalse: [X25]) reg: -1].
	k = 0 ifTrue: [^self ssPush: SS_CONST val: (self intOop: x + y) reg: -1].
	k = 1 ifTrue: [^self ssPush: SS_CONST val: (self intOop: x - y) reg: -1].
	k = 14 ifTrue: [^self ssPush: SS_CONST val: (self intOop: (x bitAnd: y)) reg: -1].
	^self ssPush: SS_CONST val: (self intOop: (x bitOr: y)) reg: -1
!
arith: k pc: pc pushes: pushes
	"SmallInteger arithmetic and comparisons inline (tag checks, overflow branches, immediates); Floats and anything else in the slow path (inline Floats, then a send)."
	<function>
	| a b ra rb rr s imm c compare j aKnown bKnown bv same |
	a := ssTop - 2.
	b := ssTop - 1.
	(self foldable: k a: a b: b) ifTrue: [^self fold: k a: a b: b].
	compare := k >= 2 and: [k <= 7].
	(runtime float and: [k <= 9 and: [(self isCertainFloat: a) or: [self isCertainFloat: b]]]) ifTrue: [^self floatArith: k pc: pc pushes: pushes].
	aKnown := self ssIsSmallInt: a.
	bKnown := self ssIsSmallInt: b.
	bv := ssVal at: b.
	"the same temp twice (x * x): one register"
	same := (ssKind at: a) = SS_TEMP and: [(ssKind at: b) = SS_TEMP and: [(ssVal at: a) = bv]].
	self ssFlushKeepingDoublesTo: a.
	ra := self ssMaterialize: a.
	c := bKnown ifTrue: [bv >> 1] ifFalse: [0].
	"an immediate second operand where the instruction takes one"
	imm := bKnown and: [
		((k = 0 or: [k = 1]) and: [c > -2048 and: [c < 2048]]) or: [
			(compare and: [bv >= 0 and: [bv < 4096]]) or: [
				(k = 12 and: [c > -62 and: [c < 62]]) or: [(k = 14 or: [k = 15]) and: [c >= 0]]]]].
	rb := imm ifTrue: [-2] ifFalse: [same ifTrue: [ra] ifFalse: [self ssMaterialize: b]].
	rr := self allocReg.
	s := self slow: SL_SEND pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slA at: s put: ra asInt8.
	slB at: s put: rb asInt8.
	slY at: s put: bv.
	slR at: s put: rr asInt8.
	slInfo at: s put: ((self sendInfo: pc argc: 1 selector: k kind: 2 pushes: pushes) asInt64 bitOr: ((runtime float and: [k <= 9]) ifTrue: [SL_FLOAT] ifFalse: [0])).
	self noteDoublesBelow: a for: s.
	k = 9
		ifTrue: [
			asm comment: '/: Floats inline (out of line), anything else sends'.
			asm b: (slLabel at: s)]
		ifFalse: [
			asm comment: 'SmallInteger tag checks (else Floats out of line, else a send)'.
			aKnown
				ifTrue: [bKnown ifFalse: [self ifBitClear: rb bit: 0 to: (slLabel at: s)]]
				ifFalse: [
					bKnown
						ifTrue: [self ifBitClear: ra bit: 0 to: (slLabel at: s)]
						ifFalse: [
							asm and: X16 with: ra with: rb.
							self ifBitClear: X16 bit: 0 to: (slLabel at: s)]]].
	compare ifTrue: [
		imm
			ifTrue: [asm cmp: ra imm: bv]
			ifFalse: [asm cmp: ra with: rb].
		self ssPop: 2.
		j := self emitCompareResult: (self conditionOf: k) pc: pc into: rr.
		j >= 0 ifTrue: [
			slInfo at: s put: ((slInfo at: s) bitOr: SL_FUSED).
			slX at: s put: j.
			slTarget at: s put: fusedTarget.
			slCont at: s put: asm newLabel.
			asm bind: (slCont at: s).
			self freeReg: rr.
			^true].
		slCont at: s put: asm newLabel.
		asm bind: (slCont at: s).
		self noteContinuation: pc result: rr.
		^self ssPushReg: rr].
	k = 0 ifTrue: [
		asm comment: '+ (overflow: the slow path)'.
		imm
			ifTrue: [
				c >= 0
					ifTrue: [asm adds: rr with: ra imm: 2 * c]
					ifFalse: [asm subs: rr with: ra imm: -2 * c]]
			ifFalse: [
				asm sub: X16 with: rb imm: 1.
				asm adds: rr with: ra with: X16].
		asm b: (slLabel at: s) if: COND_VS].
	k = 1 ifTrue: [
		asm comment: '- (overflow: the slow path)'.
		imm
			ifTrue: [
				c >= 0
					ifTrue: [asm subs: rr with: ra imm: 2 * c]
					ifFalse: [asm adds: rr with: ra imm: -2 * c]]
			ifFalse: [
				asm sub: X16 with: rb imm: 1.
				asm subs: rr with: ra with: X16].
		asm b: (slLabel at: s) if: COND_VS].
	k = 8 ifTrue: [
		asm comment: '*: a 128-bit product that does not fit goes to the slow path'.
		asm asr: X16 with: ra imm: 1.
		asm sub: X17 with: rb imm: 1.
		asm isX64
			ifTrue: [
				asm muls: rr with: X16 with: X17.
				asm b: (slLabel at: s) if: COND_VS]
			ifFalse: [
				asm mul: rr with: X16 with: X17.
				asm smulh: X9 with: X16 with: X17.
				asm cmp: X9 with: rr shift: SHIFT_ASR amount: 63.
				asm b: (slLabel at: s) if: COND_NE].
		asm orr: rr with: rr imm: 1].
	(k = 10 or: [k = 13]) ifTrue: [self emitDivision: k a: ra b: rb into: rr slow: (slLabel at: s)].
	k = 12 ifTrue: [self emitShift: ra by: rb constant: c immediate: imm into: rr slow: (slLabel at: s)].
	k = 14 ifTrue: [
		asm comment: 'bitAnd:'.
		imm
			ifTrue: [
				(asm logicalImmediate: bv asUInt64 width: 64) >= 0
					ifTrue: [asm and: rr with: ra imm: bv]
					ifFalse: [
						asm mov: X16 imm: bv.
						asm and: rr with: ra with: X16]]
			ifFalse: [asm and: rr with: ra with: rb]].
	k = 15 ifTrue: [
		asm comment: 'bitOr:'.
		imm
			ifTrue: [
				asm mov: X16 imm: bv.
				asm orr: rr with: ra with: X16]
			ifFalse: [asm orr: rr with: ra with: rb]].
	slCont at: s put: asm newLabel.
	asm bind: (slCont at: s).
	self noteContinuation: pc result: rr.
	self ssPop: 2.
	^self ssPushReg: rr
!
emitDivision: k a: ra b: rb into: rr slow: slow
	"// (rounded toward negative infinity) and \\ (the divisor's sign)."
	| exact |
	exact := asm newLabel.
	asm comment: (k = 13 ifTrue: ['//: the quotient rounded toward negative infinity'] ifFalse: ['\\: the remainder with the divisor''s sign']).
	asm asr: X16 with: ra imm: 1.
	rb = -2
		ifTrue: [asm mov: X17 imm: 0]
		ifFalse: [asm asr: X17 with: rb imm: 1].
	asm cbz: X17 to: slow.
	asm sdiv: X9 with: X16 with: X17.
	asm msub: X11 with: X9 with: X17 sub: X16.
	asm cbz: X11 to: exact.
	asm eor: X10 with: X11 with: X17.
	asm tbz: X10 bit: 63 to: exact.
	k = 13
		ifTrue: [asm sub: X9 with: X9 imm: 1]
		ifFalse: [asm add: X11 with: X11 with: X17].
	asm bind: exact.
	k = 13
		ifTrue: [
			asm comment: 'the quotient must be a SmallInteger'.
			asm add: rr with: X9 with: X9.
			asm cmp: X9 with: rr shift: SHIFT_ASR amount: 1.
			asm b: slow if: COND_NE]
		ifFalse: [asm add: rr with: X11 with: X11].
	asm orr: rr with: rr imm: 1
!
emitShift: ra by: rb constant: c immediate: imm into: rr slow: slow
	"bitShift: by a constant inline (left shifts check that nothing is lost); by a variable: the slow path."
	imm ifFalse: [
		asm comment: 'bitShift: by a variable: the slow path'.
		^asm b: slow].
	c >= 0 ifTrue: [
		asm comment: 'bitShift: left (the shift must lose nothing)'.
		asm sub: X16 with: ra imm: 1.
		asm lsl: rr with: X16 imm: c.
		asm cmp: X16 with: rr shift: SHIFT_ASR amount: c.
		asm b: slow if: COND_NE.
		^asm orr: rr with: rr imm: 1].
	asm comment: 'bitShift: right'.
	asm asr: rr with: ra imm: c negated.
	asm orr: rr with: rr imm: 1
!
access: k pc: pc pushes: pushes
	"at: at:put: on Arrays inline, Strings, Symbols and ByteArrays out of line; anything else sends."
	<function>
	<var: #rb type: 'int32_t'>
	<var: #rc type: 'int32_t'>
	| n a ra rb rc rr s barrier |
	n := analysis specialArgc: k.
	a := ssTop - n - 1.
	barrier := n = 2 and: [self needsBarrier: a + 2].
	self ssFlushTo: a.
	ra := self ssMaterialize: a.
	rb := -1.
	rc := -1.
	n >= 1 ifTrue: [rb := self ssMaterialize: a + 1].
	n >= 2 ifTrue: [rc := self ssMaterialize: a + 2].
	rr := self allocReg.
	s := self slow: SL_SEND pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slA at: s put: ra asInt8.
	slB at: s put: rb asInt8.
	slC at: s put: rc asInt8.
	slR at: s put: rr asInt8.
	slInfo at: s put: ((self sendInfo: pc argc: n selector: k kind: 2 pushes: pushes) asInt64 bitOr: ((k >= 16 and: [k <= 18]) ifTrue: [SL_ACCESS] ifFalse: [0])).
	asm comment: 'the receiver must be an object'.
	asm tst: ra imm: 7.
	asm b: (slLabel at: s) if: COND_NE.
	asm ldr: X16 base: ra offset: 8.
	(k = 27 or: [k = 28]) ifTrue: [
		asm comment: (k = 27 ifTrue: ['x of a Point'] ifFalse: ['y of a Point']).
		asm ldr: X17 base: X22 offset: self pointClassOffset.
		asm cmp: X16 with: X17.
		asm b: (slLabel at: s) if: COND_NE.
		asm ldr: rr base: ra offset: (self fieldOffset: k - 27)]
		ifFalse: [
			asm comment: 'an Array (other formats out of line)'.
			asm ldr: X17 base: X22 offset: self arrayClassOffset.
			asm cmp: X16 with: X17.
			asm b: (slLabel at: s) if: COND_NE.
			asm ldr: X11 base: ra offset: 0.
			k = 18 ifTrue: [
				asm comment: 'size: its slot count'.
				asm ubfx: rr with: X11 lsb: 0 width: 32.
				asm add: rr with: rr with: rr.
				asm orr: rr with: rr imm: 1].
			k ~= 18 ifTrue: [
				asm comment: 'a SmallInteger index within its slots'.
				self ifBitClear: rb bit: 0 to: (slLabel at: s).
				asm asr: X16 with: rb imm: 1.
				asm sub: X16 with: X16 imm: 1.
				asm ubfx: X17 with: X11 lsb: 0 width: 32.
				asm cmp: X16 with: X17.
				asm b: (slLabel at: s) if: COND_HS.
				asm add: X17 with: ra imm: 16.
				k = 16
					ifTrue: [asm ldr: rr base: X17 index: X16 extend: EXT_LSL shift: 3]
					ifFalse: [
						asm comment: 'not immutable; store, answer the value'.
						self ifBitSet: X11 bit: 59 to: (slLabel at: s).
						asm str: rc base: X17 index: X16 extend: EXT_LSL shift: 3.
						barrier ifTrue: [self barrier: ra header: X11 value: rc].
						asm mov: rr with: rc]]].
	slCont at: s put: asm newLabel.
	asm bind: (slCont at: s).
	self noteContinuation: pc result: rr.
	self ssPop: n + 1.
	^self ssPushReg: rr
!
value: k pc: pc pushes: pushes
	"value value: value:value: of a closure with as many arguments: the block stub enters its code; anything else sends."
	<function>
	| n ri s info off |
	n := analysis specialArgc: k.
	ri := ssTop - n - 1.
	self prepareSend: ri.
	info := self sendInfo: pc argc: n selector: k kind: 2 pushes: pushes.
	s := self slow: SL_SEND pc: pc depth: ssTop.
	s < 0 ifTrue: [^false].
	slR at: s put: X0 asInt8.
	slInfo at: s put: info asInt64.
	asm comment: 'a BlockClosure with %d arguments (else send)' with: n.
	asm tst: X0 imm: 7.
	asm b: (slLabel at: s) if: COND_NE.
	asm ldr: X16 base: X0 offset: 8.
	asm ldr: X17 base: X22 offset: self blockClassOffset.
	asm cmp: X16 with: X17.
	asm b: (slLabel at: s) if: COND_NE.
	asm ldr: X16 base: X0 offset: (self fieldOffset: BC_NUMARGS).
	asm cmp: X16 imm: (self intOop: n).
	asm b: (slLabel at: s) if: COND_NE.
	off := 8 * (ri + 1).
	asm comment: 'x20 := the block''s fp; the block stub finds its code'.
	self addFp: off.
	asm bl: blockLabel.
	self noteRet: pc depth: (analysis depthAt: pc) info: info.
	self subFp: off.
	slCont at: s put: asm newLabel.
	asm bind: (slCont at: s).
	^self finishSend: n pc: pc
! !

!JitBaselineCompiler methodsFor: 'slow paths'!
slow: kind pc: pc depth: d
	"A slow path, emitted after the method's code; answer its index (-1 if there are too many)."
	<function>
	| s |
	slCount >= BL_MAX_SLOW ifTrue: [^-1].
	s := slCount.
	slCount := slCount + 1.
	slKind at: s put: kind asUInt8.
	slPc at: s put: pc.
	slDepth at: s put: d.
	slLabel at: s put: asm newLabel.
	slCont at: s put: -1.
	slTarget at: s put: -1.
	slA at: s put: -1.
	slB at: s put: -1.
	slC at: s put: -1.
	slR at: s put: -1.
	slX at: s put: 0.
	slY at: s put: 0.
	slInfo at: s put: 0.
	slSavedStart at: s put: savedCount.
	slSavedCount at: s put: 0.
	slLoop at: s put: (loopActive ifTrue: [loopId] ifFalse: [-1]) asInt16.
	^s
!
noteContinuation: pc result: r
	"The interpreter may return into this frame after the instruction at pc (its result in its slot): a stub loads it into r and continues the main line here."
	<function>
	| next s |
	next := (pc + (analysis lengthAt: pc)) asInt32.
	(next < analysis size and: [analysis isResume: next]) ifFalse: [^self].
	"unboxed values (on the stack, in temps' d registers) would not be what the interpreter left"
	self hasDoubles ifTrue: [^self].
	s := self slow: SL_RESUME pc: next depth: (analysis depthAt: next).
	s < 0 ifTrue: [^self].
	slR at: s put: r asInt8.
	slCont at: s put: asm newLabel.
	asm bind: (slCont at: s)
!
storeOperand: r const: v at: i
	"An operand of a slow path's send into its slot: register r, the constant v (r = -2), temp v (r = -4); r = -1: it is there; r = -3 (unboxed) is boxed by the caller."
	(r = -1 or: [r = -3]) ifTrue: [^self].
	r = -4 ifTrue: [
		asm ldr: X16 base: X20 offset: (self slot: v).
		^asm str: X16 base: X20 offset: (self slot: i)].
	r = -2
		ifTrue: [
			asm mov: X16 imm: v.
			asm str: X16 base: X20 offset: (self slot: i)]
		ifFalse: [asm str: r base: X20 offset: (self slot: i)]
!
boxOperand: r double: d at: i pc: pc depth: depth
	"An unboxed operand (r = -3, in d register d) of a slow path's send, boxed into its slot."
	r = -3 ifFalse: [^self].
	self emitBoxInSlowPath: d into: X17 pc: pc depth: depth.
	asm str: X17 base: X20 offset: (self slot: i)
!
boxSavedDoubles: i
	"Slow path i's unboxed entries below its operands into their slots (around its send)."
	| k slot d |
	k := slSavedStart at: i.
	1 to: (slSavedCount at: i) do: [:n |
		slot := (saved at: k) asInt32.
		d := (saved at: k + 1) asInt32.
		slot >= 0 ifTrue: [
			self emitBoxInSlowPath: d into: X17 pc: (slPc at: i) depth: (slDepth at: i).
			asm str: X17 base: X20 offset: (self slot: slot)].
		k := k + 2]
!
emitSlowPaths
	<function>
	<var: #i type: 'int32_t'>
	| kind i |
	i := 0.
	"slow paths may add slow paths (barriers, continuations): slCount grows"
	[i < slCount] whileTrue: [
		kind := slKind at: i.
		asm bind: (slLabel at: i).
		kind = SL_INTERRUPT ifTrue: [
			asm comment: 'interrupt: the runtime handles it'.
			self emitRuntimeCall: interruptLabel pc: (slPc at: i) depth: (slDepth at: i).
			self emitLoadLoopTemps: (slLoop at: i).
			asm b: (slCont at: i)].
		kind = SL_START ifTrue: [self emitStart: i].
		kind = SL_TIERUP ifTrue: [self emitTierUpSlow: i].
		kind = SL_SEND ifTrue: [self emitSlowSend: i].
		kind = SL_MUSTBEBOOLEAN ifTrue: [
			asm comment: 'leave to the interpreter at this instruction (mustBeBoolean, attemptToAssign:withIndex:, a married Context''s field)'.
			asm str: (slA at: i) base: X20 offset: (self slot: (slDepth at: i) - 1).
			self emitSync: (slPc at: i) depth: (slDepth at: i).
			asm b: exitSyncLabel].
		kind = SL_RETURN ifTrue: [
			asm comment: 'married frame (or frame 0): the runtime widows it or leaves'.
			(slInfo at: i) = 0 ifTrue: [asm str: X0 base: X20 offset: (self slot: (slDepth at: i) - 1)].
			self emitRuntimeCall: returnSlowLabel pc: (slPc at: i) depth: (slDepth at: i).
			(slInfo at: i) = 0
				ifTrue: [asm ldr: X0 base: X20 offset: (self slot: (slDepth at: i) - 1)]
				ifFalse: [asm ldr: X0 base: X20 offset: -8].
			asm b: (slCont at: i)].
		kind = SL_BARRIER ifTrue: [
			asm comment: 'remember the old object (the stub preserves the registers)'.
			asm mov: X16 with: (slA at: i).
			asm mov: X17 with: (slB at: i).
			asm str: X30 base: SP preIndex: -16.
			asm bl: rememberLabel.
			asm ldr: X30 base: SP postIndex: 16.
			asm b: (slCont at: i)].
		kind = SL_CLASS ifTrue: [
			asm comment: 'the class of an immediate: by its tag'.
			asm and: X16 with: (slA at: i) imm: 7.
			asm add: X17 with: X22 imm: self tagClassesOffset.
			asm ldr: (slR at: i) base: X17 index: X16 extend: EXT_LSL shift: 3.
			asm b: (slCont at: i)].
		kind = SL_ENTRY_IMM ifTrue: [
			asm comment: 'an immediate receiver: its class by its tag'.
			asm and: X16 with: X0 imm: 7.
			asm add: X17 with: X22 imm: self tagClassesOffset.
			asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
			asm cmp: X16 with: X9.
			asm b: (slCont at: i) if: COND_EQ.
			asm bind: (slTarget at: i).
			asm comment: 'the miss stub (relinks the inline cache)'.
			asm b: missLabel].
		kind = SL_ENTRY_SLOW ifTrue: [
			asm comment: 'stack full or interrupt pending: the runtime (x11 the callee: our header, 1 a block), then retry'.
			(slPc at: i) = 0
				ifTrue: [asm adr: X11 label: headerLabel]
				ifFalse: [asm mov: X11 imm: 1].
			asm adr: X10 label: (slCont at: i).
			asm b: entrySlowLabel].
		kind = SL_BOX ifTrue: [self emitBoxSlow: i].
		kind = SL_RESUME ifTrue: [
			runtime noteResume: (slPc at: i) at: asm pc - codeStart.
			self emitLoadLoopTemps: (slLoop at: i).
			(slR at: i) >= 0 ifTrue: [
				asm comment: 'resumption after an interpreted send: its result from its slot'.
				asm ldr: (slR at: i) base: X20 offset: (self slot: (slDepth at: i) - 1)].
			asm b: (slCont at: i)].
		i := i + 1].
	^asm failed not
!
emitBoxSlow: i
	"Zero, or an exponent a SmallFloat64 does not have: a BoxedFloat64 from the runtime, with the stack's registers stored around the call."
	| d r big k slot reg |
	d := self dreg: (slA at: i).
	r := slR at: i.
	big := asm newLabel.
	asm comment: 'box: zero keeps its sign'.
	asm fmov: X16 with: d.
	asm lsl: X17 with: X16 imm: 1.
	asm cbnz: X17 to: big.
	asm lsr: X17 with: X16 imm: 63.
	asm lsl: r with: X17 imm: 3.
	asm orr: r with: r imm: 4.
	asm b: (slCont at: i).
	asm bind: big.
	asm comment: 'a BoxedFloat64: the runtime boxes it (the stack''s registers into their slots around the call)'.
	k := slSavedStart at: i.
	1 to: (slSavedCount at: i) do: [:n |
		slot := (saved at: k) asInt32.
		reg := (saved at: k + 1) asInt32.
		(reg >> 8) = 0 ifTrue: [asm str: (reg bitAnd: 255) base: X20 offset: (self slot: slot)].
		k := k + 2].
	self emitSync: (slPc at: i) depth: (slDepth at: i).
	asm mov: X0 with: X19.
	asm fmov: X1 with: d.
	asm bl: boxLabel.
	r ~= X0 ifTrue: [asm mov: r with: X0].
	self emitReloadPinned.
	k := slSavedStart at: i.
	1 to: (slSavedCount at: i) do: [:n |
		slot := (saved at: k) asInt32.
		reg := (saved at: k + 1) asInt32.
		asm ldr: (reg bitAnd: 255) base: X20 offset: (self slot: slot).
		k := k + 2].
	self emitLoadLoopTemps: (slLoop at: i).
	asm ldr: X21 base: X20 offset: -8.
	asm b: (slCont at: i)
!
emitStart: i
	"Resumption at the start of a method or block (the interpreter or optimized code pushed the frame; the latter calls the prologue before it): an interrupt check, then the body."
	| intr |
	(counterAddr ~= 0 and: [runtime tiering]) ifTrue: [self emitPrologue].
	runtime noteResume: (slPc at: i) at: asm pc - codeStart.
	counterAddr ~= 0 ifTrue: [
		asm comment: 'pc and sp 0: the frame is lazy from here (a pushed frame''s pc may be stale)'.
		asm str: XZR base: X19 offset: self pcOffset].
	intr := asm newLabel.
	asm comment: 'resumption at the start: interrupt check'.
	self emitBaselinePollTo: intr.
	(self emitTierUp: (slPc at: i) depth: (slDepth at: i) loop: 0) ifFalse: [^asm fail: ASM_ERR_LABEL].
	asm b: (slCont at: i).
	asm bind: intr.
	self emitRuntimeCall: (asm labelAt: stubs entryInterruptStub) pc: (slPc at: i) depth: (slDepth at: i).
	asm ldr: X21 base: X20 offset: -8.
	asm b: (slCont at: i)
!
emitTierUp: pc depth: d loop: loop
	"--jit opt: count down toward optimization (everything is in its slot); at zero the runtime may continue the frame in optimized code."
	| s after |
	counterAddr = 0 ifTrue: [^true].
	s := self slow: SL_TIERUP pc: pc depth: d.
	s < 0 ifTrue: [^false].
	after := asm newLabel.
	slCont at: s put: after.
	slInfo at: s put: loop.
	loop = 0 ifTrue: [slLoop at: s put: -1].
	self emitCountDown: counterAddr to: (slLabel at: s).
	asm bind: after.
	^true
!
emitTierUpSlow: i
	| l |
	asm comment: 'tier up: the runtime answers 0 (go on), 1 (leave) or where the frame continues'.
	self emitSync: (slPc at: i) depth: (slDepth at: i).
	asm mov: X0 with: X19.
	asm mov: X1 imm: (slInfo at: i).
	asm bl: tierUpLabel.
	l := asm newLabel.
	asm cbz: X0 to: l.
	asm cmp: X0 imm: 1.
	asm b: exitPlainLabel if: COND_EQ.
	asm br: X0.
	asm bind: l.
	self emitReloadPinned.
	self emitLoadLoopTemps: (slLoop at: i).
	asm ldr: X21 base: X20 offset: -8.
	asm b: (slCont at: i)
!
emitSlowSend: i
	"Floats or other formats inline if flagged, then the send through its own inline cache; the result into the main line's register (or, fused, the branch)."
	<function>
	| info n ri send j dj ifTrue r leave |
	info := slInfo at: i.
	n := (info bitAnd: 255) asInt32.
	ri := (slDepth at: i) - n - 1.
	send := asm newLabel.
	leave := asm newLabel.
	(info bitAnd: SL_FLOAT) ~= 0 ifTrue: [self emitFloatPath: i send: send].
	(info bitAnd: SL_ACCESS) ~= 0 ifTrue: [self emitAccessPath: i send: send].
	asm bind: send.
	asm comment: 'send: the operands into their slots, the receiver into x0'.
	self storeOperand: (slA at: i) const: (slX at: i) at: ri.
	self storeOperand: (slB at: i) const: (slY at: i) at: ri + 1.
	self storeOperand: (slC at: i) const: 0 at: ri + 2.
	self boxOperand: (slA at: i) double: (slDA at: i) at: ri pc: (slPc at: i) depth: (slDepth at: i).
	self boxOperand: (slB at: i) double: (slDB at: i) at: ri + 1 pc: (slPc at: i) depth: (slDepth at: i).
	self boxSavedDoubles: i.
	asm ldr: X0 base: X20 offset: (self slot: ri).
	self emitSiteCall: (slPc at: i) info: (info bitAnd: 16rFFFFFFFF) asUInt32 receiver: ri.
	asm comment: 'x21 again (the callee changed it)'.
	asm ldr: X21 base: X20 offset: -8.
	self emitLoadLoopTemps: (slLoop at: i).
	(info bitAnd: SL_DOUBLES) ~= 0 ifTrue: [^self emitUnboxResult: i].
	self unboxSavedDoubles: i leave: leave.
	(info bitAnd: SL_FUSED) ~= 0 ifTrue: [
		j := (slX at: i) asInt32.
		dj := analysis depthAt: j.
		ifTrue := (analysis byteAt: j) = 16r91.
		asm comment: 'the Boolean decides the jump'.
		asm cmp: X0 with: (ifTrue ifTrue: [X24] ifFalse: [X25]).
		asm b: (slTarget at: i) if: COND_EQ.
		asm cmp: X0 with: (ifTrue ifTrue: [X25] ifFalse: [X24]).
		asm b: (slCont at: i) if: COND_EQ.
		asm comment: 'neither true nor false: the interpreter sends mustBeBoolean'.
		asm str: X0 base: X20 offset: (self slot: dj - 1).
		self emitSync: j depth: dj.
		asm b: exitSyncLabel.
		(slSavedCount at: i) > 0 ifTrue: [self emitLeaveAfter: i at: leave].
		^self].
	r := slR at: i.
	r ~= X0 ifTrue: [asm mov: r with: X0].
	asm b: (slCont at: i).
	(slSavedCount at: i) > 0 ifTrue: [self emitLeaveAfter: i at: leave]
!
emitLeaveAfter: i at: leave
	"Leave after slow path i's instruction: its result (x0) in its slot."
	| next dn |
	next := ((slPc at: i) + (analysis lengthAt: (slPc at: i))) asInt32.
	dn := (slDepth at: i) - ((slInfo at: i) bitAnd: 255) asInt32.
	asm bind: leave.
	asm comment: 'a temp is not a Float any more: the interpreter continues'.
	asm str: X0 base: X20 offset: (self slot: dn - 1).
	self emitSync: next depth: dn.
	asm b: exitSyncLabel
!
emitUnboxResult: i
	"A Float-first operation's send answered x0: unboxed into its d register; not a Float: leave after the instruction (its result in its slot)."
	| leave next n dn |
	leave := asm newLabel.
	n := ((slInfo at: i) bitAnd: 255) asInt32.
	next := ((slPc at: i) + (analysis lengthAt: (slPc at: i))) asInt32.
	dn := (slDepth at: i) - n.
	asm str: X0 base: X20 offset: (self slot: dn - 1).
	self unboxSavedDoubles: i leave: leave.
	asm ldr: X0 base: X20 offset: (self slot: dn - 1).
	asm comment: 'the result unboxed (not a Float: the interpreter continues)'.
	self emitToDouble: X0 into: (self dreg: (slR at: i)) fail: leave.
	asm b: (slCont at: i).
	asm bind: leave.
	self emitSync: next depth: dn.
	asm b: exitSyncLabel
!
unboxSavedDoubles: i leave: leave
	"After slow path i's send: the unboxed stack entries and temps again from their slots (a block may have stored into a temp: not a Float, leave)."
	| k slot d |
	k := slSavedStart at: i.
	1 to: (slSavedCount at: i) do: [:n |
		slot := (saved at: k) asInt32.
		d := (saved at: k + 1) asInt32.
		slot >= 0
			ifTrue: [
				asm comment: 'unbox stack slot %d again' with: slot.
				asm ldr: X10 base: X20 offset: (self slot: slot)]
			ifFalse: [
				asm comment: 'unbox temp %d again' with: -1 - slot.
				asm ldr: X10 base: X20 offset: (self slot: -1 - slot)].
		self emitToDouble: X10 into: (self dreg: d) fail: leave.
		k := k + 2]
!
emitToDouble: r into: d fail: fail
	"d := the SmallInteger, SmallFloat64 or BoxedFloat64 in r; else branch to fail. Uses x16, x17."
	| int obj done |
	int := asm newLabel.
	obj := asm newLabel.
	done := asm newLabel.
	self emitSmallFloat: r into: d int: int obj: obj.
	asm b: done.
	self emitOtherFloat: r into: d int: int obj: obj fail: fail done: done.
	asm bind: done
!
emitSmallFloat: r into: d int: int obj: obj
	"d := the SmallFloat64 in r; a SmallInteger branches to int, anything else to obj (x16 its tag). Uses x16, x17."
	asm tbnz: r bit: 0 to: int.
	asm and: X16 with: r imm: 7.
	asm cmp: X16 imm: 4.
	asm b: obj if: COND_NE.
	asm comment: 'a SmallFloat64: rotate back'.
	asm lsr: X16 with: r imm: 3.
	asm mov: X17 imm: 16r7000000000000000.
	asm add: X17 with: X16 with: X17.
	asm cmp: X16 imm: 1.
	asm csel: X16 with: X16 with: X17 cond: COND_LS.
	asm ror: X16 with: X16 imm: 1.
	asm fmov: d with: X16
!
emitOtherFloat: r into: d int: int obj: obj fail: fail done: done
	"emitSmallFloat:into:int:obj:'s other cases: a BoxedFloat64 at obj (then to done; anything else to fail), a SmallInteger at int (falling through)."
	asm bind: obj.
	asm cbnz: X16 to: fail.
	asm comment: 'a BoxedFloat64: its word'.
	asm ldr: X16 base: r offset: 8.
	asm ldr: X17 base: X22 offset: self boxedFloatClassOffset.
	asm cmp: X16 with: X17.
	asm b: fail if: COND_NE.
	asm ldr: d base: r offset: 16.
	asm b: done.
	asm bind: int.
	asm comment: 'a SmallInteger: convert'.
	asm asr: X16 with: r imm: 1.
	asm scvtf: d with: X16
!
emitBox: d into: r cont: cont fail: fail
	"r := the Float in d if it is a SmallFloat64, then branch to cont; else branch to fail."
	| zero |
	zero := asm newLabel.
	asm comment: 'the result: a SmallFloat64 if its exponent fits'.
	asm fmov: X16 with: d.
	asm lsl: X17 with: X16 imm: 1.
	asm cbz: X17 to: zero.
	asm ubfx: X9 with: X16 lsb: 52 width: 11.
	asm sub: X9 with: X9 imm: 897.
	asm cmp: X9 imm: 253.
	asm b: fail if: COND_HI.
	asm ror: X17 with: X16 imm: 63.
	asm mov: X9 imm: 16r7000000000000000.
	asm sub: X17 with: X17 with: X9.
	asm lsl: r with: X17 imm: 3.
	asm orr: r with: r imm: 4.
	asm b: cont.
	asm bind: zero.
	asm lsr: X17 with: X16 imm: 63.
	asm lsl: r with: X17 imm: 3.
	asm orr: r with: r imm: 4.
	asm b: cont
!
emitFloatPath: i send: send
	"Floats (SmallFloat64, BoxedFloat64, at most one SmallInteger) inline, SmallFloat64s straight through (the other cases after); two SmallIntegers (an overflow) and anything else send."
	| ra rb ia oa da ib ob db |
	ra := slA at: i.
	rb := slB at: i.
	ia := asm newLabel.
	oa := asm newLabel.
	da := asm newLabel.
	ib := asm newLabel.
	ob := asm newLabel.
	db := asm newLabel.
	asm comment: 'Floats inline: not two SmallIntegers'.
	rb = -2
		ifTrue: [asm tbnz: ra bit: 0 to: send]
		ifFalse: [
			asm and: X16 with: ra with: rb.
			asm tbnz: X16 bit: 0 to: send].
	self emitSmallFloat: ra into: D0 int: ia obj: oa.
	asm bind: da.
	rb = -2
		ifTrue: [
			asm mov: X16 imm: (slY at: i) >> 1.
			asm scvtf: D1 with: X16]
		ifFalse: [
			rb = ra
				ifTrue: [asm fmov: D1 with: D0]
				ifFalse: [
					self emitSmallFloat: rb into: D1 int: ib obj: ob.
					asm bind: db]].
	self emitFloatResult: i send: send.
	self emitOtherFloat: ra into: D0 int: ia obj: oa fail: send done: da.
	asm b: da.
	(rb = -2 or: [rb = ra]) ifTrue: [^self].
	self emitOtherFloat: rb into: D1 int: ib obj: ob fail: send done: db.
	asm b: db
!
emitFloatResult: i send: send
	"emitFloatPath:send:'s operation on d0 and d1, its result to the main line."
	| k cond |
	k := ((slInfo at: i) >> 16) bitAnd: 255.
	counterAddr ~= 0 ifTrue: [self emitFloatFeedback: (slPc at: i)].
	(k >= 2 and: [k <= 7]) ifTrue: [
		asm fcmp: D0 with: D1.
		cond := self floatConditionOf: k.
		((slInfo at: i) bitAnd: SL_FUSED) ~= 0 ifTrue: [
			asm b: (slTarget at: i) if: ((analysis byteAt: (slX at: i) asInt32) = 16r91 ifTrue: [cond] ifFalse: [cond bitXor: 1]).
			^asm b: (slCont at: i)].
		asm csel: (slR at: i) with: X24 with: X25 cond: cond.
		^asm b: (slCont at: i)].
	k = 0 ifTrue: [asm fadd: D0 with: D0 with: D1].
	k = 1 ifTrue: [asm fsub: D0 with: D0 with: D1].
	k = 8 ifTrue: [asm fmul: D0 with: D0 with: D1].
	k = 9 ifTrue: [
		asm fcmpZero: D1.
		asm b: send if: COND_EQ.
		asm fdiv: D0 with: D0 with: D1].
	(k = 0 or: [k = 1 or: [k = 8 or: [k = 9]]]) ifFalse: [^asm b: send].
	self emitBox: D0 into: (slR at: i) cont: (slCont at: i) fail: send
!
emitFloatFeedback: pc
	"--jit opt: type feedback, a Float at pc (the byte starts clear: another method's; a copy for a disassembly leaves it)."
	| a |
	a := runtime floatBitAddressFor: curMethod pc: pc.
	runtime copying ifFalse: [self uint8At: a put: 0].
	asm comment: 'type feedback: a Float here'.
	asm mov: X17 imm: 1.
	asm adrp: X16 label: (asm labelAt: a).
	asm strb: W17 base: X16 offset: (a bitAnd: 16rFFF) asInt64
!
emitAccessPath: i send: send
	"at: at:put: size of ByteStrings (and Symbols, read only) and ByteArrays; anything else sends."
	| k ra str |
	k := ((slInfo at: i) >> 16) bitAnd: 255.
	ra := slA at: i.
	str := asm newLabel.
	asm comment: 'Strings and ByteArrays'.
	asm tst: ra imm: 7.
	asm b: send if: COND_NE.
	asm ldr: X16 base: ra offset: 8.
	asm ldr: X17 base: X22 offset: self byteStringClassOffset.
	asm cmp: X16 with: X17.
	asm b: str if: COND_EQ.
	k ~= 17 ifTrue: [
		asm ldr: X17 base: X22 offset: self byteSymbolClassOffset.
		asm cmp: X16 with: X17.
		asm b: str if: COND_EQ].
	asm ldr: X17 base: X22 offset: self byteArrayClassOffset.
	asm cmp: X16 with: X17.
	asm b: send if: COND_NE.
	self emitBytes: i string: false send: send.
	asm bind: str.
	self emitBytes: i string: true send: send
!
emitBytes: i string: isString send: send
	"The byte object in slA: its size, a byte (a Character or a SmallInteger), or a byte stored."
	| k ra rb rc rr |
	k := ((slInfo at: i) >> 16) bitAnd: 255.
	ra := slA at: i.
	rb := slB at: i.
	rc := slC at: i.
	rr := slR at: i.
	asm comment: 'the byte size: slots * 8 - (format - 16)'.
	asm ldr: X11 base: ra offset: 0.
	asm ubfx: X17 with: X11 lsb: H_FMT_SHIFT width: 5.
	asm ubfx: X16 with: X11 lsb: 0 width: 32.
	asm lsl: X16 with: X16 imm: 3.
	asm sub: X16 with: X16 with: X17.
	asm add: X16 with: X16 imm: 16.
	k = 18 ifTrue: [
		asm add: rr with: X16 with: X16.
		asm orr: rr with: rr imm: 1.
		^asm b: (slCont at: i)].
	asm comment: 'a SmallInteger index within the bytes'.
	asm tbz: rb bit: 0 to: send.
	asm asr: X17 with: rb imm: 1.
	asm sub: X17 with: X17 imm: 1.
	asm cmp: X17 with: X16.
	asm b: send if: COND_HS.
	asm add: X16 with: ra imm: 16.
	k = 16 ifTrue: [
		asm ldrb: W16 base: X16 index: X17.
		isString
			ifTrue: [
				asm comment: 'a Character'.
				asm lsl: rr with: X16 imm: 3.
				asm orr: rr with: rr imm: 2]
			ifFalse: [
				asm lsl: rr with: X16 imm: 1.
				asm orr: rr with: rr imm: 1].
		^asm b: (slCont at: i)].
	asm comment: 'not immutable, a byte value'.
	asm tbnz: X11 bit: 59 to: send.
	isString
		ifTrue: [
			asm and: X9 with: rc imm: 7.
			asm cmp: X9 imm: 2.
			asm b: send if: COND_NE.
			asm lsr: X9 with: rc imm: 3]
		ifFalse: [
			asm tbz: rc bit: 0 to: send.
			asm asr: X9 with: rc imm: 1].
	asm cmp: X9 imm: 255.
	asm b: send if: COND_HI.
	asm strb: W9 base: X16 index: X17.
	asm mov: rr with: rc.
	asm b: (slCont at: i)
! !

!JitBaselineCompiler methodsFor: 'tables'!
tablesBytes
	"What writeTables:at: appends to the header: the send sites, the return map, the block entries."
	^(32 * siteCount) + (12 * retCount) + (8 * blockCount) + 8
!
oopSlotCount
	"The words of the pool the collector must update."
	| n |
	n := siteCount.
	0 to: 255 do: [:i | (poolLabels at: i) >= 0 ifTrue: [n := n + 1]].
	^n
!
writeTables: h at: p
	"The code is final: entries, send sites, return map and block entries into h's tables from p; the pool's literals registered with the collector. Answer the end."
	<function>
	| q site a |
	h entry: codeStart.
	h uentry: codeStart + uentryOffset asUInt64.
	q := (p + 7) bitClear: 7.
	h sites: (self cCoerce: q to: 'BaselineSite *').
	h siteCount: siteCount asUInt32.
	0 to: siteCount - 1 do: [:i |
		site := h sites + i.
		site bl: (siteBl at: i).
		site lit: ((asm addressOf: (siteLit at: i)) - codeStart) asUInt32.
		site info: (siteInfo at: i).
		site pc: (sitePc at: i).
		site depth: (siteDepth at: i).
		site target: 0.
		site pic: 0.
		runtime c4Baseline ifFalse: [brt registerSlot: (asm addressOf: (siteLit at: i))]].
	q := q + (32 * siteCount).
	h rets: (self cCoerce: q to: 'uint32_t *').
	h retCount: retCount asUInt32.
	0 to: retCount - 1 do: [:i |
		h rets at: 3 * i put: (retOff at: i).
		h rets at: 3 * i + 1 put: ((retPc at: i) asUInt64 bitOr: (retDepth at: i) asUInt64 << 16) asUInt32.
		h rets at: 3 * i + 2 put: (retInfo at: i)].
	q := q + (12 * retCount).
	h blocks: (self cCoerce: q to: 'uint32_t *').
	h blockCount: blockCount asUInt32.
	0 to: blockCount - 1 do: [:i |
		h blocks at: 2 * i put: (blockPcs at: i) asUInt32.
		h blocks at: 2 * i + 1 put: ((asm addressOf: (blockLabels at: i)) - codeStart) asUInt32].
	q := q + (8 * blockCount).
	0 to: 255 do: [:i | (poolLabels at: i) >= 0 ifTrue: [
		a := asm addressOf: (poolLabels at: i).
		brt registerSlot: a]].
	^q
! !

!JitBaselineCompiler methodsFor: 'inline caches'!
picCodeOffset
	"The code of a polymorphic inline cache follows its BaselinePic header."
	^self sizeof: 'BaselinePic'
!
picBytes
	"Its header and code (on x86: 14 bytes a case, 6 cases, the rest, and the assembler's 8 bytes of slack)."
	^(self sizeof: 'BaselinePic') + (asm isX64 ifTrue: [192] ifFalse: [128])
!
picBranchOffset: i
	"The b of case i (patched to its target's unchecked entry); on x86 its jmp's displacement."
	^asm isX64
		ifTrue: [self picCodeOffset + BL_PIC_HEAD_X64 + (BL_PIC_CASE_X64 * i) + BL_PIC_JMP_X64]
		ifFalse: [self picCodeOffset + 12 + (16 * i) + 12]
!
emitPicAt: pic
	"The code of the polymorphic inline cache whose header is at pic: up to brt picCases classes compared, each branching to its target (the miss stub until set); no match: the miss stub. The caller enabled writing."
	<function>
	| code imm cmp next p miss |
	asm isX64 ifTrue: [^self emitPicX64At: pic].
	code := pic + self picCodeOffset.
	asm beginAt: code limit: pic + self picBytes.
	asm recordNotes: false.
	p := self cCoerce: pic to: 'BaselinePic *'.
	miss := asm labelAt: stubs blMissStub.
	imm := asm newLabel.
	cmp := asm newLabel.
	asm and: X16 with: X0 imm: 7.
	asm cbnz: X16 to: imm.
	asm ldr: X16 base: X0 offset: 8.
	asm bind: cmp.
	0 to: brt picCases - 1 do: [:i |
		next := asm newLabel.
		asm ldr: X17 label: (asm labelAt: (self cCoerce: (p fieldAddress: #classes) to: 'uint64_t') + (8 * i)).
		asm cmp: X16 with: X17.
		asm b: next if: COND_NE.
		asm b: miss.
		asm bind: next].
	asm b: miss.
	asm bind: imm.
	asm add: X17 with: X22 imm: self tagClassesOffset.
	asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
	asm b: cmp.
	^asm finish = ASM_OK
!
emitPicX64At: pic
	"x86: as emitPicAt:, each case cmp r10, [classes + 8i] (rip-relative), jne over, jmp to its target: fixed lengths, so that picBranchOffset: finds the jmps."
	<arch: #x86_64>
	| code imm cmp p miss head |
	code := pic + self picCodeOffset.
	asm beginAt: code limit: pic + self picBytes.
	asm recordNotes: false.
	p := self cCoerce: pic to: 'BaselinePic *'.
	miss := asm labelAt: stubs blMissStub.
	imm := asm newLabel.
	cmp := asm newLabel.
	asm tst: X0 imm: 7.
	asm b: imm if: COND_NE.
	asm ldr: X16 base: X0 offset: 8.
	asm bind: cmp.
	head := asm pc - code.
	0 to: brt picCases - 1 do: [:i |
		asm picCaseX64: X16 classAt: (self cCoerce: (p fieldAddress: #classes) to: 'uint64_t') + (8 * i) target: miss].
	asm b: miss.
	asm bind: imm.
	asm and: X16 with: X0 imm: 7.
	asm add: X17 with: X22 imm: self tagClassesOffset.
	asm ldr: X16 base: X17 index: X16 extend: EXT_LSL shift: 3.
	asm b: cmp.
	^asm finish = ASM_OK and: [head = BL_PIC_HEAD_X64]
!
patchBranchAt: site to: target
	"A b or bl at site now goes to target (the caller enabled writing)."
	asm patchBranchAt: site to: target
!
branchTargetAt: site
	^asm branchTargetAt: site
! !
