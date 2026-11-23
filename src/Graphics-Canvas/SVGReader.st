Object subclass: #SVGReader
	instanceVariableNames: 'source position stack shapes viewBox'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

SVGReader comment: 'I read SVG source into an SVGImage: a small XML tokenizer (tags, attributes, comments, processing instructions; character data ignored) and the elements SVGImage describes, each with the attributes it inherits from its groups (a stack of attribute Dictionaries and transforms).'!

!SVGReader methodsFor: 'reading'!
read: aString
	source := aString.
	position := 1.
	shapes := OrderedCollection new.
	stack := OrderedCollection with: self rootState.
	[self nextTag] whileTrue.
	viewBox isNil ifTrue: [viewBox := 0 @ 0 extent: 100 @ 100].
	^SVGImage viewBox: viewBox shapes: shapes asArray
!
rootState
	^Dictionary new
		at: #fill put: (Color hex: 0);
		at: #stroke put: nil;
		at: #strokeWidth put: 1.0;
		at: #rule put: #nonzero;
		at: #join put: #miter;
		at: #cap put: #butt;
		at: #opacity put: 1.0;
		at: #fillOpacity put: 1.0;
		at: #strokeOpacity put: 1.0;
		at: #matrix put: #(1 0 0 1 0 0);
		yourself
!
nextTag
	"Read up to and including the next tag and act on it; answer false at the end."
	| start name attrs selfClosing |
	start := source indexOf: $< startingAt: position.
	start = 0 ifTrue: [^false].
	(source copyFrom: start to: (start + 3 min: source size)) = '<!!--' ifTrue: [
		position := (source indexOfSubCollection: '-->' startingAt: start) + 3.
		position <= 3 ifTrue: [position := source size + 1].
		^true].
	('?!!' includes: (source at: start + 1)) ifTrue: [
		position := (source indexOf: $> startingAt: start) + 1.
		position = 1 ifTrue: [position := source size + 1].
		^true].
	(source at: start + 1) = $/ ifTrue: [
		position := (source indexOf: $> startingAt: start) + 1.
		name := (source copyFrom: start + 2 to: position - 2) trimBoth.
		self endElement: name.
		^true].
	position := start + 1.
	name := self readName.
	attrs := self readAttributes.
	selfClosing := (source at: position - 2) = $/.
	self startElement: name attributes: attrs.
	selfClosing ifTrue: [self endElement: name].
	^true
!
readName
	| s |
	s := position.
	[position <= source size and: [(source at: position) isSeparator not and: [('/>' includes: (source at: position)) not]]] whileTrue: [position := position + 1].
	^(source copyFrom: s to: position - 1) asLowercase
!
readAttributes
	"Attributes up to and including the tag's >."
	| attrs |
	attrs := Dictionary new.
	[[position <= source size and: [(source at: position) isSeparator]] whileTrue: [position := position + 1].
	 position <= source size and: [('/>' includes: (source at: position)) not]] whileTrue: [
		| s name quote e |
		s := position.
		[position <= source size and: [('= />' includes: (source at: position)) not and: [(source at: position) isSeparator not]]] whileTrue: [position := position + 1].
		name := source copyFrom: s to: position - 1.
		[position <= source size and: [(source at: position) isSeparator]] whileTrue: [position := position + 1].
		(position <= source size and: [(source at: position) = $=])
			ifTrue: [
				position := position + 1.
				[(source at: position) isSeparator] whileTrue: [position := position + 1].
				quote := source at: position.
				e := source indexOf: quote startingAt: position + 1.
				attrs at: name put: (self decode: (source copyFrom: position + 1 to: e - 1)).
				position := e + 1]
			ifFalse: [attrs at: name put: '']].
	[position <= source size and: [(source at: position) ~= $>]] whileTrue: [position := position + 1].
	position := position + 1.
	^attrs
!
decode: aString
	(aString includes: $&) ifFalse: [^aString].
	^((aString copyReplaceAll: '&lt;' with: '<') copyReplaceAll: '&gt;' with: '>')
		copyReplaceAll: '&amp;' with: '&'
! !

!SVGReader methodsFor: 'elements'!
skipped
	"Elements whose content is not painted where it stands."
	^#('defs' 'mask' 'clippath' 'title' 'desc' 'metadata' 'style' 'lineargradient' 'radialgradient' 'pattern' 'symbol' 'text' 'marker')
!
startElement: name attributes: attrs
	| state |
	(self skipped includes: name) ifTrue: [^self skipElement: name].
	state := self stateFor: attrs.
	name = 'svg' ifTrue: [
		viewBox isNil ifTrue: [viewBox := self viewBoxOf: attrs].
		stack add: state.
		^self].
	name = 'g' ifTrue: [^stack add: state].
	stack add: state.
	(self pathOf: name attributes: attrs) ifNotNil: [:path | self addShape: path state: state]
!
endElement: name
	(name = 'svg' or: [name = 'g' or: [#('path' 'rect' 'circle' 'ellipse' 'line' 'polyline' 'polygon') includes: name]])
		ifTrue: [stack size > 1 ifTrue: [stack removeLast]]
!
skipElement: name
	"Skip to the end of this element (nested ones of the same name included); a self-closing one is done."
	| depth |
	(source at: position - 2) = $/ ifTrue: [^self].
	depth := 1.
	[depth > 0 and: [position <= source size]] whileTrue: [
		| start isEnd tagName |
		start := source indexOf: $< startingAt: position.
		start = 0 ifTrue: [position := source size + 1. ^self].
		isEnd := (source at: start + 1) = $/.
		position := isEnd ifTrue: [start + 2] ifFalse: [start + 1].
		tagName := self readName.
		position := (source indexOf: $> startingAt: position) + 1.
		tagName = name ifTrue: [
			isEnd
				ifTrue: [depth := depth - 1]
				ifFalse: [(source at: position - 2) = $/ ifFalse: [depth := depth + 1]]]]
!
viewBoxOf: attrs
	| v w h |
	v := attrs at: 'viewBox' ifAbsent: [nil].
	v notNil ifTrue: [
		| n |
		n := (v subStrings: ', ') collect: [:each | VectorPath parseNumber: each].
		n size = 4 ifTrue: [^(n at: 1) @ (n at: 2) extent: (n at: 3) @ (n at: 4)]].
	w := self length: (attrs at: 'width' ifAbsent: ['100']).
	h := self length: (attrs at: 'height' ifAbsent: ['100']).
	^0 @ 0 extent: w @ h
!
length: aString
	"A length in user units: a number, ignoring px (em and % are taken as 100)."
	| s |
	s := aString trimBoth.
	(s endsWith: 'px') ifTrue: [s := s allButLast: 2].
	^[VectorPath parseNumber: s] on: Error do: [:e | e return: 100]
!
pathOf: name attributes: attrs
	| num |
	num := [:key | [VectorPath parseNumber: (attrs at: key ifAbsent: ['0'])] on: Error do: [:e | e return: 0.0]].
	name = 'path' ifTrue: [^[VectorPath fromSVG: (attrs at: 'd' ifAbsent: [''])] on: Error do: [:e | e return: nil]].
	name = 'rect' ifTrue: [
		| rx ry |
		rx := attrs at: 'rx' ifAbsent: [nil].
		ry := attrs at: 'ry' ifAbsent: [nil].
		rx := rx isNil ifTrue: [ry isNil ifTrue: [0] ifFalse: [num value: 'ry']] ifFalse: [num value: 'rx'].
		ry := ry isNil ifTrue: [rx] ifFalse: [num value: 'ry'].
		^VectorPath rectX: (num value: 'x') y: (num value: 'y') width: (num value: 'width') height: (num value: 'height') rx: rx ry: ry].
	name = 'circle' ifTrue: [^VectorPath ellipseX: (num value: 'cx') y: (num value: 'cy') rx: (num value: 'r') ry: (num value: 'r')].
	name = 'ellipse' ifTrue: [^VectorPath ellipseX: (num value: 'cx') y: (num value: 'cy') rx: (num value: 'rx') ry: (num value: 'ry')].
	name = 'line' ifTrue: [^VectorPath polygon: (Array with: (num value: 'x1') with: (num value: 'y1') with: (num value: 'x2') with: (num value: 'y2')) closed: false].
	(name = 'polyline' or: [name = 'polygon']) ifTrue: [
		^VectorPath
			polygon: (((attrs at: 'points' ifAbsent: ['']) subStrings: ', ') collect: [:each | VectorPath parseNumber: each]) asArray
			closed: name = 'polygon'].
	^nil
!
addShape: aPath state: state
	| fill stroke |
	fill := self paint: (state at: #fill) alpha: (state at: #fillOpacity) * (state at: #opacity).
	stroke := self paint: (state at: #stroke) alpha: (state at: #strokeOpacity) * (state at: #opacity).
	(fill isNil and: [stroke isNil]) ifTrue: [^self].
	shapes add: (Dictionary new
		at: #path put: (aPath transformedBy: (state at: #matrix));
		at: #fill put: fill;
		at: #stroke put: stroke;
		at: #strokeWidth put: (state at: #strokeWidth) * (self scaleOf: (state at: #matrix));
		at: #rule put: (state at: #rule);
		at: #join put: (state at: #join);
		at: #cap put: (state at: #cap);
		yourself)
!
paint: aPaint alpha: a
	"aPaint with the opacity a; currentColor stays as it is (it is only known when painting)."
	(aPaint isNil or: [aPaint == #currentColor]) ifTrue: [^aPaint].
	^a >= 1 ifTrue: [aPaint] ifFalse: [aPaint alpha: aPaint alpha * a]
!
scaleOf: m
	^(((m at: 1) * (m at: 4)) - ((m at: 2) * (m at: 3))) abs sqrt
! !

!SVGReader methodsFor: 'attributes'!
stateFor: attrs
	"The inherited state with attrs (and their style declarations) applied."
	| state all |
	state := stack last copy.
	all := Dictionary new.
	attrs keysAndValuesDo: [:k :v | all at: k put: v].
	(attrs at: 'style' ifAbsent: [nil]) ifNotNil: [:style |
		(style subStrings: ';') do: [:decl |
			| i |
			i := decl indexOf: $:.
			i > 0 ifTrue: [all at: (decl first: i - 1) trimBoth put: (decl allButFirst: i) trimBoth]]].
	all keysAndValuesDo: [:k :v | self apply: k value: v to: state].
	state at: #opacity put: (stack last at: #opacity) * (self number: (all at: 'opacity' ifAbsent: ['1']) default: 1.0).
	^state
!
apply: name value: v to: state
	name = 'fill' ifTrue: [^state at: #fill put: (SVGImage parseColor: v)].
	name = 'stroke' ifTrue: [^state at: #stroke put: (SVGImage parseColor: v)].
	name = 'stroke-width' ifTrue: [^state at: #strokeWidth put: (self number: v default: 1.0)].
	name = 'fill-rule' ifTrue: [^state at: #rule put: (v trimBoth = 'evenodd' ifTrue: [#evenodd] ifFalse: [#nonzero])].
	name = 'stroke-linejoin' ifTrue: [^state at: #join put: v trimBoth asSymbol].
	name = 'stroke-linecap' ifTrue: [^state at: #cap put: v trimBoth asSymbol].
	name = 'fill-opacity' ifTrue: [^state at: #fillOpacity put: (self number: v default: 1.0)].
	name = 'stroke-opacity' ifTrue: [^state at: #strokeOpacity put: (self number: v default: 1.0)].
	name = 'transform' ifTrue: [^state at: #matrix put: (self multiply: (state at: #matrix) by: (self transformOf: v))]
!
number: aString default: aNumber
	^[VectorPath parseNumber: aString trimBoth] on: Error do: [:e | e return: aNumber]
!
transformOf: aString
	"The matrix of an SVG transform list (applied left to right)."
	| m rest open close |
	m := #(1 0 0 1 0 0).
	rest := aString.
	[open := rest indexOf: $(.
	 close := rest indexOf: $).
	 open > 0 and: [close > open]] whileTrue: [
		| name args t |
		name := (rest first: open - 1) trimBoth asLowercase.
		name := (name subStrings: ', ') isEmpty ifTrue: [''] ifFalse: [(name subStrings: ', ') last].
		args := ((rest copyFrom: open + 1 to: close - 1) subStrings: ', ') collect: [:each | VectorPath parseNumber: each].
		t := self matrixNamed: name args: args.
		m := self multiply: m by: t.
		rest := rest allButFirst: close].
	^m
!
matrixNamed: name args: args
	| a c s cx cy |
	name = 'matrix' ifTrue: [^args size = 6 ifTrue: [args asArray] ifFalse: [#(1 0 0 1 0 0)]].
	name = 'translate' ifTrue: [^Array with: 1 with: 0 with: 0 with: 1 with: (args at: 1 ifAbsent: [0]) with: (args at: 2 ifAbsent: [0])].
	name = 'scale' ifTrue: [^Array with: (args at: 1 ifAbsent: [1]) with: 0 with: 0 with: (args at: 2 ifAbsent: [args at: 1 ifAbsent: [1]]) with: 0 with: 0].
	name = 'rotate' ifTrue: [
		a := (args at: 1 ifAbsent: [0]) degreesToRadians.
		c := a cos. s := a sin.
		cx := args at: 2 ifAbsent: [0]. cy := args at: 3 ifAbsent: [0].
		^self multiply: (self multiply: (Array with: 1 with: 0 with: 0 with: 1 with: cx with: cy) by: (Array with: c with: s with: s negated with: c with: 0 with: 0))
			by: (Array with: 1 with: 0 with: 0 with: 1 with: cx negated with: cy negated)].
	name = 'skewx' ifTrue: [^Array with: 1 with: 0 with: (args at: 1 ifAbsent: [0]) degreesToRadians tan with: 1 with: 0 with: 0].
	name = 'skewy' ifTrue: [^Array with: 1 with: (args at: 1 ifAbsent: [0]) degreesToRadians tan with: 0 with: 1 with: 0 with: 0].
	^#(1 0 0 1 0 0)
!
multiply: m by: n
	"m applied after n: (m n) p = m (n p)."
	^Array
		with: ((m at: 1) * (n at: 1)) + ((m at: 3) * (n at: 2))
		with: ((m at: 2) * (n at: 1)) + ((m at: 4) * (n at: 2))
		with: ((m at: 1) * (n at: 3)) + ((m at: 3) * (n at: 4))
		with: ((m at: 2) * (n at: 3)) + ((m at: 4) * (n at: 4))
		with: ((m at: 1) * (n at: 5)) + ((m at: 3) * (n at: 6)) + (m at: 5)
		with: ((m at: 2) * (n at: 5)) + ((m at: 4) * (n at: 6)) + (m at: 6)
! !
