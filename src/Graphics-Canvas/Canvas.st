Object subclass: #Canvas
	instanceVariableNames: 'bytes next extent scale originX originY clipLeft clipTop clipRight clipBottom scissor opacity batches batch texture building fresh'
	classVariableNames: 'GlyphGeneration ReplaysSegments'
	package: 'Graphics-Canvas'!

Canvas comment: 'I am the drawing API widgets see. Coordinates are points (Numbers, Floats welcome); I convert them to device pixels (scale per point), snap rectangles and text baselines to whole device pixels (so a 1-point hairline is exactly 2 device pixels at scale 2) and record quads into vertex bytes. "displayList" freezes what was drawn into a DisplayList for a Renderer.

	| canvas |
	canvas := Canvas extent: 400@300 scale: 2.
	canvas fillRect: (0@0 extent: 400@300) color: Color white.
	canvas drawString: ''Hello'' at: 10@10 font: Font ui color: Color black.
	canvas displayList

Text is drawn glyph by glyph from precomputed vertex templates (GlyphInfo), in Smalltalk, a color emoji as a quad per layer of its color glyphs (Font>>colorClusterEndAt:in:to:); a new batch starts only when the texture source or the clip changes.

Retained drawing: "record: aBlock" answers a DisplaySegment of what aBlock drew; "replay: aSegment" on a later canvas draws it again (copying its vertices, moved by whole device pixels) when the drawing state matches the recorded one, and answers false otherwise, so the caller draws anew. Segments recorded or replayed inside a record: become its parts. "drawFresh: aBlock" refuses every replay inside aBlock (redraw everything); "noteVolatile" marks the segments being recorded as never replayable (they show values computed while drawing). Canvas replaysSegments: false turns replaying off everywhere (to compare with drawing everything anew).'!

!Canvas methodsFor: 'initialization'!
setExtent: aPoint scale: aNumber capacity: byteCount
	^self setExtent: aPoint scale: aNumber buffer: (ByteArray new: byteCount)
!
setExtent: aPoint scale: aNumber buffer: aByteArray
	extent := aPoint.
	scale := aNumber.
	bytes := aByteArray.
	next := 1.
	originX := 0.
	originY := 0.
	clipLeft := 0.
	clipTop := 0.
	clipRight := (aPoint x * aNumber) ceiling.
	clipBottom := (aPoint y * aNumber) ceiling.
	scissor := nil.
	opacity := 1.
	batches := OrderedCollection new.
	texture := nil.
	batch := DisplayBatch texture: nil scissor: nil first: 0.
	building := OrderedCollection new.
	fresh := false
! !

!Canvas methodsFor: 'private'!
setOriginX: x y: y clipLeft: l top: t right: r bottom: b scissor: anArrayOrNil opacity: aNumber
	originX := x.
	originY := y.
	clipLeft := l.
	clipTop := t.
	clipRight := r.
	clipBottom := b.
	opacity := aNumber.
	self setScissor: anArrayOrNil
! !

!Canvas methodsFor: 'accessing'!
extent
	^extent
!
scale
	^scale
!
origin
	"The current translation in points."
	^originX @ originY
!
clipRect
	"The current clip in my coordinates (points)."
	^Rectangle
		left: clipLeft / scale - originX right: clipRight / scale - originX
		top: clipTop / scale - originY bottom: clipBottom / scale - originY
!
opacity
	^opacity
!
vertexCount
	^next - 1 // 40
! !

!Canvas methodsFor: 'drawing'!
fillRect: aRectangle color: aColor
	self fillLeft: aRectangle left top: aRectangle top right: aRectangle right bottom: aRectangle bottom color: aColor
!
fillLeft: left top: top right: right bottom: bottom color: aColor
	"Fill the rectangle (points, edges snapped to device pixels)."
	| x0 y0 x1 y1 |
	x0 := self deviceX: left.
	x1 := self deviceX: right.
	y0 := self deviceY: top.
	y1 := self deviceY: bottom.
	(x1 <= clipLeft or: [x0 >= clipRight or: [y1 <= clipTop or: [y0 >= clipBottom]]]) ifTrue: [^self].
	(x1 <= x0 or: [y1 <= y0]) ifTrue: [^self].
	self quadX0: x0 y0: y0 x1: x1 y1: y1 color: (self pack: aColor) mode: 0
!
strokeRect: aRectangle color: aColor width: lineWidth
	"Draw a frame of lineWidth points inside aRectangle (like a CSS border)."
	| l t r b w |
	l := aRectangle left.
	t := aRectangle top.
	r := aRectangle right.
	b := aRectangle bottom.
	w := lineWidth.
	self fillLeft: l top: t right: r bottom: t + w color: aColor.
	self fillLeft: l top: b - w right: r bottom: b color: aColor.
	self fillLeft: l top: t + w right: l + w bottom: b - w color: aColor.
	self fillLeft: r - w top: t + w right: r bottom: b - w color: aColor
!
line: startPoint to: endPoint color: aColor width: lineWidth
	"Horizontal and vertical lines cover the pixels to the right of / below the line from startPoint to endPoint (so line: 0@10 to: 100@10 width: 1 fills the row of points 10..11); other lines are antialiased quads centered on the line."
	| x0 y0 x1 y1 |
	x0 := startPoint x.
	y0 := startPoint y.
	x1 := endPoint x.
	y1 := endPoint y.
	y0 = y1 ifTrue: [^self fillLeft: (x0 min: x1) top: y0 right: (x0 max: x1) bottom: y0 + lineWidth color: aColor].
	x0 = x1 ifTrue: [^self fillLeft: x0 top: (y0 min: y1) right: x0 + lineWidth bottom: (y0 max: y1) color: aColor].
	self antialiasedLineX0: x0 + originX * scale y0: y0 + originY * scale x1: x1 + originX * scale y1: y1 + originY * scale
		width: lineWidth * scale color: (self pack: aColor)
!
pattern: aSymbol in: aRectangle
	self pattern: aSymbol in: aRectangle color: Color black
!
pattern: aSymbol in: aRectangle color: aColor
	"Fill aRectangle with a procedural pattern, computed per device pixel from the rectangle's top-left: #halftone (the Blue Book desk: a 1-point dot in every 2×2-point cell), #stripes (1-point horizontal lines, 1 point apart: focused title bars), #verticalStripes, #diagonalStripes (4-point bands at 45 degrees: busy bars), #checkerboard."
	| cell mode variant |
	cell := scale.
	mode := DisplayList modeStripes.
	variant := 0.
	aSymbol == #halftone ifTrue: [mode := DisplayList modeHalftone].
	aSymbol == #checkerboard ifTrue: [mode := DisplayList modeHalftone. variant := 1].
	aSymbol == #verticalStripes ifTrue: [variant := 1].
	aSymbol == #diagonalStripes ifTrue: [variant := 2. cell := 4 * scale].
	self pattern: mode variant: variant cell: cell in: aRectangle color: aColor
!
pattern: mode variant: variant cell: cell in: aRectangle color: aColor
	| x0 y0 x1 y1 |
	x0 := self deviceX: aRectangle left.
	x1 := self deviceX: aRectangle right.
	y0 := self deviceY: aRectangle top.
	y1 := self deviceY: aRectangle bottom.
	(x1 <= clipLeft or: [x0 >= clipRight or: [y1 <= clipTop or: [y0 >= clipBottom]]]) ifTrue: [^self].
	(x1 <= x0 or: [y1 <= y0]) ifTrue: [^self].
	self quadX0: x0 y0: y0 x1: x1 y1: y1 color: (self pack: aColor)
		mode: mode + ((cell rounded max: 1) bitShift: 8) + (variant bitShift: 16)
!
image: anImage in: aRectangle
	"Draw anImage (a Form or a Surface) scaled into aRectangle."
	self image: anImage from: (0 @ 0 extent: anImage width @ anImage height) in: aRectangle
!
image: anImage from: sourceRect in: aRectangle
	"Draw the part sourceRect (pixels of anImage) scaled into aRectangle (points)."
	| x0 y0 x1 y1 p |
	x0 := self deviceX: aRectangle left.
	x1 := self deviceX: aRectangle right.
	y0 := self deviceY: aRectangle top.
	y1 := self deviceY: aRectangle bottom.
	(x1 <= clipLeft or: [x0 >= clipRight or: [y1 <= clipTop or: [y0 >= clipBottom]]]) ifTrue: [^self].
	(x1 <= x0 or: [y1 <= y0]) ifTrue: [^self].
	self useTexture: anImage.
	p := self reserveQuad.
	bytes float32At: p put: x0.
	bytes float32At: p + 4 put: y0.
	bytes float32At: p + 8 put: x1.
	bytes float32At: p + 12 put: y1.
	bytes uint32At: p + 16 put: sourceRect left rounded + (sourceRect top rounded bitShift: 16).
	bytes uint32At: p + 20 put: sourceRect right rounded + (sourceRect bottom rounded bitShift: 16).
	bytes uint32At: p + 24 put: (self pack: Color white).
	bytes uint32At: p + 28 put: DisplayList modeImage.
	self replicateVertexAt: p
!
record: aBlock
	"Draw aBlock and answer a DisplaySegment of what it drew, for replay: on a later canvas. If aBlock does not complete (an exception, or another Process terminates mine wherever it is, as Window>>close does) there is no segment: what was drawn belongs to the segment recorded around this one."
	| segment |
	self closeRun.
	segment := DisplaySegment scale: scale opacity: opacity deviceX: originX * scale deviceY: originY * scale
		clipLeft: clipLeft top: clipTop right: clipRight bottom: clipBottom.
	segment glyphGeneration: GlyphGeneration.
	segment runStart: next - 1 // 40.
	building addLast: segment.
	aBlock ifCurtailed: [
		"Only drop segment and those left on it: a Process terminated between two stores leaves their parts and runs half made, not to be read."
		[building isEmpty or: [building removeLast == segment]] whileFalse].
	self closeRun.
	building removeLast.
	segment finish.
	building isEmpty
		ifTrue: [segment compactVertices]
		ifFalse: [building last addPart: segment dx: 0 dy: 0; runStart: next - 1 // 40].
	^segment
! !

!Canvas methodsFor: 'text'!
drawString: aString at: aPoint font: aFont color: aColor
	"Draw aString with the top-left of its line box (aFont lineHeight high) at aPoint."
	self drawString: aString from: 1 to: aString size at: aPoint font: aFont color: aColor
!
drawString: aString from: start to: stop at: aPoint font: aFont color: aColor
	| string baseline penX color glyphs advances phases b cp adv q xi phase info template p limit i j |
	aFont scale = scale ifFalse: [
		^self drawString: aString from: start to: stop at: aPoint font: (aFont atScale: scale) color: aColor].
	stop < start ifTrue: [^self].
	string := aFont isUppercase ifTrue: [aString asUppercase] ifFalse: [aString].
	baseline := self deviceY: aPoint y + aFont baselineOffset.
	(baseline - (aFont lineHeight * scale) >= clipBottom or: [baseline + (aFont lineHeight * scale) <= clipTop]) ifTrue: [^self].
	penX := (aPoint x + originX * scale) asFloat.
	limit := clipRight + 0.0.
	color := self pack: aColor.
	glyphs := aFont glyphTable.
	advances := aFont deviceAdvances.
	phases := aFont phases.
	i := start.
	[i <= stop] whileTrue: [
		penX >= limit ifTrue: [^self].
		cp := (string at: i) value.
		((cp >= 16r203C or: [i < stop and: [(string at: i + 1) value >= 16r203C]])
				and: [(j := aFont colorClusterEndAt: i in: string to: stop) > 0])
			ifTrue: [
				penX := self drawColorGlyphs: (aFont colorGlyphsFrom: i to: j in: string) at: penX baseline: baseline font: aFont color: aColor.
				i := j + 1]
			ifFalse: [
				q := penX * phases + 0.5.
				q := q >= 0 ifTrue: [q truncated] ifFalse: [q floor].
				xi := q // phases.
				phase := q - (xi * phases).
				cp < 256
					ifTrue: [
						adv := advances at: cp + 1.
						(info := glyphs at: cp * phases + phase + 1) isNil ifTrue: [info := aFont glyphForCodePoint: cp phase: phase]]
					ifFalse: [
						adv := aFont deviceAdvanceOf: cp.
						info := aFont glyphForCodePoint: cp phase: phase].
				(template := info template) isNil ifFalse: [
					info page == texture ifFalse: [self useTexture: info page].
					(p := next) + 239 > bytes size ifTrue: [self grow].
					b := bytes.
					b replaceFrom: p to: p + 39 with: template startingAt: 1.
					b uint32At: p + 24 put: color.
					b float32At: p + 32 put: xi.
					b float32At: p + 36 put: baseline.
					b replaceFrom: p + 40 to: p + 79 with: b startingAt: p.
					b replaceFrom: p + 80 to: p + 159 with: b startingAt: p.
					b replaceFrom: p + 160 to: p + 239 with: b startingAt: p.
					next := p + 240].
				penX := penX + adv.
				i := i + 1]]
!
drawColorGlyphs: anArray at: x baseline: baseline font: aFont color: aColor
	"Color emoji (Font>>colorClusterEndAt:in:to:) from the pen x (device pixels; at whole pixels): a quad per layer in its palette color with aColor's alpha, aColor itself for the text color layers. Answer the pen after them."
	| penX text alpha xi layers info c p |
	penX := x.
	text := self pack: aColor.
	alpha := aColor alpha * opacity.
	anArray do: [:glyph |
		xi := (penX + 0.5) floor.
		layers := aFont colorLayersOf: glyph.
		1 to: layers size by: 2 do: [:k |
			info := aFont colorLayerGlyph: (layers at: k).
			c := layers at: k + 1.
			info isBlank ifFalse: [
				info page == texture ifFalse: [self useTexture: info page].
				p := self reserveQuad.
				bytes replaceFrom: p to: p + 39 with: info template startingAt: 1.
				bytes uint32At: p + 24 put: (c isNil ifTrue: [text] ifFalse: [c premultipliedRGBA8Times: alpha]).
				bytes float32At: p + 32 put: xi.
				bytes float32At: p + 36 put: baseline.
				self replicateVertexAt: p]].
		penX := penX + (aFont deviceAdvanceOfColorGlyph: glyph)].
	^penX
!
drawString: aString in: aRectangle font: aFont color: aColor align: alignSymbol
	"Draw aString in one line, vertically centered in aRectangle, aligned #left, #center or #right."
	| x y |
	x := aRectangle left.
	alignSymbol == #center ifTrue: [x := aRectangle left + (aRectangle width - (aFont widthOf: aString) / 2)].
	alignSymbol == #right ifTrue: [x := aRectangle right - (aFont widthOf: aString)].
	y := aRectangle top + (aRectangle height - aFont lineHeight / 2).
	self drawString: aString at: x @ y font: aFont color: aColor
!
measure: aString font: aFont
	"Answer the size (points) of aString's line box."
	^(aFont widthOf: aString) @ aFont lineHeight
! !

!Canvas methodsFor: 'state'!
translateBy: aPoint during: aBlock
	"Draw with the origin moved by aPoint."
	| ox oy |
	ox := originX.
	oy := originY.
	originX := originX + aPoint x.
	originY := originY + aPoint y.
	^aBlock ensure: [originX := ox. originY := oy]
!
clip: aRectangle during: aBlock
	"Draw only inside aRectangle (intersected with the current clip)."
	| l t r b oldScissor |
	l := clipLeft.
	t := clipTop.
	r := clipRight.
	b := clipBottom.
	oldScissor := scissor.
	clipLeft := (self deviceX: aRectangle left) max: l.
	clipTop := (self deviceY: aRectangle top) max: t.
	clipRight := (self deviceX: aRectangle right) min: r.
	clipBottom := (self deviceY: aRectangle bottom) min: b.
	clipRight := clipRight max: clipLeft.
	clipBottom := clipBottom max: clipTop.
	self setScissor: (Array with: clipLeft with: clipTop with: clipRight - clipLeft with: clipBottom - clipTop).
	^aBlock ensure: [
		clipLeft := l. clipTop := t. clipRight := r. clipBottom := b.
		self setScissor: oldScissor]
!
alpha: aNumber during: aBlock
	"Draw with all colors' alpha multiplied by aNumber."
	| old |
	old := opacity.
	opacity := opacity * aNumber.
	^aBlock ensure: [opacity := old]
! !

!Canvas methodsFor: 'retained drawing'!
replay: aSegment
	"Draw aSegment again and answer true if it is valid here: recorded at my scale and opacity, in my clip relative to the origin, at an origin whole device pixels away from mine. Answer false (drawing nothing) otherwise, inside drawFresh:, for a volatile segment, or when replaying is off."
	| x y |
	(fresh or: [aSegment isVolatile or: [ReplaysSegments == false or: [aSegment glyphGeneration ~~ GlyphGeneration]]]) ifTrue: [^false].
	(aSegment scale = scale and: [aSegment opacity = opacity]) ifFalse: [^false].
	x := originX * scale - aSegment deviceX.
	y := originY * scale - aSegment deviceY.
	(x = x truncated and: [y = y truncated]) ifFalse: [^false].
	x := x truncated.
	y := y truncated.
	(clipLeft - x = aSegment clipLeft and: [clipTop - y = aSegment clipTop
		and: [clipRight - x = aSegment clipRight and: [clipBottom - y = aSegment clipBottom]]]) ifFalse: [^false].
	self closeRun.
	self append: aSegment dx: x dy: y.
	building isEmpty ifFalse: [building last addPart: aSegment dx: x dy: y; runStart: next - 1 // 40].
	^true
!
drawFresh: aBlock
	"Evaluate aBlock with replay: refusing every segment: everything is drawn (and recorded) anew."
	| old |
	old := fresh.
	fresh := true.
	^aBlock ensure: [fresh := old]
!
isFresh
	^fresh or: [ReplaysSegments == false]
!
emptyCopy
	"A new empty canvas in my drawing state (extent, scale, origin, clip, opacity), e.g. to compare a replay with drawing anew."
	^(self class extent: extent scale: scale) setOriginX: originX y: originY clipLeft: clipLeft top: clipTop right: clipRight bottom: clipBottom scissor: scissor opacity: opacity
!
noteVolatile
	"What is being drawn was computed while drawing: the segments being recorded must not be replayed."
	building do: [:each | each beVolatile]
! !

!Canvas methodsFor: 'finishing'!
displayList
	"Freeze what was drawn into a DisplayList. I must not be used afterwards."
	| list |
	self closeBatch.
	list := DisplayList
		vertices: bytes count: next - 1 // 40
		batches: batches asArray
		extent: extent scale: scale.
	bytes := nil.
	^list
! !

!Canvas methodsFor: 'private'!
deviceX: x
	"Snap a horizontal coordinate (points, before translation) to device pixels."
	| d |
	d := x + originX * scale + 0.5.
	^d >= 0 ifTrue: [d truncated] ifFalse: [d floor]
!
deviceY: y
	| d |
	d := y + originY * scale + 0.5.
	^d >= 0 ifTrue: [d truncated] ifFalse: [d floor]
!
pack: aColor
	opacity = 1 ifTrue: [^aColor premultipliedRGBA8].
	^aColor premultipliedRGBA8Times: opacity
!
reserveQuad
	"Answer the byte index of a fresh quad with no per-vertex translation."
	| p |
	(p := next) + 239 > bytes size ifTrue: [self grow].
	bytes float32At: p + 32 put: 0.
	bytes float32At: p + 36 put: 0.
	next := p + 240.
	^p
!
grow
	| newBytes |
	newBytes := ByteArray new: bytes size * 2.
	newBytes replaceFrom: 1 to: next - 1 with: bytes startingAt: 1.
	bytes := newBytes
!
closeRun
	"Freeze what was drawn since the current segment's last part into a leaf part."
	| top v n |
	building isEmpty ifTrue: [^self].
	top := building last.
	v := next - 1 // 40.
	n := v - top runStart.
	n > 0 ifTrue: [top addPart: (self leafFrom: top runStart count: n) dx: 0 dy: 0].
	top runStart: v
!
leafFrom: firstVertex count: n
	"A leaf DisplaySegment of my vertices firstVertex .. firstVertex + n - 1 (the last ones drawn; they are never overwritten, so the leaf refers to them) with their batches."
	| list end i b start stop |
	end := firstVertex + n.
	list := OrderedCollection new.
	i := batches size.
	[i >= 1 and: [(b := batches at: i) first + b count > firstVertex]] whileTrue: [
		start := b first max: firstVertex.
		stop := b first + b count min: end.
		stop > start ifTrue: [
			list addFirst: (DisplayBatch texture: b texture scissor: b scissor first: start - firstVertex count: stop - start dx: b dx dy: b dy)].
		i := i - 1].
	start := batch first max: firstVertex.
	end > start ifTrue: [
		list add: (DisplayBatch texture: batch texture scissor: batch scissor first: start - firstVertex count: end - start dx: batch dx dy: batch dy)].
	^DisplaySegment vertices: bytes offset: firstVertex * 40 count: n batches: list asArray
!
append: aSegment dx: x dy: y
	"Copy aSegment's vertices, moved by x @ y device pixels, continuing the current batch where it can."
	| n base |
	aSegment isLeaf ifFalse: [
		^aSegment partsDo: [:each :px :py | self append: each dx: x + px dy: y + py]].
	(n := aSegment vertexCount) = 0 ifTrue: [^self].
	base := next - 1 // 40.
	aSegment batches do: [:b | | s tx ty |
		s := b scissor.
		(s isNil or: [x = 0 and: [y = 0]]) ifFalse: [
			s := Array with: (s at: 1) + x with: (s at: 2) + y with: (s at: 3) with: (s at: 4)].
		tx := b dx + x.
		ty := b dy + y.
		(batch dx = tx and: [batch dy = ty and: [batch scissor = s
			and: [texture isNil or: [b texture isNil or: [texture == b texture]]]]])
			ifTrue: [
				(texture isNil and: [b texture notNil]) ifTrue: [
					texture := b texture.
					batch texture: texture]]
			ifFalse: [
				self closeBatchAt: base + b first.
				texture := b texture.
				batch := DisplayBatch texture: texture scissor: s first: base + b first count: 0 dx: tx dy: ty]].
	[next + (n * 40) - 1 > bytes size] whileTrue: [self grow].
	bytes replaceFrom: next to: next + (n * 40) - 1 with: aSegment vertices startingAt: aSegment byteOffset + 1.
	next := next + (n * 40).
	"Go on drawing in the last batch if it is unmoved and has the current clip."
	(batch dx = 0 and: [batch dy = 0 and: [batch scissor = scissor]]) ifFalse: [
		self closeBatch.
		texture := nil.
		batch := DisplayBatch texture: nil scissor: scissor first: next - 1 // 40]
!
replicateVertexAt: p
	"Copy the first vertex of the quad at p to its other five."
	bytes replaceFrom: p + 40 to: p + 79 with: bytes startingAt: p.
	bytes replaceFrom: p + 80 to: p + 159 with: bytes startingAt: p.
	bytes replaceFrom: p + 160 to: p + 239 with: bytes startingAt: p
!
quadX0: x0 y0: y0 x1: x1 y1: y1 color: packedColor mode: mode
	| p |
	p := self reserveQuad.
	bytes float32At: p put: x0.
	bytes float32At: p + 4 put: y0.
	bytes float32At: p + 8 put: x1.
	bytes float32At: p + 12 put: y1.
	bytes uint32At: p + 24 put: packedColor.
	bytes uint32At: p + 28 put: mode.
	self replicateVertexAt: p
!
antialiasedLineX0: x0 y0: y0 x1: x1 y1: y1 width: w color: packedColor
	"A quad around the segment (device pixels), widened by one pixel on each side; each vertex carries its signed distance across the line and the half width, so the fragment shader computes exact coverage."
	| dx dy len nx ny half reach ex ey corners p |
	dx := x1 - x0.
	dy := y1 - y0.
	len := (dx * dx + (dy * dy)) sqrt.
	len = 0 ifTrue: [^self].
	nx := dy negated / len.
	ny := dx / len.
	ex := dx / len * 0.5.
	ey := dy / len * 0.5.
	half := w / 2.0.
	reach := half + 1.0.
	"corner: x y distance"
	corners := Array new: 12.
	corners at: 1 put: x0 - ex + (nx * reach); at: 2 put: y0 - ey + (ny * reach); at: 3 put: reach.
	corners at: 4 put: x1 + ex + (nx * reach); at: 5 put: y1 + ey + (ny * reach); at: 6 put: reach.
	corners at: 7 put: x0 - ex - (nx * reach); at: 8 put: y0 - ey - (ny * reach); at: 9 put: reach negated.
	corners at: 10 put: x1 + ex - (nx * reach); at: 11 put: y1 + ey - (ny * reach); at: 12 put: reach negated.
	p := self reserveQuad.
	#(1 2 3 2 4 3) doWithIndex: [:corner :i |
		| q c |
		q := p + (i - 1 * 40).
		c := corner - 1 * 3.
		bytes float32At: q put: (corners at: c + 1).
		bytes float32At: q + 4 put: (corners at: c + 2).
		bytes float32At: q + 16 put: (corners at: c + 3).
		bytes float32At: q + 20 put: half.
		bytes uint32At: q + 24 put: packedColor.
		bytes uint32At: q + 28 put: DisplayList modeLine + DisplayList explicitPosition]
!
useTexture: aTextureSource
	"Make aTextureSource the texture of the current batch, starting a new batch if it already has another one."
	texture == aTextureSource ifTrue: [^self].
	texture isNil ifFalse: [
		self closeBatch.
		batch := DisplayBatch texture: nil scissor: scissor first: next - 1 // 40].
	texture := aTextureSource.
	batch texture: aTextureSource
!
setScissor: anArrayOrNil
	| first |
	scissor = anArrayOrNil ifTrue: [^self].
	scissor := anArrayOrNil.
	first := next - 1 // 40.
	self closeBatch.
	batch := DisplayBatch texture: texture scissor: scissor first: first
!
closeBatch
	"Finish the current batch (dropping it if empty)."
	self closeBatchAt: next - 1 // 40
!
closeBatchAt: vertexIndex
	"Finish the current batch before vertexIndex (dropping it if empty)."
	| count |
	count := vertexIndex - batch first.
	count > 0 ifTrue: [
		batch count: count.
		batches add: batch]
! !

!Canvas class methodsFor: 'retained drawing'!
glyphsChanged
	"The glyphs are rasterized anew (Font class>>regenerateGlyphs): segments recorded before refer to atlas entries the fonts no longer use, so they are not replayed."
	GlyphGeneration := (GlyphGeneration ifNil: [0]) + 1
!
replaysSegments
	^ReplaysSegments ~~ false
!
replaysSegments: aBoolean
	"false: replay: refuses every segment, so everything is drawn anew (to compare retained drawing with that)."
	ReplaysSegments := aBoolean
! !

!Canvas class methodsFor: 'instance creation'!
extent: aPoint scale: aNumber
	"A canvas for a target of aPoint points at aNumber device pixels per point."
	^self extent: aPoint scale: aNumber capacity: 32768
!
extent: aPoint scale: aNumber capacity: byteCount
	"The same with room for byteCount bytes of vertices before growing (e.g. what the previous frame needed)."
	^self new setExtent: aPoint scale: aNumber capacity: (byteCount max: 2400)
!
extent: aPoint
	^self extent: aPoint scale: Font deviceScale
!
extent: aPoint scale: aNumber buffer: aByteArray
	"Use exclusively owned scratch storage; the caller must not reuse it while the list is in use."
	^self new setExtent: aPoint scale: aNumber buffer: aByteArray
! !
