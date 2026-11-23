| fixture worker sel source check run expected weak hold |
check := [:ok :s | ok ifFalse: [Smalltalk vm stderrWrite: s, String lf. Smalltalk quit: 1]].
Profiler default stop.
Processor stopTimeSlicer.
"Keep the tested native frame on the runnable caller during the collector cut. Weak clearing still runs; delivery/preemption has separate scheduler tests."
WeakRegistry finalizationProcess suspend.
Delay primSignal: nil atMilliseconds: 0.
fixture := Object subclass: #OptLoopFixture instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
sel := #loopCount:seed:keep:a:b:c:d:e:.
source := 'loopCount: n seed: seed keep: keep a: a b: b c: c d: d e: e | i sum | i := n. sum := seed. [i > 0] whileTrue: [sum := sum + 1. i := i - 1]. ^sum'.
fixture compile: source.
"An independent interpreter oracle: same stock method under an unselected selector."
fixture compile: (source copyReplaceAll: 'loopCount:' with: 'oracleCount:').
worker := fixture new.
run := [:n :seed | worker loopCount: n seed: seed keep: nil a: 71 b: 72 c: 73 d: 74 e: 75].
expected := [:n :seed | worker oracleCount: n seed: seed keep: nil a: 71 b: 72 c: 73 d: 74 e: 75].
check value: ((run value: 13 value: 71) = (expected value: 13 value: 71)) value: 'ordinary parity'.
check value: ((run value: 3 value: SmallInteger maxVal - 1) = (expected value: 3 value: SmallInteger maxVal - 1)
	and: [(run value: 3 value: SmallInteger maxVal - 1) = (SmallInteger maxVal + 2)]) value: 'overflow parity'.
check value: ((run value: 3 value: 10.5) = 13.5) value: 'tag fallback'.
weak := WeakArray new: 2.
weak at: 1 put: (41 @ 67); at: 2 put: (53 @ 83).
hold := [:depth :again | depth = 0
	ifTrue: [worker loopCount: 1024 seed: 137 keep: (weak at: 1) a: 71 b: 72 c: 73 d: 74 e: 75]
	ifFalse: [again value: depth - 1 value: again]].
check value: (hold value: 96 value: hold) = (expected value: 1024 value: 137) value: 'long parity'.
 "WEAK_WITNESS"
"Corrupt and restore a versioned byte: the inexact loop is never admitted."
Smalltalk vm stderrWrite: 'loop fixture: edit', String lf.
(fixture methodDict at: sel) bytecodes at: 15 put: 2.
check value: ((run value: 13 value: 71) = 97) value: 'bytecode edit'.
Smalltalk vm stderrWrite: 'loop fixture: restore', String lf.
(fixture methodDict at: sel) bytecodes at: 15 put: 1.
check value: ((run value: 13 value: 71) = 84) value: 'bytecode restore'.
Smalltalk vm stdoutWrite: 'checked loop parity ok', String lf.
Smalltalk quit: 0
