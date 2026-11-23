| check cold holder point weak hash copy matches fixture method denied heapStats |
check := [:ok :label | ok ifFalse: [
	Smalltalk vm stderrWrite: label, (String with: Character lf).
	Smalltalk quit: 1]].
cold := Interval from: 7 to: 1975308649 by: 987654321.
cold instVarAt: 3 put: 987654321. "Optional native witness watches this store."
hash := cold identityHash.
holder := Interval basicNew.
holder instVarAt: 3 put: cold. "A strong, non-numeric reference in the third slot."
point := 17 @ 21.
weak := WeakArray new: 3.
weak at: 1 put: cold; at: 2 put: (Interval from: 3 to: 8); at: 3 put: point.
cold := nil.
24 timesRepeat: [
	1 to: 850 do: [:i | Interval from: i to: i + 2. i @ 1].
	fixture := ByteArray new: 1048576.
	(Delay forMilliseconds: 35) wait.
	512 timesRepeat: [17 + 8]].
cold := holder instVarAt: 3.
check value: (cold == (weak at: 1) and: [cold identityHash = hash and: [cold size = 3]])
	value: 'cold Interval identity, third slot, or size changed'.
check value: ((weak at: 2) isNil and: [(weak at: 3) == point and: [point x = 17 and: [point y = 21]]])
	value: 'weak clear or Point regression'.
copy := cold shallowCopy.
check value: (copy class == Interval and: [copy ~~ cold and: [copy last = 1975308649]])
	value: 'Interval shallow copy failed'.
24 timesRepeat: [
	copy setFrom: 4 to: 10 by: 3.
	check value: ((copy at: 2) = 7 and: [copy increment = 3]) value: 'Interval replay failed'].
matches := Interval allInstances select: [:each | each == cold].
check value: (matches size = 1 and: [matches first == cold]) value: 'Interval enumeration did not deduplicate'.
(Smalltalk vm specialObjectsArray size >= 38 and: [(Smalltalk vm specialObjectsArray at: 38) == Interval])
	ifTrue: [
		#(3 4) do: [:i |
			method := CompiledMethod new.
			denied := false.
			[method instVarAt: i put: cold] on: Error do: [:ex | denied := true].
			check value: denied value: 'Interval admitted as raw method storage']].
check value: (fixture size = 1048576) value: 'pinned pressure object lost'.
heapStats := Smalltalk vm primStatistics.
check value: (heapStats first = 0 and: [heapStats second = 0]) value: 'legacy collection ran'.
Smalltalk vm stdoutWrite: 'C4 Interval ok', (String with: Character lf).
Smalltalk quit: 0
