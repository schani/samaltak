OptModule subclass: #OptCodegen
	instanceVariableNames: 'cgHeldSlot cgHeldReg cgHeldCount cgScanPc cgBinds ir passes regalloc cgCodeStart cgBcSize cgValidSlots cgEntryPc cgSlotTop cgRawBase cgMaxOut cgNeed cgExitPlainLabel cgExitSyncLabel cgDeoptLabel cgReturnLabel cgHeaderLabel cgChecksLabel cgBodyLabel cgInterruptLabel cgBarrierLabel cgDeoptReturnLabel cgStackFullLabel cgOuts cgOutCount cgPoolOops cgPoolLabels cgPoolCount cgMetaWords cgMetaCount cgSpOffsets cgSpCount cgMoveSrc cgMoveDst cgMoveLoc cgMoveCount cgRootAct cgLastPc cgLastAct builder cgDeps cgDepCount cgSunk cgSunkCount cgChainActs cgChainCount cgDoubles cgSiteBl cgSiteLit cgSiteInfo cgSiteIndex cgSiteSel cgSiteCount cgRetOff cgRetIndex cgRetArgc cgRetCount cgOrder cgPlaced'
	classVariableNames: 'CG_MAX_META CG_MAX_MOVES CG_MAX_OUT CG_MAX_POOL CG_MAX_RETS CG_MAX_HELD CG_MAX_SITES CG_MAX_SP OUT_ARRAY OUT_BARRIER OUT_BOTTOM OUT_DEOPT OUT_FOLLOW OUT_INTERRUPT OUT_LAZY OUT_NOTMADE OUT_RESUME OUT_SENT OUT_SITE OUT_STACK OUT_WIDOW'
	package: 'VM-Jit'!

OptCodegen comment: 'Emits arm64 code for the allocated IR (OptRegalloc) in block order, then the out-of-line paths (guard failures, interrupt checks, brace Arrays the runtime makes, store barriers, deoptimization after a call, resumption after a call, the stack check), then the oop pool the code loads constants from (pc-relative; GC roots) and the inline caches'' literals. Records for every safepoint and guard the deoptimization metadata (OptRuntime decodes it): kind, continuation, the send, and for each activation its method, closure, receiver, pc and where each slot''s value is (LOC_*).

Frame layout: slots 0..numArgs-1 the arguments, then home slots (OptRegalloc), then from rawBase raw ones (doubles'' IEEE bits; the collector skips them), slotTop of them; a send''s receiver and arguments go at slotTop..., the callee''s frame starts after them. Calls are baseline code''s (docs/jit.md, Calls between the tiers): the receiver in x0, x20 the callee''s fp, bl to a known method''s unchecked entry, to the block stub, or to an inline cache''s target (JitBaselineRuntime links it); the result comes back in x0, and in slot slotTop if the interpreter returns into the frame (a resumption stub loads it). A frame suspended in a call is lazy as baseline code''s: the return map (return offset, safepoint, argument count) gives its pc (bcSize + the safepoint''s index) and sp. Method and block units start with the entry baseline-style calls take (emitBaselineEntry: the frame built as baseline code builds it), then the prologue for callers that pushed the frame; x23-x25 stay baseline code''s nil, true and false, and are where the code takes them from.

What registers hold: the code generator knows which registers hold the values of which slots (cgHeldSlot and cgHeldReg: pairs of a slot''s offset and a register), from the code it emitted since the last label control may come to from elsewhere (catchUp decodes it): loads and stores of slots make their registers hold them, anything else that writes a register makes it hold nothing, calls and jumps everything. A slot a register holds is not loaded again (from another register: moved), nor stored again. At a safepoint of its own (interrupt checks, deoptimization) the code stores the frame''s pc and sp, so GCs see every value saved there; the bytecode map has the continuation of each call under that pc.'!

!OptCodegen class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (passes OptPasses) (regalloc OptRegalloc)
		(cgCodeStart uint64_t) (cgBcSize int32_t) (cgValidSlots int32_t) (cgEntryPc int32_t) (cgSlotTop int32_t) (cgRawBase int32_t) (cgMaxOut int32_t) (cgNeed int32_t)
		(cgExitPlainLabel int32_t) (cgExitSyncLabel int32_t) (cgDeoptLabel int32_t) (cgReturnLabel int32_t) (cgHeaderLabel int32_t) (cgChecksLabel int32_t) (cgBodyLabel int32_t) (cgInterruptLabel int32_t)
		(cgBarrierLabel int32_t) (cgDeoptReturnLabel int32_t) (cgStackFullLabel int32_t)
		(cgOuts 'OptOut[CG_MAX_OUT]') (cgOutCount int32_t)
		(cgPoolOops 'oop[CG_MAX_POOL]') (cgPoolLabels 'int32_t[CG_MAX_POOL]') (cgPoolCount int32_t)
		(cgMetaWords 'int32_t[CG_MAX_META]') (cgMetaCount int32_t) (cgSpOffsets 'int32_t[CG_MAX_SP]') (cgSpCount int32_t)
		(cgMoveSrc 'int32_t[CG_MAX_MOVES]') (cgMoveDst 'int32_t[CG_MAX_MOVES]') (cgMoveLoc 'int32_t[CG_MAX_MOVES]') (cgMoveCount int32_t) (cgRootAct int32_t) (cgLastPc int32_t) (cgLastAct int32_t) (cgHeldSlot 'int32_t[CG_MAX_HELD]') (cgHeldReg 'int32_t[CG_MAX_HELD]') (cgHeldCount int32_t) (cgScanPc uint64_t) (cgBinds int32_t)
		(builder OptBuilder) (cgDeps 'int32_t[256]') (cgDepCount int32_t)
		(cgSunk 'int32_t[64]') (cgSunkCount int32_t) (cgDoubles bool) (cgChainActs 'int32_t[512]') (cgChainCount int32_t)
		(cgSiteBl 'uint32_t[CG_MAX_SITES]') (cgSiteLit 'int32_t[CG_MAX_SITES]') (cgSiteInfo 'uint32_t[CG_MAX_SITES]') (cgSiteIndex 'int32_t[CG_MAX_SITES]') (cgSiteSel 'int32_t[CG_MAX_SITES]') (cgSiteCount int32_t)
		(cgRetOff 'uint32_t[CG_MAX_RETS]') (cgRetIndex 'int32_t[CG_MAX_RETS]') (cgRetArgc 'int32_t[CG_MAX_RETS]') (cgRetCount int32_t)
		(cgOrder 'int32_t[OPT_MAX_BLOCKS]') (cgPlaced 'uint8_t[OPT_MAX_BLOCKS]'))
!
initialize
	CG_MAX_OUT := 4096.
	CG_MAX_POOL := 1024.
	CG_MAX_META := 262144.
	CG_MAX_SP := 4096.
	CG_MAX_MOVES := 256.
	CG_MAX_SITES := 4096.
	CG_MAX_RETS := 8192.
	CG_MAX_HELD := 32.
	OUT_DEOPT := 1.
	OUT_INTERRUPT := 2.
	OUT_BARRIER := 3.
	OUT_LAZY := 4.
	OUT_STACK := 5.
	OUT_BOTTOM := 6.
	OUT_SITE := 7.
	OUT_WIDOW := 8.
	OUT_RESUME := 9.
	OUT_SENT := 10.
	OUT_NOTMADE := 11.
	OUT_ARRAY := 12.
	OUT_FOLLOW := 13
! !

!OptCodegen methodsFor: 'accessing'!
slotTop
	^cgSlotTop
!
rawBase
	"The first raw slot (slotTop if none)."
	^cgRawBase
!
maxOut
	^cgMaxOut
!
poolCount
	^cgPoolCount
!
poolOffset
	"Code offset of the pool (8-byte entries)."
	cgPoolCount = 0 ifTrue: [^0 asInt64].
	^((asm addressOf: (cgPoolLabels at: 0)) - cgCodeStart) asInt64
!
spCount
	^cgSpCount
!
spOffsetAt: i
	^cgSpOffsets at: i
!
metaCount
	^cgMetaCount
!
metaAt: i
	^cgMetaWords at: i
!
siteCount
	^cgSiteCount
!
siteBlAt: i
	"Code offset of inline cache i's bl."
	^cgSiteBl at: i
!
siteLitAddressAt: i
	^asm addressOf: (cgSiteLit at: i)
!
siteInfoAt: i
	^cgSiteInfo at: i
!
siteIndexAt: i
	"Its safepoint."
	^cgSiteIndex at: i
!
siteSelectorAt: i
	"Its selector's pool index."
	^cgSiteSel at: i
!
retCount
	^cgRetCount
!
retOffAt: i
	^cgRetOff at: i
!
retIndexAt: i
	^cgRetIndex at: i
!
retArgcAt: i
	^cgRetArgc at: i
! !

!OptCodegen methodsFor: 'registers'!
scratchA
	"The code generator's first scratch register for operands: x14 (on x86 x10: x14 has no x86 register)."
	^asm isX64 ifTrue: [X10] ifFalse: [X14]
!
scratchB
	^asm isX64 ifTrue: [X11] ifFalse: [X15]
!
dregBase
	"The first d register OptRegalloc allocates: d16 (on x86 d2: xmm2-xmm15)."
	^asm isX64 ifTrue: [D2] ifFalse: [D16]
!
dregPairs
	"Pairs of d registers from dregBase saved around a call."
	^asm isX64 ifTrue: [7] ifFalse: [8]
! !

!OptCodegen methodsFor: 'generating'!
generate: m act: a
	"Emit the code at the assembler's pc; answer whether it could."
	<function>
	| b need |
	cgCodeStart := asm pc.
	cgScanPc := asm pc.
	cgBinds := asm labelsBound.
	self forgetAll.
	cgRootAct := a.
	cgLastPc := -1.
	cgLastAct := -1.
	cgBcSize := self methodSize: m.
	cgValidSlots := builder validSlots.
	cgEntryPc := builder entryPc.
	cgSlotTop := regalloc slotCount.
	cgSlotTop < cgValidSlots ifTrue: [cgSlotTop := cgValidSlots].
	cgRawBase := cgSlotTop - regalloc rawCount.
	cgMaxOut := self maxOutgoing asInt32.
	"room for the frame's slots and outgoing calls, and for its activations' frames should it deoptimize"
	need := 0.
	0 to: ir actCount - 1 do: [:i | need := need + (ir act: i) nslots + 1].
	cgNeed := ((cgSlotTop + cgMaxOut + 1) max: need) asInt32.
	cgDoubles := false.
	0 to: ir nodeCount - 1 do: [:i | ((ir node: i) block >= 0 and: [(ir node: i) rep asInt32 = R_DBL]) ifTrue: [cgDoubles := true]].
	cgOutCount := 0.
	cgPoolCount := 0.
	cgMetaCount := 0.
	cgSpCount := 0.
	cgSiteCount := 0.
	cgRetCount := 0.
	cgExitPlainLabel := asm newLabel.
	cgExitSyncLabel := asm newLabel.
	cgDeoptLabel := asm labelAt: stubs optDeoptStub.
	cgReturnLabel := asm labelAt: stubs optReturnStub.
	cgInterruptLabel := asm labelAt: stubs interruptStub.
	cgBarrierLabel := asm labelAt: stubs barrierStub.
	cgDeoptReturnLabel := asm labelAt: stubs optDeoptReturnStub.
	cgStackFullLabel := asm labelAt: stubs optStackFullStub.
	cgHeaderLabel := asm newLabel.
	cgChecksLabel := asm newLabel.
	cgBodyLabel := asm newLabel.
	0 to: passes orderCount - 1 do: [:i | (ir block: (passes orderAt: i)) label: asm newLabel].
	builder isEntryUnit ifTrue: [self emitBaselineEntry].
	self emitEntry.
	self order.
	0 to: passes orderCount - 1 do: [:i |
		b := cgOrder at: i.
		self bindBlock: b after: (i > 0 ifTrue: [cgOrder at: i - 1] ifFalse: [-1]).
		self emitBlock: b next: (self nextWithCode: i + 1)].
	(self emitOuts) ifFalse: [^false].
	cgDepCount := (builder depCount min: 256) asInt32.
	0 to: cgDepCount - 1 do: [:i | cgDeps at: i put: (self poolIndexOf: (builder depAt: i))].
	asm bind: cgExitPlainLabel.
	asm comment: 'leave to the interpreter (the runtime made the frames canonical)'.
	asm b: (asm labelAt: stubs exitPlainAddress).
	asm bind: cgExitSyncLabel.
	asm comment: 'leave to the interpreter at the stored pc'.
	asm b: (asm labelAt: stubs blExitSyncAddress).
	self emitPool.
	"the inline caches' literals (JitBaselineRuntime sets them; GC roots once registered)"
	0 to: cgSiteCount - 1 do: [:i |
		asm bind: (cgSiteLit at: i).
		asm emit64: 0].
	"the header follows, 8-byte aligned (JitRuntime>>finish:code:mode:)"
	asm isX64
		ifTrue: [asm alignTo: 8]
		ifFalse: [[(asm pc bitAnd: 7) ~= 0] whileTrue: [asm emit: 16rD503201F]].
	asm bind: cgHeaderLabel.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'codegen: asm error %d, %d safepoints, %d metadata words
' with: asm errorCode with: cgSpCount with: cgMetaCount].
	^asm failed not and: [cgSpCount < CG_MAX_SP and: [cgMetaCount < (CG_MAX_META - 1024)]]
!
maxOutgoing
	| n |
	n := 0.
	0 to: ir nodeCount - 1 do: [:i |
		((ir node: i) block >= 0 and: [((ir node: i) op asInt32 = O_SEND or: [(ir node: i) op asInt32 = O_CALL or: [(ir node: i) op asInt32 = O_MKARRAY]])]) ifTrue: [
			n := n max: (ir node: i) nargs asInt32]].
	^n
!
emitBaselineEntry
	"The entry of a call made as baseline code makes it (x0 the receiver, a block's unit: the closure; x20 our fp, the arguments in place; x30 back to the caller): a method's unchecked entry branches here once this code is installed (JitBaselineRuntime>>redirect:to:), the block stub enters a block's unit here. The frame as baseline code builds it (code, closure, ctx, fp, a zero pc and sp: the runtime derives the rest), temps and home slots nil; no room on the stack: baseline's entry slow path (the runtime retries, leaves or sends)."
	| ac n fb entry slow far fl |
	ac := ir act: cgRootAct.
	n := ac numArgs.
	fb := self frameBytes asInt64.
	"the baseline limit leaves room for any frame; more than that is checked as the prologue's entry does"
	far := cgNeed > (analysis maxDepthLimit + 1).
	entry := asm newLabel.
	slow := asm newLabel.
	asm bind: entry.
	asm comment: 'entry from a call: room on the stack?'.
	asm isX64
		ifTrue: [asm cmp: X20 withStateWordAt: self stackLimitNormalOffset]
		ifFalse: [
			asm ldr: X16 base: X22 offset: self stackLimitNormalOffset.
			asm cmp: X20 with: X16].
	asm b: slow if: COND_HS.
	asm comment: 'native frame record, our Frame: code, closure, ctx, fp, pc and sp 0 (lazy)'.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm add: X19 with: X19 imm: fb.
	asm adr: X16 label: cgHeaderLabel.
	asm str: X16 base: X19 offset: self codeOffset.
	builder isMethodUnit
		ifTrue: [asm stp: X23 with: X23 base: X19 offset: self closureOffset]
		ifFalse: [
			asm stp: X0 with: X23 base: X19 offset: self closureOffset.
			asm comment: 'the receiver: the outer context''s (followed if a forwarder)'.
			asm ldr: X16 base: X0 offset: (self fieldOffset: BC_OUTER).
			asm ldr: X17 base: X16 offset: (self fieldOffset: CTX_RECEIVER).
			fl := asm newLabel.
			self emitForwardersTestTo: (self out: OUT_FOLLOW node: -1 index: (X17 bitOr: 255 << 8)).
			(cgOuts + (cgOutCount - 1)) resume: fl.
			asm bind: fl.
			asm stur: X17 base: X20 offset: -8].
	asm stp: X20 with: XZR base: X19 offset: self fpOffset.
	asm comment: 'temps nil'.
	self emitNilFrom: n to: (far ifTrue: [cgValidSlots] ifFalse: [cgRawBase]).
	asm b: (far ifTrue: [cgChecksLabel] ifFalse: [cgBodyLabel]).
	asm bind: slow.
	asm comment: 'no room: the entry slow path (x10 where to retry)'.
	asm adr: X10 label: entry.
	asm b: (asm labelAt: stubs blEntrySlowStub)
!
emitNilFrom: i0 to: i1
	"Slots i0 to i1 - 1 := nil (x23)."
	| i |
	i := i0.
	[i < i1] whileTrue: [
		(i + 1 < i1 and: [i < 63])
			ifTrue: [
				asm stp: X23 with: X23 base: X20 offset: 8 * i.
				i := i + 2]
			ifFalse: [
				asm str: X23 base: X20 offset: 8 * i.
				i := i + 1]]
!
emitEntry
	"The prologue from callers that pushed the frame (the runtime, the interpreter), then start: room for the frame and for its activations' frames should it deoptimize, home slots nil (not raw ones), the arguments."
	| s |
	self emitPrologue.
	runtime noteResume: cgEntryPc at: asm pc - cgCodeStart.
	builder isMethodUnit ifTrue: [
		asm comment: 'x0 := the receiver, as a call brings it'.
		asm ldur: X0 base: X20 offset: -8].
	asm bind: cgChecksLabel.
	asm comment: 'room for the frame''s slots and its activations'' frames (else the interpreter runs it)'.
	s := self out: OUT_STACK node: -1 index: 0.
	asm mov: X16 imm: 8 * cgNeed.
	asm add: X16 with: X20 with: X16.
	asm isX64
		ifTrue: [asm cmp: X16 withStateWordAt: self cstackLimitOffset]
		ifFalse: [
			asm ldr: X17 base: X22 offset: self cstackLimitOffset.
			asm cmp: X16 with: X17].
	asm b: s if: COND_HI.
	asm comment: 'invalidated (entered from older code): the interpreter runs it'.
	asm adr: X16 label: cgHeaderLabel.
	asm ldr: W16 base: X16 offset: self headerFlagsOffset.
	asm tst: W16 imm: 2.
	asm b: s if: COND_NE.
	cgRawBase > cgValidSlots ifTrue: [
		asm comment: 'home slots nil'.
		cgValidSlots to: cgRawBase - 1 do: [:i | asm str: X23 base: X20 offset: 8 * i]].
	asm bind: cgBodyLabel
!
order
	"The blocks in the order of their code: reverse postorder, but a loop's back edge (a block that only jumps back to the loop's head) right after the comparison that branches to it, which falls into it: a turn of the loop takes one branch."
	| n b t |
	0 to: passes orderCount - 1 do: [:i | cgPlaced at: (passes orderAt: i) put: 0].
	n := 0.
	0 to: passes orderCount - 1 do: [:i |
		b := passes orderAt: i.
		(cgPlaced at: b) = 0 ifTrue: [
			cgOrder at: n put: b.
			cgPlaced at: b put: 1.
			n := n + 1.
			t := self backEdgeAfter: b.
			(t >= 0 and: [(cgPlaced at: t) = 0]) ifTrue: [
				cgOrder at: n put: t.
				cgPlaced at: t put: 1.
				n := n + 1]]]
!
backEdgeAfter: b
	"The successor of b's compare and branch that only jumps back to the head of a loop around b, -1 if none."
	| bl nd |
	bl := ir block: b.
	(bl succ1 >= 0 and: [bl last >= 0]) ifFalse: [^-1].
	nd := ir node: bl last.
	(nd op asInt32 = O_BRANCH and: [self isFused: nd a]) ifFalse: [^-1].
	(self is: bl succ0 backEdgeFrom: b) ifTrue: [^bl succ0].
	(self is: bl succ1 backEdgeFrom: b) ifTrue: [^bl succ1].
	^-1
!
is: s backEdgeFrom: b
	| sb |
	sb := ir block: s.
	^sb npreds = 1 and: [sb succ1 < 0 and: [sb succ0 >= 0 and: [(ir block: sb succ0) rpo <= (ir block: b) rpo and: [
		sb last >= 0 and: [(ir node: sb last) op asInt32 = O_GOTO]]]]]
!
nextWithCode: i
	"The first block from order position i on that emits code (blocks with no nodes but phis and constants fall through), -1 if none."
	<function>
	| j |
	j := i.
	[j < passes orderCount] whileTrue: [
		(self isEmpty: (cgOrder at: j)) ifFalse: [^cgOrder at: j].
		j := j + 1].
	^-1
!
isEmpty: b
	| n op |
	n := (ir block: b) first.
	[n >= 0] whileTrue: [
		op := (ir node: n) op asInt32.
		(op = O_PHI or: [op = O_CONST]) ifFalse: [^false].
		n := (ir node: n) next].
	^true
!
jumpTargetOf: t
	"The block a branch to t ends up in: past blocks that only jump on, with no phi moves on the way."
	<function>
	| b nd hops |
	b := t.
	hops := 0.
	[nd := ir block: b.
	 hops < 16 and: [nd first >= 0 and: [nd first = nd last and: [(ir node: nd first) op asInt32 = O_GOTO and: [
		nd succ0 >= 0 and: [(ir block: nd succ0) first < 0 or: [(ir node: (ir block: nd succ0) first) op asInt32 ~= O_PHI]]]]]]] whileTrue: [
			b := nd succ0.
			hops := hops + 1].
	^b
!
bindBlock: b after: prev
	"b's label. Control that can only fall into b from prev, the block before it (its one predecessor, which neither branches to it nor is jumped through), keeps what registers hold."
	| keep |
	self catchUp.
	keep := (ir block: b) npreds = 1 and: [prev >= 0 and: [(ir pred: 0 of: b) = prev and: [(self jumpTargetOf: prev) = prev and: [(asm hasBranchesTo: (ir block: b) label) not]]]].
	asm bind: (ir block: b) label.
	keep ifTrue: [cgBinds := asm labelsBound]
!
emitBlock: b next: nextBlock
	| n nd |
	n := (ir block: b) first.
	[n >= 0] whileTrue: [
		nd := ir node: n.
		((nd bcact ~= cgLastAct or: [nd bcpc ~= cgLastPc]) and: [nd op asInt32 ~= O_PHI and: [nd op asInt32 ~= O_CONST]]) ifTrue: [
			nd bcact = cgRootAct
				ifTrue: [asm bytecode: nd bcpc]
				ifFalse: [
					nd bcact ~= cgLastAct ifTrue: [asm comment: 'inlined activation %d' with: nd bcact].
					asm comment: 'its pc %d' with: nd bcpc].
			cgLastAct := nd bcact.
			cgLastPc := nd bcpc].
		self emitNode: n block: b next: nextBlock.
		n := nd next]
! !

!OptCodegen methodsFor: 'operands'!
src: v into: scratch
	"A register holding v, which the caller only reads: its own, x23-x25 for nil, true and false, or scratch loaded from its slot or with the constant."
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [
		nd aux asUInt64 = memory nilOop ifTrue: [^X23].
		nd aux asUInt64 = memory trueOop ifTrue: [^X24].
		nd aux asUInt64 = memory falseOop ifTrue: [^X25].
		self loadConstant: nd aux asUInt64 into: scratch.
		^scratch].
	nd reg >= 0 ifTrue: [^nd reg asInt32].
	nd slot >= 0 ifTrue: [
		self load: scratch slot: nd slot asInt32.
		^scratch].
	asm fail: ASM_ERR_OPERAND.
	^scratch
!
dst: n
	"Where n's result is computed: its register, or X14 if it lives in its slot."
	| nd |
	nd := ir node: n.
	nd reg >= 0 ifTrue: [^nd reg asInt32].
	^self scratchA
!
def: n from: r
	"n's result is in r: into its register, and into its home slot if it has one (a value lives in its slot across safepoints: stored once, where it is defined; one only interrupt checks need there by their slow path)."
	| nd |
	nd := ir node: n.
	(nd reg >= 0 and: [nd reg asInt32 ~= r]) ifTrue: [asm mov: nd reg asInt32 with: r].
	(nd slot >= 0 and: [(nd flags bitAnd: NF_LAZY) = 0]) ifTrue: [self store: r slot: nd slot asInt32]
!
loadConstant: v into: r
	(self isInt: v) ifTrue: [
		(v asInt64 between: -16r80000000 and: 16r7FFFFFFF) ifTrue: [^asm mov: r imm: v asInt64].
		^asm mov: r imm: v].
	v = memory nilOop ifTrue: [^asm mov: r with: X23].
	v = memory trueOop ifTrue: [^asm mov: r with: X24].
	v = memory falseOop ifTrue: [^asm mov: r with: X25].
	(v bitAnd: 7) ~= 0 ifTrue: [^asm mov: r imm: v].
	asm ldr: r label: (cgPoolLabels at: (self poolIndexOf: v))
!
poolIndexOf: v
	"v's entry in the pool (made if needed)."
	<function>
	0 to: cgPoolCount - 1 do: [:i | (cgPoolOops at: i) = v ifTrue: [^i]].
	cgPoolCount >= CG_MAX_POOL ifTrue: [
		asm fail: ASM_ERR_FULL.
		^0].
	cgPoolOops at: cgPoolCount put: v.
	cgPoolLabels at: cgPoolCount put: asm newLabel.
	cgPoolCount := cgPoolCount + 1.
	^cgPoolCount - 1
!
load: r slot: s
	"r := slot s: nothing if r holds it, a move if another register does."
	<function>
	| h |
	self catchUp.
	(self register: r holds: 8 * s) ifTrue: [^self].
	h := self holderOf: 8 * s.
	(r <= 30 and: [h >= 0])
		ifTrue: [asm mov: r with: h]
		ifFalse: [asm ldr: r base: X20 offset: 8 * s]
!
store: r slot: s
	"Slot s := r, unless r holds it."
	<function>
	self catchUp.
	(self register: r holds: 8 * s) ifFalse: [asm str: r base: X20 offset: 8 * s]
!
register: r holds: off
	0 to: cgHeldCount - 1 do: [:i | ((cgHeldReg at: i) = r and: [(cgHeldSlot at: i) = off]) ifTrue: [^true]].
	^false
!
holderOf: off
	0 to: cgHeldCount - 1 do: [:i | (cgHeldSlot at: i) = off ifTrue: [^cgHeldReg at: i]].
	^-1
!
forgetAll
	cgHeldCount := 0
!
hold: off in: r
	"r holds the slot at off (as well)."
	(r < 31 and: [r ~= 20 and: [cgHeldCount < CG_MAX_HELD]]) ifTrue: [
		cgHeldSlot at: cgHeldCount put: off.
		cgHeldReg at: cgHeldCount put: r.
		cgHeldCount := cgHeldCount + 1]
!
forgetSlot: off
	| i |
	i := 0.
	[i < cgHeldCount] whileTrue: [
		(cgHeldSlot at: i) = off
			ifTrue: [
				cgHeldCount := cgHeldCount - 1.
				cgHeldSlot at: i put: (cgHeldSlot at: cgHeldCount).
				cgHeldReg at: i put: (cgHeldReg at: cgHeldCount)]
			ifFalse: [i := i + 1]]
!
catchUp
	"What registers hold, for the code emitted up to here: decoded since the last time, from the last label on if one was bound since (control may come to it from elsewhere: nothing known there)."
	<function>
	asm labelsBound ~= cgBinds ifTrue: [
		self forgetAll.
		cgBinds := asm labelsBound.
		cgScanPc := cgScanPc max: asm boundPc].
	asm isX64 ifTrue: [^self catchUpX64].
	[cgScanPc < asm pc] whileTrue: [
		self track: (self uint32At: cgScanPc).
		cgScanPc := cgScanPc + 4]
!
catchUpX64
	"catchUp's decoding of x86 code: what each instruction does, as Amd64Assembler>>effectAt: tells; from one it does not know on, nothing is known."
	<arch: #x86_64>
	| e n k r |
	[cgScanPc < asm pc] whileTrue: [
		e := asm effectAt: cgScanPc.
		n := e bitAnd: 255.
		n = 0
			ifTrue: [
				self forgetAll.
				cgScanPc := asm pc]
			ifFalse: [
				k := (e >> 8) bitAnd: 255.
				r := ((e >> 16) bitAnd: 255) asInt32.
				k = ASM_EF_LOAD ifTrue: [self loaded: r base: 20 offset: (e >> 32) asInt32].
				k = ASM_EF_STORE ifTrue: [self stored: r base: 20 offset: (e >> 32) asInt32].
				k = ASM_EF_MOVE ifTrue: [self copy: ((e >> 24) bitAnd: 255) asInt32 to: r].
				k = ASM_EF_WRITE ifTrue: [
					self wrote: r.
					self wrote: ((e >> 24) bitAnd: 255) asInt32].
				k = ASM_EF_FORGET ifTrue: [self forgetAll].
				cgScanPc := cgScanPc + n]].
	cgScanPc > asm pc ifTrue: [
		self forgetAll.
		cgScanPc := asm pc]
!
track: w
	"What instruction w does to what registers hold: ldr, str, ldur and stur of an X register at a slot make it hold the slot (a store makes the slot's other holders hold nothing), mov copies what a register holds; other writes make a register hold nothing; b.cond, cbz, cbnz, tbz and tbnz nothing; other branches (b, bl, br, blr, ret) and what is not decoded here, all registers."
	<var: #w type: 'uint32_t'>
	| rt rn |
	rt := (w bitAnd: 31) asInt32.
	rn := ((w >> 5) bitAnd: 31) asInt32.
	(w bitAnd: 16rFFC00000) = 16rF9400000 ifTrue: [^self loaded: rt base: rn offset: ((w >> 10) bitAnd: 16rFFF) asInt32 * 8].
	(w bitAnd: 16rFFC00000) = 16rF9000000 ifTrue: [^self stored: rt base: rn offset: ((w >> 10) bitAnd: 16rFFF) asInt32 * 8].
	(w bitAnd: 16rFFE00C00) = 16rF8400000 ifTrue: [^self loaded: rt base: rn offset: (self imm9Of: w)].
	(w bitAnd: 16rFFE00C00) = 16rF8000000 ifTrue: [^self stored: rt base: rn offset: (self imm9Of: w)].
	(w bitAnd: 16rFFE0FFE0) = 16rAA0003E0 ifTrue: [^self copy: ((w >> 16) bitAnd: 31) asInt32 to: rt].
	"other loads and stores (bit 27 set, 25 clear)"
	(w bitAnd: 16r0A000000) = 16r08000000 ifTrue: [^self loadStore: w].
	"data processing, immediate (bits 28:26 100) or register (27:25 101); floating point and SIMD (27:25 111) may write a general register"
	((w bitAnd: 16r1C000000) = 16r10000000 or: [(w bitAnd: 16r0E000000) = 16r0A000000 or: [(w bitAnd: 16r0E000000) = 16r0E000000]]) ifTrue: [^self wrote: rt].
	"b.cond; cbz, cbnz, tbz, tbnz"
	((w bitAnd: 16rFF000010) = 16r54000000 or: [(w bitAnd: 16r7C000000) = 16r34000000]) ifTrue: [^self].
	self forgetAll
!
loadStore: w
	"Loads and stores other than track:'s: what they load into and the bases they write back hold nothing; a store into the frame, nothing holds anything. Exclusives, atomics and the like: not decoded."
	<var: #w type: 'uint32_t'>
	| rt rn |
	rt := (w bitAnd: 31) asInt32.
	rn := ((w >> 5) bitAnd: 31) asInt32.
	"ldr literal (bits 29:27 011, 25:24 00)"
	(w bitAnd: 16r3B000000) = 16r18000000 ifTrue: [^self wrote: rt].
	"pairs (29:27 101): load bit 22, the second register bits 14:10, write-back bit 23"
	(w bitAnd: 16r38000000) = 16r28000000 ifTrue: [
		(w bitAnd: 16r400000) ~= 0
			ifTrue: [
				self wrote: rt.
				self wrote: ((w >> 10) bitAnd: 31) asInt32]
			ifFalse: [rn = 20 ifTrue: [self forgetAll]].
		(w bitAnd: 16r800000) ~= 0 ifTrue: [self wrote: rn].
		^self].
	"one register (29:27 111): register offset (bit 21, bits 11:10 10) or none; a store: opc (23:22) 00, or 10 of a SIMD register (bit 26); write-back: bits 24 and 21 clear, bit 10 set"
	((w bitAnd: 16r38000000) = 16r38000000 and: [(w bitAnd: 16r1200000) ~= 16r200000 or: [(w bitAnd: 16rC00) = 16r800]]) ifTrue: [
		((w bitAnd: 16rC00000) = 0 or: [(w bitAnd: 16r4400000) = 16r4000000])
			ifTrue: [rn = 20 ifTrue: [self forgetAll]]
			ifFalse: [self wrote: rt].
		((w bitAnd: 16r1200000) = 0 and: [(w bitAnd: 16r400) ~= 0]) ifTrue: [self wrote: rn].
		^self].
	self forgetAll
!
imm9Of: w
	"The signed 9-bit offset of ldur and stur."
	<var: #w type: 'uint32_t'>
	| i |
	i := ((w >> 12) bitAnd: 16r1FF) asInt32.
	^i >= 256 ifTrue: [i - 512] ifFalse: [i]
!
loaded: rt base: rn offset: off
	self wrote: rt.
	(rn = 20 and: [rt ~= rn]) ifTrue: [self hold: off in: rt]
!
stored: rt base: rn offset: off
	rn = 20 ifFalse: [^self].
	(off bitAnd: 7) ~= 0 ifTrue: [^self forgetAll].
	self forgetSlot: off.
	self hold: off in: rt
!
copy: rm to: rd
	"mov rd, rm: rd holds what rm holds."
	| n |
	self wrote: rd.
	n := cgHeldCount.
	0 to: n - 1 do: [:i | (cgHeldReg at: i) = rm ifTrue: [self hold: (cgHeldSlot at: i) in: rd]]
!
wrote: r
	"r changed: it holds no slot; x20 changed: no register does."
	| i |
	r = 20 ifTrue: [^self forgetAll].
	i := 0.
	[i < cgHeldCount] whileTrue: [
		(cgHeldReg at: i) = r
			ifTrue: [
				cgHeldCount := cgHeldCount - 1.
				cgHeldSlot at: i put: (cgHeldSlot at: cgHeldCount).
				cgHeldReg at: i put: (cgHeldReg at: cgHeldCount)]
			ifFalse: [i := i + 1]]
!
emitPool
	asm isX64
		ifTrue: [asm alignTo: 8]
		ifFalse: [[(asm pc bitAnd: 7) ~= 0] whileTrue: [asm emit: 16rD503201F]].
	0 to: cgPoolCount - 1 do: [:i |
		asm bind: (cgPoolLabels at: i).
		asm emit64: (cgPoolOops at: i)]
!
cstackLimitOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #cstackLimit) to: 'int64_t'
!
stackLimitNormalOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #stackLimitNormal) to: 'int64_t'
!
dumpOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #dump) to: 'int64_t'
!
hashBoxOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #hashBox) to: 'int64_t'
!
boxedFloatClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #boxedFloatClass) to: 'int64_t'
!
stressOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #stress) to: 'int64_t'
!
codeOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #code) to: 'int64_t'
!
ipOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #ip) to: 'int64_t'
!
headerFlagsOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitMethod *') fieldAddress: #flags) to: 'int64_t'
! !

!OptCodegen methodsFor: 'nodes'!
emitNode: n block: b next: nextBlock
	<function>
	| nd op x y r s l |
	nd := ir node: n.
	op := nd op asInt32.
	op = O_PHI ifTrue: [^self].
	op = O_CONST ifTrue: [^self].
	op = O_CLOSURE ifTrue: [^self].
	op = O_HOMESLOT ifTrue: [^self].
	op = O_LOADSLOT ifTrue: [
		r := self dst: n.
		self load: r slot: nd aux asInt32.
		^self def: n from: r].
	op = O_STORESLOT ifTrue: [
		self store: (self src: nd a into: self scratchA) slot: nd aux asInt32.
		^self].
	op = O_PARAM ifTrue: [
		(nd reg < 0 and: [nd slot < 0 or: [nd slot asInt64 = nd aux]]) ifTrue: [^self].
		r := self dst: n.
		"a method's receiver: x0, as calls bring it (the prologue loads it there)"
		(nd aux = -1 and: [builder isMethodUnit]) ifTrue: [
			r ~= X0 ifTrue: [asm mov: r with: X0].
			^self def: n from: r].
		"-2 a block unit's closure, -3 the frame's Context"
		nd aux = -2
			ifTrue: [asm ldr: r base: X19 offset: self closureOffset]
			ifFalse: [
				nd aux = -3
					ifTrue: [asm ldr: r base: X19 offset: self ctxOffset]
					ifFalse: [self load: r slot: nd aux asInt32]].
		"an argument's home is its own slot"
		nd slot asInt64 = nd aux ifTrue: [^self].
		^self def: n from: r].
	op = O_LOADFIELD ifTrue: [
		x := self src: nd a into: self scratchB.
		r := self dst: n.
		asm ldr: r base: x offset: (self fieldOffset: nd aux).
		(nd flags bitAnd: NF_FOLLOW) ~= 0 ifTrue: [
			l := asm newLabel.
			self emitForwardersTestTo: (self out: OUT_FOLLOW node: n index: (r bitOr: 255 << 8)).
			(cgOuts + (cgOutCount - 1)) resume: l.
			asm bind: l].
		^self def: n from: r].
	op = O_STOREFIELD ifTrue: [^self emitStore: n].
	(op = O_OUTERLOAD or: [op = O_OUTERSTORE]) ifTrue: [^self emitOuterTemp: n].
	op = O_OUTERSLOT ifTrue: [^self emitOuterSlot: n].
	op = O_INDEXLOAD ifTrue: [^self emitIndexLoad: n].
	op = O_INDEXSTORE ifTrue: [^self emitIndexStore: n].
	op = O_SIZE ifTrue: [
		x := self src: nd a into: self scratchB.
		self emitSizeOf: x kind: nd aux asInt32 fixed: nd aux2 asInt32.
		asm add: X16 with: X16 with: X16.
		r := self dst: n.
		asm orr: r with: X16 imm: 1.
		^self def: n from: r].
	op = O_CLASSOF ifTrue: [^self emitClassOf: n].
	(op = O_STRHASH or: [op = O_STRCMP]) ifTrue: [^self emitString: n].
	(op = O_UNBOXF or: [op = O_BOXF or: [op = O_FARITH or: [op = O_FSQRT]]]) ifTrue: [^self emitFloat: n].
	(op = O_EQ or: [op = O_NE or: [op = O_ICMP or: [op = O_CLASSIS or: [op = O_FCMP or: [op = O_BOTHINT]]]]]) ifTrue: [
		(self isFused: n) ifTrue: [^self].
		self emitCompare: n.
		r := self dst: n.
		asm csel: r with: X24 with: X25 cond: (self conditionOf: n).
		^self def: n from: r].
	op = O_GUARDCLASS ifTrue: [
		s := self deoptLabelFor: n.
		x := self src: nd a into: self scratchB.
		asm comment: ((nd flags bitAnd: NF_HOISTED) ~= 0 ifTrue: ['guard: its class, once before the loop'] ifFalse: ['guard: its class']).
		self emitClassTest: x class: nd aux asUInt64.
		asm b: s if: COND_NE.
		^self def: n from: x].
	op = O_GUARDMUTABLE ifTrue: [
		s := self deoptLabelFor: n.
		x := self src: nd a into: self scratchA.
		asm comment: 'guard: not immutable, once before the loop (its stores into it check nothing)'.
		asm ldr: X16 base: x offset: 0.
		asm tst: X16 imm: H_IMMUTABLE.
		asm b: s if: COND_NE.
		^self].
	op = O_GUARDEQ ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: ((nd flags bitAnd: NF_HOISTED) ~= 0 ifTrue: ['guard, once before the loop: the global holds another value than the class speculated: deoptimize'] ifFalse: ['guard: the global holds another value than the class speculated: deoptimize']).
		x := self src: nd a into: self scratchA.
		asm cmp: x with: (self src: nd b into: self scratchB).
		asm b: s if: COND_NE.
		^self].
	op = O_GUARDCLOSURE ifTrue: [
		s := self deoptLabelFor: n.
		x := self src: nd a into: self scratchB.
		asm comment: ((nd flags bitAnd: NF_HOISTED) ~= 0 ifTrue: ['guard: the closure whose body is inline, once before the loop'] ifFalse: ['guard: the closure whose body is inline']).
		asm ldr: X16 base: x offset: (self fieldOffset: BC_STARTPC).
		asm mov: X17 imm: (self intOop: nd aux) asInt64.
		asm cmp: X16 with: X17.
		asm b: s if: COND_NE.
		asm ldr: X16 base: x offset: (self fieldOffset: BC_OUTER).
		asm ldr: X16 base: X16 offset: (self fieldOffset: CTX_METHOD).
		asm cmp: X16 with: (self src: nd b into: self scratchA).
		asm b: s if: COND_NE.
		^self def: n from: x].
	op = O_CAST ifTrue: [^self def: n from: (self src: nd a into: self scratchB)].
	op = O_GUARDINT ifTrue: [
		s := self deoptLabelFor: n.
		x := self src: nd a into: self scratchB.
		asm comment: ((nd flags bitAnd: NF_HOISTED) ~= 0 ifTrue: ['guard: a SmallInteger, once before the loop'] ifFalse: ['guard: a SmallInteger']).
		asm tst: x imm: 1.
		asm b: s if: COND_EQ.
		^self def: n from: x].
	(op = O_IADD or: [op = O_ISUB]) ifTrue: [^self emitAddSub: n].
	op = O_IMUL ifTrue: [^self emitMul: n].
	(op = O_IMOD or: [op = O_IDIV or: [op = O_ISHIFT]]) ifTrue: [^self emitDivShift: n].
	op = O_CHARCONV ifTrue: [
		x := self src: nd a into: self scratchA.
		r := self dst: n.
		nd aux = 0 ifTrue: [
			asm comment: 'a Character''s value'.
			asm lsr: r with: x imm: 2.
			asm orr: r with: r imm: 1.
			^self def: n from: r].
		(nd flags bitAnd: NF_INRANGE) ~= 0 ifTrue: [
			asm comment: 'the Character of a code point'.
			asm asr: X16 with: x imm: 1.
			asm lsl: r with: X16 imm: 3.
			asm orr: r with: r imm: 2.
			^self def: n from: r].
		s := self deoptLabelFor: n.
		asm comment: 'the Character of a SmallInteger (0 to 16r10FFFF)'.
		asm asr: X16 with: x imm: 1.
		asm mov: X17 imm: CHAR_VALUE_MAX.
		asm cmp: X16 with: X17.
		asm b: s if: COND_HI.
		asm lsl: r with: X16 imm: 3.
		asm orr: r with: r imm: 2.
		^self def: n from: r].
	op = O_GUARDLE ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: 'guard: at most the other, once before the loop (its indexed accesses check no bounds)'.
		y := self src: nd b into: self scratchB.
		nd a >= 0
			ifTrue: [
				x := self src: nd a into: self scratchA.
				asm cmp: x with: y.
				asm b: s if: (nd aux2 = 1 ifTrue: [COND_GE] ifFalse: [COND_GT])]
			ifFalse: [
				nd aux <= 4095
					ifTrue: [asm cmp: y imm: nd aux]
					ifFalse: [
						asm mov: X17 imm: nd aux.
						asm cmp: y with: X17].
				asm b: s if: COND_LT].
		^self].
	op = O_NOTINTS ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: 'guard: not two SmallIntegers'.
		x := self src: nd a into: self scratchA.
		y := self src: nd b into: self scratchB.
		asm and: X16 with: x with: y.
		asm tst: X16 imm: 1.
		asm b: s if: COND_NE.
		^self].
	(op = O_IAND or: [op = O_IOR or: [op = O_IXOR]]) ifTrue: [
		x := self src: nd a into: self scratchA.
		y := self src: nd b into: self scratchB.
		r := self dst: n.
		op = O_IAND ifTrue: [asm and: r with: x with: y].
		op = O_IOR ifTrue: [asm orr: r with: x with: y].
		op = O_IXOR ifTrue: [
			asm eor: r with: x with: y.
			asm orr: r with: r imm: 1].
		^self def: n from: r].
	op = O_CHECKINT ifTrue: [^self emitCheckInterrupt: n].
	op = O_MKARRAY ifTrue: [^self emitMakeArray: n].
	(op = O_SEND or: [op = O_CALL]) ifTrue: [^self emitSend: n].
	op = O_GOTO ifTrue: [
		self emitMovesFrom: b to: (ir block: b) succ0.
		((ir block: b) succ0 = nextBlock or: [(self jumpTargetOf: (ir block: b) succ0) = nextBlock]) ifFalse: [
			asm b: (ir block: (self jumpTargetOf: (ir block: b) succ0)) label].
		^self].
	op = O_BRANCH ifTrue: [^self emitBranch: n block: b next: nextBlock].
	op = O_RETURN ifTrue: [^self emitReturn: n].
	op = O_DEOPT ifTrue: [
		(ir node: n) aux = 1 ifTrue: [asm comment: 'the global holds another value than the class speculated: deoptimize'].
		asm b: (self deoptLabelFor: n).
		^self].
	asm fail: ASM_ERR_OPERAND
!
isFused: n
	"A comparison whose only use is the branch right after it (or, after the jump that ends its block, the first node of the block that only that jump reaches: an inlined method answered it): the branch compares."
	| nd nx c op |
	nd := ir node: n.
	op := nd op asInt32.
	(op = O_EQ or: [op = O_NE or: [op = O_ICMP or: [op = O_CLASSIS or: [op = O_FCMP or: [op = O_BOTHINT]]]]]) ifFalse: [^false].
	nd uses = 1 ifFalse: [^false].
	nd next < 0 ifTrue: [^false].
	nx := ir node: nd next.
	(nx op asInt32 = O_BRANCH and: [nx a = n]) ifTrue: [^true].
	nx op asInt32 = O_GOTO ifFalse: [^false].
	c := ir block: (ir block: nd block) succ0.
	(c npreds = 1 and: [c first >= 0]) ifFalse: [^false].
	nx := ir node: c first.
	^nx op asInt32 = O_BRANCH and: [nx a = n]
!
conditionOf: n
	| nd k |
	nd := ir node: n.
	nd op asInt32 = O_EQ ifTrue: [^COND_EQ].
	nd op asInt32 = O_CLASSIS ifTrue: [^COND_EQ].
	nd op asInt32 = O_NE ifTrue: [^COND_NE].
	nd op asInt32 = O_BOTHINT ifTrue: [^COND_EQ].
	k := nd aux asInt32.
	"floats: unordered (NaN) compares false, except ~="
	nd op asInt32 = O_FCMP ifTrue: [^k caseOf: {[2] -> [COND_MI]. [3] -> [COND_GT]. [4] -> [COND_LS]. [5] -> [COND_GE]. [6] -> [COND_EQ]} otherwise: [COND_NE]].
	^k caseOf: {[2] -> [COND_LT]. [3] -> [COND_GT]. [4] -> [COND_LE]. [5] -> [COND_GE]. [6] -> [COND_EQ]} otherwise: [COND_NE]
!
isNoForwarderTarget: v
	"Value v is never a forwarder nor forwarded to: an immediate, nil, true or false."
	| k |
	k := (ir node: v) tkind asInt32.
	^k = T_SMI or: [k = T_BOOL or: [k = T_NIL or: [k = T_CHAR or: [(k = T_FLOAT and: [(ir node: v) op asInt32 = O_CONST])]]]]
!
emitCompare: n
	| nd x y l back |
	nd := ir node: n.
	nd op asInt32 = O_FCMP ifTrue: [
		x := self dsrc: nd a into: D0.
		y := self dsrc: nd b into: D1.
		^asm fcmp: x with: y].
	x := self src: nd a into: self scratchA.
	nd op asInt32 = O_CLASSIS ifTrue: [^self emitClassTest: x class: nd aux asUInt64].
	nd op asInt32 = O_BOTHINT ifTrue: [
		y := self src: nd b into: self scratchB.
		asm and: X16 with: x with: y.
		asm and: X16 with: X16 imm: 1.
		^asm cmp: X16 imm: 1].
	((ir node: nd b) op asInt32 = O_CONST and: [(self isInt: (ir node: nd b) aux asUInt64) and: [(ir node: nd b) aux between: -4095 and: 4095]])
		ifTrue: [
			(ir node: nd b) aux >= 0
				ifTrue: [asm cmp: x imm: (ir node: nd b) aux]
				ifFalse: [asm cmn: x imm: (ir node: nd b) aux negated]]
		ifFalse: [
			y := self src: nd b into: self scratchB.
			((nd op asInt32 = O_EQ or: [nd op asInt32 = O_NE]) and: [(self isNoForwarderTarget: nd a) not and: [(self isNoForwarderTarget: nd b) not]]) ifTrue: [
				"some object is a forwarder (becomeForward:): follow both first"
				l := self out: OUT_FOLLOW node: n index: (x bitOr: y << 8).
				back := asm newLabel.
				(cgOuts + (cgOutCount - 1)) resume: back.
				self emitForwardersTestTo: l.
				asm bind: back].
			asm cmp: x with: y]
!
emitBranch: n block: b next: nextBlock
	| nd v vd t f tl fl s rv |
	nd := ir node: n.
	v := nd a.
	vd := ir node: v.
	(vd tkind asInt32 ~= T_BOOL and: [(self isFused: v) not]) ifTrue: [s := self deoptLabelFor: n].
	t := (ir block: b) succ0.
	f := (ir block: b) succ1.
	tl := (ir block: (self jumpTargetOf: t)) label.
	fl := (ir block: (self jumpTargetOf: f)) label.
	(self isFused: v) ifTrue: [
		self emitCompare: v.
		(t = nextBlock or: [(self jumpTargetOf: t) = nextBlock])
			ifTrue: [asm b: fl if: ((self conditionOf: v) bitXor: 1)]
			ifFalse: [
				asm b: tl if: (self conditionOf: v).
				(f = nextBlock or: [(self jumpTargetOf: f) = nextBlock]) ifFalse: [asm b: fl]].
		^self].
	rv := self src: v into: self scratchA.
	asm cmp: rv with: X24.
	asm b: tl if: COND_EQ.
	vd tkind asInt32 ~= T_BOOL ifTrue: [
		asm comment: 'neither true nor false: the interpreter sends mustBeBoolean'.
		asm cmp: rv with: X25.
		asm b: s if: COND_NE].
	(f = nextBlock or: [(self jumpTargetOf: f) = nextBlock]) ifFalse: [asm b: fl]
!
emitDouble: bits into: d
	"d := the double with the IEEE bits bits: an fmov immediate where one encodes it."
	(asm fmovImmediate: (self doubleFromBits: bits)) >= 0 ifTrue: [^asm fmov: d imm: (self doubleFromBits: bits)].
	asm comment: 'a Float constant'.
	asm mov: X16 imm: bits.
	asm fmov: d with: X16
!
dsrc: v into: d
	"A d register holding double v, which the caller only reads: its own, or d (D0 or D1, the code generator's) loaded from its raw slot or with the Float constant."
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [
		self emitDouble: (self constantDouble: nd aux asUInt64) into: d.
		^d].
	nd reg >= D0 ifTrue: [^nd reg asInt32].
	nd slot >= 0 ifTrue: [
		self load: d slot: nd slot asInt32.
		^d].
	asm fail: ASM_ERR_OPERAND.
	^d
!
ddst: n
	"Where double n is computed: its d register, or D0 if it lives in its raw slot."
	(ir node: n) reg >= 0 ifTrue: [^(ir node: n) reg asInt32].
	^D0
!
ddef: n from: d
	"Double n is in d: into its d register, and into its raw slot if it lives there or has its home there (as def:from:)."
	| nd |
	nd := ir node: n.
	(nd reg >= 0 and: [nd reg asInt32 ~= d]) ifTrue: [asm fmov: nd reg asInt32 with: d].
	(nd slot >= 0 and: [nd reg < 0 or: [(nd flags bitAnd: NF_LAZY) = 0]]) ifTrue: [self store: d slot: nd slot asInt32]
!
emitFloat: n
	"Unboxing (a SmallFloat64 or BoxedFloat64 decoded, a SmallInteger converted), boxing (as a SmallFloat64), arithmetic and sqrt on doubles; what does not fit deoptimizes. Doubles in raw slots are loaded into D0 and D1, results computed in D0 and stored."
	| nd op s x y r int boxed done zero store k |
	nd := ir node: n.
	op := nd op asInt32.
	op = O_UNBOXF ifTrue: [
		r := self ddst: n.
		((ir node: nd a) op asInt32 = O_CONST and: [((ir node: nd a) aux bitAnd: 1) ~= 0 or: [((ir node: nd a) aux bitAnd: 7) = 4]]) ifTrue: [
			self emitDouble: (self constantDouble: (ir node: nd a) aux asUInt64) into: r.
			^self ddef: n from: r].
		x := self src: nd a into: self scratchB.
		(ir node: nd a) tkind asInt32 = T_SMI ifTrue: [
			asm comment: 'a SmallInteger''s double'.
			asm asr: X16 with: x imm: 1.
			asm scvtf: r with: X16.
			^self ddef: n from: r].
		(ir node: nd a) tkind asInt32 ~= T_FLOAT ifTrue: [
			s := self deoptLabelFor: n.
			int := asm newLabel.
			boxed := asm newLabel.
			done := asm newLabel.
			asm tbnz: x bit: 0 to: int.
			asm and: X16 with: x imm: 7.
			asm cmp: X16 imm: 4.
			asm b: boxed if: COND_NE].
		asm comment: 'a SmallFloat64''s double'.
		asm lsr: X16 with: x imm: 3.
		asm mov: X17 imm: 16r7000000000000000.
		asm add: X17 with: X16 with: X17.
		asm cmp: X16 imm: 1.
		asm csel: X16 with: X16 with: X17 cond: COND_LS.
		asm ror: X16 with: X16 imm: 1.
		asm fmov: r with: X16.
		(ir node: nd a) tkind asInt32 ~= T_FLOAT ifTrue: [
			asm b: done.
			asm bind: boxed.
			asm comment: 'a BoxedFloat64''s double (anything else deoptimizes)'.
			asm cbnz: X16 to: s.
			asm ldr: X16 base: x offset: 8.
			asm ldr: X17 base: X22 offset: self boxedFloatClassOffset.
			asm cmp: X16 with: X17.
			asm b: s if: COND_NE.
			asm ldr: r base: x offset: 16.
			asm b: done.
			asm bind: int.
			asm asr: X16 with: x imm: 1.
			asm scvtf: r with: X16.
			asm bind: done].
		^self ddef: n from: r].
	op = O_BOXF ifTrue: [
		s := self deoptLabelFor: n.
		zero := asm newLabel.
		store := asm newLabel.
		asm comment: 'as a SmallFloat64 (out of its exponent range: deoptimize)'.
		asm fmov: X16 with: (self dsrc: nd a into: D0).
		asm lsl: X17 with: X16 imm: 1.
		asm cbz: X17 to: zero.
		asm ubfx: self scratchB with: X16 lsb: 52 width: 11.
		asm sub: self scratchB with: self scratchB imm: 897.
		asm cmp: self scratchB imm: 253.
		asm b: s if: COND_HI.
		asm ror: X17 with: X16 imm: 63.
		asm mov: self scratchB imm: 16r7000000000000000.
		asm sub: X17 with: X17 with: self scratchB.
		asm b: store.
		asm bind: zero.
		asm lsr: X17 with: X16 imm: 63.
		asm bind: store.
		r := self dst: n.
		asm lsl: r with: X17 imm: 3.
		asm orr: r with: r imm: 4.
		^self def: n from: r].
	op = O_FSQRT ifTrue: [
		x := self dsrc: nd a into: D0.
		r := self ddst: n.
		asm fsqrt: r with: x.
		^self ddef: n from: r].
	k := nd aux asInt32.
	x := self dsrc: nd a into: D0.
	y := self dsrc: nd b into: D1.
	k = 9 ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: 'division by zero: deoptimize'.
		asm fcmpZero: y.
		asm b: s if: COND_EQ].
	r := self ddst: n.
	k = 0 ifTrue: [asm fadd: r with: x with: y].
	k = 1 ifTrue: [asm fsub: r with: x with: y].
	k = 8 ifTrue: [asm fmul: r with: x with: y].
	k = 9 ifTrue: [asm fdiv: r with: x with: y].
	self ddef: n from: r
!
emitSizeOf: x kind: ek fixed: fixed
	"X16 := the number of indexable elements of x (pointer slots after fixed fields, or bytes); uses X17."
	ek = E_PTR ifTrue: [
		asm ldr: W16 base: x offset: 0.
		fixed > 0 ifTrue: [asm sub: X16 with: X16 imm: fixed].
		^self].
	asm comment: 'bytes: 8 per slot less the unused ones (the format''s low bits)'.
	asm ldr: X17 base: x offset: 0.
	asm ubfx: X16 with: X17 lsb: 0 width: 32.
	asm ubfx: X17 with: X17 lsb: 32 width: 5.
	asm sub: X17 with: X17 imm: F_BYTES.
	asm lsl: X16 with: X16 imm: 3.
	asm sub: X16 with: X16 with: X17
!
emitIndexCheck: n
	"X17 := the 0-based element index of n's index operand (a SmallInteger) in its object, deoptimizing if it is out of bounds; answer the object's register."
	| nd x i s |
	nd := ir node: n.
	(nd flags bitAnd: NF_NOBOUNDS) ~= 0 ifTrue: [
		x := self src: nd a into: self scratchA.
		asm comment: 'within bounds: checked once before the loop'.
		i := self src: nd b into: self scratchB.
		asm asr: X17 with: i imm: 1.
		asm sub: X17 with: X17 imm: 1.
		^x].
	s := self deoptLabelFor: n.
	x := self src: nd a into: self scratchA.
	asm comment: 'bounds check'.
	self emitSizeOf: x kind: nd aux asInt32 fixed: nd aux2 asInt32.
	i := self src: nd b into: self scratchB.
	asm asr: X17 with: i imm: 1.
	asm sub: X17 with: X17 imm: 1.
	asm cmp: X17 with: X16.
	asm b: s if: COND_HS.
	^x
!
emitIndexLoad: n
	| nd x r ek |
	nd := ir node: n.
	ek := nd aux asInt32.
	x := self emitIndexCheck: n.
	asm add: X16 with: x imm: 16 + (8 * nd aux2).
	r := self dst: n.
	ek = E_PTR ifTrue: [
		asm ldr: r base: X16 index: X17 extend: EXT_LSL shift: 3.
		^self def: n from: r].
	asm ldrb: W16 base: X16 index: X17.
	ek = E_BYTE
		ifTrue: [
			asm lsl: X16 with: X16 imm: 1.
			asm orr: r with: X16 imm: 1]
		ifFalse: [
			asm lsl: X16 with: X16 imm: 3.
			asm orr: r with: X16 imm: 2].
	self def: n from: r
!
emitIndexStore: n
	"The value: a SmallInteger 0-255 into bytes, a Character below 256 into a string, any oop into pointers (with the store barrier); an immutable object deoptimizes."
	| nd x v ek s done check slow |
	nd := ir node: n.
	ek := nd aux asInt32.
	s := self deoptLabelFor: n.
	x := self emitIndexCheck: n.
	(nd flags bitAnd: NF_MUTABLE) = 0 ifTrue: [
		asm ldr: X16 base: x offset: 0.
		asm tst: X16 imm: H_IMMUTABLE.
		asm b: s if: COND_NE].
	asm add: X16 with: x imm: 16 + (8 * nd aux2).
	asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: (ek = E_PTR ifTrue: [3] ifFalse: [0]).
	v := self src: nd c into: self scratchB.
	ek ~= E_PTR ifTrue: [
		(nd flags bitAnd: NF_INRANGE) ~= 0 ifTrue: [
			asm comment: 'a byte or a Character below 256: unchecked'.
			asm lsr: X17 with: v imm: (ek = E_BYTE ifTrue: [1] ifFalse: [3]).
			asm strb: W17 base: X16 offset: 0.
			^self].
		ek = E_BYTE
			ifTrue: [
				asm tst: v imm: 1.
				asm b: s if: COND_EQ.
				asm lsr: X17 with: v imm: 1]
			ifFalse: [
				asm and: X17 with: v imm: 7.
				asm cmp: X17 imm: 2.
				asm b: s if: COND_NE.
				asm lsr: X17 with: v imm: 3].
		asm cmp: X17 imm: 255.
		asm b: s if: COND_HI.
		asm strb: W17 base: X16 offset: 0.
		^self].
	asm str: v base: X16 offset: 0.
	(ir node: nd c) op asInt32 = O_CONST ifTrue: [
		(((ir node: nd c) aux bitAnd: 7) ~= 0 or: [(self isYoung: (ir node: nd c) aux asUInt64) not]) ifTrue: [^self]].
	done := asm newLabel.
	check := asm newLabel.
	slow := self out: OUT_BARRIER node: n index: (x bitOr: v << 8).
	(cgOuts + (cgOutCount - 1)) resume: done.
	asm comment: 'store barrier'.
	asm tst: v imm: 7.
	asm b: done if: COND_NE.
	asm ldr: X16 base: X22 offset: self youngLoOffset.
	asm cmp: v with: X16.
	asm b: done if: COND_LO.
	asm ldr: X17 base: X22 offset: self youngHiOffset.
	asm cmp: v with: X17.
	asm b: done if: COND_HS.
	asm cmp: x with: X16.
	asm b: check if: COND_LO.
	asm cmp: x with: X17.
	asm b: done if: COND_LO.
	asm bind: check.
	asm ldr: X16 base: x offset: 0.
	asm tst: X16 imm: H_REMEMBERED.
	asm b: slow if: COND_EQ.
	asm bind: done
!
emitClassTest: x class: cls
	"Flags EQ if x's class is cls (no branch: a tagged x reads a word of the JitState instead of a class)."
	cls = memory clsSmallint ifTrue: [
		asm and: X16 with: x imm: 1.
		^asm cmp: X16 imm: 1].
	cls = memory clsSmallfloat ifTrue: [
		asm and: X16 with: x imm: 7.
		^asm cmp: X16 imm: 4].
	cls = memory clsChar ifTrue: [
		asm and: X16 with: x imm: 7.
		^asm cmp: X16 imm: 2].
	asm tst: x imm: 7.
	asm csel: X16 with: x with: X22 cond: COND_EQ.
	asm ldr: X16 base: X16 offset: 8.
	self loadConstant: cls into: X17.
	asm cmp: X16 with: X17
!
emitAddSub: n
	| nd x y c isAdd s checked |
	nd := ir node: n.
	"no overflow check where the operands' ranges rule it out"
	checked := (nd flags bitAnd: NF_INRANGE) = 0.
	checked ifTrue: [s := self deoptLabelFor: n].
	isAdd := nd op asInt32 = O_IADD.
	x := self src: nd a into: self scratchA.
	((ir node: nd b) op asInt32 = O_CONST and: [((ir node: nd b) aux asUInt64 - 1) asInt64 between: -4095 and: 4095])
		ifTrue: [
			c := ((ir node: nd b) aux asUInt64 - 1) asInt64.
			(isAdd = (c >= 0))
				ifTrue: [asm adds: X16 with: x imm: (c < 0 ifTrue: [c negated] ifFalse: [c])]
				ifFalse: [asm subs: X16 with: x imm: (c < 0 ifTrue: [c negated] ifFalse: [c])]]
		ifFalse: [
			y := self src: nd b into: self scratchB.
			asm sub: X17 with: y imm: 1.
			isAdd
				ifTrue: [asm adds: X16 with: x with: X17]
				ifFalse: [asm subs: X16 with: x with: X17]].
	checked ifTrue: [asm b: s if: COND_VS].
	self def: n from: X16
!
emitDivShift: n
	"SmallInteger modulo and division (floored, aux 1 truncated: rem: quo:, aux 2 exact: /, a remainder deoptimizes; a zero divisor deoptimizes; \\ by a divisor that turns out a positive power of two: a mask) and bitShift: (a result that does not fit deoptimizes)."
	| nd s op neg done d k r general |
	nd := ir node: n.
	op := nd op asInt32.
	d := self constantDivisorOf: n.
	(nd aux = 0 and: [d > 1 and: [(d bitAnd: d - 1) = 0 and: [d < 16r40000000]]]) ifTrue: [
		"floored by 2^k, on the tagged value 2x + 1: shifted right by k it is the quotient's 2q or 2q + 1, its low k + 1 bits are the remainder's 2r + 1"
		k := 0.
		[(1 asInt64 << k) < d] whileTrue: [k := k + 1].
		r := self dst: n.
		op = O_IDIV
			ifTrue: [
				asm comment: 'floored division by the constant %d' with: d.
				asm asr: r with: (self src: nd a into: self scratchA) imm: k.
				asm orr: r with: r imm: 1]
			ifFalse: [
				asm comment: 'modulo the constant %d' with: d.
				asm and: r with: (self src: nd a into: self scratchA) imm: d + d - 1].
		^self def: n from: r].
	s := self deoptLabelFor: n.
	asm asr: X16 with: (self src: nd a into: self scratchA) imm: 1.
	done := asm newLabel.
	d := self constantDivisorOf: n.
	d ~= 0 ifTrue: [
		^self emitDivTail: n done: done floored: (self emitDivBy: d node: n)].
	asm asr: X17 with: (self src: nd b into: self scratchB) imm: 1.
	op = O_ISHIFT ifTrue: [
		neg := asm newLabel.
		asm tbnz: X17 bit: 63 to: neg.
		asm comment: 'left: back again or deoptimize'.
		asm cmp: X17 imm: 62.
		asm b: s if: COND_HI.
		asm lsl: self scratchB with: X16 with: X17.
		asm asr: self scratchA with: self scratchB with: X17.
		asm cmp: self scratchA with: X16.
		asm b: s if: COND_NE.
		asm b: done.
		asm bind: neg.
		asm neg: X17 with: X17.
		asm mov: self scratchA imm: 63.
		asm cmp: X17 with: self scratchA.
		asm csel: X17 with: X17 with: self scratchA cond: COND_LS.
		asm asr: self scratchB with: X16 with: X17.
		asm bind: done.
		asm adds: self scratchB with: self scratchB with: self scratchB.
		asm b: s if: COND_VS.
		asm orr: self scratchB with: self scratchB imm: 1.
		^self def: n from: self scratchB].
	asm cbz: X17 to: s.
	(op = O_IMOD and: [nd aux = 0]) ifTrue: [
		"a hashed collection's capacity, a ring buffer's size: a positive power of two masks"
		general := asm newLabel.
		asm comment: 'modulo a power of two: a mask'.
		asm tbnz: X17 bit: 63 to: general.
		asm sub: self scratchB with: X17 imm: 1.
		asm tst: X17 with: self scratchB.
		asm b: general if: COND_NE.
		asm and: self scratchA with: X16 with: self scratchB.
		asm b: done.
		asm bind: general].
	asm sdiv: self scratchB with: X16 with: X17.
	asm msub: self scratchA with: self scratchB with: X17 sub: X16.
	self emitDivTail: n done: done floored: false
!
emitDivTail: n done: done floored: floored
	"After the division of x16 by x17: the truncated quotient in scratchB, the remainder in scratchA (floored: the floored ones); exact, floored, the result tagged."
	| nd s op |
	nd := ir node: n.
	op := nd op asInt32.
	s := self deoptLabelFor: n.
	floored ifFalse: [
		nd aux = 2 ifTrue: [
			asm comment: 'exact: a remainder deoptimizes (the interpreter makes the Fraction)'.
			asm cbnz: self scratchA to: s].
		nd aux >= 1 ifTrue: [asm b: done].
		asm comment: 'floored: a remainder of the divisor''s other sign moves'.
		asm cbz: self scratchA to: done.
		asm eor: X16 with: self scratchA with: X17.
		asm tbz: X16 bit: 63 to: done.
		op = O_IMOD
			ifTrue: [asm add: self scratchA with: self scratchA with: X17]
			ifFalse: [asm sub: self scratchB with: self scratchB imm: 1]].
	asm bind: done.
	op = O_IMOD
		ifTrue: [
			asm add: self scratchA with: self scratchA with: self scratchA.
			asm orr: self scratchB with: self scratchA imm: 1]
		ifFalse: [
			asm adds: self scratchB with: self scratchB with: self scratchB.
			asm b: s if: COND_VS.
			asm orr: self scratchB with: self scratchB imm: 1].
	self def: n from: self scratchB
!
constantDivisorOf: n
	"The divisor of modulo or division n if it is a SmallInteger constant, else 0."
	| b |
	(ir node: n) op asInt32 = O_ISHIFT ifTrue: [^0].
	b := ir node: (ir node: n) b.
	(b op asInt32 = O_CONST and: [self isInt: b aux asUInt64]) ifFalse: [^0].
	^self intVal: b aux asUInt64
!
emitDivBy: d node: n
	"x16 by the constant d (not 0) without a division: the truncated quotient into scratchB, the remainder into scratchA and x17 := d; answer false. Floored by a power of two: the floored ones, and answer true. By 2^k with shifts; else multiplying by a magic number and shifting (Hacker's Delight, 10-1)."
	| q r k ad m sh |
	q := self scratchB.
	r := self scratchA.
	asm comment: 'division by the constant %d' with: d.
	(d = 1 or: [d = -1]) ifTrue: [
		d = 1 ifTrue: [asm mov: q with: X16] ifFalse: [asm neg: q with: X16].
		asm mov: r imm: 0.
		asm mov: X17 imm: d.
		^false].
	ad := d < 0 ifTrue: [0 - d] ifFalse: [d].
	(d > 0 and: [(ad bitAnd: ad - 1) = 0]) ifTrue: [
		k := 0.
		[(1 asInt64 << k) < ad] whileTrue: [k := k + 1].
		(ir node: n) aux = 0 ifTrue: [
			asm asr: q with: X16 imm: k.
			asm and: r with: X16 imm: ad - 1.
			^true].
		asm asr: q with: X16 imm: 63.
		asm add: q with: X16 with: q shift: SHIFT_LSR amount: 64 - k.
		asm asr: q with: q imm: k.
		asm sub: r with: X16 with: q shift: SHIFT_LSL amount: k.
		asm mov: X17 imm: d.
		^false].
	sh := self local: 'int64_t'.
	m := self magic: d shift: sh.
	asm mov: X17 imm: m.
	asm smulh: q with: X16 with: X17.
	(d > 0 and: [m < 0]) ifTrue: [asm add: q with: q with: X16].
	(d < 0 and: [m > 0]) ifTrue: [asm sub: q with: q with: X16].
	sh value > 0 ifTrue: [asm asr: q with: q imm: sh value].
	asm add: q with: q with: q shift: SHIFT_LSR amount: 63.
	asm mov: X17 imm: d.
	asm msub: r with: q with: X17 sub: X16.
	^false
!
magic: d shift: sh
	"The magic number of signed 64-bit division by the constant d (|d| >= 2), its shift into sh: Hacker's Delight, 10-1."
	<function>
	<var: #d type: 'int64_t'>
	<var: #sh type: 'int64_t *'>
	<returns: 'int64_t'>
	| ad t anc p q1 r1 q2 r2 delta two63 m |
	<var: #ad type: 'uint64_t'>
	<var: #t type: 'uint64_t'>
	<var: #anc type: 'uint64_t'>
	<var: #q1 type: 'uint64_t'>
	<var: #r1 type: 'uint64_t'>
	<var: #q2 type: 'uint64_t'>
	<var: #r2 type: 'uint64_t'>
	<var: #delta type: 'uint64_t'>
	<var: #two63 type: 'uint64_t'>
	<var: #m type: 'uint64_t'>
	two63 := 1 asUInt64 << 63.
	ad := d < 0 ifTrue: [(0 - d) asUInt64] ifFalse: [d asUInt64].
	t := two63 + (d asUInt64 >> 63).
	anc := t - 1 - (t rem: ad).
	p := 63.
	q1 := two63 quo: anc.
	r1 := two63 - (q1 * anc).
	q2 := two63 quo: ad.
	r2 := two63 - (q2 * ad).
	[p := p + 1.
	q1 := q1 * 2.
	r1 := r1 * 2.
	r1 >= anc ifTrue: [
		q1 := q1 + 1.
		r1 := r1 - anc].
	q2 := q2 * 2.
	r2 := r2 * 2.
	r2 >= ad ifTrue: [
		q2 := q2 + 1.
		r2 := r2 - ad].
	delta := ad - r2.
	q1 < delta or: [q1 = delta and: [r1 = 0]]] whileTrue.
	sh value: p - 64.
	m := q2 + 1.
	^(d < 0 ifTrue: [0 asUInt64 - m] ifFalse: [m]) asInt64
!
emitMul: n
	| nd x y s |
	nd := ir node: n.
	s := self deoptLabelFor: n.
	x := self src: nd a into: self scratchA.
	y := self src: nd b into: self scratchB.
	asm asr: X16 with: x imm: 1.
	asm sub: X17 with: y imm: 1.
	asm isX64
		ifTrue: [
			asm muls: self scratchB with: X16 with: X17.
			asm b: s if: COND_VS]
		ifFalse: [
			asm mul: self scratchB with: X16 with: X17.
			asm smulh: X16 with: X16 with: X17.
			asm cmp: X16 with: self scratchB shift: SHIFT_ASR amount: 63.
			asm b: s if: COND_NE].
	asm orr: X16 with: self scratchB imm: 1.
	self def: n from: X16
!
emitClassOf: n
	| nd x r imm done ch back fwd |
	nd := ir node: n.
	x := self src: nd a into: self scratchB.
	r := self dst: n.
	imm := asm newLabel.
	done := asm newLabel.
	ch := asm newLabel.
	back := asm newLabel.
	fwd := self out: OUT_FOLLOW node: n index: (x bitOr: 255 << 8).
	(cgOuts + (cgOutCount - 1)) resume: back.
	asm bind: back.
	asm ands: X16 with: x imm: 7.
	asm b: imm if: COND_NE.
	asm comment: 'a forwarder''s class word is tagged: follow it (out of line)'.
	asm ldr: X17 base: x offset: 8.
	asm tst: X17 imm: 7.
	asm b: fwd if: COND_NE.
	asm mov: r with: X17.
	asm b: done.
	asm bind: imm.
	asm tst: x imm: 1.
	asm b: ch if: COND_EQ.
	self loadConstant: memory clsSmallint into: r.
	asm b: done.
	asm bind: ch.
	asm cmp: X16 imm: 2.
	self loadConstant: memory clsChar into: X17.
	self loadConstant: memory clsSmallfloat into: r.
	asm csel: r with: X17 with: r cond: COND_EQ.
	asm bind: done.
	self def: n from: r
!
emitStore: n
	"Store b into a's field; the generational barrier's tests inline, the remembering out of line. A frame state: deoptimize if a is immutable."
	| nd o v s |
	nd := ir node: n.
	nd state >= 0 ifTrue: [s := self deoptLabelFor: n].
	o := self src: nd a into: self scratchA.
	v := self src: nd b into: self scratchB.
	nd state >= 0 ifTrue: [
		asm comment: 'immutable: the interpreter sends attemptToAssign:withIndex:'.
		asm ldr: X16 base: o offset: 0.
		asm tst: X16 imm: H_IMMUTABLE.
		asm b: s if: COND_NE].
	asm str: v base: o offset: (self fieldOffset: nd aux).
	self emitBarrier: n object: o value: v
!
emitBarrier: n object: o value: v
	"After storing n's value v into object o: the generational barrier (o and v not in X16, X17)."
	| done slow check nd |
	nd := ir node: n.
	(ir node: nd b) op asInt32 = O_CONST ifTrue: [
		(((ir node: nd b) aux bitAnd: 7) ~= 0 or: [(self isYoung: (ir node: nd b) aux asUInt64) not]) ifTrue: [^self]].
	"immediates, Booleans, nil: never young"
	((ir node: nd b) tkind asInt32 between: T_SMI and: T_NIL) ifTrue: [^self].
	(ir node: nd b) tkind asInt32 = T_CHAR ifTrue: [^self].
	done := asm newLabel.
	check := asm newLabel.
	slow := self out: OUT_BARRIER node: n index: (o bitOr: v << 8).
	(cgOuts + (cgOutCount - 1)) resume: done.
	asm comment: 'store barrier: an immediate, an old value, a young object or a remembered one need nothing'.
	asm tst: v imm: 7.
	asm b: done if: COND_NE.
	asm ldr: X16 base: X22 offset: self youngLoOffset.
	asm cmp: v with: X16.
	asm b: done if: COND_LO.
	asm ldr: X17 base: X22 offset: self youngHiOffset.
	asm cmp: v with: X17.
	asm b: done if: COND_HS.
	asm cmp: o with: X16.
	asm b: check if: COND_LO.
	asm cmp: o with: X17.
	asm b: done if: COND_LO.
	asm bind: check.
	asm ldr: X16 base: o offset: 0.
	asm tst: X16 imm: H_REMEMBERED.
	asm b: slow if: COND_EQ.
	asm bind: done
!
emitOuterTemp: n
	"A temp of the Context lv levels out of the unit's closure: in the frame it is married to (sender: the frame's index), else in it."
	| nd v x married done r |
	nd := ir node: n.
	nd op asInt32 = O_OUTERSTORE ifTrue: [v := self src: nd b into: self scratchA].
	nd c >= 0 ifTrue: [^self emitOuterTemp: n value: v].
	x := self src: nd a into: self scratchB.
	asm comment: 'outer temp %d' with: nd aux2.
	asm ldr: self scratchB base: x offset: (self fieldOffset: BC_OUTER).
	2 to: nd aux asInt32 do: [:k |
		asm ldr: X17 base: self scratchB offset: (self fieldOffset: CTX_CLOSURE).
		asm ldr: self scratchB base: X17 offset: (self fieldOffset: BC_OUTER)].
	asm ldr: X17 base: self scratchB offset: (self fieldOffset: CTX_SENDER).
	married := asm newLabel.
	done := asm newLabel.
	asm tbnz: X17 bit: 0 to: married.
	nd op asInt32 = O_OUTERLOAD
		ifTrue: [
			r := self dst: n.
			asm ldr: r base: self scratchB offset: (self fieldOffset: CTX_FIXED + nd aux2).
			asm b: done.
			asm bind: married.
			asm ldr: X16 base: X22 offset: self framesOffset.
			asm asr: X17 with: X17 imm: 1.
			asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: 6.
			asm ldr: X16 base: X16 offset: self fpOffset.
			asm ldr: r base: X16 offset: 8 * nd aux2.
			asm bind: done.
			^self def: n from: r].
	asm str: v base: self scratchB offset: (self fieldOffset: CTX_FIXED + nd aux2).
	self emitBarrier: n object: self scratchB value: v.
	asm b: done.
	asm bind: married.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm asr: X17 with: X17 imm: 1.
	asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: 6.
	asm ldr: X16 base: X16 offset: self fpOffset.
	asm str: v base: X16 offset: 8 * nd aux2.
	asm bind: done
!
emitOuterTemp: n value: v
	"emitOuterTemp: for one whose loop found where its Context's frame is, if any (O_OUTERSLOT, n's operand c): there, or in the Context."
	| nd x married done r |
	nd := ir node: n.
	married := asm newLabel.
	done := asm newLabel.
	asm comment: 'outer temp %d: in the frame found before the loop, if any' with: nd aux2.
	x := self src: nd c into: self scratchB.
	nd op asInt32 = O_OUTERLOAD ifTrue: [r := self dst: n].
	asm cmp: x imm: 1.
	asm b: married if: COND_NE.
	asm ldr: self scratchB base: (self src: nd a into: self scratchB) offset: (self fieldOffset: BC_OUTER).
	2 to: nd aux asInt32 do: [:k |
		asm ldr: X17 base: self scratchB offset: (self fieldOffset: CTX_CLOSURE).
		asm ldr: self scratchB base: X17 offset: (self fieldOffset: BC_OUTER)].
	nd op asInt32 = O_OUTERLOAD
		ifTrue: [asm ldr: r base: self scratchB offset: (self fieldOffset: CTX_FIXED + nd aux2)]
		ifFalse: [
			asm str: v base: self scratchB offset: (self fieldOffset: CTX_FIXED + nd aux2).
			self emitBarrier: n object: self scratchB value: v].
	asm b: done.
	asm bind: married.
	asm sub: X16 with: x imm: 1.
	nd op asInt32 = O_OUTERLOAD
		ifTrue: [asm ldr: r base: X16 offset: 8 * nd aux2]
		ifFalse: [asm str: v base: X16 offset: 8 * nd aux2].
	asm bind: done.
	nd op asInt32 = O_OUTERLOAD ifTrue: [self def: n from: r]
!
emitOuterSlot: n
	"Where the slots are of the frame that the Context aux levels out of closure a is married to, plus 1 (emitOuterTemp:'s walk, once for a loop); the SmallInteger 0 if it is married to none."
	| nd married done r |
	nd := ir node: n.
	married := asm newLabel.
	done := asm newLabel.
	asm comment: 'the frame of its outer temps, if any, once before the loop'.
	asm ldr: self scratchB base: (self src: nd a into: self scratchB) offset: (self fieldOffset: BC_OUTER).
	2 to: nd aux asInt32 do: [:k |
		asm ldr: X17 base: self scratchB offset: (self fieldOffset: CTX_CLOSURE).
		asm ldr: self scratchB base: X17 offset: (self fieldOffset: BC_OUTER)].
	asm ldr: X17 base: self scratchB offset: (self fieldOffset: CTX_SENDER).
	r := self dst: n.
	asm tbnz: X17 bit: 0 to: married.
	asm mov: r imm: 1.
	asm b: done.
	asm bind: married.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm asr: X17 with: X17 imm: 1.
	asm add: X16 with: X16 with: X17 shift: SHIFT_LSL amount: 6.
	asm ldr: X16 base: X16 offset: self fpOffset.
	asm add: r with: X16 imm: 1.
	asm bind: done.
	self def: n from: r
!
emitReturn: n
	| nd x s back w |
	nd := ir node: n.
	x := self src: nd a into: self scratchA.
	asm comment: 'the bottom frame returns into a Context: the interpreter does it'.
	s := self out: OUT_BOTTOM node: n index: 0.
	asm ldr: X16 base: X22 offset: self framesOffset.
	asm cmp: X19 with: X16.
	asm b: s if: COND_EQ.
	asm comment: 'the result in x0, pop the frame, return'.
	x ~= X0 ifTrue: [asm mov: X0 with: x].
	builder entryPc > (ir act: cgRootAct) startpc ifTrue: [
		"a loop's unit: the frame may be married (no block refers to its Context)"
		back := asm newLabel.
		w := self out: OUT_WIDOW node: n index: 0.
		(cgOuts + (cgOutCount - 1)) resume: back.
		asm ldr: X16 base: X19 offset: self ctxOffset.
		asm cmp: X16 with: X23.
		asm b: w if: COND_NE.
		asm bind: back].
	asm sub: X19 with: X19 imm: self frameBytes.
	asm ldp: X29 with: X30 base: SP postIndex: 16.
	asm ret
!
emitCheckInterrupt: n
	| s back |
	back := asm newLabel.
	s := self out: OUT_INTERRUPT node: n index: 0.
	(cgOuts + (cgOutCount - 1)) resume: back.
	asm comment: 'interrupt check'.
	self emitInterruptTestTo: s.
	self emitStressAt: n label: s.
	asm bind: back
!
emitStressAt: n label: l
	"--jit-flags deopt: every so often take the slow path anyway."
	(runtime flag: runtime deoptFlag) ifFalse: [^self].
	asm comment: 'deoptimization stress'.
	asm ldr: X16 base: X22 offset: self stressOffset.
	asm subs: X16 with: X16 imm: 1.
	asm str: X16 base: X22 offset: self stressOffset.
	asm b: l if: COND_EQ
!
emitSend: n
	"A call as baseline code makes it: receiver and arguments at slotTop, the receiver in x0, x20 the callee's fp, then bl to a known method's unchecked entry (O_CALL: its primitive's machine code, or its frame and body; optimized code through the redirection), to the block stub (NF_BLOCKCALL: a closure with as many arguments), or to an inline cache's target (the miss stub until JitBaselineRuntime links it; what that cannot link the runtime sends, OptRuntime>>sendFrom:ret:). The result comes back in x0."
	| nd argc k r off back cont done slow lazy |
	nd := ir node: n.
	argc := nd nargs asInt32 - 1.
	k := self recordCall: n.
	done := asm newLabel.
	(nd flags bitAnd: NF_ALLOC) ~= 0 ifTrue: [
		slow := asm newLabel.
		self emitAllocate: n slow: slow done: done.
		asm bind: slow].
	(nd flags bitAnd: NF_REPLACE) ~= 0 ifTrue: [
		slow := asm newLabel.
		self emitReplace: n slow: slow done: done.
		asm bind: slow].
	self saveAcross: n.
	asm comment: 'receiver and arguments'.
	0 to: argc do: [:i |
		r := self src: (ir operand: nd args + i) into: self scratchA.
		asm str: r base: X20 offset: 8 * (cgSlotTop + i)].
	r := self src: (ir operand: nd args) into: X0.
	r ~= X0 ifTrue: [asm mov: X0 with: r].
	off := 8 * (cgSlotTop + 1).
	asm comment: 'x20 := the callee''s fp'.
	self addFp: off.
	back := asm newLabel.
	nd op asInt32 = O_CALL
		ifTrue: [
			asm comment: 'call its unchecked entry'.
			asm bl: (asm labelAt: (runtime lookup: nd tcls) uentry)]
		ifFalse: [
			(nd flags bitAnd: NF_BLOCKCALL) ~= 0
				ifTrue: [
					slow := self out: OUT_SITE node: n index: k.
					(cgOuts + (cgOutCount - 1)) resume: back.
					asm comment: 'a closure with as many arguments: the block stub enters its code'.
					asm ldr: X16 base: X0 offset: (self fieldOffset: BC_NUMARGS).
					asm cmp: X16 imm: (self intOop: argc) asInt64.
					asm b: slow if: COND_NE.
					asm bl: (asm labelAt: stubs blBlockStub)]
				ifFalse: [self emitSiteCall: n index: k]].
	self noteRet: k argc: argc.
	asm bind: back.
	self subFp: off.
	cont := asm newLabel.
	asm bind: cont.
	slow := self out: OUT_RESUME node: n index: k.
	(cgOuts + (cgOutCount - 1)) resume: cont.
	lazy := self out: OUT_LAZY node: n index: k.
	asm comment: 'invalidated meanwhile: deoptimize'.
	asm adr: X16 label: cgHeaderLabel.
	asm ldr: W16 base: X16 offset: self headerFlagsOffset.
	asm tst: W16 imm: 2.
	asm b: lazy if: COND_NE.
	self emitStressAt: n label: lazy.
	(nd flags bitAnd: NF_ALLOC) ~= 0 ifTrue: [
		asm comment: 'an instance of the class it makes (its primitive''s fallback may answer anything: deoptimize, and the site sends from then on)'.
		lazy := self out: OUT_NOTMADE node: n index: k.
		asm tst: X0 imm: 7.
		asm b: lazy if: COND_NE.
		asm ldr: X16 base: X0 offset: 8.
		self loadConstant: nd tcls into: X17.
		asm cmp: X16 with: X17.
		asm b: lazy if: COND_NE.
		"the allocation's slow path: an interrupt it requested (an allocation sample) is taken after it, as the runtime's send would"
		cont := asm newLabel.
		slow := self out: OUT_SENT node: n index: k.
		(cgOuts + (cgOutCount - 1)) resume: cont.
		asm comment: 'interrupt check (an allocation sample)'.
		self emitInterruptTestTo: slow.
		asm bind: cont].
	asm comment: 'the result (x0)'.
	self def: n from: X0.
	self reloadAcross: n.
	"only the fast paths jump here (a label resets what registers are known to hold)"
	(nd flags bitAnd: (NF_ALLOC bitOr: NF_REPLACE)) ~= 0 ifTrue: [asm bind: done]
!
emitSiteCall: n index: k
	"An inline cache: x9 its class (megamorphic: the selector) from its literal, bl to its target, the miss stub while unlinked."
	| lit |
	lit := asm newLabel.
	asm comment: 'x9 := inline cache %d''s class' with: cgSiteCount.
	asm ldr: X9 label: lit.
	self noteSite: n index: k literal: lit.
	asm comment: 'call the inline cache''s target (the miss stub while unlinked)'.
	asm bl: (asm labelAt: stubs blMissStub)
!
noteSite: n index: k literal: lit
	"The inline cache whose bl is next (JitBaselineRuntime links it): its info as baseline code's (argc | kind << 24), its safepoint, its selector's pool index."
	| nd |
	nd := ir node: n.
	cgSiteCount >= CG_MAX_SITES ifTrue: [^asm fail: ASM_ERR_FULL].
	asm isX64
		ifTrue: [cgSiteBl at: cgSiteCount put: (asm pc + 1 - cgCodeStart) asUInt32]
		ifFalse: [cgSiteBl at: cgSiteCount put: (asm pc - cgCodeStart) asUInt32].
	cgSiteLit at: cgSiteCount put: lit.
	cgSiteInfo at: cgSiteCount put: ((nd aux2 bitAnd: 255) bitOr: ((nd aux2 >> 8) bitAnd: 3) << 24) asUInt32.
	cgSiteIndex at: cgSiteCount put: k.
	cgSiteSel at: cgSiteCount put: (self poolIndexOf: nd aux asUInt64).
	cgSiteCount := cgSiteCount + 1
!
noteRet: k argc: n
	"The return address just emitted (after a bl): a frame suspended there is at safepoint k, its receiver and n arguments at slotTop (JitBaselineRuntime>>setTop:ret:mode:, canonicalizeBelow:)."
	cgRetCount >= CG_MAX_RETS ifTrue: [^asm fail: ASM_ERR_FULL].
	cgRetOff at: cgRetCount put: (asm pc - cgCodeStart) asUInt32.
	cgRetIndex at: cgRetCount put: k.
	cgRetArgc at: cgRetCount put: n.
	cgRetCount := cgRetCount + 1
!
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
emitReplace: n slow: slow done: done
	"replaceFrom:to:with:startingAt: (NF_REPLACE: the receiver's elements bytes, NF_W32 32-bit words, NF_PTRS pointers) as its primitive does it (JitBaselineCompiler>>emitReplacePrimitive:), in x16, x17 and the scratch registers, its arguments read again where needed: the copy stub, the receiver the result; anything else the call (slow)."
	| nd s args d e young old skip r fail fused |
	fused := self isFusedReplace: n.
	fail := fused ifTrue: [asm newLabel] ifFalse: [slow].
	nd := ir node: n.
	s := (nd flags bitAnd: NF_PTRS) ~= 0 ifTrue: [3] ifFalse: [(nd flags bitAnd: NF_W32) ~= 0 ifTrue: [2] ifFalse: [0]].
	args := nd args.
	asm comment: 'replaceFrom:to:with:startingAt: stop (x17), start - 1 (x16): not below 0, stop not below it'.
	self untag: (ir operand: args + 2) into: X17 slow: fail.
	self untag: (ir operand: args + 1) into: X16 slow: fail.
	asm subs: X16 with: X16 imm: 1.
	asm b: fail if: COND_LT.
	asm cmp: X17 with: X16.
	asm b: fail if: COND_LT.
	asm comment: 'the receiver: of its kind, not immutable, stop within it'.
	d := self src: (ir operand: args) into: self scratchA.
	asm ldr: self scratchB base: d offset: 0.
	asm tst: self scratchB imm: H_IMMUTABLE.
	asm b: fail if: COND_NE.
	asm ubfx: X16 with: self scratchB lsb: H_FMT_SHIFT width: 5.
	self emitKindCheck: X16 shift: s slow: fail.
	s = 3 ifTrue: [
		asm comment: 'young or remembered'.
		young := asm newLabel.
		old := asm newLabel.
		asm ldr: X16 base: X22 offset: self youngLoOffset.
		asm cmp: d with: X16.
		asm b: old if: COND_LO.
		asm ldr: X16 base: X22 offset: self youngHiOffset.
		asm cmp: d with: X16.
		asm b: young if: COND_LO.
		asm bind: old.
		asm tst: self scratchB imm: H_REMEMBERED.
		asm b: fail if: COND_EQ.
		asm bind: young].
	self emitElementsOf: d shift: s into: self scratchB temp: X16.
	asm cmp: X17 with: self scratchB.
	asm b: fail if: COND_GT.
	asm comment: 'the replacement: an object of the receiver''s kind; its start - 1 (x16) not below 0, n from it within it'.
	e := self src: (ir operand: args + 3) into: self scratchB.
	asm tst: e imm: 7.
	asm b: fail if: COND_NE.
	asm ldr: X17 base: e offset: 0.
	asm ubfx: X17 with: X17 lsb: H_FMT_SHIFT width: 5.
	self emitKindCheck: X17 shift: s slow: fail.
	self emitElementsOf: e shift: s into: X17 temp: X16.
	self untag: (ir operand: args + 4) into: X16 slow: fail.
	asm subs: X16 with: X16 imm: 1.
	asm b: fail if: COND_LT.
	asm sub: X17 with: X17 with: X16.
	self untag: (ir operand: args + 2) into: X16 slow: fail.
	asm sub: X17 with: X17 with: X16.
	self untag: (ir operand: args + 1) into: X16 slow: fail.
	asm add: X17 with: X17 with: X16.
	asm subs: X17 with: X17 imm: 1.
	asm b: fail if: COND_LT.
	asm comment: 'the copy stub: x16 the receiver''s elements from start, x17 the replacement''s from its start, n << %d bytes' with: s.
	skip := asm newLabel.
	self untag: (ir operand: args + 4) into: X17 slow: fail.
	asm add: X17 with: e with: X17 shift: SHIFT_LSL amount: s.
	asm add: X17 with: X17 imm: 16 - (1 << s).
	self untag: (ir operand: args + 2) into: self scratchB slow: fail.
	self untag: (ir operand: args + 1) into: X16 slow: fail.
	asm sub: self scratchB with: self scratchB with: X16.
	asm adds: self scratchB with: self scratchB imm: 1.
	d := self src: (ir operand: args) into: self scratchA.
	asm add: X16 with: d with: X16 shift: SHIFT_LSL amount: s.
	asm add: X16 with: X16 imm: 16 - (1 << s).
	asm cbz: self scratchB to: skip.
	s = 0
		ifTrue: [asm mov: stubs copyCountRegister with: self scratchB]
		ifFalse: [asm lsl: stubs copyCountRegister with: self scratchB imm: s].
	asm bl: (asm labelAt: stubs blCopyStub).
	self reloadDoublesAcross: n.
	asm bind: skip.
	asm comment: 'the receiver the result'.
	r := self dst: n.
	d := self src: (ir operand: args) into: r.
	d ~= r ifTrue: [asm mov: r with: d].
	self def: n from: r.
	asm b: done.
	fused ifTrue: [
		asm bind: fail.
		asm comment: 'the receiver, just allocated: its elements zeroed before the call'.
		d := self src: (ir operand: args) into: X16.
		d ~= X16 ifTrue: [asm mov: X16 with: d].
		asm ldr: (self scratchB bitOr: REG_W) base: X16 offset: 0.
		asm mov: X17 imm: 0.
		self emitZeroSlotsOf: X16 from: X17 count: self scratchB]
!
emitString: n
	"String>>hash (O_STRHASH) or compareWith: (O_STRCMP) of bytes: compareWith:'s argument checked to be bytes (NF_GUARD: else deoptimize), then the string hash, compare or, where only = 0 uses it (NF_EQONLY), equal stub (x16 the receiver, x17 the argument, the result in x16)."
	| nd s x |
	nd := ir node: n.
	(nd flags bitAnd: NF_GUARD) ~= 0 ifTrue: [
		s := self deoptLabelFor: n.
		asm comment: 'guard: the argument is bytes'.
		x := self src: nd b into: X17.
		asm tst: x imm: 7.
		asm b: s if: COND_NE.
		asm ldr: X16 base: x offset: 0.
		asm ubfx: X16 with: X16 lsb: H_FMT_SHIFT width: 5.
		self emitKindCheck: X16 shift: 0 slow: s].
	x := self src: nd a into: X16.
	x ~= X16 ifTrue: [asm mov: X16 with: x].
	nd op asInt32 = O_STRHASH
		ifTrue: [
			asm comment: 'String>>hash of bytes: the string hash stub'.
			asm bl: (asm labelAt: stubs blStringHashStub)]
		ifFalse: [
			x := self src: nd b into: X17.
			x ~= X17 ifTrue: [asm mov: X17 with: x].
			(nd flags bitAnd: NF_EQONLY) ~= 0
				ifTrue: [
					asm comment: 'compareWith: of bytes, only = 0 used: the string equal stub'.
					asm bl: (asm labelAt: stubs blStringEqualStub)]
				ifFalse: [
					asm comment: 'compareWith: of bytes: the string compare stub'.
					asm bl: (asm labelAt: stubs blStringCompareStub)]].
	self def: n from: X16
!
emitKindCheck: f shift: s slow: slow
	"Unless format f is one of elements of 1 << s bytes (bytes, 32-bit words, pointers without fixed fields): slow."
	s = 0 ifTrue: [
		asm cmp: f imm: F_BYTES.
		^asm b: slow if: COND_LO].
	s = 2 ifTrue: [
		asm cmp: f imm: F_W32.
		asm b: slow if: COND_LO.
		asm cmp: f imm: F_W32 + 1.
		^asm b: slow if: COND_HI].
	asm cmp: f imm: F_VAR.
	asm b: slow if: COND_NE
!
untag: v into: r slow: slow
	"r := the value of v, a SmallInteger; anything else: slow."
	| nd x |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [
		(self isInt: nd aux asUInt64) ifFalse: [^asm b: slow].
		^asm mov: r imm: (self intVal: nd aux asUInt64)].
	x := self src: v into: r.
	nd tkind asInt32 = T_SMI ifFalse: [asm tbz: x bit: 0 to: slow].
	asm asr: r with: x imm: 1
!
emitElementsOf: x shift: s into: r temp: t
	"r := the elements of x, an object of 1 << s byte elements (bytes and 32-bit words: less the format's unused ones)."
	asm ldr: (r bitOr: REG_W) base: x offset: 0.
	s = 3 ifTrue: [^self].
	asm lsl: r with: r imm: 3 - s.
	asm ldrb: (t bitOr: REG_W) base: x offset: 4.
	asm and: t with: t imm: (s = 0 ifTrue: [7] ifFalse: [1]).
	asm sub: r with: r with: t
!
fusedReplaceOf: n
	"The replaceFrom: 1 to: stop with:startingAt: (NF_REPLACE) of allocation n's elements (bytes or 32-bit words) that writes them before anything can see them, -1 if there is none: up to it no node deoptimizes, calls or uses n but for its size, through jumps into blocks only that way reaches and a branch on stop > 0 (else it has nothing to write), stop is n's size or defined before n, and so is the replacement (isBefore:node:: then it is another object, not n with its unwritten elements). n leaves elements from stop on zeroed only, the call the others if its fast path fails (emitFill:upTo:)."
	<function>
	| nd fmt x b t c xd stop r rd tested |
	tested := -1.
	nd := ir node: n.
	fmt := (nd c bitAnd: 255) asInt32.
	(fmt = F_BYTES or: [fmt = F_W32]) ifFalse: [^-1].
	nd nargs asInt32 = 2 ifFalse: [^-1].
	b := nd block.
	x := nd next.
	[true] whileTrue: [
		x < 0 ifTrue: [^-1].
		xd := ir node: x.
		((xd op asInt32 = O_CALL or: [xd op asInt32 = O_SEND]) and: [(xd flags bitAnd: NF_REPLACE) ~= 0 and: [(ir resolve: (ir operand: xd args)) = n]]) ifTrue: [
			r := x.
			rd := xd.
			((rd flags bitAnd: NF_PTRS) ~= 0 or: [((rd flags bitAnd: NF_W32) ~= 0) ~= (fmt = F_W32)]) ifTrue: [^-1].
			(self isConstant: (ir operand: rd args + 1) value: 1) ifFalse: [^-1].
			stop := self baseValueOf: (ir operand: rd args + 2).
			(tested < 0 or: [tested = stop]) ifFalse: [^-1].
			(stop = (self baseValueOf: (ir operand: nd args + 1)) or: [self isBefore: stop node: n]) ifFalse: [^-1].
			(self isBefore: (self baseValueOf: (ir operand: rd args + 3)) node: n) ifFalse: [^-1].
			^r].
		xd op asInt32 = O_GOTO ifTrue: [
			b := (ir block: b) succ0.
			(ir block: b) npreds = 1 ifFalse: [^-1].
			x := (ir block: b) first]
		ifFalse: [
			xd op asInt32 = O_BRANCH
				ifTrue: [
					t := (ir block: b) succ0.
					((ir block: t) npreds = 1 and: [tested < 0 and: [self isPositiveTest: xd a]]) ifFalse: [^-1].
					tested := self baseValueOf: (ir node: (ir resolve: xd a)) a.
					b := t.
					x := (ir block: b) first]
				ifFalse: [
					(self isQuiet: x for: n) ifFalse: [^-1].
					x := xd next]]].
	^-1
!
isBefore: v node: n
	"Value v (past guards and casts: baseValueOf:) is a constant or defined before node n, which it dominates as both are operands of what follows n: it existed before n ran, so if n allocates, v is another object."
	| vd |
	vd := ir node: v.
	^vd op asInt32 = O_CONST or: [vd pos < (ir node: n) pos]
!
isFusedReplace: n
	"Replace n writes the elements of the allocation that is its receiver before anything sees them (fusedReplaceOf:): the allocation zeroed only the rest."
	| a ad |
	a := ir resolve: (ir operand: (ir node: n) args).
	ad := ir node: a.
	((ad op asInt32 = O_CALL or: [ad op asInt32 = O_SEND]) and: [(ad flags bitAnd: NF_ALLOC) ~= 0]) ifFalse: [^false].
	^(self fusedReplaceOf: a) = n
!
isQuiet: x for: n
	"Node x neither deoptimizes, calls, stores nor uses n but for its size."
	| xd op |
	xd := ir node: x.
	op := xd op asInt32.
	xd state >= 0 ifTrue: [^false].
	(op = O_CONST or: [op = O_PHI or: [op = O_IADD or: [op = O_ISUB or: [op = O_ICMP or: [op = O_EQ or: [op = O_NE or: [op = O_SIZE or: [op = O_LOADFIELD or: [op = O_CAST or: [op = O_GUARDINT or: [op = O_HOMESLOT or: [op = O_PARAM or: [op = O_LOADSLOT]]]]]]]]]]]]]) ifFalse: [^false].
	op = O_SIZE ifTrue: [^true].
	op = O_PHI ifTrue: [
		0 to: xd nargs asInt32 - 1 do: [:i | (ir resolve: (ir operand: xd args + i)) = n ifTrue: [^false]].
		^true].
	^(ir resolve: xd a) ~= n and: [(ir resolve: xd b) ~= n]
!
isPositiveTest: t
	"t (a branch's condition) is x > 0 or x >= 1 (x the stop of the replace on its true side)."
	| td |
	td := ir node: (ir resolve: t).
	td op asInt32 = O_ICMP ifFalse: [^false].
	^(td aux = 3 and: [self isConstant: td b value: 0]) or: [td aux = 5 and: [self isConstant: td b value: 1]]
!
isConstant: v value: i
	"v is the SmallInteger i."
	| nd |
	nd := ir node: (ir resolve: v).
	^nd op asInt32 = O_CONST and: [nd aux asUInt64 = (self intOop: i)]
!
baseValueOf: v
	"v, past guards and casts."
	| r |
	r := ir resolve: v.
	[(ir node: r) op asInt32 = O_GUARDINT or: [(ir node: r) op asInt32 = O_CAST]] whileTrue: [r := ir resolve: (ir node: r) a].
	^r
!
emitAllocate: n slow: slow done: done
	"basicNew(:) in eden: header (slots, format, a hash from the JitState's seed), class, nil fields (bytes and 32-bit words zeroed, their slots and format from the size); no room, the sample's limit or more than 4096 slots: the send (slow)."
	| nd fmt isize k e sz r loop fill even v shift max fused |
	nd := ir node: n.
	fmt := (nd c bitAnd: 255) asInt32.
	isize := (nd c >> 8) asInt32.
	"elements per slot: 8 bytes, 2 words, a pointer"
	shift := fmt = F_BYTES ifTrue: [3] ifFalse: [fmt = F_W32 ifTrue: [1] ifFalse: [0]].
	max := 4096 << shift.
	k := -1.
	asm comment: 'allocate in eden'.
	nd nargs asInt32 = 1
		ifTrue: [k := isize]
		ifFalse: [
			sz := ir node: (ir operand: nd args + 1).
			(sz op asInt32 = O_CONST and: [(self isInt: sz aux asUInt64) and: [(self intVal: sz aux asUInt64) between: 0 and: max]]) ifTrue: [
				e := (self intVal: sz aux asUInt64) asInt32.
				k := isize + ((e + (1 << shift) - 1) >> shift).
				shift > 0 ifTrue: [fmt := (fmt + ((k << shift) - e)) asInt32]]].
	k >= 0
		ifTrue: [
			asm comment: 'header: slots, format, a hash (the VM''s generator)'.
			asm mov: self scratchB imm: (k asInt64 bitOr: fmt asInt64 << H_FMT_SHIFT)]
		ifFalse: [
			r := self src: (ir operand: nd args + 1) into: self scratchB.
			asm tbz: r bit: 0 to: slow.
			asm asr: self scratchB with: r imm: 1.
			asm cmp: self scratchB imm: max.
			asm b: slow if: COND_HI.
			isize > 0 ifTrue: [asm add: self scratchB with: self scratchB imm: isize].
			shift > 0
				ifTrue: [
					asm comment: 'slots and the format''s unused elements'.
					asm add: X16 with: self scratchB imm: (1 << shift) - 1.
					asm lsr: X16 with: X16 imm: shift.
					asm lsl: X17 with: X16 imm: shift.
					asm sub: X17 with: X17 with: self scratchB.
					asm add: X17 with: X17 imm: fmt.
					asm orr: self scratchB with: X16 with: X17 shift: SHIFT_LSL amount: H_FMT_SHIFT]
				ifFalse: [asm orr: self scratchB with: self scratchB imm: fmt asUInt64 << H_FMT_SHIFT].
			asm comment: 'header: slots, format, a hash (the VM''s generator)'].
	self emitEdenObject: nd tcls slow: slow.
	(shift > 0 and: [(fused := self fusedReplaceOf: n) >= 0]) ifTrue: [
		self emitFill: n upTo: (ir operand: (ir node: fused) args + 2).
		r := self dst: n.
		asm mov: r with: X16.
		self def: n from: r.
		^asm b: done].
	asm comment: (shift = 0 ifTrue: ['fields nil'] ifFalse: ['zeroed']).
	v := shift = 0 ifTrue: [X23] ifFalse: [XZR].
	(k >= 0 and: [k <= 16])
		ifTrue: [0 to: k - 1 do: [:i | asm str: v base: X16 offset: 16 + (8 * i)]]
		ifFalse: [
			loop := asm newLabel.
			fill := asm newLabel.
			even := asm newLabel.
			asm ldr: (self scratchB bitOr: REG_W) base: X16 offset: 0.
			asm add: self scratchA with: X16 imm: 16.
			asm tbz: self scratchB bit: 0 to: even.
			asm str: v base: self scratchA postIndex: 8.
			asm bind: even.
			asm lsr: (self scratchB bitOr: REG_W) with: (self scratchB bitOr: REG_W) imm: 1.
			asm b: fill.
			asm bind: loop.
			asm stp: v with: v base: self scratchA postIndex: 16.
			asm sub: (self scratchB bitOr: REG_W) with: (self scratchB bitOr: REG_W) imm: 1.
			asm bind: fill.
			asm cbnz: (self scratchB bitOr: REG_W) to: loop].
	r := self dst: n.
	asm mov: r with: X16.
	self def: n from: r.
	asm b: done
!
emitEdenObject: cls slow: slow
	"x16 := a new object of class cls in eden, its header the slots and format in scratchB with a hash (the VM's generator); no room, or the allocation sample's limit: slow. Uses scratchA, scratchB, x17."
	asm ldr: X16 base: X22 offset: self hashBoxOffset.
	asm ldr: X17 base: X16 offset: 0.
	asm mov: self scratchA imm: 6364136223846793005.
	asm mul: X17 with: X17 with: self scratchA.
	asm mov: self scratchA imm: 1442695040888963407.
	asm add: X17 with: X17 with: self scratchA.
	asm str: X17 base: X16 offset: 0.
	asm lsr: X17 with: X17 imm: 40.
	asm and: X17 with: X17 imm: H_HASH_MASK.
	asm cmp: X17 imm: 0.
	asm csinc: X17 with: X17 with: XZR cond: COND_NE.
	asm orr: self scratchB with: self scratchB with: X17 shift: SHIFT_LSL amount: H_HASH_SHIFT.
	asm comment: 'room in eden'.
	asm ubfx: self scratchA with: self scratchB lsb: 0 width: 32.
	asm lsl: self scratchA with: self scratchA imm: 3.
	asm add: self scratchA with: self scratchA imm: 16.
	asm adrp: X17 label: (asm labelAt: gc edenBoxAddress).
	asm add: X17 with: X17 imm: (gc edenBoxAddress bitAnd: 16rFFF) asInt64.
	asm ldr: X16 base: X17 offset: 0.
	asm add: self scratchA with: X16 with: self scratchA.
	asm ldr: X17 base: X17 offset: 8.
	asm cmp: self scratchA with: X17.
	asm b: slow if: COND_HI.
	asm adrp: X17 label: (asm labelAt: gc edenBoxAddress).
	asm add: X17 with: X17 imm: (gc edenBoxAddress bitAnd: 16rFFF) asInt64.
	asm str: self scratchA base: X17 offset: 0.
	self loadConstant: cls into: X17.
	asm stp: self scratchB with: X17 base: X16 offset: 0
!
emitMakeArray: n
	"0x94: an Array of the operands in eden (young: no store barrier) if there are at most 64 and there is room; else the runtime makes it from the slots at slotTop (OUT_ARRAY)."
	| nd k slow back x r |
	nd := ir node: n.
	k := nd nargs asInt32.
	slow := self out: OUT_ARRAY node: n index: 0.
	back := asm newLabel.
	(cgOuts + (cgOutCount - 1)) resume: back.
	r := self dst: n.
	k <= 64
		ifTrue: [
			asm comment: 'make an Array in eden, the operands its elements'.
			asm mov: self scratchB imm: (k asInt64 bitOr: F_VAR asInt64 << H_FMT_SHIFT).
			self emitEdenObject: memory clsArray slow: slow.
			0 to: k - 1 do: [:i |
				x := self src: (ir operand: nd args + i) into: self scratchA.
				asm str: x base: X16 offset: (self fieldOffset: i)].
			asm mov: r with: X16]
		ifFalse: [asm b: slow].
	asm bind: back.
	self def: n from: r
!
emitFill: n upTo: stop
	"Allocation n (x16) of bytes or 32-bit words, its header stored, that the replace writing elements 1 to stop follows (fusedReplaceOf:): its slots zeroed from the one element stop + 1 starts in (all of them if stop is not a SmallInteger; none past the last); stop its size: the last slot (the format's unused elements)."
	| s r zero all smi |
	s := (((ir node: n) c bitAnd: 255) asInt32 = F_W32) ifTrue: [2] ifFalse: [0].
	asm ldr: (self scratchB bitOr: REG_W) base: X16 offset: 0.
	(self baseValueOf: stop) = (self baseValueOf: (ir operand: (ir node: n) args + 1)) ifTrue: [
		zero := asm newLabel.
		asm comment: 'the last slot zeroed (the replace that follows writes the elements)'.
		asm cbz: self scratchB to: zero.
		asm add: self scratchA with: X16 with: self scratchB shift: SHIFT_LSL amount: 3.
		asm str: XZR base: self scratchA offset: 8.
		^asm bind: zero].
	asm comment: 'zeroed from the slot of the element after those the replace that follows writes'.
	smi := (ir node: (self baseValueOf: stop)) tkind asInt32 = T_SMI.
	zero := asm newLabel.
	all := asm newLabel.
	r := self src: stop into: X17.
	smi ifFalse: [asm tbz: r bit: 0 to: all].
	asm asr: X17 with: r imm: 1.
	asm cmp: X17 imm: 0.
	asm csel: X17 with: X17 with: XZR cond: COND_GT.
	asm lsl: self scratchA with: self scratchB imm: 3 - s.
	asm cmp: X17 with: self scratchA.
	asm csel: X17 with: X17 with: self scratchA cond: COND_LO.
	s > 0 ifTrue: [asm lsl: X17 with: X17 imm: s].
	asm lsr: X17 with: X17 imm: 3.
	smi ifFalse: [
		asm b: zero.
		asm bind: all.
		asm mov: X17 imm: 0].
	asm bind: zero.
	self emitZeroSlotsOf: X16 from: X17 count: self scratchB
!
emitZeroSlotsOf: o from: w count: k
	"Zero o's slots w (a register; changed) to k (a register) - 1; scratchA changes."
	| loop done |
	loop := asm newLabel.
	done := asm newLabel.
	asm bind: loop.
	asm cmp: w with: k.
	asm b: done if: COND_HS.
	asm add: self scratchA with: o with: w shift: SHIFT_LSL amount: 3.
	asm str: XZR base: self scratchA offset: 16.
	asm add: w with: w imm: 1.
	asm b: loop.
	asm bind: done
!
emitReloadPinned
	asm comment: 'nil, true, false again (a GC may have moved them)'.
	asm ldp: X23 with: X24 base: X22 offset: self nilOffset.
	asm ldr: X25 base: X22 offset: self falseOffset
!
emitFramePc: pc sp: sp
	asm comment: 'frame pc and sp'.
	asm mov: X16 imm: ((sp asInt64 << 32) bitOr: pc).
	asm str: X16 base: X19 offset: self pcOffset
!
saveAcross: n
	"Values live after safepoint n are in their home slots: stored where they are defined (def:from:), or here if only interrupt checks need them there."
	| v nd |
	(ir node: n) live to: (ir node: n) live + (ir node: n) nlive - 1 do: [:i |
		v := regalloc safeLiveAt: i.
		nd := ir node: v.
		((nd flags bitAnd: NF_LAZY) ~= 0 and: [nd reg >= 0 and: [nd slot >= 0]]) ifTrue: [self store: nd reg asInt32 slot: nd slot asInt32]]
!
reloadAcross: n
	| v nd |
	(ir node: n) live to: (ir node: n) live + (ir node: n) nlive - 1 do: [:i |
		v := regalloc safeLiveAt: i.
		nd := ir node: v.
		(nd reg >= 0 and: [nd slot >= 0]) ifTrue: [self load: nd reg asInt32 slot: nd slot asInt32]]
!
reloadDoublesAcross: n
	"The doubles live after call n are in their d registers again, from their raw slots (stored where they are defined): its fast path called C, which keeps no d register."
	| v nd |
	(ir node: n) live to: (ir node: n) live + (ir node: n) nlive - 1 do: [:i |
		v := regalloc safeLiveAt: i.
		nd := ir node: v.
		(nd reg >= D0 and: [nd slot >= 0]) ifTrue: [self load: nd reg asInt32 slot: nd slot asInt32]]
! !

!OptCodegen methodsFor: 'phi moves'!
emitMovesFrom: b to: s
	"Parallel moves into s's phis of their operands from b."
	| k n nd |
	k := regalloc predIndexOf: b in: s.
	k < 0 ifTrue: [^self].
	cgMoveCount := 0.
	n := (ir block: s) first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		((regalloc isValue: n) and: [nd rep asInt32 ~= R_DBL]) ifTrue: [
			cgMoveCount >= CG_MAX_MOVES ifTrue: [^asm fail: ASM_ERR_FULL].
			cgMoveDst at: cgMoveCount put: n.
			cgMoveSrc at: cgMoveCount put: (ir operand: nd args + k).
			cgMoveCount := cgMoveCount + 1].
		n := nd next].
	self sequentializeMoves.
	self emitDoubleMovesFrom: k to: s
!
emitDoubleMovesFrom: k to: s
	"The parallel moves into s's phis on doubles of their k-th operands, between d registers and raw slots (locOf:; a cycle through D0), then Float constants; a phi with a register and a home slot is stored there too (as moveRegTo:from:)."
	| n nd d c blocked progress |
	cgMoveCount := 0.
	n := (ir block: s) first.
	[n >= 0 and: [(ir node: n) op asInt32 = O_PHI]] whileTrue: [
		nd := ir node: n.
		((regalloc isValue: n) and: [nd rep asInt32 = R_DBL]) ifTrue: [
			cgMoveCount >= CG_MAX_MOVES ifTrue: [^asm fail: ASM_ERR_FULL].
			cgMoveDst at: cgMoveCount put: n.
			cgMoveSrc at: cgMoveCount put: (ir operand: nd args + k).
			cgMoveLoc at: cgMoveCount put: (self locOf: (ir operand: nd args + k)).
			cgMoveCount := cgMoveCount + 1].
		n := nd next].
	[(self firstRegisterMove) >= 0] whileTrue: [
		progress := false.
		0 to: cgMoveCount - 1 do: [:i |
			d := self locOf: (cgMoveDst at: i).
			((cgMoveLoc at: i) >= 0 and: [progress not]) ifTrue: [
				blocked := false.
				0 to: cgMoveCount - 1 do: [:j | (j ~= i and: [(cgMoveLoc at: j) = d]) ifTrue: [blocked := true]].
				blocked ifFalse: [
					(cgMoveLoc at: i) ~= d ifTrue: [self moveDouble: (cgMoveDst at: i) from: (cgMoveLoc at: i)].
					cgMoveLoc at: i put: -2.
					progress := true]]].
		progress ifFalse: [
			"a cycle: the first pending destination's value goes to D0, its readers read D0"
			c := self firstRegisterMove.
			d := self locOf: (cgMoveDst at: c).
			d < 1000
				ifTrue: [asm fmov: D0 with: d]
				ifFalse: [self load: D0 slot: d - 1000].
			0 to: cgMoveCount - 1 do: [:j | (cgMoveLoc at: j) = d ifTrue: [cgMoveLoc at: j put: D0]]]].
	0 to: cgMoveCount - 1 do: [:i |
		(cgMoveLoc at: i) = -1 ifTrue: [
			d := (ir node: (cgMoveDst at: i)) reg >= 0 ifTrue: [(ir node: (cgMoveDst at: i)) reg asInt32] ifFalse: [D1].
			self emitDouble: (self constantDouble: (ir node: (cgMoveSrc at: i)) aux asUInt64) into: d.
			self ddef: (cgMoveDst at: i) from: d]].
	cgMoveCount := 0
!
moveDouble: phi from: l
	"Double phi := the double at location l (a d register below 1000, else a raw slot; a slot to a slot through D1)."
	| r |
	r := l.
	l >= 1000 ifTrue: [
		r := (ir node: phi) reg >= 0 ifTrue: [(ir node: phi) reg asInt32] ifFalse: [D1].
		self load: r slot: l - 1000].
	self ddef: phi from: r
!
locOf: v
	"A location for the move resolver: register r, 1000 + slot, -1 for a constant."
	| nd |
	nd := ir node: v.
	nd op asInt32 = O_CONST ifTrue: [^-1].
	nd reg >= 0 ifTrue: [^nd reg asInt32].
	^1000 + nd slot asInt32
!
sequentializeMoves
	"Emit the parallel moves: one whose destination no pending move reads; in a cycle, the destination's value is kept in X16 and its readers read X16. Constants last (they read nothing)."
	| progress d blocked k |
	0 to: cgMoveCount - 1 do: [:i | cgMoveLoc at: i put: (self locOf: (cgMoveSrc at: i))].
	[(k := self firstRegisterMove) >= 0] whileTrue: [
		progress := false.
		k := 0.
		[k < cgMoveCount] whileTrue: [
			d := self locOf: (cgMoveDst at: k).
			blocked := false.
			(cgMoveLoc at: k) >= 0 ifTrue: [
				0 to: cgMoveCount - 1 do: [:j | (j ~= k and: [(cgMoveLoc at: j) = d]) ifTrue: [blocked := true]]].
			((cgMoveLoc at: k) < 0 or: [blocked]) ifTrue: [k := k + 1] ifFalse: [
				(cgMoveLoc at: k) ~= d ifTrue: [
					self moveLoc: (cgMoveLoc at: k) toReg: X17 unless: d.
					self moveRegTo: (cgMoveDst at: k) from: ((cgMoveLoc at: k) < 1000 ifTrue: [cgMoveLoc at: k] ifFalse: [X17])].
				self removeMove: k.
				progress := true]].
		progress ifFalse: [
			"a cycle: keep the first register move's destination in X16"
			k := self firstRegisterMove.
			d := self locOf: (cgMoveDst at: k).
			self moveLoc: d toReg: X16 unless: -1.
			0 to: cgMoveCount - 1 do: [:j | (cgMoveLoc at: j) = d ifTrue: [cgMoveLoc at: j put: X16]]]].
	0 to: cgMoveCount - 1 do: [:i | self moveRegTo: (cgMoveDst at: i) from: (self src: (cgMoveSrc at: i) into: X17)].
	cgMoveCount := 0
!
firstRegisterMove
	0 to: cgMoveCount - 1 do: [:i | (cgMoveLoc at: i) >= 0 ifTrue: [^i]].
	^-1
!
removeMove: k
	cgMoveCount := cgMoveCount - 1.
	cgMoveSrc at: k put: (cgMoveSrc at: cgMoveCount).
	cgMoveDst at: k put: (cgMoveDst at: cgMoveCount).
	cgMoveLoc at: k put: (cgMoveLoc at: cgMoveCount)
!
moveLoc: l toReg: r unless: d
	"r := the value at location l (a register below 1000, else a slot); nothing if l is a register (moveRegTo:from: reads it)."
	l < 1000 ifTrue: [
		d = -1 ifTrue: [asm mov: r with: l].
		^self].
	self load: r slot: l - 1000
!
moveValue: v to: phi
	| r |
	(self locOf: v) = (self locOf: phi) ifTrue: [^self].
	r := self src: v into: X17.
	self moveRegTo: phi from: r
!
moveLoc: l toReg: r
	l < 1000
		ifTrue: [asm mov: r with: l]
		ifFalse: [self load: r slot: l - 1000]
!
moveRegTo: phi from: r
	| nd |
	nd := ir node: phi.
	(nd reg >= 0 and: [nd reg asInt32 ~= r]) ifTrue: [asm mov: nd reg asInt32 with: r].
	(nd slot >= 0 and: [(nd flags bitAnd: NF_LAZY) = 0]) ifTrue: [self store: r slot: nd slot asInt32]
! !

!OptCodegen methodsFor: 'out of line'!
out: kind node: n index: i
	"An out-of-line path emitted after the code; answer its label."
	| o |
	cgOutCount >= CG_MAX_OUT ifTrue: [
		asm fail: ASM_ERR_FULL.
		^asm newLabel].
	o := cgOuts + cgOutCount.
	o kind: kind.
	o node: n.
	o index: i.
	o label: asm newLabel.
	o resume: -1.
	o pos: (n >= 0 ifTrue: [(ir node: n) pos] ifFalse: [0]).
	cgOutCount := cgOutCount + 1.
	^o label
!
deoptLabelFor: n
	"The label of a guard's failure: its metadata recorded with the registers as they are here."
	| k l |
	k := self recordGuard: n.
	l := self out: OUT_DEOPT node: n index: k.
	self emitStressAt: n label: l.
	^l
!
emitOuts
	| o |
	0 to: cgOutCount - 1 do: [:i |
		o := cgOuts + i.
		asm bind: o label.
		o kind = OUT_DEOPT ifTrue: [
			asm comment: 'guard failed: deoptimize'.
			asm mov: W17 imm: o index.
			asm b: cgDeoptLabel].
		o kind = OUT_INTERRUPT ifTrue: [
			asm comment: 'interrupt: call the runtime'.
			self saveAcross: o node.
			self emitFramePc: cgBcSize + (self recordSafepoint: o node kind: (ir node: o node) aux asInt32) sp: cgSlotTop.
			asm mov: X0 with: X19.
			asm bl: ((ir node: o node) aux = SP_ENTRY ifTrue: [asm labelAt: stubs entryInterruptStub] ifFalse: [cgInterruptLabel]).
			asm cbnz: X0 to: cgExitPlainLabel.
			self emitReloadPinned.
			self reloadAcross: o node.
			asm b: o resume].
		o kind = OUT_ARRAY ifTrue: [self emitMakeArraySlow: o].
		o kind = OUT_FOLLOW ifTrue: [
			asm comment: 'some object is a forwarder (becomeForward:): follow the operands'.
			self emitFollow: (o index bitAnd: 255).
			(o index >> 8) ~= 255 ifTrue: [self emitFollow: o index >> 8].
			asm b: o resume].
		o kind = OUT_BARRIER ifTrue: [
			asm comment: 'remember the old object: call the runtime'.
			self emitBarrierCall: o].
		(o kind = OUT_LAZY or: [o kind = OUT_NOTMADE]) ifTrue: [
			asm comment: 'deoptimize after the call: the runtime rebuilds the frames (the result in its slot)'.
			asm str: X0 base: X20 offset: 8 * cgSlotTop.
			self emitFramePc: cgBcSize + o index sp: cgSlotTop + 1.
			asm mov: X0 with: X19.
			asm mov: X1 imm: o index.
			asm mov: X2 imm: (o kind = OUT_NOTMADE ifTrue: [1] ifFalse: [0]).
			asm bl: cgDeoptReturnLabel.
			asm b: cgExitPlainLabel].
		o kind = OUT_RESUME ifTrue: [
			runtime noteResume: cgBcSize + o index at: asm pc - cgCodeStart.
			asm comment: 'resumption after the call (the interpreter returned into the frame): the result from its slot'.
			asm ldr: X0 base: X20 offset: 8 * cgSlotTop.
			asm b: o resume].
		o kind = OUT_SENT ifTrue: [
			asm comment: 'interrupt after the call: the runtime handles it (the result in its slot)'.
			asm str: X0 base: X20 offset: 8 * cgSlotTop.
			self emitFramePc: cgBcSize + o index sp: cgSlotTop + 1.
			asm mov: X0 with: X19.
			asm bl: cgInterruptLabel.
			asm cbnz: X0 to: cgExitPlainLabel.
			self emitReloadPinned.
			asm ldr: X0 base: X20 offset: 8 * cgSlotTop.
			asm b: o resume].
		o kind = OUT_SITE ifTrue: [
			asm comment: 'not a closure with as many arguments: the send through an inline cache'.
			self emitSiteCall: o node index: o index.
			self noteRet: o index argc: (ir node: o node) nargs asInt32 - 1.
			asm b: o resume].
		o kind = OUT_STACK ifTrue: [
			asm comment: 'no room for the frame: the interpreter runs it'.
			self emitFramePc: cgEntryPc sp: cgValidSlots.
			asm mov: X0 with: X19.
			asm bl: cgStackFullLabel.
			asm b: cgExitSyncLabel].
		o kind = OUT_WIDOW ifTrue: [
			asm comment: 'married: its Context becomes a dead one'.
			asm stur: X0 base: X20 offset: -8.
			self emitFramePc: 0 sp: 0.
			asm mov: X0 with: X19.
			asm bl: (asm labelAt: stubs widowStub).
			asm ldur: X0 base: X20 offset: -8.
			asm b: o resume].
		o kind = OUT_BOTTOM ifTrue: [
			asm comment: 'the bottom frame returns into a Context: the runtime does it'.
			asm mov: W17 imm: (self recordGuard: o node).
			asm b: cgReturnLabel]].
	^true
!
emitMakeArraySlow: o
	"Eden is full (or the Array is big): the runtime makes it from the operands at slotTop (it may collect; values live after it reloaded from their home slots)."
	| nd k x |
	nd := ir node: o node.
	k := nd nargs asInt32.
	asm comment: 'make the Array: call the runtime'.
	self saveAcross: o node.
	0 to: k - 1 do: [:i |
		x := self src: (ir operand: nd args + i) into: self scratchA.
		asm str: x base: X20 offset: 8 * (cgSlotTop + i)].
	self emitFramePc: cgBcSize + (self recordSafepoint: o node kind: SP_ALLOC) sp: cgSlotTop + k.
	asm mov: X0 with: X19.
	asm mov: X1 imm: k.
	asm bl: (asm labelAt: stubs optMakeArrayStub).
	asm str: X0 base: X20 offset: 8 * cgSlotTop.
	self emitReloadPinned.
	self reloadAcross: o node.
	asm ldr: (self dst: o node) base: X20 offset: 8 * cgSlotTop.
	asm b: o resume
!
emitBarrierCall: o
	"Save the scratch registers the C function may change, call the barrier, restore."
	| obj v |
	obj := o index bitAnd: 255.
	v := o index >> 8.
	0 to: 7 do: [:i | asm stp: 2 * i with: 2 * i + 1 base: SP preIndex: -16].
	cgDoubles ifTrue: [0 to: self dregPairs - 1 do: [:i | asm stp: self dregBase + (2 * i) with: self dregBase + (2 * i) + 1 base: SP preIndex: -16]].
	asm mov: X16 with: obj.
	asm mov: X17 with: v.
	asm mov: X0 with: X16.
	asm mov: X1 with: X17.
	asm bl: cgBarrierLabel.
	cgDoubles ifTrue: [self dregPairs - 1 to: 0 by: -1 do: [:i | asm ldp: self dregBase + (2 * i) with: self dregBase + (2 * i) + 1 base: SP postIndex: 16]].
	7 to: 0 by: -1 do: [:i | asm ldp: 2 * i with: 2 * i + 1 base: SP postIndex: 16].
	asm b: o resume
! !

!OptCodegen methodsFor: 'metadata'!
meta: w
	cgMetaCount < CG_MAX_META ifTrue: [cgMetaWords at: cgMetaCount put: w asInt32].
	cgMetaCount := cgMetaCount + 1
!
newSafepoint
	| k |
	k := cgSpCount.
	cgSpCount < CG_MAX_SP ifTrue: [cgSpOffsets at: k put: 0].
	cgSpCount := cgSpCount + 1.
	^k
!
recordGuard: n
	"Metadata for deoptimizing at guard n: its state with every value where it is now, and why (feedback for the next compilation)."
	| op why |
	op := (ir node: n) op asInt32.
	why := (op = O_GUARDCLASS or: [op = O_GUARDCLOSURE or: [op = O_DEOPT and: [(ir node: n) aux = 0]]])
		ifTrue: [feedback deoptClass]
		ifFalse: [op = O_NOTINTS ifTrue: [feedback sawInts] ifFalse: [
			(op = O_GUARDINT or: [op = O_IADD or: [op = O_ISUB or: [op = O_IMUL or: [op = O_IMOD or: [op = O_IDIV or: [op = O_ISHIFT]]]]]]) ifTrue: [feedback deoptArith] ifFalse: [feedback deoptOther]]].
	((ir node: n) flags bitAnd: NF_HOISTED) ~= 0 ifTrue: [why := feedback deoptHoisted].
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [libc fprintf: libc stderr format: 'guard safepoint %d: v%d
' with: cgSpCount with: n].
	^self recordState: (ir node: n) state kind: (SP_GUARD bitOr: why asInt64 << 8) asInt32 node: n inSlots: false
!
recordSafepoint: n kind: k
	^self recordState: (ir node: n) state kind: k node: n inSlots: true
!
recordCall: n
	^self recordState: (ir node: n) state kind: SP_CALL node: n inSlots: true
!
recordState: s kind: kind node: n inSlots: inSlots
	"Safepoint record: kind, metadata offset in the table; [kind, send pc, send info, selector, nacts, then per activation from the outermost: method, closure, receiver, pc, depth, locations]."
	<function>
	| k chain nchain t st nd |
	k := self newSafepoint.
	k < CG_MAX_SP ifTrue: [cgMetaWords at: CG_MAX_META - 1 - k put: cgMetaCount].
	nd := ir node: n.
	self meta: kind.
	kind = SP_CALL
		ifTrue: [
			self meta: (nd aux2 >> 32) asInt32.
			self meta: (nd aux2 bitAnd: 16rFFFFFFFF) asInt32.
			self meta: (self poolIndexOf: nd aux asUInt64)]
		ifFalse: [
			"a guard moved before a loop: the site it came from, and where a class guard's value is (plus 1: its class is feedback there; not of a frame slot's guard at a loop unit's entry, which comes from no send)"
			self meta: ((nd flags bitAnd: NF_HOISTED) ~= 0 ifTrue: [nd bcpc] ifFalse: [-1]).
			self meta: (((nd flags bitAnd: NF_HOISTED) ~= 0 and: [nd op asInt32 = O_GUARDCLASS and: [nd state ~= ir osrState]]) ifTrue: [(self locOf: nd a inSlots: false) + 1] ifFalse: [0]).
			self meta: ((nd flags bitAnd: NF_HOISTED) ~= 0 ifTrue: [self poolIndexOf: (ir act: nd bcact) method] ifFalse: [0])].
	"the chain of states, outermost first"
	nchain := 0.
	t := s.
	[t >= 0] whileTrue: [
		nchain := nchain + 1.
		t := (ir state: t) parent].
	self meta: nchain.
	cgSunkCount := 0.
	cgChainCount := nchain asInt32.
	nchain - 1 to: 0 by: -1 do: [:i |
		t := s.
		i timesRepeat: [t := (ir state: t) parent].
		st := ir state: t.
		cgChainActs at: nchain - 1 - i put: st act.
		self meta: (self poolIndexOf: (ir act: st act) method).
		self meta: ((ir act: st act) closure >= 0 ifTrue: [self closureLocOf: (ir act: st act) closure inSlots: inSlots] ifFalse: [-1]).
		self meta: (self locOf: (ir operand: st vals) inSlots: inSlots).
		self meta: st pc.
		self meta: st depth.
		0 to: st depth - 1 do: [:j | self meta: (self locOf: (ir operand: st vals + 1 + j) inSlots: inSlots)]].
	"closures that were never made: the activation that makes them (its index above), startpc, arguments, temps, frame size"
	self meta: cgSunkCount.
	0 to: cgSunkCount - 1 do: [:j |
		nd := ir node: (cgSunk at: j).
		t := -1.
		0 to: nchain - 1 do: [:i | (cgChainActs at: i) = (nd aux2 >> 32) asInt32 ifTrue: [t := i asInt32]].
		t < 0 ifTrue: [asm fail: ASM_ERR_OPERAND].
		self meta: t.
		self meta: nd aux asInt32.
		self meta: (nd aux2 bitAnd: 16rFFFFFF) asInt32].
	^k
!
closureLocOf: v inSlots: inSlots
	"A block unit's closure is its frame's (-2)."
	(ir node: v) op asInt32 = O_PARAM ifTrue: [^-2].
	^self locOf: v inSlots: inSlots
!
sunkIndexOf: v
	"v's entry in this record's closures that were never made."
	0 to: cgSunkCount - 1 do: [:j | (cgSunk at: j) = v ifTrue: [^j]].
	cgSunkCount >= 64 ifTrue: [
		asm fail: ASM_ERR_FULL.
		^0].
	cgSunk at: cgSunkCount put: v.
	cgSunkCount := cgSunkCount + 1.
	^cgSunkCount - 1
!
locOf: v inSlots: inSlots
	"Where deoptimization finds v: a constant, its register (not at a safepoint), its slot; a double: its d register (not at a safepoint), its raw slot."
	| nd c |
	nd := ir node: v.
	nd rep asInt32 = R_DBL ifTrue: [
		(inSlots not and: [nd reg >= 0]) ifTrue: [^((nd reg asInt64 - D0) << 3) bitOr: LOC_DREG].
		nd slot >= 0 ifTrue: [^(nd slot asInt64 << 3) bitOr: LOC_RAW].
		asm fail: ASM_ERR_OPERAND.
		^0].
	nd op asInt32 = O_CLOSURE ifTrue: [^((self sunkIndexOf: v) asInt64 << 3) bitOr: LOC_SUNK].
	nd op asInt32 = O_HOMESLOT ifTrue: [^(nd aux << 3) bitOr: LOC_SLOT].
	nd op asInt32 = O_CONST ifTrue: [
		c := nd aux asUInt64.
		((self isInt: c) and: [(self intVal: c) between: -16r8000000 and: 16r7FFFFFF]) ifTrue: [^((self intVal: c) << 3) bitOr: LOC_SMI].
		^((self poolIndexOf: c) asInt64 << 3) bitOr: LOC_CONST].
	(inSlots not and: [nd reg >= 0]) ifTrue: [^(nd reg asInt64 << 3) bitOr: LOC_REG].
	nd slot >= 0 ifTrue: [^(nd slot asInt64 << 3) bitOr: LOC_SLOT].
	asm fail: ASM_ERR_OPERAND.
	^0
!
depCount
	^cgDepCount
!
depAt: i
	^cgDeps at: i
!
spTableAt: k
	"The metadata offset of safepoint k."
	^cgMetaWords at: CG_MAX_META - 1 - k
! !

VMStruct subclass: #OptOut
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptOut comment: 'An out-of-line path of optimized code (OptCodegen): its kind, the node it belongs to, an index (a safepoint, registers), its label and where it goes back to.'!

!OptOut class methodsFor: 'declaring'!
fields
	^#((kind int32_t) (node int32_t) (index int32_t) (label int32_t) (resume int32_t) (pos int32_t))
! !
