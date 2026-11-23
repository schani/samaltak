Widget subclass: #TextEditor
	instanceVariableNames: 'buffer textLayout highlighter history caret anchor goalX granularity dragAnchorStart dragAnchorStop dragging scrollBar marks pcGlide pcAnimation readOnly dirty tracksDirty title caretOn blinkTimer onDoIt onPrintIt onInspectIt onBrowseIt onAccept onChange onKey rowDrawings rowsKey preedit'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextEditor comment: 'I am a multi-line text editor for code and text: soft-wrapped lines, a blinking caret, selection (mouse drag, shift-arrows, double-click word or bracket contents, triple-click line), Mac keyboard editing (arrows; option moves by words, command by lines and the whole text; home/end; page up/down; backspace/delete, by words with option; return keeps the indentation; tab, and shift-tab or tab on a multi-line selection to outdent/indent; ⌘A ⌘C ⌘X ⌘V; ⌘Z and ⇧⌘Z undo/redo), vertical scrolling, Smalltalk syntax highlighting through the Compiler''s Scanner (Blue Book colors from the Theme), and marks (TextMark: #result #error #pc #pcReturn #search).

I am a facade over collaborators: a TextBuffer (the text, its lines and words), a TextLayout (rows, x positions, rectangles, the scroll offset), a TextHighlighter (the Scanner tokens and styled runs) and a TextUndoHistory. I keep the selection, the marks, the keyboard and mouse handling and the drawing. Each row replays what it drew last time while what it shows (its text, styled runs, marks, selection, position) is the same, so a keystroke or a caret blink redraws one row.

Positions: caret and selection ends are gap positions (0 = before the first character, text size = after the last); selectionInterval and the mark API use 1-based character Intervals like the rest of Smalltalk.

Characters are grapheme clusters (String>>graphemeClusterEndAfter:): the caret moves over a cluster (é as e + U+0301, 👩‍👩‍👧, 🇩🇪, 👍🏽, Hangul jamo) at once, backspace and delete remove the whole cluster, clicks land between clusters. Typed controls (DEL, C1) are dropped; line ends are normalized to line feeds (pasting CR LF).

Input methods: a TextEditingEvent''s composition (preedit) shows at the caret, underlined, the rest of the row moved right; it is not in the text nor in the undo history. The committed TextEvent replaces it, an empty one removes it, and while it shows, keys without ⌘ belong to the input method. I tell the window where the caret is (textInputArea:cursor:) whenever it moves, so the input method''s candidates appear there.

Tools plug in with blocks; each receives the text of the selection (or of the caret''s line, which gets selected), its Interval and me:
	editor onDoIt: [:text :range | ...]; onPrintIt: [...]; onInspectIt: [...]; onBrowseIt: [...]   "⌘D ⌘P ⌘I ⌘B"
	editor onAccept: [:text | ...]      "⌘S; answer false to stay dirty"
	editor onChange: [:editor | ...]; onKey: [:keyEvent | true if handled]
⌘. is not handled here (it bubbles to the window). Right-click opens a menu with these commands (menuBlock: replaces it).

For print it: (editor insertAfterSelection: '' '', result printString select: true) answers the Interval of the inserted text; add a mark with editor addMark: interval style: #result. pcMark: anInterval moves the debugger''s highlight (gliding).'!

!TextEditor methodsFor: 'initialization'!
initialize
	super initialize.
	buffer := TextBuffer new.
	buffer addListener: self.
	highlighter := TextHighlighter on: buffer.
	textLayout := TextLayout on: buffer in: self.
	history := TextUndoHistory new.
	caret := 0.
	anchor := 0.
	marks := OrderedCollection new.
	readOnly := false.
	dirty := false.
	tracksDirty := false.
	caretOn := true.
	granularity := #character.
	dragging := false.
	scrollBar := ScrollBar new client: self; yourself.
	scrollBar setVisible: false.
	self addChild: scrollBar
! !

!TextEditor methodsFor: 'accessing'!
text
	^buffer string
!
contents
	^buffer string
!
text: aString
	"Replace the whole text: no undo, clean, caret at the start, marks removed."
	preedit := nil.
	buffer string: aString.
	caret := 0.
	anchor := 0.
	textLayout offset: 0.
	goalX := nil.
	history reset.
	dirty := false.
	self layout.
	self invalidate
!
contents: aString
	self text: aString
!
size
	^buffer size
!
title
	^title
!
title: aString
	"The remote-control label (e.g. 'code')."
	title := aString
!
font
	^textLayout font
!
font: aFontOrSymbol
	textLayout font: aFontOrSymbol.
	self invalidate
!
isReadOnly
	^readOnly
!
readOnly: aBoolean
	readOnly := aBoolean.
	self invalidate
!
isDirty
	^dirty
!
dirty: aBoolean
	dirty := aBoolean.
	self invalidate
!
beClean
	self dirty: false
!
tracksDirty: aBoolean
	"Show the dirty bar and report dirty in remote state (set by onAccept:)."
	tracksDirty := aBoolean
!
wrap: aBoolean
	textLayout wrap: aBoolean.
	self invalidate
!
highlighting: aBoolean
	"Syntax highlighting on (default) or off (plain text)."
	highlighter enabled: aBoolean.
	self invalidate
!
scanner: aScanner
	"What highlights my text (TextHighlighter scanner:): another language's scanner, nil for Smalltalk."
	highlighter scanner: aScanner.
	self invalidate
!
methodMode: aBoolean
	"Highlight the first line as a method pattern (bold)."
	highlighter methodMode: aBoolean.
	self invalidate
! !

!TextEditor methodsFor: 'hooks'!
onDoIt: aBlock
	onDoIt := aBlock
!
onPrintIt: aBlock
	onPrintIt := aBlock
!
onInspectIt: aBlock
	onInspectIt := aBlock
!
onBrowseIt: aBlock
	onBrowseIt := aBlock
!
onAccept: aBlock
	onAccept := aBlock.
	tracksDirty := aBlock notNil
!
onChange: aBlock
	onChange := aBlock
!
onKey: aBlock
	"aBlock receives each KeyEvent first and answers true if it handled it."
	onKey := aBlock
! !

!TextEditor methodsFor: 'selection'!
caret
	"The caret's gap position (0 = before the first character)."
	^caret
!
anchor
	^anchor
!
selectionStart
	^caret min: anchor
!
selectionStop
	^caret max: anchor
!
hasSelection
	^caret ~= anchor
!
selectedText
	^buffer copyFrom: self selectionStart + 1 to: self selectionStop
!
selectionInterval
	"The selected characters as a 1-based Interval (empty: caret + 1 to: caret)."
	^self selectionStart + 1 to: self selectionStop
!
selectFrom: start to: stop
	"Select the characters start to stop (1-based; stop = start - 1 puts the caret before start)."
	self setAnchor: start - 1 caret: stop
!
selectAll
	self setAnchor: 0 caret: buffer size
!
caret: aPosition
	"Put the caret at a gap position, without a selection."
	self setAnchor: aPosition caret: aPosition
!
setAnchor: a caret: c
 | direction |
 direction := c - caret.
 a = c
 ifTrue: [
 caret := self snapPosition: c direction: direction.
 anchor := caret]
 ifFalse: [
 anchor := self snapPosition: a direction: (a < c ifTrue: [-1] ifFalse: [1]).
 caret := self snapPosition: c direction: (c < a ifTrue: [-1] ifFalse: [1])].
 goalX := nil.
 self caretMoved
!
caretMoved
	caretOn := true.
	self restartBlink.
	self scrollToCaret.
	self invalidate.
	self updateTextInputArea
!
selectionOrLine
	"Answer the selected text; with no selection, select the caret's line first."
	| line |
	self hasSelection ifFalse: [
		line := self lineIndexOf: caret.
		self setAnchor: (self lineStarts at: line) caret: (self lineEndAt: line)].
	^self selectedText
!
snapPosition: position direction: direction
 | p |
 p := (position max: 0) min: buffer size.
 marks do: [:m |
 (m isAtomic and: [p > m start and: [p < m stop]]) ifTrue: [
 p := direction < 0 ifTrue: [m start] ifFalse: [
 direction > 0 ifTrue: [m stop] ifFalse: [
 p - m start < (m stop - p) ifTrue: [m start] ifFalse: [m stop]]]]].
 ^p
! !

!TextEditor methodsFor: 'lines'!
lineCount
	^buffer lineCount
!
lineAt: anInteger
	^buffer lineAt: anInteger
!
lines
	^buffer lines
!
lineStarts
	"Gap positions where the lines start."
	^buffer lineStarts
!
lineEndAt: lineIndex
	"The gap position at the end of the line (before its line feed)."
	^buffer lineEndAt: lineIndex
!
lineIndexOf: aPosition
	^buffer lineIndexOf: aPosition
!
tabCountOfLine: lineIndex
	^buffer tabCountOfLine: lineIndex
! !

!TextEditor methodsFor: 'buffer changes'!
textReset
	marks := OrderedCollection new
!
textReplacedFrom: start to: stop with: aString
	"Drop the marks the edit touched (and the transient ones); shift the ones after it."
	| delta |
	delta := aString size - (stop - start).
	marks := marks reject: [:m |
		m isTransient or: [m stop > start and: [m start < stop]]].
	marks do: [:m |
		m start >= stop ifTrue: [m start: m start + delta stop: m stop + delta]]
! !

!TextEditor methodsFor: 'geometry'!
lineHeight
	^textLayout lineHeight
!
rowCount
	^textLayout rowCount
!
rowOf: aPosition
	^textLayout rowOf: aPosition
!
rowStart: r
	^textLayout rowStart: r
!
rowEnd: r
	^textLayout rowEnd: r
!
rowTop: r
	"Content y of row r."
	^textLayout rowTop: r
!
contentHeight
	^textLayout contentHeight
!
xOf: aPosition
	^textLayout xOf: aPosition
!
positionAt: aPoint
	"The gap position nearest to a local point."
	^textLayout positionAt: aPoint
!
caretRect
	"The caret's rectangle in my coordinates."
	^textLayout caretRectAt: caret
!
rectsFrom: start to: stop
	"The rectangles (my coordinates) covering the characters start + 1 .. stop, one per row."
	^textLayout rectsFrom: start to: stop
! !

!TextEditor methodsFor: 'scrolling'!
scrollTotal
	^textLayout scrollTotal
!
scrollVisible
	^self height
!
scrollOffset
	^textLayout offset
!
scrollOffset: points
	| new |
	new := textLayout clampedOffset: points.
	new = textLayout offset ifTrue: [^self].
	textLayout offset: new.
	self invalidate.
	self updateTextInputArea
!
scrollToCaret
	| r top bottom padY offset |
	self height <= 0 ifTrue: [^self].
	r := self rowOf: caret.
	top := self rowTop: r.
	bottom := top + self lineHeight.
	padY := textLayout padY.
	offset := textLayout offset.
	top - padY < offset ifTrue: [^self scrollOffset: (textLayout wholeLines: top - padY)].
	bottom + padY > (offset + self height) ifTrue: [self scrollOffset: (textLayout wholeLines: bottom + padY - self height)]
!
visibleRowCount
	^textLayout visibleRowCount
! !

!TextEditor methodsFor: 'layout'!
layout
	| bar |
	bar := self theme metric: #scrollBarWidth.
	textLayout ensureRows; clampOffset.
	scrollBar setVisible: textLayout contentHeight > self height.
	scrollBar bounds: ((self width - bar) @ 0 corner: self width @ self height)
! !

!TextEditor methodsFor: 'editing'!
replaceFrom: start to: stop with: aString
	"Replace the characters between the gap positions start and stop with aString, undoably. Answer the gap position after the inserted text."
	^self replaceFrom: start to: stop with: aString kind: #edit
!
replaceFrom: start to: stop with: aString kind: kind
 | removed new before after first last editKind |
 first := start.
 last := stop.
 marks do: [:m |
 (m isAtomic and: [
 (m stop > first and: [m start < last]) or: [
 first = last and: [first > m start and: [first < m stop]]]]) ifTrue: [
 first := first min: m start.
 last := last max: m stop]].
 removed := buffer copyFrom: first + 1 to: last.
 new := buffer normalize: aString.
 before := Array with: anchor with: caret with: self atomicMarksSnapshot.
 editKind := (marks anySatisfy: [:m | m isAtomic and: [m stop > first and: [m start < last]]])
 ifTrue: [#atomic] ifFalse: [kind].
 buffer replaceFrom: first to: last with: new.
 after := first + new size.
 anchor := after.
 caret := after.
 history record: editKind position: first removed: removed inserted: new before: before
 after: (Array with: anchor with: caret with: self atomicMarksSnapshot).
 self edited.
 ^after
!
edited
	dirty := true.
	goalX := nil.
	self layout.
	self caretMoved.
	onChange isNil ifFalse: [onChange cull: self]
!
insert: aString
	"Replace the selection with aString (as typing does)."
	readOnly ifTrue: [^self].
	self replaceFrom: self selectionStart to: self selectionStop with: aString kind: #typing
!
typeString: aString
	self insert: aString
!
deleteSelection
	self hasSelection ifFalse: [^self].
	self replaceFrom: self selectionStart to: self selectionStop with: '' kind: #delete
!
deleteBackward: unit
	| target |
	readOnly ifTrue: [^self].
	self hasSelection ifTrue: [^self deleteSelection].
	caret = 0 ifTrue: [^self].
	target := unit == #word
		ifTrue: [buffer wordStartBefore: caret]
		ifFalse: [unit == #line ifTrue: [(self rowStart: (self rowOf: caret)) = caret ifTrue: [caret - 1] ifFalse: [self rowStart: (self rowOf: caret)]] ifFalse: [buffer string graphemeClusterStartBefore: caret]].
	self replaceFrom: target to: caret with: '' kind: #backspace
!
deleteForward: unit
	| target |
	readOnly ifTrue: [^self].
	self hasSelection ifTrue: [^self deleteSelection].
	caret = buffer size ifTrue: [^self].
	target := unit == #word
		ifTrue: [buffer wordEndAfter: caret]
		ifFalse: [unit == #line ifTrue: [(self rowEnd: (self rowOf: caret)) = caret ifTrue: [caret + 1] ifFalse: [self rowEnd: (self rowOf: caret)]] ifFalse: [buffer string graphemeClusterEndAfter: caret]].
	self replaceFrom: caret to: target with: '' kind: #forwardDelete
!
newline
	"Insert a line feed and the current line's indentation."
	| line ls i indent |
	readOnly ifTrue: [^self].
	line := self lineIndexOf: self selectionStart.
	ls := self lineStarts at: line.
	i := ls.
	[i < self selectionStart and: [(buffer at: i + 1) == Character tab or: [(buffer at: i + 1) == $ ]]] whileTrue: [i := i + 1].
	indent := buffer copyFrom: ls + 1 to: i.
	self replaceFrom: self selectionStart to: self selectionStop with: (String with: Character lf), indent kind: #newline
!
tab: outdent
	"Insert a tab; with a selection spanning lines (or shift), indent or outdent those lines."
	| first last |
	readOnly ifTrue: [^self].
	first := self lineIndexOf: self selectionStart.
	last := self lineIndexOf: (self selectionStop - 1 max: self selectionStart).
	(outdent not and: [first = last]) ifTrue: [^self replaceFrom: self selectionStart to: self selectionStop with: (String with: Character tab) kind: #typing].
	self shiftLines: first to: last outdent: outdent
!
shiftLines: first to: last outdent: outdent
	| start stop block lines newBlock |
	start := self lineStarts at: first.
	stop := self lineEndAt: last.
	block := buffer copyFrom: start + 1 to: stop.
	lines := block lines.
	(block notEmpty and: [block last == Character lf]) ifTrue: [lines := lines copyWith: ''].
	lines isEmpty ifTrue: [lines := Array with: ''].
	newBlock := String new: block size + lines size streamContents: [:s |
		lines doWithIndex: [:line :i |
			i > 1 ifTrue: [s nextPut: Character lf].
			outdent
				ifTrue: [
					(line notEmpty and: [line first == Character tab])
						ifTrue: [s nextPutAll: line allButFirst]
						ifFalse: [s nextPutAll: line]]
				ifFalse: [line isEmpty ifFalse: [s nextPut: Character tab]. s nextPutAll: line]]].
	self replaceFrom: start to: stop with: newBlock kind: #indent.
	anchor := start.
	caret := start + newBlock size.
	self invalidate
!
insertAfterSelection: aString select: aBoolean
	"Insert aString after the selection (print it). Select the inserted text without its leading white space if aBoolean. Answer that text's Interval (1-based)."
	| pos lead |
	pos := self selectionStop.
	self basicInsertAt: pos string: aString.
	lead := 0.
	[lead < aString size and: [(aString at: lead + 1) isWhiteSpace]] whileTrue: [lead := lead + 1].
	aBoolean
		ifTrue: [self setAnchor: pos + lead caret: pos + aString size]
		ifFalse: [self invalidate].
	^pos + lead + 1 to: pos + aString size
!
basicInsertAt: pos string: aString
	"Insert undoably even when read-only (tools printing results)."
	| before new |
	before := Array with: anchor with: caret.
	new := buffer normalize: aString.
	buffer replaceFrom: pos to: pos with: new.
	anchor := pos + new size.
	caret := anchor.
	history record: #insert position: pos removed: '' inserted: new before: before after: (Array with: anchor with: caret).
	self edited
!
appendText: aString
	"Add aString at the end (transcripts), keeping the caret at the end if it was there."
	| atEnd |
	atEnd := caret = buffer size.
	buffer replaceFrom: buffer size to: buffer size with: (buffer normalize: aString).
	atEnd ifTrue: [caret := buffer size. anchor := caret].
	self layout.
	atEnd ifTrue: [self scrollToCaret].
	self invalidate
!
copySelection
 | w context |
 self hasSelection ifTrue: [
 self clipboardText: self selectedText.
 (Smalltalk at: #ActionContext ifAbsent: [nil]) ifNotNil: [:actions | actions copied: (actions forEditor: self)].
 ^self].
 w := self window.
 (w notNil and: [(w content respondsTo: #agentContext) and: [Smalltalk includesKey: #ActionContext]]) ifTrue: [
 context := (Smalltalk at: #ActionContext) for: w content.
 self clipboardText: context value printString.
 (Smalltalk at: #ActionContext) copied: context]
!
atomicMarksSnapshot
 ^(marks select: [:m | m isAtomic]) collect: [:m | m copy]
!
replay: start to: stop with: aString selection: selection
 buffer replaceFrom: start to: stop with: aString.
 selection size >= 3 ifTrue: [
 marks := marks reject: [:m | m isAtomic].
 (selection at: 3) do: [:m | marks add: m copy]].
 anchor := (selection at: 1) min: buffer size.
 caret := (selection at: 2) min: buffer size.
 self edited
!
insertAtomicText: aString style: style data: object
 | stop |
 readOnly ifTrue: [^self].
 stop := self replaceFrom: self selectionStart to: self selectionStop with: aString kind: #atomic.
 (self addMarkFrom: stop - aString size to: stop style: style) data: object.
 history lastAfter: (Array with: anchor with: caret with: self atomicMarksSnapshot)
! !

!TextEditor methodsFor: 'undo'!
canUndo
	^history canUndo
!
canRedo
	^history canRedo
!
undo
	history undoWith: [:start :stop :aString :selection | self replay: start to: stop with: aString selection: selection]
!
redo
	history redoWith: [:start :stop :aString :selection | self replay: start to: stop with: aString selection: selection]
! !

!TextEditor methodsFor: 'clipboard'!
cut
	self hasSelection ifFalse: [^self].
	self copySelection.
	readOnly ifFalse: [self replaceFrom: self selectionStart to: self selectionStop with: '' kind: #cut]
!
paste
	| s |
	readOnly ifTrue: [^self].
	s := self clipboardText.
	(s isNil or: [s isEmpty]) ifTrue: [^self].
	self replaceFrom: self selectionStart to: self selectionStop with: s kind: #paste
! !

!TextEditor methodsFor: 'commands'!
runHook: aBlock
	| t |
	aBlock isNil ifTrue: [^false].
	t := self selectionOrLine.
	aBlock cull: t cull: self selectionInterval cull: self.
	^true
!
doIt
	^self runHook: onDoIt
!
printIt
	^self runHook: onPrintIt
!
accept
	"The handler sees me clean (a status it shows says accepted); answering false leaves me dirty."
	| result |
	onAccept isNil ifTrue: [^false].
	dirty := false.
	result := onAccept cull: buffer string cull: self.
	result == false ifTrue: [self dirty: true] ifFalse: [self beClean].
	^true
!
defaultMenu
	| m |
	m := Menu new.
	m add: 'do it' key: '⌘D' action: [self inWindowDo: [self doIt]].
	(m add: 'print it' key: '⌘P' action: [self inWindowDo: [self printIt]]) enabled: onPrintIt notNil.
	(m add: 'inspect it' key: '⌘I' action: [self inWindowDo: [self inspectIt]]) enabled: onInspectIt notNil.
	(m add: 'browse it' key: '⌘B' action: [self inWindowDo: [self browseIt]]) enabled: onBrowseIt notNil.
	(m itemLabeled: 'do it') enabled: onDoIt notNil.
	m addSeparator.
	(m add: 'accept' key: '⌘S' action: [self inWindowDo: [self accept]]) enabled: onAccept notNil.
	m addSeparator.
	(m add: 'undo' key: '⌘Z' action: [self inWindowDo: [self undo]]) enabled: self canUndo.
	(m add: 'redo' key: '⇧⌘Z' action: [self inWindowDo: [self redo]]) enabled: self canRedo.
	(m add: 'cut' key: '⌘X' action: [self inWindowDo: [self cut]]) enabled: (self hasSelection and: [readOnly not]).
	(m add: 'copy' key: '⌘C' action: [self inWindowDo: [self copySelection]]) enabled: self hasSelection.
	(m add: 'paste' key: '⌘V' action: [self inWindowDo: [self paste]]) enabled: readOnly not.
	m add: 'select all' key: '⌘A' action: [self inWindowDo: [self selectAll]].
	^m
!
contextMenuAt: aPoint
	menuBlock isNil ifFalse: [^super contextMenuAt: aPoint].
	^self defaultMenu
! !

!TextEditor methodsFor: 'marks'!
marks
	^marks
!
addMark: anInterval style: aSymbol
	"Mark the characters of anInterval (1-based); answer the TextMark."
	^self addMarkFrom: anInterval first - 1 to: anInterval last style: aSymbol
!
addMarkFrom: start to: stop style: aSymbol
	"Mark between gap positions."
	| m |
	m := TextMark start: ((start max: 0) min: buffer size) stop: ((stop max: 0) min: buffer size) style: aSymbol.
	marks add: m.
	self invalidate.
	^m
!
removeMark: aTextMark
	marks remove: aTextMark ifAbsent: [].
	self invalidate
!
removeMarksStyled: aSymbol
	marks := marks reject: [:m | m style == aSymbol].
	self invalidate
!
clearMarks
	marks := OrderedCollection new.
	self invalidate
!
marksStyled: aSymbol
	^marks select: [:m | m style == aSymbol]
!
pcMark
	^marks detect: [:m | m style == #pc] ifNone: [nil]
!
pcMark: anIntervalOrNil
	"Move the debugger's current-statement highlight (gliding from where it was), or remove it (nil)."
	^self pcMark: anIntervalOrNil style: #pc
!
pcMark: anIntervalOrNil style: aSymbol
	| old oldRect newMark newRect |
	old := marks detect: [:m | m style == #pc or: [m style == #pcReturn]] ifNone: [nil].
	oldRect := old isNil ifTrue: [nil] ifFalse: [(self rectsFrom: old start to: old stop) ifEmpty: [nil] ifNotEmpty: [:rs | rs first translateBy: 0 @ self scrollOffset]].
	marks := marks reject: [:m | m style == #pc or: [m style == #pcReturn]].
	anIntervalOrNil isNil ifTrue: [self invalidate. ^nil].
	newMark := self addMark: anIntervalOrNil style: aSymbol.
	self scrollToShowMark: newMark.
	newRect := (self rectsFrom: newMark start to: newMark stop) ifEmpty: [nil] ifNotEmpty: [:rs | rs first translateBy: 0 @ self scrollOffset].
	(oldRect notNil and: [newRect notNil and: [aSymbol == #pc and: [oldRect ~= newRect]]]) ifTrue: [
		pcAnimation isNil ifFalse: [pcAnimation stop].
		pcGlide := oldRect.
		pcAnimation := self tweenFrom: oldRect to: newRect duration: (self theme metric: #glideMs) + 100 do: [:r |
			pcGlide := r.
			r = newRect ifTrue: [pcGlide := nil. pcAnimation := nil].
			self invalidate]].
	^newMark
!
scrollToShowMark: aTextMark
	| top bottom padY offset |
	top := self rowTop: (self rowOf: aTextMark start).
	bottom := (self rowTop: (self rowOf: aTextMark stop)) + self lineHeight.
	padY := textLayout padY.
	offset := textLayout offset.
	top - padY < offset ifTrue: [^self scrollOffset: (textLayout wholeLines: top - padY)].
	bottom + padY > (offset + self height) ifTrue: [self scrollOffset: ((textLayout wholeLines: bottom + padY - self height) min: (textLayout wholeLines: top - padY))]
!
isGliding
	^pcGlide notNil
! !

!TextEditor methodsFor: 'highlighting'!
ensureTokens
	highlighter ensureTokens
!
tokens
	"The highlight tokens as {type. start. stop} triples (1-based character indices)."
	^highlighter tokens
!
tokenTypeAt: anIndex
	"The highlight type of the character at anIndex (1-based), or nil for white space."
	^highlighter tokenTypeAt: anIndex
! !

!TextEditor methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| first last clip y textArea selColor overrides offset drawn key same |
	textLayout ensureRows.
	aCanvas fillRect: self localBounds color: self theme paper.
	(tracksDirty and: [dirty]) ifTrue: [aCanvas fillRect: (0 @ 0 extent: 2 @ self height) color: self theme ultramarine].
	textArea := 0 @ 0 corner: (scrollBar isVisible ifTrue: [self width - (self theme metric: #scrollBarWidth)] ifFalse: [self width]) @ self height.
	clip := aCanvas clipRect intersect: textArea.
	first := textLayout rowAtY: clip top.
	last := textLayout rowAtY: clip bottom.
	selColor := self isFocused ifTrue: [self theme color: #textSelection] ifFalse: [self theme color: #textSelectionInactive].
	overrides := self textColorOverrides.
	highlighter ensureTokens.
	offset := textLayout offset.
	drawn := Dictionary new.
	"Nothing the rows show changed (a caret blink): replay them without comparing what each shows."
	key := Array new: 14.
	key at: 1 put: buffer string; at: 2 put: highlighter tokenTypes; at: 3 put: textLayout rowStarts; at: 4 put: textLayout rowEnds;
		at: 5 put: offset; at: 6 put: first; at: 7 put: last; at: 8 put: caret; at: 9 put: anchor; at: 10 put: selColor;
		at: 11 put: self font; at: 12 put: self visibleMarks asArray; at: 13 put: textArea corner; at: 14 put: preedit.
	same := self rowsKey: key matches: rowsKey.
	aCanvas clip: textArea during: [
		first to: last do: [:r | | cached |
			cached := same ifTrue: [rowDrawings at: r ifAbsent: [nil]].
			(cached notNil and: [aCanvas replay: cached last]) ifFalse: [
				y := (textLayout rowTop: r) - offset.
				cached := self drawRow: r y: y selectionColor: selColor overrides: overrides on: aCanvas].
			drawn at: r put: cached].
		pcGlide isNil ifFalse: [self drawGlideOn: aCanvas].
		self drawCaretOn: aCanvas].
	rowDrawings := drawn.
	rowsKey := key
!
rowsKey: anArray matches: anotherArray
	"The same objects (the same numbers), elementwise; the marks too."
	anotherArray isNil ifTrue: [^false].
	1 to: anArray size do: [:i | | a b |
		a := anArray at: i.
		b := anotherArray at: i.
		(a == b or: [(a isNumber or: [a isPoint]) and: [a = b]]) ifFalse: [
			(i = 12 and: [a size = b size and: [(1 to: a size) allSatisfy: [:k | (a at: k) == (b at: k)]]]) ifFalse: [^false]]].
	^true
!
drawRow: r y: y selectionColor: selColor overrides: overrides on: aCanvas
	"Draw row r (backgrounds and text), replaying its last drawing if it shows the same; answer {what it shows. its DisplaySegment}."
	| shows cached |
	shows := self rowShows: r y: y selectionColor: selColor.
	cached := rowDrawings isNil ifFalse: [rowDrawings at: r ifAbsent: [nil]].
	(cached notNil and: [cached first = shows and: [aCanvas replay: cached last]]) ifTrue: [^cached].
	^Array with: shows with: (aCanvas record: [
		(preedit notNil and: [(textLayout rowOf: caret) = r])
			ifTrue: [self drawPreeditRow: r y: y selectionColor: selColor overrides: overrides on: aCanvas]
			ifFalse: [
				self drawBackgroundsOfRow: r y: y selectionColor: selColor on: aCanvas.
				self drawTextOfRow: r y: y overrides: overrides forcedColor: nil on: aCanvas]])
!
drawPreeditRow: r y: y selectionColor: selColor overrides: overrides on: aCanvas
	"Row r with the input method's composition at the caret, underlined (the part being converted thicker); the text after the caret moves right to make room."
	| x w lh s font ink a b |
	s := preedit string.
	font := self font.
	ink := self theme ink.
	x := textLayout textLeft + (textLayout xOf: caret inRow: r).
	w := font widthOf: s.
	lh := self lineHeight.
	aCanvas clip: (0 @ y corner: x @ (y + lh)) during: [
		self drawBackgroundsOfRow: r y: y selectionColor: selColor on: aCanvas.
		self drawTextOfRow: r y: y overrides: overrides forcedColor: nil on: aCanvas].
	aCanvas translateBy: w @ 0 during: [
		aCanvas clip: (x @ y corner: self width @ (y + lh)) during: [
			self drawBackgroundsOfRow: r y: y selectionColor: selColor on: aCanvas.
			self drawTextOfRow: r y: y overrides: overrides forcedColor: nil on: aCanvas]].
	aCanvas drawString: s at: x @ y font: font color: ink.
	aCanvas fillRect: (x @ (y + lh - 2) corner: (x + w) @ (y + lh - 1)) color: ink.
	(preedit selectionSize notNil and: [preedit selectionSize > 0]) ifTrue: [
		a := (preedit cursor ifNil: [0]) min: s size.
		b := a + preedit selectionSize min: s size.
		aCanvas fillRect: ((x + (font widthOf: s from: 1 to: a)) @ (y + lh - 3) corner: (x + (font widthOf: s from: 1 to: b)) @ (y + lh - 1)) color: ink]
!
rowShows: r y: y selectionColor: selColor
	"Everything row r's drawing depends on, relative to its first character."
	| rs re runs shown sel |
	rs := textLayout rowStarts at: r.
	re := textLayout rowEnds at: r.
	runs := OrderedCollection new.
	(re > rs and: [highlighter isActive]) ifTrue: [
		highlighter styledRunsFrom: rs to: re color: nil do: [:a :b :f :c | runs add: a - rs; add: b - rs; add: f; add: c]].
	shown := OrderedCollection new.
	self visibleMarks do: [:m |
		(m stop >= rs and: [m start <= (re + 1)]) ifTrue: [shown add: m style; add: m start - rs; add: m stop - rs]].
	sel := (self hasSelection and: [self selectionStop >= rs and: [self selectionStart <= (re + 1)]])
		ifTrue: [Array with: self selectionStart - rs with: self selectionStop - rs with: selColor].
	^(Array new: 10)
		at: 1 put: y;
		at: 2 put: (buffer string copyFrom: rs + 1 to: re);
		at: 3 put: runs asArray;
		at: 4 put: shown asArray;
		at: 5 put: sel;
		at: 6 put: self font;
		at: 7 put: (re > rs and: [textLayout isMonoLine: (buffer lineIndexOf: rs)]);
		at: 8 put: highlighter isActive;
		at: 9 put: self theme ink;
		at: 10 put: ((preedit notNil and: [(textLayout rowOf: caret) = r]) ifTrue: [preedit]);
		yourself
!
invalidate
	"Rows replay what did not change (drawRow:...), so draw only me again, and my scroll bar."
	scrollBar invalidate.
	self ownDrawingChanged.
	self requestRedraw
!
visibleMarks
	pcGlide isNil ifTrue: [^marks].
	^marks reject: [:m | m style == #pc]
!
textColorOverrides
	| result |
	result := OrderedCollection new.
	self visibleMarks do: [:m | (m textColorIn: self theme) ifNotNil: [:c | result add: (Array with: m start with: m stop with: c)]].
	^result
!
drawBackgroundsOfRow: r y: y selectionColor: selColor on: aCanvas
	| rs re |
	rs := textLayout rowStarts at: r.
	re := textLayout rowEnds at: r.
	self visibleMarks do: [:m |
		(m stop >= rs and: [m start <= (re + 1)]) ifTrue: [
			(m backgroundColorIn: self theme) ifNotNil: [:c |
				(textLayout rectOfRow: r from: m start to: m stop) ifNotNil: [:rect | aCanvas fillRect: rect color: c]].
			(m underlineColorIn: self theme) ifNotNil: [:c |
				(textLayout rectOfRow: r from: m start to: m stop) ifNotNil: [:rect |
					aCanvas fillRect: (rect left @ (rect bottom - 2) corner: rect right @ rect bottom) color: c]]]].
	self hasSelection ifTrue: [
		(self selectionStop >= rs and: [self selectionStart <= (re + 1)]) ifTrue: [
			(textLayout rectOfRow: r from: self selectionStart to: self selectionStop) ifNotNil: [:rect |
				aCanvas fillRect: rect color: selColor]]]
!
drawTextOfRow: r y: y overrides: overrides forcedColor: forced on: aCanvas
	"Draw the row's styled runs (TextHighlighter)."
	| rs re x pos ov mono |
	rs := textLayout rowStarts at: r.
	re := textLayout rowEnds at: r.
	re <= rs ifTrue: [^self].
	mono := (textLayout isMonoLine: (buffer lineIndexOf: rs)) ifTrue: [textLayout monoAdvance] ifFalse: [false].
	ov := forced isNil ifTrue: [overrides] ifFalse: [#()].
	highlighter isActive ifFalse: [
		^self drawRunFrom: rs to: re x: 0 y: y font: self font color: (forced ifNil: [self theme ink]) overrides: ov mono: mono on: aCanvas].
	x := 0.
	pos := rs.
	highlighter styledRunsFrom: rs to: re color: forced do: [:a :b :f :c |
		x := textLayout xFrom: pos to: a startX: x.
		x := self drawRunFrom: a to: b x: x y: y font: f color: c overrides: ov mono: mono on: aCanvas.
		pos := b]
!
drawRunFrom: a to: b x: startX y: y font: aFont color: aColor overrides: overrides mono: mono on: aCanvas
	"Draw the characters a + 1 .. b starting at startX (relative to the text left), splitting where a mark replaces the color. Answer the x after b."
	| x cuts |
	overrides isEmpty ifTrue: [^self drawPlainFrom: a to: b x: startX y: y font: aFont color: aColor mono: mono on: aCanvas].
	cuts := OrderedCollection new.
	overrides do: [:o |
		((o at: 1) > a and: [(o at: 1) < b]) ifTrue: [cuts add: (o at: 1)].
		((o at: 2) > a and: [(o at: 2) < b]) ifTrue: [cuts add: (o at: 2)]].
	cuts := (Array with: a) , cuts asSortedCollection asArray , (Array with: b).
	x := startX.
	1 to: cuts size - 1 do: [:i |
		| from to color |
		from := cuts at: i.
		to := cuts at: i + 1.
		color := aColor.
		overrides do: [:o | (from >= (o at: 1) and: [to <= (o at: 2)]) ifTrue: [color := o at: 3]].
		x := self drawPlainFrom: from to: to x: x y: y font: aFont color: color mono: mono on: aCanvas].
	^x
!
drawPlainFrom: a to: b x: startX y: y font: aFont color: aColor mono: mono on: aCanvas
	"mono is the advance of every character when the row is printable ASCII and the font is monospaced, else false."
	| i j x tab left base text |
	tab := Character tab.
	left := textLayout textLeft.
	text := buffer string.
	mono == false ifFalse: [
		aCanvas drawString: text from: a + 1 to: b at: (left + startX) @ y font: aFont color: aColor.
		^startX + ((b - a) * mono)].
	base := self font.
	x := startX.
	i := a.
	[i < b] whileTrue: [
		j := i.
		[j < b and: [(text at: j + 1) ~~ tab]] whileTrue: [j := j + 1].
		j > i ifTrue: [
			aCanvas drawString: text from: i + 1 to: j at: (left + x) @ y font: aFont color: aColor.
			x := x + (base widthOf: text from: i + 1 to: j)].
		j < b ifTrue: [
			x := textLayout nextTabStop: x.
			j := j + 1].
		i := j].
	^x
!
drawGlideOn: aCanvas
	| r first last offset |
	offset := textLayout offset.
	r := pcGlide translateBy: 0 @ offset negated.
	aCanvas fillRect: r color: self theme ultramarine.
	aCanvas clip: r during: [
		first := textLayout rowAtY: r top.
		last := textLayout rowAtY: r bottom - 0.01.
		first to: last do: [:row |
			self drawTextOfRow: row y: (textLayout rowTop: row) - offset overrides: #() forcedColor: self theme paper on: aCanvas]]
!
drawCaretOn: aCanvas
	(self isFocused and: [readOnly not and: [caretOn and: [self hasSelection not]]]) ifFalse: [^self].
	aCanvas fillRect: (self caretRect translateBy: self preeditCaretX @ 0) color: self theme ink
! !

!TextEditor methodsFor: 'input method'!
preedit
	"The input method's composition shown at the caret (a TextEditingEvent), or nil."
	^preedit
!
preeditCaretX
	"Points from the caret to the input method's cursor in its composition."
	| s |
	preedit isNil ifTrue: [^0].
	s := preedit string.
	^self font widthOf: s from: 1 to: ((preedit cursor ifNil: [s size]) min: s size)
!
textEditing: anEvent
	"Show the composition at the caret (replacing a selection), or remove it (empty)."
	readOnly ifTrue: [^true].
	(anEvent string isEmpty and: [preedit isNil]) ifTrue: [^true].
	(anEvent string notEmpty and: [preedit isNil]) ifTrue: [self deleteSelection].
	preedit := anEvent string isEmpty ifFalse: [anEvent].
	caretOn := true.
	self restartBlink.
	self invalidate.
	self updateTextInputArea.
	^true
!
updateTextInputArea
	"Tell the input method where the caret and the composition are (screen points), for its candidates."
	| w r |
	(readOnly not and: [self isFocused]) ifFalse: [^self].
	w := self window.
	r := self caretRect.
	w textInputArea: ((self screenPointFrom: r origin) extent: ((preedit isNil ifTrue: [0] ifFalse: [self font widthOf: preedit string]) max: r width) @ r height)
		cursor: self preeditCaretX
! !

!TextEditor methodsFor: 'caret blinking'!
restartBlink
	blinkTimer isNil ifFalse: [blinkTimer cancel. blinkTimer := nil].
	self hasKeyboardFocus ifFalse: [^self].
	blinkTimer := self afterAnimationTime: (self theme metric: #caretBlinkMs) do: [self blink]
!
blink
	blinkTimer := nil.
	self hasKeyboardFocus ifFalse: [^self].
	self isFocused
		ifTrue: [caretOn := caretOn not. self invalidate]
		ifFalse: [caretOn := true].
	blinkTimer := self afterAnimationTime: (self theme metric: #caretBlinkMs) do: [self blink]
!
isCaretOn
	^caretOn
!
focusGained
	caretOn := true.
	self restartBlink.
	self invalidate.
	self updateTextInputArea
!
focusLost
	blinkTimer isNil ifFalse: [blinkTimer cancel. blinkTimer := nil].
	dragging := false.
	preedit := nil.
	self invalidate
! !

!TextEditor methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
cursorAt: aPoint
	^#ibeam
!
mouseDown: anEvent
	| pos range p |
	anEvent button = 1 ifFalse: [^false].
	p := self localEventPosition: anEvent.
	pos := self positionAt: p.
	dragging := true.
	anEvent clickCount >= 3 ifTrue: [
		granularity := #line.
		range := buffer lineRangeAt: pos.
		(range at: 2) < buffer size ifTrue: [range at: 2 put: (range at: 2) + 1].
		^self startDragRange: range].
	anEvent clickCount = 2 ifTrue: [
		granularity := #word.
		^self startDragRange: (buffer wordRangeAt: pos)].
	granularity := #character.
	anEvent modifiers shift
		ifTrue: [self setAnchor: anchor caret: pos]
		ifFalse: [self setAnchor: pos caret: pos].
	dragAnchorStart := anchor.
	dragAnchorStop := anchor.
	^true
!
startDragRange: range
	dragAnchorStart := range at: 1.
	dragAnchorStop := range at: 2.
	self setAnchor: dragAnchorStart caret: dragAnchorStop.
	^true
!
mouseMove: anEvent
	| p pos range |
	dragging ifFalse: [^false].
	p := self localEventPosition: anEvent.
	p y < 0 ifTrue: [self scrollOffset: self scrollOffset - self lineHeight].
	p y > self height ifTrue: [self scrollOffset: self scrollOffset + self lineHeight].
	pos := self positionAt: p.
	granularity == #character ifTrue: [
		self setAnchor: dragAnchorStart caret: pos.
		^true].
	range := granularity == #word ifTrue: [buffer wordRangeAt: pos] ifFalse: [buffer lineRangeAt: pos].
	(granularity == #line and: [(range at: 2) < buffer size]) ifTrue: [range at: 2 put: (range at: 2) + 1].
	pos < dragAnchorStart
		ifTrue: [anchor := dragAnchorStop. caret := range at: 1]
		ifFalse: [anchor := dragAnchorStart. caret := (range at: 2) max: dragAnchorStop].
	self setAnchor: anchor caret: caret.
	^true
!
mouseUp: anEvent
	dragging := false.
	^true
!
wheel: anEvent
	self scrollOffset: self scrollOffset - (anEvent delta y * 40).
	^true
!
textInput: anEvent
	| s |
	readOnly ifTrue: [^true].
	preedit isNil ifFalse: [preedit := nil. self invalidate].
	s := anEvent string select: [:c | (c value >= 32 and: [c value < 127 or: [c value > 159]]) or: [c == Character tab]].
	s isEmpty ifTrue: [^true].
	self insert: s.
	^true
!
keyDown: anEvent
	| key mods cmd opt shift |
	"Keys typed while the input method composes are its own (they also come here on macOS)."
	(preedit notNil and: [anEvent modifiers commandKey not]) ifTrue: [^true].
	(onKey notNil and: [(onKey value: anEvent) == true]) ifTrue: [^true].
	key := anEvent key.
	mods := anEvent modifiers.
	cmd := mods commandKey.
	opt := mods option.
	shift := mods shift.
	key isCharacter ifTrue: [
		cmd ifFalse: [^false].
		^self commandKey: key asLowercase shift: shift].
	key == #left ifTrue: [^self moveLeft: (cmd ifTrue: [#line] ifFalse: [opt ifTrue: [#word] ifFalse: [#character]]) extend: shift].
	key == #right ifTrue: [^self moveRight: (cmd ifTrue: [#line] ifFalse: [opt ifTrue: [#word] ifFalse: [#character]]) extend: shift].
	key == #up ifTrue: [^cmd ifTrue: [self moveTo: 0 extend: shift] ifFalse: [self moveRows: -1 extend: shift]].
	key == #down ifTrue: [^cmd ifTrue: [self moveTo: buffer size extend: shift] ifFalse: [self moveRows: 1 extend: shift]].
	key == #home ifTrue: [^self moveTo: (cmd ifTrue: [0] ifFalse: [self rowStart: (self rowOf: caret)]) extend: shift].
	key == #end ifTrue: [^self moveTo: (cmd ifTrue: [buffer size] ifFalse: [self rowEnd: (self rowOf: caret)]) extend: shift].
	key == #pageUp ifTrue: [^self moveRows: self visibleRowCount negated extend: shift].
	key == #pageDown ifTrue: [^self moveRows: self visibleRowCount extend: shift].
	key == #backspace ifTrue: [self deleteBackward: (cmd ifTrue: [#line] ifFalse: [opt ifTrue: [#word] ifFalse: [#character]]). ^true].
	key == #delete ifTrue: [self deleteForward: (opt ifTrue: [#word] ifFalse: [cmd ifTrue: [#line] ifFalse: [#character]]). ^true].
	(key == #return or: [key == #enter]) ifTrue: [
		cmd ifTrue: [^false].
		readOnly ifTrue: [^false].
		self newline.
		^true].
	key == #tab ifTrue: [
		(cmd or: [opt]) ifTrue: [^false].
		readOnly ifTrue: [^false].
		self tab: shift.
		^true].
	key == #escape ifTrue: [^false].
	^false
!
commandKey: aCharacter shift: shift
	aCharacter = $j ifTrue: [(Smalltalk at: #ActionContext ifAbsent: [nil]) ifNotNil: [:actions | (actions forEditor: self) agent]. ^true].
 aCharacter = $a ifTrue: [self selectAll. ^true].
	aCharacter = $c ifTrue: [self copySelection. ^true].
	aCharacter = $x ifTrue: [self cut. ^true].
	aCharacter = $v ifTrue: [self paste. ^true].
	aCharacter = $z ifTrue: [shift ifTrue: [self redo] ifFalse: [self undo]. ^true].
	aCharacter = $d ifTrue: [^self doIt].
	aCharacter = $p ifTrue: [^self printIt].
	aCharacter = $i ifTrue: [^self inspectIt].
	aCharacter = $b ifTrue: [^self browseIt].
	aCharacter = $s ifTrue: [^self accept].
	^false
!
moveTo: aPosition extend: shift
	shift
		ifTrue: [self setAnchor: anchor caret: aPosition]
		ifFalse: [self setAnchor: aPosition caret: aPosition].
	^true
!
moveLeft: unit extend: shift
	| target |
	(self hasSelection and: [shift not and: [unit == #character]]) ifTrue: [^self moveTo: self selectionStart extend: false].
	target := unit == #character ifTrue: [buffer string graphemeClusterStartBefore: caret] ifFalse: [
		unit == #word ifTrue: [buffer wordStartBefore: caret] ifFalse: [self rowStart: (self rowOf: caret)]].
	^self moveTo: (target max: 0) extend: shift
!
moveRight: unit extend: shift
	| target |
	(self hasSelection and: [shift not and: [unit == #character]]) ifTrue: [^self moveTo: self selectionStop extend: false].
	target := unit == #character ifTrue: [buffer string graphemeClusterEndAfter: caret] ifFalse: [
		unit == #word ifTrue: [buffer wordEndAfter: caret] ifFalse: [self rowEnd: (self rowOf: caret)]].
	^self moveTo: (target min: buffer size) extend: shift
!
moveRows: delta extend: shift
	| row target x newRow |
	row := self rowOf: caret.
	x := goalX ifNil: [textLayout xOf: caret inRow: row].
	newRow := row + delta.
	newRow < 1
		ifTrue: [target := 0]
		ifFalse: [
			newRow > self rowCount
				ifTrue: [target := buffer size]
				ifFalse: [target := textLayout positionInRow: newRow atX: x]].
	self moveTo: target extend: shift.
	goalX := x.
	^true
! !

!TextEditor methodsFor: 'remote control'!
remoteRole
	^#editor
!
remoteLabel
	^title
!
remoteState
	| s |
	s := OrderedCollection new.
	s add: 'lines=', self lineCount printString.
	self hasSelection
		ifTrue: [s add: 'sel=', self selectionStart printString, '-', self selectionStop printString]
		ifFalse: [s add: 'caret=', caret printString].
	tracksDirty ifTrue: [s add: (dirty ifTrue: ['dirty'] ifFalse: ['dirty=false'])].
	readOnly ifTrue: [s add: #readonly].
	self isFocused ifTrue: [s add: #focused].
	s add: 'text=', (self remoteQuote: (self collapsedText: 60)).
	^s asArray
!
collapsedText: max
	| out lastSpace |
	out := WriteStream on: (String new: max).
	lastSpace := true.
	buffer string do: [:c |
		out position >= max ifTrue: [^out contents trimRight].
		c isWhiteSpace
			ifTrue: [lastSpace ifFalse: [out nextPut: $ ]. lastSpace := true]
			ifFalse: [out nextPut: c. lastSpace := false]].
	^out contents trimRight
!
remoteChildren
	| kids |
	kids := OrderedCollection new.
	self hasSelection ifTrue: [
		kids add: (WidgetPart of: self role: #selection label: (self cut: self selectedText to: 240))].
	marks do: [:m |
		kids add: ((WidgetPart of: self role: #mark label: (self cut: (buffer copyFrom: m start + 1 to: m stop) to: 240))
			state: (Array with: m style); yourself)].
	self lines doWithIndex: [:line :i | i <= 400 ifTrue: [kids add: '| ', line]].
	^kids asArray
!
cut: aString to: max
	aString size <= max ifTrue: [^aString].
	^(aString first: (aString graphemeClusterStartBefore: max)), (String with: (Character value: 8230))
!
remoteText
	^buffer string
!
remoteSelect: aSpec
	"Select for remote control: 'all', 'end', 'start', 'line:n', a String to find, or a Dictionary with from/to (0-based gap positions) or line (1-based)."
	^self inWindowWait: [self selectSpec: aSpec]
!
remoteSelect: aSpec then: aBlock
	"Like remoteSelect:, without waiting: select in my window's Process, then aBlock value: the answer (there)."
	self inWindowDo: [aBlock value: (self selectSpec: aSpec)]
!
selectSpec: aSpec
	| i line |
	aSpec isString ifTrue: [
		aSpec = 'all' ifTrue: [self selectAll. ^self remoteSelectionAnswer].
		aSpec = 'end' ifTrue: [self caret: buffer size. ^self remoteSelectionAnswer].
		aSpec = 'start' ifTrue: [self caret: 0. ^self remoteSelectionAnswer].
		(aSpec beginsWith: 'line:') ifTrue: [
			line := Number readFrom: (aSpec allButFirst: 5) ifFail: [nil].
			^self selectLine: line].
		i := buffer string indexOfSubCollection: aSpec startingAt: 1.
		i = 0 ifTrue: [^RemoteError notFound: 'text not found: ', aSpec].
		self setAnchor: i - 1 caret: i - 1 + aSpec size.
		^self remoteSelectionAnswer].
	(aSpec respondsTo: #at:ifAbsent:) ifTrue: [
		(aSpec at: 'line' ifAbsent: [nil]) ifNotNil: [:n | ^self selectLine: n].
		(aSpec at: 'from' ifAbsent: [nil]) ifNotNil: [:from |
			self setAnchor: from caret: (aSpec at: 'to' ifAbsent: [from]).
			^self remoteSelectionAnswer]].
	^RemoteError signal: 'cannot select ', aSpec printString
!
selectLine: n
	(n isInteger and: [n between: 1 and: self lineCount]) ifFalse: [^RemoteError signal: 'no line ', n printString].
	self setAnchor: (self lineStarts at: n) caret: (self lineEndAt: n).
	^self remoteSelectionAnswer
!
remoteSelectionAnswer
	^Dictionary new
		at: 'sel' put: self selectionStart printString, '-', self selectionStop printString;
		at: 'caret' put: caret;
		yourself
! !

!TextEditor class methodsFor: 'instance creation'!
text: aString
	^self new text: aString; yourself
! !

!TextEditor methodsFor: 'actions'!
inspectIt
 (Smalltalk at: #ActionContext ifAbsent: [nil]) ifNotNil: [:actions | (actions forEditor: self) inspect].
 ^true
!
browseIt
 (Smalltalk at: #ActionContext ifAbsent: [nil]) ifNotNil: [:actions | (actions forEditor: self) browse].
 ^true
! !
