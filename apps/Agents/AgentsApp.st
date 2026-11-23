Application subclass: #AgentsApp
	instanceVariableNames: 'card process wakeup'
	classVariableNames: ''
	package: 'Agents'!

AgentsApp comment: 'I am the Omarchy desktop''s agents card as a window of its own: an AgentsCard of the records omarchy-agent-usage-update keeps in ~/.local/state/omarchy/agents/usage, read again every minute (the times to reset count down), less the agents the card''s settings hide (~/.config/omarchy/desktop-cards.json, card "agents": {"settings": {"hide": ["kimi"]}}). The window''s height follows the agents shown.

	bin/samaltak run apps/Agents
	AgentsApp run

A click opens the bar''s Agents panel (omarchy-shell), a middle click asks the collectors for fresh limits (omarchy-agent-usage-update --limits-only) and reads the records again.'!

!AgentsApp methodsFor: 'accessing'!
title
	^'Agents'
!
card
	^card
!
content
	card isNil ifTrue: [
		card := AgentsCard new.
		card onActivate: [Omarchy togglePanel: 'omarchy.agents'].
		card onRefresh: [self update]].
	^card
!
backgroundColor
	^self content background
! !

!AgentsApp methodsFor: 'records'!
hidden
	| hide |
	hide := (Omarchy cardSettings: 'agents') at: 'hide' ifAbsent: [#()].
	^(hide isKindOf: Array) ifTrue: [hide] ifFalse: [#()]
!
readUsages
	^AgentUsage recordsIn: AgentUsage directory hiding: self hidden
!
now
	^Time utcMicroseconds / 1.0e6
!
reload
	"Read the records again and show them (any Process)."
	| usages t |
	usages := self readUsages.
	t := self now.
	window isNil
		ifTrue: [card usages: usages at: t]
		ifFalse: [window do: [card usages: usages at: t. self fitToContent]]
!
update
	"Ask the collectors for fresh limits, then read them."
	Omarchy launch: #('omarchy-agent-usage-update' '--limits-only') then: [:p | wakeup signal]
! !

!AgentsApp methodsFor: 'hooks'!
prepare
	OmarchyTheme install.
	"the window opens as tall as the agents it shows"
	self content.
	self reload
!
started
	wakeup := Semaphore new.
	process := [[wakeup waitTimeoutMSecs: 60000. self reload] repeat] newProcess.
	process priority: Processor userBackgroundPriority; name: 'Agents reload'.
	process resume
!
stopped
	process isNil ifFalse: [process terminate. process := nil]
! !
