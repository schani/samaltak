Object subclass: #ChunkFile
	instanceVariableNames: 'text chunks sections methods'
	classVariableNames: ''
	package: 'Compiler'!

ChunkFile comment: 'I am the text of a chunk-format source file (src/<package>/<Class>.st): definitions and comments as top-level chunks, methods in sections "!!X methodsFor: ''category''!!" ... "!! !!". I find and change single chunks in place, so a file stays byte-for-byte the same except for the method, comment or definition that changed (SourceFiler uses me for the browser''s accept).

chunks: Arrays {start. stop} of each chunk''s raw text (character positions, delimiters excluded; stop + 1 is its terminating !!). sections: Arrays {className. isMeta. category. headerChunk. endChunk}. methods: Arrays {selector. section. chunk}.'!

!ChunkFile methodsFor: 'initialization'!
setText: aString
	text := aString.
	self parse
! !

!ChunkFile methodsFor: 'accessing'!
text
	^text
!
chunkCount
	^chunks size
!
rawChunk: index
	| c |
	c := chunks at: index.
	^text copyFrom: c first to: c last
!
chunkBody: index
	"The chunk's text without the doubled !!s and surrounding white space (what the bootstrapper compiles)."
	^(self unescape: (self rawChunk: index)) trimBoth
! !

!ChunkFile methodsFor: 'parsing'!
parse
	| i n start mode |
	chunks := OrderedCollection new.
	i := 1.
	n := text size.
	start := 1.
	[i <= n] whileTrue: [
		(text at: i) = $!!
			ifTrue: [
				(i < n and: [(text at: i + 1) = $!!])
					ifTrue: [i := i + 2]
					ifFalse: [
						chunks add: (Array with: start with: i - 1).
						start := i + 1.
						i := i + 1]]
			ifFalse: [i := i + 1]].
	(start <= n and: [((text copyFrom: start to: n) allSatisfy: [:c | c isSeparator]) not])
		ifTrue: [chunks add: (Array with: start with: n)].
	sections := OrderedCollection new.
	methods := OrderedCollection new.
	mode := nil.
	1 to: chunks size do: [:k |
		| body header |
		body := self chunkBody: k.
		mode isNil
			ifTrue: [
				header := self parseHeader: body.
				header isNil ifFalse: [
					mode := Array with: header first with: (header at: 2) with: header last with: k with: nil.
					sections add: mode]]
			ifFalse: [
				body isEmpty
					ifTrue: [mode at: 5 put: k. mode := nil]
					ifFalse: [methods add: (Array with: (self class selectorOf: body) with: sections size with: k)]]]
!
parseHeader: aString
	"{className. isMeta. category} of a methodsFor: header, or nil."
	| words rest cat i |
	(aString includesSubstring: 'methodsFor:') ifFalse: [^nil].
	words := aString substrings.
	words size < 3 ifTrue: [^nil].
	(words at: 2) = 'class'
		ifTrue: [(words at: 3) = 'methodsFor:' ifFalse: [^nil]]
		ifFalse: [(words at: 2) = 'methodsFor:' ifFalse: [^nil]].
	i := aString indexOf: $'.
	i = 0 ifTrue: [^nil].
	rest := aString copyFrom: i + 1 to: aString size.
	cat := WriteStream on: (String new: 40).
	i := 1.
	[i <= rest size] whileTrue: [
		(rest at: i) = $'
			ifTrue: [
				(i < rest size and: [(rest at: i + 1) = $'])
					ifTrue: [cat nextPut: $'. i := i + 2]
					ifFalse: [i := rest size + 1]]
			ifFalse: [cat nextPut: (rest at: i). i := i + 1]].
	^Array with: words first with: (words at: 2) = 'class' with: cat contents
!
unescape: aString
	(aString includesSubstring: '!!!!') ifFalse: [^aString].
	^aString copyReplaceAll: '!!!!' with: '!!'
!
escape: aString
	(aString includes: $!!) ifFalse: [^aString].
	^aString copyReplaceAll: '!!' with: '!!!!'
! !

!ChunkFile methodsFor: 'queries'!
methodEntryFor: aSelector className: aString meta: aBoolean
	^methods detect: [:m |
		| s |
		s := sections at: (m at: 2).
		m first = aSelector and: [s first = aString and: [(s at: 2) = aBoolean]]] ifNone: [nil]
!
sourceOf: aSelector className: aString meta: aBoolean
	| m |
	m := self methodEntryFor: aSelector className: aString meta: aBoolean.
	^m isNil ifTrue: [nil] ifFalse: [self chunkBody: m last]
!
sectionFor: aString meta: aBoolean category: aCategory
	^sections detect: [:s | s first = aString and: [(s at: 2) = aBoolean and: [(s at: 3) = aCategory and: [(s at: 5) notNil]]]] ifNone: [nil]
!
definitionChunkFor: aString
	"The index of the class definition chunk of class aString, or nil."
	1 to: chunks size do: [:k |
		| body words |
		(self isInSection: k) ifFalse: [
			body := self chunkBody: k.
			words := body substrings.
			(words size >= 2 and: [((words at: 2) endsWith: 'ubclass:') and: [words size >= 3 and: [(words at: 3) = ('#', aString)]]])
				ifTrue: [^k]]].
	^nil
!
commentChunkFor: aString
	1 to: chunks size do: [:k |
		(self isInSection: k) ifFalse: [
			((self chunkBody: k) beginsWith: aString, ' comment:') ifTrue: [^k]]].
	^nil
!
isInSection: k
	^sections anySatisfy: [:s | k >= (s at: 4) and: [(s at: 5) isNil or: [k <= (s at: 5)]]]
! !

!ChunkFile methodsFor: 'editing'!
replaceChunk: index with: aString
	"Replace the chunk's body by aString (escaped), keeping the white space around it."
	| c raw lead trail newRaw |
	c := chunks at: index.
	raw := self rawChunk: index.
	lead := 0.
	[lead < raw size and: [(raw at: lead + 1) isSeparator]] whileTrue: [lead := lead + 1].
	trail := 0.
	[trail < (raw size - lead) and: [(raw at: raw size - trail) isSeparator]] whileTrue: [trail := trail + 1].
	newRaw := (raw copyFrom: 1 to: lead), (self escape: aString), (raw copyFrom: raw size - trail + 1 to: raw size).
	self setText: (text copyReplaceFrom: c first to: c last with: newRaw)
!
insert: aString after: chunkIndex
	"Insert aString right after the !! that ends chunk chunkIndex."
	| pos |
	pos := (chunks at: chunkIndex) last + 1.
	self setText: (text copyReplaceFrom: pos + 1 to: pos with: aString)
!
removeChunk: index
	"Remove the chunk and its terminating !!."
	| c |
	c := chunks at: index.
	self setText: (text copyReplaceFrom: c first to: (c last + 1 min: text size) with: '')
!
lf
	^String with: Character lf
!
putMethod: aSource selector: aSelector className: aString meta: aBoolean category: aCategory
	"Make the file hold aSource as the method aSelector in aCategory. Answer whether the text changed."
	| old entry section oldSection |
	old := text.
	entry := self methodEntryFor: aSelector className: aString meta: aBoolean.
	entry notNil ifTrue: [
		oldSection := sections at: (entry at: 2).
		(oldSection at: 3) = aCategory ifTrue: [
			(self chunkBody: entry last) = aSource ifFalse: [self replaceChunk: entry last with: aSource].
			^text ~= old].
		self removeMethodEntry: entry].
	section := self sectionFor: aString meta: aBoolean category: aCategory.
	section isNil
		ifTrue: [self appendSection: aSource className: aString meta: aBoolean category: aCategory]
		ifFalse: [self insert: self lf, (self escape: aSource), self lf, '!!' after: (section at: 5) - 1].
	^text ~= old
!
removeMethodEntry: anEntry
	"Remove a method chunk; remove its section when it was the only method."
	| section count |
	section := sections at: (anEntry at: 2).
	count := (methods select: [:m | (m at: 2) = (anEntry at: 2)]) size.
	count > 1 ifTrue: [^self removeChunk: anEntry last].
	"The header is preceded by the (white space) chunk its opening !! ends: remove from there."
	self setText: (text copyReplaceFrom: ((section at: 4) > 1 ifTrue: [(chunks at: (section at: 4) - 1) first] ifFalse: [1])
		to: ((chunks at: (section at: 5)) last + 1 min: text size) with: '')
!
appendSection: aSource className: aString meta: aBoolean category: aCategory
	| header s |
	header := String new: 60 streamContents: [:out |
		out nextPut: $!!; nextPutAll: aString.
		aBoolean ifTrue: [out nextPutAll: ' class'].
		out nextPutAll: ' methodsFor: '; print: aCategory; nextPut: $!!].
	s := text.
	(s notEmpty and: [s last ~= Character lf]) ifTrue: [s := s, self lf].
	s notEmpty ifTrue: [s := s, self lf].
	self setText: s, header, self lf, (self escape: aSource), self lf, '!! !!', self lf
!
putDefinition: aString className: className
	"Replace (or add, at the top) the class definition chunk. Answer whether the text changed."
	| old k |
	old := text.
	k := self definitionChunkFor: className.
	k isNil
		ifTrue: [self setText: (self escape: aString), '!!', self lf, (text isEmpty ifTrue: [''] ifFalse: [self lf]), text]
		ifFalse: [(self chunkBody: k) = aString ifFalse: [self replaceChunk: k with: aString]].
	^text ~= old
!
putComment: aString className: className
	"Replace (or add after the definition) the class comment chunk. Answer whether the text changed."
	| old chunk k def |
	old := text.
	chunk := className, ' comment: ', aString printString.
	k := self commentChunkFor: className.
	k isNil
		ifTrue: [
			def := self definitionChunkFor: className.
			def isNil
				ifTrue: [self setText: (self escape: chunk), '!!', self lf, text]
				ifFalse: [self insert: self lf, self lf, (self escape: chunk), '!!' after: def]]
		ifFalse: [(self chunkBody: k) = chunk ifFalse: [self replaceChunk: k with: chunk]].
	^text ~= old
! !

!ChunkFile class methodsFor: 'instance creation'!
on: aString
	^self new setText: aString
! !

!ChunkFile class methodsFor: 'selectors'!
selectorOf: aMethodSource
	"The selector of a method's source, from its pattern (unary, binary or keywords)."
	| s c word sel |
	s := ReadStream on: aMethodSource.
	[s atEnd not and: [s peek isWhiteSpace]] whileTrue: [s next].
	s atEnd ifTrue: [^#''].
	c := s peek.
	(c isLetter or: [c = $_]) ifFalse: [
		sel := WriteStream on: (String new: 4).
		[s atEnd not and: ['+-*/\<>=~@%|&?,' includes: s peek]] whileTrue: [sel nextPut: s next].
		^sel contents asSymbol].
	sel := WriteStream on: (String new: 20).
	[word := self readWordFrom: s.
	 (s atEnd not and: [s peek = $:])
		ifTrue: [
			s next.
			sel nextPutAll: word; nextPut: $:.
			[s atEnd not and: [s peek isWhiteSpace]] whileTrue: [s next].
			self readWordFrom: s.
			[s atEnd not and: [s peek isWhiteSpace]] whileTrue: [s next].
			s atEnd not and: [s peek isLetter and: [self keywordFollowsIn: s]]]
		ifFalse: [
			sel position = 0 ifTrue: [sel nextPutAll: word].
			false]] whileTrue.
	^sel contents asSymbol
!
readWordFrom: aStream
	| w |
	w := WriteStream on: (String new: 16).
	[aStream atEnd not and: [aStream peek isLetter or: [aStream peek isDigit or: [aStream peek = $_]]]] whileTrue: [w nextPut: aStream next].
	^w contents
!
keywordFollowsIn: aStream
	"Whether a keyword (word followed by a colon) starts at aStream's position (the position is kept)."
	| p result |
	p := aStream position.
	self readWordFrom: aStream.
	result := aStream atEnd not and: [aStream peek = $:].
	aStream position: p.
	^result
! !
