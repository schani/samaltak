| check test target source |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, (String with: Character lf).
	Smalltalk quit: 1]].
Processor stopTimeSlicer.

String compile: 'c4BecomeIdentical: other
	<primitive: ''identical''>
	self error: ''identity primitive failed'''.
StringTest compile: 'c4BecomeQuickLiteral
	^''c4 quick literal source'''.
StringTest compile: 'c4BecomeLiteralSize
	| n |
	n := ''c4 nonquick literal source'' size.
	^n'.
StringTest compile: 'c4BecomeConvertPair: pair
	(pair at: 1) becomeForward: (pair at: 2).
	pair at: 1 put: nil; at: 2 put: nil.
	^nil'.
String compile: 'c4BecomeCheckRawRootAfter: ignored hash: hash
	"No explicit yield: keep the pre-become receiver in the C stack."
	1 to: 12 do: [:batch |
		ByteArray new: 1048579.
		1 to: 8000 do: [:i | i + 1]].
	^self class == WideString and: [self identityHash = hash and: [
		self size = 5003 and: [(self at: 1) codePoint = 955]]]'.
StringTest compile: 'c4BecomeStack
	| old target hash pair |
	old := ByteString new: 1.
	target := WideString new: 5003.
	target at: 1 put: (Character value: 955).
	hash := target identityHash.
	pair := Array with: old with: target.
	old := target := nil.
	^(pair at: 1) c4BecomeCheckRawRootAfter: (self c4BecomeConvertPair: pair) hash: hash'.
StringTest compile: 'c4BecomeChurn
	36 timesRepeat: [
		ByteArray new: 1048579.
		(Delay forMilliseconds: 25) wait.
		512 timesRepeat: [1 + 2]]'.
StringTest compile: 'c4BecomeHeap: check
	| strong weak live dead anchor target hash fresh |
	live := ByteString new: 9.
	dead := ByteString new: 17.
	strong := Association key: live value: #retained.
	weak := WeakArray new: 2.
	weak at: 1 put: live; at: 2 put: dead.
	anchor := WideString new: 11.
	anchor at: 11 put: (Character value: 955).
	hash := anchor identityHash.
	target := WideString new: 5003.
	live becomeForward: anchor.
	dead becomeForward: target.
	live := dead := anchor := target := nil.
	self c4BecomeChurn.
	"Force full collection in legacy only; in C4 the image fallback answers zero."
	Smalltalk vm garbageCollect.
	check value: (weak at: 2) isNil value: ''weak-only target survived''.
	"Keep several new targets of the dead target extent live at once."
	fresh := (1 to: 16) collect: [:i |
		(WideString new: 5003) at: 1 put: (Character value: 955 + i); yourself].
	self c4BecomeChurn.
	check value: (weak at: 2) isNil value: ''weak-only alias revived after reuse''.
	anchor := strong key.
	check value: ((weak at: 1) == anchor and: [anchor class == WideString and: [
		anchor identityHash = hash and: [anchor size = 11 and: [(anchor at: 11) codePoint = 955]]]])
		value: ''strong/weak aliases disagree on target identity, class, hash or contents''.
	check value: ((fresh last at: 1) codePoint = 971 and: [fresh last ~~ anchor])
		value: ''fresh target storage was corrupted'''.

test := StringTest new.
source := ByteString new: 1.
target := WideString new: 11.
check value: (source == (source becomeForward: target)) value: 'identity bytecode missed stale operand'.
source := ByteString new: 1.
check value: (source ~~ (source becomeForward: target)) not value: 'not-identical bytecode missed stale operand'.
source := ByteString new: 1.
check value: (source c4BecomeIdentical: (source becomeForward: target)) value: 'identity primitive missed stale receiver'.
(StringTest >> #c4BecomeQuickLiteral) literals first becomeForward: target.
check value: test c4BecomeQuickLiteral == target value: 'quick literal returned an alias'.
(StringTest >> #c4BecomeLiteralSize) literals first becomeForward: target.
check value: test c4BecomeLiteralSize = 11 value: 'literal dispatch used old class or length'.
check value: test c4BecomeStack value: 'stale stack receiver did not keep target alive'.
test c4BecomeHeap: check.
Smalltalk vm stdoutWrite: 'become aliases ok', (String with: Character lf).
Smalltalk quit: 0
