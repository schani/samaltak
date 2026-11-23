| cls worker before after answer weak held timer sema ready |
cls := Object subclass: #C4JitLiveFixture instanceVariableNames: 'payload' classVariableNames: '' package: 'Tests-VM'.
cls compile: 'touch: p
	payload := p.
	^payload x + payload y'.
cls compile: 'deep: n keep: p
	n = 0 ifTrue: [^self touch: p].
	^1 + (self deep: n - 1 keep: p)'.
cls compile: 'spin: limit
	| i total |
	i := 0. total := 0.
	[i < limit] whileTrue: [total := total + 1. i := i + 1].
	^total'.
cls compile: 'nativeChurn: limit keep: p
	| i array |
	i := 0.
	[i < limit] whileTrue: [array := {i. p. self}. i := i + 1].
	^array'.
cls compile: 'osr: limit
	| i |
	i := 0.
	[i < limit] whileTrue: [i := i + 1].
	^i'.
worker := cls new.
ready := false.
sema := Semaphore new.
timer := [[(Delay forMilliseconds: 1) wait. ready := true. sema signal] forkAt: Processor userInterruptPriority].
before := Smalltalk vm statistics counters.
worker spin: 10.
timer value.
answer := worker spin: 5000000.
ready ifFalse: [self error: 'ticker did not preempt the compiled loop'].
sema wait.
answer = 5000000 ifFalse: [self error: 'native loop result'].
weak := WeakArray new: 2.
held := 3 @ 4.
weak at: 1 put: held.
weak at: 2 put: (100 @ 101).
((worker nativeChurn: 180000 keep: held) at: 2) == held ifFalse: [self error: 'native Array publication'].
120 timesRepeat: [
	256 timesRepeat: [ByteArray new: 4096].
	(worker deep: 180 keep: held) = 187 ifFalse: [self error: 'deep native entry / Point access'].
	(weak at: 1) == held ifFalse: [self error: 'live weak Point lost'].
	(Delay forMilliseconds: 1) wait].
(weak at: 2) isNil ifFalse: [self error: 'unreachable weak Point retained'].
Smalltalk vm jitParameters: {nil. nil. 65535. 0}.
(worker osr: 1000000) = 1000000 ifFalse: [self error: 'OSR result'].
after := Smalltalk vm statistics counters.
{1. 2} do: [:i | (after at: i) = 0 ifFalse: [self error: 'legacy collection in C4']].
{15. 20. 22. 23. 25. 31} do: [:i |
	(after at: i) > (before at: i) ifFalse: [self error: 'missing JIT counter ', i printString]].
'c4-jit-live ok'
