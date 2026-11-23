| check message binding bindings method weak hash mhash churn after answer stats rejected |
check := [:ok :label | ok ifFalse: [
	Smalltalk vm stderrWrite: label, (String with: Character lf).
	Smalltalk quit: 1]].
message := [(Object new) c4MoveMissing: 17] on: MessageNotUnderstood do: [:ex | ex message].
check value: (message class == Message and: [message selector == #c4MoveMissing: and: [message argument = 17]])
	value: 'VM-created Message fields'.
bindings := Dictionary new.
binding := Association key: #probe value: message.
bindings at: #probe put: binding.
hash := binding identityHash.
mhash := message identityHash.
weak := WeakArray new: 4.
weak at: 1 put: binding; at: 2 put: message;
	at: 3 put: (Association key: #weakOnly value: 10);
	at: 4 put: (Message selector: #weakOnly).
churn := [:cycles |
	cycles timesRepeat: [
		1 to: 900 do: [:i | Association key: #temp value: i. Message selector: #temp].
		after := ByteArray new: 1048576.
		(Delay forMilliseconds: 40) wait.
		1024 timesRepeat: [1 + 2]]].
bindings at: #churn put: (Association key: #churn value: churn).
method := Compiler compileDoIt: '
	churn value: 18.
	probe := {probe. 99}.
	churn value: 18.
	probe' in: UndefinedObject bindings: bindings.
check value: (method literals anySatisfy: [:lit | lit == binding]) value: 'binding missing from pinned literal table'.
rejected := false.
[(CompiledMethod new) instVarAt: 3 put: binding] on: Error do: [:ex | rejected := true].
check value: rejected value: 'movable Association admitted as raw literal storage'.
bindings removeKey: #probe.
binding := nil.
answer := Compiler execute: method for: nil.
binding := weak at: 1.
check value: (binding class == Association and: [binding identityHash = hash and: [binding key == #probe and: [binding value == answer]]])
	value: 'literal binding identity, slot read or bytecode store changed'.
check value: (answer first == message and: [answer second = 99 and: [
	message identityHash = mhash and: [(weak at: 2) == message and: [message argument = 17]]]])
	value: 'Message identity, fields or weak alias changed'.
message instVarAt: 2 put: #(41).
check value: (message shallowCopy argument = 41 and: [(weak at: 2) argument = 41])
	value: 'Message reflective write or shallow copy failed'.
check value: ((weak at: 3) isNil and: [(weak at: 4) isNil]) value: 'weak-only non-Points not cleared'.
check value: (after size = 1048576) value: 'pinned allocation lost'.
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0]) value: 'legacy collection ran'.
Smalltalk vm stdoutWrite: 'C4 moving Associations and Messages ok', (String with: Character lf).
Smalltalk quit: 0
