| slots mode owner survivor probe stats check filled step |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, String lf.
	Smalltalk quit: 1]].
slots := Smalltalk at: #C4WorkerSlots.
mode := Smalltalk at: #C4WorkerMode.
Profiler default stop.
Processor stopTimeSlicer.
survivor := Array with: 73.
mode = #strong
	ifTrue: [
		owner := Array new: slots.
		probe := WeakArray new: 2.
		probe at: 1 put: survivor]
	ifFalse: [
		owner := BulkReferenceWeakArray new: slots.
		owner tag: survivor.
		probe := owner].
check value: (owner first isNil and: [owner last isNil]) value: 'expected nil-filled array'.
owner at: 1 put: survivor; at: slots // 2 put: survivor; at: slots - 1 put: survivor.
mode = #dense ifTrue: [
	"Keep the strong tag and fill the weak suffix in the VM's bulk copy path."
	filled := 1.
	[filled < slots] whileTrue: [
		step := filled min: slots - filled.
		owner replaceFrom: filled + 1 to: filled + step with: owner startingAt: 1.
		filled := filled + step]].
probe at: probe size put: (ByteArray new: 65536).
survivor := nil.
C4WORKERROUNDS timesRepeat: [
	256 timesRepeat: [ByteArray new: 4096].
	(Delay forMilliseconds: C4WORKERDELAY) wait].
check value: (probe last isNil and: [
	(owner first == (owner at: slots // 2)) and: [
	(owner first == (owner at: slots - 1)) and: [owner first first = 73]]])
	value: 'live edge lost or dead weak edge retained'.
mode = #strong
	ifTrue: [check value: (probe first == owner first and: [owner last isNil]) value: 'strong owner']
	ifFalse: [check value: (owner tag == owner first) value: 'weak owner fixed prefix'].
mode = #dense ifFalse: [
	check value: ((owner at: slots // 2 + 1) isNil and: [(owner at: slots // 4) isNil])
		value: 'implicit nil changed'].
stats := Smalltalk vm primStatistics.
check value: ((stats first = 0 and: [stats second = 0]) and: [(stats at: 12) > 0])
	value: 'legacy GC ran or no weak clear'.
Smalltalk vm stdoutWrite: 'C4 sparse worker ok', String lf.
Smalltalk quit: 0
