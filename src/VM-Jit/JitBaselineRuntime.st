VMCoreModule subclass: #JitBaselineRuntime
	instanceVariableNames: 'compiler stubs cache asm analysis feedback oopSlots oopSlotCount youngSlots youngSlotCount youngSlotsOverflow megaTable blockTable primKinds primOps primKindsReady nilScanned nilInline nilFound statMisses statLinks statPics statMegas statBlockMisses statPrimCalls statWalks'
	classVariableNames: 'BL_BLOCK_CACHE BL_BLOCK_WORDS BL_MAX_OOP_SLOTS BL_MAX_YOUNG_SLOTS BL_MEGA_CACHE BL_MEGA_WORDS BL_PIC_CASES BL_SITE_MEGA PK_AT PK_AT_PUT PK_BASIC_SIZE PK_BASICNEW PK_BASICNEW_SIZE PK_CHAR_FROM_VALUE PK_CHAR_VALUE PK_CLASS PK_CLOSURE_VALUE PK_FLOAT_OP PK_HASH PK_IDENTICAL PK_INT_OP PK_MARKER PK_NONE PK_PERFORM PK_REPLACE PK_STRING_AT PK_STRING_AT_PUT PK_STRING_COMPARE PK_UINT32_AT PK_UINT32_AT_PUT'
	package: 'VM-Jit'!

JitBaselineRuntime comment: 'What baseline code (JitBaselineCompiler) needs of the runtime beyond JitRuntime:

Lazy frames: a frame suspended in a send has a stale pc and sp; the return address in its callee''s native frame record (the record of frame f is at baseRecord - 16 (f - baseFrame) / 64) says where it is (the return map: return offset, pc, depth, argc, length, pushes). canonicalizeBelow: makes them canonical, from the top down, stopping at a frame that already is (the prologue zeroes pc and sp; a suspended frame''s pc is never 0). Optimized frames are lazy the same way, with optimized code''s return map (return offset, safepoint, argc).

Inline caches (baseline code''s, and optimized code''s, which has the same sites): miss:receiver:ret: (the miss stub: unlinked sites, a callee''s failed class check, polymorphic and megamorphic misses) looks the send up, compiles the target when its activations reach the threshold, links the site (monomorphic: the class in the site''s literal, bl to the target''s checked entry; then a BaselinePic of up to BL_PIC_CASES classes; then megamorphic: the selector in the literal, bl to the megamorphic stub, which probes megaTable, two-way sets by the addresses of class and selector) and answers the target''s unchecked entry. Young classes and methods are cached too: a young object written into the code makes its word a young root. unlinkAll (method dictionaries changed, become) and unlinkSelector: reset sites. A site''s state is its type feedback: unlinked, monomorphic (class, target), polymorphic (the BaselinePic''s classes and targets), megamorphic. The perform methods'' machine code probes megaTable too (class, selector; the fourth word: the selector''s argument count); performMiss:receiver:ret:info: fills it.

The collector: the words in the code that hold objects (the method''s literals, the caches'' classes) are registered (oopSlots, the young ones also in youngSlots) and updated as roots; megaTable and blockTable (home method, startpc -> block entry) are cleared by every GC and become.

Type feedback: feedbackSitesOf: and friends enumerate a method''s send sites (pc, selector, state, cases with receiver class and target method), which jitSendSites answers to the image. Under --jit opt every miss of baseline code reports its receiver class to JitFeedback, and redirect:to: makes a method''s unchecked entry branch to its optimized code.

Also: block:closure:ret: (the block stub''s miss), entrySlow:ret:callee: (a callee''s stack check: interrupts, a full C stack), prim:ret:fn:info:fp: (a compiled method''s C primitive), returnSlow: (a married frame or frame 0 returns). A callee entered by perform: has its arguments one slot down, over the selector: its sender''s send cannot be executed again, so what runs before its frame exists takes the sender as past the send (setTop:ret:fp:argc:).'!

!JitBaselineRuntime class methodsFor: 'declaring'!
declarations
	^#((compiler JitBaselineCompiler) (stubs JitStubs) (cache CodeCache) (asm JitAssembler) (analysis BytecodeAnalysis) (feedback JitFeedback)
		(oopSlots 'uint64_t[BL_MAX_OOP_SLOTS]') (oopSlotCount int64_t) (youngSlots 'uint64_t[BL_MAX_YOUNG_SLOTS]') (youngSlotCount int64_t) (youngSlotsOverflow bool)
		(megaTable 'uint64_t[BL_MEGA_WORDS]') (blockTable 'uint64_t[BL_BLOCK_WORDS]')
		(primKinds 'uint8_t[1024]') (primOps 'uint8_t[1024]') (primKindsReady bool) (nilScanned bool) (nilInline bool) (nilFound int32_t)
		(statMisses uint64_t) (statLinks uint64_t) (statPics uint64_t) (statMegas uint64_t) (statBlockMisses uint64_t) (statPrimCalls uint64_t) (statWalks uint64_t))
!
initialize
	BL_MAX_OOP_SLOTS := 262144.
	BL_MAX_YOUNG_SLOTS := 16384.
	BL_MEGA_CACHE := 4096.
	BL_MEGA_WORDS := 4 * 4096.
	BL_BLOCK_CACHE := 1024.
	BL_BLOCK_WORDS := 4 * 1024.
	BL_PIC_CASES := 6.
	BL_SITE_MEGA := 16r40000000.
	PK_NONE := 0.
	PK_PERFORM := 1.
	PK_MARKER := 2.
	PK_BASICNEW := 3.
	PK_BASICNEW_SIZE := 4.
	PK_IDENTICAL := 5.
	PK_CLASS := 6.
	PK_CLOSURE_VALUE := 7.
	"SmallInteger and Float primitives in machine code; primOps: 0 + 1 - 2 * 3 / 4 bitAnd: 5 bitOr: 6 bitXor: 7 bitShift: 8 < 9 > 10 <= 11 >= 12 = 13 ~= 14 sqrt 15 truncated 16 quo: 17 rem: 18 // 19 \\"
	PK_INT_OP := 8.
	PK_FLOAT_OP := 9.
	PK_CHAR_VALUE := 10.
	PK_HASH := 11.
	PK_CHAR_FROM_VALUE := 12.
	"at:, at:put:, basicSize, uint32At:, uint32At:put: of indexable pointers without fixed fields, 32-bit words, bytes"
	PK_AT := 13.
	PK_AT_PUT := 14.
	PK_BASIC_SIZE := 15.
	PK_UINT32_AT := 16.
	PK_UINT32_AT_PUT := 17.
	PK_STRING_COMPARE := 18.
	"at: and at:put: of Strings (bytes, 32-bit words): Characters"
	PK_STRING_AT := 19.
	PK_STRING_AT_PUT := 20.
	"replaceFrom:to:with:startingAt: of bytes, 32-bit words, indexable pointers without fixed fields"
	PK_REPLACE := 21
! !

!JitBaselineRuntime methodsFor: 'accessing'!
picCases
	^BL_PIC_CASES
!
megaMask
	"The megamorphic cache's sets: two entries of 4 words each (class, selector, target, argument count)."
	^(BL_MEGA_CACHE >> 1) - 1
!
blockMask
	^BL_BLOCK_CACHE - 1
!
pkPerform
	^PK_PERFORM
!
pkMarker
	^PK_MARKER
!
pkBasicNew
	^PK_BASICNEW
!
pkBasicNewSize
	^PK_BASICNEW_SIZE
!
pkIdentical
	^PK_IDENTICAL
!
pkClass
	^PK_CLASS
!
pkClosureValue
	^PK_CLOSURE_VALUE
!
pkIntOp
	^PK_INT_OP
!
pkFloatOp
	^PK_FLOAT_OP
!
pkCharValue
	^PK_CHAR_VALUE
!
pkCharFromValue
	^PK_CHAR_FROM_VALUE
!
pkAt
	^PK_AT
!
pkAtPut
	^PK_AT_PUT
!
pkBasicSize
	^PK_BASIC_SIZE
!
pkUint32At
	^PK_UINT32_AT
!
pkUint32AtPut
	^PK_UINT32_AT_PUT
!
pkStringCompare
	^PK_STRING_COMPARE
!
pkStringAt
	^PK_STRING_AT
!
pkStringAtPut
	^PK_STRING_AT_PUT
!
pkHash
	^PK_HASH
!
pkReplace
	^PK_REPLACE
!
blockInstSize
	"Slots of a BlockClosure."
	^(self intVal: (self loadRef: memory clsBlock at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK
!
refresh
	"After a GC: the caches' addresses for machine code."
	jit state megaCache: (self cCoerce: megaTable to: 'uint64_t').
	jit state blockCache: (self cCoerce: blockTable to: 'uint64_t')
! !

!JitBaselineRuntime methodsFor: 'functions for the stubs'!
missFunction
	^self cCoerce: (self functionPointer: #miss:receiver:ret:) to: 'uint64_t'
!
blockFunction
	^self cCoerce: (self functionPointer: #block:closure:ret:) to: 'uint64_t'
!
performFunction
	^self cCoerce: (self functionPointer: #performMiss:receiver:ret:info:) to: 'uint64_t'
!
entrySlowFunction
	^self cCoerce: (self functionPointer: #entrySlow:ret:callee:) to: 'uint64_t'
!
primFunction
	^self cCoerce: (self functionPointer: #prim:fp:fn:info:) to: 'uint64_t'
!
leafPrimFunction
	^self cCoerce: (self functionPointer: #leafPrim:fn:argc:) to: 'uint64_t'
!
returnSlowFunction
	^self cCoerce: (self functionPointer: #returnSlow:) to: 'uint64_t'
!
boxFunction
	^self cCoerce: (self functionPointer: #box:bits:) to: 'uint64_t'
! !

!JitBaselineRuntime methodsFor: 'primitives'!
initPrimKinds
	| t e k op |
	primKindsReady := true.
	0 to: 1023 do: [:i |
		primKinds at: i put: PK_MARKER.
		primOps at: i put: 0].
	t := self primitiveTable.
	0 to: self primitiveCount - 1 do: [:i |
		e := t + i.
		(e number > 0 and: [e number < 1024]) ifTrue: [
			k := PK_NONE.
			op := 0.
			(self named: e name is: 'perform') ifTrue: [k := PK_PERFORM].
			(self named: e name is: 'performWithArguments') ifTrue: [k := PK_PERFORM. op := 1].
			(self named: e name is: 'basicNew') ifTrue: [k := PK_BASICNEW].
			(self named: e name is: 'basicNew:') ifTrue: [k := PK_BASICNEW_SIZE].
			(self named: e name is: 'identical') ifTrue: [k := PK_IDENTICAL].
			(self named: e name is: 'class') ifTrue: [k := PK_CLASS].
			(self named: e name is: 'closureValue') ifTrue: [k := PK_CLOSURE_VALUE].
			(self named: e name is: 'closureValueWithArguments') ifTrue: [k := PK_CLOSURE_VALUE. op := 1].
			(self named: e name is: 'charValue') ifTrue: [k := PK_CHAR_VALUE].
			(self named: e name is: 'charFromValue') ifTrue: [k := PK_CHAR_FROM_VALUE].
			(self named: e name is: 'at') ifTrue: [k := PK_AT].
			(self named: e name is: 'atPut') ifTrue: [k := PK_AT_PUT].
			(self named: e name is: 'basicSize') ifTrue: [k := PK_BASIC_SIZE].
			(self named: e name is: 'bytesUint32At') ifTrue: [k := PK_UINT32_AT].
			(self named: e name is: 'bytesUint32AtPut') ifTrue: [k := PK_UINT32_AT_PUT].
			(self named: e name is: 'stringCompare') ifTrue: [k := PK_STRING_COMPARE].
			(self named: e name is: 'stringAt') ifTrue: [k := PK_STRING_AT].
			(self named: e name is: 'stringAtPut') ifTrue: [k := PK_STRING_AT_PUT].
			(self named: e name is: 'identityHash') ifTrue: [k := PK_HASH].
			(self named: e name is: 'replaceFromToWithStartingAt') ifTrue: [k := PK_REPLACE].
			(self named: e name is: 'intAdd') ifTrue: [k := PK_INT_OP. op := 0].
			(self named: e name is: 'intSub') ifTrue: [k := PK_INT_OP. op := 1].
			(self named: e name is: 'intMul') ifTrue: [k := PK_INT_OP. op := 2].
			(self named: e name is: 'intBitAnd') ifTrue: [k := PK_INT_OP. op := 4].
			(self named: e name is: 'intBitOr') ifTrue: [k := PK_INT_OP. op := 5].
			(self named: e name is: 'intBitXor') ifTrue: [k := PK_INT_OP. op := 6].
			(self named: e name is: 'intBitShift') ifTrue: [k := PK_INT_OP. op := 7].
			(self named: e name is: 'intQuo') ifTrue: [k := PK_INT_OP. op := 16].
			(self named: e name is: 'intRem') ifTrue: [k := PK_INT_OP. op := 17].
			(self named: e name is: 'intFloorDiv') ifTrue: [k := PK_INT_OP. op := 18].
			(self named: e name is: 'intMod') ifTrue: [k := PK_INT_OP. op := 19].
			(self named: e name is: 'intLess') ifTrue: [k := PK_INT_OP. op := 8].
			(self named: e name is: 'intGreater') ifTrue: [k := PK_INT_OP. op := 9].
			(self named: e name is: 'intLessEq') ifTrue: [k := PK_INT_OP. op := 10].
			(self named: e name is: 'intGreaterEq') ifTrue: [k := PK_INT_OP. op := 11].
			(self named: e name is: 'intEq') ifTrue: [k := PK_INT_OP. op := 12].
			(self named: e name is: 'intNotEq') ifTrue: [k := PK_INT_OP. op := 13].
			(self named: e name is: 'floatAdd') ifTrue: [k := PK_FLOAT_OP. op := 0].
			(self named: e name is: 'floatSub') ifTrue: [k := PK_FLOAT_OP. op := 1].
			(self named: e name is: 'floatMul') ifTrue: [k := PK_FLOAT_OP. op := 2].
			(self named: e name is: 'floatDiv') ifTrue: [k := PK_FLOAT_OP. op := 3].
			(self named: e name is: 'floatLess') ifTrue: [k := PK_FLOAT_OP. op := 8].
			(self named: e name is: 'floatGreater') ifTrue: [k := PK_FLOAT_OP. op := 9].
			(self named: e name is: 'floatLessEq') ifTrue: [k := PK_FLOAT_OP. op := 10].
			(self named: e name is: 'floatGreaterEq') ifTrue: [k := PK_FLOAT_OP. op := 11].
			(self named: e name is: 'floatEq') ifTrue: [k := PK_FLOAT_OP. op := 12].
			(self named: e name is: 'floatNotEq') ifTrue: [k := PK_FLOAT_OP. op := 13].
			(self named: e name is: 'floatSqrt') ifTrue: [k := PK_FLOAT_OP. op := 14].
			(self named: e name is: 'floatTruncated') ifTrue: [k := PK_FLOAT_OP. op := 15].
			(e number = PRIM_ENSURE_MARKER or: [e number = PRIM_ONDO_MARKER]) ifTrue: [k := PK_MARKER].
			primKinds at: e number put: k asUInt8.
			primOps at: e number put: op asUInt8]]
!
named: s is: name
	^(libc strcmp: s with: name) = 0
!
primKindOf: p
	"How compiled code runs primitive p (PK_MARKER: not at all, the method's body runs)."
	<function>
	primKindsReady ifFalse: [self initPrimKinds].
	(p <= 0 or: [p >= 1024]) ifTrue: [^PK_MARKER].
	^(primKinds at: p) asInt32
!
primOpOf: p
	"The operation of a PK_INT_OP or PK_FLOAT_OP primitive (see initialize); 1: PK_PERFORM's perform:withArguments:, PK_CLOSURE_VALUE's valueWithArguments:."
	<function>
	(p <= 0 or: [p >= 1024]) ifTrue: [^0].
	^(primOps at: p) asInt32
!
primFunctionOf: p
	^self cCoerce: (primitives lookup: p) to: 'uint64_t'
!
isLeafPrimitive: p
	^primitives isLeaf: p
! !

!JitBaselineRuntime methodsFor: 'nil tests'!
nilTestOf: sel
	"1 if sel is #isNil, 2 if #notNil, else 0."
	<function>
	| n |
	((self isPtr: sel) and: [(self rawClass: sel) = jit state byteSymbolClass]) ifFalse: [^0].
	n := memory byteSize: sel.
	(n = 5 and: [(libc memcmp: (self bytesOf: sel) with: 'isNil' size: 5) = 0]) ifTrue: [^1].
	(n = 6 and: [(libc memcmp: (self bytesOf: sel) with: 'notNil' size: 6) = 0]) ifTrue: [^2].
	^0
!
nilTestsInlinable
	"isNil and notNil may be compiled as comparisons with nil: on the heap, the only methods so named are UndefinedObject's and ProtoObject's quick ones (checked once, again after flushMethodCache; a new definition drops all code)."
	<function>
	nilScanned ifFalse: [
		nilScanned := true.
		nilInline := true.
		nilFound := 0.
		gc walkOldSpace: (self functionPointer: #noteNilTest:data:) data: self null.
		gc walkYoungSpace: (self functionPointer: #noteNilTest:data:) data: self null.
		nilFound = 15 ifFalse: [nilInline := false]].
	^nilInline
!
noteNilTest: m data: d
	"m, if a method isNil or notNil, keeps nil tests inlinable only if it is UndefinedObject's or ProtoObject's quick one (nilFound: which of the four were seen)."
	<function>
	| k cls bc root quick |
	(nilInline and: [(self rawClass: m) = (memory special: SO_COMPILEDMETHOD)]) ifFalse: [^self].
	k := self nilTestOf: (self loadRef: m at: CM_SELECTOR).
	k = 0 ifTrue: [^self].
	cls := self loadRef: m at: CM_CLASS.
	root := self rawClass: memory nilOop.
	[(self loadRef: root at: BEH_SUPERCLASS) ~= memory nilOop] whileTrue: [root := self loadRef: root at: BEH_SUPERCLASS].
	(cls = (self rawClass: memory nilOop) or: [cls = root]) ifFalse: [
		nilInline := false.
		^self].
	"^true (16r71) or ^false (16r72), then returnTop"
	quick := ((k = 1) = (cls ~= root)) ifTrue: [16r71] ifFalse: [16r72].
	bc := self loadRef: m at: CM_BYTECODES.
	((self isPtr: bc) and: [(memory formatOf: bc) >= F_BYTES and: [(memory byteSize: bc) = 2 and: [((self bytesOf: bc) at: 0) = quick and: [((self bytesOf: bc) at: 1) = 16r79]]]]) ifFalse: [
		nilInline := false.
		^self].
	nilFound := (nilFound bitOr: 1 << ((k - 1) * 2 + (cls = root ifTrue: [1] ifFalse: [0]))) asInt32
!
nilTestsChanged: sel
	"Method dictionaries changed (sel 0: all of them, scanned again): a definition of isNil or notNil ends their inlining; if code inlined them, it all goes."
	<function>
	| was |
	was := nilScanned and: [nilInline].
	sel = 0
		ifTrue: [
			was ifFalse: [^self].
			nilScanned := false.
			self nilTestsInlinable ifTrue: [^self]]
		ifFalse: [
			(self nilTestOf: sel) = 0 ifTrue: [^self].
			nilScanned := true.
			nilInline := false.
			was ifFalse: [^self]].
	jit dropAllCode
! !

!JitBaselineRuntime methodsFor: 'lazy frames'!
retIndexOf: h at: ret
	"The return map entry of return address ret in h's code, -1 if none."
	<function>
	| off lo hi mid v |
	off := (ret - h codeStart) asUInt32.
	lo := 0.
	hi := h retCount asInt64 - 1.
	[lo <= hi] whileTrue: [
		mid := (lo + hi) quo: 2.
		v := h rets at: 3 * mid.
		v = off ifTrue: [^mid].
		v < off ifTrue: [lo := mid + 1] ifFalse: [hi := mid - 1]].
	^-1
!
retEntry: ret of: f
	| h i |
	(jit isCode: f code) ifFalse: [self fatal: 'baseline: a frame without code in machine code'].
	h := self cCoerce: f code to: 'JitMethod *'.
	i := self retIndexOf: h at: ret.
	i < 0 ifTrue: [self fatal: 'baseline: no return map entry for %p' with: (self ptr: ret)].
	^h rets + (3 * i)
!
setTop: f ret: ret mode: mode
	"f (the top frame) is in the send whose return address is ret: mode 0 at the send (the interpreter would execute it again), 1 in its primitive (arguments still on the stack, pc after it). Optimized code: at the call's safepoint, its receiver and arguments on the stack (OptRuntime decodes either from there)."
	<function>
	| e pc d info h |
	e := self retEntry: ret of: f.
	h := self cCoerce: f code to: 'JitMethod *'.
	h mode = jit optMode ifTrue: [
		f pc: (h bcSize + (e at: 1)) asInt32.
		f sp: (h slots + (e at: 2) + 1) asInt32.
		^self].
	pc := ((e at: 1) bitAnd: 16rFFFF) asInt32.
	d := ((e at: 1) >> 16) asInt32.
	info := e at: 2.
	mode = 0
		ifTrue: [
			f pc: pc.
			f sp: d]
		ifFalse: [
			f pc: pc + ((info >> 8) bitAnd: 255) asInt32.
			f sp: d + ((info >> 26) bitAnd: 3) asInt32]
!
setTop: f ret: ret fp: fp argc: n
	"f (the top frame) is past the send whose return address is ret: its callee's receiver below fp, n arguments from fp (perform: moved them down over its selector), as the interpreter has them while the callee's primitive runs or when its frame is pushed."
	self setTop: f ret: ret mode: 1.
	f sp: ((self cCoerce: fp to: 'oop *') - f fp + n) asInt32
!
calleeFp: f ret: ret
	"The fp of the callee of f's send at ret (f at the send: setTop:ret:mode: 0; a superinstruction's operands are not pushed yet)."
	| info |
	info := (self retEntry: ret of: f) at: 2.
	^f fp + (f sp + ((info >> 26) bitAnd: 3) asInt32 - (info bitAnd: 255) asInt32)
!
canonicalizeBelow: f
	"The frames below f (the top) that machine code suspended in calls get their method, pc, sp, ip and lits from the return addresses in their callees' records: baseline code's return map, or optimized code's (the call's safepoint: pc bcSize + its index, sp its slots)."
	<function>
	| base g h rec ret e pc sp info |
	base := self cCoerce: jit state baseFrame to: 'Frame *'.
	g := f - 1.
	statWalks := statWalks + 1.
	[g >= base] whileTrue: [
		asm isX64
			ifTrue: [
				"x86: the record is the return address call pushed"
				rec := jit state baseRecord - (8 * ((g + 1) - base)) asUInt64.
				ret := self uint64At: rec]
			ifFalse: [
				rec := jit state baseRecord - (16 * ((g + 1) - base)) asUInt64.
				ret := self uint64At: rec + 8].
		e := self retEntry: ret of: g.
		h := self cCoerce: g code to: 'JitMethod *'.
		h mode = jit optMode
			ifTrue: [
				pc := (h bcSize + (e at: 1)) asInt32.
				sp := h slots asInt32]
			ifFalse: [
				info := e at: 2.
				pc := ((e at: 1) bitAnd: 16rFFFF) asInt32 + ((info >> 8) bitAnd: 255) asInt32.
				sp := ((e at: 1) >> 16) asInt32 + ((info >> 26) bitAnd: 3) asInt32 - (info bitAnd: 255) asInt32 - 1].
		(g pc = pc and: [g sp = sp]) ifTrue: [^self].
		"optimized code killed meanwhile keeps the method its frames had"
		h method ~= memory nilOop ifTrue: [g method: h method].
		g pc: pc.
		g sp: sp.
		g ip: (interpreter methodBcs: g method) + pc.
		g lits: (self slotsOf: (self literalsOf: g method)).
		g := g - 1]
! !

!JitBaselineRuntime methodsFor: 'inline caches'!
siteOf: h at: ret
	"The send site whose call returns to ret."
	| off lo hi mid v |
	off := (ret - 4 - h codeStart) asUInt32.
	lo := 0.
	hi := h siteCount asInt64 - 1.
	[lo <= hi] whileTrue: [
		mid := (lo + hi) quo: 2.
		v := (h sites + mid) bl.
		v = off ifTrue: [^h sites + mid].
		v < off ifTrue: [lo := mid + 1] ifFalse: [hi := mid - 1]].
	^self null
!
selectorOf: s in: h
	| info i |
	"optimized code: depth is the selector's index in its pool"
	h mode = jit optMode ifTrue: [^self uint64At: h codeStart + h poolOffset + (8 * s depth) asUInt64].
	info := s info.
	i := (info >> 16) bitAnd: 255.
	((info >> 24) bitAnd: 3) = 2 ifTrue: [^self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: i].
	^self loadRef: (self literalsOf: h method) at: i
!
miss: f receiver: rcv ret: ret
	"A send at f's site ret found no target (unlinked, a class check failed, no case of the polymorphic or megamorphic cache): look it up, link the site, answer the target's unchecked entry (1: leave, the interpreter sends). Optimized code's sites link the same way; where baseline code would leave, the runtime sends (OptRuntime>>sendFrom:ret:)."
	<function>
	<var: #f type: 'Frame *'>
	<var: #rcv type: 'oop'>
	<var: #ret type: 'uint64_t'>
	<returns: 'uint64_t'>
	| h s kind sel cls t opt fl r |
	statMisses := statMisses + 1.
	h := self cCoerce: f code to: 'JitMethod *'.
	self setTop: f ret: ret mode: 0.
	jit sync: f.
	s := self siteOf: h at: ret.
	s isNull ifTrue: [self fatal: 'baseline: no send site for %p' with: (self ptr: ret)].
	opt := h mode = jit optMode.
	kind := (s info >> 24) bitAnd: 3.
	r := rcv.
	(gc forwardersExist and: [memory isForwarder: r]) ifTrue: [
		"a forwarder (becomeForward:) misses every class check: the send goes to its target (the stub reloads the receiver from its slot)"
		r := memory follow: r.
		opt
			ifTrue: [(f fp + h slots asInt64) at: 0 put: r]
			ifFalse: [(self calleeFp: f ret: ret) at: -1 put: r]].
	"an optimized super send: the runtime finds its class (the method it is in may be inlined)"
	(opt and: [kind = 1]) ifTrue: [^jit optSendFrom: f ret: ret].
	sel := self selectorOf: s in: h.
	cls := kind = 1
		ifTrue: [self loadRef: (self loadRef: h method at: CM_CLASS) at: BEH_SUPERCLASS]
		ifFalse: [interpreter receiverClass: r].
	"--jit opt: what the site saw is type feedback"
	(jit tiering and: [kind ~= 1 and: [opt not]]) ifTrue: [
		feedback noteSend: h method pc: s pc asInt64 class: cls.
		"a SmallInteger sent arithmetic that has an inline SmallInteger path: the path did not apply"
		(kind = 2 and: [cls = memory clsSmallint and: [compiler inlinesIntegers: ((s info >> 16) bitAnd: 255) asInt32]]) ifTrue: [
			fl := feedback flagsOf: ((self calleeFp: f ret: ret) at: 0).
			feedback noteFlags: h method pc: s pc asInt64 flags: (fl = 0 ifTrue: [feedback overflowed] ifFalse: [fl])]].
	t := self targetFor: cls selector: sel.
	t isNull ifTrue: [^opt ifTrue: [jit optSendFrom: f ret: ret] ifFalse: [1]].
	"a forwarder's site keeps its cases: the target's class may be one of them already"
	(jit ic and: [r = rcv]) ifTrue: [self link: s in: h class: cls selector: sel target: t super: kind = 1].
	^t uentry
!
targetFor: cls selector: sel
	"The baseline code a send of sel to an instance of cls may call, compiled when the method's activations reach the threshold; null if there is none or the interpreter sends it (doesNotUnderstand:)."
	<function>
	| e m t |
	e := interpreter entryFor: cls selector: sel.
	e isNull ifTrue: [^self null].
	m := e method.
	t := jit codeOf: m counting: true.
	(jit hasCode: t) ifFalse: [^self null].
	t mode = jit optMode ifTrue: [t := self cCoerce: t lower to: 'JitMethod *'].
	t mode = jit baselineMode ifFalse: [^self null].
	^t
!
patchCall: site to: target
	compiler patchBranchAt: site to: target.
	cache invalidate: site size: 4
!
redirect: h to: o
	"--jit opt: the callers of h's unchecked entry go to o, its method's optimized code (a b to the frame code at its start), or (o = h) to h's own code again."
	<function>
	| a |
	(jit tiering and: [h mode = jit baselineMode and: [(h flags bitAnd: jit entryFlag) ~= 0]]) ifFalse: [^self].
	(o ~= h and: [o blockStart ~= 0 or: [o osrPc ~= 0]]) ifTrue: [^self].
	a := h uentry.
	cache beginWriting.
	asm isX64 ifTrue: [
		self redirectX64: h at: a to: o.
		^cache endWriting].
	o = h
		ifTrue: [
			h entryWord ~= 0 ifTrue: [
				self uint32At: a put: h entryWord.
				h entryWord: 0]]
		ifFalse: [
			h entryWord = 0 ifTrue: [h entryWord: (self uint32At: a)].
			self uint32At: a put: (16r14000000 bitOr: ((o codeStart asInt64 - a asInt64) >> 2 bitAnd: 16r3FFFFFF)) asUInt32].
	cache invalidate: a size: 4.
	cache endWriting
!
redirectX64: h at: a to: o
	"x86: a jmp rel32 over the first 5 bytes of the unchecked entry, whose first instruction is the stack check's cmp rbx, [rip + limit] (16r48, then the 4 bytes entryWord saves)."
	<arch: #x86_64>
	o = h
		ifTrue: [
			h entryWord ~= 0 ifTrue: [
				self uint32At: a + 1 put: h entryWord.
				self uint8At: a put: 16r48.
				h entryWord: 0]]
		ifFalse: [
			h entryWord = 0 ifTrue: [h entryWord: (self uint32At: a + 1)].
			self uint32At: a + 1 put: (o codeStart asInt64 - (a + 5) asInt64) asUInt32.
			self uint8At: a put: 16rE9].
	cache invalidate: a size: 5
!
link: s in: h class: cls selector: sel target: t super: isSuper
	"Link site s for cls: unlinked -> monomorphic -> polymorphic -> megamorphic."
	| site lit p |
	site := h codeStart + s bl.
	lit := h codeStart + s lit.
	cache beginWriting.
	isSuper
		ifTrue: [
			s target: (self cCoerce: t to: 'uint64_t').
			self patchCall: site to: t uentry]
		ifFalse: [
			(s info bitAnd: BL_SITE_MEGA) ~= 0
				ifTrue: [self megaFill: cls selector: sel target: t]
				ifFalse: [
					s target = 0
						ifTrue: [
							statLinks := statLinks + 1.
							self setSlot: lit to: cls.
							s target: (self cCoerce: t to: 'uint64_t').
							self patchCall: site to: t entry]
						ifFalse: [
							p := s pic.
							(p = 0 and: [jit pic]) ifTrue: [
								p := self newPicFor: site class: (self uint64At: lit) target: (self cCoerce: s target to: 'JitMethod *').
								p ~= 0 ifTrue: [
									statPics := statPics + 1.
									s pic: p.
									self patchCall: site to: p + compiler picCodeOffset]].
							(p ~= 0 and: [self addCaseTo: p class: cls target: t]) ifFalse: [
								self goMega: s site: site lit: lit selector: sel.
								self megaFill: cls selector: sel target: t]]]].
	cache endWriting
!
goMega: s site: site lit: lit selector: sel
	statMegas := statMegas + 1.
	s info: (s info bitOr: BL_SITE_MEGA).
	self setSlot: lit to: sel.
	self patchCall: site to: (jit mega ifTrue: [stubs blMegaStub] ifFalse: [stubs blMissStub])
!
megaFill: cls selector: sel target: t
	"Two-way: the set of (class, selector) holds the two pairs used last, so two hot pairs whose addresses meet in a set do not evict each other; a new pair goes first, the first moves second. The fourth word, for the perform methods' machine code: sel's argument count, -1 if t is a perform method (the interpreter does perform: of perform:)."
	| i |
	i := ((((cls bitXor: sel) >> 3) bitAnd: self megaMask) * 8) asInt64.
	(megaTable at: i) = 0 ifFalse: [
		0 to: 3 do: [:k | megaTable at: i + 4 + k put: (megaTable at: i + k)]].
	megaTable at: i put: cls.
	megaTable at: i + 1 put: sel.
	megaTable at: i + 2 put: t uentry.
	megaTable at: i + 3 put: ((self isPerform: t) ifTrue: [-1] ifFalse: [(interpreter selectorArgc: sel) asInt64]) asUInt64
!
isPerform: t
	^(self primKindOf: ((interpreter methodPrim: t method) bitAnd: CM_PRIM_MASK) asInt32) = PK_PERFORM
!
newPicFor: site class: c0 target: t0
	"A polymorphic inline cache whose first case is c0 (to t0); 0 if the code cache or the slot registry is full."
	<function>
	| p pic |
	oopSlotCount + BL_PIC_CASES > BL_MAX_OOP_SLOTS ifTrue: [^0].
	p := cache allocate: compiler picBytes asUInt64.
	p = 0 ifTrue: [
		jit requestFlush.
		^0].
	pic := self cCoerce: p to: 'BaselinePic *'.
	libc memset: pic value: 0 size: (self sizeof: 'BaselinePic').
	pic site: site.
	(compiler emitPicAt: p) ifFalse: [^0].
	cache invalidate: p size: compiler picBytes asUInt64.
	jit perfMapAt: p size: compiler picBytes asUInt64 name: 'pic'.
	0 to: BL_PIC_CASES - 1 do: [:i | self registerSlot: (self cCoerce: (pic fieldAddress: #classes) to: 'uint64_t') + (8 * i) asUInt64].
	(self addCaseTo: p class: c0 target: t0) ifFalse: [^0].
	^p
!
addCaseTo: p class: c target: t
	"Case count of pic p: c goes to t's unchecked entry; false if it is full."
	| pic n |
	pic := self cCoerce: p to: 'BaselinePic *'.
	n := pic count.
	n >= BL_PIC_CASES ifTrue: [^false].
	self setSlot: (self cCoerce: (pic fieldAddress: #classes) to: 'uint64_t') + (8 * n) asUInt64 to: c.
	self uint64At: (self cCoerce: (pic fieldAddress: #targets) to: 'uint64_t') + (8 * n) asUInt64 put: (self cCoerce: t to: 'uint64_t').
	pic count: n + 1.
	self patchCall: p + (compiler picBranchOffset: n asInt32) to: t uentry.
	^true
!
unlinkSite: s in: h
	| site |
	site := h codeStart + s bl.
	self uint64At: h codeStart + s lit put: 0.
	s target: 0.
	s pic: 0.
	s info: (s info bitClear: BL_SITE_MEGA).
	self patchCall: site to: stubs blMissStub
!
unlinkAll
	"Method dictionaries changed or objects were become: every site unlinked, the caches cleared."
	<function>
	self unlinkSelector: 0
!
unlinkSelector: sel
	"The sites sending sel (0: all), baseline code's and optimized code's, unlinked, the caches cleared."
	<function>
	| h |
	self clearCaches.
	jit tableCount = 0 ifTrue: [^self].
	cache beginWriting.
	0 to: jit tableSize - 1 do: [:i |
		h := jit headerAt: i.
		(h notNull and: [h mode = jit baselineMode]) ifTrue: [self unlinkSitesOf: h selector: sel]].
	0 to: jit optHeaderCount - 1 do: [:i | self unlinkSitesOf: (jit optHeaderAt: i) selector: sel].
	cache endWriting
!
unlinkSitesOf: h selector: sel
	| s |
	(h flags bitAnd: 3) = 0 ifFalse: [^self].
	0 to: h siteCount asInt64 - 1 do: [:k |
		s := h sites + k.
		(s target ~= 0 or: [(s info bitAnd: BL_SITE_MEGA) ~= 0]) ifTrue: [
			(sel = 0 or: [(self selectorOf: s in: h) = sel]) ifTrue: [self unlinkSite: s in: h]]]
!
clearCaches
	libc memset: megaTable value: 0 size: 8 * BL_MEGA_WORDS.
	libc memset: blockTable value: 0 size: 8 * BL_BLOCK_WORDS
!
release
	"All code was dropped (flushed): give back the pages of the code's object slots (none is in use now)."
	<function>
	gc releasePages: oopSlots size: 8 * BL_MAX_OOP_SLOTS.
	gc releasePages: youngSlots size: 8 * BL_MAX_YOUNG_SLOTS
! !

!JitBaselineRuntime methodsFor: 'type feedback'!
headerOf: m
	"m's baseline code, null if it has none."
	<function>
	| h |
	h := jit lookup: m.
	((jit hasCode: h) and: [h mode = jit baselineMode]) ifFalse: [^self null].
	^h
!
feedbackSitesOf: m
	"How many send sites m's baseline code has (in code order, the order of their pcs within straight-line code); -1 if it has no baseline code."
	<function>
	| h |
	h := self headerOf: m.
	h isNull ifTrue: [^-1].
	^h siteCount asInt64
!
feedbackPcOf: m site: i
	"The bytecode pc of send site i."
	<function>
	^((self headerOf: m) sites + i) pc asInt64
!
feedbackSelectorOf: m site: i
	<function>
	| h |
	h := self headerOf: m.
	^self selectorOf: h sites + i in: h
!
feedbackStateOf: m site: i
	"0 unlinked, 1 monomorphic, 2 polymorphic, 3 megamorphic."
	<function>
	<returns: 'int64_t'>
	| s |
	s := (self headerOf: m) sites + i.
	(s info bitAnd: BL_SITE_MEGA) ~= 0 ifTrue: [^3].
	s pic ~= 0 ifTrue: [^2].
	^s target ~= 0 ifTrue: [1] ifFalse: [0]
!
feedbackCasesOf: m site: i
	"The receiver classes site i's caches hold (a megamorphic site: those of the polymorphic cache it had); a super send has one case without a class."
	<function>
	| s |
	s := (self headerOf: m) sites + i.
	s pic ~= 0 ifTrue: [^(self cCoerce: s pic to: 'BaselinePic *') count asInt64].
	(s target ~= 0 and: [(s info bitAnd: BL_SITE_MEGA) = 0]) ifTrue: [^1].
	^0
!
feedbackClassOf: m site: i case: j
	"Case j's receiver class (nil for a super send)."
	<function>
	| h s |
	h := self headerOf: m.
	s := h sites + i.
	s pic ~= 0 ifTrue: [^self uint64At: (self cCoerce: ((self cCoerce: s pic to: 'BaselinePic *') fieldAddress: #classes) to: 'uint64_t') + (8 * j) asUInt64].
	((s info >> 24) bitAnd: 3) = 1 ifTrue: [^memory nilOop].
	^self uint64At: h codeStart + s lit
!
feedbackTargetOf: m site: i case: j
	"Case j's method."
	<function>
	| s |
	s := (self headerOf: m) sites + i.
	s pic ~= 0 ifTrue: [^(self cCoerce: (self uint64At: (self cCoerce: ((self cCoerce: s pic to: 'BaselinePic *') fieldAddress: #targets) to: 'uint64_t') + (8 * j) asUInt64) to: 'JitMethod *') method].
	^(self cCoerce: s target to: 'JitMethod *') method
! !

!JitBaselineRuntime methodsFor: 'called by machine code'!
block: f closure: c ret: ret
	"The block stub found no entry for closure c (its argument count checked; f past the send, the arguments in the callee's slots: valueWithArguments: has put them there): its home method's code, compiled if need be, and the block's entry, its optimized unit's if it has one; none: the block's frame pushed, 1 (leave: the interpreter runs it)."
	<function>
	<var: #f type: 'Frame *'>
	<var: #c type: 'oop'>
	<var: #ret type: 'uint64_t'>
	<returns: 'uint64_t'>
	| m startpc entry i n |
	statBlockMisses := statBlockMisses + 1.
	n := (self intVal: (self loadRef: c at: BC_NUMARGS)) asInt32.
	self setTop: f ret: ret mode: 0.
	self setTop: f ret: ret fp: (self calleeFp: f ret: ret) argc: n.
	jit sync: f.
	entry := self entryOfBlock: c.
	entry = 0 ifTrue: [
		interpreter activateBlock: n.
		^1].
	jit blocks ifTrue: [
		m := self loadRef: (self loadRef: c at: BC_OUTER) at: CTX_METHOD.
		startpc := self loadRef: c at: BC_STARTPC.
		i := ((((startpc bitXor: m >> 3)) bitAnd: BL_BLOCK_CACHE - 1) * 4) asInt64.
		blockTable at: i put: m.
		blockTable at: i + 1 put: startpc.
		blockTable at: i + 2 put: entry].
	^entry
!
entryOfBlock: c
	"Where closure c's code starts: its block's optimized unit (--jit opt), else the block's entry in its home method's baseline code, compiled if need be; 0 if none."
	| ctx m h startpc entry |
	ctx := self loadRef: c at: BC_OUTER.
	((self isPtr: ctx) and: [ctx ~= memory nilOop]) ifFalse: [^0 asUInt64].
	m := self loadRef: ctx at: CTX_METHOD.
	startpc := self loadRef: c at: BC_STARTPC.
	h := jit lookup: m.
	h isNull ifTrue: [h := jit compileAndInstall: m].
	((jit hasCode: h) and: [h mode = jit baselineMode]) ifFalse: [^0 asUInt64].
	entry := jit optUnitEntryOf: m start: (self intVal: startpc).
	entry ~= 0 ifTrue: [^entry].
	0 to: h blockCount asInt64 - 1 do: [:k |
		(self intOop: (h blocks at: 2 * k) asInt64) = startpc ifTrue: [entry := h codeStart + (h blocks at: 2 * k + 1)]].
	^entry
!
performMiss: f receiver: rcv ret: ret info: info
	"A perform method's machine code (info: its argument count n, | 256 for perform:withArguments:) found no target in megaTable for rcv's class and the selector: look it up, fill the table, move the arguments down over the selector (perform:withArguments:: the Array's elements) and answer the target's unchecked entry; 0: the primitive fails (the method's body runs); 1: leave, the interpreter sends (not understood, not compiled yet, perform: again, no room; a sender in optimized code: the runtime sends, OptRuntime>>sendFrom:ret:)."
	<function>
	<var: #f type: 'Frame *'>
	<var: #rcv type: 'oop'>
	<var: #ret type: 'uint64_t'>
	<var: #info type: 'uint64_t'>
	<returns: 'uint64_t'>
	| n fp sel arr k cls t |
	statMisses := statMisses + 1.
	n := (info bitAnd: 255) asInt32.
	self setTop: f ret: ret mode: 0.
	jit sync: f.
	fp := self calleeFp: f ret: ret.
	(self unlikely: gc forwardersExist) ifTrue: [
		"the selector and the Array are checked here, not by the C primitive's retry"
		fp at: 0 put: (memory follow: (fp at: 0)).
		(info bitAnd: 256) ~= 0 ifTrue: [fp at: 1 put: (memory follow: (fp at: 1))]].
	sel := fp at: 0.
	k := n - 1.
	(info bitAnd: 256) ~= 0 ifTrue: [
		arr := fp at: 1.
		k := ((self isPtr: arr) and: [(self rawClass: arr) = memory clsArray]) ifTrue: [(self numSlots: arr) asInt32] ifFalse: [-1]].
	(k < 0 or: [(interpreter selectorArgc: sel) ~= k]) ifTrue: [^0].
	cls := interpreter receiverClass: rcv.
	t := self targetFor: cls selector: sel.
	(t isNull or: [(self isPerform: t) or: [(self cCoerce: fp to: 'uint64_t') >= jit state stackLimitNormal or: [(self married: f lacksRoomAt: fp argc: k)]]]) ifTrue: [
		^(jit isOptFrame: f) ifTrue: [jit optSendFrom: f ret: ret] ifFalse: [1]].
	jit ic ifTrue: [self megaFill: cls selector: sel target: t].
	(info bitAnd: 256) ~= 0
		ifTrue: [0 to: k - 1 do: [:i | fp at: i put: (self loadRef: arr at: i)]]
		ifFalse: [libc memmove: fp from: fp + 1 size: k asUInt64 * 8].
	^t uentry
!
married: f lacksRoomAt: fp argc: k
	"f is married and not optimized, and its Context would not hold its slots up to k arguments from fp (a C primitive's, as prim:fp:fn:info: has them; materializeAll copies them into it)."
	<var: #f type: 'Frame *'>
	^f ctx ~= memory nilOop and: [(jit isOptFrame: f) not and: [(self cCoerce: fp to: 'oop *') - f fp + k > ((self numSlots: f ctx) asInt64 - CTX_FIXED)]]
!
entrySlow: f ret: ret callee: c
	"A callee's stack check failed (f is its sender, at the send; c the callee's header, 1 at a block's entry): the C stack is full (the frames become Contexts and the interpreter sends again; a sender in optimized code: the runtime sends, answer where the call continues) or an interrupt is pending: taken with the callee's frame pushed, as at its first instruction (perform: may have moved the arguments: the send cannot be executed again), the frame popped again if no frames were flushed. 0: retry, 1: leave."
	<function>
	<var: #f type: 'Frame *'>
	<var: #ret type: 'uint64_t'>
	<var: #c type: 'uint64_t'>
	<returns: 'uint64_t'>
	| nfp n h g moved inv |
	self setTop: f ret: ret mode: 0.
	jit sync: f.
	nfp := self calleeFp: f ret: ret.
	(self cCoerce: nfp to: 'uint64_t') >= jit state stackLimitNormal ifTrue: [
		(jit isOptFrame: f) ifTrue: [^jit optSendFrom: f ret: ret].
		interpreter materializeAll.
		^1].
	h := self cCoerce: c to: 'JitMethod *'.
	n := (self intVal: (c = 1 ifTrue: [self loadRef: (nfp at: -1) at: BC_NUMARGS] ifFalse: [self loadRef: h method at: CM_NUMARGS])) asInt32.
	self setTop: f ret: ret fp: nfp argc: n.
	interpreter syncFrame: f.
	moved := interpreter frameEpoch.
	inv := jit invalidations.
	c = 1
		ifTrue: [interpreter activateBlock: n]
		ifFalse: [
			g := interpreter pushFrame: h method argc: n code: c ecode: -1.
			g isNull ifTrue: [self fatal: 'baseline: no room for a frame below the stack limit'].
			(((interpreter methodPrim: h method) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0 and: [(self loadRef: h method at: CM_NUMTEMPS) ~= (self intOop: 0)]) ifTrue: [
				"a failed primitive's error code into the first temp, as the frame's code puts it"
				g fp at: n put: jit state ecode asUInt64]].
	jit resetStress.
	jit clearInterrupt.
	interpreter entrySafepoint.
	(interpreter frameEpoch ~= moved or: [inv ~= jit invalidations]) ifTrue: [^1].
	c = 1 ifTrue: [nfp at: -1 put: (interpreter frames + (interpreter nframes - 1)) closure].
	interpreter nframes: (f - interpreter frames) asInt32 + 1.
	^0
!
prim: f fp: fp fn: fn info: info
	"A compiled method's C primitive (f the sender, at the send whose return address is the state's primRet; the receiver below fp): 0 success (the result in the state), 1 leave, 2 failure (the error code in the state)."
	<function>
	<var: #f type: 'Frame *'>
	<var: #fp type: 'uint64_t'>
	<var: #fn type: 'uint64_t'>
	<var: #info type: 'uint64_t'>
	<returns: 'uint64_t'>
	| n leaf base moved inv status v code |
	statPrimCalls := statPrimCalls + 1.
	n := (info bitAnd: 255) asInt32.
	leaf := (info bitAnd: 256) ~= 0.
	base := (self cCoerce: fp to: 'oop *') - 1.
	leaf ifFalse: [
		self setTop: f ret: jit state primRet fp: fp argc: n.
		jit sync: f].
	moved := interpreter frameEpoch.
	inv := jit invalidations.
	status := interpreter callPrimitive: (self cCoerce: fn to: 'prim_fn') base: base argc: n.
	status = PS_OK ifTrue: [
		v := interpreter primResult.
		interpreter primResult: memory nilOop.
		interpreter frameEpoch ~= moved ifTrue: [
			interpreter primCommit: v.
			^1].
		inv ~= jit invalidations ifTrue: [
			base at: 0 put: v.
			(jit isOptFrame: f) ifTrue: [^jit leaveAfter: f pc: f pc sp: f sp].
			f sp: f sp - n.
			jit sync: f.
			^1].
		jit state result: v.
		^0].
	"the primitive committed its result (a process primitive that did not switch): machine code goes on with it; invalidated baseline code leaves (the interpreter continues its frame), optimized code cannot"
	(status = PS_SWITCHED and: [interpreter frameEpoch = moved and: [interpreter nframes = ((f - interpreter frames) + 1) and: [inv = jit invalidations or: [jit isOptFrame: f]]]]) ifTrue: [
		inv ~= jit invalidations ifTrue: [^jit leaveAfter: f pc: f pc sp: f sp].
		jit state result: (base at: 0).
		^0].
	status = PS_FAIL ifTrue: [
		code := interpreter primErrorCode.
		jit state ecode: (((info bitAnd: 512) ~= 0 and: [code >= 0]) ifTrue: [self intOop: code asInt64] ifFalse: [memory nilOop]) asInt64.
		^2].
	status = PS_RESEND ifTrue: [self fatal: 'a resending primitive called from baseline code'].
	^1
!
leafPrim: fp fn: fn argc: n
	"A compiled method's <leaf> C primitive, called directly by its machine code (the receiver below fp, n arguments from fp; nothing canonical: a leaf primitive neither allocates, collects, switches processes, looks at Contexts nor invalidates code): its result, or 0 (no oop) if it failed, the error code then in the state."
	<function>
	<var: #fp type: 'uint64_t'>
	<var: #fn type: 'uint64_t'>
	<var: #n type: 'uint64_t'>
	<returns: 'uint64_t'>
	| status v code |
	statPrimCalls := statPrimCalls + 1.
	status := interpreter callLeafPrimitive: (self cCoerce: fn to: 'prim_fn') base: (self cCoerce: fp to: 'oop *') - 1 argc: n asInt32.
	(self likely: status = PS_OK) ifTrue: [
		v := interpreter primResult.
		interpreter primResult: memory nilOop.
		^v].
	status = PS_FAIL ifFalse: [self fatal: 'a leaf primitive neither answered nor failed'].
	code := interpreter primErrorCode.
	jit state ecode: (code >= 0 ifTrue: [self intOop: code asInt64] ifFalse: [memory nilOop]) asInt64.
	^0
!
box: f bits: b
	"A Float (IEEE bits b) that is not a SmallFloat64 (f's pc and sp stored): a BoxedFloat64, which may collect."
	<function>
	<var: #f type: 'Frame *'>
	<var: #b type: 'uint64_t'>
	<returns: 'oop'>
	jit sync: f.
	^memory floatOop: (self doubleFromBits: b)
!
returnSlow: f
	"f returns but is married or frame 0 (pc and sp stored): widow it, or leave for the interpreter to return into the Context below."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	jit sync: f.
	f = interpreter frames ifTrue: [^1].
	f ctx ~= memory nilOop ifTrue: [interpreter widow: f].
	^0
! !

!JitBaselineRuntime methodsFor: 'collector'!
setSlot: a to: v
	"Store v into the registered word at a; a young v makes it a young root."
	<function>
	self uint64At: a put: v.
	((self isPtr: v) and: [self isYoung: v]) ifTrue: [self noteYoungSlot: a]
!
noteYoungSlot: a
	"Once: scavenges update the word at a."
	youngSlotsOverflow ifTrue: [^self].
	0 to: youngSlotCount - 1 do: [:i | (youngSlots at: i) = a ifTrue: [^self]].
	youngSlotCount < BL_MAX_YOUNG_SLOTS
		ifTrue: [
			youngSlots at: youngSlotCount put: a.
			youngSlotCount := youngSlotCount + 1]
		ifFalse: [youngSlotsOverflow := true]
!
canRegister: n
	^oopSlotCount + n <= BL_MAX_OOP_SLOTS
!
registerSlot: a
	"The word at a in the code holds an object: the collector updates it."
	<function>
	| v |
	oopSlotCount >= BL_MAX_OOP_SLOTS ifTrue: [self fatal: 'baseline: too many object references in code'].
	oopSlots at: oopSlotCount put: a.
	oopSlotCount := oopSlotCount + 1.
	v := self uint64At: a.
	((self isPtr: v) and: [v ~= 0 and: [self isYoung: v]]) ifTrue: [self noteYoungSlot: a]
!
youngRoots: fn
	"Scavenges (writing enabled): the code's young objects."
	<function>
	youngSlotsOverflow ifTrue: [^self allRoots: fn].
	0 to: youngSlotCount - 1 do: [:i | fn call: (self cCoerce: (youngSlots at: i) to: 'oop *')]
!
allRoots: fn
	"Full GCs and become (writing enabled): every object in the code; the caches keyed by objects are cleared."
	<function>
	0 to: oopSlotCount - 1 do: [:i | fn call: (self cCoerce: (oopSlots at: i) to: 'oop *')].
	self clearCaches
!
afterGC
	"Forget slots whose objects are old now; the caches keyed by objects are cleared (young ones moved)."
	<function>
	| n v |
	self clearCaches.
	youngSlotsOverflow ifTrue: [
		youngSlotsOverflow := false.
		youngSlotCount := 0.
		0 to: oopSlotCount - 1 do: [:i |
			v := self uint64At: (oopSlots at: i).
			((self isPtr: v) and: [v ~= 0 and: [self isYoung: v]]) ifTrue: [
				youngSlotCount < BL_MAX_YOUNG_SLOTS
					ifTrue: [
						youngSlots at: youngSlotCount put: (oopSlots at: i).
						youngSlotCount := youngSlotCount + 1]
					ifFalse: [youngSlotsOverflow := true]]].
		^self].
	n := 0.
	0 to: youngSlotCount - 1 do: [:i |
		v := self uint64At: (youngSlots at: i).
		((self isPtr: v) and: [v ~= 0 and: [self isYoung: v]]) ifTrue: [
			youngSlots at: n put: (youngSlots at: i).
			n := n + 1]].
	youngSlotCount := n
!
forgetSlotsFrom: address
	"The code from address on is dropped: its words are not the collector's business any more."
	<function>
	| n |
	n := 0.
	0 to: oopSlotCount - 1 do: [:i | (oopSlots at: i) < address ifTrue: [
		oopSlots at: n put: (oopSlots at: i).
		n := n + 1]].
	oopSlotCount := n.
	n := 0.
	0 to: youngSlotCount - 1 do: [:i | (youngSlots at: i) < address ifTrue: [
		youngSlots at: n put: (youngSlots at: i).
		n := n + 1]].
	youngSlotCount := n
!
flushed
	"The code cache was flushed."
	<function>
	oopSlotCount := 0.
	youngSlotCount := 0.
	youngSlotsOverflow := false.
	self clearCaches
! !

!JitBaselineRuntime methodsFor: 'statistics'!
statMisses
	^statMisses
!
statLinks
	^statLinks
!
statPics
	^statPics
!
statMegas
	^statMegas
!
statBlockMisses
	^statBlockMisses
!
statPrimCalls
	^statPrimCalls
!
statWalks
	^statWalks
! !

VMStruct subclass: #BaselineSite
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

BaselineSite comment: 'A send site of baseline code (in its JitMethod''s table, by offset): the bl''s offset, its literal''s (class, or selector once megamorphic), info (argc | instruction length << 8 | selector << 16 | kind << 24 (0 literal, 1 super, 2 special) | operands pushed by a superinstruction << 26 | 1 << 30 megamorphic), the pc and depth of the send, the target''s JitMethod (0: unlinked), its BaselinePic (0: none).'!

!BaselineSite class methodsFor: 'declaring'!
fields
	^#((bl uint32_t) (lit uint32_t) (info uint32_t) (pc uint16_t) (depth uint16_t) (target uint64_t) (pic uint64_t))
! !

VMStruct subclass: #BaselinePic
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

BaselinePic comment: 'A polymorphic inline cache: its site (the bl''s address), the cases in use, their classes and targets (JitMethods); its code follows (JitBaselineCompiler>>emitPicAt:).'!

!BaselinePic class methodsFor: 'declaring'!
fields
	^#((site uint64_t) (count uint32_t) (pad uint32_t) (classes 'oop[6]') (targets 'uint64_t[6]'))
! !
