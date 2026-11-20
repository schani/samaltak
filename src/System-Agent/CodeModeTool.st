AgentTool subclass: #CodeModeTool
	instanceVariableNames: 'timeout'
	classVariableNames: ''
	package: 'System-Agent'!

CodeModeTool comment: 'I am the code-mode tool: the call''s input is Smalltalk source, run as a do-it against the conversation''s AgentContext with the conversation''s objects bound as o1 … oN. It runs in a fresh Process (''agent code-mode'', the priority of a Workspace do-it); the turn waits for it at most timeout seconds (default 60), then terminates it.

The output is the value''s id and printString (cut to 4,000 characters), e.g. ''o2 an Array(3 4)''; ''syntax error: <message>''; ''error: <class>: <messageText>'' and the top 10 frames of the signaling stack (an unhandled error, halt or breakpoint ends the cell''s Process, no debugger opens); or ''error: terminated after 60 s''.'!

!CodeModeTool methodsFor: 'initialization'!
initialize
	timeout := 60
! !

!CodeModeTool methodsFor: 'accessing'!
name
	^'code-mode'
!
spec
	^Dictionary new
		at: 'type' put: 'custom';
		at: 'name' put: self name;
		at: 'description' put: 'Run Smalltalk code in the live image. The input is raw Smalltalk source (statements or an expression), not JSON. Answers the id of the resulting object (o1, o2, ...) and its printString; later code can use the id as a variable bound to that object.';
		at: 'format' put: (Dictionary new at: 'type' put: 'text'; yourself);
		yourself
!
timeout
	"Seconds a cell may run."
	^timeout
!
timeout: seconds
	timeout := seconds
! !

!CodeModeTool methodsFor: 'running'!
run: aCallDictionary in: anAgentConversation
	| item |
	item := AgentItem call: aCallDictionary kind: #code text: (aCallDictionary at: 'input' ifAbsent: ['']).
	anAgentConversation add: item.
	self evaluate: item in: anAgentConversation.
	anAgentConversation changed.
	^item result
!
evaluate: anAgentItem in: anAgentConversation
	"Run anAgentItem's source in a new Process and wait for it; give anAgentItem its value or error and its output. That Process ends with the wait, also when the waiting Process is terminated, wherever it is."
	| done value text error process |
	done := Semaphore new.
	[process := [
		[[[value := anAgentConversation context evaluate: anAgentItem text bindings: anAgentConversation objectBindings.
		   text := self printStringOf: value]
			on: SyntaxError do: [:e | error := 'syntax error: ', e messageText asString. e return: nil]]
			on: UnhandledError do: [:e | error := self describeError: e exception. e return: nil]]
				ensure: [done signal]] newProcess.
	 process priority: Processor userSchedulingPriority; name: 'agent code-mode'.
	 process resume.
	 (done waitTimeoutMSecs: (timeout * 1000) rounded)
		ifTrue: [error := 'error: terminated after ', timeout printString, ' s']]
			ensure: [process isNil ifFalse: [process terminate]].
	(error isNil and: [text isNil]) ifTrue: [error := 'error: terminated'].
	error notNil ifTrue: [
		anAgentItem failed: true.
		^anAgentItem output: error].
	anAgentItem object: value; objectId: (anAgentConversation idFor: value).
	anAgentItem output: anAgentItem objectId, ' ', text
!
printStringOf: anObject
	^[anObject printStringLimitedTo: 4000] on: Error do: [:e |
		e return: 'a ', anObject class name, ' (printString failed: ', e messageText asString, ')']
!
describeError: anException
	"error: <class>: <messageText>, then the frames from the signaler down to the cell's DoIt, at most 10, indented."
	| ctx count |
	^String new: 400 streamContents: [:s |
		s nextPutAll: 'error: '; nextPutAll: anException class name; nextPutAll: ': '; nextPutAll: anException messageText asString.
		ctx := anException signalerContext.
		count := 0.
		[ctx notNil and: [count < 10 and: [ctx method ~~ (Compiler >> #evaluate:for:)]]] whileTrue: [
			s nextPut: Character lf; nextPutAll: '  '; nextPutAll: ([ctx printString] on: Error do: [:e | e return: '?']).
			ctx := ctx sender.
			count := count + 1]]
! !
