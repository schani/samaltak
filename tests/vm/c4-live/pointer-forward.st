| check src dst obj hash weak holder ring |
check := [:ok :msg | ok ifFalse: [
	Smalltalk vm stderrWrite: msg, (String with: Character lf).
	Smalltalk quit: 1]].
Processor stopTimeSlicer.
Point compile: 'c4PointerReceiverAfter: ignored hash: h
	self x: self x + 1.
	^self x = 101 and: [self y = 200 and: [self identityHash = h]]'.
Point compile: 'c4PointerActiveFrameTo: other
	| h |
	h := other identityHash.
	self becomeForward: other.
	self x: self x + 1.
	^self x = 101 and: [self y = 200 and: [self identityHash = h]]'.
StringTest compile: 'c4PointerReplacePair: pair
	(pair at: 1) becomeForward: (pair at: 2).
	pair at: 1 put: nil; at: 2 put: nil.
	^nil'.
StringTest compile: 'c4PointerRawReceiver
	| pair h |
	pair := Array with: 1@2 with: 100@200.
	h := (pair at: 2) identityHash.
	^(pair at: 1) c4PointerReceiverAfter: (self c4PointerReplacePair: pair) hash: h'.
StringTest compile: 'c4PointerWeakOnly: weak
	| src dst |
	src := 80@90.
	dst := 801@901.
	weak at: 2 put: src.
	src becomeForward: dst.
	^nil'.

src := 10@20.
dst := 100@200.
weak := WeakArray new: 2.
weak at: 1 put: src.
holder := Array with: src.
hash := dst identityHash.
check value: (src == (src becomeForward: dst)) value: 'identity did not canonicalize alias'.
check value: ((weak at: 1) == dst and: [(holder at: 1) == dst]) value: 'heap aliases disagree'.
check value: (src identityHash = hash) value: 'target identity hash changed'.
src instVarAt: 2 put: 400.
check value: (dst x = 100 and: [dst y = 400]) value: 'old owner store missed target'.
12 timesRepeat: [
	check value: StringTest new c4PointerRawReceiver value: 'raw operand missed target'.
	check value: ((1@2) c4PointerActiveFrameTo: (100@200)) value: 'receiver in active frame missed target'].

Smalltalk at: #C4PointerBinding put: 42.
StringTest compile: 'c4PointerBinding
	^C4PointerBinding'.
obj := StringTest new.
12 timesRepeat: [check value: obj c4PointerBinding = 42 value: 'binding warmup failed'].
src := Smalltalk associationAt: #C4PointerBinding.
dst := Association key: #C4PointerBinding value: 77.
src becomeForward: dst.
check value: (obj c4PointerBinding = 77 and: [(Smalltalk associationAt: #C4PointerBinding) == dst])
	value: 'compiled binding missed forwarded Association'.
Smalltalk removeKey: #C4PointerBinding.

src := Message selector: #first argument: 4.
dst := Message selector: #second argument: 8.
holder at: 1 put: src.
src becomeForward: dst.
check value: (src == dst and: [src selector == #second and: [src argument = 8]])
	value: 'Message layout/identity changed'.
"Do not read holder until after collection: retain the target only through
the raw strong slot in C4."
hash := dst identityHash.

StringTest new c4PointerWeakOnly: weak.
src := dst := nil.
ring := Array new: 4.
36 timesRepeat: [
	ring at: 1 put: (ByteArray new: 1048579).
	(Delay forMilliseconds: 50) wait.
	512 timesRepeat: [1 + 2]].
Smalltalk vm garbageCollect.
check value: ((weak at: 2) isNil) value: 'weak-only target survived'.
12 timesRepeat: [ring at: 2 put: 1@2].
check value: ((weak at: 2) isNil) value: 'weak alias revived'.
check value: ((weak at: 1) isNil) value: 'former target sticky marker incorrectly rooted it'.
obj := holder at: 1.
check value: (obj identityHash = hash and: [obj argument = 8]) value: 'raw strong target lost after GC'.
Smalltalk vm stdoutWrite: 'pointer forward ok', (String with: Character lf).
Smalltalk quit: 0
