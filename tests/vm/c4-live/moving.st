| check anchor peer hash strong weak after churn stats |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].
anchor := Point new.
peer := Point new.
anchor setX: peer setY: 13.
peer setX: anchor setY: 37.
hash := anchor identityHash.
anchor beReadOnlyObject.
strong := Array with: anchor.
weak := WeakArray new: 2.
weak at: 1 put: peer; at: 2 put: (101 @ 103).
churn := [:cycles |
	cycles timesRepeat: [
		1 to: 1024 do: [:i | i @ (i + 1)].
		after := ByteArray new: 1048576.
		(Delay forMilliseconds: 40) wait.
		1024 timesRepeat: [1 + 2]]].
churn value: 24.
check value: (after size = 1048576) value: 'pinned allocation lost'.
check value: ((strong at: 1) == anchor and: [anchor class == Point and: [anchor identityHash = hash and: [anchor isReadOnlyObject]]])
	value: 'Point identity, class, hash or header changed'.
check value: (anchor x == peer and: [peer x == anchor and: [(weak at: 1) == peer]])
	value: 'Point cycle or weak alias lost'.
check value: (weak at: 2) isNil value: 'weak-only Point not cleared'.
peer setX: anchor setY: 99.
churn value: 12.
check value: ((weak at: 1) == peer and: [anchor x y = 99]) value: 'write after relocation lost'.
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0]) value: 'legacy collection ran'.
Smalltalk vm stdoutWrite: 'C4 moving Points ok', (String with: Character lf).
Smalltalk quit: 0
