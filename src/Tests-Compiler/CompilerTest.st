TestCase subclass: #CompilerTest
	instanceVariableNames: 'installed'
	classVariableNames: ''
	package: 'Tests-Compiler'!

CompilerTest comment: 'I compile methods and do-its with the Smalltalk compiler and run them.'!

!CompilerTest class methodsFor: 'debugger support'!
unmappedStopsIn: aMethod
	"Answer the pcs of sends, stores, returns and closure pushes of aMethod that have no sourceMap entry."
	| mapped result |
	mapped := Set new.
	aMethod sourceMap isNil ifFalse: [
		1 to: aMethod sourceMap size by: 3 do: [:i | mapped add: (aMethod sourceMap at: i)]].
	result := OrderedCollection new.
	aMethod instructionsDo: [:pc :op |
		((self isStopOpcode: op) and: [(mapped includes: pc) not]) ifTrue: [result add: pc]].
	^result
!
isStopOpcode: op
	(op between: 16r60 and: 16r67) ifTrue: [^true].
	(op between: 16r79 and: 16r7C) ifTrue: [^true].
	(op between: 16r84 and: 16r8F) ifTrue: [^op ~= 16r8A].
	((op between: 16r97 and: 16r9F) or: [op between: 16rF0 and: 16rFB]) ifTrue: [^true].
	^op between: 16rA0 and: 16rEF
! !

!CompilerTest methodsFor: 'running'!
setUp
	installed := OrderedCollection new
!
tearDown
	installed do: [:each | (each at: 1) removeSelector: (each at: 2)]
! !

!CompilerTest methodsFor: 'helpers'!
unmappedStopsIn: aMethod
	"Answer the pcs of sends, stores, returns and closure pushes that have no sourceMap entry."
	^CompilerTest unmappedStopsIn: aMethod
!
assertCaptures: aString equal: anArray
	"Evaluate aString, with bs an OrderedCollection, k 0, x nil, and the closures it collects in bs, with the blocks marked @ inlined and not; both must answer anArray."
	#('' ' yourself') do: [:suffix | | source |
		source := '| bs k x | bs := OrderedCollection new. k := 0. ' , (aString copyReplaceAll: '@' with: suffix) , '. (bs collect: [:b | b value]) asArray'.
		self assert: (self eval: source) equals: anArray]
!
closuresIn: aMethod
	| n |
	n := 0.
	aMethod instructionsDo: [:pc :op | op = 16r8F ifTrue: [n := n + 1]].
	^n
!
compile: aString
	^self compile: aString in: CompilerTestSubject
!
compile: aString in: aClass
	| method |
	method := Compiler compile: aString in: aClass classified: 'compiler tests'.
	installed add: (Array with: aClass with: method selector).
	^method
!
run: aString
	^self run: aString on: CompilerTestSubject new
!
run: aString on: anObject
	^anObject perform: (self compile: aString in: anObject class) selector
!
eval: aString
	^Compiler evaluate: aString
!
errorIn: aString
	"Answer the SyntaxError signaled when compiling aString as a method of CompilerTestSubject, or nil."
	^[Compiler compileMethod: aString in: CompilerTestSubject classified: nil.
	  nil]
		on: SyntaxError
		do: [:e | e return: e]
!
primitiveNumberOf: aString
	| names |
	names := Smalltalk vm primitiveNames.
	1 to: names size do: [:i |
		((names at: i) notNil and: [(names at: i) asString = aString]) ifTrue: [^i]].
	^0
! !

!CompilerTest methodsFor: 'tests - literals'!
testIntegerLiterals
	self assert: (self eval: '3') equals: 3.
	self assert: (self eval: '-3') equals: -3.
	self assert: (self eval: '16r1F') equals: 31.
	self assert: (self eval: '2r1010') equals: 10.
	self assert: (self eval: '-16rFF') equals: -255.
	self assert: (self eval: '16r-FF') equals: -255.
	self assert: (self eval: '36rZ') equals: 35.
	self assert: (self eval: '1e3') equals: 1000.
	self assert: (self eval: '40000') equals: 40000.
	self assert: (self eval: '-40000') equals: -40000.
	self assert: (self eval: '1073741823') equals: 1073741823.
	self assert: (self eval: '4611686018427387903') equals: 4611686018427387903.
	self assert: (self eval: '-4611686018427387904') equals: -4611686018427387904
!
testLargeIntegerLiterals
	self assert: (self eval: '4611686018427387904') equals: 4611686018427387903 + 1.
	self assert: (self eval: '1000000000000000000000') equals: 1000000000 * 1000000000000.
	self assert: (self eval: '-1000000000000000000000') equals: -1000000000 * 1000000000000.
	self assert: (self eval: '16rFFFFFFFFFFFFFFFFFFFF') equals: (1 bitShift: 80) - 1
!
testFloatLiterals
	self assert: (self eval: '2.5') equals: 2.5.
	self assert: (self eval: '0.1') equals: 1 / 10.0.
	self assert: (self eval: '1.5e3') equals: 1500.0.
	self assert: (self eval: '2.5e-3') equals: 25 / 10000.0.
	self assert: (self eval: '-0.5') equals: -1 / 2.0.
	self assert: (self eval: '1.0e10') equals: 10000000000.0.
	self assert: (self eval: '0.00166007664274403694') asIEEEBits equals: 16r3F5B32DDB8EC9209.
	self assert: (self eval: '12.894369562139131') asIEEEBits equals: 16r4029C9EACEA7D9CF.
	self assert: (self eval: '2.5') isFloat
!
testCharacterAndStringLiterals
	self assert: (self eval: '$a') equals: $a.
	self assert: (self eval: '$ ') equals: (Character value: 32).
	self assert: (self eval: '$''') equals: (Character value: 39).
	self assert: (self eval: '''it''''s''') equals: 'it''s'.
	self assert: (self eval: '''it''''s''') size equals: 4.
	self assert: (self eval: '''''') isEmpty
!
testSymbolLiterals
	self assert: (self eval: '#foo') == #foo.
	self assert: (self eval: '#foo:bar:') == #foo:bar:.
	self assert: (self eval: '#+') == #+.
	self assert: (self eval: '#''hello world''') == #'hello world'.
	self assert: (self eval: '#Foo') == #Foo
!
testUnicodeNames
	"Temporaries, keyword and binary selectors and symbols with non-ASCII names, in strings: these sources are compiled by the seed image's compiler."
	| subject |
	self assert: (self eval: '| größe | größe := 3. größe * 2') equals: 6.
	self assert: (self eval: '| λ 日本 | λ := 2. 日本 := 5. λ * 日本') equals: 10.
	self assert: (self eval: '#größe') == 'größe' asSymbol.
	self assert: (self eval: '#(größe: × #λ)') equals: {'größe:' asSymbol. '×' asSymbol. 'λ' asSymbol}.
	self assert: (self eval: '#größe:von: numArgs') equals: 2.
	self assert: (self eval: 'Object' , (String with: (Character value: 160)) , 'name') equals: 'Object'.
	self compile: 'größe: x von: y ^x - y'.
	self compile: '× other ^42 + other'.
	self compile: 'größe ^self größe: 10 von: (self × 1)'.
	subject := CompilerTestSubject new.
	self assert: (subject perform: 'größe:von:' asSymbol with: 5 with: 3) equals: 2.
	self assert: (subject perform: '×' asSymbol with: 1) equals: 43.
	self assert: (subject perform: 'größe' asSymbol) equals: -33.
	self assert: (self errorIn: 'foo ^😀') notNil.
	self assert: (self errorIn: 'foo | 😀 | ^1') notNil
!
testLiteralArrays
	self assert: (self eval: '#(1 $a ''s'' #sym foo bar: #(2 3) (4 5) true false nil)')
		equals: {1. $a. 's'. #sym. #foo. #bar:. #(2 3). #(4 5). true. false. nil}.
	self assert: (self eval: '#(foo:bar: + - #at:put:)') equals: {#foo:bar:. #+. #-. #at:put:}.
	self assert: (self eval: '#(1 -2 3.5 -4.5e1)') equals: {1. -2. 3.5. -45.0}.
	self assert: (self eval: '#()') equals: #().
	self assert: (self eval: '#(#(#(1)))') equals: {{{1}}}
!
testByteArrayLiterals
	| bytes |
	bytes := self eval: '#[1 2 255]'.
	self assert: bytes class == ByteArray.
	self assert: bytes size equals: 3.
	self assert: (bytes at: 3) equals: 255.
	self assert: (self eval: '#(#[7])') first class == ByteArray
!
testBraceArrays
	self assert: (self eval: '{1. 2 + 3. #x}') equals: #(1 5 #x).
	self assert: (self eval: '{}') equals: #().
	self assert: (self eval: '{1. {2}}') equals: {1. {2}}
!
testSpecialLiterals
	self assert: (self eval: 'nil') isNil.
	self assert: (self eval: 'true') == true.
	self assert: (self eval: 'false') == false.
	self assert: (self eval: '') isNil
! !

!CompilerTest methodsFor: 'tests - messages'!
testPrecedence
	self assert: (self eval: '3 + 4 * 2') equals: 14.
	self assert: (self eval: '3 + (4 * 2)') equals: 11.
	self assert: (self eval: '(Array new: 2 + 1) size') equals: 3.
	self assert: (self eval: '3 - -4') equals: 7.
	self assert: (self eval: '3-4') equals: -1.
	self assert: (self eval: '#(3 4) size negated abs') equals: 2
!
testCascades
	self assert: (self eval: '(OrderedCollection new) add: 1; add: 2; yourself') asArray equals: #(1 2).
	self assert: (self eval: 'OrderedCollection new add: 5; add: 6') equals: 6.
	self assert: (self eval: '| c | c := OrderedCollection new. c add: 3; add: 4. c size') equals: 2.
	self assert: (self eval: '| c | c := OrderedCollection new. c add: 3 + 4; add: (c size); yourself. c asArray') equals: #(7 1)
!
testCascadeOnSuper
	self compile: 'tCascadeSuper ^super greeting; greeting' in: CompilerTestSubjectChild.
	self assert: CompilerTestSubjectChild new tCascadeSuper equals: 'hello'
!
testSuperSend
	self compile: 'tSuper ^super greeting , self greeting' in: CompilerTestSubjectChild.
	self assert: CompilerTestSubjectChild new tSuper equals: 'hellochild'
!
testThisContext
	self assert: (self eval: 'thisContext method selector') == #DoIt.
	self assert: (self eval: 'thisContext method methodClass') == UndefinedObject.
	self assert: (self eval: 'thisContext receiver') isNil.
	self assert: (self eval: 'thisContext sender method selector') == #evaluate:for:.
	self assert: (self eval: 'thisContext sender method methodClass') == Compiler
!
testEvaluateForReceiver
	self assert: (Compiler evaluate: 'self + 1' for: 41) equals: 42.
	self assert: (Compiler evaluate: 'thisContext method methodClass' for: 3) == SmallInteger.
	self assert: (Compiler evaluate: 'a' for: CompilerTestSubject new) isNil
!
testSpecialSelectorSends
	self assert: (self eval: '#(1 2 3) at: 2') equals: 2.
	self assert: (self eval: '(Array new: 3) at: 1 put: 7; yourself') first equals: 7.
	self assert: (self eval: '3 @ 4') x equals: 3.
	self assert: (self eval: '7 \\ 3') equals: 1.
	self assert: (self eval: '7 // 2') equals: 3.
	self assert: (self eval: '1 bitShift: 4') equals: 16.
	self assert: (self eval: '3 max: 9') equals: 9.
	self assert: (self eval: '[:x :y | x - y] value: 5 value: 3') equals: 2.
	self assert: (self eval: '3 == 3').
	self assert: (self eval: '3 ~~ 4').
	self assert: (self eval: 'nil isNil').
	self assert: (self eval: '3 notNil').
	self assert: (self eval: '3 class') == SmallInteger
! !

!CompilerTest methodsFor: 'tests - variables'!
testTemporaries
	self assert: (self eval: '| a b | a := b := 3. a + b') equals: 6.
	self assert: (self eval: '| a | a') isNil
!
testInstanceVariables
	| subject |
	self compile: 'tSetA: x a := x'.
	self compile: 'tSetB: x ^b := x'.
	subject := CompilerTestSubject new.
	subject tSetA: 5.
	self assert: subject a equals: 5.
	self assert: (subject tSetB: 6) equals: 6.
	self assert: subject b equals: 6
!
testInheritedInstanceVariables
	self compile: 'tSetAD: x a := x. d := x + 1. ^a + d' in: CompilerTestSubjectChild.
	self assert: (CompilerTestSubjectChild new tSetAD: 1) equals: 3
!
testClassVariables
	self compile: 'tShared: x Shared := x'.
	self compile: 'tShared ^Shared'.
	self compile: 'tChildShared ^Shared' in: CompilerTestSubjectChild.
	CompilerTestSubject new tShared: 42.
	self assert: CompilerTestSubject new tShared equals: 42.
	self assert: CompilerTestSubjectChild new tChildShared equals: 42.
	CompilerTestSubject new tShared: nil
!
testClassSideAccessesClassVariables
	self compile: 'tClassShared ^Shared' in: CompilerTestSubject class.
	self compile: 'tShared: x Shared := x'.
	CompilerTestSubject new tShared: 7.
	self assert: CompilerTestSubject tClassShared equals: 7.
	CompilerTestSubject new tShared: nil
!
testGlobals
	self assert: (self eval: 'Object') == Object.
	self assert: (self eval: 'Smalltalk') == Smalltalk
! !

!CompilerTest methodsFor: 'tests - blocks'!
testBlockValues
	self assert: (self eval: '[:x | x + 1] value: 2') equals: 3.
	self assert: (self eval: '[:x :y | x * y] value: 3 value: 4') equals: 12.
	self assert: (self eval: '[3] value') equals: 3.
	self assert: (self eval: '[] value') isNil.
	self assert: (self eval: '[:x | ] value: 3') isNil.
	self assert: (self eval: '[| t | t] value') isNil.
	self assert: (self eval: '[:a :b | a] numArgs') equals: 2
!
testOuterTemps
	self assert: (self eval: '| x | x := 1. [x := x + 1] value. x') equals: 2.
	self assert: (self eval: '| x | x := 0. [:a | [:b | x := x + a + b] value: 2] value: 1. x') equals: 3.
	self assert: (self eval: '| x | x := 5. [:a | | y | y := a. [y + x] value] value: 10') equals: 15
!
testBlocksReturningBlocks
	self assert: (self eval: '| adder | adder := [:n | [:m | n + m]]. (adder value: 3) value: 4') equals: 7.
	self assert: (self eval: '| counter c | counter := [| n | n := 0. [n := n + 1]]. c := counter value. c value. c value') equals: 2
!
testBlockActivationsAreIndependent
	self assert: (self eval: '| bs | bs := OrderedCollection new. #(1 2 3) do: [:i | bs add: [i * 10]]. (bs collect: [:b | b value]) asArray')
		equals: #(10 20 30)
!
testRecursiveBlock
	self assert: (self eval: '| f | f := [:n | n <= 1 ifTrue: [1] ifFalse: [n * (f value: n - 1)]]. f value: 10') equals: 3628800
!
testNonLocalReturn
	self compile: 'tNlr #(1 2 3) do: [:e | e = 2 ifTrue: [^e * 100]]. ^0'.
	self compile: 'tNlrNested ^[:x | [:y | ^x + y] value: 1] value: 2'.
	self compile: 'tNlrSelf [^self] value. ^nil'.
	self assert: CompilerTestSubject new tNlr equals: 200.
	self assert: CompilerTestSubject new tNlrNested equals: 3.
	self assert: CompilerTestSubject new tNlrSelf class == CompilerTestSubject.
	self assert: (self eval: '#(1 2 3) do: [:e | e = 2 ifTrue: [^e]]. 0') equals: 2
!
testNonLocalReturnThroughEnsure
	| log |
	log := OrderedCollection new.
	self compile: 'tNlrEnsure: log [^1] ensure: [log add: #done]. ^2'.
	self assert: (CompilerTestSubject new tNlrEnsure: log) equals: 1.
	self assert: log asArray equals: #(#done)
!
testBlockInCascade
	self assert: (self eval: '| c | c := OrderedCollection new. c add: [1]; add: [2]. (c collect: [:b | b value]) asArray') equals: #(1 2)
! !

!CompilerTest methodsFor: 'tests - inlining'!
testIfTrueIfFalse
	self assert: (self eval: '3 > 2 ifTrue: [#yes] ifFalse: [#no]') == #yes.
	self assert: (self eval: '3 < 2 ifTrue: [#yes] ifFalse: [#no]') == #no.
	self assert: (self eval: '3 < 2 ifTrue: [#yes]') isNil.
	self assert: (self eval: '3 > 2 ifTrue: [#yes]') == #yes.
	self assert: (self eval: '3 < 2 ifFalse: [#no]') == #no.
	self assert: (self eval: '3 > 2 ifFalse: [#no]') isNil.
	self assert: (self eval: '3 > 2 ifFalse: [#no] ifTrue: [#yes]') == #yes.
	self assert: (self eval: '3 > 2 ifTrue: []') isNil.
	self assert: (self eval: '| r | r := 0. 3 > 2 ifTrue: [r := 1]. 3 < 2 ifTrue: [r := 2]. r') equals: 1.
	self assert: (self eval: '| r | 3 > 2 ifTrue: [r := 1] ifFalse: [r := 2]. r') equals: 1.
	self assert: (self eval: '(3 > 2 ifTrue: [1] ifFalse: [2]) + 10') equals: 11
!
testAndOr
	self assert: (self eval: '(3 > 2) and: [2 > 1]') == true.
	self assert: (self eval: '(3 > 2) and: [2 > 5]') == false.
	self assert: (self eval: '(3 < 2) and: [nil foo]') == false.
	self assert: (self eval: '(3 > 2) or: [nil foo]') == true.
	self assert: (self eval: '(3 < 2) or: [3 > 2]') == true.
	self assert: (self eval: '(3 < 2) or: [3 < 2]') == false.
	self assert: (self eval: '| r | r := 0. (3 > 2) and: [r := 5]. r') equals: 5
!
testWhileLoops
	self assert: (self eval: '| i s | i := 0. s := 0. [i < 5] whileTrue: [i := i + 1. s := s + i]. s') equals: 15.
	self assert: (self eval: '| i | i := 0. [i >= 3] whileFalse: [i := i + 1]. i') equals: 3.
	self assert: (self eval: '| i | i := 0. [i := i + 1. i < 10] whileTrue. i') equals: 10.
	self assert: (self eval: '| i | i := 0. [i := i + 1. i >= 4] whileFalse. i') equals: 4.
	self assert: (self eval: '| i | i := 0. ([i < 2] whileTrue: [i := i + 1]) isNil') == true
!
testRepeat
	self compile: 'tRepeat | i | i := 0. [i := i + 1. i = 7 ifTrue: [^i]] repeat'.
	self assert: CompilerTestSubject new tRepeat equals: 7
!
testToDo
	self assert: (self eval: '| s | s := 0. 1 to: 10 do: [:i | s := s + i]. s') equals: 55.
	self assert: (self eval: '| s | s := OrderedCollection new. 10 to: 1 by: -3 do: [:i | s add: i]. s asArray') equals: #(10 7 4 1).
	self assert: (self eval: '| s | s := OrderedCollection new. 1 to: 2 by: 0.5 do: [:i | s add: i]. s size') equals: 3.
	self assert: (self eval: '| n s | n := 3. s := 0. 1 to: n do: [:i | n := 10. s := s + 1]. s') equals: 3.
	self assert: (self eval: '| r | r := OrderedCollection new. 1 to: 3 do: [:i | | t | t := i * i. r add: t]. r asArray') equals: #(1 4 9).
	self assert: (self eval: '| s | s := 0. 5 to: 1 do: [:i | s := s + 1]. s') equals: 0.
	self assert: (self eval: '| s | s := 0. 1 to: 3 do: [:i | 1 to: i do: [:j | s := s + j]]. s') equals: 10
!
testToDoClosureSeesLoopVariable
	self assert: (self eval: '| r | r := OrderedCollection new. 1 to: 3 do: [:i | r add: ([:k | k + i] value: 100)]. r asArray') equals: #(101 102 103)
!
testIfNil
	self assert: (self eval: 'nil ifNil: [3]') equals: 3.
	self assert: (self eval: '4 ifNil: [3]') equals: 4.
	self assert: (self eval: 'nil ifNotNil: [:x | x + 1]') isNil.
	self assert: (self eval: '4 ifNotNil: [:x | x + 1]') equals: 5.
	self assert: (self eval: '4 ifNotNil: [7]') equals: 7.
	self assert: (self eval: 'nil ifNil: [1] ifNotNil: [:x | x]') equals: 1.
	self assert: (self eval: '5 ifNil: [1] ifNotNil: [:x | x * 2]') equals: 10.
	self assert: (self eval: '5 ifNotNil: [:x | x * 3] ifNil: [0]') equals: 15.
	self assert: (self eval: 'nil ifNotNil: [:x | x] ifNil: [0]') equals: 0.
	self assert: (self eval: '| r | r := 0. nil ifNil: [r := 1]. 5 ifNotNil: [:x | r := r + x]. 7 ifNil: [r := 100]. nil ifNotNil: [:x | r := 100]. r') equals: 6.
	self assert: (self eval: '| r | 5 ifNil: [r := 1] ifNotNil: [:x | r := x]. r') equals: 5
!
testInliningShowsInBytecodes
	| m |
	m := self compile: 'tInl: x ^x ifTrue: [1] ifFalse: [2]'.
	self assert: (m literals includes: #ifTrue:ifFalse:) not.
	self assert: (m symbolic includesSubstring: 'jumpFalseTo:').
	m := self compile: 'tInl: x with: aBlock ^x ifTrue: aBlock'.
	self assert: (m literals includes: #ifTrue:).
	m := self compile: 'tInlWhile | i | i := 0. [i < 3] whileTrue: [i := i + 1]. ^i'.
	self assert: (m literals includes: #whileTrue:) not.
	self assert: CompilerTestSubject new tInlWhile equals: 3
!
testNonInlinedFallbacks
	self assert: (self eval: '| b | b := [#yes]. 3 > 2 ifTrue: b') == #yes.
	self assert: (self eval: '| b | b := [:x | x + 1]. 3 ifNotNil: b') equals: 4.
	self assert: (self eval: '| s b | s := 0. b := [:i | s := s + i]. 1 to: 4 do: b. s') equals: 10
!
testLoopVariablesFreshPerIteration
	"A closure in an inlined loop captures the variables of its own iteration (the loop variable, the temporaries of the loop's blocks and of the blocks inlined into them), as in the loop's non-inlined form: @ marks the blocks the form leaves inlined or (yourself) not."
	self assertCaptures: '1 to: 3 do: [:i | | j | j := i * 10. bs add: [j + i]]@' equal: #(11 22 33).
	self assertCaptures: '1 to: 3 do: [:i | bs add: [i]]@' equal: #(1 2 3).
	self assertCaptures: '1 to: 3 do: [:i | | j | bs add: [j]. j := i * 10]@' equal: #(10 20 30).
	self assertCaptures: '1 to: 3 do: [:i | | j | bs add: [j]. i = 1 ifTrue: [j := 5]]@' equal: #(5 nil nil).
	self assertCaptures: '1 to: 3 do: [:i | | j | j := i. bs add: [j := j + 1]]@' equal: #(2 3 4).
	self assertCaptures: '1 to: 3 do: [:i | | j | j := i. [j := j + 100] value. bs add: [j]]@' equal: #(101 102 103).
	self assertCaptures: '7 to: 1 by: -3 do: [:i | bs add: [i]]@' equal: #(7 4 1).
	self assertCaptures: '[k < 3]@ whileTrue: [| j | k := k + 1. j := k. bs add: [j]]@' equal: #(1 2 3).
	self assertCaptures: '[k < 3]@ whileTrue: [| j | bs add: [j]. k := k + 1. j := k]@' equal: #(1 2 3).
	self assertCaptures: '[k >= 3]@ whileFalse: [| j | k := k + 1. j := k. bs add: [j]]@' equal: #(1 2 3).
	self assertCaptures: '[| j | j := k. bs add: [j]. k >= 2]@ whileFalse: [k := k + 1]@' equal: #(0 1 2).
	self assertCaptures: '[| j | j := k. bs add: [j]. (k := k + 1) < 3]@ whileTrue' equal: #(0 1 2).
	self assertCaptures: '[| j | bs add: [j]. j := k. (k := k + 1) >= 3]@ whileFalse' equal: #(0 1 2).
	self assertCaptures: '[| j | j := k. bs add: [j]. (k := k + 1) = 3 ifTrue: [^(bs collect: [:b | b value]) asArray]]@ repeat' equal: #(0 1 2).
	self assertCaptures: '1 to: 3 do: [:i | i >= 0 ifTrue: [| j | j := i. bs add: [j]]@]@' equal: #(1 2 3).
	self assertCaptures: '1 to: 3 do: [:i | i < 0 ifFalse: [| j | j := i. bs add: [j]]@]@' equal: #(1 2 3).
	self assertCaptures: '1 to: 3 do: [:i | i odd ifTrue: [| j | j := i. bs add: [j]]@ ifFalse: [| j | j := i negated. bs add: [j]]@]@' equal: #(1 -2 3).
	self assertCaptures: '1 to: 3 do: [:i | (i > 0 and: [| j | j := i. bs add: [j]. true]@) | (i < 0 or: [| j | j := i * 2. bs add: [j]. true]@)]@' equal: #(1 2 2 4 3 6).
	self assertCaptures: '1 to: 3 do: [:i | i ifNotNil: [:v | bs add: [v]]@]@' equal: #(1 2 3).
	self assertCaptures: '1 to: 3 do: [:i | nil ifNil: [| j | j := i. bs add: [j]]@]@' equal: #(1 2 3).
	self assertCaptures: '1 to: 3 do: [:i | i ifNil: [nil]@ ifNotNil: [:v | bs add: [v * 2]]@]@' equal: #(2 4 6).
	self assertCaptures: '1 to: 3 do: [:i | i ifNotNil: [:v | bs add: [v * 3]]@ ifNil: [nil]@]@' equal: #(3 6 9).
	self assertCaptures: '1 to: 2 do: [:i | 1 to: 2 do: [:k | bs add: [i * 10 + k]]@]@' equal: #(11 12 21 22).
	self assertCaptures: '1 to: 2 do: [:i | | k | k := 0. [k < 2]@ whileTrue: [| j | k := k + 1. j := k. bs add: [i * 10 + j]]@]@' equal: #(11 12 21 22).
	self assertCaptures: '1 to: 3 do: [:i | x := i. bs add: [x]]@' equal: #(3 3 3).
	self assertCaptures: '1 to: 3 do: [:i | | j | j := i. bs add: [j]. x := (x ifNil: [0]) * 10 + (thisContext tempNamed: ''j'')]@. bs add: [x]' equal: #(1 2 3 123)
!
testLoopBlocksWithCapturedVariablesReturn
	self compile: 'tCapturedReturn | r | 1 to: 5 do: [:i | | j | j := i. r := [j]. i = 3 ifTrue: [^r]]. ^nil'.
	self assert: CompilerTestSubject new tCapturedReturn value equals: 3.
	self compile: 'tCapturedWhileReturn | k | k := 0. [| j | j := k. k := k + 1. k = 2 ifTrue: [^[j]]. true] whileTrue. ^nil'.
	self assert: CompilerTestSubject new tCapturedWhileReturn value equals: 1.
	self assert: (self eval: '1 to: 3 do: [:i | [i]]') isNil.
	self assert: (self eval: '| k | k := 0. [| j | j := k. [j]. (k := k + 1) < 3] whileTrue: [| j | j := k. [j]]') isNil
!
testLoopsWithoutCapturedVariablesStayInlined
	"Only a loop whose own variables a closure captures gets a block of its own."
	| m |
	m := self compile: 'tNoCapture: c | s | s := 0. 1 to: 3 do: [:i | | t | t := i. s := s + t. c do: [:e | s := s + e]. c do: [:i | s := s + i]]. [s > 100] whileFalse: [s := s * 2]. ^s'.
	self assert: (self closuresIn: m) equals: 2.
	self assert: (CompilerTestSubject new tNoCapture: #(1)) equals: 192.
	m := self compile: 'tNested | bs | bs := OrderedCollection new. 1 to: 2 do: [:i | 1 to: 2 do: [:k | bs add: [k]]]. ^(bs collect: [:b | b value]) asArray'.
	self assert: (self closuresIn: m) equals: 3.
	self assert: CompilerTestSubject new tNested equals: #(1 2 1 2)
!
testHoistedTemps
	| m |
	m := self compile: 'tHoist | a | 1 to: 3 do: [:i | | t | t := i]. ^a'.
	self assert: m numTemps equals: 3.
	m := self compile: 'tHoistLimit: n 1 to: n do: [:i | ]'.
	self assert: m numTemps equals: 2
! !

!CompilerTest methodsFor: 'tests - primitives'!
testPrimitiveSuccess
	| m |
	m := self compile: 'tPrimClass <primitive: ''class''> ^#failed'.
	self assert: m primitive equals: (self primitiveNumberOf: 'class').
	self assert: m primitive > 0.
	self assert: CompilerTestSubject new tPrimClass == CompilerTestSubject
!
testPrimitiveFailure
	self compile: 'tPrimFail: x <primitive: ''intAdd''> ^#failed'.
	self assert: (CompilerTestSubject new tPrimFail: 3) == #failed
!
testPrimitiveErrorCode
	| m result |
	m := self compile: 'tPrimEc: x <primitive: ''intAdd'' error: ec> | t | t := 5. ^{#failed. ec. t}'.
	self assert: m numArgs equals: 1.
	self assert: m numTemps equals: 2.
	self assert: m primitiveNumber equals: (self primitiveNumberOf: 'intAdd').
	self assert: (m primitive bitAnd: VMConstants cmPrimErrorFlag) equals: VMConstants cmPrimErrorFlag.
	self assert: (m tempNamesAt: 0) equals: #('x' 'ec' 't').
	result := CompilerTestSubject new tPrimEc: 3.
	self assert: result first == #failed.
	self assert: result last equals: 5
!
testPrimitiveByNumber
	| n m |
	n := self primitiveNumberOf: 'class'.
	m := self compile: 'tPrimNum <primitive: ' , n printString , '> ^#failed'.
	self assert: m primitive equals: n.
	self assert: CompilerTestSubject new tPrimNum == CompilerTestSubject
!
testUnknownPrimitive
	| e |
	e := self errorIn: 'tPrimBad <primitive: ''noSuchPrimitive''> ^1'.
	self assert: e notNil.
	self assert: (e messageText includesSubstring: 'Unknown primitive')
!
testPragmas
	| m |
	m := self compile: 'tPragmas <foo: 1 bar: #baz> <qux> ^1'.
	self assert: m pragmas size equals: 2.
	self assert: m pragmas first selector == #foo:bar:.
	self assert: m pragmas first arguments equals: #(1 #baz).
	self assert: m pragmas last selector == #qux.
	self assert: m primitive equals: 0
! !

!CompilerTest methodsFor: 'tests - workspace'!
testWorkspaceBindings
	| bindings |
	bindings := Dictionary new.
	self assert: (Compiler evaluate: 'x := 3' for: nil bindings: bindings) equals: 3.
	self assert: (Compiler evaluate: 'x + 1' for: nil bindings: bindings) equals: 4.
	self assert: (bindings at: #x) value equals: 3.
	self assert: (Compiler evaluate: 'y' for: nil bindings: bindings) isNil.
	self assert: (bindings includesKey: #y).
	Compiler evaluate: 'blk := [x := x + 1]' for: nil bindings: bindings.
	self assert: (Compiler evaluate: 'blk value. blk value. x' for: nil bindings: bindings) equals: 5
!
testWorkspaceUndeclaredGlobal
	| e |
	e := [Compiler evaluate: 'Zork123' for: nil bindings: Dictionary new. nil]
		on: SyntaxError
		do: [:ex | ex return: ex].
	self assert: e notNil.
	self assert: (e messageText includesSubstring: 'Undeclared').
	self assert: e position equals: 1
!
testDoItWithoutBindingsRejectsUnknown
	| e |
	e := [Compiler evaluate: 'zork := 3'. nil] on: SyntaxError do: [:ex | ex return: ex].
	self assert: e notNil
! !

!CompilerTest methodsFor: 'tests - errors'!
testSyntaxErrorPositions
	| e |
	e := self errorIn: 'foo ^3 +'.
	self assert: e position equals: 9.
	self assert: (e messageText includesSubstring: 'expected').
	e := self errorIn: 'foo ^(3'.
	self assert: e position equals: 8.
	self assert: (e messageText includesSubstring: ')').
	e := self errorIn: 'foo ^3 ]'.
	self assert: e position equals: 8.
	e := self errorIn: 'foo ^zork'.
	self assert: e position equals: 6.
	self assert: (e messageText includesSubstring: 'zork').
	e := self errorIn: 'foo: x x := 3'.
	self assert: e position equals: 8.
	e := self errorIn: 'foo ^''abc'.
	self assert: e position equals: 6.
	e := self errorIn: 'foo ^#(1 2'.
	self assert: e position equals: 11.
	e := self errorIn: 'foo | a a | ^a'.
	self assert: e position equals: 9.
	e := self errorIn: 'foo ^1. 2'.
	self assert: e position equals: 9.
	e := self errorIn: 'foo self := 3'.
	self assert: e position equals: 5.
	e := self errorIn: 'foo ^[:x x]'.
	self assert: e position equals: 10.
	e := self errorIn: 'foo ^{1. 2'.
	self assert: e position equals: 11.
	e := self errorIn: '3 foo'.
	self assert: e position equals: 1.
	e := self errorIn: 'foo ^"unterminated'.
	self assert: e position equals: 6
!
testSyntaxErrorCarriesSource
	| e |
	e := self errorIn: 'foo ^3 +'.
	self assert: e source equals: 'foo ^3 +'
!
testValidMethodHasNoError
	self assert: (self errorIn: 'foo: x | t | t := x. ^[:y | t + y] value: 1') isNil
! !

!CompilerTest methodsFor: 'tests - bytecodes'!
testBytecodesInstVar
	| m |
	m := self compile: 'tBc1 ^a'.
	self assert: m bytecodes asArray equals: #(16r10 16r79).
	m := self compile: 'tBc2: x a := x'.
	self assert: m bytecodes asArray equals: #(16r00 16r85 16r00 16r78 16r7A).
	self assert: m numArgs equals: 1.
	self assert: m numTemps equals: 0.
	self assert: m frameSize equals: 2
!
testBytecodesConstants
	| m |
	m := self compile: 'tBc3 ^1000'.
	self assert: m bytecodes asArray equals: #(16r93 16rE8 16r03 16r79).
	m := self compile: 'tBc3b ^-2'.
	self assert: m bytecodes asArray equals: #(16r93 16rFE 16rFF 16r79).
	m := self compile: 'tBc3c ^#(1 2)'.
	self assert: m bytecodes asArray equals: #(16r20 16r79).
	self assert: m literals equals: #(#(1 2))
!
testBytecodesSends
	| m |
	m := self compile: 'tBc4 ^self foo'.
	self assert: m bytecodes asArray equals: #(16r70 16rC0 16r79).
	self assert: m literals equals: #(#foo).
	m := self compile: 'tBc5 ^3 + 4'.
	self assert: m bytecodes asArray equals: #(16r93 3 0 16r93 4 0 16rA0 16r79).
	m := self compile: 'tBc5b ^self foo: 1 bar: 2 baz: 3'.
	self assert: m bytecodes asArray equals: #(16r70 16r75 16r93 2 0 16r93 3 0 16r8D 0 3 16r79).
	m := self compile: 'tBc7 ^super greeting' in: CompilerTestSubjectChild.
	self assert: m bytecodes asArray equals: #(16r70 16r8E 0 0 16r79)
!
testBytecodesBlocks
	| m |
	m := self compile: 'tBc6 ^[:x | x]'.
	self assert: m bytecodes asArray equals: #(16r8F 1 0 2 0 2 16r00 16r7B 16r79).
	self assert: m frameSize equals: 1.
	m := self compile: 'tBc8 | t | ^[t := 1. t]'.
	self assert: m bytecodes asArray equals: #(16r8F 0 0 1 0 8 16r75 16r8C 1 0 16r8A 1 0 16r7B 16r79).
	self assert: m numTemps equals: 1.
	self assert: m frameSize equals: 2.
	m := self compile: 'tBc9 ^[^1]'.
	self assert: m bytecodes asArray equals: #(16r8F 0 0 1 0 2 16r75 16r7C 16r79)
!
testBytecodesMisc
	| m |
	m := self compile: 'tBc10 ^thisContext'.
	self assert: m bytecodes asArray equals: #(16r76 16r79).
	m := self compile: 'tBc11 ^self foo; bar'.
	self assert: m bytecodes asArray equals: #(16r70 16r77 16rC0 16r78 16rC1 16r79).
	m := self compile: 'tBc12 ^Object'.
	self assert: m bytecodes asArray equals: #(16r40 16r79).
	self assert: m literals first == (Smalltalk associationAt: #Object).
	m := self compile: 'tBc13 ^{1. 2}'.
	self assert: m bytecodes asArray equals: #(16r75 16r93 2 0 16r94 2 16r79).
	m := self compile: 'tBc14'.
	self assert: m bytecodes asArray equals: #(16r7A)
!
testDisassembler
	| m |
	m := self compile: 'tDis: x | t | t := [:y | t := y + x. t]. Object. Shared := nil. ^x ifTrue: [super foo: 1000 bar: #a] ifFalse: [{t value: -2. thisContext. self == nil}]' in: CompilerTestSubjectChild.
	self assert: m symbolic equals: '   0 <8F 01 00 03 00 0C> pushClosure numArgs: 1 numTemps: 0 frameSize: 3 to: 18
   6 <00> pushTemp: 0
   7 <8A 01 00> pushOuterTemp: 0 depth: 1
  10 <A0> send: #+
  11 <8C 01 01> popIntoOuterTemp: 1 depth: 1
  14 <8A 01 01> pushOuterTemp: 1 depth: 1
  17 <7B> blockReturnTop
  18 <61> popIntoTemp: 1
  19 <40> pushLitVar: #Object
  20 <78> pop
  21 <73> pushConstant: nil
  22 <89 01> popIntoLitVar: #Shared
  24 <00> pushTemp: 0
  25 <92 0B 00> jumpFalseTo: 39
  28 <70> pushSelf
  29 <93 E8 03> pushConstant: 1000
  32 <22> pushConstant: #a
  33 <8E 03 02> superSend: #foo:bar: numArgs: 2
  36 <90 0B 00> jumpTo: 50
  39 <01> pushTemp: 1
  40 <93 FE FF> pushConstant: -2
  43 <B6> send: #value:
  44 <76> pushThisContext
  45 <70> pushSelf
  46 <73> pushConstant: nil
  47 <B3> send: #==
  48 <94 03> makeArray: 3
  50 <79> returnTop
'.
	self assert: (Disassembler disassemble: (CompiledMethod basicNew bytecodes: (ByteArray with: 16rFF with: 16r7A); literals: #(); yourself)) equals: '   0 <FF> unknown
   1 <7A> returnSelf
'
!
testLongForms
	"More than 16 temps and 32 literals use the long push/store/send forms."
	| source m result |
	source := WriteStream on: String new.
	source nextPutAll: 'tLong | '.
	0 to: 19 do: [:i | source nextPutAll: 't' , i printString , ' '].
	source nextPutAll: '| '.
	0 to: 19 do: [:i | source nextPutAll: 't' , i printString , ' := #s' , i printString , '. '].
	source nextPutAll: '^{'.
	0 to: 19 do: [:i | source nextPutAll: 't' , i printString , '. '].
	20 to: 39 do: [:i | source nextPutAll: '#s' , i printString , '. '].
	source nextPutAll: '#s0 yourself}'.
	m := self compile: source contents.
	self assert: m numTemps equals: 20.
	self assert: (m bytecodes includes: 16r87).
	self assert: (m bytecodes includes: 16r80).
	self assert: (m bytecodes includes: 16r82).
	self assert: (m bytecodes includes: 16r8D).
	result := CompilerTestSubject new tLong.
	self assert: result size equals: 41.
	0 to: 39 do: [:i | self assert: (result at: i + 1) == ('s' , i printString) asSymbol].
	self assert: result last == #s0
!
testMethodFields
	| m |
	m := self compile: 'tFields: x ^x'.
	self assert: m selector == #tFields:.
	self assert: m methodClass == CompilerTestSubject.
	self assert: m category equals: 'compiler tests'.
	self assert: m source equals: 'tFields: x ^x'.
	self assert: (CompilerTestSubject compiledMethodAt: #tFields:) == m
!
testSymbolic
	| m |
	m := self compile: 'tSym: x ^[:y | x + y] value: 1'.
	self assert: (m symbolic includesSubstring: 'pushClosure').
	self assert: (m symbolic includesSubstring: 'pushOuterTemp: 0 depth: 1').
	self assert: (m symbolic includesSubstring: 'blockReturnTop').
	self assert: (m symbolic includesSubstring: 'returnTop')
! !

!CompilerTest methodsFor: 'tests - file in'!
testFileInString
	| source probe |
	source := 'Object subclass: #CompilerFileInProbe
	instanceVariableNames: ''x''
	classVariableNames: ''''
	package: ''Tests-Compiler''!!

!!CompilerFileInProbe methodsFor: ''accessing''!!
x
	^x
!!
x: anObject
	x := anObject
!! !!

!!CompilerFileInProbe class methodsFor: ''instance creation''!!
with: anObject
	^self new x: anObject; yourself
!! !!
'.
	Compiler fileInString: source.
	probe := Smalltalk at: #CompilerFileInProbe.
	[self assert: (probe with: 42) x equals: 42.
	 self assert: (probe compiledMethodAt: #x:) category equals: 'accessing'.
	 self assert: (probe compiledMethodAt: #x:) source equals: 'x: anObject
	x := anObject']
		ensure: [probe removeFromSystem]
! !

!CompilerTest methodsFor: 'tests - debugger support'!
testEveryStopIsMapped
	| sources m |
	sources := #(
		'tStop1 | s | s := 0. 1 to: 5 do: [:i | | t | t := i. s := s + t]. ^s'
		'tStop2: n | s | s := 0. 1 to: n by: 2 do: [:i | s := s + i]. n timesRepeat: [s := s + 1]. ^s'
		'tStop3: x ^(x ifNil: [0] ifNotNil: [:y | y + 1]) + (x ifNotNil: [:y | y]) + (x ifNotNil: [:y | y] ifNil: [1])'
		'tStop4: x x ifNotNil: [:y | a := y]. [:z | | w | w := z. ^w] value: x. ^self'
		'tStop5 a := b := 3. Shared := a. [a < 5] whileTrue: [a := a + 1]. ^{a. b}').
	sources do: [:each |
		m := self compile: each.
		self assert: (self unmappedStopsIn: m) isEmpty description: each].
	m := self compile: 'tStop6 | sum | sum := 0. 1 to: 5 do: [:i | sum := sum + i]. ^sum'.
	self assert: CompilerTestSubject new tStop6 equals: 15.
	"The stores of the loop counter i (temp 1) map to the whole to:do: expression."
	m instructionsDo: [:pc :op |
		op = 16r61 ifTrue: [
			self assert: (m sourceIntervalAt: pc) asArray
				equals: ((m source indexOf: $1) to: (m source indexOf: $])) asArray]]
!
testSourceMapSends
	| m |
	m := self compile: 'tMap ^self foo: 3 + 4'.
	self assert: m sourceMap equals: #(7 17 21 8 7 21 9 6 21).
	self assert: (m sourceIntervalAt: 0) asArray equals: (17 to: 21) asArray.
	self assert: (m sourceIntervalAt: 8) asArray equals: (7 to: 21) asArray.
	self assert: (m sourceIntervalBefore: 9) asArray equals: (7 to: 21) asArray
!
testSourceMapStores
	| m |
	m := self compile: 'tMapAssign | t | t := 3. ^t'.
	self assert: m sourceMap equals: #(3 18 23 5 26 27)
!
testSourceMapBlocks
	| m |
	m := self compile: 'tMapBlock ^[:x | x]'.
	self assert: m sourceMap equals: #(0 12 19 7 19 19 8 11 19)
!
testSourceMapImplicitReturn
	| m |
	m := self compile: 'tMapSelf a foo'.
	self assert: m sourceMap equals: #(1 10 14 3 14 14)
!
testSourceMapLoopWithoutSends
	"An interrupt stops [true] whileTrue at its jump: it maps to the loop."
	| m |
	m := self compile: 'tMapLoop [true] whileTrue. ^3'.
	self assert: (m sourceIntervalAt: 0) asArray equals: (10 to: 25) asArray
!
testTempNames
	| m |
	m := self compile: 'tTemps: a | b | ^[:c | | d | d := c. b := d. [a] value] value: 1'.
	self assert: (m tempNamesAt: 0) equals: #('a' 'b').
	self assert: (m tempNamesAt: 6) equals: #('c' 'd').
	m := self compile: 'tTempsHoisted 1 to: 2 do: [:i | | t | t := i]'.
	self assert: (m tempNamesAt: 0) equals: #('i' 't')
!
testTempNamesForContext
	| m ctxs |
	m := self compile: 'tCtx | x | x := 1. ^{thisContext. [:y | thisContext] value: 2}'.
	ctxs := CompilerTestSubject new tCtx.
	self assert: (m tempNamesForContext: ctxs first) equals: #('x').
	self assert: (m tempNamesForContext: ctxs last) equals: #('y')
! !
