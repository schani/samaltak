Button subclass: #AgentSignOutButton instanceVariableNames: '' classVariableNames: '' package: 'UI-Agent'!

!AgentSignOutButton methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| r ink paper frame |
	r := self localBounds.
	ink := self theme ink.
	paper := self theme paper.
	frame := self isEnabled ifTrue: [ink] ifFalse: [self theme color: #ink4].
	aCanvas fillRect: r color: (self isInverted ifTrue: [ink] ifFalse: [paper]).
	aCanvas fillRect: (0 @ 0 corner: self width @ 1) color: frame.
	aCanvas fillRect: (0 @ 0 corner: 1 @ self height) color: frame.
	aCanvas fillRect: ((self width - 1) @ 0 corner: self width @ self height) color: frame.
	aCanvas drawString: self label in: r font: self font color: (self isInverted ifTrue: [paper] ifFalse: [frame]) align: #center
! !
