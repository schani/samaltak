!MiniTests methodsFor: 'c4 pressure'!
c4Require: condition message: message
	condition ifFalse: [
		self stderr: message , Character lf asString.
		Smalltalk quit: 1]
!
c4Update: graph batch: n
	| bytes entry indexed |
	bytes := ByteArray new: 65536.
	bytes at: 1 put: n; at: bytes size put: 255 - n.
	entry := Point new setX: bytes setY: graph.
	indexed := graph at: 1.
	indexed replaceFrom: 1 to: 1 with: (Array with: entry) startingAt: 1.
	indexed at: 2 put: (Array with: n).
	(graph at: 2) setX: (n @ (n + 1))
!
c4Check: graph batch: n
	| entry bytes point anchor indexed |
	indexed := graph at: 1.
	entry := indexed at: 1.
	bytes := entry x.
	point := (graph at: 2) x.
	anchor := (graph at: 2) y.
	self c4Require: (entry class == Point and: [entry y == graph]) message: 'C4 pressure: broken cycle'.
	self c4Require: (((indexed at: 2) at: 1) = n) message: 'C4 pressure: lost indexed write'.
	self c4Require: (bytes class == ByteArray and: [(bytes at: 1) = n and: [(bytes at: bytes size) = (255 - n)]])
		message: 'C4 pressure: lost byte payload'.
	self c4Require: (point class == Point and: [point x = n and: [point y = (n + 1)]])
		message: 'C4 pressure: lost instance variable write'.
	self c4Require: ((anchor at: 1) = 73 and: [(anchor at: anchor size) = 149])
		message: 'C4 pressure: lost long-lived payload'
!
c4ChurnBuffer: marker
	| bytes check |
	bytes := ByteArray new: 4096.
	1 to: bytes size by: 256 do: [:i | bytes at: i put: marker].
	check := 0.
	1 to: bytes size by: 256 do: [:i | check := check + (bytes at: i)].
	self c4Require: check = (16 * marker) message: 'C4 pressure: corrupt churn buffer'.
	^bytes size
!
c4Churn: graph
	| allocated |
	allocated := 0.
	1 to: 128 do: [:batch |
		self c4Update: graph batch: batch.
		384 timesRepeat: [allocated := allocated + (self c4ChurnBuffer: batch)].
		self c4Check: graph batch: batch].
	^allocated
!
c4Frames: depth graph: graph
	| token context allocated |
	depth = 0 ifTrue: [^self c4Churn: graph].
	"Keep a distinct object in each frame. Materialize some of the stack, leaving
	the innermost frames in the ordinary interpreter representation."
	token := depth @ (depth + 1).
	(depth bitAnd: 63) = 0 ifTrue: [context := thisContext].
	allocated := self c4Frames: depth - 1 graph: graph.
	self c4Require: (token x = depth and: [token y = (depth + 1)]) message: 'C4 pressure: lost frame local'.
	context ifNotNil: [
		self c4Require: (context method selector == #c4Frames:graph:) message: 'C4 pressure: lost Context'].
	^allocated
!
testC4Pressure
	| anchor graph bytes stats |
	anchor := ByteArray new: 65536.
	anchor at: 1 put: 73; at: anchor size put: 149.
	graph := Array with: (Array new: 2) with: (Point new setX: nil setY: anchor).
	anchor := nil.
	bytes := self c4Frames: 1024 graph: graph.
	self c4Check: graph batch: 128.
	(Smalltalk getenv: 'SAMALTAK_C4_STATS') ifNotNil: [
		stats := Smalltalk vmStats.
		self c4Require: ((stats at: 1) = 0 and: [(stats at: 2) = 0])
			message: 'C4 pressure: legacy GC ran'].
	('payload bytes: ' , bytes printString) displayNl.
	'C4 pressure ok' displayNl
!
testC4OOM
	"On a 64 MiB heap, even an empty arena cannot fit this payload plus its header.
	The primitive fails with no-memory (1), rather than depending on GC progress."
	self c4Require: (ByteArray basicNew: 67108864) isNil message: 'C4 OOM: unexpectedly allocated'.
	self c4Require: (ByteArray new: 16) size = 16 message: 'C4 OOM: failed to recover'.
	'C4 OOM ok' displayNl
! !

!MiniTests methodsFor: 'c4 latency'!
c4LatencyBatch: ring
	| bytes |
	1 to: 128 do: [:i |
		bytes := ByteArray new: 2048.
		bytes at: 2048 put: i.
		ring at: (i bitAnd: 31) + 1 put: (i @ bytes)]
!
testC4Latency
	| ring samples start check |
	ring := Array new: 32.
	samples := Array new: 1000.
	50 timesRepeat: [self c4LatencyBatch: ring].
	1 to: samples size do: [:i |
		start := Smalltalk microsecondClock.
		self c4LatencyBatch: ring.
		samples at: i put: Smalltalk microsecondClock - start].
	check := ring inject: 0 into: [:sum :entry | sum + entry x + (entry y at: 2048)].
	('checksum: ' , check printString) displayNl.
	samples do: [:us | self stderr: 'latency_us ' , us printString , Character lf asString]
! !
