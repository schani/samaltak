| real mixed clone signal keepers check filler stats |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].

"Exercise Process registry growth and make finalization the only wakeup."
Profiler default stop.
Processor stopTimeSlicer.
Processor idleProcess suspend.
Delay primSignal: nil atMilliseconds: 0.
signal := Semaphore new.
Smalltalk vm finalizationSemaphore: signal.
keepers := (1 to: 100) collect: [:i | [] newProcess name: 'c4-weak-probe'; yourself].
check value: ((Process allLive count: [:p | p name = 'c4-weak-probe']) = keepers size)
	value: 'process registry lost live entries'.

real := WeakArray new: 1.
real at: 1 put: (ByteArray new: 2097153).
check value: (real at: 1) size = 2097153 value: 'weak load before collection'.
mixed := BulkReferenceWeakArray new: 4.
mixed tag: (Array with: #strong).
mixed at: 1 put: 23; at: 2 put: mixed tag; at: 3 put: $x.
mixed replaceFrom: 2 to: 4 with: mixed startingAt: 1.
mixed replaceFrom: 1 to: 3 with: mixed startingAt: 2.
clone := mixed shallowCopy.
mixed := nil.
keepers := nil.
"Keep pressure storage live, so it can't account for the reclaimed bytes.
Do not read the weak target during marking; a read may keep it alive."
filler := ByteArray new: 8388608.
signal wait.
check value: (real at: 1) isNil value: 'weak-only target not cleared'.
check value: (clone tag = #(strong) and: [(clone at: 2) == clone tag])
	value: 'fixed field did not retain weak target'.
check value: ((clone at: 1) = 23 and: [(clone at: 3) = $x and: [(clone at: 4) = $x]])
	value: 'weak immediates, copy or overlap failed'.
check value: (Process allLive noneSatisfy: [:p | p name = 'c4-weak-probe'])
	value: 'process registry retained unreachable processes'.
"Let the worker finish publishing reusable blocks, with the normal timer."
(Delay forMilliseconds: 50) wait.
check value: filler size = 8388608 value: 'pressure allocation lost'.
stats := Smalltalk vm primStatistics.
check value: ((stats first = 0 and: [stats second = 0]) and: [(stats at: 12) > 0])
	value: 'expected weak clears without legacy collection'.
Smalltalk vm stdoutWrite: 'C4 weak and idle finalization ok', (String with: Character lf).
Smalltalk quit: 0
