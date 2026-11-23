| fixture worker check answer |
check := [:ok | ok ifFalse: [Smalltalk quit: 1]].
fixture := Object subclass: #OptSliceBounds instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
fixture compile: 'sliceWide: x b: b c: c d: d e: e f: f g: g h: h i: i j: j k: k l: l ^(x + b) - c'.
fixture compile: 'sliceReject: x | i | i := 0. [i < x] whileTrue: [i := i + 1]. ^i'.
worker := fixture new.
3 timesRepeat: [
	check value: (worker sliceWide: 30 b: 13 c: 7 d: nil e: true f: false g: 1 h: 9 i: 30 j: 11 k: 21 l: 42) = 36.
	check value: (worker sliceReject: 13) = 13].
check value: (worker sliceWide: 4611686018427387903 b: 3 c: 7 d: nil e: true f: false g: 1 h: 9 i: 30 j: 11 k: 21 l: 42) = 4611686018427387899.
check value: (worker sliceWide: 30 b: 13.5 c: 7 d: nil e: true f: false g: 1 h: 9 i: 30 j: 11 k: 21 l: 42) = 36.5.
Smalltalk vm stdoutWrite: 'checked prefix wide parity ok', String lf.
Smalltalk quit: 0
