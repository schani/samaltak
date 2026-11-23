!SystemDictionary methodsFor: 'startup'!
bootstrapStartUp
	"The seed image starts here, in the bootstrap process (priority 40): finish what the image builder leaves to the image, then handle the command line. Never returns."
	MainProcess := Processor activeProcess.
	MainProcess name: 'main'.
	Symbol rebuildSymbolTable.
	HashedCollection rehashAll.
	self undeclared isNil ifTrue: [self at: #Undeclared put: Dictionary new].
	self initializeClassesInLoadOrder.
	self installTranscript.
	self addToStartUpList: Delay.
	self addToStartUpList: ProcessorScheduler.
	self addFirstToStartUpList: WeakRegistry.
	self addToShutDownList: WeakRegistry.
	self addToShutDownList: Delay.
	self startBackgroundProcesses.
	self processStartUpList: true.
	self processCommandLine
!
initializeClassesInLoadOrder
	"Send initialize to every class that defines it on its class side, package by package in load order, superclasses first."
	self packages do: [:package |
		package classesInLoadOrder do: [:class |
			(class class includesSelector: #initialize) ifTrue: [class initialize]]]
!
installTranscript
	(self at: #Transcript ifAbsent: [nil]) isNil
		ifTrue: [self at: #Transcript put: TranscriptStream new]
!
startBackgroundProcesses
	"Start the timer process (delays and time slicing) and the idle process (once)."
	(Delay timerProcess isNil or: [Delay timerProcess isTerminated]) ifTrue: [Delay startTimerEventLoop].
	Processor startIdleProcess.
	WeakRegistry startFinalizationProcess.
	Processor startTimeSlicer
!
processCommandLine
	"Act on the command line: --stage2 <out>; else first file in the sources of --load <path>... and --app <directory>, then --test [names], --eval <expression>, or run the main action. Never returns."
	| value |
	value := self argumentAfter: '--stage2'.
	value isNil ifFalse: [
		Runtime := self vm arguments includes: '--runtime'.
		^self stage2: value].
	self loadCommandLineSources.
	(self vm arguments includes: '--test') ifTrue: [^self runTestsAndQuit].
	value := self argumentAfter: '--eval'.
	value isNil ifFalse: [^self evaluateAndQuit: value].
	^self runMainAction
!
loadCommandLineSources
	"File in each path after --load (a package directory or a chunk-format file), then the package directory after --app, whose classes appClasses answers (the window system runs its application instead of the World). A source that does not load quits with its error on stderr."
	| compiler paths app |
	paths := self argumentsAfterEach: '--load'.
	app := self argumentAfter: '--app'.
	(paths isEmpty and: [app isNil]) ifTrue: [^self].
	compiler := self at: #Compiler ifAbsent: [nil].
	compiler isNil ifTrue: [
		self vm stderrWrite: 'Samaltak: --load and --app need the Compiler package', (String with: Character lf).
		^self quit: 1].
	[paths do: [:each | self fileInSource: each with: compiler].
	 app isNil ifFalse: [AppClasses := self fileInSource: app with: compiler]]
		on: Error do: [:e |
			self vm stderrWrite: 'Samaltak: loading failed: ', e messageText asString, (String with: Character lf).
			self quit: 1]
!
fileInSource: aPath with: aCompiler
	"File in a package directory or a chunk-format file; answer the classes a directory defined."
	((self at: #File) isDirectory: aPath) ifTrue: [^aCompiler fileInPackage: aPath].
	aCompiler fileIn: aPath.
	^#()
!
appClasses
	"The classes of the package directory after --app (none without one)."
	^AppClasses ifNil: [#()]
!
argumentAfter: aString
	"Answer the command-line argument following aString, or nil."
	| args index |
	args := self vm arguments.
	index := args indexOf: aString.
	(index = 0 or: [index = args size]) ifTrue: [^nil].
	^args at: index + 1
!
argumentsAfter: aString
	"Answer the command-line arguments following aString up to the next option."
	| args index result |
	args := self vm arguments.
	index := args indexOf: aString.
	result := OrderedCollection new.
	index = 0 ifTrue: [^result].
	index + 1 to: args size do: [:i |
		((args at: i) beginsWith: '--') ifTrue: [^result].
		result add: (args at: i)].
	^result
!
argumentsAfterEach: aString
	"Answer the command-line arguments following each occurrence of aString, each run up to the next option."
	| args result taking |
	args := self vm arguments.
	result := OrderedCollection new.
	taking := false.
	args do: [:each |
		(each beginsWith: '--')
			ifTrue: [taking := each = aString]
			ifFalse: [taking ifTrue: [result add: each]]].
	^result
!
isRuntimeImage
	"Whether I am the runtime image applications run on (src/runtime.txt, stage 2 with --runtime): lean on fonts (fallback faces read from fonts/ when first needed, nothing pre-rasterized)."
	^Runtime == true
!
isHeadless
	"Answer whether the VM was started without a display."
	^self vm arguments includes: '--headless'
!
mainProcess
	^MainProcess
!
mainAction: aBlock
	"Set what a normal start (no --stage2, --test or --eval) does; the UI opens its World here."
	MainAction := aBlock
!
runMainAction
	MainAction isNil ifTrue: [
		Transcript show: 'Samaltak: nothing to do (use --test, --eval <expression> or --stage2 <image>)'; cr.
		^self quit: 0].
	MainAction value.
	Processor terminateActive
!
evaluateAndQuit: aString
	"Evaluate aString with the Smalltalk compiler and print the result."
	| compiler result |
	compiler := self at: #Compiler ifAbsent: [nil].
	compiler isNil ifTrue: [
		self vm stderrWrite: 'Samaltak: --eval needs the Compiler package', (String with: Character lf).
		^self quit: 1].
	"An unhandled error reports itself and terminates this Process: then quit with 1, whatever else still runs (Processes the sources --load started, pending Delays)."
	[result := compiler evaluate: aString] ifCurtailed: [self quit: 1].
	Transcript show: result printString; cr.
	self quit: 0
!
runTestsAndQuit
	"Run the TestCases (all, or those of the classes and packages named after --test) and quit with 0 if all passed, else 1."
	| names result |
	RunningTests := true.
	names := self argumentsAfter: '--test'.
	result := names isEmpty
		ifTrue: [TestCase runAll]
		ifFalse: [TestCase runNamed: names].
	self quit: (result hasPassed ifTrue: [0] ifFalse: [1])
!
isRunningTests
	^RunningTests == true
! !

!SystemDictionary methodsFor: 'startup and shutdown lists'!
addToStartUpList: aClass
	"aClass will receive startUp: resuming whenever the image starts (resuming is true when it was resumed from a snapshot)."
	StartUpList isNil ifTrue: [StartUpList := OrderedCollection new].
	(StartUpList includes: aClass name) ifFalse: [StartUpList addLast: aClass name]
!
addToShutDownList: aClass
	"aClass will receive shutDown: quitting before a snapshot or quit."
	ShutDownList isNil ifTrue: [ShutDownList := OrderedCollection new].
	(ShutDownList includes: aClass name) ifFalse: [ShutDownList addLast: aClass name]
!
addFirstToStartUpList: aClass
	"Like addToStartUpList:, but aClass starts up before all others."
	self removeFromStartUpList: aClass.
	StartUpList isNil ifTrue: [StartUpList := OrderedCollection new].
	StartUpList addFirst: aClass name
!
removeFromStartUpList: aClass
	StartUpList isNil ifFalse: [StartUpList remove: aClass name ifAbsent: []]
!
removeFromShutDownList: aClass
	ShutDownList isNil ifFalse: [ShutDownList remove: aClass name ifAbsent: []]
!
startUpList
	^StartUpList ifNil: [#()]
!
shutDownList
	^ShutDownList ifNil: [#()]
!
processStartUpList: resuming
	"Tell the registered classes, in registration order, that the image started. Meanwhile isStartingUp."
	StartingUp := true.
	[self startUpList do: [:name |
		(self at: name ifAbsent: [nil]) ifNotNil: [:class | class startUp: resuming]]]
			ensure: [StartingUp := false]
!
isStartingUp
	"Is the image running its startup list? A resumed image is half restored then: e.g. its World still has the previous VM's compositor."
	^StartingUp == true
!
processShutDownList: quitting
	"Tell the registered classes, in reverse order, that the image is about to be saved or to quit."
	self shutDownList reverseDo: [:name |
		(self at: name ifAbsent: [nil]) ifNotNil: [:class | class shutDown: quitting]]
! !

!SystemDictionary methodsFor: 'snapshot and quit'!
snapshot: aPath
	"Write the image to aPath. Answer false right after writing, true when the image is later resumed from it."
	| resumed |
	self processShutDownList: false.
	resumed := self primSnapshot: aPath.
	self processStartUpList: resumed == true.
	resumed isNil ifTrue: [^self error: 'Could not write the image to ', aPath].
	^resumed
!
primSnapshot: aPath
	<primitive: 'snapshot'>
	^self primitiveFailed
!
quit
	self quit: 0
!
quit: exitCode
	"Run the shutdown list and leave the VM with exitCode."
	Transcript flush.
	[self processShutDownList: true] on: Error do: [:e | e return: nil].
	self primQuit: exitCode
!
primQuit: exitCode
	<primitive: 'quit'>
	^self primitiveFailed
! !

!SystemDictionary methodsFor: 'stage 2'!
addStage2Step: aBlock named: aString
	"Register a step of stage 2 (building the full image from the seed). Steps run in registration order; re-registering a name replaces that step in place."
	| existing |
	Stage2Steps isNil ifTrue: [Stage2Steps := OrderedCollection new].
	existing := Stage2Steps detect: [:each | each key = aString] ifNone: [nil].
	existing isNil
		ifTrue: [Stage2Steps addLast: aString -> aBlock]
		ifFalse: [existing value: aBlock]
!
removeStage2StepNamed: aString
	Stage2Steps isNil ifFalse: [Stage2Steps removeAllSuchThat: [:each | each key = aString]]
!
stage2Steps
	^Stage2Steps ifNil: [#()]
!
stage2: outPath
	"Run the stage-2 steps, then snapshot to outPath and quit. When the written image is started, continue with its command line."
	| start |
	self stage2Steps do: [:step |
		start := Time millisecondClockValue.
		Transcript show: 'stage 2: '; show: step key; show: ' ...'; flush.
		step value value.
		Transcript show: ' '; show: (Time millisecondClockValue - start) printString; show: ' ms'; cr].
	Transcript show: 'stage 2: writing '; show: outPath; cr.
	(self snapshot: outPath) ifTrue: [^self processCommandLine].
	self quit: 0
! !

!SystemDictionary methodsFor: 'error handling'!
unhandledErrorHandler
	"Answer the one-argument block run for unhandled errors (nil: print and terminate)."
	^UnhandledErrorHandler
!
unhandledErrorHandler: aBlock
	"Install aBlock (receiving the exception) as the system-wide handler of unhandled errors; the UI opens a debugger here. A process's own errorHandler takes precedence."
	UnhandledErrorHandler := aBlock
!
handleUnhandledError: anException
	"Called by UnhandledError>>defaultAction. The answer resumes anException."
	| handler |
	handler := Processor activeProcess errorHandler.
	handler isNil ifTrue: [handler := UnhandledErrorHandler].
	handler isNil ifTrue: [^self defaultUnhandledError: anException].
	^handler value: anException
!
defaultUnhandledError: anException
	"Print the error and the stack on stderr. Quit with 1 when running tests or when it happened in the main process; otherwise terminate the faulting process."
	| process |
	ErrorDepth := (ErrorDepth ifNil: [0]) + 1.
	ErrorDepth > 2 ifTrue: [
		self vm stderrWrite: 'Samaltak: recursive error while reporting an error', (String with: Character lf).
		self primQuit: 1].
	[self vm stderrWrite: (self errorReportFor: anException)]
		ensure: [ErrorDepth := ErrorDepth - 1].
	process := Processor activeProcess.
	(RunningTests == true or: [process == MainProcess]) ifTrue: [self quit: 1].
	process terminate
!
errorReportFor: anException
	"Answer the error and the stack of its signaler as text."
	| lf ctx |
	lf := String with: Character lf.
	^String new: 1000 streamContents: [:s |
		s nextPutAll: 'Error: '; nextPutAll: ([anException printString] on: Error do: [:e | e return: anException class name]); nextPutAll: lf.
		s nextPutAll: 'Process: '; nextPutAll: Processor activeProcess name; nextPutAll: lf.
		ctx := anException signalerContext.
		ctx isNil ifFalse: [ctx printStackOn: s limit: 40]]
!
handleWarning: aWarning
	"Default action of Warning: report it and resume with nil."
	Transcript show: 'Warning: '; show: aWarning messageText; cr.
	^nil
! !
