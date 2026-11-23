| fixture worker check add sub b l |
check := [:value :expected | value = expected ifFalse: [
	Smalltalk vm stderrWrite: value printString, ' != ', expected printString, String lf. Smalltalk quit: 1]].
fixture := Object subclass: #OptSliceEdits instanceVariableNames: '' classVariableNames: '' package: 'Tests-VM'.
fixture compile: 'sliceAdd: x ^x + 3'.
fixture compile: 'sliceLiteral: x ^x + 1000000'.
worker := fixture new.
add := fixture compiledMethodAt: #sliceAdd:.
sub := fixture compiledMethodAt: #sliceLiteral:.
4 timesRepeat: [
	check value: (worker sliceAdd: 11) value: 14.
	check value: (worker sliceLiteral: 212) value: 1000212].
b := add bytecodes.
b beWritableObject.
b at: 3 put: 4.
l := sub literals.
l beWritableObject.
l at: (l indexOf: 1000000) put: 1000001.
4 timesRepeat: [
	check value: (worker sliceAdd: 11) value: 15.
	check value: (worker sliceLiteral: 212) value: 1000213].
Smalltalk vm stdoutWrite: 'checked prefix edits ok', String lf.
Smalltalk quit: 0
