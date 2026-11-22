| test source target check before after |
check := [:ok :message | ok ifFalse: [
	Smalltalk vm stderrWrite: message, String lf.
	Smalltalk quit: 1]].
StringTest compile: 'c4NativeLiteral
	| s |
	s := ''fresh baseline String literal''.
	^s'.
StringTest compile: 'c4NativeIdentity: a after: b
	^a == b'.
StringTest compile: 'c4NativeNotIdentical: a after: b
	^a ~~ b'.
StringTest compile: 'c4NativeAcrossBecome: a to: b
	| held i |
	held := a.
	a becomeForward: b.
	i := 0.
	[i < 256] whileTrue: [i := i + 1].
	^held == b'.
WideString compile: 'c4NativeTargetSize
	| size |
	size := self size.
	^size'.
StringTest compile: 'c4NativeWideSize
	| s |
	s := self c4NativeLiteral.
	^s c4NativeTargetSize'.
test := StringTest new.
source := test c4NativeLiteral.
target := WideString new: 5003.
target at: 1 put: (Character value: 955).
before := Smalltalk vm statistics.
check value: (test c4NativeIdentity: source after: source) value: 'native identity warmup'.
check value: (test c4NativeNotIdentical: source after: target) value: 'native not-identical warmup'.
check value: (test c4NativeLiteral == source) value: 'native literal warmup'.
check value: (test c4NativeAcrossBecome: source to: target) value: 'stale local across interpreter forwarding'.
check value: (String lf size = 1) value: 'captured initializer broken after forwarding'.
check value: ((Smalltalk vm statistics - before) jitCacheFlushes > 0) value: 'old code generation survived forwarding'.
check value: (Smalltalk vm jitParameters first = 'baseline') value: 'forwarding disabled baseline'.
before := Smalltalk vm statistics.
check value: (test c4NativeIdentity: source after: target) value: 'alias identity'.
check value: (test c4NativeNotIdentical: source after: target) not value: 'alias not-identical'.
check value: (test c4NativeWideSize = 5003) value: 'compiled literal used stale size or class'.
32 timesRepeat: [
	ByteArray new: 1048579.
	(Delay forMilliseconds: 50) wait].
check value: (test c4NativeLiteral == target and: [(test c4NativeLiteral at: 1) codePoint = 955]) value: 'literal alias failed after C4 reuse'.
after := Smalltalk vm statistics - before.
check value: (after jitEntries > 0 and: [after jitMethodsCompiled > 0]) value: 'expected live native baseline'.
check value: (Smalltalk vm primStatistics first = 0 and: [Smalltalk vm primStatistics second = 0])
	value: 'legacy GC used'.
check value: (String lf size = 1) value: 'captured initializer broken after reuse'.
Smalltalk vm stdoutWrite: 'c4-jit forwarding ok', (String with: Character lf).
Smalltalk quit: 0
