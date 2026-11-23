VMConstants subclass: #VMModule
	instanceVariableNames: 'sim'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

VMModule comment: 'I am the abstract class of the VM''s modules (see docs/lowtalk.md). A module is a C file: its instance variables, declared with C types in declarations (class side), are C globals, its methods C functions. In the simulator a VMSimulation instantiates the modules and connects their module-typed variables; sim is the simulation (not part of the C).

My methods in ''intrinsics'' are the Lowtalk primitives: raw memory access, casts, sizeof, locals in memory, function pointers. The translator knows each by selector; their bodies here are the simulation.'!

!VMModule class methodsFor: 'declaring'!
declarations
	"#((name type [initialValue]) ...): my instance variables as C globals. A type naming a VMModule or CLibrary subclass connects the module."
	^#()
!
registers
	"Instance variables that are locals of the interpreter loop function (only its handlers may use them)."
	^#()
!
cFileName
	^LowtalkNames snake: self name
!
isAbstractModule
	^self == VMModule
!
isInterface
	"Whether I only declare functions that another module implements (with the same C names)."
	^false
!
targetOS
	"The operating system I am compiled for: nil (every one), #darwin, #linux or #uefi. One implementation of an interface per OS: the build compiles the one for its OS (vm/gen/sources.mk), the C file and my prototypes are guarded by the OS's predefined macro."
	^nil
!
replaces
	"The CLibrary or VMModule (or an Array of them) I take the place of in the translation for my targetOS alone (VMTranslator>>setOS:): calls to it are sends to me, under the same selectors. nil: none."
	^nil
!
replacedClasses
	| r |
	r := self replaces.
	r isNil ifTrue: [^#()].
	^r isBehavior ifTrue: [Array with: r] ifFalse: [r]
!
definedExternStructs
	"The ExternStructs of the library I implement, which the translation for my targetOS defines (no system header does)."
	^#()
!
targetArch
	"The CPU I am compiled for: nil (every one), #arm64 or #x86_64 (VMTranslator class>>targetArchs). The build compiles the modules of its CPU (vm/gen/sources.mk); a module for every CPU reaches one for a CPU through an arch interface (isArchInterface)."
	^nil
!
isArchInterface
	"Whether I am the abstract class of modules for one CPU each (targetArch): a connection typed with me is, in the translation for a CPU, the subclass for that CPU (its inline methods expand there), so a module that uses me is translated once per CPU (VMTranslator, TArchMerge)."
	^false
!
isSimulated
	"Whether a simulation may run me. Where several modules implement an interface, a simulation connects one that is simulated."
	^true
! !

!VMModule methodsFor: 'simulation'!
sim
	^sim
!
setSimulation: aSimulation
	sim := aSimulation
!
simulatedMemory
	^sim memory
!
initializeVariables
	"Give each declared variable its initial value (zero for its type unless declared), as a C program starts."
	| registry |
	registry := CTypeRegistry default.
	self class allDeclarations do: [:decl |
		| type value |
		(sim isModuleType: (decl at: 2))
			ifTrue: [value := sim moduleOrLibrary: (decl at: 2)]
			ifFalse: [
				type := registry parse: (decl at: 2).
				value := (type isArray or: [type isStruct])
					ifTrue: [
						| a |
						a := sim memory allocate: type size.
						decl size > 2 ifTrue: [self simulationStoreInitial: (decl at: 3) type: type at: a].
						type load: sim memory at: a]
					ifFalse: [
						decl size > 2
							ifTrue: [self initialValue: (decl at: 3) type: type]
							ifFalse: [type zeroValueIn: sim memory]]].
		self instVarNamed: (decl at: 1) asString put: value]
!
initialValue: aLiteral type: aCType
	aCType isBool ifTrue: [^aLiteral == true].
	aCType isFloat ifTrue: [^aLiteral asFloat].
	aCType isPointer ifTrue: [^aLiteral isString ifTrue: [aLiteral] ifFalse: [sim memory pointerTo: aCType target at: aLiteral]].
	^aLiteral isSymbol ifTrue: [self class classPool at: aLiteral ifAbsent: [VMConstants classPool at: aLiteral]] ifFalse: [aLiteral]
!
simulationStoreInitial: anArray type: aCType at: anAddress
	aCType isArray ifFalse: [^self error: 'only arrays have initializer lists'].
	anArray doWithIndex: [:v :i |
		aCType element store: (self initialValue: v type: aCType element) in: sim memory at: anAddress + ((i - 1) * aCType element size)]
! !

!VMModule class methodsFor: 'the VM'!
vmModules
	"The concrete modules of the VM packages, in a stable order."
	^((self allSubclasses select: [:c |
		(#('VM-Core' 'VM-Jit' 'VM-Platform') includes: c packageName) and: [c isAbstractModule not]])
		asSortedCollection: [:a :b | a name <= b name]) asArray
! !

!VMModule class methodsFor: 'declaring'!
allDeclarations
	"My declarations and my superclasses' (up to VMModule)."
	| all |
	all := OrderedCollection new.
	self withAllSuperclasses reverseDo: [:c |
		(c inheritsFrom: VMModule) ifTrue: [all addAll: c declarations]].
	^all
! !

!VMModule methodsFor: 'intrinsics'!
uint64At: a
	<intrinsic>
	^sim memory uint64At: a
!
uint64At: a put: v
	<intrinsic>
	^sim memory uint64At: a put: v
!
uint32At: a
	<intrinsic>
	^sim memory uint32At: a
!
uint32At: a put: v
	<intrinsic>
	^sim memory uint32At: a put: v
!
uint16At: a
	<intrinsic>
	^sim memory uint16At: a
!
uint16At: a put: v
	<intrinsic>
	^sim memory uint16At: a put: v
!
uint8At: a
	<intrinsic>
	^sim memory uint8At: a
!
uint8At: a put: v
	<intrinsic>
	^sim memory uint8At: a put: v
!
int64At: a
	<intrinsic>
	^sim memory int64At: a
!
int64At: a put: v
	<intrinsic>
	^sim memory int64At: a put: v
!
int32At: a
	<intrinsic>
	^sim memory int32At: a
!
int32At: a put: v
	<intrinsic>
	^sim memory int32At: a put: v
!
int16At: a
	<intrinsic>
	^sim memory int16At: a
!
int16At: a put: v
	<intrinsic>
	^sim memory int16At: a put: v
!
int8At: a
	<intrinsic>
	^sim memory int8At: a
!
int8At: a put: v
	<intrinsic>
	^sim memory int8At: a put: v
!
float64At: a
	<intrinsic>
	^sim memory float64At: a
!
float64At: a put: v
	<intrinsic>
	^sim memory float64At: a put: v
!
float32At: a
	<intrinsic>
	^sim memory float32At: a
!
float32At: a put: v
	<intrinsic>
	^sim memory float32At: a put: v
!
local: aTypeString
	"Answer a pointer to fresh zeroed storage for a value of the C type aTypeString (an array: to its first element)."
	<intrinsic>
	| type a |
	type := CTypeRegistry default parse: aTypeString.
	a := sim memory allocateLocal: type size.
	^type isArray
		ifTrue: [sim memory pointerTo: type element at: a]
		ifFalse: [sim memory pointerTo: type at: a]
!
cString: aStringLiteral
	"A string literal as a char * the program may read (passing literals to C library functions needs no cString:)."
	<intrinsic>
	^sim memory pointerTo: (CTypeRegistry default at: 'char') at: (sim memory cStringFor: aStringLiteral)
!
null
	"The null pointer."
	<intrinsic>
	^CPointer null
!
sizeof: aTypeString
	<intrinsic>
	^(CTypeRegistry default parse: aTypeString) size
!
cCoerce: aValue to: aTypeString
	"A C cast."
	<intrinsic>
	^self coerce: aValue to: (CTypeRegistry default parse: aTypeString)
!
coerce: aValue to: aCType
	| v |
	aCType isInteger ifTrue: [
		v := aValue.
		v isInteger ifFalse: [
			v := (v == true or: [v == false])
				ifTrue: [v ifTrue: [1] ifFalse: [0]]
				ifFalse: [v isNumber ifTrue: [v truncated] ifFalse: [sim memory addressOf: v]]].
		^aCType wrap: v].
	aCType isFloat ifTrue: [^aValue asFloat].
	aCType isBool ifTrue: [^aValue isInteger ifTrue: [aValue ~= 0] ifFalse: [aValue]].
	aCType isPointer ifTrue: [^sim memory pointerTo: aCType target at: (sim memory addressOf: aValue)].
	^self error: 'cannot cast to ' , aCType name
!
functionPointer: aSelector
	"A pointer to my function aSelector."
	<intrinsic>
	^sim functionPointerTo: self selector: aSelector
!
likely: aBoolean
	"A branch hint (__builtin_expect)."
	<intrinsic>
	^aBoolean
!
unlikely: aBoolean
	<intrinsic>
	^aBoolean
!
bitsOfDouble: aFloat
	"The 64 IEEE bits of a double (memcpy)."
	<intrinsic>
	^aFloat asFloat asIEEEBits
!
doubleFromBits: anInteger
	<intrinsic>
	^Float fromIEEEBits: anInteger
!
mul64: a by: b plus: c plus: d high: hi
	"The low 64 bits of a * b + c + d (64-bit unsigned operands: the sum is below 2^128), its high 64 bits into hi (a uint64_t local); C: unsigned __int128."
	<intrinsic>
	| t |
	t := a * b + c + d.
	hi value: (t bitShift: -64).
	^t bitAnd: 16rFFFFFFFFFFFFFFFF
!
div128: hi low: lo by: d remainder: rem
	"(hi * 2^64 + lo) quo: d for hi < d (so the quotient fits 64 bits), the remainder into rem (a uint64_t local); C: unsigned __int128."
	<intrinsic>
	| n |
	n := (hi bitShift: 64) + lo.
	rem value: n \\ d.
	^n // d
!
varargBits: aValue
	"aValue as the 64 bits a C variadic function would read: a double's IEEE bits, an integer widened (a signed one sign-extended), a pointer's address. What a Lowtalk printf takes for its ... (UefiLibC)."
	<intrinsic>
	aValue isFloat ifTrue: [^aValue asIEEEBits].
	(aValue == true or: [aValue == false]) ifTrue: [^aValue ifTrue: [1] ifFalse: [0]].
	aValue isInteger ifTrue: [^aValue bitAnd: 16rFFFFFFFFFFFFFFFF].
	^sim memory addressOf: aValue
!
primitiveTable
	"The VM's primitives: an array of PrimitiveEntry structs (number, flags: 1 leaf 2 tryable, name, function), sorted by number."
	<intrinsic>
	^sim primitiveTable
!
primitiveCount
	<intrinsic>
	^sim primitiveCount
!
atomicLoad: aSymbol
	"Load my atomic variable (or element zero of an atomic array), relaxed."
	<intrinsic>
	| old |
	old := self instVarAt: (sim indexOfVariable: aSymbol in: self class).
	^(old isKindOf: CPointer) ifTrue: [old at: 0] ifFalse: [old]
!
atomicStore: aSymbol value: aValue
	"Store to my atomic variable (or element zero of an atomic array), relaxed."
	<intrinsic>
	| i old |
	i := sim indexOfVariable: aSymbol in: self class.
	old := self instVarAt: i.
	^(old isKindOf: CPointer)
		ifFalse: [self instVarAt: i put: aValue]
		ifTrue: [old at: 0 put: aValue]
!
atomicExchange: aSymbol value: aValue
	"Store to my atomic variable (or element zero of an atomic array) and answer its previous value (sequentially consistent)."
	<intrinsic>
	| old |
	old := self atomicLoad: aSymbol.
	self atomicStore: aSymbol value: aValue.
	^old
! !
