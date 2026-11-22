| check rejected ctx live heapBase replacement proc testMethod |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].
rejected := [:store |
	[store value. false] on: SubscriptOutOfBounds do: [:e | e return: true]].

ctx := Context basicNew: 300.
check value: (ctx instVarAt: 3 put: 256) = 256 value: 'bounded stackp growth failed'.
live := Array with: #live.
ctx basicAt: 1 put: live; basicAt: 256 put: (Array with: #discarded).
check value: (ctx instVarAt: 3 put: 1) = 1 value: 'stackp shrink failed'.
check value: (ctx basicAt: 256) isNil value: 'read exposed inactive tail'.
check value: (rejected value: [ctx instVarAt: 262 put: live]) value: 'write into inactive tail succeeded'.
#(nil -1 301 258 1152921504606846976 1180591620717411303424) do: [:bad |
	check value: (rejected value: [ctx instVarAt: 3 put: bad]) value: 'invalid stackp accepted'.
	check value: ((ctx instVarAt: 3) = 1 and: [(ctx basicAt: 1) == live])
		value: 'rejected stackp write changed the live prefix'].
check value: (ctx instVarAt: 3 put: 256) = 256 value: 'stackp regrowth failed'.
check value: ((ctx basicAt: 1) == live and: [(ctx basicAt: 256) isNil])
	value: 'regrowth did not preserve the live prefix and nil the new slots'.
ctx instVarAt: 3 put: 300.
check value: ((ctx basicAt: 300) isNil and: [(ctx instVarAt: 3) = 300])
	value: 'stackp did not reach physical capacity'.

check value: (MarriedContextTest new married: [:c |
	| n copy |
	n := c instVarAt: 3.
	check value: (rejected value: [c instVarAt: 3 put: n])
		value: 'reflective stackp write accepted on married Context'.
	copy := c shallowCopy.
	(copy instVarAt: 3) = n and: [(copy tempAt: 2) = 42]])
	value: 'married shallowCopy lost the live stack'.

"Call the primitive directly from its married receiver's activation: flushing
 that receiver makes it the heap base before the reflective write."
Context compile: 'c4TrySlot: index put: value
	<primitive: ''instVarAtPut''>
	^#rejected'.
MarriedContextTest compile: 'c4TryReplaceOwnMethod: replacement
	^thisContext c4TrySlot: 4 put: replacement'.
testMethod := MarriedContextTest >> #c4TryReplaceOwnMethod:.
check value: (MarriedContextTest new c4TryReplaceOwnMethod: testMethod shallowCopy) = #rejected
	value: 'reflective method replacement accepted after materialization'.

"Start a process directly in a heap Context; no frame owns its code pointers."
Processor stopTimeSlicer.
heapBase := [
	check value: thisContext == heapBase value: 'expected to run in heap base'.
	check value: (rejected value: [heapBase instVarAt: 3 put: 0])
		value: 'reflective stackp write accepted on heap base'.
	check value: (rejected value: [heapBase instVarAt: 4 put: replacement])
		value: 'reflective method replacement accepted on heap base'.
	check value: (heapBase instVarAt: 4 put: heapBase method) == heapBase method
		value: 'no-op reflective method store rejected'.
	heapBase method: heapBase method.
	check value: heapBase method ~~ replacement value: 'heap base method changed'.
	check value: (ctx instVarAt: 4 put: replacement) == replacement
		value: 'inactive Context method replacement rejected'.
	Smalltalk vm stdoutWrite: 'C4 Context reflection ok', (String with: Character lf).
	Smalltalk quit: 0] asContext.
replacement := heapBase method shallowCopy.
proc := Process forContext: heapBase priority: Processor activeProcess priority + 1.
proc resume.
Smalltalk quit: 2
