Object subclass: #AgentConversation
	instanceVariableNames: 'context items objects tools provider process done streaming usage changeBlock initialInstructions'
	classVariableNames: ''
	package: 'System-Agent'!

AgentConversation comment: 'I am a conversation with the coding agent (docs/agent.md): my items (AgentItems, the transcript), my object table (objects by identity: the id ''o3'' is the third, kept strongly, an object keeps its id), my AgentContext and my tools.

	(AgentConversation new ask: ''how many classes are in UI-Widgets?'') wait

ask: runs a turn in a Process of its own (''agent turn''): send the developer instructions and every item''s wire to the provider, show the streamed text, record the completed output items in order and run each tool call; while there were tool calls, send again. Any error ends the turn with an #error item. ask: while a turn runs is an error; I am busy (isBusy) from before the turn''s user message is among my items. stop ends a turn from another Process: the provider is cancelled, the turn''s Process and its running cell terminated, every tool call left without output answered ''error: stopped by the user'', so the next request is valid.

The provider (late-bound, default a new CodexProvider) answers send:tools:onText:onItem: (blocking; the usage Dictionary or nil; AgentError on failure), cancel and modelName. My onChange: block is evaluated after every visible change: an item added, streaming text grown, a turn begun or ended.'!

!AgentConversation methodsFor: 'initialization'!
initialize
	context := AgentContext new.
	items := OrderedCollection new.
	objects := OrderedCollection new.
	tools := AgentTool all
! !

!AgentConversation methodsFor: 'accessing'!
context
	^context
!
context: anAgentContext
	context := anAgentContext
!
items
	^items
!
tools
	^tools
!
toolNamed: aString
	^tools detect: [:each | each name = aString] ifNone: [nil]
!
provider
	^provider ifNil: [provider := (Smalltalk at: #CodexProvider ifAbsent: [AgentError signal: 'No provider: CodexProvider is not in this image']) new]
!
provider: aProvider
	provider := aProvider
!
usage
	"The cumulative token usage of all completed responses in this conversation, or nil."
	^usage
!
add: anAgentItem
	items add: anAgentItem.
	self changed.
	^anAgentItem
!
onChange: aBlock
	"Set the default subscriber, or remove it with nil."
	self onChange: aBlock for: self
!
onChange: aBlock for: anOwner
	"Subscribe an owner to visible changes; nil removes its subscription."
	changeBlock ifNil: [changeBlock := IdentityDictionary new].
	aBlock
		ifNil: [changeBlock removeKey: anOwner ifAbsent: []]
		ifNotNil: [changeBlock at: anOwner put: aBlock]
!
contextTokens
	"Latest measured context size, as reported for the last completed request."
	^usage ifNotNil: [usage at: 'context_tokens' ifAbsent: [nil]]
!
canRetry
	^self isBusy not and: [items notEmpty and: [items last kind = #error and: [items last failed and: [items last call isNil]]]]
! !

!AgentConversation methodsFor: 'objects'!
idFor: anObject
	"anObject's id, registering it if it has none."
	objects doWithIndex: [:each :i | each == anObject ifTrue: [^'o', i printString]].
	objects add: anObject.
	^'o', objects size printString
!
objectAt: anId ifAbsent: aBlock
	| index |
	(anId isString and: [anId size > 1 and: [anId first = $o]]) ifFalse: [^aBlock value].
	index := Integer readFrom: anId allButFirst ifFail: [^aBlock value].
	(index between: 1 and: objects size) ifFalse: [^aBlock value].
	^objects at: index
!
objectAt: anId
	^self objectAt: anId ifAbsent: [nil]
!
objectBindings
	"o1 … oN as variables of a cell (Symbol -> Association)."
	| bindings |
	bindings := Dictionary new.
	objects doWithIndex: [:each :i | | name |
		name := ('o', i printString) asSymbol.
		bindings at: name put: name -> each].
	^bindings
! !

!AgentConversation methodsFor: 'asking'!
ask: aString
	^self ask: aString images: #()
!
wait
	"Block until the turn ends; answer the last assistant text, or the error that ended the turn."
	| semaphore |
	semaphore := done.
	(self isBusy and: [semaphore notNil]) ifTrue: [semaphore wait. semaphore signal].
	^self lastText
!
isBusy
	^process notNil
!
stop
	"End the running turn (from another Process)."
	| turn |
	turn := process.
	turn isNil ifTrue: [^self].
	process := nil.
	turn terminate.
	provider ifNotNil: [:p | p cancel].
	items do: [:each | each isOpen ifTrue: [each failed: true; output: 'error: stopped by the user']].
	items add: (AgentItem kind: #error text: 'Stopped.').
	self endTurn
!
lastText
	items reverseDo: [:each |
		(each kind == #assistant or: [each kind == #error and: [each wire isEmpty]]) ifTrue: [^each text]].
	^nil
! !

!AgentConversation methodsFor: 'turn'!
runTurn
	[[self request] whileTrue]
		on: Error do: [:e |
			items add: ((AgentItem kind: #error text: ((e isKindOf: AgentError)
				ifTrue: [e messageText asString]
				ifFalse: [e class name asString, ': ', e messageText asString])) failed: true; yourself).
			e return: nil]
!
grow: aString
	streaming isNil ifTrue: [streaming := self add: (AgentItem kind: #assistant text: '')].
	streaming text: streaming text, aString.
	self changed
!
record: anItem
	"Add the completed output item anItem; if it is a tool call, run it and answer true."
	| type item tool |
	type := anItem at: 'type' ifAbsent: [nil].
	type = 'message' ifTrue: [
		item := streaming ifNil: [self add: (AgentItem kind: #assistant text: '')].
		streaming := nil.
		item text: (AgentItem textOf: anItem); wire: (Array with: anItem).
		self changed.
		^false].
	type = 'reasoning' ifTrue: [
		self add: ((AgentItem kind: #reasoning text: '') wire: (Array with: anItem); yourself).
		^false].
	(AgentItem isCall: anItem) ifFalse: [^false].
	tool := self toolNamed: (anItem at: 'name' ifAbsent: [nil]).
	tool isNil
		ifTrue: [
			item := AgentItem call: anItem kind: #error text: 'no such tool: ', (anItem at: 'name' ifAbsent: ['']) asString.
			item failed: true; output: 'error: no such tool'.
			self add: item]
		ifFalse: [tool run: anItem in: self].
	^true
!
endTurn
	process := nil.
	done signal.
	self changed
! !

!AgentConversation class methodsFor: 'instance creation'!
on: anAgentContext
	^self new context: anAgentContext; yourself
! !

!AgentConversation methodsFor: 'running'!
ask: aString images: images
	"Add a user message with image content and start a turn. I am busy before the message is there: another Process that sees it and sees me not busy sees a turn that is over."
	| message |
	self isBusy ifTrue: [^self error: 'The agent is busy: wait for it or stop it first'].
	message := AgentItem user: aString images: images.
	done := Semaphore new.
	process := [self runTurn. self endTurn] newProcess.
	process priority: Processor userSchedulingPriority; name: 'agent turn'.
	self add: message.
	process resume
! !

!AgentConversation methodsFor: 'private'!
changed
	changeBlock ifNotNil: [
		changeBlock values copy do: [:block | block value: self]]
!
accumulateUsage: answer
	"Sum token usage across every response in this conversation."
	| details cached previous |
	usage isNil ifTrue: [usage := Dictionary new].
	usage at: 'context_tokens' put: (answer at: 'input_tokens' ifAbsent: [nil]).
	#('input_tokens' 'output_tokens' 'total_tokens') do: [:key |
		usage at: key put: (usage at: key ifAbsent: [0]) + (answer at: key ifAbsent: [0])].
	details := answer at: 'input_tokens_details' ifAbsent: [nil].
	details ifNotNil: [
		cached := details at: 'cached_tokens' ifAbsent: [0].
		previous := usage at: 'input_tokens_details' ifAbsentPut: [Dictionary new].
		previous at: 'cached_tokens' put: (previous at: 'cached_tokens' ifAbsent: [0]) + cached]


!
request
	"Send everything so far, then record the response's items and run its tool calls; answer whether there were any."
	| received called answer |
	received := OrderedCollection new.
	streaming := nil.
	answer := self provider
		send: self input
		tools: (tools collect: [:each | each spec])
		onText: [:delta | self grow: delta]
		onItem: [:item | received add: item].
	answer ifNotNil: [self accumulateUsage: answer].
	called := false.
	received do: [:item | (self record: item) ifTrue: [called := true]].
	^called
!
input
	"Snapshot initial instructions once. Never rewrite the prefix from live context."
	| input |
	initialInstructions ifNil: [
		initialInstructions := AgentItem message: 'developer' text: (AgentInstructions textFor: context)].
	input := OrderedCollection new.
	input add: initialInstructions.
	items do: [:each | input addAll: each wire].
	^input asArray
! !

!AgentConversation methodsFor: 'actions'!
retry
	"Resume the failed turn without adding another user message."
	self canRetry ifFalse: [^self].
	streaming := nil.
	done := Semaphore new.
	process := [self runTurn. self endTurn] newProcess.
	process priority: Processor userSchedulingPriority; name: 'agent turn'.
	self changed.
	process resume
! !
