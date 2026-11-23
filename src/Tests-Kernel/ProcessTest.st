TestCase subclass: #ProcessTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

ProcessTest comment: 'Tests processes, priorities, semaphores, mutexes, delays, shared queues, time slicing and termination with unwinding.

The timer process preempts the running process every few milliseconds and sends it to the back of its run queue (time slicing), wherever it is: after a yield another process of the same priority need not have reached its wait, or anything else. So the tests wait for the state they need (waitUntil:waitsFor:, waitFor:); where the order of the processes itself is the subject, they run at the timing priority, which nothing preempts (atTimingPriority:).'!

!ProcessTest methodsFor: 'helpers'!
waitUntil: aProcess waitsFor: aSemaphore
	self assert: (self waitFor: [aProcess suspendingList == aSemaphore]) description: [aProcess printString, ' does not wait for ', aSemaphore printString]
!
atTimingPriority: aBlock
	"Evaluate aBlock at the highest priority, the timer process's: nothing preempts it or the processes it forks, they switch only where they yield or wait."
	| active priority |
	active := Processor activeProcess.
	priority := active priority.
	active priority: Processor timingPriority.
	^aBlock ensure: [active priority: priority]
! !

!ProcessTest methodsFor: 'tests'!
testForkRuns
	| done sem |
	sem := Semaphore new.
	done := false.
	[done := true. sem signal] fork.
	sem wait.
	self assert: done
!
testPriorityPreemption
	| log |
	log := OrderedCollection new.
	[log add: #high] forkAt: Processor activePriority + 1.
	log add: #main.
	[log add: #low] forkAt: Processor activePriority - 1.
	log add: #main2.
	self assert: log asArray = #(#high #main #main2).
	self assert: (self waitFor: [log size = 4]).
	self assert: log asArray = #(#high #main #main2 #low)
!
testYield
	| log |
	log := OrderedCollection new.
	self atTimingPriority: [
		[log add: #other] fork.
		log add: #first.
		Processor yield.
		log add: #second].
	self assert: log asArray equals: #(#first #other #second)
!
testSemaphore
	| sem log first second |
	sem := Semaphore new.
	log := OrderedCollection new.
	first := self fork: [sem wait. log add: 1].
	self waitUntil: first waitsFor: sem.
	second := self fork: [sem wait. log add: 2].
	self waitUntil: second waitsFor: sem.
	self assert: log asArray equals: #().
	sem signal.
	self assert: (self waitFor: [log notEmpty]) description: [first printString, ' was not signaled'].
	self assert: log asArray equals: #(1).
	self assert: second suspendingList == sem description: [second printString, ' does not wait'].
	sem signal; signal.
	self assert: (self waitFor: [log size = 2]) description: [second printString, ' was not signaled'].
	self assert: log asArray equals: #(1 2).
	self assert: sem excessSignals equals: 1.
	sem wait.
	self assert: sem excessSignals equals: 0
!
testCritical
	| mutex log p |
	mutex := Semaphore forMutualExclusion.
	log := OrderedCollection new.
	mutex critical: [
		p := self fork: [mutex critical: [log add: #p]].
		self waitUntil: p waitsFor: mutex.
		log add: #main].
	self assert: (self waitFor: [p isTerminated]) description: [p printString, ' did not end'].
	self assert: log asArray equals: #(#main #p).
	self assert: (mutex critical: [42]) = 42.
	self assert: mutex excessSignals equals: 1.
	self assert: ([mutex critical: [Error signal]] on: Error do: [:e | 1]) = 1.
	self assert: mutex excessSignals = 1
!
testMutexIsReentrant
	| m |
	m := Mutex new.
	self assert: (m critical: [m critical: [7]]) = 7.
	self deny: m isOwned
!
testDelay
	| start elapsed |
	start := Time millisecondClockValue.
	(Delay forMilliseconds: 50) wait.
	elapsed := Time millisecondClockValue - start.
	self assert: elapsed >= 49.
	self assert: elapsed < 1000
!
testDelaysWakeInOrder
	"Delays wake in the order of their resumption times, whatever the order they were scheduled in. The waiting processes have the timing priority: nothing preempts one between its wakeup and its entry in the log."
	| delays log sem |
	delays := #(30 10 20) collect: [:ms | Delay forMilliseconds: ms].
	log := OrderedCollection new.
	sem := Semaphore new.
	delays do: [:each | self fork: [each wait. log add: each. sem signal] at: Processor timingPriority].
	3 timesRepeat: [sem wait].
	self assert: (log collect: [:each | each resumptionTime]) asArray
		equals: (delays collect: [:each | each resumptionTime]) asSortedCollection asArray
!
testWaitTimeout
	| sem start |
	sem := Semaphore new.
	start := Time millisecondClockValue.
	self assert: (sem waitTimeoutMSecs: 30).
	self assert: Time millisecondClockValue - start >= 29.
	[sem signal] fork.
	self deny: (sem waitTimeoutMSecs: 1000).
	sem signal.
	self deny: (sem waitTimeoutMSecs: 0).
	self assert: (sem waitTimeoutMSecs: 0).
	self assert: sem excessSignals = 0
!
testSharedQueue
	| q results consumer |
	q := SharedQueue new.
	results := OrderedCollection new.
	consumer := self fork: [5 timesRepeat: [results add: q next]].
	1 to: 5 do: [:i | q nextPut: i * i].
	self assert: (self waitFor: [results size = 5]).
	self assert: results asArray = #(1 4 9 16 25).
	self assert: q isEmpty.
	self assert: q nextOrNil isNil.
	q nextPut: 7.
	self assert: q peek = 7.
	self assert: q size = 1.
	self assert: q next = 7
!
testRoundRobin
	"Two busy processes of the same priority both make progress (time slicer): neither waits or yields before both have counted, and this process waits for their signal, so only the time slicer can have switched between them."
	| counts stop both procs |
	counts := Array new: 2 withAll: 0.
	stop := false.
	both := Semaphore new.
	procs := (1 to: 2) collect: [:i |
		self fork: [[stop] whileFalse: [
			counts at: i put: (counts at: i) + 1.
			((counts at: 1) > 0 and: [(counts at: 2) > 0]) ifTrue: [both signal]]] at: Processor activePriority - 1].
	self deny: (both waitTimeoutMSecs: 5000) description: ['No time slice in 5 s: counts ', counts printString].
	stop := true.
	self assert: (self waitFor: [procs allSatisfy: [:p | p isTerminated]]) description: [procs printString, ' did not end']
!
testTerminateRunsUnwindBlocks
	| sem log p |
	sem := Semaphore new.
	log := OrderedCollection new.
	p := self fork: [[sem wait. log add: #notReached] ensure: [log add: #ensure]].
	self waitUntil: p waitsFor: sem.
	self deny: p isTerminated.
	p terminate.
	self assert: log asArray equals: #(#ensure).
	self assert: p isTerminated.
	sem signal.
	Processor yield.
	self assert: log asArray equals: #(#ensure).
	self assert: sem excessSignals equals: 1
!
testTerminateActive
	| log done p |
	log := OrderedCollection new.
	done := Semaphore new.
	p := [[log add: #start. Processor activeProcess terminate. log add: #no] ensure: [log add: #ensure. done signal]] fork.
	done wait.
	self assert: (self waitFor: [p isTerminated]) description: [p printString, ' did not end'].
	self assert: log asArray equals: #(#start #ensure)
!
testSuspendResume
	| p count |
	count := 0.
	p := self fork: [[true] whileTrue: [count := count + 1. Processor yield]].
	Processor yield.
	p suspend.
	self assert: p isSuspended.
	count := 0.
	Processor yield.
	self assert: count = 0.
	p resume.
	self assert: (self waitFor: [count > 0]) description: [p printString, ' does not run'].
	p terminate.
	self assert: p isTerminated
!
testProcessAccessors
	| p |
	p := [nil] newProcess.
	p name: 'worker'.
	self assert: p name = 'worker'.
	self assert: p priority = Processor activePriority.
	p priority: 30.
	self assert: p priority = 30.
	self assert: p isSuspended.
	self assert: (p printString includesSubstring: 'worker').
	self assert: Processor activeProcess isActiveProcess.
	self assert: Processor activeProcess priority = Processor activePriority.
	self assert: Processor timingPriority = 80.
	self assert: Processor idleProcess priority = 1.
	self should: [p priority: 0] raise: Error.
	p terminate
!
testSignalException
	| sem p caught done |
	sem := Semaphore new.
	done := Semaphore new.
	caught := nil.
	p := self fork: [[sem wait] on: ZeroDivide do: [:e | caught := e class]. done signal].
	self waitUntil: p waitsFor: sem.
	p signalException: ZeroDivide new.
	done wait.
	self assert: caught == ZeroDivide
!
testValueWithin
	self assert: ([3 + 4] valueWithin: 1000 onTimeout: [#timeout]) = 7.
	self assert: ([Semaphore new wait. 1] valueWithin: 20 onTimeout: [#timeout]) = #timeout
!
testCpuTime
	| p sem |
	sem := Semaphore new.
	p := [1 to: 20000 do: [:i | i * i]. sem signal] fork.
	sem wait.
	self assert: p cpuTime >= 0
!
testRegistryHasEveryProcess
	| procs live |
	procs := (1 to: 300) collect: [:i | [nil] newProcess].
	live := Processor allProcesses asIdentitySet.
	self assert: (procs allSatisfy: [:p | live includes: p]).
	self assert: (live includes: Processor activeProcess).
	procs do: [:p | p terminate]
!
testRegistryKeepsRunnableAndSuspendedProcesses
	| runnable suspended ticks finalizers finalized all |
	runnable := Array new: 3.
	suspended := Array new: runnable size.
	ticks := Array new: runnable size withAll: 0.
	runnable withIndexDo: [:unused :i |
		suspended at: i put: (self track: [nil] newProcess).
		runnable at: i put: (self fork: [[true] whileTrue: [
			self spin: 1000.
			ticks at: i put: (ticks at: i) + 1.
			Processor yield]] at: Processor activePriority - 1)].
	finalizers := WeakRegistry new.
	finalized := Semaphore new.
	finalizers add: Object new executor: [finalized signal].
	self collectUntil: [(finalized waitTimeoutMSecs: 50) not].
	self assert: finalizers size equals: 0.
	self assert: (self waitFor: [ticks allSatisfy: [:n | n > 0]]) description: [ticks printString].
	all := Processor allProcesses asIdentitySet.
	self assert: (all includes: Processor activeProcess).
	runnable do: [:p |
		self assert: (all includes: p).
		self assert: p isRunnable description: 'Worker was not runnable'.
		self assert: p cpuMicroseconds > 0 description: 'Worker CPU time was not charged'].
	suspended do: [:p |
		self assert: (all includes: p).
		self assert: p isSuspended description: 'Suspended process changed state'.
		self assert: p cpuMicroseconds equals: 0]
!
testRegistryReusesCollectedSlots
	| capacity procs weak |
	procs := (1 to: 2000) collect: [:i | [nil] newProcess].
	weak := WeakArray new: procs size.
	weak replaceFrom: 1 to: procs size with: procs startingAt: 1.
	procs := nil.
	self collectUntil: [weak allSatisfy: [:p | p isNil]].
	capacity := self registryCapacity.
	procs := (1 to: 2000) collect: [:i | [nil] newProcess].
	self assert: self registryCapacity equals: capacity.
	procs do: [:p | p terminate]
!
testRegistryStaysSmall
	| sem |
	sem := Semaphore new.
	20000 timesRepeat: [[sem wait] forkAt: Processor activePriority + 1].
	self assert: self registryCapacity <= 65536.
	self assert: Processor allProcesses size > 20000.
	20000 timesRepeat: [sem signal]
!
testRegistryShrinksAfterABurst
	"A burst of processes gone and collected, the next allProcesses compacts the registry; it still has every process, and registers the next ones."
	| kept sem burst later all |
	kept := (1 to: 100) collect: [:i | [nil] newProcess].
	sem := Semaphore new.
	burst := self waitingProcesses: 5000 on: sem.
	self assert: self registryCapacity >= 8192.
	5000 timesRepeat: [sem signal].
	self collectBurst: burst.
	Processor allProcesses.
	self assert: self registryCapacity < 5000.
	self assert: self registryCapacity <= (64 max: self registered * 4).
	later := (1 to: 1000) collect: [:i | [nil] newProcess].
	all := Processor allProcesses asIdentitySet.
	self assert: (kept allSatisfy: [:p | all includes: p]).
	self assert: (later allSatisfy: [:p | all includes: p]).
	self assert: (all includes: Processor activeProcess).
	kept do: [:p | p terminate].
	later do: [:p | p terminate]
!
testRegistryShrinksWhileProcessesRegister
	"A process of higher priority goes on registering processes while bursts come and go and the registry is compacted: none is lost."
	| made done finished sem burst all |
	made := OrderedCollection new.
	done := false.
	finished := Semaphore new.
	self fork: [[done] whileFalse: [
		made add: [nil] newProcess.
		(Delay forMilliseconds: 1) wait].
		finished signal] at: Processor activePriority + 1.
	5 timesRepeat: [
		sem := Semaphore new.
		burst := self waitingProcesses: 2000 on: sem.
		2000 timesRepeat: [sem signal].
		self collectBurst: burst.
		Processor allProcesses.
		self assert: self registryCapacity <= (64 max: self registered * 4)].
	done := true.
	finished wait.
	all := Processor allProcesses asIdentitySet.
	self assert: made notEmpty.
	self assert: (made allSatisfy: [:p | all includes: p]).
	made do: [:p | p terminate]
!
testRegistryAnswersNoCollectedProcess
	| weak |
	weak := self unreferencedProcesses: 100.
	self collectUntil: [weak allSatisfy: [:p | p isNil]].
	self assert: (Processor allProcesses allSatisfy: [:p | p notNil and: [p isTerminated not]])
!
testCpuTimeAddsUp
	"While two processes switch 100,000 times, the Processes are charged the VM thread's CPU time, but for the JIT's compiling: all of them, as others run meanwhile (the timer Process sampling for the profiler, finalization). The thread clock is read inside the Processes' readings, the JIT's time inside the thread clock's."
	| a b c0 t0 j0 j1 t1 c t |
	a := Semaphore new.
	b := Semaphore new.
	self partner: 50000 waitOn: a signal: b spin: 0.
	c0 := self cpuTimes.
	t0 := Smalltalk vm threadCpuMicroseconds.
	j0 := Smalltalk vm statistics jitCompileMicroseconds.
	50000 timesRepeat: [a signal. b wait].
	j1 := Smalltalk vm statistics jitCompileMicroseconds.
	t1 := Smalltalk vm threadCpuMicroseconds.
	c := self cpuMicrosecondsSince: c0.
	t := t1 - t0 - (j1 - j0).
	self assert: (c - t) abs <= 2000
!
testShortSlicesAreCharged
	"Both sides of a fast ping-pong are charged, the one that works three times as much more."
	| a b me other m0 o0 mine its |
	a := Semaphore new.
	b := Semaphore new.
	me := Processor activeProcess.
	other := self partner: 2000 waitOn: a signal: b spin: 3000.
	Smalltalk vm scavenge.
	m0 := me cpuMicroseconds.
	o0 := other cpuMicroseconds.
	2000 timesRepeat: [self spin: 1000. a signal. b wait].
	mine := me cpuMicroseconds - m0.
	its := other cpuMicroseconds - o0.
	self assert: mine > 0.
	self assert: its > mine.
	self assert: its < (mine * 10)
!
testCpuTimeNeverDecreases
	| a b me other last mine |
	a := Semaphore new.
	b := Semaphore new.
	me := Processor activeProcess.
	other := self partner: 10000 waitOn: a signal: b spin: 0.
	last := 0.
	mine := 0.
	10000 timesRepeat: [| ct cm own |
		a signal.
		b wait.
		ct := other cpuTime.
		cm := other cpuMicroseconds.
		own := me cpuMicroseconds.
		self assert: ct >= last.
		self assert: cm >= ct.
		self assert: own >= mine.
		last := cm.
		mine := own]
!
testWaitsAreNotCharged
	| done p c0 idle i0 |
	done := Semaphore new.
	p := self fork: [20 timesRepeat: [(Delay forMilliseconds: 10) wait]. done signal] at: Processor activePriority + 1.
	c0 := p cpuMicroseconds.
	done wait.
	self assert: p cpuMicroseconds - c0 < 5000.
	idle := Processor idleProcess.
	i0 := idle cpuMicroseconds.
	(Delay forMilliseconds: 200) wait.
	self assert: idle cpuMicroseconds - i0 < 5000
!
testCpuTimeIsChargedInBatches
	"The VM thread's CPU time, a system call to read, is read far less often than processes switch."
	| a b s |
	a := Semaphore new.
	b := Semaphore new.
	self partner: 50000 waitOn: a signal: b spin: 0.
	s := Smalltalk vm statistics.
	50000 timesRepeat: [a signal. b wait].
	s := Smalltalk vm statistics - s.
	self assert: s processSwitches >= 100000.
	self assert: s cpuTimeReconciles < (s processSwitches // 20)
! !

!ProcessTest methodsFor: 'support'!
unreferencedProcesses: anInteger
	"Answer a WeakArray of anInteger new processes nothing else references."
	| weak |
	weak := WeakArray new: anInteger.
	1 to: anInteger do: [:i | weak at: i put: [nil] newProcess].
	^weak
!
waitingProcesses: count on: semaphore
	| weak |
	weak := WeakArray new: count.
	1 to: count do: [:i |
		weak at: i put: ([semaphore wait] forkAt: Processor activePriority + 1)].
	^weak
!
collectBurst: weak
	"Terminated processes can still be scheduler roots (e.g. the charging
	ledger). Observe loss of the bulk of the burst, not of every last entry."
	self collectUntil: [(weak count: [:p | p isNil]) >= (weak size * 9 // 10)]
!
collectUntil: cleared
	"The copying collector supports explicit collection. C4 does not: drive
	natural cycles with bounded pressure and check the actual targets. Check
	sparsely: a weak read before close may keep an object for that cycle."
	| fullGCs |
	fullGCs := Smalltalk vm statistics fullGCs.
	Smalltalk vm garbageCollect.
	Smalltalk vm statistics fullGCs = fullGCs ifTrue: [
		32 timesRepeat: [
			ByteArray new: 4 * 1024 * 1024.
			(Delay forMilliseconds: 25) wait.
			cleared value ifTrue: [^self]]].
	self assert: cleared description: 'Expected collection was not observed'
!
registered
	"How many processes the registry holds."
	^(Process classPool at: #Registry) count: [:each | each notNil]
!
registryCapacity
	^(Process classPool at: #Registry) size
!
cpuTimes
	"Every live Process's CPU time, by Process."
	| times |
	times := IdentityDictionary new.
	Process allLive do: [:p | times at: p put: p cpuMicroseconds].
	^times
!
cpuMicrosecondsSince: times
	"The CPU time charged since cpuTimes answered times to the Processes in it (also those that have terminated since) and to those started since."
	| sum |
	sum := 0.
	times keysAndValuesDo: [:p :us | sum := sum + p cpuMicroseconds - us].
	Process allLive do: [:p | (times includesKey: p) ifFalse: [sum := sum + p cpuMicroseconds]].
	^sum
!
partner: n waitOn: a signal: b spin: work
	"Answer a process at my priority that, n times, waits on a, spins work times and signals b; it is waiting on a."
	| p |
	p := self fork: [n timesRepeat: [a wait. self spin: work. b signal]].
	Processor yield.
	^p
!
spin: n
	| x |
	x := 0.
	1 to: n do: [:i | x := x + i bitAnd: 16rFFFF].
	^x
! !
