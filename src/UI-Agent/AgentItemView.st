Widget subclass: #AgentItemView
	instanceVariableNames: 'item shown heights'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentItemView comment: 'I am the abstract view of one AgentItem in an AgentWindow''s transcript (AgentTranscript), as tall as heightFor: my width answers. AgentItemView for: anItem answers the view for its kind (nil: not shown, e.g. #reasoning): the seam for richer views. refresh redraws me when what I show of the item changed (an assistant message grows while it streams, a cell gets its result).

Geometry: a gutter of gutterWidth on the left (who speaks), the content up to margin from the right.'!

!AgentItemView methodsFor: 'accessing'!
item
	^item
!
item: anAgentItem
	item := anAgentItem.
	shown := self shownState
!
gutterWidth
	^62
!
margin
	^14
!
contentWidth
	^self width - self gutterWidth - self margin max: 40
!
agentContext
	^AgentContext new
		receiver: item object;
		label: item objectId;
		yourself
! !

!AgentItemView methodsFor: 'updating'!
shownState
	^Array with: item text with: item result with: item failed
!
refresh
	"Redraw me if my item changed since I last showed it."
	| state |
	state := self shownState.
	state = shown ifTrue: [^self].
	shown := state.
	heights := nil.
	self invalidate
! !

!AgentItemView methodsFor: 'layout'!
heightFor: aWidth
	"My height when I am aWidth wide (cached)."
	(heights notNil and: [heights key = aWidth]) ifTrue: [^heights value].
	heights := aWidth -> (self computeHeightFor: aWidth).
	^heights value
!
computeHeightFor: aWidth
	^self subclassResponsibility
!
wrap: aString font: aFont width: aWidth
	"aString's lines broken at spaces to fit aWidth."
	| lines |
	lines := OrderedCollection new.
	(aString isEmpty ifTrue: [#('')] ifFalse: [aString lines]) do: [:paragraph | | line |
		line := ''.
		(paragraph substrings: ' ') do: [:word | | candidate |
			candidate := line isEmpty ifTrue: [word] ifFalse: [line, ' ', word].
			((aFont widthOf: candidate) > aWidth and: [line notEmpty])
				ifTrue: [lines add: line. line := word]
				ifFalse: [line := candidate]].
		lines add: line].
	^lines
! !

!AgentItemView methodsFor: 'drawing'!
drawOref: anId at: aPoint on: aCanvas
	"An object id boxed in ultramarine (the mock's .oref); answer its width."
	| font w |
	font := self theme font: #codeSmall.
	w := (font widthOf: anId) + 8.
	aCanvas strokeRect: (aPoint extent: w @ font lineHeight) color: self theme ultramarine width: 1.
	aCanvas drawString: anId at: aPoint + (4 @ 0) font: font color: self theme ultramarine.
	^w
!
drawOverlayOn: aCanvas
	self hasKeyboardFocus ifTrue: [
		aCanvas strokeRect: ((self gutterWidth @ 0 corner: (self width - self margin) @ (self height - 8)) insetBy: 1) color: self theme ultramarine width: 2]
! !

!AgentItemView methodsFor: 'remote control'!
remoteRole
	^#item
!
remoteLabel
	^item text
!
remoteState
	^item failed ifTrue: [#(#failed)] ifFalse: [#()]
! !

!AgentItemView class methodsFor: 'instance creation'!
for: anAgentItem
	"The view for anAgentItem, or nil if it is not shown."
	| class |
	class := Dictionary new
		at: #user put: AgentMessageView;
		at: #assistant put: AgentMessageView;
		at: #error put: AgentMessageView;
		at: #code put: AgentCodeView;
		at: #show put: AgentShowView;
		yourself.
	^(class at: anAgentItem kind ifAbsent: [^nil]) new item: anAgentItem; yourself
! !

!AgentItemView methodsFor: 'events'!
wantsKeyboardFocus
	^item notNil and: [item objectId notNil and: [item failed not]]
!
mouseDown: anEvent
	self wantsKeyboardFocus ifFalse: [^false].
	self focus.
	^true
! !
