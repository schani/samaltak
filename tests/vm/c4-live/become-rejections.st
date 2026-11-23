| check target original replacement bcs |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].
ProtoObject compile: 'c4TryBecome: other
	<primitive: ''becomeForward''>
	^#rejected'.
target := WideString new: 1.
check value: (#c4Symbol c4TryBecome: target) == #rejected value: 'accepted ByteSymbol source'.
check value: ((ByteArray new: 1) c4TryBecome: target) == #rejected value: 'accepted ByteArray source'.
check value: ((ByteString new: 1) c4TryBecome: (ByteString new: 1)) == #rejected value: 'accepted ByteString target'.
check value: (target c4TryBecome: (WideString new: 1)) == #rejected value: 'accepted WideString source'.
check value: (Object new c4TryBecome: Object new) == #rejected value: 'accepted general become'.
check value: ((ByteString new: 1) c4TryBecome: target) == target value: 'rejected bounded become'.

StringTest compile: 'c4BorrowedBytecodes
	^(StringTest >> #c4BorrowedBytecodes) bytecodes c4TryBecome: (WideString new: 32)'.
original := StringTest >> #c4BorrowedBytecodes.
bcs := ByteString new: original bytecodes size.
1 to: bcs size do: [:i | bcs basicAt: i put: (original bytecodes at: i)].
replacement := CompiledMethod new
	selector: original selector;
	literals: original literals;
	bytecodes: bcs;
	numArgs: original numArgs;
	numTemps: original numTemps;
	frameSize: original frameSize;
	yourself.
StringTest addSelector: original selector withMethod: replacement.
check value: StringTest new c4BorrowedBytecodes == #rejected value: 'accepted borrowed ByteString bytecodes'.
check value: bcs class == ByteString value: 'failed become changed code storage'.
check value: ((Smalltalk vm primStatistics first = 0) and: [Smalltalk vm primStatistics second = 0])
	value: 'legacy collection ran in C4'.
Smalltalk vm stdoutWrite: 'become rejections ok', (String with: Character lf).
Smalltalk quit: 0
