Object subclass: #JitWorkerProof
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'JitWorkerProof'!

!CompiledMethod methodsFor: 'worker test control'!
workerTest: command
	<primitive: 'jitWorkerTest'>
	self primitiveFailed
! !

!JitWorkerProof class methodsFor: 'test support'!
check: got is: wanted
	got = wanted ifFalse: [self error: 'wanted ', wanted printString, '; got ', got printString]
!
queue: selector
	| m status |
	m := self class >> selector.
	self check: (m workerTest: 0) is: 0.
	self check: (self perform: selector with: 40) is: 42.
	self check: (self perform: selector with: 40) is: 42.
	status := m workerTest: 2.
	status = 2 ifFalse: [self error: selector, ' queue: wanted 2; got ', status printString].
	self check: (m workerTest: 4) is: 0.
	^m
!
discard: m
	self check: (m workerTest: 3) is: 4.
	self check: (m workerTest: 4) is: 0
! !

!JitWorkerProof class methodsFor: 'tests'!
install
	| m |
	m := self queue: #addForInstall:.
	"Another entry cannot publish while the worker's result is held."
	self check: (self addForInstall: 23) is: 25.
	self check: (m workerTest: 4) is: 0.
	self check: (m workerTest: 5) is: 1.
	self check: (self addForInstall: 40) is: 42.
	self check: (m workerTest: 1) is: 3.
	self check: (m workerTest: 4) is: 1.
	self check: (self addForInstall: 42) is: 44.
	self check: (self addForInstall: 1.5) is: 3.5.
	^true
!
collections
	| m |
	m := self queue: #addForScavenge:.
	Smalltalk vm scavenge.
	self discard: m.
	self check: (self addForScavenge: 40) is: 42.
	self check: (m workerTest: 4) is: 1.
	m := self queue: #addForFull:.
	Smalltalk vm garbageCollect.
	self discard: m.
	self check: (self addForFull: 40) is: 42.
	self check: (m workerTest: 4) is: 1.
	^true
!
invalidation
	| m flushes |
	m := self queue: #addForInvalidation:.
	Smalltalk vm flushCacheForSelector: #addForInvalidation:.
	self discard: m.
	m := self queue: #addForFlush:.
	Smalltalk vm jitParameters: #(nil 'bg' nil nil).
	self discard: m.
	flushes := Smalltalk vm statistics jitCacheFlushes.
	m := self queue: #addForRelease:.
	self check: (m workerTest: 1) is: 1.
	Smalltalk vm releaseMemory.
	self check: (m workerTest: 1) is: 4.
	self discard: m.
	self check: Smalltalk vm statistics jitCacheFlushes is: flushes + 1.
	self check: (self addForRelease: 40) is: 42.
	^true
!
fallback: status
	| m |
	m := self class >> #addForInstall:.
	status = -2 ifFalse: [self check: (m workerTest: 0) is: 0].
	self check: (self addForInstall: 40) is: 42.
	self check: (self addForInstall: 41) is: 43.
	self check: (m workerTest: 2) is: status.
	self check: (m workerTest: 4) is: 1.
	^true
!
interleavedDiscards
	| a b |
	a := self queue: #addForRedoA:.
	Smalltalk vm scavenge.
	self discard: a.
	b := self queue: #addForRedoB:.
	Smalltalk vm scavenge.
	self discard: b.
	self check: (a workerTest: 0) is: 0.
	self check: (self addForRedoA: 40) is: 42.
	self check: (a workerTest: 1) is: 0.
	self check: (a workerTest: 4) is: 1.
	self check: (b workerTest: 0) is: 0.
	self check: (self addForRedoB: 40) is: 42.
	self check: (b workerTest: 1) is: 0.
	self check: (b workerTest: 4) is: 1.
	^true
!
scratchContention
	| m competing |
	competing := self class >> #competingSum:.
	m := self queue: #addForContention:.
	"An unrelated loop tiers up synchronously and must take back the scratch slot."
	self check: (self competingSum: 10) is: 55.
	self check: (competing workerTest: 4) is: 1.
	self check: (m workerTest: 1) is: 4.
	self discard: m.
	self check: (self addForContention: 40) is: 42.
	self check: (m workerTest: 4) is: 1.
	^true
!
boundFfi
	| m binding code |
	m := self class >> #boundStep:with:.
	binding := FFI bind: #(call 'wrapped' 'wrapped_step' (i32) i32).
	"Leave monomorphic baseline feedback before asking this method to queue."
	self check: (self boundStep: binding with: 40) is: -39.
	self check: (self boundStep: binding with: 41) is: -40.
	self check: (m workerTest: 0) is: 0.
	self check: (self boundStep: binding with: 42) is: -41.
	self check: (m workerTest: 1) is: 0.
	self check: (m workerTest: 4) is: 1.
	code := m jitCode: #opt.
	self check: ((code at: 4) includes: 'bound FFI site: direct wrapper') is: true.
	^true
!
quitWithJob
	| m |
	m := self class >> #addForInstall:.
	self check: (m workerTest: 0) is: 0.
	self check: (self addForInstall: 40) is: 42.
	self check: (self addForInstall: 41) is: 43.
	self check: (m workerTest: 1) is: 1.
	Smalltalk quit: 0
! !

!JitWorkerProof class methodsFor: 'tier-up targets'!
addForInstall: x
	^x + 2
!
addForScavenge: x
	^x + 2
!
addForFull: x
	^x + 2
!
addForInvalidation: x
	^x + 2
!
addForFlush: x
	^x + 2
!
addForRelease: x
	^x + 2
!
addForRedoA: x
	^x + 2
!
addForRedoB: x
	^x + 2
!
addForContention: x
	^x + 2
!
competingSum: n
	| i sum |
	i := n.
	sum := 0.
	[i > 0] whileTrue: [sum := sum + i. i := i - 1].
	^sum
! !

!JitWorkerProof class methodsFor: 'FFI target'!
boundStep: binding with: n
	^binding tryInvoke1: n
! !
