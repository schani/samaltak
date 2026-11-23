OptModule subclass: #OptRuntime
	instanceVariableNames: 'ir builder passes regalloc codegen rtDeoptVals rtDeoptCount rtActMethod rtActClosure rtActRcv rtActPc rtActDepth rtActVals rtActCount rtOptYoung rtOptYoungCount rtOptYoungOverflow rtStatOptCompiled rtStatOptFailed rtStatOptBytecodes rtStatOptUs rtStatOptBytes rtStatDeopts rtStatOptOsr rtStatInvalidations rtAll rtAllCount rtSunkAct rtSunkStart rtSunkInfo rtSunkOrder rtSunkCount rtSunkUseVal rtSunkUseId rtSunkUseCount rtFloatVal rtFloatLoc rtFloatBits rtFloatCount rtWritten rtUnitStart rtUnitOsr rtUnitDepth rtUnits rtUnitCount rtVariantCount rtFailed rtTrace rtTraceSends rtStamp rtStatSends rtUnitFrame rtUnitSignature rtSigCtx rtSigCount'
	classVariableNames: 'OPT_MAX_UNITS OPT_MAX_VARIANT_UNITS OPT_MAX_VARIANTS OPT_MAX_GENERATIONS OPT_MAX_DEOPTS OPT_MAX_DEOPT_ACTS OPT_MAX_DEOPT_VALS OPT_MAX_HEADERS OPT_MAX_YOUNG'
	package: 'VM-Jit'!

OptRuntime comment: 'The optimizing tier''s side of the runtime (docs/jit.md, Optimizing tier): when to optimize (tierUp:), compiling (OptBuilder, OptPasses, OptRegalloc, OptCodegen), sends from optimized code, deoptimization (a guard failed: the registers are in the JitState; after a send: everything is in slots), rebuilding an optimized frame''s activations as frames (deoptimization) or Contexts (materializeAll), resuming an optimized frame the interpreter returns into, the GC roots of optimized code (its method and oop pool).

An optimized method''s header (JitMethod, mode opt) is linked from its method''s lower-tier (baseline) header (opt; lower back); new frames of the method run the optimized code: the interpreter''s and optimized callers through the method''s cell, baseline callers through its unchecked entry (JitBaselineRuntime>>redirect:to:). Blocks and loops have units of their own (unitOf:start:osr:). The header carries the safepoint table (spTable: offset of each safepoint''s record in meta) and the records (OptCodegen>>recordState:kind:node:inSlots:).'!

!OptRuntime class methodsFor: 'declaring'!
declarations
	^#((ir OptIR) (builder OptBuilder) (passes OptPasses) (regalloc OptRegalloc) (codegen OptCodegen)
		(rtDeoptVals 'oop[OPT_MAX_DEOPT_VALS]') (rtDeoptCount int32_t)
		(rtActMethod 'oop[OPT_MAX_DEOPT_ACTS]') (rtActClosure 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActRcv 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActPc 'int32_t[OPT_MAX_DEOPT_ACTS]')
		(rtActDepth 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActVals 'int32_t[OPT_MAX_DEOPT_ACTS]') (rtActCount int32_t)
		(rtOptYoung 'JitMethod *[OPT_MAX_YOUNG]') (rtOptYoungCount int32_t) (rtOptYoungOverflow bool)
		(rtStatOptCompiled uint64_t) (rtStatOptFailed uint64_t) (rtStatOptBytecodes uint64_t) (rtStatOptUs uint64_t) (rtStatOptBytes uint64_t)
		(rtStatDeopts uint64_t) (rtStatOptOsr uint64_t) (rtStatInvalidations uint64_t)
		(rtAll 'JitMethod *[OPT_MAX_HEADERS]') (rtAllCount int32_t)
		(rtSunkAct 'int32_t[64]') (rtSunkStart 'int32_t[64]') (rtSunkInfo 'int32_t[64]') (rtSunkOrder 'int32_t[64]') (rtSunkCount int32_t)
		(rtSunkUseVal 'int32_t[OPT_MAX_DEOPT_VALS]') (rtSunkUseId 'int32_t[OPT_MAX_DEOPT_VALS]') (rtSunkUseCount int32_t)
		(rtFloatVal 'int32_t[OPT_MAX_DEOPT_VALS]') (rtFloatLoc 'int32_t[OPT_MAX_DEOPT_VALS]') (rtFloatBits 'uint64_t[OPT_MAX_DEOPT_VALS]') (rtFloatCount int32_t) (rtWritten int32_t)
		(rtUnitStart int32_t) (rtUnitOsr int32_t) (rtUnitDepth int32_t) (rtUnits 'JitMethod *[OPT_MAX_UNITS]') (rtUnitCount int32_t) (rtVariantCount int32_t) (rtFailed 'uint64_t[OPT_MAX_UNITS]') (rtTrace bool) (rtTraceSends bool) (rtStamp uint32_t) (rtStatSends uint64_t) (rtUnitFrame 'Frame *') (rtUnitSignature uint32_t) (rtSigCtx 'oop[8]') (rtSigCount int32_t))
!
initialize
	OPT_MAX_DEOPT_VALS := 8192.
	OPT_MAX_DEOPT_ACTS := 256.
	OPT_MAX_YOUNG := 1024.
	OPT_MAX_HEADERS := 16384.
	OPT_MAX_DEOPTS := 8.
	OPT_MAX_GENERATIONS := 32.
	OPT_MAX_VARIANTS := 16.
	OPT_MAX_VARIANT_UNITS := 2048.
	OPT_MAX_UNITS := 8192
! !

!OptRuntime methodsFor: 'statistics'!
statOptCompiled
	^rtStatOptCompiled
!
statOptFailed
	^rtStatOptFailed
!
statOptBytecodes
	^rtStatOptBytecodes
!
statOptUs
	^rtStatOptUs
!
statOptBytes
	^rtStatOptBytes
!
statDeopts
	^rtStatDeopts
!
statOptOsr
	^rtStatOptOsr
!
statInvalidations
	^rtStatInvalidations
!
stat: i
	"vmStats' order: optimized, bytecodes, µs, code bytes, deoptimizations, OSR entries, invalidations, failures, sends through the runtime."
	i = 8 ifTrue: [^rtStatSends asInt64].
	i = 0 ifTrue: [^rtStatOptCompiled asInt64].
	i = 1 ifTrue: [^rtStatOptBytecodes asInt64].
	i = 2 ifTrue: [^rtStatOptUs asInt64].
	i = 3 ifTrue: [^rtStatOptBytes asInt64].
	i = 4 ifTrue: [^rtStatDeopts asInt64].
	i = 5 ifTrue: [^rtStatOptOsr asInt64].
	i = 6 ifTrue: [^rtStatInvalidations asInt64].
	^rtStatOptFailed asInt64
! !

!OptRuntime methodsFor: 'functions for the stubs'!
deoptFunction
	^self cCoerce: (self functionPointer: #deoptGuard:index:) to: 'uint64_t'
!
deoptReturnFunction
	^self cCoerce: (self functionPointer: #deoptReturn:index:notMade:) to: 'uint64_t'
!
stackFullFunction
	^self cCoerce: (self functionPointer: #stackFull:) to: 'uint64_t'
!
makeArrayFunction
	^self cCoerce: (self functionPointer: #makeArray:count:) to: 'uint64_t'
!
returnFunction
	^self cCoerce: (self functionPointer: #returnBottom:index:) to: 'uint64_t'
! !

!OptRuntime methodsFor: 'headers'!
isOpt: h
	^h notNull and: [h mode = runtime optMode]
!
isAlive: h
	"An optimized header whose code may run."
	^(runtime hasCode: h) and: [(h flags bitAnd: 2) = 0]
!
optOf: h
	"The live optimized header of lower-tier header h, null if none."
	| o |
	h isNull ifTrue: [^self null].
	h opt = 0 ifTrue: [^self null].
	o := self cCoerce: h opt to: 'JitMethod *'.
	(self isAlive: o) ifFalse: [^self null].
	^o
!
recordOf: h index: k
	^h meta + (h spTable at: k)
!
poolAt: i of: h
	^(self cCoerce: h codeStart + h poolOffset to: 'oop *') at: i
!
headerCount
	"Optimized headers since the last flush (live or not)."
	^rtAllCount
!
headerAt: i
	^rtAll at: i
! !

!OptRuntime methodsFor: 'tiering'!
initialCount: m
	"The lower tier's count for m when its code is installed: entries and backward jumps before m is optimized."
	<function>
	(runtime flag: runtime eagerFlag) ifTrue: [^1].
	^(runtime optThreshold max: 1) asInt32
!
tierUp: f loop: loop
	"f's method ran out of its count at f's pc (synced), its entry or (loop ~= 0) a loop head: answer 0 to go on in the lower tier, 1 to leave, or where f continues in optimized code (at a loop head: on-stack replacement)."
	<function>
	<var: #o type: 'JitMethod *'>
	| m h o s k |
	m := f method.
	"the count's slot is shared by methods whose hashes meet there, and more units of m may follow (its blocks, its loops, frames resumed in the lower tier): it starts over whatever happens; failures are remembered per unit"
	runtime counterFor: m put: (self initialCount: m).
	h := runtime lookup: m.
	(runtime hasCode: h) ifFalse: [^0].
	f code = (self cCoerce: h to: 'uint64_t') ifFalse: [^0].
	s := f closure = memory nilOop ifTrue: [0] ifFalse: [(self intVal: (self loadRef: f closure at: BC_STARTPC)) asInt32].
	(s = 0 and: [h opt = 0 and: [(self failed: m start: 0 osr: 0) not]]) ifTrue: [
		(self optimize: m lower: h) isNull ifTrue: [self noteFailed: m start: 0 osr: 0]].
	k := loop = 0 ifTrue: [0] ifFalse: [f pc + 1].
	"a married frame's temps may change through its Context (blocks it made): a unit of its own keeps those in the frame"
	(k ~= 0 and: [f ctx ~= memory nilOop and: [self makesClosures: m start: s]]) ifTrue: [k := k + 16r10000].
	"the loop's variant for the closures other frames made that it may inline, or its plain unit"
	k ~= 0 ifTrue: [k := self variantOf: f method: m start: s osr: k].
	(s = 0 and: [k = 0])
		ifTrue: [o := self optOf: h]
		ifFalse: [
			o := self unitOf: m start: s osr: k.
			"a failed compilation leaves a header without code: not compiled again (an invalidated one is)"
			((o isNull or: [(runtime hasCode: o) and: [(self isAlive: o) not and: [o generation < OPT_MAX_GENERATIONS]]]) and: [(self failed: m start: s osr: k) not]) ifTrue: [
				"a loop's unit may inline closures this frame made"
				k ~= 0 ifTrue: [rtUnitFrame := f].
				o := self optimizeUnit: m start: s osr: k depth: f sp lower: h previous: o.
				rtUnitFrame := self null.
				o isNull ifTrue: [self noteFailed: m start: s osr: k]]].
	rtUnitSignature := 0.
	(o isNull or: [(self isAlive: o) not]) ifTrue: [^0].
	k ~= 0 ifTrue: [rtStatOptOsr := rtStatOptOsr + 1].
	f code: (self cCoerce: o to: 'uint64_t').
	^o start
!
variantOf: f method: m start: s osr: g
	"The key of the unit f enters at loop key g: the variant (bits 17 and up: 1 to OPT_MAX_VARIANTS) whose signature is f's (signatureOf:method:), a new one if there is room (OPT_MAX_VARIANT_UNITS in all, a free unit) and none failed to compile, else the loop's plain unit (variant 0, which inlines no closures other frames made). rtUnitSignature: the variant's signature, 0 for the plain unit."
	<function>
	<var: #f type: 'Frame *'>
	<var: #o type: 'JitMethod *'>
	| w t o |
	rtUnitSignature := 0.
	w := self signatureOf: f method: m.
	w = 0 ifTrue: [^g].
	1 to: OPT_MAX_VARIANTS do: [:v |
		t := g + (v asInt64 << 17) asInt32.
		o := self unitOf: m start: s osr: t.
		o isNull
			ifTrue: [
				((self failed: m start: s osr: t) or: [rtVariantCount >= OPT_MAX_VARIANT_UNITS or: [self unitsFull]]) ifTrue: [^g].
				rtUnitSignature := w.
				^t]
			ifFalse: [
				o signature = w ifTrue: [
					((runtime hasCode: o) and: [(self failed: m start: s osr: t) not and: [(self isAlive: o) or: [o generation < OPT_MAX_GENERATIONS]]]) ifFalse: [^g].
					rtUnitSignature := w.
					^t]]].
	^g
!
signatureOf: f method: m
	"What a variant of a loop's unit for f is compiled for: the closures other frames made (closureSignatureOf:) and, where m is inherited, the class of the receiver (OptBuilder>>guardReceiverClass:: its sends to self find their methods); 0: nothing, the plain unit."
	<var: #f type: 'Frame *'>
	<returns: 'uint32_t'>
	| w c |
	w := self closureSignatureOf: f.
	c := interpreter receiverClass: (f fp at: -1).
	c = (self loadRef: m at: CM_CLASS) ifTrue: [^w].
	w := ((self mix: w asUInt64 with: (self hashOf: c) asUInt64 + 1) bitAnd: 16rFFFFFFFF) asUInt32.
	w = 0 ifTrue: [^1].
	^w
!
closureSignatureOf: f
	"The code of the closures other frames made that a loop's unit for f may inline (OptBuilder>>foreignClosureOf:numArgs:pc:act:), and where they are: those in f's slots (the first 64), and those in the temps (the first 32) of every Context out from such a closure (OptBuilder>>knownOuterTemp:levels:of:), hashed into 32 bits; 0 if there are none, or too many Contexts."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint32_t'>
	| h n v w |
	h := 0 asUInt64.
	n := 0.
	rtSigCount := 0.
	0 to: (f sp min: 64) - 1 do: [:i |
		v := f fp at: i.
		((builder inlinableClosure: v) and: [(self loadRef: v at: BC_OUTER) ~= f ctx]) ifTrue: [
			h := self mix: h closure: v at: i depth: 0 frameContext: f ctx.
			n := n + 1]].
	(n = 0 or: [rtSigCount > 8]) ifTrue: [^0].
	h := h bitXor: h >> 32.
	w := (h bitAnd: 16rFFFFFFFF) asUInt32.
	w = 0 ifTrue: [^1].
	^w
!
mix: h with: x
	<var: #h type: 'uint64_t'>
	<var: #x type: 'uint64_t'>
	<returns: 'uint64_t'>
	| r |
	r := (h bitXor: x) * 16r5851F42D4C957F2D asUInt64.
	^r bitXor: r >> 29
!
mix: h0 closure: c at: i depth: d frameContext: fc
	"h0 with closure c (in slot or temp i, d Contexts out from f's slots) mixed in: its code, then the Contexts out from it not visited yet (rtSigCtx; a ninth: rtSigCount 9) with the closures their temps hold, depth first."
	<function>
	<var: #h0 type: 'uint64_t'>
	<returns: 'uint64_t'>
	| h ctx cl lv j s g n v |
	ctx := self loadRef: c at: BC_OUTER.
	h := self mix: h0 with: ((1 bitOr: d asUInt64 << 8) bitOr: i asUInt64 << 16).
	h := self mix: h with: (self hashOf: (self loadRef: ctx at: CTX_METHOD)) asUInt64.
	h := self mix: h with: (self loadRef: c at: BC_STARTPC).
	lv := 1.
	[self isContext: ctx] whileTrue: [
		"one visited already: the rest of its chain is in h"
		j := -1.
		0 to: rtSigCount - 1 do: [:k | (rtSigCtx at: k) = ctx ifTrue: [j := k]].
		j >= 0 ifTrue: [^self mix: h with: ((3 bitOr: d asUInt64 << 8) bitOr: (j + 1) asUInt64 << 16)].
		rtSigCount >= 8 ifTrue: [
			rtSigCount := 9.
			^h].
		rtSigCtx at: rtSigCount put: ctx.
		rtSigCount := rtSigCount + 1.
		h := self mix: h with: ((2 bitOr: d asUInt64 << 8) bitOr: lv asUInt64 << 16).
		s := self loadRef: ctx at: CTX_SENDER.
		(self isInt: s)
			ifTrue: [
				g := interpreter frames + (self intVal: s).
				n := g sp min: 32.
				"not an optimized frame's raw slots"
				(runtime isOptFrame: g) ifTrue: [n := n min: (self rawBaseOf: g) asInt32]]
			ifFalse: [n := ((self numSlots: ctx) asInt32 - CTX_FIXED) min: 32].
		0 to: n - 1 do: [:k |
			v := (self isInt: s) ifTrue: [g fp at: k] ifFalse: [self loadRef: ctx at: CTX_FIXED + k].
			((builder inlinableClosure: v) and: [(self loadRef: v at: BC_OUTER) ~= fc]) ifTrue: [
				h := self mix: h closure: v at: k depth: d + 1 frameContext: fc.
				rtSigCount > 8 ifTrue: [^h]]].
		cl := self loadRef: ctx at: CTX_CLOSURE.
		ctx := (self isClosure: cl) ifTrue: [self loadRef: cl at: BC_OUTER] ifFalse: [memory nilOop].
		lv := lv + 1].
	^self mix: h with: (3 bitOr: d asUInt64 << 8)
!
isClosure: v
	^(self isPtr: v) and: [(self rawClass: v) = memory clsBlock]
!
isContext: v
	^(self isPtr: v) and: [(self rawClass: v) = memory clsContext]
!
makesClosures: m start: s
	"The code of m (s 0) or of its block at startpc s makes BlockClosures that may reach its frame (through outer temps, ^, thisContext)."
	| bcs pc end op closures reach |
	bcs := self methodBytecodes: m.
	end := s = 0 ifTrue: [self methodSize: m] ifFalse: [s + (((bcs at: s - 2) asInt64 << 8) bitOr: (bcs at: s - 1)) asInt32].
	pc := s.
	closures := false.
	reach := false.
	[pc < end] whileTrue: [
		op := bcs at: pc.
		op = 16r8F ifTrue: [closures := true].
		((op >= 16r8A and: [op <= 16r8C]) or: [op = 16r7C or: [op = 16r76]]) ifTrue: [reach := true].
		pc := (pc + (analysis lengthOf: op)) asInt32].
	^closures and: [reach]
!
unitEntryOf: m start: s
	"Where the block stub enters m's block at startpc s: its unit's entry (OptCodegen>>emitBaselineEntry), 0 if it has none that may run."
	<function>
	| o |
	o := self unitOf: m start: s asInt32 osr: 0.
	(o notNull and: [self isAlive: o]) ifFalse: [^0 asUInt64].
	^o codeStart
!
unitOf: m start: s osr: t
	"The optimized code of m's block at startpc s (0: m) entered at its start (t 0) or at loop head t - 1, alive or not; null if there is none."
	<function>
	| i h |
	i := self unitHash: m start: s osr: t.
	[(h := rtUnits at: i) notNull] whileTrue: [
		(h methodHash = (self hashOf: m) asUInt32 and: [h blockStart = s asUInt32 and: [h osrPc = t asUInt32 and: [h method = m or: [(self isAlive: h) not]]]]) ifTrue: [^h].
		i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	^self null
!
failedKey: m start: s osr: t
	^((((self hashOf: m) asUInt64 bitXor: t asUInt64 >> 16) << 32) bitOr: ((s asUInt64 bitAnd: 16rFFFF) << 16)) bitOr: (t asUInt64 bitAnd: 16rFFFF)
!
failed: m start: s osr: t
	"Compiling this unit failed before (a hash table of keys; a collision only means it is not tried; noteFailed: probes as far)."
	| key i n |
	key := (self failedKey: m start: s osr: t) bitOr: 1 << 63.
	i := ((key bitXor: key >> 29) bitAnd: OPT_MAX_UNITS - 1) asInt32.
	n := 0.
	[(rtFailed at: i) ~= 0 and: [n < (OPT_MAX_UNITS quo: 2)]] whileTrue: [
		(rtFailed at: i) = key ifTrue: [^true].
		n := n + 1.
		i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	^false
!
noteFailed: m start: s osr: t
	| key i n |
	key := (self failedKey: m start: s osr: t) bitOr: 1 << 63.
	i := ((key bitXor: key >> 29) bitAnd: OPT_MAX_UNITS - 1) asInt32.
	n := 0.
	[(rtFailed at: i) ~= 0] whileTrue: [
		n := n + 1.
		n >= (OPT_MAX_UNITS quo: 2) ifTrue: [^self].
		i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	rtFailed at: i put: key
!
unitHash: m start: s osr: t
	"a loop's variants (bits 17 and up) apart"
	^((((self hashOf: m) asUInt64 * 31 + s asUInt64) * 31 + t asUInt64) + ((t asUInt64 >> 17) * 2654435761)) bitAnd: OPT_MAX_UNITS - 1
!
blockCodeFor: m start: s
	"Frame code of a new activation of m's block at s: its optimized code if it may run, else m's (lower tier, or counting)."
	<function>
	| o |
	o := self unitOf: m start: s osr: 0.
	(o notNull and: [self isAlive: o]) ifTrue: [^self cCoerce: o to: 'uint64_t'].
	^runtime blockCodeFor: m
!
optimizeUnit: m start: s osr: t depth: d lower: h previous: p
	"Compile m's block at startpc s (0: m) entered at its start (t 0) or at loop head t - 1 with d slots as a unit of its own, in place of p (invalidated) if not null; null if it could not."
	<function>
	| o t0 i |
	self unitsFull ifTrue: [^self null].
	rtUnitStart := s.
	rtUnitOsr := t.
	rtUnitDepth := d.
	t0 := runtime nowUs.
	o := runtime compile: m mode: runtime optMode notes: runtime notes.
	rtStatOptUs := rtStatOptUs + (runtime nowUs - t0) asUInt64.
	rtUnitStart := 0.
	rtUnitOsr := 0.
	o isNull ifTrue: [^self null].
	rtAllCount < OPT_MAX_HEADERS
		ifTrue: [
			rtAll at: rtAllCount put: o.
			rtAllCount := rtAllCount + 1]
		ifFalse: [runtime requestFlush].
	cache beginWriting.
	o lower: (self cCoerce: h to: 'uint64_t').
	o blockStart: s asUInt32.
	o osrPc: t asUInt32.
	o stamp: rtStamp.
	p notNull ifTrue: [o generation: p generation + 1].
	o methodHash: (self hashOf: m) asUInt32.
	o signature: rtUnitSignature.
	cache endWriting.
	self noteYoung: o.
	i := self unitHash: m start: s osr: t.
	[(rtUnits at: i) notNull and: [(rtUnits at: i) ~= p]] whileTrue: [i := (i + 1) bitAnd: OPT_MAX_UNITS - 1].
	(rtUnits at: i) isNull ifTrue: [
		rtUnitCount := rtUnitCount + 1.
		t >> 17 ~= 0 ifTrue: [rtVariantCount := rtVariantCount + 1]].
	rtUnits at: i put: o.
	"a block's unit: the block stub enters it from now on"
	(s ~= 0 and: [t = 0]) ifTrue: [brt clearCaches].
	^o
!
unitsFull
	"No unit is installed any more until the code cache is flushed."
	^rtUnitCount >= ((OPT_MAX_UNITS quo: 4) * 3)
!
unitEntry
	"The pc the unit being compiled is entered at: 0 for a method, a block's startpc, a loop head."
	rtUnitOsr > 0 ifTrue: [^(rtUnitOsr bitAnd: 16rFFFF) - 1].
	^rtUnitStart
!
unitOsr
	"Not 0 while a loop's unit is being compiled."
	^rtUnitOsr
!
optimize: m lower: h
	"Compile m with the optimizer, link it to its lower-tier header h and install it; null if it could not."
	<function>
	| o t0 |
	t0 := runtime nowUs.
	o := runtime compile: m mode: runtime optMode notes: runtime notes.
	rtStatOptUs := rtStatOptUs + (runtime nowUs - t0) asUInt64.
	o isNull ifTrue: [^self null].
	rtAllCount < OPT_MAX_HEADERS
		ifTrue: [
			rtAll at: rtAllCount put: o.
			rtAllCount := rtAllCount + 1]
		ifFalse: [runtime requestFlush].
	cache beginWriting.
	h opt: (self cCoerce: o to: 'uint64_t').
	o lower: (self cCoerce: h to: 'uint64_t').
	o stamp: rtStamp.
	cache endWriting.
	self noteYoung: o.
	(runtime hasCode: o) ifFalse: [^self null].
	runtime codeChanged: m.
	^o
!
compile: m
	"Emit optimized code for m at the assembler's pc (JitRuntime>>compile:mode:notes:); answer whether it could."
	<function>
	| ok trace limit |
	trace := (libc getenv: 'SAMALTAK_OPT_TRACE') notNull.
	rtTrace := trace.
	rtTraceSends := (libc getenv: 'SAMALTAK_OPT_SENDS') notNull.
	limit := libc getenv: 'SAMALTAK_OPT_LIMIT'.
	(limit notNull and: [rtStatOptCompiled >= (libc atol: limit) asUInt64]) ifTrue: [^false].
	trace ifTrue: [
		libc fprintf: libc stderr format: 'opt: (block %d, loop %d) ' with: rtUnitStart with: rtUnitOsr.
		interpreter printActivation: m receiver: memory nilOop closure: memory nilOop on: libc stderr].
	builder frame: rtUnitFrame.
	builder foreign: rtUnitSignature ~= 0.
	passes unboxOff: false.
	ok := self buildAndAllocate: m trace: trace.
	"twins on doubles that make the compilation fail: again without them"
	(ok not and: [passes unboxed]) ifTrue: [
		passes unboxOff: true.
		ok := self buildAndAllocate: m trace: trace.
		passes unboxOff: false].
	ok := ok and: [
		trace ifTrue: [
			libc fputs: 'allocated:
' to: libc stderr.
			ir print].
		codegen generate: m act: 0].
	"the analysis the runtime reads afterwards is m's"
	analysis analyze: m.
	ok ifFalse: [rtStatOptFailed := rtStatOptFailed + 1].
	trace ifTrue: [libc fprintf: libc stderr format: 'opt: %s
' with: (ok ifTrue: ['ok'] ifFalse: ['failed'])].
	^ok
!
buildAndAllocate: m trace: trace
	"The unit's IR built, cleaned up and allocated; answer whether it could be."
	^(builder build: m start: rtUnitStart osr: (rtUnitOsr bitAnd: 16rFFFF) - 1 depth: rtUnitDepth resident: (rtUnitOsr bitAnd: 16r10000) ~= 0) and: [
		passes cleanup: builder entryBlock.
		trace ifTrue: [ir print].
		ir full not and: [regalloc allocate: builder paramSlots valid: builder validSlots]]
!
extraBytes
	"What the optimized code's header needs after its notes: the safepoint table, the records, the dependencies, the inline caches and the return map."
	^4 * (codegen spCount + codegen metaCount + codegen depCount) + 16 + (32 * codegen siteCount) + (12 * codegen retCount)
!
siteCount
	"Inline caches of the code being compiled (their literals are registered with the collector)."
	^codegen siteCount
!
writeExtra: h at: p
	"Fill the optimized header h's own fields and write its tables at p; answer the address after them."
	| q site |
	h slots: codegen slotTop asUInt32.
	h rawBase: codegen rawBase asUInt32.
	h bcSize: (self methodSize: h method) asUInt32.
	h poolOffset: codegen poolOffset asUInt32.
	h poolCount: codegen poolCount asUInt32.
	h spCount: codegen spCount asUInt32.
	h spTable: (self cCoerce: p to: 'int32_t *').
	0 to: codegen spCount - 1 do: [:i | h spTable at: i put: (codegen spTableAt: i)].
	q := p + (4 * codegen spCount).
	h meta: (self cCoerce: q to: 'int32_t *').
	0 to: codegen metaCount - 1 do: [:i | h meta at: i put: (codegen metaAt: i)].
	q := q + (4 * codegen metaCount).
	h depCount: codegen depCount asUInt32.
	h deps: (self cCoerce: q to: 'int32_t *').
	0 to: codegen depCount - 1 do: [:i | h deps at: i put: (codegen depAt: i)].
	q := ((q + (4 * codegen depCount)) + 7) bitClear: 7.
	"inline caches as baseline code's (JitBaselineRuntime links them): pc the safepoint, depth the selector's pool index"
	h sites: (self cCoerce: q to: 'BaselineSite *').
	h siteCount: codegen siteCount asUInt32.
	0 to: codegen siteCount - 1 do: [:i |
		site := h sites + i.
		site bl: (codegen siteBlAt: i).
		site lit: ((codegen siteLitAddressAt: i) - h codeStart) asUInt32.
		site info: (codegen siteInfoAt: i).
		site pc: (codegen siteIndexAt: i) asUInt16.
		site depth: (codegen siteSelectorAt: i) asUInt16.
		site target: 0.
		site pic: 0.
		brt registerSlot: (codegen siteLitAddressAt: i)].
	q := q + (32 * codegen siteCount).
	"the return map: return offset, safepoint, argument count"
	h rets: (self cCoerce: q to: 'uint32_t *').
	h retCount: codegen retCount asUInt32.
	0 to: codegen retCount - 1 do: [:i |
		h rets at: 3 * i put: (codegen retOffAt: i).
		h rets at: 3 * i + 1 put: (codegen retIndexAt: i) asUInt32.
		h rets at: 3 * i + 2 put: (codegen retArgcAt: i) asUInt32].
	rtStatOptCompiled := rtStatOptCompiled + 1.
	rtStatOptBytecodes := rtStatOptBytecodes + h bcSize asUInt64.
	rtStatOptBytes := rtStatOptBytes + h codeSize asUInt64.
	^q + (12 * codegen retCount)
!
noteYoung: o
	"o's method or a pool entry is young: scavenges visit it."
	| young |
	young := self isYoung: o method.
	0 to: o poolCount asInt64 - 1 do: [:i | ((self isPtr: (self poolAt: i of: o)) and: [self isYoung: (self poolAt: i of: o)]) ifTrue: [young := true]].
	young ifFalse: [^self].
	rtOptYoungCount < OPT_MAX_YOUNG
		ifTrue: [
			rtOptYoung at: rtOptYoungCount put: o.
			rtOptYoungCount := rtOptYoungCount + 1]
		ifFalse: [rtOptYoungOverflow := true]
! !

!OptRuntime methodsFor: 'sends'!
send: f index: k site: key
	"Optimized code sends at safepoint k of f (its pc and sp set, receiver and arguments at slot slots; key: the site, for the interpreter's inline cache): answer 0 (the result is in that slot), 1 (leave) or the callee's entry (frame pushed)."
	<function>
	| h rec info n kind sp sel base r cls e ns ok moved |
	rtStatSends := rtStatSends + 1.
	h := self cCoerce: f code to: 'JitMethod *'.
	rec := self recordOf: h index: k.
	info := rec at: 2.
	n := (info bitAnd: 255) asInt32.
	kind := (info >> 8) bitAnd: 255.
	sp := (info >> 16) bitAnd: 255.
	sel := self poolAt: (rec at: 3) of: h.
	rtTraceSends ifTrue: [
		interpreter printSymbol: sel on: libc stderr.
		libc fputs: ' in ' to: libc stderr.
		interpreter printActivation: h method receiver: memory nilOop closure: memory nilOop on: libc stderr].
	base := f fp + h slots asInt64.
	r := base at: 0.
	(gc forwardersExist and: [memory isForwarder: r]) ifTrue: [
		r := memory follow: r.
		base at: 0 put: r].
	kind = 2 ifTrue: [
		r := runtime specialFast: sp base: base.
		r ~= 0 ifTrue: [
			base at: 0 put: r.
			^0].
		r := base at: 0.
		((sp = 21 or: [sp = 22 or: [sp = 30]]) and: [(self isPtr: r) and: [(self rawClass: r) = memory clsBlock and: [(self loadRef: r at: BC_NUMARGS) = (self intOop: n)]]]) ifTrue: [
			runtime sync: f.
			moved := interpreter frameEpoch.
			interpreter activateBlock: n.
			"no room for its frame: the frames became Contexts, the interpreter goes on"
			interpreter frameEpoch ~= moved ifTrue: [^1].
			^runtime entryOfTop]].
	cls := kind = 1
		ifTrue: [self loadRef: (self loadRef: (self innermostMethodOf: rec h: h) at: CM_CLASS) at: BEH_SUPERCLASS]
		ifFalse: [interpreter receiverClass: r].
	e := interpreter icacheAt: (self cCoerce: key to: 'uint8_t *').
	(e cls = cls and: [e sel = key]) ifFalse: [
		e := interpreter siteEntry: (self cCoerce: key to: 'uint8_t *') class: cls selector: sel.
		e isNull ifTrue: [^self doesNotUnderstand: sel class: cls frame: f index: k argc: n]].
	(e kind bitAnd: runtime kConst) ~= 0 ifTrue: [
		e qconst ~= 0 ifTrue: [base at: 0 put: e qconst].
		^self sent: f].
	((e kind bitAnd: runtime kQuick) ~= 0 and: [n = 0 and: [(self isPtr: r) and: [(self formatOf: r) <= F_FIXVAR and: [(self numSlots: r) > e quick asUInt32]]]]) ifTrue: [
		base at: 0 put: (self loadRef: r at: e quick).
		^self sent: f].
	((e kind bitAnd: runtime kSetter) ~= 0 and: [e nset = n and: [(self isPtr: r) and: [((self header: r) bitAnd: H_IMMUTABLE) = 0 and: [(self formatOf: r) <= F_FIXVAR]]]]) ifTrue: [
		ns := self numSlots: r.
		ok := true.
		0 to: n - 1 do: [:j | ok := ok and: [(e setIvar at: j) < ns]].
		ok ifTrue: [
			0 to: n - 1 do: [:j | self storeRef: r at: (e setIvar at: j) put: (base at: 1 + j)].
			^self sent: f]].
	"a leaf primitive neither collects nor leaves: the frames below need not be canonical"
	((e kind bitAnd: runtime kLeaf) ~= 0 and: [runtime callLeaf: e base: base argc: n]) ifTrue: [^self sent: f].
	runtime sync: f.
	(runtime isPerform: e) ifTrue: [^self perform: e frame: f index: k argc: n].
	runtime sendPushed: 0.
	r := runtime dispatch: e frame: f argc: n.
	"a primitive answered: a safepoint (the profiler samples an allocation there)"
	r = 0 ifTrue: [^self sent: f].
	^r
!
sendFrom: f ret: ret
	"A call of f's optimized code (at the call safepoint return address ret is in; JitBaselineRuntime>>setTop:ret:mode: set its pc and sp) found no machine code it may call (not linked: what baseline code leaves to the interpreter for; or no room on the stack): the runtime sends. Answer where the call continues: the callee's entry (its frame pushed), the sent stub (the result is in the receiver's slot) or 1 (leave)."
	<function>
	| h r |
	h := self cCoerce: f code to: 'JitMethod *'.
	r := self send: f index: (f pc - h bcSize asInt32) asInt64 site: ret.
	r = 0 ifTrue: [^stubs blSentStub].
	^r
!
perform: e frame: f index: k argc: n
	"Safepoint k of f sends a perform: (entry e, n arguments): send its selector as the primitive does (Interpreter>>primResend:argc:), the arguments moved down over the selector. A send that would not complete here (the primitive fails, cannotSend:base:) leaves before the perform:, which the interpreter executes again."
	| base sel arr m g |
	base := f fp + (f sp - n - 1).
	sel := base at: 1.
	arr := n = 2 ifTrue: [base at: 2] ifFalse: [memory nilOop].
	m := (runtime isPerformWithArguments: e)
		ifTrue: [((self isPtr: arr) and: [(self rawClass: arr) = memory clsArray]) ifTrue: [(self numSlots: arr) asInt32] ifFalse: [-1]]
		ifFalse: [n - 1].
	g := (m >= 0 and: [(interpreter selectorArgc: sel) = m]) ifTrue: [interpreter entryFor: (interpreter receiverClass: (base at: 0)) selector: sel] ifFalse: [self null].
	(self cannotSend: g base: base) ifTrue: [^self leaveBefore: f index: k].
	(runtime isPerformWithArguments: e)
		ifTrue: [0 to: m - 1 do: [:i | base at: 1 + i put: (self loadRef: arr at: i)]]
		ifFalse: [libc memmove: base + 1 from: base + 2 size: m asUInt64 * 8].
	interpreter activeSetStackp: f sp - n + m.
	^self resend: g frame: f argc: m
!
doesNotUnderstand: sel class: cls frame: f index: k argc: n
	"Safepoint k of f sends sel, which cls does not understand: send doesNotUnderstand: with a Message of sel and the arguments, over them, as the interpreter does (Interpreter>>sendDoesNotUnderstand). If that would not complete here (cannotSend:base:) leave before the send."
	| base roots msg isize |
	base := f fp + (f sp - n - 1).
	(self cannotSend: (interpreter entryFor: cls selector: (memory special: SO_SEL_DNU)) base: base) ifTrue: [^self leaveBefore: f index: k].
	runtime sync: f.
	"allocating may collect: sel, cls and the Array are roots, the arguments are in slots"
	roots := self local: 'oop[3]'.
	roots at: 0 put: sel.
	roots at: 1 put: cls.
	memory pushRoot: roots.
	memory pushRoot: roots + 1.
	roots at: 2 put: (memory allocObj: memory clsArray format: F_VAR slots: n asUInt32).
	libc memcpy: (self slotsOf: (roots at: 2)) from: base + 1 size: n asUInt64 * 8.
	gc rememberIfOld: (roots at: 2).
	memory pushRoot: roots + 2.
	isize := (self intVal: (self loadRef: memory clsMessage at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	msg := memory allocObj: memory clsMessage format: F_FIXED slots: (isize < 2 ifTrue: [2] ifFalse: [isize]) asUInt32.
	memory popRoot.
	memory popRoot.
	memory popRoot.
	self storeRef: msg at: MSG_SELECTOR put: (roots at: 0).
	self storeRef: msg at: MSG_ARGS put: (roots at: 2).
	base at: 1 put: msg.
	interpreter activeSetStackp: f sp - n + 1.
	^self resend: (interpreter entryFor: (roots at: 1) selector: (memory special: SO_SEL_DNU)) frame: f argc: 1
!
cannotSend: g base: base
	"The send of g's method to the receiver at base cannot complete here: not understood (g null), perform: again, no room for its frame."
	^g isNull or: [(runtime isPerform: g) or: [(self cCoerce: base + (1 + g fsize) to: 'uint64_t') > interpreter cstackLimit]]
!
resend: g frame: f argc: n
	"Send g's method to the receiver and n arguments on top of f (they replaced a perform:'s or a send's): answer as send:index:site:."
	| r |
	runtime sendPushed: 0.
	r := runtime dispatch: g frame: f argc: n.
	r = 0 ifTrue: [^self sent: f].
	^r
!
sent: f
	"A send completed without a frame: a safepoint, as in the interpreter."
	runtime state interrupt = 0 ifTrue: [^0 asUInt64].
	f sp: ((self cCoerce: f code to: 'JitMethod *') slots + 1) asInt32.
	^runtime interrupt: f
!
innermostMethodOf: rec h: h
	| p nacts m |
	nacts := rec at: 4.
	p := 5.
	m := memory nilOop.
	0 to: nacts - 1 do: [:j |
		m := self poolAt: (rec at: p) of: h.
		p := p + 5 + (rec at: p + 4)].
	^m
!
leave: f after: after
	"The runtime leaves to the interpreter while optimized frame f (on top) sends: before the send (it is executed again) or after it (its result pushed)."
	<function>
	| h |
	h := self cCoerce: f code to: 'JitMethod *'.
	^self deoptFrame: f index: f pc - h bcSize asInt32 regs: self null mode: (after ifTrue: [2] ifFalse: [1])
!
leaveBefore: f index: k
	runtime sync: f.
	^self deoptFrame: f index: k regs: self null mode: 1
!
makeArray: f count: n
	"Optimized code's 0x94 at f's safepoint (pc and sp stored; eden full, or more than 64 elements): an Array of the n slots below f's sp. It may collect, it never switches processes nor deoptimizes."
	<function>
	<var: #f type: 'Frame *'>
	<var: #n type: 'uint64_t'>
	<returns: 'oop'>
	runtime sync: f.
	^runtime newArray: n asUInt32 from: f fp + (f sp asInt64 - n asInt64)
!
stackFull: f
	"No room for f's optimized frame at its entry: the interpreter runs it from pc 0 (f's pc and sp stored)."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	| h |
	h := self cCoerce: f code to: 'JitMethod *'.
	f code: h lower.
	^0
! !

!OptRuntime methodsFor: 'deoptimization'!
deoptGuard: f index: k
	"A guard of f's code failed at safepoint k; the registers are in the JitState's dump. Rebuild f's activations as frames; the interpreter continues the top one."
	<function>
	<var: #f type: 'Frame *'>
	<var: #k type: 'int64_t'>
	<returns: 'uint64_t'>
	| h why r m pc fresh stressed sig rec met |
	runtime canonicalizeBelow: f.
	h := self cCoerce: f code to: 'JitMethod *'.
	rec := self recordOf: h index: k.
	why := (rec at: 0) >> 8.
	"--jit-flags deopt: no feedback from the stress"
	stressed := (runtime flag: runtime deoptFlag) and: [runtime state stress <= 0].
	stressed ifTrue: [why := 0].
	met := (why = feedback deoptHoisted and: [(rec at: 2) ~= 0]) and: [self noteHoisted: rec of: h frame: f].
	r := self deoptFrame: f index: k regs: runtime state dump mode: 0.
	"a block unit's ^ (the interpreter does it every time): the unit is not optimized again"
	((self methodBytecodes: (rtActMethod at: rtActCount - 1)) at: (rtActPc at: rtActCount - 1)) = 16r7C ifTrue: [
		(self isAlive: h) ifTrue: [
			self noteFailed: h method start: h blockStart asInt32 osr: h osrPc asInt32.
			self invalidate: h].
		^r].
	"the innermost activation's method and pc: where the guard's bytecode is; feedback it had not given: compile again now"
	(why = feedback deoptArith or: [why = feedback deoptOther]) ifTrue: [why := why bitOr: (self operandFlagsAt: (rtActMethod at: rtActCount - 1) pc: (rtActPc at: rtActCount - 1)) asInt32].
	fresh := false.
	why ~= 0 ifTrue: [
		m := rtActMethod at: rtActCount - 1.
		pc := rtActPc at: rtActCount - 1.
		"a guard moved before a loop reports at the send it came from"
		why = feedback deoptHoisted ifTrue: [
			m := self poolAt: (rec at: 3) of: h.
			pc := rec at: 1].
		sig := self signatureAt: m pc: pc.
		"a class guard moved before a loop that met a class its send had not reported (when its code was compiled): the next code has that case, the guard may stay before the loop"
		met ifFalse: [feedback noteFlags: m pc: pc flags: why asUInt32].
		(why bitAnd: feedback deoptClass) ~= 0 ifTrue: [self noteReceiverAt: m pc: pc].
		fresh := met or: [(self signatureAt: m pc: pc) ~= sig].
		fresh ifTrue: [
			rtStamp := rtStamp + 1.
			(feedback siteAt: m pc: pc) stamp: rtStamp].
		"in code compiled before the feedback said it: compile again now; again in code compiled with it: speculate no more here"
		(fresh not and: [self isAlive: h]) ifTrue: [
			(feedback siteAt: m pc: pc) stamp > h stamp
				ifTrue: [fresh := true]
				ifFalse: [
					why := why bitOr: feedback deoptOther asInt32.
					fresh := ((feedback flagsAt: m pc: pc) bitAnd: feedback deoptOther) = 0.
					feedback noteFlags: m pc: pc flags: why asUInt32]].
		(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
			libc fprintf: libc stderr format: 'deopt why %d fresh %d flags now %d at pc %d of ' with: why with: (fresh ifTrue: [1] ifFalse: [0]) with: (feedback flagsAt: m pc: pc) with: pc.
			interpreter printActivation: m receiver: memory nilOop closure: memory nilOop on: libc stderr]].
	stressed ifTrue: [^r].
	cache beginWriting.
	h deopts: h deopts + 1.
	cache endWriting.
	(fresh or: [h deopts > OPT_MAX_DEOPTS]) ifTrue: [self invalidate: h].
	^r
!
noteHoisted: rec of: h frame: f
	"A class guard moved before a loop failed (rec: its record): the class of its value, still where the code had it, is feedback for the send it came from, as noteReceiverAt:pc: has it of a guard at the send. Answer whether that explains the failure: the send had not reported that class, or not when h was compiled."
	| m pc k sig |
	m := self poolAt: (rec at: 3) of: h.
	pc := rec at: 1.
	rtDeoptCount := 0.
	k := self value: (rec at: 2) - 1 h: h frame: f regs: runtime state dump.
	sig := self signatureAt: m pc: pc.
	feedback noteSend: m pc: pc class: (interpreter receiverClass: (self followed: (rtDeoptVals at: k))).
	^(self signatureAt: m pc: pc) ~= sig or: [(feedback siteAt: m pc: pc) stamp > h stamp]
!
signatureAt: m pc: pc
	"What the site at m's pc reports: its flags and how many classes."
	| s n |
	s := feedback siteAt: m pc: pc.
	s isNull ifTrue: [^-1].
	n := 0.
	0 to: feedback classSlots - 1 do: [:i | (s classes at: i) ~= 0 ifTrue: [n := n + 1]].
	^s flags asInt64 + (n << 32)
!
noteReceiverAt: m pc: pc
	"A class guard of the send at m's pc failed: its receiver (on the rebuilt top frame; a superinstruction's is the temp it pushes first) is feedback, the next type switch takes its class too."
	| p g i |
	p := (self methodBytecodes: m) + pc.
	g := interpreter frames + (interpreter nframes - 1).
	i := (analysis pushesOf: p) > 0
		ifTrue: [(p at: 1) asInt64]
		ifFalse: [(g sp - (analysis sendArgcOf: p) - 1) asInt64].
	i >= 0 ifTrue: [
		feedback noteSend: m pc: pc class: (interpreter receiverClass: (self followed: (g fp at: i))).
		(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
			libc fprintf: libc stderr format: 'deopt receiver %lld (Array %lld): ' with: (interpreter receiverClass: (self followed: (g fp at: i))) with: memory clsArray.
			interpreter printClassName: (interpreter receiverClass: (self followed: (g fp at: i))) on: libc stderr.
			libc fputc: 10 to: libc stderr]]
!
operandFlagsAt: m pc: pc
	"An arithmetic guard of the instruction at m's pc failed: its operands (on top of the rebuilt top frame, or the temps a superinstruction pushes) were Floats, or something neither a Float nor a SmallInteger (feedback)."
	| g p op fl |
	g := interpreter frames + (interpreter nframes - 1).
	p := (self methodBytecodes: m) + pc.
	op := p at: 0.
	(analysis pushesOf: p) > 0 ifTrue: [
		fl := feedback flagsOf: (g fp at: (p at: 1)).
		(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]]) ifTrue: [fl := fl bitOr: (feedback flagsOf: (g fp at: (p at: 2)))].
		^fl].
	fl := 0.
	g sp - 2 to: g sp - 1 do: [:i | i >= 0 ifTrue: [fl := fl bitOr: (feedback flagsOf: (g fp at: i))]].
	^fl
!
returnBottom: f index: k
	"Frame f (the bottom frame) returns into activeCtx at safepoint k (its state: the return bytecode, the result on top; the registers in the JitState's dump), as the interpreter's returnTop does; if activeCtx is dead the interpreter does it (deoptimize)."
	<function>
	<var: #f type: 'Frame *'>
	<var: #k type: 'int64_t'>
	<returns: 'uint64_t'>
	| h ctx sp v |
	h := self cCoerce: f code to: 'JitMethod *'.
	ctx := interpreter activeCtx.
	(self isInt: (self loadRef: ctx at: CTX_PC)) ifFalse: [^self deoptFrame: f index: k regs: runtime state dump mode: 0].
	self decode: h index: k frame: f regs: runtime state dump mode: 0.
	"a double that is no SmallFloat64 (a BoxedFloat64 to make): the interpreter does it"
	rtFloatCount > 0 ifTrue: [^self deoptFrame: f index: k regs: runtime state dump mode: 0].
	"return top: the stack's top; return self: the receiver"
	v := ((self methodBytecodes: (rtActMethod at: 0)) at: (rtActPc at: 0)) = 16r7A
		ifTrue: [rtDeoptVals at: (rtActRcv at: 0)]
		ifFalse: [rtDeoptVals at: rtDeoptCount - 1].
	rtDeoptCount := 0.
	f ctx ~= memory nilOop ifTrue: [
		f sp: 0.
		interpreter widow: f].
	interpreter nframes: 0.
	interpreter cstackUsed: 0.
	sp := self intVal: (self loadRef: ctx at: CTX_STACKP).
	self storeRef: ctx at: CTX_FIXED + sp put: v.
	(self slotsOf: ctx) at: CTX_STACKP put: (self intOop: sp + 1).
	gc rememberIfOld: ctx.
	runtime noteBottomReturn.
	^1
!
deoptReturn: f index: k notMade: notMade
	"After the send of safepoint k (the result in slot slots): f's code was invalidated (or stress), or (notMade 1) an allocation's send answered no instance of its class: rebuild its activations; for the allocation the send's feedback says so (the next compilation sends it) and the code goes."
	<function>
	<var: #f type: 'Frame *'>
	<var: #k type: 'int64_t'>
	<var: #notMade type: 'int64_t'>
	<returns: 'uint64_t'>
	| h r |
	runtime canonicalizeBelow: f.
	h := self cCoerce: f code to: 'JitMethod *'.
	r := self deoptFrame: f index: k regs: self null mode: 2.
	notMade ~= 0 ifTrue: [
		feedback noteFlags: (rtActMethod at: rtActCount - 1) pc: ((self recordOf: h index: k) at: 1) flags: feedback deoptOther.
		self invalidate: h].
	^r
!
deoptFrame: f index: k regs: regs mode: mode
	"Rebuild optimized frame f (the top frame) as the frames of its activations at safepoint k. mode 0: as recorded (a guard, an interrupt check), 1: before the send (it is executed again), 2: after it (its result pushed). Doubles that are no SmallFloat64s become BoxedFloat64s, closures the code never made are made now (their outer activations' frames married). Answer 1 (leave: the interpreter continues the top frame)."
	<function>
	<returns: 'uint64_t'>
	| h fi g sunk |
	h := self cCoerce: f code to: 'JitMethod *'.
	rtStatDeopts := rtStatDeopts + 1.
	runtime resetStress.
	self decode: h index: k frame: f regs: regs mode: mode.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [self traceDeopt: h index: k mode: mode].
	fi := (f - interpreter frames) asInt32.
	self writeFrames: fi from: f fp.
	rtFloatCount > 0 ifTrue: [
		self boxFloats.
		self writeFrames: fi from: f fp].
	0 to: rtSunkCount - 1 do: [:j |
		sunk := rtSunkOrder at: j.
		g := interpreter frames + fi + (rtSunkAct at: sunk).
		interpreter marry: g.
		self makeSunk: sunk outer: g ctx.
		self writeFrames: fi from: (interpreter frames + fi) fp].
	rtDeoptCount := 0.
	^1
!
writeFrames: fi from: fp0
	"The activations' frames from frame fi on, the first one's slots at fp0, their values from deoptVals (married frames stay married)."
	| fp g m d cl |
	fp := fp0.
	0 to: rtActCount - 1 do: [:i |
		g := interpreter frames + (fi + i).
		m := rtActMethod at: i.
		d := rtActDepth at: i.
		i > 0 ifTrue: [fp := fp + (rtActDepth at: i - 1) + 1].
		fp at: -1 put: (self followed: (rtDeoptVals at: (rtActRcv at: i))).
		0 to: d - 1 do: [:s | fp at: s put: (rtDeoptVals at: (rtActVals at: i) + s)].
		cl := (rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop].
		(i >= rtWritten and: [i > 0]) ifTrue: [g ctx: memory nilOop].
		g method: m.
		g closure: cl.
		g code: (runtime blockCodeFor: m).
		g fp: fp.
		g ip: (self methodBytecodes: m) + (rtActPc at: i).
		g pc: (rtActPc at: i).
		g lits: (self slotsOf: (self literalsOf: m)).
		g sp: d].
	rtWritten := rtActCount.
	interpreter nframes: fi + rtActCount.
	interpreter cstackUsed: (fp + (rtActDepth at: rtActCount - 1) - interpreter cstackBase) asUInt64
!
makeSunk: s outer: ctx
	"Make the closure of sunk entry s, its outerContext ctx; every value that was it becomes it."
	<function>
	| r b bc isize info o |
	r := self local: 'oop'.
	r value: ctx.
	memory pushRoot: r.
	bc := memory clsBlock.
	isize := (self intVal: (self loadRef: bc at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	b := memory allocObj: bc format: F_FIXED slots: (isize < 5 ifTrue: [5] ifFalse: [isize]) asUInt32.
	memory popRoot.
	info := rtSunkInfo at: s.
	o := self slotsOf: b.
	o at: BC_OUTER put: r value.
	o at: BC_STARTPC put: (self intOop: (rtSunkStart at: s)).
	o at: BC_NUMARGS put: (self intOop: (info bitAnd: 255)).
	o at: BC_NUMTEMPS put: (self intOop: ((info >> 8) bitAnd: 255)).
	o at: BC_FRAMESIZE put: (self intOop: ((info >> 16) bitAnd: 255)).
	gc rememberIfOld: b.
	0 to: rtSunkUseCount - 1 do: [:i | (rtSunkUseId at: i) = s ifTrue: [rtDeoptVals at: (rtSunkUseVal at: i) put: b]]
!
decode: h index: k frame: f regs: regs mode: mode
	"Read safepoint k's record into the activation arrays, the values into deoptVals (GC roots), the closures never made into the sunk arrays (in the order of the activations that make them), the doubles that are no SmallFloat64s into the float arrays (nil in deoptVals until boxFloats). mode 1 pushes the send's receiver and arguments (and goes back to the send), 2 its result."
	<function>
	| rec p nacts d base sendPc argc op bcs ns t |
	rec := self recordOf: h index: k.
	sendPc := rec at: 1.
	argc := ((rec at: 2) bitAnd: 255) asInt32.
	nacts := rec at: 4.
	p := 5.
	rtDeoptCount := 0.
	rtSunkUseCount := 0.
	rtFloatCount := 0.
	rtWritten := 0.
	rtActCount := nacts.
	0 to: nacts - 1 do: [:j |
		rtActMethod at: j put: (self poolAt: (rec at: p) of: h).
		rtActClosure at: j put: ((rec at: p + 1) < 0 ifTrue: [-1] ifFalse: [self value: (rec at: p + 1) h: h frame: f regs: regs]).
		(rec at: p + 1) = -2 ifTrue: [
			"a block unit's closure: its frame's"
			self push: f closure.
			rtActClosure at: j put: rtDeoptCount - 1].
		rtActRcv at: j put: (self value: (rec at: p + 2) h: h frame: f regs: regs).
		rtActPc at: j put: (rec at: p + 3).
		d := rec at: p + 4.
		rtActDepth at: j put: d.
		rtActVals at: j put: rtDeoptCount.
		0 to: d - 1 do: [:i | self value: (rec at: p + 5 + i) h: h frame: f regs: regs].
		p := p + 5 + d].
	ns := rec at: p.
	p := p + 1.
	rtSunkCount := ns.
	0 to: ns - 1 do: [:j |
		rtSunkAct at: j put: (rec at: p).
		rtSunkStart at: j put: (rec at: p + 1).
		rtSunkInfo at: j put: (rec at: p + 2).
		rtSunkOrder at: j put: j.
		p := p + 3].
	"outer activations' closures first"
	1 to: ns - 1 do: [:j |
		t := rtSunkOrder at: j.
		d := j - 1.
		[d >= 0 and: [(rtSunkAct at: (rtSunkOrder at: d)) > (rtSunkAct at: t)]] whileTrue: [
			rtSunkOrder at: d + 1 put: (rtSunkOrder at: d).
			d := d - 1].
		rtSunkOrder at: d + 1 put: t].
	base := f fp + h slots asInt64.
	mode = 2 ifTrue: [
		self push: (base at: 0).
		rtActDepth at: nacts - 1 put: (rtActDepth at: nacts - 1) + 1].
	mode = 1 ifTrue: [
		bcs := self methodBytecodes: (rtActMethod at: nacts - 1).
		op := bcs at: sendPc.
		((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifFalse: [
			self push: (base at: 0).
			"a perform: of a constant selector sent it: the selector goes back between receiver and arguments"
			((rec at: 2) bitAnd: SI_PERFORMED) ~= 0 ifTrue: [
				self push: (self poolAt: (rec at: 3) of: h).
				rtActDepth at: nacts - 1 put: (rtActDepth at: nacts - 1) + 1].
			1 to: argc do: [:i | self push: (base at: i)].
			rtActDepth at: nacts - 1 put: (rtActDepth at: nacts - 1) + argc + 1].
		rtActPc at: nacts - 1 put: sendPc]
!
traceDeopt: h index: k mode: mode
	<function>
	libc fprintf: libc stderr format: 'deopt mode %d at %lld (unit loop %d), %d activations, ' with: mode with: k with: h osrPc with: rtActCount.
	libc fprintf: libc stderr format: 'innermost pc %d depth %d: ' with: (rtActPc at: rtActCount - 1) with: (rtActDepth at: rtActCount - 1).
	interpreter printActivation: h method receiver: memory nilOop closure: memory nilOop on: libc stderr
!
push: v
	"v at the end of deoptVals (it extends the innermost activation)."
	rtDeoptCount < OPT_MAX_DEOPT_VALS ifTrue: [
		rtDeoptVals at: rtDeoptCount put: v.
		rtDeoptCount := rtDeoptCount + 1]
!
value: loc h: h frame: f regs: regs
	"Append the value at location loc to deoptVals; answer its index."
	| kind payload v |
	kind := loc bitAnd: 7.
	payload := loc asInt64 >> 3.
	v := memory nilOop.
	kind = LOC_SLOT ifTrue: [v := f fp at: payload].
	kind = LOC_REG ifTrue: [v := regs at: payload].
	kind = LOC_CONST ifTrue: [v := self poolAt: payload of: h].
	kind = LOC_SMI ifTrue: [v := self intOop: payload].
	kind = LOC_DREG ifTrue: [^self double: (regs at: 32 + payload) at: loc].
	kind = LOC_RAW ifTrue: [^self double: (f fp at: payload) at: loc].
	(kind = LOC_SUNK and: [rtSunkUseCount < OPT_MAX_DEOPT_VALS]) ifTrue: [
		rtSunkUseVal at: rtSunkUseCount put: rtDeoptCount.
		rtSunkUseId at: rtSunkUseCount put: payload asInt32.
		rtSunkUseCount := rtSunkUseCount + 1].
	self push: v.
	^rtDeoptCount - 1
!
double: b at: loc
	"Append the double with IEEE bits b at location loc to deoptVals as a Float; answer its index. One that is no SmallFloat64 (ObjectMemory>>floatOop:) is nil there until boxFloats makes it."
	<var: #b type: 'uint64_t'>
	| e v |
	v := memory nilOop.
	e := ((b >> 52) bitAnd: 16r7FF) asUInt32.
	(b << 1) asUInt64 = 0
		ifTrue: [v := ((b >> 63) << 3) bitOr: 4]
		ifFalse: [(e > 896 and: [e < 1151]) ifTrue: [v := ((((b << 1) asUInt64 bitOr: b >> 63) - (896 << 53)) << 3) bitOr: 4]].
	(v = memory nilOop and: [rtFloatCount < OPT_MAX_DEOPT_VALS and: [rtDeoptCount < OPT_MAX_DEOPT_VALS]]) ifTrue: [
		rtFloatVal at: rtFloatCount put: rtDeoptCount.
		rtFloatLoc at: rtFloatCount put: loc.
		rtFloatBits at: rtFloatCount put: b.
		rtFloatCount := rtFloatCount + 1].
	self push: v.
	^rtDeoptCount - 1
!
boxFloats
	"The decoded doubles that are no SmallFloat64s become BoxedFloat64s, one per location (values from one location are one object). Allocating may collect: the frames are valid, deoptVals are roots."
	| i j |
	i := 0.
	[i < rtFloatCount] whileTrue: [
		j := 0.
		[j < i and: [(rtFloatLoc at: j) ~= (rtFloatLoc at: i)]] whileTrue: [j := j + 1].
		j < i
			ifTrue: [rtDeoptVals at: (rtFloatVal at: i) put: (rtDeoptVals at: (rtFloatVal at: j))]
			ifFalse: [rtDeoptVals at: (rtFloatVal at: i) put: (memory floatOop: (self doubleFromBits: (rtFloatBits at: i)))].
		i := i + 1].
	rtFloatCount := 0
!
materialize: f
	"materializeAll meets optimized frame f: a Context for each of its activations (their senders chained from activeCtx), the last one activeCtx; the BoxedFloat64s of its doubles and the closures never made. The outermost activation's method counts --jit-osr backward jumps in the lower tier."
	<function>
	<var: #mode type: 'int32_t'>
	| h k mode top ctx n s first sunk c count full |
	h := self cCoerce: f code to: 'JitMethod *'.
	k := f pc - h bcSize asInt32.
	top := f = (interpreter frames + (interpreter nframes - 1)).
	mode := 0.
	(top and: [f sp = (h slots + 1) asInt32 and: [((self recordOf: h index: k) at: 0) = SP_CALL]]) ifTrue: [mode := 2].
	self decode: h index: k frame: f regs: self null mode: mode.
	"its method resumes in the lower tier: after as many backward jumps there as an interpreted loop makes before it is compiled (not a full count), it enters optimized code again (a loop that turns once per wake-up of its process stays in the lower tier, which these flushes cost less)"
	count := runtime osrThreshold.
	full := self initialCount: (rtActMethod at: 0).
	runtime counterFor: (rtActMethod at: 0) put: ((count max: 1) min: full).
	rtTrace ifTrue: [
		libc fprintf: libc stderr format: 'materialize top %d sp %d: ' with: (top ifTrue: [1] ifFalse: [0]) with: f sp.
		self traceDeopt: h index: k mode: mode].
	(top and: [mode = 0 and: [((self recordOf: h index: k) at: 0) = SP_CALL]]) ifTrue: [
		"a primitive is running: its receiver and arguments (up to sp: a perform: sends fewer) are on the stack, as the interpreter's"
		interpreter primBaseIndex: (rtActDepth at: rtActCount - 1).
		0 to: f sp - h slots asInt32 - 1 do: [:i | self push: ((f fp + h slots asInt64) at: i)].
		rtActDepth at: rtActCount - 1 put: rtDeoptCount - (rtActVals at: rtActCount - 1)].
	self boxFloats.
	"the Contexts (kept in deoptVals), then the closures, then the Contexts' contents"
	first := rtDeoptCount.
	0 to: rtActCount - 1 do: [:i |
		n := (self frameSizeOfAct: i) + CTX_SLACK.
		n < (rtActDepth at: i) ifTrue: [n := rtActDepth at: i].
		"a married frame (a loop's unit) keeps its Context"
		(i = 0 and: [f ctx ~= memory nilOop and: [(self numSlots: f ctx) >= (CTX_FIXED + n) asUInt32]])
			ifTrue: [ctx := f ctx]
			ifFalse: [ctx := memory allocContext: n asUInt32].
		self push: ctx].
	0 to: rtSunkCount - 1 do: [:j |
		sunk := rtSunkOrder at: j.
		self makeSunk: sunk outer: (rtDeoptVals at: first + (rtSunkAct at: sunk))].
	0 to: rtActCount - 1 do: [:i |
		c := rtDeoptVals at: first + i.
		s := self slotsOf: c.
		s at: CTX_SENDER put: interpreter activeCtx.
		s at: CTX_PC put: (self intOop: (rtActPc at: i)).
		s at: CTX_STACKP put: (self intOop: (rtActDepth at: i)).
		s at: CTX_METHOD put: (rtActMethod at: i).
		s at: CTX_CLOSURE put: ((rtActClosure at: i) >= 0 ifTrue: [rtDeoptVals at: (rtActClosure at: i)] ifFalse: [memory nilOop]).
		s at: CTX_RECEIVER put: (self followed: (rtDeoptVals at: (rtActRcv at: i))).
		0 to: (rtActDepth at: i) - 1 do: [:j | s at: CTX_FIXED + j put: (rtDeoptVals at: (rtActVals at: i) + j)].
		gc rememberIfOld: c.
		interpreter activeCtx: c].
	rtDeoptCount := 0
!
frameSizeOfAct: i
	"The frame size of decoded activation i: its closure's (made or not), else its method's."
	| c info |
	(rtActClosure at: i) < 0 ifTrue: [^self frameSizeOf: (rtActMethod at: i) closure: memory nilOop].
	0 to: rtSunkUseCount - 1 do: [:u |
		(rtSunkUseVal at: u) = (rtActClosure at: i) ifTrue: [
			info := rtSunkInfo at: (rtSunkUseId at: u).
			^((info >> 16) bitAnd: 255) max: (info bitAnd: 255) + ((info >> 8) bitAnd: 255)]].
	c := rtDeoptVals at: (rtActClosure at: i).
	^self frameSizeOf: (rtActMethod at: i) closure: c
!
frameSizeOf: m closure: c
	"frameSize of an activation of m or of block c (at least its arguments and temps), as Interpreter>>frameSize:."
	<function>
	| src fs min blk |
	blk := c ~= memory nilOop.
	src := blk ifTrue: [c] ifFalse: [m].
	fs := self intVal: (self loadRef: src at: (blk ifTrue: [BC_FRAMESIZE] ifFalse: [CM_FRAMESIZE])).
	min := blk
		ifTrue: [(self intVal: (self loadRef: src at: BC_NUMARGS)) + (self intVal: (self loadRef: src at: BC_NUMTEMPS))]
		ifFalse: [(self intVal: (self loadRef: src at: CM_NUMARGS)) + (self intVal: (self loadRef: src at: CM_NUMTEMPS))].
	^fs > min ifTrue: [fs] ifFalse: [min]
!
rawBaseOf: f
	"Optimized frame f's first raw slot (doubles' IEEE bits, no oops, up to its slots: rawTopOf:)."
	^(self cCoerce: f code to: 'JitMethod *') rawBase asInt64
!
rawTopOf: f
	^(self cCoerce: f code to: 'JitMethod *') slots asInt64
!
resume: f
	"The interpreter returns into optimized frame f (on top; the result is in slot slots): answer where its code continues, 0 if it was deoptimized (the interpreter continues the top frame)."
	<function>
	| h k off |
	h := self cCoerce: f code to: 'JitMethod *'.
	k := f pc - h bcSize asInt32.
	off := (self isAlive: h) ifTrue: [runtime mapOffsetOf: h pc: f pc] ifFalse: [-1].
	(off < 0 and: [k < 0]) ifTrue: [
		"not entered yet: the lower tier runs it"
		f code: h lower.
		^runtime addressFor: f].
	off < 0 ifTrue: [
		self deoptFrame: f index: k regs: self null mode: 2.
		^0].
	^h codeStart + off asUInt64
! !

!OptRuntime methodsFor: 'garbage collection'!
youngRoots: fn
	<function>
	| n o |
	self decodedRoots: fn.
	rtOptYoungOverflow ifTrue: [^self allPools: fn].
	rtOptYoungCount = 0 ifTrue: [^self].
	cache beginWriting.
	0 to: rtOptYoungCount - 1 do: [:i | self roots: (rtOptYoung at: i) fn: fn].
	cache endWriting.
	n := 0.
	0 to: rtOptYoungCount - 1 do: [:i |
		o := rtOptYoung at: i.
		(self stillYoung: o) ifTrue: [
			rtOptYoung at: n put: o.
			n := n + 1]].
	rtOptYoungCount := n asInt32
!
decodedRoots: fn
	"While activations are rebuilt (materialize: allocates): their methods and values."
	rtDeoptCount = 0 ifTrue: [^self].
	0 to: rtDeoptCount - 1 do: [:i | fn call: rtDeoptVals + i].
	0 to: rtActCount - 1 do: [:i | fn call: rtActMethod + i]
!
stillYoung: o
	(self isYoung: o method) ifTrue: [^true].
	0 to: o poolCount asInt64 - 1 do: [:i | ((self isPtr: (self poolAt: i of: o)) and: [self isYoung: (self poolAt: i of: o)]) ifTrue: [^true]].
	^false
!
allRoots: fn
	<function>
	self decodedRoots: fn.
	self allPools: fn
!
allPools: fn
	"Every optimized header's method and pool (in the code cache)."
	cache beginWriting.
	0 to: rtAllCount - 1 do: [:i | self roots: (rtAll at: i) fn: fn].
	cache endWriting
!
headerValid: o with: valid
	"The GC verifier: o's method and pool."
	<function>
	| pool |
	(valid call: o method) ifFalse: [
		libc fputs: 'optimized code: bad method
' to: libc stderr.
		^false].
	pool := self cCoerce: o codeStart + o poolOffset to: 'oop *'.
	0 to: o poolCount asInt64 - 1 do: [:i |
		((self isPtr: (pool at: i)) and: [(valid call: (pool at: i)) not]) ifTrue: [
			libc fprintf: libc stderr format: 'optimized code: bad pool entry %lld: %llx
' with: i with: (pool at: i).
			^false]].
	^true
!
roots: o fn: fn
	| pool |
	fn call: (o fieldAddress: #method).
	pool := self cCoerce: o codeStart + o poolOffset to: 'oop *'.
	0 to: o poolCount asInt64 - 1 do: [:i | (self isPtr: (pool at: i)) ifTrue: [fn call: pool + i]]
!
flushed
	"The code cache was flushed."
	<function>
	rtOptYoungCount := 0.
	rtOptYoungOverflow := false.
	rtAllCount := 0.
	libc memset: rtUnits value: 0 size: 8 * OPT_MAX_UNITS.
	libc memset: rtFailed value: 0 size: 8 * OPT_MAX_UNITS.
	rtUnitCount := 0.
	rtVariantCount := 0
!
release
	"All code was dropped (flushed): give back the pages of the optimizer's scratch areas; each compile starts them anew."
	<function>
	ir release.
	regalloc release
! !

!OptRuntime methodsFor: 'invalidation'!
invalidate: o
	"o's assumptions no longer hold: its code must not run again (frames running it deoptimize when they continue); its method or unit is optimized again later."
	| h |
	(self isAlive: o) ifFalse: [^self].
	rtStatInvalidations := rtStatInvalidations + 1.
	(o blockStart = 0 and: [o osrPc = 0]) ifTrue: [
		runtime counterFor: o method put: (self initialCount: o method).
		h := self cCoerce: o lower to: 'JitMethod *'.
		cache beginWriting.
		h opt: 0.
		cache endWriting.
		runtime codeChanged: o method].
	runtime kill: o
!
invalidateSelector: sel
	"A method for sel was added or removed: optimized code that inlined or speculated on a send of sel."
	<function>
	| o |
	0 to: rtAllCount - 1 do: [:i |
		o := rtAll at: i.
		0 to: o depCount asInt64 - 1 do: [:k | (self poolAt: (o deps at: k) of: o) = sel ifTrue: [self invalidate: o]]]
!
followed: o
	"o, or its target if o is a forwarder (becomeForward:)."
	gc forwardersExist ifFalse: [^o].
	^memory follow: o
!
invalidateEmbedding: o
	"becomeForward: made o a forwarder: code with o in its pool is invalidated (it may have folded o's class or fields). A young o can only be in the pools of the units scavenges visit."
	<function>
	((self isYoung: o) and: [rtOptYoungOverflow not])
		ifTrue: [0 to: rtOptYoungCount - 1 do: [:i | self invalidate: (rtOptYoung at: i) ifPoolHas: o]]
		ifFalse: [0 to: rtAllCount - 1 do: [:i | self invalidate: (rtAll at: i) ifPoolHas: o]]
!
invalidate: h ifPoolHas: o
	| pool found |
	(self isAlive: h) ifFalse: [^self].
	pool := self cCoerce: h codeStart + h poolOffset to: 'oop *'.
	found := false.
	0 to: h poolCount asInt64 - 1 do: [:k | (pool at: k) = o ifTrue: [found := true]].
	found ifTrue: [self invalidate: h]
!
invalidateAll
	<function>
	0 to: rtAllCount - 1 do: [:i | self invalidate: (rtAll at: i)]
!
