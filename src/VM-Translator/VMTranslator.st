Object subclass: #VMTranslator
	instanceVariableNames: 'registry moduleClasses modules externs functions errors headerName queue queued arch os calledLibraries usedStructs'
	classVariableNames: ''
	package: 'VM-Translator'!

VMTranslator comment: 'I translate Lowtalk modules (docs/lowtalk.md) into C: one header with the constants, types, globals and prototypes, and one C file per module.

	(VMTranslator modules: VMTranslator vmModules header: ''samaltak'') writeTo: ''vm/gen''.
	VMTranslator generateVM	"what make translate runs"

The C functions take their names from their selectors (assignCNames) and their signatures from their callers and returns (inferSignatures, TSignature).

Errors (TranslationError) name the method and quote the source; translate collects them all before it fails.

One vm/gen serves every OS: a module or C library whose targetOS is #darwin or #linux has its headers, prototypes and C file guarded by the OS''s predefined macro (targetOSes), and sources.mk lists its file under that OS (VM_CORE_SOURCES_LINUX ...), so the build picks the OS''s implementation of each interface. A module for every OS may not use one OS''s library or module.

It serves every CPU too (targetArchs): a module whose targetArch is #arm64 or #x86_64 is translated only for that CPU and listed under it in sources.mk (VM_CORE_SOURCES_X86_64 ...); a connection typed with an arch interface (JitAssembler) is the interface''s module for the CPU translated for, and a method marked <arch: #x86_64> exists only there. Where that makes a difference, translate translates once per CPU and TArchMerge merges the results: what differs is guarded by the CPU''s macro, so each CPU''s compiler sees exactly its own translation.'!

Error subclass: #TranslationError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Translator'!

!VMTranslator class methodsFor: 'instance creation'!
modules: aCollectionOfClasses header: aString
	^self new setModules: aCollectionOfClasses header: aString
! !

!VMTranslator class methodsFor: 'operating systems'!
targetOSes
	"#(os predefinedMacro makeSuffix): the operating systems a module or library can be for (targetOS), the C macro that is defined there, the suffix of their source lists in sources.mk (uname -s, upper case)."
	^#((darwin '__APPLE__' 'DARWIN') (linux '__linux__' 'LINUX') (uefi 'SAMALTAK_UEFI' 'UEFI'))
!
guardFor: anOS
	^((self targetOSes detect: [:e | (e at: 1) = anOS] ifNone: [self error: 'no such target OS: ' , anOS printString]) at: 2)
! !

!VMTranslator class methodsFor: 'CPUs'!
targetArchs
	"#(arch makeSuffix): the CPUs a module can be for (targetArch), the suffix of their source lists in sources.mk (the build adds those of its uname -m). The first is the default: what is for x86_64 only is guarded by __x86_64__, what is for arm64 only is compiled everywhere else."
	^#((arm64 'ARM64') (x86_64 'X86_64'))
!
archGuardFor: anArch
	"The preprocessor condition under which anArch's code is compiled."
	^anArch = #x86_64 ifTrue: ['defined(__x86_64__)'] ifFalse: ['!!defined(__x86_64__)']
!
archSuffixFor: anArch
	^(self targetArchs detect: [:e | (e at: 1) = anArch] ifNone: [self error: 'no such target CPU: ' , anArch printString]) at: 2
! !

!VMTranslator class methodsFor: 'the VM'!
vmModules
	^VMModule vmModules
!
generateVM
	"Translate the VM into vm/gen (the C the build compiles)."
	^self generateVMInto: 'vm/gen'
!
generateVMInto: aDirectory
	^(self modules: self vmModules header: 'samaltak') writeTo: aDirectory
!
generateVMInto: aDirectory for: anArch
	"The VM for one CPU (targetArchs) only: C that builds there, translated in half the time."
	^(self modules: self vmModules header: 'samaltak') setArch: anArch; writeTo: aDirectory
!
generateVMInto: aDirectory os: anOS arch: anArch
	"The VM for an OS without a C library (#uefi): its own translation, which takes the modules for anOS and those for every OS, and binds what they replace to them (setOS:)."
	^(self modules: (self modulesFor: anOS) header: 'samaltak') setOS: anOS; setArch: anArch; writeTo: aDirectory
!
modulesFor: anOS
	"The concrete modules of the VM packages and of anOS's package (VM-UEFI), for every OS or for anOS."
	^((VMModule allSubclasses select: [:c |
		(#('VM-Core' 'VM-Jit' 'VM-Platform') , (Array with: 'VM-' , anOS asUppercase) includes: c packageName)
			and: [c isAbstractModule not and: [c targetOS isNil or: [c targetOS = anOS]]]])
		asSortedCollection: [:a :b | a name <= b name]) asArray
! !

!VMTranslator methodsFor: 'initialization'!
setModules: aCollection header: aString
	moduleClasses := aCollection asArray.
	headerName := aString.
	self initializeConstants.
	CTypeRegistry reset.
	registry := CTypeRegistry default.
	modules := IdentityDictionary new.
	externs := Dictionary new.
	errors := OrderedCollection new
!
initializeConstants
	"The constants I write are the class variables the modules' class-side initialize methods set: run those again, superclasses first, each once, so an edited one (e.g. GarbageCollector's TENURE_AGE) is what I translate."
	| done |
	done := IdentitySet new.
	moduleClasses do: [:module |
		module withAllSuperclasses reverseDo: [:c |
			((c == VMConstants or: [c inheritsFrom: VMConstants]) and: [(done includes: c) not]) ifTrue: [
				done add: c.
				(c class includesSelector: #initialize) ifTrue: [c initialize]]]]
! !

!VMTranslator methodsFor: 'accessing'!
registry
	^registry
!
moduleFor: aClass
	^modules at: aClass ifAbsent: [modules at: aClass put: (TModule on: aClass translator: self)]
!
translatedModules
	^moduleClasses collect: [:c | self moduleFor: c]
!
lookup: aSelector in: aTModule
	"The TFunction for aSelector seen from aTModule: its own, then its superclasses' up to VMModule."
	| c |
	c := aTModule moduleClass.
	[c notNil and: [c includesBehavior: VMModule]] whileTrue: [
		(c includesSelector: aSelector) ifTrue: [^(self moduleFor: c) functionAt: aSelector].
		c := c superclass].
	^nil
!
externFor: aSelector library: aLibraryClass
	^externs at: aLibraryClass name , '>>' , aSelector ifAbsent: [
		externs at: aLibraryClass name , '>>' , aSelector put: (TExtern library: aLibraryClass selector: aSelector translator: self)]
!
constantNamed: aString in: aClass ifAbsent: aBlock
	"A class variable of aClass or a superclass."
	| sym |
	sym := aString asSymbol.
	aClass withAllSuperclasses do: [:c |
		(c classPool includesKey: sym) ifTrue: [^c classPool at: sym]].
	^aBlock value
!
errors
	^errors
! !

!VMTranslator methodsFor: 'errors'!
error: aString
	^TranslationError signal: aString
!
error: aString in: aTFunctionOrNil node: aNodeOrNil
	| s |
	s := WriteStream on: String new.
	aTFunctionOrNil notNil ifTrue: [s print: aTFunctionOrNil; nextPutAll: ': '].
	s nextPutAll: aString.
	(aNodeOrNil notNil and: [aTFunctionOrNil notNil and: [aNodeOrNil start notNil]]) ifTrue: [
		s nextPutAll: ' in: '; nextPutAll: (self snippetOf: aNodeOrNil in: aTFunctionOrNil)].
	^TranslationError signal: s contents
!
snippetOf: aNode in: aTFunction
	| src |
	src := aTFunction ast source.
	^((src copyFrom: (aNode start max: 1) to: (aNode stop min: src size)) copyReplaceAll: (String with: Character lf) with: ' ')
! !

!VMTranslator methodsFor: 'translating'!
translate
	"Answer the files: an OrderedCollection of name -> contents. Signals a TranslationError listing every error. Modules that differ per CPU (targetArchs) are translated once per CPU, the results merged (TArchMerge)."
	| archs |
	arch notNil ifTrue: [^self translateForArch].
	archs := self archs.
	archs size = 1 ifTrue: [
		self setArch: archs first.
		^self translateForArch].
	^TArchMerge new merge: (archs collect: [:a | a -> ((self class modules: moduleClasses header: headerName) setArch: a; translateForArch)])
!
translateForArch
	"The files for one CPU (arch)."
	| cFunctions files |
	cFunctions := OrderedCollection new.
	self checkTargetOSes.
	self checkTargetArchs.
	self assignCNames.
	self inferSignatures.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			f isFunction ifTrue: [
				[cFunctions add: ((TCodeGenerator translator: self inferring: false) generate: f)]
					on: TranslationError
					do: [:e | errors add: e messageText. e return: nil]]]].
	errors notEmpty ifTrue: [^TranslationError signal: (errors inject: '' into: [:acc :e | acc , e , (String with: Character lf)])].
	files := OrderedCollection new.
	files add: headerName , '.h' -> (self header: cFunctions).
	self translatedModules do: [:m |
		files add: m cFileName , '.c' -> (self cFileFor: m functions: (cFunctions select: [:f | f function module == m]))].
	(self primitives notEmpty) ifTrue: [files add: 'primitive_entries.c' -> self primitiveTableFile].
	files add: 'sources.mk' -> self sourcesMakefile.
	^files
!
writeTo: aDirectory
	"Write the C files into aDirectory; answer their names."
	| files |
	files := self translate.
	(File exists: aDirectory) ifFalse: [Directory create: aDirectory].
	files do: [:each | File writeText: each value to: aDirectory , '/' , each key].
	^files collect: [:each | each key]
!
inferSignatures
	"Every function's signature (TSignature): generate the functions as far as what is known allows (TCodeGenerator inferring), a function again whenever a signature it depends on changes, until none changes; the smallest first, since most of them return what a big caller wants to know. A function with parameters waits for a caller. Then literals alone give their own types, which may start another round. Answer how many generations it took."
	| count |
	queue := SortedCollection sortBlock: [:a :b | a ast source size <= b ast source size].
	queued := IdentitySet new.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			(f isFunction and: [f parametersKnown]) ifTrue: [self enqueue: f]]].
	count := 0.
	[[queue isEmpty] whileFalse: [
		| f |
		f := queue removeFirst.
		queued remove: f.
		count := count + 1.
		count > 20000 ifTrue: [^self error: 'the signatures do not settle'].
		(TCodeGenerator translator: self inferring: true) generate: f].
	 self adoptConstants] whileTrue.
	queue := nil.
	^count
!
adoptConstants
	"Signatures that have seen nothing but literals take their types now; answer whether any did (the queue has work then)."
	| any |
	any := false.
	self translatedModules do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			(f isFunction and: [f signature adoptConstants]) ifTrue: [any := true]]].
	^any
!
enqueue: aTFunction
	"To be generated (again): only inside inferSignatures, and only functions of the modules I translate."
	queue isNil ifTrue: [^self].
	((aTFunction isFunction and: [moduleClasses identityIncludes: aTFunction module moduleClass]) and: [(queued includes: aTFunction) not]) ifTrue: [
		queued add: aTFunction.
		queue add: aTFunction]
! !

!VMTranslator methodsFor: 'names'!
assignCNames
	"Every function's C name: the first keyword of its selector in snake case (TFunction>>baseName); one that another function or a C library, global, local or type name claims too takes its module's name in front, and if that still clashes (same module, same first keyword) its whole selector. An interface and its implementations are one function."
	| functions names reserved |
	self moduleClassesWithSuperclasses do: [:c | self moduleFor: c].
	functions := self functionsSorted reject: [:f | f interface notNil].
	names := IdentityDictionary new.
	functions do: [:f | names at: f put: f baseName].
	reserved := self reservedCNames.
	#(moduleQualifiedName fullyQualifiedName) do: [:qualified |
		| counts |
		counts := Bag withAll: names values.
		functions do: [:f |
			((reserved includes: (names at: f)) or: [(counts occurrencesOf: (names at: f)) > 1])
				ifTrue: [names at: f put: (f perform: qualified)]]].
	(Set withAll: names values) size = functions size ifFalse: [^self error: 'two functions have the same C name'].
	modules do: [:m |
		m functions do: [:f |
			f isFunction ifTrue: [f cName: (names at: (f interface ifNil: [f]))]]]
!
functionsSorted
	"Every function, translated or an interface's, in a stable order."
	| all |
	all := OrderedCollection new.
	(modules values asSortedCollection: [:a :b | a name <= b name]) do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			f isFunction ifTrue: [all add: f]]].
	^all
!
reservedCNames
	"The names a function may not take: C library names and what the system headers declare, globals, the names of types, and every name a local in the modules' code goes by (a local would hide the function)."
	| names |
	names := Set withAll: #('ops' 'local' 'stop' 'v' 'memset' 'vm_primitive_table' 'vm_primitive_count' 'system' 'semaphore_signal' 'semaphore_wait').
	(self isReplaced: LibC) ifTrue: [names remove: 'memset'].
	names addAll: registry typeNames.
	(CLibrary allSubclasses reject: [:lib | self isReplaced: lib]) do: [:lib |
		lib selectors do: [:sel |
			| m |
			m := lib compiledMethodAt: sel.
			(m pragmas notNil and: [m pragmas anySatisfy: [:p | #(#c: #cVariable: #cMacro:) includes: p selector]]) ifTrue: [
				names add: (self externFor: sel library: lib) cName]]].
	modules do: [:m |
		m globals do: [:g | g isModuleReference ifFalse: [names add: g cName]].
		m functions do: [:f | names addAll: f localNames]].
	^names
! !

!VMTranslator methodsFor: 'CPUs'!
arch
	"The CPU I translate for (targetArchs), nil until translate picks it."
	^arch
!
setArch: anArch
	"Translate for anArch: its modules and those for every CPU, arch interfaces bound to their modules for anArch."
	arch := anArch.
	moduleClasses := moduleClasses select: [:c | c targetArch isNil or: [c targetArch = anArch]]
!
archs
	"The CPUs to translate for: one if nothing differs between them (no module for one CPU, no connection to an arch interface, no method for one CPU), else every CPU for which each module's connections resolve."
	| all |
	(moduleClasses anySatisfy: [:c | self isArchDependent: c]) ifFalse: [^Array with: self class targetArchs first first].
	all := self class targetArchs collect: [:spec | spec first].
	^all select: [:a | self canTranslateFor: a]
!
isArchDependent: aModuleClass
	aModuleClass targetArch notNil ifTrue: [^true].
	(aModuleClass allDeclarations anySatisfy: [:decl |
		| ref |
		ref := Smalltalk at: (decl at: 2) asString asSymbol ifAbsent: [nil].
		ref isBehavior and: [(ref inheritsFrom: VMModule) and: [ref isArchInterface or: [ref targetArch notNil]]]]) ifTrue: [^true].
	^aModuleClass withAllSuperclasses anySatisfy: [:c |
		(c inheritsFrom: VMModule) and: [c methodDict values anySatisfy: [:m | (m pragmas ifNil: [#()]) anySatisfy: [:p | p selector == #arch:]]]]
!
canTranslateFor: anArch
	"Whether the modules for anArch connect only to modules for every CPU or for anArch, and every arch interface they use has its module for anArch among them."
	| mine |
	mine := moduleClasses select: [:c | c targetArch isNil or: [c targetArch = anArch]].
	^mine allSatisfy: [:c |
		c allDeclarations allSatisfy: [:decl |
			| ref |
			ref := Smalltalk at: (decl at: 2) asString asSymbol ifAbsent: [nil].
			(ref isBehavior and: [ref inheritsFrom: VMModule]) not or: [
				ref isArchInterface
					ifTrue: [mine anySatisfy: [:m | (m inheritsFrom: ref) and: [m targetArch = anArch]]]
					ifFalse: [ref targetArch isNil or: [ref targetArch = anArch]]]]]
!
implementationOf: aClass
	"The module a connection typed aClass connects to: for an arch interface, its module for the CPU I translate for; for a C library or a module that a module for the OS I translate for alone replaces (setOS:), that one."
	(aClass isBehavior and: [(aClass inheritsFrom: CLibrary) or: [aClass inheritsFrom: VMModule]]) ifTrue: [
		(self replacementFor: aClass) ifNotNil: [:r | ^r]].
	(aClass isBehavior and: [(aClass inheritsFrom: VMModule) and: [aClass isArchInterface and: [arch notNil]]]) ifFalse: [^aClass].
	^moduleClasses detect: [:c | (c inheritsFrom: aClass) and: [c targetArch = arch]]
		ifNone: [self error: 'no module for ' , arch , ' implements ' , aClass name]
!
includesMethod: aCompiledMethod
	"Whether a method is translated: one marked <arch: #x86_64> only for that CPU."
	| p |
	p := (aCompiledMethod pragmas ifNil: [#()]) detect: [:each | each selector == #arch:] ifNone: [nil].
	^p isNil or: [arch isNil or: [p arguments first = arch]]
!
checkTargetArchs
	"A module may use the modules for every CPU and for its own (an arch interface is resolved already)."
	self translatedModules do: [:m |
		m globals do: [:g |
			| other |
			(g isModuleReference and: [(g referencedModule inheritsFrom: VMModule) and: [(other := g referencedModule targetArch) notNil and: [other ~= arch]]]) ifTrue: [
				errors add: m name , ': ' , g name , ' is ' , g referencedModule name , ', for ' , other , ' only']]].
	errors notEmpty ifTrue: [^TranslationError signal: (errors inject: '' into: [:acc :e | acc , e , (String with: Character lf)])]
! !

!VMTranslator methodsFor: 'operating systems'!
os
	"The OS I translate for alone (setOS:), or nil: every one, in one vm/gen."
	^os
!
setOS: anOS
	"Translate for anOS only: its modules and those for every OS. A C library or module that one of them replaces (replaces) is that module: a connection typed with it connects to the replacement, a replaced module is not translated, a replaced library's names are free. An interface implemented for anOS is implemented by that module alone. Only the headers of the libraries the translation calls are included."
	| mine |
	os := anOS.
	moduleClasses := moduleClasses select: [:c | c targetOS isNil or: [c targetOS = anOS]].
	mine := moduleClasses select: [:c | c targetOS = anOS].
	moduleClasses := moduleClasses reject: [:c |
		(self isReplaced: c) or: [
			c targetOS isNil and: [(self interfaceOf: c) notNil and: [mine anySatisfy: [:m | (self interfaceOf: m) == (self interfaceOf: c)]]]]]
!
interfaceOf: aModuleClass
	"The interface aModuleClass implements, or nil."
	^aModuleClass allSuperclasses detect: [:c | (c inheritsFrom: VMModule) and: [c isInterface]] ifNone: [nil]
!
replacementFor: aClass
	"The module that replaces aClass in the translation for os, or nil."
	os isNil ifTrue: [^nil].
	^moduleClasses detect: [:c | c replacedClasses includes: aClass] ifNone: [nil]
!
isReplaced: aClass
	^(self replacementFor: aClass) notNil
!
noteLibraryCalled: aLibraryClass
	calledLibraries isNil ifTrue: [calledLibraries := IdentitySet new].
	calledLibraries add: aLibraryClass
!
checkTargetOSes
	"A module may use the libraries and modules of every OS and of its own; translated for one OS alone (setOS:), also that OS's, which implement its libraries."
	self translatedModules do: [:m |
		| mine |
		mine := m moduleClass targetOS.
		m globals do: [:g |
			| other |
			(g isModuleReference and: [(other := g referencedModule targetOS) notNil and: [other ~= mine and: [other ~= os]]]) ifTrue: [
				errors add: m name , ': ' , g name , ' is ' , g referencedModule name , ', for ' , other , ' only, but ' , m name , ' is for ' , (mine ifNil: ['every OS'])]]].
	errors notEmpty ifTrue: [^TranslationError signal: (errors inject: '' into: [:acc :e | acc , e , (String with: Character lf)])]
!
osGroups: aCollection key: aKeyBlock do: anEmitBlock on: aStream
	"anEmitBlock on the elements for every OS, then on each OS's under its guard. aKeyBlock answers an element's targetOS."
	(aCollection select: [:e | (aKeyBlock value: e) isNil]) do: anEmitBlock.
	self class targetOSes do: [:spec |
		| own |
		own := aCollection select: [:e | (aKeyBlock value: e) = (spec at: 1)].
		own notEmpty ifTrue: [
			aStream nextPutAll: '#ifdef '; nextPutAll: (spec at: 2); lf.
			own do: anEmitBlock.
			aStream nextPutAll: '#endif'; lf]]
!
includeLibraries: aCollection on: aStream seen: aSet
	"The headers of the libraries for every OS, then each OS's under its guard. What an OS's libraries include stays unseen, so that a later library for every OS still includes it."
	(aCollection select: [:lib | lib targetOS isNil]) do: [:lib | lib headers do: [:h | self include: h on: aStream seen: aSet]].
	self class targetOSes do: [:spec |
		| own seen |
		own := aCollection select: [:lib | lib targetOS = (spec at: 1)].
		own notEmpty ifTrue: [
			seen := aSet copy.
			aStream nextPutAll: '#ifdef '; nextPutAll: (spec at: 2); lf.
			own do: [:lib | lib headers do: [:h | self include: h on: aStream seen: seen]].
			aStream nextPutAll: '#endif'; lf]]
! !

!VMTranslator methodsFor: 'printing C'!
banner
	^'/* Generated by VMTranslator from the Lowtalk sources (docs/lowtalk.md). Do not edit. */'
!
structClasses
	"The structs of the translated packages; translated for one OS alone, those the translated code names (usedStructs)."
	| structs |
	structs := OrderedCollection new.
	VMStruct allSubclasses do: [:c |
		(c isExtern not and: [c ~~ ExternStruct and: [self isTranslatedPackage: c packageName]]) ifTrue: [structs add: c]].
	usedStructs notNil ifTrue: [structs := structs select: [:c | usedStructs includes: c]].
	^self sortStructs: structs
!
structsUsedBy: cFunctions
	"The structs whose C names the functions, the globals and the typedefs use, and those these structs contain or point to."
	| words s all used more |
	s := WriteStream on: String new.
	cFunctions do: [:f | f printOn: s].
	self translatedModules do: [:m | m globals do: [:g | g isModuleReference ifFalse: [s nextPutAll: (g type declare: g cName); space]]].
	self typedefs do: [:td | s nextPutAll: (td at: 2) asString; space].
	self primitives notEmpty ifTrue: [s nextPutAll: (registry at: 'PrimitiveEntry') name].
	words := self identifiersIn: s contents.
	all := VMStruct allSubclasses reject: [:c | c isExtern or: [c == ExternStruct]].
	used := IdentitySet new.
	[more := all select: [:c | (used includes: c) not and: [(words includes: c ctype name) or: [words includes: c name asString]]].
	 more notEmpty] whileTrue: [
		used addAll: more.
		more do: [:c | c fields do: [:spec |
			spec first == #union
				ifTrue: [spec allButFirst do: [:m | words addAll: (self identifiersIn: (m at: 2) asString)]]
				ifFalse: [words addAll: (self identifiersIn: (spec at: 2) asString)]]]].
	^used
!
identifiersIn: aString
	| words w |
	words := Set new.
	w := WriteStream on: String new.
	aString do: [:c |
		(c isLetter or: [c isDigit or: [c = $_]])
			ifTrue: [w nextPut: c]
			ifFalse: [
				w contents isEmpty ifFalse: [words add: w contents].
				w := WriteStream on: String new]].
	w contents isEmpty ifFalse: [words add: w contents].
	^words
!
isTranslatedPackage: aString
	^moduleClasses anySatisfy: [:m | m packageName = aString]
!
sortStructs: aCollection
	"Structs that contain others by value come after them."
	| sorted visit visiting |
	sorted := OrderedCollection new.
	visiting := Set new.
	visit := nil.
	visit := [:c |
		(sorted includes: c) ifFalse: [
			(visiting includes: c) ifTrue: [self error: 'struct cycle at ' , c name].
			visiting add: c.
			c ctype fields do: [:f |
				| t |
				t := f type.
				[t isArray] whileTrue: [t := t element].
				(t isStruct and: [aCollection includes: t structClass]) ifTrue: [visit value: t structClass]].
			sorted add: c]].
	(aCollection asSortedCollection: [:a :b | a name <= b name]) do: [:c | visit value: c].
	^sorted
!
constants
	"Every class variable of VMConstants and the modules, name -> value, sorted by name."
	| all |
	all := Dictionary new.
	(Array with: VMConstants) , self moduleClassesWithSuperclasses , self structClasses asArray do: [:c |
		c classPool keysAndValuesDo: [:k :v | (v isInteger or: [v isFloat]) ifTrue: [all at: k asString put: v]]].
	^(all associations asSortedCollection: [:a :b | a key <= b key]) asArray
!
moduleClassesWithSuperclasses
	| all |
	all := OrderedCollection new.
	moduleClasses do: [:c |
		c withAllSuperclasses do: [:each | ((each inheritsFrom: VMModule) and: [(all includes: each) not]) ifTrue: [all add: each]]].
	^all asArray
!
typedefs
	| all |
	all := OrderedCollection new.
	self moduleClassesWithSuperclasses do: [:c | ((self isPlatformClass: c) not and: [c class includesSelector: #typedefs]) ifTrue: [all addAll: c typedefs]].
	^all
!
header: cFunctions
	| s guard included |
	s := WriteStream on: String new.
	guard := headerName asUppercase , '_H'.
	os notNil ifTrue: [usedStructs := self structsUsedBy: cFunctions].
	s nextPutAll: self banner; lf.
	s nextPutAll: '#ifndef '; nextPutAll: guard; lf; nextPutAll: '#define '; nextPutAll: guard; lf; lf.
	included := Set new.
	(os isNil ifTrue: [#('<stdatomic.h>' '<stdbool.h>' '<stddef.h>' '<stdint.h>' '<string.h>')] ifFalse: [#('<stdatomic.h>' '<stdbool.h>' '<stddef.h>' '<stdint.h>' '<limits.h>')])
		do: [:h | self include: h on: s seen: included].
	self includeLibraries: self coreLibraries on: s seen: included.
	self platform: [self includeLibraries: self platformLibraries on: s seen: included] on: s.
	s lf; nextPutAll: 'typedef uint64_t oop;'; lf.
	os notNil ifTrue: [
		"the registry's built-in types that a freestanding compiler's headers lack"
		#(#(pid_t int32_t) #(off_t int64_t) #(ssize_t int64_t) #(time_t int64_t)) do: [:td |
			s nextPutAll: 'typedef '; nextPutAll: (td at: 2); space; nextPutAll: (td at: 1); nextPut: $;; lf]].
	self typedefs do: [:td |
		(td at: 2) == #opaque
			ifTrue: [s nextPutAll: 'typedef struct '; nextPutAll: (td at: 1); space; nextPutAll: (td at: 1); nextPut: $;; lf]
			ifFalse: [s nextPutAll: 'typedef '; nextPutAll: ((registry parse: (td at: 2)) declare: (td at: 1) asString); nextPut: $;; lf]].
	self platform: [
		self platformTypedefs do: [:td |
			s nextPutAll: 'typedef '; nextPutAll: ((registry parse: (td at: 2)) declare: (td at: 1) asString); nextPut: $;; lf]] on: s.
	s lf.
	self constants do: [:c |
		s nextPutAll: '#define '; nextPutAll: c key; space.
		c value isInteger
			ifTrue: [s nextPutAll: (CConst value: c value type: (registry at: ((c value between: -16r80000000 and: 16r7FFFFFFF) ifTrue: ['int'] ifFalse: [c value > 16r7FFFFFFFFFFFFFFF ifTrue: ['uint64_t'] ifFalse: ['int64_t']]))) cString]
			ifFalse: [s print: c value].
		s lf].
	s lf.
	self structClasses do: [:c | (self isPlatformClass: c) ifFalse: [s nextPutAll: 'typedef struct '; nextPutAll: c ctype name; space; nextPutAll: c ctype name; nextPut: $;; lf]].
	self platform: [self structClasses do: [:c | (self isPlatformClass: c) ifTrue: [s nextPutAll: 'typedef struct '; nextPutAll: c ctype name; space; nextPutAll: c ctype name; nextPut: $;; lf]]] on: s.
	s lf.
	self structClasses do: [:c | (self isPlatformClass: c) ifFalse: [self printStruct: c on: s]].
	self definedExternStructs do: [:c | self printExternStruct: c on: s].
	self platform: [self structClasses do: [:c | (self isPlatformClass: c) ifTrue: [self printStruct: c on: s]]] on: s.
	(self primitives notEmpty) ifTrue: [
		s nextPutAll: 'extern '; nextPutAll: (registry at: 'PrimitiveEntry') name; nextPutAll: ' vm_primitive_table[];'; lf.
		s nextPutAll: 'extern int vm_primitive_count;'; lf; lf].
	#(false true) do: [:platform |
		self platform: [
			self osGroups: (self translatedModules select: [:m | (self isPlatformModule: m) = platform]) key: [:m | m moduleClass targetOS] do: [:m |
				(m globals values asSortedCollection: [:a :b | a name <= b name]) do: [:g |
					(g isModuleReference not and: [g isRegister not and: [g isUsedOutside]]) ifTrue: [
						s nextPutAll: 'extern '; nextPutAll: (g type declare: g cName); nextPut: $;; lf]]] on: s]
			if: platform on: s].
	s lf.
	#(false true) do: [:platform |
		self platform: [
			self osGroups: (cFunctions select: [:f | f function isStatic not and: [(self isPlatformModule: f function module) = platform]])
				key: [:f | f function module moduleClass targetOS]
				do: [:f | s nextPutAll: f declaration; nextPut: $;; lf]
				on: s]
			if: platform on: s].
	(modules values select: [:m | m moduleClass isInterface]) do: [:m |
		(m functions values asSortedCollection: [:a :b | a selector <= b selector]) do: [:f |
			(f isFunction and: [(cFunctions anySatisfy: [:g | g function cName = f cName]) not]) ifTrue: [
				s nextPutAll: (f functionType prototypeNamed: f cName); nextPut: $;; lf]]].
	s lf; nextPutAll: self helpers.
	s lf; nextPutAll: '#endif'; lf.
	^s contents
!
include: aHeader on: aStream seen: aSet
	"An #include line (once), or a preprocessor line as it is."
	aHeader first = $# ifTrue: [^aStream nextPutAll: aHeader; lf].
	(aSet includes: aHeader) ifTrue: [^self].
	aSet add: aHeader.
	aStream nextPutAll: '#include '; nextPutAll: aHeader; lf
!
platform: aBlock on: aStream
	self platform: aBlock if: true on: aStream
!
platform: aBlock if: aBoolean on: aStream
	"What only the platform layer needs is left out of a headless build (no SDL headers there)."
	aBoolean ifTrue: [aStream nextPutAll: '#ifndef SAMALTAK_NO_PLATFORM'; lf].
	aBlock value.
	aBoolean ifTrue: [aStream nextPutAll: '#endif'; lf]
!
isPlatformClass: aClass
	^aClass packageName = 'VM-Platform'
!
librariesOf: aCollectionOfTModules
	"The libraries they connect to; translated for one OS alone, those they call."
	| libs |
	libs := Set new.
	aCollectionOfTModules do: [:m |
		m globals do: [:g | (g isModuleReference and: [g referencedModule inheritsFrom: CLibrary]) ifTrue: [libs add: g referencedModule]]].
	os notNil ifTrue: [^libs select: [:lib | calledLibraries notNil and: [calledLibraries includes: lib]]].
	^libs
!
coreLibraries
	^((self librariesOf: (self translatedModules reject: [:m | self isPlatformModule: m])) asSortedCollection: [:a :b | a name <= b name]) asArray
!
platformLibraries
	| core |
	core := self coreLibraries.
	^(((self librariesOf: (self translatedModules select: [:m | self isPlatformModule: m])) reject: [:lib | core includes: lib])
		asSortedCollection: [:a :b | a name <= b name]) asArray
!
platformTypedefs
	| all |
	all := OrderedCollection new.
	self moduleClassesWithSuperclasses do: [:c | ((self isPlatformClass: c) and: [c class includesSelector: #typedefs]) ifTrue: [all addAll: c typedefs]].
	^all
!
helpers
	^'static inline uint64_t lt_bits_of_double(double d)
{
    uint64_t b;
    memcpy(&b, &d, 8);
    return b;
}

static inline double lt_double_from_bits(uint64_t b)
{
    double d;
    memcpy(&d, &b, 8);
    return d;
}

static inline uint64_t lt_mul64(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t *hi)
{
    unsigned __int128 t = (unsigned __int128)a * b + c + d;
    *hi = (uint64_t)(t >> 64);
    return (uint64_t)t;
}

static inline uint64_t lt_div128(uint64_t hi, uint64_t lo, uint64_t d, uint64_t *rem)
{
#if defined(__x86_64__)
    /* hi < d: the quotient fits, divq does not trap (and no __udivti3, which UEFI builds lack) */
    uint64_t q, r;
    __asm__("divq %4" : "=a"(q), "=d"(r) : "a"(lo), "d"(hi), "rm"(d));
    *rem = r;
    return q;
#elif defined(SAMALTAK_UEFI)
    /* freestanding arm64, no __udivti3: Knuth D in two 64-by-32-bit steps, d normalized (divlu) */
    int s = __builtin_clzll(d);
    uint64_t v = d << s, vn1 = v >> 32, vn0 = v & 0xFFFFFFFFu;
    uint64_t un32 = s == 0 ? hi : (hi << s) | (lo >> (64 - s)), un10 = lo << s;
    uint64_t un1 = un10 >> 32, un0 = un10 & 0xFFFFFFFFu;
    uint64_t q1 = un32 / vn1, rhat = un32 - q1 * vn1;
    while (q1 > 0xFFFFFFFFu || q1 * vn0 > (rhat << 32) + un1) {
        q1--;
        rhat += vn1;
        if (rhat > 0xFFFFFFFFu) break;
    }
    uint64_t un21 = (un32 << 32) + un1 - q1 * v;
    uint64_t q0 = un21 / vn1;
    rhat = un21 - q0 * vn1;
    while (q0 > 0xFFFFFFFFu || q0 * vn0 > (rhat << 32) + un0) {
        q0--;
        rhat += vn1;
        if (rhat > 0xFFFFFFFFu) break;
    }
    *rem = ((un21 << 32) + un0 - q0 * v) >> s;
    return (q1 << 32) + q0;
#else
    unsigned __int128 n = ((unsigned __int128)hi << 64) | lo;
    uint64_t q = (uint64_t)(n / d);
    *rem = lo - q * d;
    return q;
#endif
}
'
!
printStruct: aStructClass on: s
	| ctype |
	ctype := aStructClass ctype.
	ctype fields do: [:f |
		((VMStruct canUnderstand: f name asSymbol) or: [VMStruct canUnderstand: (f name , ':') asSymbol]) ifTrue: [
			self error: aStructClass name , ': the field ' , f name , ' would hide a method of VMStruct in the simulator']].
	s nextPutAll: 'struct '; nextPutAll: ctype name; nextPutAll: ' {'; lf.
	aStructClass fields do: [:spec |
		(spec at: 1) == #union
			ifTrue: [
				s nextPutAll: '    union {'; lf.
				spec allButFirst do: [:m |
					s nextPutAll: '        '; nextPutAll: ((registry parse: (m at: 2)) declare: (aStructClass cNameOfField: (m at: 1))); nextPut: $;; lf].
				s nextPutAll: '    };'; lf]
			ifFalse: [
				s nextPutAll: '    '; nextPutAll: ((registry parse: (spec at: 2)) declare: (aStructClass cNameOfField: (spec at: 1))); nextPut: $;; lf]].
	s nextPutAll: '};'; lf.
	s nextPutAll: '_Static_assert(sizeof('; nextPutAll: ctype name; nextPutAll: ') == '; print: ctype size;
		nextPutAll: ', "the simulator lays out '; nextPutAll: aStructClass name; nextPutAll: ' as C does");'; lf; lf
!
definedExternStructs
	| all |
	all := OrderedCollection new.
	moduleClasses do: [:c | c definedExternStructs do: [:each | (all includes: each) ifFalse: [all add: each]]].
	^all
!
printExternStruct: anExternStructClass on: s
	"The fields the VM uses, by their C names: all there is of the struct where no system header defines it."
	s nextPutAll: anExternStructClass ctype name; nextPutAll: ' {'; lf.
	anExternStructClass fields do: [:spec |
		s nextPutAll: '    '; nextPutAll: ((registry parse: (spec at: 2)) declare: (anExternStructClass cNameOfField: (spec at: 1))); nextPut: $;; lf].
	s nextPutAll: '};'; lf; lf
!
cFileFor: aTModule functions: cFunctions
	| s globals |
	s := WriteStream on: String new.
	s nextPutAll: self banner; lf.
	s nextPutAll: '/* '; nextPutAll: aTModule name; nextPutAll: ' ('; nextPutAll: aTModule moduleClass packageName; nextPutAll: ') */'; lf.
	(aTModule moduleClass class includesSelector: #cPreamble) ifTrue: [s nextPutAll: aTModule moduleClass cPreamble; lf].
	s nextPutAll: '#include "'; nextPutAll: headerName; nextPutAll: '.h"'; lf; lf.
	aTModule moduleClass targetOS notNil ifTrue: [s nextPutAll: '#ifdef '; nextPutAll: (self class guardFor: aTModule moduleClass targetOS); lf; lf].
	globals := (aTModule globals values select: [:g | g isModuleReference not and: [g isRegister not]])
		asSortedCollection: [:a :b | a name <= b name].
	globals do: [:g |
		g isUsedOutside ifFalse: [s nextPutAll: 'static '].
		s nextPutAll: (g type declare: g cName).
		g initialValue notNil ifTrue: [s nextPutAll: ' = '; nextPutAll: (self initializer: g initialValue type: g type)].
		s nextPut: $;; lf].
	globals isEmpty ifFalse: [s lf].
	cFunctions do: [:f |
		f function isStatic ifTrue: [s nextPutAll: 'static '; nextPutAll: f declaration; nextPut: $;; lf]].
	(cFunctions anySatisfy: [:f | f function isStatic]) ifTrue: [s lf].
	cFunctions do: [:f |
		s nextPutAll: '/* '; nextPutAll: f function printString; nextPutAll: ' */'; lf.
		f printOn: s.
		s lf].
	aTModule moduleClass targetOS notNil ifTrue: [s nextPutAll: '#endif'; lf].
	^s contents
!
initializer: aLiteral type: aCType
	aLiteral isArray ifTrue: [
		^String new: 100 streamContents: [:s |
			s nextPut: ${.
			aLiteral do: [:v | s nextPutAll: (self initializer: v type: aCType element)] separatedBy: [s nextPutAll: ', '].
			s nextPut: $}]].
	aLiteral isSymbol ifTrue: [^aLiteral asString].
	aLiteral isString ifTrue: [^(CConst value: aLiteral type: aCType) cString].
	(aLiteral == true or: [aLiteral == false]) ifTrue: [^aLiteral printString].
	aLiteral isFloat ifTrue: [^(CConst value: aLiteral type: aCType) cString].
	^(CConst value: aLiteral type: aCType) cString
! !

!VMTranslator methodsFor: 'primitives'!
primitives
	"The primitive functions, sorted by number."
	| all |
	all := OrderedCollection new.
	self translatedModules do: [:m |
		m functions do: [:f | f primitive notNil ifTrue: [all add: f]]].
	^(all asSortedCollection: [:a :b | (a primitive at: 1) <= (b primitive at: 1)]) asArray
!
primitiveTableFile
	"The platform layer's rows are left out of a headless build (SAMALTAK_NO_PLATFORM)."
	| s |
	s := WriteStream on: String new.
	s nextPutAll: self banner; lf.
	s nextPutAll: '#include "'; nextPutAll: headerName; nextPutAll: '.h"'; lf; lf.
	s nextPutAll: (registry at: 'PrimitiveEntry') name; nextPutAll: ' vm_primitive_table[] = {'; lf.
	self primitives do: [:f |
		| p platform fos |
		p := f primitive.
		platform := self isPlatformModule: f module.
		fos := f module moduleClass targetOS.
		platform ifTrue: [s nextPutAll: '#ifndef SAMALTAK_NO_PLATFORM'; lf].
		fos notNil ifTrue: [s nextPutAll: '#ifdef '; nextPutAll: (self class guardFor: fos); lf].
		s nextPutAll: '    {'; print: (p at: 1); nextPutAll: ', '; print: ((p at: 3) ifTrue: [1] ifFalse: [0]) + ((p at: 4) ifTrue: [2] ifFalse: [0]);
			nextPutAll: ', '; nextPutAll: (CConst value: (p at: 2) type: nil) cString; nextPutAll: ', '; nextPutAll: f cName; nextPutAll: '},'; lf.
		fos notNil ifTrue: [s nextPutAll: '#endif'; lf].
		platform ifTrue: [s nextPutAll: '#endif'; lf]].
	s nextPutAll: '};'; lf; lf.
	s nextPutAll: 'int vm_primitive_count = sizeof vm_primitive_table / sizeof vm_primitive_table[0];'; lf.
	^s contents
!
isPlatformModule: aTModule
	^aTModule moduleClass packageName = 'VM-Platform'
!
sourcesMakefile
	"Which generated files make which VM: the core, then one platform implementation (headless, or the platform layer); each followed by its files for one OS only (VM_CORE_SOURCES_LINUX: the build adds those of its uname -s)."
	| s lists kind |
	lists := Dictionary new.
	self translatedModules do: [:m |
		kind := (self isPlatformModule: m)
			ifTrue: ['VM_PLATFORM_SOURCES']
			ifFalse: [(m moduleClass inheritsFrom: PlatformInterface) ifTrue: ['VM_HEADLESS_SOURCES'] ifFalse: ['VM_CORE_SOURCES']].
		m moduleClass targetOS notNil ifTrue: [
			kind := kind , '_' , ((self class targetOSes detect: [:spec | (spec at: 1) = m moduleClass targetOS]) at: 3)].
		(lists at: kind ifAbsentPut: [OrderedCollection new]) add: m cFileName , '.c'].
	self primitives notEmpty ifTrue: [(lists at: 'VM_CORE_SOURCES' ifAbsentPut: [OrderedCollection new]) add: 'primitive_entries.c'].
	s := WriteStream on: String new.
	s nextPutAll: '# Generated by VMTranslator. Do not edit.'; lf.
	#('VM_CORE_SOURCES' 'VM_HEADLESS_SOURCES' 'VM_PLATFORM_SOURCES') do: [:var |
		(Array with: var) , ((self class targetOSes select: [:spec | self translatedModules anySatisfy: [:m | m moduleClass targetOS = (spec at: 1)]])
			collect: [:spec | var , '_' , (spec at: 3)]) do: [:name |
			s nextPutAll: name; nextPutAll: ' :='.
			((lists at: name ifAbsent: [#()]) asSortedCollection: [:a :b | a <= b]) do: [:f | s nextPutAll: ' '; nextPutAll: f].
			s lf]].
	^s contents
! !
