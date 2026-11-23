Object subclass: #VMStatistics
	instanceVariableNames: 'counters'
	classVariableNames: ''
	package: 'System-Support'!

VMStatistics comment: 'I am a snapshot of the VM''s counters (Smalltalk vm statistics), over the Array the vmStats primitive answers (SystemPrimitives>>primVMStats), with a named accessor per counter. A - b answers the differences. Counters the VM does not report answer 0; ones I have no accessor for are kept.'!

!VMStatistics methodsFor: 'accessing'!
counters
	"Answer the raw Array, in vmStats order."
	^counters
!
counterAt: anInteger
	^anInteger <= counters size ifTrue: [counters at: anInteger] ifFalse: [0]
!
scavenges
	^self counterAt: 1
!
fullGCs
	^self counterAt: 2
!
scavengeMicroseconds
	^self counterAt: 3
!
fullGCMicroseconds
	^self counterAt: 4
!
oldBytesUsed
	^self counterAt: 5
!
oldBudget
	^self counterAt: 6
!
edenBytes
	^self counterAt: 7
!
bytesAllocated
	^self counterAt: 8
!
rememberedSetSize
	^self counterAt: 9
!
processSwitches
	^self counterAt: 10
!
bytesTenured
	^self counterAt: 11
!
tenureAge
	"The scavenges an object survives before it is promoted (the running VM's GarbageCollector TENURE_AGE)."
	^self counterAt: 41
!
cpuTimeReconciles
	"Reads of the VM thread's CPU time that charged it to the Processes that ran (Scheduler>>reconcile)."
	^self counterAt: 42
!
weakSlotsCleared
	^self counterAt: 12
!
contextsMaterialized
	"Frames flushed into Contexts."
	^self counterAt: 13
!
frameFlushes
	"Flushes of the frame stack (each materializes every frame on it)."
	^self counterAt: 14
!
jitMethodsCompiled
	^self counterAt: 15
!
jitBytecodesCompiled
	^self counterAt: 16
!
jitCompileMicroseconds
	^self counterAt: 17
!
jitCodeBytes
	^self counterAt: 18
!
jitCacheFlushes
	^self counterAt: 19
!
jitEntries
	"Interpreter to machine code."
	^self counterAt: 20
!
jitExits
	"Machine code to the interpreter."
	^self counterAt: 21
!
jitResumes
	"Machine code continued after a return, a send the interpreter made or a process switch."
	^self counterAt: 22
!
jitOsrEntries
	"On-stack replacements: a running method entered at a backward jump."
	^self counterAt: 23
!
jitCompileFailures
	^self counterAt: 24
!
jitInlineCacheMisses
	"Baseline: sends that found no target in machine code (unlinked, a failed class check, a cache without the class)."
	^self counterAt: 25
!
jitInlineCacheLinks
	"Baseline: sites linked monomorphically."
	^self counterAt: 26
!
jitPolymorphicCaches
	^self counterAt: 27
!
jitMegamorphicSites
	^self counterAt: 28
!
jitBlockCacheMisses
	"Baseline: closure evaluations whose block entry was not in the block cache."
	^self counterAt: 29
!
jitPrimitiveCalls
	"Baseline: primitives called through their C function."
	^self counterAt: 30
!
jitFrameWalks
	"Baseline: lazily canonicalized frame stacks (calls into the runtime that are safepoints)."
	^self counterAt: 31
!
optMethodsCompiled
	^self counterAt: 32
!
optBytecodesCompiled
	^self counterAt: 33
!
optCompileMicroseconds
	^self counterAt: 34
!
optCodeBytes
	^self counterAt: 35
!
optDeoptimizations
	^self counterAt: 36
!
optOsrEntries
	^self counterAt: 37
!
optInvalidations
	^self counterAt: 38
!
optCompileFailures
	^self counterAt: 39
!
optRuntimeSends
	"Sends of optimized code the runtime made (no machine code to call: perform:, doesNotUnderstand:, a method not compiled yet)."
	^self counterAt: 40
!
gcCount
	"Answer the scavenges plus the full GCs."
	^self scavenges + self fullGCs
!
gcMicroseconds
	^self scavengeMicroseconds + self fullGCMicroseconds
! !

!VMStatistics methodsFor: 'arithmetic'!
- aVMStatistics
	"Answer the counter differences (gauges such as oldBytesUsed become differences too)."
	^self class counters: ((1 to: (counters size min: aVMStatistics counters size))
		collect: [:i | (counters at: i) - (aVMStatistics counters at: i)])
! !

!VMStatistics methodsFor: 'printing'!
printOn: aStream
	"One counter per line."
	self class counterNames do: [:each |
		aStream nextPutAll: each; nextPutAll: ': '; print: (self perform: each); nextPut: Character lf]
! !

!VMStatistics methodsFor: 'private'!
setCounters: anArray
	counters := anArray
! !

!VMStatistics class methodsFor: 'instance creation'!
counters: anArray
	^self new setCounters: anArray
! !

!VMStatistics class methodsFor: 'accessing'!
counterNames
	"Answer my counter accessors in vmStats order."
	^#(#scavenges #fullGCs #scavengeMicroseconds #fullGCMicroseconds #oldBytesUsed #oldBudget #edenBytes #bytesAllocated #rememberedSetSize #processSwitches #bytesTenured #weakSlotsCleared #contextsMaterialized #frameFlushes #jitMethodsCompiled #jitBytecodesCompiled #jitCompileMicroseconds #jitCodeBytes #jitCacheFlushes #jitEntries #jitExits #jitResumes #jitOsrEntries #jitCompileFailures #jitInlineCacheMisses #jitInlineCacheLinks #jitPolymorphicCaches #jitMegamorphicSites #jitBlockCacheMisses #jitPrimitiveCalls #jitFrameWalks #optMethodsCompiled #optBytecodesCompiled #optCompileMicroseconds #optCodeBytes #optDeoptimizations #optOsrEntries #optInvalidations #optCompileFailures #optRuntimeSends #tenureAge #cpuTimeReconciles)
! !
