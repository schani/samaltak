Object subclass: #AgentTools
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools-Agent'!

AgentTools comment: 'I connect the Agent (AgentWindow, UI-Agent) to the desktop''s tools: ⌘J in a tool (Tools open: #agent with: aTool) and Agent in the Tools menu. The tools'' agentContext methods are extensions of this package.'!

!AgentTools class methodsFor: 'class initialization'!
initialize
	Tools registerOpener: #agent with: [:tool | AgentWindow openFor: tool].
	ToolsMenu register: 'Agent' description: '⌘J in a tool' order: 65 action: [:point |
		AgentWindow openOn: (AgentConversation on: (AgentContext new label: 'Desktop'; yourself)) origin: nil in: (Tools placeAt: point extent: 720 @ 640)]
! !
