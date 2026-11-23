Object subclass: #VectorPath
	instanceVariableNames: 'contours current'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

VectorPath comment: 'I am a vector outline: contours of straight lines and cubic Béziers in absolute coordinates, each open or closed. Quadratic Béziers and elliptical arcs become cubics (quadratics exactly, arcs to within a hair). I read SVG path data (every command, absolute and relative, with its shorthand rules), map through affine transforms (#(a b c d e f): x'' = ax + cy + e, y'' = bx + dy + f) and flatten into polylines for VectorPainter.

	(VectorPath fromSVG: ''M10 10h80v80H10z'') contours
	(VectorPath new moveToX: 0 y: 0; lineToX: 10 y: 0; close; yourself)

A contour is an Array of commands: #(#move x y), #(#line x y), #(#cubic x1 y1 x2 y2 x y), and #(#close) last if closed.'!

!VectorPath methodsFor: 'initialization'!
initialize
	contours := OrderedCollection new
! !

!VectorPath methodsFor: 'accessing'!
contours
	"The contours (Arrays of commands) of a finished path."
	^(contours collect: [:each | each asArray]) asArray
!
isEmpty
	^contours isEmpty
! !

!VectorPath methodsFor: 'building'!
moveToX: x y: y
	current := OrderedCollection with: (Array with: #move with: x with: y).
	contours add: current
!
lineToX: x y: y
	current isNil ifTrue: [^self moveToX: x y: y].
	current add: (Array with: #line with: x with: y)
!
cubicToX1: x1 y1: y1 x2: x2 y2: y2 x: x y: y
	current isNil ifTrue: [self moveToX: x1 y: y1].
	current add: {#cubic. x1. y1. x2. y2. x. y}
!
quadFromX: x0 y: y0 toX1: x1 y1: y1 x: x y: y
	"A quadratic Bézier from x0@y0, as the cubic it is."
	self cubicToX1: x0 + (2.0 / 3.0 * (x1 - x0)) y1: y0 + (2.0 / 3.0 * (y1 - y0))
		x2: x + (2.0 / 3.0 * (x1 - x)) y2: y + (2.0 / 3.0 * (y1 - y))
		x: x y: y
!
close
	current isNil ifTrue: [^self].
	current add: #(#close).
	current := nil
!
arcFromX: x1 y: y1 rx: rxIn ry: ryIn rotation: degrees large: large sweep: sweep toX: x2 y: y2
	"An SVG elliptical arc (endpoint parameterization, SVG 1.1 F.6.5) as cubics of at most a quarter turn each."
	| rx ry phi cosPhi sinPhi dx dy x1p y1p lambda sign num den coef cxp cyp cx cy theta1 dtheta segments delta t a |
	(x1 = x2 and: [y1 = y2]) ifTrue: [^self].
	rx := rxIn abs.
	ry := ryIn abs.
	(rx = 0 or: [ry = 0]) ifTrue: [^self lineToX: x2 y: y2].
	phi := degrees degreesToRadians.
	cosPhi := phi cos.
	sinPhi := phi sin.
	dx := (x1 - x2) / 2.0.
	dy := (y1 - y2) / 2.0.
	x1p := cosPhi * dx + (sinPhi * dy).
	y1p := cosPhi * dy - (sinPhi * dx).
	lambda := (x1p * x1p) / (rx * rx) + ((y1p * y1p) / (ry * ry)).
	lambda > 1.0 ifTrue: [rx := rx * lambda sqrt. ry := ry * lambda sqrt].
	sign := large = sweep ifTrue: [-1.0] ifFalse: [1.0].
	num := (rx * rx * ry * ry) - (rx * rx * y1p * y1p) - (ry * ry * x1p * x1p).
	den := (rx * rx * y1p * y1p) + (ry * ry * x1p * x1p).
	coef := (den = 0 or: [num <= 0]) ifTrue: [0.0] ifFalse: [sign * (num / den) sqrt].
	cxp := coef * rx * y1p / ry.
	cyp := coef negated * ry * x1p / rx.
	cx := cosPhi * cxp - (sinPhi * cyp) + ((x1 + x2) / 2.0).
	cy := sinPhi * cxp + (cosPhi * cyp) + ((y1 + y2) / 2.0).
	theta1 := self angleFromX: 1.0 y: 0.0 toX: (x1p - cxp) / rx y: (y1p - cyp) / ry.
	dtheta := self angleFromX: (x1p - cxp) / rx y: (y1p - cyp) / ry toX: (x1p negated - cxp) / rx y: (y1p negated - cyp) / ry.
	(sweep not and: [dtheta > 0]) ifTrue: [dtheta := dtheta - (2 * Float pi)].
	(sweep and: [dtheta < 0]) ifTrue: [dtheta := dtheta + (2 * Float pi)].
	segments := (dtheta abs / (Float pi / 2)) ceiling max: 1.
	delta := dtheta / segments.
	t := 4.0 / 3.0 * (delta / 4.0) tan.
	a := theta1.
	segments timesRepeat: [
		| c1 s1 c2 s2 p1x p1y p2x p2y ex ey |
		c1 := a cos. s1 := a sin.
		c2 := (a + delta) cos. s2 := (a + delta) sin.
		p1x := c1 - (t * s1). p1y := s1 + (t * c1).
		p2x := c2 + (t * s2). p2y := s2 - (t * c2).
		ex := c2. ey := s2.
		self cubicToX1: (self ellipseX: p1x y: p1y rx: rx ry: ry cos: cosPhi sin: sinPhi cx: cx) y1: (self ellipseY: p1x y: p1y rx: rx ry: ry cos: cosPhi sin: sinPhi cy: cy)
			x2: (self ellipseX: p2x y: p2y rx: rx ry: ry cos: cosPhi sin: sinPhi cx: cx) y2: (self ellipseY: p2x y: p2y rx: rx ry: ry cos: cosPhi sin: sinPhi cy: cy)
			x: (self ellipseX: ex y: ey rx: rx ry: ry cos: cosPhi sin: sinPhi cx: cx) y: (self ellipseY: ex y: ey rx: rx ry: ry cos: cosPhi sin: sinPhi cy: cy).
		a := a + delta]
!
ellipseX: x y: y rx: rx ry: ry cos: c sin: s cx: cx
	^c * rx * x - (s * ry * y) + cx
!
ellipseY: x y: y rx: rx ry: ry cos: c sin: s cy: cy
	^s * rx * x + (c * ry * y) + cy
!
angleFromX: ux y: uy toX: vx y: vy
	| dot len ang |
	dot := ux * vx + (uy * vy).
	len := ((ux * ux + (uy * uy)) * (vx * vx + (vy * vy))) sqrt.
	len = 0 ifTrue: [^0.0].
	ang := ((dot / len) max: -1.0) min: 1.0.
	ang := ang arcCos.
	^(ux * vy - (uy * vx)) < 0 ifTrue: [ang negated] ifFalse: [ang]
! !

!VectorPath methodsFor: 'transforming'!
transformedBy: m
	"A copy mapped through the affine transform m, #(a b c d e f)."
	| copy |
	copy := VectorPath new.
	self contours do: [:contour |
		contour do: [:cmd |
			| k |
			k := cmd first.
			k == #move ifTrue: [copy moveToX: (self mapX: (cmd at: 2) y: (cmd at: 3) by: m) y: (self mapY: (cmd at: 2) y: (cmd at: 3) by: m)].
			k == #line ifTrue: [copy lineToX: (self mapX: (cmd at: 2) y: (cmd at: 3) by: m) y: (self mapY: (cmd at: 2) y: (cmd at: 3) by: m)].
			k == #cubic ifTrue: [copy
				cubicToX1: (self mapX: (cmd at: 2) y: (cmd at: 3) by: m) y1: (self mapY: (cmd at: 2) y: (cmd at: 3) by: m)
				x2: (self mapX: (cmd at: 4) y: (cmd at: 5) by: m) y2: (self mapY: (cmd at: 4) y: (cmd at: 5) by: m)
				x: (self mapX: (cmd at: 6) y: (cmd at: 7) by: m) y: (self mapY: (cmd at: 6) y: (cmd at: 7) by: m)].
			k == #close ifTrue: [copy close]]].
	^copy
!
mapX: x y: y by: m
	^(m at: 1) * x + ((m at: 3) * y) + (m at: 5)
!
mapY: x y: y by: m
	^(m at: 2) * x + ((m at: 4) * y) + (m at: 6)
! !

!VectorPath methodsFor: 'flattening'!
polylinesTolerance: tolerance
	"Each contour as {flat Array of x y ... . closed?}, cubics split into segments that stray from the curve by about tolerance."
	^self contours collect: [:contour |
		| pts x y closed |
		pts := OrderedCollection new.
		closed := false.
		contour do: [:cmd |
			| k |
			k := cmd first.
			k == #move ifTrue: [x := cmd at: 2. y := cmd at: 3. pts add: x; add: y].
			k == #line ifTrue: [x := cmd at: 2. y := cmd at: 3. pts add: x; add: y].
			k == #cubic ifTrue: [
				| n |
				n := self segmentsFromX: x y: y cubic: cmd tolerance: tolerance.
				1 to: n do: [:i |
					| t mt |
					t := i / n.
					mt := 1.0 - t.
					pts add: (mt * mt * mt * x) + (3.0 * mt * mt * t * (cmd at: 2)) + (3.0 * mt * t * t * (cmd at: 4)) + (t * t * t * (cmd at: 6)).
					pts add: (mt * mt * mt * y) + (3.0 * mt * mt * t * (cmd at: 3)) + (3.0 * mt * t * t * (cmd at: 5)) + (t * t * t * (cmd at: 7))].
				x := cmd at: 6. y := cmd at: 7].
			k == #close ifTrue: [closed := true]].
		Array with: pts asArray with: closed]
!
segmentsFromX: x0 y: y0 cubic: cmd tolerance: tolerance
	"Enough segments that the chords stay within tolerance of the curve (from the control polygon's second differences)."
	| ddx ddy dd |
	ddx := ((x0 - (2 * (cmd at: 2)) + (cmd at: 4)) abs) max: (((cmd at: 2) - (2 * (cmd at: 4)) + (cmd at: 6)) abs).
	ddy := ((y0 - (2 * (cmd at: 3)) + (cmd at: 5)) abs) max: (((cmd at: 3) - (2 * (cmd at: 5)) + (cmd at: 7)) abs).
	dd := (ddx * ddx + (ddy * ddy)) sqrt.
	^((((dd * 3.0) / (4.0 * tolerance)) sqrt) ceiling max: 1) min: 100
! !

!VectorPath class methodsFor: 'instance creation'!
fromSVG: aString
	"The path of SVG path data (the d attribute)."
	^self new readSVG: aString; yourself
!
rectX: x y: y width: w height: h rx: rxIn ry: ryIn
	| p rx ry k |
	p := self new.
	rx := (rxIn min: w / 2.0) max: 0.
	ry := (ryIn min: h / 2.0) max: 0.
	(rx = 0 or: [ry = 0]) ifTrue: [
		p moveToX: x y: y; lineToX: x + w y: y; lineToX: x + w y: y + h; lineToX: x y: y + h; close.
		^p].
	k := 0.5522847498.
	p moveToX: x + rx y: y.
	p lineToX: x + w - rx y: y.
	p cubicToX1: x + w - rx + (k * rx) y1: y x2: x + w y2: y + ry - (k * ry) x: x + w y: y + ry.
	p lineToX: x + w y: y + h - ry.
	p cubicToX1: x + w y1: y + h - ry + (k * ry) x2: x + w - rx + (k * rx) y2: y + h x: x + w - rx y: y + h.
	p lineToX: x + rx y: y + h.
	p cubicToX1: x + rx - (k * rx) y1: y + h x2: x y2: y + h - ry + (k * ry) x: x y: y + h - ry.
	p lineToX: x y: y + ry.
	p cubicToX1: x y1: y + ry - (k * ry) x2: x + rx - (k * rx) y2: y x: x + rx y: y.
	p close.
	^p
!
ellipseX: cx y: cy rx: rx ry: ry
	| p k |
	p := self new.
	k := 0.5522847498.
	p moveToX: cx + rx y: cy.
	p cubicToX1: cx + rx y1: cy + (k * ry) x2: cx + (k * rx) y2: cy + ry x: cx y: cy + ry.
	p cubicToX1: cx - (k * rx) y1: cy + ry x2: cx - rx y2: cy + (k * ry) x: cx - rx y: cy.
	p cubicToX1: cx - rx y1: cy - (k * ry) x2: cx - (k * rx) y2: cy - ry x: cx y: cy - ry.
	p cubicToX1: cx + (k * rx) y1: cy - ry x2: cx + rx y2: cy - (k * ry) x: cx + rx y: cy.
	p close.
	^p
!
polygon: points closed: aBoolean
	"points: a flat Array x y x y ..."
	| p |
	p := self new.
	points size < 2 ifTrue: [^p].
	p moveToX: (points at: 1) y: (points at: 2).
	3 to: points size - 1 by: 2 do: [:i | p lineToX: (points at: i) y: (points at: i + 1)].
	aBoolean ifTrue: [p close].
	^p
! !

!VectorPath methodsFor: 'reading SVG'!
readSVG: aString
	"Every SVG path command; after M or m further pairs are lines, after Z the point is the contour's start, S and T reflect the previous control point."
	| scanner cmd x y startX startY lastCtrlX lastCtrlY lastCmd |
	scanner := ReadStream on: aString.
	x := y := startX := startY := 0.0.
	lastCtrlX := lastCtrlY := nil.
	lastCmd := nil.
	[self skipSeparators: scanner. scanner atEnd] whileFalse: [
		| c |
		c := scanner peek.
		(c isLetter)
			ifTrue: [cmd := scanner next]
			ifFalse: [
				cmd isNil ifTrue: [^self error: 'path data must start with a command'].
				cmd = $M ifTrue: [cmd := $L].
				cmd = $m ifTrue: [cmd := $l]].
		(cmd = $Z or: [cmd = $z])
			ifTrue: [
				self close.
				x := startX. y := startY.
				lastCtrlX := nil]
			ifFalse: [
				| rel |
				rel := cmd isLowercase.
				(cmd = $M or: [cmd = $m]) ifTrue: [
					| nx ny |
					nx := self number: scanner. ny := self number: scanner.
					rel ifTrue: [nx := nx + x. ny := ny + y].
					self moveToX: nx y: ny.
					x := startX := nx. y := startY := ny.
					lastCtrlX := nil].
				(cmd = $L or: [cmd = $l]) ifTrue: [
					| nx ny |
					nx := self number: scanner. ny := self number: scanner.
					rel ifTrue: [nx := nx + x. ny := ny + y].
					self lineToX: nx y: ny.
					x := nx. y := ny. lastCtrlX := nil].
				(cmd = $H or: [cmd = $h]) ifTrue: [
					| nx |
					nx := self number: scanner.
					rel ifTrue: [nx := nx + x].
					self lineToX: nx y: y.
					x := nx. lastCtrlX := nil].
				(cmd = $V or: [cmd = $v]) ifTrue: [
					| ny |
					ny := self number: scanner.
					rel ifTrue: [ny := ny + y].
					self lineToX: x y: ny.
					y := ny. lastCtrlX := nil].
				(cmd = $C or: [cmd = $c]) ifTrue: [
					| v |
					v := (1 to: 6) collect: [:i | self number: scanner].
					rel ifTrue: [v := v withIndexCollect: [:e :i | e + (i odd ifTrue: [x] ifFalse: [y])]].
					self cubicToX1: (v at: 1) y1: (v at: 2) x2: (v at: 3) y2: (v at: 4) x: (v at: 5) y: (v at: 6).
					lastCtrlX := v at: 3. lastCtrlY := v at: 4.
					x := v at: 5. y := v at: 6].
				(cmd = $S or: [cmd = $s]) ifTrue: [
					| v c1x c1y |
					v := (1 to: 4) collect: [:i | self number: scanner].
					rel ifTrue: [v := v withIndexCollect: [:e :i | e + (i odd ifTrue: [x] ifFalse: [y])]].
					((lastCmd notNil and: ['CcSs' includes: lastCmd]) and: [lastCtrlX notNil])
						ifTrue: [c1x := 2 * x - lastCtrlX. c1y := 2 * y - lastCtrlY]
						ifFalse: [c1x := x. c1y := y].
					self cubicToX1: c1x y1: c1y x2: (v at: 1) y2: (v at: 2) x: (v at: 3) y: (v at: 4).
					lastCtrlX := v at: 1. lastCtrlY := v at: 2.
					x := v at: 3. y := v at: 4].
				(cmd = $Q or: [cmd = $q]) ifTrue: [
					| v |
					v := (1 to: 4) collect: [:i | self number: scanner].
					rel ifTrue: [v := v withIndexCollect: [:e :i | e + (i odd ifTrue: [x] ifFalse: [y])]].
					self quadFromX: x y: y toX1: (v at: 1) y1: (v at: 2) x: (v at: 3) y: (v at: 4).
					lastCtrlX := v at: 1. lastCtrlY := v at: 2.
					x := v at: 3. y := v at: 4].
				(cmd = $T or: [cmd = $t]) ifTrue: [
					| nx ny qx qy |
					nx := self number: scanner. ny := self number: scanner.
					rel ifTrue: [nx := nx + x. ny := ny + y].
					((lastCmd notNil and: ['QqTt' includes: lastCmd]) and: [lastCtrlX notNil])
						ifTrue: [qx := 2 * x - lastCtrlX. qy := 2 * y - lastCtrlY]
						ifFalse: [qx := x. qy := y].
					self quadFromX: x y: y toX1: qx y1: qy x: nx y: ny.
					lastCtrlX := qx. lastCtrlY := qy.
					x := nx. y := ny].
				(cmd = $A or: [cmd = $a]) ifTrue: [
					| rx ry rot large sweep nx ny |
					rx := self number: scanner. ry := self number: scanner. rot := self number: scanner.
					large := (self flag: scanner) = 1.
					sweep := (self flag: scanner) = 1.
					nx := self number: scanner. ny := self number: scanner.
					rel ifTrue: [nx := nx + x. ny := ny + y].
					self arcFromX: x y: y rx: rx ry: ry rotation: rot large: large sweep: sweep toX: nx y: ny.
					x := nx. y := ny. lastCtrlX := nil].
				('MmLlHhVvCcSsQqTtAa' includes: cmd) ifFalse: [^self error: 'unknown path command ', (String with: cmd)]].
		lastCmd := cmd]
!
skipSeparators: aStream
	[aStream atEnd not and: [aStream peek isSeparator or: [aStream peek = $,]]] whileTrue: [aStream next]
!
flag: aStream
	"An arc flag: one digit, which may touch the next number (a1 1 0 011 1)."
	| c |
	self skipSeparators: aStream.
	c := aStream next.
	(c = $0 or: [c = $1]) ifFalse: [^self error: 'arc flag expected'].
	^c digitValue
!
number: aStream
	"An SVG number: sign, digits, a point, an exponent; a second point or sign starts the next one (-.5.5 is -0.5 and 0.5)."
	| s c seenPoint seenExp |
	self skipSeparators: aStream.
	s := WriteStream on: (String new: 16).
	(aStream peek = $- or: [aStream peek = $+]) ifTrue: [s nextPut: aStream next].
	seenPoint := seenExp := false.
	[aStream atEnd not and: [
		c := aStream peek.
		c isDigit
			or: [(c = $. and: [seenPoint not and: [seenExp not]])
			or: [(c = $e or: [c = $E]) and: [seenExp not]]]]]
		whileTrue: [
			c = $. ifTrue: [seenPoint := true].
			(c = $e or: [c = $E]) ifTrue: [
				seenExp := true.
				s nextPut: aStream next.
				(aStream peek = $- or: [aStream peek = $+]) ifTrue: [s nextPut: aStream next]]
			ifFalse: [s nextPut: aStream next]].
	^self class parseNumber: s contents
! !

!VectorPath class methodsFor: 'numbers'!
parseNumber: aString
	"A number in SVG's syntax (.5, -3., 1e-3) as a Float."
	| s |
	s := aString.
	s isEmpty ifTrue: [^self error: 'number expected'].
	(s first = $.) ifTrue: [s := '0', s].
	((s beginsWith: '-.') or: [s beginsWith: '+.']) ifTrue: [s := (s first: 1), '0', (s allButFirst: 1)].
	(s last = $.) ifTrue: [s := s, '0'].
	s := s copyReplaceAll: '.e' with: '.0e'.
	s := s copyReplaceAll: '.E' with: '.0E'.
	(s first = $+) ifTrue: [s := s allButFirst].
	^(Number readFrom: s) asFloat
! !
