Widget subclass: #AgentTranscript
	instanceVariableNames: 'conversation count'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentTranscript comment: 'I am the transcript of an AgentWindow, the content of its ScrollPane: one AgentItemView per shown item of the conversation, stacked, each as tall as it needs at my width. sync (in my window''s Process) adds views for new items and redraws the changed ones.'!

!AgentTranscript methodsFor: 'initialization'!
conversation: anAgentConversation
	conversation := anAgentConversation.
	count := 0
! !

!AgentTranscript methodsFor: 'updating'!
sync
	| items |
	items := conversation items.
	[count < items size] whileTrue: [
		count := count + 1.
		(AgentItemView for: (items at: count)) ifNotNil: [:view |
			view name: (items at: count) kind, '-', count printString.
			((view isKindOf: AgentMessageView) and: [view hasRetry]) ifTrue: [
				view addChild: ((Button label: 'Retry' action: [conversation retry]) name: 'retry'; yourself)].
			self addChild: view]].
	self children do: [:each |
		each refresh.
		each children do: [:button |
			button name = 'retry' ifTrue: [button enabled: (conversation canRetry and: [each item == conversation items last])]]].
	self layout
! !

!AgentTranscript methodsFor: 'layout'!
viewWidth
	"The ScrollPane's width less its scroll bar's, whether that shows or not."
	^(owner isNil ifTrue: [self width] ifFalse: [owner width - (self theme metric: #scrollBarWidth)]) max: 200
!
preferredExtent
	| w previous height |
	w := self viewWidth.
	height := self children inject: 12 into: [:sum :each | | next |
		next := sum + (self topGapFor: each after: previous)
			+ (each heightFor: w - (2 * (self insetFor: each))).
		previous := each.
		next].
	^w @ height
!
layout
	| w y previous |
	w := self viewWidth.
	y := 6.
	self children do: [:each | | inset width h |
		inset := self insetFor: each.
		width := w - (2 * inset).
		h := each heightFor: width.
		y := y + (self topGapFor: each after: previous).
		each bounds: (inset @ y extent: width @ h).
		y := y + h.
		previous := each]
!
insetFor: aView
	^((aView isKindOf: AgentCodeView) or: [aView isKindOf: AgentShowView])
		ifTrue: [4] ifFalse: [0]
!
topGapFor: aView after: previousView
	((aView isKindOf: AgentCodeView) and: [previousView isKindOf: AgentCodeView])
		ifTrue: [^0].
	^self insetFor: aView
! !
