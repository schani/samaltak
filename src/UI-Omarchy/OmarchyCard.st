Widget subclass: #OmarchyCard
	instanceVariableNames: 'onActivate onRefresh scrollOffset maxHeight pills'
	classVariableNames: ''
	package: 'UI-Omarchy'!

OmarchyCard comment: 'I am a card of the Omarchy desktop (the desktop-cards plugin''s CardFrame) as a widget: the popup surface, the card''s padding, its column''s width, and the shell''s typeface, type scale, spacing and colors (OmarchyTheme; under another theme its paper, ink and code face). A click runs onActivate, a middle click onRefresh. Subclasses answer contentHeight and draw drawContentOn:width: in content coordinates.

Content taller than maxHeight (points, the card''s padding included; nil: no limit) scrolls with the wheel, with a thin indicator at the right, as CardFrame does.

Helpers for subclasses: fonts (fontOfSize:bold:, fontOfSize:style:tracking:, pixelsOf:), space: (Style.space), colors (foreground, muted: Label''s 0.6 opacity, dim: Qt.darker 1.4, accent, urgent), text as Qt''s Text lays it out (widthOf:in:, truncate:to:font:, lines:width:font:, a paragraph wrapped at white space), and a Meter (drawMeterOn:in:value:marker:alarming:, rounded pills painted by VectorPainter).'!

!OmarchyCard methodsFor: 'initialization'!
initialize
	super initialize.
	scrollOffset := 0.
	pills := Dictionary new
! !

!OmarchyCard methodsFor: 'accessing'!
onActivate: aBlock
	"A click."
	onActivate := aBlock
!
onRefresh: aBlock
	"A middle click."
	onRefresh := aBlock
!
maxHeight
	^maxHeight
!
maxHeight: points
	"The most I grow to, padding included (nil: no limit); my content scrolls past it."
	maxHeight := points.
	self clampScroll.
	self invalidate
! !

!OmarchyCard methodsFor: 'theme'!
omarchy
	"The current theme if it is Omarchy's, else nil."
	^(self theme respondsTo: #fontOfSize:style:letterSpacing:) ifTrue: [self theme] ifFalse: [nil]
!
fontOfSize: pixels bold: aBoolean
	^self fontOfSize: pixels style: (aBoolean ifTrue: [#bold] ifFalse: [#regular]) tracking: 0
!
fontOfSize: pixels bold: aBoolean tracking: points
	^self fontOfSize: pixels style: (aBoolean ifTrue: [#bold] ifFalse: [#regular]) tracking: points
!
fontOfSize: pixels style: aSymbol tracking: points
	"The shell's typeface at pixels, #regular, #bold or #italic, points between letters."
	| font |
	self omarchy ifNotNil: [:t | ^t fontOfSize: pixels style: aSymbol letterSpacing: points].
	font := Font faceNamed: (aSymbol == #bold
		ifTrue: ['JetBrainsMono-Bold']
		ifFalse: [aSymbol == #italic ifTrue: ['JetBrainsMono-Italic'] ifFalse: ['JetBrainsMono-Regular']]) size: pixels.
	points = 0 ifFalse: [font letterSpacing: points].
	^font
!
fontOf: aToken
	"The shell's Style.font aToken (#caption, #body, #title ...), regular."
	^self fontOfSize: (self pixelsOf: aToken) bold: false
!
pixelsOf: aToken
	"The shell's type scale (OmarchyTheme), or its defaults at base size 12."
	self omarchy ifNotNil: [:t | ^t pixelsOf: aToken].
	^(12 * (OmarchyTheme tokenFactors at: aToken)) rounded
!
space: points
	self omarchy ifNotNil: [:t | ^t space: points].
	^points
!
cardPadding
	"The desktop card's padding (Style.spacing.panelPadding, 18) less its 2-point border, which the window manager's border replaces: Hyprland draws its border outside the window, the card inside its padding."
	^(self omarchy ifNil: [18] ifNotNil: [:t | t metric: #panelPadding]) - (self space: 2)
!
background
	self omarchy ifNotNil: [:t | ^t color: #popupBackground].
	^self theme paper
!
foreground
	self omarchy ifNotNil: [:t | ^t color: #popupText].
	^self theme ink
!
muted
	"A muted Label: the text at 0.6 opacity."
	^self foreground alpha: 0.6
!
dim
	"Qt.darker(text, 1.4), as cards dim their captions."
	^self darker: self foreground by: 1.4
!
dimmer
	^self darker: self foreground by: 1.5
!
accent
	self omarchy ifNotNil: [:t | ^t accent].
	^Color ultramarine
!
urgent
	self omarchy ifNotNil: [:t | ^t urgent].
	^Color r: 0.8 g: 0.2 b: 0.2
!
darker: aColor by: factor
	^Color r: aColor red / factor g: aColor green / factor b: aColor blue / factor a: aColor alpha
!
isLight
	"Whether the card's surface is light (HSL lightness above a half), as cards choose their light icons."
	| c |
	c := self background.
	^((c red max: (c green max: c blue)) + (c red min: (c green min: c blue))) / 2 > 0.5
! !

!OmarchyCard methodsFor: 'layout'!
contentWidth
	"A column of desktop-cards on a 1512-point screen less the card's padding: desktop-cards (Layout.js) makes a column floor((1512 - 4 gaps of 10) / 3) = 490 wide."
	^490 - (2 * (self space: 18))
!
contentHeight
	"The height of everything I show, in points."
	^self subclassResponsibility
!
viewHeight
	"The height of my content that shows."
	| h |
	h := self contentHeight.
	maxHeight isNil ifTrue: [^h].
	^h min: ((maxHeight - (2 * self cardPadding)) max: 40)
!
maxScroll
	^(self contentHeight - self viewHeight) max: 0
!
preferredExtent
	^(self contentWidth + (2 * self cardPadding)) ceiling @ (self viewHeight + (2 * self cardPadding)) ceiling
! !

!OmarchyCard methodsFor: 'scrolling'!
scrollOffset
	^scrollOffset
!
scrollOffset: points
	scrollOffset := (points min: self maxScroll) max: 0.
	self invalidate
!
clampScroll
	scrollOffset := (scrollOffset min: self maxScroll) max: 0
!
wheel: anEvent
	self maxScroll > 0 ifFalse: [^false].
	self scrollOffset: scrollOffset - (anEvent delta y * 40).
	^true
! !

!OmarchyCard methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| pad w view |
	aCanvas fillRect: self localBounds color: self background.
	pad := self cardPadding.
	w := self width - (2 * pad).
	self clampScroll.
	view := self viewHeight.
	aCanvas clip: (pad @ pad extent: w @ view) during: [
		aCanvas translateBy: pad @ (pad - scrollOffset) during: [
			self drawContentOn: aCanvas width: w]].
	self maxScroll > 0 ifTrue: [self drawScrollIndicatorOn: aCanvas]
!
drawContentOn: aCanvas width: w
	"Draw my content, its top left at 0 @ 0, w points wide."
	^self subclassResponsibility
!
drawScrollIndicatorOn: aCanvas
	"CardFrame's: a thin bar in the padding at the right, as long as the view is of the content."
	| pad view total barH y x |
	pad := self cardPadding.
	view := self viewHeight.
	total := self contentHeight.
	barH := (view * view / total) max: 20.
	y := pad + ((view - barH) * scrollOffset / self maxScroll).
	x := self width - (pad / 2) - (self space: 1).
	self drawPillOn: aCanvas in: (x @ y extent: (self space: 2) @ barH) color: (self foreground alpha: 0.3)
!
drawMeterOn: aCanvas in: aRectangle value: aFraction marker: markerFraction alarming: aBoolean
	"The desktop cards' Meter: a rounded track (the text at 0.12) filled to aFraction (accent, urgent when alarming) and, unless markerFraction is negative, a tick at markerFraction (the text at 0.7)."
	| v fillW tickW tickH x |
	self drawPillOn: aCanvas in: aRectangle color: (self foreground alpha: 0.12).
	v := (aFraction max: 0) min: 1.
	aFraction > 0 ifTrue: [
		fillW := aRectangle height max: aRectangle width * v.
		self drawPillOn: aCanvas in: (aRectangle origin extent: fillW @ aRectangle height)
			color: (aBoolean ifTrue: [self urgent] ifFalse: [self accent])].
	markerFraction >= 0 ifTrue: [
		tickW := (self space: 2) max: 2.
		tickH := aRectangle height + (self space: 6).
		x := (aRectangle width * ((markerFraction max: 0) min: 1) - (tickW / 2)) rounded.
		self drawPillOn: aCanvas
			in: ((aRectangle left + x) @ (aRectangle center y - (tickH / 2)) extent: tickW @ tickH)
			color: (self foreground alpha: 0.7)]
!
drawPillOn: aCanvas in: aRectangle color: aColor
	"A rectangle with fully rounded ends (radius half its smaller side), antialiased."
	| s w h form key |
	s := aCanvas scale.
	w := (aRectangle width * s) rounded max: 1.
	h := (aRectangle height * s) rounded max: 1.
	key := Array with: w with: h with: aColor.
	form := pills at: key ifAbsent: [
		| f r |
		pills size > 64 ifTrue: [pills := Dictionary new].
		f := Form width: w height: h.
		r := (w min: h) / 2.0.
		(VectorPainter on: f)
			fill: (VectorPath rectX: 0 y: 0 width: w height: h rx: r ry: r) color: aColor rule: #nonzero.
		pills at: key put: f].
	aCanvas image: form in: (aRectangle origin extent: (w / s) @ (h / s))
! !

!OmarchyCard methodsFor: 'text'!
widthOf: aString in: aFont
	"The width a Qt Text gives aString: its natural width (ink past the last advance included), in whole points."
	^(aFont naturalWidthOf: aString) ceiling
!
truncate: aString to: width font: aFont
	^self class truncate: aString to: width font: aFont
!
lines: aString width: width font: aFont
	"aString as a wrapped Qt Text shows it: its lines, each paragraph broken after white space (a word longer than width where it no longer fits)."
	^self class lines: aString width: width font: aFont
!
drawLines: lines on: aCanvas at: aPoint font: aFont color: aColor lineHeight: points
	"Draw lines top to bottom from aPoint, points apart; answer the height they took."
	| y |
	y := aPoint y.
	lines do: [:each |
		each isEmpty ifFalse: [aCanvas drawString: each at: aPoint x @ y font: aFont color: aColor].
		y := y + points].
	^y - aPoint y
! !

!OmarchyCard methodsFor: 'events'!
mouseDown: anEvent
	anEvent button = 1 ifTrue: [onActivate isNil ifFalse: [onActivate value]. ^true].
	anEvent button = 3 ifTrue: [onRefresh isNil ifFalse: [onRefresh value]. ^true].
	^false
!
cursorAt: aPoint
	^#hand
! !

!OmarchyCard methodsFor: 'remote control'!
remoteRole
	^#card
! !

!OmarchyCard class methodsFor: 'text'!
truncate: aString to: width font: aFont
	"aString, cut with an ellipsis to fit width points."
	| s |
	(aFont naturalWidthOf: aString) <= width ifTrue: [^aString].
	s := aString.
	[s notEmpty and: [(aFont naturalWidthOf: s, '…') > width]] whileTrue: [s := s allButLast].
	^s, '…'
!
lines: aString width: width font: aFont
	| out |
	aString isEmpty ifTrue: [^Array with: ''].
	out := OrderedCollection new.
	(aString lines) do: [:paragraph | out addAll: (self wrap: paragraph width: width font: aFont)].
	(aString notEmpty and: [aString last = Character lf]) ifTrue: [out add: ''].
	^out asArray
!
wrap: aParagraph width: width font: aFont
	"One paragraph's lines: greedy, breaking after spaces; a word too long for a line is broken where it no longer fits."
	| out line words |
	out := OrderedCollection new.
	aParagraph isEmpty ifTrue: [^Array with: ''].
	line := ''.
	words := self words: aParagraph.
	words do: [:word |
		| candidate |
		candidate := line, word.
		(line isEmpty not and: [(aFont naturalWidthOf: candidate trimRight) > width])
			ifTrue: [
				out add: line trimRight.
				line := word]
			ifFalse: [line := candidate].
		[(aFont naturalWidthOf: line trimRight) > width and: [line trimRight size > 1]] whileTrue: [
			| cut |
			cut := line size.
			[cut > 1 and: [(aFont naturalWidthOf: (line copyFrom: 1 to: cut - 1)) > width]] whileTrue: [cut := cut - 1].
			cut := (cut - 1) max: 1.
			out add: (line copyFrom: 1 to: cut).
			line := line copyFrom: cut + 1 to: line size]].
	out add: line trimRight.
	^out asArray
!
words: aString
	"aString cut after each run of spaces: the words with the spaces that follow them."
	| out start i |
	out := OrderedCollection new.
	start := 1.
	i := 1.
	[i <= aString size] whileTrue: [
		(aString at: i) isSeparator
			ifTrue: [
				[i <= aString size and: [(aString at: i) isSeparator]] whileTrue: [i := i + 1].
				out add: (aString copyFrom: start to: i - 1).
				start := i]
			ifFalse: [i := i + 1]].
	start <= aString size ifTrue: [out add: (aString copyFrom: start to: aString size)].
	^out
! !
