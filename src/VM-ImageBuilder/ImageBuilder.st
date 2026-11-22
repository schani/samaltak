VMConstants subclass: #ImageBuilder
	instanceVariableNames: 'source sim memory classes globals undeclared symbols nilOop trueOop falseOop primitiveNumbers layerErrors warnings currentFile currentLine currentPackage currentSource lastNode methodCount log'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

ImageBuilder comment: 'I build a seed image from a source tree (src/, or the mini kernel of the VM tests): I read the packages (ImageSource), lay out the classes, create the objects of the new image with the VM''s own object memory (VM-Core''s ObjectMemory and GarbageCollector, simulated over a SimulatedMemory, so the object format has one definition), compile every method with the Smalltalk compiler (BuilderCodeGenerator), check the layering rules of packages.txt, and write the image file.

	ImageBuilder buildFrom: ''src'' to: ''build/seed.image''

The image starts in SystemDictionary>>bootstrapStartUp, in a Process at priority 40, as stage 2 expects. make seed runs me in the checked-in boot/seed.image, after filing in my current sources (boot/build-seed.st).'!

!ImageBuilder class methodsFor: 'building'!
buildFrom: aSourceDirectory to: anImagePath
	"Build and write the image; answer a one-line summary. Signals ImageBuildError with every error found."
	^self new buildFrom: aSourceDirectory to: anImagePath
!
buildFrom: aSourceDirectory packages: aListPath to: anImagePath
	"The same with only the packages aListPath names (one a line, # comments; nil or '': all), e.g. src/runtime.txt."
	^self new buildFrom: aSourceDirectory packages: aListPath to: anImagePath
!
requiredClasses
	^#('Object' 'Behavior' 'ClassDescription' 'Class' 'Metaclass' 'UndefinedObject' 'True' 'False' 'SmallInteger' 'Character' 'SmallFloat64' 'BoxedFloat64' 'Array' 'ByteArray' 'ByteString' 'ByteSymbol' 'WideString' 'WideSymbol' 'CompiledMethod' 'Context' 'BlockClosure' 'Process' 'ProcessorScheduler' 'LinkedList' 'Semaphore' 'Association' 'Message' 'Point' 'LargePositiveInteger' 'LargeNegativeInteger' 'MethodDictionary' 'SystemDictionary' 'Dictionary')
!
vmLayouts
	"Classes whose first instance variables the VM knows."
	^Dictionary new
		at: 'Behavior' put: 'superclass methodDict format';
		at: 'ClassDescription' put: 'superclass methodDict format instanceVariables organization';
		at: 'Class' put: 'superclass methodDict format instanceVariables organization subclasses name classPool sharedPools package comment';
		at: 'Metaclass' put: 'superclass methodDict format instanceVariables organization thisClass';
		at: 'MethodDictionary' put: 'tally keys values';
		at: 'CompiledMethod' put: 'selector methodClass literals bytecodes numArgs numTemps frameSize primitive';
		at: 'Context' put: 'sender pc stackp method closureOrNil receiver';
		at: 'BlockClosure' put: 'outerContext startpc numArgs numTemps frameSize';
		at: 'Process' put: 'nextLink suspendedContext priority myList name cpuTime';
		at: 'ProcessorScheduler' put: 'quiescentProcessLists activeProcess';
		at: 'LinkedList' put: 'firstLink lastLink';
		at: 'Semaphore' put: 'firstLink lastLink excessSignals';
		at: 'Association' put: 'key value';
		at: 'Message' put: 'selector arguments';
		at: 'Point' put: 'x y';
		yourself
!
specialSelectors
	^#(#+ #- #< #> #<= #>= #= #~= #* #/ #\\ #@ #bitShift: #// #bitAnd: #bitOr: #at: #at:put: #size #== #~~ #value #value: #isNil #notNil #new #new: #x #y #class #value:value: #max:)
! !

!ImageBuilder methodsFor: 'building'!
buildFrom: aSourceDirectory to: anImagePath
	^self buildFrom: aSourceDirectory packages: nil to: anImagePath
!
buildFrom: aSourceDirectory packages: aListPath to: anImagePath
	| bytes |
	source := ImageSource on: aSourceDirectory.
	(aListPath isNil or: [aListPath isEmpty]) ifFalse: [
		source only: (((File readText: aListPath) lines collect: [:each | each trimBoth])
			reject: [:each | each isEmpty or: [each first = $#]])].
	source read.
	classes := source classes.
	classes do: [:c | c builder: self].
	globals := Dictionary new.
	undeclared := Dictionary new.
	symbols := Dictionary new.
	layerErrors := OrderedCollection new.
	warnings := 0.
	methodCount := 0.
	log := WriteStream on: String new.
	self sortClasses.
	self computeLayouts.
	self startObjectSpace.
	self createClasses.
	self definePools.
	self defineGlobals.
	self compileMethods.
	self finish.
	bytes := self writeTo: anImagePath.
	^log contents , 'image builder: ' , classes size printString , ' classes, ' , methodCount printString , ' methods, ' , bytes printString , ' bytes -> ' , anImagePath
!
warn: aString
	warnings := warnings + 1.
	log nextPutAll: 'image builder: warning: '; nextPutAll: aString; lf
!
fail: aString
	^ImageBuildError signal: aString
! !

!ImageBuilder methodsFor: 'classes'!
sortClasses
	"Superclasses first, otherwise in the order of the sources."
	| done sorted visit |
	done := Set new.
	sorted := OrderedCollection new.
	visit := nil.
	visit := [:c :stack |
		(done includes: c name) ifFalse: [
			(stack includes: c name) ifTrue: [self fail: c file , ':' , c line printString , ': superclass cycle at ' , c name].
			c superclassName notNil ifTrue: [
				visit
					value: (classes at: c superclassName ifAbsent: [self fail: c file , ':' , c line printString , ': unknown superclass ' , c superclassName])
					value: (stack copyWith: c name)].
			done add: c name.
			sorted add: c]].
	source classOrder do: [:c | visit value: c value: #()].
	source classOrder removeAll: source classOrder; addAll: sorted.
	self class requiredClasses do: [:n | (classes includesKey: n) ifFalse: [self fail: 'required class ' , n , ' is not defined']].
	source classOrder do: [:c | c superclassName notNil ifTrue: [self layerCheck: c superclassName package: c sourcePackage file: c file line: c line]]
!
order
	^source classOrder
!
superOf: aBuilderClass
	^aBuilderClass superclassName isNil ifTrue: [nil] ifFalse: [classes at: aBuilderClass superclassName]
!
computeLayouts
	| classIvars |
	self order do: [:c |
		| sup isize k spec |
		sup := self superOf: c.
		c allInstVarNames: (sup isNil ifTrue: [#()] ifFalse: [sup allInstVarNames]) , c instanceVariables.
		isize := c allInstVarNames size.
		k := c kind.
		(k == #fixed and: [sup notNil and: [(#(0 1) includes: sup instSpec) not]]) ifTrue: [
			k := (Dictionary new at: F_VAR put: #pointers; at: F_FIXVAR put: #pointers; at: F_WEAK put: #weak; at: F_IMMEDIATE put: #immediate;
				at: F_W64 put: #doublewords; at: F_W32 put: #words; at: F_BYTES put: #bytes; yourself) at: sup instSpec].
		c name = 'BoxedFloat64' ifTrue: [k := #doublewords].
		spec := k caseOf: {
			[#fixed] -> [isize > 0 ifTrue: [F_FIXED] ifFalse: [F_EMPTY]].
			[#pointers] -> [isize > 0 ifTrue: [F_FIXVAR] ifFalse: [F_VAR]].
			[#weak] -> [F_WEAK].
			[#immediate] -> [F_IMMEDIATE].
			[#doublewords] -> [F_W64].
			[#words] -> [F_W32].
			[#bytes] -> [F_BYTES]}.
		((#(7 9 10 16) includes: spec) and: [isize > 0]) ifTrue: [
			self fail: c file , ':' , c line printString , ': ' , c name , ': non-pointer classes cannot have instance variables'].
		c instSpec: spec.
		c format: (spec << CLS_SPEC_SHIFT) + isize].
	classIvars := (classes at: 'Class') allInstVarNames.
	self order do: [:c |
		| sup |
		sup := self superOf: c.
		c metaInstVarNames: (sup isNil ifTrue: [classIvars] ifFalse: [sup metaInstVarNames]) , c classInstanceVariables].
	self class vmLayouts keysAndValuesDo: [:n :layout |
		| c want |
		c := classes at: n ifAbsent: [nil].
		c notNil ifTrue: [
			want := layout substrings.
			(c allInstVarNames size >= want size and: [(c allInstVarNames first: want size) = want asArray]) ifFalse: [
				self fail: c file , ':' , c line printString , ': ' , n , ' must start with instance variables: ' , layout]]].
	(classes at: 'Context') instSpec = F_FIXVAR ifFalse: [self fail: 'Context must be a variableSubclass:']
! !

!ImageBuilder methodsFor: 'object space'!
startObjectSpace
	"The VM's object memory, simulated: every object is allocated in old space, in order."
	| mods |
	mods := VMModule vmModules select: [:c | c packageName ~= 'VM-Platform'].
	sim := VMSimulation modules: mods.
	memory := sim module: ObjectMemory.
	memory memoryInit: 1024 * 1024 maxHeap: 4096 * 1024 * 1024.
	memory instVarNamed: 'largeObjectBytes' put: 0.
	(sim module: GarbageCollector) oldBudget: 4096 * 1024 * 1024
!
new: aClassOop format: aFormat slots: n
	^memory allocObj: aClassOop format: aFormat slots: n
!
slotOf: anOop at: anIndex put: aValue
	sim memory uint64At: anOop + 16 + (8 * anIndex) put: aValue
!
slotOf: anOop at: anIndex
	^sim memory uint64At: anOop + 16 + (8 * anIndex)
!
classOf: anOop put: aClassOop
	sim memory uint64At: anOop + 8 put: aClassOop
!
beImmutable: anOop
	sim memory uint64At: anOop put: ((sim memory uint64At: anOop) bitOr: H_IMMUTABLE)
!
hashOf: anOop
	^((sim memory uint64At: anOop) >> H_HASH_SHIFT) bitAnd: H_HASH_MASK
!
writeBytes: aByteArray at: anAddress
	sim memory bytesAt: anAddress put: aByteArray
!
intOop: anInteger
	^((anInteger bitShift: 1) bitOr: 1) asUInt64
!
classOop: aName
	^(classes at: aName) oop
!
instanceOf: aClassOrName values: aDictionary extra: n
	"A pointer instance of a BuilderClass (or the class named) with instance variables set by name."
	| aBuilderClass ivars spec o |
	aBuilderClass := aClassOrName isString ifTrue: [classes at: aClassOrName] ifFalse: [aClassOrName].
	ivars := aBuilderClass allInstVarNames.
	spec := aBuilderClass instSpec.
	o := self new: aBuilderClass oop format: ((#(2 3 4) includes: spec) ifTrue: [spec] ifFalse: [ivars isEmpty ifTrue: [F_EMPTY] ifFalse: [F_FIXED]]) slots: ivars size + n.
	aDictionary keysAndValuesDo: [:k :v |
		| i |
		i := ivars indexOf: k.
		i = 0
			ifTrue: [v = nilOop ifFalse: [self fail: aBuilderClass name , ' lacks instance variable ' , k]]
			ifFalse: [self slotOf: o at: i - 1 put: v]].
	^o
!
instanceOf: aClassName values: aDictionary
	^self instanceOf: (classes at: aClassName) values: aDictionary extra: 0
!
symbol: aString
	^symbols at: aString asString ifAbsent: [
		| o |
		o := self string: aString class: ((aString allSatisfy: [:c | c value < 256]) ifTrue: ['ByteSymbol'] ifFalse: ['WideSymbol']).
		self beImmutable: o.
		symbols at: aString asString put: o]
!
string: aString
	^self string: aString class: ((aString allSatisfy: [:c | c value < 256]) ifTrue: ['ByteString'] ifFalse: ['WideString'])
!
string: aString class: aClassName
	| o |
	(aString allSatisfy: [:c | c value < 256])
		ifTrue: [
			o := memory allocBytes: (self classOop: aClassName) count: aString size.
			self writeBytes: (ByteArray withAll: (aString asArray collect: [:c | c value])) at: o + 16]
		ifFalse: [
			o := memory allocWords32: (self classOop: aClassName) count: aString size.
			aString doWithIndex: [:c :i | sim memory uint32At: o + 16 + (4 * (i - 1)) put: c value]].
	^o
!
byteArray: aByteArray
	| o |
	o := memory allocBytes: (self classOop: 'ByteArray') count: aByteArray size.
	self writeBytes: aByteArray at: o + 16.
	^o
!
array: aCollection
	| o |
	o := self new: (self classOop: 'Array') format: F_VAR slots: aCollection size.
	aCollection doWithIndex: [:v :i | self slotOf: o at: i - 1 put: v].
	^o
!
association: keyOop value: valueOop
	^self instanceOf: 'Association' values: (Dictionary new at: 'key' put: keyOop; at: 'value' put: valueOop; yourself)
!
largeInteger: anInteger
	| mag bytes o |
	mag := anInteger abs.
	bytes := ByteArray new: (mag highBit + 7 // 8).
	1 to: bytes size do: [:i | bytes at: i put: ((mag bitShift: (i - 1) * -8) bitAnd: 255)].
	o := memory allocBytes: (self classOop: (anInteger < 0 ifTrue: ['LargeNegativeInteger'] ifFalse: ['LargePositiveInteger'])) count: bytes size.
	self writeBytes: bytes at: o + 16.
	^o
!
floatOop: aFloat
	| bits e o |
	bits := aFloat asIEEEBits.
	(bits bitShift: 1) asUInt64 = 0 ifTrue: [^((bits bitShift: -63) bitShift: 3) bitOr: 4].
	e := (bits bitShift: -52) bitAnd: 16r7FF.
	(e > 896 and: [e < 1151]) ifTrue: [^(((((bits bitShift: 1) asUInt64 bitOr: (bits bitShift: -63)) - (896 bitShift: 53)) bitShift: 3) bitOr: 4) asUInt64].
	o := self new: (self classOop: 'BoxedFloat64') format: F_W64 slots: 1.
	self slotOf: o at: 0 put: bits.
	^o
!
oopFor: aLiteral
	"The new image's value for a literal (constants are immutable there)."
	| o |
	aLiteral isNil ifTrue: [^nilOop].
	aLiteral == true ifTrue: [^trueOop].
	aLiteral == false ifTrue: [^falseOop].
	aLiteral isSymbol ifTrue: [^self symbol: aLiteral].
	aLiteral isString ifTrue: [
		o := self string: aLiteral.
		self beImmutable: o.
		^o].
	aLiteral isCharacter ifTrue: [^((aLiteral value bitShift: 3) bitOr: 2)].
	aLiteral isInteger ifTrue: [
		(aLiteral between: VM_INT_MIN and: VM_INT_MAX) ifTrue: [^self intOop: aLiteral].
		o := self largeInteger: aLiteral.
		self beImmutable: o.
		^o].
	aLiteral isFloat ifTrue: [
		o := self floatOop: aLiteral.
		(self isPointer: o) ifTrue: [self beImmutable: o].
		^o].
	(aLiteral isKindOf: BuilderBinding) ifTrue: [^aLiteral oop].
	(aLiteral isKindOf: ByteArray) ifTrue: [
		o := self byteArray: aLiteral.
		self beImmutable: o.
		^o].
	aLiteral class == Array ifTrue: [
		o := self array: (aLiteral collect: [:each | self oopFor: each]).
		self beImmutable: o.
		^o].
	(aLiteral isKindOf: Message) ifTrue: [
		^self instanceOf: 'Message' values: (Dictionary new
			at: 'selector' put: (self symbol: aLiteral selector);
			at: 'arguments' put: (self oopFor: aLiteral arguments asArray);
			yourself)].
	^self fail: 'cannot put a ' , aLiteral class name , ' into the image'
!
isPointer: anOop
	^(anOop bitAnd: 7) = 0
! !

!ImageBuilder methodsFor: 'building the classes'!
createClasses
	"Metaclasses first (their class is patched once Metaclass exists), then their instances."
	| metaclass msize |
	metaclass := classes at: 'Metaclass'.
	msize := metaclass allInstVarNames size.
	self order do: [:c |
		c metaOop: (self new: 0 format: (msize = 0 ifTrue: [F_EMPTY] ifFalse: [F_FIXED]) slots: msize).
		c oop: (self new: c metaOop format: (c metaInstVarNames isEmpty ifTrue: [F_EMPTY] ifFalse: [F_FIXED]) slots: c metaInstVarNames size)].
	self order do: [:c | self classOf: c metaOop put: metaclass oop].
	nilOop := self new: (self classOop: 'UndefinedObject') format: F_EMPTY slots: 0.
	memory nilOop: nilOop.
	trueOop := self new: (self classOop: 'True') format: F_EMPTY slots: 0.
	falseOop := self new: (self classOop: 'False') format: F_EMPTY slots: 0
!
definePools
	self order do: [:c |
		c classVariables do: [:v |
			| b |
			b := BuilderBinding key: v value: nilOop.
			b oop: (self association: (self symbol: v) value: nilOop).
			c pool at: v put: b]]
!
defineGlobals
	self order do: [:c | self global: c name value: c oop].
	#('Smalltalk' 'Processor' 'Undeclared') do: [:n | (globals includesKey: n) ifFalse: [self global: n value: nilOop]].
	source globalDecls do: [:decl |
		((globals includesKey: (decl at: 1)) and: [classes includesKey: (decl at: 1)]) ifTrue: [
			self fail: (decl at: 3) , ':' , (decl at: 4) printString , ': ' , (decl at: 1) , ' is a class'].
		self global: (decl at: 1) value: (self oopFor: (decl at: 2))]
!
global: aName value: anOop
	| b |
	b := globals at: aName ifAbsent: [
		globals at: aName put: ((BuilderBinding key: aName value: anOop) oop: (self association: (self symbol: aName) value: anOop); yourself)].
	b value: anOop.
	self slotOf: b oop at: 1 put: anOop.
	^b
! !

!ImageBuilder methodsFor: 'compiling'!
primitiveNumberOf: aName ifAbsent: aBlock
	primitiveNumbers isNil ifTrue: [
		primitiveNumbers := Dictionary new.
		VMModule vmModules do: [:c |
			c selectors do: [:sel |
				((c compiledMethodAt: sel) pragmas ifNil: [#()]) do: [:p |
					p selector == #vmPrimitive:name: ifTrue: [primitiveNumbers at: (p arguments at: 2) put: (p arguments at: 1)]]]]].
	^primitiveNumbers at: aName ifAbsent: aBlock
!
bindingOf: aString from: aBuilderClass
	"Class variables of aBuilderClass and its superclasses, then globals."
	| c |
	c := aBuilderClass.
	[c notNil] whileTrue: [
		(c pool at: aString ifAbsent: [nil]) ifNotNil: [:b | ^b].
		c := self superOf: c].
	^globals at: aString ifAbsent: [nil]
!
bindingOf: aString inMethod: aMethodNode class: aClassOrMetaclass
	"For the compiler: a global or class variable (checking the layering rules), or one bound in Undeclared."
	| b line |
	line := currentLine + (lastNode isNil ifTrue: [0] ifFalse: [(currentSource first: (lastNode start - 1 max: 0)) occurrencesOf: Character lf]).
	b := self bindingOf: aString from: aClassOrMetaclass theNonMetaClass.
	b notNil ifTrue: [
		(globals at: aString ifAbsent: [nil]) == b ifTrue: [self layerCheck: aString package: currentPackage file: currentFile line: line].
		^b].
	(aString first isUppercase) ifFalse: [^nil].
	^undeclared at: aString ifAbsent: [
		self warn: currentFile , ':' , line printString , ': undeclared variable ' , aString , ' (bound in Undeclared)'.
		undeclared at: aString put: ((BuilderBinding key: aString value: nilOop) oop: (self association: (self symbol: aString) value: nilOop); yourself)]
!
noteNode: aVariableNode
	lastNode := aVariableNode
!
globalPackageOf: aName
	| c d |
	c := classes at: aName ifAbsent: [nil].
	c notNil ifTrue: [^c sourcePackage].
	d := source globalDecls detect: [:each | (each at: 1) = aName] ifNone: [nil].
	^d isNil ifTrue: [nil] ifFalse: [d at: 5]
!
layerCheck: aName package: aPackage file: aFile line: aLine
	"Packages may use globals of their own layer, the one directly below and layer 0, exported ones from the export layer up, and those of packages they use."
	| owner mine theirs export |
	owner := self globalPackageOf: aName.
	(owner isNil or: [owner = aPackage or: [(source usesOf: aPackage) includes: owner]]) ifTrue: [^self].
	mine := source layerOf: aPackage.
	theirs := source layerOf: owner.
	(theirs = 0 or: [theirs = mine or: [theirs = (mine - 1)]]) ifTrue: [^self].
	export := source exportLayerOf: aName from: owner.
	(export notNil and: [mine >= export]) ifTrue: [^self].
	layerErrors add: aFile , ':' , aLine printString , ': ' , aPackage , ' (layer ' , mine printString , ') uses ' , aName , ' of ' , owner , ' (layer ' , theirs printString , ')'
!
compileMethods
	| errors |
	errors := OrderedCollection new.
	source methodChunks do: [:chunk |
		errors size < 50 ifTrue: [
			[self compileChunk: chunk]
				on: SyntaxError, ImageBuildError
				do: [:e | errors add: ((e isKindOf: SyntaxError)
					ifTrue: [(chunk at: 5) , ':' , ((chunk at: 6) + (e position notNil ifTrue: [((chunk at: 4) first: ((e position - 1) max: 0)) occurrencesOf: Character lf] ifFalse: [0])) printString , ': ' , e messageText]
					ifFalse: [e messageText])]]].
	errors notEmpty ifTrue: [^self fail: (errors inject: '' into: [:all :e | all , 'image builder: error: ' , e , (String with: Character lf)])].
	layerErrors notEmpty ifTrue: [
		^self fail: (layerErrors inject: '' into: [:all :e | all , 'image builder: error: ' , e , (String with: Character lf)]) ,
			'image builder: ' , layerErrors size printString , ' layering violation(s); the rule and its exceptions (export, uses) are in ' , source directory , '/packages.txt']
!
compileChunk: chunk
	| cls isMeta node method target table |
	cls := classes at: (chunk at: 1) ifAbsent: [^self fail: (chunk at: 5) , ':' , (chunk at: 6) printString , ': unknown class ' , (chunk at: 1)].
	isMeta := chunk at: 2.
	currentFile := chunk at: 5.
	currentLine := chunk at: 6.
	currentPackage := chunk at: 7.
	currentSource := chunk at: 4.
	lastNode := nil.
	node := Parser new parseMethod: (chunk at: 4).
	method := (BuilderCodeGenerator new builder: self)
		generate: node
		class: (isMeta ifTrue: [cls metaclass] ifFalse: [cls])
		bindings: nil.
	(method frameSize > 255 or: [method numTemps > 255]) ifTrue: [self fail: currentFile , ':' , currentLine printString , ': method frame too large'].
	target := self instanceOf: 'CompiledMethod' values: (Dictionary new
		at: 'selector' put: (self symbol: method selector);
		at: 'methodClass' put: (isMeta ifTrue: [cls metaOop] ifFalse: [cls oop]);
		at: 'literals' put: (self array: (method literals collect: [:each | self oopFor: each]));
		at: 'bytecodes' put: (self byteArray: method bytecodes);
		at: 'numArgs' put: (self intOop: method numArgs);
		at: 'numTemps' put: (self intOop: method numTemps);
		at: 'frameSize' put: (self intOop: method frameSize);
		at: 'primitive' put: (self intOop: method primitive);
		at: 'source' put: (self string: (chunk at: 4));
		at: 'category' put: (self string: (chunk at: 3));
		at: 'pragmas' put: (method pragmas isNil ifTrue: [nilOop] ifFalse: [self oopFor: method pragmas asArray]);
		yourself)
		extra: 0.
	table := isMeta ifTrue: [cls classMethods] ifFalse: [cls methods].
	(table includesKey: method selector) ifTrue: [self warn: currentFile , ':' , currentLine printString , ': ' , cls name , (isMeta ifTrue: [' class'] ifFalse: ['']) , '>>' , method selector , ' redefined'].
	table at: method selector put: target.
	methodCount := methodCount + 1
! !

!ImageBuilder methodsFor: 'finishing'!
stringHash: aString
	"String>>hash of aString as ObjectMemory>>stringHash: computes it, with what the seed image the builder runs in has."
	| byBytes m h w k |
	byBytes := aString size <= 8.
	aString do: [:c | c value > 255 ifTrue: [byBytes := true]].
	byBytes ifTrue: [
		h := 2166136261.
		aString do: [:c | h := ((h bitXor: c value) * 16777619) bitAnd: 16rFFFFFFFF].
		^h bitAnd: 16r3FFFFFFF].
	m := 16rFFFFFFFFFFFFFFFF.
	h := aString size.
	w := 0.
	k := 0.
	aString do: [:c |
		w := w bitOr: (c value bitShift: 8 * k).
		k := k + 1.
		k = 8 ifTrue: [
			h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m.
			w := 0.
			k := 0]].
	k > 0 ifTrue: [h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m].
	h := h bitXor: (h bitShift: -32).
	h := (h * 16r2545F4914F6CDD1D) bitAnd: m.
	h := h bitXor: (h bitShift: -29).
	^h bitAnd: 16r3FFFFFFF
!
hashed: aClassName items: items hash: aBlock
	"A HashedCollection (tally array) with items placed by aBlock, linear probing."
	| cap arr |
	cap := 4.
	[cap < (2 * items size)] whileTrue: [cap := cap * 2].
	arr := Array new: cap withAll: nil.
	items do: [:it |
		| i |
		i := (aBlock value: it) \\ cap + 1.
		[(arr at: i) notNil] whileTrue: [i := i \\ cap + 1].
		arr at: i put: it].
	^self instanceOf: aClassName values: (Dictionary new
		at: 'tally' put: (self intOop: items size);
		at: 'array' put: (self array: (arr collect: [:each | each ifNil: [nilOop]]));
		yourself)
!
dictionary: aClassName bindings: aCollection
	| keys |
	keys := Dictionary new.
	aCollection do: [:b | keys at: b oop put: b key].
	^self hashed: aClassName items: (aCollection collect: [:b | b oop]) asArray hash: [:assoc | self stringHash: (keys at: assoc)]
!
methodDictionary: aDictionary
	| cap keys values |
	cap := 4.
	[cap < (2 * aDictionary size)] whileTrue: [cap := cap * 2].
	keys := Array new: cap withAll: nilOop.
	values := Array new: cap withAll: nilOop.
	(aDictionary keys asSortedCollection: [:a :b | a <= b]) do: [:sel |
		| s i |
		s := self symbol: sel.
		i := (self hashOf: s) bitAnd: cap - 1.
		[(keys at: i + 1) ~= nilOop] whileTrue: [i := (i + 1) bitAnd: cap - 1].
		keys at: i + 1 put: s.
		values at: i + 1 put: (aDictionary at: sel)].
	^self instanceOf: 'MethodDictionary' values: (Dictionary new
		at: 'tally' put: (self intOop: aDictionary size);
		at: 'keys' put: (self array: keys);
		at: 'values' put: (self array: values);
		yourself)
!
setField: aName of: anOop layout: anArray to: aValue
	| i |
	i := anArray indexOf: aName.
	i > 0 ifTrue: [self slotOf: anOop at: i - 1 put: aValue]
!
fillClasses
	| metaclass subclasses classClass |
	metaclass := classes at: 'Metaclass'.
	classClass := classes at: 'Class'.
	subclasses := Dictionary new.
	self order do: [:c | subclasses at: c name put: OrderedCollection new].
	self order do: [:c | c superclassName notNil ifTrue: [(subclasses at: c superclassName) add: c]].
	self order do: [:c |
		| sup lay o m mlay |
		sup := self superOf: c.
		lay := c metaInstVarNames.
		o := c oop.
		0 to: lay size - 1 do: [:i | self slotOf: o at: i put: nilOop].
		self setField: 'superclass' of: o layout: lay to: (sup isNil ifTrue: [nilOop] ifFalse: [sup oop]).
		self setField: 'methodDict' of: o layout: lay to: (self methodDictionary: c methods).
		self setField: 'format' of: o layout: lay to: (self intOop: c format).
		self setField: 'instanceVariables' of: o layout: lay to: (self array: (c instanceVariables collect: [:v | self string: v])).
		self setField: 'subclasses' of: o layout: lay to: (self array: ((subclasses at: c name) collect: [:s | s oop])).
		self setField: 'name' of: o layout: lay to: (self symbol: c name).
		self setField: 'classPool' of: o layout: lay to: (c pool isEmpty
			ifTrue: [nilOop]
			ifFalse: [self dictionary: 'Dictionary' bindings: (c pool values asSortedCollection: [:a :b | a key <= b key]) asArray]).
		self setField: 'package' of: o layout: lay to: (self string: c package).
		self setField: 'comment' of: o layout: lay to: (c comment isNil ifTrue: [nilOop] ifFalse: [self string: c comment]).
		m := c metaOop.
		mlay := metaclass allInstVarNames.
		0 to: mlay size - 1 do: [:i | self slotOf: m at: i put: nilOop].
		self setField: 'superclass' of: m layout: mlay to: (sup isNil ifTrue: [classClass oop] ifFalse: [sup metaOop]).
		self setField: 'methodDict' of: m layout: mlay to: (self methodDictionary: c classMethods).
		self setField: 'format' of: m layout: mlay to: (self intOop: ((c metaInstVarNames isEmpty ifTrue: [F_EMPTY] ifFalse: [F_FIXED]) << CLS_SPEC_SHIFT) + c metaInstVarNames size).
		self setField: 'instanceVariables' of: m layout: mlay to: (self array: (c classInstanceVariables collect: [:v | self string: v])).
		self setField: 'thisClass' of: m layout: mlay to: o]
!
lookup: aSelector in: aBuilderClass
	| c |
	c := aBuilderClass.
	[c notNil] whileTrue: [
		(c methods at: aSelector ifAbsent: [nil]) ifNotNil: [:m | ^m].
		c := self superOf: c].
	^nil
!
finish
	| sysdict smalltalk lists sched start numTemps frameSize ctx proc so specials holder setClass names |
	sysdict := classes at: 'SystemDictionary'.
	smalltalk := self instanceOf: sysdict values: Dictionary new extra: 0.
	self global: 'Smalltalk' value: smalltalk.
	(sysdict pool at: 'PackageList' ifAbsent: [nil]) ifNotNil: [:b |
		b value: (self array: (source packages collect: [:p | self array: (Array with: (self string: (p at: 1)) with: (self intOop: (p at: 2)))])).
		self slotOf: b oop at: 1 put: b value].
	lists := self array: ((1 to: 80) collect: [:i | self instanceOf: 'LinkedList' values: Dictionary new]).
	sched := self instanceOf: 'ProcessorScheduler' values: (Dictionary new at: 'quiescentProcessLists' put: lists; yourself).
	self global: 'Processor' value: sched.
	start := self lookup: #bootstrapStartUp in: sysdict.
	start isNil ifTrue: [self fail: 'SystemDictionary>>bootstrapStartUp is not defined'].
	numTemps := (self slotOf: start at: ((classes at: 'CompiledMethod') allInstVarNames indexOf: 'numTemps') - 1) bitShift: -1.
	frameSize := (self slotOf: start at: ((classes at: 'CompiledMethod') allInstVarNames indexOf: 'frameSize') - 1) bitShift: -1.
	ctx := self instanceOf: (classes at: 'Context') values: (Dictionary new
		at: 'pc' put: (self intOop: 0);
		at: 'stackp' put: (self intOop: numTemps);
		at: 'method' put: start;
		at: 'receiver' put: smalltalk;
		yourself) extra: frameSize + CTX_SLACK.
	proc := self instanceOf: 'Process' values: (Dictionary new
		at: 'suspendedContext' put: ctx;
		at: 'priority' put: (self intOop: 40);
		at: 'name' put: (self string: 'bootstrap');
		at: 'cpuTime' put: (self intOop: 0);
		yourself).
	self setField: 'activeProcess' of: sched layout: (classes at: 'ProcessorScheduler') allInstVarNames to: proc.
	self global: 'Undeclared' value: (self dictionary: 'Dictionary' bindings: (undeclared values asSortedCollection: [:a :b | a key <= b key]) asArray).
	so := Dictionary new.
	so at: SO_NIL put: nilOop; at: SO_FALSE put: falseOop; at: SO_TRUE put: trueOop; at: SO_PROCESSOR put: sched; at: SO_SMALLTALK put: smalltalk.
	#((SO_SMALLINTEGER 'SmallInteger') (SO_CHARACTER 'Character') (SO_SMALLFLOAT 'SmallFloat64') (SO_BOXEDFLOAT 'BoxedFloat64')
		(SO_ARRAY 'Array') (SO_BYTEARRAY 'ByteArray') (SO_BYTESTRING 'ByteString') (SO_BYTESYMBOL 'ByteSymbol') (SO_WIDESTRING 'WideString')
		(SO_COMPILEDMETHOD 'CompiledMethod') (SO_CONTEXT 'Context') (SO_BLOCKCLOSURE 'BlockClosure') (SO_PROCESS 'Process')
		(SO_SEMAPHORE 'Semaphore') (SO_POINT 'Point') (SO_LARGEPOS 'LargePositiveInteger') (SO_LARGENEG 'LargeNegativeInteger')
		(SO_MESSAGE 'Message') (SO_ASSOCIATION 'Association') (SO_BITMAP 'Bitmap') (SO_WIDESYMBOL 'WideSymbol')) do: [:pair |
			so at: (VMConstants classPool at: (pair at: 1)) put: ((classes includesKey: (pair at: 2)) ifTrue: [self classOop: (pair at: 2)] ifFalse: [nilOop])].
	#((SO_SEL_DNU 'doesNotUnderstand:') (SO_SEL_MUSTBEBOOLEAN 'mustBeBoolean') (SO_SEL_CANNOTRETURN 'cannotReturn:')
		(SO_SEL_ABOUTTORETURN 'aboutToReturn:through:') (SO_SEL_ATTEMPTTOASSIGN 'attemptToAssign:withIndex:')
		(SO_SEL_STACKOVERFLOW 'stackOverflow:') (SO_SEL_PRIMITIVEFAILED 'primitiveFailed')) do: [:pair |
			so at: (VMConstants classPool at: (pair at: 1)) put: (self symbol: (pair at: 2))].
	so at: SO_SPECIAL_SELECTORS put: (self array: (self class specialSelectors collect: [:s | self symbol: s])).
	so at: SO_TIMER_SEMAPHORE put: nilOop.
	so at: SO_EXTERNAL_OBJECTS put: (self array: (Array new: EXTERNAL_OBJECTS_SIZE withAll: nilOop)).
	so at: SO_FINALIZATION_SEMAPHORE put: nilOop.
	so at: SO_INTERVAL put: ((classes at: 'Interval' ifAbsent: [nil])
		ifNil: [nilOop]
		ifNotNil: [:c |
			(c instSpec = F_FIXED and: [c allInstVarNames = #('start' 'stop' 'step')])
				ifTrue: [c oop]
				ifFalse: [nilOop]]).
	so size = SO_COUNT ifFalse: [self fail: 'special objects: ' , so size printString , ' of ' , SO_COUNT printString].
	self fillClasses.
	(sysdict allInstVarNames first: 2) = #('tally' 'array') ifFalse: [self fail: 'SystemDictionary must start with instance variables: tally array'].
	names := (globals values asSortedCollection: [:a :b | a key <= b key]) asArray.
	self copyHashedSlotsOf: (self dictionary: 'SystemDictionary' bindings: names) into: smalltalk.
	specials := self array: ((0 to: SO_COUNT - 1) collect: [:i | so at: i]).
	memory specialsOop: specials.
	holder := self order detect: [:c | c pool includesKey: 'SymbolTable'] ifNone: [nil].
	holder notNil ifTrue: [
		| b syms |
		setClass := (classes includesKey: 'Set') ifTrue: ['Set'] ifFalse: ['Dictionary'].
		syms := Dictionary new.
		symbols keysAndValuesDo: [:k :v | syms at: v put: k].
		b := holder pool at: 'SymbolTable'.
		b value: (self hashed: setClass items: ((symbols keys asSortedCollection: [:a :b2 | a <= b2]) collect: [:k | symbols at: k]) asArray hash: [:s | self stringHash: (syms at: s)]).
		self slotOf: b oop at: 1 put: b value]
!
copyHashedSlotsOf: aDictionaryOop into: aSystemDictionaryOop
	self slotOf: aSystemDictionaryOop at: 0 put: (self slotOf: aDictionaryOop at: 0).
	self slotOf: aSystemDictionaryOop at: 1 put: (self slotOf: aDictionaryOop at: 1)
! !

!ImageBuilder methodsFor: 'writing'!
writeTo: aPath
	"The image file: a 64-byte header (ImageHeader) and old space as it is in the simulated memory."
	| gcm lo top n bytes header |
	gcm := sim module: GarbageCollector.
	lo := gcm oldLo.
	top := gcm oldTop.
	n := top - lo.
	bytes := ByteArray new: 64 + n.
	header := #[83 65 77 65 76 84 75 49].
	bytes replaceFrom: 1 to: 8 with: header startingAt: 1.
	self put64: 1 in: bytes at: 9.
	self put64: 64 in: bytes at: 17.
	self put64: n in: bytes at: 25.
	self put64: lo in: bytes at: 33.
	self put64: memory specialsOop in: bytes at: 41.
	self put64: memory hashSeed in: bytes at: 49.
	"its symbols and bindings are hashed by words of 8 bytes (stringHash:)"
	self put64: 1 in: bytes at: 57.
	bytes replaceFrom: 65 to: 64 + n with: (sim memory bytesAt: lo count: n) startingAt: 1.
	File writeBytes: bytes to: aPath.
	^n
!
put64: anInteger in: aByteArray at: anIndex
	aByteArray uint32At: anIndex put: (anInteger bitAnd: 16rFFFFFFFF).
	aByteArray uint32At: anIndex + 4 put: ((anInteger bitShift: -32) bitAnd: 16rFFFFFFFF)
! !
