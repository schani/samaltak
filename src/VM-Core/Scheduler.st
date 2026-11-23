VMCoreModule subclass: #Scheduler
	instanceVariableNames: 'interruptPending lastPreempted lastPreemptedAtEntry allocSampleClass allocSampleSize allocSampleInterval allocSampleCountdown allocSampleSema statProcessSwitches allocSamplePending inIdle preemptToFront allocSampleUnread samplerTickUnread timerMs samplerIntervalUs samplerNextUs sliceStartNs windowStartNs windowCpuUs ledgerProcs ledgerNs ledgerN statReconciles startUs samplerSema pendingExt pendingExtN pendingExtCap tickIdle tickPollUs tickArmedPoll tickArmedDeadline tickDeadlineFired ticker workClockOn workClockRunning workClockPaced workClockUsesCycles workClockUs workClockCycles workClockRaw workClockHeld workClockHoldCycles workClockQuerying frameSema frameFps frameOriginUs frameIndex frameNextUs sliceUs sliceDueUs slicePriority sliceExpired'
	classVariableNames: 'LEDGER_SIZE RECONCILE_NS TICK_DEADLINE TICK_POLL WORK_CLOCK_FLOOR WORK_CLOCK_POLL_US WORK_CYCLES_PER_US'
	package: 'VM-Core'!

Scheduler comment: 'Process scheduler, semaphores and interrupts: the timer, the CPU and allocation samplers, external semaphore signals, time slices.

Time slicing (setTimeSlice:): while another Process of the active one''s priority is ready, the active one runs at most sliceUs before it goes to the back of its run list, so equal-priority Processes take turns. The slice''s deadline is armed only under that contention (a Process made ready at the active priority, a switch to a Process with peers waiting): a program whose Processes do not compete, or that idles, has no timer for it.

Processes are charged the VM thread''s CPU time (threadCpuUs) in batches, as one read of that clock costs a system call: a switch adds the outgoing Process''s slice, by the monotonic clock, to its entry in a ledger of LEDGER_SIZE entries. Once the ledger is full or its window older than RECONCILE_NS (or when charging pauses, or a Process in it or running is asked its time), reconcile splits the thread clock''s advance over the window among the entries in proportion to their slices, exactly. While the VM waits or compiles, charging pauses (pauseCharging, resumeCharging).

While Smalltalk runs, a timer of the Ticker (its thread calls tickFired:) requests an interrupt check when the timer or the CPU sampler is due, and a periodic one every tickPollUs if the platform asked for polls (requestPeriodicPoll:). While the VM waits in the platform''s wait both are disarmed: the wait''s timeout covers the timer and the sampler, and the platform wakes it for events. tickUpdate (VM thread) re-arms after any change.

While a video is recorded (workClockStart:semaphore:) my clock is the work clock, so that what is recorded does not depend on the machine''s load: it counts the cycles of the VM thread at 3.3 GHz (not real time, not CPU time), jumps to the next deadline when no Process can run, and stands still between the commands of the driver (workClockRunning:), when only the Processes at WORK_CLOCK_FLOOR and above run. It never passes a deadline, so frames and Delays land on their exact times; the work a late interrupt check lets through is not counted. The Ticker only polls then. While an external program runs (workClockPaced:) it also moves at least at the pace of real time, and does not stand still.'!

!Scheduler class methodsFor: 'declaring'!
declarations
	^#((interruptPending atomic_int) (lastPreempted oop) (lastPreemptedAtEntry bool) (allocSampleClass oop) (allocSampleSize int64_t)
		(allocSampleInterval int64_t) (allocSampleCountdown int64_t) (allocSampleSema int32_t) (statProcessSwitches uint64_t)
		(allocSamplePending bool) (inIdle bool) (preemptToFront bool) (allocSampleUnread bool) (samplerTickUnread bool)
		(timerMs int64_t -1) (samplerIntervalUs int64_t) (samplerNextUs int64_t) (sliceStartNs int64_t) (windowStartNs int64_t) (windowCpuUs int64_t)
		(ledgerProcs 'oop[16]') (ledgerNs 'int64_t[16]') (ledgerN int32_t) (statReconciles uint64_t) (startUs int64_t)
		(samplerSema int32_t) (pendingExt 'int32_t *') (pendingExtN int32_t) (pendingExtCap int32_t)
		(tickIdle bool) (tickPollUs int64_t) (tickArmedPoll int64_t) (tickArmedDeadline int64_t 16r7FFFFFFFFFFFFFFF)
		(tickDeadlineFired atomic_bool) (ticker Ticker)
		(workClockOn bool) (workClockRunning bool) (workClockPaced bool) (workClockUsesCycles bool)
		(workClockUs int64_t) (workClockCycles int64_t) (workClockRaw int64_t) (workClockHeld bool) (workClockHoldCycles int64_t) (workClockQuerying bool)
		(frameSema int32_t) (frameFps int64_t) (frameOriginUs int64_t) (frameIndex int64_t) (frameNextUs int64_t)
		(sliceUs int64_t) (sliceDueUs int64_t) (slicePriority int64_t) (sliceExpired bool))
!
initialize
	"Charging: the ledger's entries (the size of ledgerProcs and ledgerNs), the longest window between two reads of the thread clock (ns)."
	LEDGER_SIZE := 16.
	RECONCILE_NS := 200000.
	TICK_DEADLINE := 1.
	TICK_POLL := 2.
	"The work clock: its rate (a 3.3 GHz core), how often a running Smalltalk is checked against its deadlines (µs of real time), the lowest priority that runs while it stands still (the control server's)."
	WORK_CYCLES_PER_US := 3300.
	WORK_CLOCK_POLL_US := 200.
	WORK_CLOCK_FLOOR := 50
! !

!Scheduler methodsFor: 'accessing'!
interruptPendingRelaxed
	^self atomicLoad: #interruptPending
!
lastPreempted
	^lastPreempted
!
lastPreempted: o
	lastPreempted := o
!
lastPreemptedAtEntry
	"Whether lastPreempted was preempted at an activation's first instruction (and has not run since)."
	^lastPreemptedAtEntry
!
allocSampleClass
	^allocSampleClass
!
allocSampleClass: o
	allocSampleClass := o
!
allocSampleSize
	^allocSampleSize
!
allocSampleInterval
	^allocSampleInterval
!
allocSampleInterval: n
	allocSampleInterval := n
!
allocSampleCountdown
	^allocSampleCountdown
!
allocSampleCountdown: n
	allocSampleCountdown := n
!
allocSampleSema: n
	allocSampleSema := n
!
allocSampleUnread
	^allocSampleUnread
!
allocSampleUnread: aBoolean
	allocSampleUnread := aBoolean
!
samplerTickUnread
	^samplerTickUnread
!
samplerTickUnread: aBoolean
	samplerTickUnread := aBoolean
!
statProcessSwitches
	^statProcessSwitches
!
statReconciles
	^statReconciles
!
ledgerProcs
	^ledgerProcs
!
ledgerN
	^ledgerN
! !

!Scheduler methodsFor: 'time'!
rawNowUs
	<function>
	| ts |
	ts := self local: 'Timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
!
rawNowNs
	<function>
	| ts |
	ts := self local: 'Timespec'.
	posix clockGettime: posix CLOCK_MONOTONIC into: ts.
	^(ts tv_sec * 1000000000) + ts tv_nsec
!
nowUs
	<function>
	workClockOn ifTrue: [^self workClockSync].
	^self rawNowUs - startUs
!
nowMs
	<function>
	^self nowUs quo: 1000
!
threadCpuUs
	"The VM thread's CPU time, which Processes are charged: wall time would charge the running one while the OS runs other threads. While recording its cycles at the work clock's rate."
	<function>
	workClockOn ifTrue: [^self workClockThreadCycles quo: WORK_CYCLES_PER_US].
	^self realThreadCpuUs
!
realThreadCpuUs
	| ts |
	ts := self local: 'Timespec'.
	posix clockGettime: posix CLOCK_THREAD_CPUTIME_ID into: ts.
	^(ts tv_sec * 1000000) + (ts tv_nsec quo: 1000)
!
pauseCharging
	"Charge the Processes that ran (reconcile); until resumeCharging nothing is charged (the VM waits, or works for itself). Answer the thread clock."
	<function>
	^self reconcile
!
resumeCharging
	"Charging goes on: a new window and slice from now. Answer the thread clock."
	<function>
	sliceStartNs := self rawNowNs.
	windowStartNs := sliceStartNs.
	windowCpuUs := self threadCpuUs.
	^windowCpuUs
!
reconcile
	"End the running slice and the window: split the thread clock's advance since the window began among the ledger's Processes in proportion to their slices (rounding the running sums, so that the shares add up to it), empty the ledger and begin the next window. Answer the thread clock."
	<function>
	| now cpu t total scale acc given share |
	now := self rawNowNs.
	self ledgerAdd: self activeProcess ns: now - sliceStartNs.
	cpu := self threadCpuUs.
	t := cpu - windowCpuUs.
	total := 0.
	0 to: ledgerN - 1 do: [:i | total := total + (ledgerNs at: i)].
	"weights below 2^24: t times one does not overflow"
	scale := 0.
	[(total >> scale) > 16rFFFFFF] whileTrue: [scale := scale + 1].
	acc := 0.
	given := 0.
	0 to: ledgerN - 1 do: [:i |
		acc := acc + (ledgerNs at: i).
		share := total = 0
			ifTrue: [i = (ledgerN - 1) ifTrue: [t] ifFalse: [0]]
			ifFalse: [t * (acc >> scale) quo: (total >> scale)].
		self charge: (ledgerProcs at: i) us: share - given.
		given := share].
	ledgerN := 0.
	sliceStartNs := now.
	windowStartNs := now.
	windowCpuUs := cpu.
	statReconciles := statReconciles + 1.
	^cpu
!
ledgerAdd: proc ns: ns
	"Add ns to proc's entry, a new one if it has none (there is room)."
	0 to: ledgerN - 1 do: [:i |
		(ledgerProcs at: i) = proc ifTrue: [
			ledgerNs at: i put: (ledgerNs at: i) + ns.
			^self]].
	ledgerProcs at: ledgerN put: proc.
	ledgerNs at: ledgerN put: ns.
	ledgerN := ledgerN + 1
!
inLedger: proc
	0 to: ledgerN - 1 do: [:i | (ledgerProcs at: i) = proc ifTrue: [^true]].
	^false
!
charge: proc us: us
	| ct |
	ct := self loadRef: proc at: PROC_CPUTIME.
	self storeRef: proc at: PROC_CPUTIME put: (self intOop: ((self isInt: ct) ifTrue: [self intVal: ct] ifFalse: [0]) + us)
! !

!Scheduler methodsFor: 'interrupts'!
requestInterruptCheck
	"Any thread."
	<function>
	self atomicStore: #interruptPending value: 1.
	jit requestInterrupt
!
signalExternalSemaphore: index
	"1-based index into externalObjects; VM thread only, queued."
	<export>
	<var: #index type: 'int32_t'>
	pendingExtN = pendingExtCap ifTrue: [
		pendingExtCap := pendingExtCap = 0 ifTrue: [64] ifFalse: [pendingExtCap * 2].
		pendingExt := self cCoerce: (libc realloc: pendingExt size: 4 * pendingExtCap asUInt64) to: 'int32_t *'.
		pendingExt isNull ifTrue: [self fatal: 'out of memory queueing external semaphore signals']].
	pendingExt at: pendingExtN put: index.
	pendingExtN := pendingExtN + 1.
	self requestInterruptCheck
! !

!Scheduler methodsFor: 'work clock'!
workClockStart: fps semaphore: index
	"From now on the clock is the work clock (see my comment), running. With fps > 0, external semaphore index is signaled when frame k is due, on the millisecond grid of the clock (the Delays'): ceiling(k × 1000 / fps) ms after frame 0, which is due at the next whole millisecond (kept if that semaphore is already armed). Answer when frame 0 is."
	<function>
	workClockOn ifFalse: [
		self pauseCharging.
		workClockUs := self nowUs.
		workClockUsesCycles := ticker threadCycles >= 0.
		workClockUsesCycles ifFalse: [
			libc fprintf: libc stderr format: 'samaltak: no cycle counter here: the recording clock counts CPU time, so load and core type change what is recorded
'].
		workClockOn := true.
		workClockRunning := true.
		workClockPaced := false.
		workClockCycles := self workClockThreadCycles.
		workClockRaw := self rawNowUs.
		self resumeCharging.
		self tickUpdate].
	(fps > 0 and: [frameSema ~= index]) ifTrue: [
		frameSema := index.
		frameFps := fps.
		frameOriginUs := self workClockSync + 999 quo: 1000.
		frameOriginUs := frameOriginUs * 1000.
		frameIndex := 0.
		frameNextUs := frameOriginUs].
	^frameOriginUs
!
workClockStop
	"Back to the real clock, which goes on from the work clock's time."
	<function>
	workClockOn ifFalse: [^self].
	self pauseCharging.
	self workClockSync.
	startUs := self rawNowUs - workClockUs.
	workClockOn := false.
	frameSema := 0.
	self resumeCharging.
	self tickUpdate
!
workClockRunning: aBoolean
	"Whether a command of the driver is in flight: the clock stands still between commands."
	<function>
	workClockOn ifTrue: [self workClockSetRunning: aBoolean paced: workClockPaced]
!
workClockPaced: aBoolean
	"Whether an external program is running: the clock then moves at least as fast as real time, even between commands."
	<function>
	workClockOn ifTrue: [self workClockSetRunning: workClockRunning paced: aBoolean]
!
workClockSetRunning: running paced: paced
	| moving |
	moving := workClockRunning or: [workClockPaced].
	moving ifTrue: [self workClockSync].
	"Staying paced, the real time not yet counted (a frame's, while held) stays to be counted."
	(workClockPaced and: [paced]) ifFalse: [workClockRaw := self rawNowUs].
	workClockRunning := running.
	workClockPaced := paced.
	moving ifFalse: [workClockCycles := self workClockThreadCycles]
!
workClockNextFrame
	"When the next frame is due (µs), < 0 while the work clock is off."
	<function>
	workClockOn ifFalse: [^-1].
	^frameNextUs
!
workClockQuerying: aBoolean
	"A query is being served with the clock standing still: Processes below the floor may run if it waits for one (it may hold a lock the query needs); the clock stays where it is."
	<function>
	workClockQuerying := aBoolean
!
workClockHold
	"The Compositor's frame begins: its work does not move the clock (Compositor>>frameOnWorkClock)."
	<function>
	workClockOn ifFalse: [^self].
	self workClockSync.
	workClockHeld := true.
	workClockHoldCycles := self workClockThreadCycles
!
workClockRelease
	"The frame ended: answer its work, in µs at the clock's rate. Paced, the real time the frame took still counts (the program outside ran meanwhile)."
	<function>
	| now |
	workClockOn ifFalse: [^0].
	now := self workClockThreadCycles.
	workClockHeld := false.
	workClockCycles := now.
	workClockPaced ifFalse: [workClockRaw := self rawNowUs].
	^(now - workClockHoldCycles) quo: WORK_CYCLES_PER_US
!
workClockSkipRealTime
	"Paced: the real time gone by and not yet counted is not counted (a recorded frame ends: its wait for the GPU and for the reader is not the clock's, Compositor>>frameOnWorkClock)."
	<function>
	workClockOn ifTrue: [workClockRaw := self rawNowUs]
!
workClockHeldUs
	"During a frame the clock stands still; this one, its time plus the frame's work so far, does not: for the times the frame reports, and how long a garbage collection in it took."
	<function>
	workClockHeld ifFalse: [^self nowUs].
	^workClockUs + ((self workClockThreadCycles - workClockHoldCycles) quo: WORK_CYCLES_PER_US)
!
workClockCharge: us
	"A frame took longer than a tick: the clock passes the excess."
	<function>
	workClockOn ifFalse: [^self].
	workClockUs := workClockUs + us
!
workClockThreadCycles
	"The VM thread's cycles; without a cycle counter, its CPU time at the same rate."
	workClockUsesCycles ifTrue: [^ticker threadCycles].
	^self realThreadCpuUs * WORK_CYCLES_PER_US
!
workClockDeadline
	"The next time something is due: my clock does not pass it, however late the interrupt check comes."
	| due |
	due := 16r7FFFFFFFFFFFFFFF.
	(timerMs >= 0 and: [timerMs < (16r7FFFFFFFFFFFFFFF quo: 1000)]) ifTrue: [due := timerMs * 1000].
	(samplerIntervalUs > 0 and: [samplerNextUs < due]) ifTrue: [due := samplerNextUs].
	(frameSema ~= 0 and: [frameNextUs < due]) ifTrue: [due := frameNextUs].
	(sliceDueUs ~= 0 and: [sliceDueUs < due]) ifTrue: [due := sliceDueUs].
	^due
!
workClockSync
	"Advance the clock by the work done since the last time (paced: at least by the real time gone by), stopping at the next deadline; answer it."
	| us raw next due |
	((workClockRunning or: [workClockPaced]) and: [workClockHeld not]) ifFalse: [^workClockUs].
	us := (self workClockThreadCycles - workClockCycles) quo: WORK_CYCLES_PER_US.
	workClockCycles := workClockCycles + (us * WORK_CYCLES_PER_US).
	raw := 0.
	workClockPaced ifTrue: [
		raw := self rawNowUs.
		raw - workClockRaw > us ifTrue: [us := raw - workClockRaw]].
	next := workClockUs.
	us > 0 ifTrue: [
		next := workClockUs + us.
		due := self workClockDeadline.
		next > due ifTrue: [next := due]].
	"Paced, real time past the deadline is counted after it (the next sync), not dropped."
	workClockPaced ifTrue: [
		workClockRaw := workClockRaw + (next - workClockUs max: 0).
		workClockRaw > raw ifTrue: [workClockRaw := raw]].
	next > workClockUs ifTrue: [workClockUs := next].
	^workClockUs
!
workClockIdle
	"No Process can run. The clock jumps to the next deadline; paced, it waits for it in real time, or for an outside event (a child's output). Standing still, or with no deadline, only an outside event (the driver's next command) can change anything."
	| now due |
	now := self workClockSync.
	due := self workClockDeadline.
	((workClockRunning or: [workClockPaced]) and: [due ~= 16r7FFFFFFFFFFFFFFF]) ifFalse: [
		self tickSetIdle: true.
		platform wait: -1.
		self tickSetIdle: false.
		^self].
	workClockPaced ifTrue: [
		due > now ifTrue: [
			self tickSetIdle: true.
			platform wait: due - now.
			self tickSetIdle: false].
		^self].
	due > now ifTrue: [workClockUs := due].
	workClockCycles := self workClockThreadCycles
!
workClockIdleWait
	self workClockIdle.
	self handleInterrupts.
	self resumeCharging.
	inIdle := false
!
workClockFrameDue
	frameIndex := frameIndex + 1.
	frameNextUs := frameOriginUs + ((((frameIndex * 1000) + frameFps - 1) quo: frameFps) * 1000).
	self signalIndex: frameSema
!
lowestRunList
	"The first run list that may run: while the work clock stands still, only the control Processes do."
	^(workClockOn and: [(workClockRunning or: [workClockPaced or: [workClockQuerying]]) not]) ifTrue: [WORK_CLOCK_FLOOR - 1] ifFalse: [0]
! !

!Scheduler methodsFor: 'ticker'!
tickFired: ident
	"The Ticker's thread: timer ident (TICK_DEADLINE, TICK_POLL) fired; request an interrupt check."
	<function>
	ident = TICK_DEADLINE ifTrue: [self atomicStore: #tickDeadlineFired value: true].
	self requestInterruptCheck
!
tickUpdate
	"A pending one-shot is not armed twice; one that fired before its deadline (clock skew) is armed again."
	<function>
	| due poll now |
	due := 16r7FFFFFFFFFFFFFFF.
	poll := tickIdle ifTrue: [0] ifFalse: [workClockOn ifTrue: [WORK_CLOCK_POLL_US] ifFalse: [tickPollUs]].
	now := self nowUs.
	(tickIdle or: [workClockOn]) ifFalse: [
		(timerMs >= 0 and: [timerMs < (16r7FFFFFFFFFFFFFFF quo: 1000)]) ifTrue: [due := timerMs * 1000].
		(samplerIntervalUs > 0 and: [samplerNextUs < due]) ifTrue: [due := samplerNextUs].
		(sliceDueUs ~= 0 and: [sliceDueUs < due]) ifTrue: [due := sliceDueUs]].
	((self atomicExchange: #tickDeadlineFired value: false) or: [due ~= tickArmedDeadline]) ifTrue: [
		due <= now ifTrue: [self requestInterruptCheck].
		ticker arm: TICK_DEADLINE microseconds: ((due = 16r7FFFFFFFFFFFFFFF or: [due <= now]) ifTrue: [-1] ifFalse: [due - now]) periodic: false.
		tickArmedDeadline := due].
	poll ~= tickArmedPoll ifTrue: [
		ticker arm: TICK_POLL microseconds: (poll ~= 0 ifTrue: [poll] ifFalse: [-1]) periodic: true.
		tickArmedPoll := poll]
!
tickSetIdle: aBoolean
	<function>
	tickIdle := aBoolean.
	self tickUpdate
!
requestPeriodicPoll: intervalUs
	"While Smalltalk runs, check interrupts (and so poll the platform) at least every intervalUs; 0 = only on request."
	<var: #intervalUs type: 'int64_t'>
	<export>
	tickPollUs := intervalUs > 0 ifTrue: [intervalUs] ifFalse: [0].
	self tickUpdate
!
init
	<function>
	startUs := self rawNowUs.
	lastPreempted := memory nilOop.
	allocSampleClass := memory nilOop.
	self resumeCharging.
	ticker start
! !

!Scheduler methodsFor: 'linked lists'!
addLastLink: link to: list
	<function>
	self storeRef: link at: PROC_NEXT put: memory nilOop.
	(self loadRef: list at: LL_FIRST) = memory nilOop
		ifTrue: [self storeRef: list at: LL_FIRST put: link]
		ifFalse: [self storeRef: (self loadRef: list at: LL_LAST) at: PROC_NEXT put: link].
	self storeRef: list at: LL_LAST put: link.
	self storeRef: link at: PROC_MYLIST put: list
!
removeFirstLink: list
	<function>
	| first next |
	first := self loadRef: list at: LL_FIRST.
	first = memory nilOop ifTrue: [^memory nilOop].
	next := self loadRef: first at: PROC_NEXT.
	self storeRef: list at: LL_FIRST put: next.
	next = memory nilOop ifTrue: [self storeRef: list at: LL_LAST put: memory nilOop].
	self storeRef: first at: PROC_NEXT put: memory nilOop.
	self storeRef: first at: PROC_MYLIST put: memory nilOop.
	^first
!
addFirstLink: link to: list
	<function>
	self storeRef: link at: PROC_NEXT put: (self loadRef: list at: LL_FIRST).
	(self loadRef: list at: LL_FIRST) = memory nilOop ifTrue: [self storeRef: list at: LL_LAST put: link].
	self storeRef: list at: LL_FIRST put: link.
	self storeRef: link at: PROC_MYLIST put: list
!
removeLink: link from: list
	<function>
	| prev cur next |
	prev := memory nilOop.
	cur := self loadRef: list at: LL_FIRST.
	[cur ~= memory nilOop and: [cur ~= link]] whileTrue: [
		prev := cur.
		cur := self loadRef: cur at: PROC_NEXT].
	cur = memory nilOop ifTrue: [^false].
	next := self loadRef: link at: PROC_NEXT.
	prev = memory nilOop
		ifTrue: [self storeRef: list at: LL_FIRST put: next]
		ifFalse: [self storeRef: prev at: PROC_NEXT put: next].
	(self loadRef: list at: LL_LAST) = link ifTrue: [self storeRef: list at: LL_LAST put: prev].
	self storeRef: link at: PROC_NEXT put: memory nilOop.
	self storeRef: link at: PROC_MYLIST put: memory nilOop.
	^true
! !

!Scheduler methodsFor: 'scheduling'!
processor
	^memory special: SO_PROCESSOR
!
activeProcess
	<function>
	^self loadRef: self processor at: SCHED_ACTIVE
!
priorityOf: p
	<function>
	| v pr |
	v := self loadRef: p at: PROC_PRIORITY.
	pr := (self isInt: v) ifTrue: [self intVal: v] ifFalse: [1].
	^pr < 1 ifTrue: [1] ifFalse: [pr > 80 ifTrue: [80] ifFalse: [pr]]
!
runList: pri
	^self loadRef: (self loadRef: self processor at: SCHED_LISTS) at: pri - 1
!
transferTo: aProcess
	"Save the active context into the outgoing process and switch to aProcess."
	<function>
	| proc old now ctx |
	proc := self local: 'oop'.
	proc value: aProcess.
	memory pushRoot: proc.
	interpreter materializeAll.
	memory popRoot.
	old := self activeProcess.
	"only the process that ran into the safepoint is at an entry"
	interpreter safepointAtEntry: false.
	proc value = lastPreempted ifTrue: [lastPreemptedAtEntry := false].
	now := self rawNowNs.
	self ledgerAdd: old ns: now - sliceStartNs.
	sliceStartNs := now.
	(ledgerN = LEDGER_SIZE or: [now - windowStartNs >= RECONCILE_NS]) ifTrue: [self reconcile].
	self storeRef: old at: PROC_SUSPENDED put: interpreter activeCtx.
	self storeRef: self processor at: SCHED_ACTIVE put: proc value.
	ctx := self loadRef: proc value at: PROC_SUSPENDED.
	((self isPtr: ctx) not or: [ctx = memory nilOop]) ifTrue: [self fatal: 'resuming a process without a context'].
	self storeRef: proc value at: PROC_SUSPENDED put: memory nilOop.
	interpreter activeCtx: ctx.
	gc rememberIfOld: ctx.
	statProcessSwitches := statProcessSwitches + 1.
	self sliceCheck
!
idleWait
	<function>
	| now wait |
	inIdle := true.
	sliceDueUs := 0.
	sliceExpired := false.
	self pauseCharging.
	(pendingExtN = 0 and: [allocSamplePending not]) ifTrue: [
		workClockOn ifTrue: [^self workClockIdleWait].
		now := self nowUs.
		wait := 16r7FFFFFFFFFFFFFFF.
		timerMs >= 0 ifTrue: [wait := (timerMs * 1000) - now].
		(samplerIntervalUs > 0 and: [samplerNextUs - now < wait]) ifTrue: [wait := samplerNextUs - now].
		self tickSetIdle: true.
		wait = 16r7FFFFFFFFFFFFFFF
			ifTrue: [platform wait: -1]
			ifFalse: [wait > 0 ifTrue: [platform wait: wait]].
		self tickSetIdle: false].
	self handleInterrupts.
	self resumeCharging.
	inIdle := false
!
transferToHighest
	<function>
	| lists l |
	[lists := self loadRef: self processor at: SCHED_LISTS.
	 (self numSlots: lists) asInt64 - 1 to: self lowestRunList by: -1 do: [:i |
		l := self loadRef: lists at: i.
		(self loadRef: l at: LL_FIRST) ~= memory nilOop ifTrue: [
			self transferTo: (self removeFirstLink: l).
			^self]].
	 self idleWait] repeat
!
resumeProcess: proc
	<function>
	| active |
	active := self activeProcess.
	(inIdle not and: [(self priorityOf: proc) > (self priorityOf: active)])
		ifTrue: [
			"Profiler wakeups must not reorder the run queue: they would act as a 1 ms time slicer and bias the samples."
			preemptToFront
				ifTrue: [self addFirstLink: active to: (self runList: (self priorityOf: active))]
				ifFalse: [self addLastLink: active to: (self runList: (self priorityOf: active))].
			lastPreempted := active.
			lastPreemptedAtEntry := interpreter safepointAtEntry.
			self transferTo: proc]
		ifFalse: [
			self addLastLink: proc to: (self runList: (self priorityOf: proc)).
			(inIdle not and: [(self priorityOf: proc) = (self priorityOf: active)]) ifTrue: [self sliceCheck]]
!
suspendActive
	<function>
	self transferToHighest
!
semaphoreSignal: sem
	<function>
	| ex |
	(self loadRef: sem at: LL_FIRST) = memory nilOop
		ifTrue: [
			ex := self loadRef: sem at: SEM_EXCESS.
			self storeRef: sem at: SEM_EXCESS put: (self intOop: ((self isInt: ex) ifTrue: [self intVal: ex] ifFalse: [0]) + 1)]
		ifFalse: [self resumeProcess: (self removeFirstLink: sem)]
!
semaphoreWait: sem
	<function>
	| ex |
	ex := self loadRef: sem at: SEM_EXCESS.
	((self isInt: ex) and: [(self intVal: ex) > 0]) ifTrue: [
		self storeRef: sem at: SEM_EXCESS put: (self intOop: (self intVal: ex) - 1).
		^self].
	self addLastLink: self activeProcess to: sem.
	self transferToHighest
!
processorYield
	<function>
	| active l |
	active := self activeProcess.
	l := self runList: (self priorityOf: active).
	(self loadRef: l at: LL_FIRST) = memory nilOop ifTrue: [^self].
	self addLastLink: active to: l.
	self transferTo: (self removeFirstLink: l)
! !

!Scheduler methodsFor: 'interrupt handling'!
isSemaphore: s
	^(self isPtr: s) and: [s ~= memory nilOop and: [(self fmtHasPointers: (self formatOf: s)) and: [(self numSlots: s) > SEM_EXCESS]]]
!
signalIndex: index
	<function>
	| ext s |
	ext := memory special: SO_EXTERNAL_OBJECTS.
	(index < 1 or: [(self isPtr: ext) not or: [ext = memory nilOop or: [index asUInt32 > (self numSlots: ext)]]]) ifTrue: [^self].
	s := self loadRef: ext at: index - 1.
	(self isSemaphore: s) ifTrue: [self semaphoreSignal: s]
!
handleInterrupts
	<function>
	| now s |
	self atomicStore: #interruptPending value: 0.
	platform poll.
	now := self nowUs.
	(timerMs >= 0 and: [(now quo: 1000) >= timerMs]) ifTrue: [
		timerMs := -1.
		s := memory special: SO_TIMER_SEMAPHORE.
		(self isSemaphore: s) ifTrue: [self semaphoreSignal: s]].
	preemptToFront := true.
	(samplerIntervalUs > 0 and: [now >= samplerNextUs]) ifTrue: [
		"keep the phase, so the mean interval is exact even if interrupt checks come late"
		samplerNextUs := samplerNextUs + samplerIntervalUs.
		samplerNextUs <= now ifTrue: [samplerNextUs := now + samplerIntervalUs].
		samplerTickUnread := true.
		self signalIndex: samplerSema].
	allocSamplePending ifTrue: [
		allocSamplePending := false.
		self signalIndex: allocSampleSema].
	preemptToFront := false.
	(frameSema ~= 0 and: [now >= frameNextUs]) ifTrue: [self workClockFrameDue].
	(sliceDueUs ~= 0 and: [inIdle not and: [now >= sliceDueUs]]) ifTrue: [
		"The slice is over: the active Process goes to the back of its run list if one of its priority waits; the switch starts the next one's slice. Over while a higher Process interrupted the slice's (the profiler's timer Process, woken in this same check): it stays over, and that Process goes to the back as soon as its priority runs again (sliceCheck)."
		sliceDueUs := 0.
		(self priorityOf: self activeProcess) = slicePriority
			ifTrue: [
				sliceExpired := false.
				self processorYield]
			ifFalse: [sliceExpired := true].
		sliceDueUs = 0 ifTrue: [self tickUpdate]].
	gc finalizationPending ifTrue: [
		gc finalizationPending: false.
		s := memory special: SO_FINALIZATION_SEMAPHORE.
		(self isSemaphore: s) ifTrue: [self semaphoreSignal: s]].
	0 to: pendingExtN - 1 do: [:i | self signalIndex: (pendingExt at: i)].
	pendingExtN := 0.
	self tickUpdate
!
setTimer: ms
	<function>
	timerMs := ms.
	self tickUpdate
!
setTimeSlice: us
	"Equal-priority Processes take turns every us microseconds while more than one is ready (0: they do not)."
	<function>
	sliceUs := us.
	sliceDueUs := 0.
	sliceExpired := false.
	self sliceCheck.
	self tickUpdate
!
sliceCheck
	"After a switch, or a Process made ready at the active one's priority: the slice runs while another Process of the active one's priority is ready (it starts when none ran, or for another priority), and stops when none is; a Process of higher priority interrupting leaves it running."
	<function>
	| pri contended |
	sliceUs = 0 ifTrue: [^self].
	pri := self priorityOf: self activeProcess.
	((sliceDueUs ~= 0 or: [sliceExpired]) and: [pri > slicePriority]) ifTrue: [^self].
	contended := inIdle not and: [(self loadRef: (self runList: pri) at: LL_FIRST) ~= memory nilOop].
	contended
		ifTrue: [
			(sliceExpired and: [pri = slicePriority])
				ifTrue: [
					"its slice ran out while a higher Process ran: due now"
					sliceExpired := false.
					sliceDueUs := self nowUs.
					self tickUpdate]
				ifFalse: [
					(sliceDueUs = 0 or: [slicePriority ~= pri]) ifTrue: [
						sliceExpired := false.
						sliceDueUs := self nowUs + sliceUs.
						slicePriority := pri.
						self tickUpdate]]]
		ifFalse: [
			sliceExpired := false.
			sliceDueUs ~= 0 ifTrue: [
				sliceDueUs := 0.
				self tickUpdate]]
!
processCpuTimeUs: proc
	"cpuTime, settled first if proc is running or has a slice in the ledger."
	<function>
	| ct |
	(inIdle not and: [proc = self activeProcess or: [self inLedger: proc]]) ifTrue: [self reconcile].
	ct := self loadRef: proc at: PROC_CPUTIME.
	^(self isInt: ct) ifTrue: [self intVal: ct] ifFalse: [0]
!
setSampler: intervalUs semaphore: sema
	<function>
	samplerIntervalUs := intervalUs.
	samplerSema := sema.
	samplerNextUs := self nowUs + intervalUs.
	self tickUpdate
!
allocSampleHit: aClass bytes: bytes
	<function>
	allocSampleClass := aClass.
	allocSampleSize := bytes asInt64.
	allocSamplePending := true.
	allocSampleUnread := true.
	self requestInterruptCheck
!
relinquish: microseconds
	<function>
	| us now |
	(pendingExtN ~= 0 or: [allocSamplePending]) ifTrue: [^self].
	self pauseCharging.
	workClockOn
		ifTrue: [self workClockIdle]
		ifFalse: [
			us := microseconds.
			now := self nowUs.
			(timerMs >= 0 and: [(timerMs * 1000) - now < us]) ifTrue: [us := (timerMs * 1000) - now].
			(samplerIntervalUs > 0 and: [samplerNextUs - now < us]) ifTrue: [us := samplerNextUs - now].
			us > 0 ifTrue: [
				self tickSetIdle: true.
				platform wait: us.
				self tickSetIdle: false]].
	self resumeCharging.
	self requestInterruptCheck
! !
