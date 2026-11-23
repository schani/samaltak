Object subclass: #GlyphRasterizer
	instanceVariableNames: 'width height accumulator'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

GlyphRasterizer comment: 'I rasterize outlines (lines and quadratic Béziers, in device pixels, y down) into 8-bit coverage with exact area antialiasing, the signed-area accumulation of font-rs / stb_truetype v2: every line segment adds, to the cells of each scanline it crosses, the signed area it covers to its right; a running sum along the rows then yields the winding-weighted coverage, clamped to [0, 1] (non-zero winding). Quadratics are flattened adaptively (segment count from the curve''s deviation).'!

!GlyphRasterizer methodsFor: 'initialization'!
setWidth: w height: h
	width := w.
	height := h.
	accumulator := Array new: w * h + 2 withAll: 0.0
! !

!GlyphRasterizer methodsFor: 'accessing'!
width
	^width
!
height
	^height
! !

!GlyphRasterizer methodsFor: 'drawing'!
addContour: contour scale: s offsetX: dx offsetY: dy
	"Add a TrueType contour (flat x y onCurve triples, font units, y up), mapped to x * s + dx, dy - (y * s)."
	| n firstOn startX startY prevX prevY ctrlX ctrlY hasCtrl x y on i k |
	n := contour size // 3.
	n < 2 ifTrue: [^self].
	"Start at an on-curve point; with none, at the midpoint of the first two off-curve points."
	firstOn := 0.
	k := 1.
	[firstOn = 0 and: [k <= n]] whileTrue: [
		(contour at: k * 3) ifTrue: [firstOn := k].
		k := k + 1].
	firstOn = 0
		ifTrue: [
			startX := ((contour at: 1) + (contour at: 4)) * 0.5 * s + dx.
			startY := dy - (((contour at: 2) + (contour at: 5)) * 0.5 * s).
			firstOn := 2]
		ifFalse: [
			startX := (contour at: firstOn * 3 - 2) * s + dx.
			startY := dy - ((contour at: firstOn * 3 - 1) * s).
			firstOn := firstOn + 1].
	prevX := startX.
	prevY := startY.
	hasCtrl := false.
	i := firstOn.
	n timesRepeat: [
		i > n ifTrue: [i := 1].
		x := (contour at: i * 3 - 2) * s + dx.
		y := dy - ((contour at: i * 3 - 1) * s).
		on := contour at: i * 3.
		on
			ifTrue: [
				hasCtrl
					ifTrue: [self quadFromX: prevX y: prevY ctrlX: ctrlX y: ctrlY toX: x y: y]
					ifFalse: [self lineFromX: prevX y: prevY toX: x y: y].
				prevX := x. prevY := y. hasCtrl := false]
			ifFalse: [
				hasCtrl ifTrue: [
					| mx my |
					mx := (ctrlX + x) * 0.5.
					my := (ctrlY + y) * 0.5.
					self quadFromX: prevX y: prevY ctrlX: ctrlX y: ctrlY toX: mx y: my.
					prevX := mx. prevY := my].
				ctrlX := x. ctrlY := y. hasCtrl := true].
		i := i + 1].
	"Close the contour (the start point may come after the last point we visited)."
	hasCtrl
		ifTrue: [self quadFromX: prevX y: prevY ctrlX: ctrlX y: ctrlY toX: startX y: startY]
		ifFalse: [self lineFromX: prevX y: prevY toX: startX y: startY]
!
quadFromX: x0 y: y0 ctrlX: x1 y: y1 toX: x2 y: y2
	"Flatten adaptively. With n segments the chords stay within |p0 - 2 p1 + p2| / (4 n^2) of the curve; choose n for at most 1/50 pixel."
	| devX devY devSq n step t px py nx ny mt |
	devX := x0 - (2.0 * x1) + x2.
	devY := y0 - (2.0 * y1) + y2.
	devSq := (devX * devX) + (devY * devY).
	devSq < 0.0064 ifTrue: [^self lineFromX: x0 y: y0 toX: x2 y: y2].
	n := (devSq sqrt * 12.5) sqrt ceiling.
	step := 1.0 / n.
	px := x0.
	py := y0.
	t := 0.0.
	n - 1 timesRepeat: [
		t := t + step.
		mt := 1.0 - t.
		nx := (mt * mt * x0) + (2.0 * mt * t * x1) + (t * t * x2).
		ny := (mt * mt * y0) + (2.0 * mt * t * y1) + (t * t * y2).
		self lineFromX: px y: py toX: nx y: ny.
		px := nx.
		py := ny].
	self lineFromX: px y: py toX: x2 y: y2
!
lineFromX: ax y: ay toX: bx y: by
	"Accumulate the signed area of the segment (device pixels, y down) into the cells of each row it crosses."
	| dir x0 y0 x1 y1 dxdy x rowStart rowEnd base dy xnext d xa xb xai xbi xf xmf s a0 xbf am a1 a2 idx acc w |
	(ay - by) abs < 1.0e-9 ifTrue: [^self].
	w := width.
	acc := accumulator.
	ay < by
		ifTrue: [dir := 1.0. x0 := ax. y0 := ay. x1 := bx. y1 := by]
		ifFalse: [dir := -1.0. x0 := bx. y0 := by. x1 := ax. y1 := ay].
	x0 := (x0 max: 0.0) min: w.
	x1 := (x1 max: 0.0) min: w.
	dxdy := (x1 - x0) / (y1 - y0).
	x := x0.
	y0 < 0.0
		ifTrue: [x := x - (y0 * dxdy). rowStart := 0]
		ifFalse: [rowStart := y0 truncated].
	rowEnd := y1 ceiling min: height.
	rowStart to: rowEnd - 1 do: [:row |
		base := row * w + 1.
		dy := ((row + 1) min: y1) - (row max: y0).
		xnext := x + (dxdy * dy).
		d := dy * dir.
		x < xnext ifTrue: [xa := x. xb := xnext] ifFalse: [xa := xnext. xb := x].
		xai := xa truncated.
		xbi := xb ceiling.
		xbi <= (xai + 1)
			ifTrue: [
				xmf := 0.5 * (x + xnext) - xai.
				idx := base + xai.
				acc at: idx put: (acc at: idx) + (d - (d * xmf)).
				acc at: idx + 1 put: (acc at: idx + 1) + (d * xmf)]
			ifFalse: [
				s := 1.0 / (xb - xa).
				xf := xa - xai.
				a0 := 0.5 * s * (1.0 - xf) * (1.0 - xf).
				xbf := xb - xbi + 1.0.
				am := 0.5 * s * xbf * xbf.
				idx := base + xai.
				acc at: idx put: (acc at: idx) + (d * a0).
				xbi = (xai + 2)
					ifTrue: [acc at: idx + 1 put: (acc at: idx + 1) + (d * (1.0 - a0 - am))]
					ifFalse: [
						a1 := s * (1.5 - xf).
						acc at: idx + 1 put: (acc at: idx + 1) + (d * (a1 - a0)).
						xai + 2 to: xbi - 2 do: [:xi |
							acc at: base + xi put: (acc at: base + xi) + (d * s)].
						a2 := a1 + ((xbi - xai - 3) * s).
						acc at: base + xbi - 1 put: (acc at: base + xbi - 1) + (d * (1.0 - a2 - am))].
				acc at: base + xbi put: (acc at: base + xbi) + (d * am)].
		x := xnext]
! !

!GlyphRasterizer methodsFor: 'output'!
coverage
	"Answer the coverage as a ByteArray of width * height bytes (0..255), rows top to bottom."
	| out sum v acc |
	out := ByteArray new: width * height.
	acc := accumulator.
	sum := 0.0.
	1 to: out size do: [:i |
		sum := sum + (acc at: i).
		v := sum < 0.0 ifTrue: [sum negated] ifFalse: [sum].
		out at: i put: (v >= 1.0 ifTrue: [255] ifFalse: [(v * 255.0 + 0.5) truncated])].
	^out
!
coverageEvenOdd
	"The coverage for the even-odd rule (SVG's fill-rule evenodd): a winding of 2 is outside again. As coverage, but the running sum folds to [0, 1] by its distance from the nearest even number."
	| out sum v acc |
	out := ByteArray new: width * height.
	acc := accumulator.
	sum := 0.0.
	1 to: out size do: [:i |
		sum := sum + (acc at: i).
		v := sum < 0.0 ifTrue: [sum negated] ifFalse: [sum].
		v := v - (2.0 * (v / 2.0) floor).
		v > 1.0 ifTrue: [v := 2.0 - v].
		out at: i put: (v >= 1.0 ifTrue: [255] ifFalse: [(v * 255.0 + 0.5) truncated])].
	^out
!
coverageSum
	"Answer the total coverage in pixels (exact, before quantization)."
	| sum total v |
	sum := 0.0.
	total := 0.0.
	1 to: width * height do: [:i |
		sum := sum + (accumulator at: i).
		v := sum abs.
		total := total + (v min: 1.0)].
	^total
! !

!GlyphRasterizer class methodsFor: 'instance creation'!
width: w height: h
	^self new setWidth: w height: h
! !
