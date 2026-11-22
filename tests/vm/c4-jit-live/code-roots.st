| check probe marker takeOut query before weak |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, String lf.
	Smalltalk quit: 1]].
probe := Object subclass: #DenseCodeOwner instanceVariableNames: '' classVariableNames: '' package: 'C4-Live-Test'.
marker := Object subclass: #DenseCodeMarker instanceVariableNames: '' classVariableNames: '' package: 'C4-Live-Test'.
weak := WeakArray new: 1.
takeOut := [
	| method n |
	probe compile: 'denseCodeWitness
	| i |
	i := 0.
	[i < 512] whileTrue: [i := i + 1].
	^#denseRootLiteral'.
	method := probe methodDict at: #denseCodeWitness.
	n := method literals indexOf: #denseRootLiteral.
	check value: n > 0 value: 'probe literal missing'.
	method literals at: n put: marker new.
	weak at: 1 put: probe new denseCodeWitness.
	check value: (method jitSendSites notNil) value: 'probe never installed native code'.
	probe methodDict removeKey: #denseCodeWitness.
	probe flushCacheFor: #denseCodeWitness.
	method := nil].
takeOut value.
"Churn through mark cuts with no Smalltalk strong reference to the marker,
then ask a separate enumeration cut to find the code-only literal."
24 timesRepeat: [
	ByteArray new: 1048579.
	(Delay forMilliseconds: 20) wait].
check value: (weak at: 1) notNil value: 'mark lost the cached method or its literal'.
query := [
	| result |
	result := marker allInstances.
	check value: (result size = 1 and: [result first == (weak at: 1)])
		value: 'enumeration lost the code-only literal'.
	result := nil].
query value.
before := Smalltalk vm statistics.
Smalltalk vm jitParameters: {'none'. nil. nil. nil}.
check value: marker allInstances isEmpty value: 'stale code remained a root after flush'.
check value: ((Smalltalk vm statistics - before) jitCacheFlushes > 0)
	value: 'tier exit did not flush the old generation'.
24 timesRepeat: [
	ByteArray new: 1048579.
	(Delay forMilliseconds: 125) wait].
check value: (weak at: 1) isNil value: 'stale code literal still retained by marking'.
check value: (Smalltalk vm primStatistics first = 0 and: [Smalltalk vm primStatistics second = 0])
	value: 'legacy GC used'.
Smalltalk vm stdoutWrite: 'c4-jit code roots ok', String lf.
Smalltalk quit: 0
