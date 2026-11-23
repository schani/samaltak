TestCase subclass: #AgentNativeTest
	instanceVariableNames: 'previous app account'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

AgentNativeTest comment: 'Tests the Agent as a window of the host''s window manager, on hidden host windows: an application''s right-click menu offers it, it opens in a host window of its own on the application''s agentContext (the application, its window, content and world, and notes on where it runs), a second time brings it back, and closing it leaves the application running; AgentApp is the Agent alone.'!

!AgentNativeTest methodsFor: 'running'!
setUp
	previous := World current.
	account := AgentTestAccount new.
	AgentWindow account: account
!
tearDown
	World all do: [:world | ((world isKindOf: AppWorld) and: [world isMain not]) ifTrue: [world stop]].
	(app notNil and: [app world notNil and: [app world isRunning]]) ifTrue: [app world stop].
	AgentWindow account: nil.
	World current: previous.
	Profiler resume
!
timeLimitMilliseconds
	^30000
! !

!AgentNativeTest methodsFor: 'tests'!
testTheApplicationsMenuOpensTheAgentOnIt
	| item agent view context again |
	app := TestApplication new runHidden: true.
	item := app contextMenu itemLabeled: 'Agent'.
	self assert: item notNil.
	self assert: (app contextMenu items collect: [:each | each label]) asArray equals: #('Own item' 'Agent').
	agent := AgentWindow openNativeFor: app hidden: true.
	self assert: (agent isKindOf: AppWindow).
	self assert: agent world ~~ app world.
	self deny: agent world isMain.
	self assert: World current == app world.
	self assert: (agent world waitUntilSettled: 5000).
	view := agent content.
	self assert: (view isKindOf: AgentWindow).
	self assert: view origin == app.
	self assert: agent title equals: 'Agent — Test application'.
	context := view conversation context.
	self assert: context receiver == app.
	self assert: (context bindings at: #window) value == app window.
	self assert: (context bindings at: #content) value == app content.
	self assert: (context bindings at: #world) value == app world.
	self assert: (context notes includesSubstring: 'TestApplication').
	self assert: ((AgentInstructions textFor: context) includesSubstring: 'window do: [').
	again := AgentWindow openNativeFor: app hidden: true.
	self assert: again == agent.
	agent close.
	self assert: (self waitFor: [agent world isRunning not]).
	self assert: app world isRunning.
	self assert: (AgentWindow nativeWindowFor: app) isNil
!
testAgentApp
	| agentApp |
	agentApp := AgentApp new runHidden: true.
	app := agentApp.
	self assert: (agentApp window content isKindOf: AgentWindow).
	self assert: agentApp world isMain.
	self assert: agentApp world extent equals: 720 @ 640.
	self assert: agentApp window content conversation context label equals: 'Samaltak'.
	self assert: (agentApp world waitUntilSettled: 5000).
	agentApp stop.
	self assert: (self waitFor: [agentApp world isRunning not])
! !
