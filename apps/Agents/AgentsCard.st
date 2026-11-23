OmarchyCard subclass: #AgentsCard
	instanceVariableNames: 'usages now logos'
	classVariableNames: ''
	package: 'Agents'!

AgentsCard comment: 'I show the rate limits of every agent subscription as the Omarchy desktop card does: for each agent its logo, name and plan (and "stale" when its limits are old), then a row per window: its title, a meter filled to how much of it is used with a tick at how far through its span it is (a fill past the tick is ahead of pace; urgent from 90 %), the percentage and the time until it resets; prepaid accounts a Balance row. The logos are the bar''s own SVGs (Omarchy path, shell/plugins/agents/assets), painted by SVGImage, the -light ones on light themes.'!

!AgentsCard methodsFor: 'initialization'!
initialize
	super initialize.
	usages := #().
	now := 0.
	logos := Dictionary new
! !

!AgentsCard methodsFor: 'accessing'!
usages: anArray at: nowSeconds
	"Show anArray of AgentUsages as they stand at nowSeconds (UTC)."
	usages := anArray.
	now := nowSeconds.
	self invalidate
!
usages
	^usages
!
assetsDirectory
	^Omarchy path, '/shell/plugins/agents/assets'
! !

!AgentsCard methodsFor: 'fonts'!
bodyFont
	^self fontOf: #body
!
nameFont
	"Style.font.title, DemiBold (the typeface's bold where it has no demibold)."
	^self fontOfSize: (self pixelsOf: #title) bold: true
!
captionFont
	^self fontOf: #caption
! !

!AgentsCard methodsFor: 'layout'!
titleWidth
	^self space: 84
!
percentWidth
	^self space: 40
!
resetWidth
	^self space: 64
!
logoSize
	^self space: 16
!
meterHeight
	^(self space: 6) max: 4
!
rowHeight
	^self bodyFont lineHeight max: self meterHeight
!
headerHeight: aUsage
	| h |
	h := self nameFont lineHeight max: self bodyFont lineHeight.
	(self logoFor: aUsage) isNil ifFalse: [h := h max: self logoSize].
	aUsage isStale ifTrue: [h := h max: self captionFont lineHeight].
	^h
!
heightOf: aUsage
	| rows |
	rows := (aUsage windowsAt: now) size + (aUsage hasBalance ifTrue: [1] ifFalse: [0]).
	^(self headerHeight: aUsage) + (rows * ((self space: 8) + self rowHeight))
!
contentHeight
	usages isEmpty ifTrue: [^self bodyFont lineHeight].
	^(usages inject: 0 into: [:sum :each | sum + (self heightOf: each)]) + ((usages size - 1) * (self space: 16))
! !

!AgentsCard methodsFor: 'drawing'!
drawContentOn: aCanvas width: w
	| y |
	usages isEmpty ifTrue: [
		^aCanvas drawString: 'No agent usage yet' at: 0 @ 0 font: self bodyFont color: self muted].
	y := 0.
	usages do: [:usage |
		self drawUsage: usage on: aCanvas at: y width: w.
		y := y + (self heightOf: usage) + (self space: 16)]
!
drawUsage: aUsage on: c at: top width: w
	| y |
	self drawHeaderOf: aUsage on: c at: top width: w.
	y := top + (self headerHeight: aUsage).
	(aUsage windowsAt: now) do: [:win |
		y := y + (self space: 8).
		self drawRowOn: c at: y width: w title: (win at: 1)
			value: (win at: 2) marker: (win at: 4) alarming: (win at: 2) >= 0.9
			percent: (AgentUsage percent: (win at: 2)) reset: (AgentUsage duration: (win at: 3)).
		y := y + self rowHeight].
	aUsage hasBalance ifTrue: [
		| b |
		b := aUsage balance.
		y := y + (self space: 8).
		self drawBalance: b on: c at: y width: w]
!
drawHeaderOf: aUsage on: c at: top width: w
	"Logo, name (title, bold), plan (muted, filling the row), stale (caption, muted) at the right; all vertically centered."
	| h x logo name nameFont body stale staleW tierW |
	h := self headerHeight: aUsage.
	x := 0.
	logo := self logoFor: aUsage.
	logo isNil ifFalse: [
		c image: logo in: (0 @ (top + ((h - self logoSize) / 2)) extent: self logoSize @ self logoSize).
		x := self logoSize + (self space: 8)].
	nameFont := self nameFont.
	body := self bodyFont.
	name := aUsage name.
	c drawString: name at: x @ (top + ((h - nameFont lineHeight) / 2)) font: nameFont color: self foreground.
	x := x + (self widthOf: name in: nameFont) + (self space: 8).
	staleW := 0.
	aUsage isStale ifTrue: [
		stale := 'stale'.
		staleW := self widthOf: stale in: self captionFont.
		c drawString: stale at: (w - staleW) @ (top + ((h - self captionFont lineHeight) / 2)) font: self captionFont color: self muted.
		staleW := staleW + (self space: 8)].
	tierW := w - x - staleW.
	tierW > 0 ifTrue: [
		c drawString: (self truncate: aUsage tierLabel to: tierW font: body)
			at: x @ (top + ((h - body lineHeight) / 2)) font: body color: self muted]
!
drawRowOn: c at: top width: w title: title value: value marker: marker alarming: alarming percent: percentText reset: resetText
	"Title (muted) | meter | percentage, right-aligned | time to reset (muted), right-aligned."
	| body h ty gap meterX meterW x |
	body := self bodyFont.
	h := self rowHeight.
	ty := top + ((h - body lineHeight) / 2).
	gap := self space: 10.
	c drawString: (self truncate: title to: self titleWidth font: body) at: 0 @ ty font: body color: self muted.
	meterX := self titleWidth + gap.
	meterW := w - self titleWidth - self percentWidth - self resetWidth - (3 * gap).
	self drawMeterOn: c in: (meterX @ (top + ((h - self meterHeight) / 2)) extent: meterW @ self meterHeight)
		value: value marker: marker alarming: alarming.
	x := meterX + meterW + gap.
	c drawString: percentText at: (x + self percentWidth - (self widthOf: percentText in: body)) @ ty font: body color: self foreground.
	x := x + self percentWidth + gap.
	c drawString: resetText at: (x + self resetWidth - (self widthOf: resetText in: body)) @ ty font: body color: self muted
!
drawBalance: b on: c at: top width: w
	"Balance | meter of what is left of what was funded | $12.50 left, right-aligned across the percentage and reset columns."
	| body h ty gap remaining funded meterX labelW meterW text fraction |
	body := self bodyFont.
	h := self rowHeight.
	ty := top + ((h - body lineHeight) / 2).
	gap := self space: 10.
	remaining := b at: 1.
	funded := b at: 2.
	fraction := funded > 0 ifTrue: [remaining / funded] ifFalse: [0].
	c drawString: 'Balance' at: 0 @ ty font: body color: self muted.
	meterX := self titleWidth + gap.
	labelW := self percentWidth + self resetWidth + gap.
	meterW := w - self titleWidth - labelW - (2 * gap).
	self drawMeterOn: c in: (meterX @ (top + ((h - self meterHeight) / 2)) extent: meterW @ self meterHeight)
		value: fraction marker: -1 alarming: (funded > 0 and: [fraction <= 0.1]).
	text := (AgentUsage money: remaining currency: (b at: 3)), ' left'.
	c drawString: text at: (w - (self widthOf: text in: body)) @ ty font: body color: self foreground
! !

!AgentsCard methodsFor: 'logos'!
logoFor: aUsage
	"The agent's logo as a Form of the logo size in device pixels, the -light one on a light surface if there is one; nil if there is none."
	| light pixels key |
	light := self isLight.
	pixels := (self logoSize * Font deviceScale) rounded.
	key := Array with: aUsage id with: light with: pixels.
	^logos at: key ifAbsent: [
		| svg |
		svg := nil.
		light ifTrue: [svg := self svgNamed: aUsage id, '-light'].
		svg isNil ifTrue: [svg := self svgNamed: aUsage id].
		logos at: key put: (svg isNil ifTrue: [nil] ifFalse: [svg formWidth: pixels height: pixels color: self foreground])]
!
svgNamed: aName
	| path |
	(aName allSatisfy: [:c | c isLetter or: [c isDigit or: ['-_' includes: c]]]) ifFalse: [^nil].
	path := self assetsDirectory, '/', aName, '.svg'.
	(File exists: path) ifFalse: [^nil].
	^[SVGImage fromFile: path] on: Error do: [:e | e return: nil]
! !

!AgentsCard methodsFor: 'remote control'!
remoteLabel
	^usages isEmpty ifTrue: ['No agent usage yet'] ifFalse: [(usages collect: [:u | u name]) inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]]
!
remoteState
	^usages collect: [:u |
		u id, '=', ((u windowsAt: now) collect: [:win | (win at: 1), ' ', (AgentUsage percent: (win at: 2))]) printString]
! !
