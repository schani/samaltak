JitRuntimeTest subclass: #JitOptRuntimeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitOptRuntimeTest comment: 'JitRuntimeTest under the optimizing tier (--jit opt, --jit-flags eager: every method optimized at its first count), and what only it does: deoptimizing a failed speculation, and not where nothing was speculated (perform:, doesNotUnderstand:, SmallIntegers beside Floats, BoxedFloat64s), invalidating inlined code while it runs, the deoptimization stress.'!

!JitOptRuntimeTest methodsFor: 'running'!
mode
	^'opt'
!
setUp
	saved := Smalltalk vm jitParameters: {self mode. 'eager'. 0. 5}
!
tearDown
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	super tearDown
! !

!JitOptRuntimeTest methodsFor: 'helpers'!
disassemblyNotes
	^#('interrupt check' 'guard: a SmallInteger' 'frame pc and sp' 'entry: x19')
!
stressed
	"--jit-flags deopt: optimized code deoptimizes every so often anyway."
	^((Smalltalk vm jitParameters at: 2) substrings: ',') includes: 'deopt'
! !

!JitOptRuntimeTest methodsFor: 'tests'!
testParameters
	| now |
	now := Smalltalk vm jitParameters.
	self assert: (now at: 1) equals: self mode.
	self assert: (((now at: 2) substrings: ',') includes: 'eager').
	self assert: Smalltalk vm jitMode equals: self mode asSymbol
!
testDeoptimizationOfASpeculation
	"SmallInteger arithmetic speculated from feedback: a Float deoptimizes to the send, the next compilation takes Floats too."
	| o before |
	self define: 'twice: x ^x + x'.
	self define: 'sumTwice: n | s | s := 0. 1 to: n do: [:i | s := s + (self twice: i)]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o sumTwice: 1000) equals: 1001000.
	before := self statistics.
	self assert: (o twice: 1.5) equals: 3.0.
	self assert: (o twice: 1/2) equals: 1.
	self assert: (o sumTwice: 1000) equals: 1001000.
	self assert: (self statistics - before) optDeoptimizations + (self statistics - before) optMethodsCompiled > 0
!
testActivationsFindOptimizedCodeThroughAnEntryOfBaselineCode
	"An interpreted send whose cache entry was filled when plusOne: had baseline code only: its activations run the optimized code the method gets meanwhile (JitRuntime>>best:). The Float failing a SmallInteger guard in it shows that they do."
	| o before |
	Smalltalk vm jitParameters: #(nil '-eager' 2 1000000).
	self define: 'plusOne: x ^x + 1'.
	self define: 'warm: n | s | s := 0. 1 to: n do: [:i | s := self plusOne: i]. ^s'.
	self define: 'sends: n last: v | s | s := 0. 1 to: n do: [:i | s := self plusOne: (i = n ifTrue: [v] ifFalse: [i])]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o warm: 4) equals: 5.
	"a full GC empties the method caches: the entry of the send in sends:last: is filled from the baseline code"
	Smalltalk vm garbageCollect.
	before := self statistics.
	self assert: (o sends: 5000 last: 1.5) equals: 2.5.
	self assert: (self statistics - before) optMethodsCompiled > 0.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations > 0]
!
testInvalidationWhileRunning
	"A method inlined into running optimized code (a loop's unit, from feedback) is redefined: the code is invalidated, the running activation continues with the new method."
	| before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'answer ^1'.
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | i = n ifTrue: [self class compile: ''answer ^2'']. s := s + self answer]. ^s'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new sum: 20000) equals: 20001.
	self assert: (self statistics - before) optInvalidations > 0
!
testPerformInALoopStaysOptimized
	"perform: and perform:with: of constant selectors are sends of them, perform:withArguments: calls its machine code: a loop of them neither deoptimizes nor sends through the runtime (unless --jit-flags deopt makes it)."
	| o before |
	self define: 'one ^1'.
	self define: 'plus: x ^x + 1'.
	self define: 'performs: n | s a | s := 0. a := Array new: 1. 1 to: n do: [:i | a at: 1 put: i. s := s + (self perform: #one) + (self perform: #plus: with: i) + (i perform: #+ with: 1) + (self perform: #plus: withArguments: a)]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o performs: 100) equals: 15550.
	before := self statistics.
	self assert: (o performs: 10000) equals: 150055000.
	self stressed ifFalse: [
		self assert: (self statistics - before) optDeoptimizations < 1000.
		self assert: (self statistics - before) optRuntimeSends < 50]
!
testAtOfAStringArgumentIsInlined
	"at: of a String argument (push temp, push temp, at:: a superinstruction; baseline code reads Strings without a send, so they leave no feedback): the deoptimization reports the String, the code compiled again reads it inline, without calling the C primitive (unless --jit-flags deopt makes it). The counter is the VM's, other Processes' calls included: the quietest of 3 rounds counts."
	| o s calls |
	self define: 'count: c in: aString | n | n := 0. 1 to: aString size do: [:i | (aString at: i) == c ifTrue: [n := n + 1]]. ^n'.
	o := JitRuntimeTestSubject new.
	s := String new: 1000 withAll: $a.
	3 timesRepeat: [self assert: (o count: $a in: s) equals: 1000].
	calls := (1 to: 3) collect: [:i | | before |
		before := self statistics.
		self assert: (o count: $a in: s) equals: 1000.
		(self statistics - before) jitPrimitiveCalls].
	self stressed ifFalse: [self assert: calls min < 100]
!
testPerformOfAConstantIsInlined
	"perform: of a constant selector is a send of it, inlined into a loop's unit: redefining the method invalidates the code, the loop goes on with the new one."
	| before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'answer ^1'.
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | i = n ifTrue: [self class compile: ''answer ^2'']. s := s + (self perform: #answer)]. ^s'.
	before := self statistics.
	self assert: (JitRuntimeTestSubject new sum: 20000) equals: 20001.
	self assert: (self statistics - before) optInvalidations > 0
!
testNotUnderstoodInALoopStaysOptimized
	"A selector not understood in optimized code: the runtime sends doesNotUnderstand: with its Message, a loop of them does not deoptimize every time (unless --jit-flags deopt makes it)."
	| o before |
	self define: 'doesNotUnderstand: aMessage ^aMessage arguments isEmpty ifTrue: [1] ifFalse: [aMessage arguments first]'.
	self define: 'unknowns: n | s | s := 0. 1 to: n do: [:i | s := s + self unknownUnary + (self unknownWith: i)]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o unknowns: 100) equals: 5150.
	before := self statistics.
	self assert: (o unknowns: 10000) equals: 50015000.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations < 1000]
!
testCallsTakeMachineCode
	"What optimized code does not inline it calls as baseline code does, through no runtime: primitives in machine code (uint32At:put:, uint32At:, identityHash), a method too big to inline, a megamorphic send, a block it did not make."
	| o bytes block mixed before |
	self define: 'big: x | a | a := x. ' , ((1 to: 150) inject: '' into: [:all :i | all , 'a := a. ']) , '^a'.
	self define: 'callsIn: bytes block: b mixed: m n: n | s | s := 0. 1 to: n do: [:i | bytes uint32At: 1 put: i. s := s + (bytes uint32At: 1) + (bytes identityHash bitAnd: 0) + (b value: i) + (self big: 0) + ((m at: i \\ m size + 1) yourself == nil ifTrue: [1] ifFalse: [0])]. ^s'.
	o := JitRuntimeTestSubject new.
	bytes := ByteArray new: 8.
	block := [:x | x * 2].
	mixed := {1. 'a'. #b. 2.5. nil. $c. Object new}.
	self assert: (o callsIn: bytes block: block mixed: mixed n: 700) equals: 736150.
	before := self statistics.
	self assert: (o callsIn: bytes block: block mixed: mixed n: 7000) equals: 73511500.
	self stressed ifFalse: [self assert: (self statistics - before) optRuntimeSends < 50]
!
testClosureTheFrameMadeInALoopUnit
	"A loop's unit (entered at on-stack replacement) inlines the closures its frame made before the loop, guarded: one that stores a temp, one that returns from the method, one the temp stops holding (another closure: the guard fails, deoptimize)."
	| o |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'count: n | k b | k := 0. b := [k := k + 1]. 1 to: n do: [:i | b value]. ^k'.
	self define: 'find: n | b | b := [:x | x = n ifTrue: [^x]]. 1 to: n * 2 do: [:i | b value: i]. ^0'.
	self define: 'other ^[:x | x + 2]'.
	self define: 'switch: n | s b | s := 0. b := [:x | x + 1]. 1 to: n do: [:i | i = (n // 2) ifTrue: [b := self other]. s := b value: s]. ^s'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o count: 30000) equals: 30000.
		self assert: (o find: 30000) equals: 30000.
		self assert: (o switch: 30000) equals: 45001]
!
testClosuresOtherFramesMadeInALoopUnit
	"A loop's unit inlines the closures other frames made that its frame holds (a block passed to a method whose loop evaluates it), guarded by their code; their outer temps and self through the closure: one that stores its home's temp and sends to self, one that a block passed on reaches (a fold), different blocks through the same loop, one with ^ (called, not inlined), one whose home has returned."
	| o adder |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'each: n do: aBlock 1 to: n do: [:i | aBlock value: i]'.
	self define: 'twice: x ^x * 2'.
	self define: 'sumTo: n | s | s := 0. self each: n do: [:i | s := s + (self twice: i)]. ^s'.
	self define: 'fold: n from: init with: aBlock | acc | acc := init. self each: n do: [:i | acc := aBlock value: acc value: i]. ^acc'.
	self define: 'foldSum: n ^self fold: n from: 0 with: [:a :b | a + b]'.
	self define: 'foldMax: n ^self fold: n from: 0 with: [:a :b | a max: b \\ 1000]'.
	self define: 'find: k in: n self each: n do: [:i | i = k ifTrue: [^i]]. ^0'.
	self define: 'adder | total | total := 0. ^[:i | total := total + i. total]'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o sumTo: 30000) equals: 900030000.
		self assert: (o foldSum: 30000) equals: 450015000.
		self assert: (o foldMax: 30000) equals: 999.
		self assert: (o foldSum: 20000) equals: 200010000.
		self assert: (o find: 25000 in: 30000) equals: 25000.
		self assert: (o find: 0 in: 30000) equals: 0.
		adder := o adder.
		o each: 30000 do: adder.
		self assert: (adder value: 0) equals: 450015000]
!
testClosuresSeveralContextsOutInALoopUnit
	"A loop's unit inlines a block passed on through two more blocks (sum:of: through a fold through each:do:): each such block gets a variant of the loop's unit, the second does not deoptimize in the first's; an object that is not a block in its place is sent value:. Each call waits once early in the loop: its frame goes on in baseline code and enters the loop's unit."
	| o before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'pause (Delay forMilliseconds: 1) wait'.
	self define: 'each: n do: aBlock 1 to: n do: [:i | i = 10 ifTrue: [self pause]. aBlock value: i]'.
	self define: 'fold: n from: init with: aBlock | acc | acc := init. self each: n do: [:i | acc := aBlock value: acc value: i]. ^acc'.
	self define: 'sum: n of: aBlock ^self fold: n from: 0 with: [:a :i | a + (aBlock value: i)]'.
	self define: 'squares: n ^self sum: n of: [:i | i * i]'.
	self define: 'cubes: n ^self sum: n of: [:i | i * i * i]'.
	self define: 'value: i ^i + 1'.
	o := JitRuntimeTestSubject new.
	self assert: (o squares: 30000) equals: 9000450005000.
	before := self statistics.
	self assert: (o cubes: 30000) equals: 202513500225000000.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations equals: 0].
	3 timesRepeat: [
		self assert: (o squares: 30000) equals: 9000450005000.
		self assert: (o cubes: 30000) equals: 202513500225000000.
		self assert: (o sum: 30000 of: o) equals: 450045000]
!
testLoopUnitVariantsAreBounded
	"A loop's unit has variants for at most 16 different blocks other frames made; frames holding others enter its plain unit, which inlines none: they do not deoptimize. Each call waits once early in the loop: its frame goes on in baseline code and enters the loop's unit."
	| o before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'pause (Delay forMilliseconds: 1) wait'.
	self define: 'each: n do: aBlock 1 to: n do: [:i | i = 10 ifTrue: [self pause]. aBlock value: i]'.
	1 to: 20 do: [:k | self define: 'sum' , k printString , ': n | s | s := 0. self each: n do: [:i | s := s + (i \\ ' , k printString , ')]. ^s'].
	o := JitRuntimeTestSubject new.
	1 to: 20 do: [:k | | expected |
		expected := 0.
		1 to: 3000 do: [:i | expected := expected + (i \\ k)].
		k = 17 ifTrue: [before := self statistics].
		self assert: (o perform: ('sum' , k printString , ':') asSymbol with: 3000) equals: expected].
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations equals: 0]
!
testMalformedClosuresALoopUnitDoesNotInline
	"Malformed closures a loop's frame (or its block's outer Context) holds and never calls are not inlined, nor their outerContext's method read as one: no outerContext; a method that is nil, an Array, bytes, a CompiledMethod without bytecodes, one with a block's bytecodes but bytes for literals. Each call waits once early in the loop: its frame goes on in baseline code and enters the loop's unit."
	| o junk bad real |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'pause (Delay forMilliseconds: 1) wait'.
	self define: 'each: n do: aBlock junk: j | a b c d e f | a := j at: 1. b := j at: 2. c := j at: 3. d := j at: 4. e := j at: 5. f := j at: 6. 1 to: n do: [:i | i = 10 ifTrue: [self pause]. i = 0 ifTrue: [a value. b value. c value. d value. e value. f value]. aBlock value: i]'.
	self define: 'sumTo: n junk: j | s x | s := 0. x := j at: 3. self each: n do: [:i | s := s + i] junk: j. x yourself. ^s'.
	self define: 'junk ^[3]'.
	o := JitRuntimeTestSubject new.
	real := o junk.
	bad := [:method | | ctx blk |
		ctx := Context basicNew.
		ctx instVarAt: 4 put: method.
		blk := BlockClosure basicNew.
		blk instVarAt: 1 put: ctx; instVarAt: 2 put: (real instVarAt: 2); instVarAt: 3 put: 0.
		blk].
	junk := {
		BlockClosure basicNew.
		bad value: nil.
		bad value: (Array new: 20).
		bad value: (ByteArray new: 64).
		bad value: CompiledMethod basicNew.
		bad value: (CompiledMethod basicNew instVarAt: 3 put: (ByteArray new: 64); instVarAt: 4 put: (((real instVarAt: 1) instVarAt: 4) instVarAt: 4); yourself)}.
	3 timesRepeat: [self assert: (o sumTo: 30000 junk: junk) equals: 450015000]
!
testProcessPrimitivesThatDoNotSwitch
	"signal and wait that switch no process (their C primitives commit their results) return into the optimized code that called them."
	| o s |
	self define: 'signalAndWait: s n: n | k | k := 0. 1 to: n do: [:i | s signal. s wait. k := k + 1]. ^k'.
	o := JitRuntimeTestSubject new.
	s := Semaphore new.
	3 timesRepeat: [self assert: (o signalAndWait: s n: 1000) equals: 1000]
!
testPerformTheRuntimeDoesNotSend
	"The interpreter does what perform: cannot send from optimized code: a selector not understood, perform: again, the wrong number of arguments; a frame without room (recursion through perform:with:)."
	| o |
	self define: 'doesNotUnderstand: aMessage ^aMessage arguments first'.
	self define: 'plus: x ^x + 1'.
	self define: 'unknown: x ^self perform: #noSuchSelector: with: x'.
	self define: 'twice: x ^self perform: #perform:with: with: #plus: with: x'.
	self define: 'wrong ^self perform: #plus:'.
	self define: 'deep: n block: b ^n = 0 ifTrue: [0] ifFalse: [1 + (b perform: #value: with: n - 1)]'.
	self define: 'deep: n | b | b := [:k | self deep: k block: b]. ^self deep: n block: b'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o unknown: 7) equals: 7.
		self assert: (o twice: 1) equals: 2.
		self should: [o wrong] raise: Error.
		self assert: (o deep: 20000) equals: 20000]
!
testPerformedPrimitiveThatMakesFramesContexts
	"A primitive perform: sends from optimized code makes the frames Contexts before it answers (new JIT flags): the Context has its receiver and arguments, the answer replaces them."
	self define: 'modeVia: vm ^(vm perform: #jitParameters: with: #(nil ''eager'' nil nil)) first'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new modeVia: Smalltalk vm) equals: self mode]
!
testIntegerArithmeticBesideFloats
	"Where only other arithmetic of the method saw Floats the optimized code also takes two SmallIntegers: it does not deoptimize and compile again, site after site (unless --jit-flags deopt makes it)."
	| o a before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'mixed: a | s f | s := 0. f := 0. 1 to: a size do: [:i | f := f + (a at: i). s := s + (i \\ 7) - (i // 3)]. ^s + f'.
	o := JitRuntimeTestSubject new.
	a := (1 to: 100000) asArray collect: [:i | i / 2.0].
	before := self statistics.
	self assert: (o mixed: a) equals: 833675000.0.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations < 2]
!
testBoxedFloatsInFloatArithmetic
	"BoxedFloat64s (the infinities, NaN) are decoded as SmallFloat64s are: comparing them does not deoptimize (unless --jit-flags deopt makes it); NaN compares false."
	| o a before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'atMostOne: a | n | n := 0. 1 to: a size do: [:i | (a at: i) <= 1.0 ifTrue: [n := n + 1]]. ^n'.
	o := JitRuntimeTestSubject new.
	a := (1 to: 30000) asArray collect: [:i | i \\ 3 = 0 ifTrue: [Float infinity] ifFalse: [i \\ 5 = 0 ifTrue: [Float nan] ifFalse: [i \\ 7 = 0 ifTrue: [Float negativeInfinity] ifFalse: [i / 30000.0]]]].
	before := self statistics.
	5 timesRepeat: [self assert: (o atMostOne: a) equals: 16000].
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations < 2]
!
testBlockCallWithoutRoomForItsFrame
	"Optimized code calls a block while the stack is full: the frames become Contexts for its frame, the interpreter goes on from there."
	self define: 'deep: n block: b ^n = 0 ifTrue: [0] ifFalse: [1 + (b value: n - 1)]'.
	self define: 'deep: n | b | b := [:k | self deep: k block: b]. ^self deep: n block: b'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new deep: 20000) equals: 20000]
!
testSendToAMarriedContext
	"A Context married to a frame keeps its state in the frame: optimized code does not inline its methods (from feedback), it calls them, and they read the frame."
	| o |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'senderOf: x ^x sender'.
	self define: 'probe ^self senderOf: [:a | a] outerContext'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:i | self assert: (o probe isKindOf: Context)]
!
testNonLocalReturnThroughAMarriedLoop
	"Reading the sender of callerContext's Context, an optimized frame, makes the frames Contexts; each:'s Context goes on married to a frame in its loop's unit, whose frame has more slots than the Context holds. A non-local return through it fills the Context, not the object after it (the block's Context)."
	| o r |
	self define: 'setA: x b: y a := x. b := y'.
	self define: 'each: aBlock 1 to: b do: [:i | aBlock value: (a at: i)]'.
	self define: 'callerContext ^thisContext sender'.
	self define: 'escape | c n | self each: [:x | x = 1 ifTrue: [c := self callerContext. n := c basicSize]. x = 50 ifTrue: [^{c. n}]]. ^nil'.
	o := JitRuntimeTestSubject new setA: (1 to: 100) asArray b: 100; yourself.
	3 timesRepeat: [
		r := o escape.
		self assert: r first basicSize equals: r last]
!
testEntryFromBaselineCodeWithoutRoom
	"Baseline code (thisContext keeps down: from being optimized) calls optimized code with many temps while the stack is nearly full: its entry checks for room as the baseline entry it took over did."
	self define: 'down: n ^n = 0 ifTrue: [thisContext. 0] ifFalse: [(self many: n) + 0]'.
	self define: 'many: n | a b c d e f g h i j k l | a := n. b := a. c := b. d := c. e := d. f := e. g := f. h := g. i := h. j := i. k := j. l := k. ^(self down: l - 1) + 1'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new down: 30000) equals: 30000]
!
testLoopValuesAcrossInterruptChecks
	"Values a loop keeps in registers and only its interrupt check needs in their home slots are stored there when the check calls the runtime: a Process that collects runs there, objects move, the loop goes on with what it held."
	| o done p r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'carry: n | a s | a := Array with: 0. s := 0. 1 to: n do: [:i | s := s + (a at: 1). a := Array with: (a at: 1) + 1 with: s]. ^{s. a first. a last}'.
	o := JitRuntimeTestSubject new.
	done := false.
	p := self fork: [[done] whileFalse: [Smalltalk vm scavenge. (Delay forMilliseconds: 1) wait]] at: Processor activePriority + 1.
	1 to: 5 do: [:k |
		r := o carry: 200000.
		self assert: r equals: {19999900000. 200000. 19999900000}].
	done := true
!
testFloatLoopsKeepTheirSumsOnDoubles
	"A loop's running Float stays on doubles (its phi's twin), across interrupt checks where Processes switch and the collector runs; a SmallInteger sum beside it stays one; a loop unit entered with a SmallInteger, a Fraction or nil where it was compiled with a Float answers what the interpreter answers; a loop that sends keeps its Float on doubles too; more running Floats than d registers spill to raw slots."
	| o done many |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'fsum: n | r | r := 0.0. 1 to: n do: [:i | r := r + (i * 0.5)]. ^r'.
	self define: 'fsumFrom: r0 n: n | r | r := r0. 1 to: n do: [:i | r := r + i]. ^r'.
	self define: 'big: x | a | a := x. ' , ((1 to: 150) inject: '' into: [:all :i | all , 'a := a. ']) , '^a'.
	self define: 'fsumSends: n | r | r := 0.0. 1 to: n do: [:i | r := r + (self big: i * 0.5)]. ^r'.
	many := String new writeStream.
	many nextPutAll: 'many: n | '.
	1 to: 20 do: [:k | many nextPutAll: 'a'; print: k; space].
	many nextPutAll: '| '.
	1 to: 20 do: [:k | many nextPutAll: 'a'; print: k; nextPutAll: ' := '; print: k; nextPutAll: '.0. '].
	many nextPutAll: '1 to: n do: [:i | '.
	1 to: 20 do: [:k | many nextPutAll: 'a'; print: k; nextPutAll: ' := a'; print: k; nextPutAll: ' + 0.5. '].
	many nextPutAll: ']. ^'.
	(1 to: 20) do: [:k | many nextPutAll: 'a'; print: k] separatedBy: [many nextPutAll: ' + '].
	self define: many contents.
	o := JitRuntimeTestSubject new.
	done := false.
	self fork: [[done] whileFalse: [Smalltalk vm scavenge. (Delay forMilliseconds: 1) wait]] at: Processor activePriority + 1.
	1 to: 5 do: [:k | self assert: (o fsum: 200000) equals: 10000050000.0].
	done := true.
	self assert: (o fsumFrom: 0.5 n: 100000) equals: 5000050000.5.
	self assert: (o fsumFrom: 0.5 n: 100000) equals: 5000050000.5.
	self assert: (o fsumFrom: 1 n: 100000) equals: 5000050001.
	self assert: (o fsumFrom: 1/2 n: 100000) equals: 10000100001 / 2.
	self should: [o fsumFrom: nil n: 100000] raise: MessageNotUnderstood.
	self assert: (o fsumFrom: 0.5 n: 100000) equals: 5000050000.5.
	self assert: (o fsumSends: 100000) equals: 2500025000.0.
	self assert: (o many: 100000) equals: 1000210.0
!
testDoublesInFrameStatesOfGuards
	"A Float that only frame states name stays a double (its box goes): a guard that fails makes it a SmallFloat64, or a BoxedFloat64 (an infinity, a NaN, one too small or too large), as the interpreter has it; in a d register, or in its raw slot where more doubles live than there are registers."
	| o many huge r before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'prod: x and: y then: o | d | d := x * y. ^(o size * 0) + d'.
	many := String new writeStream.
	many nextPutAll: 'twenty: x then: o | '.
	1 to: 20 do: [:k | many nextPutAll: 'a'; print: k; space].
	many nextPutAll: '| '.
	1 to: 20 do: [:k | many nextPutAll: 'a'; print: k; nextPutAll: ' := x * '; print: k; nextPutAll: '.0. '].
	many nextPutAll: '^(o size * 0) + '.
	(1 to: 20) do: [:k | many nextPutAll: 'a'; print: k] separatedBy: [many nextPutAll: ' + '].
	self define: many contents.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k |
		self assert: (o prod: 1.5 and: 2.0 then: #(1 2 3)) equals: 3.0.
		self assert: (o twenty: 0.5 then: #(1 2 3)) equals: 105.0].
	huge := (2 raisedTo: 1000) asFloat.
	before := self statistics.
	r := o prod: 1.5 and: 2.0 then: 'abcd'.
	self assert: r equals: 3.0.
	self assert: r class equals: SmallFloat64.
	r := o prod: 1.0e300 and: 1.0e10 then: 'abcd'.
	self assert: r equals: Float infinity.
	self assert: r class equals: BoxedFloat64.
	r := o prod: 1.0e-20 and: 1.0e-20 then: 'abcd'.
	self assert: r equals: 1.0e-20 * 1.0e-20.
	self assert: r class equals: BoxedFloat64.
	r := o prod: Float nan and: 1.0 then: 'abcd'.
	self assert: r isNaN.
	self assert: r class equals: BoxedFloat64.
	r := o twenty: huge then: 'abcd'.
	self assert: r equals: huge * 210.
	self assert: r class equals: BoxedFloat64.
	self assert: (o twenty: 0.5 then: 'abcd') equals: 105.0.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations > 0].
	"where no guard fails: the result's box is out of range"
	self assert: (o prod: 1.0e300 and: 1.0e10 then: #(1 2)) equals: Float infinity.
	self assert: (o twenty: huge then: #(1 2)) equals: huge * 210.
	self assert: (o twenty: Float nan then: #(1 2)) isNaN
!
testDoublesInInlinedActivationsStates
	"A guard of an inlined method fails: the caller's activation, rebuilt with it, has its Float, which only frame states named, as the interpreter has it."
	| o r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'sizeOf: o ^o size'.
	self define: 'outer: x and: y with: o | d | d := x * y. ^((self sizeOf: o) * 0) + d'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k | self assert: (o outer: 1.5 and: 2.0 with: #(1 2 3)) equals: 3.0].
	r := o outer: 1.5 and: 2.0 with: 'abc'.
	self assert: r equals: 3.0.
	self assert: r class equals: SmallFloat64.
	r := o outer: 1.0e300 and: 1.0e300 with: 'abc'.
	self assert: r equals: Float infinity.
	self assert: r class equals: BoxedFloat64.
	r := o outer: 1.0e200 and: 2.0 with: 'abc'.
	self assert: r equals: 2.0e200.
	self assert: r class equals: BoxedFloat64
!
testDoublesAcrossSendsThatCollect
	"Floats live across a send are doubles in raw slots of the frame, which neither scavenges nor full collections read; the send's callee collects."
	| o r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'collect: k k = 1 ifTrue: [Smalltalk vm garbageCollect]. k = 2 ifTrue: [Smalltalk vm scavenge]. ^k * 0'.
	self define: 'keep: x and: y collect: k | d e | d := x * y. e := x + y. ^(self collect: k) + d + e'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k | self assert: (o keep: 1.5 and: 2.0 collect: k \\ 100) equals: 6.5].
	1 to: 3 do: [:k |
		self assert: (o keep: 1.5 and: 2.0 collect: 1) equals: 6.5.
		self assert: (o keep: 1.5 and: 2.0 collect: 2) equals: 6.5.
		r := o keep: 1.0e300 and: 1.0e10 collect: 1.
		self assert: r equals: Float infinity.
		self assert: r class equals: BoxedFloat64.
		r := o keep: 1.0e100 and: 1.0e100 collect: 2.
		self assert: r equals: (1.0e100 * 1.0e100) + (1.0e100 + 1.0e100).
		self assert: r class equals: BoxedFloat64]
!
testDoublesOfFramesMadeContexts
	"Reading thisContext's sender makes the frames Contexts (materializeAll) while the optimized caller waits in a send with a Float in a raw slot: its Context has it as a SmallFloat64 or a BoxedFloat64."
	| o r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'senderNow: k thisContext sender. ^k'.
	self define: 'flush: x and: y | d | d := x * y. ^(self senderNow: 0) + d'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k | self assert: (o flush: 1.5 and: 2.0) equals: 3.0].
	r := o flush: 1.5 and: 2.0.
	self assert: r equals: 3.0.
	self assert: r class equals: SmallFloat64.
	r := o flush: 1.0e300 and: 1.0e10.
	self assert: r equals: Float infinity.
	self assert: r class equals: BoxedFloat64.
	r := o flush: 1.0e-200 and: 1.0e100.
	self assert: r equals: 1.0e-200 * 1.0e100.
	self assert: r class equals: BoxedFloat64
!
testDoublesAcrossInterruptChecksAndSends
	"A loop's running Float stays a double across the loop's sends and interrupt checks, in its raw slot there: a Process that scavenges and collects runs at the interrupt checks, switching to it makes the frames Contexts, the loop goes on with its sum. One that overflows to an infinity answers it."
	| o done k |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'big: x | a | a := x. ' , ((1 to: 150) inject: '' into: [:all :i | all , 'a := a. ']) , '^a'.
	self define: 'sumSends: n by: p | r | r := 0.0. 1 to: n do: [:i | r := r + (i * p) + ((self big: i) * 0)]. ^r'.
	o := JitRuntimeTestSubject new.
	done := false.
	k := 0.
	self fork: [[done] whileFalse: [
		k := k + 1.
		k \\ 10 = 0 ifTrue: [Smalltalk vm garbageCollect] ifFalse: [Smalltalk vm scavenge].
		(Delay forMilliseconds: 1) wait]] at: Processor activePriority + 1.
	1 to: 5 do: [:i | self assert: (o sumSends: 100000 by: 0.5) equals: 2500025000.0].
	done := true.
	self assert: (o sumSends: 20000 by: 1.0e300) equals: Float infinity
!
testDoublePhisThatSwap
	"Loop phis that take each other's values (a cycle of moves at the back edge), their running sum on doubles, and the same through Float arithmetic (twins on doubles)."
	| o |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'swap: n | a b t s | a := 1.5. b := 2.5. s := 0.0. 1 to: n do: [:i | s := s + a. t := a. a := b. b := t]. ^s'.
	self define: 'swapScaled: n | a b t s | a := 1.5. b := 2.5. s := 0.0. 1 to: n do: [:i | s := s + a. t := a. a := b * 1.0. b := t * 1.0]. ^s'.
	o := JitRuntimeTestSubject new.
	3 timesRepeat: [
		self assert: (o swap: 100000) equals: 200000.0.
		self assert: (o swapScaled: 100000) equals: 200000.0.
		self assert: (o swapScaled: 100001) equals: 200001.5]
!
testFloatSumsBoxedWhereTheirLoopIsDone
	"A loop's running Float that only the loop's arithmetic reads has no box in the loop (frame states name its double): its sum leaves SmallFloat64's range and comes back without deoptimizing. Returned, stored into an Array's element or an instance variable after the loop it is boxed there: out of SmallFloat64's range that deoptimizes, the interpreter makes the BoxedFloat64."
	| o arr big before deopts r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'sum: n by: x | r | r := 0.0. 1 to: n do: [:i | r := r + x]. ^r'.
	self define: 'upDown: n by: x | r | r := 0.0. 1 to: n do: [:i | r := r + x]. 1 to: n do: [:i | r := r - x]. ^r'.
	self define: 'sumInto: arr n: n by: x | r | r := 0.0. 1 to: n do: [:i | r := r + x]. arr at: 2 put: r. ^arr'.
	self define: 'sumIntoA: n by: x | r | r := 0.0. 1 to: n do: [:i | r := r + x]. a := r. ^a'.
	o := JitRuntimeTestSubject new.
	arr := Array new: 3.
	1 to: 3000 do: [:k |
		self assert: (o sum: 10 by: 0.5) equals: 5.0.
		self assert: (o upDown: 10 by: 0.5) equals: 0.0.
		self assert: ((o sumInto: arr n: 10 by: 0.5) at: 2) equals: 5.0.
		self assert: (o sumIntoA: 10 by: 0.5) equals: 5.0].
	big := (2 raisedTo: 127) asFloat.
	before := self statistics.
	r := o upDown: 10 by: big.
	deopts := (self statistics - before) optDeoptimizations.
	self assert: r equals: 0.0.
	self assert: r class equals: SmallFloat64.
	self stressed ifFalse: [self assert: deopts equals: 0].
	r := o sum: 10 by: big.
	self assert: r equals: big * 10.
	self assert: r class equals: BoxedFloat64.
	r := (o sumInto: arr n: 10 by: big) at: 2.
	self assert: r equals: big * 10.
	self assert: r class equals: BoxedFloat64.
	r := o sumIntoA: 10 by: big.
	self assert: r equals: big * 10.
	self assert: r class equals: BoxedFloat64.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations >= 3].
	self assert: (o sum: 10 by: 0.5) equals: 5.0.
	self assert: ((o sumInto: arr n: 10 by: 0.5) at: 2) equals: 5.0.
	self assert: (o sumIntoA: 10 by: 0.5) equals: 5.0
!
testFloatPhisOfNestedLoopsMergesAndSwaps
	"Without boxes in their loops: a running Float carried across two nested loops, one that adds what a conditional made (a phi of Floats where its branches meet), two Floats that swap every turn; out of SmallFloat64's range they are boxed (deoptimizing) where they are returned."
	| o big r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'nested: n by: x | r | r := 0.0. 1 to: n do: [:i | 1 to: n do: [:j | r := r + x]]. ^r'.
	self define: 'merge: n by: x | r | r := 0.0. 1 to: n do: [:i | r := r + (i odd ifTrue: [x * 2.0] ifFalse: [x + 1.0])]. ^r'.
	self define: 'swap: x and: y n: n | a b t | a := x * 1.0. b := y * 1.0. t := 0.0. 1 to: n do: [:i | t := a. a := b. b := t]. ^a'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k |
		self assert: (o nested: 4 by: 0.5) equals: 8.0.
		self assert: (o merge: 4 by: 0.5) equals: 5.0.
		self assert: (o swap: 1.5 and: 2.5 n: 3) equals: 2.5.
		self assert: (o swap: 1.5 and: 2.5 n: 4) equals: 1.5].
	big := (2 raisedTo: 127) asFloat.
	r := o nested: 4 by: big.
	self assert: r equals: big * 16.
	self assert: r class equals: BoxedFloat64.
	r := o merge: 4 by: big.
	self assert: r equals: big * 6.
	self assert: r class equals: BoxedFloat64.
	r := o swap: big * 2.0 and: 2.5 n: 4.
	self assert: r equals: big * 2.0.
	self assert: r class equals: BoxedFloat64.
	r := o swap: big * 2.0 and: 2.5 n: 3.
	self assert: r equals: 2.5.
	self assert: r class equals: SmallFloat64.
	self assert: (o nested: 4 by: 0.5) equals: 8.0.
	self assert: (o merge: 4 by: 0.5) equals: 5.0
!
testFloatSumOnlyOnDoublesWhereAGuardFails
	"A guard fails in a loop whose running Float is only a double there (its box went): the interpreter goes on with it as a SmallFloat64, or a BoxedFloat64 out of that range, on the loop's first turn as on a later one."
	| o halves big arr r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'sumFirst: arr | r | r := 0.0. 1 to: arr size do: [:i | r := r + (arr at: i)]. ^r'.
	self define: 'sumLater: arr | r | r := 0.0. 1 to: arr size do: [:i | r := r + (arr at: i)]. ^r'.
	self define: 'sumBig: arr | r | r := 0.0. 1 to: arr size do: [:i | r := r + (arr at: i)]. ^r'.
	o := JitRuntimeTestSubject new.
	halves := (1 to: 10) asArray collect: [:i | i * 0.5].
	1 to: 3000 do: [:k |
		self assert: (o sumFirst: halves) equals: 27.5.
		self assert: (o sumLater: halves) equals: 27.5.
		self assert: (o sumBig: halves) equals: 27.5].
	arr := halves copy.
	arr at: 1 put: 1/2.
	r := o sumFirst: arr.
	self assert: r equals: 27.5.
	self assert: r class equals: SmallFloat64.
	arr := halves copy.
	arr at: 7 put: 7/2.
	r := o sumLater: arr.
	self assert: r equals: 27.5.
	self assert: r class equals: SmallFloat64.
	big := (2 raisedTo: 127) asFloat.
	arr := Array new: 10 withAll: big.
	arr at: 7 put: 1/2.
	r := o sumBig: arr.
	self assert: r equals: (arr inject: 0.0 into: [:sum :e | sum + e]).
	self assert: r class equals: BoxedFloat64
!
testFloatSumSentInItsLoopKeepsItsBox
	"A running Float that the loop sends keeps its box in the loop: out of SmallFloat64's range it deoptimizes there, as before."
	| o big before r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'big: x | a | a := x. ' , ((1 to: 150) inject: '' into: [:all :i | all , 'a := a. ']) , '^a'.
	self define: 'sumSent: n by: x | r | r := 0.0. 1 to: n do: [:i | self big: r. r := r + x]. ^r'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k | self assert: (o sumSent: 10 by: 0.5) equals: 5.0].
	big := (2 raisedTo: 127) asFloat.
	before := self statistics.
	r := o sumSent: 10 by: big.
	self assert: r equals: big * 10.
	self assert: r class equals: BoxedFloat64.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations > 0].
	self assert: (o sumSent: 10 by: 0.5) equals: 5.0
!
testLoopUnitEnteredWithAFloatOrNot
	"A loop's unit compiled where its running Float was a SmallFloat64 guards the frame's slot where it is entered: a SmallFloat64 passes (no deoptimization), a SmallInteger (osrA:) or a BoxedFloat64 (osrB:) fails it and the interpreter goes on from the loop's head, as after a Fraction in the unit compiled again. The method's own unit is never compiled (a literal Array is not), so every call enters the loop's unit."
	| o before deopts r |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'osrA: r0 n: n | r | r := {r0} first. 1 to: n do: [:i | r := r + i]. ^r'.
	self define: 'osrB: r0 n: n | r | r := {r0} first. 1 to: n do: [:i | r := r + i]. ^r'.
	o := JitRuntimeTestSubject new.
	self assert: (o osrA: 0.5 n: 100000) equals: 5000050000.5.
	self assert: (o osrB: 0.5 n: 100000) equals: 5000050000.5.
	before := self statistics.
	r := (o osrA: 0.5 n: 100000) + (o osrB: 0.5 n: 100000).
	deopts := (self statistics - before) optDeoptimizations.
	self assert: r equals: 10000100001.0.
	self stressed ifFalse: [self assert: deopts equals: 0].
	r := o osrA: 1 n: 100000.
	self assert: r equals: 5000050001.
	self assert: r class equals: SmallInteger.
	r := o osrB: 1.0e300 n: 100000.
	self assert: r equals: 1.0e300.
	self assert: r class equals: BoxedFloat64.
	self assert: (o osrA: 1/2 n: 100000) equals: 10000100001 / 2.
	self assert: (o osrA: 0.5 n: 100000) equals: 5000050000.5.
	self assert: (o osrB: 0.5 n: 100000) equals: 5000050000.5
!
testDeoptimizationStress
	"--jit-flags deopt: optimized code deoptimizes every so often at its guards and safepoints; the compiler's tests still pass."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. 'opt'. '--jit-threshold'. '0'. '--jit-flags'. 'eager,deopt'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := TestCase runNamed: #(''Tests-Compiler''). {r failures size + r errors size. r runCount > 0. Smalltalk vm statistics optDeoptimizations > 0}'}).
	self assert: (run output trimBoth endsWith: '#(0 true true)')
!
testReceiverStaysInX0
	"An optimized method takes its receiver from x0, where calls bring it: its first instruction does not load it from its slot (on the path of every call)."
	| o listing lines i first |
	self define: 'setA: x b: y a := x. b := y'.
	self define: 'sumAB ^a + b'.
	o := JitRuntimeTestSubject new setA: 3 b: 4.
	self assert: o sumAB equals: 7.
	listing := (JitRuntimeTestSubject >> #sumAB) machineCodeFor: #opt.
	self assert: (listing includesSubstring: 'x0 := the receiver, as a call brings it').
	lines := listing lines.
	i := (1 to: lines size) detect: [:k | (lines at: k) beginsWith: 'pc 0:'].
	first := OrderedCollection new.
	[(i := i + 1) <= lines size and: [((lines at: i) beginsWith: 'pc ') not]] whileTrue: [first add: (lines at: i)].
	self assert: (first anySatisfy: [:line | line includesSubstring: (self isX64 ifTrue: ['rdi'] ifFalse: ['x0'])]).
	self deny: (first anySatisfy: [:line | line includesSubstring: (self isX64 ifTrue: ['[rbx-0x8]'] ifFalse: ['[x20, #-0x8]'])])
!
testDisassemblyShowsInlinedActivations
	| listing |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'inc: x ^x + 1'.
	self define: 'sumInc: n | s | s := 0. 1 to: n do: [:i | s := s + (self inc: i)]. ^s'.
	self assert: (JitRuntimeTestSubject new sumInc: 20000) equals: 200030000.
	listing := (JitRuntimeTestSubject >> #sumInc:) machineCodeFor: #opt.
	self assert: (listing beginsWith: 'JitRuntimeTestSubject>>sumInc:  opt').
	self assert: (listing includesSubstring: 'inlined activation 1')
!
testGuardsOfValuesFromBeforeALoopLeaveIt
	"A guard every turn of a loop passes, of a value from before the loop, runs once before it, in the loop's own unit too, out of nested loops and inlined loops. A value of another kind fails it there, also before a loop that would not have turned at all: the interpreter goes on from the loop's head, and the guard stays in the loop from then on."
	| o m before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'times: n sizeOf: x | s | s := 0. 1 to: n do: [:i | s := s + x size]. ^s'.
	self define: 'times: n add: x | s | s := 0. 1 to: n do: [:i | s := s + x]. ^s'.
	self define: 'times: n nested: x | s | s := 0. 1 to: n do: [:i | 1 to: n do: [:j | s := s + x size]]. ^s'.
	self define: 'sumOver: a sizeOf: x | s | s := 0. a do: [:e | s := s + x size]. ^s'.
	self define: 'while: n sizeOf: x | s i | s := 0. i := 0. [i < n] whileTrue: [s := s + x size. i := i + 1]. ^s'.
	o := JitRuntimeTestSubject new.
	self assert: (o times: 20000 sizeOf: #(1 2 3)) equals: 60000.
	1 to: 3000 do: [:k |
		self assert: (o times: 10 sizeOf: #(1 2 3)) equals: 30.
		self assert: (o times: 10 add: 2) equals: 20.
		self assert: (o times: 10 nested: #(1 2 3)) equals: 300.
		self assert: (o sumOver: #(1 2 3 4) sizeOf: #(1 2 3)) equals: 12.
		self assert: (o while: 10 sizeOf: #(1 2 3)) equals: 30].
	m := JitRuntimeTestSubject >> #times:sizeOf:.
	self assert: ((m machineCodeFor: #opt) includesSubstring: 'guard: its class, once before the loop').
	self assert: (((JitRuntimeTestSubject >> #times:add:) machineCodeFor: #opt) includesSubstring: 'guard: a SmallInteger, once before the loop').
	before := self statistics.
	self assert: (o times: 10 sizeOf: 'abcd') equals: 40.
	self assert: (o while: 0 sizeOf: 'abcd') equals: 0.
	self assert: (o times: 10 add: 1.5) equals: 15.0.
	self assert: (o times: 10 nested: 'abcd') equals: 400.
	self assert: (o sumOver: #(1 2 3 4) sizeOf: 'abcd') equals: 16.
	self stressed ifFalse: [
		self assert: (self statistics - before) optDeoptimizations >= 5.
		self deny: ((m machineCodeFor: #opt) includesSubstring: 'guard: its class, once before the loop')].
	self assert: (o times: 10 sizeOf: #(1 2)) equals: 20
!
testSmallIntegerDivisionInline
	"SmallInteger / inline while its quotients are exact, also beside Float arithmetic; a remainder deoptimizes to the send (a Fraction), as does a zero divisor (ZeroDivide)."
	| o before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'sumOver: n by: d | s | s := 0. 1 to: n do: [:i | s := s + (i * d / d)]. ^s'.
	self define: 'quotients: n by: d | s | s := 0. 1 to: n do: [:i | s := s + (i / d)]. ^s'.
	self define: 'harmonic: n | s | s := 0.0. 1 to: n do: [:i | s := s + (1.0 / (i * 2 / 2))]. ^s'.
	o := JitRuntimeTestSubject new.
	1 to: 3000 do: [:k |
		self assert: (o sumOver: 10 by: 3) equals: 55.
		self assert: (o quotients: 10 by: 1) equals: 55.
		self assert: (o harmonic: 10) equals: ((1 to: 10) inject: 0.0 into: [:sum :i | sum + (1.0 / i)])].
	self assert: (((JitRuntimeTestSubject >> #sumOver:by:) machineCodeFor: #opt) includesSubstring: 'exact: a remainder deoptimizes').
	self assert: (((JitRuntimeTestSubject >> #harmonic:) machineCodeFor: #opt) includesSubstring: 'exact: a remainder deoptimizes').
	before := self statistics.
	self assert: (o quotients: 10 by: 2) equals: 55 / 2.
	self should: [o quotients: 3 by: 0] raise: ZeroDivide.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations > 0].
	self assert: (o quotients: 10 by: 4) equals: 55 / 4
!
testDisassemblyLeavesFeedback
	"A listing of code compiled without notes compiles a copy: the Float the method's baseline code saw stays feedback, its optimized code takes Floats. Feedback bytes are shared by hash and compiling another method may clear this one's, so a new method gets 3 tries; a listing that clears it fails all of them."
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self assert: ((1 to: 3) anySatisfy: [:i | self listingLeavesFeedback])
!
listingLeavesFeedback
	| m |
	self define: 'add: x to: y ^x + y'.
	m := JitRuntimeTestSubject >> #add:to:.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new add: 1.5 to: 2.5) equals: 4.0].
	self assert: ((m machineCodeFor: #opt) includesSubstring: self floatAdd).
	self assert: ((m machineCodeFor: #baseline) beginsWith: 'JitRuntimeTestSubject>>add:to:  baseline').
	^(m machineCodeFor: #opt) includesSubstring: self floatAdd
!
floatAdd
	"The mnemonic of a double add in a listing."
	^self isX64 ifTrue: ['addsd'] ifFalse: ['fadd']
!
testCharacterValueGuardsItsArgumentFirst
	"Character value: inlined (feedback) for a value not known to be a SmallInteger: the guard on it comes before the conversion, which reads the guard's result."
	| listing g |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'char: n ^Character value: n'.
	3 timesRepeat: [self assert: (JitRuntimeTestSubject new char: 65) equals: $A].
	listing := (JitRuntimeTestSubject >> #char:) machineCodeFor: #opt.
	g := listing indexOfSubCollection: 'guard: a SmallInteger'.
	self assert: (g > 0 and: [g < (listing indexOfSubCollection: 'the Character of a SmallInteger')])
!
testClosureMadeBeforeALoopStoresATemp
	"The closure, inlined into the loop, stores a temp of the loop's activation: the loop does not keep the temp's value on entry."
	self define: 'storeInLoop | n b | n := 0. b := [n := n + 1]. 1 to: 3 do: [:i | b value]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInLoop equals: 3]
!
testClosureStoresATempInNestedLoops
	self define: 'storeInNestedLoops | n b | n := 0. b := [n := n + 1]. 1 to: 3 do: [:i | 1 to: 4 do: [:j | b value]]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInNestedLoops equals: 12]
!
testClosureStoresATempInAWhileLoop
	self define: 'storeInWhileLoop | n k b | n := 0. k := 0. b := [n := n + 2]. [k < 5] whileTrue: [b value. k := k + 1]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInWhileLoop equals: 10]
!
testClosureAndLoopStoreATemp
	self define: 'storeInLoopAndClosure | n b | n := 0. b := [n := n * 2]. 1 to: 3 do: [:i | n := n + i. b value]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInLoopAndClosure equals: 22]
!
testClosureMadeInALoopStoresATemp
	self define: 'storeInLoopBlock | n | n := 0. 1 to: 3 do: [:i | [n := n + i] value]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInLoopBlock equals: 6]
!
testClosureCalledConditionallyInALoop
	self define: 'storeSometimes | n b | n := 0. b := [n := n + 1]. 1 to: 10 do: [:i | (i bitAnd: 1) = 1 ifTrue: [b value]]. ^n'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeSometimes equals: 5]
!
testClosureStoresATempOfAnInlinedBlock
	"The loop and the closure belong to a block inlined into the method."
	self define: 'storeInBlockLoop ^[:k | | n b | n := 0. b := [n := n + 1]. 1 to: k do: [:i | b value]. n] value: 3'.
	3 timesRepeat: [self assert: JitRuntimeTestSubject new storeInBlockLoop equals: 3]
!
testClosurePassedToAMethodInALoop
	"The closure reaches the loop through an inlined method (from feedback: optimized after 1000 counts)."
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'call: aBlock ^aBlock value'.
	self define: 'storeThroughCall | n b | n := 0. b := [n := n + 1]. 1 to: 3 do: [:i | self call: b]. ^n'.
	3000 timesRepeat: [self assert: JitRuntimeTestSubject new storeThroughCall equals: 3]
!
testCountSharedWithAFailedMethod
	"Methods count toward optimization in slots by identity hash (modulo 65536). One the optimizer cannot compile ({} is not compiled) leaves its slot counting: a method sharing it is still optimized."
	| failing plain o before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'failing: x ^{x}'.
	self define: 'plain: x ^x + 1'.
	self define: 'plain: x times: n 1 to: n do: [:i | self plain: x]. ^{x}'.
	failing := JitRuntimeTestSubject >> #failing:.
	plain := JitRuntimeTestSubject >> #plain:.
	"one slot, two hashes: failures are remembered by hash"
	[(plain identityHash bitAnd: 16rFFFF) = (failing identityHash bitAnd: 16rFFFF) and: [plain identityHash ~= failing identityHash]] whileFalse: [plain := plain shallowCopy].
	JitRuntimeTestSubject addSelectorSilently: #plain: withMethod: plain.
	o := JitRuntimeTestSubject new.
	"plain: counts in the slot before failing: fails (installing its code later would start the count over)"
	o plain: 0.
	before := self statistics.
	3000 timesRepeat: [o failing: 0].
	self assert: (self statistics - before) optCompileFailures > 0.
	"plain:times: fails too ({}): what is compiled is plain:"
	before := self statistics.
	o plain: 0 times: 3000.
	self assert: (self statistics - before) optMethodsCompiled > 0
!
testDeoptimizationWithDeadTemps
	"Frame states name nil for the temps that no bytecode reads again before storing them: guards that fail where such temps are dead (straight code, one branch of two, a loop that carries a temp around its back edge, one that stores its temps first on every turn) rebuild frames that answer what the interpreter answers."
	| o good bad sizes before |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'straight: x with: o | t u | t := x + 1. u := t * 2. ^u + o size'.
	self define: 'branch: x flag: f with: o | t s | t := x + 1. f ifTrue: [s := o size + t] ifFalse: [s := o size]. ^s'.
	self define: 'carried: arr | prev s | prev := 0. s := 0. 1 to: arr size do: [:i | s := s + (arr at: i) size + prev. prev := i]. ^s'.
	self define: 'fresh: arr | t u s | s := 0. 1 to: arr size do: [:i | t := i * 2. u := i. s := s + u + (arr at: i) size + t]. ^s'.
	o := JitRuntimeTestSubject new.
	good := (1 to: 100) collect: [:i | Array new: i \\ 3].
	bad := good copy.
	bad at: 70 put: 'abcd'.
	sizes := [:arr | arr inject: 0 into: [:sum :e | sum + e size]].
	1 to: 3000 do: [:k |
		self assert: (o straight: k with: #(1 2 3)) equals: k + 1 * 2 + 3.
		self assert: (o branch: k flag: k \\ 2 = 1 with: #(1 2 3)) equals: (k \\ 2 = 1 ifTrue: [k + 4] ifFalse: [3]).
		self assert: (o carried: good) equals: (sizes value: good) + 4950.
		self assert: (o fresh: good) equals: (sizes value: good) + 15150].
	before := self statistics.
	self assert: (o straight: 5 with: 'abcd') equals: 16.
	self assert: (o branch: 5 flag: true with: 'abcd') equals: 10.
	self assert: (o branch: 5 flag: false with: 'abcd') equals: 4.
	self assert: (o carried: bad) equals: (sizes value: bad) + 4950.
	self assert: (o fresh: bad) equals: (sizes value: bad) + 15150.
	self stressed ifFalse: [self assert: (self statistics - before) optDeoptimizations > 0]
!
testNestedFloatLoopsWithDeadTemps
	"Nested loops whose turns store Float temps before they read them (dead at the loop heads: no phis there): a guard that fails inside rebuilds the frame, the sum is exact."
	| o good bad expected |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'nested: n with: arr | s d x | s := 0.0. 1 to: n do: [:i | 1 to: n do: [:j | d := i * 0.5. x := d * j. s := s + x + (arr at: j) size]]. ^s'.
	o := JitRuntimeTestSubject new.
	good := (1 to: 30) collect: [:i | Array new: i \\ 4].
	bad := good copy.
	bad at: 20 put: 'abcde'.
	expected := [:arr | | s | s := 0.0. 1 to: 30 do: [:i | 1 to: 30 do: [:j | s := s + (i * 0.5 * j) + (arr at: j) size]]. s].
	1 to: 300 do: [:k | self assert: (o nested: 30 with: good) equals: (expected value: good)].
	self assert: (o nested: 30 with: bad) equals: (expected value: bad).
	self assert: (o nested: 30 with: good) equals: (expected value: good)
!
testBlocksReadTempsTheirHomeDoesNot
	"Temps that only blocks read or store are named in every frame state of their home: a guard that fails in an inlined block rebuilds the frames and makes the closure, which goes on with them; the same in a loop's unit that inlines a closure its frame made."
	| o good bad expected |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'inlined: arr | k t blk | k := 0. t := 5. blk := [:x | k := k + x size + t]. arr do: [:e | blk value: e]. ^k'.
	self define: 'real: arr | k t blk | k := 0. t := 5. blk := [:x | k := k + x size + t]. 1 to: arr size do: [:i | blk value: (arr at: i)]. ^k'.
	o := JitRuntimeTestSubject new.
	good := (1 to: 30000) collect: [:i | Array new: i \\ 3].
	bad := good copy.
	bad at: 25000 put: 'abcd'.
	expected := [:arr | (arr inject: 0 into: [:sum :e | sum + e size]) + (5 * arr size)].
	1 to: 3000 do: [:k | self assert: (o inlined: (good copyFrom: 1 to: 10)) equals: (expected value: (good copyFrom: 1 to: 10))].
	self assert: (o inlined: (bad copyFrom: 24991 to: 25000)) equals: (expected value: (bad copyFrom: 24991 to: 25000)).
	3 timesRepeat: [
		self assert: (o real: good) equals: (expected value: good).
		self assert: (o real: bad) equals: (expected value: bad)]
!
testFramesMadeContextsHaveNilInDeadTemps
	"Reading thisContext's sender makes the frames Contexts while the optimized caller waits in a send: its live temps are what it holds, its dead ones nil (with --jit-flags -live it keeps every temp); a method with a primitive keeps all of its temps."
	| o r live |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	live := Smalltalk vm jitFlags includes: 'live'.
	self define: 'senderTemp: k ^thisContext sender tempAt: k'.
	self define: 'temps: x | d l | d := x * 3. l := d + 1. ^Array with: (self senderTemp: 2) with: (self senderTemp: 3) with: l'.
	self define: 'primTemps: x <primitive: ''intAdd'' error: ec> | d l | d := x * 3. l := d + 1. ^Array with: (self senderTemp: 3) with: (self senderTemp: 4) with: l'.
	o := JitRuntimeTestSubject new.
	1 to: 1500 do: [:k |
		self assert: (o temps: k) last equals: k * 3 + 1.
		self assert: (o primTemps: k) last equals: k * 3 + 1].
	r := o temps: 5.
	self assert: (r copyFrom: 2 to: 3) equals: #(16 16).
	(self stressed not and: [live]) ifTrue: [self assert: r first isNil].
	self assert: (o primTemps: 5) equals: #(15 16 16).
	"code compiled before the flags change still runs until the pending flush (JitRuntime>>prepare)"
	[Smalltalk vm jitParameters: #(nil '-live' nil nil).
	 1 to: 1500 do: [:k | self assert: (o temps: k) last equals: k * 3 + 1].
	 self assert: (o temps: 5) equals: #(15 16 16)]
		ensure: [live ifTrue: [Smalltalk vm jitParameters: #(nil 'live' nil nil)]]
!
testLoopUnitWithDeadTemps
	"A loop's unit entered where temps are dead (stored before every read, or never read again): its entry names nil for them; a guard that fails in the loop rebuilds the frame, the result is exact."
	| o good bad expected |
	Smalltalk vm jitParameters: #(nil '-eager' nil nil).
	self define: 'osr: arr | dead s t last | dead := arr size * 2. s := 0. 1 to: arr size do: [:i | t := i \\ 7. s := s + t + (arr at: i) size. last := i]. ^s + last'.
	o := JitRuntimeTestSubject new.
	good := (1 to: 30000) collect: [:i | Array new: i \\ 3].
	bad := good copy.
	bad at: 25000 put: 'abcd'.
	expected := [:arr | ((1 to: arr size) inject: 0 into: [:sum :i | sum + (i \\ 7) + (arr at: i) size]) + arr size].
	3 timesRepeat: [
		self assert: (o osr: good) equals: (expected value: good).
		self assert: (o osr: bad) equals: (expected value: bad)]
! !
