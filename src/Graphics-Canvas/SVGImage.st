Object subclass: #SVGImage
	instanceVariableNames: 'viewBox shapes'
	classVariableNames: 'NamedColors'
	package: 'Graphics-Canvas'!

SVGImage comment: 'I am an SVG document (the static subset logos and icons use) read into shapes I paint into a Form at any size: svg (viewBox, else width and height; fitted xMidYMid meet), g, path, rect, circle, ellipse, line, polyline and polygon; fill, stroke, stroke-width, stroke-linejoin, stroke-linecap, fill-rule, opacity, fill-opacity and stroke-opacity, as attributes or in style, inherited through groups; transform (matrix, translate, scale, rotate, skewX, skewY). Colors are #rgb, #rrggbb, rgb(), a few names, none and currentColor (the color given when painting). Not read: masks and clip paths (their content is left out, what they apply to is painted unclipped), gradients (painted in currentColor), text, images, use, CSS.

	(SVGImage fromString: (File readText: ''logo.svg'')) formWidth: 32 height: 32 color: Color white'!

!SVGImage methodsFor: 'initialization'!
setViewBox: aRectangle shapes: aCollection
	viewBox := aRectangle.
	shapes := aCollection
! !

!SVGImage methodsFor: 'accessing'!
viewBox
	^viewBox
!
shapes
	"Each a Dictionary: path (VectorPath, user units), fill, stroke (Colors, #currentColor or nil), strokeWidth, rule, join, cap."
	^shapes
! !

!SVGImage methodsFor: 'painting'!
formWidth: w height: h color: currentColor
	"A Form of w × h pixels with me fitted inside, centered; currentColor paints what is currentColor (and gradients)."
	| form painter s tx ty m |
	form := Form width: w height: h.
	painter := VectorPainter on: form.
	s := (w / viewBox width) min: (h / viewBox height).
	tx := (w - (viewBox width * s)) / 2.0 - (viewBox left * s).
	ty := (h - (viewBox height * s)) / 2.0 - (viewBox top * s).
	m := Array with: s with: 0 with: 0 with: s with: tx with: ty.
	shapes do: [:shape |
		| path |
		path := (shape at: #path) transformedBy: m.
		painter fill: path color: (self paint: (shape at: #fill) current: currentColor) rule: (shape at: #rule).
		painter stroke: path width: (shape at: #strokeWidth) * s color: (self paint: (shape at: #stroke) current: currentColor)
			join: (shape at: #join) cap: (shape at: #cap)].
	^form
!
paint: aPaint current: currentColor
	aPaint isNil ifTrue: [^nil].
	aPaint == #currentColor ifTrue: [^currentColor].
	^aPaint
! !

!SVGImage class methodsFor: 'instance creation'!
fromString: aString
	^SVGReader new read: aString
!
fromFile: aPath
	^self fromString: (File readText: aPath)
!
viewBox: aRectangle shapes: aCollection
	^self new setViewBox: aRectangle shapes: aCollection
! !

!SVGImage class methodsFor: 'colors'!
parseColor: aString
	"An SVG color: #rgb, #rrggbb, rgb(r, g, b), a name; none answers nil, currentColor #currentColor, url(...) (a gradient) #currentColor; nil if unknown."
	| s |
	s := aString trimBoth asLowercase.
	s = 'none' ifTrue: [^nil].
	(s = 'currentcolor' or: [s beginsWith: 'url(']) ifTrue: [^#currentColor].
	(s beginsWith: '#') ifTrue: [
		| hex |
		hex := s allButFirst.
		hex size = 3 ifTrue: [hex := hex inject: '' into: [:acc :c | acc, (String with: c with: c)]].
		hex size = 6 ifFalse: [^nil].
		^Color hex: (Integer readFrom: hex asUppercase base: 16)].
	(s beginsWith: 'rgb(') ifTrue: [
		| parts |
		parts := ((s copyFrom: 5 to: s size - 1) subStrings: ', ') collect: [:p |
			(p endsWith: '%') ifTrue: [(Number readFrom: p allButLast) * 2.55] ifFalse: [Number readFrom: p]].
		parts size >= 3 ifFalse: [^nil].
		^Color r: (parts at: 1) / 255.0 g: (parts at: 2) / 255.0 b: (parts at: 3) / 255.0].
	^self namedColors at: s ifAbsent: [nil]
!
namedColors
	^NamedColors ifNil: [
		NamedColors := Dictionary new.
		#('black' 16r000000 'white' 16rFFFFFF 'red' 16rFF0000 'green' 16r008000 'blue' 16r0000FF 'yellow' 16rFFFF00
			'gray' 16r808080 'grey' 16r808080 'orange' 16rFFA500 'purple' 16r800080 'silver' 16rC0C0C0)
			pairsDo: [:name :hex | NamedColors at: name put: (Color hex: hex)].
		NamedColors]
! !
