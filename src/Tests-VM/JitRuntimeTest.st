TestCase subclass: #JitRuntimeTest
	instanceVariableNames: 'saved'
	classVariableNames: ''
	package: 'Tests-VM'!

JitRuntimeTest comment: 'The JIT runtime under the baseline compiler (JitOptRuntimeTest: under the optimizing tier), switched on for each test (Smalltalk vm jitParameters:, every method compiled on its first activation): on-stack replacement, methods redefined and become while their machine code runs, process switches in compiled loops, deep recursion, perform: (argument counts, failures, kinds of targets, many selectors at one site), valueWithArguments:, code cache flushes (a VM with a 1 MB cache), the annotated disassembly. JitTest runs the JIT inside the simulator.'!

!JitRuntimeTest methodsFor: 'running'!
mode
	"The compiler under test."
	^'baseline'
!
setUp
	saved := Smalltalk vm jitParameters: {self mode. nil. 0. 5}
!
tearDown
	| on flags |
	on := (saved at: 2) substrings: ','.
	flags := #('arith' 'fuse' 'barrier' 'notes') inject: '' into: [:all :each |
		(all isEmpty ifTrue: [''] ifFalse: [all , ',']) , ((on includes: each) ifTrue: [each] ifFalse: ['-' , each])].
	Smalltalk vm jitParameters: {saved at: 1. flags. saved at: 3. saved at: 4}.
	JitRuntimeTestSubject selectors do: [:each | JitRuntimeTestSubject removeSelector: each].
	JitRuntimeTestArray class selectors do: [:each | JitRuntimeTestArray class removeSelector: each]
!
timeLimitMilliseconds
	^120000
! !

!JitRuntimeTest methodsFor: 'helpers'!
isX64
	"The JIT emits x86-64 (listings name its registers and instructions)."
	^Smalltalk vm jitArchitecture = #x86_64
!
disassemblyNotes
	"What the listing of sum: says, besides the bytecodes and the entry."
	^#('interrupt check' 'SmallInteger tag check' 'checked entry' 'return top')
!
define: aString
	JitRuntimeTestSubject compile: aString
!
stressed
	"Under --jit-flags deopt (JitOptRuntimeTest) optimized code leaves to the interpreter every so often."
	^false
!
statistics
	^Smalltalk vm statistics
! !

!JitRuntimeTest methodsFor: 'tests'!
testParameters
	| now |
	now := Smalltalk vm jitParameters.
	self assert: (now at: 1) equals: self mode.
	self assert: (now at: 3) equals: 0.
	self assert: (now at: 4) equals: 5.
	self assert: ((now at: 2) substrings: ',') asSet equals: ((saved at: 2) substrings: ',') asSet.
	self should: [Smalltalk vm jitParameters: #('nonsense' nil nil nil)] raise: Error.
	self should: [Smalltalk vm jitParameters: #(nil 'nonsense' nil nil)] raise: Error.
	self assert: Smalltalk vm jitMode equals: self mode asSymbol
!
testCompiledCodeRuns
	| before |
	self define: 'fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new fib: 20) equals: 6765.
	self assert: (self statistics - before) jitMethodsCompiled > 0
!
testActivationsFindCodeCompiledSinceTheEntryWasFilled
	"The send's cache entry counts answer's activations; answer is compiled at the fourth. Installing code leaves the entries as they are: the later activations through this one still enter the machine code. sends: must stay interpreted: a method compiled on its first activation (its hash shares a counter with others') calls answer from machine code, not through the entry; define it anew then."
	| before tries |
	Smalltalk vm jitParameters: #(nil nil 3 1000000).
	self define: 'answer | x | x := 1. ^x'.
	tries := 0.
	[self define: 'sends: n | s | s := 0. 1 to: n do: [:i | s := s + self answer]. ^s'.
	 before := self statistics.
	 self assert: (JitRuntimeTestSubject new sends: 20) equals: 20.
	 tries := tries + 1.
	 (JitRuntimeTestSubject >> #sends:) jitSendSites notNil and: [tries < 5]] whileTrue.
	self assert: (JitRuntimeTestSubject >> #sends:) jitSendSites isNil description: 'sends: was compiled'.
	self assert: (self statistics - before) jitEntries >= 17
!
testOnStackReplacement
	"A loop in a method the interpreter started: compiled after 5 backward jumps and continued in machine code."
	| before |
	Smalltalk vm jitParameters: #(nil nil 1000 5).
	self define: 'loop: n | s | s := 0. 1 to: n do: [:i | s := s + i]. ^s'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new loop: 100000) equals: 5000050000.
	self assert: (self statistics - before) jitOsrEntries > 0
!
testRedefinitionWhileRunning
	"Machine code sending a method that is redefined meanwhile finds the new one; a running activation of a redefined method finishes with its old code."
	self define: 'answer | x | x := 1. ^x'.
	self define: 'sumWhileRedefining | s | s := 0. 1 to: 10 do: [:i | i = 6 ifTrue: [self class compile: ''answer | x | x := 2. ^x'']. s := s * 10 + self answer]. ^s'.
	self assert: JitRuntimeTestSubject new sumWhileRedefining equals: 1111122222.
	self define: 'phase | r | r := 1. self class compile: ''phase ^2''. ^r'.
	self assert: JitRuntimeTestSubject new phase equals: 1.
	self assert: JitRuntimeTestSubject new phase equals: 2
!
testBecomeOfACompiledMethod
	| o |
	self define: 'alpha | x | x := 1. ^x'.
	self define: 'beta | x | x := 2. ^x'.
	self define: 'callAlpha ^self alpha + 0'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [self assert: o callAlpha equals: 1].
	(JitRuntimeTestSubject >> #alpha) becomeForward: (JitRuntimeTestSubject >> #beta).
	self assert: o callAlpha equals: 2
!
testBecomeOfAnEmbeddedLiteral
	"Old literals are in the code: full GCs and become update them."
	| o old |
	self define: 'literal ^#(1 2 3) , #()'.
	Smalltalk vm garbageCollect.
	o := JitRuntimeTestSubject new.
	self assert: o literal equals: #(1 2 3).
	Smalltalk vm garbageCollect.
	self assert: o literal equals: #(1 2 3).
	old := (JitRuntimeTestSubject >> #literal) literals detect: [:each | each = #(1 2 3)].
	old becomeForward: #(4 5) copy.
	self assert: o literal equals: #(4 5)
!
testProcessSwitchesInCompiledLoops
	| ping pong done log p |
	self define: 'ping: s pong: t log: log | r | r := 0. 1 to: 50 do: [:i | s signal. t wait. r := r + i. log add: i]. ^r'.
	ping := Semaphore new.
	pong := Semaphore new.
	log := OrderedCollection new.
	done := nil.
	p := self fork: [1 to: 50 do: [:i | ping wait. log add: i negated. pong signal]].
	done := JitRuntimeTestSubject new ping: ping pong: pong log: log.
	self assert: done equals: 1275.
	self assert: log size equals: 100.
	self assert: (log first: 4) asArray equals: #(-1 1 -2 2)
!
testTickerInterruptsInCompiledLoop
	"The high-priority process can only release the loop while it is running. Warm the method before arming the timer."
	| o flags |
	self define: 'spin: n flags: flags | i | i := 0. flags at: 2 put: true. [i < n and: [flags at: 1]] whileTrue: [i := i + 1]. flags at: 2 put: false. ^i'.
	o := JitRuntimeTestSubject new.
	flags := {true. false}.
	2 timesRepeat: [self assert: (o spin: 128 flags: flags) equals: 128].
	self fork: [[(Delay forMilliseconds: 1) wait. flags at: 2] whileFalse. flags at: 1 put: false]
		at: Processor activePriority + 1.
	self assert: (o spin: 20000000 flags: flags) < 20000000
!
testDeepRecursion
	| before |
	self define: 'depth: n ^n = 0 ifTrue: [0] ifFalse: [(self depth: n - 1) + 1]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new depth: 300000) equals: 300000.
	self assert: (self statistics - before) frameFlushes > 0
!
testCodeCacheFlush
	"A VM with a 1 MB code cache that keeps notes fills it often: all code is dropped and compiled again, the results stay right."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. self mode. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--jit-flags'. 'notes'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := 0. 10 timesRepeat: [r := r + (Compiler evaluate: ''(1 to: 10) inject: 0 into: [:a :b | a + b]'')]. String selectors do: [:s | Compiler compileMethod: (String >> s) source in: String classified: nil]. {r. Smalltalk vm statistics jitCacheFlushes > 0}'}).
	self assert: run output trimBoth equals: '#(550 true)'
!
testDisassembly
	| listing |
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | s := s + (i * 2)]. ^s'.
	listing := (JitRuntimeTestSubject >> #sum:) machineCode.
	self assert: (listing beginsWith: 'JitRuntimeTestSubject>>sum:  ' , self mode).
	self assert: (listing includesSubstring: 'pc 0: ').
	self assert: (listing includesSubstring: '-- sum: n').
	self disassemblyNotes do: [:each | self assert: (listing includesSubstring: each)].
	self assert: (((JitRuntimeTestSubject >> #sum:) machineCodeFor: self mode asSymbol) beginsWith: 'JitRuntimeTestSubject>>sum:  ' , self mode).
	self should: [(JitRuntimeTestSubject >> #sum:) machineCodeFor: #nonsense] raise: Error
! !

!JitRuntimeTest methodsFor: 'tests: perform'!
testPerform
	"perform: with up to four arguments and perform:withArguments: with up to seven, selectors the sends do not know: once their targets are cached no lookups (inline cache misses) and no sends through the runtime. The counters are the VM's, other Processes' included: the quietest of 3 rounds counts."
	| o sels arrays deltas |
	self define: 'zero ^0'.
	self define: 'one: x ^x'.
	self define: 'two: x with: y ^x * 10 + y'.
	self define: 'three: x with: y with: z ^(x * 10 + y) * 10 + z'.
	self define: 'four: x with: y with: z with: w ^((x * 10 + y) * 10 + z) * 10 + w'.
	self define: 'seven: a with: b with: c with: d with: e with: f with: g ^(((((a * 10 + b) * 10 + c) * 10 + d) * 10 + e) * 10 + f) * 10 + g'.
	self define: 'performs: n with: s with: a | r | r := 0. 1 to: n do: [:i | r := r + (self perform: (s at: 1)) + (self perform: (s at: 2) with: 1) + (self perform: (s at: 3) with: 1 with: 2) + (self perform: (s at: 4) with: 1 with: 2 with: 3) + (self perform: (s at: 5) with: 1 with: 2 with: 3 with: 4) + (self perform: (s at: 1) withArguments: (a at: 1)) + (self perform: (s at: 2) withArguments: (a at: 2)) + (self perform: (s at: 3) withArguments: (a at: 3)) + (self perform: (s at: 4) withArguments: (a at: 4)) + (self perform: (s at: 5) withArguments: (a at: 5)) + (self perform: (s at: 6) withArguments: (a at: 6))]. ^r'.
	self define: 'call: s withArguments: a ^self perform: s withArguments: a'.
	o := JitRuntimeTestSubject new.
	sels := #(#zero #one: #two:with: #three:with:with: #four:with:with:with: #seven:with:with:with:with:with:with:).
	arrays := #(#() #(1) #(1 2) #(1 2 3) #(1 2 3 4) #(1 2 3 4 5 6 7)).
	self assert: (o performs: 10 with: sels with: arrays) equals: 12373070.
	deltas := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		self assert: (o performs: 3000 with: sels with: arrays) equals: 3711921000.
		self statistics - before].
	self assert: (deltas collect: [:d | d jitInlineCacheMisses]) min < 300.
	self assert: (deltas collect: [:d | d optRuntimeSends]) min < 300.
	3 timesRepeat: [
		self assert: (o call: #three:with:with: withArguments: #(1 2 3)) equals: 123.
		self assert: (o call: #four:with:with:with: withArguments: #(1 2 3 4)) equals: 1234]
!
testPerformWithTheWrongArgumentCount
	"A selector of another argument count, or arguments not in an Array: the primitive fails, as in the interpreter."
	| o |
	self define: 'one: x ^x'.
	self define: 'call: s ^self perform: s'.
	self define: 'call: s with: x with: y ^self perform: s with: x with: y'.
	self define: 'call: s withArguments: a ^self perform: s withArguments: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self should: [o call: #one:] raise: Error.
		self should: [o call: #one: with: 1 with: 2] raise: Error.
		self should: [o call: #one: withArguments: #(1 2)] raise: Error.
		self should: [o call: #one: withArguments: (OrderedCollection with: 1)] raise: Error.
		self assert: (o call: #one: withArguments: #(5)) equals: 5]
!
testPerformNotUnderstood
	"A selector not understood: doesNotUnderstand: gets it and the arguments."
	| o |
	self define: 'doesNotUnderstand: aMessage ^{aMessage selector. aMessage arguments}'.
	self define: 'call: s with: x ^self perform: s with: x'.
	self define: 'call: s withArguments: a ^self perform: s withArguments: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o call: #noSuchSelector: with: 7) equals: #(#noSuchSelector: #(7)).
		self assert: (o call: #noSuch:selector: withArguments: #(1 2)) equals: #(#noSuch:selector: #(1 2))]
!
testPerformOfPerform
	| o |
	self define: 'plus: x ^x + 1'.
	self define: 'twice: x ^self perform: #perform:with: with: #plus: with: x'.
	self define: 'call: p with: s with: x ^self perform: p with: s with: x'.
	self define: 'call: p with: s withArguments: a ^self perform: p with: s with: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o twice: 1) equals: 2.
		self assert: (o call: #perform:with: with: #plus: with: 2) equals: 3.
		self assert: (o call: #perform:withArguments: with: #plus: withArguments: #(4)) equals: 5.
		self assert: (o perform: #perform: with: #yourself) == o]
!
testPerformTargets
	"Targets that are primitives in machine code, through their C function (one failing into its body), quick methods, a closure, a method not compiled yet."
	| o block |
	self define: 'x ^a'.
	self define: 'x: v a := v'.
	self define: 'call: r with: s ^r perform: s'.
	self define: 'call: r with: s with: v ^r perform: s with: v'.
	o := JitRuntimeTestSubject new.
	block := [:v | v * 2].
	3 timesRepeat: [
		self assert: (o call: 3 with: #+ with: 4) equals: 7.
		self assert: (o call: 3 with: #+ with: 2.5) equals: 5.5.
		self assert: (o call: #(10 20 30) with: #at: with: 2) equals: 20.
		self assert: (o call: 'abc' with: #size) equals: 3.
		self assert: (o call: #(1 2) with: #shallowCopy) equals: #(1 2).
		self assert: (o call: o with: #x: with: 5) == o.
		self assert: (o call: o with: #x) equals: 5.
		self assert: (o call: o with: #yourself) == o.
		self assert: (o call: nil with: #isNil).
		self assert: (o call: block with: #value: with: 21) equals: 42].
	Smalltalk vm jitParameters: #(nil nil 1000 nil).
	self define: 'fresh: v ^v + 1'.
	3 timesRepeat: [self assert: (o call: o with: #fresh: with: 1) equals: 2]
!
testPerformManySelectorsAndClasses
	"One perform: site, ten receiver classes and eleven selectors."
	| o receivers selectors |
	self define: 'call: r with: s ^r perform: s'.
	o := JitRuntimeTestSubject new.
	receivers := {3. 4.5. $a. 'str'. #sym. #(1 2). nil. Object new. 1 / 2. o}.
	selectors := #(#yourself #isNil #notNil #isString #isSymbol #isNumber #isCharacter #printString #class #isArray #isInteger).
	2 timesRepeat: [
		receivers do: [:r |
			self assert: (selectors collect: [:s | o call: r with: s]) equals: {r yourself. r isNil. r notNil. r isString. r isSymbol. r isNumber. r isCharacter. r printString. r class. r isArray. r isInteger}]]
!
testPerformAfterRedefinition
	"The method perform: finds is redefined while its target is cached: the next one finds the new method."
	self define: 'answer ^1'.
	self define: 'sumPerforming: s | t | t := 0. 1 to: 10 do: [:i | i = 6 ifTrue: [self class compile: ''answer ^2'']. t := t * 10 + (self perform: s)]. ^t'.
	self assert: (JitRuntimeTestSubject new sumPerforming: #answer) equals: 1111122222
!
testPerformDeepRecursion
	"Recursion through perform:with: (a selector the send knows, and one it does not) and perform:withArguments: deeper than the C stack: the frames become Contexts."
	| before |
	self define: 'depth: n ^n = 0 ifTrue: [0] ifFalse: [(self perform: #depth: with: n - 1) + 1]'.
	self define: 'depth: n via: s ^n = 0 ifTrue: [0] ifFalse: [(self perform: s with: n - 1 with: s) + 1]'.
	self define: 'depth: n via: s with: x ^n = 0 ifTrue: [0] ifFalse: [(self perform: s withArguments: (Array with: n - 1 with: s with: x)) + 1]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new depth: 200000) equals: 200000.
	self assert: (JitRuntimeTestSubject new depth: 200000 via: #depth:via:) equals: 200000.
	self assert: (JitRuntimeTestSubject new depth: 200000 via: #depth:via:with: with: 3) equals: 200000.
	self assert: (self statistics - before) frameFlushes > 0
!
testPerformFromAMarriedSender
	"perform:withArguments: from a married frame, whose Context must hold the arguments (a C primitive target may flush the frames): a C primitive that switches to another Process, three and four arguments; seven answer right or the primitive fails (the Context is too small), as in the interpreter."
	| o sem log seven |
	self define: 'married: r perform: s with: a | b | b := [:x | x]. thisContext. ^b value: (r perform: s withArguments: a)'.
	self define: 'three: x with: y with: z ^(x * 10 + y) * 10 + z'.
	self define: 'four: x with: y with: z with: w ^((x * 10 + y) * 10 + z) * 10 + w'.
	self define: 'seven: a with: b with: c with: d with: e with: f with: g ^(((((a * 10 + b) * 10 + c) * 10 + d) * 10 + e) * 10 + f) * 10 + g'.
	o := JitRuntimeTestSubject new.
	sem := Semaphore new.
	log := OrderedCollection new.
	self fork: [3 timesRepeat: [sem wait. log add: #woken]] at: Processor activePriority + 1.
	1 to: 3 do: [:i |
		self assert: (o married: sem perform: #signal with: #()) == sem.
		self assert: log size equals: i.
		self assert: (o married: o perform: #three:with:with: with: #(1 2 3)) equals: 123.
		self assert: (o married: o perform: #four:with:with:with: with: #(1 2 3 4)) equals: 1234.
		seven := [o married: o perform: #seven:with:with:with:with:with:with: with: #(1 2 3 4 5 6 7)] on: Error do: [:e | #failed].
		self assert: (seven = 1234567 or: [seven = #failed])]
!
testPerformWithProcessSwitches
	"A process wakes up every millisecond while perform: enters methods (their arguments moved down over the selector): interrupts at their entries switch to it, the results stay right."
	| o result ticks stop |
	self define: 'sum: n via: s | t | t := 0. 1 to: n do: [:i | t := t + (self perform: s with: i with: 1)]. ^t'.
	self define: 'add: x to: y ^x + y'.
	o := JitRuntimeTestSubject new.
	ticks := 0.
	stop := false.
	self fork: [[stop] whileFalse: [(Delay forMilliseconds: 1) wait. ticks := ticks + 1]] at: Processor activePriority + 1.
	"a loaded machine may wake it late: until it has woken up during a run"
	[[result := o sum: 1000000 via: #add:to:.
	  self assert: result equals: 500001500000.
	  ticks = 0] whileTrue] ensure: [stop := true]
! !

!JitRuntimeTest methodsFor: 'tests: copying'!
replacements
	"Results and receivers of replaceFrom:to:with:startingAt: (or the error) for fresh receivers of every element kind and other objects, replacements of every kind and the receiver itself, ranges within, overlapping either way, empty, out of bounds, and other arguments; long ones too."
	| long wide dsts srcs ranges |
	self define: 'replaceIn: dsts from: srcs ranges: ranges | r | r := OrderedCollection new. dsts do: [:b | srcs do: [:s0 | ranges do: [:t | | d s | d := b value. s := s0 == #self ifTrue: [d] ifFalse: [s0]. r add: ([d replaceFrom: (t at: 1) to: (t at: 2) with: s startingAt: (t at: 3)] on: Error do: [:e | e class name]) printString , '' '' , d printString]]]. ^r asArray'.
	long := ((1 to: 700) collect: [:i | i \\ 251]) asByteArray.
	wide := String with: (Character value: 955) with: $b with: $c with: $d with: $e with: $f.
	dsts := {[#[1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20] copy]. ['abcdefghijklmnopqrst' copy]. [#abcdefghijklmnopqrst]. ['abcdefghijklmnopqrst' copy beReadOnlyObject; yourself].
		[wide copy]. [Bitmap withAll: (1 to: 20)]. [(1 to: 20) asArray]. [WeakArray new: 20].
		[(2 raisedTo: 160) + 12345]. [long copy]. [String new: 3]. [Array new: 0]. [OrderedCollection withAll: (1 to: 20)]}.
	srcs := {#self. #[101 102 103 104 105 106 107 108 109 110 111 112]. 'ABCDEFGHIJKL'. #ABCDEFGHIJKL. String with: (Character value: 1000) with: $Y with: $Z.
		Bitmap withAll: (100 to: 111). (101 to: 112) asArray. (101 to: 112) asOrderedCollection. long. 3. nil}.
	ranges := #(#(1 5 1) #(3 10 1) #(1 8 3) #(2 2 1) #(1 0 1) #(5 4 1) #(0 -1 1) #(1 0 0) #(6 5 99) #(0 3 1) #(1 3 0) #(1 21 1) #(18 22 1) #(1 3 11) #(1 3 12) #(5 3 1) #(1 1 -1) #(1 20 1) #(13 20 1) #(1 700 1) #(5 700 1) #(1 690 11) #(1 3 nil) #(nil 3 1) #(1 3.0 1) #(1 4611686018427387903 1)).
	^JitRuntimeTestSubject new replaceIn: dsts from: srcs ranges: ranges
!
testReplaceFromToWithStartingAt
	"replaceFrom:to:with:startingAt: in machine code copies and answers what its C function does, failures included (see replacements); the copies it does call no C function (the VM's counter, other Processes' calls included: the quietest of 3 rounds counts)."
	| on off calls |
	on := self replacements.
	Smalltalk vm jitParameters: #(nil '-prims' nil nil).
	[off := self replacements] ensure: [Smalltalk vm jitParameters: #(nil 'prims' nil nil)].
	self assert: on size equals: off size.
	1 to: on size do: [:i | self assert: (on at: i) equals: (off at: i)].
	self assert: (on includes: '#[1 2 1 2 3 4 5 6 7 8 11 12 13 14 15 16 17 18 19 20] #[1 2 1 2 3 4 5 6 7 8 11 12 13 14 15 16 17 18 19 20]').
	self define: 'copies: n | s t | s := ''abcdefghij''. t := Array new: 3. 1 to: n do: [:i | (s copyFrom: 2 to: 9) , ''xyz''. t replaceFrom: 1 to: 3 with: #(1 2 3) startingAt: 1]. ^t'.
	calls := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		JitRuntimeTestSubject new copies: 1000.
		(self statistics - before) jitPrimitiveCalls].
	self assert: calls min < 1000
!
testReplaceRemembersAnOldReceiver
	"Young objects copied into an old Array: it is remembered, the objects survive the scavenges (in their places)."
	| old |
	self define: 'fill: a times: n | young | 1 to: n do: [:i | young := (1 to: a size) collect: [:k | (k * i) printString]. a replaceFrom: 1 to: a size with: young startingAt: 1. Smalltalk vm scavenge. a replaceFrom: 2 to: a size with: a startingAt: 1. Smalltalk vm scavenge. a replaceFrom: 1 to: 1 with: young startingAt: 1. 1 to: a size do: [:k | (a at: k) = ((k - 1 max: 1) * i) printString ifFalse: [^k]]. Smalltalk vm garbageCollect]. ^0'.
	old := Array new: 50.
	Smalltalk vm garbageCollect.
	self assert: (JitRuntimeTestSubject new fill: old times: 5) equals: 0
! !

!JitRuntimeTest methodsFor: 'tests: copying'!
testReplaceKeepsItsSemantics
	"What code relies on, in compiled code: a copy within one object as memmove does it (either way), bytes into bytes of another class (ByteArray, ByteString, from a Symbol), 32-bit words into 32-bit words; elements of another width are the fallback's (a ByteString takes a wide Character by widening)."
	| expected |
	self define: 'semantics | r b | r := OrderedCollection new.
		b := ''hello world'' copy. b replaceFrom: 1 to: 5 with: b startingAt: 7. r add: b.
		b := ''0123456789'' copy. b replaceFrom: 3 to: 10 with: b startingAt: 1. r add: b.
		b := ((1 to: 300) collect: [:i | i \\ 256]) asByteArray. b replaceFrom: 1 to: 290 with: b startingAt: 11. r add: (b first: 3) asArray; add: (b last: 11) asArray.
		b := ((1 to: 300) collect: [:i | i \\ 256]) asByteArray. b replaceFrom: 11 to: 300 with: b startingAt: 1. r add: (b first: 12) asArray; add: (b last: 2) asArray.
		r add: ((ByteArray new: 3) replaceFrom: 1 to: 3 with: ''abc'' startingAt: 1).
		r add: ((String new: 3) replaceFrom: 1 to: 3 with: #[104 105 33] startingAt: 1).
		r add: ((String new: 4 withAll: $ ) replaceFrom: 2 to: 4 with: #symbol startingAt: 2).
		r add: ((ByteArray new: 2) replaceFrom: 1 to: 2 with: #ab startingAt: 1).
		r add: ((Bitmap new: 3) replaceFrom: 1 to: 3 with: (Bitmap withAll: #(7 8 9 10)) startingAt: 2) asArray.
		b := String new: 2. b replaceFrom: 1 to: 2 with: (String with: (Character value: 955) with: $x) startingAt: 1. r add: b isWideString; add: (b asArray collect: [:c | c value]).
		b := String with: (Character value: 955) with: $x with: $y. b replaceFrom: 2 to: 3 with: ''ab'' startingAt: 1. r add: (b asArray collect: [:c | c value]).
		r add: ([(ByteArray new: 2) replaceFrom: 1 to: 2 with: (Bitmap new: 2) startingAt: 1. #copied] on: Error do: [:e | #failed]).
		^r asArray'.
	expected := {'world world'. '0101234567'. #(11 12 13). #(44 35 36 37 38 39 40 41 42 43 44). #(1 2 3 4 5 6 7 8 9 10 1 2). #(33 34). #[97 98 99]. 'hi!!'. ' ymb'. #[97 98]. #(8 9 10). true. #(955 120). #(955 97 98). #copied}.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new semantics equals: expected]
!
testAllocationOfBytesAndWords
	"ByteArrays, ByteStrings, WideStrings and Bitmaps of sizes 0 to 70 and large ones come zeroed, of their size and class, with a hash; strings made of them compare and hash as literals do. Enough of them fill eden many times over (the slow path)."
	| scavenges |
	self define: 'allocs: n | r | r := OrderedCollection new. 0 to: n do: [:k | r add: (ByteArray new: k); add: (String new: k); add: (WideString new: k); add: (Bitmap new: k)]. #(4095 4096 4097 32767 32768 32769 100000) do: [:k | r add: (ByteArray new: k); add: (Bitmap new: k // 4)]. ^r'.
	self define: 'filled: k ^(String new: k) atAllPut: $a; yourself'.
	self define: 'churn: n | s | s := 0. 1 to: n do: [:i | s := s + (ByteArray new: i \\ 200) size + (String new: 3) size + (Bitmap new: i \\ 50) size]. ^s'.
	3 timesRepeat: [| objs |
		objs := JitRuntimeTestSubject new allocs: 70.
		self assert: objs size equals: 71 * 4 + 14.
		objs do: [:o |
			self assert: (o allSatisfy: [:e | e = 0 or: [e = (Character value: 0)]]).
			self assert: o identityHash > 0].
		0 to: 70 do: [:k |
			self assert: (objs at: 4 * k + 1) class equals: ByteArray.
			self assert: (objs at: 4 * k + 1) size equals: k.
			self assert: (objs at: 4 * k + 2) class equals: ByteString.
			self assert: (objs at: 4 * k + 2) size equals: k.
			self assert: (objs at: 4 * k + 3) class equals: WideString.
			self assert: (objs at: 4 * k + 3) size equals: k.
			self assert: (objs at: 4 * k + 4) class equals: Bitmap.
			self assert: (objs at: 4 * k + 4) size equals: k].
		self assert: ((objs last: 14) collect: [:o | o size]) asArray equals: #(4095 1023 4096 1024 4097 1024 32767 8191 32768 8192 32769 8192 100000 25000).
		0 to: 20 do: [:k |
			self assert: (JitRuntimeTestSubject new filled: k) equals: (String new: k withAll: $a).
			self assert: (JitRuntimeTestSubject new filled: k) hash equals: (String new: k withAll: $a) hash]].
	scavenges := self statistics scavenges.
	self assert: (JitRuntimeTestSubject new churn: 300000) equals: 300000 * 3 + (1500 * 199 * 200 / 2) + (6000 * 49 * 50 / 2).
	self assert: self statistics scavenges > scavenges
! !

!JitRuntimeTest methodsFor: 'tests: primitives'!
leafPrimitiveResults
	"Leaf primitives (with no arguments up to four) that answer and that fail, through their methods (the fallback's result, or the error's class), and methods of the subject's whose leaf primitive fails on it (arguments and receiver intact in the body, the error code nil)."
	self define: 'leafs | r try | r := OrderedCollection new. try := [:b | r add: (b on: Error do: [:e | e class name])].
		try value: [''abcdefg'' indexOf: $d startingAt: 2]. try value: [''abcdefg'' indexOf: $d startingAt: 5]. try value: [''abcdefg'' indexOf: 100 startingAt: 1]. try value: [''abc'' indexOf: $a startingAt: 0]. try value: [(String with: (Character value: 955) with: $q) indexOf: $q startingAt: 1].
		try value: [''abcdefg'' indexOfSubCollection: ''cde'' startingAt: 1]. try value: [''abcdefg'' indexOfSubCollection: ''cde'' startingAt: 4]. try value: [''abcdefg'' indexOfSubCollection: #(1 2) startingAt: 1]. try value: [''abcdefg'' indexOfSubCollection: ''a'' startingAt: nil]. try value: [''abcdefg'' includesSubstring: ''fg''].
		try value: [''abc'' compareWith: ''abd'']. try value: [''abc'' compareWith: 3]. try value: [''abc'' lowercaseCompare: ''ABC'']. try value: [''abc'' hash]. try value: [#[1 2 3 4 5] uint16At: 2]. try value: [#[1 2 3 4 5] uint16At: 5]. try value: [#[1 2 3 4 5] uint16BigEndianAt: 1]. try value: [#[1 2 3 4 5] int16At: 4].
		try value: [(ByteArray new: 8) uint32At: 2 put: 16r01020304; yourself]. try value: [(ByteArray new: 8) uint32At: 6 put: 1; yourself]. try value: [(ByteArray new: 8) float64At: 1 put: 2.5; yourself]. try value: [(ByteArray new: 8) float64At: 1 put: 3; yourself].
		try value: [(2 raisedTo: 70) compareInteger: (2 raisedTo: 71)]. try value: [(2 raisedTo: 70) compareInteger: 7]. try value: [12 bitXor: 10]. try value: [12 bitXor: (2 raisedTo: 70)]. try value: [3.75 truncated]. try value: [1.0e300 truncated]. try value: [$a value].
		try value: [(String new: 5) replaceFrom: 2 to: 4 with: ''xyz'' startingAt: 1; yourself]. try value: [(String new: 5) replaceFrom: 2 to: 6 with: ''xyzuv'' startingAt: 1; yourself].
		r add: self hashed = self identityHash; add: (self plus: 3); add: (self cmp: ''x''); add: (self idx: $a from: 1); add: (self rep: 1 to: 2 with: ''ab'' from: 1).
		^r asArray'.
	self define: 'hashed <primitive: ''identityHash''> ^#failed'.
	self define: 'plus: x <primitive: ''intAdd''> ^{#failed. x. self class name}'.
	self define: 'cmp: x <primitive: ''stringCompare'' error: ec> ^{#failed. x. ec. self class name}'.
	self define: 'idx: c from: s <primitive: ''stringIndexOf''> ^{#failed. c. s. self class name}'.
	self define: 'rep: i to: j with: s from: k <primitive: ''replaceFromToWithStartingAt''> ^{#failed. i. j. s. k. self class name}'.
	^JitRuntimeTestSubject new leafs
!
testLeafPrimitives
	"Leaf C primitives, which machine code calls directly, answer and fail as through the runtime (--jit-flags -prims): every argument count, failures falling into the method's body with its receiver and arguments, the error code nil; the calls are counted (C primitive calls)."
	| on off calls |
	on := (1 to: 3) collect: [:i | self leafPrimitiveResults].
	Smalltalk vm jitParameters: #(nil '-prims' nil nil).
	[off := self leafPrimitiveResults] ensure: [Smalltalk vm jitParameters: #(nil 'prims' nil nil)].
	on do: [:each | self assert: each equals: off].
	self assert: (off first: 3) equals: #(4 0 0).
	self assert: (off at: 5) equals: 2.
	self assert: (off last: 5) equals: {true. {#failed. 3. #JitRuntimeTestSubject}. {#failed. 'x'. nil. #JitRuntimeTestSubject}. {#failed. $a. 1. #JitRuntimeTestSubject}. {#failed. 1. 2. 'ab'. 1. #JitRuntimeTestSubject}}.
	self assert: (((JitRuntimeTestSubject >> #idx:from:) machineCodeFor: #baseline) includesSubstring: 'called directly').
	self define: 'calls: n | s c | s := ''abcdefg''. c := 0. 1 to: n do: [:i | c := c + (s indexOf: $g startingAt: 1)]. ^c'.
	calls := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		self assert: (JitRuntimeTestSubject new calls: 1000) equals: 7000.
		(self statistics - before) jitPrimitiveCalls].
	self assert: calls max >= 1000
! !

!JitRuntimeTest methodsFor: 'tests: primitives'!
testStringHashAndCompare
	"String>>hash (FNV-1a, or 8 bytes a word past 8 code points all below 256), compareWith: (also where only = 0 uses it) and = in compiled code answer what their definitions in Smalltalk do: Strings of every size to 40, each with its first, middle or last byte changed up or down or to one above 127 (compared unsigned), against each other and against Symbols, a WideString and a ByteArray (bytes: the primitive takes them)."
	| strings others o def cmp |
	self define: 'hashOf: s ^s hash'.
	self define: 'compare: a with: b ^a compareWith: b'.
	self define: 'equal: a to: b ^a = b'.
	self define: 'bytes: a equal: b ^(a compareWith: b) = 0'.
	def := [:s | | m h w k |
		(s size <= 8 or: [s anySatisfy: [:c | c asInteger > 255]])
			ifTrue: [
				h := 2166136261.
				s do: [:c | h := ((h bitXor: c asInteger) * 16777619) bitAnd: 16rFFFFFFFF].
				h bitAnd: 16r3FFFFFFF]
			ifFalse: [
				m := 16rFFFFFFFFFFFFFFFF.
				h := s size.
				w := 0.
				k := 0.
				s do: [:c |
					w := w bitOr: (c asInteger bitShift: 8 * k).
					k := k + 1.
					k = 8 ifTrue: [
						h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m.
						w := 0.
						k := 0]].
				k > 0 ifTrue: [h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m].
				h := h bitXor: (h bitShift: -32).
				h := (h * 16r2545F4914F6CDD1D) bitAnd: m.
				h := h bitXor: (h bitShift: -29).
				h bitAnd: 16r3FFFFFFF]].
	cmp := [:a :b | | r |
		r := nil.
		1 to: (a size min: b size) do: [:i | (r isNil and: [(a at: i) asInteger ~= (b at: i) asInteger]) ifTrue: [r := (a at: i) asInteger < (b at: i) asInteger ifTrue: [-1] ifFalse: [1]]].
		r ifNil: [(a size - b size) sign]].
	strings := OrderedCollection new.
	0 to: 40 do: [:n | | base |
		base := String new: n.
		1 to: n do: [:i | base at: i put: (Character value: 97 + (i \\ 26))].
		strings add: base.
		n > 0 ifTrue: [
			{1. n // 2 + 1. n} do: [:p | #(1 -1 200) do: [:d | | v |
				v := base copy.
				v at: p put: (Character value: (d = 200 ifTrue: [200] ifFalse: [(v at: p) asInteger + d])).
				strings add: v]]]].
	others := {#abc. #abcdefghijklmnop. 'abd' asWideString. #[97 98 99]}.
	o := JitRuntimeTestSubject new.
	strings do: [:a |
		self assert: (o hashOf: a) equals: (def value: a).
		(strings , others) do: [:b |
			(a size - b size) abs <= 1 ifTrue: [
				self assert: (o compare: a with: b) equals: (cmp value: a value: b).
				self assert: (o bytes: a equal: b) equals: (cmp value: a value: b) = 0.
				self assert: (o equal: a to: b) equals: (b isString and: [(cmp value: a value: b) = 0])]]].
	others do: [:a | a isString ifTrue: [self assert: (o hashOf: a) equals: (def value: a)]].
	self assert: (o compare: #abc with: 'abc') equals: 0.
	self assert: (o equal: #abc to: 'abc')
! !

!JitRuntimeTest methodsFor: 'tests: copying'!
testCopiesOfEveryLengthAndOverlap
	"replaceFrom:to:with:startingAt: in compiled code (the copy stub) against element by element copies: bytes, 32-bit words and pointers, every length up to 80 (40), within one object shifted either way by up to 9 elements (overlapping or not), and into another object between guard elements that stay."
	self define: 'within: b n: n by: o | e |
		e := b copy. 1 to: n do: [:i | e at: 40 + o + i - 1 put: (b at: 40 + i - 1)].
		b replaceFrom: 40 + o to: 40 + o + n - 1 with: b startingAt: 40. ^b = e'.
	self define: 'into: d from: s n: n at: k | e |
		e := d copy. 1 to: n do: [:i | e at: k + i - 1 put: (s at: i + 3)].
		d replaceFrom: k to: k + n - 1 with: s startingAt: 4. ^d = e'.
	self define: 'copies: make n: max | bad |
		bad := OrderedCollection new.
		0 to: max do: [:n |
			-9 to: 9 do: [:o | ((self within: (make value: 140) n: n by: o) and: [self into: (make value: 140) from: ((make value: 240) copyFrom: 101 to: 200) n: n at: 11 + o]) ifFalse: [bad add: n -> o]]].
		^bad asArray'.
	3 timesRepeat: [
		self assert: (JitRuntimeTestSubject new copies: [:k | ((1 to: k) collect: [:i | i * 7 \\ 251]) asByteArray] n: 80) equals: #().
		self assert: (JitRuntimeTestSubject new copies: [:k | Bitmap withAll: ((1 to: k) collect: [:i | i * 123457 \\ 16rFFFFFFFF])] n: 40) equals: #().
		self assert: (JitRuntimeTestSubject new copies: [:k | (1 to: k) collect: [:i | i printString]] n: 40) equals: #()]
! !

!JitRuntimeTest methodsFor: 'tests: arithmetic'!
testModuloByAVariable
	"x \\ d of SmallIntegers in compiled code is the truncated remainder, floored: divisors that are positive powers of two (a mask) and others, negative ones, the ends of the range, dividends of both signs."
	| o xs ds |
	self define: 'mod: x by: d ^x \\ d'.
	o := JitRuntimeTestSubject new.
	xs := #(0 1 -1 7 -7 8 -8 1000 -1000 12345 -12345) , {SmallInteger maxVal. SmallInteger maxVal - 1. SmallInteger minVal. SmallInteger minVal + 1}.
	ds := #(1 2 3 4 7 8 16 1024 1000 -1 -2 -3 -4 -8 -16) , {SmallInteger maxVal. SmallInteger minVal. 1 bitShift: 40. (1 bitShift: 40) negated. (1 bitShift: 40) + 1}.
	3 timesRepeat: [
		xs do: [:x | ds do: [:d | | r |
			r := x rem: d.
			(r ~= 0 and: [r < 0 ~= (d < 0)]) ifTrue: [r := r + d].
			self assert: (o mod: x by: d) equals: r]]]
!
divisors
	"Divisors for the constant division tests: 1 to 20, 2^k and 2^k +- 1 of either sign for every k SmallIntegers reach, others, the extremes and their neighbours."
	| ds |
	ds := OrderedCollection new.
	ds addAll: (1 to: 20); addAll: #(25 641 1000 6700417 1000000007 1000000000000000000 3458764513820540928).
	0 to: 61 do: [:k | | p | p := 1 bitShift: k. ds add: p; add: p - 1; add: p + 1].
	ds addAll: {SmallInteger maxVal. SmallInteger maxVal - 1}.
	ds := (ds collect: [:d | {d. d negated}]) inject: OrderedCollection new into: [:all :each | all addAll: each; yourself].
	ds add: SmallInteger minVal; add: SmallInteger minVal + 1.
	^(ds select: [:d | d ~= 0 and: [d class == SmallInteger]]) asSet asSortedCollection asArray
!
dividends
	"Dividends: small ones, 2^k and its neighbours of either sign, SmallInteger's extremes and their neighbours, and others spread over the range (a fixed sequence)."
	| xs x |
	xs := OrderedCollection new.
	xs addAll: (-9 to: 9); addAll: {SmallInteger maxVal. SmallInteger minVal. SmallInteger maxVal - 1. SmallInteger minVal + 1. SmallInteger maxVal // 2. SmallInteger minVal // 2}.
	0 to: 61 do: [:k | | p | p := 1 bitShift: k. xs add: p - 1; add: p + 1; add: p negated; add: p negated - 1].
	x := 12345.
	1 to: 60 do: [:i | x := x * 1103515245 + 12345 \\ SmallInteger maxVal. xs add: (x bitShift: 0 - (i \\ 61)); add: (x bitShift: 0 - (i \\ 61)) negated].
	^(xs select: [:e | e class == SmallInteger]) asArray
!
divisionMethodFor: d index: i
	"A method dividing by the constant d every x and the multiples of d around it (q*d - 1, q*d, q*d + 1): its count of results unlike dividing by d in a variable."
	| ds |
	ds := d printString.
	^'div' , i printString , ': xs v: dv | bad v m e | bad := 0. v := dv at: 1. xs do: [:x0 | m := x0 // v * v. {x0. m - 1. m. m + 1} do: [:x | x class == SmallInteger ifTrue: [
		e := x - (x rem: v).
		((x // ' , ds , ') = (x // v) and: [(x \\ ' , ds , ') = (x \\ v) and: [(x rem: ' , ds , ') = (x rem: v) and: [(x quo: ' , ds , ') = (x quo: v) and: [(e / ' , ds , ') = (e quo: v)]]]]) ifFalse: [bad := bad + 1]]]]. ^bad'
!
testDivisionByConstants
	"Division and modulo (floored and truncated) and exact division by constants (shifts for powers of two, else a multiplication by a magic number) answer what they answer by the same divisor in a variable: every divisor of divisors, every dividend of dividends and the multiples around it, SmallInteger's extremes (the most negative by -1 overflows into a LargeInteger)."
	| ds xs bad o |
	ds := self divisors.
	xs := self dividends.
	ds doWithIndex: [:d :i | self define: (self divisionMethodFor: d index: i)].
	o := JitRuntimeTestSubject new.
	bad := OrderedCollection new.
	ds doWithIndex: [:d :i | 1 to: 2 do: [:round | | n | n := o perform: ('div' , i printString , ':v:') asSymbol with: xs with: {d}. n > 0 ifTrue: [bad add: d -> n]]].
	self assert: bad asArray equals: #().
	self define: 'minByMinusOne: x ^x // -1'.
	self assert: (o minByMinusOne: SmallInteger minVal) equals: SmallInteger maxVal + 1
! !

!JitRuntimeTest methodsFor: 'tests: copying'!
garbageSource
	"garbage leaves eden full of objects of 255s and 16rFFFFFFFFs (copies made and dropped): what is allocated next lands on them."
	^'garbage | b w | b := ByteArray new: 2000. b atAllPut: 255. w := Bitmap new: 500. w atAllPut: 16rFFFFFFFF. 1 to: 10 do: [:i | b copy. w copy]'
!
copyingSource
	"copies: max answers the copyFrom:to: and , that do not answer what element by element copies answer: bytes, Strings, 32-bit words, sizes 0 to max and large ones, each made on garbage (garbageSource)."
	^'copies: max | bad |
		bad := OrderedCollection new.
		((0 to: max) asArray , #(1000 4095 4096 4097 32767 32769 40000)) do: [:n | | b s w ws |
			b := ByteArray new: n + 10. 1 to: n + 10 do: [:i | b at: i put: i * 7 \\ 251 + 1].
			s := ByteString new: n + 10. 1 to: n + 10 do: [:i | s at: i put: (Character value: i * 7 \\ 90 + 33)].
			w := Bitmap new: n + 10. 1 to: n + 10 do: [:i | w at: i put: i * 123457 + 1 \\ 16rFFFFFFFF].
			ws := WideString new: n + 10. 1 to: n + 10 do: [:i | ws at: i put: (Character value: i * 7 + 300)].
			{b. s. w. ws} do: [:x | | c d |
				self garbage.
				c := x copyFrom: 3 to: n + 2.
				(c class == x class and: [c size = n and: [(1 to: n) allSatisfy: [:i | (c at: i) = (x at: i + 2)]]]) ifFalse: [bad add: x class name -> n].
				self garbage.
				d := (x copyFrom: 1 to: n) , (x copyFrom: 5 to: 9).
				(d size = (n + 5) and: [((1 to: n) allSatisfy: [:i | (d at: i) = (x at: i)]) and: [(1 to: 5) allSatisfy: [:i | (d at: n + i) = (x at: i + 4)]]]) ifFalse: [bad add: x class name -> n negated]]].
		^bad asArray'
!
fillingSources
	"New objects that one copy fills (fusedReplaceOf:: stop a SmallInteger before the allocation, no guard in between): all of them, part of them (the rest zeroed), from themselves (nothing written yet: all zero)."
	^#('fillB: k stop: s0 from: x | r s | s := s0 + 0. r := ByteArray new: k. s > 0 ifTrue: [r replaceFrom: 1 to: s with: x startingAt: 1]. ^r'
		'fillW: k stop: s0 from: x | r s | s := s0 + 0. r := Bitmap new: k. s > 0 ifTrue: [r replaceFrom: 1 to: s with: x startingAt: 1]. ^r'
		'selfB: k at: j | r n | n := k - j + 1. r := ByteArray new: k. r replaceFrom: 1 to: n with: r startingAt: j. ^r'
		'selfW: k at: j | r n | n := k - j + 1. r := Bitmap new: k. r replaceFrom: 1 to: n with: r startingAt: j. ^r')
!
fillingResults
	"What fillingSources answer that is not what they should (called often enough first to be optimized with the feedback they give), every size to 40, made on garbage."
	| o bad src wsrc r |
	self define: self garbageSource.
	self fillingSources do: [:each | self define: each].
	o := JitRuntimeTestSubject new.
	bad := OrderedCollection new.
	src := (1 to: 60) asByteArray.
	wsrc := Bitmap withAll: (16rFFFFFF01 to: 16rFFFFFF3C).
	1 to: 1200 do: [:i | o fillB: 8 stop: 3 from: src; fillW: 8 stop: 3 from: wsrc; selfB: 8 at: i \\ 2 + 1; selfW: 8 at: i \\ 2 + 1].
	0 to: 40 do: [:k |
		0 to: k do: [:s |
			o garbage.
			r := o fillB: k stop: s from: src.
			r asArray = ((1 to: k) collect: [:i | i <= s ifTrue: [i] ifFalse: [0]]) asArray ifFalse: [bad add: {#fillB. k. s}].
			o garbage.
			r := o fillW: k stop: s from: wsrc.
			r asArray = ((1 to: k) collect: [:i | i <= s ifTrue: [wsrc at: i] ifFalse: [0]]) asArray ifFalse: [bad add: {#fillW. k. s}]].
		1 to: 2 do: [:j |
			o garbage.
			((o selfB: k at: j) allSatisfy: [:e | e = 0]) ifFalse: [bad add: {#selfB. k. j}].
			o garbage.
			((o selfW: k at: j) allSatisfy: [:e | e = 0]) ifFalse: [bad add: {#selfW. k. j}]]].
	^bad asArray
!
testFusedAllocationAndCopy
	"copyFrom:to: and , answer what element by element copies do (copyingSource), new objects filled in full or in part or from themselves are what they should be (fillingResults), all made on garbage, here and in a VM with a 1 MB eden under the heap verifier (at most 100 s; any error is its answer); a copy into a new object whose fast path fails (the replacement too short: the fallback copies until it fails) leaves the new object's other elements zeroed."
	| child short r |
	self mode = 'opt' ifTrue: [Smalltalk vm jitParameters: #(nil '-eager' nil nil)].
	self define: self garbageSource.
	self define: self copyingSource.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new copies: 70) equals: #()].
	self assert: self fillingResults equals: #().
	short := #[1 2 3 4 5].
	1 to: 40 do: [:n |
		JitRuntimeTestSubject new garbage.
		r := [JitRuntimeTestSubject new fillB: n stop: n from: short] on: Error do: [:e | | c |
			c := e signalerContext.
			[c method selector = #fillB:stop:from:] whileFalse: [c := c sender].
			c tempAt: 4].
		self assert: r size equals: n.
		self assert: r asArray equals: ((1 to: n) collect: [:i | i <= 5 ifTrue: [i] ifFalse: [0]]) asArray].
	child := (OSProcess command: (OSProcess commandFor: {'env'. 'SAMALTAK_VERIFY_GC=1'. 'vm/build/samaltak'. '--eden'. '1'. '--jit'. self mode. '--jit-threshold'. '0'. '--jit-flags'. (self mode = 'opt' ifTrue: ['eager'] ifFalse: ['notes']). Smalltalk vm imagePath. '--headless'. '--eval'.
		'[JitRuntimeTestSubject compile: ' , self garbageSource printString , '. JitRuntimeTestSubject compile: ' , self copyingSource printString , '. (JitRuntimeTestSubject new copies: 40) , (JitRuntimeTestSubject new copies: 40)] on: Error do: [:e | ''failed: '' , e messageText]'})) start.
	[self assert: (self waitFor: [child poll] timeout: 100000)] ensure: [child terminate].
	self assert: child output trimBoth equals: '#()'
! !

!JitRuntimeTest methodsFor: 'tests: allocation'!
testAllocationWhosePrimitiveFails
	"An allocation whose primitive fails answers what its fallback answers (here nil, or a String), and sends to it go to that: compiled code does not take it for an instance of the class."
	| o |
	JitRuntimeTestArray class compile: 'make: n <primitive: ''basicNew:'' error: ec> ^n = -1 ifTrue: [nil] ifFalse: [''fallback'' , ec printString]'.
	self define: 'make: n | x | x := JitRuntimeTestArray make: n. ^{x. x printString. x isNil}'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o make: 2) first class equals: JitRuntimeTestArray.
		self assert: (o make: -1) equals: {nil. 'nil'. true}.
		self assert: (o make: 1099511627776) equals: {'fallback1'. '''fallback1'''. false}]
! !

!JitRuntimeTest methodsFor: 'tests: speculation'!
testReassignedGlobalClass
	"Code that reads a global holding a class sees the value the global holds when it runs: another class, something else, the class again."
	| o |
	Smalltalk at: #JitRuntimeTestGlobal put: Array.
	[self define: 'makeGlobal ^JitRuntimeTestGlobal new: 2'.
	self define: 'makeGlobals: n | r | r := OrderedCollection new. 1 to: n do: [:i | r add: self makeGlobal class]. ^r asArray'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [self assert: (o makeGlobals: 3) equals: {Array. Array. Array}].
	Smalltalk at: #JitRuntimeTestGlobal put: OrderedCollection.
	3 timesRepeat: [self assert: (o makeGlobals: 2) equals: {OrderedCollection. OrderedCollection}].
	Smalltalk at: #JitRuntimeTestGlobal put: 'ab'.
	self assert: ([o makeGlobal] on: Error do: [:e | #failed]) equals: #failed.
	Smalltalk at: #JitRuntimeTestGlobal put: ByteArray.
	3 timesRepeat: [self assert: (o makeGlobals: 2) equals: {ByteArray. ByteArray}]]
		ensure: [Smalltalk removeKey: #JitRuntimeTestGlobal ifAbsent: []]
!
testBranchesOnBooleans
	"Branches on ==, ~~, isNil and on what and: and or: answer (phis of Booleans), on comparisons an inlined method answers, on constants; a value that is not a Boolean still sends mustBeBoolean."
	| o |
	self define: 'same: a as: b ^(a == b) ifTrue: [1] ifFalse: [(a ~~ b and: [a isNil]) ifTrue: [2] ifFalse: [3]]'.
	self define: 'either: a or: b ^(a or: [b]) ifTrue: [#yes] ifFalse: [#no]'.
	self define: 'positive: x ^(self isPositive: x) ifTrue: [#pos] ifFalse: [#neg]'.
	self define: 'isPositive: x ^x > 0'.
	self define: 'folded ^(#a == #a) ifTrue: [(3 == 4) ifTrue: [#wrong] ifFalse: [#right]] ifFalse: [#wrong]'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: ({o same: 1 as: 1. o same: nil as: 2. o same: 3 as: 4. o same: #a as: #a. o same: nil as: nil}) equals: #(1 2 3 1 1).
		self assert: ({o either: true or: false. o either: false or: true. o either: false or: false}) equals: #(#yes #yes #no).
		self assert: ({o positive: 3. o positive: -3. o positive: 0} ) equals: #(#pos #neg #neg).
		self assert: o folded equals: #right.
		self assert: ([o either: false or: 3] on: Error do: [:e | #notBoolean]) equals: #notBoolean]
! !

!JitRuntimeTest methodsFor: 'tests: valueWithArguments'!
testValueWithArguments
	"valueWithArguments: of Arrays of 0, 1, 4 and 7 elements, literal and made by braces: the machine code copies the elements into the block's arguments and enters it, no C primitive and no exit to the interpreter (unless --jit-flags deopt makes it). The counters are the VM's, other Processes' included: the quietest of 3 rounds counts."
	| o deltas |
	self define: 'values: n | r b0 b1 b4 b7 | r := 0. b0 := [1]. b1 := [:x | x]. b4 := [:x :y :z :w | x + y + z + w]. b7 := [:x1 :x2 :x3 :x4 :x5 :x6 :x7 | x1 + x2 + x3 + x4 + x5 + x6 + x7]. 1 to: n do: [:i | r := r + (b0 valueWithArguments: #()) + (b1 valueWithArguments: #(2)) + (b4 valueWithArguments: #(1 2 3 4)) + (b7 valueWithArguments: #(1 2 3 4 5 6 7)) + (b0 valueWithArguments: {}) + (b1 valueWithArguments: {i}) + (b4 valueWithArguments: {i. 2. 3. 4}) + (b7 valueWithArguments: {i. 2. 3. 4. 5. 6. 7})]. ^r'.
	o := JitRuntimeTestSubject new.
	self assert: (o values: 10) equals: 945.
	deltas := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		self assert: (o values: 3000) equals: 13738500.
		self statistics - before].
	self stressed ifFalse: [
		self assert: (deltas collect: [:d | d jitPrimitiveCalls]) min < 300.
		self assert: (deltas collect: [:d | d jitExits]) min < 300]
!
testValueWithArgumentsFailures
	"An Array of another size, or not an Array: the primitive fails, as in the interpreter."
	| o |
	self define: 'call: b withArguments: a ^b valueWithArguments: a'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self should: [o call: [:x | x] withArguments: #(1 2)] raise: Error.
		self should: [o call: [:x | x] withArguments: #()] raise: Error.
		self should: [o call: [:x | x] withArguments: (OrderedCollection with: 1)] raise: Error.
		self should: [o call: [:x | x] withArguments: nil] raise: Error.
		self assert: (o call: [:x :y | x - y] withArguments: #(5 3)) equals: 2]
!
testValueWithArgumentsContexts
	"A block entered by valueWithArguments: returns from its home with ^, runs inside ensure: and ensure: inside it, and has its sender's activation as its sender, as with value:."
	| o log |
	self define: 'nlr: x [:y | y > 0 ifTrue: [^#positive]. #other] valueWithArguments: {x}. ^#notReturned'.
	self define: 'ensured: log ^[[:x | log add: x. x * 2] valueWithArguments: #(21)] ensure: [log add: #done]'.
	self define: 'ensuredReturn: log [:x | [^x] ensure: [log add: x]] valueWithArguments: {7}. ^0'.
	self define: 'blockSender ^[:x | thisContext sender] valueWithArguments: #(1)'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o nlr: 1) equals: #positive.
		self assert: (o nlr: -1) equals: #notReturned.
		log := OrderedCollection new.
		self assert: (o ensured: log) equals: 42.
		self assert: log asArray equals: #(21 #done).
		log := OrderedCollection new.
		self assert: (o ensuredReturn: log) equals: 7.
		self assert: log asArray equals: #(7).
		self assert: o blockSender method equals: JitRuntimeTestSubject >> #blockSender.
		self assert: o blockSender receiver == o]
!
testValueWithArgumentsDeepRecursion
	"Recursion through valueWithArguments: deeper than the C stack: the frames become Contexts."
	| before |
	self define: 'depth: n ^n = 0 ifTrue: [0] ifFalse: [([:k | self depth: k] valueWithArguments: {n - 1}) + 1]'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new depth: 200000) equals: 200000.
	self assert: (self statistics - before) frameFlushes > 0
!
testValueWithArgumentsWithProcessSwitches
	"A process wakes up every millisecond while a married frame calls a block through valueWithArguments: of four elements: interrupts at the block's entry switch to it, the results stay right."
	| o result ticks stop |
	self define: 'sum: n | t b | t := 0. b := [:w :x :y :z | w + x + y + z]. thisContext. 1 to: n do: [:i | t := t + (b valueWithArguments: {i. 1. 2. 3})]. ^t'.
	o := JitRuntimeTestSubject new.
	ticks := 0.
	stop := false.
	self fork: [[stop] whileFalse: [(Delay forMilliseconds: 1) wait. ticks := ticks + 1]] at: Processor activePriority + 1.
	"a loaded machine may wake it late: until it has woken up during a run"
	[[result := o sum: 1000000.
	  self assert: result equals: 500006500000.
	  ticks = 0] whileTrue] ensure: [stop := true]
! !
