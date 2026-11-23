Object subclass: #VectorPainter
	instanceVariableNames: 'form tolerance'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

VectorPainter comment: 'I paint VectorPaths into a Form, in device pixels, antialiased with the exact area coverage of GlyphRasterizer: fill: (non-zero or even-odd winding) and stroke: (each segment a quad of the stroke''s width, round joins and caps as discs, all wound alike so their non-zero union is the stroke). Colors are composited over what the Form holds (premultiplied source over).

	painter := VectorPainter on: (Form width: 32 height: 32).
	painter fill: (VectorPath ellipseX: 16 y: 16 rx: 12 ry: 12) color: Color ultramarine rule: #nonzero.
	painter stroke: (VectorPath fromSVG: ''M4 28L28 4'') width: 3 color: Color black join: #round cap: #round.
	painter form'!

!VectorPainter methodsFor: 'initialization'!
setForm: aForm
	form := aForm.
	"how far a chord may stray from the curve, in pixels: coverage lost at the edges stays below a hundredth of a pixel"
	tolerance := 0.05
! !

!VectorPainter methodsFor: 'accessing'!
form
	^form
! !

!VectorPainter methodsFor: 'painting'!
fill: aPath color: aColor rule: aSymbol
	"Fill aPath (device pixels) with aColor; aSymbol #nonzero or #evenodd."
	| r |
	(aColor isNil or: [aColor alpha = 0]) ifTrue: [^self].
	r := GlyphRasterizer width: form width height: form height.
	(aPath polylinesTolerance: tolerance) do: [:each | self add: each first closed: true to: r].
	self composite: (aSymbol == #evenodd ifTrue: [r coverageEvenOdd] ifFalse: [r coverage]) color: aColor
!
stroke: aPath width: w color: aColor join: joinSymbol cap: capSymbol
	"Stroke aPath (device pixels) w pixels wide; joins #round, #miter or #bevel (all but round drawn as bevels), caps #butt, #round or #square."
	| r half |
	(aColor isNil or: [aColor alpha = 0 or: [w <= 0]]) ifTrue: [^self].
	r := GlyphRasterizer width: form width height: form height.
	half := w / 2.0.
	(aPath polylinesTolerance: tolerance) do: [:each |
		| pts closed n |
		pts := each first.
		closed := each last.
		n := pts size // 2.
		n >= 2 ifTrue: [
			1 to: n - 1 do: [:i |
				self quadFromX: (pts at: i * 2 - 1) y: (pts at: i * 2) toX: (pts at: i * 2 + 1) y: (pts at: i * 2 + 2) half: half into: r].
			closed ifTrue: [self quadFromX: (pts at: n * 2 - 1) y: (pts at: n * 2) toX: (pts at: 1) y: (pts at: 2) half: half into: r].
			"joins: a disc at every vertex inside the contour, everywhere when closed"
			(closed ifTrue: [1 to: n] ifFalse: [2 to: n - 1]) do: [:i |
				joinSymbol == #round
					ifTrue: [self discX: (pts at: i * 2 - 1) y: (pts at: i * 2) radius: half into: r]
					ifFalse: [self bevelAt: i of: pts count: n closed: closed half: half into: r]].
			(closed not and: [capSymbol ~~ #butt]) ifTrue: [
				capSymbol == #round
					ifTrue: [
						self discX: (pts at: 1) y: (pts at: 2) radius: half into: r.
						self discX: (pts at: n * 2 - 1) y: (pts at: n * 2) radius: half into: r]
					ifFalse: [
						self squareCapAtX: (pts at: 1) y: (pts at: 2) fromX: (pts at: 3) y: (pts at: 4) half: half into: r.
						self squareCapAtX: (pts at: n * 2 - 1) y: (pts at: n * 2) fromX: (pts at: n * 2 - 3) y: (pts at: n * 2 - 2) half: half into: r]]]].
	self composite: r coverage color: aColor
! !

!VectorPainter methodsFor: 'private'!
add: points closed: aBoolean to: aRasterizer
	| n |
	n := points size // 2.
	n < 2 ifTrue: [^self].
	1 to: n - 1 do: [:i |
		aRasterizer lineFromX: (points at: i * 2 - 1) y: (points at: i * 2) toX: (points at: i * 2 + 1) y: (points at: i * 2 + 2)].
	aBoolean ifTrue: [aRasterizer lineFromX: (points at: n * 2 - 1) y: (points at: n * 2) toX: (points at: 1) y: (points at: 2)]
!
polygon: points into: aRasterizer
	"A closed polygon wound counterclockwise in device space (positive area with y down), so overlapping pieces add up."
	| area n pts |
	n := points size // 2.
	area := 0.0.
	1 to: n do: [:i |
		| j |
		j := i \\ n + 1.
		area := area + (((points at: i * 2 - 1) * (points at: j * 2)) - ((points at: j * 2 - 1) * (points at: i * 2)))].
	pts := area < 0
		ifTrue: [
			| rev |
			rev := Array new: points size.
			1 to: n do: [:i | rev at: i * 2 - 1 put: (points at: (n - i + 1) * 2 - 1). rev at: i * 2 put: (points at: (n - i + 1) * 2)].
			rev]
		ifFalse: [points].
	self add: pts closed: true to: aRasterizer
!
quadFromX: x0 y: y0 toX: x1 y: y1 half: half into: r
	| dx dy len nx ny |
	dx := x1 - x0.
	dy := y1 - y0.
	len := (dx * dx + (dy * dy)) sqrt.
	len = 0 ifTrue: [^self].
	nx := dy negated / len * half.
	ny := dx / len * half.
	self polygon: {x0 + nx. y0 + ny. x1 + nx. y1 + ny. x1 - nx. y1 - ny. x0 - nx. y0 - ny} into: r
!
discX: x y: y radius: radius into: r
	"A polygon close to the circle (edges within tolerance) with the circle's area, so coverage adds up as the circle's would."
	| n pts rr |
	n := radius <= tolerance
		ifTrue: [8]
		ifFalse: [((Float pi / (1.0 - (tolerance / radius)) arcCos) ceiling max: 8) min: 128].
	rr := radius * (Float pi / (n / 2.0 * (2.0 * Float pi / n) sin)) sqrt.
	pts := Array new: n * 2.
	1 to: n do: [:i |
		| a |
		a := (i - 1) / n * 2 * Float pi.
		pts at: i * 2 - 1 put: x + (rr * a cos).
		pts at: i * 2 put: y + (rr * a sin)].
	self polygon: pts into: r
!
bevelAt: i of: pts count: n closed: closed half: half into: r
	"The triangle between the two segments' outer corners at vertex i."
	| prev next x y d1 d2 |
	prev := i = 1 ifTrue: [n] ifFalse: [i - 1].
	next := i = n ifTrue: [1] ifFalse: [i + 1].
	x := pts at: i * 2 - 1. y := pts at: i * 2.
	d1 := self normalFromX: (pts at: prev * 2 - 1) y: (pts at: prev * 2) toX: x y: y half: half.
	d2 := self normalFromX: x y: y toX: (pts at: next * 2 - 1) y: (pts at: next * 2) half: half.
	(d1 isNil or: [d2 isNil]) ifTrue: [^self].
	self polygon: (Array with: x with: y with: x + d1 x with: y + d1 y with: x + d2 x with: y + d2 y) into: r.
	self polygon: (Array with: x with: y with: x - d1 x with: y - d1 y with: x - d2 x with: y - d2 y) into: r
!
normalFromX: x0 y: y0 toX: x1 y: y1 half: half
	| dx dy len |
	dx := x1 - x0. dy := y1 - y0.
	len := (dx * dx + (dy * dy)) sqrt.
	len = 0 ifTrue: [^nil].
	^(dy negated / len * half) @ (dx / len * half)
!
squareCapAtX: x y: y fromX: px y: py half: half into: r
	| dx dy len ux uy |
	dx := x - px. dy := y - py.
	len := (dx * dx + (dy * dy)) sqrt.
	len = 0 ifTrue: [^self].
	ux := dx / len * half. uy := dy / len * half.
	self quadFromX: x y: y toX: x + ux y: y + uy half: half into: r
!
composite: coverage color: aColor
	"Source over: aColor at each pixel's coverage onto form (premultiplied, red in the low byte)."
	| bits cr cg cb ca |
	bits := form bits.
	cr := aColor red. cg := aColor green. cb := aColor blue. ca := aColor alpha.
	1 to: coverage size do: [:i |
		| c |
		c := coverage at: i.
		c > 0 ifTrue: [
			| a d inv dr dg db da |
			a := c / 255.0 * ca.
			d := bits at: i.
			inv := 1.0 - a.
			dr := d bitAnd: 255. dg := (d bitShift: -8) bitAnd: 255. db := (d bitShift: -16) bitAnd: 255. da := (d bitShift: -24) bitAnd: 255.
			bits at: i put: ((cr * a * 255.0 + (dr * inv)) rounded min: 255)
				+ (((cg * a * 255.0 + (dg * inv)) rounded min: 255) bitShift: 8)
				+ (((cb * a * 255.0 + (db * inv)) rounded min: 255) bitShift: 16)
				+ (((a * 255.0 + (da * inv)) rounded min: 255) bitShift: 24)]].
	form changed
! !

!VectorPainter class methodsFor: 'instance creation'!
on: aForm
	^self new setForm: aForm
! !
