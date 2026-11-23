| slots strong weak survivor stats check |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].
slots := Smalltalk at: #C4PublishSlots.
strong := Array new: slots.
weak := WeakArray new: slots.
survivor := Array with: 73.
check value: (strong first isNil and: [strong last isNil and: [weak first isNil and: [weak last isNil]]])
	value: 'large allocation was not nil-filled'.
strong at: slots - 3 put: survivor.
weak at: slots - 3 put: survivor.
weak at: slots put: (Array with: 81).
survivor := nil.
24 timesRepeat: [
	768 timesRepeat: [ByteArray new: 2048].
	(Delay forMilliseconds: 75) wait].
check value: ((weak at: slots - 3) == (strong at: slots - 3) and: [
	(strong at: slots - 3) first = 73 and: [
	weak last isNil and: [(weak at: slots - 2) isNil and: [strong last isNil]]]])
	value: 'large strong/weak shadow did not survive collection'.
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0]) value: 'legacy collection ran'.
Smalltalk vm stdoutWrite: 'C4 bounded publication ok', (String with: Character lf).
Smalltalk quit: 0
