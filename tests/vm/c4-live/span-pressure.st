| large small guards weak settle check backing stats refill |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, String lf.
	Smalltalk quit: 1]].
Processor stopTimeSlicer.
"Keep guards and backing live across all rounds. The two ByteArray sizes
 occupy 1023 and 960 words including headers; both were in the same bucket."
large := Array new: 4096.
small := Array new: 1024.
guards := Array new: 5120.
weak := WeakArray new: 2.
1 to: large size do: [:i |
	large at: i put: (ByteArray new: 8168).
	guards at: i put: (Array with: i)].
1 to: small size do: [:i |
	small at: i put: (ByteArray new: 7664).
	guards at: large size + i put: (Array with: i negated)].
backing := ByteArray new: 2097136.
backing at: 1 put: 47; at: backing size put: 99.
weak at: 1 put: large last; at: 2 put: small last.
settle := [
	4 timesRepeat: [
		128 timesRepeat: [ByteArray new: 4096].
		(Delay forMilliseconds: 170) wait]].
large atAllPut: nil.
small := nil.
settle value.
check value: (weak first isNil and: [weak second isNil]) value: 'pools not reclaimed'.
refill := [:round |
	1 to: large size do: [:i | | bytes |
		bytes := [ByteArray new: 8168] on: OutOfMemory do: [:ex |
			Smalltalk vm stderrWrite: 'C4 span pressure: round ', round printString,
				' refill failed at ', i printString, String lf.
			Smalltalk quit: 1].
		bytes at: 1 put: i \\ 251; at: bytes size put: round.
		large at: i put: bytes]].
1 to: 16 do: [:round |
	refill value: round.
	1 to: large size do: [:i | | bytes |
		bytes := large at: i.
		check value: (bytes size = 8168 and: [
			(bytes at: 1) = (i \\ 251) and: [(bytes at: bytes size) = round]])
			value: 'payload corrupted'].
	1 to: guards size do: [:i |
		check value: ((guards at: i) first = (i <= large size ifTrue: [i] ifFalse: [large size - i]))
			value: 'guard corrupted'].
	check value: ((backing at: 1) = 47 and: [(backing at: backing size) = 99])
		value: 'backing corrupted'.
	large atAllPut: nil.
	settle value].
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0]) value: 'legacy GC ran'.
Smalltalk vm stdoutWrite: 'C4 span pressure ok', String lf.
Smalltalk quit: 0
