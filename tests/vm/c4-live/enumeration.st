| check cls child keep weak points result caller witness sawWait isC4 pair target message association overflow |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].
isC4 := Smalltalk vm arguments includes: 'c4-enum'.
cls := Object subclass: #EnumLiveProbe instanceVariableNames: '' classVariableNames: '' package: 'C4-Live-Test'.
child := cls subclass: #EnumLiveChild instanceVariableNames: '' classVariableNames: '' package: 'C4-Live-Test'.
cls class compile: 'leaveWeakIn: weak
	weak at: 1 put: self new.
	self new.
	^nil'.
keep := cls new.
weak := WeakArray new: 1.
cls leaveWeakIn: weak.
child := child new.
result := cls allInstances.
check value: (result size = 1 and: [result first == keep]) value: 'wrong exact class/live-only set'.
check value: child class superclass == cls value: 'subclass lost'.
check value: SmallInteger allInstances isEmpty value: 'returned tagged immediates'.
check value: (UndefinedObject allInstances = (Array with: nil)) value: 'nil not enumerated exactly once'.
points := (1 to: 160) collect: [:i | i @ (i + 5)].
result := Point allInstances.
check value: (points allSatisfy: [:p | (result count: [:each | each == p]) = 1])
	value: 'logical Point oop missing or duplicated'.
check value: (points last y = 165) value: 'Point body resolve failed'.

isC4 ifTrue: [
	pair := Array with: (ByteString new: 2).
	target := WideString new: 2.
	pair first becomeForward: target.
	result := WideString allInstances.
	check value: (pair first == target and: [(result count: [:each | each == target]) = 1])
		value: 'forwarded identity missing or duplicated'.
	association := Association key: #enumTest value: points first.
	message := Message selector: #doIt arguments: (Array with: association).
	result := Message allInstances.
	check value: ((result count: [:each | each == message]) = 1 and: [message arguments first == association])
		value: 'Message identity or Association field lost'.
	"An always-runnable lower-priority witness cannot run until the caller
	 parks. Use several sends in case the worker completes an early one."
	caller := Processor activeProcess.
	sawWait := false.
	witness := [
		[sawWait not] whileTrue: [
			sawWait := caller isWaiting.
			Processor yield]]
		newProcess.
	witness priority: (caller priority - 1 max: 1); resume.
	8 timesRepeat: [
		result := Point allInstances.
		check value: (result identityIncludes: points first) value: 'lost live Point on repeat'].
	witness isTerminated ifFalse: [witness terminate].
	check value: sawWait value: 'no lower-priority process ran while the caller waited'.
	Profiler default stop.
	Processor stopTimeSlicer.
	Processor idleProcess suspend.
	Delay primSignal: nil atMilliseconds: 0.
	result := cls allInstances.
	check value: (result size = 1 and: [result first == keep]) value: 'idle completion failed'.
	overflow := (1 to: 4097) collect: [:i | cls new].
	check value: ([cls allInstances. false] on: PrimitiveFailed do: [:e | e return: e selector == #allInstances])
		value: 'overflow did not fail as allInstances'.
	check value: overflow size = 4097 value: 'overflow candidates did not stay live'.
	overflow := nil.
	result := cls allInstances.
	check value: (result size = 1 and: [result first == keep]) value: 'overflow left a stuck query or retained objects'.
	check value: (Smalltalk vm primStatistics first = 0 and: [Smalltalk vm primStatistics second = 0])
		value: 'enumerated through the legacy collector'].
Smalltalk vm stdoutWrite: 'heap enumeration ok', (String with: Character lf).
Smalltalk quit: 0
