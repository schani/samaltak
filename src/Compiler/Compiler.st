Object subclass: #Compiler
	instanceVariableNames: 'bindings doIt doItSource'
	classVariableNames: 'PackageDirectories RecompiledAll'
	package: 'Compiler'!

Compiler comment: 'I am the facade of the Smalltalk compiler.

	Compiler compile: ''foo ^1'' in: Object classified: ''demo''	"compile and install"
	Compiler evaluate: ''3 + 4''
	Compiler evaluate: ''x := x + 1'' for: nil bindings: aDictionary	"workspace variables: Symbol -> Association"
	Compiler new bindings: aDictionary; evaluate: ''3 + 4'' for: anObject	"as in Smalltalk-80: the do-it runs called from Compiler>>evaluate:for:"
	Compiler recompileAll	"stage 2"
	Compiler fileIn: ''path/to/File.st''	"chunk format"
	Compiler fileInPackage: ''apps/Weather''	"a directory in the format of src/<package>/"

Errors are signaled as SyntaxError.'!

!Compiler class methodsFor: 'class initialization'!
initialize
	(Smalltalk respondsTo: #addStage2Step:named:)
		ifTrue: [Smalltalk addStage2Step: [Compiler stage2] named: 'Recompile all methods']
! !

!Compiler class methodsFor: 'compiling'!
compile: aString in: aClass classified: aCategory
	"Compile a method, install it in aClass and answer it."
	| method |
	method := self compileMethod: aString in: aClass classified: aCategory.
	aClass addSelector: method selector withMethod: method.
	^method
!
compile: aString in: aClass
	^self compile: aString in: aClass classified: 'as yet unclassified'
!
compileMethod: aString in: aClass classified: aCategory
	"Compile a method without installing it."
	| method |
	method := CodeGenerator new
		generate: (Parser new parseMethod: aString)
		class: aClass
		bindings: nil.
	method category: aCategory.
	^method
!
compileDoIt: aString in: aClass bindings: aDictionaryOrNil
	"Compile a do-it as an unbound method DoIt of aClass. It answers the value of its last statement."
	^CodeGenerator new
		generate: (Parser new parseExpression: aString)
		class: aClass
		bindings: aDictionaryOrNil
! !

!Compiler class methodsFor: 'evaluating'!
evaluate: aString
	^self evaluate: aString for: nil bindings: nil
!
evaluate: aString for: anObject
	^self evaluate: aString for: anObject bindings: nil
!
evaluate: aString for: anObject bindings: aDictionaryOrNil
	"Compile aString as a do-it on anObject's class and run it with anObject as receiver. Unknown lowercase names are added to aDictionaryOrNil (Symbol -> Association) when it is not nil."
	^self new bindings: aDictionaryOrNil; evaluate: aString for: anObject
!
execute: aCompiledMethod for: anObject
	"Run aCompiledMethod (no arguments, at least one temporary) in a real method context whose sender is this context, and answer its result."
	^(Context sender: thisContext receiver: anObject method: aCompiledMethod arguments: #()) jump
! !

!Compiler methodsFor: 'evaluating'!
bindings: aDictionaryOrNil
	"Workspace variables (Symbol -> Association): unknown lowercase names in a do-it are declared there."
	bindings := aDictionaryOrNil
!
doIt: aCompiledMethod source: aString
	"aCompiledMethod is aString already compiled as a do-it (a tool compiles first to mark syntax errors in place): evaluate:for: runs it instead of compiling aString again."
	doIt := aCompiledMethod.
	doItSource := aString
!
evaluate: aString for: anObject
	"Compile aString as a do-it on anObject's class and run it with anObject as receiver, called from this context (as in Smalltalk-80, debugger stacks read DoIt, Compiler>>evaluate:for:)."
	| method |
	method := (doIt notNil and: [doItSource = aString])
		ifTrue: [doIt]
		ifFalse: [self class compileDoIt: aString in: anObject class bindings: bindings].
	^(Context sender: thisContext receiver: anObject method: method arguments: #()) jump
! !

!Compiler class methodsFor: 'stage 2'!
stage2
	| count |
	count := self recompileAll.
	self log: 'Compiler: recompiled ' , count printString , ' methods'
!
recompileAll
	"Recompile every method that has source with this compiler. All methods are compiled first and installed together, so the compiler keeps running the old code while it works. Answer the number of methods recompiled."
	| work |
	work := OrderedCollection new.
	Smalltalk allBehaviorsDo: [:behavior | self recompileMethodsOf: behavior into: work].
	work do: [:each | (each at: 1) at: (each at: 2) put: (each at: 3)].
	Object flushCache.
	RecompiledAll := true.
	^work size
!
recompileMethodsOf: aBehavior into: work
	"Add {valuesArray. index. newMethod} to work for each method of aBehavior. Uses the MethodDictionary layout (tally keys values) so installation needs no message sends."
	| dict keys values old new |
	dict := aBehavior methodDict.
	dict isNil ifTrue: [^self].
	keys := dict instVarAt: 2.
	values := dict instVarAt: 3.
	1 to: keys size do: [:i |
		old := values at: i.
		((keys at: i) notNil and: [old notNil and: [old source notNil]]) ifTrue: [
			new := [self compileMethod: old source in: aBehavior classified: old category]
				on: Error
				do: [:e |
					self log: 'Compiler: cannot recompile ' , aBehavior name , '>>' , (keys at: i) , ': ' , e messageText printString.
					nil].
			(new notNil and: [new selector == (keys at: i)])
				ifTrue: [work add: (Array with: values with: i with: new)]]]
!
hasRecompiledAll
	"Answer whether every method in the image was compiled by me (stage 2 ran)."
	^RecompiledAll == true
!
log: aString
	| transcript |
	transcript := Smalltalk at: #Transcript ifAbsent: [nil].
	transcript isNil ifFalse: [transcript show: aString; cr]
! !

!Compiler class methodsFor: 'file in'!
fileIn: aPath
	"File in a chunk-format source file."
	^self fileInString: (self contentsOfFile: aPath)
!
contentsOfFile: aPath
	| file |
	file := Smalltalk at: #File ifAbsent: [^self error: 'Compiler fileIn: needs the File class'].
	^file readText: aPath
!
fileInString: aString
	"Evaluate the chunks of aString. An empty chunk is followed by a method-category header (X methodsFor: 'cat' or X class methodsFor: 'cat') and that category's method chunks, terminated by an empty chunk."
	^self fileInString: aString except: [:chunk | false]
!
fileInString: aString except: aBlock
	"Evaluate the chunks of aString (fileInString:) but the top-level ones for which aBlock answers true."
	| reader chunk |
	reader := ChunkReader on: aString.
	[(chunk := reader nextChunk) notNil] whileTrue: [
		(reader isBlank: chunk)
			ifTrue: [
				chunk := reader nextChunk.
				chunk notNil ifTrue: [self fileInMethodsFor: chunk from: reader]]
			ifFalse: [(aBlock value: chunk) ifFalse: [self evaluate: chunk]]]
!
fileInPackage: aDirectory
	"File in a package directory in the format of src/<package>/ (a class a file, Class.extension.st for methods added to other packages' classes, read after the others) and answer the classes it defines, in definition order. Every class definition is evaluated first, a superclass before its subclasses, so methods compile against all of them; then the rest of each file; then each defined class that has a class-side initialize gets it, in definition order."
	| directory sources definitions classes pending ready |
	directory := Smalltalk at: #Directory ifAbsent: [^self error: 'Compiler fileInPackage: needs the Directory class'].
	sources := (((directory fileNames: aDirectory) select: [:f | f endsWith: '.st']) asSortedCollection: [:a :b |
		(a endsWith: '.extension.st') = (b endsWith: '.extension.st')
			ifTrue: [a <= b]
			ifFalse: [b endsWith: '.extension.st']]) asArray
		collect: [:f | self contentsOfFile: aDirectory, '/', f].
	definitions := OrderedCollection new.
	sources do: [:source |
		| reader chunk |
		reader := ChunkReader on: source.
		[(chunk := reader nextChunk) notNil] whileTrue: [
			(self classDefinitionIn: chunk) ifNotNil: [:pair | definitions add: (Array with: chunk with: pair first with: pair last)]]].
	classes := OrderedCollection new.
	pending := definitions.
	[pending isEmpty] whileFalse: [
		ready := pending select: [:d | (pending anySatisfy: [:other | (other at: 3) = (d at: 2)]) not].
		ready isEmpty ifTrue: [^self error: 'Circular superclasses in ', aDirectory].
		ready do: [:d | classes add: (self evaluate: d first)].
		pending := pending reject: [:d | ready includes: d]].
	sources do: [:source | self fileInString: source except: [:chunk | definitions anySatisfy: [:d | d first == chunk or: [d first = chunk]]]].
	classes do: [:c | (c class includesSelector: #initialize) ifTrue: [c initialize]].
	classes isEmpty ifFalse: [
		PackageDirectories isNil ifTrue: [PackageDirectories := Dictionary new].
		PackageDirectories at: classes first packageName put: aDirectory].
	^classes asArray
!
packageDirectoryOf: aPackageName
	"The directory fileInPackage: loaded the package aPackageName from (an application's, apps/Weather), or nil."
	PackageDirectories isNil ifTrue: [^nil].
	^PackageDirectories at: aPackageName ifAbsent: [nil]
!
classDefinitionIn: aChunk
	"Answer {superclass name. class name} if aChunk is a class definition (Superclass subclass: #Name ...), else nil."
	| node statement keyword |
	(aChunk includesSubstring: 'ubclass:') ifFalse: [^nil].
	node := [Parser new parseExpression: aChunk] on: SyntaxError do: [:e | ^nil].
	node body statements size = 1 ifFalse: [^nil].
	statement := node body statements first.
	statement isMessage ifFalse: [^nil].
	keyword := statement selector keywords first.
	(#('subclass:' 'variableSubclass:' 'variableByteSubclass:' 'variableWordSubclass:' 'variableDoubleWordSubclass:' 'weakSubclass:' 'immediateSubclass:') includes: keyword) ifFalse: [^nil].
	(statement receiver isVariable and: [statement arguments first isLiteral]) ifFalse: [^nil].
	^Array with: statement receiver name asString with: statement arguments first value asString
!
fileInMethodsFor: aHeader from: aChunkReader
	| target category chunk |
	target := self evaluate: (self receiverOfHeader: aHeader).
	category := (Parser new parseExpression: aHeader) body statements first arguments first value.
	[(chunk := aChunkReader nextChunk) notNil and: [(aChunkReader isBlank: chunk) not]]
		whileTrue: [self compile: (aChunkReader trim: chunk) in: target classified: category]
!
receiverOfHeader: aHeader
	"Answer the source of the receiver of a 'X methodsFor: ...' header."
	| node message |
	node := Parser new parseExpression: aHeader.
	message := node body statements isEmpty ifFalse: [node body statements first].
	(message notNil and: [message isMessage and: [message selector == #methodsFor:]])
		ifFalse: [^SyntaxError signal: 'methodsFor: expected' at: 1 in: aHeader].
	^aHeader copyFrom: message receiver start to: message receiver stop
! !

!Compiler class methodsFor: 'private'!
specialSelectorIndexOf: aSymbol
	"Answer the 1-based index of aSymbol among the special selectors (bytecodes 16rA0-16rBF), or 0."
	^CompiledMethod specialSelectors indexOf: aSymbol
! !
