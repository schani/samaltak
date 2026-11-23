AgentItemView subclass: #AgentMessageView
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Agent'!

AgentMessageView comment: 'I show a message of an AgentConversation as wrapped plain text: the user''s (You, a rule above: a new turn), the agent''s (growing while it streams) or an error (in ultramarine).'!

!AgentMessageView methodsFor: 'layout'!
font
	^self theme font: #ui
!
lines
	^self wrap: item text font: self font width: self contentWidth
!
top
	^item kind == #user ifTrue: [9] ifFalse: [3]
!
computeHeightFor: aWidth
	| textWidth |
	textWidth := aWidth - self gutterWidth - self margin max: 40.
	^self top + ((self wrap: item text font: self font width: textWidth) size * self font lineHeight)
		+ (item kind == #user ifTrue: [9] ifFalse: [5]) + (self hasRetry ifTrue: [30] ifFalse: [0])
!
layout
	self children do: [:button |
		button bounds: (self gutterWidth @ (self height - 30) extent: 70 @ 26)]
!
gutterWidth
	^item kind == #error ifTrue: [super gutterWidth] ifFalse: [self margin]
! !

!AgentMessageView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| font y color |
	font := self font.
	color := self theme ink.
	item kind == #user ifTrue: [
		aCanvas fillRect: (0 @ 0 extent: self width @ self height) color: self theme ink.
		color := self theme paper].
	item kind == #error ifTrue: [
		color := self theme ultramarine.
		aCanvas drawString: 'Error' in: (0 @ self top extent: (self gutterWidth - 12) @ font lineHeight)
			font: (self theme font: #uiBold) color: color align: #right].
	y := self top.
	self lines do: [:line |
		aCanvas drawString: line at: self gutterWidth @ y font: font color: color.
		y := y + font lineHeight]
! !

!AgentMessageView methodsFor: 'testing'!
hasRetry
	^item kind = #error and: [item failed and: [item call isNil]]
! !
