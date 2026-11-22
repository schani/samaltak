| check src dst third method literals cm |
check := [:ok :msg | ok ifFalse: [
	Smalltalk vm stderrWrite: msg, (String with: Character lf).
	Smalltalk quit: 1]].
ProtoObject compile: 'c4TryPointerForward: other
	<primitive: ''becomeForward''>
	^#rejected'.
src := 1@2.
dst := 3@4.
third := 5@6.
check value: ((src c4TryPointerForward: dst) == dst) value: 'exact Point rejected'.
check value: ((dst c4TryPointerForward: third) == #rejected) value: 'accepted target as source'.
check value: ((src c4TryPointerForward: third) == #rejected) value: 'accepted raw alias as source'.
check value: ((third c4TryPointerForward: (Message selector: #first)) == #rejected) value: 'accepted cross-class'.
check value: (((1 to: 4) c4TryPointerForward: (2 to: 7)) == #rejected) value: 'accepted Interval'.
check value: (((Array new: 2) c4TryPointerForward: (Array new: 2)) == #rejected) value: 'accepted indexed body'.
check value: ((third c4TryPointerForward: nil) == #rejected) value: 'accepted nil'.
check value: ((third c4TryPointerForward: 42) == #rejected) value: 'accepted immediate'.

"Adversarial but previously legal: use a pinned F_FIXED body as a method
literal vector. The frame/entry obtains its raw address, which must make
the owner ineligible even after the frame returns."
StringTest compile: 'c4RawLiteralOwner
	| x |
	x := ''a literal entry''.
	^x yourself'.
method := StringTest >> #c4RawLiteralOwner.
literals := Message selector: method literals first arguments: method literals second.
cm := CompiledMethod new
	selector: method selector;
	literals: literals;
	bytecodes: method bytecodes;
	numArgs: method numArgs;
	numTemps: method numTemps;
	frameSize: method frameSize;
	yourself.
StringTest addSelector: method selector withMethod: cm.
check value: StringTest new c4RawLiteralOwner = 'a literal entry' value: 'failed literal body witness'.
check value: ((literals c4TryPointerForward: (Message selector: #no)) == #rejected) value: 'accepted borrowed source'.
check value: (((Message selector: #no) c4TryPointerForward: literals) == #rejected) value: 'accepted borrowed target'.
Smalltalk vm stdoutWrite: 'pointer rejections ok', (String with: Character lf).
Smalltalk quit: 0
