Object subclass: #UIWindows
	instanceVariableNames: ''
	classVariableNames: 'StartupAction'
	package: 'UI-Windows'!

UIWindows comment: 'I start the window system. A normal start of the image (no --stage2, --test or --eval) runs my main action: unless --headless, open the host window (1440×900 points, or --window-size WxH; --hidden keeps it offscreen), start the World with its Compositor and InputDispatcher, register the World with remote control when the control server runs (--control), and run the startup action (set by the Demos or the Tools package: UIWindows startupAction: [...]). An image saved while its World ran resumes that World (World>>resumeHidden:): every window as it was, with its Process, behind a splash until they are composited again; before a quit the screen fades to black (WorldCurtain).

	UIWindows startUp          "open the World now (answers it)"
	UIWindows startupAction: [World current ...]'!

!UIWindows class methodsFor: 'class initialization'!
initialize
	Smalltalk mainAction: [self runMainAction].
	Smalltalk addToStartUpList: self.
	Smalltalk addToShutDownList: self.
	SystemChanges subscribe: #UIWindows do: [:change |
		(self isDrawingChange: change) ifTrue: [World restyleAll]].
	Renderer shaderErrorHandler: [:error | self reportShaderError: error].
	DebugSession subscribe: #UIWindows do: [:process :event |
		World allDo: [:world | world debugged: process changed: event]]
!
isDrawingChange: aSystemChange
	"Answer whether aSystemChange may change what is on the screen: views and the drawing packages."
	^(aSystemChange affects: View)
		or: [#('Graphics-Canvas' 'Graphics-GPU' 'UI-Windows' 'UI-Widgets') includes: aSystemChange theClass packageName]
!
reportShaderError: anError
	"Changed shader source did not build (the Renderer keeps its old pipeline): tell the Transcript and the user."
	| text |
	text := anError messageText asString.
	Transcript show: 'Shader not rebuilt, keeping the old one: ', text; cr.
	World current ifNotNil: [:world |
		world toast: 'Shader error, old shader kept: ', (self firstShaderErrorIn: text) duration: 6000]
!
firstShaderErrorIn: aString
	"The first compiler message of a Metal log, as 'line:column: message' (at most 90 characters)."
	| i rest stop |
	i := aString indexOfSubCollection: 'program_source:'.
	rest := i = 0 ifTrue: [aString] ifFalse: [aString copyFrom: i + 15 to: aString size].
	stop := rest findFirst: [:c | c = $; or: [c = $" or: [c = Character lf]]].
	stop > 0 ifTrue: [rest := rest copyFrom: 1 to: stop - 1].
	rest := rest copyReplaceAll: ' error:' with: ''.
	^rest size > 90 ifTrue: [(rest copyFrom: 1 to: 89), '…'] ifFalse: [rest]
!

startUp: resuming
	"A World saved in the image lost its host window, GPU objects, compositor and input dispatcher; its windows and their Processes did not. With a display it resumes as it was saved, else it is abandoned."
	(resuming and: [World current notNil]) ifFalse: [^self].
	Smalltalk isHeadless ifTrue: [^World current abandon].
	World current resumeHidden: self isHidden.
	ControlServer current isNil ifFalse: [UIRemote installOn: World current]
!
shutDown: quitting
	"Before a quit the screen visibly goes away."
	quitting ifTrue: [World current ifNotNil: [:world | world leave]]
! !

!UIWindows class methodsFor: 'starting'!
runMainAction
	"The kernel's main action. The World runs in its own Processes, so the main Process ends after the startup action. With --app the application runs instead of the World."
	Smalltalk isHeadless ifTrue: [^self runHeadless].
	(Smalltalk appClasses notEmpty or: [(Smalltalk argumentAfter: '--run') notNil]) ifTrue: [^self runApp].
	self startUp.
	self runStartupAction
!
runApp
	"--app <directory>: run the application its package defines (a subclass of Application, UI-Widgets) in a window of the host's window manager (AppWorld). --run <class name>: run that Application of the image (AgentApp)."
	| base app name |
	base := Smalltalk at: #Application ifAbsent: [nil].
	name := Smalltalk argumentAfter: '--run'.
	app := base isNil ifFalse: [
		name isNil
			ifTrue: [Smalltalk appClasses detect: [:c | c ~~ base and: [c inheritsFrom: base]] ifNone: [nil]]
			ifFalse: [(Smalltalk at: name asSymbol ifAbsent: [nil]) ifNotNil: [:c | (c isBehavior and: [c inheritsFrom: base]) ifTrue: [c]]]].
	app isNil ifTrue: [
		Smalltalk vm stderrWrite: (name isNil ifTrue: ['Samaltak: the --app package defines no Application'] ifFalse: ['Samaltak: no Application named ', name]), (String with: Character lf).
		^Smalltalk quit: 1].
	app run.
	ControlServer current isNil ifFalse: [UIRemote installOn: World current]
!
runHeadless
	"No display: keep serving remote control if it runs, else explain and quit."
	ControlServer current isNil ifFalse: [^Semaphore new wait].
	Transcript show: 'Samaltak: headless and nothing to do (use --test, --eval <expression> or --control)'; cr.
	Smalltalk quit: 0
!
startUp
	"Open the host window and the World; answer the World."
	| world |
	World current isNil ifFalse: [^World current].
	world := World openExtent: self windowSize hidden: self isHidden.
	ControlServer current isNil ifFalse: [UIRemote installOn: world].
	^world
!
runStartupAction
	[StartupAction isNil ifFalse: [StartupAction value]]
		on: Error do: [:e |
			Transcript show: 'Startup action failed: ', e messageText asString; cr.
			World current isNil ifFalse: [World current toast: 'Startup action failed: ', e messageText asString].
			e return: nil]
!
startupAction
	^StartupAction
!
startupAction: aBlock
	"What runs after the World opened."
	StartupAction := aBlock
!
windowSize
	"--window-size WxH, default 1440x900 points."
	| arg x |
	arg := Smalltalk argumentAfter: '--window-size'.
	arg isNil ifTrue: [^1440 @ 900].
	x := arg indexOf: $x.
	x = 0 ifTrue: [^1440 @ 900].
	^(Integer readFrom: (arg copyFrom: 1 to: x - 1) ifFail: [1440]) @ (Integer readFrom: (arg copyFrom: x + 1 to: arg size) ifFail: [900])
!
isHidden
	^Smalltalk vm arguments includes: '--hidden'
! !
