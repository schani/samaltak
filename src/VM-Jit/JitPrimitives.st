VMPrimitiveModule subclass: #JitPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitPrimitives comment: 'The JIT seen from the image: its parameters (jitParameters), the machine code of a method with the notes its compiler recorded (jitCode), for the annotated disassembly (CompiledMethod>>machineCode), and the type feedback of baseline code''s inline caches (jitSendSites).'!

!JitPrimitives methodsFor: 'parameters'!
primJitParameters
	"Smalltalk vm jitParameters [: anArray]: {mode. flags. threshold. osr. cache MB. CPU}, mode, flags and CPU as Strings ('baseline', 'arith,fuse,barrier', 'arm64'). With anArray {mode. flags. threshold. osr} (nil keeps one; flags are changes, as --jit-flags) set them; answer the parameters before. A new mode or new flags drop all machine code."
	<vmPrimitive: 180 name: 'jitParameters'>
	| r old p m saved s |
	r := self local: 'oop'.
	r value: (memory allocObj: memory clsArray format: F_VAR slots: 6).
	memory pushRoot: r.
	"Allocating the strings may collect: r value only after them."
	s := self stringFrom: (jit modeName: jit mode).
	self storeRef: r value at: 0 put: s.
	s := self flagsString.
	self storeRef: r value at: 1 put: s.
	self storeRef: r value at: 2 put: (self intOop: jit threshold).
	self storeRef: r value at: 3 put: (self intOop: jit osrThreshold).
	self storeRef: r value at: 4 put: (self intOop: jit cacheMB).
	s := self stringFrom: (jit isX64 ifTrue: ['x86_64'] ifFalse: ['arm64']).
	self storeRef: r value at: 5 put: s.
	memory popRoot.
	self argCount = 0 ifTrue: [^self answer: r value].
	old := self arg: 0.
	((self isPtr: old) and: [(self rawClass: old) = memory clsArray and: [(self numSlots: old) >= 4]]) ifFalse: [^self fail].
	((self element: old at: 2) ~= memory nilOop and: [(self isInt: (self element: old at: 2)) not]) ifTrue: [^self fail].
	((self element: old at: 3) ~= memory nilOop and: [(self isInt: (self element: old at: 3)) not]) ifTrue: [^self fail].
	m := jit mode.
	(self element: old at: 0) ~= memory nilOop ifTrue: [
		(memory isKindOfString: (self element: old at: 0)) ifFalse: [^self fail].
		p := memory utf8Of: (self element: old at: 0).
		p isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
		m := jit modeNamed: p.
		libc free: p.
		m < 0 ifTrue: [^self fail]].
	(self element: old at: 1) ~= memory nilOop ifTrue: [
		(memory isKindOfString: (self element: old at: 1)) ifFalse: [^self fail].
		p := memory utf8Of: (self element: old at: 1).
		p isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
		saved := jit flags.
		(jit parseFlags: p) ifFalse: [
			jit setFlags: saved.
			libc free: p.
			^self fail].
		libc free: p.
		jit setFlags: jit flags].
	m ~= jit mode ifTrue: [(jit setMode: m) ifFalse: [^self fail]].
	(self element: old at: 2) ~= memory nilOop ifTrue: [jit threshold: (self intVal: (self element: old at: 2))].
	(self element: old at: 3) ~= memory nilOop ifTrue: [jit osrThreshold: (self intVal: (self element: old at: 3))].
	self answer: r value
!
stringFrom: s
	<function>
	^memory stringFromUtf8: s size: (libc strlen: s)
!
flagsString
	"The flags that are on, comma-separated."
	<function>
	| buf n bit name len |
	buf := self local: 'char[256]'.
	n := 0.
	bit := 1.
	[bit <= jit lastFlag] whileTrue: [
		(jit flags bitAnd: bit) ~= 0 ifTrue: [
			name := jit flagName: bit asUInt32.
			len := libc strlen: name.
			n > 0 ifTrue: [
				buf at: n put: $, value.
				n := n + 1].
			libc memcpy: buf + n from: name size: len.
			n := n + len asInt64].
		bit := bit << 1].
	^memory stringFromUtf8: buf size: n asUInt64
! !

!JitPrimitives methodsFor: 'type feedback'!
primJitSendSites
	"aCompiledMethod jitSendSites: what the inline caches of its baseline code saw, {pc. state. classes. methods. selector} per send site in code order (state 0 unlinked, 1 monomorphic, 2 polymorphic, 3 megamorphic; a megamorphic site keeps the classes of the polymorphic cache it had; a super send has a method but no class), nil if it has no baseline code."
	<vmPrimitive: 182 name: 'jitSendSites'>
	| m n r e k count a |
	m := self receiver.
	((self isPtr: m) and: [(self rawClass: m) = (memory special: SO_COMPILEDMETHOD)]) ifFalse: [^self fail].
	n := jit brtFeedbackSitesOf: m.
	n < 0 ifTrue: [^self answer: memory nilOop].
	r := self local: 'oop'.
	e := self local: 'oop'.
	a := self local: 'oop'.
	a value: m.
	memory pushRoot: a.
	r value: (memory allocObj: memory clsArray format: F_VAR slots: n asUInt32).
	memory pushRoot: r.
	memory pushRoot: e.
	0 to: n - 1 do: [:i |
		e value: (memory allocObj: memory clsArray format: F_VAR slots: 5).
		self storeRef: r value at: i put: e value.
		self storeRef: e value at: 0 put: (self intOop: (jit brtFeedbackPcOf: a value site: i)).
		self storeRef: e value at: 1 put: (self intOop: (jit brtFeedbackStateOf: a value site: i)).
		count := jit brtFeedbackCasesOf: a value site: i.
		k := memory allocObj: memory clsArray format: F_VAR slots: count asUInt32.
		self storeRef: e value at: 2 put: k.
		k := memory allocObj: memory clsArray format: F_VAR slots: count asUInt32.
		self storeRef: e value at: 3 put: k.
		0 to: count - 1 do: [:j |
			self storeRef: (self element: e value at: 2) at: j put: (jit brtFeedbackClassOf: a value site: i case: j).
			self storeRef: (self element: e value at: 3) at: j put: (jit brtFeedbackTargetOf: a value site: i case: j)].
		self storeRef: e value at: 4 put: (jit brtFeedbackSelectorOf: a value site: i)].
	memory popRoot.
	memory popRoot.
	memory popRoot.
	self answer: r value
! !

!JitPrimitives methodsFor: 'disassembly'!
primJitCode
	"aCompiledMethod jitCode: modeName (nil: the current compiler, baseline under --jit none): {address. code (ByteArray). map {pc. offset ...}. notes {offset. text or nil (a bytecode). value ...}. symbols {address. name ...}. mode} of its machine code with the compiler's notes. Installed code with notes is answered as it is; otherwise the method is compiled for this and the code dropped. Answers nil if the compiler does not compile it."
	<vmPrimitive: 181 name: 'jitCode'>
	| m md p h scratch top |
	m := self receiver.
	((self isPtr: m) and: [(self rawClass: m) = (memory special: SO_COMPILEDMETHOD)]) ifFalse: [^self fail].
	md := jit mode = 0 ifTrue: [jit baselineMode] ifFalse: [jit mode].
	(self argCount > 0 and: [self arg0 ~= memory nilOop]) ifTrue: [
		(memory isKindOfString: self arg0) ifFalse: [^self fail].
		p := memory utf8Of: self arg0.
		p isNull ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
		md := jit modeNamed: p.
		libc free: p.
		md <= 0 ifTrue: [^self fail]].
	jit ensureOpen ifFalse: [^self fail].
	h := jit lookup: m.
	scratch := ((jit hasCode: h) and: [h mode = md and: [jit hasNotes: h]]) not.
	top := jit codeTop.
	scratch ifTrue: [h := jit compileCopy: m mode: md].
	(jit hasCode: h)
		ifTrue: [self answer: (self listingOf: h mode: md)]
		ifFalse: [self answer: memory nilOop].
	scratch ifTrue: [jit codeResetTo: top]
!
listingOf: h mode: md
	<function>
	| r a n s |
	r := self local: 'oop'.
	r value: (memory allocObj: memory clsArray format: F_VAR slots: 6).
	memory pushRoot: r.
	self storeRef: r value at: 0 put: (self intOop: h codeStart asInt64).
	a := memory allocBytes: memory clsBytearray count: h codeSize.
	libc memcpy: (self bytesOf: a) from: (self ptr: h codeStart) size: h codeSize.
	self storeRef: r value at: 1 put: a.
	n := h mapCount asInt64.
	a := memory allocObj: memory clsArray format: F_VAR slots: (2 * n) asUInt32.
	0 to: 2 * n - 1 do: [:i | (self slotsOf: a) at: i put: (self intOop: (h map at: i))].
	self storeRef: r value at: 2 put: a.
	n := h noteCount asInt64.
	a := memory allocObj: memory clsArray format: F_VAR slots: (3 * n) asUInt32.
	self storeRef: r value at: 3 put: a.
	0 to: n - 1 do: [:i |
		(self slotsOf: (self element: r value at: 3)) at: 3 * i put: (self intOop: (h noteOffsets at: i)).
		(self slotsOf: (self element: r value at: 3)) at: 3 * i + 2 put: (self intOop: (h noteValues at: i)).
		(h noteTexts at: i) ~= 0 ifTrue: [
			s := self stringFrom: (self cCoerce: (h noteTexts at: i) to: 'const char *').
			self storeRef: (self element: r value at: 3) at: 3 * i + 1 put: s]].
	n := jit symbolCount.
	a := memory allocObj: memory clsArray format: F_VAR slots: (2 * n) asUInt32.
	self storeRef: r value at: 4 put: a.
	0 to: n - 1 do: [:i |
		(self slotsOf: (self element: r value at: 4)) at: 2 * i put: (self intOop: (jit symbolAddressAt: i) asInt64).
		s := self stringFrom: (jit symbolNameAt: i).
		self storeRef: (self element: r value at: 4) at: 2 * i + 1 put: s].
	s := self stringFrom: (jit modeName: md).
	self storeRef: r value at: 5 put: s.
	memory popRoot.
	^r value
! !
