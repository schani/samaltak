VMCoreModule subclass: #Interpreter
	instanceVariableNames: 'activeCtx tmpRoots primStatus primErrorCode primNargs primBase primBaseIndex primResult resendSelector resendArgc cstack frames nframes cstackUsed tagClass stackLimit stackCheckAt stackCheckDue stackCheckHash safepointAtEntry statMaterialized statFlushes frameEpoch cache icache specialArgc ip sp fp lits fr sel cls argc result epoch newMethod newBcs newLits newTemps newFsize newEcode newFp newCode'
	classVariableNames: 'CACHE_SIZE CSTACK_SLOTS ICACHE_SIZE MAX_FRAMES'
	package: 'VM-Core'!

Interpreter class instanceVariableNames: 'handlers'!

Interpreter comment: 'The bytecode interpreter: dispatch, sends, returns, stack frames, method caches, primitive plumbing.

Activations live in frames on a C stack (cstack: arguments, temps and operand stacks of all frames, contiguous; frames: one Frame per activation) above a heap Context, the base (activeCtx). A frame gets a Context lazily, by marriage (marry:): creating a closure in it, thisContext, reading the sender of the Context above it, the primitives that find handler and unwind contexts, a non-local return that must send. A married Context''s sender is its frame''s index; its pc, stackp, temps and stack stay in the frame and the VM answers Smalltalk from there (contextField:of:, contextSlot:of:, context:slot:put: for the bytecodes 0x81 and 0x88 and the object primitives; senderOf:marker:upTo: and terminate:to: for the context primitives). Outer temp access goes to the frame, and when the frame returns or is unwound its Context becomes a dead Context holding its final slots. Every frame is flushed into a Context (sender chain intact, married ones reusing theirs) only where Contexts must stand on their own: process switch, snapshot, stack overflow, a store that may change how a married Context continues, Smalltalk looking into an optimized frame. Execution then continues in the top Context. With no frames (nframes = 0) the interpreter executes activeCtx itself; a send pushes a frame.

interpret is one C function: the bytecode handlers (<bytecode:>) and the labels of the send and return paths (<label>) are labels in it, ip, sp, fp, lits and fr its locals (registers). In the simulator the handlers are methods and a goto is a call.'!

!Interpreter class methodsFor: 'declaring'!
declarations
	^#((activeCtx oop) (tmpRoots 'oop[4]')
		(primStatus int32_t) (primErrorCode int32_t) (primNargs int32_t) (primBase 'oop *') (primBaseIndex int64_t)
		(primResult oop) (resendSelector oop) (resendArgc int32_t)
		(cstack 'oop[CSTACK_SLOTS]') (frames 'Frame[MAX_FRAMES]') (nframes int32_t) (cstackUsed size_t)
		(tagClass 'oop[8]')
		(stackLimit int64_t 1000000) (stackCheckAt uint64_t) (stackCheckDue bool) (stackCheckHash uint32_t) (safepointAtEntry bool)
		(statMaterialized uint64_t) (statFlushes uint64_t) (frameEpoch uint64_t)
		(cache 'CacheEntry[CACHE_SIZE]') (icache 'CacheEntry[ICACHE_SIZE]')
		(specialArgc 'int32_t[32]')
		(ip 'uint8_t *') (sp 'oop *') (fp 'oop *') (lits 'oop *') (fr 'Frame *') (sel oop) (cls oop) (argc int32_t) (result oop) (epoch uint64_t)
		(newMethod oop) (newBcs 'uint8_t *') (newLits 'oop *') (newTemps int32_t) (newFsize int32_t) (newEcode int32_t) (newFp 'oop *') (newCode uint64_t))
!
registers
	^#(ip sp fp lits fr sel cls argc result epoch newMethod newBcs newLits newTemps newFsize newEcode newFp newCode)
!
typedefs
	^#((prim_fn 'void (*)(void)'))
!
initialize
	CSTACK_SLOTS := 64 * 1024.
	MAX_FRAMES := CSTACK_SLOTS.
	CACHE_SIZE := 4096.
	ICACHE_SIZE := 4096
!
handlerTable
	"Simulation: the handler selector of each bytecode."
	^handlers ifNil: [handlers := self buildHandlerTable]
!
resetSimulationCaches
	handlers := nil
!
buildHandlerTable
	"Single-bytecode handlers and lists take precedence over ranges."
	| table bad ranges |
	table := Array new: 256.
	ranges := OrderedCollection new.
	self selectors do: [:s |
		| m p |
		m := self compiledMethodAt: s.
		(m pragmas ifNil: [#()]) do: [:each |
			each selector == #bytecode: ifTrue: [table at: each arguments first + 1 put: s].
			each selector == #bytecodeList: ifTrue: [each arguments first do: [:b | table at: b + 1 put: s]].
			each selector == #bytecodes: ifTrue: [
				each arguments first isEmpty
					ifTrue: [bad := s]
					ifFalse: [ranges add: each arguments first -> s]]]].
	ranges do: [:r | (r key at: 1) to: (r key at: 2) do: [:b | (table at: b + 1) isNil ifTrue: [table at: b + 1 put: r value]]].
	^table collect: [:s | s ifNil: [bad]]
! !

!Interpreter methodsFor: 'accessing'!
activeCtx
	^activeCtx
!
activeCtx: c
	activeCtx := c
!
tmpRoots
	^tmpRoots
!
primResult
	^primResult
!
primResult: o
	primResult := o
!
resendSelector
	^resendSelector
!
resendSelector: o
	resendSelector := o
!
primStatus
	^primStatus
!
primStatus: s
	primStatus := s
!
primErrorCode
	^primErrorCode
!
nframes
	^nframes
!
frames
	^frames
!
cstackEnd
	^self cCoerce: cstack + CSTACK_SLOTS to: 'uint64_t'
!
specialArgcAt: k
	^specialArgc at: k
!
stackLimit
	^stackLimit
!
stackLimit: n
	stackLimit := n
!
stackCheckAt: n
	stackCheckAt := n
!
statMaterialized
	^statMaterialized
!
statFlushes
	^statFlushes
!
frameEpoch
	"Changes whenever frames are flushed or moved: machine code running on them must leave."
	^frameEpoch
!
safepointAtEntry
	^safepointAtEntry
!
safepointAtEntry: aBoolean
	safepointAtEntry := aBoolean
! !

!Interpreter methodsFor: 'frames'!
roots: fn
	"The frames' methods, closures and Contexts and the live C stack slots are GC roots (not optimized frames' raw slots: doubles' IEEE bits)."
	<function>
	<var: #w type: 'int64_t'>
	<var: #lo type: 'int64_t'>
	<var: #hi type: 'int64_t'>
	| w n f lo hi |
	0 to: nframes - 1 do: [:i |
		fn call: ((frames + i) fieldAddress: #method).
		fn call: ((frames + i) fieldAddress: #closure).
		fn call: ((frames + i) fieldAddress: #ctx)].
	w := 0.
	n := 0.
	[w < cstackUsed asInt64] whileTrue: [
		"up to the next optimized frame's raw slots, lo to hi"
		lo := cstackUsed asInt64.
		hi := lo.
		[n < nframes and: [hi = lo]] whileTrue: [
			f := frames + n.
			n := n + 1.
			(jit isOptFrame: f) ifTrue: [
				lo := (f fp - cstack) asInt64 + (jit rawBaseOf: f).
				hi := (f fp - cstack) asInt64 + (jit rawTopOf: f)]].
		[w < (lo min: cstackUsed asInt64)] whileTrue: [
			fn call: cstack + w.
			w := w + 1].
		w := w max: hi]
!
frame: i holds: o
	"Frame i's receiver, arguments, temps or stack (not an optimized frame's raw slots) include o."
	<function>
	<var: #w type: 'int64_t'>
	<var: #hi type: 'int64_t'>
	<var: #rlo type: 'int64_t'>
	<var: #rhi type: 'int64_t'>
	| f w hi rlo rhi |
	f := frames + i.
	hi := i + 1 < nframes ifTrue: [((frames + (i + 1)) fp - cstack) asInt64 - 1] ifFalse: [cstackUsed asInt64].
	rlo := hi.
	rhi := hi.
	(jit isOptFrame: f) ifTrue: [
		rlo := (f fp - cstack) asInt64 + (jit rawBaseOf: f).
		rhi := (f fp - cstack) asInt64 + (jit rawTopOf: f)].
	w := (f fp - cstack) asInt64 - 1.
	[w < hi] whileTrue: [
		((w < rlo or: [w >= rhi]) and: [(cstack at: w) = o]) ifTrue: [^true].
		w := w + 1].
	^false
!
methodBcs: m
	^self bytesOf: (self loadRef: m at: CM_BYTECODES)
!
refreshLiterals
	"becomeForward: may have forwarded a method's literal Array: the frames take their pointers into literals again, and the interpreter reloads its registers when the primitive returns."
	<function>
	| f |
	0 to: nframes - 1 do: [:i |
		f := frames + i.
		f lits: (self slotsOf: (self literalsOf: f method))].
	gc gcEpoch: gc gcEpoch + 1
!
beforeGC
	"Frames hold raw pointers into their methods' bytecodes and literals: offsets while objects move."
	<function>
	| f |
	0 to: nframes - 1 do: [:i |
		f := frames + i.
		(jit isOptFrame: f) ifFalse: [f pc: (f ip - (self methodBcs: f method)) asInt32]]
!
refreshTagClasses
	"Classes of immediates by tag (low 3 bits); 0 = object pointer."
	<function>
	1 to: 7 do: [:t |
		tagClass at: t put: ((t bitAnd: 1) ~= 0
			ifTrue: [memory clsSmallint]
			ifFalse: [t = 2 ifTrue: [memory clsChar] ifFalse: [t = 4 ifTrue: [memory clsSmallfloat] ifFalse: [memory nilOop]]])]
!
receiverClass: r
	^(r bitAnd: 7) ~= 0 ifTrue: [tagClass at: (r bitAnd: 7)] ifFalse: [self rawClass: r]
!
afterGC
	<function>
	| f |
	self refreshTagClasses.
	self refreshPrimBase.
	0 to: nframes - 1 do: [:i |
		f := frames + i.
		f ip: (self methodBcs: f method) + f pc.
		f lits: (self slotsOf: (self literalsOf: f method))]
!
frameSize: f
	"frameSize of a frame's method or block (at least its args and temps)."
	<function>
	| blk src fs min |
	blk := f closure ~= memory nilOop.
	src := blk ifTrue: [f closure] ifFalse: [f method].
	fs := self intVal: (self loadRef: src at: (blk ifTrue: [BC_FRAMESIZE] ifFalse: [CM_FRAMESIZE])).
	min := blk
		ifTrue: [(self intVal: (self loadRef: src at: BC_NUMARGS)) + (self intVal: (self loadRef: src at: BC_NUMTEMPS))]
		ifFalse: [(self intVal: (self loadRef: src at: CM_NUMARGS)) + (self intVal: (self loadRef: src at: CM_NUMTEMPS))].
	^fs > min ifTrue: [fs] ifFalse: [min]
!
framesValid: valid
	<function>
	<var: #w type: 'int64_t'>
	<var: #lo type: 'int64_t'>
	<var: #hi type: 'int64_t'>
	| w n f lo hi |
	0 to: nframes - 1 do: [:i |
		((valid call: (frames + i) method) and: [(valid call: (frames + i) closure) and: [valid call: (frames + i) ctx]]) ifFalse: [^false].
		"a married Context names its frame (materializeAll fills them one by one)"
		((frames + i) ctx ~= memory nilOop and: [(self isInt: (self loadRef: (frames + i) ctx at: CTX_SENDER)) and: [(self loadRef: (frames + i) ctx at: CTX_SENDER) ~= (self intOop: i)]]) ifTrue: [
			libc fprintf: libc stderr format: 'frame %lld: its Context is married to another frame
' with: i asInt64.
			^false]].
	w := 0.
	n := 0.
	[w < cstackUsed asInt64] whileTrue: [
		"as roots:, not optimized frames' raw slots"
		lo := cstackUsed asInt64.
		hi := lo.
		[n < nframes and: [hi = lo]] whileTrue: [
			f := frames + n.
			n := n + 1.
			(jit isOptFrame: f) ifTrue: [
				lo := (f fp - cstack) asInt64 + (jit rawBaseOf: f).
				hi := (f fp - cstack) asInt64 + (jit rawTopOf: f)]].
		[w < (lo min: cstackUsed asInt64)] whileTrue: [
			(valid call: (cstack at: w)) ifFalse: [
				libc fprintf: libc stderr format: 'slot %lld of %lld: %llx
' with: w with: cstackUsed asInt64 with: (cstack at: w).
				0 to: nframes - 1 do: [:k |
					libc fprintf: libc stderr format: 'frame %d fp %lld sp %d pc %d ' with: k with: ((frames + k) fp - cstack) asInt64 with: (frames + k) sp with: (frames + k) pc.
					self printActivation: (frames + k) method receiver: ((frames + k) fp at: -1) closure: (frames + k) closure on: libc stderr].
				^false].
			w := w + 1].
		w := w max: hi].
	^true
!
materializeAll
	"Flush every frame into a Context (bottom up, so senders exist first; a married frame fills its own); afterwards activeCtx is the top one. The caller has externalized the top frame."
	<function>
	| n ctx f s byHeap |
	nframes ~= 0 ifTrue: [
		statFlushes := statFlushes + 1.
		frameEpoch := frameEpoch + 1].
	statMaterialized := statMaterialized + nframes asUInt64.
	0 to: nframes - 1 do: [:i |
		f := frames + i.
		(jit isOptFrame: f)
			ifTrue: [jit materializeOpt: f]
			ifFalse: [
				ctx := f ctx.
				ctx = memory nilOop ifTrue: [
					n := (self frameSize: f) + CTX_SLACK.
					n < f sp ifTrue: [n := f sp].
					ctx := memory allocContext: n asUInt32].
				s := self slotsOf: ctx.
				s at: CTX_SENDER put: activeCtx.
				s at: CTX_PC put: (self intOop: f ip - (self methodBcs: f method)).
				s at: CTX_STACKP put: (self intOop: f sp).
				s at: CTX_METHOD put: f method.
				s at: CTX_CLOSURE put: f closure.
				s at: CTX_RECEIVER put: (f fp at: -1).
				libc memcpy: s + CTX_FIXED from: f fp size: f sp asUInt64 * 8.
				gc rememberIfOld: ctx.
				activeCtx := ctx]].
	nframes := 0.
	cstackUsed := 0.
	self refreshPrimBase.
	gc gcEpoch: gc gcEpoch + 1.
	(statMaterialized >= stackCheckAt and: [stackLimit > 0]) ifTrue: [
		byHeap := ((gc maxHeapBytes quo: 4) quo: 8 * (2 + CTX_FIXED + CTX_SLACK)) asInt64.
		stackCheckAt := statMaterialized + ((stackLimit min: byHeap) asUInt64 quo: 8) + 1.
		stackCheckDue := true.
		stackCheckHash := self hashOf: scheduler activeProcess.
		scheduler requestInterruptCheck]
!
marry: f
	"Frame f's Context, created if it has none: method, closure and receiver set, sender f's index (the mark of a married Context), stackp 0; pc, temps and stack stay in the frame. The caller has externalized."
	<function>
	| n ctx s |
	f ctx ~= memory nilOop ifTrue: [^f ctx].
	n := (self frameSize: f) + CTX_SLACK.
	n < f sp ifTrue: [n := f sp].
	ctx := memory allocContext: n asUInt32.
	s := self slotsOf: ctx.
	s at: CTX_SENDER put: (self intOop: f - frames).
	s at: CTX_STACKP put: (self intOop: 0).
	s at: CTX_METHOD put: f method.
	s at: CTX_CLOSURE put: f closure.
	s at: CTX_RECEIVER put: (f fp at: -1).
	gc rememberIfOld: ctx.
	f ctx: ctx.
	^ctx
!
isMarried: o
	"o is a Context married to a frame (its sender is the frame's index)."
	<function>
	^(self isPtr: o) and: [(self rawClass: o) = memory clsContext and: [self isInt: (self loadRef: o at: CTX_SENDER)]]
!
flushIfMarried: o
	"Before reading o's slots: a married Context gets its frame's state (all frames are flushed). The caller has externalized."
	<function>
	(self isMarried: o) ifTrue: [self materializeAll]
!
widow: f
	"Married frame f returns: its Context becomes a dead Context with the frame's slots (blocks that outlive it use them), as many as it holds: an optimized frame (a loop's unit entered married) may have more."
	<function>
	| ctx s n |
	ctx := f ctx.
	s := self slotsOf: ctx.
	n := (self numSlots: ctx) asInt64 - CTX_FIXED.
	f sp < n ifTrue: [n := f sp].
	"not an optimized frame's raw slots (doubles' IEEE bits)"
	((jit isOptFrame: f) and: [(jit rawBaseOf: f) < (jit rawTopOf: f)]) ifTrue: [n := n min: (jit rawBaseOf: f)].
	libc memcpy: s + CTX_FIXED from: f fp size: n asUInt64 * 8.
	s at: CTX_SENDER put: memory nilOop.
	s at: CTX_PC put: memory nilOop.
	s at: CTX_STACKP put: (self intOop: n).
	gc rememberIfOld: ctx.
	f ctx: memory nilOop
!
widowFrom: k to: n
	"Frames k to n are dropped (externalized)."
	<function>
	<var: #n type: 'int64_t'>
	k to: n do: [:i | (frames + i) ctx ~= memory nilOop ifTrue: [self widow: frames + i]]
!
contextField: i of: c
	"Field i (sender, pc or stackp) of Context c as Smalltalk sees it: a married one answers from its frame, its sender being the caller frame's Context, married now (activeCtx for frame 0). 0 if that would look into an optimized frame (the caller's; c's own for pc and stackp): the frames are flushed instead, and c holds the answer. The caller has externalized."
	<function>
	| f |
	(self isMarried: c) ifFalse: [^(self slotsOf: c) at: i].
	f := frames + (self intVal: (self loadRef: c at: CTX_SENDER)).
	i = CTX_SENDER ifTrue: [
		f = frames ifTrue: [^activeCtx].
		(jit isOptFrame: f - 1) ifTrue: [
			self materializeAll.
			^0].
		^self marry: f - 1].
	(jit isOptFrame: f) ifTrue: [
		self materializeAll.
		^0].
	i = CTX_PC ifTrue: [^self intOop: f ip - (self methodBcs: f method)].
	^self intOop: f sp
!
contextSlot: k of: c
	"Indexable slot k (0-based) of married Context c: its frame's below the frame's stack pointer, nil above. 0 if c's frame is optimized: the frames are flushed instead, and c holds it. The caller has externalized."
	<function>
	| f |
	f := frames + (self intVal: (self loadRef: c at: CTX_SENDER)).
	(jit isOptFrame: f) ifTrue: [
		self materializeAll.
		^0].
	k < f sp asInt64 ifTrue: [^f fp at: k].
	^memory nilOop
!
context: c slot: k put: v
	"Store v into indexable slot k of married Context c, in its frame. false if k is above the frame's stack pointer or the frame is optimized: the frames are flushed instead, and the caller stores into c. The caller has externalized."
	<function>
	| f |
	f := frames + (self intVal: (self loadRef: c at: CTX_SENDER)).
	((jit isOptFrame: f) or: [k >= f sp asInt64]) ifTrue: [
		self materializeAll.
		^false].
	f fp at: k put: v.
	^true
!
senderOf: c marker: p upTo: stop
	"The first activation among c's senders, before stop, of a method (not a block) whose primitive is marker p: frames from c's down, married then, followed by the Contexts below them; nil if there is none. The caller has externalized."
	<function>
	<var: #p type: 'int64_t'>
	| x j f |
	x := c.
	[(self isMarried: x)
		ifTrue: [
			j := self intVal: (self loadRef: x at: CTX_SENDER).
			[j > 0] whileTrue: [
				j := j - 1.
				f := frames + j.
				(stop ~= memory nilOop and: [f ctx = stop]) ifTrue: [^memory nilOop].
				(f closure = memory nilOop and: [((self methodPrim: f method) bitAnd: CM_PRIM_MASK) = p]) ifTrue: [^self marry: f]].
			x := activeCtx]
		ifFalse: [x := self loadRef: x at: CTX_SENDER].
	 (self isPtr: x) and: [x ~= memory nilOop and: [x ~= stop]]] whileTrue: [
		((self loadRef: x at: CTX_CLOSURE) = memory nilOop and: [((self methodPrim: (self loadRef: x at: CTX_METHOD)) bitAnd: CM_PRIM_MASK) = p]) ifTrue: [^x]].
	^memory nilOop
!
terminate: c to: target
	"c terminateTo: target, for c married to the top frame and target married to a frame below it, neither optimized, or target a Context among activeCtx and its senders: the activations in between die (frames widowed, Contexts terminated) and the top frame moves down to just above target's frame (to frame 0, activeCtx being target). false otherwise: Smalltalk does it. The caller has externalized."
	<function>
	| t j x next |
	t := nframes - 1.
	(t >= 0 and: [(self isMarried: c) and: [(self loadRef: c at: CTX_SENDER) = (self intOop: t) and: [(jit isOptFrame: frames + t) not]]]) ifFalse: [^false].
	(self isMarried: target)
		ifTrue: [
			j := self intVal: (self loadRef: target at: CTX_SENDER).
			(j >= t or: [jit isOptFrame: frames + j]) ifTrue: [^false]]
		ifFalse: [
			j := -1.
			x := activeCtx.
			[x ~= target and: [(self isPtr: x) and: [x ~= memory nilOop]]] whileTrue: [x := self loadRef: x at: CTX_SENDER].
			(x = target and: [target ~= memory nilOop]) ifFalse: [^false]].
	self widowFrom: j + 1 to: t - 1.
	j < 0 ifTrue: [
		x := activeCtx.
		[x ~= target] whileTrue: [
			next := self loadRef: x at: CTX_SENDER.
			self storeRef: x at: CTX_SENDER put: memory nilOop.
			self storeRef: x at: CTX_PC put: memory nilOop.
			x := next].
		activeCtx := target].
	j + 1 < t ifTrue: [self moveTop: t to: j + 1].
	^true
!
moveTop: t to: k
	"Top frame t becomes frame k (k < t; the frames between are dropped): its receiver and slots move to where frame k's are, its Context follows."
	| f g nfp |
	f := frames + t.
	g := frames + k.
	nfp := g fp.
	libc memmove: nfp - 1 from: f fp - 1 size: (f sp asUInt64 + 1) * 8.
	g copyStructFrom: f.
	g fp: nfp.
	g ctx ~= memory nilOop ifTrue: [(self slotsOf: g ctx) at: CTX_SENDER put: (self intOop: k)].
	nframes := (k + 1) asInt32.
	cstackUsed := (nfp + g sp - cstack) asUInt64.
	self refreshPrimBase.
	gc gcEpoch: gc gcEpoch + 1.
	frameEpoch := frameEpoch + 1
!
stackOverflowDepth
	"The active process's depth (frames + Contexts) if it is too deep: beyond stackLimit, or its Contexts take more than a quarter of the heap limit. Else 0."
	<function>
	| depth bytes c |
	stackCheckDue := false.
	stackLimit <= 0 ifTrue: [^0].
	depth := nframes asInt64.
	bytes := 0 asUInt64.
	c := activeCtx.
	[(self isPtr: c) and: [c ~= memory nilOop]] whileTrue: [
		depth := depth + 1.
		bytes := bytes + (self objBytes: c).
		c := self loadRef: c at: CTX_SENDER].
	^(depth > stackLimit or: [bytes > (gc maxHeapBytes quo: 4)]) ifTrue: [depth] ifFalse: [0]
! !

!Interpreter methodsFor: 'method cache'!
cacheIndexOf: aClass selector: aSelector
	^(((aClass >> 3) bitXor: (aSelector >> 3)) bitXor: (aSelector >> 12)) bitAnd: CACHE_SIZE - 1
!
icacheIndexOf: site
	| s |
	s := self cCoerce: site to: 'uint64_t'.
	^(s bitXor: s >> 12) bitAnd: ICACHE_SIZE - 1
!
flushMethodCache
	<function>
	libc memset: cache value: 0 size: (self sizeof: 'CacheEntry') * CACHE_SIZE.
	libc memset: icache value: 0 size: (self sizeof: 'CacheEntry') * ICACHE_SIZE
!
flushMethodCacheSelector: aSelector
	<function>
	| e |
	0 to: CACHE_SIZE - 1 do: [:i |
		e := cache + i.
		e sel = aSelector ifTrue: [
			e cls: 0.
			e sel: 0]].
	libc memset: icache value: 0 size: (self sizeof: 'CacheEntry') * ICACHE_SIZE
!
lookupMethod: aClass selector: aSelector
	<function>
	| h c md keys vals cap mask i k n |
	h := self hashOf: aSelector.
	c := aClass.
	[(self isPtr: c) and: [c ~= memory nilOop]] whileTrue: [
		md := self loadRef: c at: BEH_METHODDICT.
		((self isPtr: md) and: [md ~= memory nilOop]) ifTrue: [
			keys := memory follow: (self loadRef: md at: MD_KEYS).
			vals := memory follow: (self loadRef: md at: MD_VALUES).
			cap := self numSlots: keys.
			(cap ~= 0 and: [(self isPtr: vals) and: [(self numSlots: vals) >= cap]]) ifTrue: [
				mask := cap - 1.
				i := h bitAnd: mask.
				n := 0.
				[n < cap] whileTrue: [
					k := self loadRef: keys at: i.
					k = aSelector ifTrue: [^self loadRef: vals at: i].
					k = memory nilOop
						ifTrue: [n := cap]
						ifFalse: [
							i := (i + 1) bitAnd: mask.
							n := n + 1]]]].
		c := self loadRef: c at: BEH_SUPERCLASS].
	^0
!
methodPrim: m
	| p |
	p := self loadRef: m at: CM_PRIMITIVE.
	^(self isInt: p) ifTrue: [self intVal: p] ifFalse: [0]
!
fillCache: aClass selector: aSelector
	<function>
	| m e p pf bc na nt b n ok qc qv litsOop size |
	m := self lookupMethod: aClass selector: aSelector.
	m = 0 ifTrue: [^self null].
	e := cache + (self cacheIndexOf: aClass selector: aSelector).
	e cls: aClass.
	e sel: aSelector.
	e method: m.
	p := (self methodPrim: m) bitAnd: CM_PRIM_MASK.
	pf := (p ~= 0 and: [p ~= PRIM_ENSURE_MARKER and: [p ~= PRIM_ONDO_MARKER]])
		ifTrue: [primitives lookup: p]
		ifFalse: [self null].
	bc := self loadRef: m at: CM_BYTECODES.
	na := self loadRef: m at: CM_NUMARGS.
	nt := self loadRef: m at: CM_NUMTEMPS.
	e bcs: (self bytesOf: bc).
	e lits: (self slotsOf: (self literalsOf: m)).
	e ntemps: (self intVal: nt) asInt32.
	e fsize: (self intVal: (self loadRef: m at: CM_FRAMESIZE)) asInt32.
	e fsize < ((self intVal: na) + e ntemps) ifTrue: [e fsize: ((self intVal: na) + e ntemps) asInt32].
	"Quick methods (as in Smalltalk-80 and Squeak): a unary method whose bytecodes are exactly push inst var i, return top answers the receiver's slot i without activating a frame."
	e quick: -1.
	e nset: 0.
	(p = 0 and: [na = (self intOop: 0) and: [(self isPtr: bc) and: [(memory formatOf: bc) >= F_BYTES and: [(memory byteSize: bc) = 2]]]]) ifTrue: [
		b := self bytesOf: bc.
		((b at: 0) >= 16r10 and: [(b at: 0) <= 16r1F and: [(b at: 1) = 16r79]]) ifTrue: [e quick: ((b at: 0) - 16r10) asInt8]].
	"Setters: for each argument k in order push temp k, store inst var i, pop, then return self, no temps."
	(p = 0 and: [(self isInt: na) and: [(self intVal: na) >= 1 and: [(self intVal: na) <= 4 and: [nt = (self intOop: 0) and: [
		(self isPtr: bc) and: [(memory formatOf: bc) >= F_BYTES and: [(memory byteSize: bc) = (4 * (self intVal: na) + 1) asUInt64]]]]]]]) ifTrue: [
		b := self bytesOf: bc.
		n := self intVal: na.
		ok := (b at: 4 * n) = 16r7A.
		0 to: n - 1 do: [:k |
			ok := ok and: [(b at: 4 * k) = k and: [(b at: 4 * k + 1) = 16r85 and: [(b at: 4 * k + 3) = 16r78]]]].
		ok ifTrue: [
			0 to: n - 1 do: [:k | e setIvar at: k put: (b at: 4 * k + 2)].
			e nset: n asUInt8]].
	"^self, ^true / ^false / ^nil / ^0 / ^1, ^literal, ^smallInt: answer it without a frame"
	qc := false.
	qv := 0 asUInt64.
	(p = 0 and: [(self isPtr: bc) and: [(memory formatOf: bc) >= F_BYTES]]) ifTrue: [
		b := self bytesOf: bc.
		size := memory byteSize: bc.
		litsOop := self literalsOf: m.
		(size = 1 and: [(b at: 0) = 16r7A])
			ifTrue: [qc := true]
			ifFalse: [
				(size = 2 and: [(b at: 1) = 16r79 and: [(b at: 0) >= 16r71 and: [(b at: 0) <= 16r75]]])
					ifTrue: [
						qv := (b at: 0) <= 16r73
							ifTrue: [(b at: 0) = 16r71 ifTrue: [memory trueOop] ifFalse: [(b at: 0) = 16r72 ifTrue: [memory falseOop] ifFalse: [memory nilOop]]]
							ifFalse: [self intOop: (b at: 0) - 16r74].
						qc := true]
					ifFalse: [
						(size = 2 and: [(b at: 1) = 16r79 and: [(b at: 0) >= 16r20 and: [(b at: 0) <= 16r3F and: [(self isPtr: litsOop) and: [((b at: 0) - 16r20) asUInt32 < (self numSlots: litsOop)]]]]])
							ifTrue: [
								"the cache is flushed at every GC"
								qv := self loadRef: litsOop at: (b at: 0) - 16r20.
								qc := qv ~= 0]
							ifFalse: [
								(size = 4 and: [(b at: 0) = 16r93 and: [(b at: 3) = 16r79]]) ifTrue: [
									qv := self intOop: ((b at: 1) bitOr: (b at: 2) asUInt64 << 8) asInt16.
									qc := true]]]]].
	qc ifTrue: [e qconst: qv] ifFalse: [e prim: pf].
	e kind: ((((pf notNull ifTrue: [K_PRIM] ifFalse: [0])
		bitOr: ((pf notNull and: [primitives isLeaf: p]) ifTrue: [K_LEAF] ifFalse: [0]))
		bitOr: (e quick >= 0 ifTrue: [K_QUICK] ifFalse: [0]))
		bitOr: ((e nset ~= 0 ifTrue: [K_SETTER] ifFalse: [0]) bitOr: (qc ifTrue: [K_CONST] ifFalse: [0]))) asUInt8.
	"An ordinary method under a JIT: its code, or 1 while its activations are counted."
	(e kind = 0 and: [jit enabled]) ifTrue: [
		e code: (jit cacheCodeFor: m).
		e code ~= 0 ifTrue: [e kind: K_JIT]].
	^e
!
selectorArgc: aSelector
	<function>
	<returns: 'int'>
	| n b c |
	((self isPtr: aSelector) not or: [(memory formatOf: aSelector) < F_BYTES]) ifTrue: [^-1].
	n := memory byteSize: aSelector.
	b := self bytesOf: aSelector.
	n = 0 ifTrue: [^0].
	(((b at: 0) >= $a value and: [(b at: 0) <= $z value]) or: [((b at: 0) >= $A value and: [(b at: 0) <= $Z value]) or: [(b at: 0) = $_ value]])
		ifFalse: [^1].
	c := 0.
	0 to: n asInt64 - 1 do: [:i | (b at: i) = $: value ifTrue: [c := c + 1]].
	^c
! !

!Interpreter methodsFor: 'interrupts'!
interruptSafepoint
	"At an interrupt check (registers externalized), before handleInterrupts can switch processes: if a depth check of the active process is due and it is too deep, its frames are flushed and the top Context sends stackOverflow: depth, as if its next instruction did (an activation above it; its own stack unchanged). The pending interrupts are then handled at the next safepoint."
	<function>
	| depth sel m ntemps fsize ctx s |
	depth := (stackCheckDue and: [(self hashOf: scheduler activeProcess) = stackCheckHash]) ifTrue: [self stackOverflowDepth] ifFalse: [0].
	depth = 0 ifTrue: [^scheduler handleInterrupts].
	self materializeAll.
	"these flushed frames must not trigger a check of the stack being handled"
	stackCheckDue := false.
	sel := memory special: SO_SEL_STACKOVERFLOW.
	m := self lookupMethod: (self rawClass: activeCtx) selector: sel.
	(m = 0 or: [(self isPtr: m) not or: [(self methodPrim: m) ~= 0 or: [(self loadRef: m at: CM_NUMARGS) ~= (self intOop: 1)]]]) ifTrue: [
		^scheduler handleInterrupts].
	ntemps := self intVal: (self loadRef: m at: CM_NUMTEMPS).
	fsize := self intVal: (self loadRef: m at: CM_FRAMESIZE).
	fsize < (1 + ntemps) ifTrue: [fsize := 1 + ntemps].
	tmpRoots at: 0 put: m.
	ctx := memory allocContext: (fsize + CTX_SLACK) asUInt32.
	s := self slotsOf: ctx.
	s at: CTX_SENDER put: activeCtx.
	s at: CTX_RECEIVER put: activeCtx.
	s at: CTX_PC put: (self intOop: 0).
	s at: CTX_STACKP put: (self intOop: 1 + ntemps).
	s at: CTX_METHOD put: (tmpRoots at: 0).
	s at: CTX_FIXED put: (self intOop: depth).
	tmpRoots at: 0 put: memory nilOop.
	activeCtx := ctx
!
entrySafepoint
	"interruptSafepoint at an activation's first instruction: a process preempted here has its top frame just activated (Scheduler>>resumeProcess:)."
	<function>
	safepointAtEntry := true.
	self interruptSafepoint.
	safepointAtEntry := false
! !

!Interpreter methodsFor: 'the active activation'!
ctxStackp: ctx
	<function>
	^self intVal: (self loadRef: ctx at: CTX_STACKP)
!
ctx: ctx setStackp: n
	<function>
	(self slotsOf: ctx) at: CTX_STACKP put: (self intOop: n)
!
ctxHome: aContext
	<function>
	| c cl |
	c := aContext.
	[(cl := self loadRef: c at: CTX_CLOSURE) ~= memory nilOop] whileTrue: [c := self loadRef: cl at: BC_OUTER].
	^c
!
activeSlots
	"Args, temps and stack of the active frame or Context."
	<function>
	^nframes ~= 0 ifTrue: [(frames + (nframes - 1)) fp] ifFalse: [(self slotsOf: activeCtx) + CTX_FIXED]
!
activeStackp
	<function>
	^nframes ~= 0 ifTrue: [(frames + (nframes - 1)) sp asInt64] ifFalse: [self ctxStackp: activeCtx]
!
activeSetStackp: n
	<function>
	| f |
	nframes ~= 0
		ifTrue: [
			f := frames + (nframes - 1).
			f sp: n asInt32.
			cstackUsed := (f fp + n - cstack) asUInt64]
		ifFalse: [self ctx: activeCtx setStackp: n]
!
activeCapacity
	"Indexable slots the active activation may use: a Context's; a frame's up to the end of the C stack, or as many as its Context holds if it is married (materializeAll copies them into it; Contexts made for frames hold all of theirs)."
	<function>
	| f |
	nframes = 0 ifTrue: [^(self numSlots: activeCtx) asInt64 - CTX_FIXED].
	f := frames + (nframes - 1).
	f ctx ~= memory nilOop ifTrue: [^(self numSlots: f ctx) asInt64 - CTX_FIXED].
	^cstack + CSTACK_SLOTS - f fp
! !

!Interpreter methodsFor: 'primitive plumbing'!
primArgc
	^primNargs
!
primReceiver
	^primBase at: 0
!
primArg: i
	^primBase at: 1 + i
!
primStackBase
	"The receiver slot in the active activation."
	^primBase
!
setPrimBase: n
	"The primitive's receiver is at the active stack top - n."
	<function>
	primNargs := n.
	primBaseIndex := self activeStackp - 1 - n.
	primBase := self activeSlots + primBaseIndex
!
refreshPrimBase
	<function>
	primBase := self activeSlots + primBaseIndex
!
primReturn: v
	primResult := v.
	primStatus := PS_OK
!
primFail
	primStatus := PS_FAIL.
	primErrorCode := -1
!
primFailCode: code
	"The method's error temp (<primitive: 'x' error: ec>) gets SmallInteger code."
	primStatus := PS_FAIL.
	primErrorCode := code
!
primFailed
	^primStatus = PS_FAIL
!
primCommit: aResult
	"Pop receiver and arguments, push aResult now, mark switched."
	<function>
	primBase at: 0 put: aResult.
	self activeSetStackp: self activeStackp - primNargs.
	primNargs := 0.
	primStatus := PS_SWITCHED
!
primSwitched
	"The primitive arranged the stack itself."
	primStatus := PS_SWITCHED
!
primCommitted
	"The primitive arranged the stack itself, and its arguments are gone."
	primNargs := 0.
	primStatus := PS_SWITCHED
!
primResend: aSelector argc: n
	"The primitive becomes a send of aSelector with n arguments (perform:)."
	resendSelector := aSelector.
	resendArgc := n.
	primStatus := PS_RESEND
!
followArgs: n at: b
	"A primitive failed: if its receiver or one of its n arguments at b is a forwarder (becomeForward:), replace it by its target and answer true (the primitive runs again)."
	<function>
	| found |
	gc forwardersExist ifFalse: [^false].
	found := false.
	0 to: n do: [:i |
		(memory isForwarder: (b at: i)) ifTrue: [
			b at: i put: (memory follow: (b at: i)).
			found := true]].
	^found
! !

!Interpreter methodsFor: 'blocks'!
blockActivate: n fromArray: fromArray
	"Push a frame for the closure at the stack base (n args above it, or one Array when fromArray). The caller has externalized."
	<function>
	| count base b cl arr ntemps fsize nfp outer m f |
	count := n.
	base := self activeStackp - 1 - (fromArray ifTrue: [1] ifFalse: [count]).
	b := self activeSlots + base.
	cl := b at: 0.
	arr := fromArray ifTrue: [b at: 1] ifFalse: [0 asUInt64].
	fromArray ifTrue: [count := (self numSlots: arr) asInt32].
	ntemps := self intVal: (self loadRef: cl at: BC_NUMTEMPS).
	fsize := self intVal: (self loadRef: cl at: BC_FRAMESIZE).
	fsize < (count + ntemps) ifTrue: [fsize := count + ntemps].
	nframes ~= 0
		ifTrue: [
			nfp := b + 1.
			(nframes >= MAX_FRAMES or: [nfp + fsize + CTX_SLACK > (cstack + CSTACK_SLOTS)]) ifTrue: [
				self materializeAll.
				^self blockActivate: (fromArray ifTrue: [0] ifFalse: [count]) fromArray: fromArray].
			(frames + (nframes - 1)) sp: base asInt32.
			b at: 0 put: (self receiverOfClosure: cl).
			fromArray ifTrue: [0 to: count - 1 do: [:i | nfp at: i put: (self loadRef: arr at: i)]]]
		ifFalse: [
			cstack at: 0 put: (self receiverOfClosure: cl).
			0 to: count - 1 do: [:i | cstack at: 1 + i put: (fromArray ifTrue: [self loadRef: arr at: i] ifFalse: [b at: 1 + i])].
			self ctx: activeCtx setStackp: base.
			nfp := cstack + 1].
	outer := self loadRef: cl at: BC_OUTER.
	m := self loadRef: outer at: CTX_METHOD.
	f := frames + nframes.
	nframes := nframes + 1.
	f method: m.
	f closure: cl.
	f ctx: memory nilOop.
	f code: (jit frameCodeFor: m block: (self intVal: (self loadRef: cl at: BC_STARTPC)) asInt32).
	f fp: nfp.
	f pc: (self intVal: (self loadRef: cl at: BC_STARTPC)) asInt32.
	f ip: (self methodBcs: m) + (self intVal: (self loadRef: cl at: BC_STARTPC)).
	f lits: (self slotsOf: (self literalsOf: m)).
	f sp: (count + ntemps) asInt32.
	count to: count + ntemps - 1 do: [:i | nfp at: i put: memory nilOop].
	cstackUsed := (nfp + count + ntemps - cstack) asUInt64
!
receiverOfClosure: cl
	"The receiver of closure cl's activation: its outer Context's (which may hold a forwarder: Contexts are not fixed when an object is forwarded)."
	| r |
	r := self loadRef: (self loadRef: cl at: BC_OUTER) at: CTX_RECEIVER.
	(self unlikely: gc forwardersExist) ifTrue: [r := memory follow: r].
	^r
!
activateBlock: n
	<function>
	self blockActivate: n fromArray: false
!
activateBlockWithArray
	<function>
	self blockActivate: 0 fromArray: true
! !

!Interpreter methodsFor: 'machine code'!
syncFrame: f
	"Machine code ran f and stored its pc and sp: f is the top frame."
	<function>
	nframes := (f - frames) asInt32 + 1.
	f ip: (self methodBcs: f method) + f pc.
	cstackUsed := (f fp + f sp - cstack) asUInt64
!
icacheAt: site
	"The inline cache entry of the send site site."
	^icache + (self icacheIndexOf: site)
!
siteEntry: site class: aClass selector: aSelector
	"As doSiteLookup: the inline cache entry of the send whose continuation is site; null if aClass does not understand aSelector."
	<function>
	| e g |
	e := icache + (self icacheIndexOf: site).
	(e cls = aClass and: [e sel = (self cCoerce: site to: 'oop')]) ifTrue: [^e].
	g := cache + (self cacheIndexOf: aClass selector: aSelector).
	(g cls ~= aClass or: [g sel ~= aSelector]) ifTrue: [
		g := self fillCache: aClass selector: aSelector.
		g isNull ifTrue: [^self null]].
	e copyStructFrom: g.
	e sel: (self cCoerce: site to: 'oop').
	^e
!
callPrimitive: fn base: b argc: n
	"Run primitive fn on the receiver and n arguments at b, the top of the top frame (externalized); answer primStatus."
	<function>
	primNargs := n.
	primBase := b.
	primBaseIndex := b - self activeSlots.
	primStatus := PS_NONE.
	fn call.
	(self unlikely: (primStatus = PS_FAIL and: [gc forwardersExist and: [self followArgs: n at: primBase]])) ifTrue: [
		primStatus := PS_NONE.
		fn call].
	^primStatus
!
callLeafPrimitive: fn base: b argc: n
	"Run the leaf primitive fn on the receiver and n arguments at b, as the interpreter does: nothing externalized; answer primStatus."
	primNargs := n.
	primBase := b.
	primStatus := PS_NONE.
	fn call.
	(self unlikely: (primStatus = PS_FAIL and: [gc forwardersExist and: [self followArgs: n at: b]])) ifTrue: [
		primStatus := PS_NONE.
		fn call].
	^primStatus
!
pushFrame: m argc: n code: c ecode: ecode
	"Activate m as activate does: its receiver and n arguments are the top of the top frame, whose ip the caller set. Answer the new frame, null if the stack is full."
	<function>
	| f g nfp ntemps fsize |
	f := frames + (nframes - 1).
	ntemps := self intVal: (self loadRef: m at: CM_NUMTEMPS).
	fsize := self intVal: (self loadRef: m at: CM_FRAMESIZE).
	fsize < (n + ntemps) ifTrue: [fsize := n + ntemps].
	nfp := f fp + f sp - n.
	nfp + fsize > (cstack + (CSTACK_SLOTS - CTX_SLACK)) ifTrue: [^self null].
	f sp: (f sp - n - 1) asInt32.
	g := f + 1.
	g method: m.
	g closure: memory nilOop.
	g ctx: memory nilOop.
	g code: c.
	g fp: nfp.
	g ip: (self methodBcs: m).
	g lits: (self slotsOf: (self literalsOf: m)).
	g sp: (n + ntemps) asInt32.
	n to: n + ntemps - 1 do: [:i | nfp at: i put: memory nilOop].
	ecode >= 0 ifTrue: [nfp at: n put: (self intOop: ecode)].
	nframes := nframes + 1.
	cstackUsed := (nfp + n + ntemps - cstack) asUInt64.
	^g
!
pushFrameEntry: e argc: n
	"pushFrame:argc:code:ecode: for e's method and code, its shape from the cache entry."
	<function>
	| f g nfp ntemps |
	f := frames + (nframes - 1).
	ntemps := e ntemps.
	nfp := f fp + f sp - n.
	nfp + e fsize > (cstack + (CSTACK_SLOTS - CTX_SLACK)) ifTrue: [^self null].
	f sp: (f sp - n - 1) asInt32.
	g := f + 1.
	g method: e method.
	g closure: memory nilOop.
	g ctx: memory nilOop.
	g code: e code.
	g fp: nfp.
	g ip: e bcs.
	g lits: e lits.
	(self unlikely: gc forwardersExist) ifTrue: [g lits: (self slotsOf: (self literalsOf: e method))].
	g sp: n + ntemps.
	n to: n + ntemps - 1 do: [:i | nfp at: i put: memory nilOop].
	nframes := nframes + 1.
	cstackUsed := (nfp + n + ntemps - cstack) asUInt64.
	^g
!
thawFor: code
	"Under a JIT: activeCtx (no frames, registers saved) is married to frame 0, its sender the new base Context, so that its machine code (code) continues it. Answer the frame, null if activeCtx's sender is not a live Context."
	<function>
	| c s sender n m f |
	c := activeCtx.
	s := self slotsOf: c.
	sender := s at: CTX_SENDER.
	(nframes = 0 and: [(self isPtr: sender) and: [sender ~= memory nilOop and: [(self rawClass: sender) = memory clsContext and: [self isInt: ((self slotsOf: sender) at: CTX_PC)]]]]) ifFalse: [^self null].
	n := self intVal: (s at: CTX_STACKP).
	m := s at: CTX_METHOD.
	f := frames + 0.
	cstack at: 0 put: (s at: CTX_RECEIVER).
	(self unlikely: gc forwardersExist) ifTrue: [cstack at: 0 put: (memory follow: (cstack at: 0))].
	libc memcpy: cstack + 1 from: s + CTX_FIXED size: n asUInt64 * 8.
	f method: m.
	f closure: (s at: CTX_CLOSURE).
	f ctx: c.
	f code: code.
	f fp: cstack + 1.
	f ip: (self methodBcs: m) + (self intVal: (s at: CTX_PC)).
	f lits: (self slotsOf: (self literalsOf: m)).
	f sp: n asInt32.
	s at: CTX_SENDER put: (self intOop: 0).
	s at: CTX_STACKP put: (self intOop: 0).
	activeCtx := sender.
	nframes := 1.
	cstackUsed := (n + 1) asUInt64.
	^f
!
cstackLimit
	"The end of the slots a frame may use (frames need CTX_SLACK more)."
	^self cCoerce: cstack + (CSTACK_SLOTS - CTX_SLACK) to: 'uint64_t'
!
cstackBase
	^cstack
!
nframes: n
	nframes := n
!
cstackUsed: n
	cstackUsed := n
!
primBaseIndex: i
	primBaseIndex := i
!
entryFor: aClass selector: aSelector
	"The global method cache's entry for aClass and aSelector, filled if need be; null if aClass does not understand it."
	<function>
	| g |
	g := cache + (self cacheIndexOf: aClass selector: aSelector).
	(g cls = aClass and: [g sel = aSelector]) ifTrue: [^g].
	^self fillCache: aClass selector: aSelector
! !

!Interpreter methodsFor: 'diagnostics'!
printClassName: aClass on: f
	<function>
	| cc n t |
	((self isPtr: aClass) not or: [aClass = memory nilOop]) ifTrue: [libc fputs: 'nil' to: f. ^self].
	cc := self rawClass: aClass.
	(((self numSlots: aClass) > CLS_NAME and: [self isPtr: (self loadRef: aClass at: CLS_NAME)])
		and: [(memory formatOf: (self loadRef: aClass at: CLS_NAME)) >= F_BYTES
		and: [(self rawClass: (self loadRef: aClass at: CLS_NAME)) = (memory special: SO_BYTESYMBOL)]]) ifTrue: [
			n := self loadRef: aClass at: CLS_NAME.
			libc fprintf: f format: '%.*s' with: (memory byteSize: n) asInt32 with: (self cCoerce: (self bytesOf: n) to: 'char *').
			^self].
	((self numSlots: aClass) > META_THISCLASS and: [(self isPtr: (self loadRef: aClass at: META_THISCLASS)) and: [cc ~= aClass]]) ifTrue: [
		t := self loadRef: aClass at: META_THISCLASS.
		(self numSlots: t) > CLS_NAME ifTrue: [
			self printClassName: t on: f.
			libc fputs: ' class' to: f.
			^self]].
	libc fputs: '?' to: f
!
printSymbol: s on: f
	<function>
	((self isPtr: s) and: [(memory formatOf: s) >= F_BYTES])
		ifTrue: [libc fprintf: f format: '%.*s' with: (memory byteSize: s) asInt32 with: (self cCoerce: (self bytesOf: s) to: 'char *')]
		ifFalse: [libc fputs: '?' to: f]
!
printActivation: m receiver: r closure: closure on: f
	<function>
	| rc mc |
	closure ~= memory nilOop ifTrue: [libc fputs: '[] in ' to: f].
	rc := memory classOf: r.
	mc := (self isPtr: m) ifTrue: [self loadRef: m at: CM_CLASS] ifFalse: [memory nilOop].
	self printClassName: rc on: f.
	mc ~= rc ifTrue: [
		libc fputc: $( value to: f.
		self printClassName: mc on: f.
		libc fputc: $) value to: f].
	libc fputs: '>>' to: f.
	self printSymbol: ((self isPtr: m) ifTrue: [self loadRef: m at: CM_SELECTOR] ifFalse: [memory nilOop]) on: f.
	libc fputc: 10 to: f
!
printStack: aContext on: f
	"The frames, then the sender chain; deep stacks show the top 40 and bottom 10 activations."
	<function>
	| depth i c fr2 |
	depth := nframes asInt64.
	i := 0.
	c := aContext.
	[(self isPtr: c) and: [c ~= memory nilOop]] whileTrue: [
		depth := depth + 1.
		c := self loadRef: c at: CTX_SENDER].
	nframes - 1 to: 0 by: -1 do: [:k |
		(depth > 60 and: [i = 40]) ifTrue: [libc fprintf: f format: '... %lld more frames ...
' with: depth - 50].
		(depth <= 60 or: [i < 40 or: [i >= (depth - 10)]]) ifTrue: [
			fr2 := frames + k.
			self printActivation: fr2 method receiver: (fr2 fp at: -1) closure: fr2 closure on: f].
		i := i + 1].
	c := aContext.
	[(self isPtr: c) and: [c ~= memory nilOop]] whileTrue: [
		(depth > 60 and: [i = 40]) ifTrue: [libc fprintf: f format: '... %lld more frames ...
' with: depth - 50].
		(depth <= 60 or: [i < 40 or: [i >= (depth - 10)]]) ifTrue: [
			self printActivation: (self loadRef: c at: CTX_METHOD) receiver: (self loadRef: c at: CTX_RECEIVER) closure: (self loadRef: c at: CTX_CLOSURE) on: f].
		c := self loadRef: c at: CTX_SENDER.
		i := i + 1]
!
fatalBegin
	<function>
	libc fputs: 'samaltak: fatal: ' to: libc stderr
!
fatalEnd
	"After a fatal message: the Smalltalk stack, then exit."
	<noreturn>
	libc fputc: 10 to: libc stderr.
	libc fflush: libc stdout.
	((self isPtr: activeCtx) and: [activeCtx ~= 0 and: [memory specialsOop ~= 0]]) ifTrue: [
		libc fputs: 'Smalltalk stack:
' to: libc stderr.
		self printStack: activeCtx on: libc stderr].
	libc exit: 70
! !

!Interpreter methodsFor: 'arithmetic helpers'!
floatImm: d
	"The SmallFloat64 for d, or 0 if d has none."
	| b e |
	b := self bitsOfDouble: d.
	(b << 1) asUInt64 = 0 ifTrue: [^((b >> 63) << 3) bitOr: 4].
	e := ((b >> 52) bitAnd: 16r7FF) asUInt32.
	(e > 896 and: [e < 1151]) ifTrue: [^((((b << 1) asUInt64 bitOr: b >> 63) - (896 << 53)) << 3) bitOr: 4].
	^0 asUInt64
!
isNumber: o
	"SmallInteger, SmallFloat64 or BoxedFloat64."
	^(o bitAnd: 1) ~= 0 or: [(o bitAnd: 7) = 4 or: [(self isPtr: o) and: [(self rawClass: o) = memory clsBoxedfloat]]]
!
numVal: o
	"o is a number (isNumber:)."
	| b r |
	(o bitAnd: 1) ~= 0 ifTrue: [^(self intVal: o) asFloat].
	(o bitAnd: 7) = 4
		ifTrue: [
			r := o >> 3.
			b := r <= 1 ifTrue: [r << 63] ifFalse: [((r + (896 << 53)) >> 1) bitOr: ((r + (896 << 53)) << 63) asUInt64]]
		ifFalse: [b := (self slotsOf: o) at: 0].
	^self doubleFromBits: b
!
isFloatPair: a and: b
	"Both numbers, at least one a Float (the SmallInteger pair is handled before)."
	^((a bitAnd: b) bitAnd: 1) = 0 and: [(self isNumber: a) and: [self isNumber: b]]
!
floorDiv: a by: b
	| q |
	q := a quo: b.
	((a rem: b) ~= 0 and: [(a < 0) ~= (b < 0)]) ifTrue: [q := q - 1].
	^q
!
floorMod: a by: b
	| r |
	r := a rem: b.
	(r ~= 0 and: [(r < 0) ~= (b < 0)]) ifTrue: [r := r + b].
	^r
!
readInt16: p
	^self int16At: (self cCoerce: p to: 'uint64_t')
! !

!Interpreter methodsFor: 'interpreter registers'!
loadCtx
	| s m |
	s := self slotsOf: activeCtx.
	(self unlikely: gc forwardersExist) ifTrue: [self storeRef: activeCtx at: CTX_RECEIVER put: (memory follow: (s at: CTX_RECEIVER))].
	m := s at: CTX_METHOD.
	lits := self slotsOf: (self literalsOf: m).
	fp := s + CTX_FIXED.
	sp := fp + (self intVal: (s at: CTX_STACKP)) - 1.
	(self isInt: (s at: CTX_PC)) ifFalse: [self fatal: 'resuming a dead context'].
	ip := (self methodBcs: m) + (self intVal: (s at: CTX_PC)).
	fr := self null
!
saveCtx
	| s |
	s := self slotsOf: activeCtx.
	s at: CTX_PC put: (self intOop: ip - (self methodBcs: (s at: CTX_METHOD))).
	s at: CTX_STACKP put: (self intOop: sp - fp + 1)
!
loadFrame
	fr := frames + (nframes - 1).
	lits := fr lits.
	fp := fr fp.
	sp := fp + fr sp - 1.
	ip := fr ip
!
saveFrame
	nframes := (fr - frames) asInt32 + 1.
	fr ip: ip.
	fr sp: (sp - fp + 1) asInt32.
	cstackUsed := (sp + 1 - cstack) asUInt64
!
externalize
	fr notNull ifTrue: [self saveFrame] ifFalse: [self saveCtx]
!
reload
	nframes ~= 0 ifTrue: [self loadFrame] ifFalse: [self loadCtx]
!
toContext
	"Frames into Contexts: from here on the top activation runs in activeCtx."
	fr notNull ifTrue: [
		self saveFrame.
		self materializeAll.
		self loadCtx]
!
push: v
	sp := sp + 1.
	sp value: v
!
checkInterrupts
	(self unlikely: scheduler interruptPendingRelaxed ~= 0) ifTrue: [
		self externalize.
		self interruptSafepoint.
		self reload]
!
checkInterruptsAtEntry
	(self unlikely: scheduler interruptPendingRelaxed ~= 0) ifTrue: [
		self externalize.
		self entrySafepoint.
		self reload]
!
jumpedBack
	"A backward jump: interrupts, then on-stack replacement if the frame's method has code or counts toward it; under a JIT a looping Context may continue in machine code."
	self checkInterrupts.
	fr notNull
		ifTrue: [
			(self unlikely: fr code ~= 0) ifTrue: [
				self externalize.
				jit backJump: fr.
				self reload]]
		ifFalse: [
			(self unlikely: jit enabled) ifTrue: [
				self saveCtx.
				jit resumeContext: true.
				self reload]]
!
jitResumeContext
	"Returned or switched into activeCtx (no frames): under a JIT it may continue in machine code."
	(self unlikely: (fr isNull and: [jit enabled])) ifTrue: [
		self saveCtx.
		jit resumeContext: false.
		self reload]
!
jitResume
	"The top frame (fr) has machine code: continue it there."
	self externalize.
	jit resume: fr.
	self reload
!
jitResumeTop
	(self unlikely: (fr notNull and: [jit isCode: fr code])) ifTrue: [self jitResume]
!
pushFused: b
	"Superinstructions decided at dispatch time (methods keep their bytecodes): a push followed by + - < > <= >= on two SmallIntegers computes right away, and its result goes straight into a following pop-store temp or conditional jump."
	| a nx c j o |
	a := sp value.
	nx := (ip value - 16rA0) asUInt32.
	(nx < 6 and: [self isInt: (a bitAnd: b)]) ifTrue: [
		nx < 2
			ifTrue: [
				nx = 0
					ifTrue: [a asInt64 ifNoOverflowAdd: b asInt64 - 1 do: [:r | ^self fusedStore: r]]
					ifFalse: [a asInt64 ifNoOverflowSub: b asInt64 - 1 do: [:r | ^self fusedStore: r]]]
			ifFalse: [
				c := nx = 2
					ifTrue: [a asInt64 < b asInt64]
					ifFalse: [nx = 3 ifTrue: [a asInt64 > b asInt64] ifFalse: [nx = 4 ifTrue: [a asInt64 <= b asInt64] ifFalse: [a asInt64 >= b asInt64]]].
				ip := ip + 1.
				j := ip value.
				(j = 16r92 or: [j = 16r91]) ifTrue: [
					o := self readInt16: ip + 1.
					sp := sp - 1.
					ip := ip + 3.
					c = (j = 16r91) ifTrue: [
						ip := ip + o.
						o < 0 ifTrue: [self jumpedBack]].
					^self].
				sp value: (self bool: c).
				^self]].
	self push: b
!
fusedStore: r
	"The result of a fused + or -, stored into a following pop-store temp if there is one."
	| n |
	ip := ip + 1.
	n := ip value.
	(n bitAnd: 16rF8) = 16r60 ifTrue: [
		fp at: (n bitAnd: 7) put: r asUInt64.
		sp := sp - 1.
		ip := ip + 1.
		^self].
	sp value: r asUInt64
!
boolResult: c
	"A comparison followed by a conditional jump branches directly (the Boolean is never pushed)."
	| nx o |
	nx := ip value.
	(nx = 16r92 or: [nx = 16r91]) ifTrue: [
		o := self readInt16: ip + 1.
		sp := sp - 2.
		ip := ip + 3.
		c = (nx = 16r91) ifTrue: [
			ip := ip + o.
			o < 0 ifTrue: [self jumpedBack]].
		^self].
	sp := sp - 1.
	sp value: (self bool: c)
!
ret1: v
	"Replace the two operands by v; r := a op b stores into the temp directly."
	| nx |
	nx := ip value.
	(nx bitAnd: 16rF8) = 16r60 ifTrue: [
		fp at: (nx bitAnd: 7) put: v.
		sp := sp - 2.
		ip := ip + 1.
		^self].
	sp := sp - 1.
	sp value: v
! !

!Interpreter methodsFor: 'interpreter loop'!
interpret
	<function>
	| ss |
	ss := memory special: SO_SPECIAL_SELECTORS.
	0 to: 31 do: [:i |
		specialArgc at: i put: (((self isPtr: ss) and: [i asUInt32 < (self numSlots: ss)]) ifTrue: [self selectorArgc: (self loadRef: ss at: i)] ifFalse: [0])].
	cstackUsed := 0.
	nframes := 0.
	self refreshTagClasses.
	self loadCtx.
	self dispatchLoop
!
dispatchLoop
	<dispatchLoop>
	[true] whileTrue: [self dispatch: self nextBytecode]
!
nextBytecode
	ip := ip + 1.
	^(ip - 1) value
!
dispatch: aByte
	<dispatch>
	sim noteBytecode.
	^self perform: (self class handlerTable at: aByte + 1)
!
currentBytecode
	<currentBytecode>
	^ip at: -1
! !

!Interpreter methodsFor: 'bytecodes: pushes and stores'!
badBytecode
	<bytecodes: #()>
	self externalize.
	self fatal: 'unknown bytecode 0x%02X' with: (ip at: -1) asInt32
!
pushTemp
	<bytecodes: #(16r00 16r0F)>
	<specialize>
	self push: (fp at: (self currentBytecode bitAnd: 15))
!
pushInstVar
	<bytecodes: #(16r10 16r1F)>
	<specialize>
	self push: ((self slotsOf: (fp at: -1)) at: (self currentBytecode bitAnd: 15))
!
pushLiteral
	<bytecodes: #(16r20 16r3F)>
	<specialize>
	self push: (lits at: self currentBytecode - 16r20)
!
pushLiteralVariable
	<bytecodes: #(16r40 16r5F)>
	<specialize>
	self push: ((self slotsOf: (lits at: self currentBytecode - 16r40)) at: ASSOC_VALUE)
!
popStoreTemp
	<bytecodes: #(16r60 16r67)>
	<specialize>
	fp at: (self currentBytecode bitAnd: 7) put: sp value.
	sp := sp - 1
!
pushSelf
	<bytecode: 16r70>
	self push: (fp at: -1)
!
pushTrue
	<bytecode: 16r71>
	self push: memory trueOop
!
pushFalse
	<bytecode: 16r72>
	self push: memory falseOop
!
pushNil
	<bytecode: 16r73>
	self push: memory nilOop
!
pushZero
	<bytecode: 16r74>
	self push: (self intOop: 0)
!
pushOne
	<bytecode: 16r75>
	^self pushFused: (self intOop: 1)
!
pushThisContext
	"The top frame's Context (married now), or activeCtx when it runs."
	<bytecode: 16r76>
	fr isNull ifTrue: [^self push: activeCtx].
	self externalize.
	self marry: fr.
	self reload.
	self push: fr ctx
!
dup
	<bytecode: 16r77>
	sp at: 1 put: sp value.
	sp := sp + 1
!
pop
	<bytecode: 16r78>
	sp := sp - 1
!
pushTempX
	<bytecode: 16r80>
	self push: (fp at: ip value).
	ip := ip + 1
!
pushInstVarX
	"Fields 0-2 (sender, pc, stackp) of a married Context come from its frame (Context's methods read them with this long form)."
	<bytecode: 16r81>
	| i v |
	i := ip value.
	ip := ip + 1.
	(self unlikely: (i <= CTX_STACKP and: [self isMarried: (fp at: -1)])) ifTrue: [
		self externalize.
		v := self contextField: i of: (fp at: -1).
		self reload.
		v = 0 ifTrue: [v := (self slotsOf: (fp at: -1)) at: i].
		^self push: v].
	self push: ((self slotsOf: (fp at: -1)) at: i)
!
pushLiteralX
	<bytecode: 16r82>
	self push: (lits at: ip value).
	ip := ip + 1
!
pushLiteralVariableX
	<bytecode: 16r83>
	self push: ((self slotsOf: (lits at: ip value)) at: ASSOC_VALUE).
	ip := ip + 1
!
storeTempX
	<bytecode: 16r84>
	fp at: ip value put: sp value.
	ip := ip + 1
!
storeInstVarX
	<bytecode: 16r85>
	| i r v |
	i := ip value.
	ip := ip + 1.
	r := fp at: -1.
	(self isImmutable: r) ifTrue: [
		v := sp value.
		sp value: r.
		self push: v.
		self push: (self intOop: i + 1).
		sel := memory special: SO_SEL_ATTEMPTTOASSIGN.
		argc := 2.
		^self doSend].
	self storeRef: r at: i put: sp value
!
storeContextInstVarX
	"As 0x85, into a receiver that may be a married Context (Context's methods store with this form): its frames are flushed first, as the store may change how it continues."
	<bytecode: 16r88>
	(self unlikely: (self isMarried: (fp at: -1))) ifTrue: [self toContext].
	^self storeInstVarX
!
storeLiteralVariableX
	<bytecode: 16r86>
	self storeRef: (lits at: ip value) at: ASSOC_VALUE put: sp value.
	ip := ip + 1
!
popStoreTempX
	<bytecode: 16r87>
	fp at: ip value put: sp value.
	ip := ip + 1.
	sp := sp - 1
!
popStoreLiteralVariableX
	<bytecode: 16r89>
	self storeRef: (lits at: ip value) at: ASSOC_VALUE put: sp value.
	ip := ip + 1.
	sp := sp - 1
!
outerTemp
	"push (8A), store (8B), pop-store (8C) a temp of an outer context: depth, index. A married Context's temps are in its frame."
	<bytecodes: #(16r8A 16r8C)>
	| op d i cl c k |
	op := ip at: -1.
	d := (ip at: 0) asInt32.
	i := ip at: 1.
	ip := ip + 2.
	cl := fr notNull ifTrue: [fr closure] ifFalse: [self loadRef: activeCtx at: CTX_CLOSURE].
	c := self loadRef: cl at: BC_OUTER.
	[d := d - 1. d > 0] whileTrue: [c := self loadRef: (self loadRef: c at: CTX_CLOSURE) at: BC_OUTER].
	k := self loadRef: c at: CTX_SENDER.
	(self isInt: k) ifTrue: [
		op = 16r8A
			ifTrue: [self push: ((frames + (self intVal: k)) fp at: i)]
			ifFalse: [
				(frames + (self intVal: k)) fp at: i put: sp value.
				op = 16r8C ifTrue: [sp := sp - 1]].
		^self].
	op = 16r8A
		ifTrue: [self push: (self loadRef: c at: CTX_FIXED + i)]
		ifFalse: [
			self storeRef: c at: CTX_FIXED + i put: sp value.
			op = 16r8C ifTrue: [sp := sp - 1]]
!
pushInteger
	<bytecode: 16r93>
	| v |
	v := self intOop: (self readInt16: ip).
	ip := ip + 2.
	^self pushFused: v
!
makeArray
	<bytecode: 16r94>
	| n a |
	n := ip value.
	ip := ip + 1.
	self externalize.
	a := memory allocObj: memory clsArray format: F_VAR slots: n.
	self reload.
	sp := sp - n.
	libc memcpy: (self slotsOf: a) from: sp + 1 size: n asUInt64 * 8.
	gc rememberIfOld: a.
	self push: a
!
closure
	<bytecode: 16r8F>
	| na nt fs size bc isize b s |
	na := ip at: 0.
	nt := ip at: 1.
	fs := ip at: 2.
	size := ((ip at: 3) asInt64 << 8) bitOr: (ip at: 4).
	ip := ip + 5.
	self externalize.
	fr notNull ifTrue: [self marry: fr].
	bc := memory clsBlock.
	isize := (self intVal: (self loadRef: bc at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	b := memory allocObj: bc format: F_FIXED slots: (isize < 5 ifTrue: [5] ifFalse: [isize]) asUInt32.
	self reload.
	s := self slotsOf: b.
	s at: BC_OUTER put: (fr notNull ifTrue: [fr ctx] ifFalse: [activeCtx]).
	s at: BC_STARTPC put: (self intOop: ip - (self methodBcs: (fr notNull ifTrue: [fr method] ifFalse: [self loadRef: activeCtx at: CTX_METHOD]))).
	s at: BC_NUMARGS put: (self intOop: na).
	s at: BC_NUMTEMPS put: (self intOop: nt).
	s at: BC_FRAMESIZE put: (self intOop: fs).
	gc rememberIfOld: b.
	self push: b.
	ip := ip + size
! !

!Interpreter methodsFor: 'bytecodes: jumps'!
jump
	<bytecode: 16r90>
	| o |
	o := self readInt16: ip.
	ip := ip + 2 + o.
	o < 0 ifTrue: [self jumpedBack]
!
conditionalJump
	"jump if true (91), jump if false (92)"
	<bytecodes: #(16r91 16r92)>
	<specialize>
	| op v o |
	op := self currentBytecode.
	v := sp value.
	sp := sp - 1.
	o := self readInt16: ip.
	ip := ip + 2.
	v = (op = 16r91 ifTrue: [memory trueOop] ifFalse: [memory falseOop])
		ifTrue: [
			ip := ip + o.
			o < 0 ifTrue: [self jumpedBack]]
		ifFalse: [
			v ~= (op = 16r91 ifTrue: [memory falseOop] ifFalse: [memory trueOop]) ifTrue: [
				ip := ip - 3.
				self push: v.
				sel := memory special: SO_SEL_MUSTBEBOOLEAN.
				argc := 0.
				^self doSend]]
! !

!Interpreter methodsFor: 'bytecodes: superinstructions'!
pushTempTempSend
	"push temp a, push temp b, then the special-selector bytecode op (97 a b op)"
	<bytecode: 16r97>
	sp at: 1 put: (fp at: (ip at: 0)).
	sp at: 2 put: (fp at: (ip at: 1)).
	sp := sp + 2.
	ip := ip + 3.
	^self dispatch: (ip at: -1)
!
pushTempLiteralSend
	<bytecode: 16r98>
	sp at: 1 put: (fp at: (ip at: 0)).
	sp at: 2 put: (lits at: (ip at: 1)).
	sp := sp + 2.
	ip := ip + 3.
	^self dispatch: (ip at: -1)
!
pushTempIntegerSend
	<bytecode: 16r99>
	sp at: 1 put: (fp at: (ip at: 0)).
	sp at: 2 put: (self intOop: (ip at: 1) asInt8).
	sp := sp + 2.
	ip := ip + 3.
	^self dispatch: (ip at: -1)
!
fusedArithmetic
	"+ - < > <= >= with the selector in the opcode (9A-9F temp temp, F0-F5 temp literal, F6-FB temp int8): two SmallIntegers finish here, together with a following pop-store temp or conditional jump; anything else continues in the selector's handler."
	<bytecodeList: #(16r9A 16r9B 16r9C 16r9D 16r9E 16r9F 16rF0 16rF1 16rF2 16rF3 16rF4 16rF5 16rF6 16rF7 16rF8 16rF9 16rFA 16rFB)>
	<specialize>
	| op k a b c |
	op := self currentBytecode.
	k := op < 16rA0 ifTrue: [op - 16r9A] ifFalse: [(op - 16rF0) rem: 6].
	a := fp at: (ip at: 0).
	b := op < 16rA0
		ifTrue: [fp at: (ip at: 1)]
		ifFalse: [op < 16rF6 ifTrue: [lits at: (ip at: 1)] ifFalse: [self intOop: (ip at: 1) asInt8]].
	(self isInt: (a bitAnd: b)) ifTrue: [
		k = 0 ifTrue: [a asInt64 ifNoOverflowAdd: b asInt64 - 1 do: [:r | ^self fusedArithmeticResult: r]].
		k = 1 ifTrue: [a asInt64 ifNoOverflowSub: b asInt64 - 1 do: [:r | ^self fusedArithmeticResult: r]].
		k >= 2 ifTrue: [
			c := k = 2
				ifTrue: [a asInt64 < b asInt64]
				ifFalse: [k = 3 ifTrue: [a asInt64 > b asInt64] ifFalse: [k = 4 ifTrue: [a asInt64 <= b asInt64] ifFalse: [a asInt64 >= b asInt64]]].
			^self fusedCompareResult: c]].
	sp at: 1 put: a.
	sp at: 2 put: b.
	sp := sp + 2.
	ip := ip + 2.
	k = 0 ifTrue: [^self add].
	k = 1 ifTrue: [^self subtract].
	k = 2 ifTrue: [^self lessThan].
	k = 3 ifTrue: [^self greaterThan].
	k = 4 ifTrue: [^self lessOrEqual].
	^self greaterOrEqual
!
fusedArithmeticResult: r
	| n |
	n := ip at: 2.
	(n bitAnd: 16rF8) = 16r60 ifTrue: [
		fp at: (n bitAnd: 7) put: r asUInt64.
		ip := ip + 3.
		^self].
	self push: r asUInt64.
	ip := ip + 2
!
fusedCompareResult: c
	| j o |
	j := ip at: 2.
	(j = 16r92 or: [j = 16r91]) ifTrue: [
		o := self readInt16: ip + 3.
		ip := ip + 5.
		c = (j = 16r91) ifTrue: [
			ip := ip + o.
			o < 0 ifTrue: [self jumpedBack]].
		^self].
	self push: (self bool: c).
	ip := ip + 2
! !

!Interpreter methodsFor: 'bytecodes: special selectors'!
specialSend
	"Special selectors without a fast path: a normal send."
	<bytecodes: #(16rA0 16rBF)>
	^self sendSpecial: self currentBytecode - 16rA0
!
add
	<bytecode: 16rA0>
	| a b f |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [a asInt64 ifNoOverflowAdd: b asInt64 - 1 do: [:r | ^self ret1: r asUInt64]].
	(self isFloatPair: a and: b) ifTrue: [
		f := self floatImm: (self numVal: a) + (self numVal: b).
		f ~= 0 ifTrue: [^self ret1: f]].
	^self sendSpecial: 0
!
subtract
	<bytecode: 16rA1>
	| a b f |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [a asInt64 ifNoOverflowSub: b asInt64 - 1 do: [:r | ^self ret1: r asUInt64]].
	(self isFloatPair: a and: b) ifTrue: [
		f := self floatImm: (self numVal: a) - (self numVal: b).
		f ~= 0 ifTrue: [^self ret1: f]].
	^self sendSpecial: 1
!
multiply
	<bytecode: 16rA8>
	| a b f |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [
		(self intVal: a) ifNoOverflowMul: (self intVal: b) do: [:r | (self intFits: r) ifTrue: [^self ret1: (self intOop: r)]]].
	(self isFloatPair: a and: b) ifTrue: [
		f := self floatImm: (self numVal: a) * (self numVal: b).
		f ~= 0 ifTrue: [^self ret1: f]].
	^self specialSend
!
divide
	<bytecode: 16rA9>
	| a b f y |
	a := sp at: -1.
	b := sp value.
	((self isInt: (a bitAnd: b)) and: [(self intVal: b) ~= 0 and: [((self intVal: a) rem: (self intVal: b)) = 0 and: [self intFits: ((self intVal: a) quo: (self intVal: b))]]])
		ifTrue: [^self ret1: (self intOop: ((self intVal: a) quo: (self intVal: b)))].
	(self isFloatPair: a and: b) ifTrue: [
		y := self numVal: b.
		y ~= 0.0 ifTrue: [
			f := self floatImm: (self numVal: a) / y.
			f ~= 0 ifTrue: [^self ret1: f]]].
	^self specialSend
!
compareFor: aSelectorIndex
	"< > <= >= = ~= (special selectors 2-7): SmallIntegers and Floats branch or push right away; answer whether they did."
	| a b x y c |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [
		c := aSelectorIndex = 2 ifTrue: [a asInt64 < b asInt64] ifFalse: [
			aSelectorIndex = 3 ifTrue: [a asInt64 > b asInt64] ifFalse: [
				aSelectorIndex = 4 ifTrue: [a asInt64 <= b asInt64] ifFalse: [
					aSelectorIndex = 5 ifTrue: [a asInt64 >= b asInt64] ifFalse: [
						aSelectorIndex = 6 ifTrue: [a = b] ifFalse: [a ~= b]]]]].
		self boolResult: c.
		^true].
	(self isFloatPair: a and: b) ifTrue: [
		x := self numVal: a.
		y := self numVal: b.
		c := aSelectorIndex = 2 ifTrue: [x < y] ifFalse: [
			aSelectorIndex = 3 ifTrue: [x > y] ifFalse: [
				aSelectorIndex = 4 ifTrue: [x <= y] ifFalse: [
					aSelectorIndex = 5 ifTrue: [x >= y] ifFalse: [
						aSelectorIndex = 6 ifTrue: [x = y] ifFalse: [x ~= y]]]]].
		self boolResult: c.
		^true].
	^false
!
lessThan
	<bytecode: 16rA2>
	(self compareFor: 2) ifFalse: [^self sendSpecial: 2]
!
greaterThan
	<bytecode: 16rA3>
	(self compareFor: 3) ifFalse: [^self sendSpecial: 3]
!
lessOrEqual
	<bytecode: 16rA4>
	(self compareFor: 4) ifFalse: [^self sendSpecial: 4]
!
greaterOrEqual
	<bytecode: 16rA5>
	(self compareFor: 5) ifFalse: [^self sendSpecial: 5]
!
equal
	<bytecode: 16rA6>
	(self compareFor: 6) ifFalse: [^self sendSpecial: 6]
!
notEqual
	<bytecode: 16rA7>
	(self compareFor: 7) ifFalse: [^self sendSpecial: 7]
!
modulo
	<bytecode: 16rAA>
	| a b |
	a := sp at: -1.
	b := sp value.
	((self isInt: (a bitAnd: b)) and: [(self intVal: b) ~= 0]) ifTrue: [
		^self ret1: (self intOop: (self floorMod: (self intVal: a) by: (self intVal: b)))].
	^self specialSend
!
floorDivide
	<bytecode: 16rAD>
	| a b |
	a := sp at: -1.
	b := sp value.
	((self isInt: (a bitAnd: b)) and: [(self intVal: b) ~= 0 and: [self intFits: (self floorDiv: (self intVal: a) by: (self intVal: b))]]) ifTrue: [
		^self ret1: (self intOop: (self floorDiv: (self intVal: a) by: (self intVal: b)))].
	^self specialSend
!
bitShift
	<bytecode: 16rAC>
	| a b v s |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [
		v := self intVal: a.
		s := self intVal: b.
		s >= 0
			ifTrue: [
				(s < 62 and: [(self intFits: (v asUInt64 << s) asInt64) and: [((v asUInt64 << s) asInt64 >> s) = v]]) ifTrue: [
					^self ret1: (self intOop: (v asUInt64 << s) asInt64)].
				v = 0 ifTrue: [^self ret1: a]]
			ifFalse: [^self ret1: (self intOop: (s <= -63 ifTrue: [v < 0 ifTrue: [-1] ifFalse: [0]] ifFalse: [v >> s negated]))]].
	^self specialSend
!
bitAnd
	<bytecode: 16rAE>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [^self ret1: (a bitAnd: b)].
	^self specialSend
!
bitOr
	<bytecode: 16rAF>
	| a b |
	a := sp at: -1.
	b := sp value.
	(self isInt: (a bitAnd: b)) ifTrue: [^self ret1: (a bitOr: b)].
	^self specialSend
!
identical
	<bytecode: 16rB3>
	^self boolResult: (self is: (sp at: -1) identicalTo: sp value)
!
notIdentical
	<bytecode: 16rB4>
	^self boolResult: (self is: (sp at: -1) identicalTo: sp value) not
!
is: a identicalTo: b
	"==: either may be a forwarder (becomeForward:) of the other."
	a = b ifTrue: [^true].
	(self unlikely: gc forwardersExist) ifFalse: [^false].
	^(memory follow: a) = (memory follow: b)
!
bcAt
	<bytecode: 16rB0>
	| a b c k |
	a := sp at: -1.
	b := sp value.
	((self isInt: b) and: [self isPtr: a]) ifTrue: [
		c := self rawClass: a.
		k := ((self intVal: b) - 1) asUInt64.
		c = memory clsArray
			ifTrue: [k < (self numSlots: a) ifTrue: [^self ret1: ((self slotsOf: a) at: k)]]
			ifFalse: [
				c = memory clsBytestring
					ifTrue: [k < (memory byteSize: a) ifTrue: [^self ret1: (self charOop: ((self bytesOf: a) at: k))]]
					ifFalse: [
						c = memory clsBytearray ifTrue: [
							k < (memory byteSize: a) ifTrue: [^self ret1: (self intOop: ((self bytesOf: a) at: k))]]]]].
	^self specialSend
!
bcAtPut
	<bytecode: 16rB1>
	| o v a c k |
	o := sp at: -2.
	v := sp value.
	a := sp at: -1.
	((self isInt: a) and: [(self isPtr: o) and: [(self isImmutable: o) not]]) ifTrue: [
		c := self rawClass: o.
		k := ((self intVal: a) - 1) asUInt64.
		(c = memory clsArray and: [k < (self numSlots: o)]) ifTrue: [
			self storeRef: o at: k put: v.
			^self atPutAnswer: v].
		(c = memory clsBytestring and: [(self isChar: v) and: [(self charVal: v) < 256 and: [k < (memory byteSize: o)]]]) ifTrue: [
			(self bytesOf: o) at: k put: (self charVal: v) asUInt8.
			^self atPutAnswer: v].
		(c = memory clsBytearray and: [(self isInt: v) and: [(self intVal: v) asUInt64 < 256 and: [k < (memory byteSize: o)]]]) ifTrue: [
			(self bytesOf: o) at: k put: (self intVal: v) asUInt8.
			^self atPutAnswer: v]].
	^self specialSend
!
atPutAnswer: v
	sp := sp - 2.
	sp value: v
!
bcSize
	<bytecode: 16rB2>
	| b c |
	b := sp value.
	(self isPtr: b) ifTrue: [
		c := self rawClass: b.
		c = memory clsArray ifTrue: [
			sp value: (self intOop: (self numSlots: b)).
			^self].
		(c = memory clsBytestring or: [c = memory clsBytearray]) ifTrue: [
			sp value: (self intOop: (memory byteSize: b) asInt64).
			^self]].
	^self specialSend
!
bcValue
	"value (B5), value: (B6), value:value: (BE)"
	<bytecodeList: #(16rB5 16rB6 16rBE)>
	<specialize>
	| op n bl |
	op := self currentBytecode.
	n := op = 16rB5 ifTrue: [0] ifFalse: [op = 16rB6 ifTrue: [1] ifFalse: [2]].
	bl := n ~= 0 ifTrue: [sp at: n negated] ifFalse: [sp value].
	((self isPtr: bl) and: [(self rawClass: bl) = memory clsBlock and: [(self loadRef: bl at: BC_NUMARGS) = (self intOop: n)]]) ifTrue: [
		self externalize.
		self blockActivate: n fromArray: false.
		self loadFrame.
		(self unlikely: (jit isCode: fr code)) ifTrue: [
			self jitResume.
			^self].
		self checkInterruptsAtEntry.
		^self].
	^self specialSend
!
bcPoint
	"x (BB), y (BC)"
	<bytecodeList: #(16rBB 16rBC)>
	<specialize>
	| b |
	b := sp value.
	((self isPtr: b) and: [(self rawClass: b) = memory clsPoint]) ifTrue: [
		sp value: ((self slotsOf: b) at: self currentBytecode - 16rBB).
		^self].
	^self specialSend
!
bcClass
	<bytecode: 16rBD>
	| r |
	r := sp value.
	(self unlikely: ((r bitAnd: 7) = 0 and: [((self rawClass: r) bitAnd: 7) ~= 0])) ifTrue: [r := memory follow: r].
	sp value: ((r bitAnd: 7) = 0 ifTrue: [self rawClass: r] ifFalse: [(r bitAnd: 1) ~= 0 ifTrue: [memory clsSmallint] ifFalse: [memory classOf: r]])
! !

!Interpreter methodsFor: 'bytecodes: sends'!
send
	<bytecode: 16r8D>
	sel := lits at: (ip at: 0).
	argc := ip at: 1.
	ip := ip + 2.
	^self doSend
!
sendShort
	"Selector literal 0-15, 0-2 arguments in the opcode."
	<bytecodes: #(16rC0 16rEF)>
	sel := lits at: ((ip at: -1) bitAnd: 15).
	argc := ((ip at: -1) - 16rC0) >> 4.
	^self doSend
!
superSend
	<bytecode: 16r8E>
	sel := lits at: (ip at: 0).
	argc := ip at: 1.
	ip := ip + 2.
	cls := self loadRef: (self loadRef: (fr notNull ifTrue: [fr method] ifFalse: [self loadRef: activeCtx at: CTX_METHOD]) at: CM_CLASS) at: BEH_SUPERCLASS.
	^self doSiteLookup
!
sendSpecial: six
	<label>
	sel := self loadRef: (memory special: SO_SPECIAL_SELECTORS) at: six.
	argc := specialArgc at: six.
	^self doSend
!
doSend
	<label>
	cls := self receiverClass: (sp at: argc negated).
	^self doSiteLookup
!
doSiteLookup
	"Monomorphic inline caches, one per send site (direct-mapped by the site's address), filled from the global cache."
	<label>
	| e g |
	e := icache + (self icacheIndexOf: ip).
	(self unlikely: (e cls ~= cls or: [e sel ~= (self cCoerce: ip to: 'oop')])) ifTrue: [
		g := cache + (self cacheIndexOf: cls selector: sel).
		(g cls ~= cls or: [g sel ~= sel]) ifTrue: [
			g := self fillCache: cls selector: sel.
			g isNull ifTrue: [^self sendDoesNotUnderstand]].
		e copyStructFrom: g.
		e sel: (self cCoerce: ip to: 'oop')].
	^self haveEntry: e
!
doSendGlobal
	"Sends whose selector a site does not determine (doesNotUnderstand:, perform:, cannotReturn:, aboutToReturn:) use the global cache only."
	<label>
	cls := self receiverClass: (sp at: argc negated).
	^self doLookup
!
doLookup
	<label>
	| e |
	e := cache + (self cacheIndexOf: cls selector: sel).
	(self unlikely: (e cls ~= cls or: [e sel ~= sel])) ifTrue: [
		e := self fillCache: cls selector: sel.
		e isNull ifTrue: [^self sendDoesNotUnderstand]].
	^self haveEntry: e
!
haveEntry: e
	<label>
	| r ns ok v |
	newMethod := e method.
	newBcs := e bcs.
	newLits := e lits.
	"a cached method's literal Array may have been forwarded since"
	(self unlikely: gc forwardersExist) ifTrue: [newLits := self slotsOf: (self literalsOf: newMethod)].
	newTemps := e ntemps.
	newFsize := e fsize.
	newEcode := -1.
	newCode := 0.
	(self likely: e kind = 0) ifTrue: [^self activate].
	e kind = K_JIT ifTrue: [
		newCode := e code.
		^self activate].
	(e kind bitAnd: K_LEAF) ~= 0 ifTrue: [
		"no allocation, no GC: the registers stay valid"
		primNargs := argc.
		primBase := sp - argc.
		primStatus := PS_NONE.
		e prim call.
		(self unlikely: (primStatus = PS_FAIL and: [gc forwardersExist and: [self followArgs: argc at: sp - argc]])) ifTrue: [
			primStatus := PS_NONE.
			e prim call].
		(self likely: primStatus = PS_OK) ifTrue: [
			sp := sp - argc.
			sp value: primResult.
			primResult := memory nilOop.
			^self].
		(primErrorCode >= 0 and: [newTemps > 0 and: [((self methodPrim: newMethod) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0]]) ifTrue: [newEcode := primErrorCode].
		^self activate].
	(e kind bitAnd: K_CONST) ~= 0 ifTrue: [
		"(the entry has no primitive: its constant takes that place)"
		((self unlikely: gc forwardersExist) and: [self isLiteralConstant: e qconst]) ifTrue: [^self activate].
		v := e qconst ~= 0 ifTrue: [e qconst] ifFalse: [sp at: argc negated].
		sp := sp - argc.
		sp value: v.
		self checkInterrupts.
		^self].
	(e nset = argc and: [argc ~= 0]) ifTrue: [
		r := sp at: argc negated.
		((self isPtr: r) and: [(self isImmutable: r) not and: [(memory formatOf: r) <= F_FIXVAR]]) ifTrue: [
			ns := self numSlots: r.
			ok := true.
			0 to: argc - 1 do: [:k | ok := ok and: [(e setIvar at: k) < ns]].
			ok ifTrue: [
				0 to: argc - 1 do: [:k | self storeRef: r at: (e setIvar at: k) put: (sp at: argc negated + 1 + k)].
				sp := sp - argc.
				sp value: r.
				self checkInterrupts.
				^self]]].
	(e quick >= 0 and: [argc = 0]) ifTrue: [
		r := sp value.
		((self isPtr: r) and: [(memory formatOf: r) <= F_FIXVAR and: [(self numSlots: r) > e quick asUInt32]]) ifTrue: [
			sp value: (self loadRef: r at: e quick).
			self checkInterrupts.
			^self]].
	primStatus := PS_NONE.
	e prim notNull ifTrue: [
		self externalize.
		primNargs := argc.
		primBase := sp - argc.
		primBaseIndex := primBase - fp.
		epoch := gc gcEpoch.
		tmpRoots at: 0 put: newMethod.
		e prim call.
		(self unlikely: (primStatus = PS_FAIL and: [gc forwardersExist and: [gc gcEpoch = epoch and: [self followArgs: argc at: primBase]]])) ifTrue: [
			primStatus := PS_NONE.
			e prim call].
		primStatus caseOf: {
			[PS_OK] -> [
				gc gcEpoch ~= epoch ifTrue: [self reload].
				sp := sp - argc.
				sp value: primResult.
				primResult := memory nilOop.
				tmpRoots at: 0 put: memory nilOop.
				^self].
			[PS_SWITCHED] -> [
				tmpRoots at: 0 put: memory nilOop.
				self reload.
				"a process switch left no frames: the Process switched to may continue in machine code"
				fr isNull ifTrue: [self jitResumeContext] ifFalse: [self jitResumeTop].
				^self].
			[PS_RESEND] -> [
				tmpRoots at: 0 put: memory nilOop.
				self reload.
				sel := resendSelector.
				argc := resendArgc.
				^self doSendGlobal]}
			otherwise: [
				gc gcEpoch ~= epoch ifTrue: [self reload].
				newMethod := tmpRoots at: 0.
				tmpRoots at: 0 put: memory nilOop.
				newBcs := self methodBcs: newMethod.
				newLits := self slotsOf: (self literalsOf: newMethod).
				(primErrorCode >= 0 and: [newTemps > 0 and: [((self methodPrim: newMethod) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0]]) ifTrue: [newEcode := primErrorCode]]].
	^self activate
!
activate
	"Activate newMethod in a new frame; receiver and arguments are in memory at sp - argc .. sp."
	<label>
	fr isNull ifTrue: [^self activateFromContext].
	newFp := sp - argc + 1.
	(self unlikely: newFp + newFsize > (cstack + (CSTACK_SLOTS - CTX_SLACK))) ifTrue: [
		"stack full: flush the frames into Contexts and start a new stack"
		self saveFrame.
		tmpRoots at: 0 put: newMethod.
		self materializeAll.
		newMethod := tmpRoots at: 0.
		tmpRoots at: 0 put: memory nilOop.
		newBcs := self methodBcs: newMethod.
		newLits := self slotsOf: (self literalsOf: newMethod).
		self loadCtx.
		^self activateFromContext].
	fr ip: ip.
	fr sp: (newFp - 1 - fp) asInt32.
	fr := fr + 1.
	^self enterFrame
!
activateFromContext
	<label>
	| src |
	src := sp - argc.
	cstack at: 0 put: (src at: 0).
	1 to: argc do: [:k | cstack at: k put: (src at: k)].
	sp := src - 1.
	self saveCtx.
	newFp := cstack + 1.
	fr := frames + 0.
	^self enterFrame
!
enterFrame
	<label>
	fr method: newMethod.
	fr closure: memory nilOop.
	fr ctx: memory nilOop.
	fr code: newCode.
	fp := newFp.
	fr fp: newFp.
	ip := newBcs.
	lits := newLits.
	fr lits: newLits.
	sp := newFp + argc - 1.
	1 to: newTemps do: [:k | self push: memory nilOop].
	(self unlikely: newEcode >= 0) ifTrue: [newFp at: argc put: (self intOop: newEcode)].
	(self unlikely: newCode ~= 0) ifTrue: [
		"machine code checks interrupts itself"
		self externalize.
		jit activated: fr.
		self reload.
		^self].
	self checkInterruptsAtEntry
!
sendDoesNotUnderstand
	<label>
	| dnu msg args mc isize |
	(self unlikely: (cls bitAnd: 7) = FWD_TAG) ifTrue: [
		"the receiver is a forwarder (becomeForward:): send to its target"
		sp at: argc negated put: (memory follow: (sp at: argc negated)).
		cls := self receiverClass: (sp at: argc negated).
		^self doLookup].
	dnu := memory special: SO_SEL_DNU.
	sel = dnu ifTrue: [
		self externalize.
		msg := sp value.
		libc fprintf: libc stderr format: 'samaltak: doesNotUnderstand: not understood ('.
		self printClassName: cls on: libc stderr.
		libc fputs: '>>' to: libc stderr.
		self printSymbol: (((self isPtr: msg) and: [(self numSlots: msg) > 0]) ifTrue: [self loadRef: msg at: MSG_SELECTOR] ifFalse: [memory nilOop]) on: libc stderr.
		libc fputs: ')
' to: libc stderr.
		self fatal: 'recursive doesNotUnderstand:'].
	self externalize.
	tmpRoots at: 1 put: sel.
	tmpRoots at: 2 put: cls.
	args := memory allocObj: memory clsArray format: F_VAR slots: argc asUInt32.
	self reload.
	libc memcpy: (self slotsOf: args) from: sp - argc + 1 size: argc asUInt64 * 8.
	gc rememberIfOld: args.
	tmpRoots at: 3 put: args.
	mc := memory clsMessage.
	isize := (self intVal: (self loadRef: mc at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	msg := memory allocObj: mc format: F_FIXED slots: (isize < 2 ifTrue: [2] ifFalse: [isize]) asUInt32.
	self reload.
	self storeRef: msg at: MSG_SELECTOR put: (tmpRoots at: 1).
	self storeRef: msg at: MSG_ARGS put: (tmpRoots at: 3).
	cls := tmpRoots at: 2.
	tmpRoots at: 1 put: memory nilOop.
	tmpRoots at: 2 put: memory nilOop.
	tmpRoots at: 3 put: memory nilOop.
	sp := sp - argc.
	self push: msg.
	sel := memory special: SO_SEL_DNU.
	argc := 1.
	^self doLookup
! !

!Interpreter methodsFor: 'bytecodes: returns'!
returnSelf
	<bytecode: 16r7A>
	self push: (fp at: -1).
	^self returnTop
!
widowIfMarried
	(self unlikely: fr ctx ~= memory nilOop) ifTrue: [
		fr sp: (sp - fp + 1) asInt32.
		self widow: fr]
!
returnTop
	<bytecodeList: #(16r79 16r7B)>
	result := sp value.
	fr notNull ifTrue: [
		fr > (frames + 0) ifTrue: [
			self widowIfMarried.
			sp := fr fp - 1.
			sp value: result.
			fr := fr - 1.
			lits := fr lits.
			fp := fr fp.
			ip := fr ip.
			(self unlikely: (jit isCode: fr code)) ifTrue: [self jitResume].
			^self].
		(self isInt: ((self slotsOf: activeCtx) at: CTX_PC)) ifFalse: [
			"returning into a dead Context: let the Context path send cannotReturn:"
			self saveFrame.
			self materializeAll.
			self loadCtx.
			result := sp value.
			^self contextReturn].
		self widowIfMarried.
		nframes := 0.
		cstackUsed := 0.
		gc rememberIfOld: activeCtx.
		self loadCtx.
		self push: result.
		self jitResumeContext.
		^self].
	^self contextReturn
!
contextReturn
	<label>
	| s sender |
	s := self slotsOf: activeCtx.
	sender := s at: CTX_SENDER.
	(sender = memory nilOop or: [(self isInt: ((self slotsOf: sender) at: CTX_PC)) not]) ifTrue: [^self cannotReturn].
	s at: CTX_PC put: memory nilOop.
	s at: CTX_SENDER put: memory nilOop.
	activeCtx := sender.
	gc rememberIfOld: sender.
	self loadCtx.
	self push: result.
	self jitResumeContext
!
nonLocalReturn
	<bytecode: 16r7C>
	| home c hs next hk h m mk |
	result := sp value.
	fr isNull ifTrue: [^self contextNonLocalReturn].
	self saveFrame.
	home := self ctxHome: (self loadRef: fr closure at: BC_OUTER).
	hk := self loadRef: home at: CTX_SENDER.
	(self isInt: hk) ifTrue: [
		"Home is married to frame h. Its sender (frame h - 1, or activeCtx) dead: cannotReturn:; an unwind marker from the top down to h: aboutToReturn:through: it; else drop frames h and above and return to h's sender."
		h := (self intVal: hk) asInt32.
		(h = 0 and: [(self isInt: ((self slotsOf: activeCtx) at: CTX_PC)) not]) ifTrue: [^self frameNonLocalReturnThrough: memory nilOop].
		m := self unwindFrameFrom: nframes - 1 downTo: h.
		m >= 0 ifTrue: [^self frameNonLocalReturnThrough: (self marry: frames + m)].
		self widowFrom: h to: nframes - 1.
		h = 0 ifTrue: [
			nframes := 0.
			cstackUsed := 0.
			gc rememberIfOld: activeCtx.
			self loadCtx.
			self push: result.
			self jitResumeContext.
			^self].
		nframes := h.
		fr := frames + h.
		sp := fr fp - 1.
		sp value: result.
		fr := fr - 1.
		lits := fr lits.
		fp := fr fp.
		ip := fr ip.
		(self unlikely: (jit isCode: fr code)) ifTrue: [self jitResume].
		^self].
	"Home is a Context below the frames. It or its sender dead, or not on the way: cannotReturn:; the first unwind marker on the way (frames, then Contexts down to home): aboutToReturn:through: it; else drop the frames and return from home directly."
	hs := self loadRef: home at: CTX_SENDER.
	((self isInt: (self loadRef: home at: CTX_PC)) not or: [hs = memory nilOop or: [(self isInt: (self loadRef: hs at: CTX_PC)) not]]) ifTrue: [
		^self frameNonLocalReturnThrough: memory nilOop].
	mk := memory nilOop.
	c := activeCtx.
	[c = memory nilOop ifTrue: [^self frameNonLocalReturnThrough: memory nilOop].
	 (mk = memory nilOop and: [((self methodPrim: (self loadRef: c at: CTX_METHOD)) bitAnd: CM_PRIM_MASK) = PRIM_ENSURE_MARKER]) ifTrue: [mk := c].
	 c ~= home] whileTrue: [c := self loadRef: c at: CTX_SENDER].
	m := self unwindFrameFrom: nframes - 1 downTo: 0.
	m >= 0 ifTrue: [^self frameNonLocalReturnThrough: (self marry: frames + m)].
	mk ~= memory nilOop ifTrue: [^self frameNonLocalReturnThrough: mk].
	self widowFrom: 0 to: nframes - 1.
	nframes := 0.
	cstackUsed := 0.
	c := activeCtx.
	[next := self loadRef: c at: CTX_SENDER.
	 (self slotsOf: c) at: CTX_PC put: memory nilOop.
	 (self slotsOf: c) at: CTX_SENDER put: memory nilOop.
	 c ~= home] whileTrue: [c := next].
	activeCtx := hs.
	gc rememberIfOld: hs.
	self loadCtx.
	self push: result.
	self jitResumeContext
!
unwindFrameFrom: top downTo: h
	"The first of frames top down to h whose method is an unwind marker (ensure:, ifCurtailed:), -1 if none."
	top to: h by: -1 do: [:j | ((self methodPrim: (frames + j) method) bitAnd: CM_PRIM_MASK) = PRIM_ENSURE_MARKER ifTrue: [^j]].
	^-1
!
frameNonLocalReturnThrough: marked
	"The non-local return of the top frame's block (externalized, its result on top) cannot return directly: the block's Context, married now, sends itself cannotReturn: result (marked nil) or aboutToReturn: result through: marked (the first unwind marker's Context)."
	<label>
	| rcv mk |
	tmpRoots at: 1 put: marked.
	rcv := self marry: fr.
	mk := tmpRoots at: 1.
	tmpRoots at: 1 put: memory nilOop.
	self loadFrame.
	result := sp value.
	sp value: rcv.
	self push: result.
	mk = memory nilOop ifTrue: [
		sel := memory special: SO_SEL_CANNOTRETURN.
		argc := 1.
		^self doSendGlobal].
	self push: mk.
	sel := memory special: SO_SEL_ABOUTTORETURN.
	argc := 2.
	^self doSendGlobal
!
contextNonLocalReturn
	<label>
	| home hs c marked next |
	home := self ctxHome: activeCtx.
	(self isInt: (self loadRef: home at: CTX_PC)) ifFalse: [^self cannotReturn].
	hs := self loadRef: home at: CTX_SENDER.
	(hs = memory nilOop or: [(self isInt: (self loadRef: hs at: CTX_PC)) not]) ifTrue: [^self cannotReturn].
	c := activeCtx.
	marked := 0 asUInt64.
	[c = memory nilOop ifTrue: [^self cannotReturn].
	 (marked = 0 and: [((self methodPrim: (self loadRef: c at: CTX_METHOD)) bitAnd: CM_PRIM_MASK) = PRIM_ENSURE_MARKER]) ifTrue: [marked := c].
	 c ~= home] whileTrue: [c := self loadRef: c at: CTX_SENDER].
	marked ~= 0 ifTrue: [
		sp value: activeCtx.
		self push: result.
		self push: marked.
		sel := memory special: SO_SEL_ABOUTTORETURN.
		argc := 2.
		^self doSendGlobal].
	c := activeCtx.
	[next := self loadRef: c at: CTX_SENDER.
	 (self slotsOf: c) at: CTX_PC put: memory nilOop.
	 (self slotsOf: c) at: CTX_SENDER put: memory nilOop.
	 c ~= home] whileTrue: [c := next].
	activeCtx := hs.
	gc rememberIfOld: hs.
	self loadCtx.
	self push: result.
	self jitResumeContext
!
cannotReturn
	<label>
	sp value: activeCtx.
	self push: result.
	sel := memory special: SO_SEL_CANNOTRETURN.
	argc := 1.
	^self doSendGlobal
! !

VMStruct subclass: #Frame
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Frame comment: 'An activation on the interpreter''s C stack: method and closure (GC roots; closure is nil for method activations), fp (first argument/temp in cstack; fp[-1] holds the receiver, as in a Context), ip (saved when not executing; a pc offset during GC), lits (refreshed after every GC), sp (used slots from fp, saved when the frame is not executing), ctx (its married Context, a GC root; nil if none), code (the JitMethod of its method''s machine code; 0 if none; up to JIT_MAX_COUNT while the JIT counts its backward jumps, 1 + count; machine code running the frame keeps pc and sp current at safepoints instead of ip; baseline code sets only code, closure, ctx, fp and a zero pc and sp when it pushes a frame: the runtime derives method, pc, sp, ip and lits of a frame suspended in machine code when it needs them, JitBaselineRuntime). 64 bytes; fields in pairs for stp.'!

!Frame class methodsFor: 'declaring'!
fields
	^#((method oop) (code uint64_t) (closure oop) (ctx oop) (fp 'oop *') (pc int32_t) (sp int32_t) (ip 'uint8_t *') (lits 'oop *'))
! !

VMStruct subclass: #CacheEntry
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

CacheEntry comment: 'A method cache entry. Key cls and sel (in the inline cache, sel holds the send site: ip after the send bytecode). kind 0: activate a frame; else K_PRIM, K_QUICK, K_SETTER, K_CONST, K_LEAF bits, or K_JIT: activate a frame for a method with machine code (code: its JitMethod) or whose activations the JIT counts (code 1); code is what the method had when the entry was filled, installing code does not touch the entries: an activation counted by an entry finds code compiled since (JitRuntime>>codeOf:counting:), one through baseline code the method''s optimized code (JitRuntime>>best:). qconst: the method only answers this constant (or self if 0): no frame (Squeak''s quick returns). quick >= 0: the method is ^instVar quick. nset > 0: a setter storing its arguments into setIvar. bcs and lits are raw pointers into the method, valid until the next GC (which flushes the caches). 64 bytes.'!

!CacheEntry class methodsFor: 'declaring'!
fields
	^#((cls oop) (sel oop) (method oop) (union (prim prim_fn) (qconst oop) (code uint64_t)) (bcs 'uint8_t *') (lits 'oop *')
		(ntemps int32_t) (fsize int32_t) (kind uint8_t) (quick int8_t) (nset uint8_t) (setIvar 'uint8_t[4]'))
! !
