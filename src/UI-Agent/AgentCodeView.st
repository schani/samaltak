AgentItemView subclass: #AgentCodeView
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Agent'!

AgentCodeView comment: 'I show a code-mode cell (the mock''s .call): a frame with a CODE-MODE header, the source highlighted as the editors do (TextHighlighter, Theme syntax styles), and below a dotted rule the result: its object id boxed (oN) and its printString, or the error of a failed cell, or ''running…''. Lines too long for my width are cut.'!

!AgentCodeView methodsFor: 'accessing'!
source
	"The cell's source as I draw it: tabs as spaces, no trailing newlines."
	| s |
	s := (item text copyReplaceAll: (String with: Character tab) with: '    ') copyWithout: Character cr.
	^s trimRight
!
sourceLines
	^self source isEmpty ifTrue: [#('')] ifFalse: [self source lines]
!
resultLines
	| text lines |
	item result isNil ifTrue: [^#('running…')].
	text := (item failed or: [item objectId isNil])
		ifTrue: [item result]
		ifFalse: [item result allButFirst: item objectId size + 1].
	lines := text lines.
	lines isEmpty ifTrue: [^#('')].
	^lines size > 12 ifTrue: [(lines first: 12) copyWith: '…'] ifFalse: [lines]
!
headerHeight
	^21
!
codeFont
	^self theme font: #code
!
resultFont
	^self theme font: #codeSmall
! !

!AgentCodeView methodsFor: 'layout'!
computeHeightFor: aWidth
	^self headerHeight + (self sourceLines size * self codeFont lineHeight) + 8 + (self resultLines size * self resultFont lineHeight) + 5 + 8
!
gutterWidth
	^0
!
margin
	^0
! !

!AgentCodeView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| box x y |
	box := self gutterWidth @ 0 corner: (self width - self margin) @ (self height - 8).
	aCanvas fillRect: box color: self theme paper.
	aCanvas strokeRect: box color: self theme ink width: 1.
	x := box left + 8.
	aCanvas drawString: 'Code-mode' at: x @ 4 font: (self theme font: #header) color: self theme ink.
	aCanvas fillRect: (box left @ (self headerHeight - 1) extent: box width @ 1) color: self theme rule.
	aCanvas clip: (box insetBy: 1) during: [
		y := self drawSourceAt: x @ (self headerHeight + 3) on: aCanvas.
		y := y + 3.
		x := box left + 1.
		[x < (box right - 1)] whileTrue: [
			aCanvas fillRect: (x @ y extent: 1 @ 1) color: self theme ink.
			x := x + 3].
		self drawResultAt: (box left + 8) @ (y + 3) on: aCanvas]
!
drawSourceAt: aPoint on: aCanvas
	"Draw the highlighted source; answer the y below it."
	| source highlighter start y advance |
	source := self source.
	highlighter := TextHighlighter on: (TextBuffer string: source).
	highlighter ensureTokens.
	advance := self codeFont widthOf: 'm'.
	start := 0.
	y := aPoint y.
	self sourceLines do: [:line |
		highlighter isActive ifTrue: [
			highlighter styledRunsFrom: start to: start + line size color: nil do: [:a :b :font :color |
				aCanvas drawString: source from: a + 1 to: b at: (aPoint x + (a - start * advance)) @ y font: font color: color]].
		start := start + line size + 1.
		y := y + self codeFont lineHeight].
	^y
!
drawResultAt: aPoint on: aCanvas
	| font x y |
	font := self resultFont.
	x := aPoint x.
	y := aPoint y.
	aCanvas drawString: '→' at: x @ y font: font color: self theme muted.
	x := x + (font widthOf: '→ ').
	(item failed not and: [item objectId notNil]) ifTrue: [
		x := x + (self drawOref: item objectId at: x @ y on: aCanvas) + 6].
	self resultLines do: [:line |
		aCanvas drawString: line at: x @ y font: (item result isNil ifTrue: [self theme font: #smallItalic] ifFalse: [font]) color: self theme ink.
		y := y + font lineHeight]
! !
