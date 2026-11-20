ToolsTestCase subclass: #AgentWindowTest
	instanceVariableNames: 'account provider debugged'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

AgentWindowTest comment: 'I test the Agent window in a real World without a network: a ScriptedProvider answers, an AgentTestAccount signs in. ⌘J in a Workspace (its variables shared with the cells, a second ⌘J brings the window back), every tool''s context (and ⌘J in the Process Browser, the System Browser, the Breakpoints window and the Profiler), the transcript''s views for a turn, Inspect, Stop, and the login card.'!

!AgentWindowTest methodsFor: 'running'!
setUp
	super setUp.
	account := AgentTestAccount new.
	AgentWindow account: account.
	provider := ScriptedProvider new
!
tearDown
	(self windowsOf: AgentWindow) do: [:w | w content conversation stop].
	debugged isNil ifFalse: [debugged terminate].
	AgentWindow account: nil.
	super tearDown
! !

!AgentWindowTest methodsFor: 'support'!
openAgent
	^self open: [AgentWindow openOn: (AgentConversation new provider: provider; yourself) origin: nil in: (100 @ 60 extent: 720 @ 700)]
!
ask: aString in: anAgentWindow
	"Type aString into the ASK editor and press Return, as the user does; wait for the turn and the transcript."
	| view asked |
	view := anAgentWindow content.
	asked := view conversation items size.
	self in: anAgentWindow do: [view askEditor text: aString; focus].
	self settle.
	self key: #return modifiers: 0.
	self assert: (self waitFor: [view conversation items size > asked and: [view conversation isBusy not]]) description: 'the turn did not end'.
	self assert: (self waitFor: [anAgentWindow queue isEmpty and: [(self kindsIn: anAgentWindow) size = (self shownItemsIn: view)]]) description: 'the transcript did not follow'
!
shownItemsIn: anAgentWindowView
	^(anAgentWindowView conversation items reject: [:each | each kind == #reasoning]) size
!
kindsIn: anAgentWindow
	^(self in: anAgentWindow do: [anAgentWindow content transcript children collect: [:each | each item kind]]) asArray
!
named: aString in: aWidget
	"The widget named aString in aWidget's tree, as remote control finds it."
	aWidget name = aString ifTrue: [^aWidget].
	aWidget children do: [:each | (self named: aString in: each) ifNotNil: [:found | ^found]].
	^nil
!
frameOf: x
	"Stop in a frame with an argument and a temporary."
	| y |
	y := x + 1.
	Processor activeProcess suspend.
	^y
!
errorIn: x
	"Fail (ZeroDivide) in a frame with an argument and a temporary."
	| y |
	y := x + 1.
	^y / 0
!
suspendedInFrameOf: x
	"debugged, suspended in frameOf: x; answer that frame."
	| frame |
	debugged := [self frameOf: x] newProcess.
	debugged resume.
	self assert: (self waitFor: [debugged isSuspended]).
	frame := debugged suspendedContext.
	[frame method selector == #frameOf:] whileFalse: [frame := frame sender].
	^frame
!
commandJIn: aWindow
	"Press ⌘J in aWindow; answer the Agent window it opened for aWindow's tool."
	| agent |
	self in: aWindow do: [aWindow focus].
	self assert: (self waitFor: [world activeWindow == aWindow]).
	self settle.
	self key: $j modifiers: self commandModifier.
	self assert: (self waitFor: [(self windowsOf: AgentWindow) size = 1]) description: '⌘J opened no Agent window'.
	agent := (self windowsOf: AgentWindow) first.
	self assert: (self waitFor: [agent isOpen and: [agent queue isEmpty]]).
	self assert: agent content origin == aWindow content.
	^agent
!
valueOf: aSymbol in: anAgentContext
	^(anAgentContext bindings at: aSymbol) value
! !

!AgentWindowTest methodsFor: 'tests'!
testCommandJInAWorkspace
	| ws agent conversation |
	ws := self openWorkspaceWith: 'p := 3 @ 4'.
	self evaluate: 'p := 3 @ 4' in: ws mode: #do.
	self key: $j modifiers: self commandModifier.
	self assert: (self waitFor: [(self windowsOf: AgentWindow) size = 1]) description: '⌘J opened no Agent window'.
	agent := (self windowsOf: AgentWindow) first.
	self assert: (self waitFor: [agent isOpen and: [agent queue isEmpty]]).
	self assert: agent title equals: 'Agent — Workspace'.
	self assert: agent content origin == ws content.
	conversation := agent content conversation.
	self assert: conversation context bindings == ws content bindings.
	self assert: conversation context selection equals: 'p := 3 @ 4'.
	provider reply: {ScriptedProvider code: 'p := p * 2' call: 'c1'}.
	provider reply: {ScriptedProvider message: 'Doubled.'}.
	self in: agent do: [conversation provider: provider].
	self ask: 'double p' in: agent.
	self assert: (ws content bindings at: #p) value equals: 6 @ 8.
	"A second ⌘J in the Workspace brings the same window back."
	self in: ws do: [ws focus. ws content editor focus].
	self assert: (self waitFor: [world activeWindow == ws]).
	self settle.
	self key: $j modifiers: self commandModifier.
	self assert: (self waitFor: [world activeWindow == agent]) description: 'the Agent window did not come back'.
	self assert: (self windowsOf: AgentWindow) size equals: 1.
	self assert: (ToolsMenu labels includes: 'Agent')
!
testInspectorContext
	| inspector context |
	inspector := self open: [Inspector openOn: 3 @ 4 in: (100 @ 100 extent: 450 @ 290) bindings: nil].
	context := self in: inspector do: [inspector content agentContext].
	self assert: context receiver equals: 3 @ 4.
	self assert: context label equals: 'Inspector: a Point'.
	self assert: (self valueOf: #field in: context) equals: 3 @ 4.
	context := self in: inspector do: [inspector content fieldList select: (inspector content fieldNamed: 'y'). inspector content agentContext].
	self assert: (self valueOf: #field in: context) equals: 4.
	self assert: (context describe includesSubstring: 'field = 4 (SmallInteger)')
!
testDebuggerContext
	| debugger context frame |
	debugged := [self frameOf: 41] newProcess.
	debugged resume.
	self assert: (self waitFor: [debugged isSuspended]).
	debugger := self open: [Debugger openOn: (DebugSession debugProcess: debugged)].
	frame := debugged suspendedContext.
	[frame method selector == #frameOf:] whileFalse: [frame := frame sender].
	context := self in: debugger do: [debugger content selectFrame: frame. debugger content agentContext].
	self assert: context frame == frame.
	self assert: (context label beginsWith: 'Debugger: ').
	self assert: (context evaluate: 'x + y' bindings: Dictionary new) equals: 83.
	self assert: context receiver == self
!
testATurnShowsItsItems
	| agent views shown inspectors |
	agent := self openAgent.
	provider reply: {ScriptedProvider code: 'Form extent: 40 @ 20' call: 'c1'. ScriptedProvider code: '3 + 4' call: 'c2'}.
	provider reply: {ScriptedProvider show: 'o1' call: 'c3'. ScriptedProvider show: 'o2' call: 'c4'}.
	provider reply: {ScriptedProvider code: '3 zork' call: 'c5'}.
	provider reply: #('Se' 'ven.') items: {ScriptedProvider message: 'Seven.'}.
	self ask: 'show me' in: agent.
	self assert: (self kindsIn: agent) equals: #(#user #code #code #show #user #show #code #assistant).
	views := self in: agent do: [agent content transcript children asArray].
	self assert: (views at: 2) item result equals: 'o1 a Form(40x20)'.
	self assert: (views at: 4) isForm.
	self deny: (views at: 6) isForm.
	self assert: (views at: 6) remoteLabel equals: 'o2 7'.
	self assert: (views at: 7) item failed.
	self assert: (views last remoteLabel) equals: 'Seven.'.
	self assert: ((views collect: [:each | each height]) allSatisfy: [:h | h > 0]).
	"Inspect opens the real Inspector on the shown object."
	shown := views at: 6.
	self in: agent do: [(self named: 'inspect' in: shown) click].
	self assert: (self waitFor: [(self windowsOf: Inspector) notEmpty]) description: 'Inspect opened no Inspector'.
	inspectors := self windowsOf: Inspector.
	self assert: inspectors first content object equals: 7.
	self assert: (self in: agent do: [agent content askEditor text]) equals: ''
!
testStop
	| agent conversation |
	agent := self openAgent.
	conversation := agent content conversation.
	provider block.
	self in: agent do: [agent content askEditor text: 'wait'. agent content send].
	self assert: conversation isBusy.
	self in: agent do: [(self named: 'stop' in: agent content) click].
	self assert: (self waitFor: [conversation isBusy not]).
	self assert: (self waitFor: [(self kindsIn: agent) = #(#user #error)]).
	self assert: conversation items last text equals: 'Stopped.'
!
testSignInFromTheLoginCard
	| agent view card |
	account signOut.
	agent := self openAgent.
	view := agent content.
	card := view loginCard.
	self assert: card isVisible.
	self deny: view transcript owner isVisible.
	self in: agent do: [card signInButton click].
	self assert: (self waitFor: [(self in: agent do: [card code]) = 'TEST-1234']) description: 'no code on the card'.
	account approve.
	self assert: (self waitFor: [self in: agent do: [card isVisible not and: [view transcript owner isVisible]]]) description: 'the transcript did not come back'.
	self assert: account isSignedIn
!
testClosingCancelsTheLogin
	| agent |
	account signOut.
	agent := self openAgent.
	self in: agent do: [agent content loginCard signInButton click].
	self assert: (self waitFor: [account isLoginPending]).
	agent close.
	self assert: (self waitFor: [account isLoginPending not]) description: 'the login was not cancelled'.
	self deny: account isSignedIn
!
testImageAttachment
	| editor item content |
	editor := AgentInputEditor new.
	editor attach: #[1 2 3] mime: 'image/png'.
	self assert: editor images size equals: 1.
	item := AgentItem user: '' images: editor images.
	content := item wire first at: 'content'.
	self assert: (content last at: 'type') equals: 'input_image'.
	self assert: (content last at: 'image_url') equals: 'data:image/png;base64,AQID'.
	editor clearImages.
	self assert: editor images isEmpty
!
testCommandJInAnAgentWindow
	| parent child context |
	parent := self openAgent.
	child := self open: [AgentWindow openFor: parent content].
	self assert: child ~~ parent.
	self assert: child content origin == parent content.
	context := child content conversation context.
	self assert: context receiver == parent content.
	self assert: (context bindings at: #conversation) value == parent content conversation.
	self assert: (AgentWindow openFor: parent content) == child
!
testRemovingImageAttachments
	| editor |
	editor := AgentInputEditor new.
	editor text: 'Keep this text'.
	editor attach: #[1 2 3] mime: 'image/png'.
	editor attach: #[4 5 6] mime: 'image/png'.
	self assert: editor images size equals: 2.
	editor clearImages.
	self assert: editor images isEmpty.
	self assert: editor text equals: 'Keep this text'
!
testCachePercentageUsesCumulativeTotalTokens
	"Output tokens do not enter the cumulative cache percentage."
	| c window |
	c := AgentConversation new.
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 10000; at: 'total_tokens' put: 20000; at: 'input_tokens_details' put: (Dictionary new at: 'cached_tokens' put: 8000; yourself); yourself).
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 30000; at: 'total_tokens' put: 30000; at: 'input_tokens_details' put: (Dictionary new at: 'cached_tokens' put: 12000; yourself); yourself).
	window := AgentWindow new.
	self assert: (window cacheUsageText: c usage) = '50% cached'
!
testCachePercentageRequiresContextBeyondTenThousand
	| c window |
	c := AgentConversation new.
	window := AgentWindow new.
	self assert: (window cacheUsageText: c usage) isNil.
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 10000; at: 'input_tokens_details' put: (Dictionary new at: 'cached_tokens' put: 5000; yourself); yourself).
	self assert: (window cacheUsageText: c usage) isNil.
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 10001; at: 'input_tokens_details' put: (Dictionary new at: 'cached_tokens' put: 5000; yourself); yourself).
	self assert: (window cacheUsageText: c usage) = '50% cached'
! !

!AgentWindowTest methodsFor: 'tests - contexts'!
testProcessBrowserContext
	| frame browser context |
	frame := self suspendedInFrameOf: 41.
	browser := self open: [ProcessBrowser openIn: (100 @ 100 extent: 530 @ 340)].
	context := self in: browser do: [
		browser content selectProcess: debugged.
		browser content stackList select: frame.
		browser content agentContext].
	self assert: context receiver == debugged.
	self assert: (self valueOf: #context in: context) == frame.
	self assert: context frame isNil.
	self assert: context label equals: 'Process Browser'
!
testCommandJInAProcessBrowser
	| frame browser context |
	frame := self suspendedInFrameOf: 41.
	browser := self open: [ProcessBrowser openIn: (100 @ 100 extent: 530 @ 340)].
	self in: browser do: [browser content selectProcess: debugged. browser content stackList select: frame].
	context := (self commandJIn: browser) content conversation context.
	self assert: context receiver == debugged.
	self assert: (self valueOf: #context in: context) == frame.
	self assert: (context describe includesSubstring: 'context = AgentWindowTest>>frameOf:')
!
testToolsNotifierContext
	| saved session notifier stack frame context |
	saved := DebugSession openerBlock.
	DebugSession openerBlock: [:each | session := each].
	[debugged := [self errorIn: 41] newProcess.
	 debugged resume.
	 self assert: (self waitFor: [session notNil and: [debugged isSuspended]])]
		ensure: [DebugSession openerBlock: saved].
	notifier := self open: [ToolsNotifier openOn: session].
	stack := self named: 'stack' in: notifier content.
	context := self in: notifier do: [
		frame := stack items detect: [:each | each selector == #errorIn:].
		stack select: frame.
		notifier content agentContext].
	self assert: context frame == frame.
	self assert: context receiver == self.
	self assert: (self valueOf: #session in: context) == session.
	self assert: ((self valueOf: #exception in: context) isKindOf: ZeroDivide).
	self assert: (context evaluate: '{y. exception class}' bindings: Dictionary new) equals: {42. ZeroDivide}.
	self assert: context label equals: session label
!
testSystemBrowserContext
	| browser context |
	browser := self open: [SystemBrowser openIn: (40 @ 60 extent: 866 @ 468) onClass: OrderedCollection selector: #add:].
	context := self in: browser do: [browser content code selectFrom: 1 to: 4. browser content agentContext].
	self assert: context receiver == (OrderedCollection >> #add:).
	self assert: (self valueOf: #behavior in: context) == OrderedCollection.
	self assert: (self valueOf: #selector in: context) equals: #add:.
	self assert: (self valueOf: #method in: context) == (OrderedCollection >> #add:).
	self assert: (self valueOf: #package in: context) == browser content selectedPackage.
	self assert: context selection equals: 'add:'.
	self assert: context label equals: 'System Browser: OrderedCollection'.
	context := self in: browser do: [browser content selectSide: #class. browser content agentContext].
	self assert: context receiver == OrderedCollection class.
	self deny: (context bindings includesKey: #selector).
	self assert: context selection isNil
!
testCommandJInASystemBrowser
	| browser context |
	browser := self open: [SystemBrowser openIn: (40 @ 60 extent: 866 @ 468) onClass: OrderedCollection selector: #add:].
	context := (self commandJIn: browser) content conversation context.
	self assert: context receiver == (OrderedCollection >> #add:).
	self assert: (self valueOf: #method in: context) == (OrderedCollection >> #add:)
!
testMethodBrowserContext
	| browser list context |
	browser := self open: [MethodBrowser open: (Smalltalk implementorsOf: #agentContext) label: 'Implementors of #agentContext'].
	list := self named: 'methods' in: browser content.
	context := self in: browser do: [(self named: 'code' in: browser content) selectFrom: 1 to: 12. browser content agentContext].
	self assert: (self valueOf: #methods in: context) equals: list items.
	self assert: (self valueOf: #method in: context) == list items first.
	self assert: context selection equals: 'agentContext'.
	self assert: context receiver isNil.
	self assert: context label equals: 'Implementors of #agentContext'
!
testFileBrowserContext
	| window browser context |
	window := self open: [FileBrowser openOn: 'src/Tools-Agent/AgentWindow.st' at: 60 @ 60].
	browser := window content.
	context := self in: window do: [browser viewer selectFrom: 1 to: 12. browser agentContext].
	self assert: ((self valueOf: #path in: context) endsWith: '/src/Tools-Agent/AgentWindow.st').
	self assert: (self valueOf: #entry in: context) == browser file.
	self assert: context selection equals: 'ToolPane sub'.
	context := self in: window do: [browser reveal: 'src/Tools-Agent'. browser agentContext].
	self assert: ((self valueOf: #path in: context) endsWith: '/src/Tools-Agent').
	self assert: context selection isNil.
	self assert: context label equals: 'File Browser: Tools-Agent'
!
testTerminalContext
	| window terminal context |
	window := self open: [Terminal openOn: #('/bin/sh' '-c' 'printf "hello agent\n"; sleep 30') in: '/' at: 100 @ 80].
	terminal := window content.
	[self assert: (self waitFor: [terminal screen text includesSubstring: 'hello agent'] timeout: 20000).
	 context := self in: window do: [| row |
		row := terminal screen scrolledTotal + 1.
		terminal view select: (Array with: row with: 1) to: (Array with: row with: 5).
		terminal agentContext].
	 self assert: (self valueOf: #terminal in: context) == terminal.
	 self assert: ((self valueOf: #text in: context) includesSubstring: 'hello agent').
	 self assert: context selection equals: 'hello']
		ensure: [window close]
!
testTranscriptContext
	| window context |
	Transcript show: 'agent context'; cr.
	window := self open: [TranscriptView openIn: (700 @ 100 extent: 500 @ 200)].
	self assert: (self waitFor: [window content text includesSubstring: 'agent context']).
	context := self in: window do: [window content editor selectFrom: 1 to: 3. window content agentContext].
	self assert: (self valueOf: #text in: context) equals: window content text.
	self assert: context selection equals: (window content text first: 3).
	self assert: context label equals: 'Transcript'
!
testVMRebuilderContext
	| tool editor context |
	tool := VMRebuilder openAt: 100 @ 100.
	self open: [tool window].
	editor := self named: 'output' in: tool.
	context := self in: tool window do: [editor text: 'built build/samaltak'. editor selectFrom: 7 to: 11. tool agentContext].
	self assert: (self valueOf: #output in: context) equals: 'built build/samaltak'.
	self assert: context selection equals: 'build'.
	self assert: context label equals: 'VM Rebuild'
!
testVMSimulatorContext
	| window editor context |
	window := self open: [VMSimulator openAt: 100 @ 100].
	editor := self named: 'output' in: window content.
	context := self in: window do: [editor text: 'Samaltak VM'. editor selectFrom: 10 to: 11. window content agentContext].
	self assert: (self valueOf: #output in: context) equals: 'Samaltak VM'.
	self assert: context selection equals: 'VM'.
	self assert: context label equals: 'VM Simulator'
!
testSystemMonitorContext
	| window context |
	window := self open: [SystemMonitor open].
	context := self in: window do: [window content agentContext].
	self assert: context receiver == window content data.
	self assert: context label equals: 'System Monitor'
!
testCommandJInTheBreakpointsWindow
	| breakpoint window context |
	breakpoint := Breakpoint on: AgentWindowTest selector: #frameOf:.
	window := self open: [BreakpointsBrowser open].
	self in: window do: [window content list select: breakpoint].
	context := (self commandJIn: window) content conversation context.
	self assert: context receiver equals: window content list items.
	self assert: (self valueOf: #breakpoint in: context) == breakpoint.
	self assert: context label equals: 'Breakpoints'
!
testCommandJInTheProfiler
	| window view process range context |
	window := ProfilerView open.
	view := window content.
	[self assert: (self waitFor: [window isOpen and: [view data notNil]]).
	 self in: window do: [
		process := Processor activeProcess.
		view selectFilter: process.
		range := Array with: view data now - 500000 with: view data now.
		view dragRange: range final: true refilter: true].
	 context := (self commandJIn: window) content conversation context.
	 self assert: context receiver == view data.
	 self assert: (self valueOf: #range in: context) equals: range.
	 self assert: (self valueOf: #process in: context) == process.
	 self assert: context label equals: 'Profiler']
		ensure: [window close]
! !
