!AgentWindow class methodsFor: '*Tools-Agent'!
openFor: aTool
	^self openFor: aTool context: aTool
!
openFor: aToolOrNil context: aContext
	"⌘J opens the Agent for a tool on aContext's agentContext, bringing it back if already open."
	| existing |
	existing := aToolOrNil isNil ifFalse: [(Tools windowsOf: self) detect: [:each | each content origin == aToolOrNil] ifNone: [nil]].
	existing isNil ifFalse: [existing focus. ^existing].
	^self openOn: (AgentConversation on: aContext agentContext) origin: aToolOrNil in: (Tools placeNear: aContext window extent: 720 @ 640)
! !
