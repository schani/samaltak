Object subclass: #TCodeGenerator
	instanceVariableNames: 'translator function cModule locals usedNames block frame env labelCounter interpreterLoop opsTable nextExpression labelParameters inferring'
	classVariableNames: 'ControlSelectors'
	package: 'VM-Translator'!

TCodeGenerator comment: 'I translate one C function: a TFunction of kind #function, with the inline methods, blocks and (for the interpreter function) bytecode handlers and labels it expands. I walk the Smalltalk syntax tree with an environment (TEnv) and a frame stack (TFrame) and build a typed C syntax tree (CNode), folding constants and dropping dead branches as I go, so a specialized handler''s case analysis on its bytecode leaves only its own code.

Statements go into block (the current CBlock); expressions never hoist statements: an inline expansion or a control structure that needs statements in expression position becomes a GNU statement expression.'!

!TCodeGenerator class methodsFor: 'private'!
controlSelectors
	ControlSelectors isNil ifTrue: [
		ControlSelectors := #(#ifTrue: #ifFalse: #ifTrue:ifFalse: #ifFalse:ifTrue: #and: #or: #whileTrue: #whileFalse: #whileTrue #whileFalse #to:do: #to:by:do: #timesRepeat: #repeat #caseOf: #caseOf:otherwise:) asSet].
	^ControlSelectors
! !

!TCodeGenerator class methodsFor: 'instance creation'!
translator: aTranslator inferring: aBoolean
	^self new setTranslator: aTranslator inferring: aBoolean
! !

!TCodeGenerator methodsFor: 'initialization'!
setTranslator: aTranslator inferring: aBoolean
	translator := aTranslator.
	inferring := aBoolean
! !

!TCodeGenerator methodsFor: 'generating'!
generate: aTFunction
	"Answer the TCFunction of aTFunction (a #function). Inferring, it only feeds the signatures (docs/lowtalk.md, Functions): a statement that cannot be translated yet is left out, the function runs again when something it depends on changes."
	| body result |
	function := aTFunction.
	cModule := aTFunction module.
	locals := OrderedCollection new.
	usedNames := Set new.
	labelCounter := 0.
	labelParameters := Dictionary new.
	interpreterLoop := self callsDispatchLoop: aTFunction.
	frame := TFrame kind: #function function: aTFunction module: cModule parent: nil.
	frame returnType: aTFunction returnType.
	env := frame env.
	aTFunction arguments doWithIndex: [:arg :i |
		| cName type |
		cName := self reserveName: (LowtalkNames snake: arg).
		type := aTFunction parameterTypeAt: i.
		(inferring or: [type notNil]) ifFalse: [self error: 'nothing gives the type of parameter ' , arg , ': no call site (declare it with <var: #' , arg , ' type: ''T''>)' node: nil].
		env at: arg put: (TBinding local: cName type: type)].
	interpreterLoop ifTrue: [self declareRegisters].
	body := CBlock new.
	block := body.
	self declareTemporariesOf: aTFunction in: frame.
	aTFunction statements do: [:s | self statement: s].
	inferring ifTrue: [^nil].
	(aTFunction returnType isVoid not and: [body endsControlFlow not]) ifTrue: [
		self error: 'missing return at the end of a function returning ' , aTFunction returnType name node: nil].
	"A thread's endless loop at the end: say so, or gcc reports a function returning non-void without a return statement."
	(aTFunction returnType isVoid not and: [body statements notEmpty and: [
		(body statements last isKindOf: CWhile) and: [body statements last endsControlFlow]]]) ifTrue: [
			body add: (CExprStatement expression: (CRaw text: '__builtin_unreachable()' type: (translator registry at: 'void')))].
	result := TCFunction new
		setFunction: aTFunction
		locals: locals
		body: body.
	^result
! !

!TCodeGenerator methodsFor: 'names'!
reserveName: aString
	| name n |
	name := aString.
	n := 1.
	[usedNames includes: name] whileTrue: [
		n := n + 1.
		name := aString , '_' , n printString].
	usedNames add: name.
	^name
!
newLocal: aString type: aCType
	"Declare a new local of the C function; answer a reference to it."
	| name |
	name := self reserveName: aString.
	locals add: (CDeclaration name: name type: aCType initializer: nil).
	^CVarRef name: name type: aCType
!
declareLocal: aTBinding type: aCType
	"Give a lazily typed local its type at its first assignment."
	aTBinding type: aCType.
	locals add: (CDeclaration name: aTBinding cName type: aCType initializer: nil)
!
newLabel: aString
	labelCounter := labelCounter + 1.
	^self reserveName: aString
!
declareTemporariesOf: aTFunction in: aTFrame
	aTFunction temporaries do: [:t | self declareTemporary: t function: aTFunction in: aTFrame env]
!
declareTemporary: aString function: aTFunction in: aTEnv
	| typeName cName binding |
	cName := self reserveName: (LowtalkNames snake: aString).
	binding := TBinding local: cName type: nil.
	typeName := aTFunction declaredTypeOf: aString.
	typeName notNil ifTrue: [self declareLocal: binding type: (translator registry parse: typeName)].
	aTEnv at: aString put: binding
! !

!TCodeGenerator methodsFor: 'errors'!
error: aString node: aNodeOrNil
	frame function == function ifTrue: [^translator error: aString in: function node: aNodeOrNil].
	^translator error: aString , ' (inlined into ' , function printString , ')' in: frame function node: aNodeOrNil
! !

!TCodeGenerator methodsFor: 'statements'!
statement: aNode
	inferring ifFalse: [^self translateStatement: aNode].
	[self translateStatement: aNode] on: Error do: [:e | e return: nil]
!
translateStatement: aNode
	aNode isReturn ifTrue: [^self returnStatement: aNode].
	aNode isAssignment ifTrue: [^self assignment: aNode valueWanted: false].
	aNode isMessage ifTrue: [
		| e |
		e := self send: aNode valueWanted: false.
		(e notNil and: [e isPure not]) ifTrue: [block add: (CExprStatement expression: e)].
		^self].
	aNode isCascade ifTrue: [^self cascade: aNode].
	(aNode isVariable or: [aNode isLiteral]) ifTrue: [^self].
	self error: 'not a Lowtalk statement' node: aNode
!
statements: aCollection
	aCollection do: [:s | self statement: s]
!
cascade: aCascadeNode
	aCascadeNode messages do: [:m | self statement: m]
!
withBlock: aCBlock do: aBlock
	| saved |
	saved := block.
	block := aCBlock.
	^aBlock ensure: [block := saved]
!
withEnv: aTEnv frame: aTFrame do: aBlock
	| savedEnv savedFrame |
	savedEnv := env.
	savedFrame := frame.
	env := aTEnv.
	frame := aTFrame.
	^aBlock ensure: [env := savedEnv. frame := savedFrame]
! !

!TCodeGenerator methodsFor: 'returns'!
returnStatement: aReturnNode
	"A return leaves the frame the method was written in (blocks return from their home)."
	| home |
	home := frame.
	home kind == #function ifTrue: [^self functionReturn: aReturnNode value].
	home kind == #inline ifTrue: [^self inlineReturn: aReturnNode value frame: home].
	home isInterpreterFrame ifTrue: [^self interpreterReturn: aReturnNode value].
	self error: 'return outside a method' node: aReturnNode
!
functionReturn: aNode
	| e |
	inferring ifTrue: [^self inferReturn: aNode].
	frame returnType isVoid ifTrue: [
		(aNode isVariable and: [aNode isSelf]) ifFalse: [
			aNode isMessage
				ifTrue: [self statement: aNode]
				ifFalse: [
					e := self expression: aNode.
					e isPure ifFalse: [block add: (CExprStatement expression: e)]]].
		block endsControlFlow ifFalse: [block add: (CReturn expression: nil)].
		^self].
	(aNode isVariable and: [aNode isSelf]) ifTrue: [^self error: 'a function returning ' , frame returnType name , ' answers self' node: aNode].
	e := self coerce: (self expressionOrInline: aNode type: frame returnType) to: frame returnType node: aNode.
	block add: (CReturn expression: e)
!
inferReturn: aNode
	"While inferring: a ^expression's value joins the function's result; a ^ of no value (^self, the tail call of a void function: an error in expression:) leaves it as it is."
	| e |
	(aNode isVariable and: [aNode isSelf]) ifTrue: [^self].
	e := self expression: aNode.
	(function signature noteResultType: (self valueType: e) adaptive: (self isAdaptive: e) literal: (self literalValueOf: e)) ifFalse: [
		self error: 'the ^expressions of a function have no common type' node: aNode]
!
inlineReturn: aNode frame: aTFrame
	| e |
	aTFrame noteReturn.
	aTFrame exitDispatches ifTrue: [^self dispatchingReturn: aNode].
	aTFrame valueWanted
		ifTrue: [
			(aNode isVariable and: [aNode isSelf]) ifTrue: [^self error: 'an inline method used for its value answers self' node: aNode].
			e := self expression: aNode.
			self assignResult: e to: aTFrame node: aNode]
		ifFalse: [
			(aNode isVariable and: [aNode isSelf]) ifFalse: [
				aNode isMessage
					ifTrue: [self statement: aNode]
					ifFalse: [
						e := self expression: aNode.
						e isPure ifFalse: [block add: (CExprStatement expression: e)]]]].
	aTFrame exitLabel isNil ifTrue: [aTFrame exitLabel: (self newLabel: 'exit_' , (LowtalkNames functionNameFor: aTFrame function selector))].
	block add: (CGoto label: aTFrame exitLabel)
!
assignResult: aCExpr to: aTFrame node: aNode
	| var |
	var := aTFrame resultVar.
	var type isNil
		ifTrue: [
			| decl |
			decl := locals detect: [:d | d name = var name].
			var type: (self inferredType: aCExpr).
			decl setName: var name type: var type initializer: nil]
		ifFalse: [self checkAssignable: aCExpr to: var type node: aNode].
	block add: (CExprStatement expression: (CBinary operator: '=' left: var right: (self coerce: aCExpr to: var type node: aNode) type: var type))
!
dispatchingReturn: aNode
	"A return from an inline method whose caller's handler ends with it: its effect, then the dispatch."
	(aNode isVariable and: [aNode isSelf]) ifTrue: [^self emitNext].
	(self inlineTailCall: aNode) ifTrue: [^self].
	self statement: aNode.
	block endsControlFlow ifFalse: [self emitNext]
!
inlineTailCall: aNode
	"If aNode is a send of an inline method to self, expand it so that its returns dispatch; answer whether it was."
	| f |
	(aNode isMessage and: [aNode receiver isVariable and: [aNode receiver isSelf]]) ifFalse: [^false].
	f := translator lookup: aNode selector in: frame module.
	(f notNil and: [f kind == #inline]) ifFalse: [^false].
	self inline: f module: (translator moduleFor: f module moduleClass) arguments: aNode arguments node: aNode valueWanted: false dispatching: true.
	block endsControlFlow ifFalse: [self emitNext].
	^true
!
interpreterReturn: aNode
	"In a handler or label: ^self dispatches the next bytecode, ^self aLabel jumps, ^self dispatch: b re-dispatches."
	| f |
	(aNode isVariable and: [aNode isSelf]) ifTrue: [^self emitNext].
	(aNode isMessage and: [aNode receiver isVariable and: [aNode receiver isSelf]]) ifFalse: [
		^self error: 'a handler answers self or jumps (^self aLabel)' node: aNode].
	f := translator lookup: aNode selector in: frame module.
	f isNil ifTrue: [^self error: 'unknown function ' , aNode selector node: aNode].
	(f kind == #label or: [f kind == #handler]) ifTrue: [^self jumpTo: f arguments: aNode arguments node: aNode].
	f kind == #dispatch ifTrue: [
		^block add: (CGoto computed: (CIndex base: opsTable index: (self expression: aNode arguments first) type: self voidPointer))].
	(self inlineTailCall: aNode) ifTrue: [^self].
	self statement: aNode.
	block endsControlFlow ifFalse: [self emitNext]
!
emitNext
	block add: (CGoto computed: (CIndex base: opsTable index: (self expression: nextExpression) type: self voidPointer))
! !

!TCodeGenerator methodsFor: 'assignments'!
assignment: anAssignmentNode valueWanted: aBoolean
	| name binding target value g |
	name := anAssignmentNode variable name.
	binding := env lookup: name.
	binding notNil
		ifTrue: [
			binding kind == #local ifFalse: [^self error: 'cannot assign to ' , name node: anAssignmentNode].
			binding type isNil
				ifTrue: [
					value := self expression: anAssignmentNode value.
					(value isConstant and: [(frame function assignmentCountOf: name) = 1 and: [aBoolean not]]) ifTrue: [
						"assigned once, a constant: no variable (so a specialized handler's case analysis folds)"
						env rebind: name to: (TBinding expression: value).
						^nil].
					self declareLocal: binding type: (self inferredType: value)]
				ifFalse: [value := self expressionOrInline: anAssignmentNode value type: binding type].
			target := binding reference]
		ifFalse: [
			g := self globalNamed: name node: anAssignmentNode.
			value := self expressionOrInline: anAssignmentNode value type: g type.
			target := self globalReference: g].
	self checkAssignable: value to: target type node: anAssignmentNode.
	value := CBinary operator: '=' left: target right: (self coerce: value to: target type node: anAssignmentNode) type: target type.
	aBoolean ifTrue: [^value].
	block add: (CExprStatement expression: value).
	^nil
!
expressionOrInline: aNode type: aCType
	^self expression: aNode
! !

!TCodeGenerator methodsFor: 'expressions'!
expression: aNode
	aNode isLiteral ifTrue: [^self literal: aNode].
	aNode isVariable ifTrue: [^self variable: aNode].
	aNode isAssignment ifTrue: [^self assignment: aNode valueWanted: true].
	aNode isMessage ifTrue: [
		| e |
		e := self send: aNode valueWanted: true.
		(e isNil or: [e type notNil and: [e type isVoid]]) ifTrue: [self error: aNode selector , ' has no value' node: aNode].
		^e].
	aNode isBlock ifTrue: [^self error: 'blocks are only arguments of control structures and inline methods' node: aNode].
	^self error: 'not a Lowtalk expression' node: aNode
!
literal: aLiteralNode
	| v |
	v := aLiteralNode value.
	v isInteger ifTrue: [^self integerConstant: v hex: (self isHexLiteral: aLiteralNode)].
	v isFloat ifTrue: [^CConst value: v type: (translator registry at: 'double')].
	(v == true or: [v == false]) ifTrue: [^CConst value: v type: (translator registry at: 'bool')].
	v isSymbol ifTrue: [^self error: 'symbols are not Lowtalk values' node: aLiteralNode].
	v isString ifTrue: [^CConst value: v type: (translator registry parse: 'char *')].
	v isNil ifTrue: [^self error: 'nil is not Lowtalk: use self null for pointers' node: aLiteralNode].
	v isCharacter ifTrue: [^self error: 'use $c value for a character code' node: aLiteralNode].
	^self error: 'unsupported literal ' , v printString node: aLiteralNode
!
integerConstant: anInteger hex: aBoolean
	| type |
	type := (anInteger between: -16r80000000 and: 16r7FFFFFFF)
		ifTrue: [translator registry at: 'int']
		ifFalse: [
			(anInteger between: -16r8000000000000000 and: 16r7FFFFFFFFFFFFFFF)
				ifTrue: [translator registry at: 'int64_t']
				ifFalse: [translator registry at: 'uint64_t']].
	^CConst value: anInteger type: type hex: aBoolean
!
isHexLiteral: aLiteralNode
	| src |
	src := frame function ast source.
	(src isNil or: [aLiteralNode start isNil]) ifTrue: [^false].
	^(src copyFrom: aLiteralNode start to: (aLiteralNode start + 2 min: src size)) = '16r'
!
variable: aVariableNode
	| name binding |
	name := aVariableNode name.
	(name = 'self' or: [name = 'super']) ifTrue: [^self error: 'self is only a receiver' node: aVariableNode].
	name = 'thisContext' ifTrue: [^self error: 'thisContext is not Lowtalk' node: aVariableNode].
	name = 'nil' ifTrue: [^self error: 'nil is not Lowtalk: use self null for pointers' node: aVariableNode].
	name = 'true' ifTrue: [^CConst value: true type: (translator registry at: 'bool')].
	name = 'false' ifTrue: [^CConst value: false type: (translator registry at: 'bool')].
	binding := env lookup: name.
	binding notNil ifTrue: [^self bindingValue: binding node: aVariableNode].
	^self nonLocal: name node: aVariableNode
!
bindingValue: aTBinding node: aNode
	aTBinding kind == #expr ifTrue: [^aTBinding expression].
	aTBinding kind == #local ifTrue: [
		aTBinding type isNil ifTrue: [^self error: aNode name , ' is used before it is assigned (declare it with <var: #' , aNode name , ' type: ''T''>)' node: aNode].
		^aTBinding reference].
	^self error: 'a block is only an argument here' node: aNode
!
nonLocal: aString node: aNode
	"A module variable or a constant."
	| g value |
	g := frame module globalNamed: aString.
	g notNil ifTrue: [
		g isModuleReference ifTrue: [^self error: aString , ' is a module, not a value' node: aNode].
		^self globalReference: g].
	value := self constantNamed: aString ifAbsent: [^self error: 'unknown variable ' , aString node: aNode].
	^value
!
globalNamed: aString node: aNode
	| g |
	g := frame module globalNamed: aString.
	g isNil ifTrue: [^self error: 'unknown variable ' , aString node: aNode].
	g isModuleReference ifTrue: [^self error: aString , ' is a module' node: aNode].
	^g
!
globalReference: aTGlobal
	aTGlobal isRegister
		ifTrue: [
			interpreterLoop ifFalse: [^self error: aTGlobal name , ' is a register of the interpreter loop' node: nil].
			^CVarRef name: aTGlobal cName type: aTGlobal type].
	inferring ifFalse: [aTGlobal noteUsedFrom: cModule].
	^CVarRef name: aTGlobal cName type: aTGlobal type
!
constantNamed: aString ifAbsent: aBlock
	"A class variable of the module's class or its superclasses (VMConstants): a #define."
	| value |
	value := translator constantNamed: aString in: frame module moduleClass ifAbsent: [^aBlock value].
	value isInteger ifFalse: [^aBlock value].
	^(self integerConstant: value hex: false) symbol: aString
! !

!TCodeGenerator methodsFor: 'sends'!
send: aMessageNode valueWanted: aBoolean
	| sel rcv binding |
	sel := aMessageNode selector.
	rcv := aMessageNode receiver.
	(rcv isLiteral and: [rcv value isCharacter and: [sel == #value]]) ifTrue: [
		^CConst value: rcv value value type: (translator registry at: 'int')].
	(self class controlSelectors includes: sel) ifTrue: [^self control: aMessageNode valueWanted: aBoolean].
	rcv isVariable ifTrue: [
		(rcv isSelf or: [rcv isSuper]) ifTrue: [^self send: sel to: frame module arguments: aMessageNode arguments node: aMessageNode valueWanted: aBoolean].
		binding := env lookup: rcv name.
		(binding notNil and: [binding isBlock]) ifTrue: [^self valueOfBlock: binding selector: sel arguments: aMessageNode arguments node: aMessageNode valueWanted: aBoolean].
		binding isNil ifTrue: [
			| g |
			g := frame module globalNamed: rcv name.
			(g notNil and: [g isModuleReference]) ifTrue: [
				^(g referencedModule inheritsFrom: CLibrary)
					ifTrue: [self externSend: sel library: g referencedModule arguments: aMessageNode arguments node: aMessageNode]
					ifFalse: [self send: sel to: (translator moduleFor: g referencedModule) arguments: aMessageNode arguments node: aMessageNode valueWanted: aBoolean]]]].
	^self valueSend: aMessageNode valueWanted: aBoolean
!
send: aSelector to: aTModule arguments: argNodes node: aNode valueWanted: aBoolean
	| f |
	f := translator lookup: aSelector in: aTModule.
	f isNil ifTrue: [^self error: aTModule name , ' has no function ' , aSelector node: aNode].
	f kind == #intrinsic ifTrue: [^self intrinsic: aSelector arguments: argNodes node: aNode valueWanted: aBoolean].
	f kind == #function ifTrue: [^self call: f arguments: argNodes node: aNode].
	f kind == #inline ifTrue: [^self inline: f module: (translator moduleFor: f module moduleClass) arguments: argNodes node: aNode valueWanted: aBoolean].
	f kind == #currentBytecode ifTrue: [
		frame bytecode notNil ifTrue: [^self integerConstant: frame bytecode hex: true].
		^self inline: f module: f module arguments: argNodes node: aNode valueWanted: aBoolean].
	f kind == #dispatchLoop ifTrue: [
		interpreterLoop ifFalse: [^self error: 'dispatchLoop outside the interpreter function' node: aNode].
		self dispatchLoop: f.
		^nil].
	^self error: aSelector , ' (' , f kind , ') is only a jump at the end of a handler: ^self ' , aSelector node: aNode
!
call: aTFunction arguments: argNodes node: aNode
	| args |
	inferring ifTrue: [aTFunction signature addDependent: function] ifFalse: [aTFunction noteCalledFrom: cModule].
	args := OrderedCollection new.
	argNodes doWithIndex: [:a :i |
		| e t |
		e := self expression: a.
		inferring ifTrue: [self note: e argument: i of: aTFunction signature node: a].
		t := aTFunction parameterTypeAt: i.
		t notNil ifTrue: [
			self checkAssignable: e to: t node: a.
			e := self coerce: e to: t node: a].
		args add: e].
	^(CCall function: aTFunction cName arguments: args type: aTFunction returnType)
		noReturn: (aTFunction hasPragma: #noreturn);
		yourself
!
note: aCExpr argument: anInteger of: aTSignature node: aNode
	(aTSignature noteArgument: anInteger type: (self valueType: aCExpr) adaptive: (self isAdaptive: aCExpr) literal: (self literalValueOf: aCExpr)) ifFalse: [
		self error: 'the arguments at the call sites have no common type (' , (aTSignature parameterTypeAt: anInteger) name , ' and ' , (self valueType: aCExpr) name , ')' node: aNode]
!
literalValueOf: aCExpr
	"The integer an adaptive constant is; nil otherwise."
	^(aCExpr isConstant and: [aCExpr value isInteger]) ifTrue: [aCExpr value] ifFalse: [nil]
!
isAdaptive: aCExpr
	"A literal or named constant takes the type of whatever it joins with; one that is cast has its own."
	| v |
	aCExpr isConstant ifFalse: [^false].
	v := aCExpr value.
	v isNil ifTrue: [^true].
	v isInteger ifTrue: [^aCExpr type == (self integerConstant: v hex: false) type].
	^v isFloat
!
externSend: aSelector library: aLibraryClass arguments: argNodes node: aNode
	| ext ftype args |
	ext := translator externFor: aSelector library: aLibraryClass.
	translator noteLibraryCalled: aLibraryClass.
	ext kind == #variable ifTrue: [^CVarRef name: ext cName type: ext type].
	ext kind == #macro ifTrue: [^(CRaw pureText: ext cName type: ext type)].
	ftype := ext type.
	(ftype isVariadic not and: [argNodes size ~= ftype parameterTypes size]) ifTrue: [
		^self error: ext cName , ' takes ' , ftype parameterTypes size printString , ' arguments' node: aNode].
	args := OrderedCollection new.
	argNodes doWithIndex: [:a :i |
		| e |
		e := self expression: a.
		i <= ftype parameterTypes size
			ifTrue: [
				self checkAssignable: e to: (ftype parameterTypes at: i) node: a.
				e := self coerce: e to: (ftype parameterTypes at: i) node: a]
			ifFalse: [e := self variadicArgument: e].
		args add: e].
	^(CCall function: ext cName arguments: args type: ftype returnType)
		noReturn: ext isNoReturn;
		yourself
!
varargBits: aCExpr
	"A double's bits, an integer or bool converted (C sign-extends a signed one), a pointer through uintptr_t."
	| t u64 |
	t := self valueType: aCExpr.
	u64 := translator registry at: 'uint64_t'.
	t isFloat ifTrue: [^CCall function: 'lt_bits_of_double' arguments: (Array with: (self cast: aCExpr to: (translator registry at: 'double'))) type: u64].
	t isPointer ifTrue: [^self cast: (self cast: aCExpr to: (translator registry at: 'uintptr_t')) to: u64].
	^self cast: aCExpr to: u64
!
variadicArgument: aCExpr
	"A 64-bit integer passed to ... (printf's %lld, %llu, %llx) as long long: what int64_t is on macOS, while on Linux it is long."
	| t |
	t := self valueType: aCExpr.
	(#('int64_t' 'uint64_t' 'oop') includes: t name) ifFalse: [^aCExpr].
	^self cast: aCExpr to: (translator registry at: (t isSigned ifTrue: ['long long'] ifFalse: ['unsigned long long']))
! !

!TCodeGenerator methodsFor: 'inlining'!
inline: aTFunction module: aTModule arguments: argNodes node: aNode valueWanted: aBoolean
	^self inline: aTFunction module: aTModule arguments: argNodes node: aNode valueWanted: aBoolean dispatching: false
!
inline: aTFunction module: aTModule arguments: argNodes node: aNode valueWanted: aBoolean dispatching: isDispatching
	"Expand aTFunction here. Arguments that are pure expressions are substituted, blocks are inlined where they are evaluated, arguments it never reads are evaluated as statements, other arguments go through a local. If isDispatching, the expansion ends a handler: its returns dispatch."
	| f stmts result body |
	f := TFrame kind: #inline function: aTFunction module: aTModule parent: frame.
	f valueWanted: aBoolean.
	f exitDispatches: isDispatching.
	aTFunction arguments with: argNodes do: [:name :arg |
		arg isBlock
			ifTrue: [f env at: name put: (TBinding block: arg frame: frame env: env)]
			ifFalse: [
				(aTFunction reads: name)
					ifFalse: [self statement: arg]
					ifTrue: [
						| e |
						e := self expression: arg.
						(e isPure and: [e isConstant or: [e isVariable]])
							ifTrue: [f env at: name put: (TBinding expression: e)]
							ifFalse: [
								| tmp |
								tmp := self newLocal: (LowtalkNames snake: name) type: (self valueType: e).
								block add: (CExprStatement expression: (CBinary operator: '=' left: tmp right: e type: tmp type)).
								f env at: name put: (TBinding expression: tmp)]]]].
	stmts := aTFunction statements.
	"^expression alone: an expression"
	(aBoolean and: [stmts size = 1 and: [stmts first isReturn and: [aTFunction temporaries isEmpty]]]) ifTrue: [
		^self withEnv: f env frame: f do: [self expression: stmts first value]].
	(aBoolean not and: [stmts size = 1 and: [stmts first isReturn not and: [aTFunction temporaries isEmpty]]]) ifTrue: [
		self withEnv: f env frame: f do: [self statement: stmts first].
		^nil].
	body := CBlock new.
	aBoolean ifTrue: [f resultVar: (self newLocal: 'r_' , (LowtalkNames functionNameFor: aTFunction selector) type: nil)].
	self withBlock: body do: [
		self withEnv: f env frame: f do: [
			self declareTemporariesOf: aTFunction in: f.
			stmts doWithIndex: [:s :i |
				(i = stmts size and: [s isReturn])
					ifTrue: [self finalInlineReturn: s value frame: f]
					ifFalse: [self statement: s]]]].
	f exitLabel notNil ifTrue: [body add: (CLabel name: f exitLabel)].
	aBoolean ifFalse: [
		block add: body.
		^nil].
	(stmts isEmpty or: [stmts last isReturn not]) ifTrue: [
		f returnCount = 0 ifTrue: [^self error: aTFunction selector , ' answers no value' node: aNode]].
	result := f resultVar.
	result type isNil ifTrue: [^self error: aTFunction selector , ' answers no value' node: aNode].
	^CStatementExpr block: body result: result type: result type
!
finalInlineReturn: aNode frame: aTFrame
	"The last statement: no jump needed."
	| e |
	aTFrame noteReturn.
	aTFrame exitDispatches ifTrue: [^self dispatchingReturn: aNode].
	aTFrame valueWanted ifFalse: [
		(aNode isVariable and: [aNode isSelf]) ifTrue: [^self].
		^self statement: aNode].
	(aNode isVariable and: [aNode isSelf]) ifTrue: [^self error: 'an inline method used for its value answers self' node: aNode].
	e := self expression: aNode.
	self assignResult: e to: aTFrame node: aNode
!
valueOfBlock: aTBinding selector: aSelector arguments: argNodes node: aNode valueWanted: aBoolean
	"aBlock value / value: x ... where aBlock is a block argument of an inline method."
	| args |
	(#(#value #value: #value:value: #value:value:value: #value:value:value:value:) includes: aSelector)
		ifFalse: [^self error: 'a block argument only understands value...' node: aNode].
	args := argNodes collect: [:a | self expression: a].
	^self inlineBlock: aTBinding blockNode frame: aTBinding frame env: aTBinding env arguments: args valueWanted: aBoolean node: aNode
!
inlineBlock: aBlockNode frame: aTFrame env: aTEnv arguments: argExprs valueWanted: aBoolean node: aNode
	"Emit aBlockNode's statements here, in the frame and environment it was written in; answer its value."
	| childEnv value body |
	aBlockNode arguments size = argExprs size ifFalse: [^self error: 'wrong number of block arguments' node: aNode].
	childEnv := aTEnv child.
	aBlockNode arguments with: argExprs do: [:argNode :e |
		childEnv at: argNode name put: (TBinding expression: e)].
	aBoolean ifFalse: [
		self withEnv: childEnv frame: aTFrame do: [
			aBlockNode temporaries do: [:t | self declareTemporary: t name function: aTFrame function in: childEnv].
			self statements: aBlockNode statements].
		^nil].
	body := CBlock new.
	value := self withBlock: body do: [
		self withEnv: childEnv frame: aTFrame do: [
			aBlockNode temporaries do: [:t | self declareTemporary: t name function: aTFrame function in: childEnv].
			self blockValue: aBlockNode]].
	body isEmpty ifTrue: [^value].
	value isNil ifTrue: [block add: body. ^nil].
	^CStatementExpr block: body result: value type: value type
!
blockValue: aBlockNode
	"Emit all but the last statement of aBlockNode into block; answer the last one's value (nil if it returns)."
	| stmts last |
	stmts := aBlockNode statements.
	stmts isEmpty ifTrue: [^self error: 'an empty block has no value' node: aBlockNode].
	stmts allButLast do: [:s | self statement: s].
	last := stmts last.
	last isReturn ifTrue: [self statement: last. ^nil].
	^self expression: last
!
blockBody: aBlockNode arguments: argExprs
	"Answer a CBlock with aBlockNode's statements (its value ignored)."
	| body |
	body := CBlock new.
	self withBlock: body do: [
		self inlineBlock: aBlockNode frame: frame env: env arguments: argExprs valueWanted: false node: aBlockNode].
	^body
!
blockValue: aBlockNode into: aCBlock
	"Emit aBlockNode (no arguments) into aCBlock, answer its value."
	^self withBlock: aCBlock do: [
		| childEnv |
		childEnv := env child.
		self withEnv: childEnv frame: frame do: [
			aBlockNode temporaries do: [:t | self declareTemporary: t name function: frame function in: childEnv].
			self blockValue: aBlockNode]]
! !

!TCodeGenerator methodsFor: 'control structures'!
control: aMessageNode valueWanted: aBoolean
	| sel |
	sel := aMessageNode selector.
	(sel == #ifTrue: or: [sel == #ifFalse: or: [sel == #ifTrue:ifFalse: or: [sel == #ifFalse:ifTrue:]]])
		ifTrue: [^self conditional: aMessageNode valueWanted: aBoolean].
	(sel == #and: or: [sel == #or:]) ifTrue: [^self logical: aMessageNode].
	(sel == #whileTrue: or: [sel == #whileFalse: or: [sel == #whileTrue or: [sel == #whileFalse]]])
		ifTrue: [self while: aMessageNode. ^nil].
	(sel == #to:do: or: [sel == #to:by:do:]) ifTrue: [self toDo: aMessageNode. ^nil].
	sel == #timesRepeat: ifTrue: [self timesRepeat: aMessageNode. ^nil].
	sel == #repeat ifTrue: [self repeat: aMessageNode. ^nil].
	^self caseOf: aMessageNode valueWanted: aBoolean
!
requireBlock: aNode arguments: anInteger
	(aNode isBlock and: [aNode arguments size = anInteger]) ifFalse: [
		self error: 'a literal block with ' , anInteger printString , ' arguments expected' node: aNode]
!
condition: aNode
	| c |
	c := self expression: aNode.
	(self valueType: c) isBool ifFalse: [^self error: 'a condition must be a bool, not ' , (self valueType: c) name node: aNode].
	^c
!
negate: aCExpr
	aCExpr isConstant ifTrue: [^CConst value: aCExpr value not type: aCExpr type].
	(aCExpr isKindOf: CUnary) ifTrue: [aCExpr operator = '!!' ifTrue: [^aCExpr operand]].
	^CUnary operator: '!!' operand: aCExpr type: aCExpr type
!
conditional: aMessageNode valueWanted: aBoolean
	| sel cond trueNode falseNode tb fb tv fv type res |
	sel := aMessageNode selector.
	cond := self condition: aMessageNode receiver.
	sel == #ifTrue: ifTrue: [trueNode := aMessageNode arguments first].
	sel == #ifFalse: ifTrue: [falseNode := aMessageNode arguments first].
	sel == #ifTrue:ifFalse: ifTrue: [trueNode := aMessageNode arguments first. falseNode := aMessageNode arguments last].
	sel == #ifFalse:ifTrue: ifTrue: [falseNode := aMessageNode arguments first. trueNode := aMessageNode arguments last].
	trueNode notNil ifTrue: [self requireBlock: trueNode arguments: 0].
	falseNode notNil ifTrue: [self requireBlock: falseNode arguments: 0].
	cond isConstant ifTrue: [
		| taken |
		taken := cond value ifTrue: [trueNode] ifFalse: [falseNode].
		taken isNil ifTrue: [^nil].
		^self inlineBlock: taken frame: frame env: env arguments: #() valueWanted: aBoolean node: aMessageNode].
	(aBoolean and: [trueNode notNil and: [falseNode notNil]]) ifFalse: [
		aBoolean ifTrue: [^self error: sel , ' with one branch has no value' node: aMessageNode].
		tb := trueNode isNil ifTrue: [nil] ifFalse: [self blockBody: trueNode arguments: #()].
		fb := falseNode isNil ifTrue: [nil] ifFalse: [self blockBody: falseNode arguments: #()].
		tb isNil ifTrue: [block add: (CIf condition: (self negate: cond) then: fb else: nil). ^nil].
		block add: (CIf condition: cond then: tb else: fb).
		^nil].
	tb := CBlock new.
	tv := self blockValue: trueNode into: tb.
	fb := CBlock new.
	fv := self blockValue: falseNode into: fb.
	(tv notNil and: [fv notNil and: [tb isEmpty and: [fb isEmpty]]]) ifTrue: [
		type := self commonType: tv and: fv node: aMessageNode.
		^CConditional condition: cond ifTrue: (self coerce: tv to: type node: trueNode) ifFalse: (self coerce: fv to: type node: falseNode) type: type].
	type := tv isNil ifTrue: [self valueType: fv] ifFalse: [fv isNil ifTrue: [self valueType: tv] ifFalse: [self commonType: tv and: fv node: aMessageNode]].
	res := self newLocal: 'v' type: type.
	tv notNil ifTrue: [tb add: (CExprStatement expression: (CBinary operator: '=' left: res right: (self coerce: tv to: type node: trueNode) type: type))].
	fv notNil ifTrue: [fb add: (CExprStatement expression: (CBinary operator: '=' left: res right: (self coerce: fv to: type node: falseNode) type: type))].
	^CStatementExpr block: (CBlock with: (CIf condition: cond then: tb else: fb)) result: res type: type
!
logical: aMessageNode
	| left rb rv right op |
	left := self condition: aMessageNode receiver.
	self requireBlock: aMessageNode arguments first arguments: 0.
	op := aMessageNode selector == #and: ifTrue: ['&&'] ifFalse: ['||'].
	left isConstant ifTrue: [
		(left value = (op = '&&')) ifFalse: [^left]].
	rb := CBlock new.
	rv := self blockValue: aMessageNode arguments first into: rb.
	rv isNil ifTrue: [^self error: 'the block of ' , aMessageNode selector , ' must answer a value' node: aMessageNode].
	(self valueType: rv) isBool ifFalse: [^self error: 'the block of ' , aMessageNode selector , ' must answer a bool' node: aMessageNode].
	right := rb isEmpty ifTrue: [rv] ifFalse: [CStatementExpr block: rb result: rv type: rv type].
	left isConstant ifTrue: [^right].
	(right isConstant and: [right value = (op = '&&')]) ifTrue: [^left].
	^CBinary operator: op left: left right: right type: (translator registry at: 'bool')
!
while: aMessageNode
	| sel cb cv body loop |
	sel := aMessageNode selector.
	self requireBlock: aMessageNode receiver arguments: 0.
	cb := CBlock new.
	cv := self blockValue: aMessageNode receiver into: cb.
	cv isNil ifTrue: [^self error: 'a loop condition must answer a value' node: aMessageNode].
	(self valueType: cv) isBool ifFalse: [^self error: 'a loop condition must be a bool' node: aMessageNode].
	(sel == #whileFalse: or: [sel == #whileFalse]) ifTrue: [cv := self negate: cv].
	body := aMessageNode arguments isEmpty
		ifTrue: [CBlock new]
		ifFalse: [
			self requireBlock: aMessageNode arguments first arguments: 0.
			self blockBody: aMessageNode arguments first arguments: #()].
	(cb isEmpty and: [aMessageNode arguments notEmpty])
		ifTrue: [
			(cv isConstant and: [cv value == false]) ifTrue: [^self].
			loop := CWhile condition: ((cv isConstant and: [cv value == true]) ifTrue: [nil] ifFalse: [cv]) body: body]
		ifFalse: [
			| all |
			all := CBlock new.
			all addAll: cb statements.
			(cv isConstant and: [cv value == true]) ifFalse: [
				all add: (CIf condition: (self negate: cv) then: (CBlock with: CBreak new) else: nil)].
			all add: body.
			loop := CWhile condition: nil body: all].
	block add: loop
!
toDo: aMessageNode
	| start stop step loopBlock var stopExpr type body cmp |
	start := self expression: aMessageNode receiver.
	stop := self expression: aMessageNode arguments first.
	aMessageNode selector == #to:by:do:
		ifTrue: [
			step := self expression: (aMessageNode arguments at: 2).
			step isConstant ifFalse: [^self error: 'to:by:do: needs a constant step' node: aMessageNode].
			loopBlock := aMessageNode arguments at: 3]
		ifFalse: [
			step := self integerConstant: 1 hex: false.
			loopBlock := aMessageNode arguments at: 2].
	self requireBlock: loopBlock arguments: 1.
	((self valueType: stop) isInteger and: [(self valueType: stop) isSigned not and: [(stop isKindOf: CBinary) and: [stop operator = '-']]]) ifTrue: [
		^self error: 'an unsigned loop limit computed by a subtraction wraps in C when it would go negative: use asInt64' node: aMessageNode arguments first].
	type := self arithmeticType: start and: stop node: aMessageNode.
	var := self newLocal: (LowtalkNames snake: loopBlock arguments first name) type: type.
	stopExpr := stop isPure
		ifTrue: [stop]
		ifFalse: [
			| t |
			t := self newLocal: 'stop' type: (self valueType: stop).
			block add: (CExprStatement expression: (CBinary operator: '=' left: t right: stop type: t type)).
			t].
	body := self blockBody: loopBlock arguments: (Array with: var).
	cmp := step value >= 0 ifTrue: ['<='] ifFalse: ['>='].
	block add: (CFor
		init: (CBinary operator: '=' left: var right: start type: type)
		condition: (CBinary operator: cmp left: var right: stopExpr type: (translator registry at: 'bool'))
		step: (CBinary operator: (step value >= 0 ifTrue: ['+='] ifFalse: ['-=']) left: var right: (self integerConstant: step value abs hex: false) type: type)
		body: body)
!
timesRepeat: aMessageNode
	| count var body |
	count := self expression: aMessageNode receiver.
	self requireBlock: aMessageNode arguments first arguments: 0.
	var := self newLocal: 'i' type: (self promote: (self valueType: count)).
	body := self blockBody: aMessageNode arguments first arguments: #().
	block add: (CFor
		init: (CBinary operator: '=' left: var right: (self integerConstant: 0 hex: false) type: var type)
		condition: (CBinary operator: '<' left: var right: count type: (translator registry at: 'bool'))
		step: (CBinary operator: '+=' left: var right: (self integerConstant: 1 hex: false) type: var type)
		body: body)
!
repeat: aMessageNode
	self requireBlock: aMessageNode receiver arguments: 0.
	block add: (CWhile condition: nil body: (self blockBody: aMessageNode receiver arguments: #()))
!
caseOf: aMessageNode valueWanted: aBoolean
	"x caseOf: {[k1] -> [...]. [k2] -> [...]} otherwise: [...]: a switch on constant keys."
	| subject subjectVar cases default res type |
	(aMessageNode arguments first isKindOf: BraceNode) ifFalse: [^self error: 'caseOf: expects a brace array of [key] -> [action]' node: aMessageNode].
	subject := self expression: aMessageNode receiver.
	(self valueType: subject) isInteger ifFalse: [^self error: 'caseOf: switches on integers' node: aMessageNode].
	cases := OrderedCollection new.
	aBoolean ifTrue: [res := nil].
	aMessageNode arguments first elements do: [:assoc |
		| keyNode key body value |
		(assoc isMessage and: [assoc selector == #->]) ifFalse: [^self error: 'case [key] -> [action] expected' node: assoc].
		keyNode := assoc receiver.
		self requireBlock: keyNode arguments: 0.
		key := self expression: keyNode statements last.
		key isConstant ifFalse: [^self error: 'a case key must be a constant' node: keyNode].
		self requireBlock: assoc arguments first arguments: 0.
		body := CBlock new.
		aBoolean
			ifTrue: [
				value := self blockValue: assoc arguments first into: body.
				value notNil ifTrue: [
					res isNil ifTrue: [res := self newLocal: 'v' type: (self valueType: value)].
					body add: (CExprStatement expression: (CBinary operator: '=' left: res right: value type: res type))]]
			ifFalse: [body := self blockBody: assoc arguments first arguments: #()].
		cases add: (Array with: key) -> body].
	aMessageNode selector == #caseOf:otherwise:
		ifTrue: [
			| dnode |
			dnode := aMessageNode arguments last.
			self requireBlock: dnode arguments: 0.
			default := CBlock new.
			aBoolean
				ifTrue: [
					| value |
					value := self blockValue: dnode into: default.
					(value notNil and: [res notNil]) ifTrue: [
						default add: (CExprStatement expression: (CBinary operator: '=' left: res right: value type: res type))]]
				ifFalse: [default := self blockBody: dnode arguments: #()]]
		ifFalse: [default := nil].
	subject isConstant ifTrue: [
		| hit |
		hit := cases detect: [:c | c key first value = subject value] ifNone: [nil].
		block add: (hit isNil ifTrue: [default ifNil: [CBlock new]] ifFalse: [hit value])]
		ifFalse: [block add: (CSwitch expression: subject cases: cases asArray default: default)].
	aBoolean ifFalse: [^nil].
	res isNil ifTrue: [^self error: 'caseOf: has no value' node: aMessageNode].
	^res
! !

!TCodeGenerator methodsFor: 'values'!
valueSend: aMessageNode valueWanted: aBoolean
	"A message to a value: arithmetic, comparisons, casts, pointers, struct fields, function pointers."
	| sel rcv args type |
	sel := aMessageNode selector.
	rcv := self expression: aMessageNode receiver.
	type := self valueType: rcv.
	(sel == #ifNoOverflowAdd:do: or: [sel == #ifNoOverflowSub:do: or: [sel == #ifNoOverflowMul:do:]])
		ifTrue: [self overflowCheck: aMessageNode receiver: rcv. ^nil].
	((type isPointer and: [type target isFunction]) and: [self isCallSelector: sel])
		ifTrue: [^self callPointer: rcv arguments: aMessageNode arguments node: aMessageNode].
	((type isPointerLike and: [type target isStruct]) or: [type isStruct]) ifTrue: [
		(self isFieldSelector: sel of: type) ifTrue: [^self field: aMessageNode receiver: rcv]].
	type isPointerLike ifTrue: [^self pointerSend: aMessageNode receiver: rcv].
	args := aMessageNode arguments collect: [:a | self expression: a].
	^self operator: sel receiver: rcv arguments: args node: aMessageNode
!
operator: sel receiver: rcv arguments: args node: aNode
	| type arg |
	type := self valueType: rcv.
	args size = 1 ifTrue: [arg := args first].
	(#(#+ #- #* #/ #quo: #rem:) includes: sel) ifTrue: [^self arithmetic: sel left: rcv right: arg node: aNode].
	(#(#< #> #<= #>= #= #~=) includes: sel) ifTrue: [^self comparison: sel left: rcv right: arg node: aNode].
	(#(#bitAnd: #bitOr: #bitXor:) includes: sel) ifTrue: [^self bitwise: sel left: rcv right: arg node: aNode].
	(sel == #<< or: [sel == #>>]) ifTrue: [^self shift: sel left: rcv right: arg node: aNode].
	sel == #bitShift: ifTrue: [
		arg isConstant ifFalse: [^self error: 'bitShift: needs a constant; use << or >>' node: aNode].
		^arg value >= 0
			ifTrue: [self shift: #<< left: rcv right: arg node: aNode]
			ifFalse: [self shift: #>> left: rcv right: (self integerConstant: arg value negated hex: false) node: aNode]].
	sel == #bitClear: ifTrue: [
		self requireInteger: rcv node: aNode.
		^self bitwise: #bitAnd: left: rcv right: (self fold: (CUnary operator: '~' operand: (self coerce: arg to: (self promote: type) node: aNode) type: (self promote: type))) node: aNode].
	sel == #negated ifTrue: [^self fold: (CUnary operator: '-' operand: rcv type: (self promote: type))].
	sel == #not ifTrue: [
		type isBool ifFalse: [^self error: 'not needs a bool' node: aNode].
		^self negate: rcv].
	sel == #bitInvert ifTrue: [
		(type isInteger and: [type isSigned]) ifFalse: [^self error: 'bitInvert of an unsigned value: use bitInvert64 or bitInvert32' node: aNode].
		^self fold: (CUnary operator: '~' operand: rcv type: (self promote: type))].
	sel == #bitInvert64 ifTrue: [^self fold: (CUnary operator: '~' operand: (self cast: rcv to: (translator registry at: 'uint64_t')) type: (translator registry at: 'uint64_t'))].
	sel == #bitInvert32 ifTrue: [^self fold: (CUnary operator: '~' operand: (self cast: rcv to: (translator registry at: 'uint32_t')) type: (translator registry at: 'uint32_t'))].
	(#(#asInt8 #asUInt8 #asInt16 #asUInt16 #asInt32 #asUInt32 #asInt64 #asUInt64) includes: sel) ifTrue: [
		self requireInteger: rcv node: aNode.
		^self cast: rcv to: (translator registry at: (self castTypeNameFor: sel))].
	sel == #asFloat ifTrue: [^self cast: rcv to: (translator registry at: 'double')].
	sel == #truncated ifTrue: [
		type isFloat ifFalse: [^self error: 'truncated of a non-float' node: aNode].
		^self cast: rcv to: (translator registry at: 'int64_t')].
	(sel == #max: or: [sel == #min:]) ifTrue: [^self minMax: sel left: rcv right: arg node: aNode].
	sel == #between:and: ifTrue: [
		^self bitwiseFoldAnd: (self comparison: #>= left: rcv right: args first node: aNode) with: (self comparison: #<= left: rcv right: args last node: aNode)].
	sel == #value ifTrue: [^self error: 'value of a non-pointer' node: aNode].
	sel == #isNull ifTrue: [^self error: 'isNull of a non-pointer' node: aNode].
	sel == #abs ifTrue: [
		rcv isConstant ifTrue: [^CConst value: rcv value abs type: rcv type].
		^self error: 'abs: write x < 0 ifTrue: [x negated] ifFalse: [x]' node: aNode].
	(sel == #& or: [sel == #|]) ifTrue: [
		(type isBool and: [(self valueType: arg) isBool]) ifFalse: [^self error: sel , ' needs bools' node: aNode].
		^CBinary operator: (sel == #& ifTrue: ['&&'] ifFalse: ['||']) left: rcv right: arg type: type].
	^self error: 'not a Lowtalk operation: ' , type name , ' ' , sel node: aNode
!
castTypeNameFor: aSelector
	^(Dictionary new
		at: #asInt8 put: 'int8_t'; at: #asUInt8 put: 'uint8_t'; at: #asInt16 put: 'int16_t'; at: #asUInt16 put: 'uint16_t';
		at: #asInt32 put: 'int32_t'; at: #asUInt32 put: 'uint32_t'; at: #asInt64 put: 'int64_t'; at: #asUInt64 put: 'uint64_t';
		yourself) at: aSelector
!
requireInteger: aCExpr node: aNode
	(self valueType: aCExpr) isInteger ifFalse: [self error: 'an integer is needed, not ' , (self valueType: aCExpr) name node: aNode]
!
bitwiseFoldAnd: a with: b
	(a isConstant and: [a value == false]) ifTrue: [^a].
	(a isConstant and: [a value == true]) ifTrue: [^b].
	^CBinary operator: '&&' left: a right: b type: (translator registry at: 'bool')
!
minMax: sel left: a right: b node: aNode
	| type cmp |
	type := self arithmeticType: a and: b node: aNode.
	(a isConstant and: [b isConstant]) ifTrue: [^CConst value: (sel == #max: ifTrue: [a value max: b value] ifFalse: [a value min: b value]) type: type].
	(a isPure and: [b isPure]) ifFalse: [^self error: sel , ' needs simple operands (assign them to locals first)' node: aNode].
	cmp := CBinary operator: (sel == #max: ifTrue: ['>'] ifFalse: ['<']) left: a right: b type: (translator registry at: 'bool').
	^CConditional condition: cmp ifTrue: (self coerce: a to: type node: aNode) ifFalse: (self coerce: b to: type node: aNode) type: type
!
overflowCheck: aMessageNode receiver: rcv
	"x ifNoOverflowAdd: y do: [:r | ...]"
	| op arg blk int64 r cond builtin |
	op := aMessageNode selector.
	arg := self expression: aMessageNode arguments first.
	blk := aMessageNode arguments last.
	self requireBlock: blk arguments: 1.
	self requireInteger: rcv node: aMessageNode.
	self requireInteger: arg node: aMessageNode.
	int64 := translator registry at: 'int64_t'.
	r := self newLocal: (LowtalkNames snake: blk arguments first name) type: int64.
	builtin := op == #ifNoOverflowAdd:do: ifTrue: ['__builtin_add_overflow'] ifFalse: [
		op == #ifNoOverflowSub:do: ifTrue: ['__builtin_sub_overflow'] ifFalse: ['__builtin_mul_overflow']].
	cond := CUnary operator: '!!' operand: (CCall function: builtin arguments: (Array with: (self cast: rcv to: int64) with: (self cast: arg to: int64) with: (CUnary operator: '&' operand: r type: int64 pointer)) type: (translator registry at: 'bool')) type: (translator registry at: 'bool').
	block add: (CIf condition: cond then: (self blockBody: blk arguments: (Array with: r)) else: nil)
!
isCallSelector: aSymbol
	"call, call:, call:with: ... up to ten arguments: a call through a function pointer."
	| s |
	aSymbol == #call ifTrue: [^true].
	(aSymbol numArgs between: 1 and: 10) ifFalse: [^false].
	s := WriteStream on: String new.
	s nextPutAll: 'call:'.
	aSymbol numArgs - 1 timesRepeat: [s nextPutAll: 'with:'].
	^aSymbol asString = s contents
!
callPointer: aCExpr arguments: argNodes node: aNode
	| ftype args |
	ftype := (self valueType: aCExpr) target.
	args := argNodes collect: [:a | self expression: a].
	args size = ftype parameterTypes size ifFalse: [^self error: 'wrong number of arguments for a function pointer' node: aNode].
	(inferring and: [ftype isKindOf: TSignature]) ifTrue: [
		ftype root addDependent: function.
		argNodes doWithIndex: [:a :i | self note: (args at: i) argument: i of: ftype root node: a]].
	^CCall function: aCExpr arguments: (args with: ftype parameterTypes collect: [:e :t | self coerce: e to: t node: aNode]) type: ftype returnType
! !

!TCodeGenerator methodsFor: 'pointers and structs'!
structTypeOf: aCType
	aCType isStruct ifTrue: [^aCType].
	^aCType target
!
isFieldSelector: aSelector of: aCType
	| s name |
	s := self structTypeOf: aCType.
	s isStruct ifFalse: [^false].
	name := aSelector asString.
	(name endsWith: ':') ifTrue: [name := name allButLast].
	(name includes: $:) ifTrue: [^false].
	^(s fieldNamed: name ifAbsent: [nil]) notNil
!
field: aMessageNode receiver: rcv
	| sel name s f member type value |
	sel := aMessageNode selector asString.
	name := (sel endsWith: ':') ifTrue: [sel allButLast] ifFalse: [sel].
	type := self valueType: rcv.
	s := self structTypeOf: type.
	f := s fieldNamed: name ifAbsent: nil.
	member := CMember base: rcv field: f cName arrow: type isStruct not type: f type.
	aMessageNode arguments isEmpty ifTrue: [^member].
	value := self expression: aMessageNode arguments first.
	self checkStore: value to: f type node: aMessageNode.
	^CBinary operator: '=' left: member right: (self coerce: value to: f type node: aMessageNode) type: f type
!
pointerSend: aMessageNode receiver: rcv
	| sel type target args |
	sel := aMessageNode selector.
	type := self valueType: rcv.
	target := type target.
	args := sel == #fieldAddress:
		ifTrue: [#()]
		ifFalse: [aMessageNode arguments collect: [:a | self expression: a]].
	sel == #isNull ifTrue: [^CBinary operator: '==' left: rcv right: (CConst value: nil type: self voidPointer) type: self boolType].
	sel == #notNull ifTrue: [^CBinary operator: '!!=' left: rcv right: (CConst value: nil type: self voidPointer) type: self boolType].
	sel == #at: ifTrue: [
		self requireInteger: args first node: aMessageNode.
		target isStruct ifTrue: [^CBinary operator: '+' left: rcv right: args first type: type].
		^CIndex base: rcv index: args first type: target].
	sel == #at:put: ifTrue: [
		self requireInteger: args first node: aMessageNode.
		self checkStore: args last to: target node: aMessageNode.
		^CBinary operator: '=' left: (CIndex base: rcv index: args first type: target) right: (self coerce: args last to: target node: aMessageNode) type: target].
	sel == #value ifTrue: [
		target isStruct ifTrue: [^rcv].
		^CUnary operator: '*' operand: rcv type: target].
	sel == #value: ifTrue: [
		target isStruct ifTrue: [
			^CBinary operator: '=' left: (CUnary operator: '*' operand: rcv type: target) right: (CUnary operator: '*' operand: args first type: target) type: target].
		self checkStore: args first to: target node: aMessageNode.
		^CBinary operator: '=' left: (CUnary operator: '*' operand: rcv type: target) right: (self coerce: args first to: target node: aMessageNode) type: target].
	sel == #fieldAddress: ifTrue: [
		| f |
		(target isStruct and: [aMessageNode arguments first isLiteral and: [aMessageNode arguments first value isSymbol]]) ifFalse: [
			^self error: 'fieldAddress: takes a field name of a struct pointer' node: aMessageNode].
		f := target fieldNamed: aMessageNode arguments first value asString ifAbsent: [^self error: 'no field ' , aMessageNode arguments first value node: aMessageNode].
		^CUnary operator: '&' operand: (CMember base: rcv field: f cName arrow: true type: f type) type: f type pointer].
	sel == #copyStructFrom: ifTrue: [
		^CBinary operator: '=' left: (CUnary operator: '*' operand: rcv type: target) right: (CUnary operator: '*' operand: args first type: target) type: target].
	sel == #+ ifTrue: [
		self requireInteger: args first node: aMessageNode.
		^CBinary operator: '+' left: rcv right: args first type: (type isArray ifTrue: [type decayed] ifFalse: [type])].
	sel == #- ifTrue: [
		(self valueType: args first) isPointerLike ifTrue: [
			^CBinary operator: '-' left: rcv right: args first type: (translator registry at: 'int64_t')].
		self requireInteger: args first node: aMessageNode.
		^CBinary operator: '-' left: rcv right: args first type: (type isArray ifTrue: [type decayed] ifFalse: [type])].
	(#(#< #> #<= #>= #= #~=) includes: sel) ifTrue: [
		| other |
		other := args first.
		((self valueType: other) isPointerLike or: [other isConstant and: [other value isNil]]) ifFalse: [
			^self error: 'a pointer compares with a pointer' node: aMessageNode].
		^self fold: (CBinary operator: (self cOperatorFor: sel) left: rcv right: other type: self boolType)].
	^self error: 'not a pointer operation: ' , sel node: aMessageNode
! !

!TCodeGenerator methodsFor: 'arithmetic'!
cOperatorFor: aSelector
	^(Dictionary new
		at: #+ put: '+'; at: #- put: '-'; at: #* put: '*'; at: #/ put: '/'; at: #quo: put: '/'; at: #rem: put: '%';
		at: #< put: '<'; at: #> put: '>'; at: #<= put: '<='; at: #>= put: '>='; at: #= put: '=='; at: #~= put: '!!=';
		at: #bitAnd: put: '&'; at: #bitOr: put: '|'; at: #bitXor: put: '^'; at: #<< put: '<<'; at: #>> put: '>>';
		yourself) at: aSelector
!
arithmetic: sel left: a right: b node: aNode
	| ta tb type |
	ta := self valueType: a.
	tb := self valueType: b.
	(ta isPointerLike or: [tb isPointerLike]) ifTrue: [^self error: 'pointer arithmetic needs the pointer as receiver' node: aNode].
	(ta isArithmetic and: [tb isArithmetic]) ifFalse: [^self error: 'arithmetic on ' , ta name , ' and ' , tb name node: aNode].
	sel == #/ ifTrue: [
		(ta isFloat or: [tb isFloat]) ifFalse: [^self error: '/ on integers: use quo: (truncating)' node: aNode]].
	(sel == #quo: or: [sel == #rem:]) ifTrue: [
		(ta isInteger and: [tb isInteger]) ifFalse: [^self error: sel , ' on non-integers' node: aNode]].
	type := self arithmeticType: a and: b node: aNode modular: (#(#+ #- #*) includes: sel).
	^self fold: (CBinary operator: (self cOperatorFor: sel) left: a right: b type: type)
!
comparison: sel left: a right: b node: aNode
	| ta tb |
	ta := self valueType: a.
	tb := self valueType: b.
	(ta isPointerLike or: [tb isPointerLike]) ifTrue: [
		^CBinary operator: (self cOperatorFor: sel) left: a right: b type: self boolType].
	(ta isBool and: [tb isBool]) ifTrue: [
		(sel == #= or: [sel == #~=]) ifFalse: [^self error: 'bools only compare for equality' node: aNode].
		^self fold: (CBinary operator: (self cOperatorFor: sel) left: a right: b type: self boolType)].
	(ta isArithmetic and: [tb isArithmetic]) ifFalse: [^self error: 'cannot compare ' , ta name , ' with ' , tb name node: aNode].
	self arithmeticType: a and: b node: aNode.
	"An unsigned value is never below 0: x >= 0 is true, x < 0 false (C compilers warn about such comparisons)."
	(b isConstant and: [b value = 0 and: [ta isInteger and: [ta isSigned not and: [a isPure]]]]) ifTrue: [
		sel == #>= ifTrue: [^CConst value: true type: self boolType].
		sel == #< ifTrue: [^CConst value: false type: self boolType]].
	(a isConstant and: [a value = 0 and: [tb isInteger and: [tb isSigned not and: [b isPure]]]]) ifTrue: [
		sel == #<= ifTrue: [^CConst value: true type: self boolType].
		sel == #> ifTrue: [^CConst value: false type: self boolType]].
	^self fold: (CBinary operator: (self cOperatorFor: sel) left: a right: b type: self boolType)
!
bitwise: sel left: a right: b node: aNode
	self requireInteger: a node: aNode.
	self requireInteger: b node: aNode.
	^self fold: (CBinary operator: (self cOperatorFor: sel) left: a right: b type: (self arithmeticType: a and: b node: aNode modular: true))
!
shift: sel left: a right: b node: aNode
	| left |
	self requireInteger: a node: aNode.
	self requireInteger: b node: aNode.
	left := a.
	(a isConstant and: [b isConstant not]) ifTrue: [
		left := CConst value: a value type: (translator registry at: (a value > 16r7FFFFFFFFFFFFFFF ifTrue: ['uint64_t'] ifFalse: ['int64_t']))].
	(sel == #<< and: [left isConstant not and: [(self promote: (self valueType: left)) size < 8]]) ifTrue: [
		^self error: 'a left shift of a ' , (self valueType: left) name , ' overflows at 32 bits in C but not in the simulator: widen it first (asInt64, asUInt64)' node: aNode].
	^self fold: (CBinary operator: (self cOperatorFor: sel) left: left right: b type: (self promote: (self valueType: left)))
!
promote: aCType
	"C's integer promotion."
	(aCType isInteger and: [aCType size < 4]) ifTrue: [^translator registry at: 'int'].
	aCType isBool ifTrue: [^translator registry at: 'int'].
	^aCType
!
arithmeticType: a and: b node: aNode
	"The type of a op b under C's usual arithmetic conversions. Converting a signed operand that may be negative to unsigned is an error: the simulator would compute with the negative value."
	^self arithmeticType: a and: b node: aNode modular: false
!
arithmeticType: a and: b node: aNode modular: isModular
	"With isModular (+ - * and bitwise operations), converting a signed operand to unsigned is fine: the result is the same modulo 2^64, and the simulator checks the value where it is stored."
	| ta tb pa pb signed unsigned |
	ta := self valueType: a.
	tb := self valueType: b.
	(ta isFloat or: [tb isFloat]) ifTrue: [
		^(ta isFloat and: [ta size = 8]) | (tb isFloat and: [tb size = 8])
			ifTrue: [translator registry at: 'double']
			ifFalse: [translator registry at: 'float']].
	(ta isInteger and: [tb isInteger]) ifFalse: [^self error: 'arithmetic on ' , ta name , ' and ' , tb name node: aNode].
	pa := self promote: ta.
	pb := self promote: tb.
	pa isSigned = pb isSigned ifTrue: [
		pa size = pb size ifTrue: [^a isConstant ifTrue: [pb] ifFalse: [pa]].
		^pa size > pb size ifTrue: [pa] ifFalse: [pb]].
	pa isSigned
		ifTrue: [signed := a. unsigned := b]
		ifFalse: [signed := b. unsigned := a].
	(self promote: (self valueType: signed)) size > (self promote: (self valueType: unsigned)) size
		ifTrue: [^self promote: (self valueType: signed)].
	(signed isConstant and: [signed value >= 0]) ifTrue: [^self promote: (self valueType: unsigned)].
	(((self valueType: signed) isInteger and: [(self valueType: signed) isSigned not]) or: [(self valueType: signed) isBool]) ifTrue: [
		"a small unsigned type promoted to int is never negative"
		^self promote: (self valueType: unsigned)].
	(signed isConstant not and: [unsigned isConstant and: [unsigned value <= 16r7FFFFFFF]]) ifTrue: [
		^self promote: (self valueType: signed)].
	isModular ifTrue: [^self promote: (self valueType: unsigned)].
	^self error: 'mixing signed ' , (self valueType: signed) name , ' and unsigned ' , (self valueType: unsigned) name , ' (C would convert the signed one): cast one' node: aNode
!
commonType: a and: b node: aNode
	| ta tb |
	ta := self valueType: a.
	tb := self valueType: b.
	(ta isArithmetic and: [tb isArithmetic]) ifTrue: [^self arithmeticType: a and: b node: aNode].
	(ta isPointerLike and: [b isConstant and: [b value isNil]]) ifTrue: [^ta].
	(tb isPointerLike and: [a isConstant and: [a value isNil]]) ifTrue: [^tb].
	(ta sameAs: tb) ifTrue: [^ta].
	^self error: 'branches of different types: ' , ta name , ' and ' , tb name node: aNode
!
inferredType: aCExpr
	"The type of a local first assigned aCExpr: an integer constant gives a 64-bit integer (the simulator computes exactly, so a narrower local could differ from it)."
	(aCExpr isConstant and: [aCExpr value isInteger]) ifTrue: [
		(aCExpr type isInteger and: [aCExpr type size = 8]) ifTrue: [^aCExpr type].
		^translator registry at: (aCExpr value > 16r7FFFFFFFFFFFFFFF ifTrue: ['uint64_t'] ifFalse: ['int64_t'])].
	^self valueType: aCExpr
!
valueType: aCExpr
	"The type of aCExpr as a value: arrays decay to pointers, a const qualifier goes."
	| t |
	t := aCExpr type.
	t isNil ifTrue: [^self error: 'expression without a type' node: nil].
	t isConst ifTrue: [t := t base].
	t isArray ifTrue: [^t decayed].
	^t
!
cast: aCExpr to: aCType
	aCExpr isConstant ifTrue: [
		(aCExpr value isInteger and: [aCType isInteger]) ifTrue: [^CConst value: (aCType wrap: aCExpr value) type: aCType].
		(aCExpr value isNumber and: [aCType isFloat]) ifTrue: [^CConst value: aCExpr value asFloat type: aCType]].
	((self valueType: aCExpr) = aCType) ifTrue: [^aCExpr].
	^CCast to: aCType operand: aCExpr
!
checkAssignable: aCExpr to: aCType node: aNode
	| t |
	t := self valueType: aCExpr.
	aCType isBool ifTrue: [t isBool ifFalse: [self error: 'a bool is needed, not ' , t name node: aNode]. ^self].
	aCType isFloat ifTrue: [
		t isFloat ifFalse: [
			(aCExpr isConstant and: [aCExpr value isNumber]) ifTrue: [^self].
			self error: 'a ' , aCType name , ' is needed, not ' , t name , ' (use asFloat)' node: aNode].
		^self].
	aCType isInteger ifTrue: [
		t isInteger ifFalse: [self error: 'an integer (' , aCType name , ') is needed, not ' , t name node: aNode].
		aCExpr isConstant ifTrue: [
			(aCType includes: aCExpr value) ifFalse: [self error: aCExpr value printString , ' does not fit ' , aCType name node: aNode].
			^self].
		(self type: t fitsIn: aCType) ifFalse: [
			self error: 'a ' , t name , ' does not always fit ' , aCType name , ' (convert it: asInt32, asUInt64, ...)' node: aNode].
		^self].
	aCType isPointer ifTrue: [
		(aCExpr isConstant and: [aCExpr value isNil]) ifTrue: [^self].
		(aCExpr isConstant and: [aCExpr value isString]) ifTrue: [^self].
		t isPointerLike ifFalse: [self error: 'a pointer (' , aCType name , ') is needed, not ' , t name node: aNode].
		(t isPointer and: [t target isFunction and: [aCType target isFunction and: [(t target isKindOf: TSignature) or: [aCType target isKindOf: TSignature]]]]) ifTrue: [
			"an inferred function pointer: it unifies with the other one"
			inferring ifTrue: [(t target isKindOf: TSignature) ifTrue: [t target unifyWith: aCType target] ifFalse: [aCType target unifyWith: t target]].
			^self].
		(aCType sameAs: t) ifFalse: [self error: 'a ' , aCType name , ' is needed, not ' , t name node: aNode].
		^self].
	aCType isStruct ifTrue: [^self error: 'structs are assigned with value:' node: aNode]
!
type: aSourceType fitsIn: aTargetType
	"Whether every value of aSourceType is one of aTargetType."
	aTargetType isSigned ifTrue: [
		^aSourceType isSigned
			ifTrue: [aSourceType size <= aTargetType size]
			ifFalse: [aSourceType size < aTargetType size]].
	^aSourceType isSigned not and: [aSourceType size <= aTargetType size]
!
checkStore: aCExpr to: aCType node: aNode
	"Into memory: integers may narrow (the simulator checks each stored value)."
	| t |
	t := self valueType: aCExpr.
	(aCType isInteger and: [t isInteger and: [aCExpr isConstant not]]) ifTrue: [^self].
	^self checkAssignable: aCExpr to: aCType node: aNode
!
coerce: aCExpr to: aCType node: aNode
	"Make the C conversion explicit where C would not do it silently (void pointers)."
	| t |
	t := self valueType: aCExpr.
	(aCType isPointer and: [t isPointerLike and: [(aCType = t) not and: [aCType isVoidPointer not]]]) ifTrue: [
		t isVoidPointer ifTrue: [^CCast to: aCType operand: aCExpr]].
	(aCType isFloat and: [aCExpr isConstant and: [aCExpr value isInteger]]) ifTrue: [^CConst value: aCExpr value asFloat type: aCType].
	^aCExpr
!
boolType
	^translator registry at: 'bool'
!
voidPointer
	^translator registry parse: 'void *'
! !

!TCodeGenerator methodsFor: 'folding'!
fold: aCExpr
	"Constant folding with C semantics for integer and boolean constants; v == v and v !!= v fold too."
	| op l r v type |
	(aCExpr isKindOf: CUnary) ifTrue: [
		aCExpr operand isConstant ifFalse: [^aCExpr].
		v := aCExpr operand value.
		v isInteger ifFalse: [^aCExpr].
		op := aCExpr operator.
		op = '-' ifTrue: [^self constant: v negated type: aCExpr type].
		op = '~' ifTrue: [^self constant: (aCExpr type wrap: v bitInvert) type: aCExpr type].
		^aCExpr].
	(aCExpr isKindOf: CBinary) ifFalse: [^aCExpr].
	((aCExpr operator = '==' or: [aCExpr operator = '!!=']) and: [self isSameVariable: aCExpr left as: aCExpr right]) ifTrue: [
		^CConst value: aCExpr operator = '==' type: self boolType].
	(aCExpr left isConstant and: [aCExpr right isConstant]) ifFalse: [^aCExpr].
	l := aCExpr left value.
	r := aCExpr right value.
	(l isInteger and: [r isInteger]) ifFalse: [
		((l == true or: [l == false]) and: [r == true or: [r == false]]) ifTrue: [
			op := aCExpr operator.
			op = '==' ifTrue: [^CConst value: l = r type: self boolType].
			op = '!!=' ifTrue: [^CConst value: l ~= r type: self boolType]].
		^aCExpr].
	op := aCExpr operator.
	type := aCExpr type.
	op = '+' ifTrue: [^self constant: l + r type: type].
	op = '-' ifTrue: [^self constant: l - r type: type].
	op = '*' ifTrue: [^self constant: l * r type: type].
	op = '/' ifTrue: [r = 0 ifTrue: [^aCExpr]. ^self constant: (l quo: r) type: type].
	op = '%' ifTrue: [r = 0 ifTrue: [^aCExpr]. ^self constant: (l rem: r) type: type].
	op = '&' ifTrue: [^self constant: (l bitAnd: r) type: type].
	op = '|' ifTrue: [^self constant: (l bitOr: r) type: type].
	op = '^' ifTrue: [^self constant: (l bitXor: r) type: type].
	op = '<<' ifTrue: [^self constant: (l bitShift: r) type: type].
	op = '>>' ifTrue: [^self constant: (l bitShift: r negated) type: type].
	op = '<' ifTrue: [^CConst value: l < r type: self boolType].
	op = '>' ifTrue: [^CConst value: l > r type: self boolType].
	op = '<=' ifTrue: [^CConst value: l <= r type: self boolType].
	op = '>=' ifTrue: [^CConst value: l >= r type: self boolType].
	op = '==' ifTrue: [^CConst value: l = r type: self boolType].
	op = '!!=' ifTrue: [^CConst value: l ~= r type: self boolType].
	^aCExpr
!
constant: anInteger type: aCType
	"A folded constant: it keeps aCType if it fits, else it widens (the simulator computes exactly)."
	(aCType isInteger and: [aCType includes: anInteger]) ifTrue: [^CConst value: anInteger type: aCType].
	^self integerConstant: anInteger hex: false
!
isSameVariable: a as: b
	"Whether a and b read one integer or pointer variable, so a == b: not a double (NaN) nor an atomic (each read is an ordered load)."
	| t |
	(a isVariable and: [b isVariable and: [a name = b name]]) ifFalse: [^false].
	t := self valueType: a.
	^(t isInteger or: [t isPointerLike]) and: [(t name beginsWith: 'atomic') not]
! !

!TCodeGenerator methodsFor: 'intrinsics'!
intrinsic: aSelector arguments: argNodes node: aNode valueWanted: aBoolean
	| registry access |
	registry := translator registry.
	access := self memoryAccessTypeFor: aSelector.
	access notNil ifTrue: [
		| addr ptr |
		addr := self expression: argNodes first.
		ptr := CUnary operator: '*' operand: (CCast to: (CPointerType to: access) operand: addr) type: access.
		argNodes size = 1 ifTrue: [^ptr].
		^CBinary operator: '=' left: ptr right: (self coerce: (self expression: argNodes last) to: access node: aNode) type: access].
	aSelector == #null ifTrue: [^CConst value: nil type: self voidPointer].
	aSelector == #cString: ifTrue: [
		(argNodes first isLiteral and: [argNodes first value isString]) ifFalse: [^self error: 'cString: takes a string literal' node: aNode].
		^CConst value: argNodes first value type: (registry parse: 'char *')].
	aSelector == #primitiveTable ifTrue: [^CVarRef name: 'vm_primitive_table' type: (registry parse: 'PrimitiveEntry *')].
	aSelector == #primitiveCount ifTrue: [^CVarRef name: 'vm_primitive_count' type: (registry at: 'int')].
	aSelector == #sizeof: ifTrue: [
		^CRaw pureText: 'sizeof(' , ((self typeArgument: argNodes first) declarator: '') , ')' type: (registry at: 'size_t')].
	aSelector == #cCoerce:to: ifTrue: [
		| t e |
		t := self typeArgument: argNodes last.
		e := self expression: argNodes first.
		^self cast: e to: t].
	aSelector == #local: ifTrue: [^self localStorage: (self typeArgument: argNodes first) node: aNode].
	aSelector == #functionPointer: ifTrue: [^self functionPointer: argNodes first node: aNode].
	aSelector == #likely: ifTrue: [^CCall function: '__builtin_expect' arguments: (Array with: (self condition: argNodes first) with: (CConst value: 1 type: (registry at: 'int'))) type: self boolType].
	aSelector == #unlikely: ifTrue: [^CCall function: '__builtin_expect' arguments: (Array with: (self condition: argNodes first) with: (CConst value: 0 type: (registry at: 'int'))) type: self boolType].
	aSelector == #bitsOfDouble: ifTrue: [^CCall function: 'lt_bits_of_double' arguments: (Array with: (self expression: argNodes first)) type: (registry at: 'uint64_t')].
	aSelector == #varargBits: ifTrue: [^self varargBits: (self expression: argNodes first)].
	aSelector == #doubleFromBits: ifTrue: [^CCall function: 'lt_double_from_bits' arguments: (Array with: (self expression: argNodes first)) type: (registry at: 'double')].
	aSelector == #mul64:by:plus:plus:high: ifTrue: [^CCall function: 'lt_mul64' arguments: (argNodes collect: [:n | self expression: n]) asArray type: (registry at: 'uint64_t')].
	aSelector == #div128:low:by:remainder: ifTrue: [^CCall function: 'lt_div128' arguments: (argNodes collect: [:n | self expression: n]) asArray type: (registry at: 'uint64_t')].
	aSelector == #atomicLoad: ifTrue: [
		| g |
		g := self atomicVariable: argNodes first.
		^CCall function: 'atomic_load_explicit' arguments: (Array with: (CUnary operator: '&' operand: g type: g type pointer) with: (CRaw pureText: 'memory_order_relaxed' type: (registry at: 'int'))) type: g type].
	aSelector == #atomicStore:value: ifTrue: [
		| g |
		g := self atomicVariable: argNodes first.
		^CCall function: 'atomic_store_explicit' arguments: (Array with: (CUnary operator: '&' operand: g type: g type pointer) with: (self expression: argNodes last) with: (CRaw pureText: 'memory_order_relaxed' type: (registry at: 'int'))) type: (registry at: 'void')].
	aSelector == #atomicExchange:value: ifTrue: [
		| g |
		g := self atomicVariable: argNodes first.
		^CCall function: 'atomic_exchange' arguments: (Array with: (CUnary operator: '&' operand: g type: g type pointer) with: (self expression: argNodes last)) type: g type].
	^self error: 'unknown intrinsic ' , aSelector node: aNode
!
memoryAccessTypeFor: aSelector
	| names |
	names := #('uint64' 'uint32' 'uint16' 'uint8' 'int64' 'int32' 'int16' 'int8').
	names do: [:n |
		(aSelector = (n , 'At:') asSymbol or: [aSelector = (n , 'At:put:') asSymbol]) ifTrue: [^translator registry at: n , '_t']].
	(aSelector == #float64At: or: [aSelector == #float64At:put:]) ifTrue: [^translator registry at: 'double'].
	(aSelector == #float32At: or: [aSelector == #float32At:put:]) ifTrue: [^translator registry at: 'float'].
	^nil
!
typeArgument: aNode
	(aNode isLiteral and: [aNode value isString]) ifFalse: [^self error: 'a C type name (a string literal) is needed' node: aNode].
	^translator registry parse: aNode value
!
localStorage: aCType node: aNode
	"self local: 'T': a zeroed T that lives until the function returns."
	| storage |
	storage := self newLocal: 'local' type: aCType.
	block add: (CExprStatement expression: (CCall function: 'memset' arguments: (Array with: (CUnary operator: '&' operand: storage type: aCType pointer) with: (CConst value: 0 type: (translator registry at: 'int')) with: (CRaw pureText: 'sizeof ' , storage name type: (translator registry at: 'size_t'))) type: self voidPointer)).
	aCType isArray ifTrue: [^storage].
	^CUnary operator: '&' operand: storage type: aCType pointer
!
functionPointer: aNode node: aMessageNode
	| f |
	(aNode isLiteral and: [aNode value isSymbol]) ifFalse: [^self error: 'functionPointer: needs a selector literal' node: aMessageNode].
	f := translator lookup: aNode value in: frame module.
	(f isNil or: [f kind ~~ #function]) ifTrue: [^self error: aNode value , ' is not a function of ' , frame module name node: aMessageNode].
	inferring ifFalse: [
		f noteAddressTaken.
		f noteCalledFrom: cModule].
	^CVarRef name: f cName type: (CPointerType to: f signature)
!
atomicVariable: aNode
	| g |
	(aNode isLiteral and: [aNode value isSymbol]) ifFalse: [^self error: 'an atomic variable is named by a symbol' node: aNode].
	g := self globalNamed: aNode value asString node: aNode.
	^self globalReference: g
! !

!TCodeGenerator methodsFor: 'interpreter loop'!
callsDispatchLoop: aTFunction
	^aTFunction statements anySatisfy: [:s |
		s isMessage and: [s receiver isVariable and: [s receiver isSelf and: [
			| f |
			f := translator lookup: s selector in: aTFunction module.
			f notNil and: [f kind == #dispatchLoop]]]]]
!
declareRegisters
	cModule registers do: [:name |
		| g |
		g := cModule globalNamed: name.
		usedNames add: g cName.
		locals add: (CDeclaration name: g cName type: g type initializer: nil)].
	opsTable := CVarRef name: 'ops' type: (CArrayType of: self voidPointer count: 256).
	usedNames add: 'ops'
!
dispatchLoop: aTFunction
	"Dispatch the first bytecode, then all handlers and labels of the interpreter module, each a label of this function."
	| handlers labels table bad dispatchSend entries |
	dispatchSend := self findDispatchIn: aTFunction.
	nextExpression := dispatchSend arguments first.
	handlers := (cModule functions values select: [:f | f kind == #handler]) asSortedCollection: [:a :b |
		(a bytecodes isEmpty ifTrue: [256] ifFalse: [a bytecodes first]) <= (b bytecodes isEmpty ifTrue: [256] ifFalse: [b bytecodes first])].
	labels := (cModule functions values select: [:f | f kind == #label]) asSortedCollection: [:a :b | a selector <= b selector].
	table := Array new: 256.
	bad := handlers detect: [:h | h bytecodes isEmpty] ifNone: [^self error: 'the interpreter needs a handler for unknown bytecodes (<bytecodes: #()>)' node: nil].
	(handlers asArray reject: [:h | h isRange]) , (handlers asArray select: [:h | h isRange]) do: [:h |
		h bytecodes do: [:b |
			(table at: b + 1) notNil
				ifTrue: [h isRange ifFalse: [^self error: 'two handlers for bytecode ' , b printString node: nil]]
				ifFalse: [table at: b + 1 put: (self labelOf: h bytecode: b)]]].
	entries := WriteStream on: String new.
	entries nextPutAll: '{'.
	0 to: 255 do: [:b |
		b \\ 4 = 0 ifTrue: [entries lf; nextPutAll: '        '].
		entries nextPutAll: '&&'; nextPutAll: ((table at: b + 1) ifNil: [self labelOf: bad bytecode: nil]); nextPutAll: ', '].
	entries lf; nextPutAll: '    }'.
	locals addFirst: ((CDeclaration name: 'ops' type: (CArrayType of: self voidPointer count: 256) initializer: entries contents) beStatic; yourself).
	self emitNext.
	handlers do: [:h |
		(h isSpecialized and: [h bytecodes notEmpty])
			ifTrue: [h bytecodes do: [:b | (table at: b + 1) = (self labelOf: h bytecode: b) ifTrue: [self handler: h bytecode: b]]]
			ifFalse: [self handler: h bytecode: nil]].
	labels do: [:l | self label: l]
!
findDispatchIn: aLoopFunction
	"The dispatch: send in the dispatch loop method: its argument fetches the next bytecode."
	aLoopFunction statements do: [:s |
		| found |
		found := self findDispatchSendIn: s module: aLoopFunction module.
		found notNil ifTrue: [^found]].
	^self error: 'the dispatch loop method has no self dispatch: self nextBytecode' node: nil
!
findDispatchSendIn: aNode module: aTModule
	aNode isMessage ifTrue: [
		(aNode receiver isVariable and: [aNode receiver isSelf]) ifTrue: [
			| f |
			f := translator lookup: aNode selector in: aTModule.
			(f notNil and: [f kind == #dispatch]) ifTrue: [^aNode]].
		(Array with: aNode receiver) , aNode arguments do: [:n |
			| r |
			r := self findDispatchSendIn: n module: aTModule.
			r notNil ifTrue: [^r]]].
	aNode isBlock ifTrue: [
		aNode statements do: [:n |
			| r |
			r := self findDispatchSendIn: n module: aTModule.
			r notNil ifTrue: [^r]]].
	^nil
!
labelOf: aTFunction bytecode: anIntegerOrNil
	(aTFunction isSpecialized and: [anIntegerOrNil notNil])
		ifTrue: [^aTFunction cName , '_' , ((anIntegerOrNil printStringBase: 16) asLowercase padLeftTo: 2 with: $0)].
	^aTFunction cName
!
handler: aTFunction bytecode: anIntegerOrNil
	| f |
	block add: (CLabel name: (self labelOf: aTFunction bytecode: anIntegerOrNil)).
	f := TFrame kind: #handler function: aTFunction module: cModule parent: nil.
	anIntegerOrNil notNil ifTrue: [f bytecode: anIntegerOrNil].
	self body: aTFunction frame: f
!
label: aTFunction
	block add: (CLabel name: aTFunction cName).
	self body: aTFunction frame: (TFrame kind: #label function: aTFunction module: cModule parent: nil)
!
jumpTo: aTFunction arguments: argNodes node: aNode
	"^self aLabel: x: assign the label's parameters, goto."
	| target |
	aTFunction kind == #handler ifTrue: [
		(aTFunction isSpecialized and: [aTFunction bytecodes size > 1]) ifTrue: [
			^self error: 'cannot jump to a specialized handler' node: aNode].
		^block add: (CGoto label: (self labelOf: aTFunction bytecode: (aTFunction bytecodes isEmpty ifTrue: [nil] ifFalse: [aTFunction bytecodes first])))].
	aTFunction arguments with: argNodes do: [:name :arg |
		| binding value |
		binding := self labelParameterBinding: aTFunction name: name.
		value := self expression: arg.
		binding type isNil ifTrue: [self declareLocal: binding type: (self valueType: value)].
		block add: (CExprStatement expression: (CBinary operator: '=' left: binding reference right: (self coerce: value to: binding type node: arg) type: binding type))].
	target := aTFunction cName.
	block add: (CGoto label: target)
!
labelParameterBinding: aTFunction name: aString
	"Label arguments are locals of the interpreter function, assigned by the jumps."
	^labelParameters at: aTFunction cName , ':' , aString ifAbsent: [
		labelParameters at: aTFunction cName , ':' , aString put: (TBinding local: (self reserveName: (LowtalkNames snake: aString)) type: nil)]
!
body: aTFunction frame: aTFrame
	self withEnv: aTFrame env frame: aTFrame do: [
		aTFunction kind == #label ifTrue: [
			aTFunction arguments do: [:arg |
				aTFrame env at: arg put: (self labelParameterBinding: aTFunction name: arg)]].
		self declareTemporariesOf: aTFunction in: aTFrame.
		self statements: aTFunction statements.
		block endsControlFlow ifFalse: [self emitNext]]
! !

Object subclass: #TCFunction
	instanceVariableNames: 'function locals body'
	classVariableNames: ''
	package: 'VM-Translator'!

TCFunction comment: 'I am a translated C function: a TFunction''s prototype, locals and body.'!

!TCFunction methodsFor: 'initialization'!
setFunction: aTFunction locals: aCollection body: aCBlock
	function := aTFunction.
	locals := aCollection.
	body := aCBlock
! !

!TCFunction methodsFor: 'accessing'!
function
	^function
!
declaration
	"The prototype, with _Noreturn for <noreturn> functions."
	(function hasPragma: #noreturn) ifTrue: [^'_Noreturn ' , self prototype].
	^self prototype
!
prototype
	^function functionType prototypeNamed: function cName
!
definitionPrototype
	"With the Smalltalk argument names, which the body uses."
	| ft names |
	ft := function functionType.
	names := function arguments collect: [:a | LowtalkNames snake: a].
	^(CFunctionType returning: ft returnType parameters: ft parameterTypes names: names variadic: ft isVariadic) abi: ft abi; prototypeNamed: function cName
! !

!TCFunction methodsFor: 'printing'!
printOn: aStream
	function isStatic ifTrue: [aStream nextPutAll: 'static '].
	aStream nextPutAll: self definitionPrototype; lf; nextPut: ${.
	locals do: [:d | aStream lf; nextPutAll: '    '. d printCOn: aStream indent: 1].
	body printStatementsOn: aStream indent: 1.
	aStream lf; nextPut: $}; lf
! !
