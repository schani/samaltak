| cls obj check method bc lits before a |
check := [:condition :label | condition ifFalse: [
	Smalltalk vm stderrWrite: label, String lf. Smalltalk quit: 1]].
cls := Object subclass: #C4TierWorkload instanceVariableNames: 'stored'
	classVariableNames: '' package: 'Tests-VM'.
cls compile: 'fold: x with: y | t | t := x + y. ^t - 3 + x'.
cls compile: 'offset: x ^x + 1000000'.
cls compile: 'byteEdit: x ^x + 3'.
cls compile: 'invokeFold: x ^self fold: x with: 7'.
cls compile: 'unsupportedLoop: x | total | total := 0. 1 to: x do: [:i | total := total + i]. ^total'.
cls compile: 'unsupportedHeap: x stored := x. ^Array with: stored'.
cls compile: 'unsupportedLiteral: x ^x + 1.5'.
obj := cls new.
before := Smalltalk vm primStatistics at: 32.
2000 timesRepeat: [
	check value: (obj invokeFold: 21) = 46 value: 'wrong native-caller result'.
	check value: (obj offset: 19) = 1000019 value: 'wrong literal result'.
	check value: (obj byteEdit: 19) = 22 value: 'wrong byte-edit method result'].
check value: ((Smalltalk vm primStatistics at: 32) >= (before + 3)) value: 'ordinary hot methods did not optimize'.
before := Smalltalk vm primStatistics at: 36.
a := SmallInteger maxVal.
64 timesRepeat: [
	check value: (obj invokeFold: 2.5) = 9.0 value: 'wrong tag exit replay'.
	check value: (obj invokeFold: a) = (a * 2 + 4) value: 'wrong overflow exit replay'].
check value: ((Smalltalk vm primStatistics at: 36) >= (before + 2)) value: 'missing guard exits'.

before := Smalltalk vm primStatistics at: 38.
method := cls compiledMethodAt: #offset:.
lits := method literals.
lits beWritableObject.
lits at: (lits indexOf: 1000000) put: 1000001.
2000 timesRepeat: [
	check value: (obj offset: 19) = 1000020 value: 'stale optimized literal'.
	check value: (obj byteEdit: 19) = 22 value: 'wrong byte-edit method before write'].
check value: ((Smalltalk vm primStatistics at: 38) > before) value: 'literal edit did not retire optimized code'.

before := Smalltalk vm primStatistics at: 38.
method := cls compiledMethodAt: #byteEdit:.
bc := method bytecodes.
bc beWritableObject.
bc at: 3 put: 4.
2000 timesRepeat: [check value: (obj byteEdit: 19) = 23 value: 'stale optimized bytecode'].
check value: ((Smalltalk vm primStatistics at: 38) > before) value: 'bytecode edit did not retire optimized code'.

before := Smalltalk vm primStatistics at: 38.
cls compile: 'byteEdit: x ^x - 17'.
2000 timesRepeat: [check value: (obj byteEdit: 19) = 2 value: 'stale dictionary entry'].
check value: ((Smalltalk vm primStatistics at: 38) > before) value: 'method replacement did not retire optimized code'.

2000 timesRepeat: [
	check value: (obj unsupportedLoop: 9) = 45 value: 'wrong loop fallback'.
	check value: (obj unsupportedHeap: #stored) = #(#stored) value: 'wrong heap fallback'.
	check value: (obj unsupportedLiteral: 12) = 13.5 value: 'wrong unsupported literal fallback'].
a := Smalltalk vm primStatistics.
check value: ((a at: 1) = 0 and: [(a at: 2) = 0]) value: 'legacy collector ran'.
Smalltalk vm stdoutWrite: 'C4 automatic opt entries, exits and edits ok', String lf.
Smalltalk quit: 0
