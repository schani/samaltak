OmarchyCard subclass: #WodifyCard
	instanceVariableNames: 'days ok error loading today settings laidOut layoutKey version'
	classVariableNames: ''
	package: 'Wodify'!

WodifyCard comment: 'I show the day''s and the next day''s workouts as the Omarchy desktop card does: for each day (a hairline between them) TODAY or TOMORROW and the date, the workout''s title, a note when there is no workout, its comments, and its parts: section headers small and dim, a part''s name bold, its text wrapped, its comment muted and italic. Past days are left out, even from the offline cache. Taller than maxHeight I scroll.

The card''s settings (desktop-cards.json, card "wodify"): days (1 or 2), comments (true), notes (false), hide (parts, sections or level blocks to leave out: case, spaces and dashes ignored, a fragment is enough; a hidden section takes the parts under it along), level (keep only that level of workouts written in "- RX -" … blocks).'!

!WodifyCard methodsFor: 'initialization'!
initialize
	super initialize.
	days := #().
	ok := false.
	error := ''.
	loading := true.
	today := ''.
	settings := Dictionary new.
	version := 0
! !

!WodifyCard methodsFor: 'accessing'!
days: anArray ok: okBoolean error: aString loading: loadingBoolean today: anISODate
	"Show what the service has (in my window's Process)."
	days := anArray.
	ok := okBoolean.
	error := aString ifNil: [''].
	loading := loadingBoolean.
	today := anISODate.
	self changedContent
!
settings: aDictionary
	settings := (aDictionary isKindOf: Dictionary) ifTrue: [aDictionary] ifFalse: [Dictionary new].
	self changedContent
!
changedContent
	version := version + 1.
	laidOut := nil.
	self clampScroll.
	self invalidate
! !

!WodifyCard methodsFor: 'settings'!
dayCount
	| n |
	n := settings at: 'days' ifAbsent: [2].
	n := n isNumber ifTrue: [n truncated] ifFalse: [(n isString ifTrue: [n asInteger] ifFalse: [nil]) ifNil: [2]].
	^(n max: 1) min: 2
!
showComments
	^(settings at: 'comments' ifAbsent: [true]) ~~ false
!
showNotes
	^(settings at: 'notes' ifAbsent: [false]) == true
!
hidden
	| hide |
	hide := settings at: 'hide' ifAbsent: [#()].
	(hide isKindOf: Array) ifFalse: [^#()].
	^(hide collect: [:h | WodifyText squash: h]) reject: [:h | h isEmpty]
!
level
	| l |
	l := settings at: 'level' ifAbsent: [''].
	^l isString ifTrue: [l trimBoth asUppercase] ifFalse: ['']
!
shownDays
	"The days from today on, as many as the settings want."
	| shown |
	shown := days select: [:d | d date >= today].
	^shown copyFrom: 1 to: (shown size min: self dayCount)
!
visibleItems: items
	"items less the parts settings hide; a hidden section header takes the parts under it along."
	| hidden inHidden |
	hidden := self hidden.
	inHidden := false.
	^items select: [:it |
		(it at: 'section') == true ifTrue: [inHidden := WodifyText isHidden: (it at: 'name') by: hidden].
		(inHidden or: [WodifyText isHidden: (it at: 'name') by: hidden]) not]
!
levelText: aString
	^WodifyText level: self level of: aString hiding: self hidden
! !

!WodifyCard methodsFor: 'labels'!
dayLabel: anISODate
	"TODAY, TOMORROW or the weekday."
	| d t diff |
	d := self dateOf: anISODate.
	t := self dateOf: today.
	(d isNil or: [t isNil]) ifTrue: [^''].
	diff := d subtractDate: t.
	diff = 0 ifTrue: [^'TODAY'].
	diff = 1 ifTrue: [^'TOMORROW'].
	^d dayOfWeekName asUppercase
!
dateLabel: anISODate
	"ddd d MMM: Sun 22 Nov."
	| d |
	d := self dateOf: anISODate.
	d isNil ifTrue: [^''].
	^(d dayOfWeekName copyFrom: 1 to: 3), ' ', d day printString, ' ', (d monthName copyFrom: 1 to: 3)
!
dateOf: anISODate
	(anISODate isString and: [anISODate size = 10]) ifFalse: [^nil].
	^[Date year: (anISODate copyFrom: 1 to: 4) asInteger month: (anISODate copyFrom: 6 to: 7) asInteger day: (anISODate copyFrom: 9 to: 10) asInteger]
		on: Error do: [:e | e return: nil]
!
statusText
	loading ifTrue: [^'Fetching workouts…'].
	^error isEmpty ifTrue: ['No workouts'] ifFalse: [error]
! !

!WodifyCard methodsFor: 'fonts'!
bodyFont
	^self fontOf: #body
!
boldFont
	^self fontOfSize: (self pixelsOf: #body) bold: true
!
italicFont
	^self fontOfSize: (self pixelsOf: #body) style: #italic tracking: 0
!
captionFont
	^self fontOf: #caption
!
trackedCaptionFont
	^self fontOfSize: (self pixelsOf: #caption) bold: false tracking: 1
! !

!WodifyCard methodsFor: 'layout'!
layoutFor: w
	"What I show at width w, laid out: {y. kind. ...} for each text (#text, lines, font, color, line step; #pair, the day row) and hairline (#rule); cached until my content, the width or the fonts change."
	| key |
	key := Array with: version with: w with: self bodyFont with: Font deviceScale.
	(laidOut notNil and: [layoutKey = key]) ifTrue: [^laidOut].
	layoutKey := key.
	^laidOut := self computeLayout: w
!
computeLayout: w
	| out y shown first |
	out := OrderedCollection new.
	y := 0.
	first := true.
	"the column's children, space: 14 apart"
	shown := self shownDays.
	shown isEmpty ifTrue: [
		y := self add: (self wrapped: self statusText font: self bodyFont width: w) font: self bodyFont color: self muted step: 1 at: y to: out.
		first := false].
	shown doWithIndex: [:day :index |
		first ifFalse: [y := y + (self space: 14)].
		first := false.
		y := self layDay: day index: index at: y width: w to: out].
	(shown notEmpty and: [ok not and: [error notEmpty]]) ifTrue: [
		y := y + (self space: 14).
		y := self add: (self wrapped: 'Offline: ', error font: self captionFont width: w) font: self captionFont color: self muted step: 1 at: y to: out].
	out addFirst: y.
	^out asArray
!
layDay: day index: index at: top width: w to: out
	"A day's column, its children space: 8 apart; answer the y below it."
	| y gap first |
	y := top.
	gap := self space: 8.
	first := true.
	index > 1 ifTrue: [
		out add: (Array with: y with: #rule with: (self space: 1)).
		y := y + (self space: 1) + (self space: 6).
		first := false].
	first ifFalse: [y := y + gap].
	first := false.
	out add: (Array with: y with: #pair with: (self dayLabel: day date) with: (self dateLabel: day date)).
	y := y + (self trackedCaptionFont lineHeight max: self captionFont lineHeight).
	day title notEmpty ifTrue: [
		y := self add: (self wrapped: day title font: self bodyFont width: w) font: self bodyFont color: self muted step: 1 at: y + gap to: out].
	day note notEmpty ifTrue: [
		y := self add: (Array with: (self truncate: day note to: w font: self italicFont)) font: self italicFont color: self muted step: 1 at: y + gap to: out].
	(self showComments and: [day comments notEmpty]) ifTrue: [
		y := self add: (self wrapped: day comments font: self bodyFont width: w) font: self bodyFont color: self muted step: 1 at: y + gap to: out].
	(self showNotes and: [day notes notEmpty]) ifTrue: [
		y := self add: (self wrapped: day notes font: self bodyFont width: w) font: self bodyFont color: self muted step: 1 at: y + gap to: out].
	(self visibleItems: day items) do: [:item |
		y := y + gap.
		(item at: 'section') == true ifTrue: [y := y + (self space: 4)].
		y := self layItem: item at: y width: w to: out].
	^y
!
layItem: item at: top width: w to: out
	"A part's column, its children space: 2 apart."
	| y gap any section name text comment |
	y := top.
	gap := self space: 2.
	any := false.
	section := (item at: 'section') == true.
	name := item at: 'name'.
	name notEmpty ifTrue: [
		section
			ifTrue: [y := self add: (self wrapped: name asUppercase font: self trackedCaptionFont width: w) font: self trackedCaptionFont color: self dim step: 1 at: y to: out]
			ifFalse: [y := self add: (self wrapped: name font: self boldFont width: w) font: self boldFont color: self foreground step: 1 at: y to: out].
		any := true].
	text := item at: 'text'.
	text notEmpty ifTrue: [
		any ifTrue: [y := y + gap].
		y := self add: (self wrapped: (self levelText: text) font: self bodyFont width: w) font: self bodyFont color: self foreground step: 1.1 at: y to: out.
		any := true].
	comment := item at: 'comment'.
	(self showComments and: [comment notEmpty]) ifTrue: [
		any ifTrue: [y := y + gap].
		y := self add: (self wrapped: (self levelText: comment) font: self italicFont width: w) font: self italicFont color: self muted step: 1 at: y to: out].
	^y
!
wrapped: aString font: aFont width: w
	^self lines: aString width: w font: aFont
!
add: lines font: aFont color: aColor step: factor at: y to: out
	"A text of lines, each factor line heights below the last; answer the y below it."
	| step |
	step := aFont lineHeight * factor.
	out add: (Array with: y with: #text with: lines with: aFont with: aColor with: step).
	^y + (lines size * step)
!
contentHeight
	^(self layoutFor: self contentWidth) first
! !

!WodifyCard methodsFor: 'drawing'!
drawContentOn: aCanvas width: w
	(self layoutFor: w) allButFirst do: [:run |
		| y kind |
		y := run at: 1.
		kind := run at: 2.
		kind == #text ifTrue: [
			| lines font color step |
			lines := run at: 3. font := run at: 4. color := run at: 5. step := run at: 6.
			lines doWithIndex: [:line :i |
				line isEmpty ifFalse: [aCanvas drawString: line at: 0 @ (y + ((i - 1) * step)) font: font color: color]]].
		kind == #rule ifTrue: [
			aCanvas fillRect: (0 @ y extent: w @ (run at: 3)) color: (self foreground alpha: 0.12)].
		kind == #pair ifTrue: [
			| left |
			aCanvas drawString: (run at: 3) at: 0 @ y font: self trackedCaptionFont color: self dim.
			left := (self widthOf: (run at: 3) in: self trackedCaptionFont) + (self space: 8).
			aCanvas drawString: (run at: 4) at: left @ y font: self captionFont color: self muted]]
! !

!WodifyCard methodsFor: 'remote control'!
remoteLabel
	^self shownDays isEmpty ifTrue: [self statusText] ifFalse: [(self shownDays collect: [:d | self dayLabel: d date]) printString]
!
remoteState
	^self shownDays collect: [:d | d date, '=', d title]
! !
