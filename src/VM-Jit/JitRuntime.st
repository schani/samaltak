VMCoreModule subclass: #JitRuntime
	instanceVariableNames: 'sliceTest stubs baseline brt cache asm analysis jitMode jitFlags jitThreshold jitOsrThreshold jitCacheMB cacheOpened flushPending releasePending invalidations stateBlock methodTable tableCount methodCounts youngMethods youngCount youngOverflow mapPcs mapOffsets mapCount sendPushed performFn performArgsFn statCompiled statFailed statBytecodes statCompileUs statCodeBytes statCacheFlushes statEntries statExits statResumes statOsr feedback optimizer jitOptThreshold optCounts copying bottomReturned perfMap c4NativePolls c4NativeYields sliceLoop sliceSelector sliceNameSize sliceHeader sliceStamp sliceTestVersion sliceCacheGeneration c4TierFrame c4OptCompiles c4OptRejects c4OptEntries c4OptReturns c4OptTags c4OptOverflows c4OptInterrupts c4OptRetired c4OptVersionMisses c4OptBytecodes c4OptBytes c4OptUs'
	classVariableNames: 'JIT_BASELINE JIT_FLAG_ACCESS JIT_FLAG_ALLOC JIT_FLAG_ARITH JIT_FLAG_BARRIER JIT_FLAG_BLOCKS JIT_FLAG_CALLS JIT_FLAG_DEOPT JIT_FLAG_EAGER JIT_FLAG_FLOAT JIT_FLAG_FUSE JIT_FLAG_GVN JIT_FLAG_HOIST JIT_FLAG_IC JIT_FLAG_INLINE JIT_FLAG_LAST JIT_FLAG_LIVE JIT_FLAG_MEGA JIT_FLAG_NOTES JIT_FLAG_PIC JIT_FLAG_PRIMS JIT_FLAG_QUICK JIT_FLAG_REGS JIT_FLAG_UNBOX JIT_MAX_COUNT JIT_MAX_MAP JIT_MAX_YOUNG JIT_NONE JIT_OPT JIT_PROLOGUE_BYTES JIT_PROLOGUE_BYTES_X64 JIT_TABLE_SIZE JM_DEAD JM_ENTRY JM_FAILED JM_NOTES JM_OSR'
	package: 'VM-Jit'!

JitRuntime comment: 'The runtime every compiler''s machine code runs on (docs/jit.md, Shared runtime): configuration (--jit, --jit-threshold, --jit-osr, --jit-flags, --jit-cache), the compiled methods (JitMethod headers in the code cache, found by the method''s identity hash; their methods are GC roots, young ones listed for scavenges), the interpreter''s hooks (activated:, resume:, backJump:), the functions machine code calls (interrupt:, interruptAtEntry:, closure:, makeArray:, widow:, writeBarrier:value:), code cache flushes, statistics.

Machine code runs the interpreter''s frames: x19 the Frame, x20 its slots, x21 the receiver, x22 the JitState. Before calling a function here that may allocate, collect, flush frames, switch processes or run Smalltalk, it stores the frame''s pc and sp (the bytecode it is at and the slots in use); the function makes the interpreter''s view canonical (sync:) and answers 0 to continue, 1 to leave to the interpreter (the native stack is dropped; the interpreter reloads the top frame or Context), or for a send the entry of the callee''s code (frame pushed, the caller calls it with blr). The compilers are Arm64Modules (they name registers); they ask me what they need through inline accessors.'!

!JitRuntime class methodsFor: 'declaring'!
declarations
	^#((sliceTest OptSliceTest) (stubs JitStubs) (baseline JitBaselineCompiler) (brt JitBaselineRuntime) (cache CodeCache) (asm JitAssembler) (analysis BytecodeAnalysis)
		(feedback JitFeedback) (optimizer OptRuntime)
		(jitMode int32_t) (jitFlags uint32_t) (jitThreshold int64_t 2) (jitOsrThreshold int64_t 50) (jitOptThreshold int64_t 1000) (jitCacheMB int64_t 64)
		(cacheOpened bool) (flushPending bool) (releasePending bool) (invalidations uint64_t)
		(stateBlock 'JitState[1]')
		(methodTable 'JitMethod *[JIT_TABLE_SIZE]') (tableCount int64_t) (methodCounts 'uint16_t[JIT_TABLE_SIZE]')
		(youngMethods 'JitMethod *[JIT_MAX_YOUNG]') (youngCount int32_t) (youngOverflow bool) (optCounts 'int32_t[JIT_TABLE_SIZE]')
		(mapPcs 'uint32_t[JIT_MAX_MAP]') (mapOffsets 'uint32_t[JIT_MAX_MAP]') (mapCount int32_t)
		(sendPushed int32_t)
		(performFn prim_fn) (performArgsFn prim_fn)
		(statCompiled uint64_t) (statFailed uint64_t) (statBytecodes uint64_t) (statCompileUs uint64_t) (statCodeBytes uint64_t) (statCacheFlushes uint64_t)
		(statEntries uint64_t) (statExits uint64_t) (statResumes uint64_t) (statOsr uint64_t) (copying bool) (bottomReturned bool) (perfMap 'FILE *')
		(c4NativePolls uint64_t) (c4NativeYields uint64_t)
		(sliceLoop bool) (sliceSelector 'const char *') (sliceNameSize uint64_t)
		(sliceHeader 'JitMethod *') (sliceStamp uint64_t)
		(sliceTestVersion 'C4JitVersion[1]') (sliceCacheGeneration uint64_t) (c4TierFrame 'Frame *')
		(c4OptCompiles uint64_t) (c4OptRejects uint64_t) (c4OptEntries uint64_t) (c4OptReturns uint64_t)
		(c4OptTags uint64_t) (c4OptOverflows uint64_t) (c4OptInterrupts uint64_t)
		(c4OptRetired uint64_t) (c4OptVersionMisses uint64_t) (c4OptBytecodes uint64_t) (c4OptBytes uint64_t) (c4OptUs uint64_t))
!
initialize
	JIT_NONE := 0.
	JIT_BASELINE := 1.
	JIT_OPT := 2.
	JIT_FLAG_ARITH := 1.
	JIT_FLAG_FUSE := 2.
	JIT_FLAG_BARRIER := 4.
	JIT_FLAG_NOTES := 8.
	JIT_FLAG_IC := 16.
	JIT_FLAG_PIC := 32.
	JIT_FLAG_MEGA := 64.
	JIT_FLAG_REGS := 128.
	JIT_FLAG_PRIMS := 256.
	JIT_FLAG_ACCESS := 512.
	JIT_FLAG_ALLOC := 1024.
	JIT_FLAG_FLOAT := 2048.
	JIT_FLAG_BLOCKS := 4096.
	JIT_FLAG_QUICK := 8192.
	"the optimizing tier's (also blocks, prims, alloc; then its stress flags)"
	JIT_FLAG_INLINE := 16384.
	JIT_FLAG_UNBOX := 32768.
	JIT_FLAG_CALLS := 65536.
	JIT_FLAG_GVN := 131072.
	JIT_FLAG_EAGER := 262144.
	JIT_FLAG_DEOPT := 524288.
	JIT_FLAG_HOIST := 1048576.
	JIT_FLAG_LIVE := 2097152.
	JIT_FLAG_LAST := JIT_FLAG_LIVE.
	JIT_TABLE_SIZE := 65536.
	JIT_MAX_YOUNG := 4096.
	JIT_MAX_MAP := 32768.
	JIT_PROLOGUE_BYTES := 20.
	"x86: lea, mov, mov (the call pushed the return address)"
	JIT_PROLOGUE_BYTES_X64 := 12.
	JIT_MAX_COUNT := 16rFFFF.
	JM_FAILED := 1.
	JM_DEAD := 2.
	JM_NOTES := 4.
	JM_OSR := 8.
	"baseline: its unchecked entry builds the frame (no quick method or primitive first), optimized code may take it over"
	JM_ENTRY := 16
! !

!JitRuntime methodsFor: 'configuration'!
enabled
	^jitMode ~= JIT_NONE
!
mode
	^jitMode
!
flags
	^jitFlags
!
threshold
	^jitThreshold
!
osrThreshold
	^jitOsrThreshold
!
cacheMB
	^jitCacheMB
!
mode: m
	jitMode := m
!
threshold: n
	jitThreshold := n
!
osrThreshold: n
	jitOsrThreshold := n
!
cacheMB: n
	jitCacheMB := n
!
arith
	"Inline SmallInteger arithmetic and comparisons."
	^(jitFlags bitAnd: JIT_FLAG_ARITH) ~= 0
!
fuse
	"A comparison followed by a conditional jump branches directly."
	^(jitFlags bitAnd: JIT_FLAG_FUSE) ~= 0
!
barrier
	"The store barrier's fast path inline."
	^(jitFlags bitAnd: JIT_FLAG_BARRIER) ~= 0
!
notes
	"Record annotations for all code, not only for code compiled for disassembly."
	^(jitFlags bitAnd: JIT_FLAG_NOTES) ~= 0
!
flag: bit
	^(jitFlags bitAnd: bit) ~= 0
!
inlineFlag
	^JIT_FLAG_INLINE
!
blocksFlag
	^JIT_FLAG_BLOCKS
!
primsFlag
	^JIT_FLAG_PRIMS
!
gvnFlag
	^JIT_FLAG_GVN
!
hoistFlag
	^JIT_FLAG_HOIST
!
liveFlag
	^JIT_FLAG_LIVE
!
unboxFlag
	^JIT_FLAG_UNBOX
!
callsFlag
	^JIT_FLAG_CALLS
!
allocFlag
	^JIT_FLAG_ALLOC
!
eagerFlag
	^JIT_FLAG_EAGER
!
deoptFlag
	^JIT_FLAG_DEOPT
!
optThreshold
	^jitOptThreshold
!
optThreshold: n
	jitOptThreshold := n
!
tiering
	"Legacy optimizer: feedback, direct call redirection, blocks and OSR."
	^jitMode = JIT_OPT and: [vmMain c4Enabled not]
!
allowsC4Opt
	"Build/CLI gate. Destructive handle forwarding is interpreter-only."
	^vmMain headless and: [c4 supported and: [asm isX64 and: [cache canRunCode and: [
		c4 platformFiles not and: [c4 platformSDL not and: [c4 arm64Interpreter not and: [c4 movingForwardEnabled not]]]]]]]
!
c4Optimizing
	^vmMain c4Enabled and: [jitMode = JIT_OPT]
!
optMode
	^JIT_OPT
!
lowerMode
	"The compiler of a method's first machine code."
	^jitMode = JIT_OPT ifTrue: [JIT_BASELINE] ifFalse: [jitMode]
!
ic
	"Baseline: machine-code inline caches (else every send looks up in the runtime)."
	^vmMain c4Enabled not and: [(jitFlags bitAnd: JIT_FLAG_IC) ~= 0]
!
pic
	"Baseline: polymorphic inline caches (else a monomorphic miss goes megamorphic)."
	^(jitFlags bitAnd: JIT_FLAG_PIC) ~= 0
!
mega
	"Baseline: megamorphic sends probe a cache in machine code (else they call the runtime)."
	^(jitFlags bitAnd: JIT_FLAG_MEGA) ~= 0
!
regs
	"Baseline: operands stay in registers between bytecodes (else every push goes to its slot)."
	^(jitFlags bitAnd: JIT_FLAG_REGS) ~= 0
!
prims
	"Baseline: primitives of compiled methods in machine code (else they call the primitive's C function)."
	^(jitFlags bitAnd: JIT_FLAG_PRIMS) ~= 0
!
access
	"Baseline: at: at:put: size class x y inline at send sites."
	^vmMain c4Enabled not and: [(jitFlags bitAnd: JIT_FLAG_ACCESS) ~= 0]
!
float
	"Baseline: Float arithmetic and comparisons inline."
	^vmMain c4Enabled not and: [(jitFlags bitAnd: JIT_FLAG_FLOAT) ~= 0]
!
blocks
	"Baseline: value sends enter the block's code directly (a cache in machine code)."
	^vmMain c4Enabled not and: [(jitFlags bitAnd: JIT_FLAG_BLOCKS) ~= 0]
!
quick
	"Baseline: methods that only answer an instance variable, a constant or self, or set instance variables, run without a frame."
	^vmMain c4Enabled not and: [(jitFlags bitAnd: JIT_FLAG_QUICK) ~= 0]
!
baselineMode
	^JIT_BASELINE
!
entryFlag
	^JM_ENTRY
!
nilTestsInlinable
	^brt nilTestsInlinable
!
floatBitAddressFor: m pc: pc
	^feedback floatBitAddressFor: m pc: pc
!
baselineCode
	"Baseline code runs: --jit baseline, and --jit opt's lower tier."
	^jitMode = JIT_BASELINE or: [jitMode = JIT_OPT]
!
isX64
	"The code generators emit x86-64 (else arm64)."
	^asm isX64
!
prologueBytes
	^asm isX64 ifTrue: [JIT_PROLOGUE_BYTES_X64] ifFalse: [JIT_PROLOGUE_BYTES]
!
modeNamed: name
	"The mode called name, -1 if there is none."
	<function>
	(libc strcmp: name with: 'none') = 0 ifTrue: [^JIT_NONE].
	(libc strcmp: name with: 'opt') = 0 ifTrue: [^JIT_OPT].
	(libc strcmp: name with: 'baseline') = 0 ifTrue: [^JIT_BASELINE].
	^-1
!
modeName: m
	<function>
	m = JIT_OPT ifTrue: [^'opt'].
	m = JIT_BASELINE ifTrue: [^'baseline'].
	^'none'
!
flagNamed: name length: n
	"The bit of the ablation flag called name (n bytes), 0 if there is none."
	(self is: name length: n named: 'arith') ifTrue: [^JIT_FLAG_ARITH].
	(self is: name length: n named: 'fuse') ifTrue: [^JIT_FLAG_FUSE].
	(self is: name length: n named: 'barrier') ifTrue: [^JIT_FLAG_BARRIER].
	(self is: name length: n named: 'notes') ifTrue: [^JIT_FLAG_NOTES].
	(self is: name length: n named: 'ic') ifTrue: [^JIT_FLAG_IC].
	(self is: name length: n named: 'pic') ifTrue: [^JIT_FLAG_PIC].
	(self is: name length: n named: 'mega') ifTrue: [^JIT_FLAG_MEGA].
	(self is: name length: n named: 'regs') ifTrue: [^JIT_FLAG_REGS].
	(self is: name length: n named: 'prims') ifTrue: [^JIT_FLAG_PRIMS].
	(self is: name length: n named: 'access') ifTrue: [^JIT_FLAG_ACCESS].
	(self is: name length: n named: 'alloc') ifTrue: [^JIT_FLAG_ALLOC].
	(self is: name length: n named: 'float') ifTrue: [^JIT_FLAG_FLOAT].
	(self is: name length: n named: 'blocks') ifTrue: [^JIT_FLAG_BLOCKS].
	(self is: name length: n named: 'quick') ifTrue: [^JIT_FLAG_QUICK].
	(self is: name length: n named: 'inline') ifTrue: [^JIT_FLAG_INLINE].
	(self is: name length: n named: 'gvn') ifTrue: [^JIT_FLAG_GVN].
	(self is: name length: n named: 'hoist') ifTrue: [^JIT_FLAG_HOIST].
	(self is: name length: n named: 'live') ifTrue: [^JIT_FLAG_LIVE].
	(self is: name length: n named: 'unbox') ifTrue: [^JIT_FLAG_UNBOX].
	(self is: name length: n named: 'calls') ifTrue: [^JIT_FLAG_CALLS].
	(self is: name length: n named: 'eager') ifTrue: [^JIT_FLAG_EAGER].
	(self is: name length: n named: 'deopt') ifTrue: [^JIT_FLAG_DEOPT].
	^0
!
is: s length: n named: name
	^(libc strlen: name) = n asUInt64 and: [(libc memcmp: s with: name size: n asUInt64) = 0]
!
flagName: bit
	<function>
	bit = JIT_FLAG_ARITH ifTrue: [^'arith'].
	bit = JIT_FLAG_FUSE ifTrue: [^'fuse'].
	bit = JIT_FLAG_BARRIER ifTrue: [^'barrier'].
	bit = JIT_FLAG_NOTES ifTrue: [^'notes'].
	bit = JIT_FLAG_IC ifTrue: [^'ic'].
	bit = JIT_FLAG_PIC ifTrue: [^'pic'].
	bit = JIT_FLAG_MEGA ifTrue: [^'mega'].
	bit = JIT_FLAG_REGS ifTrue: [^'regs'].
	bit = JIT_FLAG_PRIMS ifTrue: [^'prims'].
	bit = JIT_FLAG_ACCESS ifTrue: [^'access'].
	bit = JIT_FLAG_ALLOC ifTrue: [^'alloc'].
	bit = JIT_FLAG_FLOAT ifTrue: [^'float'].
	bit = JIT_FLAG_BLOCKS ifTrue: [^'blocks'].
	bit = JIT_FLAG_QUICK ifTrue: [^'quick'].
	bit = JIT_FLAG_INLINE ifTrue: [^'inline'].
	bit = JIT_FLAG_GVN ifTrue: [^'gvn'].
	bit = JIT_FLAG_HOIST ifTrue: [^'hoist'].
	bit = JIT_FLAG_LIVE ifTrue: [^'live'].
	bit = JIT_FLAG_UNBOX ifTrue: [^'unbox'].
	bit = JIT_FLAG_CALLS ifTrue: [^'calls'].
	bit = JIT_FLAG_EAGER ifTrue: [^'eager'].
	^'deopt'
!
lastFlag
	^JIT_FLAG_LAST
!
parseFlags: s
	"a,b,-c: set a and b, clear c. Answer whether every name is a flag."
	<function>
	| i start bit off |
	i := 0.
	[(s at: i) ~= 0] whileTrue: [
		off := (s at: i) = $- value.
		off ifTrue: [i := i + 1].
		start := i.
		[(s at: i) ~= 0 and: [(s at: i) ~= $, value]] whileTrue: [i := i + 1].
		bit := self flagNamed: s + start length: i - start.
		bit = 0 ifTrue: [^false].
		jitFlags := (off ifTrue: [jitFlags bitClear: bit] ifFalse: [jitFlags bitOr: bit]) asUInt32.
		(s at: i) = $, value ifTrue: [i := i + 1]].
	^true
!
setMode: m
	"Switch compilers: all code is dropped at the next point without machine code on the native stack."
	<function>
	(c4 platformSDL and: [m ~= JIT_NONE]) ifTrue: [^false].
	(vmMain c4Enabled and: [m ~= JIT_NONE and: [c4 arm64Interpreter or: [c4 platformFiles or: [c4 movingForwardEnabled or: [m = JIT_OPT and: [self allowsC4Opt not]]]]]]) ifTrue: [^false].
	(m ~= JIT_NONE and: [self ensureOpen not]) ifTrue: [^false].
	"optimized frames keep the cache from being flushed: they become Contexts"
	self noOptFrames ifFalse: [interpreter materializeAll].
	jitMode := m.
	self dropAllCode.
	interpreter flushMethodCache.
	^true
!
setFlags: f
	<function>
	self noOptFrames ifFalse: [interpreter materializeAll].
	jitFlags := f.
	self dropAllCode
!
defaults
	"Before the command line: --jit opt, threshold 2, OSR after 50 backward jumps, optimization after 1000 entries and backward jumps, 64 MB, every flag but notes and the stress flags eager and deopt."
	<function>
	jitMode := JIT_OPT.
	jitFlags := ((JIT_FLAG_LAST << 1) - 1 bitClear: ((JIT_FLAG_NOTES bitOr: JIT_FLAG_EAGER) bitOr: JIT_FLAG_DEOPT)) asUInt32
!
start
	"After the image is loaded. Where machine code does not run (in the simulator) the JIT stays off, whatever --jit says."
	<function>
	| t |
	t := self primitiveTable.
	0 to: self primitiveCount - 1 do: [:i |
		(libc strcmp: (t + i) name with: 'perform') = 0 ifTrue: [performFn := (t + i) function].
		(libc strcmp: (t + i) name with: 'performWithArguments') = 0 ifTrue: [performArgsFn := (t + i) function]].
	self refreshState.
	cache canRunCode ifFalse: [jitMode := JIT_NONE].
	sliceTest enabled ifTrue: [self configureSlice].
	(jitMode ~= JIT_NONE and: [self ensureOpen not]) ifTrue: [self fatal: 'cannot open a %lld MB code cache' with: jitCacheMB]
!
ensureOpen
	"Map the code cache and generate the stubs, once."
	<function>
	cacheOpened ifTrue: [^true].
	(jitCacheMB < 1 or: [jitCacheMB > 128]) ifTrue: [^false].
	(cache openWithSize: (jitCacheMB << 20) asUInt64) ifFalse: [^false].
	self refreshState.
	asm isX64 ifTrue: [asm setState: self stateAddress].
	stubs generate ifFalse: [^false].
	cache keep.
	cacheOpened := true.
	self openPerfMap.
	^true
!
openPerfMap
	"With SAMALTAK_PERF_MAP set, /tmp/perf-<pid>.map (perf's map of JIT code) names the stubs, then the code as it is made."
	<function>
	| path end |
	(libc getenv: 'SAMALTAK_PERF_MAP') isNull ifTrue: [^self].
	path := self local: 'char[64]'.
	libc snprintf: path size: 64 format: '/tmp/perf-%d.map' with: posix getpid.
	perfMap := libc fopen: path mode: 'w'.
	perfMap isNull ifTrue: [^self].
	0 to: stubs symbolCount - 1 do: [:i |
		end := i + 1 < stubs symbolCount ifTrue: [stubs symbolAddressAt: i + 1] ifFalse: [cache top].
		libc fprintf: perfMap format: '%llx %llx stub:%s
' with: (stubs symbolAddressAt: i) with: end - (stubs symbolAddressAt: i) with: (stubs symbolNameAt: i)].
	libc fflush: perfMap
!
perfMapCode: h mode: md
	"h's code in the perf map: bl:Class>>selector, opt: for optimized code (a block's or a loop's unit with its pc)."
	<function>
	<var: #h type: 'JitMethod *'>
	libc fprintf: perfMap format: '%llx %x ' with: h codeStart with: h codeSize.
	libc fputs: (md = JIT_OPT ifTrue: ['opt:'] ifFalse: ['bl:']) to: perfMap.
	interpreter printClassName: (self loadRef: h method at: CM_CLASS) on: perfMap.
	libc fputs: '>>' to: perfMap.
	interpreter printSymbol: (self loadRef: h method at: CM_SELECTOR) on: perfMap.
	md = JIT_OPT ifTrue: [
		optimizer unitOsr > 0 ifTrue: [libc fprintf: perfMap format: ' [loop %d]' with: optimizer unitEntry].
		(optimizer unitOsr = 0 and: [optimizer unitEntry > 0]) ifTrue: [libc fprintf: perfMap format: ' [block %d]' with: optimizer unitEntry]].
	libc fputc: 10 to: perfMap.
	libc fflush: perfMap
!
perfMapAt: start size: n name: name
	"Other code (a polymorphic inline cache) in the perf map."
	<function>
	<var: #name type: 'const char *'>
	perfMap isNull ifTrue: [^self].
	libc fprintf: perfMap format: '%llx %llx %s
' with: start with: n with: name.
	libc fflush: perfMap
! !

!JitRuntime methodsFor: 'state'!
state
	^stateBlock
!
refreshState
	"The JitState machine code reads through x22."
	<function>
	stateBlock nilOop: memory nilOop.
	stateBlock trueOop: memory trueOop.
	stateBlock falseOop: memory falseOop.
	stateBlock frames: (self cCoerce: interpreter frames to: 'uint64_t').
	stateBlock youngLo: gc youngLo.
	stateBlock youngHi: gc youngHi.
	stateBlock arrayClass: memory clsArray.
	stateBlock pointClass: memory clsPoint.
	stateBlock stackLimitNormal: interpreter cstackEnd - (8 * (analysis maxDepthLimit + CTX_SLACK + 1)) asUInt64.
	stateBlock edenBox: gc edenBoxAddress.
	stateBlock hashBox: memory hashBoxAddress.
	stateBlock lcgMul: 6364136223846793005.
	stateBlock lcgAdd: 1442695040888963407.
	0 to: 7 do: [:t | stateBlock tagClasses at: t put: ((t bitAnd: 1) ~= 0
		ifTrue: [memory clsSmallint]
		ifFalse: [t = 2 ifTrue: [memory clsChar] ifFalse: [t = 4 ifTrue: [memory clsSmallfloat] ifFalse: [memory nilOop]]])].
	stateBlock blockClass: memory clsBlock.
	stateBlock byteStringClass: memory clsBytestring.
	stateBlock byteArrayClass: memory clsBytearray.
	stateBlock boxedFloatClass: memory clsBoxedfloat.
	stateBlock wordArrayClass: (memory special: SO_BITMAP).
	stateBlock byteSymbolClass: (memory special: SO_BYTESYMBOL).
	stateBlock contextClass: memory clsContext.
	brt refresh.
	stateBlock cstackLimit: interpreter cstackLimit.
	self resetStress
!
resetStress
	"--jit-flags deopt: optimized code takes its slow paths every 37th time it passes one of them."
	stateBlock stress <= 0 ifTrue: [stateBlock stress: 37]
!
stateAddress
	^self cCoerce: stateBlock to: 'uint64_t'
! !

!JitRuntime methodsFor: 'functions for the stubs'!
primitiveNumberNamed: name
	"The number of the primitive called name, -1 if there is none."
	<function>
	| t |
	t := self primitiveTable.
	0 to: self primitiveCount - 1 do: [:i | (libc strcmp: (t + i) name with: name) = 0 ifTrue: [^(t + i) number asInt64]].
	^-1
!
nowUs
	^scheduler nowUs
!
optDeoptFunction
	^optimizer deoptFunction
!
optDeoptReturnFunction
	^optimizer deoptReturnFunction
!
optStackFullFunction
	^optimizer stackFullFunction
!
optMakeArrayFunction
	^optimizer makeArrayFunction
!
optReturnFunction
	^optimizer returnFunction
!
interruptFunction
	^self cCoerce: (self functionPointer: #interrupt:) to: 'uint64_t'
!
interruptAtEntryFunction
	^self cCoerce: (self functionPointer: #interruptAtEntry:) to: 'uint64_t'
!
closureFunction
	^self cCoerce: (self functionPointer: #closure:) to: 'uint64_t'
!
contextFunction
	^self cCoerce: (self functionPointer: #pushContext:) to: 'uint64_t'
!
contextFieldFunction
	^self cCoerce: (self functionPointer: #contextField:) to: 'uint64_t'
!
makeArrayFunction
	^self cCoerce: (self functionPointer: #makeArray:) to: 'uint64_t'
!
widowFunction
	^self cCoerce: (self functionPointer: #widow:) to: 'uint64_t'
!
writeBarrierFunction
	^self cCoerce: (self functionPointer: #writeBarrier:value:) to: 'uint64_t'
!
moveFunction
	^self cCoerce: (self functionPointer: #move:from:size:) to: 'uint64_t'
!
tierUpFunction
	^self cCoerce: (self functionPointer: #tierUp:loop:) to: 'uint64_t'
!
exitSyncFunction
	^self cCoerce: (self functionPointer: #exitSync:) to: 'uint64_t'
! !

!JitRuntime methodsFor: 'compiled methods'!
codeAddressOf: m
	"m has machine code compiled code may call directly (pushing its frame itself)."
	<function>
	jitMode = JIT_NONE ifTrue: [^false].
	^self hasCode: (self lookup: m)
!
slotOf: m
	"The index of m's header in the method table, -1 if it has none."
	<function>
	| i h |
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	[(h := methodTable at: i) notNull] whileTrue: [
		h method = m ifTrue: [^i].
		i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1].
	^-1
!
codeChanged: m
	"m's best code changed (optimized, invalidated): calls of its baseline code's unchecked entry follow."
	<function>
	| i |
	i := self slotOf: m.
	i < 0 ifTrue: [^self].
	brt redirect: (methodTable at: i) to: (self best: (methodTable at: i))
!
lookup: m
	"m's header, null if m has none."
	<function>
	| i h |
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	[(h := methodTable at: i) notNull] whileTrue: [
		h method = m ifTrue: [^h].
		i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1].
	^self null
!
insert: h
	| i |
	tableCount >= ((JIT_TABLE_SIZE quo: 4) * 3) ifTrue: [
		flushPending := true.
		^false].
	i := (self hashOf: h method) bitAnd: JIT_TABLE_SIZE - 1.
	[(methodTable at: i) notNull] whileTrue: [i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1].
	methodTable at: i put: h.
	tableCount := tableCount + 1.
	(self isYoung: h method) ifTrue: [
		youngCount < JIT_MAX_YOUNG
			ifTrue: [
				youngMethods at: youngCount put: h.
				youngCount := youngCount + 1]
			ifFalse: [youngOverflow := true]].
	^true
!
hasCode: h
	^h notNull and: [(h flags bitAnd: JM_FAILED) = 0]
!
isCode: c
	"A frame's or cache entry's code: a JitMethod (not 0, nor a count up to JIT_MAX_COUNT)."
	^c > JIT_MAX_COUNT
!
hasNotes: h
	^(h flags bitAnd: JM_NOTES) ~= 0
!
codeTop
	^cache top
!
invalidations
	^invalidations
!
tableCount
	^tableCount
!
tableSize
	^JIT_TABLE_SIZE
!
headerAt: i
	^methodTable at: i
!
requestFlush
	"The code cache is full: flush it at the next interpreter hook."
	flushPending := true
!
codeResetTo: address
	"Drop code compiled from address on (for a disassembly only)."
	brt forgetSlotsFrom: address.
	cache resetTo: address
!
symbolCount
	^stubs symbolCount
!
symbolAddressAt: i
	^stubs symbolAddressAt: i
!
symbolNameAt: i
	^stubs symbolNameAt: i
!
codeOf: m counting: counting
	"m's header if it has code; else, counting an activation, compile it when its count reaches the threshold."
	<function>
	| h i c |
	jitMode = JIT_NONE ifTrue: [^self null].
	h := self lookup: m.
	h notNull ifTrue: [^(self hasCode: h) ifTrue: [self best: h] ifFalse: [self null]].
	counting ifFalse: [^self null].
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	c := (methodCounts at: i) asInt64.
	c >= jitThreshold ifTrue: [^self compileAndInstall: m].
	c < 65535 ifTrue: [methodCounts at: i put: (c + 1) asUInt16].
	^self null
!
cacheCodeFor: m
	"What a method cache entry for m remembers (CacheEntry code): its header, 1 to count its activations, 0 if it is never compiled."
	<function>
	| h |
	jitMode = JIT_NONE ifTrue: [^0].
	h := self lookup: m.
	h isNull ifTrue: [^1].
	^(self hasCode: h) ifTrue: [self cCoerce: (self best: h) to: 'uint64_t'] ifFalse: [0]
!
best: h
	"h's method's optimized code if it has some that may run, else h."
	| o |
	(h opt = 0 or: [self tiering not]) ifTrue: [^h].
	o := self cCoerce: h opt to: 'JitMethod *'.
	((self hasCode: o) and: [(o flags bitAnd: JM_DEAD) = 0]) ifTrue: [^o].
	^h
!
isOptFrame: f
	"f runs optimized code (its pc is a safepoint, its slots are the optimizer's)."
	^(self isCode: f code) and: [(self cCoerce: f code to: 'JitMethod *') mode = JIT_OPT]
!
tableAt: i
	^methodTable at: i
!
isPerform: e
	^(e kind bitAnd: K_PRIM) ~= 0 and: [e prim = performFn or: [e prim = performArgsFn]]
!
isPerformWithArguments: e
	^(e kind bitAnd: K_PRIM) ~= 0 and: [e prim = performArgsFn]
!
sendPushed: n
	sendPushed := n
!
kConst
	^K_CONST
!
kQuick
	^K_QUICK
!
kSetter
	^K_SETTER
!
kLeaf
	^K_LEAF
!
callLeaf: e base: base argc: n
	"Call e's leaf primitive on the n arguments and receiver at base; answer whether it succeeded (its result at base)."
	(interpreter callPrimitive: e prim base: base argc: n) = PS_OK ifFalse: [^false].
	base at: 0 put: interpreter primResult.
	interpreter primResult: memory nilOop.
	^true
!
frameCodeFor: m
	"Frame code of a new activation of m (a block's frame: its home method)."
	jitMode = JIT_NONE ifTrue: [^0 asUInt64].
	^self blockCodeFor: m
!
frameCodeFor: m block: startpc
	"Frame code of a new activation of m's block at startpc: its optimized code if it has some, else its home method's."
	jitMode = JIT_NONE ifTrue: [^0 asUInt64].
	self tiering ifTrue: [^optimizer blockCodeFor: m start: startpc].
	^self blockCodeFor: m
!
blockCodeFor: m
	<function>
	| h |
	h := self lookup: m.
	(self hasCode: h) ifTrue: [^self cCoerce: h to: 'uint64_t'].
	^1
!
compileAndInstall: m
	<function>
	| h |
	self c4NativeBlocked ifTrue: [^self null].
	h := self compile: m mode: self lowerMode notes: self notes.
	h isNull ifTrue: [^self null].
	(self insert: h) ifFalse: [^self null].
	(self hasCode: h) ifFalse: [^self null].
	(self tiering or: [self c4Optimizing]) ifTrue: [
		optCounts at: (self optCountIndex: m) put: (optimizer initialCount: m)].
	^h
!
compileCopy: m mode: md
	"Compile m with notes for a disassembly (codeResetTo: drops the code): what its installed code reports stays feedback."
	| h |
	copying := true.
	h := self compile: m mode: md notes: true.
	copying := false.
	^h
!
copying
	^copying
!
compile: m mode: md notes: wantNotes
	"Compile m with compiler md into the code cache; answer its header (flagged JM_FAILED if md cannot compile it), null if the cache is full."
	<function>
	<var: #h type: 'JitMethod *'>
	| t0 dt start ok h err |
	"Never build a legacy optimizing body on C4, even via a new caller."
	(vmMain c4Enabled and: [md ~= JIT_BASELINE]) ifTrue: [^self null].
	self ensureOpen ifFalse: [^self null].
	vmMain c4Enabled ifTrue: [
		c4 noteCodeBytes: (interpreter methodStorage: m at: CM_BYTECODES)].
	t0 := scheduler pauseCharging.
	start := cache top.
	mapCount := 0.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: wantNotes.
	ok := (analysis analyze: m) and: [
		md caseOf: {
			[JIT_BASELINE] -> [baseline compile: m].
			[JIT_OPT] -> [optimizer compile: m]}
			otherwise: [false]].
	err := asm finish.
	(asm isFull: err) ifTrue: [
		asm recordNotes: false.
		cache endWritingFrom: start size: 0.
		flushPending := true.
		scheduler resumeCharging.
		^self null].
	(ok and: [asm isOK: err])
		ifTrue: [h := self finish: m code: start mode: md]
		ifFalse: [
			statFailed := statFailed + 1.
			h := self failedHeaderFor: m].
	asm recordNotes: false.
	cache endWritingFrom: start size: cache top - start.
	h isNull ifTrue: [
		flushPending := true.
		scheduler resumeCharging.
		^self null].
	(self hasCode: h) ifTrue: [
		statCompiled := statCompiled + 1.
		statBytecodes := statBytecodes + analysis size asUInt64.
		statCodeBytes := statCodeBytes + h codeSize.
		(perfMap notNull and: [copying not]) ifTrue: [self perfMapCode: h mode: md]].
	"CPU time, the VM's: not charged to the running Process"
	dt := scheduler resumeCharging - t0.
	statCompileUs := statCompileUs + dt asUInt64.
	^h
!
finish: m code: start mode: md
	"The code is at start up to asm pc: append the header, the bytecode map and the notes."
	<function>
	| hdr p size n h |
	hdr := (asm pc + 7) bitClear: 7.
	n := asm noteCount.
	size := (hdr - start) + (self sizeof: 'JitMethod') + (8 * mapCount) + (20 * n) + 8.
	md = JIT_OPT ifTrue: [
		size := size + optimizer extraBytes.
		(brt canRegister: optimizer siteCount) ifFalse: [^self null]].
	md = JIT_BASELINE ifTrue: [
		size := size + baseline tablesBytes asUInt64.
		(brt canRegister: (vmMain c4Enabled ifTrue: [1] ifFalse: [baseline oopSlotCount])) ifFalse: [^self null]].
	cache limit - start < size ifTrue: [^self null].
	h := self cCoerce: hdr to: 'JitMethod *'.
	libc memset: h value: 0 size: (self sizeof: 'JitMethod').
	h method: m.
	h mode: md.
	h codeStart: start.
	h codeSize: (asm pc - start) asUInt32.
	h bytecodes: analysis size asUInt32.
	vmMain c4Enabled ifTrue: [brt registerSlot: (self cCoerce: (h fieldAddress: #method) to: 'uint64_t')].
	p := hdr + (self sizeof: 'JitMethod').
	h map: (self cCoerce: p to: 'uint32_t *').
	h mapCount: mapCount asUInt32.
	0 to: mapCount - 1 do: [:i |
		h map at: 2 * i put: (mapPcs at: i).
		h map at: 2 * i + 1 put: (mapOffsets at: i)].
	p := p + (8 * mapCount).
	n > 0 ifTrue: [
		h flags: JM_NOTES.
		h noteCount: n asUInt32.
		h noteValues: (self cCoerce: p to: 'int64_t *').
		h noteTexts: (self cCoerce: p + (8 * n) to: 'uint64_t *').
		h noteOffsets: (self cCoerce: p + (16 * n) to: 'uint32_t *').
		0 to: n - 1 do: [:i |
			h noteValues at: i put: (asm noteValueAt: i).
			h noteTexts at: i put: (self cCoerce: (asm noteTextAt: i) to: 'uint64_t').
			h noteOffsets at: i put: (asm noteOffsetAt: i)].
		p := p + (20 * n)].
	md = JIT_OPT ifTrue: [p := optimizer writeExtra: h at: p].
	md = JIT_BASELINE ifTrue: [
		p := baseline writeTables: h at: p.
		(baseline plainEntry and: [asm isX64 not or: [(self uint8At: h uentry) = 16r48]]) ifTrue: [h flags: (h flags bitOr: JM_ENTRY)]].
	self sortMap: h.
	h start: start + (self mapOffsetOf: h pc: (md = JIT_OPT ifTrue: [optimizer unitEntry] ifFalse: [0])).
	cache allocate: p - start.
	^h
!
sortMap: h
	"Resumption points emitted out of line come late: put the map in pc order."
	| i pc off |
	1 to: h mapCount asInt64 - 1 do: [:k |
		pc := h map at: 2 * k.
		off := h map at: 2 * k + 1.
		i := k - 1.
		[i >= 0 and: [(h map at: 2 * i) > pc]] whileTrue: [
			h map at: 2 * i + 2 put: (h map at: 2 * i).
			h map at: 2 * i + 3 put: (h map at: 2 * i + 1).
			i := i - 1].
		h map at: 2 * i + 2 put: pc.
		h map at: 2 * i + 3 put: off]
!
failedHeaderFor: m
	"A header without code: m is not compiled again until the next flush."
	<function>
	| hdr h |
	hdr := (cache top + 7) bitClear: 7.
	cache limit - cache top < ((self sizeof: 'JitMethod') + 8) ifTrue: [^self null].
	h := self cCoerce: hdr to: 'JitMethod *'.
	libc memset: h value: 0 size: (self sizeof: 'JitMethod').
	h method: m.
	h flags: JM_FAILED.
	vmMain c4Enabled ifTrue: [
		(brt canRegister: 1) ifFalse: [^self null].
		brt registerSlot: (self cCoerce: (h fieldAddress: #method) to: 'uint64_t')].
	cache allocate: hdr + (self sizeof: 'JitMethod') - cache top.
	^h
!
counterAddressFor: m
	"Legacy counts share a hash slot. C4 counts belong to a baseline header;
	its insertion slot cannot change until the whole cache is flushed."
	(self tiering or: [self c4Optimizing and: [self c4Candidate: m]]) ifFalse: [^0 asUInt64].
	^self cCoerce: optCounts + (self optCountIndex: m) to: 'uint64_t'
!
optCountIndex: m
	| i h |
	i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
	self c4Optimizing ifTrue: [
		[(h := methodTable at: i) notNull and: [h method ~= m]] whileTrue: [
			i := (i + 1) bitAnd: JIT_TABLE_SIZE - 1]].
	^i
!
counterFor: m put: n
	optCounts at: ((self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1) put: n asInt32
!
noteResume: pc at: offset
	"The compiler: the interpreter may continue the frame at pc in the code at offset."
	mapCount < JIT_MAX_MAP ifTrue: [
		mapPcs at: mapCount put: pc asUInt32.
		mapOffsets at: mapCount put: offset asUInt32.
		mapCount := mapCount + 1]
!
mapOffsetOf: h pc: pc
	"The code offset of resumption point pc, -1 if pc is none (binary search: the map is in pc order)."
	<function>
	| lo hi mid v |
	lo := 0.
	hi := h mapCount asInt64 - 1.
	[lo <= hi] whileTrue: [
		mid := (lo + hi) quo: 2.
		v := (h map at: 2 * mid) asInt64.
		v = pc ifTrue: [^(h map at: 2 * mid + 1) asInt64].
		v < pc ifTrue: [lo := mid + 1] ifFalse: [hi := mid - 1]].
	^-1
!
addressFor: f
	"Where f's machine code continues at f's ip, 0 if nowhere."
	<function>
	| h off |
	(self isCode: f code) ifFalse: [^0].
	h := self cCoerce: f code to: 'JitMethod *'.
	h mode = JIT_OPT ifTrue: [^optimizer resume: f].
	off := self mapOffsetOf: h pc: f ip - (interpreter methodBcs: f method).
	off < 0 ifTrue: [^0].
	^h codeStart + off asUInt64
!
kill: h
	"h's code must not run again: frames using it go back to the interpreter for good."
	<function>
	| f |
	cache beginWriting.
	h method: memory nilOop.
	h flags: (h flags bitOr: JM_DEAD).
	cache endWriting.
	h mode ~= JIT_OPT ifTrue: [
		0 to: interpreter nframes - 1 do: [:i |
			f := interpreter frames + i.
			f code = (self cCoerce: h to: 'uint64_t') ifTrue: [f code: 0]]].
	(h opt ~= 0 and: [h mode ~= JIT_OPT]) ifTrue: [self kill: (self cCoerce: h opt to: 'JitMethod *')].
	invalidations := invalidations + 1.
	interpreter flushMethodCache.
	self baselineCode ifTrue: [brt unlinkAll]
!
methodsChanged
	"Smalltalk changed method dictionaries (flushMethodCache): inline caches relink."
	<function>
	(self baselineCode and: [cacheOpened and: [vmMain c4Enabled not]]) ifTrue: [
		brt unlinkAll.
		brt nilTestsChanged: 0]
!
methodsChangedFor: sel
	<function>
	(self baselineCode and: [cacheOpened and: [vmMain c4Enabled not]]) ifTrue: [
		brt unlinkSelector: sel.
		brt nilTestsChanged: sel]
!
dropAllCode
	"Code that may be wrong now: running code leaves at its next runtime call, all code is dropped before Smalltalk goes on."
	flushPending := true.
	invalidations := invalidations + 1
!
releaseMemory
	"Drop all machine code and give back the memory it took: the code, the type feedback it was compiled from, the optimizer's scratch areas. At the next flush (prepare), when no machine code runs. For an idle program: what runs again is compiled again."
	<export>
	cacheOpened ifFalse: [^self].
	releasePending := true.
	self dropAllCode
!
flushCode
	"Drop all machine code (none is on the native stack): frames continue in the interpreter."
	<function>
	| used |
	sliceTest enabled ifTrue: [self retireSlice].
	used := cacheOpened ifTrue: [cache top] ifFalse: [0].
	0 to: interpreter nframes - 1 do: [:i | (interpreter frames + i) code: (jitMode = JIT_NONE ifTrue: [0] ifFalse: [1])].
	libc memset: methodTable value: 0 size: 8 * JIT_TABLE_SIZE.
	libc memset: methodCounts value: 0 size: 2 * JIT_TABLE_SIZE.
	tableCount := 0.
	c4OptRetired := c4OptCompiles.
	youngCount := 0.
	youngOverflow := false.
	cacheOpened ifTrue: [cache flush].
	optimizer flushed.
	brt flushed.
	interpreter flushMethodCache.
	flushPending := false.
	statCacheFlushes := statCacheFlushes + 1.
	releasePending ifTrue: [
		releasePending := false.
		cacheOpened ifTrue: [gc releasePages: (self cCoerce: cache top to: 'void *') size: used - cache top].
		feedback release.
		brt release.
		optimizer release]
!
prepare
	"Interpreter side, no machine code on the native stack: apply a pending flush (not while optimized frames wait for callees: their metadata is in the cache)."
	self c4NativeBlocked ifTrue: [^self].
	(flushPending and: [self noOptFrames]) ifTrue: [self flushCode]
!
noOptFrames
	<function>
	0 to: interpreter nframes - 1 do: [:i | (self isOptFrame: interpreter frames + i) ifTrue: [^false]].
	^true
! !

!JitRuntime methodsFor: 'C4 baseline'!
c4Baseline
	^vmMain c4Enabled
!
c4NativeBlocked
	^vmMain c4Enabled and: [interpreter c4Publishing]
!
c4PrepareOutsideNative
	"Pending flushes must also retire roots with the tier switched off.
	Do not free code at a checkpoint taken from native code."
	(flushPending and: [stateBlock baseRecord = 0]) ifTrue: [self prepare]
!
c4ForwardingOutsideNative
	"The native entry stubs publish their base record before any machine
	bytecode executes. The wrapper clears it on every native return."
	^stateBlock baseRecord = 0
!
c4ForwardingInstalled
	"Do not resume any old compiled body after destructive forwarding.
	prepare defers cache release while an arm-time code root is unread;
	every native entry is gated during that interval."
	<function>
	(self baselineCode or: [sliceTest enabled and: [sliceHeader notNull]]) ifTrue: [
		self dropAllCode.
		self prepare]
!
c4BytecodeWillWrite: obj
	<function>
	(vmMain c4Enabled and: [c4 isCodeBytes: obj]) ifTrue: [
		self c4ForwardingOutsideNative ifFalse: [self fatal: 'C4 byte write on a native stack'].
		self c4ForwardingInstalled]
!
c4MaxCodeRoots
	^brt c4MaxCodeRoots
!
c4CodeRootCount
	^brt c4CodeRootCount
!
c4CodeRootAt: i
	^brt c4CodeRootAt: i
!
c4NativeCheckpoint
	"Called only after sync: all frames and live oop slots are now canonical."
	<function>
	stateBlock c4Budget: 64.
	c4NativePolls := c4NativePolls + 1.
	interpreter c4CanonicalCheckpoint.
	self c4NativeBlocked ifTrue: [c4NativeYields := c4NativeYields + 1]
!
reportC4
	<function>
	libc fprintf: libc stderr format: 'c4-jit: checkpoints=%llu publishing_exits=%llu
' with: c4NativePolls with: c4NativeYields.
	(c4OptCompiles + c4OptRejects > 0 or: [self c4Optimizing]) ifTrue: [
		libc fprintf: libc stderr format: 'c4-opt: compiled=%llu rejected=%llu entries=%llu returns=%llu' with: c4OptCompiles with: c4OptRejects with: c4OptEntries with: c4OptReturns.
		libc fprintf: libc stderr format: ' tag_exits=%llu overflow_exits=%llu interrupt_exits=%llu' with: c4OptTags with: c4OptOverflows with: c4OptInterrupts.
		libc fprintf: libc stderr format: ' retired=%llu version_misses=%llu
' with: c4OptRetired with: c4OptVersionMisses]
! !

!JitRuntime methodsFor: 'garbage collection'!
youngRoots: fn
	"Scavenges: the methods of headers compiled while their method was young, the young objects baseline code refers to."
	<function>
	feedback youngRoots: fn.
	optimizer youngRoots: fn.
	cacheOpened ifFalse: [^self].
	cache beginWriting.
	youngOverflow
		ifTrue: [self methodRoots: fn]
		ifFalse: [0 to: youngCount - 1 do: [:i | fn call: ((youngMethods at: i) fieldAddress: #method)]].
	brt youngRoots: fn.
	cache endWriting
!
methodRoots: fn
	| h |
	0 to: JIT_TABLE_SIZE - 1 do: [:i |
		h := methodTable at: i.
		h notNull ifTrue: [fn call: (h fieldAddress: #method)]]
!
allRoots: fn
	"Full GCs and become: every header's method and every object in the code."
	<function>
	self visitAllRoots: fn updating: true
!
readRoots: fn
	"Same roots, with no writes, cache invalidation or write-protection changes."
	<function>
	self visitAllRoots: fn updating: false
!
visitAllRoots: fn updating: updating
	feedback allRoots: fn.
	optimizer allRoots: fn updating: updating.
	cacheOpened ifFalse: [^self].
	updating ifTrue: [cache beginWriting].
	updating ifTrue: [brt allRoots: fn] ifFalse: [brt codeRoots: fn].
	tableCount ~= 0 ifTrue: [self methodRoots: fn].
	updating ifTrue: [cache endWriting]
!
afterGC
	"Objects moved: refresh the JitState, forget young headers whose methods are old now."
	<function>
	| n |
	self refreshState.
	brt afterGC.
	n := 0.
	youngOverflow ifFalse: [
		0 to: youngCount - 1 do: [:i |
			(self isYoung: (youngMethods at: i) method) ifTrue: [
				youngMethods at: n put: (youngMethods at: i).
				n := n + 1]].
		youngCount := n asInt32]
!
classChanged
	"An object got another class in place (changeClassTo:). Optimized code may know the old one (it made the object, or guarded it before): all of it is invalidated, and frames in it leave where they next return or check."
	<function>
	self tiering ifTrue: [optimizer invalidateAll]
!
optMethodsChanged: sel
	"Smalltalk changed a method dictionary (for selector sel; nil: any): optimized code relying on it is invalidated."
	<function>
	self c4Optimizing ifTrue: [
		c4OptCompiles ~= c4OptRetired ifTrue: [self dropAllCode].
		^self].
	self tiering ifFalse: [^self].
	sel = memory nilOop
		ifTrue: [optimizer invalidateAll]
		ifFalse: [optimizer invalidateSelector: sel]
!
materializeOpt: f
	"materializeAll meets optimized frame f."
	<function>
	optimizer materialize: f
!
rawBaseOf: f
	"Optimized frame f's raw slots (doubles' IEEE bits, no oops) are from this one up to rawTopOf: f."
	^optimizer rawBaseOf: f
!
rawTopOf: f
	^optimizer rawTopOf: f
!
becomeMethod: from
	"from is about to be replaced: if it is a compiled method, its code must not run for its successor."
	<function>
	| h |
	"C4 keeps header oops frozen during root publication."
	vmMain c4Enabled ifTrue: [^self dropAllCode].
	jitMode = JIT_NONE ifTrue: [^self].
	"optimized code embeds classes and methods it speculated on"
	self tiering ifTrue: [optimizer invalidateAll].
	h := self lookup: from.
	h notNull ifTrue: [self kill: h].
	(self baselineCode and: [cacheOpened]) ifTrue: [brt unlinkAll]
!
headersValid: valid
	<function>
	| h |
	0 to: JIT_TABLE_SIZE - 1 do: [:i |
		h := methodTable at: i.
		(h notNull and: [(valid call: h method) not]) ifTrue: [^false].
		(h notNull and: [h opt ~= 0 and: [(optimizer headerValid: (self cCoerce: h opt to: 'JitMethod *') with: valid) not]]) ifTrue: [^false]].
	^true
! !

!JitRuntime methodsFor: 'interpreter hooks'!
activated: f
	"The interpreter pushed f (top frame) for a method whose cache entry has code or counts activations."
	<function>
	| h |
	self c4NativeBlocked ifTrue: [
		scheduler interruptPendingRelaxed ~= 0 ifTrue: [interpreter entrySafepoint].
		^self].
	self prepare.
	h := (self isCode: f code)
		ifTrue: [self best: (self cCoerce: f code to: 'JitMethod *')]
		ifFalse: [self codeOf: f method counting: true].
	h isNull ifTrue: [
		f code: (jitMode = JIT_NONE ifTrue: [0] ifFalse: [1]).
		(vmMain c4Enabled and: [scheduler interruptPendingRelaxed ~= 0]) ifTrue: [interpreter entrySafepoint].
		^self].
	f code: (self cCoerce: h to: 'uint64_t').
	self run: f at: h start
!
resume: f
	"The interpreter is about to continue f (top frame, f code a header) at f's ip."
	<function>
	| a |
	self c4NativeBlocked ifTrue: [^self].
	self prepare.
	a := self addressFor: f.
	a = 0 ifTrue: [^self].
	statResumes := statResumes + 1.
	self run: f at: a
!
backJump: f
	"The interpreter jumped back in f (top frame, f code not 0): on-stack replacement."
	<function>
	| n h a |
	self c4NativeBlocked ifTrue: [^self].
	self prepare.
	f code = 0 ifTrue: [^self].
	(self isCode: f code) ifFalse: [
		n := f code.
		n < jitOsrThreshold asUInt64 ifTrue: [
			n < JIT_MAX_COUNT ifTrue: [f code: n + 1].
			^self].
		h := self lookup: f method.
		h isNull ifTrue: [h := self compileAndInstall: f method].
		(self hasCode: h) ifFalse: [
			f code: 0.
			^self].
		f code: (self cCoerce: h to: 'uint64_t')].
	a := self addressFor: f.
	a = 0 ifTrue: [^self].
	statOsr := statOsr + 1.
	self run: f at: a
!
resumeContext: looping
	"The interpreter runs activeCtx without frames, returned into it or (looping) jumping back in it: it may continue in machine code (contextEntry:)."
	<function>
	| a |
	self c4NativeBlocked ifTrue: [^self].
	self prepare.
	a := self contextEntry: looping.
	a = 0 ifTrue: [^self].
	looping ifTrue: [statOsr := statOsr + 1] ifFalse: [statResumes := statResumes + 1].
	self run: interpreter frames at: a
!
contextEntry: looping
	"If activeCtx's method has machine code for its pc, marry activeCtx to frame 0 (Interpreter>>thawFor:) and answer where the code continues, else 0. A looping Context's method is compiled after --jit-osr backward jumps."
	<function>
	| c m h pc off i n |
	c := interpreter activeCtx.
	m := self loadRef: c at: CTX_METHOD.
	pc := self loadRef: c at: CTX_PC.
	(self isInt: pc) ifFalse: [^0].
	h := self lookup: m.
	(h isNull and: [looping]) ifTrue: [
		i := (self hashOf: m) bitAnd: JIT_TABLE_SIZE - 1.
		n := (methodCounts at: i) asInt64.
		n >= jitOsrThreshold
			ifTrue: [h := self compileAndInstall: m]
			ifFalse: [methodCounts at: i put: (n + 1) asUInt16]].
	(self hasCode: h) ifFalse: [^0].
	off := self mapOffsetOf: h pc: (self intVal: pc).
	off < 0 ifTrue: [^0].
	(interpreter thawFor: (self cCoerce: h to: 'uint64_t')) isNull ifTrue: [^0].
	^h codeStart + off asUInt64
!
run: frame at: address
	"Run machine code from address in frame (top frame, state externalized) until it leaves; on return into a frame with code continue there, and on optimized code's return into activeCtx (OptRuntime>>returnBottom:index:) as the interpreter's returns do (contextEntry:)."
	| r f a g |
	f := frame.
	a := address.
	vmMain c4Enabled ifTrue: [stateBlock c4Budget: 64].
	[statEntries := statEntries + 1.
	 (self baselineCode and: [(self isOptFrame: f) not]) ifTrue: [
		"baseline returns from frame 0 (into a Context) take the married frame's slow path; machine code keeps pc and sp"
		(f = interpreter frames and: [f ctx = memory nilOop]) ifTrue: [interpreter marry: f].
		f pc: 0.
		f sp: 0].
	 r := (self cCoerce: stubs blEnterAddress to: 'int64_t (*)(Frame *, uint64_t)') call: f with: a.
	 vmMain c4Enabled ifTrue: [stateBlock baseRecord: 0].
	 r = 0
		ifTrue: [
			statExits := statExits + 1.
			(vmMain c4Enabled and: [c4TierFrame notNull]) ifTrue: [^self finishC4TierUp].
			bottomReturned ifFalse: [^self].
			bottomReturned := false.
			self c4NativeBlocked ifTrue: [^self].
			self prepare.
			a := self contextEntry: false.
			g := interpreter frames]
		ifFalse: [
			g := self cCoerce: (r bitClear: 7) to: 'Frame *'.
			(r bitAnd: 7) = 0 ifTrue: [
				statExits := statExits + 1.
				^interpreter syncFrame: g].
			g sp: g sp + 1.
			(self isOptFrame: g) ifFalse: [g pc: (g ip - (interpreter methodBcs: g method)) asInt32].
			interpreter syncFrame: g.
			a := self addressFor: g].
	 (a = 0 or: [self c4NativeBlocked]) ifTrue: [^self].
	 statResumes := statResumes + 1.
	 f := g] repeat
! !

!JitRuntime methodsFor: 'called by machine code'!
sync: f
	"Machine code stored f's pc and sp: f is the top frame (baseline frames suspended below it become canonical too)."
	self baselineCode ifTrue: [
		f method: (self cCoerce: f code to: 'JitMethod *') method.
		brt canonicalizeBelow: f].
	interpreter syncFrame: f.
	f lits: (self slotsOf: (self loadRef: f method at: CM_LITERALS))
!
canonicalizeBelow: f
	"Baseline frames suspended below f (top, its pc and sp stored) become canonical: the runtime may collect, flush or leave."
	self baselineCode ifTrue: [brt canonicalizeBelow: f]
!
noteBottomReturn
	"Optimized code's bottom frame returned into activeCtx and leaves (OptRuntime>>returnBottom:index:): run:at: continues activeCtx."
	bottomReturned := true
!
exitSync: f
	"The exit stub: f stored its pc and sp and leaves to the interpreter."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	self sync: f.
	^0
!
leave: f pc: pc sp: n
	"Leave to the interpreter, which continues f at pc with n slots."
	<function>
	<var: #n type: 'int64_t'>
	(self isOptFrame: f) ifTrue: [^optimizer leave: f after: false].
	f pc: pc asInt32.
	f sp: n asInt32.
	interpreter syncFrame: f.
	^1
!
leaveAfter: f pc: pc sp: n
	"Leave to the interpreter after a send completed (its result pushed)."
	(self isOptFrame: f) ifTrue: [^optimizer leave: f after: true].
	^self leave: f pc: pc sp: n
!
specialFast: k base: base
	"The interpreter's fast paths of special selector k with receiver and arguments at base: the result, or 0."
	<function>
	| a b x y c i v fx fy |
	a := base at: 0.
	b := base at: 1.
	k = 19 ifTrue: [^self bool: a = b].
	k = 20 ifTrue: [^self bool: a ~= b].
	k = 29 ifTrue: [^memory classOf: a].
	(k = 27 or: [k = 28]) ifTrue: [
		((self isPtr: a) and: [(self rawClass: a) = memory clsPoint]) ifTrue: [^self loadRef: a at: k - 27].
		^0].
	k = 18 ifTrue: [
		(self isPtr: a) ifTrue: [
			(self rawClass: a) = memory clsArray ifTrue: [^self intOop: (self numSlots: a)].
			((self rawClass: a) = memory clsBytestring or: [(self rawClass: a) = memory clsBytearray]) ifTrue: [^self intOop: (memory byteSize: a) asInt64]].
		^0].
	k = 16 ifTrue: [
		((self isInt: b) and: [self isPtr: a]) ifTrue: [
			i := ((self intVal: b) - 1) asUInt64.
			((self rawClass: a) = memory clsArray and: [i < (self numSlots: a)]) ifTrue: [^self loadRef: a at: i].
			((self rawClass: a) = memory clsBytestring and: [i < (memory byteSize: a)]) ifTrue: [^self charOop: ((self bytesOf: a) at: i)].
			((self rawClass: a) = memory clsBytearray and: [i < (memory byteSize: a)]) ifTrue: [^self intOop: ((self bytesOf: a) at: i)]].
		^0].
	k = 17 ifTrue: [
		v := base at: 2.
		((self isInt: b) and: [(self isPtr: a) and: [(self isImmutable: a) not]]) ifTrue: [
			i := ((self intVal: b) - 1) asUInt64.
			((self rawClass: a) = memory clsArray and: [i < (self numSlots: a)]) ifTrue: [
				self storeRef: a at: i put: v.
				^v].
			((self rawClass: a) = memory clsBytestring and: [(self isChar: v) and: [(self charVal: v) < 256 and: [i < (memory byteSize: a)]]]) ifTrue: [
				(self bytesOf: a) at: i put: (self charVal: v) asUInt8.
				^v].
			((self rawClass: a) = memory clsBytearray and: [(self isInt: v) and: [(self intVal: v) asUInt64 < 256 and: [i < (memory byteSize: a)]]]) ifTrue: [
				(self bytesOf: a) at: i put: (self intVal: v) asUInt8.
				^v]].
		^0].
	(k > 15 or: [k = 11]) ifTrue: [^0].
	(self isInt: (a bitAnd: b)) ifTrue: [
		x := self intVal: a.
		y := self intVal: b.
		k = 0 ifTrue: [x ifNoOverflowAdd: y do: [:r | (self intFits: r) ifTrue: [^self intOop: r]]. ^0].
		k = 1 ifTrue: [x ifNoOverflowSub: y do: [:r | (self intFits: r) ifTrue: [^self intOop: r]]. ^0].
		(k >= 2 and: [k <= 7]) ifTrue: [
			c := k = 2 ifTrue: [x < y] ifFalse: [
				k = 3 ifTrue: [x > y] ifFalse: [
					k = 4 ifTrue: [x <= y] ifFalse: [
						k = 5 ifTrue: [x >= y] ifFalse: [
							k = 6 ifTrue: [x = y] ifFalse: [x ~= y]]]]].
			^self bool: c].
		k = 8 ifTrue: [x ifNoOverflowMul: y do: [:r | (self intFits: r) ifTrue: [^self intOop: r]]. ^0].
		k = 9 ifTrue: [
			(y ~= 0 and: [(x rem: y) = 0 and: [self intFits: (x quo: y)]]) ifTrue: [^self intOop: (x quo: y)].
			^0].
		k = 10 ifTrue: [
			y ~= 0 ifTrue: [^self intOop: (interpreter floorMod: x by: y)].
			^0].
		k = 13 ifTrue: [
			(y ~= 0 and: [self intFits: (interpreter floorDiv: x by: y)]) ifTrue: [^self intOop: (interpreter floorDiv: x by: y)].
			^0].
		k = 12 ifTrue: [
			y >= 0 ifTrue: [
				(y < 62 and: [(self intFits: (x asUInt64 << y) asInt64) and: [((x asUInt64 << y) asInt64 >> y) = x]]) ifTrue: [^self intOop: (x asUInt64 << y) asInt64].
				x = 0 ifTrue: [^a].
				^0].
			^self intOop: (y <= -63 ifTrue: [x < 0 ifTrue: [-1] ifFalse: [0]] ifFalse: [x >> y negated])].
		k = 14 ifTrue: [^a bitAnd: b].
		k = 15 ifTrue: [^a bitOr: b].
		^0].
	k > 9 ifTrue: [^0].
	(interpreter isFloatPair: a and: b) ifFalse: [^0].
	fx := interpreter numVal: a.
	fy := interpreter numVal: b.
	(k >= 2 and: [k <= 7]) ifTrue: [
		c := k = 2 ifTrue: [fx < fy] ifFalse: [
			k = 3 ifTrue: [fx > fy] ifFalse: [
				k = 4 ifTrue: [fx <= fy] ifFalse: [
					k = 5 ifTrue: [fx >= fy] ifFalse: [
						k = 6 ifTrue: [fx = fy] ifFalse: [fx ~= fy]]]]].
		^self bool: c].
	k = 0 ifTrue: [^interpreter floatImm: fx + fy].
	k = 1 ifTrue: [^interpreter floatImm: fx - fy].
	k = 8 ifTrue: [^interpreter floatImm: fx * fy].
	(k = 9 and: [fy ~= 0.0]) ifTrue: [^interpreter floatImm: fx / fy].
	^0
!
dispatch: e frame: f argc: n
	"f's ip is past the send, f's sp counts receiver and arguments."
	<function>
	<var: #h type: 'JitMethod *'>
	| kind base m status ecode moved inv r v ns ok g h |
	kind := e kind.
	base := f fp + (f sp - n - 1).
	m := e method.
	kind = K_JIT ifTrue: [
		(self isCode: e code) ifFalse: [^self activate: m frame: f argc: n ecode: -1 code: 0].
		h := self best: (self cCoerce: e code to: 'JitMethod *').
		g := interpreter pushFrameEntry: e argc: n.
		g isNull ifTrue: [^self leave: f pc: f pc sp: f sp - sendPushed].
		g code: (self cCoerce: h to: 'uint64_t').
		^h start - self prologueBytes].
	kind = 0 ifTrue: [^self activate: m frame: f argc: n ecode: -1 code: 0].
	(kind bitAnd: K_LEAF) ~= 0 ifTrue: [
		status := interpreter callPrimitive: e prim base: base argc: n.
		status = PS_OK ifTrue: [
			base at: 0 put: interpreter primResult.
			interpreter primResult: memory nilOop.
			^0].
		^self activate: m frame: f argc: n ecode: (self errorCodeFor: m) code: 0].
	(kind bitAnd: K_CONST) ~= 0 ifTrue: [
		e qconst ~= 0 ifTrue: [base at: 0 put: e qconst].
		^0].
	(e nset = n and: [n ~= 0]) ifTrue: [
		r := base at: 0.
		((self isPtr: r) and: [(self isImmutable: r) not and: [(memory formatOf: r) <= F_FIXVAR]]) ifTrue: [
			ns := self numSlots: r.
			ok := true.
			0 to: n - 1 do: [:k | ok := ok and: [(e setIvar at: k) < ns]].
			ok ifTrue: [
				0 to: n - 1 do: [:k | self storeRef: r at: (e setIvar at: k) put: (base at: 1 + k)].
				^0]]].
	(e quick >= 0 and: [n = 0]) ifTrue: [
		r := base at: 0.
		((self isPtr: r) and: [(memory formatOf: r) <= F_FIXVAR and: [(self numSlots: r) > e quick asUInt32]]) ifTrue: [
			base at: 0 put: (self loadRef: r at: e quick).
			^0]].
	(kind bitAnd: K_PRIM) = 0 ifTrue: [^self activate: m frame: f argc: n ecode: -1 code: 0].
	moved := interpreter frameEpoch.
	inv := invalidations.
	interpreter tmpRoots at: 0 put: m.
	status := interpreter callPrimitive: e prim base: base argc: n.
	m := interpreter tmpRoots at: 0.
	interpreter tmpRoots at: 0 put: memory nilOop.
	status = PS_OK ifTrue: [
		v := interpreter primResult.
		interpreter primResult: memory nilOop.
		interpreter frameEpoch ~= moved ifTrue: [
			interpreter primCommit: v.
			^1].
		base at: 0 put: v.
		inv ~= invalidations ifTrue: [^self leaveAfter: f pc: (f ip - (interpreter methodBcs: f method)) sp: f sp - n].
		^0].
	status = PS_SWITCHED ifTrue: [
		interpreter frameEpoch ~= moved ifTrue: [^1].
		interpreter nframes > ((f - interpreter frames) + 1) ifTrue: [^self entryOfTop].
		inv ~= invalidations ifTrue: [^self leaveAfter: f pc: (f ip - (interpreter methodBcs: f method)) sp: f sp].
		^0].
	status = PS_RESEND ifTrue: [self fatal: 'a resending primitive called from machine code'].
	interpreter frameEpoch ~= moved ifTrue: [self fatal: 'a failing primitive flushed the frames'].
	^self activate: m frame: f argc: n ecode: (self errorCodeFor: m) code: 0
!
errorCodeFor: m
	"The error code a failed primitive leaves in m's first temp, -1 if none."
	(interpreter primErrorCode >= 0 and: [(self intVal: (self loadRef: m at: CM_NUMTEMPS)) > 0 and: [((interpreter methodPrim: m) bitAnd: CM_PRIM_ERROR_FLAG) ~= 0]]) ifTrue: [^interpreter primErrorCode].
	^-1
!
activate: m frame: f argc: n ecode: ecode code: hint
	"Push a frame for m (receiver and arguments at the top of f, f's ip at the continuation, its pc still at the send): answer its entry, or 1 to leave for the interpreter to run it. If the stack is full the interpreter executes the send again."
	<function>
	<var: #hint type: 'uint64_t'>
	| h g |
	h := (self isCode: hint) ifTrue: [self cCoerce: hint to: 'JitMethod *'] ifFalse: [self codeOf: m counting: true].
	g := interpreter pushFrame: m argc: n code: ((self hasCode: h) ifTrue: [self cCoerce: h to: 'uint64_t'] ifFalse: [self frameCodeFor: m]) ecode: ecode.
	g isNull ifTrue: [^self leave: f pc: f pc sp: f sp - sendPushed].
	(self hasCode: h) ifFalse: [^1].
	^h start - self prologueBytes
!
entryOfTop
	"A frame was pushed above the caller: its entry if it has code, else 1."
	<function>
	| top a |
	top := interpreter frames + (interpreter nframes - 1).
	a := self addressFor: top.
	a = 0 ifTrue: [^1].
	^a - self prologueBytes
!
interrupt: f
	"An interrupt check at a loop head, a backward jump or after a send; f's pc and sp are where the interpreter would continue."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	^self interruptFrame: f atEntry: false
!
interruptAtEntry: f
	"An interrupt check at a method or block entry: f was just activated."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	^self interruptFrame: f atEntry: true
!
interruptFrame: f atEntry: atEntry
	<function>
	<var: #f type: 'Frame *'>
	<var: #atEntry type: 'bool'>
	<returns: 'uint64_t'>
	| moved inv |
	self sync: f.
	self resetStress.
	moved := interpreter frameEpoch.
	inv := invalidations.
	vmMain c4Enabled ifTrue: [self c4NativeCheckpoint].
	(vmMain c4Enabled not or: [scheduler interruptPendingRelaxed ~= 0]) ifTrue: [
		atEntry ifTrue: [interpreter entrySafepoint] ifFalse: [interpreter interruptSafepoint]].
	(interpreter frameEpoch ~= moved or: [inv ~= invalidations or: [self c4NativeBlocked]]) ifTrue: [^1].
	^0
!
closure: f
	"0x8F at f's pc: push a BlockClosure whose outerContext is f's (married) Context."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	| p na nt fs b bc isize s startpc |
	self sync: f.
	p := f ip.
	na := p at: 1.
	nt := p at: 2.
	fs := p at: 3.
	startpc := f pc + 6.
	interpreter marry: f.
	bc := memory clsBlock.
	isize := (self intVal: (self loadRef: bc at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	b := memory allocObj: bc format: F_FIXED slots: (isize < 5 ifTrue: [5] ifFalse: [isize]) asUInt32.
	vmMain c4Enabled
		ifTrue: [
			self storeRef: b at: BC_OUTER put: f ctx.
			self storeRef: b at: BC_STARTPC put: (self intOop: startpc).
			self storeRef: b at: BC_NUMARGS put: (self intOop: na).
			self storeRef: b at: BC_NUMTEMPS put: (self intOop: nt).
			self storeRef: b at: BC_FRAMESIZE put: (self intOop: fs)]
		ifFalse: [
			s := self slotsOf: b.
			s at: BC_OUTER put: f ctx.
			s at: BC_STARTPC put: (self intOop: startpc).
			s at: BC_NUMARGS put: (self intOop: na).
			s at: BC_NUMTEMPS put: (self intOop: nt).
			s at: BC_FRAMESIZE put: (self intOop: fs).
			gc rememberIfOld: b].
	f fp at: f sp put: b.
	^0
!
pushContext: f
	"0x76 at f's pc: push f's Context, married now."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	self sync: f.
	interpreter marry: f.
	f fp at: f sp put: f ctx.
	^0
!
contextField: f
	"0x81 i (i <= 2: sender, pc, stackp) at f's pc, the receiver a married Context: push the field, which its frame answers (Interpreter>>contextField:of:). 1 if the frames were flushed instead: the interpreter executes the instruction again."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	| v |
	self sync: f.
	v := interpreter contextField: (f ip at: 1) asInt64 of: (f fp at: -1).
	v = 0 ifTrue: [^1].
	f fp at: f sp put: v.
	^0
!
makeArray: f
	"0x94 n at f's pc: the top n slots into a new Array."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	| n |
	self sync: f.
	n := f ip at: 1.
	f fp at: f sp - n put: (self newArray: n from: f fp + f sp - n).
	^0
!
newArray: n from: p
	"An Array of the n oops from p, slots the collector sees (it may run)."
	<function>
	<var: #n type: 'uint32_t'>
	<var: #p type: 'oop *'>
	<returns: 'oop'>
	| a |
	a := memory allocObj: memory clsArray format: F_VAR slots: n.
	memory copyRefs: a at: 0 fromBuffer: p count: n.
	^a
!
optSendFrom: f ret: ret
	"A call of optimized code that no machine code takes (OptRuntime>>sendFrom:ret:)."
	^optimizer sendFrom: f ret: ret
!
optUnitEntryOf: m start: s
	"The block stub's entry of m's block at startpc s if it has optimized code that may run, else 0."
	self tiering ifFalse: [^0 asUInt64].
	^optimizer unitEntryOf: m start: s
!
optHeaderCount
	^optimizer headerCount
!
optHeaderAt: i
	^optimizer headerAt: i
!
tierUp: f loop: loop
	"The lower tier's counter for f's method ran out at f's pc (a method entry, or a backward jump if loop ~= 0; f's pc and sp stored): answer 0 to go on, 1 to leave, or where f continues in optimized code."
	<function>
	<var: #f type: 'Frame *'>
	<var: #loop type: 'int64_t'>
	<returns: 'uint64_t'>
	self sync: f.
	self c4Optimizing ifTrue: [
		(loop ~= 0 or: [flushPending or: [self c4NativeBlocked or: [f ctx ~= memory nilOop or: [
			f closure ~= memory nilOop or: [memory rootCount ~= 0]]]]]) ifTrue: [
			optCounts at: (self optCountIndex: f method) put: 1.
			^0].
		c4TierFrame := f.
		^1].
	self tiering ifFalse: [^1].
	^optimizer tierUp: f loop: loop
!
widow: f
	"f returns and is married: its Context keeps its slots."
	<function>
	<var: #f type: 'Frame *'>
	<returns: 'uint64_t'>
	interpreter widow: f.
	^0
!
writeBarrier: o value: v
	"v was stored into o."
	<function>
	<var: #o type: 'oop'>
	<var: #v type: 'oop'>
	<returns: 'uint64_t'>
	((self isPtr: v) and: [(self isYoung: v) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]])
		ifTrue: [gc remember: o].
	^0
!
move: dst from: src size: n
	"The copy stub's long copies: memmove."
	<function>
	<var: #dst type: 'uint64_t'>
	<var: #src type: 'uint64_t'>
	<var: #n type: 'uint64_t'>
	libc memmove: (self ptr: dst) from: (self ptr: src) size: n
! !

!JitRuntime methodsFor: 'statistics'!
statCompiled
	^statCompiled
!
statFailed
	^statFailed
!
statBytecodes
	^statBytecodes
!
statCompileUs
	^statCompileUs
!
statCodeBytes
	^statCodeBytes
!
statCacheFlushes
	^statCacheFlushes
!
statEntries
	^statEntries
!
statExits
	^statExits
!
statResumes
	^statResumes
!
statOsr
	^statOsr
!
optStat: i
	"The optimizing tier's counters (OptRuntime>>stat:)."
	<function>
	vmMain c4Enabled ifTrue: [
		^(i caseOf: {
			[0] -> [c4OptCompiles].
			[1] -> [c4OptBytecodes].
			[2] -> [c4OptUs].
			[3] -> [c4OptBytes].
			[4] -> [c4OptTags + c4OptOverflows].
			[6] -> [c4OptRetired].
			[7] -> [c4OptRejects]}
			otherwise: [0 asUInt64]) asInt64].
	^optimizer stat: i
!
brtFeedbackSitesOf: m
	"Baseline type feedback (JitBaselineRuntime>>feedbackSitesOf: and friends) for other modules."
	^brt feedbackSitesOf: m
!
brtFeedbackPcOf: m site: i
	^brt feedbackPcOf: m site: i
!
brtFeedbackSelectorOf: m site: i
	^brt feedbackSelectorOf: m site: i
!
brtFeedbackStateOf: m site: i
	^brt feedbackStateOf: m site: i
!
brtFeedbackCasesOf: m site: i
	^brt feedbackCasesOf: m site: i
!
brtFeedbackClassOf: m site: i case: j
	^brt feedbackClassOf: m site: i case: j
!
brtFeedbackTargetOf: m site: i case: j
	^brt feedbackTargetOf: m site: i case: j
!
baselineStat: i
	"Counters of baseline code (JitBaselineRuntime): misses, links, polymorphic caches, megamorphic sites, block cache misses, C primitive calls, frame walks."
	<function>
	^i caseOf: {
		[0] -> [brt statMisses]. [1] -> [brt statLinks]. [2] -> [brt statPics]. [3] -> [brt statMegas].
		[4] -> [brt statBlockMisses]. [5] -> [brt statPrimCalls]}
		otherwise: [brt statWalks]
! !

VMStruct subclass: #JitState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitState comment: 'What machine code reads through x22: nil, true and false and the classes inline paths check (refreshed after every GC; tagClasses by the low 3 bits of an immediate), the frames array, the native stack pointer jit_enter left (exits reset it), the young space''s bounds (the store barrier). Baseline code also uses: stackLimitNormal (a callee''s fp at or above it takes the entry''s slow path: the C stack is nearly full), baseFrame and baseRecord (the first Frame and native frame record of the activations since jit_enter: frame f''s record is baseRecord - (f - baseFrame) / 4), the addresses of eden''s top and limit (edenBox) and of the identity hash generator (hashBox, with its multiplier and increment), the megamorphic and block caches (JitBaselineRuntime), and words the runtime answers through (result, ecode) or reads (primRet: where a C primitive returns to). Optimized code also uses: cstackLimit (the highest slot address a frame may use), the deoptimization stress counter, where a guard that fails saves the registers (dump: x0-x31, then d0-d31).'!

!JitState class methodsFor: 'declaring'!
fields
	^#((nilOop oop) (trueOop oop) (falseOop oop) (frames uint64_t) (exitSp uint64_t) (youngLo uint64_t) (youngHi uint64_t)
		(arrayClass oop) (pointClass oop)
		(stackLimitNormal uint64_t) (baseFrame uint64_t) (baseRecord uint64_t)
		(edenBox uint64_t) (hashBox uint64_t) (lcgMul uint64_t) (lcgAdd uint64_t)
		(tagClasses 'oop[8]') (blockClass oop) (byteStringClass oop) (byteArrayClass oop) (boxedFloatClass oop) (wordArrayClass oop) (byteSymbolClass oop) (contextClass oop)
		(megaCache uint64_t) (blockCache uint64_t) (result oop) (ecode int64_t) (primRet uint64_t)
		(cstackLimit uint64_t) (stress int64_t) (dump 'uint64_t[64]') (c4Budget uint64_t))
! !

VMStruct subclass: #JitMethod
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitMethod comment: 'The header of a compiled method, in the code cache after its code: the method (a GC root), the compiler (mode), where the code starts and how long it is, start (the method''s first bytecode, after the prologue; its entry from a compiled caller is JIT_PROLOGUE_BYTES before), the bytecode map (pc, offset pairs of the resumption points, in pc order) and, if recorded, the notes for disassembly. Baseline code also has its checked and unchecked entries, its send sites (BaselineSite), its return map (return offset, pc | depth << 16, argc | length << 8 | pushes << 26) and its blocks (startpc, entry offset). flags: JM_FAILED (no code: the method is not compiled again), JM_DEAD (its code must not run), JM_NOTES, JM_ENTRY (baseline: the unchecked entry builds the frame; entryWord: its first instruction while optimized code has taken it over). A lower tier''s header links its method''s optimized code (opt); optimized code (mode opt, OptRuntime) has: lower, its frame''s slots (from rawBase on raw ones: doubles'' IEEE bits, which the collector skips), the method''s bytecode size, its oop pool (in the code, GC roots), the safepoint table and records, its dependencies, deoptimizations, the unit (blockStart, osrPc; a loop''s variant: the signature of the closures it inlines, OptRuntime>>closureSignatureOf:) and when it was compiled (generation, stamp).'!

!JitMethod class methodsFor: 'declaring'!
fields
	^#((method oop) (start uint64_t) (codeStart uint64_t) (codeSize uint32_t) (bytecodes uint32_t) (mode int32_t) (flags uint32_t)
		(mapCount uint32_t) (map 'uint32_t *')
		(noteCount uint32_t) (methodHash uint32_t) (noteOffsets 'uint32_t *') (noteTexts 'uint64_t *') (noteValues 'int64_t *')
		(entry uint64_t) (uentry uint64_t) (sites 'BaselineSite *') (rets 'uint32_t *') (blocks 'uint32_t *') (siteCount uint32_t) (retCount uint32_t) (blockCount uint32_t) (entryWord uint32_t)
		(opt uint64_t) (lower uint64_t) (slots uint32_t) (bcSize uint32_t) (poolOffset uint32_t) (poolCount uint32_t)
		(spCount uint32_t) (depCount uint32_t) (spTable 'int32_t *') (meta 'int32_t *') (deps 'int32_t *') (deopts uint32_t) (blockStart uint32_t) (osrPc uint32_t) (generation uint32_t) (stamp uint32_t) (signature uint32_t) (rawBase uint32_t) (checked 'JitMethod *') (checkedVersion 'C4JitVersion *'))
! !

VMStruct subclass: #C4JitVersion
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

!C4JitVersion class methodsFor: 'declaring'!
fields
	^#((args int32_t) (temps int32_t) (capacity int32_t) (bcSize int32_t) (nLits int32_t)
		(bytes 'uint8_t[64]') (literals 'uint64_t[64]'))
! !

!JitRuntime methodsFor: 'C4 optimizing entry'!
c4Candidate: m
	"The baseline compiler emits a countdown only for the bounded language.
	The optimizer also verifies the IR and emitted replay maps at tier-up."
	<function>
	| size |
	(self arith and: [self sliceDescriptor: m]) ifFalse: [^false].
	size := memory byteSize: (interpreter methodStorage: m at: CM_BYTECODES).
	^size > 0 and: [size <= 64 and: [optimizer sliceEnvelope: m osr: 0]]
!
finishC4TierUp
	"We left the entire baseline native stack, after sync: canonicalized all
	callers. The pending frame pointer never survives a native return."
	<function>
	| f h m i v |
	f := c4TierFrame.
	c4TierFrame := self null.
	m := f method.
	i := self optCountIndex: m.
	optCounts at: i put: 1.
	h := self cCoerce: f code to: 'JitMethod *'.
	(self c4Optimizing and: [flushPending not and: [self c4NativeBlocked not and: [
		f = (interpreter frames + (interpreter nframes - 1)) and: [f pc = 0 and: [
		self checkedStackRoom: f]]]]]) ifTrue: [
		v := h checked isNull ifTrue: [self null] ifFalse: [h checked checkedVersion].
		h checked isNull
			ifTrue: [
				v := self local: 'C4JitVersion'.
				libc memset: v value: 0 size: (self sizeof: 'C4JitVersion').
				((self c4Candidate: m) and: [(self sliceVersion: m at: v record: true) and: [
					f sp = (v args + v temps)]]) ifTrue: [
					h checked: (self buildChecked: m osr: 0 version: v production: true)].
				h checked isNull ifTrue: [
					c4OptRejects := c4OptRejects + 1.
					"No retry after permanent rejection in this cache generation."
					optCounts at: i put: 16r7FFFFFFF]]
			ifFalse: [
				((self sliceDescriptor: m) and: [(self sliceVersion: m at: v record: false) and: [
					f sp = (v args + v temps)]]) ifFalse: [
					c4OptVersionMisses := c4OptVersionMisses + 1.
					self dropAllCode.
					self prepare.
					h := self null]].
		(h notNull and: [h checked notNull]) ifTrue: [
			self executeChecked: h checked frame: f trace: false.
			^self]].
	scheduler interruptPendingRelaxed ~= 0 ifTrue: [interpreter entrySafepoint]
!
checkedStackRoom: f
	| base fp |
	base := self cCoerce: interpreter cstackBase to: 'uint64_t'.
	fp := self cCoerce: f fp to: 'uint64_t'.
	^fp >= (base + 8) and: [fp <= (interpreter cstackLimit - 256)]
! !

!JitRuntime methodsFor: 'checked prefix'!
configureSlice
	<function>
	sliceTest enabled ifFalse: [^self].
	(asm isX64 and: [cache canRunCode]) ifTrue: [
		sliceSelector := libc getenv: 'SAMALTAK_OPT_SLICE'.
		(sliceTest loopEnabled and: [sliceSelector isNull and: [(libc getenv: 'SAMALTAK_OPT_LOOP') notNull]]) ifTrue: [
			sliceLoop := true.
			sliceSelector := 'loopCount:seed:keep:a:b:c:d:e:'].
		sliceSelector notNull ifTrue: [sliceNameSize := libc strlen: sliceSelector]]
!
retireSlice
	<function>
	sliceTest enabled ifFalse: [^self].
	sliceHeader isNull ifTrue: [^self].
	(stateBlock baseRecord ~= 0 or: [self c4NativeBlocked]) ifTrue: [
		self fatal: 'checked prefix retirement during native execution or root publication'].
	libc fputs: 'opt-slice retire
' to: libc stderr.
	sliceHeader := self null
!
sliceRequested
	^sliceNameSize > 0 and: [sliceNameSize <= 64]
!
sliceLoopCandidate: f
	<function>
	^self sliceLoopEnabled and: [self sliceNamed: f method]
!
sliceLoopEnabled
	^sliceTest loopEnabled and: [sliceLoop and: [self sliceLane and: [vmMain c4Enabled]]]
!
sliceEnabled
	^sliceLoop not and: [self sliceLane]
!
sliceLane
	^self sliceRequested and: [jitMode = JIT_NONE and: [
		vmMain c4Enabled not or: [c4 movingForwardEnabled not and: [
			c4 platformFiles not and: [c4 platformSDL not and: [c4 arm64Interpreter not]]]]]]
!
sliceNamed: m
	<function>
	| sel |
	sel := self loadRef: m at: CM_SELECTOR.
	^sel ~= 0 and: [(self isPtr: sel) and: [(self rawClass: sel) = (memory special: SO_BYTESYMBOL) and: [
		(memory byteSize: sel) = sliceNameSize and: [
		(libc memcmp: (self bytesOf: sel) with: sliceSelector size: sliceNameSize) = 0]]]]
!
sliceMethodStorage: m at: i
	<function>
	<var: #m type: #oop>
	<var: #i type: 'uint32_t'>
	^interpreter methodStorage: m at: i
!
sliceMethodLiteral: m at: i
	<function>
	<var: #m type: #oop>
	<var: #i type: 'uint32_t'>
	^memory c4LoadRef: (self sliceMethodStorage: m at: CM_LITERALS) at: i
!
sliceDescriptor: m
	"All descriptor fields and literal storage read before building."
	<function>
	| a t c p |
	a := self loadRef: m at: CM_NUMARGS.
	t := self loadRef: m at: CM_NUMTEMPS.
	c := self loadRef: m at: CM_FRAMESIZE.
	p := self loadRef: m at: CM_PRIMITIVE.
	((self isInt: a) and: [(self isInt: t) and: [(self isInt: c) and: [
		p = memory nilOop or: [p = (self intOop: 0)]]]]) ifFalse: [^false].
	a := (self intVal: a) asUInt64.
	t := (self intVal: t) asUInt64.
	c := (self intVal: c) asUInt64.
	^a <= 16 and: [t <= 16 and: [c <= 16 and: [a + t <= c]]]
!
sliceLiteralKey: o
	"Version keys are not oop roots. Only supported constant kinds."
	<returns: 'uint64_t'>
	(self isInt: o) ifTrue: [^o].
	o = memory nilOop ifTrue: [^2 asUInt64].
	o = memory trueOop ifTrue: [^4 asUInt64].
	o = memory falseOop ifTrue: [^6 asUInt64].
	^0 asUInt64
!
sliceVersion: m at: v record: record
	<function>
	<var: #v type: 'C4JitVersion *'>
	| bc lo size nl a t c x |
	bc := interpreter methodStorage: m at: CM_BYTECODES.
	lo := interpreter methodStorage: m at: CM_LITERALS.
	size := memory byteSize: bc.
	nl := self numSlots: lo.
	(size <= 0 or: [size > 64 or: [nl > 64]]) ifTrue: [^false].
	a := (self intVal: (self loadRef: m at: CM_NUMARGS)) asInt32.
	t := (self intVal: (self loadRef: m at: CM_NUMTEMPS)) asInt32.
	c := (self intVal: (self loadRef: m at: CM_FRAMESIZE)) asInt32.
	record
		ifTrue: [
			v args: a.
			v temps: t.
			v capacity: c.
			v nLits: nl asInt32.
			v bcSize: size asInt32.
			libc memcpy: v bytes from: (self bytesOf: bc) size: size]
		ifFalse: [
			(a = v args and: [t = v temps and: [c = v capacity and: [
				nl asInt32 = v nLits and: [size = v bcSize asUInt64 and: [
				(libc memcmp: v bytes with: (self bytesOf: bc) size: size) = 0]]]]]) ifFalse: [^false]].
	0 to: nl asInt32 - 1 do: [:i |
		x := self sliceLiteralKey: (self loadRef: lo at: i).
		x = 0 ifTrue: [^false].
		record
			ifTrue: [v literals at: i put: x]
			ifFalse: [(v literals at: i) = x ifFalse: [^false]]].
	^true
!
buildChecked: m osr: pc version: v production: production
	"An outside-native body only: no ordinary call entry, ret map or
	OptRuntime frame. Commit the registered roots and cache extent together."
	<function>
	<var: #v type: 'C4JitVersion *'>
	<returns: 'JitMethod *'>
	| start ok h end version p err t0 dt |
	self ensureOpen ifFalse: [^self null].
	t0 := scheduler pauseCharging.
	start := cache top.
	cache beginWriting.
	asm beginAt: start limit: cache limit.
	asm recordNotes: false.
	ok := optimizer compileSlice: m osr: pc.
	err := asm finish.
	h := self cCoerce: asm pc to: 'JitMethod *'.
	end := asm pc + (self sizeof: 'JitMethod') + optimizer sliceExtraBytes asUInt64.
	version := (end + 7) bitClear: 7.
	p := version + (self sizeof: 'C4JitVersion').
	(ok and: [(asm isOK: err) and: [(asm pc bitAnd: 7) = 0 and: [p + 15 <= cache limit]]]) ifFalse: [
		cache endWritingFrom: start size: 0.
		(production and: [(asm isFull: err) or: [ok and: [p + 15 > cache limit]]]) ifTrue: [self requestFlush].
		scheduler resumeCharging.
		^self null].
	libc memset: h value: 0 size: (self sizeof: 'JitMethod').
	h method: m.
	h mode: -1.
	h start: start.
	h codeStart: start.
	h osrPc: pc asUInt32.
	h codeSize: (asm pc - start) asUInt32.
	h bytecodes: v bcSize asUInt32.
	h methodHash: (self hashOf: m) asUInt32.
	optimizer writeSlice: h at: asm pc + (self sizeof: 'JitMethod').
	((optimizer validSlice: h end: end frame: v capacity) and: [brt canRegister: 1 + h poolCount]) ifFalse: [
		cache endWritingFrom: start size: 0.
		(production and: [(brt canRegister: 1 + h poolCount) not]) ifTrue: [self requestFlush].
		scheduler resumeCharging.
		^self null].
	h checkedVersion: (self cCoerce: version to: 'C4JitVersion *').
	libc memcpy: h checkedVersion from: v size: (self sizeof: 'C4JitVersion').
	brt registerSlot: (self cCoerce: (h fieldAddress: #method) to: 'uint64_t').
	0 to: h poolCount asInt32 - 1 do: [:i | brt registerSlot: h codeStart + h poolOffset + (8 * i)].
	cache allocate: p - start.
	cache endWritingFrom: start size: cache top - start.
	dt := scheduler resumeCharging - t0.
	production ifTrue: [
		c4OptCompiles := c4OptCompiles + 1.
		c4OptBytecodes := c4OptBytecodes + h bytecodes.
		c4OptBytes := c4OptBytes + h codeSize.
		c4OptUs := c4OptUs + dt asUInt64.
		statCompiled := statCompiled + 1.
		statBytecodes := statBytecodes + h bytecodes.
		statCodeBytes := statCodeBytes + h codeSize.
		statCompileUs := statCompileUs + dt asUInt64.
		perfMap notNull ifTrue: [self perfMapCode: h mode: JIT_OPT]].
	^h
!
compileSlice: m osr: pc
	<function>
	| h bytes hash |
	h := self buildChecked: m osr: pc version: sliceTestVersion production: false.
	h isNull ifTrue: [
		libc fputs: 'opt-slice compile rejected
' to: libc stderr.
		^false].
	sliceStamp := invalidations.
	sliceCacheGeneration := vmMain c4Enabled ifTrue: [c4 cacheGeneration] ifFalse: [0 asUInt64].
	sliceHeader := h.
	bytes := h bytecodes asInt32.
	hash := 16rCBF29CE484222325 asUInt64.
	0 to: bytes - 1 do: [:i | hash := (hash bitXor: (sliceTestVersion bytes at: i) asUInt64) * 16r100000001B3 asUInt64].
	libc fprintf: libc stderr format: 'opt-slice installed methodHash=%u bytecodeFNV=%016llx bytes=%d nativeBytes=%u
' with: h methodHash with: hash with: bytes with: h codeSize.
	libc fprintf: libc stderr format: 'opt-slice slots=%u rows=%u pool=%u
' with: h slots with: h spCount with: h poolCount.
	(libc getenv: 'SAMALTAK_OPT_SLICE_TRACE') notNull ifTrue: [self traceSlice: h].
	vmMain c4Enabled ifTrue: [
		libc fprintf: libc stderr format: 'opt-slice registered=%u generation=%llu
' with: 1 + h poolCount with: sliceCacheGeneration].
	^true
!
traceSlice: h
	<function>
	| row n |
	libc fputs: 'opt-slice machine=' to: libc stderr.
	0 to: h codeSize asInt32 - 1 do: [:i | libc fprintf: libc stderr format: '%02x' with: (self uint8At: h codeStart + i)].
	libc fputc: 10 to: libc stderr.
	0 to: h spCount asInt32 - 1 do: [:i |
		row := h meta + (h spTable at: i).
		n := row at: 2.
		libc fprintf: libc stderr format: 'opt-slice map row=%d kind=%d pc=%d depth=%d' with: i with: (row at: 0) with: (row at: 1) with: n.
		0 to: n do: [:j | libc fprintf: libc stderr format: ' %d' with: (row at: 3 + j)].
		libc fputc: 10 to: libc stderr]
!
trySlice: f
	<function>
	^self trySlice: f osr: false
!
trySliceLoop: f
	<function>
	^self trySlice: f osr: true
!
trySlice: f osr: loop
	<function>
	| m bc lo pc |
	(sliceTest enabled and: [loop ifTrue: [self sliceLoopEnabled] ifFalse: [self sliceEnabled]]) ifFalse: [^false].
	(stateBlock baseRecord ~= 0 or: [memory rootCount ~= 0 or: [
		f code ~= 0 or: [f ctx ~= memory nilOop or: [f closure ~= memory nilOop]]]]) ifTrue: [^false].
	(interpreter nframes <= 0 or: [f ~= (interpreter frames + (interpreter nframes - 1))]) ifTrue: [^false].
	m := f method.
	(sliceHeader notNull and: [sliceHeader method ~= m and: [flushPending not]]) ifTrue: [^false].
	(self sliceNamed: m) ifFalse: [^false].
	self c4NativeBlocked ifTrue: [
		libc fputs: 'opt-slice blocked by root publication
' to: libc stderr.
		^false].
	self prepare.
	flushPending ifTrue: [^false].
	(self sliceDescriptor: m) ifFalse: [^false].
	bc := interpreter methodStorage: m at: CM_BYTECODES.
	lo := interpreter methodStorage: m at: CM_LITERALS.
	pc := loop ifTrue: [6] ifFalse: [0].
	f ip = ((self bytesOf: bc) + pc) ifFalse: [^false].
	f lits = (self slotsOf: lo) ifFalse: [^false].
	(f sp = ((self intVal: (self loadRef: m at: CM_NUMARGS)) + (self intVal: (self loadRef: m at: CM_NUMTEMPS)))) ifFalse: [^false].
	(self checkedStackRoom: f) ifFalse: [^false].
	sliceHeader isNull
		ifTrue: [
			(self sliceVersion: m at: sliceTestVersion record: true) ifFalse: [^false].
			(optimizer sliceEnvelope: m osr: pc) ifFalse: [^false].
			vmMain c4Enabled ifTrue: [c4 noteCodeBytes: bc].
			(self compileSlice: m osr: pc) ifFalse: [^false]]
		ifFalse: [
			(sliceStamp = invalidations and: [
				(vmMain c4Enabled not or: [sliceCacheGeneration = c4 cacheGeneration]) and: [
					self sliceVersion: m at: sliceTestVersion record: false]]) ifFalse: [
				self dropAllCode.
				self prepare.
				^false]].
	loop ifTrue: [stateBlock stress: 4].
	self executeChecked: sliceHeader frame: f trace: true.
	^true
!
executeChecked: h frame: f trace: trace
	<function>
	| ret k reason |
	trace ifFalse: [
		statEntries := statEntries + 1.
		c4OptEntries := c4OptEntries + 1].
	stateBlock dump at: 31 put: 16rFFFFFFFFFFFFFFFF asUInt64.
	ret := (self cCoerce: stubs blEnterAddress to: 'int64_t (*)(Frame *, uint64_t)') call: f with: h start.
	stateBlock baseRecord: 0.
	k := stateBlock dump at: 31.
	(ret ~= 0 or: [k >= h spCount]) ifTrue: [self fatal: 'bad checked prefix exit'].
	reason := optimizer replaySlice: h frame: f index: k asInt32 dump: stateBlock dump trace: trace.
	libc memset: stateBlock dump value: 0 size: (32 * 8).
	"No sole root in a dump, scratch or raw body borrow at the checkpoint."
	trace
		ifTrue: [
			vmMain c4Enabled ifTrue: [
				interpreter c4CanonicalCheckpoint.
				libc fprintf: libc stderr format: 'opt-slice checkpoint partial=%d
' with: (interpreter c4Publishing ifTrue: [1] ifFalse: [0])]]
		ifFalse: [
			statExits := statExits + 1.
			reason caseOf: {
				[0] -> [c4OptInterrupts := c4OptInterrupts + 1].
				[1] -> [c4OptTags := c4OptTags + 1].
				[2] -> [c4OptOverflows := c4OptOverflows + 1].
				[3] -> [c4OptReturns := c4OptReturns + 1]}
				otherwise: [self fatal: 'unknown C4 optimized exit'].
			self c4NativeCheckpoint].
	reason = 0 ifTrue: [interpreter entrySafepoint]
! !
