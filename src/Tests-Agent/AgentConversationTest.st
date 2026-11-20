TestCase subclass: #AgentConversationTest
	instanceVariableNames: 'provider conversation frameResult'
	classVariableNames: ''
	package: 'Tests-Agent'!

AgentConversationTest comment: 'Tests AgentConversation''s turns against a ScriptedProvider: tool calls and what is sent back, the object table, code-mode results and failures, Stop, contexts (receiver, Workspace bindings, a suspended frame) and change notification.'!

!AgentConversationTest methodsFor: 'running'!
setUp
	provider := ScriptedProvider new.
	conversation := AgentConversation new provider: provider; yourself
!
tearDown
	conversation stop
! !

!AgentConversationTest methodsFor: 'helpers'!
code: aString call: anId
	^ScriptedProvider code: aString call: anId
!
message: aString
	^ScriptedProvider message: aString
!
run: sourceStrings
	"One turn running each source in a cell of its own, then a message; answer the cells' outputs."
	sourceStrings doWithIndex: [:each :i | provider reply: (Array with: (self code: each call: 'c', i printString))].
	provider reply: (Array with: (self message: 'done')).
	self assert: (conversation ask: 'go'; wait) equals: 'done'.
	^(conversation items select: [:each | each kind == #code]) asArray collect: [:each | each result]
!
itemsOfKind: aSymbol
	^(conversation items select: [:each | each kind == aSymbol]) asArray
!
frameOf: x
	"Stop in a frame with an argument and a temporary; on resumption, keep the temporary."
	| y |
	y := x + 1.
	Processor activeProcess suspend.
	frameResult := y
! !

!AgentConversationTest methodsFor: 'tests'!
testTurnWithCellsAndShow
	| second third fourth outputs |
	provider reply: (Array with: (self code: '3 + 4
' call: 'c1')).
	provider reply: (Array with: (self code: 'o1 * 2' call: 'c2')).
	provider reply: (Array with: (ScriptedProvider show: 'o2' call: 'c3')).
	provider reply: #('Four' 'teen.') items: (Array with: (self message: 'Fourteen.')).
	self assert: (conversation ask: 'double 3 + 4'; wait) equals: 'Fourteen.'.
	self deny: conversation isBusy.
	self assert: (conversation items collect: [:each | each kind]) asArray equals: #(#user #code #code #show #assistant).
	outputs := (self itemsOfKind: #code) collect: [:each | each result].
	self assert: outputs equals: #('o1 7' 'o2 14').
	self assert: (conversation items at: 4) object equals: 14.
	self assert: (conversation items at: 4) objectId equals: 'o2'.
	self assert: (conversation items at: 4) result equals: 'shown'.
	self assert: provider requests size equals: 4.
	self assert: (provider requests first collect: [:each | each at: 'role']) equals: #('developer' 'user').
	self assert: ((provider requests first first at: 'content') first at: 'text') equals: (AgentInstructions textFor: conversation context).
	self assert: (provider toolSpecs collect: [:each | each at: 'name']) equals: #('code-mode' 'show-object').
	second := provider requests at: 2.
	self assert: second size equals: 4.
	self assert: ((second at: 3) at: 'call_id') equals: 'c1'.
	self assert: ((second at: 4) at: 'type') equals: 'custom_tool_call_output'.
	self assert: ((second at: 4) at: 'call_id') equals: 'c1'.
	self assert: ((second at: 4) at: 'output') equals: 'o1 7'.
	third := provider requests at: 3.
	self assert: third size equals: 6.
	self assert: ((third at: 6) at: 'output') equals: 'o2 14'.
	fourth := provider requests at: 4.
	self assert: fourth size equals: 8.
	self assert: ((fourth at: 7) at: 'type') equals: 'function_call'.
	self assert: ((fourth at: 8) at: 'type') equals: 'function_call_output'.
	self assert: ((fourth at: 8) at: 'output') equals: 'shown'.
	self assert: (conversation usage at: 'total_tokens') equals: 440.
	"The final message goes back in the next request."
	provider reply: (Array with: (self message: 'Bye.')).
	conversation ask: 'thanks'; wait.
	self assert: (provider requests last at: 9) == (conversation items at: 5) wire first.
	self assert: ((provider requests last at: 10) at: 'role') equals: 'user'
!
testObjectIdentity
	| outputs |
	outputs := self run: #('OrderedCollection new' 'o1 add: 3. o1' '3 + 4' 'nil' 'nil').
	self assert: outputs equals: #('o1 an OrderedCollection()' 'o1 an OrderedCollection(3)' 'o2 7' 'o3 nil' 'o3 nil').
	self assert: (conversation objectAt: 'o1') == ((self itemsOfKind: #code) at: 2) object.
	self assert: (conversation objectAt: 'o1') asArray equals: #(3).
	self assert: (conversation idFor: (conversation objectAt: 'o1')) equals: 'o1'.
	self assert: (conversation objectAt: 'o9') isNil.
	self assert: (self run: #('o1 == (o1 add: 4; yourself)')) last equals: 'o4 true'
!
testRuntimeError
	| outputs lines |
	outputs := self run: #('nil foo' 'self halt. 3' '1 / 0' '5').
	lines := (outputs at: 1) lines.
	self assert: lines first equals: 'error: MessageNotUnderstood: Instance of UndefinedObject did not understand #foo'.
	self assert: (lines at: 2) equals: '  UndefinedObject(ProtoObject)>>doesNotUnderstand:'.
	self assert: lines last equals: '  UndefinedObject>>DoIt'.
	self assert: ((outputs at: 2) beginsWith: 'error: Halt').
	self assert: ((outputs at: 3) beginsWith: 'error: ZeroDivide').
	self assert: (outputs at: 4) equals: 'o1 5'.
	self assert: (((self itemsOfKind: #code) collect: [:each | each failed]) asArray) equals: #(true true true false)
!
testSyntaxError
	| outputs |
	outputs := self run: #('3 +' '3 + 4').
	self assert: ((outputs at: 1) beginsWith: 'syntax error: ').
	self assert: (outputs at: 2) equals: 'o1 7'.
	self assert: (self itemsOfKind: #code) first failed
!
testPrintStringFails
	| outputs |
	outputs := self run: #('OrderedCollection basicNew').
	self assert: ((outputs at: 1) beginsWith: 'o1 ').
	self assert: ((outputs at: 1) includesSubstring: 'printString failed')
!
testLongPrintStringIsCut
	| outputs |
	outputs := self run: #('String new: 10000 withAll: $a').
	self assert: (outputs at: 1) size < 4100
!
testTimeout
	| outputs |
	(conversation toolNamed: 'code-mode') timeout: 1.
	outputs := self run: #('(Delay forSeconds: 30) wait. 3' '4').
	self assert: outputs equals: #('error: terminated after 1 s' 'o1 4').
	self deny: (Processor allProcesses anySatisfy: [:p | p name = 'agent code-mode'])
!
testShowUnknownObjectAndUnknownTool
	| other |
	other := (self code: '3' call: 'c2') at: 'name' put: 'no-such'; yourself.
	provider reply: (Array with: (ScriptedProvider show: 'o9' call: 'c1')).
	provider reply: (Array with: other).
	provider reply: (Array with: (self message: 'ok')).
	conversation ask: 'show o9'; wait.
	self assert: ((conversation items at: 2) wire last at: 'output') equals: 'error: no object o9'.
	self assert: (conversation items at: 3) result equals: 'error: no such tool'.
	self assert: (provider requests last collect: [:each | each at: 'type']) equals: #('message' 'message' 'function_call' 'function_call_output' 'custom_tool_call' 'custom_tool_call_output')
!
testStopDuringSend
	provider block.
	conversation ask: 'wait forever'.
	self assert: (self waitFor: [provider requests size = 1]).
	conversation stop.
	self deny: conversation isBusy.
	self assert: conversation items last kind equals: #error.
	self assert: conversation wait equals: 'Stopped.'.
	provider reply: (Array with: (self message: 'Back.')).
	self assert: (conversation ask: 'again'; wait) equals: 'Back.'.
	self assert: (provider requests last collect: [:each | each at: 'role' ifAbsent: [nil]]) equals: #('developer' 'user' 'user')
!
testStopDuringCell
	| cell request |
	provider reply: (Array with: (self code: '(Delay forSeconds: 30) wait' call: 'c1')).
	conversation ask: 'sleep'.
	self assert: (self waitFor: [Processor allProcesses anySatisfy: [:p | p name = 'agent code-mode']]).
	conversation stop.
	self deny: conversation isBusy.
	self deny: (Processor allProcesses anySatisfy: [:p | p name = 'agent code-mode' or: [p name = 'agent turn']]).
	cell := (self itemsOfKind: #code) first.
	self assert: cell failed.
	self assert: cell result equals: 'error: stopped by the user'.
	self assert: cell wire size equals: 2.
	provider reply: (Array with: (self message: 'Back.')).
	self assert: (conversation ask: 'again'; wait) equals: 'Back.'.
	request := provider requests last.
	self assert: (request collect: [:each | each at: 'type']) equals: #('message' 'message' 'custom_tool_call' 'custom_tool_call_output' 'message').
	self assert: ((request at: 4) at: 'output') equals: 'error: stopped by the user'
!
testACellEndsWithTheProcessWaitingForIt
	"Wherever that Process is terminated (Stop terminates the turn's): step a Process through a cell's evaluation until the cell's Process runs, and terminate it there."
	| item session cells left |
	item := AgentItem call: (self code: '(Delay forSeconds: 30) wait' call: 'c1') kind: #code text: '(Delay forSeconds: 30) wait'.
	session := DebugSession debugProcess: (self track: [(conversation toolNamed: 'code-mode') evaluate: item in: conversation] newProcess).
	cells := [Processor allProcesses select: [:p | p name = 'agent code-mode']].
	[session interruptedContext selector == #evaluate:in:] whileFalse: [session stepInto].
	[cells value isEmpty] whileTrue: [session stepThrough].
	session stepThrough.
	self deny: cells value first isSuspended description: 'the cell''s Process does not run yet'.
	session terminate.
	left := cells value.
	left do: [:each | each terminate].
	self assert: left isEmpty description: 'the cell''s Process is still there'
!
testProviderError
	provider fail: 'The network is down'.
	self assert: (conversation ask: 'hi'; wait) equals: 'The network is down'.
	self assert: conversation items last kind equals: #error.
	self assert: conversation items last wire isEmpty.
	self deny: conversation isBusy
!
testBusy
	provider block.
	conversation ask: 'one'.
	self should: [conversation ask: 'two'] raise: Error.
	conversation stop
!
testBusyBeforeTheMessageIsThere
	"Whenever another Process looks: step a Process through its ask:, looking after every step."
	| session frame |
	provider block.
	session := DebugSession debugProcess: (self track: [conversation ask: 'hi'] newProcess).
	[session interruptedContext selector == #ask:images:] whileFalse: [session stepInto].
	frame := session interruptedContext.
	[frame isDead] whileFalse: [
		session stepOver: frame.
		self assert: (conversation items isEmpty or: [conversation isBusy]) description: 'the message is there, the conversation not busy'].
	self assert: conversation items size equals: 1.
	session terminate
!
testOnChange
	| texts busy |
	texts := OrderedCollection new.
	busy := OrderedCollection new.
	conversation onChange: [:c |
		texts add: c items last text copy.
		busy add: c isBusy].
	provider reply: #('Hel' 'lo') items: (Array with: (self message: 'Hello')).
	conversation ask: 'hi'; wait.
	self assert: (texts includes: 'Hel').
	self assert: (texts includes: 'Hello').
	self assert: busy first.
	self deny: busy last
!
testShowFormSendsImage
	| message image |
	provider reply: (Array with: (self code: 'Form width: 2 height: 3' call: 'c1')).
	provider reply: (Array with: (ScriptedProvider show: 'o1' call: 'c2')).
	provider reply: (Array with: (self message: 'seen')).
	conversation ask: 'capture'; wait.
	message := provider requests last last.
	self assert: (message at: 'role') equals: 'user'.
	image := (message at: 'content') last.
	self assert: (image at: 'type') equals: 'input_image'.
	self assert: (image at: 'image_url') equals: 'data:image/png;base64,', (Base64 encode: (conversation objectAt: 'o1') pngBytes).
	self assert: ((provider requests last at: 6) at: 'output') equals: 'shown'
!
testInputKeepsInitialInstructions
	| first |
	conversation context: (AgentContext new receiver: 5; label: 'Original'; yourself).
	first := conversation input first.
	conversation context: (AgentContext new receiver: 99; label: 'Changed'; yourself).
	self assert: conversation input first == first.
	self assert: conversation input size equals: 1.
	self assert: conversation items isEmpty
!
testContextTokensUsesLatestRequest
	| c |
	c := AgentConversation new.
	self assert: c contextTokens isNil.
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 100; at: 'total_tokens' put: 120; yourself).
	c accumulateUsage: (Dictionary new at: 'input_tokens' put: 150; at: 'total_tokens' put: 180; yourself).
	self assert: c contextTokens = 150
!
testRetryAfterProviderError
	provider fail: 'The network is down'.
	conversation ask: 'hi'; wait.
	self assert: conversation canRetry.
	provider fail: 'Still down'.
	conversation retry; wait.
	self assert: conversation canRetry.
	self assert: (self itemsOfKind: #user) size equals: 1.
	self assert: (self itemsOfKind: #error) size equals: 2
! !

!AgentConversationTest methodsFor: 'tests - contexts'!
testReceiverAndBindings
	| bindings |
	bindings := Dictionary new.
	bindings at: #x put: #x -> 3.
	conversation context: (AgentContext new receiver: 5; bindings: bindings; label: 'Workspace'; yourself).
	self assert: (self run: #('self + x' 'x := 30' 'y := 400' 'o1 + y')) equals: #('o1 8' 'o2 30' 'o3 400' 'o4 408').
	self assert: (bindings at: #x) value equals: 30.
	self assert: (bindings at: #y) value equals: 400.
	self deny: (bindings includesKey: #o1).
	self assert: (conversation context describe includesSubstring: 'self: 5 (SmallInteger)').
	self assert: (conversation context describe includesSubstring: 'Variables: x y')
!
testFrame
	| process frame |
	process := self fork: [self frameOf: 20].
	self assert: (self waitFor: [process isSuspended]).
	frame := process suspendedContext findContextSuchThat: [:ctx | ctx selector == #frameOf:].
	conversation context: (AgentContext new frame: frame; yourself).
	self assert: conversation context receiver == self.
	self assert: (self run: #('x + y' 'self class name' 'o1 + x' 'y := 5')) equals: #('o1 41' 'o2 #AgentConversationTest' 'o3 61' 'o4 5').
	self assert: (conversation context describe includesSubstring: 'Frame: AgentConversationTest>>frameOf:').
	self assert: (conversation context describe includesSubstring: 'Variables: x y').
	process resume.
	self assert: (self waitFor: [frameResult notNil]).
	self assert: frameResult equals: 5
! !
