DebuggingTestCase subclass: #DebugSessionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Debugging'!

DebugSessionTest comment: 'Integration tests of DebugSession: real code in its own process stops at a breakpoint, an error or an interrupt; the test (the debugger''s process) steps, evaluates, edits and proceeds.'!

!DebugSessionTest methodsFor: 'helpers'!
gcdSession
	"48 gcd: 18 stopped at a breakpoint on Integer>>gcd:."
	Breakpoint on: Integer selector: #gcd:.
	^self waitForGcdSessionOf: (self fork: [Smalltalk at: #DebugTestResult put: (48 gcd: 18)])
!
waitForGcdSessionOf: aProcess
	| session |
	session := self waitForSession.
	self assert: session process == aProcess.
	^session
!
result
	^Smalltalk at: #DebugTestResult ifAbsent: [nil]
!
pcTextOf: aSession
	"The source the session highlights as the pc of its interrupted context."
	| ctx interval |
	ctx := aSession interruptedContext.
	interval := aSession pcIntervalOf: ctx.
	^ctx sourceCode copyFrom: interval first to: interval last
!
sessionOn: aSelector running: aBlock
	"aBlock run in its own process, stopped at a breakpoint on DebuggingTestSubject>>aSelector."
	Breakpoint on: DebuggingTestSubject selector: aSelector.
	self fork: [Smalltalk at: #DebugTestResult put: aBlock value].
	^self waitForSession
!
waitUntilRunning: aProcess
	"Wait until aProcess has had the CPU (its cpuMicroseconds grows)."
	| cpu |
	cpu := aProcess cpuMicroseconds.
	self assert: (self waitFor: [aProcess cpuMicroseconds > cpu]) description: 'the process did not run'
!
proceedAndCheck: aSession result: anObject
	aSession proceed.
	self waitUntilTerminated: aSession process.
	self assert: self result equals: anObject
! !

!DebugSessionTest methodsFor: 'running'!
setUp
	super setUp.
	Smalltalk at: #DebugTestResult put: nil
!
tearDown
	super tearDown.
	Smalltalk removeKey: #DebugTestResult ifAbsent: [nil].
	DebuggingTestSubject restoreSources.
	(Integer includesSelector: #zork) ifTrue: [Integer removeSelector: #zork]
! !

!DebugSessionTest methodsFor: 'tests'!
testRestartWaitingProcess
	"A Process waiting on a Semaphore, suspended, restarted in the debugger and proceeded: switched to, it runs the restarted frame from its start and waits again; signaled, it finishes."
	| sem log process session |
	sem := Semaphore new.
	log := OrderedCollection new.
	process := self fork: [log add: #start. sem wait. log add: #end. Smalltalk at: #DebugTestResult put: log size].
	self assert: (self waitFor: [process suspendingList == sem]).
	process suspend.
	session := DebugSession debugProcess: process.
	self assert: (self textOf: session) equals: 'log add: #end'.
	session restart: session interruptedContext.
	session proceed.
	self assert: (self waitFor: [process suspendingList == sem]).
	self assert: log asArray equals: #(#start #start).
	sem signal.
	self waitUntilTerminated: process.
	self assert: log asArray equals: #(#start #start #end).
	self assert: self result equals: 3
!
testBreakpointStepOver
	| session texts |
	session := self gcdSession.
	self assert: session kind equals: #breakpoint.
	self assert: (session label includesSubstring: 'Integer>>gcd:').
	self assert: session interruptedContext == session process suspendedContext.
	self assert: session interruptedContext selector equals: #gcd:.
	self assert: (self textOf: session) equals: 'self abs'.
	self assert: (self temp: 'anInteger' of: session) equals: 18.
	self assert: (self temp: 'a' of: session) isNil.
	texts := OrderedCollection new.
	8 timesRepeat: [
		session stepOver.
		texts add: (self textOf: session)].
	"Entering the loop body re-nils its temporary r: that store maps to the body's first statement."
	self assert: texts asArray equals: #('a := self abs' 'anInteger abs' 'b := anInteger abs' 'b = 0' 'r := a \\ b' 'a \\ b' 'r := a \\ b' 'a := b').
	self assert: (self temp: 'a' of: session) equals: 48.
	self assert: (self temp: 'b' of: session) equals: 18.
	self assert: (self temp: 'r' of: session) equals: 12.
	self assert: session interruptedContext receiver equals: 48.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 6.
	self assert: session state equals: #running
!
testEvaluateInFrame
	| session |
	session := self gcdSession.
	4 timesRepeat: [session stepOver].
	self assert: (self textOf: session) equals: 'b = 0'.
	self assert: (self temp: 'a' of: session) equals: 48.
	self assert: (self temp: 'b' of: session) equals: 18.
	self assert: (session evaluate: 'a + b' inFrame: session interruptedContext) equals: 66.
	self assert: (session evaluate: 'self + 1' inFrame: session interruptedContext) equals: 49.
	"Assignments go to the frame."
	session evaluate: 'a := 7. b := 21' inFrame: session interruptedContext.
	self assert: (self temp: 'b' of: session) equals: 21.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 7
!
testStepInto
	| session gcd |
	session := self gcdSession.
	gcd := session interruptedContext.
	session stepInto.
	self assert: session interruptedContext selector equals: #abs.
	self assert: session interruptedContext sender == gcd.
	self assert: (session stack at: 2) == gcd.
	[session interruptedContext == gcd] whileFalse: [session stepOver].
	self assert: (self textOf: session) equals: 'a := self abs'.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 6
!
testRunToHere
	| session gcd position |
	session := self gcdSession.
	gcd := session interruptedContext.
	position := (gcd sourceCode indexOf: $\) + 1.
	session runToSourcePosition: position inFrame: gcd.
	self assert: session interruptedContext == gcd.
	self assert: (self textOf: session) equals: 'a \\ b'.
	self assert: (self temp: 'a' of: session) equals: 48.
	self assert: (self temp: 'b' of: session) equals: 18.
	session runToSourcePosition: position inFrame: gcd.
	self assert: (self textOf: session) equals: 'a \\ b'.
	self assert: (self temp: 'a' of: session) equals: 18.
	self assert: (self temp: 'b' of: session) equals: 12.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 6
!
testRestart
	| session gcd |
	session := self gcdSession.
	gcd := session interruptedContext.
	6 timesRepeat: [session stepOver].
	self assert: (self temp: 'a' of: session) equals: 48.
	session restart: gcd.
	self assert: session interruptedContext == gcd.
	self assert: (self textOf: session) equals: 'self abs'.
	self assert: (self temp: 'a' of: session) isNil.
	self assert: (self temp: 'anInteger' of: session) equals: 18.
	self assert: (Breakpoint all first hits) equals: 1.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 6
!
testStepThrough
	| session method block |
	Breakpoint on: DebuggingTestSubject selector: #sumOf:.
	self fork: [Smalltalk at: #DebugTestResult put: (DebuggingTestSubject new sumOf: #(1 2 3))].
	session := self waitForSession.
	method := session interruptedContext.
	self assert: (self textOf: session) equals: '[:sum :each | sum + each]'.
	session stepOver.
	self assert: (self textOf: session) equals: 'aCollection inject: 0 into: [:sum :each | sum + each]'.
	session stepThrough.
	block := session interruptedContext.
	self assert: block isBlockContext.
	self assert: block home == method.
	self assert: (self textOf: session) equals: 'sum + each'.
	self assert: (self temp: 'each' of: session) equals: 1.
	self assert: (self temp: 'aCollection' of: session) equals: #(1 2 3).
	session stepThrough.
	session stepThrough.
	self assert: session interruptedContext isBlockContext.
	self assert: (self temp: 'each' of: session) equals: 2.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 6
!
testEditAndContinue
	| session frame method |
	Breakpoint on: DebuggingTestSubject selector: #helper.
	self fork: [Smalltalk at: #DebugTestResult put: DebuggingTestSubject new compute].
	session := self waitForSession.
	frame := session interruptedContext.
	self assert: frame selector equals: #helper.
	self assert: (session stack at: 2) selector equals: #compute.
	method := session recompile: 'helper
	^21' inFrame: frame.
	self assert: (DebuggingTestSubject compiledMethodAt: #helper) == method.
	self assert: session interruptedContext method == method.
	self assert: session interruptedContext sender selector equals: #compute.
	self assert: (self textOf: session) equals: '^21'.
	self assert: Breakpoint all isEmpty.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 42.
	self assert: DebuggingTestSubject new compute equals: 42
!
testEditAndContinueInSender
	| session compute method |
	(Breakpoint on: DebuggingTestSubject selector: #helper) yourself.
	self fork: [Smalltalk at: #DebugTestResult put: DebuggingTestSubject new callsCompute].
	session := self waitForSession.
	Breakpoint removeAll.
	compute := session stack at: 2.
	self assert: compute selector equals: #compute.
	method := session recompile: 'compute
	^self helper * 3' inFrame: compute.
	self assert: session interruptedContext method == method.
	self assert: session interruptedContext sender selector equals: #callsCompute.
	self assert: compute isDead.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 61
!
testHalt
	| session |
	self fork: [Smalltalk at: #DebugTestResult put: (DebuggingTestSubject new haltingAdd: 4)].
	session := self waitForSession.
	self assert: session kind equals: #halt.
	self assert: session interruptedContext selector equals: #haltingAdd:.
	self assert: session interruptedContext == session process suspendedContext.
	self assert: (self textOf: session) equals: 'y * 2'.
	self assert: (self temp: 'y' of: session) equals: 5.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 10
!
testHaltInHandlerWithUnwindBlocks
	"Stopped in an exception handler (its process's frames were married to Contexts when the debugger took it): read and step it, return from the handler block, proceed; each unwind block runs once."
	| session handler |
	self fork: [Smalltalk at: #DebugTestResult put: DebuggingTestSubject new haltingHandler asArray].
	session := self waitForSession.
	self assert: session kind equals: #halt.
	handler := session interruptedContext.
	self assert: handler isBlockContext.
	self assert: handler home selector equals: #haltingHandler.
	self assert: (self temp: 'v' of: session) equals: 6.
	self assert: (session stack includes: handler home).
	session stepOver.
	self assert: session interruptedContext == handler.
	session return: 41 from: handler.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: #(#handled #unwound 41 #ensured)
!
testDoesNotUnderstandCreateMethod
	| session method |
	self fork: [Smalltalk at: #DebugTestResult put: 3 zork].
	session := self waitForSession.
	self assert: session kind equals: #dnu.
	self assert: (session label includesSubstring: 'zork').
	self assert: session interruptedContext selector equals: #doesNotUnderstand:.
	method := session createMissingMethodIn: Integer.
	self assert: (Integer compiledMethodAt: #zork) == method.
	self assert: (method sourceCode includesSubstring: 'shouldBeImplemented').
	self assert: session interruptedContext method == method.
	self assert: session interruptedContext receiver equals: 3.
	session recompile: 'zork
	^self * 100' inFrame: session interruptedContext.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 300
!
testDoesNotUnderstandStubArguments
	| session |
	self fork: [Smalltalk at: #DebugTestResult put: (3 zork: 4 with: 'x' with: 5)].
	session := self waitForSession.
	session createMissingMethodIn: Integer.
	self assert: ((Integer compiledMethodAt: #zork:with:with:) sourceCode beginsWith: 'zork: anInteger with: aString with: anInteger2').
	self assert: (self temp: 'aString' of: session) equals: 'x'.
	session abandon.
	Integer removeSelector: #zork:with:with:
!
testDoesNotUnderstandProceedResends
	| session |
	self fork: [Smalltalk at: #DebugTestResult put: 3 zork + 1].
	session := self waitForSession.
	Integer compile: 'zork
	^self * 2' classified: 'test'.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 7
!
testEditBlockOfDoItAndContinue
	"A block frame of a do-it: the edited block restarts on the new code, and the loop's later evaluations of the block run it too."
	| session ctx log |
	log := OrderedCollection new.
	Smalltalk at: #DebugTestLog put: log.
	self fork: [Compiler evaluate: '3 timesRepeat: [(Smalltalk at: #DebugTestLog) add: 1. self halt]'].
	session := self waitForSession.
	ctx := session interruptedContext.
	self assert: ctx method selector equals: #DoIt.
	self assert: ctx closureOrNil notNil.
	self assert: log asArray equals: #(1).
	session recompileDoIt: '3 timesRepeat: [(Smalltalk at: #DebugTestLog) add: 2]' inFrame: ctx.
	self assert: session interruptedContext method ~~ ctx method.
	self assert: session interruptedContext closureOrNil == ctx closureOrNil.
	self assert: ((session sourceOf: session interruptedContext) includesSubstring: 'add: 2]').
	self assert: (session selectedSourceOf: session interruptedContext) equals: 'Smalltalk at: #DebugTestLog'.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: log asArray equals: #(1 2 2 2)
!
testEditDoItOutsideTheBlockIsRefused
	| session ctx |
	Smalltalk at: #DebugTestLog put: OrderedCollection new.
	self fork: [Compiler evaluate: '3 timesRepeat: [(Smalltalk at: #DebugTestLog) add: 1. self halt]'].
	session := self waitForSession.
	ctx := session interruptedContext.
	self should: [session recompileDoIt: '4 timesRepeat: [(Smalltalk at: #DebugTestLog) add: 1]' inFrame: ctx] raise: Error.
	"Nothing changed: proceeding runs the old code."
	self assert: session interruptedContext == ctx.
	session abandon
!
testEditDoItFrameRestartsIt
	| session log |
	log := OrderedCollection new.
	Smalltalk at: #DebugTestLog put: log.
	self fork: [Smalltalk at: #DebugTestResult put: (Compiler evaluate: '(Smalltalk at: #DebugTestLog) add: 1. self halt. 7')].
	session := self waitForSession.
	self assert: session interruptedContext closureOrNil isNil.
	session recompileDoIt: '(Smalltalk at: #DebugTestLog) add: 5. 8' inFrame: session interruptedContext.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: log asArray equals: #(1 5).
	self assert: self result equals: 8
!
testErrorProceedResumesWithNil
	| session |
	self fork: [Smalltalk at: #DebugTestResult put: (Error signal: 'oops') printString].
	session := self waitForSession.
	self assert: session kind equals: #error.
	self assert: (session label includesSubstring: 'oops').
	self assert: (session exception isKindOf: Error).
	"The stack starts at the signal: the handler search and the debugger's opening were unwound."
	self assert: session interruptedContext == session exception signalContext.
	self assert: session fullStack size equals: session stack size.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 'nil'
!
testErrorWhileStepping
	| session caller |
	Breakpoint on: DebuggingTestSubject selector: #callsDivide.
	self fork: [Smalltalk at: #DebugTestResult put: DebuggingTestSubject new callsDivide].
	session := self waitForSession.
	caller := session interruptedContext.
	session stepOver.
	self assert: session stopReason equals: #error.
	self assert: session kind equals: #error.
	self assert: (session exception isKindOf: ZeroDivide).
	self assert: (session stack includes: caller).
	"Stepping on resumes the error with nil."
	[session interruptedContext == caller] whileFalse: [session stepOver: caller].
	self assert: (self textOf: session) equals: 'x := 1 / 0'.
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result isNil.
	self assert: sessions isEmpty
!
testBreakpointHitWhileSteppingOver
	| session caller |
	Breakpoint on: DebuggingTestSubject selector: #callsCompute.
	Breakpoint on: DebuggingTestSubject selector: #helper.
	self fork: [Smalltalk at: #DebugTestResult put: DebuggingTestSubject new callsCompute].
	session := self waitForSession.
	caller := session interruptedContext.
	session stepOver.
	self assert: session kind equals: #breakpoint.
	self assert: session interruptedContext selector equals: #helper.
	self assert: session interruptedContext == session process suspendedContext.
	self assert: (session stack includes: caller).
	session proceed.
	self waitUntilTerminated: session process.
	self assert: self result equals: 41
!
testUserInterrupt
	| session subject process count |
	subject := DebuggingTestSubject new.
	process := self fork: [subject loop].
	process priority: Processor userBackgroundPriority.
	self assert: (self waitFor: [subject count notNil]).
	process interrupt.
	session := self waitForSession.
	self assert: session kind equals: #interrupt.
	self assert: session label equals: 'User interrupt'.
	self assert: session interruptedContext == process suspendedContext.
	self assert: (session interruptedContext method == (DebuggingTestSubject >> #loop)).
	count := subject count.
	"Stopped: no progress within 20 ms."
	(Delay forMilliseconds: 20) wait.
	self assert: subject count equals: count.
	session stepOver.
	session stepOver.
	self assert: session interruptedContext method == (DebuggingTestSubject >> #loop).
	session proceed.
	self assert: (self waitFor: [subject count > count]).
	self deny: process isTerminated
!
testUserInterruptOfEmptyFrames
	"Loops whose frame has no temporaries and an empty stack (a temp-less method, a bare block) can be interrupted and resumed, repeatedly."
	| subject process session count |
	subject := DebuggingTestSubject new.
	process := self fork: [subject spin].
	process priority: Processor userBackgroundPriority.
	self assert: (self waitFor: [subject count notNil]).
	2 timesRepeat: [
		process interrupt.
		session := self waitForSession.
		self assert: session kind equals: #interrupt.
		self assert: session interruptedContext method == (DebuggingTestSubject >> #spin).
		self assert: session interruptedContext == process suspendedContext.
		count := subject count.
		session proceed.
		self assert: (self waitFor: [subject count > count])].
	process := self fork: [[true] whileTrue].
	process priority: Processor userBackgroundPriority.
	self waitUntilRunning: process.
	process interrupt.
	session := self waitForSession.
	self assert: session interruptedContext isBlockContext.
	self assert: session interruptedContext stackp equals: 0.
	session proceed.
	self waitUntilRunning: process.
	self assert: process isRunnable
!
testUserInterruptOfArithmeticLoops
	"Interrupts land anywhere: in LargeInteger and Float code too."
	{[[1000 factorial] repeat]. [| z | z := 0.0. [z := z * z + 0.25] repeat]} do: [:loop | | process session |
		process := self fork: loop.
		process priority: Processor userBackgroundPriority.
		3 timesRepeat: [
			self waitUntilRunning: process.
			process interrupt.
			session := self waitForSession.
			self assert: session kind equals: #interrupt.
			session proceed].
		self waitUntilRunning: process.
		self assert: process isRunnable.
		process terminate]
!
testSignalExceptionResumedInEmptyFrame
	"Without a debugger: the exception is handled in the process and the loop goes on."
	| subject process handled count |
	subject := DebuggingTestSubject new.
	handled := 0.
	process := self fork: [[subject spin] on: UserInterrupt do: [:e | handled := handled + 1. e resume]].
	process priority: Processor userBackgroundPriority.
	self assert: (self waitFor: [subject count notNil]).
	1 to: 3 do: [:i |
		process interrupt.
		self assert: (self waitFor: [handled = i])].
	self assert: handled equals: 3.
	count := subject count.
	self assert: (self waitFor: [subject count > count]).
	self assert: sessions isEmpty
!
testDebugProcess
	| subject process session count |
	subject := DebuggingTestSubject new.
	process := self fork: [subject loop].
	process priority: Processor userBackgroundPriority.
	self assert: (self waitFor: [subject count notNil]).
	session := DebugSession debugProcess: process.
	self assert: session kind equals: #suspended.
	self assert: process isSuspended.
	count := subject count.
	[subject count = count] whileTrue: [session stepOver].
	self assert: subject count equals: count + 1.
	session proceed.
	self assert: (self waitFor: [subject count > (count + 1)])
!
testProcessListenersHearHeldAndReleased
	| events process session |
	events := OrderedCollection new.
	DebugSession subscribe: #DebugSessionTest do: [:p :event | events add: p -> event].
	[Breakpoint on: Integer selector: #gcd:.
	 process := self fork: [(48 gcd: 18) + (12 gcd: 8)].
	 session := self waitForSession.
	 self assert: (events collect: [:each | each value]) asArray equals: #(#held).
	 self assert: events first key == process.
	 session proceed.
	 self assert: events last equals: process -> #released.
	 session := self waitForSession.
	 session abandon.
	 self assert: (events collect: [:each | each value]) asArray equals: #(#held #released #held #released).
	 self assert: events last key isTerminated]
		ensure: [DebugSession unsubscribe: #DebugSessionTest]
!
testAnnouncementsAndAbandon
	| session events ensured |
	ensured := false.
	Breakpoint on: DebuggingTestSubject selector: #helper.
	self fork: [[DebuggingTestSubject new compute] ensure: [ensured := true]].
	session := self waitForSession.
	events := OrderedCollection new.
	session when: [:event | events add: event].
	session stepOver.
	session evaluate: '3 + 4' inFrame: session interruptedContext.
	session abandon.
	self assert: events asArray equals: #(#stepped #evaluated #terminated).
	self assert: session process isTerminated.
	self assert: ensured
!
testWhereAndStack
	| session |
	session := self gcdSession.
	self assert: (session where includesSubstring: 'gcd:').
	self assert: (session where includesSubstring: 'self abs').
	self assert: (session stackOfSize: 1) size equals: 1.
	self assert: session stack first == session interruptedContext.
	self assert: (session receiverFieldsOf: session interruptedContext) isEmpty.
	self assert: ((session tempsOf: session interruptedContext) collect: [:a | a key]) asArray equals: #('anInteger' 'a' 'b').
	session proceed.
	self waitUntilTerminated: session process
! !

!DebugSessionTest methodsFor: 'tests - statements'!
testStepOverStatements
	"Over by statements: each step highlights the next statement; a loop statement first, then its condition without running."
	| session gcd texts pc |
	session := self gcdSession.
	gcd := session interruptedContext.
	self assert: (self pcTextOf: session) equals: 'a := self abs'.
	self assert: (session stepOverStatement: gcd) == gcd.
	self assert: (self pcTextOf: session) equals: 'b := anInteger abs'.
	self assert: (self temp: 'a' of: session) equals: 48.
	session stepOverStatement: gcd.
	self assert: (self pcTextOf: session) equals: '[b = 0] whileFalse: [| r | r := a \\ b. a := b. b := r]'.
	self assert: (self temp: 'b' of: session) equals: 18.
	pc := gcd pc.
	session stepOverStatement: gcd.
	self assert: (self pcTextOf: session) equals: 'b = 0'.
	self assert: gcd pc equals: pc.
	texts := OrderedCollection new.
	4 timesRepeat: [
		self assert: (session stepOverStatement: gcd) == gcd.
		texts add: (self pcTextOf: session).
		self assert: ((session pcIntervalOf: gcd) includes: (session intervalOf: gcd) first)].
	self assert: texts asArray equals: #('r := a \\ b' 'a := b' 'b := r' 'b = 0').
	self assert: (self temp: 'a' of: session) equals: 18.
	self assert: (self temp: 'b' of: session) equals: 12.
	self proceedAndCheck: session result: 6
!
testStepOverLastStatementReturnsToSender
	| session gcd steps ctx |
	session := self gcdSession.
	gcd := session interruptedContext.
	steps := 0.
	[(self pcTextOf: session) = '^a'] whileFalse: [
		session stepOverStatement: gcd.
		self assert: (steps := steps + 1) < 50].
	self assert: (self temp: 'a' of: session) equals: 6.
	ctx := session stepOverStatement: gcd.
	self assert: gcd isDead.
	self assert: ctx == session interruptedContext.
	self assert: ctx == session process suspendedContext.
	self assert: ctx isBlockContext.
	self assert: (self pcTextOf: session) equals: 'Smalltalk at: #DebugTestResult put: (48 gcd: 18)'.
	self proceedAndCheck: session result: 6
!
testStepOverStatementWithBlock
	"A statement sending do: with a block runs over the whole loop."
	| session method |
	session := self sessionOn: #sumTwice running: [DebuggingTestSubject new sumTwice].
	method := session interruptedContext.
	self assert: (self pcTextOf: session) equals: 'sum := 0'.
	session stepOverStatement: method.
	self assert: (self pcTextOf: session) equals: '#(1 2) do: [:each | sum := sum + each]'.
	self assert: (self temp: 'sum' of: session) equals: 0.
	session stepOverStatement: method.
	self assert: session interruptedContext == method.
	self assert: (self pcTextOf: session) equals: '^sum * 2'.
	self assert: (self temp: 'sum' of: session) equals: 3.
	self proceedAndCheck: session result: 6
!
testStepOverStatementsInBlock
	| session block steps ctx |
	session := self sessionOn: #doubledPlusOne running: [DebuggingTestSubject new doubledPlusOne].
	self assert: (self pcTextOf: session) equals: '^#(1 2) collect: [:each | | d | d := each * 2. d + 1]'.
	steps := 0.
	[session interruptedContext isBlockContext] whileFalse: [
		session stepThrough.
		self assert: (steps := steps + 1) < 10].
	block := session interruptedContext.
	self assert: block home method == (DebuggingTestSubject >> #doubledPlusOne).
	self assert: (self pcTextOf: session) equals: 'd := each * 2'.
	self assert: (session stepOverStatement: block) == block.
	self assert: (self pcTextOf: session) equals: 'd + 1'.
	self assert: (self temp: 'd' of: session) equals: 2.
	ctx := session stepOverStatement: block.
	self assert: ctx == block.
	self assert: block willReturn.
	ctx := session stepOverStatement: block.
	self assert: block isDead.
	self assert: ctx == session interruptedContext.
	self assert: ctx selector equals: #collect:.
	self proceedAndCheck: session result: #(3 5)
!
testStepOverStatementHitsBreakpoint
	"A breakpoint in a method sent by the statement stops there; Over on the caller then finishes the statement."
	| session caller ctx |
	Breakpoint on: DebuggingTestSubject selector: #helper.
	session := self sessionOn: #callsCompute running: [DebuggingTestSubject new callsCompute].
	caller := session interruptedContext.
	self assert: (self pcTextOf: session) equals: 'r := self compute'.
	ctx := session stepOverStatement: caller.
	self assert: session kind equals: #breakpoint.
	self assert: ctx == session interruptedContext.
	self assert: ctx selector equals: #helper.
	self assert: (session stack includes: caller).
	self assert: (self pcTextOf: session) equals: '^20'.
	ctx := session stepOverStatement: caller.
	self assert: ctx == caller.
	self assert: (self pcTextOf: session) equals: '^r + 1'.
	self assert: (self temp: 'r' of: session) equals: 40.
	self proceedAndCheck: session result: 41
!
testStepOverStatementHitsHalt
	| session caller ctx |
	session := self sessionOn: #callsHalting running: [DebuggingTestSubject new callsHalting].
	caller := session interruptedContext.
	ctx := session stepOverStatement: caller.
	self assert: session kind equals: #halt.
	self assert: ctx == session interruptedContext.
	self assert: ctx selector equals: #haltingAdd:.
	self assert: (self pcTextOf: session) equals: '^y * 2'.
	self assert: (self temp: 'y' of: session) equals: 5.
	ctx := session stepOverStatement: caller.
	self assert: ctx == caller.
	self assert: caller willReturn.
	self assert: (self pcTextOf: session) equals: '^(self haltingAdd: 4) + 1'.
	self proceedAndCheck: session result: 11
!
testStepOverStatementRaisesError
	"An error stops the step in the signaling frame; Over on the caller then resumes the error with nil."
	| session caller ctx |
	session := self sessionOn: #callsDivide running: [DebuggingTestSubject new callsDivide].
	caller := session interruptedContext.
	ctx := session stepOverStatement: caller.
	self assert: session stopReason equals: #error.
	self assert: session kind equals: #error.
	self assert: (session exception isKindOf: ZeroDivide).
	self assert: ctx == session interruptedContext.
	self assert: ctx ~~ caller.
	self assert: (session stack includes: caller).
	ctx := session stepOverStatement: caller.
	self assert: ctx == caller.
	self assert: (self pcTextOf: session) equals: '^x'.
	self assert: (self temp: 'x' of: session) isNil.
	self proceedAndCheck: session result: nil.
	self assert: sessions isEmpty
! !
