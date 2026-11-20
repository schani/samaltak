AgentWindowTest subclass: #AgentAskProbeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

AgentAskProbeTest comment: 'CI probe, not for merging: AgentWindowTest>>testATurnShowsItsItems PROBE_COUNT times in one VM.'!

!AgentAskProbeTest class methodsFor: 'accessing'!
suite
	^(1 to: PROBE_COUNT) collect: [:i | self selector: #testATurnShowsItsItems]
! !
