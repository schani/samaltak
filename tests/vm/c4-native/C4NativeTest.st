VMModule subclass: #C4NativeTest
	instanceVariableNames: 'arena libc posix handles replacements locations round phase'
	classVariableNames: ''
	package: 'C4-NativeTests'!

!C4NativeTest class methodsFor: 'declaring'!
declarations
	^#((arena C4NativeArena) (libc LibC) (posix Posix)
		(handles 'uint32_t[64]') (replacements 'uint32_t[64]') (locations 'uint32_t[64]') (round int) (phase int))
! !

!C4NativeTest methodsFor: 'running'!
main: argc argv: argv
	<function>
	<var: #argc type: 'int'>
	<var: #argv type: 'char **'>
	self check: arena open = 1 because: 'open worker'.
	self check: (arena capacity = 64 and: [arena rootCount = 8 and: [arena slotCount = 2]]) because: 'arena dimensions'.
	1 to: 32 do: [:i | round := i asInt32. self exercise].
	round := 33. self exerciseCancellation: true.
	round := 34. self exerciseCancellation: false.
	self check: arena close = 1 because: 'join worker'.
	self exerciseEpochLimit.
	libc printf: 'c4-native: 103 cycles passed
'.
	^0
!
check: ok because: label
	<function>
	ok ifFalse: [
		libc fprintf: libc stderr format: 'c4-native: round %d phase %d: %s
' with: round with: phase with: label.
		libc exit: 1]
!
await: aBlock because: label
	"Polling belongs to the driver, not the mutator API. run.sh also bounds stuck calls."
	| ready |
	ready := false.
	1 to: 2000 do: [:i |
		ready ifFalse: [
			ready := aBlock value.
			ready ifFalse: [posix usleep: 1000]]].
	self check: ready because: label
!
allocate: payload
	<function>
	| h |
	h := arena allocate: payload.
	self check: h ~= 0 because: 'allocate within capacity'.
	self check: ((arena slotAt: 0 of: h) = 0 and: [(arena slotAt: 1 of: h) = 0]) because: 'new slots cleared'.
	self check: (arena payloadOf: h) = payload because: 'new payload'.
	^h
!
rejectStale: stale from: live
	<function>
	self check: (arena live: stale) = 0 because: 'stale liveness'.
	self check: ((arena cellIndexOf: stale) = 0 and: [(arena relocate: stale) = 0]) because: 'stale relocation'.
	self check: (arena payloadOf: stale) = 0 because: 'stale payload read'.
	self check: (arena payloadOf: stale put: 999) = 0 because: 'stale payload write'.
	self check: (arena slotAt: 0 of: stale) = 0 because: 'stale edge read'.
	self check: (arena slotAt: 0 of: stale put: live) = 0 because: 'stale edge receiver'.
	self check: (arena slotAt: 0 of: live put: stale) = 0 because: 'stale edge target'.
	self check: (arena rootAt: 0 put: stale) = 0 because: 'stale root target'
!
exercise
	<function>
	| a b c d e f g newborn location |
	phase := 1.
	0 to: 60 do: [:i | handles at: i put: (self allocate: (100 + i) asUInt32)].
	a := handles at: 0. b := handles at: 1. c := handles at: 2.
	d := handles at: 3. e := handles at: 4.
	f := handles at: 5. g := handles at: 6.
	self check: (arena rootAt: 0 put: a) = 1 because: 'root A'.
	self check: (arena rootAt: 7 put: d) = 1 because: 'root D'.
	self check: (arena slotAt: 0 of: a put: b) = 1 because: 'A -> B'.
	self check: (arena slotAt: 1 of: b put: c) = 1 because: 'B -> C'.
	self check: (arena slotAt: 0 of: c put: a) = 1 because: 'C -> A'.
	self check: (arena slotAt: 0 of: d put: e) = 1 because: 'D -> E'.
	self check: (arena slotAt: 0 of: f put: g) = 1 because: 'dead F -> G'.
	self check: (arena slotAt: 1 of: g put: f) = 1 because: 'dead G -> F'.

	location := arena cellIndexOf: a.
	self beginParked.
	self check: (arena relocate: a) = 0 because: 'relocation blocked while parked'.
	self check: (arena cellIndexOf: a) = location because: 'parked location unchanged'.
	self check: arena begin = 0 because: 'overlapping begin'.
	self check: arena finish = 0 because: 'finish must not drain a parked worker'.
	self check: (arena rootAt: 7 put: 0) = 1 because: 'clear root D'.
	self check: (arena rootAt: 7 put: a) = 1 because: 'overwrite root D'.
	self check: (arena slotAt: 0 of: a put: 0) = 1 because: 'clear A -> B'.
	self check: (arena slotAt: 0 of: a put: c) = 1 because: 'overwrite A -> B'.
	self check: (arena slotAt: 1 of: b put: 0) = 1 because: 'overwrite B -> C'.
	61 to: 63 do: [:i | handles at: i put: (self allocate: (100 + i) asUInt32)].
	newborn := handles at: 63.
	self check: (arena slotAt: 1 of: a put: newborn) = 1 because: 'publish newborn'.
	self check: (arena rootAt: 7) = a because: 'new root visible'.
	self check: ((arena slotAt: 0 of: a) = c and: [(arena slotAt: 1 of: b) = 0]) because: 'new edges visible'.
	1 to: 64 do: [:i | self check: (arena allocate: 999) = 0 because: 'parked exhaustion without fallback'].
	self check: arena finish = 0 because: 'worker still parked'.
	self check: (arena holdWorker: 0) = 1 because: 'release worker gate'.
	1 to: 128 do: [:i |
		self check: (arena payloadOf: a put: (200 + i) asUInt32) = 1 because: 'mutate payload after release'].
	self await: [arena finish = 1] because: 'finish snapshot'.
	self checkFirstSnapshot.
	self check: (arena rootAt: 7) = a because: 'finish preserved overwritten root'.
	self check: ((arena slotAt: 0 of: a) = c and: [(arena slotAt: 1 of: a) = newborn and: [(arena slotAt: 1 of: b) = 0]]) because: 'finish preserved overwritten edges'.

	phase := 2.
	"Refill to capacity: all 56 vacated cells must be reusable, with distinct incarnations."
	5 to: 60 do: [:i | replacements at: i put: (self allocate: (300 + i) asUInt32)].
	self check: (arena allocate: 999) = 0 because: 'idle exhaustion without fallback'.
	5 to: 60 do: [:i |
		self rejectStale: (handles at: i) from: a.
		self check: (arena payloadOf: (replacements at: i)) = (300 + i) asUInt32 because: 'reuse keeps each replacement distinct'].
	self checkFirstSnapshot.
	self check: (arena rootAt: 0) = a because: 'stale write did not change root'.
	self check: (arena slotAt: 0 of: a) = c because: 'stale write did not change edge'.
	location := self moveA: a.
	self checkMovedA: a to: location edge0: c edge1: newborn.
	self check: (arena rootAt: 7) = a because: 'second root follows move'.
	self check: (arena rootAt: 7 put: 0) = 1 because: 'clear duplicate root'.
	self check: arena begin = 1 because: 'begin full-arena snapshot'.
	self await: [arena finish = 1] because: 'finish full-arena snapshot'.
	"Only moved A and its two targets are reachable. Birth protection has expired."
	0 to: 63 do: [:i |
		self check: (arena live: (handles at: i)) = ((i = 0 or: [i = 2 or: [i = 63]]) ifTrue: [1] ifFalse: [0]) asUInt32 because: 'second survivor set'].
	5 to: 60 do: [:i | self check: (arena live: (replacements at: i)) = 0 because: 'replacements collected'].
	self checkMovedA: a to: location edge0: c edge1: newborn.

	phase := 3.
	self check: (arena rootAt: 0 put: 0) = 1 because: 'drop last root'.
	self check: arena begin = 1 because: 'begin empty-root snapshot'.
	self await: [arena finish = 1] because: 'finish empty-root snapshot'.
	self check: ((arena live: a) = 0 and: [(arena live: c) = 0 and: [(arena live: newborn) = 0]]) because: 'last survivors collected'
!
residentAt: i
	^(i >= 5 and: [i <= 60]) ifTrue: [replacements at: i] ifFalse: [handles at: i]
!
moveA: a
	<function>
	| twin |
	0 to: 63 do: [:i |
		| ordinal |
		ordinal := arena cellIndexOf: (self residentAt: i).
		self check: (ordinal >= 1 and: [ordinal <= 128]) because: 'valid physical ordinal'.
		locations at: i put: ordinal].
	twin := ((((locations at: 0) - 1) bitXor: 64) + 1) asUInt32.
	self check: (arena relocate: a) = 1 because: 'move one live cell'.
	0 to: 63 do: [:i |
		self check: (arena cellIndexOf: (self residentAt: i)) = (i = 0 ifTrue: [twin] ifFalse: [locations at: i]) because: 'only selected cell moved'].
	^twin
!
checkMovedA: a to: ordinal edge0: c edge1: newborn
	<function>
	self check: (arena cellIndexOf: a) = ordinal because: 'moved location preserved'.
	self check: (arena rootAt: 0) = a because: 'root follows move'.
	self check: (arena slotAt: 0 of: c) = a because: 'incoming edge follows move'.
	self check: ((arena slotAt: 0 of: a) = c and: [(arena slotAt: 1 of: a) = newborn]) because: 'both moved edges preserved'.
	self check: (arena payloadOf: a) = 328 because: 'moved payload preserved'
!
beginParked
	self check: (arena holdWorker: 1) = 1 because: 'arm worker gate'.
	self check: arena begin = 1 because: 'begin snapshot'.
	self await: [arena workerParked = 1] because: 'worker did not park'
!
exerciseCancellation: beforeScan
	<function>
	| owner white child garbage |
	phase := 4.
	owner := self allocate: 201.
	white := self allocate: 202.
	child := self allocate: 203.
	garbage := self allocate: 204.
	self check: (arena rootAt: 0 put: owner) = 1 because: 'root owner'.
	self check: (arena slotAt: 0 of: white put: child) = 1 because: 'white -> child'.
	"Deliberately violate root discipline: publication of a snapshot-white alias must cancel sweeping."
	beforeScan
		ifTrue: [
			self beginParked.
			self check: (arena rootAt: 7 put: white) = 1 because: 'publish white root while parked'.
			self check: (arena holdWorker: 0) = 1 because: 'release worker gate']
		ifFalse: [
			self check: arena begin = 1 because: 'begin before late publication'.
			self await: [arena workerDone = 1] because: 'worker did not complete'.
			self check: (arena relocate: owner) = 0 because: 'relocation blocked until finish'.
			self check: (arena slotAt: 0 of: owner put: white) = 1 because: 'publish white edge after DONE'].
	self await: [arena finish = 1] because: 'accept cancelled cycle'.
	self check: ((arena live: owner) = 1 and: [(arena live: white) = 1
		and: [(arena live: child) = 1 and: [(arena live: garbage) = 1]]]) because: 'cancellation preserves every cell'.
	self check: (arena slotAt: 0 of: white) = child because: 'white descendants intact'.
	self check: (beforeScan ifTrue: [(arena rootAt: 7) = white] ifFalse: [(arena slotAt: 0 of: owner) = white]) because: 'publication intact'.

	phase := 5.
	self check: arena begin = 1 because: 'begin after cancellation'.
	self await: [arena finish = 1] because: 'finish after cancellation'.
	self check: ((arena live: owner) = 1 and: [(arena live: white) = 1
		and: [(arena live: child) = 1 and: [(arena live: garbage) = 0]]]) because: 'normal collection resumed'.

	phase := 6.
	self check: (arena rootAt: 0 put: 0) = 1 because: 'clear owner root'.
	self check: (arena rootAt: 7 put: 0) = 1 because: 'clear white root'.
	self check: arena begin = 1 because: 'begin cancellation cleanup'.
	self await: [arena finish = 1] because: 'finish cancellation cleanup'.
	self check: ((arena live: owner) = 0 and: [(arena live: white) = 0 and: [(arena live: child) = 0]]) because: 'published graph collected'
!
exerciseEpochLimit
	<function>
	| h |
	round := 35.
	phase := 7.
	self check: arena open = 1 because: 'reopen worker'.
	self check: arena nearEpochLimit = 1 because: 'set epoch limit fixture'.
	h := self allocate: 401.
	self check: (arena rootAt: 0 put: h) = 1 because: 'root at final epoch'.
	self beginParked.
	self check: (arena rootAt: 0 put: 0) = 1 because: 'overwrite at final epoch'.
	self check: (arena holdWorker: 0) = 1 because: 'release final epoch'.
	self await: [arena finish = 1] because: 'finish final epoch'.
	self check: (arena live: h) = 1 because: 'snapshot at final epoch'.
	self check: arena begin = 0 because: 'epoch must not wrap'.
	self check: arena finish = 0 because: 'epoch exhaustion did not start a cycle'.
	self check: arena close = 1 because: 'join reopened worker'
!
checkFirstSnapshot
	<function>
	"Independent expected set: the two begin-time paths plus every newborn, even the unrooted ones."
	0 to: 63 do: [:i |
		| h expected |
		h := handles at: i.
		expected := i <= 4 or: [i >= 61].
		self check: (arena live: h) = (expected ifTrue: [1] ifFalse: [0]) asUInt32 because: 'first survivor set'.
		expected ifTrue: [
			self check: (arena payloadOf: h) = (i = 0 ifTrue: [328] ifFalse: [100 + i]) asUInt32 because: 'survivor payload']]
! !
