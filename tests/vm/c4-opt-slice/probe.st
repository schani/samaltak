| fixture worker keep check |
check := [:answer :expected | answer = expected ifFalse: [
	Smalltalk vm stderrWrite: answer printString, ' != ', expected printString, String lf.
	Smalltalk quit: 1]].
fixture := Object subclass: #OptSliceFixture instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
fixture compile: 'sliceAdd: x ^x + 3'.
fixture compile: 'sliceSub: x keep: o
	| t |
	t := x - 253.
	^t + x'.
worker := fixture new.
keep := 31 @ 52.
check value: (worker sliceAdd: 11) value: 14.
check value: (worker sliceAdd: 1.5) value: 4.5.
check value: (worker sliceAdd: 4611686018427387903) value: 4611686018427387906.
check value: (worker sliceAdd: -61) value: -58.
check value: (worker sliceSub: 212 keep: keep) value: 171.
check value: (worker sliceSub: 112.5 keep: keep) value: -28.0.
check value: (worker sliceSub: -4611686018427387904 keep: keep) value: -9223372036854776061.
check value: (worker sliceSub: 3000000000000000000 keep: keep) value: 5999999999999999747.
check value: (worker sliceSub: 128 keep: keep) value: 3.
Smalltalk vm stdoutWrite: 'checked prefix parity ok', String lf.
Smalltalk quit: 0
