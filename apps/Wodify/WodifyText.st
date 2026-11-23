Object subclass: #WodifyText
	instanceVariableNames: ''
	classVariableNames: 'Entities'
	package: 'Wodify'!

WodifyText comment: 'I turn Wodify''s text into what the card shows (class side): plain: makes its HTML plain text (line breaks for <br>, paragraph, div and list ends, a bullet for each list item, no other tags, entities decoded, at most one empty line in a row); squash: is a name as settings match it (lowercase letters and digits); level:of: keeps the blocks of a workout written in levels ("- RX -" … "- BEGINNER -" …) that the settings want.'!

!WodifyText class methodsFor: 'html'!
plain: anObject
	"Text of Wodify's HTML (or of anything else: printed; nil is empty)."
	| text lines out |
	anObject isNil ifTrue: [^''].
	text := anObject isString ifTrue: [anObject] ifFalse: [anObject printString].
	text := self untag: text.
	text := self unescape: text.
	text := text copyReplaceAll: (String with: Character cr) with: ''.
	lines := (self linesOf: text) collect: [:l |
		(l copyReplaceAll: (String with: (Character value: 160)) with: ' ') trimRight].
	out := String new: text size streamContents: [:s |
		lines do: [:l | s nextPutAll: l] separatedBy: [s nextPut: Character lf]].
	out := out trimBoth.
	"three or more line breaks become two"
	[out includesSubstring: (String new: 3 withAll: Character lf)] whileTrue: [
		out := out copyReplaceAll: (String new: 3 withAll: Character lf) with: (String new: 2 withAll: Character lf)].
	^out
!
linesOf: aString
	"aString split at each line feed, empty lines kept."
	| out start i |
	out := OrderedCollection new.
	start := 1.
	[(i := aString indexOf: Character lf startingAt: start) > 0] whileTrue: [
		out add: (aString copyFrom: start to: i - 1).
		start := i + 1].
	out add: (aString copyFrom: start to: aString size).
	^out
!
untag: aString
	"<br>, </p>, </div>, </li> as line breaks, <li> as a bullet, other tags dropped."
	^String new: aString size streamContents: [:s |
		| i |
		i := 1.
		[i <= aString size] whileTrue: [
			| c close tag name |
			c := aString at: i.
			close := c = $< ifTrue: [aString indexOf: $> startingAt: i] ifFalse: [0].
			close > 0
				ifTrue: [
					tag := (aString copyFrom: i + 1 to: close - 1) asLowercase.
					name := (tag copyReplaceAll: '/' with: ' ') trimBoth.
					name := (name subStrings: ' ') isEmpty ifTrue: [''] ifFalse: [(name subStrings: ' ') first].
					(name = 'br' or: [(#('/p' '/div' '/li') includes: (tag copyWithout: $ ))]) ifTrue: [s nextPut: Character lf].
					(name = 'li' and: [(tag beginsWith: '/') not]) ifTrue: [s nextPutAll: '• '].
					i := close + 1]
				ifFalse: [
					s nextPut: c.
					i := i + 1]]]
!
unescape: aString
	"HTML character references: &amp; &nbsp; &#8217; &#x2019; and the named ones Wodify's editor writes."
	(aString includes: $&) ifFalse: [^aString].
	^String new: aString size streamContents: [:s |
		| i |
		i := 1.
		[i <= aString size] whileTrue: [
			| c semi ref decoded |
			c := aString at: i.
			semi := c = $& ifTrue: [aString indexOf: $; startingAt: i] ifFalse: [0].
			decoded := nil.
			(semi > (i + 1) and: [semi - i <= 12]) ifTrue: [
				ref := aString copyFrom: i + 1 to: semi - 1.
				decoded := self decode: ref].
			decoded isNil
				ifTrue: [s nextPut: c. i := i + 1]
				ifFalse: [s nextPutAll: decoded. i := semi + 1]]]
!
decode: aReference
	"The text of a character reference without & and ;, nil if it is not one."
	| code |
	(aReference beginsWith: '#') ifTrue: [
		code := ((aReference size > 1 and: [(aReference at: 2) asLowercase = $x])
			ifTrue: [[Integer readFrom: (aReference copyFrom: 3 to: aReference size) asUppercase base: 16] on: Error do: [:e | e return: nil]]
			ifFalse: [(aReference copyFrom: 2 to: aReference size) asInteger]).
		(code isNil or: [code <= 0 or: [code > 16r10FFFF]]) ifTrue: [^nil].
		^String with: (Character value: code)].
	^(self entities at: aReference ifAbsent: [nil]) ifNotNil: [:cp | String with: (Character value: cp)]
!
entities
	^Entities ifNil: [
		Entities := Dictionary new.
		#('amp' 38 'lt' 60 'gt' 62 'quot' 34 'apos' 39 'nbsp' 160 'ndash' 8211 'mdash' 8212 'lsquo' 8216 'rsquo' 8217
			'sbquo' 8218 'ldquo' 8220 'rdquo' 8221 'bdquo' 8222 'hellip' 8230 'bull' 8226 'middot' 183 'deg' 176
			'frac12' 189 'frac14' 188 'frac34' 190 'times' 215 'divide' 247 'plusmn' 177 'minus' 8722 'le' 8804 'ge' 8805
			'rarr' 8594 'larr' 8592 'uarr' 8593 'darr' 8595 'harr' 8596 'copy' 169 'reg' 174 'trade' 8482 'euro' 8364
			'pound' 163 'cent' 162 'sup2' 178 'sup3' 179 'eacute' 233 'egrave' 232 'aacute' 225 'agrave' 224 'iacute' 237
			'oacute' 243 'uacute' 250 'ntilde' 241 'ouml' 246 'uuml' 252 'auml' 228 'szlig' 223 'Ouml' 214 'Uuml' 220 'Auml' 196
			'laquo' 171 'raquo' 187 'prime' 8242 'Prime' 8243 'ensp' 8194 'emsp' 8195 'thinsp' 8201 'zwj' 8205 'zwnj' 8204)
			pairsDo: [:name :code | Entities at: name put: code].
		Entities]
! !

!WodifyText class methodsFor: 'settings'!
squash: aString
	"Lowercase letters and digits only: how hide entries and names are compared (Warm-up, warm up and WARMUP alike)."
	^(aString isString ifTrue: [aString] ifFalse: ['']) asLowercase select: [:c | c isLetter or: [c isDigit]]
!
isHidden: aName by: squashedHides
	| n |
	n := self squash: aName.
	^squashedHides anySatisfy: [:h | n includesSubstring: h]
!
level: aLevel of: aText hiding: squashedHides
	"aText's level blocks (- RX - on a line of its own, up to the next): only aLevel's (its body alone, after what precedes the first block) when aLevel names one; else those not hidden. Text without blocks is kept whole."
	| text marks keep wanted out |
	text := aText ifNil: [''].
	marks := self levelMarksIn: text.
	marks isEmpty ifTrue: [^text].
	wanted := (aLevel ifNil: ['']) trimBoth asUppercase.
	keep := marks select: [:m |
		wanted isEmpty
			ifTrue: [(self isHidden: (m at: 1) by: squashedHides) not]
			ifFalse: [(m at: 1) asUppercase = wanted]].
	(wanted notEmpty and: [keep size = 1]) ifTrue: [
		^((text copyFrom: 1 to: (marks first at: 2) - 1), (text copyFrom: (keep first at: 3) to: (keep first at: 4))) trimBoth].
	(wanted notEmpty and: [keep isEmpty]) ifTrue: [^text].
	out := WriteStream on: String new.
	out nextPutAll: (text copyFrom: 1 to: (marks first at: 2) - 1).
	keep do: [:m | out nextPutAll: (text copyFrom: (m at: 2) to: (m at: 4))].
	^out contents trimBoth
!
levelMarksIn: aText
	"{name. start. body start. end} of each line - NAME -, the end before the next one's start."
	| marks pos |
	marks := OrderedCollection new.
	pos := 1.
	[pos <= aText size] whileTrue: [
		| eol line |
		eol := aText indexOf: Character lf startingAt: pos.
		eol = 0 ifTrue: [eol := aText size + 1].
		line := aText copyFrom: pos to: eol - 1.
		((line beginsWith: '- ') and: [(line endsWith: ' -') and: [line size > 4]]) ifTrue: [
			| name |
			name := (line copyFrom: 3 to: line size - 2) trimBoth.
			name isEmpty ifFalse: [marks add: (Array with: name with: pos with: eol with: nil)]].
		pos := eol + 1].
	marks doWithIndex: [:m :i |
		m at: 4 put: (i < marks size ifTrue: [((marks at: i + 1) at: 2) - 1] ifFalse: [aText size])].
	^marks asArray
! !
