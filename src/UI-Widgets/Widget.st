View subclass: #Widget
	instanceVariableNames: 'children sizeSpec padding tooltip menuBlock name visible enabled minExtent selfDrawing overlayDrawing'
	classVariableNames: 'FallbackClipboard'
	package: 'UI-Widgets'!

Widget comment: 'I am the root of the widgets (docs/ui.md, UI-Widgets): a View with children, a size spec for my container''s layout, padding, a tooltip, a context menu (menuBlock:), enabled/visible flags and the remote-control protocol.

Drawing: drawOn: draws me (drawSelfOn:), then each visible child translated to its origin and clipped to its bounds, then drawOverlayOn:, so a Window only draws its content. Subclasses override drawSelfOn:. Drawing is retained (View): what drawSelfOn: and drawOverlayOn: drew is replayed until I change, and so is each child that did not change. invalidate when what I show changes (my whole subtree is drawn anew; invalidateOverlay redraws only drawOverlayOn:); a drawing that shows values computed while drawing calls Canvas>>noteVolatile.

Events: handlePointer:, handleKey:, handleText: and handleTextEditing: (the View contract) dispatch to mouseDown: rightMouseDown: mouseMove: mouseUp: wheel: mouseEnter: mouseLeave: keyDown: textInput: textEditing:, which answer true when handled (false bubbles to the owner). An unhandled right-button down makes the Window open contextMenuAt: (a Menu or nil); the Window also gives keyboard focus to a widget that wantsKeyboardFocus.

Layout: a container (Row, Column, Stack) sizes its children by their sizeSpec: "fixed: points", "flex: weight" (default flex: 1), "percent: p". Widgets that compute their own size answer preferredExtent.

Remote control: remoteRole (from the class), remoteLabel, remoteState (focused, disabled), remoteName (name:), remoteChildren (visible children), remoteBounds (screen points).'!

!Widget methodsFor: 'initialization'!
initialize
	super initialize.
	visible := true.
	enabled := true
! !

!Widget methodsFor: 'accessing'!
theme
	^Theme current
!
name
	^name
!
name: aString
	"The stable remote-control slug (e.g. 'packages')."
	name := aString
!
tooltip
	^tooltip
!
tooltip: aString
	tooltip := aString
!
isVisible
	^visible ~~ false
!
visible: aBoolean
	visible = aBoolean ifTrue: [^self].
	visible := aBoolean.
	owner isNil ifFalse: [owner layout].
	self invalidate
!
setVisible: aBoolean
	"Change visibility without asking my container for a new layout (for containers laying me out)."
	visible == aBoolean ifTrue: [^self].
	visible := aBoolean.
	self ownersChanged
!
isEnabled
	^enabled ~~ false
!
enabled: aBoolean
	enabled = aBoolean ifTrue: [^self].
	enabled := aBoolean.
	self invalidate
!
padding
	"Insets as a Rectangle (left top right bottom)."
	^padding ifNil: [0 @ 0 corner: 0 @ 0]
!
padding: aNumberOrPointOrRectangle
	padding := aNumberOrPointOrRectangle isNumber
		ifTrue: [aNumberOrPointOrRectangle @ aNumberOrPointOrRectangle corner: aNumberOrPointOrRectangle @ aNumberOrPointOrRectangle]
		ifFalse: [
			aNumberOrPointOrRectangle isPoint
				ifTrue: [aNumberOrPointOrRectangle corner: aNumberOrPointOrRectangle]
				ifFalse: [aNumberOrPointOrRectangle]].
	self layout
!
innerBounds
	"My local bounds minus padding."
	| p |
	p := self padding.
	^p origin corner: self bounds extent - p corner
!
minExtent
	^minExtent ifNil: [0 @ 0]
!
minExtent: aPoint
	minExtent := aPoint
!
preferredExtent
	"The size I would like (containers use it for fixed specs given as #preferred)."
	^self minExtent
! !

!Widget methodsFor: 'tree'!
children
	^children ifNil: [#()]
!
addChild: aWidget
	children isNil ifTrue: [children := OrderedCollection new].
	children add: aWidget.
	aWidget owner: self.
	self layout.
	self invalidate.
	^aWidget
!
add: aWidget
	^self addChild: aWidget
!
addAll: aCollection
	aCollection do: [:each |
		children isNil ifTrue: [children := OrderedCollection new].
		children add: each.
		each owner: self].
	self layout.
	self invalidate
!
removeChild: aWidget
	children isNil ifTrue: [^aWidget].
	children remove: aWidget ifAbsent: [^aWidget].
	aWidget owner: nil.
	self layout.
	self invalidate.
	^aWidget
!
removeAllChildren
	self children do: [:each | each owner: nil].
	children := nil.
	self invalidate
!
visibleChildren
	^self children select: [:each | each isVisible]
!
root
	| w |
	w := self.
	[w owner notNil] whileTrue: [w := w owner].
	^w
!
allWidgetsDo: aBlock
	aBlock value: self.
	self children do: [:each | (each respondsTo: #allWidgetsDo:) ifTrue: [each allWidgetsDo: aBlock]]
!
detectWidget: aBlock
	self allWidgetsDo: [:each | (aBlock value: each) ifTrue: [^each]].
	^nil
!
widgetNamed: aString
	^self detectWidget: [:each | each name = aString]
! !

!Widget methodsFor: 'size specs'!
sizeSpec
	"#(#flex 1), #(#fixed points) or #(#percent p), used by my container."
	^sizeSpec ifNil: [#(#flex 1)]
!
fixed: points
	sizeSpec := Array with: #fixed with: points.
	owner isNil ifFalse: [owner layout]
!
flex: weight
	sizeSpec := Array with: #flex with: weight.
	owner isNil ifFalse: [owner layout]
!
percent: p
	sizeSpec := Array with: #percent with: p.
	owner isNil ifFalse: [owner layout]
!
sizeToContent
	"Take my preferredExtent along my container's axis."
	sizeSpec := #(#preferred 0).
	owner isNil ifFalse: [owner layout]
!
isFixedSize
	^self sizeSpec first == #fixed
! !

!Widget methodsFor: 'coordinates'!
localToScreen: aPoint
	"Screen points of a local point (View>>screenPointFrom:)."
	^self screenPointFrom: aPoint
!
localEventPosition: anEvent
	"anEvent's position in my coordinates (the Window delivers events local to the receiver)."
	^anEvent position
! !

!Widget methodsFor: 'theme helpers'!
fontFor: aFontOrSymbol
	aFontOrSymbol isSymbol ifTrue: [^self theme font: aFontOrSymbol].
	^aFontOrSymbol
!
colorFor: aColorOrSymbol
	aColorOrSymbol isSymbol ifTrue: [^self theme color: aColorOrSymbol].
	^aColorOrSymbol
! !

!Widget methodsFor: 'drawing'!
drawOn: aCanvas
	(selfDrawing notNil and: [aCanvas replay: selfDrawing])
		ifTrue: [View isVerifyingDrawing ifTrue: [self verifyReplay: selfDrawing on: aCanvas drawing: [:c | self drawSelfOn: c]]]
		ifFalse: [selfDrawing := aCanvas record: [self drawSelfOn: aCanvas]].
	self drawChildrenOn: aCanvas.
	(overlayDrawing notNil and: [aCanvas replay: overlayDrawing])
		ifTrue: [View isVerifyingDrawing ifTrue: [self verifyReplay: overlayDrawing on: aCanvas drawing: [:c | self drawOverlayOn: c]]]
		ifFalse: [overlayDrawing := aCanvas record: [self drawOverlayOn: aCanvas]]
!
invalidateOverlay
	"Only what drawOverlayOn: draws changed."
	overlayDrawing := nil.
	self childDrawingChanged.
	self ownersChanged.
	self requestRedraw
!
forgetDrawing
	super forgetDrawing.
	selfDrawing := nil.
	overlayDrawing := nil
!
drawSelfOn: aCanvas
	"Subclasses draw themselves here, in local coordinates."
!
drawOverlayOn: aCanvas
	"Drawn after the children (focus rings, glides)."
!
drawChildrenOn: aCanvas
	| clip |
	children isNil ifTrue: [^self].
	clip := aCanvas clipRect.
	children do: [:each |
		(each isVisible and: [each bounds intersects: clip]) ifTrue: [
			aCanvas translateBy: each bounds origin during: [
				aCanvas clip: each localBounds during: [each drawRetainedOn: aCanvas]]]]
!
fullDrawOn: aCanvas
	^self drawOn: aCanvas
! !

!Widget methodsFor: 'layout'!
layout
	"Containers place their children here (called after bounds: and when children change)."
! !

!Widget methodsFor: 'events'!
viewAt: aPoint
	children isNil ifFalse: [
		children reverseDo: [:each |
			(each isVisible and: [each bounds containsPoint: aPoint])
				ifTrue: [^each viewAt: aPoint - each bounds origin]]].
	^self
!
handlePointer: anEvent
	| type |
	type := anEvent type.
	type == #down ifTrue: [
		anEvent button = 2 ifTrue: [^self rightMouseDown: anEvent].
		^self mouseDown: anEvent].
	type == #move ifTrue: [^self mouseMove: anEvent].
	type == #up ifTrue: [^self mouseUp: anEvent].
	type == #wheel ifTrue: [^self wheel: anEvent].
	type == #enter ifTrue: [^self mouseEnter: anEvent].
	type == #leave ifTrue: [^self mouseLeave: anEvent].
	^false
!
handleKey: anEvent
	anEvent type == #down ifFalse: [^false].
	^self keyDown: anEvent
!
handleText: anEvent
	^self textInput: anEvent
!
handleTextEditing: anEvent
	^self textEditing: anEvent
!
mouseDown: anEvent
	^false
!
rightMouseDown: anEvent
	"Answer false to let the Window open contextMenuAt:."
	^false
!
mouseMove: anEvent
	^false
!
mouseUp: anEvent
	^false
!
wheel: anEvent
	^false
!
mouseEnter: anEvent
	^false
!
mouseLeave: anEvent
	^false
!
keyDown: event
 ^self contextualKeyDown: event
!
textInput: anEvent
	^false
!
textEditing: anEvent
	"An input method's composition (TextEditingEvent)."
	^false
!
cursorAt: aPoint
	^#arrow
!
contextualKeyDown: event
 | context key |
 event modifiers commandKey ifFalse: [^false].
 (self respondsTo: #agentContext) ifFalse: [^false].
 "The actions are the tools' (ActionContext): an application's runtime image has none."
 (Smalltalk includesKey: #ActionContext) ifFalse: [^false].
 key := event key.
 key isCharacter ifFalse: [^false].
 key := key asLowercase.
 (#($c $x $i $b $j) includes: key) ifFalse: [^false].
 context := (Smalltalk at: #ActionContext) for: self.
 ((key = $c) or: [key = $x]) ifTrue: [
 self clipboardText: context value printString.
 (Smalltalk at: #ActionContext) copied: context.
 ^true].
 key = $j ifTrue: [context agent. ^true].
 key = $i ifTrue: [context inspect. ^true].
 key = $b ifTrue: [context browse. ^true].
 ^false
! !

!Widget methodsFor: 'context menu'!
menuBlock: aBlock
	"aBlock (optionally receiving me and the local point) answers a Menu or nil."
	menuBlock := aBlock
!
contextMenuAt: aPoint
	menuBlock isNil ifTrue: [^nil].
	^menuBlock cull: self cull: aPoint
!
tooltipAt: aPoint
	^tooltip
!
openMenu: aMenu at: aLocalPoint
	"Show aMenu (a Menu model) as a popup at aLocalPoint; answer the MenuView."
	| view |
	view := aMenu asMenuView.
	self worldDo: [:world | world openMenu: view at: (self localToScreen: aLocalPoint)].
	^view
! !

!Widget methodsFor: 'focus'!
wantsKeyboardFocus
	^false
!
focus
	| w |
	w := self window.
	w isNil ifTrue: [^self].
	w keyboardFocus == self ifFalse: [w keyboardFocus: self]
!
hasKeyboardFocus
	"Whether I am my window's keyboard focus (whether or not the window is active)."
	| w |
	w := self window.
	^w notNil and: [w keyboardFocus == self]
!
isFocused
	"Whether keys come to me: my window's focus, and the window is the active one."
	| w |
	w := self window.
	^w notNil and: [w keyboardFocus == self and: [w isFocused]]
!
focusGained
	self invalidate
!
focusLost
	self invalidate
! !

!Widget methodsFor: 'window services'!
worldDo: aBlock
	"Evaluate aBlock with my window's World, if there is one."
	| w world |
	w := self window.
	world := w isNil ifTrue: [nil] ifFalse: [w world].
	world isNil ifFalse: [^aBlock value: world].
	^nil
!
after: milliseconds do: aBlock
	"Run aBlock in my window's Process after milliseconds; answer a timer (cancel) or nil without a window."
	| w |
	w := self window.
	w isNil ifTrue: [^nil].
	^w after: milliseconds do: aBlock
!
afterAnimationTime: milliseconds do: aBlock
	"Like after:do:, milliseconds of the animation clock (Animation timeScale times longer in slow motion)."
	^self after: (Animation realMilliseconds: milliseconds) do: aBlock
!
animate: anAnimation
	"Run anAnimation on the compositor clock (or finish it at once without a window)."
	| w |
	w := self window.
	w isNil ifTrue: [anAnimation finish. ^anAnimation].
	w animate: anAnimation.
	^anAnimation
!
tweenFrom: start to: stop duration: ms do: aBlock
	"Animate a number (or point/rectangle) from start to stop, easing out; answer the Animation."
	^self animate: (Animation from: start to: stop duration: ms easing: #easeOutCubic do: aBlock)
!
inWindowDo: aBlock
	"Run aBlock in my window's Process (now, if that is the active process or there is no window)."
	| w |
	w := self window.
	(w isNil or: [(w respondsTo: #process) not or: [w process isNil or: [w process == Processor activeProcess]]])
		ifTrue: [^aBlock value].
	^w do: aBlock
!
inWindowWait: aBlock
	"Run aBlock in my window's Process and answer its value, waiting for it (remote control runs in another process)."
	| w done result |
	w := self window.
	(w isNil or: [(w respondsTo: #process) not or: [w process isNil or: [w process == Processor activeProcess]]])
		ifTrue: [^aBlock value].
	done := Semaphore new.
	w do: [[result := aBlock value] ensure: [done signal]].
	(done waitTimeoutMSecs: 2000) ifTrue: [^nil].
	^result
!
clipboardText
	| w |
	w := self window.
	w isNil ifFalse: [^w clipboard ifNil: ['']].
	^FallbackClipboard ifNil: ['']
!
clipboardData: mime
	| w |
	w := self window.
	^w isNil ifFalse: [w clipboardData: mime]
!
toast: aString
	self worldDo: [:world | world toast: aString]
! !

!Widget methodsFor: 'remote control'!
remoteRole
	^#widget
!
remoteLabel
	^nil
!
remoteState
	| s |
	s := OrderedCollection new.
	self isFocused ifTrue: [s add: #focused].
	self isEnabled ifFalse: [s add: #disabled].
	^s asArray
!
remoteName
	^name
!
remoteChildren
	"My visible children, with transparent ones (layout containers) replaced by their remote children."
	^View remoteFlatten: self visibleChildren
!
remoteIsTransparent
	^false
!
remoteBounds
	^self screenBounds
!
remoteQuote: aString
	"aString in double quotes (JSON style), cut to 60 characters, for state words like sel=..."
	| s |
	s := aString asString.
	s size > 60 ifTrue: [s := (s first: (s graphemeClusterStartBefore: 60)), (String with: (Character value: 8230))].
	^String new: s size + 2 streamContents: [:out |
		out nextPut: $".
		s do: [:c |
			(c = $" or: [c = $\]) ifTrue: [out nextPut: $\].
			c = Character lf
				ifTrue: [out nextPutAll: '\n']
				ifFalse: [c = Character tab ifTrue: [out nextPutAll: '\t'] ifFalse: [out nextPut: c]]].
		out nextPut: $"]
! !

!Widget methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	name isNil ifFalse: [aStream nextPut: $(; nextPutAll: name; nextPut: $)]
! !

!Widget methodsFor: 'clipboard'!
clipboardText: aString
 | w |
 (Smalltalk at: #ActionContext ifAbsent: [nil]) ifNotNil: [:actions | actions copied: nil].
 FallbackClipboard := aString.
 w := self window.
 w isNil ifFalse: [w clipboard: aString]
! !
