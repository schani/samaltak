| check same reject src dst h pointHash keep weak result assoc msg cm probe |
check := [:ok :why | ok ifFalse: [
	Smalltalk vm stderrWrite: why, (String with: Character lf).
	Smalltalk quit: 1]].
same := [:a :b | a == b].
reject := [:mode | [Smalltalk vm jitMode: mode. false] on: Error do: [:e | true]].
check value: (Smalltalk vm jitMode = #none and: [(reject value: #baseline) and: [reject value: #opt]])
	value: 'moving forwarding permits native execution'.
check value: Smalltalk vm jitMode = #none value: 'failed tier switch changed mode'.
Processor stopTimeSlicer.
ProtoObject compile: 'c4MoveForwardTo: other
	<primitive: ''becomeForward''>
	^#rejected'.
ProtoObject compile: 'c4TryAllocFromOperand
	<primitive: ''basicNew''>
	^#rejected'.
StringTest compile: 'c4LeaveDeadMovingAliasIn: weak
	| src dst |
	src := 519@17. dst := 520@18.
	weak at: 2 put: src; at: 3 put: dst.
	^(src c4MoveForwardTo: dst) == dst'.

src := 10@20.
dst := 987654321@40.
src identityHash.
h := pointHash := dst identityHash.
keep := Array with: src.
weak := WeakArray new: 3.
weak at: 1 put: src.
check value: ((src c4MoveForwardTo: dst) == dst) value: 'two moving Points not admitted'.
check value: ((same value: src value: dst) and: [src identityHash = h and: [src x = 987654321]])
	value: 'alias identity/hash or field read'.
src instVarAt: 2 put: 400.
check value: (dst y = 400) value: 'alias reflective store missed target'.
check value: ((src c4MoveForwardTo: 5@6) == #rejected) value: 'accepted an alias to terminal as source'.
check value: (src c4TryAllocFromOperand == #rejected) value: 'accepted Point alias as Behavior'.
cm := CompiledMethod new.
check value: ([cm instVarAt: 3 put: src. false] on: Error do: [:e | true])
	value: 'accepted Point alias as literal backing'.
check value: ([cm instVarAt: 4 put: src. false] on: Error do: [:e | true])
	value: 'accepted Point alias as bytecode backing'.
check value: (((1 to: 5) c4MoveForwardTo: (2 to: 6)) == #rejected)
	value: 'accepted Interval as donor'.

msg := Message selector: #old argument: 21.
dst := Message selector: #new argument: 33.
h := dst identityHash.
check value: ((msg c4MoveForwardTo: dst) == dst and: [
	msg identityHash = h and: [msg selector == #new and: [msg argument = 33]]])
	value: 'Message identity/hash or fields changed'.

Smalltalk at: #C4MovingForwardProbe put: 41.
StringTest compile: 'c4MovingForwardBinding
	^C4MovingForwardProbe'.
probe := StringTest new.
check value: probe c4MovingForwardBinding = 41 value: 'initial literal Association invalid'.
assoc := Smalltalk associationAt: #C4MovingForwardProbe.
dst := Association key: #C4MovingForwardProbe value: 78.
h := dst identityHash.
check value: ((assoc c4MoveForwardTo: dst) == dst and: [
	assoc identityHash = h and: [probe c4MovingForwardBinding = 78]])
	value: 'moving Association missed through pinned literal table'.
Smalltalk removeKey: #C4MovingForwardProbe.

src := ByteString new: 2.
dst := WideString new: 2.
check value: ((src c4MoveForwardTo: dst) == dst and: [src class == WideString])
	value: 'pinned ByteString forwarding changed'.
src := dst := nil.
check value: (StringTest new c4LeaveDeadMovingAliasIn: weak) value: 'weak-only install failed'.

"Keep the watched Point only through a raw strong donor slot, and do not
read the weak alias before CLEAR."
24 timesRepeat: [
	1 to: 512 do: [:i | i@i].
	ByteArray new: 1048576.
	(Delay forMilliseconds: 25) wait.
	512 timesRepeat: [1 + 2]].
Smalltalk vm garbageCollect.
check value: ((weak at: 2) isNil and: [(weak at: 3) isNil])
	value: 'dead moving donor/target weak mentions were not cleared'.
result := Point allInstances.
dst := result detect: [:p | p x = 987654321] ifNone: [nil].
check value: (dst notNil and: [(result count: [:p | p == dst]) = 1 and: [dst y = 400 and: [dst identityHash = pointHash]]])
	value: 'enumeration lost/duplicated forwarded identity'.
check value: ((keep at: 1) == dst and: [(weak at: 1) == dst])
	value: 'strong or weak alias missed canonical target after relocation'.
check value: (Smalltalk vm primStatistics first = 0 and: [Smalltalk vm primStatistics second = 0])
	value: 'unexpected legacy collection'.
Smalltalk vm stdoutWrite: 'moving forward ok', (String with: Character lf).
Smalltalk quit: 0
