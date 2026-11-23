| cls obj result start |
cls := Object subclass: #CheckedArithmeticBench instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
cls compile: 'cost: x with: y | a | a := x + y. a := a - 3. a := a + x. a := a - y. a := a + 99. a := a + y. a := a - x. ^a + 11'.
obj := cls new.
10000 timesRepeat: [obj cost: 21 with: 7].
start := Time millisecondClockValue.
result := 0.
3000000 timesRepeat: [result := obj cost: 21 with: 7].
Smalltalk vm stdoutWrite: 'result: ', result printString, ' ms: ', (Time millisecondClockValue - start) printString, String lf.
Smalltalk quit: (result = 135 ifTrue: [0] ifFalse: [1])
