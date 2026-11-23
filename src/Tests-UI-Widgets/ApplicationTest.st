TestCase subclass: #ApplicationTest
	instanceVariableNames: 'previous app'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

ApplicationTest comment: 'Tests Application on a hidden host window: the window is the content''s preferred size, shows the content, and the hooks run around opening and closing; a right-click opens its menu.'!

!ApplicationTest methodsFor: 'running'!
setUp
	previous := World current
!
tearDown
	Application removeMenuItem: #test.
	(app notNil and: [app world notNil and: [app world isRunning]]) ifTrue: [app world stop].
	World current: previous.
	Profiler resume
!
timeLimitMilliseconds
	^30000
! !

!ApplicationTest methodsFor: 'tests'!
testRunOpensTheContentAtItsPreferredSize
	app := TestApplication new runHidden: true.
	self assert: app world class equals: AppWorld.
	self assert: app world extent equals: 240 @ 90.
	self assert: app window content == app content.
	self assert: app window bounds equals: (0 @ 0 extent: 240 @ 90).
	self assert: app log equals: #(#prepare #started).
	self assert: (app world waitUntilSettled: 5000).
	app stop.
	self assert: (self waitFor: [app log last == #stopped and: [app world isRunning not]])
!
testRightClickOpensTheApplicationsMenu
	"A right-click the content does not take opens the application's menu: its own items, then those every application gets."
	| center overlay menu |
	Application addMenuItem: #test with: [:application :aMenu | aMenu add: 'Every app' action: [application log]].
	app := TestApplication new runHidden: true.
	self assert: (app world waitUntilSettled: 5000).
	"(other packages add theirs: UI-Agent's Agent)"
	self assert: (app contextMenu items collect: [:each | each label]) first equals: 'Own item'.
	self assert: (app contextMenu items collect: [:each | each label]) last equals: 'Every app'.
	center := app world extent // 2.
	#(#move #down #up) with: {UIEvent evMouseMove. UIEvent evMouseDown. UIEvent evMouseUp} do: [:kind :type |
		DisplayWindow injectEvent: {type. nil. center x. center y. (kind == #move ifTrue: [0] ifFalse: [3]). 0. (kind == #move ifTrue: [nil] ifFalse: [1]). app world displayWindow windowId}].
	self assert: (self waitFor: [app world overlays notEmpty]).
	overlay := app world overlays last.
	menu := overlay content menu.
	self assert: (menu items collect: [:each | each label]) asArray equals: (app contextMenu items collect: [:each | each label]) asArray.
	app world closeMenus
!
testTitle
	self assert: TestApplication new title equals: 'Test application'.
	self assert: (Application new title) equals: 'Application'
! !
