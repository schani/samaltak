TestCase subclass: #DebuggerUITest
	instanceVariableNames: 'world previous savedOpener savedErrorHandler savedRegistry savedPointer savedWindowId cleanups lastResponse'
	classVariableNames: ''
	package: 'Tests-Tools-Debugger'!

DebuggerUITest comment: 'End-to-end tests of the debugging tools in a real World on a hidden host window: code runs in a workspace (the core tools'' Workspace when loaded, else DebuggerTestWorkspace) in its own ''Workspace doIt'' Process, every interaction is real input injected through remote control (clicks and keys on refs like @w4.over, @w4.context.evaluator, @menu.integer), and the tests check the live Debugger, Notifier and Breakpoints windows and the debugged Processes. The walkthrough scenarios: a breakpoint on Integer>>gcd:, stepping Over by statements, a temporary''s value, a + b printed in the frame, Proceed; 3 zork, Create in Integer, edit and accept, Proceed; a watchpoint on p := 3 @ 4 hit by a forked mover, Unwatch, Proceed.'!

!DebuggerUITest class methodsFor: 'probe'!
testSelectors
	| only |
	only := Smalltalk vm getenv: 'SAMALTAK_PROBE_ONLY'.
	^(only isNil or: [only isEmpty]) ifTrue: [super testSelectors] ifFalse: [Array with: only asSymbol]
! !

!DebuggerUITest methodsFor: 'running'!
setUp
	cleanups := OrderedCollection new.
	previous := World current.
	savedOpener := DebugSession openerBlock.
	savedErrorHandler := Window errorHandler.
	world := World openHidden: 1440 @ 900.
	savedRegistry := RemoteControl registryState.
	savedPointer := RemoteInputDevice default pointer.
	savedWindowId := RemoteInputDevice default windowId.
	UIRemote installOn: world.
	DebuggerTools install.
	world waitUntilSettled: 3000
!
tearDown
	"Whatever closing the windows does, the World stops and what setUp and the test replaced comes back: a World left running composites, records frames and takes remote input during the tests after this one, with this test's breakpoints still set."
	(((Smalltalk vm getenv: 'SAMALTAK_PROBE') ifNil: ['']) = 'leak-raw' and: [testSelector == #testFullStackIntoRestartRunToHere]) ifTrue: [
		"As before the tearDown was protected: this World stays."
		world windows first close.
		self error: 'probe: tearDown cut short after closing the first window, the World left running'].
	[((Smalltalk vm getenv: 'SAMALTAK_PROBE') = 'leak' and: [testSelector == #testFullStackIntoRestartRunToHere]) ifTrue: [
		world windows first close.
		self error: 'probe: tearDown cut short after closing the first window'].
	 self trackDoIts.
	 world windows copy do: [:each | each close].
	 world waitUntilSettled: 2000.
	 self terminateForkedProcesses]
		ensure: [
			cleanups reverseDo: [:each | [each value] on: Error do: [:e | e return: nil]].
			UIRemote uninstall.
			RemoteControl registryState: savedRegistry.
			RemoteInputDevice default pointer: savedPointer; windowId: savedWindowId.
			world stop.
			World current: previous.
			DebugSession openerBlock: savedOpener.
			Window errorHandler: savedErrorHandler]
!
timeLimitMilliseconds
	^60000
! !

!DebuggerUITest methodsFor: 'remote control'!
remote: aCommand with: pairs
	| request response |
	request := Dictionary new.
	request at: 'cmd' put: aCommand.
	pairs do: [:each | request at: each key put: each value].
	"Remote input reduces Fractions (Integer>>gcd:): never stop at the tests' own breakpoints here."
	response := Breakpoint ignoreDuring: [RemoteControl dispatch: (RemoteRequest on: request)].
	lastResponse := aCommand -> response.
	self assert: (response at: 'ok') description: aCommand, ' ', pairs printString, ' failed: ', (response at: 'error' ifAbsent: ['?']) asString.
	^response
!
click: aRef
	^self remote: 'click' with: {'target' -> aRef}
!
rightClick: aRef
	^self remote: 'click' with: {'target' -> aRef. 'button' -> 'right'}
!
type: aString in: aRef
	^self remote: 'type' with: {'target' -> aRef. 'text' -> aString}
!
key: aCombo in: aRef
	^self remote: 'key' with: {'target' -> aRef. 'combo' -> aCombo}
!
select: aSpec in: aRef
	^self remote: 'select' with: {'target' -> aRef. 'spec' -> aSpec}
!
ref: aWindow at: aString
	^'@', aWindow remoteName, aString
! !

!DebuggerUITest methodsFor: 'support'!
waitFor: aBlock description: aString
	| ok |
	ok := self waitFor: aBlock timeout: 10000.
	ok ifFalse: [
		self probeDump: aString.
		(Delay forMilliseconds: 3000) wait.
		self probeDump: aString, ' (3 s later)'].
	self assert: ok description: ['timed out waiting for ', aString, ' (', self windowStates, ')']
!
probeLine: aBlock
	[Transcript show: 'PROBE ', aBlock value asString; cr] on: Error do: [:e |
		Transcript show: 'PROBE (error: ', ([e messageText asString] on: Error do: [:e2 | e2 return: e class name]), ')'; cr.
		e return: nil]
!
probeStack: aProcess named: aString
	self probeLine: ['stack of ', aString, ': ', aProcess printString, ' state ', (RemoteControl processStateName: aProcess)].
	[| frames |
	 frames := aProcess stack.
	 (frames copyFrom: 1 to: (frames size min: 16)) do: [:ctx | self probeLine: ['    ', ctx printString]]] on: Error do: [:e | self probeLine: ['    (no stack: ', e messageText asString, ')']. e return: nil]
!
probeDump: aString
	| d |
	self probeLine: ['---- ', testSelector, ' timed out waiting for ', aString].
	self probeLine: ['last response: ', lastResponse printString].
	world windows do: [:w |
		self probeLine: ['window ', w remoteName printString, ' ', w title printString, ' ', w content class name, ' process=', w processState, ' readOnly=', w isReadOnlyObject printString, ' pending=', w hasPendingWork printString, ' busy=', w isBusy printString, ' focused=', w isFocused printString, ' bounds=', w bounds printString, ' keyboardFocus=', w keyboardFocus printString].
		self probeLine: ['    text: ', ((w content widgetNamed: 'text') ifNil: ['(none)'] ifNotNil: [:e | e text printString])].
		self probeStack: w process named: 'window ', w title].
	self probeLine: ['closing ', world closingWindows size printString, ' overlays ', world overlays size printString, ' active ', (world activeWindow ifNil: ['nil'] ifNotNil: [:w | w title printString]), ' keyTarget ', (world keyTarget ifNil: ['nil'] ifNotNil: [:w | w title printString]), ' settled ', world isSettled printString, ' current ', (World current == world) printString].
	d := world dispatcher.
	self probeLine: ['dispatcher idle=', d isIdle printString, ' standIn=', d standIn printString, ' gesture=', d gesture printString, ' pressed=', (d instVarNamed: 'pressed') printString, ' capture=', (d instVarNamed: 'captureWindow') printString, ' inbox=', (d instVarNamed: 'inbox') size printString, ' excess=', (d instVarNamed: 'semaphore') excessSignals printString, ' running=', (d instVarNamed: 'running') printString, ' pointer=', d pointer printString, ' dispatchers=', InputDispatcher running size printString, ' last=', (InputDispatcher running last == d) printString].
	self probeStack: d process named: 'dispatcher'.
	self probeLine: ['watchpoints ', Watchpoint all printString, ' remote pointer ', RemoteInputDevice default pointer printString].
	Processor allProcesses do: [:p |
		self probeLine: ['process ', p name printString, ' pri ', p priority printString, ' ', (RemoteControl processStateName: p)]]
!
windowStates
	"The open windows, each with the state of its Process: a window whose Process is suspended (a Notifier holds it) takes no input."
	^String new: 100 streamContents: [:s |
		world windows
			do: [:each | s nextPutAll: each title; nextPutAll: ': '; nextPutAll: each processState]
			separatedBy: [s nextPutAll: ', ']]
!
trackDoIts
	"Have the workspaces' do-its (and the Processes the core Workspace's do-its forked) terminated after the test."
	world windows do: [:w | | c |
		c := w content.
		(c respondsTo: #evaluator) ifTrue: [(c evaluator running asArray, c evaluator children asArray) do: [:p | self track: p]].
		(c isKindOf: DebuggerTestWorkspace) ifTrue: [c processes do: [:p | self track: p]]]
!
windowOf: aClass
	^world windows detect: [:each | each isOpen and: [each content isKindOf: aClass]] ifNone: [nil]
!
waitForWindowOf: aClass
	self waitFor: [(self windowOf: aClass) notNil] description: 'a ', aClass name, ' window'.
	world waitUntilSettled: 3000.
	^self windowOf: aClass
!
waitUntilReady: aWindow
	self waitFor: [aWindow isBusy not and: [aWindow hasPendingWork not]] description: aWindow title, ' to finish'
!
openWorkspace: aString
	| tools w |
	tools := Smalltalk at: #Tools ifAbsent: [nil].
	w := (tools notNil and: [tools respondsTo: #openWorkspaceWith:])
		ifTrue: [tools openWorkspaceWith: aString]
		ifFalse: [DebuggerTestWorkspace openOn: aString in: world].
	world waitUntilSettled: 3000.
	^w
!
editorOf: aWorkspaceWindow
	^aWorkspaceWindow content widgetNamed: 'text'
!
textOf: aWorkspaceWindow
	^(self editorOf: aWorkspaceWindow) text
!
evaluateLine: anInteger in: aWorkspaceWindow with: aCombo
	| ref |
	ref := self ref: aWorkspaceWindow at: '.text'.
	self click: ref.
	self select: 'line:', anInteger printString in: ref.
	self key: aCombo in: ref
!
pcTextOf: aDebugger
	| interval |
	interval := aDebugger pcInterval.
	interval isNil ifTrue: [^nil].
	^aDebugger sourceEditor text copyFrom: interval first to: interval last
!
breakpointOn: aClass selector: aSymbol
	| bp |
	bp := Breakpoint on: aClass selector: aSymbol.
	cleanups add: [bp remove].
	^bp
!
openDebuggerOnGcd
	"A breakpoint on Integer>>gcd: and 48 gcd: 18 printed in a workspace: answer {workspace window. debugger window}."
	| ws dw |
	self breakpointOn: Integer selector: #gcd:.
	ws := self openWorkspace: '48 gcd: 18'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	dw := self waitForWindowOf: Debugger.
	^Array with: ws with: dw
! !

!DebuggerUITest methodsFor: 'tests: system processes'!
testBreakpointHaltsOnlyOneWindowsProcess
	"A conditional breakpoint in Window>>redraw scoped to all processes, true for one window: only that window's Process stops (in a Debugger); the other windows keep working; removing the breakpoint and Proceed let it redraw again."
	| ws target dw d bp |
	ws := self openWorkspace: '3 + 4'.
	target := self openWorkspace: 'target'.
	target title: 'Breakpoint target'.
	world waitUntilSettled: 3000.
	bp := Breakpoint on: Window selector: #redraw condition: '[:window | window title = ''Breakpoint target'']' scope: #all.
	cleanups add: [bp remove].
	target invalidate.
	dw := self waitForWindowOf: Debugger.
	d := dw content.
	self assert: d session process == target process.
	self assert: target process isSuspended.
	self assert: d stackList selection printString equals: 'Window>>redraw'.
	self remote: 'type' with: {'target' -> (self ref: ws at: '.text'). 'text' -> ' 5'. 'at' -> 'end'}.
	self waitFor: [(self textOf: ws) includesSubstring: '3 + 4 5'] description: 'the other workspace to take the typing'.
	self deny: ws process isSuspended.
	self click: (self ref: dw at: '.remove-breakpoint').
	self waitUntilReady: dw.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self deny: target process isSuspended.
	target invalidate.
	self waitFor: [target hasPendingWork not] description: 'the target window to redraw'
!
testBreakpointInADebuggersOwnProcess
	"Debug the debugger: a breakpoint in Debugger>>stepOver scoped to debugger A's Process; Over in A opens debugger B on A's Process; B steps; after B's Proceed, A steps as before."
	| a b bp |
	a := self openDebuggerOnGcd last.
	bp := Breakpoint on: Debugger selector: #stepOver inProcess: a process.
	cleanups add: [bp remove].
	self click: (self ref: a at: '.over').
	self waitFor: [(world windows select: [:w | w isOpen and: [w content isKindOf: Debugger]]) size = 2] description: 'a second Debugger'.
	b := world windows detect: [:w | w isOpen and: [(w content isKindOf: Debugger) and: [w ~~ a]]].
	world waitUntilSettled: 3000.
	self assert: b content session process == a process.
	self assert: a process isSuspended.
	self assert: b content stackList selection printString equals: 'Debugger>>stepOver'.
	self click: (self ref: b at: '.into').
	self waitUntilReady: b.
	self assert: a process isSuspended.
	self deny: b content session process isTerminated.
	bp remove.
	self click: (self ref: b at: '.proceed').
	self waitFor: [b isClosed] description: 'the second Debugger to close'.
	self waitFor: [a process isSuspended not] description: 'debugger A to run again'.
	self waitUntilReady: a.
	"A's interrupted Over completed"
	self waitFor: [(self pcTextOf: a content) = 'b := anInteger abs'] description: 'A''s Over to finish'.
	self click: (self ref: a at: '.over').
	self waitUntilReady: a.
	self assert: ((self pcTextOf: a content) beginsWith: '[b = 0] whileFalse: [')
!
testWatchpointStopsTheWindowManagerWithAStandIn
	"Halt on write on a window's bounds in all processes; dragging the window stops the input dispatcher at the store, in a Debugger. A stand-in dispatcher keeps input and remote control going; Proceed retires it."
	| ws dispatcher wp dw d stack |
	ws := self openWorkspace: 'drag me'.
	dispatcher := world dispatcher process.
	wp := (Watchpoint on: ws instVarNamed: 'bounds') inAllProcesses; yourself.
	cleanups add: [wp unwatch].
	self remote: 'drag' with: {'target' -> (self ref: ws at: '').  'dx' -> 60. 'dy' -> 30}.
	dw := self waitForWindowOf: Debugger.
	d := dw content.
	self assert: d session process == dispatcher.
	self assert: dispatcher isSuspended.
	self assert: world dispatcher standIn notNil.
	stack := d stackList items collect: [:each | each printString].
	self assert: (stack includes: 'Window>>moveTo:').
	self assert: (stack includes: 'DragGesture>>pointerMoved:').
	"input and remote control go on through the stand-in"
	self assert: ((self remote: 'snapshot' with: #()) at: 'text') notEmpty.
	self remote: 'type' with: {'target' -> (self ref: ws at: '.text'). 'text' -> ' 1'. 'at' -> 'end'}.
	self waitFor: [(self textOf: ws) includesSubstring: 'drag me 1'] description: 'typing through the stand-in'.
	self click: (self ref: dw at: '.unwatch').
	self waitUntilReady: dw.
	self assert: (Watchpoint forObject: ws) isEmpty.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [world dispatcher standIn isNil] description: 'the stand-in to retire'.
	self assert: world dispatcher process == dispatcher.
	self deny: dispatcher isSuspended.
	self waitFor: [(Processor allProcesses anySatisfy: [:p | p name = 'input dispatcher (stand-in)']) not] description: 'the stand-in Process to end'.
	self remote: 'type' with: {'target' -> (self ref: ws at: '.text'). 'text' -> ' 2'. 'at' -> 'end'}.
	self waitFor: [(self textOf: ws) includesSubstring: 'drag me 1 2'] description: 'typing through the original dispatcher'
!
testBreakpointInTheCompositorWithAStandIn
	"A breakpoint in the compositor's Process: the screen keeps being composited by a stand-in while the Debugger shows the stopped compositor; Proceed retires it."
	| compositor bp dw frames |
	compositor := world compositor process.
	bp := Breakpoint on: Compositor selector: #present:now: inProcess: compositor.
	cleanups add: [bp remove].
	world changed.
	dw := self waitForWindowOf: Debugger.
	self assert: dw content session process == compositor.
	self assert: compositor isSuspended.
	self assert: world compositor standIn notNil.
	frames := world compositor frameCount.
	world changed.
	self waitFor: [world compositor frameCount > frames] description: 'the stand-in to present frames'.
	self click: (self ref: dw at: '.remove-breakpoint').
	self waitUntilReady: dw.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [world compositor standIn isNil] description: 'the stand-in to retire'.
	self deny: compositor isSuspended.
	self assert: world compositor process == compositor
! !

!DebuggerUITest methodsFor: 'stack overflow'!
recurse: n
	^self recurse: n + 1
!
oldBytesAfterGC
	Smalltalk vm garbageCollect.
	^Smalltalk vm statistics oldBytesUsed
!
testStackOverflowDebugProceedAbandon
	"Runaway recursion in a do-it: a StackOverflow Notifier, the Debugger on the recursing frame with a paged Full stack, Proceed recurses on until the next StackOverflow, Abandon terminates the Process and frees its stack."
	| old before ws nw dw d process deep |
	old := Process maxStackDepth: 50000.
	cleanups add: [Process maxStackDepth: old].
	before := self oldBytesAfterGC.
	ws := self openWorkspace: 'DebuggerUITest new recurse: 1'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'StackOverflow'.
	process := nw content session process.
	self assert: process isSuspended description: 'the process is not suspended: ', process printString.
	self assert: (nw content stackList items anySatisfy: [:ctx | ctx selector == #recurse:]) description: 'no recurse: in the notifier''s stack'.
	deep := nw content session exception depth.
	self assert: deep > 50000 description: 'overflow at depth ', deep printString.
	self click: (self ref: nw at: '.debug').
	dw := self waitForWindowOf: Debugger.
	d := dw content.
	self waitUntilReady: dw.
	self assert: d stackList selection printString equals: 'DebuggerUITest>>recurse:'.
	self assert: d stackList items last == #more description: 'no more entry at the end of the short stack'.
	self click: (self ref: dw at: '.full-stack').
	self waitUntilReady: dw.
	self assert: d stackList items size equals: Debugger fullStackPage + 1.
	self assert: d stackList items last == #more description: 'no more entry at the end of the full stack page'.
	self click: (self ref: dw at: '.stack.more').
	self waitUntilReady: dw.
	self assert: d stackList items size equals: 2 * Debugger fullStackPage + 1.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'StackOverflow'.
	self assert: nw content session process == process description: 'the second notifier is on another process'.
	self assert: nw content session exception depth > (deep + 50000) description: 'second overflow at depth ', nw content session exception depth printString, ', first at ', deep printString.
	self click: (self ref: nw at: '.abandon').
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	self assert: process isTerminated description: 'the process is not terminated after Abandon: ', process printString.
	self assert: self oldBytesAfterGC - before < (4 * 1024 * 1024) description: [(self oldBytesAfterGC - before) printString, ' more bytes in old space after Abandon']
! !

!DebuggerUITest methodsFor: 'tests'!
testBreakpointStepOverEvaluateProceed
	| pair ws dw d steps |
	pair := self openDebuggerOnGcd.
	ws := pair first.
	dw := pair last.
	d := dw content.
	self assert: dw title equals: 'Debugger — Breakpoint: Integer>>gcd:'.
	self assert: d session process name equals: 'Workspace doIt'.
	self assert: d session process isSuspended.
	self assert: (Breakpoint isIgnoring: dw process).
	self assert: (d headerTitle) equals: 'Breakpoint: Integer>>gcd:'.
	self assert: ((dw content widgetNamed: 'process') text) equals: 'Process ''Workspace doIt'' · suspended'.
	self assert: d stackList selection printString equals: 'SmallInteger(Integer)>>gcd:'.
	self assert: (self pcTextOf: d) equals: 'a := self abs'.
	steps := OrderedCollection new.
	4 timesRepeat: [
		self click: (self ref: dw at: '.over').
		self waitUntilReady: dw.
		steps add: (self pcTextOf: d)].
	self assert: (steps at: 1) equals: 'b := anInteger abs'.
	self assert: ((steps at: 2) beginsWith: '[b = 0] whileFalse: [').
	self assert: ((steps at: 2) endsWith: 'b := r]').
	self assert: (steps at: 3) equals: 'b = 0'.
	self assert: (steps at: 4) equals: 'r := a \\ b'.
	self assert: (d sourceEditor pcMark) style equals: #pc.
	self click: (self ref: dw at: '.context.fields.a').
	self waitUntilReady: dw.
	self assert: d contextInspector valuePane text equals: '48'.
	self type: 'a + b' in: (self ref: dw at: '.context.evaluator').
	self key: 'Meta+p' in: (self ref: dw at: '.context.evaluator').
	self waitUntilReady: dw.
	self assert: d contextInspector evaluator text equals: 'a + b 66'.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [(self textOf: ws) includesSubstring: '48 gcd: 18 6'] description: 'the workspace to print 6'
!
testRetainedDrawingWhileStepping
	"Stepping glides the pc mark: in the middle of the glide and after it, the Debugger drawn as its next redraw would (replaying what did not change) draws like drawing it anew, quad for quad and pixel for pixel; and no replay during the steps differed (View verifyDrawing:)."
	| dw d mismatch |
	View verifyDrawing: true.
	cleanups add: [View verifyDrawing: false].
	dw := self openDebuggerOnGcd last.
	d := dw content.
	self waitUntilReady: dw.
	self assert: dw retainedDrawingMismatch isNil.
	3 timesRepeat: [
		self click: (self ref: dw at: '.over').
		self waitUntilReady: dw.
		mismatch := dw retainedDrawingMismatchAfter: [ | glide |
			glide := d sourceEditor instVarNamed: 'pcAnimation'.
			glide isNil ifFalse: [
				glide startTime isNil ifTrue: [glide startAt: Animation now].
				glide stepAt: glide startTime + (glide duration / 2)]].
		self assert: mismatch isNil description: 'mid-glide: ', mismatch printString.
		world waitUntilSettled: 3000.
		mismatch := dw retainedDrawingMismatch.
		self assert: mismatch isNil description: mismatch printString].
	self assert: View staleDrawings isEmpty description: View staleDrawings size printString, ' replays differed from drawing anew'.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'
!
testDoesNotUnderstandCreateAcceptProceed
	| ws nw dw d |
	cleanups add: [Integer removeSelector: #zork].
	ws := self openWorkspace: '3 zork'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'MessageNotUnderstood: SmallInteger>>#zork'.
	self assert: (nw content buttonNamed: 'create') isVisible.
	self assert: nw content session process isSuspended.
	self click: (self ref: nw at: '.create').
	self waitFor: [world overlays notEmpty] description: 'the Create menu'.
	self click: '@menu.integer'.
	dw := self waitForWindowOf: Debugger.
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	d := dw content.
	self waitUntilReady: dw.
	self assert: dw title equals: 'Debugger — MessageNotUnderstood: SmallInteger>>#zork'.
	self assert: (Integer includesSelector: #zork).
	self deny: (Object includesSelector: #zork).
	self assert: d stackList selection printString equals: 'SmallInteger(Integer)>>zork'.
	self assert: d sourceEditor selectedText equals: 'self shouldBeImplemented'.
	self type: 'self * 100' in: (self ref: dw at: '.source').
	self key: 'Meta+s' in: (self ref: dw at: '.source').
	self waitUntilReady: dw.
	self assert: (d sourceEditor text endsWith: '^self * 100').
	self assert: d note equals: 'accepted · frame restarted'.
	self assert: (Integer >> #zork) sourceCode equals: d sourceEditor text.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [(self textOf: ws) includesSubstring: '3 zork 300'] description: 'the workspace to print 300'
!
testWatchpointUnwatchProceed
	| ws iw dw d point before |
	before := Transcript contents size.
	cleanups add: [Watchpoint all do: [:each | (each object isKindOf: Point) ifTrue: [each unwatch]]].
	ws := self openWorkspace: 'p := 3 @ 4
[5 timesRepeat: [p x: p x + 1. Transcript show: p printString; cr]] forkNamed: ''mover'''.
	(Smalltalk at: #Inspector ifAbsent: [nil]) notNil
		ifTrue: [
			"The core tools' Inspector: ⌘I, then Halt on write on the field x."
			self evaluateLine: 1 in: ws with: 'Meta+i'.
			self waitFor: [(world windows detect: [:w | w title beginsWith: 'Inspector'] ifNone: [nil]) notNil] description: 'an Inspector'.
			iw := world windows detect: [:w | w title beginsWith: 'Inspector'].
			world waitUntilSettled: 3000.
			self rightClick: (self ref: iw at: '.fields.x').
			self waitFor: [world overlays notEmpty] description: 'the field menu'.
			self click: '@menu.halt-on-write']
		ifFalse: [
			self evaluateLine: 1 in: ws with: 'Meta+d'.
			self waitFor: [(ws content bindings at: #p ifAbsent: [nil]) notNil] description: 'p'.
			Watchpoint on: (ws content bindings at: #p) value instVarNamed: 'x'].
	self waitFor: [Watchpoint all anySatisfy: [:each | each object = (3 @ 4)]] description: 'the watchpoint'.
	point := (Watchpoint all detect: [:each | each object = (3 @ 4)]) object.
	self assert: point isReadOnlyObject.
	self evaluateLine: 2 in: ws with: 'Meta+d'.
	dw := self waitForWindowOf: Debugger.
	d := dw content.
	self assert: dw title equals: 'Debugger — ModificationForbidden → watchpoint on #x'.
	self assert: d session process name equals: 'mover'.
	self track: d session process.
	self assert: d stackList selection printString equals: '[] in UndefinedObject>>DoIt'.
	self assert: (self pcTextOf: d) equals: 'p x: p x + 1'.
	"The stack starts at the refused store's signal; the do-it's block frame is editable."
	self assert: d stackList items first printString equals: 'ModificationForbidden(Exception)>>signal'.
	self assert: (d stackList items includes: d session process suspendedContext).
	self deny: d sourceEditor isReadOnly.
	self assert: (d buttonNamed: 'unwatch') isVisible.
	self click: (self ref: dw at: '.unwatch').
	self waitUntilReady: dw.
	self deny: (d buttonNamed: 'unwatch') isVisible.
	self deny: point isReadOnlyObject.
	self assert: (Watchpoint forObject: point) isEmpty.
	self click: (self ref: dw at: '.proceed').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [point x = 8] description: 'the mover to finish'.
	self waitFor: [((Transcript contents copyFrom: before + 1 to: Transcript contents size) includesSubstring: '8@4')] description: 'the mover''s output'.
	self assert: ((Transcript contents copyFrom: before + 1 to: Transcript contents size) includesSubstring: '4@4')
!
testErrorNotifierAbandon
	| ws nw process |
	ws := self openWorkspace: '1/0'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'ZeroDivide'.
	self deny: (nw content buttonNamed: 'create') isVisible.
	process := nw content session process.
	self assert: process isSuspended.
	self click: (self ref: nw at: '.abandon').
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	self assert: process isTerminated.
	self assert: (self windowOf: Debugger) isNil
!
testNotifierDebugOpensDebuggerAndCloseAbandons
	| ws nw dw d process |
	ws := self openWorkspace: 'nil foo'.
	self evaluateLine: 1 in: ws with: 'Meta+p'.
	nw := self waitForWindowOf: Notifier.
	process := nw content session process.
	self click: (self ref: nw at: '.debug').
	dw := self waitForWindowOf: Debugger.
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	d := dw content.
	self assert: d session == nw content session.
	self assert: d stackList selection printString equals: 'UndefinedObject>>DoIt'.
	self assert: (d stackList items first printString beginsWith: 'UndefinedObject(ProtoObject)>>doesNotUnderstand:') description: d stackList items printString.
	self assert: (self pcTextOf: d) equals: 'nil foo'.
	self assert: (d buttonNamed: 'create') isVisible.
	self click: (self ref: dw at: '.close').
	self waitFor: [dw isClosed] description: 'the Debugger to close'.
	self waitFor: [process isTerminated] description: 'the Process to be abandoned'
!
testFullStackIntoRestartRunToHere
	| dw d frames full |
	dw := self openDebuggerOnGcd last.
	d := dw content.
	frames := d stackList items size.
	self assert: d stackList items last == #more.
	self click: (self ref: dw at: '.full-stack').
	self waitUntilReady: dw.
	full := d session fullStack size.
	self assert: d stackList items size equals: full.
	self assert: (d buttonNamed: 'full-stack') isOn.
	self click: (self ref: dw at: '.full-stack').
	self waitUntilReady: dw.
	self assert: d stackList items size equals: frames.
	self click: (self ref: dw at: '.into').
	self waitUntilReady: dw.
	self assert: (d session interruptedContext selector) equals: #abs.
	self assert: d stackList selection == d session interruptedContext.
	self assert: (d stackList items second printString) equals: 'SmallInteger(Integer)>>gcd:'.
	self click: (self ref: dw at: '.stack.smallinteger-integer-gcd').
	self waitUntilReady: dw.
	self click: (self ref: dw at: '.restart').
	self waitUntilReady: dw.
	self assert: d session interruptedContext printString equals: 'SmallInteger(Integer)>>gcd:'.
	self assert: (self pcTextOf: d) equals: 'a := self abs'.
	self assert: d note equals: 'restarted'.
	self select: 'b = 0' in: (self ref: dw at: '.source').
	self click: (self ref: dw at: '.run-to-here').
	self waitUntilReady: dw.
	self assert: (self pcTextOf: d) equals: 'b = 0'.
	self assert: ((d contextInspector fields items detect: [:f | f name = 'b']) value) equals: 18
!
testBreakpointsWindow
	| bp point wp bw b list |
	bp := self breakpointOn: Integer selector: #lcm:.
	point := 10 @ 20.
	wp := Watchpoint on: point instVarNamed: 'y'.
	cleanups add: [wp unwatch].
	BreakpointsBrowser open.
	bw := self waitForWindowOf: BreakpointsBrowser.
	b := bw content.
	list := b list.
	self assert: (list items includes: bp).
	self assert: (list items includes: wp).
	self assert: ((list items collect: [:each | b titleOf: each]) includes: 'Integer>>lcm:').
	self click: (self ref: bw at: '.breakpoints.integer-lcm').
	self waitUntilReady: bw.
	self assert: list selection == bp.
	self click: (self ref: bw at: '.toggle').
	self waitUntilReady: bw.
	self deny: bp isEnabled.
	self assert: ((b descriptionOf: bp) includesSubstring: 'disabled').
	3 lcm: 4.
	self assert: bp hits equals: 0.
	self click: (self ref: bw at: '.remove').
	self waitUntilReady: bw.
	self deny: bp isInstalled.
	self deny: (list items includes: bp).
	self assert: (list items includes: wp).
	BreakpointsBrowser open.
	self assert: (world windows select: [:each | each content isKindOf: BreakpointsBrowser]) size equals: 1
!
testWindowErrorOpensNotifierOnWindowProcess
	| view w nw old |
	view := DebuggerTestFaultyView new.
	w := Window new title: 'Faulty'; content: view; bounds: (100 @ 100 extent: 300 @ 200); yourself.
	w openIn: world.
	world waitUntilSettled: 3000.
	old := w process.
	self click: (self ref: w at: '.faulty').
	nw := self waitForWindowOf: Notifier.
	self assert: nw title equals: 'ZeroDivide'.
	self assert: nw content session process == old.
	self assert: old isSuspended.
	self click: (self ref: nw at: '.abandon').
	self waitFor: [nw isClosed] description: 'the notifier to close'.
	self assert: old isTerminated.
	self assert: w isOpen.
	self deny: w process == old.
	self deny: w process isTerminated
! !
