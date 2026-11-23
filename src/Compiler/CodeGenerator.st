Object subclass: #CodeGenerator
	instanceVariableNames: 'encoder scope methodNode targetClass bindings instVarNames cascadeReceiver tempNameMap inlinedTemps contextBlocks'
	classVariableNames: ''
	package: 'Compiler'!

CodeGenerator comment: 'I translate a MethodNode into a CompiledMethod: I resolve variables (scopes, instance variables, workspace bindings, class variables, globals), inline control structures with literal block arguments, and drive a BytecodeEncoder. In methods of Context and its subclasses (isContextClass), sender, pc and stackp are read and every instance variable is stored with the forms the VM answers from a married Context''s frame.

tempNameMap collects {startpc. endpc. slotNames} for the method (startpc 0) and every real block, for the debugger.

contextBlocks are the blocks of inlined loops that declare (themselves or in blocks inlined into them) variables a closure captures: each runs as a real block, evaluated in place, so that every evaluation has those variables of its own, as the loop''s non-inlined form gives them (and Pharo''s and Squeak''s compilers, with temp vectors). Found by scanning the method at its first inlined loop.'!

!CodeGenerator class methodsFor: 'inlining'!
inlinedSelectors
	^#(#ifTrue: #ifFalse: #ifTrue:ifFalse: #ifFalse:ifTrue: #and: #or: #whileTrue: #whileFalse: #whileTrue #whileFalse #repeat #to:do: #to:by:do: #ifNil: #ifNotNil: #ifNil:ifNotNil: #ifNotNil:ifNil:)
! !

!CodeGenerator methodsFor: 'accessing'!
encoder
	^encoder
! !

!CodeGenerator methodsFor: 'generating'!
generate: aMethodNode class: aClass bindings: aDictionaryOrNil
	"Answer a CompiledMethod (category and properties other than temp names are left to the caller)."
	| primitive method |
	methodNode := aMethodNode.
	targetClass := aClass.
	bindings := aDictionaryOrNil.
	encoder := BytecodeEncoder new.
	tempNameMap := OrderedCollection new.
	inlinedTemps := OrderedCollection new.
	instVarNames := targetClass allInstVarNames.
	scope := CompilerScope outer: nil inlined: false.
	methodNode arguments do: [:each | self declareArgument: each in: scope].
	methodNode errorCodeVariable isNil ifFalse: [self declareTemporary: methodNode errorCodeVariable in: scope].
	methodNode temporaries do: [:each | self declareTemporary: each in: scope].
	primitive := self primitiveNumberFor: methodNode primitive.
	methodNode errorCodeVariable isNil ifFalse: [primitive := primitive bitOr: VMConstants cmPrimErrorFlag].
	methodNode isDoIt
		ifTrue: [self emitDoItBody: methodNode body]
		ifFalse: [self emitMethodBody: methodNode body].
	(methodNode isDoIt and: [scope numArgs + scope numTemps = 0])
		ifTrue: [scope allocateSlotNamed: '(doit)'].
	tempNameMap addFirst: (Array with: 0 with: encoder pc with: scope slotNames).
	method := CompiledMethod basicNew.
	method
		selector: methodNode selector;
		methodClass: targetClass;
		literals: encoder literals;
		bytecodes: encoder bytecodes;
		numArgs: scope numArgs;
		numTemps: scope numTemps;
		frameSize: scope numArgs + scope numTemps + encoder maxDepth;
		primitive: primitive;
		source: methodNode source;
		pragmas: self pragmas;
		sourceMap: encoder sourceMap.
	self hasTempNames ifTrue: [method propertyAt: #tempNames put: self tempNames].
	inlinedTemps isEmpty ifFalse: [method propertyAt: #inlinedTemps put: inlinedTemps asArray].
	^method
!
pragmas
	| pragmas |
	methodNode pragmas isEmpty ifTrue: [^nil].
	pragmas := methodNode pragmas collect: [:each |
		Message selector: each selector arguments: (encoder freeze: each arguments)].
	^pragmas asArray
!
hasTempNames
	tempNameMap do: [:each | (each at: 3) isEmpty ifFalse: [^true]].
	^false
!
tempNames
	"Answer a flat Array startpc endpc names ... (method first, then blocks in pc order)."
	| result |
	result := OrderedCollection new.
	tempNameMap do: [:each | result addAll: each].
	^result asArray
!
primitiveNumberFor: anIntegerOrString
	| names |
	anIntegerOrString isNil ifTrue: [^0].
	anIntegerOrString isInteger ifTrue: [^anIntegerOrString].
	names := Smalltalk vm primitiveNames.
	1 to: names size do: [:i |
		((names at: i) notNil and: [(names at: i) asString = anIntegerOrString asString])
			ifTrue: [^i]].
	^self error: 'Unknown primitive ''' , anIntegerOrString asString , '''' at: methodNode start
! !

!CodeGenerator methodsFor: 'errors'!
error: aString at: anInteger
	^SyntaxError signal: aString at: anInteger in: methodNode source
!
error: aString node: aNode
	^self error: aString at: aNode start
! !

!CodeGenerator methodsFor: 'scopes'!
declareArgument: aVariableNode in: aScope
	(aScope declares: aVariableNode name)
		ifTrue: [^self error: 'Duplicate name ' , aVariableNode name node: aVariableNode].
	^aScope declareArgument: aVariableNode name
!
declareTemporary: aVariableNode in: aScope
	(aScope declares: aVariableNode name)
		ifTrue: [^self error: 'Duplicate name ' , aVariableNode name node: aVariableNode].
	^aScope declareTemporary: aVariableNode name
!
newInlinedScopeFor: aBlockNode
	"Answer a scope for an inlined block; its arguments and temporaries get slots in the enclosing frame."
	| inner |
	inner := CompilerScope outer: scope inlined: true.
	aBlockNode arguments do: [:each | self declareArgument: each in: inner].
	aBlockNode temporaries do: [:each | self declareTemporary: each in: inner].
	^inner
!
isInBlock
	"Answer whether code is being generated for a real block (not the method itself)."
	^scope realScope outer notNil
! !

!CodeGenerator methodsFor: 'bodies'!
emitMethodBody: aSequenceNode
	| statements |
	statements := aSequenceNode statements.
	statements do: [:each | each emitEffect: self].
	(statements isEmpty or: [statements last isReturn not]) ifTrue: [
		encoder noteStart: self endOfSource stop: self endOfSource.
		encoder returnSelf]
!
emitDoItBody: aSequenceNode
	| statements last |
	statements := aSequenceNode statements.
	statements isEmpty ifTrue: [
		encoder pushNil.
		encoder noteStart: self endOfSource stop: self endOfSource.
		^encoder returnTop].
	1 to: statements size - 1 do: [:i | (statements at: i) emitEffect: self].
	last := statements last.
	last isReturn ifTrue: [^last emitEffect: self].
	last emitValue: self.
	encoder noteNode: last.
	encoder returnTop
!
endOfSource
	"Answer the index of the last non-separator character of the source."
	| source i |
	source := methodNode source.
	i := source size.
	[i > 1 and: [(source at: i) value <= 32]] whileTrue: [i := i - 1].
	^i
! !

!CodeGenerator methodsFor: 'variables'!
lookupVariable: aVariableNode
	"Answer {#temp index depth isArgument}, {#instVar index} or {#literal association}."
	| name entry index assoc |
	name := aVariableNode name.
	entry := scope lookup: name.
	entry notNil ifTrue: [^Array with: #temp with: (entry at: 1) with: (entry at: 2) with: (entry at: 3)].
	index := self instVarIndexOf: name.
	index > 0 ifTrue: [^Array with: #instVar with: index - 1].
	assoc := self globalBindingOf: name.
	assoc notNil ifTrue: [^Array with: #literal with: assoc].
	(bindings notNil and: [(self isUppercaseName: name) not]) ifTrue: [
		assoc := name asSymbol -> nil.
		bindings at: name asSymbol put: assoc.
		^Array with: #literal with: assoc].
	^self error: 'Undeclared variable ' , name node: aVariableNode
!
instVarIndexOf: aString
	1 to: instVarNames size do: [:i |
		(instVarNames at: i) asString = aString ifTrue: [^i]].
	^0
!
globalBindingOf: aString
	"Workspace bindings, then class variables and globals, then Undeclared."
	| symbol assoc undeclared |
	symbol := aString asSymbol.
	bindings notNil ifTrue: [
		assoc := bindings at: symbol ifAbsent: [nil].
		assoc notNil ifTrue: [^assoc]].
	assoc := targetClass bindingOf: symbol.
	assoc notNil ifTrue: [^assoc].
	undeclared := Smalltalk undeclared.
	undeclared isNil ifTrue: [^nil].
	^undeclared associationAt: symbol ifAbsent: [nil]
!
isUppercaseName: aString
	^(aString at: 1) isUppercase
!
emitVariable: aVariableNode
	| name binding |
	name := aVariableNode name.
	(name = 'self' or: [name = 'super']) ifTrue: [^encoder pushSelf].
	name = 'thisContext' ifTrue: [^encoder pushThisContext].
	binding := self lookupVariable: aVariableNode.
	self emitPush: binding
!
emitPush: binding
	| kind |
	kind := binding at: 1.
	kind == #temp ifTrue: [
		(binding at: 3) = 0
			ifTrue: [encoder pushTemp: (binding at: 2)]
			ifFalse: [encoder pushOuterTemp: (binding at: 2) depth: (binding at: 3)].
		^self].
	kind == #instVar ifTrue: [
		^(targetClass isContextClass and: [(binding at: 2) <= 2])
			ifTrue: [encoder pushContextInstVar: (binding at: 2)]
			ifFalse: [encoder pushInstVar: (binding at: 2)]].
	encoder pushLiteralVariable: (binding at: 2)
!
emitStore: binding pop: popFlag
	| kind |
	kind := binding at: 1.
	kind == #temp ifTrue: [
		(binding at: 3) = 0
			ifTrue: [
				popFlag
					ifTrue: [encoder popStoreTemp: (binding at: 2)]
					ifFalse: [encoder storeTemp: (binding at: 2)]]
			ifFalse: [
				popFlag
					ifTrue: [encoder popStoreOuterTemp: (binding at: 2) depth: (binding at: 3)]
					ifFalse: [encoder storeOuterTemp: (binding at: 2) depth: (binding at: 3)]].
		^self].
	kind == #instVar ifTrue: [
		targetClass isContextClass
			ifTrue: [encoder storeContextInstVar: (binding at: 2)]
			ifFalse: [encoder storeInstVar: (binding at: 2)].
		popFlag ifTrue: [encoder pop].
		^self].
	popFlag
		ifTrue: [encoder popStoreLiteralVariable: (binding at: 2)]
		ifFalse: [encoder storeLiteralVariable: (binding at: 2)]
!
emitAssignment: anAssignmentNode forValue: forValue
	| binding |
	binding := self lookupVariable: anAssignmentNode variable.
	((binding at: 1) == #temp and: [binding at: 4])
		ifTrue: [^self error: 'Cannot store into argument ' , anAssignmentNode variable name node: anAssignmentNode variable].
	anAssignmentNode value emitValue: self.
	encoder noteNode: anAssignmentNode.
	self emitStore: binding pop: forValue not
! !

!CodeGenerator methodsFor: 'expressions'!
emitReturn: aReturnNode
	| value |
	value := aReturnNode value.
	(self isInBlock not and: [value isVariable and: [value isSelf]]) ifTrue: [
		encoder noteNode: aReturnNode.
		^encoder returnSelf].
	value emitValue: self.
	encoder noteNode: aReturnNode.
	self isInBlock
		ifTrue: [encoder nonLocalReturnTop]
		ifFalse: [encoder returnTop]
!
emitBrace: aBraceNode
	aBraceNode elements size > 255 ifTrue: [^self error: 'Too many elements' node: aBraceNode].
	aBraceNode elements do: [:each | each emitValue: self].
	encoder makeArray: aBraceNode elements size
!
emitCascade: aCascadeNode forValue: forValue
	| saved messages |
	aCascadeNode receiver emitValue: self.
	saved := cascadeReceiver.
	cascadeReceiver := aCascadeNode receiver.
	messages := aCascadeNode messages.
	1 to: messages size - 1 do: [:i |
		encoder dup.
		self emitSend: (messages at: i) forValue: false].
	self emitSend: messages last forValue: forValue.
	cascadeReceiver := saved
!
emitMessage: aMessageNode forValue: forValue
	(self isInlinable: aMessageNode) ifTrue: [^self emitInlined: aMessageNode forValue: forValue].
	self emitSend: aMessageNode forValue: forValue
!
emitSend: aMessageNode forValue: forValue
	| receiver isSuper saved |
	receiver := aMessageNode receiver.
	isSuper := receiver isVariable and: [receiver isSuper].
	receiver == cascadeReceiver
		ifFalse: [
			saved := cascadeReceiver.
			cascadeReceiver := nil.
			receiver emitValue: self.
			cascadeReceiver := saved].
	saved := cascadeReceiver.
	cascadeReceiver := nil.
	aMessageNode arguments do: [:each | each emitValue: self].
	cascadeReceiver := saved.
	encoder noteNode: aMessageNode.
	encoder send: aMessageNode selector numArgs: aMessageNode arguments size super: isSuper.
	forValue ifFalse: [encoder pop]
! !

!CodeGenerator methodsFor: 'closures'!
emitClosure: aBlockNode
	| position savedDepth savedMax blockScope startpc frameSize |
	encoder noteNode: aBlockNode.
	position := encoder pushClosureNumArgs: aBlockNode arguments size.
	savedDepth := encoder depth.
	savedMax := encoder maxDepth.
	encoder depth: 0; maxDepth: 0.
	blockScope := CompilerScope outer: scope inlined: false.
	aBlockNode arguments do: [:each | self declareArgument: each in: blockScope].
	aBlockNode temporaries do: [:each | self declareTemporary: each in: blockScope].
	scope := blockScope.
	startpc := encoder pc.
	self emitBlockBody: aBlockNode.
	scope := blockScope outer.
	frameSize := blockScope numArgs + blockScope numTemps + encoder maxDepth.
	encoder patchClosure: position numTemps: blockScope numTemps frameSize: frameSize.
	tempNameMap add: (Array with: startpc with: encoder pc with: blockScope slotNames).
	encoder depth: savedDepth; maxDepth: savedMax.
	encoder push
!
emitBlockBody: aBlockNode
	| statements last |
	statements := aBlockNode statements.
	statements isEmpty ifTrue: [
		encoder pushNil.
		encoder noteStart: aBlockNode stop stop: aBlockNode stop.
		^encoder blockReturnTop].
	1 to: statements size - 1 do: [:i | (statements at: i) emitEffect: self].
	last := statements last.
	last isReturn ifTrue: [^last emitEffect: self].
	last emitValue: self.
	encoder noteStart: aBlockNode stop stop: aBlockNode stop.
	encoder blockReturnTop
! !

!CodeGenerator methodsFor: 'inlining'!
isInlinable: aMessageNode
	| selector receiver arguments |
	selector := aMessageNode selector.
	receiver := aMessageNode receiver.
	arguments := aMessageNode arguments.
	(receiver == cascadeReceiver or: [receiver isVariable and: [receiver isSuper]]) ifTrue: [^false].
	(CodeGenerator inlinedSelectors includes: selector) ifFalse: [^false].
	(selector == #ifTrue: or: [selector == #ifFalse: or: [selector == #and: or: [selector == #or: or: [selector == #ifNil:]]]])
		ifTrue: [^self isBlock: arguments first withArguments: 0].
	(selector == #ifTrue:ifFalse: or: [selector == #ifFalse:ifTrue:])
		ifTrue: [^(self isBlock: arguments first withArguments: 0) and: [self isBlock: arguments last withArguments: 0]].
	(selector == #whileTrue: or: [selector == #whileFalse:])
		ifTrue: [^(self isBlock: receiver withArguments: 0) and: [self isBlock: arguments first withArguments: 0]].
	(selector == #whileTrue or: [selector == #whileFalse or: [selector == #repeat]])
		ifTrue: [^self isBlock: receiver withArguments: 0].
	selector == #to:do: ifTrue: [^self isBlock: arguments last withArguments: 1].
	selector == #to:by:do: ifTrue: [
		^(self isBlock: arguments last withArguments: 1)
			and: [(arguments at: 2) isLiteral
			and: [(arguments at: 2) value isNumber
			and: [(arguments at: 2) value ~= 0]]]].
	selector == #ifNotNil: ifTrue: [^self isBlock: arguments first withArguments: 0 or: 1].
	selector == #ifNil:ifNotNil: ifTrue: [
		^(self isBlock: arguments first withArguments: 0) and: [self isBlock: arguments last withArguments: 0 or: 1]].
	selector == #ifNotNil:ifNil: ifTrue: [
		^(self isBlock: arguments first withArguments: 0 or: 1) and: [self isBlock: arguments last withArguments: 0]].
	^false
!
isBlock: aNode withArguments: n
	^aNode isBlock and: [aNode arguments size = n]
!
isBlock: aNode withArguments: n or: m
	^aNode isBlock and: [aNode arguments size = n or: [aNode arguments size = m]]
!
emitInlined: aMessageNode forValue: forValue
	| selector |
	selector := aMessageNode selector.
	(selector == #ifTrue: or: [selector == #ifFalse:]) ifTrue: [^self emitIf: aMessageNode forValue: forValue].
	(selector == #ifTrue:ifFalse: or: [selector == #ifFalse:ifTrue:]) ifTrue: [^self emitIfElse: aMessageNode forValue: forValue].
	(selector == #and: or: [selector == #or:]) ifTrue: [^self emitAndOr: aMessageNode forValue: forValue].
	(selector == #whileTrue: or: [selector == #whileFalse:]) ifTrue: [^self emitWhile: aMessageNode forValue: forValue].
	(selector == #whileTrue or: [selector == #whileFalse]) ifTrue: [^self emitUnaryWhile: aMessageNode forValue: forValue].
	selector == #repeat ifTrue: [^self emitRepeat: aMessageNode forValue: forValue].
	(selector == #to:do: or: [selector == #to:by:do:]) ifTrue: [^self emitToDo: aMessageNode forValue: forValue].
	selector == #ifNil: ifTrue: [^self emitIfNil: aMessageNode forValue: forValue].
	selector == #ifNotNil: ifTrue: [^self emitIfNotNil: aMessageNode forValue: forValue].
	^self emitIfNilIfNotNil: aMessageNode forValue: forValue
!
emitInlinedBlock: aBlockNode forValue: forValue
	self emitStatementsOf: aBlockNode in: (self newInlinedScopeFor: aBlockNode) forValue: forValue
!
emitLoopBlock: aBlockNode forValue: forValue
	"The receiver or argument block of an inlined loop (without arguments)."
	(self needsContext: aBlockNode) ifFalse: [^self emitInlinedBlock: aBlockNode forValue: forValue].
	self emitClosure: aBlockNode.
	encoder noteNode: aBlockNode.
	encoder send: #value numArgs: 0 super: false.
	forValue ifFalse: [encoder pop]
!
emitStatementsOf: aBlockNode in: aScope forValue: forValue
	"Emit the statements of an inlined block. Its temporaries start as nil each time. For value, exactly one value is left on the stack."
	| saved statements start |
	saved := scope.
	scope := aScope.
	start := encoder pc.
	"Mapped to the block's first statement: stepping stops there as at the statement that runs next."
	aBlockNode temporaries do: [:each |
		encoder pushNil.
		encoder noteNode: (aBlockNode statements isEmpty ifTrue: [aBlockNode] ifFalse: [aBlockNode statements first]);
			popStoreTemp: (aScope indexOf: each name)].
	statements := aBlockNode statements.
	forValue
		ifTrue: [
			statements isEmpty
				ifTrue: [encoder pushNil]
				ifFalse: [
					1 to: statements size - 1 do: [:i | (statements at: i) emitEffect: self].
					statements last emitValue: self]]
		ifFalse: [statements do: [:each | each emitEffect: self]].
	"Where the block's temporaries exist (start, stop, 0-based slots): debuggers hide them elsewhere."
	aBlockNode temporaries isEmpty ifFalse: [
		inlinedTemps add: start; add: encoder pc; add: (aBlockNode temporaries collect: [:each | aScope indexOf: each name]) asArray].
	scope := saved
!
emitIf: aMessageNode forValue: forValue
	| jump end depth |
	aMessageNode receiver emitValue: self.
	jump := aMessageNode selector == #ifTrue:
		ifTrue: [encoder jumpFalse]
		ifFalse: [encoder jumpTrue].
	depth := encoder depth.
	self emitInlinedBlock: aMessageNode arguments first forValue: forValue.
	forValue
		ifTrue: [
			end := encoder jump.
			encoder patchJump: jump.
			encoder depth: depth.
			encoder pushNil.
			encoder patchJump: end]
		ifFalse: [encoder patchJump: jump]
!
emitIfElse: aMessageNode forValue: forValue
	| jump end depth |
	aMessageNode receiver emitValue: self.
	jump := aMessageNode selector == #ifTrue:ifFalse:
		ifTrue: [encoder jumpFalse]
		ifFalse: [encoder jumpTrue].
	depth := encoder depth.
	self emitInlinedBlock: aMessageNode arguments first forValue: forValue.
	end := encoder jump.
	encoder patchJump: jump.
	encoder depth: depth.
	self emitInlinedBlock: aMessageNode arguments last forValue: forValue.
	encoder patchJump: end.
	encoder depth: (forValue ifTrue: [depth + 1] ifFalse: [depth])
!
emitAndOr: aMessageNode forValue: forValue
	| isAnd jump end depth |
	isAnd := aMessageNode selector == #and:.
	aMessageNode receiver emitValue: self.
	jump := isAnd ifTrue: [encoder jumpFalse] ifFalse: [encoder jumpTrue].
	depth := encoder depth.
	self emitInlinedBlock: aMessageNode arguments first forValue: forValue.
	forValue
		ifTrue: [
			end := encoder jump.
			encoder patchJump: jump.
			encoder depth: depth.
			encoder pushLiteral: isAnd not.
			encoder patchJump: end]
		ifFalse: [encoder patchJump: jump]
!
emitWhile: aMessageNode forValue: forValue
	| loop exit |
	loop := encoder pc.
	self emitLoopBlock: aMessageNode receiver forValue: true.
	exit := aMessageNode selector == #whileTrue:
		ifTrue: [encoder jumpFalse]
		ifFalse: [encoder jumpTrue].
	self emitLoopBlock: aMessageNode arguments first forValue: false.
	encoder jumpBackTo: loop.
	encoder patchJump: exit.
	forValue ifTrue: [encoder pushNil]
!
emitUnaryWhile: aMessageNode forValue: forValue
	"A loop without sends ([true] whileTrue) maps its jump to the loop: the debugger shows it where an interrupt stops it."
	| loop mapped |
	loop := encoder pc.
	mapped := encoder sourceMapSize.
	self emitLoopBlock: aMessageNode receiver forValue: true.
	encoder sourceMapSize = mapped ifTrue: [encoder noteNode: aMessageNode].
	encoder jumpBackTo: loop if: aMessageNode selector == #whileTrue.
	forValue ifTrue: [encoder pushNil]
!
emitRepeat: aMessageNode forValue: forValue
	| loop |
	loop := encoder pc.
	self emitLoopBlock: aMessageNode receiver forValue: false.
	encoder jumpBackTo: loop.
	forValue ifTrue: [encoder pushNil]
!
emitToDo: aMessageNode forValue: forValue
	"start to: limit [by: step] do: [:i | ...] with a literal step. The limit is evaluated once, into a hidden temporary unless it is a literal. The test comes before the loop and again at its bottom: one jump per iteration."
	| arguments limit step block limitIndex blockScope index loop exit inContext |
	arguments := aMessageNode arguments.
	limit := arguments first.
	block := arguments last.
	step := aMessageNode selector == #to:by:do:
		ifTrue: [(arguments at: 2) value]
		ifFalse: [1].
	aMessageNode receiver emitValue: self.
	(limit isLiteral and: [limit value isNumber])
		ifFalse: [
			limit emitValue: self.
			limitIndex := scope realScope allocateSlotNamed: '(limit)'.
			encoder noteNode: aMessageNode; popStoreTemp: limitIndex].
	inContext := self needsContext: block.
	inContext
		ifTrue: [index := scope realScope allocateSlotNamed: '(index)']
		ifFalse: [
			blockScope := self newInlinedScopeFor: block.
			index := blockScope indexOf: block arguments first name].
	encoder noteNode: aMessageNode; popStoreTemp: index.
	self emitToDoTest: aMessageNode index: index limit: limit limitIndex: limitIndex step: step.
	exit := encoder jumpFalse.
	loop := encoder pc.
	inContext
		ifTrue: [
			self emitClosure: block.
			encoder pushTemp: index.
			encoder noteNode: block.
			encoder send: #value: numArgs: 1 super: false.
			encoder pop]
		ifFalse: [self emitStatementsOf: block in: blockScope forValue: false].
	encoder pushTemp: index.
	encoder pushLiteral: step.
	encoder noteNode: aMessageNode.
	encoder send: #+ numArgs: 1 super: false.
	encoder noteNode: aMessageNode; popStoreTemp: index.
	self emitToDoTest: aMessageNode index: index limit: limit limitIndex: limitIndex step: step.
	encoder jumpBackTo: loop if: true.
	encoder patchJump: exit.
	forValue ifTrue: [encoder pushNil]
!
emitToDoTest: aMessageNode index: index limit: limit limitIndex: limitIndex step: step
	encoder pushTemp: index.
	limitIndex isNil
		ifTrue: [encoder pushLiteral: limit value]
		ifFalse: [encoder pushTemp: limitIndex].
	encoder noteNode: aMessageNode.
	encoder send: (step > 0 ifTrue: [#<=] ifFalse: [#>=]) numArgs: 1 super: false
!
emitNilTest: aMessageNode
	"Compare the top of stack with nil (consumes it, pushes a Boolean)."
	encoder pushNil.
	encoder noteNode: aMessageNode.
	encoder send: #== numArgs: 1 super: false
!
emitIfNil: aMessageNode forValue: forValue
	| jump depth |
	aMessageNode receiver emitValue: self.
	forValue
		ifTrue: [
			encoder dup.
			self emitNilTest: aMessageNode.
			jump := encoder jumpFalse.
			depth := encoder depth.
			encoder pop.
			self emitInlinedBlock: aMessageNode arguments first forValue: true.
			encoder patchJump: jump.
			encoder depth: depth]
		ifFalse: [
			self emitNilTest: aMessageNode.
			jump := encoder jumpFalse.
			self emitInlinedBlock: aMessageNode arguments first forValue: false.
			encoder patchJump: jump]
!
emitIfNotNil: aMessageNode forValue: forValue
	| block blockScope jump depth |
	block := aMessageNode arguments first.
	aMessageNode receiver emitValue: self.
	blockScope := self newInlinedScopeFor: block.
	forValue
		ifTrue: [
			encoder dup.
			self emitNilTest: aMessageNode.
			jump := encoder jumpTrue.
			depth := encoder depth.
			block arguments isEmpty
				ifTrue: [encoder pop]
				ifFalse: [encoder noteNode: aMessageNode; popStoreTemp: (blockScope indexOf: block arguments first name)].
			self emitStatementsOf: block in: blockScope forValue: true.
			encoder patchJump: jump.
			encoder depth: depth]
		ifFalse: [
			block arguments isEmpty ifFalse: [encoder noteNode: aMessageNode; storeTemp: (blockScope indexOf: block arguments first name)].
			self emitNilTest: aMessageNode.
			jump := encoder jumpTrue.
			self emitStatementsOf: block in: blockScope forValue: false.
			encoder patchJump: jump]
!
emitIfNilIfNotNil: aMessageNode forValue: forValue
	"ifNil:ifNotNil: and ifNotNil:ifNil:"
	| nilFirst nilBlock notNilBlock blockScope jump end depth |
	nilFirst := aMessageNode selector == #ifNil:ifNotNil:.
	nilBlock := nilFirst ifTrue: [aMessageNode arguments first] ifFalse: [aMessageNode arguments last].
	notNilBlock := nilFirst ifTrue: [aMessageNode arguments last] ifFalse: [aMessageNode arguments first].
	aMessageNode receiver emitValue: self.
	blockScope := self newInlinedScopeFor: notNilBlock.
	notNilBlock arguments isEmpty ifFalse: [encoder noteNode: aMessageNode; storeTemp: (blockScope indexOf: notNilBlock arguments first name)].
	self emitNilTest: aMessageNode.
	jump := nilFirst ifTrue: [encoder jumpFalse] ifFalse: [encoder jumpTrue].
	depth := encoder depth.
	nilFirst
		ifTrue: [self emitInlinedBlock: nilBlock forValue: forValue]
		ifFalse: [self emitStatementsOf: notNilBlock in: blockScope forValue: forValue].
	end := encoder jump.
	encoder patchJump: jump.
	encoder depth: depth.
	nilFirst
		ifTrue: [self emitStatementsOf: notNilBlock in: blockScope forValue: forValue]
		ifFalse: [self emitInlinedBlock: nilBlock forValue: forValue].
	encoder patchJump: end.
	encoder depth: (forValue ifTrue: [depth + 1] ifFalse: [depth])
! !

!CodeGenerator methodsFor: 'captured variables'!
needsContext: aBlockNode
	"Whether aBlockNode, a block of an inlined loop, is one of contextBlocks."
	| saved |
	contextBlocks isNil ifTrue: [
		contextBlocks := IdentitySet new.
		saved := cascadeReceiver.
		cascadeReceiver := nil.
		self scanStatementsOf: methodNode body into: self newScan.
		cascadeReceiver := saved].
	^contextBlocks includes: aBlockNode
!
newScan
	"{free. captured. pending}: the names code refers to that it does not declare, those of them that real blocks in it refer to, and whether a closure captures a variable declared by a block inlined into it (not as a loop's block)."
	^Array with: Set new with: Set new with: false
!
scan: aNode into: aScan
	"Add aNode's names to aScan; add to contextBlocks the loop blocks in aNode that need contexts of their own."
	aNode isVariable ifTrue: [^(aScan at: 1) add: aNode name].
	aNode isLiteral ifTrue: [^self].
	aNode isBlock ifTrue: [^self scanRealBlock: aNode into: aScan].
	aNode isReturn ifTrue: [^self scan: aNode value into: aScan].
	aNode isAssignment ifTrue: [
		self scan: aNode variable into: aScan.
		^self scan: aNode value into: aScan].
	aNode isMessage ifTrue: [^self scanMessage: aNode into: aScan].
	aNode isCascade ifTrue: [
		self scan: aNode receiver into: aScan.
		^aNode messages do: [:message |
			message arguments do: [:each | self scan: each into: aScan]]].
	aNode elements do: [:each | self scan: each into: aScan]
!
scanMessage: aMessageNode into: aScan
	| inlined loop |
	inlined := (self isInlinable: aMessageNode)
		ifTrue: [self inlinedBlocksOf: aMessageNode]
		ifFalse: [#()].
	loop := #(#whileTrue: #whileFalse: #whileTrue #whileFalse #repeat #to:do: #to:by:do:) includes: aMessageNode selector.
	self scan: aMessageNode receiver loop: loop inlined: inlined into: aScan.
	aMessageNode arguments do: [:each | self scan: each loop: loop inlined: inlined into: aScan]
!
scan: aNode loop: isLoop inlined: inlinedBlocks into: aScan
	(inlinedBlocks includes: aNode)
		ifTrue: [self scanInlinedBlock: aNode loop: isLoop into: aScan]
		ifFalse: [self scan: aNode into: aScan]
!
inlinedBlocksOf: aMessageNode
	| selector |
	selector := aMessageNode selector.
	(#(#whileTrue: #whileFalse: #whileTrue #whileFalse #repeat) includes: selector)
		ifTrue: [^(Array with: aMessageNode receiver) , aMessageNode arguments].
	(selector == #to:do: or: [selector == #to:by:do:]) ifTrue: [^Array with: aMessageNode arguments last].
	^aMessageNode arguments
!
scanRealBlock: aBlockNode into: aScan
	| free |
	free := (self scanStatementsOf: aBlockNode into: self newScan) at: 1.
	self remove: (self namesDeclaredBy: aBlockNode) from: free.
	(aScan at: 1) addAll: free.
	(aScan at: 2) addAll: free
!
scanInlinedBlock: aBlockNode loop: isLoop into: aScan
	"A loop's block needs a context of its own if a closure captures a variable it declares, or one a block inlined into it declares."
	| names inner captures |
	names := self namesDeclaredBy: aBlockNode.
	inner := self scanStatementsOf: aBlockNode into: self newScan.
	captures := (inner at: 3) or: [names anySatisfy: [:each | (inner at: 2) includes: each]].
	(isLoop and: [captures])
		ifTrue: [contextBlocks add: aBlockNode]
		ifFalse: [captures ifTrue: [aScan at: 3 put: true]].
	self remove: names from: (inner at: 1).
	self remove: names from: (inner at: 2).
	(aScan at: 1) addAll: (inner at: 1).
	(aScan at: 2) addAll: (inner at: 2)
!
scanStatementsOf: aNode into: aScan
	aNode statements do: [:each | self scan: each into: aScan].
	^aScan
!
namesDeclaredBy: aBlockNode
	^(aBlockNode arguments , aBlockNode temporaries) collect: [:each | each name]
!
remove: names from: aSet
	names do: [:each | aSet remove: each ifAbsent: [nil]]
! !
