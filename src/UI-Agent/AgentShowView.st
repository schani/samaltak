AgentItemView subclass: #AgentShowView
	instanceVariableNames: 'inspectButton objectText'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentShowView comment: 'I show an object the agent showed (show-object): a frame with a SHOW header, the object''s id and an Inspect button (opens the Inspector on it, where the tools are); in it a Form drawn as an image, scaled down to fit, or any other object''s printString (bounded).'!

!AgentShowView methodsFor: 'accessing'!
item: anAgentItem
	super item: anAgentItem.
	"The Inspector is a development tool: where there is none (an application's runtime image) the button does not show."
	inspectButton := Button label: 'Inspect' action: [(Smalltalk at: #Tools) inspect: item object near: self window].
	inspectButton name: 'inspect'; visible: (Smalltalk at: #Tools ifAbsent: [nil]) notNil.
	self addChild: inspectButton
!
isForm
	^item object isKindOf: Form
!
objectText
	^objectText ifNil: [objectText := [item object printStringLimitedTo: 1000]
		on: Error do: [:e | e return: 'a ', item object class name, ' (printString failed)']]
!
headerHeight
	^26
!
font
	^self theme font: #codeSmall
!
textLinesFor: aWidth
	| lines |
	lines := self wrap: self objectText font: self font width: aWidth - self gutterWidth - self margin - 16.
	^lines size > 8 ifTrue: [(lines first: 8) copyWith: '…'] ifFalse: [lines]
!
imageExtentFor: aWidth
	"The Form's extent scaled down to fit aWidth and 240 points."
	| form scale |
	form := item object.
	scale := ((aWidth - self gutterWidth - self margin - 16) / (form width max: 1) min: 240 / (form height max: 1)) min: 1.
	^((form width * scale) rounded max: 1) @ ((form height * scale) rounded max: 1)
! !

!AgentShowView methodsFor: 'layout'!
computeHeightFor: aWidth
	^self headerHeight + 6 + (self isForm
		ifTrue: [(self imageExtentFor: aWidth) y]
		ifFalse: [(self textLinesFor: aWidth) size * self font lineHeight]) + 6 + 8
!
layout
	| e |
	e := inspectButton preferredExtent.
	inspectButton bounds: ((self width - self margin - 4 - e x) @ 3 extent: e)
!
gutterWidth
	^0
!
margin
	^0
! !

!AgentShowView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| box x y |
	box := self gutterWidth @ 0 corner: (self width - self margin) @ (self height - 8).
	aCanvas fillRect: box color: self theme paper.
	aCanvas strokeRect: box color: self theme ink width: 1.
	x := box left + 8.
	aCanvas drawString: 'Show' at: x @ 6 font: (self theme font: #header) color: self theme ink.
	self drawOref: item objectId at: (x + ((self theme font: #header) widthOf: 'SHOW') + 8) @ 4 on: aCanvas.
	aCanvas fillRect: (box left @ (self headerHeight - 1) extent: box width @ 1) color: self theme rule.
	y := self headerHeight + 6.
	self isForm ifTrue: [^aCanvas image: item object in: (x @ y extent: (self imageExtentFor: self width))].
	aCanvas clip: (box insetBy: 1) during: [
		(self textLinesFor: self width) do: [:line |
			aCanvas drawString: line at: x @ y font: self font color: self theme ink.
			y := y + self font lineHeight]]
! !

!AgentShowView methodsFor: 'remote control'!
remoteLabel
	^item objectId, ' ', (self isForm ifTrue: [item object printString] ifFalse: [self objectText])
! !
