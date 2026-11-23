TestCase subclass: #JitBaselineTest
	instanceVariableNames: 'saved defined'
	classVariableNames: ''
	package: 'Tests-VM'!

JitBaselineTest comment: 'The baseline compiler, switched on for each test (Smalltalk vm jitParameters:, every method compiled on its first activation): inline caches through their states (jitSendSites), relinking after redefinition, unboxed Floats and loop temps in registers when Smalltalk runs in a slow path, non-local returns, closures, allocation, every ablation flag, the listing; JitRuntimeTest runs the runtime''s tests under it.'!

!JitBaselineTest methodsFor: 'running'!
setUp
	saved := Smalltalk vm jitParameters: #('baseline' nil 0 5).
	defined := OrderedCollection new
!
tearDown
	| on flags |
	on := (saved at: 2) substrings: ','.
	flags := self flagNames inject: '' into: [:all :each |
		(all isEmpty ifTrue: [''] ifFalse: [all , ',']) , ((on includes: each) ifTrue: [each] ifFalse: ['-' , each])].
	Smalltalk vm jitParameters: {saved at: 1. flags. saved at: 3. saved at: 4}.
	defined do: [:each | each key removeSelector: each value]
!
timeLimitMilliseconds
	^120000
! !

!JitBaselineTest methodsFor: 'helpers'!
flagNames
	^#('arith' 'fuse' 'barrier' 'notes' 'ic' 'pic' 'mega' 'regs' 'prims' 'access' 'float' 'blocks' 'quick')
!
define: aString
	self define: aString in: JitBaselineTestSubject
!
define: aString in: aClass
	| m |
	m := aClass compile: aString.
	defined add: aClass -> (m isSymbol ifTrue: [m] ifFalse: [m selector])
!
subject
	^JitBaselineTestSubject new
!
sitesOf: aSelector
	^(JitBaselineTestSubject >> aSelector) jitSendSites
!
uninterrupted: aBlock
	"Evaluate aBlock at the timer's priority, so no process switch can land at the entry of an activation. The switch would hand that activation to the interpreter, whose sends do not touch the inline caches a test is reading."
	| p old |
	p := Processor activeProcess.
	old := p priority.
	p priority: Processor timingPriority.
	^aBlock ensure: [p priority: old]
! !

!JitBaselineTest methodsFor: 'tests'!
testParameters
	| now |
	now := Smalltalk vm jitParameters.
	self assert: (now at: 1) equals: 'baseline'.
	self assert: Smalltalk vm jitMode equals: #baseline.
	self flagNames do: [:each | self assert: (self flagNames includes: each)].
	self should: [Smalltalk vm jitParameters: #(nil 'nonsense' nil nil)] raise: Error
!
testParametersSurviveAScavenge
	"The primitive allocates the strings of its answer: a scavenge at one of them moves the answer, whose slots must still get them."
	| scavenges |
	scavenges := Smalltalk vm statistics scavenges.
	[Smalltalk vm statistics scavenges - scavenges < 30] whileTrue: [
		1000 timesRepeat: [Smalltalk vm jitParameters do: [:each | self assert: each notNil]]]
!
testEveryMethodCompiles
	"Every method of the image has baseline code."
	| failed |
	failed := OrderedCollection new.
	Smalltalk allClasses do: [:c |
		{c. c class} do: [:k |
			k methodDict do: [:m | (m jitCode: 'baseline') isNil ifTrue: [failed add: m]]]].
	self assert: failed isEmpty description: [failed printString]
!
testInlineCacheStates
	self uninterrupted: [self inlineCacheStates]
!
inlineCacheStates
	"A send site goes monomorphic, polymorphic, megamorphic; it answers right in each state, and says which classes it saw."
	| s sites receivers |
	self define: 'foo ^0' in: Object.
	self define: 'foo ^1'.
	self define: 'foo ^2' in: JitBaselineTestOther.
	self define: 'poke: x ^x foo'.
	s := self subject.
	self assert: (s poke: s) equals: 1.
	self assert: (s poke: s) equals: 1.
	sites := self sitesOf: #poke:.
	self assert: sites size equals: 1.
	self assert: (sites first at: 2) equals: 1.
	self assert: (sites first at: 3) asArray equals: {JitBaselineTestSubject}.
	self assert: (s poke: JitBaselineTestOther new) equals: 2.
	self assert: (s poke: s) equals: 1.
	sites := self sitesOf: #poke:.
	self assert: (sites first at: 2) equals: 2.
	self assert: (sites first at: 3) asSet equals: {JitBaselineTestSubject. JitBaselineTestOther} asSet.
	receivers := {3. $a. 'str'. #(1). 2.5. nil. true. Object new}.
	receivers do: [:each | self assert: (s poke: each) equals: 0].
	sites := self sitesOf: #poke:.
	self assert: (sites first at: 2) equals: 3.
	receivers do: [:each | self assert: (s poke: each) equals: 0].
	self assert: (s poke: s) equals: 1.
	self assert: (s poke: JitBaselineTestOther new) equals: 2
!
testRedefinitionRelinks
	| s |
	self define: 'answer ^1'.
	self define: 'callAnswer ^self answer + 0'.
	s := self subject.
	3 timesRepeat: [self assert: s callAnswer equals: 1].
	self define: 'answer ^2'.
	self assert: s callAnswer equals: 2.
	self define: 'answer ^3' in: JitBaselineTestOther.
	self assert: JitBaselineTestOther new callAnswer equals: 3.
	self assert: s callAnswer equals: 2
!
testFloats
	| s |
	self define: 'f1: n | x | x := 0.0. 1 to: n do: [:i | x := x + (i * 0.5) - (i / 4)]. ^x'.
	self define: 'f2: p ^(p * 0.5) + ((3.0 @ 4.0 - p) * 1.2)'.
	self define: 'f3: i ^(i * 0.5) - (i / 4)'.
	self define: 'f4: x | a b | a := x * 0.5. b := a + 1.0. ^a * b + (a - b)'.
	self define: 'f5: x ^(x * 2.0) < (x + 1.5) ifTrue: [#less] ifFalse: [#more]'.
	self define: 'f6: x ^x * 1.0e300 * 1.0e300'.
	s := self subject.
	self assert: (s f1: 10) equals: 13.75.
	self assert: (s f2: 2 @ 4) equals: 2.2 @ 2.0.
	self assert: (s f3: 2) equals: 0.5.
	self assert: (s f3: 4) equals: 1.0.
	self assert: (s f4: 3) equals: 2.75.
	self assert: (s f5: 1.0) equals: #less.
	self assert: (s f5: 2) equals: #more.
	self assert: (s f6: 2.0) isInfinite.
	self assert: ((s f6: 1.0e-300) - 1.0e300) abs < 1.0e290
!
testSquares
	"The same temp twice (x * x) is one register, decoded once by the Floats' slow path; SmallFloat64s go straight through it, its other cases (a BoxedFloat64, a SmallInteger) after it."
	| s |
	self define: 'sq: x ^x * x'.
	self define: 'sqMixed: x | y | y := x. ^(y * y) + (y - y) + (y + y)'.
	self define: 'sqCompare: x | y | y := x. ^Array with: y < y with: y = y with: y <= y'.
	self define: 'mixed: x with: y ^(x * y) + (y - x)'.
	s := self subject.
	self assert: (s sq: 3) equals: 9.
	self assert: (s sq: 1.5) equals: 2.25.
	self assert: (s sq: (2 raisedTo: 100) asFloat) equals: (2 raisedTo: 200) asFloat.
	self assert: (s sq: (2 raisedTo: 300) asFloat) equals: (2 raisedTo: 600) asFloat.
	self assert: (s sq: -0.0) equals: 0.0.
	self assert: (s sq: (2 raisedTo: 40)) equals: (2 raisedTo: 80).
	self assert: (s sq: (2 raisedTo: 70)) equals: (2 raisedTo: 140).
	self assert: (s sq: 1 / 2) equals: 1 / 4.
	self assert: (s sqMixed: 1.5) equals: 5.25.
	self assert: (s sqMixed: (2 raisedTo: 300) asFloat) equals: (2 raisedTo: 600) asFloat + (2 raisedTo: 301) asFloat.
	self assert: (s sqCompare: 2.5) equals: #(false true true).
	self assert: (s sqCompare: 7) equals: #(false true true).
	self assert: (s sqCompare: Float nan) equals: #(false false false).
	self assert: (s mixed: 2 with: 0.5) equals: -0.5.
	self assert: (s mixed: 0.5 with: 2) equals: 2.5.
	self assert: (s mixed: (2 raisedTo: 300) asFloat with: 3) equals: (2 raisedTo: 300) asFloat * 3 + (3 - (2 raisedTo: 300) asFloat).
	self assert: (s mixed: 1.5 with: (2 raisedTo: 300) asFloat) equals: (2 raisedTo: 300) asFloat * 1.5 + ((2 raisedTo: 300) asFloat - 1.5)
!
testUnboxedTempChangedInASlowPath
	"x is unboxed in a d register; the slow path of w + x runs a block that stores a String into x: the code goes on with x's new value."
	| w |
	self define: 'unboxed: w | x | w block: [x := ''abc'']. x := 2.0 * 1.0. w + x. ^x * 2.0'.
	w := self subject.
	self assert: ([self subject unboxed: w] on: MessageNotUnderstood do: [:e | e return: #dnu]) equals: #dnu
!
testLoopTempsInRegisters
	"An innermost loop that sends nothing keeps its most used temps in registers (on arm64): k is not reloaded from its slot on every turn."
	self define: 'sieve: flags size: n | count k | count := 0. 2 to: n do: [:i | (flags at: i) ifTrue: [count := count + 1. k := i + i. [k <= n] whileTrue: [flags at: k put: false. k := k + i]]]. ^count'.
	self assert: (self subject sieve: (Array new: 1000 withAll: true) size: 1000) equals: 168.
	"x86 has no registers to spare for them (Amd64Assembler: x26-x28 are words in memory)"
	Smalltalk vm jitArchitecture = #x86_64 ifTrue: [^self].
	self assert: (((JitBaselineTestSubject >> #sieve:size:) machineCodeFor: #baseline) includesSubstring: 'its loop register')
!
testLoopTempAsAFloatOperand
	"t lives in a register in the loop; 1.0 - t is a Float operation (1.0 is one for sure) whose slow path sends - with a Fraction: t goes into its operand slot from the loop's register."
	self define: 'pace: n | sum | sum := 0.0. 1 to: n do: [:i | | t mt | t := i / n. mt := 1.0 - t. sum := sum + mt]. ^sum'.
	self define: 'paceIn: n | sum | sum := 0.0. #(1) do: [:k | 1 to: n do: [:i | | t mt | t := i / n. mt := 1.0 - t. sum := sum + mt]]. ^sum'.
	self define: 'scaled: n | sum | sum := 0.0. 1 to: n do: [:i | | t mt | t := i / n. mt := 2.0 * t. sum := sum + mt]. ^sum'.
	self assert: (self subject pace: 3) equals: 1.0.
	self assert: (self subject paceIn: 3) equals: 1.0.
	self assert: (self subject paceIn: 4) equals: 1.5.
	self assert: (self subject scaled: 3) equals: 4.0
!
testLoopTempChangedInASlowPath
	"s lives in a register in the loop; the slow path of w + 1 runs a block that stores into it."
	self define: 'loop: w | s | w block: [s := 1000]. s := 0. 1 to: 3 do: [:i | s := s + i. w + 1. s := s + i]. ^s'.
	self assert: (self subject loop: self subject) equals: 1003
!
testNonLocalReturns
	self define: 'firstAbove: n in: c c do: [:e | e > n ifTrue: [^e]]. ^nil'.
	self define: 'guarded: c ^[self firstAbove: 2 in: c] ensure: [a := #done]'.
	self define: 'unwinding: c [c do: [:e | e > 2 ifTrue: [^e]]] ensure: [b := #unwound]. ^nil'.
	self define: 'aState ^{a. b}'.
	self assert: (self subject firstAbove: 2 in: #(1 2 3 4)) equals: 3.
	self assert: (self subject firstAbove: 5 in: #(1 2 3 4)) isNil.
	self assert: (self subject guarded: #(1 5)) equals: 5.
	self assert: (self subject unwinding: #(1 5); aState) equals: #(nil #unwound)
!
testClosures
	self define: 'adder ^[:x | [:y | x + y]]'.
	self define: 'counter | n | n := 0. ^[n := n + 1]'.
	self define: 'sum: c ^c inject: 0 into: [:acc :e | acc + e]'.
	self define: 'nested: n | r | r := 0. 1 to: n do: [:i | #(1 2) do: [:k | r := r + (i * k)]]. ^r'.
	self assert: ((self subject adder value: 5) value: 3) equals: 8.
	self assert: (self subject counter value; value; value) equals: 3.
	self assert: (self subject sum: (1 to: 100)) equals: 5050.
	self assert: (self subject nested: 10) equals: 165
!
testClosuresInMachineCode
	"Closures, and the Context of the frame that makes the first, are allocated by the code, not by the runtime, which would make the frames below canonical (jitFrameWalks) for each."
	| walks |
	self define: 'closures: n | r b | r := 0. 1 to: n do: [:i | b := [i]. r := r + b value]. ^r'.
	self subject closures: 10.
	walks := Smalltalk vm statistics jitFrameWalks.
	self assert: (self subject closures: 100000) equals: 5000050000.
	walks := Smalltalk vm statistics jitFrameWalks - walks.
	self assert: walks < 10000 description: [walks printString , ' frame walks']
!
testAllocation
	| arrays objects brace chain n |
	self define: 'arrays ^(1 to: 100) collect: [:i | Array new: i \\ 7]'.
	self define: 'objects ^(1 to: 100) collect: [:i | Object new]'.
	self define: 'bytes ^(ByteArray new: 5) , (String new: 3) asByteArray'.
	self define: 'braces: x ^{{}. {x}. {x. 2. x + 1}}'.
	brace := [:k | 'brace' , k printString , ': x ^{' , (((1 to: k) collect: [:i | i = k ifTrue: ['x'] ifFalse: [i printString]]) inject: '' into: [:all :each | all isEmpty ifTrue: [each] ifFalse: [all , '. ' , each]]) , '}'].
	self define: (brace value: 64).
	self define: (brace value: 65).
	self define: 'chain: k | a | a := nil. 1 to: k do: [:i | a := {i. a. i + 1}]. ^a'.
	3 timesRepeat: [
		self assert: (self subject braces: 7) equals: #(#() #(7) #(7 2 8)).
		self assert: (self subject brace64: 0) equals: ((1 to: 64) collect: [:i | i \\ 64]) asArray.
		self assert: (self subject brace65: 0) equals: ((1 to: 65) collect: [:i | i \\ 65]) asArray].
	chain := self subject chain: 200000.
	n := 0.
	[chain isNil] whileFalse: [
		self assert: (chain at: 3) equals: (chain at: 1) + 1.
		n := n + 1.
		self assert: (chain at: 1) equals: 200001 - n.
		chain := chain at: 2].
	self assert: n equals: 200000.
	arrays := self subject arrays.
	self assert: (arrays collect: [:each | each size]) asArray equals: ((1 to: 100) collect: [:i | i \\ 7]) asArray.
	self assert: (arrays allSatisfy: [:each | each allSatisfy: [:x | x isNil]]).
	objects := self subject objects.
	self assert: (objects collect: [:each | each identityHash]) asSet size > 90.
	self assert: (objects allSatisfy: [:each | each identityHash > 0]).
	self assert: self subject bytes size equals: 8
!
testPrimitives
	"The primitives in machine code answer what their C functions answer, failures included."
	| on off |
	self define: 'prims: objs | r try ints strs | r := OrderedCollection new. try := [:b | r add: (b on: Error do: [:e | e class name])]. ints := {17. -17. 5. -5. 0. 1. -1. SmallInteger maxVal. SmallInteger minVal}. ints do: [:a | ints do: [:b | try value: [a quo: b]. try value: [a rem: b]. try value: [a // b]. try value: [a \\ b]]]. #(65 0 16r3FFFFFFF -1 16r40000000) do: [:v | try value: [(Character value: v) value]]. strs := #('''' ''a'' ''abc'' ''abd'' ''ab'' ''zz'' #abc) , {String with: (Character value: 300). 3}. strs do: [:x | strs do: [:y | try value: [x compareWith: y]]]. {#(). #(1). #(1 2). #(1 2 3). OrderedCollection with: 1 with: 2. ''ab''. nil} do: [:x | try value: [[:a :b | a -> b] valueWithArguments: x]. try value: [[0] valueWithArguments: x]]. objs do: [:o | try value: [o basicSize]. 0 to: 10 do: [:i | try value: [o basicAt: i]. try value: [o basicAt: i put: i * 37]. try value: [o basicAt: i put: 300]. try value: [o basicAt: i put: nil]. try value: [o uint32At: i]. try value: [o uint32At: i put: 16rDEADBEEF]. try value: [o uint32At: i put: -1]]. r add: o printString]. ^r asArray'.
	on := self subject prims: {Array new: 5. ByteArray new: 9. Bitmap new: 3. 2 raisedTo: 100. 'abc' copy. #sym. 3. nil. Object new}.
	Smalltalk vm jitParameters: #(nil '-prims' nil nil).
	off := self subject prims: {Array new: 5. ByteArray new: 9. Bitmap new: 3. 2 raisedTo: 100. 'abc' copy. #sym. 3. nil. Object new}.
	Smalltalk vm jitParameters: #(nil 'prims' nil nil).
	self assert: on equals: off.
	self assert: (on first: 4) equals: #(1 0 1 0)
!
testStringPrimitives
	"String at: and at:put: (stringAt, stringAtPut) in machine code answer what their C functions answer: byte and wide strings, a read-only Symbol, indices out of range, Characters that do not fit, non-Characters; they call no C function (the VM's counter, other Processes' calls included: the quietest of 3 rounds counts)."
	| strings on off deltas |
	self define: 'strs: objs | r try | r := OrderedCollection new. try := [:b | r add: (b on: Error do: [:e | e class name])]. objs do: [:o | -1 to: 4 do: [:i | try value: [o perform: #at: with: i]. try value: [o streamAt: i put: $z]. try value: [o streamAt: i put: (Character value: 300)]. try value: [o streamAt: i put: 3]. try value: [o perform: #at: with: i]]. r add: o printString]. ^r asArray'.
	strings := [{'abc' copy. #sym. String with: (Character value: 955) with: $b with: $c. 'é' copy}].
	on := self subject strs: strings value.
	Smalltalk vm jitParameters: #(nil '-prims' nil nil).
	off := self subject strs: strings value.
	Smalltalk vm jitParameters: #(nil 'prims' nil nil).
	self assert: on equals: off.
	self assert: on last equals: '''z'''.
	self define: 'fill: s times: n 1 to: n do: [:k | 1 to: s size do: [:i | s streamAt: i put: (s perform: #at: with: i)]]. ^s'.
	deltas := (1 to: 3) collect: [:i | | before |
		before := Smalltalk vm statistics.
		self subject fill: (String new: 100 withAll: $q) times: 100.
		Smalltalk vm statistics - before].
	self assert: (deltas collect: [:d | d jitPrimitiveCalls]) min < 1000
!
testLoopEnteredByAThreadedJump
	"A jump threaded into a conditional jump whose next instruction is a loop's head enters the loop without falling in: the loop's temps are right there too (that loop keeps them in their slots), with sends in the loop and without."
	self define: 'id: x ^x'.
	self define: 'threaded: a m: m | k len sum | k := 1. len := 100. sum := 0. (a and: [m < 10]) ifTrue: [[k <= len] whileTrue: [sum := sum + (self id: k). k := k + 1]]. ^sum'.
	self define: 'threadedNoSends: a m: m | k len sum | k := 1. len := 100. sum := 0. (a and: [m < 10]) ifTrue: [[k <= len] whileTrue: [sum := sum + k. k := k + 1]]. ^sum'.
	self assert: (self subject threaded: true m: 3) equals: 5050.
	self assert: (self subject threaded: false m: 3) equals: 0.
	self assert: (self subject threaded: true m: 30) equals: 0.
	self assert: (self subject threadedNoSends: true m: 3) equals: 5050.
	self assert: (self subject threadedNoSends: true m: 30) equals: 0
!
testLoopBottoms
	"A loop's bottom (a comparison and a conditional jump back) is one branch to the head, where the loop checks for interrupts (also at a method's or a block's start); the comparison's slow path (Floats, LargeIntegers) goes back to the head or leaves the loop as the conditional jump would; a non-Boolean leaves for mustBeBoolean."
	| s big |
	self define: 'from: a to: b | k | k := 0. a to: b do: [:i | k := k + i]. ^k'.
	self define: 'count: n | k | [k isNil or: [k < n]] whileTrue: [k := (k ifNil: [0]) + 1]. ^k'.
	self define: 'inBlock: n | m | m := 0. [[m < n] whileTrue: [m := m + 1]] value. ^m'.
	self define: 'notBoolean: x | k | k := 0. [k := k + 1. k < 3 ifTrue: [true] ifFalse: [x]] whileTrue. ^k'.
	self define: 'many: n | k | k := 0. 1 to: n do: [:i | k := k + 1]. ^k'.
	s := self subject.
	big := 2 raisedTo: 62.
	self assert: (s from: 1 to: 100) equals: 5050.
	self assert: (s from: 1 to: 0) equals: 0.
	self assert: (s from: 1 to: 2.5) equals: 3.
	self assert: (s from: 0.5 to: 3) equals: 4.5.
	self assert: (s from: big to: big + 3) equals: 4 * big + 6.
	self assert: (s from: SmallInteger maxVal - 2 to: SmallInteger maxVal + 1) equals: 4 * SmallInteger maxVal - 2.
	self assert: (s count: 5) equals: 5.
	self assert: (s inBlock: 7) equals: 7.
	self assert: (s notBoolean: false) equals: 3.
	self should: [s notBoolean: 7] raise: Error.
	self assert: (s many: 3000000) equals: 3000000.
	self assert: (((JitBaselineTestSubject >> #from:to:) machineCodeFor: #baseline) includesSubstring: 'loop head: interrupt check')
!
testNilTests
	"isNil and notNil compare with nil until a class defines them; then all code is dropped and they are sent."
	| other |
	self define: 'nilTests: x ^{x isNil. x notNil. x isNil ifTrue: [1] ifFalse: [2]}'.
	other := JitBaselineTestOther new.
	self assert: (self subject nilTests: nil) equals: #(true false 1).
	self assert: (self subject nilTests: other) equals: #(false true 2).
	self define: 'isNil ^true' in: JitBaselineTestOther.
	self assert: (self subject nilTests: other) equals: #(true true 1).
	self assert: (self subject nilTests: nil) equals: #(true false 1)
!
testNilTestsInline
	"In a fresh VM nothing but UndefinedObject and ProtoObject defines isNil: it compiles to a comparison."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. 'baseline'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'((Dictionary >> #at:ifAbsent:) machineCodeFor: #baseline) includesSubstring: ''isNil: == nil'''}).
	self assert: run output trimBoth equals: 'true'
!
testEveryFlagOff
	"Each optimization switched off alone: the same answers."
	self define: 'fib: n ^n < 2 ifTrue: [n] ifFalse: [(self fib: n - 1) + (self fib: n - 2)]'.
	self define: 'pow: n | r b k | r := 1. b := 10. k := n. [k > 0] whileTrue: [(k bitAnd: 1) = 1 ifTrue: [r := r * b]. k := k bitShift: -1. k > 0 ifTrue: [b := b * b]]. ^r'.
	self define: 'mix: n | x a | x := 0.0. a := Array new: n. 1 to: n do: [:i | a at: i put: i * 2. x := x + (i / 2.0)]. ^{x. (a inject: 0 into: [:s :e | s + e]). a printString size}'.
	#('arith' 'fuse' 'barrier' 'ic' 'pic' 'mega' 'regs' 'prims' 'access' 'float' 'blocks' 'quick') do: [:flag |
		Smalltalk vm jitParameters: {nil. '-' , flag. nil. nil}.
		self assert: (self subject fib: 15) equals: 610.
		self assert: (self subject mix: 20) equals: #(105.0 420 58).
		self assert: (self subject pow: 22) equals: 10000000000000000000000.
		Smalltalk vm jitParameters: {nil. flag. nil. nil}]
!
testDisassembly
	| listing |
	self define: 'sum: n | s | s := 0. 1 to: n do: [:i | s := s + (i * 2.5)]. ^s'.
	listing := (JitBaselineTestSubject >> #sum:) machineCodeFor: #baseline.
	self assert: (listing beginsWith: 'JitBaselineTestSubject>>sum:  baseline').
	self assert: (listing includesSubstring: 'checked entry').
	self assert: (listing includesSubstring: 'stack check').
	self assert: (listing includesSubstring: 'native frame record').
	self assert: (listing includesSubstring: 'Floats').
	self assert: (listing includesSubstring: 'loop head: interrupt check').
	self assert: (listing includesSubstring: 'pop the frame and the record, return').
	self assert: (listing includesSubstring: '-- sum: n')
! !
