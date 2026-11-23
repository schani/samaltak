Application subclass: #AgentApp
	instanceVariableNames: 'view'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentApp comment: 'I am the Agent as an application of its own, a resizable window of the host''s window manager on a conversation that binds nothing: bin/samaltak agent. The sign-in is the one every application''s Agent shares (AgentWindow accountPath).

	bin/samaltak agent
	AgentApp run'!

!AgentApp methodsFor: 'accessing'!
title
	^'Agent'
!
content
	view isNil ifTrue: [
		AgentWindow account == OpenAIAccount default ifTrue: [OpenAIAccount default keepIn: AgentWindow accountPath].
		view := AgentWindow new
			setConversation: (AgentConversation on: (AgentContext new label: 'Samaltak'; yourself))
			origin: nil
			account: AgentWindow account].
	^view
!
extent
	^720 @ 640
!
isResizable
	^true
! !

!AgentApp methodsFor: 'hooks'!
started
	window whenClosed: [:w | view windowClosed].
	window do: [view update. view askEditor focus]
! !

!AgentApp methodsFor: 'context'!
agentContext
	"Its menu's Agent opens a second agent on this one (AgentWindow>>agentContext)."
	^view agentContext
! !
