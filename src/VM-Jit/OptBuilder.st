OptModule subclass: #OptBuilder
	instanceVariableNames: 'obSlice ir obCurBlock obBailed obVarTop obDefKeys obDefVals obDefCount obIncPhis obIncVars obIncCount obAnaMethods obAnaBases obAnaCount obAnaTop obAnaDepth obAnaFlag obAnaBack obPcBlocks obPcbTop obEntryBlock obRootMethod obInlined obDeps obDepCount obPrimKinds obPrimsKnown obNoInline obNoInlineCount obArgVals obArgFlags obUnitStart obOsrPc obParamSlots obValidSlots obSafeEpoch obAnaFloat obAnaInts obResident obChecked obCheckedCount obCheckedBlock obCheckedEpoch obFrame obSpecParam obSpecInfo obSpecCount obForeign obForeignM obForeignS obForeignDepth obNoForeignM obNoForeignS obNoForeignCount obPerformAct obPerformPc obPerformSlot obPerformCount obPerformVals obAnaLive obNilConst obConstVals obConstNodes'
	classVariableNames: 'OA_BLOCK OA_LOOP OA_START OA_TARGET OPT_MAX_VARS OPT_MAX_NOINLINE OPT_MAX_PRIM OPK_AT OPK_FLOAT OPK_FSQRT OPK_NEW OPK_NEWSIZE OPK_CLOSURE OPK_ATPUT OPK_CLASS OPK_IDENTICAL OPK_INT OPK_SIZE OPK_STRINGAT OPK_STRINGATPUT OPT_INLINE_BUDGET OPT_INLINE_DEPTH OPT_INLINE_SIZE OPT_MAX_ANA OPT_MAX_DEPS OPT_MAX_INC OPK_CHARVALUE OPK_CHARFROM OPK_REPLACE OPK_STRHASH OPK_STRCMP'
	package: 'VM-Jit'!

OptBuilder comment: 'Builds the IR (OptIR) of a method from its bytecodes: an abstract interpretation of each activation''s bytecodes in pc order, its slots (arguments, temps, operand stack: the depths BytecodeAnalysis computed) SSA variables, phis made on demand (Braun et al., Simple and Efficient Construction of Static Single Assignment Form, CC 2013: a block is sealed once all its predecessors are known; jump targets when the scan reaches them, loop heads after their last backward jump). Sends, guards and interrupt checks get frame states (OptState) for deoptimization. bail abandons the method (a bytecode the tier does not compile).'!

!OptBuilder class methodsFor: 'declaring'!
declarations
	^#((obSlice bool) (ir OptIR) (obCurBlock int32_t) (obBailed bool) (obVarTop int32_t)
		(obDefKeys 'int32_t[OPT_DEF_SIZE]') (obDefVals 'int32_t[OPT_DEF_SIZE]') (obDefCount int32_t)
		(obIncPhis 'int32_t[OPT_MAX_INC]') (obIncVars 'int32_t[OPT_MAX_INC]') (obIncCount int32_t)
		(obAnaMethods 'oop[OPT_MAX_ANA]') (obAnaBases 'int32_t[OPT_MAX_ANA]') (obAnaCount int32_t) (obAnaTop int32_t)
		(obAnaDepth 'int16_t[OPT_ANA_MAX]') (obAnaFlag 'uint8_t[OPT_ANA_MAX]') (obAnaBack 'int32_t[OPT_ANA_MAX]')
		(obPcBlocks 'int32_t[OPT_PCB_MAX]') (obPcbTop int32_t) (obEntryBlock int32_t) (obRootMethod oop)
		(obInlined int32_t) (obDeps 'oop[OPT_MAX_DEPS]') (obDepCount int32_t) (obPrimKinds 'uint8_t[OPT_MAX_PRIM]') (obPrimsKnown bool)
		(obNoInline 'oop[OPT_MAX_NOINLINE]') (obNoInlineCount int32_t) (obArgVals 'int32_t[OPT_MAX_VARS]') (obArgFlags 'uint8_t[OPT_MAX_VARS]') (obUnitStart int32_t) (obOsrPc int32_t) (obParamSlots int32_t) (obValidSlots int32_t) (obSafeEpoch int32_t) (obAnaFloat 'bool[OPT_MAX_ANA]') (obAnaInts 'bool[OPT_MAX_ANA]') (obResident bool) (obChecked 'int32_t[8]') (obCheckedCount int32_t) (obCheckedBlock int32_t) (obCheckedEpoch int32_t) (obFrame 'Frame *') (obSpecParam 'int32_t[8]') (obSpecInfo 'int32_t[8]') (obSpecCount int32_t) (obForeign bool) (obForeignM 'oop[8]') (obForeignS 'int32_t[8]') (obForeignDepth int32_t) (obNoForeignM 'oop[8]') (obNoForeignS 'int32_t[8]') (obNoForeignCount int32_t)
		(obPerformAct int32_t) (obPerformPc int32_t) (obPerformSlot int32_t) (obPerformCount int32_t) (obPerformVals 'int32_t[8]')
		(obAnaLive 'uint64_t[OPT_ANA_MAX]') (obNilConst int32_t) (obConstVals 'uint64_t[256]') (obConstNodes 'int32_t[256]'))
!
initialize
	OPT_MAX_INC := 16384.
	OPT_MAX_ANA := 256.
	OPT_MAX_DEPS := 256.
	OPT_MAX_PRIM := 1024.
	OPT_MAX_NOINLINE := 8.
	OPT_MAX_VARS := 65536.
	OPK_AT := 1.
	OPK_ATPUT := 2.
	OPK_SIZE := 3.
	OPK_STRINGAT := 4.
	OPK_STRINGATPUT := 5.
	OPK_CLASS := 6.
	OPK_IDENTICAL := 7.
	OPK_INT := 32.
	OPK_FLOAT := 64.
	OPK_FSQRT := 8.
	OPK_NEW := 9.
	OPK_NEWSIZE := 10.
	OPK_CLOSURE := 11.
	OPK_CHARVALUE := 12.
	OPK_CHARFROM := 13.
	OPK_REPLACE := 14.
	OPK_STRHASH := 15.
	OPK_STRCMP := 16.
	OPT_INLINE_SIZE := 200.
	OPT_INLINE_BUDGET := 3000.
	OPT_INLINE_DEPTH := 8.
	OA_START := 1.
	OA_TARGET := 2.
	OA_LOOP := 4.
	OA_BLOCK := 8
! !

!OptBuilder methodsFor: 'accessing'!
entryBlock
	^obEntryBlock
!
bailed
	^obBailed or: [ir full]
!
bail
	(obBailed not and: [(libc getenv: 'SAMALTAK_OPT_TRACE') notNull]) ifTrue: [
		libc fprintf: libc stderr format: 'opt: bail at pc %d of act %d
' with: ir originPc with: ir originAct].
	"in a closure another frame made: the next build calls it"
	(obBailed not and: [obForeignDepth > 0 and: [obNoForeignCount < 8]]) ifTrue: [
		obNoForeignM at: obNoForeignCount put: (obForeignM at: obForeignDepth - 1).
		obNoForeignS at: obNoForeignCount put: (obForeignS at: obForeignDepth - 1).
		obNoForeignCount := obNoForeignCount + 1].
	obBailed := true
! !

!OptBuilder methodsFor: 'building'!
buildSlice: m
	<function>
	| ok |
	obSlice := true.
	obFrame := self null.
	obForeign := false.
	obResident := false.
	obNoInlineCount := 0.
	obNoForeignCount := 0.
	obUnitStart := 0.
	obOsrPc := -1.
	ok := self buildOnce: m.
	obSlice := false.
	^ok
!
build: m start: s osr: t depth: d resident: res
	"The IR of m (s 0), or of its block at startpc s, entered at its start (t -1) or at loop head t with d slots (res: in a married frame, the temps its closures reach stay in the frame); answer whether it could be built. A closure an inlined method makes that escapes would have to be made: build again without inlining that method. Marker methods (on:do:, ensure:) are not optimized: their frames, which the exception code reads and writes through their Contexts, stay plain."
	<function>
	| e nf |
	((self methodPrimitive: m) = PRIM_ENSURE_MARKER or: [(self methodPrimitive: m) = PRIM_ONDO_MARKER]) ifTrue: [^false].
	obResident := res.
	obNoInlineCount := 0.
	obNoForeignCount := 0.
	obUnitStart := s.
	obOsrPc := t.
	obValidSlots := d.
	[nf := obNoForeignCount.
	 (self buildOnce: m)
		ifFalse: [
			"it bailed in a closure another frame made: build again calling that one"
			(obNoForeignCount > nf and: [obNoForeignCount < 8]) ifFalse: [^false]]
		ifTrue: [
			e := self escapingClosure.
			e < 0 ifTrue: [^true].
			(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [libc fprintf: libc stderr format: 'opt: a closure of act %d escapes
' with: e].
			(self foreignActOf: e) >= 0
				ifTrue: [
					"made in a closure another frame made: build again calling that one"
					obNoForeignCount >= 7 ifTrue: [^false].
					self noForeign: (self foreignActOf: e)]
				ifFalse: [
					(e = 0 or: [obNoInlineCount >= OPT_MAX_NOINLINE]) ifTrue: [^false].
					obNoInline at: obNoInlineCount put: (ir act: e) method.
					obNoInlineCount := obNoInlineCount + 1]]] repeat
!
buildOnce: m
	<function>
	| a b |
	ir reset.
	obBailed := false.
	obVarTop := 0.
	libc memset: obArgFlags value: 0 size: OPT_MAX_VARS.
	obDefCount := 0.
	libc memset: obDefKeys value: 0 size: 4 * OPT_DEF_SIZE.
	obIncCount := 0.
	obAnaCount := 0.
	obAnaTop := 0.
	obPcbTop := 0.
	obRootMethod := m.
	obInlined := 0.
	obDepCount := 0.
	obSafeEpoch := 0.
	obCheckedBlock := -1.
	obSpecCount := 0.
	obForeignDepth := 0.
	obPerformAct := -1.
	obNilConst := -1.
	0 to: 255 do: [:i | obConstNodes at: i put: -1].
	a := obUnitStart > 0 ifTrue: [self newBlockActFor: m start: obUnitStart] ifFalse: [self newActFor: m].
	a < 0 ifTrue: [^false].
	obEntryBlock := ir newBlock.
	(ir block: obEntryBlock) flags: (BF_SEALED bitOr: BF_LIVE).
	(ir block: obEntryBlock) act: a.
	obCurBlock := obEntryBlock.
	(ir act: a) receiver: (self param: -1).
	obUnitStart > 0 ifTrue: [(ir act: a) closure: (self param: -2)].
	obParamSlots := (ir act: a) numArgs.
	obOsrPc >= 0 ifTrue: [^self buildOsr: a].
	obValidSlots := (ir act: a) numArgs + (ir act: a) numTemps.
	0 to: (ir act: a) numArgs - 1 do: [:i | self writeArg: (self var: a slot: i) value: (self param: i)].
	(ir act: a) numArgs to: (ir act: a) numArgs + (ir act: a) numTemps - 1 do: [:i | self write: (self var: a slot: i) value: (self constant: memory nilOop)].
	"a failed primitive's error code is in the first temp"
	((ir act: a) numTemps > 0 and: [obUnitStart = 0 and: [(self isInt: (self loadRef: m at: CM_PRIMITIVE)) and: [((self intVal: (self loadRef: m at: CM_PRIMITIVE)) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0]]]) ifTrue: [
		self write: (self var: a slot: (ir act: a) numArgs) value: (self param: (ir act: a) numArgs).
		"home slots after it: values are stored where they are defined"
		obParamSlots := (ir act: a) numArgs + 1].
	self checkInterruptAct: a pc: obUnitStart depth: (ir act: a) numArgs + (ir act: a) numTemps kind: SP_ENTRY.
	b := ir newBlock.
	self goto: b.
	obCurBlock := b.
	self seal: b.
	self buildAct: a.
	self bailed ifTrue: [^false].
	0 to: ir blockCount - 1 do: [:k | ((ir block: k) flags bitAnd: BF_SEALED) = 0 ifTrue: [self seal: k]].
	^self bailed not
!
buildOsr: a
	"Enter at loop head obOsrPc: the frame's slots there are the parameters."
	| b |
	obValidSlots = (self depthAt: obOsrPc act: a) ifFalse: [^false].
	obParamSlots := obValidSlots.
	obResident ifTrue: [self markResident: a].
	0 to: obValidSlots - 1 do: [:i |
		i < (ir act: a) numArgs
			ifTrue: [self writeArg: (self var: a slot: i) value: (self param: i)]
			ifFalse: [(obArgFlags at: (self var: a slot: i)) = 2 ifFalse: [self write: (self var: a slot: i) value: (self param: i)]].
		self noteClosureIn: i act: a].
	ir osrEntry: obCurBlock state: (self stateAct: a pc: obOsrPc depth: obValidSlots) numbers: self frameNumbers.
	ir osrFloats: self frameFloats.
	ir osrInts: self frameInts.
	self guardReceiverClass: a.
	b := self blockAt: obOsrPc act: a.
	self goto: b.
	self buildAct: a.
	self bailed ifTrue: [^false].
	0 to: ir blockCount - 1 do: [:k | ((ir block: k) flags bitAnd: BF_SEALED) = 0 ifTrue: [self seal: k]].
	^self bailed not
!
guardReceiverClass: a
	"A variant of a loop's unit whose method the frame's receiver inherits (OptRuntime>>signatureOf:method:: the variant is that class's): the receiver is of that class, guarded once at the entry, so the sends to self are bound."
	| cls |
	(obFrame isNull or: [obForeign not]) ifTrue: [^self].
	cls := interpreter receiverClass: (obFrame fp at: -1).
	cls = (self loadRef: obRootMethod at: CM_CLASS) ifTrue: [^self].
	(ir act: a) receiver: (self guard: (ir act: a) receiver class: cls state: ir osrState)
!
frameClassOf: v
	"v is a loop unit's parameter, a frame slot (v reaches here as it was at the entry): the class of the object the frame holds there now, which the unit takes it for from here on, guarded once at the end of the entry block (as OptPasses>>guardFrameInt: guards a SmallInteger: failing, the loop's head continues in the interpreter and the loop's units take no slot for anything again). 0: not one, not an object, a closure or Context (they have their own ways), or that failed before."
	<function>
	| n nd o cls g |
	(obFrame isNull or: [obOsrPc < 0 or: [ir osrState < 0]]) ifTrue: [^0 asUInt64].
	n := self liveValueOf: v.
	nd := ir node: n.
	(nd op asInt32 = O_PARAM and: [nd tkind asInt32 = T_ANY and: [nd aux >= 0 and: [nd aux < (obValidSlots min: 64)]]]) ifFalse: [^0 asUInt64].
	o := obFrame fp at: nd aux.
	(self isPtr: o) ifFalse: [^0 asUInt64].
	cls := self rawClass: o.
	(cls = memory clsBlock or: [cls = memory clsContext]) ifTrue: [^0 asUInt64].
	((feedback flagsAt: obRootMethod pc: obOsrPc) bitAnd: feedback deoptHoisted) ~= 0 ifTrue: [^0 asUInt64].
	g := ir newNode: O_GUARDCLASS rep: R_OOP.
	ir full ifTrue: [^0 asUInt64].
	(ir node: g) a: n.
	(ir node: g) aux: cls asInt64.
	(ir node: g) state: ir osrState.
	(ir node: g) flags: (NF_GUARD bitOr: NF_HOISTED).
	(ir node: g) bcact: (ir state: ir osrState) act.
	(ir node: g) bcpc: (ir state: ir osrState) pc.
	self type: g class: cls.
	ir insert: g before: (ir block: obEntryBlock) last.
	self type: n class: cls.
	^cls
!
frameNumbers
	"Bit i: the frame's slot i holds a SmallInteger or a Float (the first 64)."
	| bits v |
	bits := 0 asUInt64.
	obFrame isNull ifTrue: [^bits].
	0 to: (obValidSlots min: 64) - 1 do: [:i |
		v := obFrame fp at: i.
		((self isInt: v) or: [(v bitAnd: 7) = 4 or: [(self isPtr: v) and: [(self rawClass: v) = memory clsBoxedfloat]]]) ifTrue: [
			bits := bits bitOr: 1 asUInt64 << i]].
	^bits
!
frameFloats
	"Bit i: the frame's slot i holds a SmallFloat64 (the first 64)."
	| bits v |
	bits := 0 asUInt64.
	obFrame isNull ifTrue: [^bits].
	0 to: (obValidSlots min: 64) - 1 do: [:i |
		v := obFrame fp at: i.
		(v bitAnd: 7) = 4 ifTrue: [bits := bits bitOr: 1 asUInt64 << i]].
	^bits
!
frameInts
	"Bit i: the frame's slot i holds a SmallInteger (the first 64) that the unit may take for one, guarded at its entry: none once such a guard failed at this loop."
	| bits |
	bits := 0 asUInt64.
	(obFrame isNull or: [((feedback flagsAt: obRootMethod pc: obOsrPc) bitAnd: feedback deoptHoisted) ~= 0]) ifTrue: [^bits].
	0 to: (obValidSlots min: 64) - 1 do: [:i |
		(self isInt: (obFrame fp at: i)) ifTrue: [bits := bits bitOr: 1 asUInt64 << i]].
	^bits
!
markResident: a
	"The temps of a that its closures reach (outer temps at a block depth that is a): read from and written to the frame."
	| bcs pc end op lvl ends n i |
	bcs := self methodBytecodes: (ir act: a) method.
	pc := (ir act: a) startpc.
	end := (ir act: a) endpc.
	ends := self local: 'int32_t[64]'.
	n := 0.
	[pc < end] whileTrue: [
		[n > 0 and: [pc >= (ends at: n - 1)]] whileTrue: [n := n - 1].
		op := bcs at: pc.
		((op >= 16r8A and: [op <= 16r8C]) and: [(bcs at: pc + 1) = n and: [n > 0]]) ifTrue: [
			i := (bcs at: pc + 2) asInt32.
			(i >= (ir act: a) numArgs and: [i < ((ir act: a) numArgs + (ir act: a) numTemps)]) ifTrue: [
				obArgFlags at: (self var: a slot: i) put: 2.
				obArgVals at: (self var: a slot: i) put: (self homeSlot: i)]].
		(op = 16r8F and: [n < 64]) ifTrue: [
			ends at: n put: pc + 6 + (((bcs at: pc + 4) asInt64 << 8) bitOr: (bcs at: pc + 5)) asInt32.
			n := n + 1].
		pc := (pc + (analysis lengthOf: op)) asInt32]
!
noteClosureIn: i act: a
	"On-stack replacement: frame slot i holds a closure this frame made (its outerContext the frame's Context): value sends to what the slot holds may inline its body (inlineFrameClosure:info:pc:act:rcvSlot:argc:). Its description is an O_CLOSURE node in no block."
	| v d pc bcs |
	(obFrame isNull or: [obFrame ctx = memory nilOop or: [obSpecCount >= 8]]) ifTrue: [^self].
	(i >= (ir act: a) numArgs and: [(obArgFlags at: (self var: a slot: i)) = 2]) ifTrue: [^self].
	v := obFrame fp at: i.
	((self isPtr: v) and: [(self rawClass: v) = memory clsBlock and: [(self loadRef: v at: BC_OUTER) = obFrame ctx]]) ifFalse: [^self].
	pc := (self intVal: (self loadRef: v at: BC_STARTPC)) asInt32 - 6.
	bcs := self methodBytecodes: (ir act: a) method.
	(pc >= 0 and: [(bcs at: pc) = 16r8F]) ifFalse: [^self].
	d := ir newNode: O_CLOSURE rep: R_OOP.
	(ir node: d) aux: pc + 6.
	(ir node: d) aux2: (((((bcs at: pc + 1) asInt64 bitOr: (bcs at: pc + 2) asInt64 << 8) bitOr: (bcs at: pc + 3) asInt64 << 16)) bitOr: a asInt64 << 32).
	obSpecParam at: obSpecCount put: (self var: a slot: i).
	obSpecInfo at: obSpecCount put: d.
	obSpecCount := obSpecCount + 1
!
frameClosureOf: v numArgs: n pc: pc act: a
	"The description of the closure v may be: v is what a frame slot that held one the frame made holds now (noteClosureIn:act:), and it takes n arguments; -1 if none, or if a guard of such a closure failed at pc before."
	<function>
	| x |
	(runtime flag: runtime blocksFlag) ifFalse: [^-1].
	((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback deoptOther) ~= 0 ifTrue: [^-1].
	x := self liveValueOf: v.
	0 to: obSpecCount - 1 do: [:i |
		(((ir node: (obSpecInfo at: i)) aux2 bitAnd: 255) = n and: [(self liveValueOf: (self read: (obSpecParam at: i))) = x]) ifTrue: [^obSpecInfo at: i]].
	^-1
!
inlineFrameClosure: x info: d pc: pc act: a rcvSlot: r argc: argc
	"x is a closure the frame made at d's startpc (its outerContext the frame's Context): guarded (class, startpc, outerContext; else deoptimize), its body inlined as if this code had made it."
	<function>
	| s g |
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	g := self guard: x class: memory clsBlock state: s.
	self deoptUnless: (self binary: O_EQ a: (self loadField: BC_STARTPC of: g) b: (self constant: (self intOop: (ir node: d) aux))) act: a state: s.
	self deoptUnless: (self binary: O_EQ a: (self loadField: BC_OUTER of: g) b: (self param: -3)) act: a state: s.
	self inlineBlock: g info: d pc: pc act: a rcvSlot: r argc: argc
!
foreignClosureOf: v numArgs: n pc: pc act: a
	"On-stack replacement: the closure v is, as the frame shows it now (knownObject:), if another frame made it (a block passed in, or one such a block reaches), the unit may inline such closures (foreign:), it takes n arguments and its body may be inlined here; else nil."
	<function>
	| c ctx m sp size |
	(obFrame isNull or: [obForeign not or: [(runtime flag: runtime blocksFlag) not]]) ifTrue: [^memory nilOop].
	((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: (feedback deoptOther bitOr: feedback deoptClass)) ~= 0 ifTrue: [^memory nilOop].
	obForeignDepth >= 8 ifTrue: [^memory nilOop].
	c := self knownObject: v.
	(c ~= 0 and: [self inlinableClosure: c]) ifFalse: [^memory nilOop].
	ctx := self loadRef: c at: BC_OUTER.
	(ctx ~= obFrame ctx and: [(self intVal: (self loadRef: c at: BC_NUMARGS)) = n]) ifFalse: [^memory nilOop].
	m := self loadRef: ctx at: CTX_METHOD.
	sp := (self intVal: (self loadRef: c at: BC_STARTPC)) asInt32.
	size := (((self methodBytecodes: m) at: sp - 2) asInt64 << 8 bitOr: ((self methodBytecodes: m) at: sp - 1)) asInt32.
	obInlined + size > OPT_INLINE_BUDGET ifTrue: [^memory nilOop].
	0 to: obNoForeignCount - 1 do: [:i | ((obNoForeignM at: i) = m and: [(obNoForeignS at: i) = sp]) ifTrue: [^memory nilOop]].
	^c
!
inlinableClosure: c
	"c is a closure whose body a loop's unit may inline where another frame made it (its code and shape: an outerContext with a method, the body's header in it, small, no bytecode the builder bails on there: ^, thisContext, Arrays, Context's mediated fields). OptRuntime>>closureSignatureOf: covers the closures this holds for."
	<function>
	| ctx m sp n size bcs pc end op len |
	((self isPtr: c) and: [(self rawClass: c) = memory clsBlock]) ifFalse: [^false].
	ctx := self loadRef: c at: BC_OUTER.
	((self isPtr: ctx) and: [(self rawClass: ctx) = memory clsContext]) ifFalse: [^false].
	m := self loadRef: ctx at: CTX_METHOD.
	((self isPtr: m) and: [(self formatOf: m) = F_FIXED and: [(self numSlots: m) > CM_PRIMITIVE]]) ifFalse: [^false].
	((self isPtr: (self loadRef: m at: CM_BYTECODES)) and: [(self formatOf: (self loadRef: m at: CM_BYTECODES)) >= F_BYTES]) ifFalse: [^false].
	((self isPtr: (self loadRef: m at: CM_LITERALS)) and: [(self formatOf: (self loadRef: m at: CM_LITERALS)) <= F_WEAK]) ifFalse: [^false].
	((self isInt: (self loadRef: c at: BC_STARTPC)) and: [self isInt: (self loadRef: c at: BC_NUMARGS)]) ifFalse: [^false].
	sp := (self intVal: (self loadRef: c at: BC_STARTPC)) asInt32.
	n := self intVal: (self loadRef: c at: BC_NUMARGS).
	(sp >= 6 and: [sp <= (self methodSize: m)]) ifFalse: [^false].
	bcs := self methodBytecodes: m.
	((bcs at: sp - 6) = 16r8F and: [(bcs at: sp - 5) = n]) ifFalse: [^false].
	size := ((bcs at: sp - 2) asInt64 << 8 bitOr: (bcs at: sp - 1)) asInt32.
	end := sp + size.
	(size > OPT_INLINE_SIZE or: [end > (self methodSize: m)]) ifTrue: [^false].
	pc := sp.
	[pc < end] whileTrue: [
		op := bcs at: pc.
		len := analysis lengthOf: op.
		(len = 0 or: [pc + len > end]) ifTrue: [^false].
		(op = 16r7C or: [op = 16r76 or: [op = 16r94 or: [op = 16r88 or: [op = 16r81 and: [(bcs at: pc + 1) <= CTX_STACKP]]]]]) ifTrue: [^false].
		pc := (pc + len) asInt32].
	^true
!
knownObject: v
	"What v holds as the frame of the on-stack replacement shows it now: a slot of the frame, or an outer temp of a closure known so; 0 if it cannot tell."
	<function>
	<returns: 'oop'>
	| n nd c |
	obFrame isNull ifTrue: [^0].
	"past the phi of a merge whose paths all bring the same value (a type switch between where it was pushed and here)"
	n := self liveValueOf: v.
	nd := ir node: n.
	"the slots closureSignatureOf: covers"
	(nd op asInt32 = O_PARAM and: [nd aux >= 0 and: [nd aux < (obValidSlots min: 64)]]) ifTrue: [^obFrame fp at: nd aux].
	(nd op asInt32 = O_GUARDCLASS or: [nd op asInt32 = O_GUARDCLOSURE or: [nd op asInt32 = O_CAST]]) ifTrue: [^self knownObject: nd a].
	nd op asInt32 = O_OUTERLOAD ifTrue: [
		c := self knownObject: nd a.
		(c ~= 0 and: [(self isPtr: c) and: [(self rawClass: c) = memory clsBlock]]) ifFalse: [^0].
		^self knownOuterTemp: nd aux2 levels: nd aux asInt32 of: c].
	^0
!
knownOuterTemp: i levels: lv of: c
	"Temp i of the Context lv levels out of closure c (O_OUTERLOAD's walk, done now): in the frame it is married to, else in it; 0 if the chain is not one of Contexts and closures, or i is not among the temps closureSignatureOf: covers (the first 32, below a married frame's sp)."
	<function>
	<returns: 'oop'>
	| ctx cl s g |
	i >= 32 ifTrue: [^0].
	ctx := self loadRef: c at: BC_OUTER.
	2 to: lv do: [:k |
		((self isPtr: ctx) and: [(self rawClass: ctx) = memory clsContext]) ifFalse: [^0].
		cl := self loadRef: ctx at: CTX_CLOSURE.
		((self isPtr: cl) and: [(self rawClass: cl) = memory clsBlock]) ifFalse: [^0].
		ctx := self loadRef: cl at: BC_OUTER].
	((self isPtr: ctx) and: [(self rawClass: ctx) = memory clsContext]) ifFalse: [^0].
	s := self loadRef: ctx at: CTX_SENDER.
	(self isInt: s) ifTrue: [
		g := interpreter frames + (self intVal: s).
		i >= g sp ifTrue: [^0].
		^g fp at: i].
	CTX_FIXED + i < (self numSlots: ctx) ifFalse: [^0].
	^self loadRef: ctx at: CTX_FIXED + i
!
inlineForeignClosure: x pc: pc act: a rcvSlot: r argc: argc
	"If x is, as the frame shows it, a closure another frame made (foreignClosureOf:numArgs:pc:act:), evaluate it here and answer true: guarded (class, startpc, its outerContext's method; else deoptimize), its body inlined as an activation without its outer one: outer temps through x (O_OUTERLOAD, O_OUTERSTORE), self its outerContext's receiver; ^ or anything else this compilation cannot do in it makes the next build call it."
	<function>
	| c s g outer m sp d bcs |
	c := self foreignClosureOf: x numArgs: argc pc: pc act: a.
	c = memory nilOop ifTrue: [^false].
	m := self loadRef: (self loadRef: c at: BC_OUTER) at: CTX_METHOD.
	sp := (self intVal: (self loadRef: c at: BC_STARTPC)) asInt32.
	bcs := self methodBytecodes: m.
	d := ir newNode: O_CLOSURE rep: R_OOP.
	(ir node: d) aux: sp.
	(ir node: d) aux2: (((bcs at: sp - 5) asInt64 bitOr: (bcs at: sp - 4) asInt64 << 8) bitOr: (bcs at: sp - 3) asInt64 << 16).
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	g := self guard: (self guard: x class: memory clsBlock state: s) startpc: sp method: m state: s.
	outer := self loadField: BC_OUTER of: g.
	obForeignM at: obForeignDepth put: m.
	obForeignS at: obForeignDepth put: sp.
	obForeignDepth := obForeignDepth + 1.
	self inlineBody: g info: d method: m ana: (self analysisOf: m) outer: -2 home: -1 receiver: (self loadField: CTX_RECEIVER of: outer) pc: pc act: a rcvSlot: r argc: argc.
	obForeignDepth := obForeignDepth - 1.
	^true
!
foreignActOf: e
	"The innermost activation that is a closure another frame made (inlineForeignClosure:...) and holds activation e (by its callers), -1 if none."
	| t |
	t := e.
	[t >= 0] whileTrue: [
		(ir act: t) outer = -2 ifTrue: [^t].
		t := (ir act: t) parent].
	^-1
!
noForeign: f
	"The next build calls the closure that activation f inlined (another frame made it)."
	obNoForeignM at: obNoForeignCount put: (ir act: f) method.
	obNoForeignS at: obNoForeignCount put: (ir act: f) startpc.
	obNoForeignCount := obNoForeignCount + 1
!
deoptUnless: test act: a state: s
	"Go on if test (a comparison) is true, else deoptimize."
	| t f |
	(ir node: test) tkind: T_BOOL.
	t := ir newBlock.
	(ir block: t) act: a.
	f := ir newBlock.
	(ir block: f) act: a.
	self branch: test true: t false: f.
	self seal: t.
	self seal: f.
	obCurBlock := f.
	self deoptAct: a state: s.
	obCurBlock := t
!
homeSlot: i
	"Slot i of the root activation's frame, as frame states see it (where it is, no value of its own)."
	| n |
	n := ir newNode: O_HOMESLOT rep: R_OOP.
	(ir node: n) aux: i.
	ir append: n to: obEntryBlock.
	^n
!
entryPc
	"Where the unit is entered: its start, or the loop head."
	obOsrPc >= 0 ifTrue: [^obOsrPc].
	^obUnitStart
!
isMethodUnit
	^obOsrPc < 0 and: [obUnitStart = 0]
!
isEntryUnit
	"A method's or a block's unit, entered at its start (not a loop's)."
	^obOsrPc < 0
!
frame: f
	"The frame a loop's unit is compiled for (on-stack replacement; null for others): closures it made may be inlined."
	obFrame := f
!
foreign: b
	"Whether the loop's unit may inline closures other frames made (a variant for their signature, OptRuntime>>tierUp:loop:)."
	obForeign := b
!
paramSlots
	"The frame's slots the code reads at its entry and keeps (home slots follow)."
	^obParamSlots
!
validSlots
	"The frame's slots that hold values at its entry (the others are made nil)."
	^obValidSlots
!
newActFor: m
	"An activation of method m (not yet linked to a caller), its analysis and pc map; -1 if m cannot be compiled."
	<function>
	| a ac ana fs |
	ana := self analysisOf: m.
	ana < 0 ifTrue: [^-1].
	a := ir newAct.
	a < 0 ifTrue: [^-1].
	ac := ir act: a.
	ac method: m.
	ac numArgs: (self intVal: (self loadRef: m at: CM_NUMARGS)) asInt32.
	ac numTemps: (self intVal: (self loadRef: m at: CM_NUMTEMPS)) asInt32.
	fs := (self intVal: (self loadRef: m at: CM_FRAMESIZE)) asInt32.
	fs < (ac numArgs + ac numTemps) ifTrue: [fs := ac numArgs + ac numTemps].
	ac nslots: fs + 4.
	ac startpc: 0.
	ac endpc: (self methodSize: m).
	ac ana: ana.
	ac home: a.
	(self allocPcBlocks: a) ifFalse: [^-1].
	ac varBase: obVarTop.
	ac retVar: obVarTop + ac nslots.
	obVarTop := obVarTop + ac nslots + 1.
	^a
!
newBlockActFor: m start: s
	"The activation of m's block at startpc s, compiled as a unit: its closure the frame's, its outer temps through it (no outer activation), ^ deoptimizes; -1 if m cannot be compiled."
	<function>
	| a ac fs |
	a := self newActFor: m.
	a < 0 ifTrue: [^-1].
	ac := ir act: a.
	ac numArgs: (self byteAt: s - 5 act: a) asInt32.
	ac numTemps: (self byteAt: s - 4 act: a) asInt32.
	fs := (self byteAt: s - 3 act: a) asInt32.
	fs < (ac numArgs + ac numTemps) ifTrue: [fs := ac numArgs + ac numTemps].
	ac startpc: s.
	ac endpc: s + (((self byteAt: s - 2 act: a) asInt64 << 8 bitOr: (self byteAt: s - 1 act: a)) asInt32).
	ac home: -1.
	fs + 4 > ac nslots ifTrue: [
		ac nslots: fs + 4.
		ac retVar: ac varBase + ac nslots.
		obVarTop := ac varBase + ac nslots + 1].
	^a
!
allocPcBlocks: a
	| ac n |
	ac := ir act: a.
	n := self methodSize: ac method.
	obPcbTop + n > OPT_PCB_MAX ifTrue: [
		self bail.
		^false].
	ac pcb: obPcbTop.
	0 to: n - 1 do: [:i | obPcBlocks at: obPcbTop + i put: -1].
	obPcbTop := obPcbTop + n.
	^true
!
analysisOf: m
	"The base of m's analysis in the arena (depth and flags per pc, the last backward jump to each loop head); -1 if m cannot be analyzed."
	<function>
	| n base f t k |
	0 to: obAnaCount - 1 do: [:i | (obAnaMethods at: i) = m ifTrue: [^obAnaBases at: i]].
	obAnaCount >= OPT_MAX_ANA ifTrue: [^-1].
	(analysis analyze: m) ifFalse: [^-1].
	n := analysis size.
	obAnaTop + n > OPT_ANA_MAX ifTrue: [^-1].
	base := obAnaTop.
	analysis analyzeLiveness.
	0 to: n - 1 do: [:pc |
		f := 0.
		(analysis isStart: pc) ifTrue: [f := f bitOr: OA_START].
		(analysis isTarget: pc) ifTrue: [f := f bitOr: OA_TARGET].
		(analysis isLoopHead: pc) ifTrue: [f := f bitOr: OA_LOOP].
		(analysis isBlockStart: pc) ifTrue: [f := f bitOr: OA_BLOCK].
		obAnaFlag at: base + pc put: f asUInt8.
		obAnaDepth at: base + pc put: (analysis depthAt: pc) asInt16.
		obAnaLive at: base + pc put: (analysis liveSlotsAt: pc).
		obAnaBack at: base + pc put: -1].
	0 to: n - 1 do: [:pc |
		((f := obAnaFlag at: base + pc) bitAnd: OA_START) ~= 0 ifTrue: [
			((analysis byteAt: pc) >= 16r90 and: [(analysis byteAt: pc) <= 16r92]) ifTrue: [
				t := analysis jumpTargetAt: pc.
				(t <= pc and: [(obAnaBack at: base + t) < pc]) ifTrue: [obAnaBack at: base + t put: pc]]]].
	obAnaMethods at: obAnaCount put: m.
	obAnaBases at: obAnaCount put: base.
	obAnaFloat at: obAnaCount put: false.
	obAnaInts at: obAnaCount put: false.
	"only m's arithmetic sites: the Float bytes of other pcs are other methods' (shared by hash)"
	0 to: n - 1 do: [:pc |
		(((obAnaFlag at: base + pc) bitAnd: OA_START) ~= 0 and: [(k := analysis specialIndexOf: analysis bytecodes + pc) >= 0]) ifTrue: [
			(k <= 9 and: [((feedback flagsAt: m pc: pc) bitAnd: feedback sawFloat) ~= 0]) ifTrue: [obAnaFloat at: obAnaCount put: true].
			((analysis specialInlinesIntegers: k) and: [self sawIntAt: m pc: pc]) ifTrue: [obAnaInts at: obAnaCount put: true]]].
	obAnaCount := obAnaCount + 1.
	obAnaTop := obAnaTop + n.
	^base
!
isStart: pc act: a
	^((obAnaFlag at: (ir act: a) ana + pc) bitAnd: OA_START) ~= 0
!
isTarget: pc act: a
	^((obAnaFlag at: (ir act: a) ana + pc) bitAnd: OA_TARGET) ~= 0
!
isLoopHead: pc act: a
	^((obAnaFlag at: (ir act: a) ana + pc) bitAnd: OA_LOOP) ~= 0
!
depthAt: pc act: a
	^(obAnaDepth at: (ir act: a) ana + pc) asInt32
!
lastBackJumpTo: pc act: a
	^obAnaBack at: (ir act: a) ana + pc
!
byteAt: pc act: a
	^(self methodBytecodes: (ir act: a) method) at: pc
!
int16At: pc act: a
	| p |
	p := self methodBytecodes: (ir act: a) method.
	^((p at: pc) bitOr: (p at: pc + 1) asInt64 << 8) asInt16 asInt32
!
literal: i act: a
	^self methodLiteral: (ir act: a) method at: i
!
buildAct: a
	"Scan a's bytecodes from startpc to endpc."
	<function>
	| pc b ac |
	ac := ir act: a.
	pc := ac startpc.
	[pc < ac endpc and: [self bailed not]] whileTrue: [
		(self isStart: pc act: a)
			ifFalse: [pc := pc + 1]
			ifTrue: [
				b := obPcBlocks at: ac pcb + pc.
				(b < 0 and: [self isTarget: pc act: a]) ifTrue: [b := self blockAt: pc act: a].
				b >= 0 ifTrue: [
					(obCurBlock >= 0 and: [obCurBlock ~= b]) ifTrue: [self goto: b].
					obCurBlock := b.
					(self isLoopHead: pc act: a)
						ifTrue: [(ir block: b) entryState: (self stateAct: a pc: pc depth: (self depthAt: pc act: a))]
						ifFalse: [self seal: b]].
				obCurBlock < 0
					ifTrue: [pc := self skip: pc act: a]
					ifFalse: [pc := self emit: pc act: a]]]
!
skip: pc act: a
	"The instruction after the one at pc in dead code (a closure's body is skipped with it)."
	| op |
	op := self byteAt: pc act: a.
	op = 16r8F ifTrue: [^pc + 6 + (((self byteAt: pc + 4 act: a) asInt64 << 8) bitOr: (self byteAt: pc + 5 act: a)) asInt32].
	^(pc + (analysis lengthOf: op)) asInt32
! !

!OptBuilder methodsFor: 'variables'!
var: a slot: i
	^(ir act: a) varBase + i
!
defIndex: var block: b
	| key i |
	key := var * OPT_MAX_BLOCKS + b + 1.
	i := (key asUInt32 * 2654435761) asUInt32 >> 15 bitAnd: OPT_DEF_SIZE - 1.
	[(obDefKeys at: i) ~= 0 and: [(obDefKeys at: i) ~= key]] whileTrue: [i := (i + 1) bitAnd: OPT_DEF_SIZE - 1].
	^i
!
write: var value: v
	| n |
	(var < OPT_MAX_VARS and: [(obArgFlags at: var) = 2]) ifTrue: [
		n := self add: O_STORESLOT rep: R_NONE.
		(ir node: n) a: v.
		(ir node: n) aux: (ir node: (obArgVals at: var)) aux.
		^self].
	self write: var value: v in: obCurBlock
!
write: var value: v in: b
	<function>
	| i |
	i := self defIndex: var block: b.
	(obDefKeys at: i) = 0 ifTrue: [
		obDefCount >= ((OPT_DEF_SIZE quo: 4) * 3) ifTrue: [^self bail].
		obDefCount := obDefCount + 1.
		obDefKeys at: i put: var * OPT_MAX_BLOCKS + b + 1].
	obDefVals at: i put: v
!
read: var
	^self read: var in: obCurBlock
!
writeArg: var value: v
	"An argument: Smalltalk never assigns it, so every read is v (no phis, even in loops not yet closed)."
	var < OPT_MAX_VARS ifTrue: [
		obArgVals at: var put: v.
		obArgFlags at: var put: 1].
	self write: var value: v
!
read: var in: b
	<function>
	| i v bl phi |
	(var < OPT_MAX_VARS and: [(obArgFlags at: var) = 2]) ifTrue: [
		v := self add: O_LOADSLOT rep: R_OOP.
		(ir node: v) aux: (ir node: (obArgVals at: var)) aux.
		^v].
	(var < OPT_MAX_VARS and: [(obArgFlags at: var) ~= 0]) ifTrue: [^ir resolve: (obArgVals at: var)].
	i := self defIndex: var block: b.
	(obDefKeys at: i) ~= 0 ifTrue: [^ir resolve: (obDefVals at: i)].
	bl := ir block: b.
	((bl flags bitAnd: BF_SEALED) = 0 and: [self loopKeeps: var block: b]) ifTrue: [
		v := self read: var in: (ir pred: 0 of: b).
		self write: var value: v in: b.
		^v].
	(bl flags bitAnd: BF_SEALED) = 0
		ifTrue: [
			phi := self newPhi: b var: var.
			obIncCount >= OPT_MAX_INC ifTrue: [
				self bail.
				^phi].
			obIncPhis at: obIncCount put: phi.
			obIncVars at: obIncCount put: var.
			obIncCount := obIncCount + 1.
			v := phi]
		ifFalse: [
			bl npreds = 1
				ifTrue: [
					"nil while it reads on: a cycle of blocks of one predecessor each (a loop whose way in is dead, never run) comes back here"
					self write: var value: self nilConstant in: b.
					v := self read: var in: (ir pred: 0 of: b)]
				ifFalse: [
					bl npreds = 0
						ifTrue: [v := self constant: memory nilOop]
						ifFalse: [
							phi := self newPhi: b var: var.
							self write: var value: phi in: b.
							self addPhiOperands: phi var: var.
							v := phi]]].
	self write: var value: v in: b.
	^v
!
loopKeeps: var block: b
	"b heads a loop not closed yet, var is a temp of its activation that no instruction of the loop stores, nor any closure of the activation (one made before the loop may be inlined into it): its value on entry, no phi."
	| bl ac slot pc end op |
	(libc getenv: 'SAMALTAK_NOKEEP') notNull ifTrue: [^false].
	bl := ir block: b.
	((bl flags bitAnd: BF_LOOP) ~= 0 and: [bl npreds = 1 and: [bl act >= 0 and: [(bl flags bitAnd: BF_LIVE) ~= 0]]]) ifFalse: [^false].
	ac := ir act: bl act.
	slot := var - ac varBase.
	(slot >= 0 and: [slot < (ac numArgs + ac numTemps)]) ifFalse: [^false].
	(self closuresOf: bl act store: slot) ifTrue: [^false].
	pc := bl pc.
	end := self lastBackJumpTo: pc act: bl act.
	end < pc ifTrue: [^false].
	[pc <= end] whileTrue: [
		op := self byteAt: pc act: bl act.
		((op >= 16r60 and: [op < 16r68]) and: [op - 16r60 = slot]) ifTrue: [^false].
		((op = 16r84 or: [op = 16r87]) and: [(self byteAt: pc + 1 act: bl act) = slot]) ifTrue: [^false].
		(analysis lengthOf: op) = 0 ifTrue: [^false].
		pc := (pc + (analysis lengthOf: op)) asInt32].
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [libc fprintf: libc stderr format: 'opt: loop at pc %d keeps slot %d
' with: bl pc with: slot].
	^true
!
closuresOf: a store: slot
	"A closure a makes (at any depth) stores a's temp slot: its outer temp at the level of a."
	| pc op n ends |
	ends := self local: 'int32_t[64]'.
	n := 0.
	pc := (ir act: a) startpc.
	[pc < (ir act: a) endpc] whileTrue: [
		[n > 0 and: [pc >= (ends at: n - 1)]] whileTrue: [n := n - 1].
		op := self byteAt: pc act: a.
		((op = 16r8B or: [op = 16r8C]) and: [n > 0 and: [(self byteAt: pc + 1 act: a) = n and: [(self byteAt: pc + 2 act: a) = slot]]]) ifTrue: [^true].
		op = 16r8F ifTrue: [
			n >= 64 ifTrue: [^true].
			ends at: n put: pc + 6 + (((self byteAt: pc + 4 act: a) asInt64 << 8) bitOr: (self byteAt: pc + 5 act: a)) asInt32.
			n := n + 1].
		(analysis lengthOf: op) = 0 ifTrue: [^true].
		pc := (pc + (analysis lengthOf: op)) asInt32].
	^false
!
newPhi: b var: var
	| n |
	n := ir newNode: O_PHI rep: R_OOP.
	(ir node: n) aux2: var.
	ir prepend: n to: b.
	^n
!
addPhiOperands: phi var: var
	<function>
	| b n args |
	b := (ir node: phi) block.
	n := (ir block: b) npreds.
	args := ir allocOperands: n.
	(ir node: phi) args: args.
	(ir node: phi) nargs: n asUInt16.
	0 to: n - 1 do: [:i | ir operand: args + i put: (self read: var in: (ir pred: i of: b))]
!
seal: b
	"All of b's predecessors are known: complete its phis."
	<function>
	| bl k |
	bl := ir block: b.
	(bl flags bitAnd: BF_SEALED) ~= 0 ifTrue: [^self].
	bl flags: (bl flags bitOr: BF_SEALED).
	k := 0.
	[k < obIncCount] whileTrue: [
		(ir node: (obIncPhis at: k)) block = b ifTrue: [
			self addPhiOperands: (obIncPhis at: k) var: (obIncVars at: k).
			obIncCount := obIncCount - 1.
			obIncPhis at: k put: (obIncPhis at: obIncCount).
			obIncVars at: k put: (obIncVars at: obIncCount)]
		ifFalse: [k := k + 1]]
! !

!OptBuilder methodsFor: 'nodes'!
add: op rep: rep
	"A new node at the end of the current block."
	| n |
	n := ir newNode: op rep: rep.
	ir append: n to: obCurBlock.
	^n
!
param: i
	| n |
	n := self add: O_PARAM rep: R_OOP.
	(ir node: n) aux: i.
	^n
!
constant: v
	"A constant oop (in the entry block, so that it dominates every use): one node per value (up to 256 values a unit), so that the values merged of equal constants are that constant (a branch on it folds where it is built)."
	<function>
	| n nd i k |
	i := ((v * 2654435761) >> 8 bitAnd: 255) asInt32.
	k := 0.
	[k < 256 and: [(obConstNodes at: i) >= 0 and: [(obConstVals at: i) ~= v]]] whileTrue: [
		i := i + 1 bitAnd: 255.
		k := k + 1].
	(k < 256 and: [(obConstNodes at: i) >= 0 and: [(ir node: (obConstNodes at: i)) block >= 0]]) ifTrue: [^obConstNodes at: i].
	n := ir newNode: O_CONST rep: R_OOP.
	nd := ir node: n.
	nd aux: v asInt64.
	nd flags: NF_PURE.
	(self isInt: v) ifTrue: [
		nd tkind: T_SMI.
		nd lo: (self intVal: v).
		nd hi: (self intVal: v)].
	v = memory nilOop ifTrue: [nd tkind: T_NIL].
	(v = memory trueOop or: [v = memory falseOop]) ifTrue: [nd tkind: T_BOOL].
	(v bitAnd: 7) = 4 ifTrue: [nd tkind: T_FLOAT].
	(ir block: obEntryBlock) last >= 0
		ifTrue: [
			((ir node: (ir block: obEntryBlock) last) op asInt32 >= O_GOTO)
				ifTrue: [ir insert: n before: (ir block: obEntryBlock) last]
				ifFalse: [ir append: n to: obEntryBlock]]
		ifFalse: [ir append: n to: obEntryBlock].
	(k < 256 and: [(obConstNodes at: i) < 0]) ifTrue: [
		obConstVals at: i put: v.
		obConstNodes at: i put: n].
	^n
!
binary: op a: x b: y
	| n |
	n := self add: op rep: R_OOP.
	(ir node: n) a: x.
	(ir node: n) b: y.
	^n
!
compare: op a: x b: y
	"x == y (O_EQ) or x ~~ y (O_NE): a Boolean (a constant if both are)."
	| n cx cy |
	cx := ir node: (self liveValueOf: x).
	cy := ir node: (self liveValueOf: y).
	(cx op asInt32 = O_CONST and: [cy op asInt32 = O_CONST]) ifTrue: [
		^self constant: ((cx aux = cy aux) = (op = O_EQ) ifTrue: [memory trueOop] ifFalse: [memory falseOop])].
	"values of two classes are not one object (T_FLOAT is a SmallFloat64 or a BoxedFloat64)"
	((self knownClassOf: x) ~= 0 and: [(self knownClassOf: y) ~= 0 and: [(self knownClassOf: x) ~= (self knownClassOf: y) and: [cx tkind asInt32 ~= T_FLOAT and: [cy tkind asInt32 ~= T_FLOAT]]]]) ifTrue: [
		^self constant: (op = O_EQ ifTrue: [memory falseOop] ifFalse: [memory trueOop])].
	n := self binary: op a: x b: y.
	(ir node: n) tkind: T_BOOL.
	^n
!
goto: b
	"End the current block with a jump to b."
	<function>
	self add: O_GOTO rep: R_NONE.
	(ir block: obCurBlock) succ0: b.
	self edgeTo: b.
	obCurBlock := -1
!
edgeTo: b
	"An edge from the current block to b: b is reachable if the current block is (the scan also builds code no edge reaches yet)."
	ir addPred: obCurBlock to: b.
	((ir block: obCurBlock) flags bitAnd: BF_LIVE) ~= 0 ifTrue: [(ir block: b) flags: ((ir block: b) flags bitOr: BF_LIVE)]
!
blockAt: pc act: a
	"The block that starts at a's pc."
	<function>
	| b |
	b := obPcBlocks at: (ir act: a) pcb + pc.
	b >= 0 ifTrue: [^b].
	b := ir newBlock.
	(ir block: b) act: a.
	(ir block: b) pc: pc.
	(self isLoopHead: pc act: a) ifTrue: [(ir block: b) flags: BF_LOOP].
	obPcBlocks at: (ir act: a) pcb + pc put: b.
	^b
! !

!OptBuilder methodsFor: 'frame states'!
stateAct: a pc: pc depth: d
	"The frame state of a continuing at pc with d slots, and its callers'."
	^self stateAct: a pc: pc depth: d livePc: pc
!
stateAct: a pc: pc depth: d livePc: lp
	"The frame state of a continuing at pc with d slots, and its callers' (each at its own pc). A temp that no instruction from lp on reads before storing it (liveSlotsAt:act:) is nil there: no phi, no value kept for it."
	<function>
	<var: #live type: 'uint64_t'>
	| s st ac vals p live |
	ac := ir act: a.
	s := ir newState.
	st := ir state: s.
	st act: a.
	st pc: pc.
	st depth: d.
	vals := ir allocOperands: d + 1.
	st vals: vals.
	ir operand: vals put: ac receiver.
	live := 16rFFFFFFFFFFFFFFFF asUInt64.
	(runtime flag: runtime liveFlag) ifTrue: [live := self liveSlotsAt: lp act: a].
	0 to: d - 1 do: [:i |
		((self var: a slot: i) < OPT_MAX_VARS and: [(obArgFlags at: (self var: a slot: i)) = 2])
			ifTrue: [ir operand: vals + 1 + i put: (obArgVals at: (self var: a slot: i))]
			ifFalse: [
				(a = obPerformAct and: [i >= obPerformSlot and: [i < (obPerformSlot + obPerformCount)]])
					ifTrue: [ir operand: vals + 1 + i put: (obPerformVals at: i - obPerformSlot)]
					ifFalse: [
						(i >= ac numArgs and: [i < (ac numArgs + ac numTemps) and: [i < 64 and: [(live bitAnd: 1 asUInt64 << i) = 0]]])
							ifTrue: [ir operand: vals + 1 + i put: self nilConstant]
							ifFalse: [ir operand: vals + 1 + i put: (self read: (self var: a slot: i))]]]].
	p := ac parent.
	p >= 0 ifTrue: [(ir state: s) parent: (self stateAct: p pc: (ac sendPc + (analysis lengthOf: (self byteAt: ac sendPc act: p))) asInt32 depth: (self receiverSlotAt: ac sendPc act: p))].
	^s
!
liveSlotsAt: pc act: a
	"The slots (0-63) of a's frame that an instruction from pc on may read before storing them (BytecodeAnalysis>>analyzeLiveness)."
	<returns: 'uint64_t'>
	(pc < 0 or: [pc >= (self methodSize: (ir act: a) method)]) ifTrue: [^16rFFFFFFFFFFFFFFFF asUInt64].
	^obAnaLive at: (ir act: a) ana + pc
!
nilConstant
	"nil for the dead temps of frame states: one constant for all of them."
	obNilConst < 0 ifTrue: [obNilConst := self constant: memory nilOop].
	^obNilConst
!
checkLive: i pc: pc act: a
	"The instruction at a's pc reads temp i: the liveness must have it live there (frame states drop the dead ones); else report it and give up the compilation."
	| ac |
	ac := ir act: a.
	((runtime flag: runtime liveFlag) and: [i >= ac numArgs and: [i < (ac numArgs + ac numTemps) and: [i < 64 and: [((self liveSlotsAt: pc act: a) bitAnd: 1 asUInt64 << i) = 0]]]]) ifFalse: [^self].
	libc fputs: 'samaltak: liveness mismatch ' to: libc stderr.
	interpreter printClassName: (self loadRef: ac method at: CM_CLASS) on: libc stderr.
	libc fputs: '>>' to: libc stderr.
	interpreter printSymbol: (self loadRef: ac method at: CM_SELECTOR) on: libc stderr.
	libc fprintf: libc stderr format: ' pc %d slot %d
' with: pc with: i.
	self bail
!
receiverSlotAt: pc act: a
	"The slot of the receiver of the send the instruction at pc makes."
	| p |
	p := (self methodBytecodes: (ir act: a) method) + pc.
	(analysis pushesOf: p) > 0 ifTrue: [^self depthAt: pc act: a].
	^(self depthAt: pc act: a) - (analysis sendArgcOf: p) - 1
!
checkInterruptAct: a pc: pc depth: d kind: k
	| n |
	n := self add: O_CHECKINT rep: R_NONE.
	obSafeEpoch := obSafeEpoch + 1.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	(ir node: n) aux: k.
	^n
! !

!OptBuilder methodsFor: 'bytecodes'!
emit: pc act: a
	"Build the instruction at a's pc; answer the next pc."
	<function>
	| op d next v |
	ir origin: a pc: pc.
	op := self byteAt: pc act: a.
	d := self depthAt: pc act: a.
	next := (pc + (analysis lengthOf: op)) asInt32.
	op < 16r10 ifTrue: [
		self checkLive: op pc: pc act: a.
		self push: (self read: (self var: a slot: op)) act: a depth: d.
		^next].
	op < 16r20 ifTrue: [
		self push: (self loadField: op - 16r10 of: (ir act: a) receiver) act: a depth: d.
		^next].
	op < 16r40 ifTrue: [
		self push: (self constant: (self literal: op - 16r20 act: a)) act: a depth: d.
		^next].
	op < 16r60 ifTrue: [
		self push: (self global: (self literal: op - 16r40 act: a) pc: pc act: a depth: d) act: a depth: d.
		^next].
	op < 16r68 ifTrue: [
		self write: (self var: a slot: op - 16r60) value: (self read: (self var: a slot: d - 1)).
		^next].
	op = 16r70 ifTrue: [
		self push: (ir act: a) receiver act: a depth: d.
		^next].
	op = 16r71 ifTrue: [
		self push: (self constant: memory trueOop) act: a depth: d.
		^next].
	op = 16r72 ifTrue: [
		self push: (self constant: memory falseOop) act: a depth: d.
		^next].
	op = 16r73 ifTrue: [
		self push: (self constant: memory nilOop) act: a depth: d.
		^next].
	op = 16r74 ifTrue: [
		self push: (self constant: (self intOop: 0)) act: a depth: d.
		^next].
	op = 16r75 ifTrue: [
		self push: (self constant: (self intOop: 1)) act: a depth: d.
		^next].
	op = 16r77 ifTrue: [
		self push: (self read: (self var: a slot: d - 1)) act: a depth: d.
		^next].
	op = 16r78 ifTrue: [^next].
	(op = 16r79 or: [op = 16r7B]) ifTrue: [
		self localReturn: (self read: (self var: a slot: d - 1)) act: a pc: pc depth: d.
		^next].
	op = 16r7A ifTrue: [
		self localReturn: (ir act: a) receiver act: a pc: pc depth: d.
		^next].
	op = 16r80 ifTrue: [
		self checkLive: (self byteAt: pc + 1 act: a) pc: pc act: a.
		self push: (self read: (self var: a slot: (self byteAt: pc + 1 act: a))) act: a depth: d.
		^next].
	(op = 16r81 and: [(self byteAt: pc + 1 act: a) > CTX_STACKP]) ifTrue: [
		self push: (self loadField: (self byteAt: pc + 1 act: a) of: (ir act: a) receiver) act: a depth: d.
		^next].
	op = 16r82 ifTrue: [
		self push: (self constant: (self literal: (self byteAt: pc + 1 act: a) act: a)) act: a depth: d.
		^next].
	op = 16r83 ifTrue: [
		self push: (self global: (self literal: (self byteAt: pc + 1 act: a) act: a) pc: pc act: a depth: d) act: a depth: d.
		^next].
	op = 16r84 ifTrue: [
		self write: (self var: a slot: (self byteAt: pc + 1 act: a)) value: (self read: (self var: a slot: d - 1)).
		^next].
	op = 16r85 ifTrue: [
		self storeField: (self byteAt: pc + 1 act: a) of: (ir act: a) receiver value: (self read: (self var: a slot: d - 1))
			checked: (self stateAct: a pc: pc depth: d).
		^next].
	(op = 16r86 or: [op = 16r89]) ifTrue: [
		self storeField: ASSOC_VALUE of: (self constant: (self literal: (self byteAt: pc + 1 act: a) act: a)) value: (self read: (self var: a slot: d - 1)) checked: -1.
		^next].
	op = 16r87 ifTrue: [
		self write: (self var: a slot: (self byteAt: pc + 1 act: a)) value: (self read: (self var: a slot: d - 1)).
		^next].
	op = 16r90 ifTrue: [
		self jumpTo: (pc + 3 + (self int16At: pc + 1 act: a)) from: pc act: a.
		^next].
	(op = 16r91 or: [op = 16r92]) ifTrue: [
		self conditionalJump: pc act: a.
		^next].
	op = 16r93 ifTrue: [
		self push: (self constant: (self intOop: (self int16At: pc + 1 act: a))) act: a depth: d.
		^next].
	(op = 16r8D or: [op = 16r8E or: [op >= 16rC0 and: [op < 16rF0]]]) ifTrue: [
		self send: pc act: a.
		^next].
	((op >= 16r97 and: [op < 16rA0]) or: [op >= 16rF0 and: [op < 16rFC]]) ifTrue: [
		self superinstruction: pc act: a.
		^next].
	(op >= 16rA0 and: [op < 16rC0]) ifTrue: [
		self special: op - 16rA0 pc: pc act: a rcvSlot: d - (analysis specialArgc: op - 16rA0) - 1.
		^next].
	op = 16r8F ifTrue: [
		v := self closureAt: pc act: a.
		self push: v act: a depth: d.
		^(pc + 6 + (((self byteAt: pc + 4 act: a) asInt64 << 8) bitOr: (self byteAt: pc + 5 act: a))) asInt32].
	(op >= 16r8A and: [op <= 16r8C]) ifTrue: [
		self outerTemp: pc act: a depth: d.
		^next].
	op = 16r7C ifTrue: [
		self nonLocalReturn: (self read: (self var: a slot: d - 1)) act: a pc: pc depth: d.
		^next].
	op = 16r94 ifTrue: [
		self makeArray: (self byteAt: pc + 1 act: a) asInt32 pc: pc act: a depth: d.
		^next].
	"thisContext, Context's mediated fields (0x81 0-2, 0x88): not yet"
	self bail.
	^next
!
makeArray: k pc: pc act: a depth: d
	"0x94 k: an Array of the top k slots (OptCodegen>>emitMakeArray:), a safepoint with the frame state before it."
	| n args |
	n := self add: O_MKARRAY rep: R_OOP.
	obSafeEpoch := obSafeEpoch + 1.
	args := ir allocOperands: k.
	0 to: k - 1 do: [:i | ir operand: args + i put: (self read: (self var: a slot: d - k + i))].
	(ir node: n) args: args.
	(ir node: n) nargs: k asUInt16.
	(ir node: n) tkind: T_OBJ.
	(ir node: n) tcls: memory clsArray.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	self push: n act: a depth: d - k
!
closureAt: pc act: a
	"0x8F: a BlockClosure for the body after pc; as long as it is only evaluated by inlined value sends it is never made (its frame states describe it)."
	| n na nt fs |
	na := self byteAt: pc + 1 act: a.
	nt := self byteAt: pc + 2 act: a.
	fs := self byteAt: pc + 3 act: a.
	n := self add: O_CLOSURE rep: R_OOP.
	(ir node: n) aux: pc + 6.
	(ir node: n) aux2: (((na asInt64 bitOr: nt asInt64 << 8) bitOr: fs asInt64 << 16) bitOr: a asInt64 << 32).
	(ir node: n) tkind: T_OBJ.
	(ir node: n) tcls: memory clsBlock.
	(ir node: n) flags: NF_PURE.
	^n
!
outerTemp: pc act: a depth: d
	"push (8A), store (8B), pop and store (8C) a temp of an enclosing block or method: inlined, it is that activation's variable."
	| op t v lv |
	op := self byteAt: pc act: a.
	t := a.
	lv := (self byteAt: pc + 1 act: a) asInt32.
	[lv > 0 and: [(ir act: t) outer >= 0]] whileTrue: [
		t := (ir act: t) outer.
		lv := lv - 1].
	lv > 0 ifTrue: [
		"the unit's block (its closure the frame's), or a closure another frame made: through its outerContext chain"
		(t = 0 and: [obUnitStart > 0]) ifTrue: [^self outerTemp: op levels: lv index: (self byteAt: pc + 2 act: a) closure: (ir act: 0) closure act: a depth: d].
		(ir act: t) outer = -2 ifTrue: [^self outerTemp: op levels: lv index: (self byteAt: pc + 2 act: a) closure: (ir act: t) closure act: a depth: d].
		^self bail].
	op = 16r8A ifTrue: [^self push: (self read: (self var: t slot: (self byteAt: pc + 2 act: a))) act: a depth: d].
	v := self read: (self var: a slot: d - 1).
	self write: (self var: t slot: (self byteAt: pc + 2 act: a)) value: v
!
outerTemp: op levels: lv index: i closure: c act: a depth: d
	"An outer temp of closure c (the block unit's, or one another frame made), lv levels out: in its outerContext chain (or the frame it is married to)."
	| n |
	n := self add: (op = 16r8A ifTrue: [O_OUTERLOAD] ifFalse: [O_OUTERSTORE]) rep: (op = 16r8A ifTrue: [R_OOP] ifFalse: [R_NONE]).
	(ir node: n) a: c.
	(ir node: n) aux: lv.
	(ir node: n) aux2: i.
	op = 16r8A ifTrue: [^self push: n act: a depth: d].
	(ir node: n) b: (self read: (self var: a slot: d - 1))
!
nonLocalReturn: v act: a pc: pc depth: d
	"^ in a block: return from its home method, inlined here (or the method compiled); in a block unit the interpreter does it."
	| h n |
	h := (ir act: a) home.
	"in a closure another frame made: the next build calls it"
	(h < 0 and: [obForeignDepth > 0]) ifTrue: [^self bail].
	(h < 0 and: [obUnitStart > 0]) ifTrue: [^self deoptAct: a state: (self stateAct: a pc: pc depth: d)].
	(h < 0 or: [(ir act: h) closure >= 0]) ifTrue: [^self bail].
	(ir act: h) parent >= 0 ifTrue: [
		self write: (ir act: h) retVar value: v.
		^self goto: (ir act: h) retBlock].
	n := self add: O_RETURN rep: R_NONE.
	(ir node: n) a: v.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	obCurBlock := -1
!
isValueSelector: sel
	"sel is value or value: repeated."
	| b n |
	((self isPtr: sel) and: [(self formatOf: sel) >= F_BYTES]) ifFalse: [^false].
	n := (memory byteSize: sel) asInt64.
	b := self bytesOf: sel.
	(n >= 5 and: [(b at: 0) = $v value and: [(b at: 1) = $a value and: [(b at: 2) = $l value and: [(b at: 3) = $u value and: [(b at: 4) = $e value]]]]]) ifFalse: [^false].
	n = 5 ifTrue: [^true].
	(n rem: 6) = 0 ifFalse: [^false].
	0 to: (n quo: 6) - 1 do: [:i |
		((b at: 6 * i) = $v value and: [(b at: 6 * i + 5) = $: value]) ifFalse: [^false]].
	^true
!
isClosure: v numArgs: n
	"v is a closure this compilation made, taking n arguments."
	| nd |
	nd := ir node: (self liveValueOf: v).
	^nd op asInt32 = O_CLOSURE and: [(nd aux2 bitAnd: 255) = n]
!
inlineBlock: c info: d pc: pc act: a rcvSlot: r argc: argc
	"Evaluate closure c here (made in this compilation, or by the frame: d describes it, an O_CLOSURE node): its body as an activation whose outer activation is the one that made it."
	<function>
	| def |
	def := ((ir node: d) aux2 >> 32) asInt32.
	self inlineBody: c info: d method: (ir act: def) method ana: (ir act: def) ana outer: def home: (ir act: def) home receiver: (ir act: def) receiver pc: pc act: a rcvSlot: r argc: argc
!
inlineBody: c info: d method: m ana: ana outer: o home: h receiver: rcv pc: pc act: a rcvSlot: r argc: argc
	"Evaluate closure c (d describes its body, an O_CLOSURE node) here, its body an activation of m whose outer activation is o (-2: not in this compilation, its outer temps through c), home h, receiver rcv."
	<function>
	| b ac nd entry ret na nt fs size |
	nd := ir node: d.
	na := (nd aux2 bitAnd: 255) asInt32.
	nt := ((nd aux2 >> 8) bitAnd: 255) asInt32.
	fs := ((nd aux2 >> 16) bitAnd: 255) asInt32.
	ana < 0 ifTrue: [^self bail].
	b := ir newAct.
	b < 0 ifTrue: [^self bail].
	ac := ir act: b.
	ac method: m.
	ac ana: ana.
	ac numArgs: na.
	ac numTemps: nt.
	fs < (na + nt) ifTrue: [fs := na + nt].
	ac nslots: fs + 4.
	ac startpc: nd aux asInt32.
	size := ((self byteAt: nd aux asInt32 - 2 act: b) asInt64 << 8 bitOr: (self byteAt: nd aux asInt32 - 1 act: b)) asInt32.
	ac endpc: nd aux asInt32 + size.
	ac closure: c.
	ac outer: o.
	ac home: h.
	ac receiver: rcv.
	ac parent: a.
	ac sendPc: pc.
	ac sendArgc: argc.
	(self allocPcBlocks: b) ifFalse: [^self].
	ac varBase: obVarTop.
	ac retVar: obVarTop + ac nslots.
	obVarTop := obVarTop + ac nslots + 1.
	obInlined := obInlined + size.
	0 to: argc - 1 do: [:i | self writeArg: (self var: b slot: i) value: (self read: (self var: a slot: r + 1 + i))].
	argc to: argc + nt - 1 do: [:i | self write: (self var: b slot: i) value: (self constant: memory nilOop)].
	entry := ir newBlock.
	(ir block: entry) act: b.
	ret := ir newBlock.
	(ir block: ret) act: a.
	ac retBlock: ret.
	self goto: entry.
	obCurBlock := entry.
	self seal: entry.
	self buildAct: b.
	ir origin: a pc: pc.
	self seal: ret.
	(ir block: ret) npreds = 0 ifTrue: [
		obCurBlock := -1.
		^self].
	obCurBlock := ret.
	self write: (self var: a slot: r) value: (self read: (ir act: b) retVar)
!
escapingClosure
	"A closure that something other than a frame state uses (it would have to be made): the activation that made it, -1 if there is none."
	<function>
	| nd |
	0 to: ir nodeCount - 1 do: [:n |
		nd := ir node: n.
		(nd block >= 0 and: [(nd flags bitAnd: NF_DEAD) = 0]) ifTrue: [
			(self usesClosure: nd a) ifTrue: [^self definingActOf: nd a].
			(self usesClosure: nd b) ifTrue: [^self definingActOf: nd b].
			(nd op asInt32 ~= O_SEND and: [self usesClosure: nd c]) ifTrue: [^self definingActOf: nd c].
			"a phi that is one closure is that closure"
			(nd op asInt32 ~= O_PHI or: [(self closureOf: n depth: 0) < 0]) ifTrue: [
				0 to: nd nargs asInt32 - 1 do: [:i | (self usesClosure: (ir operand: nd args + i)) ifTrue: [^self definingActOf: (ir operand: nd args + i)]]]]].
	^-1
!
usesClosure: v
	v < 0 ifTrue: [^false].
	^(self closureOf: v depth: 0) >= 0
!
closureOf: v depth: d
	"The closure v is (through phis of it and themselves), -1 if none."
	<function>
	<returns: 'int32_t'>
	| n nd c x |
	n := ir resolve: v.
	nd := ir node: n.
	nd op asInt32 = O_CLOSURE ifTrue: [^n].
	(nd op asInt32 = O_PHI and: [d < 8 and: [nd nargs > 0]]) ifFalse: [^-1].
	c := -1.
	0 to: nd nargs asInt32 - 1 do: [:i |
		x := ir resolve: (ir operand: nd args + i).
		x ~= n ifTrue: [
			x := self closureOf: x depth: d + 1.
			(x < 0 or: [c >= 0 and: [c ~= x]]) ifTrue: [^-1].
			c := x]].
	^c
!
definingActOf: v
	^((ir node: (self closureOf: v depth: 0)) aux2 >> 32) asInt32
!
push: v act: a depth: d
	self write: (self var: a slot: d) value: v
!
loadField: i of: o
	| n |
	n := self add: O_LOADFIELD rep: R_OOP.
	(ir node: n) a: o.
	(ir node: n) aux: i.
	^n
!
storeField: i of: o value: v checked: s
	"Store v into o's field i; s >= 0: the state if o is immutable (the interpreter sends attemptToAssign:withIndex:)."
	| n st r |
	"o was checked in this block since the last safepoint: it is still mutable"
	(obCheckedBlock ~= obCurBlock or: [obCheckedEpoch ~= obSafeEpoch]) ifTrue: [
		obCheckedCount := 0.
		obCheckedBlock := obCurBlock.
		obCheckedEpoch := obSafeEpoch].
	r := ir resolve: o.
	st := s.
	0 to: obCheckedCount - 1 do: [:k | (obChecked at: k) = r ifTrue: [st := -1]].
	(st >= 0 and: [obCheckedCount < 8]) ifTrue: [
		obChecked at: obCheckedCount put: r.
		obCheckedCount := obCheckedCount + 1].
	n := self add: O_STOREFIELD rep: R_NONE.
	(ir node: n) a: o.
	(ir node: n) b: v.
	(ir node: n) aux: i.
	(ir node: n) state: st.
	^n
!
localReturn: v act: a pc: pc depth: d
	"Return v: from the method (the state is for the interpreter to return from the bottom frame), or from an inlined activation to its caller."
	| n |
	(ir act: a) parent >= 0 ifTrue: [
		self write: (ir act: a) retVar value: v.
		^self goto: (ir act: a) retBlock].
	n := self add: O_RETURN rep: R_NONE.
	(ir node: n) a: v.
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	obCurBlock := -1
!
jumpTo: t from: pc act: a
	| b |
	b := self blockAt: t act: a.
	"a backward jump checks for interrupts before it is taken (an unconditional one at its pc, else at its target)"
	t <= pc ifTrue: [
		(self byteAt: pc act: a) = 16r90
			ifTrue: [self checkInterruptAct: a pc: pc depth: (self depthAt: pc act: a) kind: SP_LOOP]
			ifFalse: [self checkInterruptAct: a pc: t depth: (self depthAt: t act: a) kind: SP_LOOP]].
	self goto: b.
	(t <= pc and: [(self lastBackJumpTo: t act: a) = pc]) ifTrue: [self seal: b]
!
conditionalJump: pc act: a
	"Pop, jump to t if true (0x91) or false (0x92); neither: deoptimize (the interpreter sends mustBeBoolean)."
	| op t d v taken fall n onTrue onFalse k back c |
	op := self byteAt: pc act: a.
	t := pc + 3 + (self int16At: pc + 1 act: a).
	d := self depthAt: pc act: a.
	v := self read: (self var: a slot: d - 1).
	back := t <= pc.
	fall := self blockAt: pc + 3 act: a.
	taken := self blockAt: t act: a.
	k := (ir node: (self liveValueOf: v)) op asInt32.
	k = O_CONST ifTrue: [
		c := (ir node: (self liveValueOf: v)) aux asUInt64.
		(c = memory trueOop or: [c = memory falseOop]) ifTrue: [
			(c = memory trueOop) = (op = 16r91)
				ifTrue: [self jumpTo: t from: pc act: a]
				ifFalse: [self goto: fall].
			^self]].
	back ifTrue: [
		"the backward edge goes through an interrupt check"
		n := ir newBlock.
		(ir block: n) act: a.
		(ir block: n) flags: BF_SEALED.
		taken := n].
	onTrue := op = 16r91 ifTrue: [taken] ifFalse: [fall].
	onFalse := op = 16r91 ifTrue: [fall] ifFalse: [taken].
	n := self add: O_BRANCH rep: R_NONE.
	(ir node: n) a: v.
	"a Boolean branches; anything else may be sent mustBeBoolean"
	(ir node: (ir resolve: v)) tkind asInt32 ~= T_BOOL ifTrue: [(ir node: n) state: (self stateAct: a pc: pc depth: d)].
	(ir block: obCurBlock) succ0: onTrue.
	(ir block: obCurBlock) succ1: onFalse.
	self edgeTo: onTrue.
	self edgeTo: onFalse.
	obCurBlock := -1.
	back ifTrue: [
		obCurBlock := taken.
		self jumpTo: t from: pc act: a]
! !

!OptBuilder methodsFor: 'sends'!
send: pc act: a
	<var: #kind type: 'int32_t'>
	| op argc sel kind |
	op := self byteAt: pc act: a.
	op >= 16rC0
		ifTrue: [
			argc := ((op - 16rC0) >> 4) asInt32.
			sel := self literal: (op bitAnd: 15) act: a.
			kind := 0]
		ifFalse: [
			argc := (self byteAt: pc + 2 act: a) asInt32.
			sel := self literal: (self byteAt: pc + 1 act: a) act: a.
			kind := op = 16r8E ifTrue: [1] ifFalse: [0]].
	self sendSelector: sel argc: argc kind: kind special: 0 pc: pc act: a rcvSlot: (self depthAt: pc act: a) - argc - 1
!
superinstruction: pc act: a
	"push temp a, push temp / literal / int8 b, then a special selector: the operands are pushed as the interpreter would."
	| op x y k d |
	op := self byteAt: pc act: a.
	d := self depthAt: pc act: a.
	self checkLive: (self byteAt: pc + 1 act: a) pc: pc act: a.
	x := self read: (self var: a slot: (self byteAt: pc + 1 act: a)).
	(op = 16r97 or: [op >= 16r9A and: [op < 16rA0]])
		ifTrue: [
			self checkLive: (self byteAt: pc + 2 act: a) pc: pc act: a.
			y := self read: (self var: a slot: (self byteAt: pc + 2 act: a))]
		ifFalse: [
			(op = 16r98 or: [op >= 16rF0 and: [op < 16rF6]])
				ifTrue: [y := self constant: (self literal: (self byteAt: pc + 2 act: a) act: a)]
				ifFalse: [y := self constant: (self intOop: (self byteAt: pc + 2 act: a) asInt8)]].
	self push: x act: a depth: d.
	self push: y act: a depth: d + 1.
	k := analysis specialIndexOf: (self methodBytecodes: (ir act: a) method) + pc.
	self special: k pc: pc act: a rcvSlot: d
!
special: k pc: pc act: a rcvSlot: r
	"Special selector k at pc, receiver in slot r: inline what needs no send, else send it."
	| x y n argc fl |
	(sliceTest enabled and: [obSlice]) ifTrue: [
		(k = 0 or: [k = 1]) ifFalse: [^self bail].
		^self intArith: k x: (self read: (self var: a slot: r)) y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r].
	argc := analysis specialArgc: k.
	x := self read: (self var: a slot: r).
	argc > 0 ifTrue: [y := self read: (self var: a slot: r + 1)].
	(k = 19 or: [k = 20]) ifTrue: [
		self push: (self compare: (k = 19 ifTrue: [O_EQ] ifFalse: [O_NE]) a: x b: y) act: a depth: r.
		^self].
	((k = 21 or: [k = 22 or: [k = 30]]) and: [(runtime flag: runtime blocksFlag) and: [self isClosure: x numArgs: argc]]) ifTrue: [
		^self inlineBlock: (self liveValueOf: x) info: (self liveValueOf: x) pc: pc act: a rcvSlot: r argc: argc].
	((k = 21 or: [k = 22 or: [k = 30]]) and: [(n := self frameClosureOf: x numArgs: argc pc: pc act: a) >= 0]) ifTrue: [
		^self inlineFrameClosure: x info: n pc: pc act: a rcvSlot: r argc: argc].
	((k = 21 or: [k = 22 or: [k = 30]]) and: [self inlineForeignClosure: x pc: pc act: a rcvSlot: r argc: argc]) ifTrue: [^self].
	k = 29 ifTrue: [
		"the class of a value of a known class: a constant"
		(self knownClassOf: x) ~= 0 ifTrue: [
			self push: (self constant: (self knownClassOf: x)) act: a depth: r.
			^self].
		n := self add: O_CLASSOF rep: R_OOP.
		(ir node: n) a: x.
		self push: n act: a depth: r.
		^self].
	(k >= 16 and: [k <= 18 and: [(self knownClassOf: x) = 0 and: [(self frameClassOf: x) = 0 and: [(runtime flag: runtime primsFlag) and: [(feedback siteAt: (ir act: a) method pc: pc) isNull]]]]]) ifTrue: [
		"no feedback: the lower tier took them all inline"
		self write: (self var: a slot: r) value: (self guard: x class: (self guessedClassOf: x) state: (self stateAct: a pc: pc depth: (self depthAt: pc act: a)))].
	((k = 21 or: [k = 22 or: [k = 30]]) and: [(self knownClassOf: x) = 0 and: [(runtime flag: runtime callsFlag) and: [(feedback siteAt: (ir act: a) method pc: pc) isNull]]]) ifTrue: [
		"no feedback: the lower tier's closure fast path took them all"
		self write: (self var: a slot: r) value: (self guard: x class: memory clsBlock state: (self stateAct: a pc: pc depth: (self depthAt: pc act: a)))].
	((k = 23 or: [k = 24]) and: [(runtime flag: runtime primsFlag) and: [runtime nilTestsInlinable]]) ifTrue: [
		"isNil, notNil: no class but UndefinedObject and ProtoObject defines them (new definitions drop all code)"
		self push: (self compare: (k = 23 ifTrue: [O_EQ] ifFalse: [O_NE]) a: x b: (self constant: memory nilOop)) act: a depth: r.
		^self].
	(k <= 10 or: [k = 12 or: [k = 13 or: [k = 14 or: [k = 15]]]]) ifTrue: [
		fl := feedback flagsAt: (ir act: a) method pc: pc.
		(k <= 9 and: [(runtime flag: runtime unboxFlag) and: [(fl bitAnd: (feedback sawNonInt bitOr: feedback deoptOther)) = 0 and: [
			(self isFloat: x) or: [(self isFloat: y) or: [(self sawOnlyNumbersAt: pc act: a) and: [(fl bitAnd: feedback sawFloat) ~= 0 or: [self sawFloatIn: (ir act: a) method]]]]]]]) ifTrue: [
				^self floatArith: k x: x y: y pc: pc act: a rcvSlot: r].
		((fl bitAnd: ((feedback sawFloat bitOr: feedback sawNonInt) bitOr: (feedback deoptArith bitOr: feedback overflowed))) = 0 and: [
			self sawOnlyIntsAt: pc act: a]) ifTrue: [
				^self intArith: k x: x y: y pc: pc act: a rcvSlot: r]].
	self sendSelector: (self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: k) argc: argc kind: 2 special: k pc: pc act: a rcvSlot: r
!
guessedClassOf: x
	"The class to take x for where at:, at:put: or size reported none (the lower tier takes Arrays and Strings inline): the class of what an outer temp holds now, of a closure the frame shows; else the class the latest guard of x in this compilation took it for; else Array."
	<function>
	<returns: 'oop'>
	| n o nd |
	n := self liveValueOf: x.
	(ir node: n) op asInt32 = O_OUTERLOAD ifTrue: [
		o := self knownObject: n.
		(o ~= 0 and: [(self isPtr: o) and: [(self rawClass: o) ~= memory clsBlock and: [(self rawClass: o) ~= memory clsContext]]]) ifTrue: [^self rawClass: o]].
	ir nodeCount - 1 to: (ir nodeCount - 512 max: 0) by: -1 do: [:i |
		nd := ir node: i.
		(nd op asInt32 = O_GUARDCLASS and: [nd block >= 0 and: [nd a = n or: [nd a = x]]]) ifTrue: [^nd aux asUInt64]].
	^memory clsArray
!
anyImmediate: site count: n
	"Whether one of the first n classes site reports is a class of immediates (SmallInteger, Character, SmallFloat64)."
	| c |
	0 to: n - 1 do: [:i |
		c := site classes at: i.
		(c = memory clsSmallint or: [c = memory clsChar or: [c = memory clsSmallfloat]]) ifTrue: [^true]].
	^false
!
sawOnlyIntsAt: pc act: a
	"The send at a's pc reported no receiver class but SmallInteger (the lower tier's inline paths report none)."
	| site |
	site := feedback siteAt: (ir act: a) method pc: pc.
	site isNull ifTrue: [^true].
	0 to: feedback classSlots - 1 do: [:i |
		((site classes at: i) ~= 0 and: [(site classes at: i) ~= memory clsSmallint]) ifTrue: [^false]].
	^true
!
sawIntAt: m pc: pc
	"The send at m's pc reported a SmallInteger receiver."
	| site |
	site := feedback siteAt: m pc: pc.
	site isNull ifTrue: [^false].
	0 to: feedback classSlots - 1 do: [:i | (site classes at: i) = memory clsSmallint ifTrue: [^true]].
	^false
!
sawIntsIn: m
	"Some arithmetic of m that the lower tier takes inline reported a SmallInteger (m's arithmetic mixes them with other numbers: its sites that reported other classes only may well take them too, unreported)."
	0 to: obAnaCount - 1 do: [:i | (obAnaMethods at: i) = m ifTrue: [^obAnaInts at: i]].
	^false
!
sawOnlyNumbersAt: pc act: a
	"The send at a's pc reported no receiver class but SmallInteger and the Floats (a Point's arithmetic is a send)."
	| site c |
	site := feedback siteAt: (ir act: a) method pc: pc.
	site isNull ifTrue: [^true].
	0 to: feedback classSlots - 1 do: [:i |
		c := site classes at: i.
		(c ~= 0 and: [c ~= memory clsSmallint and: [c ~= memory clsSmallfloat and: [c ~= memory clsBoxedfloat]]]) ifTrue: [^false]].
	^true
!
intArith: k x: x y: y pc: pc act: a rcvSlot: r
	"SmallInteger arithmetic or comparison, speculated: guards deoptimize to the send."
	| s gx gy n |
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	gx := self guardInt: x state: s.
	gy := self guardInt: y state: s.
	(k >= 2 and: [k <= 7]) ifTrue: [
		n := self binary: O_ICMP a: gx b: gy.
		(ir node: n) aux: k.
		(ir node: n) tkind: T_BOOL.
		self push: n act: a depth: r.
		^self].
	n := self binary: (k caseOf: {[0] -> [O_IADD]. [1] -> [O_ISUB]. [8] -> [O_IMUL]. [9] -> [O_IDIV]. [10] -> [O_IMOD]. [11] -> [O_IXOR]. [12] -> [O_ISHIFT]. [13] -> [O_IDIV]. [14] -> [O_IAND]. [16] -> [O_IDIV]. [17] -> [O_IMOD]} otherwise: [O_IOR]) a: gx b: gy.
	(ir node: n) tkind: T_SMI.
	"quo: rem: truncate; / is exact (a Fraction deoptimizes)"
	k >= 16 ifTrue: [(ir node: n) aux: 1].
	k = 9 ifTrue: [(ir node: n) aux: 2].
	(k <= 1 or: [(k between: 8 and: 10) or: [k = 12 or: [k = 13 or: [k >= 16]]]]) ifTrue: [(ir node: n) state: s].
	self push: n act: a depth: r
!
floatArith: k x: x y: y pc: pc act: a rcvSlot: r
	"Float arithmetic or comparison k, speculated: SmallFloat64 or SmallInteger operands as doubles (two SmallIntegers: the SmallInteger operation), the result a SmallFloat64; anything else deoptimizes to the send."
	<function>
	<var: #merge type: 'int32_t'>
	| s fx fy n merge t f test fl |
	fl := feedback flagsAt: (ir act: a) method pc: pc.
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	merge := -1.
	(((self isFloat: x) or: [self isFloat: y]) not and: [self speculatesFloats: fl]) ifTrue: [
		"Floats here and no SmallInteger operation: two SmallIntegers deoptimize"
		test := self add: O_NOTINTS rep: R_NONE.
		(ir node: test) a: x.
		(ir node: test) b: y.
		(ir node: test) state: s.
		(ir node: test) flags: NF_GUARD].
	((self isFloat: x) or: [(self isFloat: y) or: [self speculatesFloats: fl]]) ifFalse: [
		test := self binary: O_BOTHINT a: x b: y.
		(ir node: test) tkind: T_BOOL.
		t := ir newBlock.
		(ir block: t) act: a.
		f := ir newBlock.
		(ir block: f) act: a.
		merge := ir newBlock.
		(ir block: merge) act: a.
		self branch: test true: t false: f.
		self seal: t.
		self seal: f.
		obCurBlock := t.
		(fl bitAnd: (feedback deoptArith bitOr: feedback overflowed)) ~= 0
			ifTrue: [self callSelector: (self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: k) argc: 1 kind: 2 special: k pc: pc act: a rcvSlot: r]
			ifFalse: [self intArith: k x: (self cast: x class: memory clsSmallint) y: (self cast: y class: memory clsSmallint) pc: pc act: a rcvSlot: r].
		self goto: merge.
		obCurBlock := f].
	fx := self unboxFloat: x state: s.
	fy := self unboxFloat: y state: s.
	(k >= 2 and: [k <= 7])
		ifTrue: [
			n := self binary: O_FCMP a: fx b: fy.
			(ir node: n) aux: k.
			(ir node: n) tkind: T_BOOL.
			self push: n act: a depth: r]
		ifFalse: [
			n := self add: O_FARITH rep: R_DBL.
			(ir node: n) a: fx.
			(ir node: n) b: fy.
			(ir node: n) aux: k.
			k = 9 ifTrue: [(ir node: n) state: s].
			self push: (self boxFloat: n state: s) act: a depth: r].
	merge >= 0 ifTrue: [
		self goto: merge.
		self seal: merge.
		obCurBlock := merge]
!
speculatesFloats: fl
	"An arithmetic site with flags fl takes Floats only: it saw Floats and never two SmallIntegers (one that only its method's other arithmetic saw Floats at takes both)."
	^(fl bitAnd: feedback sawFloat) ~= 0 and: [(fl bitAnd: feedback sawInts) = 0]
!
sawFloatIn: m
	"Some arithmetic of m saw a Float (its other arithmetic may well too)."
	0 to: obAnaCount - 1 do: [:i | (obAnaMethods at: i) = m ifTrue: [^obAnaFloat at: i]].
	^false
!
isFloat: v
	^(ir node: (ir resolve: v)) tkind asInt32 = T_FLOAT
!
unboxFloat: v state: s
	"v as a double: a SmallFloat64 or BoxedFloat64 decoded, a SmallInteger converted, else deoptimize; a value this block boxed since the last safepoint is used directly."
	| nd n |
	nd := ir node: v.
	(nd op asInt32 = O_BOXF and: [nd block = obCurBlock and: [nd aux2 = obSafeEpoch]]) ifTrue: [^nd a].
	n := self add: O_UNBOXF rep: R_DBL.
	(ir node: n) a: v.
	(ir node: n) state: s.
	(ir node: n) flags: NF_GUARD.
	^n
!
boxFloat: d state: s
	"Double d as a SmallFloat64; out of its range: deoptimize (the interpreter makes a boxed Float)."
	| n |
	n := self add: O_BOXF rep: R_OOP.
	(ir node: n) a: d.
	(ir node: n) state: s.
	(ir node: n) tkind: T_FLOAT.
	(ir node: n) aux2: obSafeEpoch.
	^n
!
guardInt: v state: s
	| n |
	(ir node: v) tkind asInt32 = T_SMI ifTrue: [^v].
	n := self add: O_GUARDINT rep: R_OOP.
	(ir node: n) a: v.
	(ir node: n) state: s.
	(ir node: n) tkind: T_SMI.
	(ir node: n) flags: NF_GUARD.
	^n
!
sendSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
	"A send: inlined (or called) for the receiver's class if it is known, for each class feedback saw (guarded), else through an inline cache."
	| d |
	((runtime flag: runtime blocksFlag) and: [(self isValueSelector: sel) and: [self isClosure: (self read: (self var: a slot: r)) numArgs: argc]]) ifTrue: [
		self inlineBlock: (self liveValueOf: (self read: (self var: a slot: r))) info: (self liveValueOf: (self read: (self var: a slot: r))) pc: pc act: a rcvSlot: r argc: argc.
		^-1].
	(((runtime flag: runtime blocksFlag) and: [self isValueSelector: sel]) and: [(d := self frameClosureOf: (self read: (self var: a slot: r)) numArgs: argc pc: pc act: a) >= 0]) ifTrue: [
		self inlineFrameClosure: (self read: (self var: a slot: r)) info: d pc: pc act: a rcvSlot: r argc: argc.
		^-1].
	((self isValueSelector: sel) and: [self inlineForeignClosure: (self read: (self var: a slot: r)) pc: pc act: a rcvSlot: r argc: argc]) ifTrue: [^-1].
	((runtime flag: runtime inlineFlag) and: [self inlineSend: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r]) ifTrue: [^-1].
	^self callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
!
inlineSend: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
	"Inline the send for the receiver classes it is known or speculated to have; answer whether it did."
	<function>
	<var: #rcvClass type: 'int32_t'>
	| rcv cls site n merge s test next t g fl other andInts rcvClass |
	rcv := self read: (self var: a slot: r).
	kind = 1 ifTrue: [
		cls := self loadRef: (self loadRef: (ir act: a) method at: CM_CLASS) at: BEH_SUPERCLASS.
		^self send: sel to: rcv class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r].
	cls := self knownClassOf: rcv.
	cls = 0 ifTrue: [cls := self frameClassOf: rcv].
	cls ~= 0 ifTrue: [^self send: sel to: rcv class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r].
	site := feedback siteAt: (ir act: a) method pc: pc.
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'opt: send at pc %d of act %d: feedback %s ' with: pc with: a with: (site isNull ifTrue: ['none'] ifFalse: ['some']).
		interpreter printSymbol: sel on: libc stderr.
		site isNull ifFalse: [
			libc fprintf: libc stderr format: ' (flags %d:' with: site flags.
			0 to: feedback classSlots - 1 do: [:i |
				(site classes at: i) ~= 0 ifTrue: [
					libc fputc: 32 to: libc stderr.
					interpreter printClassName: (site classes at: i) on: libc stderr]].
			libc fputc: 41 to: libc stderr].
		libc fputc: 10 to: libc stderr].
	site isNull ifTrue: [^false].
	fl := site flags.
	(fl bitAnd: (feedback mega bitOr: feedback deoptOther)) ~= 0 ifTrue: [^false].
	n := 0.
	0 to: feedback classSlots - 1 do: [:i | (site classes at: i) ~= 0 ifTrue: [n := n + 1]].
	n = 0 ifTrue: [^false].
	"the lower tier's inline Float paths report no class: an arithmetic site that saw Floats too sends what it has no class for"
	other := kind = 2 and: [k <= 9 and: [((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback sawFloat) ~= 0]].
	"nor does its inline SmallInteger path: SmallIntegers have a case where the method's arithmetic reported some, also at a site that reported none"
	andInts := kind = 2 and: [(analysis specialInlinesIntegers: k) and: [(self sawIntsIn: (ir act: a) method) and: [(self sawIntAt: (ir act: a) method pc: pc) not]]].
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	(n = 1 and: [other not and: [andInts not]]) ifTrue: [
		g := self guard: rcv class: (site classes at: 0) state: s.
		^self send: sel to: g class: (site classes at: 0) argc: argc kind: kind pc: pc act: a rcvSlot: r].
	"a type switch; any other class deoptimizes (is sent, see above)"
	merge := ir newBlock.
	(ir block: merge) act: a.
	andInts ifTrue: [n := n + 1].
	"between classes of objects (no immediates): the class loaded once, compared with each (value numbering shares the load with other switches on the value)"
	rcvClass := -1.
	(andInts not and: [n > 1 and: [(self anyImmediate: site count: n) not]]) ifTrue: [
		rcvClass := self add: O_CLASSOF rep: R_OOP.
		(ir node: rcvClass) a: rcv].
	0 to: n - 1 do: [:i |
		cls := (andInts and: [i = (n - 1)]) ifTrue: [memory clsSmallint] ifFalse: [site classes at: i].
		rcvClass >= 0
			ifTrue: [test := self compare: O_EQ a: rcvClass b: (self constant: cls)]
			ifFalse: [
				test := self add: O_CLASSIS rep: R_OOP.
				(ir node: test) a: rcv.
				(ir node: test) aux: cls asInt64.
				(ir node: test) tkind: T_BOOL].
		t := ir newBlock.
		(ir block: t) act: a.
		next := ir newBlock.
		(ir block: next) act: a.
		self branch: test true: t false: next.
		self seal: t.
		self seal: next.
		obCurBlock := t.
		g := self cast: rcv class: cls.
		self write: (self var: a slot: r) value: g.
		(self send: sel to: g class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r) ifFalse: [
			self callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r].
		obCurBlock >= 0 ifTrue: [self goto: merge].
		obCurBlock := next].
	other
		ifTrue: [
			self callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r.
			obCurBlock >= 0 ifTrue: [self goto: merge]]
		ifFalse: [self deoptAct: a state: s].
	self seal: merge.
	obCurBlock := (ir block: merge) npreds > 0 ifTrue: [merge] ifFalse: [-1].
	^true
!
send: sel to: rcv class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r
	"The receiver's class is cls: inline the method it finds, else send. Answer false only if nothing was emitted."
	| m p |
	"a married Context's slots are its frame's: its primitives (at: and friends) answer them, not inlined code"
	cls = memory clsContext ifTrue: [^false].
	m := interpreter lookupMethod: cls selector: sel.
	m = 0 ifTrue: [^false].
	self noteDependency: sel.
	self write: (self var: a slot: r) value: rcv.
	(kind = 0 and: [(p := self performedAt: r + 1 act: a argc: argc - 1 class: cls method: m) ~= 0]) ifTrue: [
		^self sendPerformed: p to: rcv class: cls argc: argc - 1 pc: pc act: a rcvSlot: r].
	((runtime flag: runtime allocFlag) and: [self allocate: m selector: sel class: cls argc: argc pc: pc act: a rcvSlot: r]) ifTrue: [^true].
	(cls = memory clsBlock and: [(runtime flag: runtime callsFlag) and: [(self primKindOf: (self methodPrimitive: m)) = OPK_CLOSURE]]) ifTrue: [
		^self blockCall: sel argc: argc pc: pc act: a rcvSlot: r].
	((runtime flag: runtime primsFlag) and: [self replace: m selector: sel class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r]) ifTrue: [^true].
	((self methodPrimitive: m) ~= 0 and: [(runtime flag: runtime primsFlag) and: [
		self inlinePrimitive: (self methodPrimitive: m) class: cls argc: argc pc: pc act: a rcvSlot: r]]) ifTrue: [^true].
	(self canInline: m act: a) ifTrue: [
		self inlineMethod: m receiverClass: cls pc: pc act: a rcvSlot: r argc: argc.
		^true].
	self call: m selector: sel argc: argc kind: kind pc: pc act: a rcvSlot: r.
	^true
!
call: m selector: sel argc: argc kind: kind pc: pc act: a rcvSlot: r
	"A send of sel that finds m; answer it."
	| n |
	n := self callSelector: sel argc: argc kind: (kind = 1 ifTrue: [1] ifFalse: [0]) special: 0 pc: pc act: a rcvSlot: r.
	((runtime flag: runtime callsFlag) and: [runtime codeAddressOf: m]) ifTrue: [
		"a direct call of its baseline code's unchecked entry: no lookup, its primitive's machine code first"
		(ir node: n) op: O_CALL.
		(ir node: n) tcls: m].
	^n
!
performedAt: i act: a argc: n class: cls method: m
	"m is perform:, perform:with:... (its primitive's) and slot i of a holds a constant selector of n arguments that cls understands: the selector, else 0."
	| nd |
	(obPerformAct < 0 and: [(brt primKindOf: (self methodPrimitive: m)) = brt pkPerform and: [(brt primOpOf: (self methodPrimitive: m)) = 0 and: [n >= 0 and: [n < 8]]]]) ifFalse: [^0 asUInt64].
	nd := ir node: (self read: (self var: a slot: i)).
	nd op asInt32 = O_CONST ifFalse: [^0 asUInt64].
	((interpreter selectorArgc: nd aux asUInt64) = n and: [(interpreter lookupMethod: cls selector: nd aux asUInt64) ~= 0]) ifFalse: [^0 asUInt64].
	^nd aux asUInt64
!
sendPerformed: sel to: rcv class: cls argc: n pc: pc act: a rcvSlot: r
	"The receiver (of class cls) performs constant selector sel with n arguments: a send of sel, its arguments a slot down over the selector; frame states at the perform: keep its slots (deoptimization executes it again), sends made for it say so (SI_PERFORMED: their selector goes back)."
	<function>
	0 to: n do: [:i | obPerformVals at: i put: (self read: (self var: a slot: r + 1 + i))].
	0 to: n - 1 do: [:i | self write: (self var: a slot: r + 1 + i) value: (obPerformVals at: i + 1)].
	obPerformAct := a.
	obPerformPc := pc.
	obPerformSlot := r + 1.
	obPerformCount := n + 1.
	self send: sel to: rcv class: cls argc: n kind: 0 pc: pc act: a rcvSlot: r.
	obPerformAct := -1.
	^true
!
blockCall: sel argc: argc pc: pc act: a rcvSlot: r
	"value, value: or value:value: of a BlockClosure: the send, with a fast path that calls the code the site called last (NF_BLOCKCALL)."
	| k n |
	k := -1.
	(self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: 21) = sel ifTrue: [k := 21].
	(self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: 22) = sel ifTrue: [k := 22].
	(self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: 30) = sel ifTrue: [k := 30].
	k < 0 ifTrue: [
		self callSelector: sel argc: argc kind: 0 special: 0 pc: pc act: a rcvSlot: r.
		^true].
	n := self callSelector: sel argc: argc kind: 2 special: k pc: pc act: a rcvSlot: r.
	(ir node: n) flags: ((ir node: n) flags bitOr: NF_BLOCKCALL).
	^true
!
allocate: m selector: sel class: cls argc: argc pc: pc act: a rcvSlot: r
	"m is basicNew or basicNew: and the receiver (of metaclass cls) a class whose instances have pointer slots, bytes or 32-bit words: the send with a fast path that allocates in eden (NF_ALLOC; c: format and fixed fields, F_BYTES or F_W32 for bytes and words); answer whether it is one."
	| kind inst fo spec isize fmt n |
	kind := self primKindOf: (self methodPrimitive: m).
	((kind = OPK_NEW and: [argc = 0]) or: [kind = OPK_NEWSIZE and: [argc = 1]]) ifFalse: [^false].
	"its send answered something else (the primitive failed): a send"
	((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback deoptOther) = 0 ifFalse: [^false].
	inst := self loadRef: cls at: META_THISCLASS.
	((self isPtr: inst) and: [(self classOf: inst) = cls]) ifFalse: [^false].
	fo := self loadRef: inst at: BEH_FORMAT.
	(self isInt: fo) ifFalse: [^false].
	spec := (self intVal: fo) >> CLS_SPEC_SHIFT.
	isize := (self intVal: fo) bitAnd: CLS_INSTSIZE_MASK.
	kind = OPK_NEW
		ifTrue: [
			spec <= 1 ifFalse: [^false].
			fmt := isize ~= 0 ifTrue: [F_FIXED] ifFalse: [F_EMPTY]]
		ifFalse: [
			((spec = 2 or: [spec = 3]) or: [(spec = F_BYTES or: [spec = F_W32]) and: [isize = 0]]) ifFalse: [^false].
			fmt := spec >= F_W32
				ifTrue: [spec asInt32]
				ifFalse: [(isize ~= 0 or: [spec = 3]) ifTrue: [F_FIXVAR] ifFalse: [F_VAR]]].
	n := self callSelector: sel argc: argc kind: 0 special: 0 pc: pc act: a rcvSlot: r.
	(ir node: n) flags: ((ir node: n) flags bitOr: NF_ALLOC).
	(ir node: n) c: (fmt bitOr: isize << 8) asInt32.
	(ir node: n) tkind: T_OBJ.
	(ir node: n) tcls: inst.
	^true
!
replace: m selector: sel class: cls argc: argc kind: kind pc: pc act: a rcvSlot: r
	"m is replaceFrom:to:with:startingAt: (its primitive's) and cls's instances bytes, 32-bit words or pointers without fixed fields: the call with a fast path that copies (NF_REPLACE, NF_W32, NF_PTRS); answer whether it is one."
	| fo spec fl n |
	((self primKindOf: (self methodPrimitive: m)) = OPK_REPLACE and: [argc = 4]) ifFalse: [^false].
	fo := self loadRef: cls at: BEH_FORMAT.
	(self isInt: fo) ifFalse: [^false].
	spec := (self intVal: fo) >> CLS_SPEC_SHIFT.
	((self intVal: fo) bitAnd: CLS_INSTSIZE_MASK) = 0 ifFalse: [^false].
	fl := 0.
	spec = F_VAR ifTrue: [fl := NF_REPLACE bitOr: NF_PTRS].
	spec = F_W32 ifTrue: [fl := NF_REPLACE bitOr: NF_W32].
	spec = F_BYTES ifTrue: [fl := NF_REPLACE].
	fl = 0 ifTrue: [^false].
	n := self call: m selector: sel argc: argc kind: kind pc: pc act: a rcvSlot: r.
	(ir node: n) flags: ((ir node: n) flags bitOr: fl).
	^true
!
primKindOf: p
	"What the optimizer knows primitive p to be (PK_*), 0 if nothing."
	obPrimsKnown ifFalse: [
		obPrimsKnown := true.
		libc memset: obPrimKinds value: 0 size: OPT_MAX_PRIM.
		self primNamed: 'at' kind: OPK_AT.
		self primNamed: 'atPut' kind: OPK_ATPUT.
		self primNamed: 'basicSize' kind: OPK_SIZE.
		self primNamed: 'stringAt' kind: OPK_STRINGAT.
		self primNamed: 'stringAtPut' kind: OPK_STRINGATPUT.
		self primNamed: 'class' kind: OPK_CLASS.
		self primNamed: 'identical' kind: OPK_IDENTICAL.
		self primNamed: 'intAdd' kind: OPK_INT + 0.
		self primNamed: 'intSub' kind: OPK_INT + 1.
		self primNamed: 'intLess' kind: OPK_INT + 2.
		self primNamed: 'intGreater' kind: OPK_INT + 3.
		self primNamed: 'intLessEq' kind: OPK_INT + 4.
		self primNamed: 'intGreaterEq' kind: OPK_INT + 5.
		self primNamed: 'intEq' kind: OPK_INT + 6.
		self primNamed: 'intNotEq' kind: OPK_INT + 7.
		self primNamed: 'intMul' kind: OPK_INT + 8.
		self primNamed: 'intBitAnd' kind: OPK_INT + 14.
		self primNamed: 'intBitOr' kind: OPK_INT + 15.
		self primNamed: 'intMod' kind: OPK_INT + 10.
		self primNamed: 'intBitXor' kind: OPK_INT + 11.
		self primNamed: 'intBitShift' kind: OPK_INT + 12.
		self primNamed: 'intFloorDiv' kind: OPK_INT + 13.
		self primNamed: 'intQuo' kind: OPK_INT + 16.
		self primNamed: 'intRem' kind: OPK_INT + 17.
		self primNamed: 'charValue' kind: OPK_CHARVALUE.
		self primNamed: 'charFromValue' kind: OPK_CHARFROM.
		self primNamed: 'floatAdd' kind: OPK_FLOAT + 0.
		self primNamed: 'floatSub' kind: OPK_FLOAT + 1.
		self primNamed: 'floatLess' kind: OPK_FLOAT + 2.
		self primNamed: 'floatGreater' kind: OPK_FLOAT + 3.
		self primNamed: 'floatLessEq' kind: OPK_FLOAT + 4.
		self primNamed: 'floatGreaterEq' kind: OPK_FLOAT + 5.
		self primNamed: 'floatEq' kind: OPK_FLOAT + 6.
		self primNamed: 'floatNotEq' kind: OPK_FLOAT + 7.
		self primNamed: 'floatMul' kind: OPK_FLOAT + 8.
		self primNamed: 'floatDiv' kind: OPK_FLOAT + 9.
		self primNamed: 'floatSqrt' kind: OPK_FSQRT.
		self primNamed: 'basicNew' kind: OPK_NEW.
		self primNamed: 'basicNew:' kind: OPK_NEWSIZE.
		self primNamed: 'closureValue' kind: OPK_CLOSURE.
		self primNamed: 'replaceFromToWithStartingAt' kind: OPK_REPLACE.
		self primNamed: 'stringHash' kind: OPK_STRHASH.
		self primNamed: 'stringCompare' kind: OPK_STRCMP].
	(p <= 0 or: [p >= OPT_MAX_PRIM]) ifTrue: [^0].
	^(obPrimKinds at: p) asInt32
!
stringPrimitive: kind spec: spec argc: argc pc: pc act: a rcvSlot: r
	"String>>hash (OPK_STRHASH) or compareWith: (OPK_STRCMP) of a receiver whose class has bytes (spec), as their primitives do it (they take any bytes): O_STRHASH, O_STRCMP; compareWith:'s argument known to be bytes, else, unless its class is known, checked (deoptimize, and the site calls from then on). Answer whether it did."
	| rcv x n s |
	spec >= F_BYTES ifFalse: [^false].
	rcv := self read: (self var: a slot: r).
	"the stub hashes by words of 8 bytes: an image hashed by FNV-1a calls the primitive"
	(kind = OPK_STRHASH and: [argc = 0 and: [memory wordHash]]) ifTrue: [
		n := self add: O_STRHASH rep: R_OOP.
		(ir node: n) a: rcv.
		(ir node: n) flags: NF_PURE.
		(ir node: n) tkind: T_SMI.
		(ir node: n) lo: 0.
		(ir node: n) hi: 16r3FFFFFFF.
		self push: n act: a depth: r.
		^true].
	(kind = OPK_STRCMP and: [argc = 1]) ifFalse: [^false].
	x := self read: (self var: a slot: r + 1).
	s := -1.
	(self hasBytes: (self knownClassOf: x)) ifFalse: [
		(self knownClassOf: x) ~= 0 ifTrue: [^false].
		((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback deoptOther) ~= 0 ifTrue: [^false].
		s := self stateAct: a pc: pc depth: (self depthAt: pc act: a)].
	n := self add: O_STRCMP rep: R_OOP.
	(ir node: n) a: rcv.
	(ir node: n) b: x.
	s >= 0
		ifTrue: [
			(ir node: n) state: s.
			(ir node: n) flags: NF_GUARD]
		ifFalse: [(ir node: n) flags: NF_PURE].
	(ir node: n) tkind: T_SMI.
	(ir node: n) lo: -1.
	(ir node: n) hi: 1.
	self push: n act: a depth: r.
	^true
!
hasBytes: cls
	"Instances of cls (0: not known) are bytes."
	cls = 0 ifTrue: [^false].
	(self isInt: (self loadRef: cls at: BEH_FORMAT)) ifFalse: [^false].
	^(self intVal: (self loadRef: cls at: BEH_FORMAT)) >> 16 >= F_BYTES
!
primNamed: name kind: k
	| p |
	p := runtime primitiveNumberNamed: name.
	(p > 0 and: [p < OPT_MAX_PRIM]) ifTrue: [obPrimKinds at: p put: k asUInt8]
!
inlinePrimitive: p class: cls argc: argc pc: pc act: a rcvSlot: r
	"The receiver (of class cls) is in a's slot r: inline primitive p if the optimizer knows it for cls (a failure deoptimizes to the send); answer whether it did."
	<function>
	<var: #p type: 'int64_t'>
	| kind fmt spec fixed ek rcv s n idx val fl |
	kind := self primKindOf: p.
	kind = 0 ifTrue: [^false].
	rcv := self read: (self var: a slot: r).
	(kind = OPK_CLASS and: [argc = 0]) ifTrue: [
		"of a value of a known class: a constant (cls may be where a super send looks)"
		(self knownClassOf: rcv) ~= 0 ifTrue: [
			self push: (self constant: (self knownClassOf: rcv)) act: a depth: r.
			^true].
		n := self add: O_CLASSOF rep: R_OOP.
		(ir node: n) a: rcv.
		self push: n act: a depth: r.
		^true].
	(kind = OPK_IDENTICAL and: [argc = 1]) ifTrue: [
		self push: (self compare: O_EQ a: rcv b: (self read: (self var: a slot: r + 1))) act: a depth: r.
		^true].
	(kind = OPK_CHARVALUE and: [argc = 0 and: [cls = memory clsChar]]) ifTrue: [
		n := self add: O_CHARCONV rep: R_OOP.
		(ir node: n) a: rcv.
		(ir node: n) tkind: T_SMI.
		self push: n act: a depth: r.
		^true].
	(kind = OPK_CHARFROM and: [argc = 1]) ifTrue: [
		"of a code point that is a constant: a constant"
		n := self liveValueOf: (self read: (self var: a slot: r + 1)).
		((ir node: n) op asInt32 = O_CONST and: [(self isInt: (ir node: n) aux asUInt64) and: [(self intVal: (ir node: n) aux asUInt64) between: 0 and: CHAR_VALUE_MAX]]) ifTrue: [
			self push: (self constant: ((self intVal: (ir node: n) aux asUInt64) asUInt64 << 3 bitOr: 2)) act: a depth: r.
			^true].
		s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
		idx := self guardInt: (self read: (self var: a slot: r + 1)) state: s.
		n := self add: O_CHARCONV rep: R_OOP.
		(ir node: n) a: idx.
		(ir node: n) aux: 1.
		(ir node: n) state: s.
		(ir node: n) flags: NF_GUARD.
		(ir node: n) tkind: T_CHAR.
		self push: n act: a depth: r.
		^true].
	(kind >= OPK_FLOAT or: [kind = OPK_FSQRT]) ifTrue: [
		(runtime flag: runtime unboxFlag) ifFalse: [^false].
		(cls = memory clsSmallfloat and: [((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: (feedback sawNonInt bitOr: feedback deoptOther)) = 0]) ifFalse: [^false].
		(kind = OPK_FSQRT and: [argc = 0]) ifTrue: [
			s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
			idx := self unboxFloat: rcv state: s.
			n := self add: O_FSQRT rep: R_DBL.
			(ir node: n) a: idx.
			self push: (self boxFloat: n state: s) act: a depth: r.
			^true].
		argc = 1 ifFalse: [^false].
		self floatArith: (kind - OPK_FLOAT) asInt32 x: rcv y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r.
		^true].
	(kind >= OPK_INT and: [argc = 1]) ifTrue: [
		cls = memory clsSmallint ifFalse: [^false].
		fl := feedback flagsAt: (ir act: a) method pc: pc.
		"the argument was not always a SmallInteger: Floats as doubles, else the send"
		(fl bitAnd: ((feedback sawFloat bitOr: feedback sawNonInt) bitOr: (feedback deoptArith bitOr: feedback overflowed))) ~= 0 ifTrue: [
			(kind - OPK_INT <= 9 and: [(runtime flag: runtime unboxFlag) and: [(fl bitAnd: feedback sawFloat) ~= 0 and: [(fl bitAnd: (feedback sawNonInt bitOr: feedback deoptOther)) = 0]]]) ifFalse: [^false].
			self floatArith: (kind - OPK_INT) asInt32 x: rcv y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r.
			^true].
		self intArith: kind - OPK_INT x: rcv y: (self read: (self var: a slot: r + 1)) pc: pc act: a rcvSlot: r.
		^true].
	fmt := self intVal: (self loadRef: cls at: BEH_FORMAT).
	spec := fmt >> 16.
	(kind = OPK_STRHASH or: [kind = OPK_STRCMP]) ifTrue: [^self stringPrimitive: kind spec: spec argc: argc pc: pc act: a rcvSlot: r].
	fixed := fmt bitAnd: CLS_INSTSIZE_MASK.
	ek := -1.
	(spec = F_VAR or: [spec = F_FIXVAR]) ifTrue: [ek := E_PTR].
	spec >= F_BYTES ifTrue: [
		ek := E_BYTE.
		fixed := 0].
	(kind = OPK_STRINGAT or: [kind = OPK_STRINGATPUT]) ifTrue: [
		spec >= F_BYTES ifFalse: [^false].
		ek := E_CHAR].
	ek < 0 ifTrue: [^false].
	((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback deoptOther) ~= 0 ifTrue: [^false].
	s := self stateAct: a pc: pc depth: (self depthAt: pc act: a).
	(kind = OPK_SIZE and: [argc = 0]) ifTrue: [
		n := self add: O_SIZE rep: R_OOP.
		(ir node: n) a: rcv.
		(ir node: n) aux: ek.
		(ir node: n) aux2: fixed.
		(ir node: n) tkind: T_SMI.
		self push: n act: a depth: r.
		^true].
	((kind = OPK_AT or: [kind = OPK_STRINGAT]) and: [argc = 1]) ifTrue: [
		idx := self guardInt: (self read: (self var: a slot: r + 1)) state: s.
		n := self add: O_INDEXLOAD rep: R_OOP.
		(ir node: n) a: rcv.
		(ir node: n) b: idx.
		(ir node: n) aux: ek.
		(ir node: n) aux2: fixed.
		(ir node: n) state: s.
		ek = E_BYTE ifTrue: [(ir node: n) tkind: T_SMI].
		ek = E_CHAR ifTrue: [(ir node: n) tkind: T_CHAR].
		self push: n act: a depth: r.
		^true].
	((kind = OPK_ATPUT or: [kind = OPK_STRINGATPUT]) and: [argc = 2]) ifTrue: [
		idx := self guardInt: (self read: (self var: a slot: r + 1)) state: s.
		val := self read: (self var: a slot: r + 2).
		n := self add: O_INDEXSTORE rep: R_NONE.
		(ir node: n) a: rcv.
		(ir node: n) b: idx.
		(ir node: n) c: val.
		(ir node: n) aux: ek.
		(ir node: n) aux2: fixed.
		(ir node: n) state: s.
		(ek = E_CHAR and: [(self knownClassOf: val) = 0]) ifTrue: [
			"stored: a Character below 256"
			val := self cast: val class: memory clsChar.
			(ir node: val) tkind: T_CHAR.
			(ir node: val) lo: 0.
			(ir node: val) hi: 255].
		self push: val act: a depth: r.
		^true].
	^false
!
knownClassOf: v
	"v's class if the IR knows it, else 0."
	| nd |
	nd := ir node: (self liveValueOf: v).
	nd op asInt32 = O_CONST ifTrue: [^self classOf: nd aux asUInt64].
	nd tkind asInt32 = T_SMI ifTrue: [^memory clsSmallint].
	nd tkind asInt32 = T_FLOAT ifTrue: [^memory clsSmallfloat].
	nd tkind asInt32 = T_NIL ifTrue: [^self classOf: memory nilOop].
	nd tkind asInt32 = T_CHAR ifTrue: [^memory clsChar].
	(nd tkind asInt32 = T_OBJ and: [nd tcls ~= 0]) ifTrue: [^nd tcls].
	^0
!
liveValueOf: v
	"v, or the one value phi v (of a block whose predecessors are all known) has from the predecessors that can run (the scan builds code past a constant condition's dead branch, whose value a merge's phi takes too)."
	<function>
	| r nd b o same depth |
	<var: #same type: 'int32_t'>
	r := ir resolve: v.
	depth := 0.
	[nd := ir node: r.
	 depth < 4 and: [nd op asInt32 = O_PHI and: [((ir block: nd block) flags bitAnd: BF_SEALED) ~= 0 and: [nd nargs asInt32 = (ir block: nd block) npreds]]]] whileTrue: [
		b := nd block.
		same := -1.
		0 to: nd nargs asInt32 - 1 do: [:i |
			(self cannotRun: (ir pred: i of: b)) ifFalse: [
				o := ir resolve: (ir operand: nd args + i).
				(o ~= r and: [o ~= same]) ifTrue: [
					same < 0 ifTrue: [same := o] ifFalse: [^r]]]].
		same < 0 ifTrue: [^r].
		r := same.
		depth := depth + 1].
	^r
!
cannotRun: b
	"b is not reachable (BF_LIVE) and, neither an entry nor a loop head (a backward jump may still come), never will be: all its predecessors are known (they come before it) and none is. Not in a loop's unit: the backward jump of a loop around its entry reaches the blocks before it."
	| bl |
	obOsrPc >= 0 ifTrue: [^false].
	bl := ir block: b.
	^(bl flags bitAnd: BF_LIVE) = 0 and: [b ~= obEntryBlock and: [(bl flags bitAnd: BF_LOOP) = 0]]
!
canInline: m act: a
	"m may be inlined into a: small, no primitive, only bytecodes the tier inlines, not too deep or recursive, within the budget."
	<function>
	| size bcs pc op depth p same |
	(self loadRef: m at: CM_PRIMITIVE) ~= (self intOop: 0) ifTrue: [^false].
	0 to: obNoInlineCount - 1 do: [:i | (obNoInline at: i) = m ifTrue: [^false]].
	size := self methodSize: m.
	size > OPT_INLINE_SIZE ifTrue: [^false].
	obInlined + size > OPT_INLINE_BUDGET ifTrue: [^false].
	depth := 0.
	same := 0.
	p := a.
	[p >= 0] whileTrue: [
		depth := depth + 1.
		(ir act: p) method = m ifTrue: [same := same + 1].
		p := (ir act: p) parent].
	(depth >= OPT_INLINE_DEPTH or: [same > 1]) ifTrue: [^false].
	(self analysisOf: m) < 0 ifTrue: [^false].
	bcs := self methodBytecodes: m.
	pc := 0.
	[pc < size] whileTrue: [
		op := bcs at: pc.
		(op = 16r76 or: [op = 16r88 or: [(op = 16r81 and: [(bcs at: pc + 1) <= CTX_STACKP]) or: [((runtime flag: runtime blocksFlag) not and: [op = 16r7C or: [op = 16r8F or: [op >= 16r8A and: [op <= 16r8C]]]])]]]) ifTrue: [^false].
		pc := pc + (analysis lengthOf: op)].
	^true
!
inlineMethod: m receiverClass: cls pc: pc act: a rcvSlot: r argc: argc
	"Build m's activation in place of the send at a's pc: its arguments are a's slots after the receiver; its returns go to a block where a continues with the result."
	<function>
	| b ac entry ret |
	b := self newActFor: m.
	b < 0 ifTrue: [^self bail].
	obInlined := obInlined + (self methodSize: m).
	ac := ir act: b.
	ac parent: a.
	ac sendPc: pc.
	ac sendArgc: argc.
	ac receiver: (self read: (self var: a slot: r)).
	ac rcvClass: cls.
	0 to: argc - 1 do: [:i | self writeArg: (self var: b slot: i) value: (self read: (self var: a slot: r + 1 + i))].
	argc to: argc + ac numTemps - 1 do: [:i | self write: (self var: b slot: i) value: (self constant: memory nilOop)].
	entry := ir newBlock.
	(ir block: entry) act: b.
	ret := ir newBlock.
	(ir block: ret) act: a.
	(ir act: b) retBlock: ret.
	self goto: entry.
	obCurBlock := entry.
	self seal: entry.
	self buildAct: b.
	ir origin: a pc: pc.
	self seal: ret.
	(ir block: ret) npreds = 0 ifTrue: [
		obCurBlock := -1.
		^self].
	obCurBlock := ret.
	self write: (self var: a slot: r) value: (self read: (ir act: b) retVar)
!
guard: v class: cls state: s
	"v, deoptimizing unless its class is cls."
	| n |
	cls = memory clsSmallint ifTrue: [^self guardInt: v state: s].
	n := self add: O_GUARDCLASS rep: R_OOP.
	(ir node: n) a: v.
	(ir node: n) aux: cls asInt64.
	(ir node: n) state: s.
	(ir node: n) flags: NF_GUARD.
	self type: n class: cls.
	^n
!
guard: v startpc: sp method: m state: s
	"Closure v, deoptimizing unless its startpc is sp and its outerContext's method m."
	| n |
	n := self add: O_GUARDCLOSURE rep: R_OOP.
	(ir node: n) a: v.
	(ir node: n) b: (self constant: m).
	(ir node: n) aux: sp.
	(ir node: n) state: s.
	(ir node: n) flags: NF_GUARD.
	self type: n class: memory clsBlock.
	^n
!
cast: v class: cls
	"v, known to be of class cls (a type switch tested it)."
	| n |
	n := self add: O_CAST rep: R_OOP.
	(ir node: n) a: v.
	self type: n class: cls.
	^n
!
type: n class: cls
	cls = memory clsSmallfloat ifTrue: [^(ir node: n) tkind: T_FLOAT].
	cls = memory clsSmallint
		ifTrue: [(ir node: n) tkind: T_SMI]
		ifFalse: [
			(ir node: n) tkind: T_OBJ.
			(ir node: n) tcls: cls]
!
branch: v true: t false: f
	"End the current block with a branch on Boolean v (known to be one)."
	| n |
	n := self add: O_BRANCH rep: R_NONE.
	(ir node: n) a: v.
	(ir block: obCurBlock) succ0: t.
	(ir block: obCurBlock) succ1: f.
	self edgeTo: t.
	self edgeTo: f.
	obCurBlock := -1
!
deoptAct: a state: s
	"End the current block: deoptimize."
	| n |
	n := self add: O_DEOPT rep: R_NONE.
	(ir node: n) state: s.
	obCurBlock := -1
!
global: assoc pc: pc act: a depth: d
	"The value of the literal variable assoc pushed at a's pc: a class it holds now is a constant, guarded (it changed: deoptimize to the push, where it is loaded from then on), else loaded."
	| v c n |
	v := self loadField: ASSOC_VALUE of: (self constant: assoc).
	c := self loadRef: assoc at: ASSOC_VALUE.
	((self isBehavior: c) and: [((feedback flagsAt: (ir act: a) method pc: pc) bitAnd: feedback deoptOther) = 0]) ifFalse: [^v].
	n := self add: O_GUARDEQ rep: R_NONE.
	(ir node: n) a: v.
	(ir node: n) b: (self constant: c).
	(ir node: n) state: (self stateAct: a pc: pc depth: d).
	(ir node: n) flags: NF_GUARD.
	^self constant: c
!
isBehavior: o
	"o is a class or a metaclass: its class's class is Metaclass (Metaclass class's class is Metaclass)."
	| m |
	(self isPtr: o) ifFalse: [^false].
	m := self rawClass: (self rawClass: o).
	^m = (self rawClass: (self rawClass: m))
!
noteDependency: sel
	"The code depends on what sel finds (inlined or speculated): a method change for sel invalidates it."
	0 to: obDepCount - 1 do: [:i | (obDeps at: i) = sel ifTrue: [^self]].
	obDepCount < OPT_MAX_DEPS ifTrue: [
		obDeps at: obDepCount put: sel.
		obDepCount := obDepCount + 1]
!
depCount
	^obDepCount
!
depAt: i
	^obDeps at: i
!
callSelector: sel argc: argc kind: kind special: k pc: pc act: a rcvSlot: r
	"A send (an inline cache, OptCodegen>>emitSend:): the result replaces the receiver."
	| n args |
	(libc getenv: 'SAMALTAK_OPT_TRACE') notNull ifTrue: [
		libc fprintf: libc stderr format: 'opt: call at pc %d of act %d: ' with: pc with: a.
		interpreter printSymbol: sel on: libc stderr.
		libc fputc: 10 to: libc stderr].
	n := self add: O_SEND rep: R_OOP.
	obSafeEpoch := obSafeEpoch + 1.
	args := ir allocOperands: argc + 1.
	0 to: argc do: [:i | ir operand: args + i put: (self read: (self var: a slot: r + i))].
	(ir node: n) args: args.
	(ir node: n) nargs: (argc + 1) asUInt16.
	(ir node: n) aux: sel asInt64.
	(ir node: n) aux2: (((argc asInt64 bitOr: kind asInt64 << 8) bitOr: k asInt64 << 16) bitOr: pc asInt64 << 32).
	(a = obPerformAct and: [pc = obPerformPc]) ifTrue: [(ir node: n) aux2: ((ir node: n) aux2 bitOr: SI_PERFORMED)].
	"its temps as at the send: deoptimization before it executes the instruction again (a superinstruction reads its temps)"
	(ir node: n) state: (self stateAct: a pc: (pc + (analysis lengthOf: (self byteAt: pc act: a))) asInt32 depth: r livePc: pc).
	self push: n act: a depth: r.
	^n
! !
