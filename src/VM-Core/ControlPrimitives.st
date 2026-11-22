VMPrimitiveModule subclass: #ControlPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

ControlPrimitives comment: 'Control primitives: perform, closures, processes, timers, samplers, the debugger''s tryPrimitive. Markers (ensure:, on:do:) always fail; Smalltalk finds those contexts by their method''s primitive.'!

!ControlPrimitives methodsFor: 'perform'!
primPerform
	<vmPrimitive: 81 name: 'perform'>
	<notTryable>
	| n b s |
	n := self argCount - 1.
	n < 0 ifTrue: [^self fail].
	b := interpreter primStackBase.
	s := b at: 1.
	(interpreter selectorArgc: s) ~= n ifTrue: [^self fail].
	vmMain c4Enabled
		ifTrue: [0 to: n - 1 do: [:i | interpreter stackSlot: b + 1 + i put: (b at: 2 + i)]]
		ifFalse: [libc memmove: b + 1 from: b + 2 size: n asUInt64 * 8].
	interpreter activeSetStackp: interpreter activeStackp - 1.
	interpreter primResend: s argc: n
!
primPerformWithArguments
	<vmPrimitive: 82 name: 'performWithArguments'>
	<notTryable>
	| b s arr n bi |
	self argCount ~= 2 ifTrue: [^self fail].
	b := interpreter primStackBase.
	s := b at: 1.
	arr := b at: 2.
	((self isPtr: arr) and: [(self rawClass: arr) = memory clsArray]) ifFalse: [^self fail].
	n := (self numSlots: arr) asInt32.
	bi := b - interpreter activeSlots.
	((interpreter selectorArgc: s) ~= n or: [bi + 1 + n > interpreter activeCapacity]) ifTrue: [^self fail].
	0 to: n - 1 do: [:i | interpreter stackSlot: b + 1 + i put: (self loadRef: arr at: i)].
	interpreter activeSetStackp: bi + 1 + n.
	interpreter primResend: s argc: n
! !

!ControlPrimitives methodsFor: 'blocks'!
isBlock: b
	^(self isPtr: b) and: [(self rawClass: b) = memory clsBlock]
!
primClosureValue
	<vmPrimitive: 120 name: 'closureValue'>
	<notTryable>
	| b |
	b := self receiver.
	((self isBlock: b) and: [(self loadRef: b at: BC_NUMARGS) = (self intOop: self argCount)]) ifFalse: [^self fail].
	interpreter activateBlock: self argCount.
	interpreter primSwitched
!
primClosureValueWithArguments
	<vmPrimitive: 121 name: 'closureValueWithArguments'>
	<notTryable>
	| b a |
	b := self receiver.
	a := self arg0.
	((self isBlock: b) and: [(self isPtr: a) and: [(self rawClass: a) = memory clsArray and: [(self loadRef: b at: BC_NUMARGS) = (self intOop: (self numSlots: a))]]]) ifFalse: [^self fail].
	interpreter activateBlockWithArray.
	interpreter primSwitched
!
primEnsureMarker
	<vmPrimitive: 198 name: 'ensureMarker'>
	self fail
!
primOnDoMarker
	<vmPrimitive: 199 name: 'onDoMarker'>
	self fail
! !

!ControlPrimitives methodsFor: 'contexts'!
isContext: c
	^(self isPtr: c) and: [(self rawClass: c) = memory clsContext]
!
primFindNextUnwindContext
	"Context>>findNextUnwindContextUpTo: aContext: the first ensure:/ifCurtailed: activation among my senders before aContext, married if it is a frame; nil if none."
	<vmPrimitive: 195 name: 'findNextUnwindContext'>
	(self isContext: self receiver) ifFalse: [^self fail].
	self answer: (interpreter senderOf: self receiver marker: PRIM_ENSURE_MARKER upTo: self arg0)
!
primTerminateTo
	"Context>>terminateTo: aContext, when I am the top frame's Context and aContext is below me in a frame or a Context (Interpreter>>terminate:to:); else the method's code does it."
	<vmPrimitive: 196 name: 'terminateTo'>
	(self argCount = 1 and: [interpreter terminate: self receiver to: self arg0]) ifFalse: [^self fail].
	self answer: self receiver
!
primNextHandlerContext
	"Context>>nextHandlerContext: the first on:do: activation among my senders, married if it is a frame; nil if none."
	<vmPrimitive: 197 name: 'nextHandlerContext'>
	(self isContext: self receiver) ifFalse: [^self fail].
	self answer: (interpreter senderOf: self receiver marker: PRIM_ONDO_MARKER upTo: memory nilOop)
! !

!ControlPrimitives methodsFor: 'processes'!
isProcess: p
	^(self isPtr: p) and: [(self rawClass: p) = (memory special: SO_PROCESS)]
!
primProcessResume
	<vmPrimitive: 130 name: 'processResume'>
	<notTryable>
	| p ctx |
	p := self receiver.
	(self isProcess: p) ifFalse: [^self fail].
	ctx := self loadRef: p at: PROC_SUSPENDED.
	((self isPtr: ctx) and: [ctx ~= memory nilOop and: [(self rawClass: ctx) = memory clsContext and: [
		(self loadRef: p at: PROC_MYLIST) = memory nilOop and: [p ~= scheduler activeProcess]]]]) ifFalse: [^self fail].
	interpreter primCommit: p.
	scheduler resumeProcess: p
!
primProcessSuspend
	<vmPrimitive: 131 name: 'processSuspend'>
	<notTryable>
	| p l |
	p := self receiver.
	(self isProcess: p) ifFalse: [^self fail].
	p = scheduler activeProcess ifTrue: [
		interpreter primCommit: memory nilOop.
		^scheduler suspendActive].
	l := self loadRef: p at: PROC_MYLIST.
	(l = memory nilOop or: [(scheduler removeLink: p from: l) not]) ifTrue: [^self fail].
	self answer: l
!
primProcessorYield
	<vmPrimitive: 132 name: 'processorYield'>
	<notTryable>
	interpreter primCommit: self receiver.
	scheduler processorYield
!
isSemaphoreLike: s
	^(self isPtr: s) and: [(self numSlots: s) > SEM_EXCESS]
!
primSemaphoreSignal
	<vmPrimitive: 133 name: 'semaphoreSignal'>
	<notTryable>
	| s |
	s := self receiver.
	(self isSemaphoreLike: s) ifFalse: [^self fail].
	interpreter primCommit: s.
	scheduler semaphoreSignal: s
!
primSemaphoreWait
	<vmPrimitive: 134 name: 'semaphoreWait'>
	<notTryable>
	| s |
	s := self receiver.
	(self isSemaphoreLike: s) ifFalse: [^self fail].
	interpreter primCommit: s.
	scheduler semaphoreWait: s
!
primProcessorLastPreempted
	<vmPrimitive: 135 name: 'processorLastPreempted'>
	self answer: scheduler lastPreempted
!
primProcessorRelinquish
	<vmPrimitive: 136 name: 'processorRelinquish'>
	| us |
	us := self arg0.
	(self isInt: us) ifFalse: [^self fail].
	scheduler relinquish: (self intVal: us).
	self answer: self receiver
!
primTimeSlice
	"microseconds -> receiver: equal-priority Processes take turns every so many microseconds while more than one is ready (0: never). The slice's timer runs only while they compete (Scheduler)."
	<vmPrimitive: 146 name: 'timeSlice'>
	(self argCount < 1 or: [(self isInt: (self arg: 0)) not or: [(self intVal: (self arg: 0)) < 0]]) ifTrue: [^self fail].
	scheduler setTimeSlice: (self intVal: (self arg: 0)).
	self answer: self receiver
!
primSignalAtMilliseconds
	<vmPrimitive: 137 name: 'signalAtMilliseconds'>
	| s |
	(self argCount < 2 or: [(self isInt: (self arg: 1)) not]) ifTrue: [^self fail].
	s := self arg: 0.
	((self isPtr: s) and: [s ~= memory nilOop and: [(self numSlots: s) > SEM_EXCESS]])
		ifTrue: [
			self storeRef: memory specialsOop at: SO_TIMER_SEMAPHORE put: s.
			scheduler setTimer: (self intVal: (self arg: 1))]
		ifFalse: [
			self storeRef: memory specialsOop at: SO_TIMER_SEMAPHORE put: memory nilOop.
			scheduler setTimer: -1].
	scheduler requestInterruptCheck.
	self answer: self receiver
!
primSamplerInterval
	<vmPrimitive: 138 name: 'samplerInterval'>
	(self argCount < 2 or: [(self isInt: (self arg: 0)) not or: [(self isInt: (self arg: 1)) not]]) ifTrue: [^self fail].
	scheduler setSampler: ((self intVal: (self arg: 0)) > 0 ifTrue: [self intVal: (self arg: 0)] ifFalse: [0]) semaphore: (self intVal: (self arg: 1)) asInt32.
	self answer: self receiver
!
primAllocationSampling
	<vmPrimitive: 139 name: 'allocationSampling'>
	| n |
	vmMain c4Enabled ifTrue: [^self fail].
	(self argCount < 2 or: [(self isInt: (self arg: 0)) not or: [(self isInt: (self arg: 1)) not]]) ifTrue: [^self fail].
	n := self intVal: (self arg: 0).
	scheduler allocSampleInterval: (n > 0 ifTrue: [n] ifFalse: [0]).
	scheduler allocSampleCountdown: scheduler allocSampleInterval.
	scheduler allocSampleSema: (self intVal: (self arg: 1)) asInt32.
	scheduler allocSampleUnread: false.
	memory resetAllocLimit.
	self answer: self receiver
!
allocationSampleInfo
	<function>
	| a |
	a := memory allocObj: memory clsArray format: F_VAR slots: 2.
	self storeRef: a at: 0 put: scheduler allocSampleClass.
	self storeRef: a at: 1 put: (self intOop: scheduler allocSampleSize).
	^a
!
primAllocationSampleInfo
	<vmPrimitive: 140 name: 'allocationSampleInfo'>
	self answer: self allocationSampleInfo
!
primProcessCpuTime
	"Process>>cpuMicroseconds: cpuTime, settled first (Scheduler>>processCpuTimeUs:)."
	<vmPrimitive: 141 name: 'processCpuTime'>
	| p |
	p := self receiver.
	((self isPtr: p) and: [(self numSlots: p) > PROC_CPUTIME]) ifFalse: [^self fail].
	self answer: (self intOop: (scheduler processCpuTimeUs: p))
!
primProcessStackInto
	"Profiler: aProcess (not active) stackInto: buffer maxDepth: n (n <= 255; buffer an Array of 2n + 1 slots). Writes the innermost n frames bottom-up as method, pc pairs (pc: the block's startpc, 0 for a method) after slot 1, which holds depth + (truncated << 16) of the stack written last. Answers k + (depth << 8) + (truncated << 16) + (innermost frame just activated << 17: the process was preempted at an activation's interrupt check, see Scheduler>>resumeProcess:); k counts the bottom frames equal to the previous content (only if both are truncated or both are not)."
	<vmPrimitive: 142 name: 'processStackInto'>
	| proc buf max meths pcs n fresh ctx cl pc truncated prev k lim |
	(self argCount < 2 or: [(self isInt: (self arg: 1)) not]) ifTrue: [^self fail].
	proc := self receiver.
	buf := self arg: 0.
	max := self intVal: (self arg: 1).
	((self isPtr: proc) and: [(self numSlots: proc) > PROC_CPUTIME and: [proc ~= scheduler activeProcess]]) ifFalse: [^self fail].
	((self isPtr: buf) and: [(self rawClass: buf) = memory clsArray and: [max >= 1 and: [max <= 255 and: [(self numSlots: buf) >= (2 * max + 1) asUInt32]]]]) ifFalse: [^self fail].
	meths := self local: 'oop[255]'.
	pcs := self local: 'int64_t[255]'.
	n := 0.
	fresh := (proc = scheduler lastPreempted and: [scheduler lastPreemptedAtEntry]) ifTrue: [1] ifFalse: [0].
	ctx := self loadRef: proc at: PROC_SUSPENDED.
	[(self isPtr: ctx) and: [ctx ~= memory nilOop and: [n < max]]] whileTrue: [
		cl := self loadRef: ctx at: CTX_CLOSURE.
		pc := ((self isPtr: cl) and: [cl ~= memory nilOop]) ifTrue: [self intVal: (self loadRef: cl at: BC_STARTPC)] ifFalse: [0].
		meths at: n put: (self loadRef: ctx at: CTX_METHOD).
		pcs at: n put: pc.
		n := n + 1.
		ctx := self loadRef: ctx at: CTX_SENDER].
	truncated := ((self isPtr: ctx) and: [ctx ~= memory nilOop]) ifTrue: [1] ifFalse: [0].
	prev := self loadRef: buf at: 0.
	k := 0.
	((self isInt: prev) and: [((self intVal: prev) >> 16 bitAnd: 1) = truncated]) ifTrue: [
		lim := ((self intVal: prev) bitAnd: 16rFFFF) < n ifTrue: [(self intVal: prev) bitAnd: 16rFFFF] ifFalse: [n].
		[k < lim and: [(self loadRef: buf at: 1 + (2 * k)) = (meths at: n - 1 - k) and: [
			(self loadRef: buf at: 2 + (2 * k)) = (self intOop: (pcs at: n - 1 - k))]]] whileTrue: [k := k + 1]].
	k to: n - 1 do: [:j |
		self storeRef: buf at: 1 + (2 * j) put: (meths at: n - 1 - j).
		self storeRef: buf at: 2 + (2 * j) put: (self intOop: (pcs at: n - 1 - j))].
	self storeRef: buf at: 0 put: (self intOop: (n bitOr: truncated asInt64 << 16)).
	self answer: (self intOop: (((k bitOr: n << 8) bitOr: truncated asInt64 << 16) bitOr: fresh asInt64 << 17))
!
primAllocationSampleTake
	"{class. size} of an allocation sample not taken yet (and mark it taken), else nil: lets one sampler process serve the CPU and allocation samplers' common semaphore."
	<vmPrimitive: 143 name: 'allocationSampleTake'>
	scheduler allocSampleUnread ifFalse: [^self answer: memory nilOop].
	scheduler allocSampleUnread: false.
	self answer: self allocationSampleInfo
!
primSamplerTickTake
	"Whether a CPU sampler tick was signalled and not taken yet (and mark it taken): the sampler semaphore may be one that is also signalled for other reasons (the timer process's)."
	<vmPrimitive: 144 name: 'samplerTickTake'>
	| t |
	t := scheduler samplerTickUnread.
	scheduler samplerTickUnread: false.
	self answerBool: t
!
primStackLimit
	"stackLimit [n]: the activations a process may have before the VM sends stackOverflow:; with n (0 = no limit), set it. Answers the previous limit."
	<vmPrimitive: 145 name: 'stackLimit'>
	| n old |
	n := self arg0.
	(self argCount > 0 and: [(self isInt: n) not or: [(self intVal: n) < 0]]) ifTrue: [^self fail].
	old := interpreter stackLimit.
	self argCount > 0 ifTrue: [
		interpreter stackLimit: (self intVal: n).
		interpreter stackCheckAt: 0].
	self answer: (self intOop: old)
!
primTryPrimitive
	"Context>>tryPrimitive: index receiver: r args: array"
	<vmPrimitive: 87 name: 'tryPrimitiveWithArgs'>
	<notTryable>
	| idx arr failed fn bi n b res |
	self argCount ~= 3 ifTrue: [^self fail].
	interpreter flushIfMarried: (self arg: 1).
	idx := self arg: 0.
	arr := self arg: 2.
	failed := memory special: SO_SEL_PRIMITIVEFAILED.
	((self isInt: idx) and: [(self isPtr: arr) and: [(self rawClass: arr) = memory clsArray]]) ifFalse: [^self fail].
	fn := primitives lookup: (self intVal: idx).
	bi := interpreter activeStackp - 1 - 3.
	n := self numSlots: arr.
	(fn isNull or: [(primitives isTryable: (self intVal: idx)) not or: [bi + 1 + n asInt64 > interpreter activeCapacity]]) ifTrue: [^self answer: failed].
	b := interpreter activeSlots + bi.
	interpreter stackSlot: b put: (b at: 2).
	0 to: n asInt64 - 1 do: [:i | interpreter stackSlot: b + 1 + i put: (self loadRef: arr at: i)].
	interpreter activeSetStackp: bi + 1 + n asInt64.
	interpreter setPrimBase: n asInt32.
	interpreter primStatus: PS_NONE.
	fn call.
	res := interpreter primStatus = PS_OK ifTrue: [interpreter primResult] ifFalse: [memory special: SO_SEL_PRIMITIVEFAILED].
	interpreter primResult: memory nilOop.
	interpreter activeSlot: bi put: res.
	interpreter activeSetStackp: bi + 1.
	interpreter primCommitted
! !
