| fixture worker weak check run hold |
check := [:ok :s | ok ifFalse: [Smalltalk vm stderrWrite: s, String lf. Smalltalk quit: 1]].
fixture := Object subclass: #OptSliceWitness instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
fixture compile: 'sliceSub: x keep: o | t | t := x - 253. ^t + x'.
worker := fixture new.
weak := WeakArray new: 2.
weak at: 1 put: (41 @ 67); at: 2 put: (53 @ 83).
run := [:n | worker sliceSub: n keep: (weak at: 1)].
check value: (run value: 112.5) = -28.0 value: 'warm up entry interrupt'.
"Deep ordinary frames keep the 64-root publication budget from sealing at entry."
hold := [:n :again | n = 0
	ifTrue: [
		worker sliceSub: 212 keep: (weak at: 1).
		"Do not touch the weak array or return through another block before reentry."
		worker sliceSub: 212 keep: nil]
	ifFalse: [again value: n - 1 value: again]].
check value: (hold value: 96 value: hold) = 171 value: 'initial result'.
24 timesRepeat: [(Delay forMilliseconds: 20) wait. 2000 timesRepeat: [2 + 3]].
check value: ((weak at: 1) notNil and: [(weak at: 1) x = 41 and: [(weak at: 1) y = 67]]) value: 'watched weak referent lost'.
check value: (weak at: 2) isNil value: 'weak-only control not cleared'.
4 timesRepeat: [check value: (run value: 128) = 3 value: 'fresh result'].
Smalltalk vm stdoutWrite: 'checked prefix moving witness ok', String lf.
Smalltalk quit: 0
