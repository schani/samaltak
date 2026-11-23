| check |
check := [:ok :msg | ok ifFalse: [
	Smalltalk vm stderrWrite: msg, (String with: Character lf).
	Smalltalk quit: 1]].
ProtoObject compile: 'c4TryPointerForward: other
	<primitive: ''becomeForward''>
	^#rejected'.
check value: ((1@2 c4TryPointerForward: 3@4) == #rejected) value: 'accepted moving Point'.
check value: ((Message selector: #foo) c4TryPointerForward: (Message selector: #bar)) == #rejected
	value: 'accepted moving Message'.
check value: ((Association key: 1 value: 2) c4TryPointerForward: (Association key: 3 value: 4)) == #rejected
	value: 'accepted moving Association'.
Smalltalk vm stdoutWrite: 'pointer moving rejects ok', (String with: Character lf).
Smalltalk quit: 0
