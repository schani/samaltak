| receiver method nativeMethod bytes location assert |
assert := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, String lf.
	Smalltalk quit: 1]].
receiver := Array new: 0.
Array compile: 'epochCacheProbe ^ true'.
Array compile: 'epochCacheSender
	| i |
	i := 0.
	[i < 256] whileTrue: [i := i + 1].
	^self epochCacheProbe'.
40 timesRepeat: [assert value: receiver epochCacheSender == true value: 'warm dispatch'].
CHECK_BASELINE ifTrue: [
	assert value: (Array >> #epochCacheSender) jitSendSites notNil value: 'sender did not compile'].
method := Array >> #epochCacheProbe.
"Neither edit flushes the method dictionary."
method bytecodes at: 1 put: 16r72.
assert value: receiver epochCacheSender == false value: 'stale quick return'.
method primitive: 78.
assert value: receiver epochCacheSender == Array value: 'stale primitive descriptor'.
method primitive: 0.
assert value: (receiver perform: #epochCacheProbe) == false value: 'stale perform entry'.
Array compile: 'epochCacheProbe ^ 0'.
40 timesRepeat: [assert value: receiver epochCacheSender == 0 value: 'stale method after replacement'].
Array compile: 'editableEpochMethod
	| i |
	i := 0.
	[i < 256] whileTrue: [i := i + 1].
	^true'.
nativeMethod := Array >> #editableEpochMethod.
40 timesRepeat: [assert value: receiver editableEpochMethod == true value: 'editable method before write'].
CHECK_BASELINE ifTrue: [
	assert value: nativeMethod jitSendSites notNil value: 'editable method never compiled'].
bytes := nativeMethod bytecodes.
location := bytes size - 1.
assert value: (bytes at: location) = 16r71 value: 'unexpected return opcode'.
bytes at: location put: 16r72.
40 timesRepeat: [assert value: receiver editableEpochMethod == false value: 'editable method after write'].
CHECK_BASELINE ifTrue: [
	assert value: nativeMethod jitSendSites notNil value: 'editable method did not recompile'].
Array removeSelector: #editableEpochMethod.
Array removeSelector: #epochCacheProbe.
assert value: ([receiver epochCacheSender. false] on: MessageNotUnderstood do: [:e | true])
	value: 'stale method after removal'.
assert value: (Smalltalk vm primStatistics first = 0 and: [Smalltalk vm primStatistics second = 0])
	value: 'legacy GC used'.
Smalltalk vm stdoutWrite: 'C4 epoch dispatch ok', String lf.
Smalltalk quit: 0
