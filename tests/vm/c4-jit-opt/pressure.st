| cls obj check anchor peer weak after before answer |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, String lf. Smalltalk quit: 1]].
cls := Object subclass: #C4TierPressure instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
cls compile: 'score: n keep: root | x | x := n + 23. ^x - 3 + n'.
obj := cls new.
before := Smalltalk vm primStatistics at: 32.
2000 timesRepeat: [check value: (obj score: 10 keep: nil) = 40 value: 'warmup result'].
check value: ((Smalltalk vm primStatistics at: 32) > before) value: 'pressure method did not optimize'.
anchor := Point new.
peer := Point new.
anchor setX: peer setY: 13.
peer setX: anchor setY: 37.
weak := WeakArray new: 2.
weak at: 1 put: peer; at: 2 put: (101 @ 103).
48 timesRepeat: [
	1 to: 2048 do: [:i | i @ (i + 1)].
	after := ByteArray new: 2097152.
	answer := obj score: 21 keep: peer.
	check value: answer = 62 value: 'score during collection'.
	(Delay forMilliseconds: 20) wait.
	128 timesRepeat: [obj score: 21 keep: peer]].
check value: (after size = 2097152) value: 'pinned allocation lost'.
check value: (anchor x == peer and: [peer x == anchor and: [(weak at: 1) == peer]])
	value: 'Point cycle or weak alias lost'.
check value: (weak at: 2) isNil value: 'weak-only Point not cleared'.
after := Smalltalk vm primStatistics.
check value: (after first = 0 and: [after second = 0]) value: 'legacy collection ran'.
Smalltalk vm stdoutWrite: 'C4 automatic opt pressure ok', String lf.
Smalltalk quit: 0
