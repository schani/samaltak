TestCase subclass: #VectorGraphicsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

VectorGraphicsTest comment: 'Tests the vector stack: VectorPath''s SVG path data and flattening, VectorPainter''s fills (non-zero, even-odd: exact area coverage) and strokes, SVGReader''s documents (groups, transforms, styles, shapes) and SVGImage fitting a document into a Form.'!

!VectorGraphicsTest methodsFor: 'support'!
alphaOf: aForm at: aPoint
	^((aForm pixelValueAt: aPoint) bitShift: -24) bitAnd: 255
!
redOf: aForm at: aPoint
	^(aForm pixelValueAt: aPoint) bitAnd: 255
!
totalAlphaOf: aForm
	| sum |
	sum := 0.
	0 to: aForm height - 1 do: [:y | 0 to: aForm width - 1 do: [:x | sum := sum + (self alphaOf: aForm at: x @ y)]].
	^sum / 255.0
! !

!VectorGraphicsTest methodsFor: 'tests'!
testPathData
	| path lines |
	path := VectorPath fromSVG: 'M1 2L3,4h2v-1zm10 10l1-1Q0 0 5 5C1 1 2 2 3 3s1 1 2 2T4 4A2 2 0 0 1 8 8'.
	self assert: path contours size equals: 2.
	lines := path polylinesTolerance: 0.2.
	self assert: lines size equals: 2.
	"a closed contour: M1 2 L3 4 h2 v-1 z"
	self assert: lines first first equals: #(1 2 3 4 5 4 5 3).
	self assert: lines first last.
	self deny: lines last last.
	self assert: (VectorPath parseNumber: '-1.5e2') equals: -150.
	self assert: (VectorPath fromSVG: '') isEmpty
!
testNonZeroAndEvenOddFill
	| form outer inner |
	"two squares, the inner wound the same way: non-zero fills both, even-odd leaves a hole"
	outer := 'M0 0H20V20H0Z'.
	inner := 'M5 5H15V15H5Z'.
	form := Form width: 20 height: 20.
	(VectorPainter on: form) fill: (VectorPath fromSVG: outer, inner) color: Color white rule: #nonzero.
	self assert: (self totalAlphaOf: form) equals: 400.
	form := Form width: 20 height: 20.
	(VectorPainter on: form) fill: (VectorPath fromSVG: outer, inner) color: Color white rule: #evenodd.
	self assert: (self totalAlphaOf: form) equals: 300.
	self assert: (self alphaOf: form at: 10 @ 10) equals: 0.
	self assert: (self alphaOf: form at: 2 @ 2) equals: 255.
	"half a pixel covered: half the alpha"
	form := Form width: 4 height: 4.
	(VectorPainter on: form) fill: (VectorPath fromSVG: 'M0 0H1.5V4H0Z') color: Color white rule: #nonzero.
	self assert: ((self alphaOf: form at: 1 @ 0) between: 126 and: 129)
!
testCircleAreaAndStroke
	| form area |
	form := Form width: 40 height: 40.
	(VectorPainter on: form) fill: (VectorPath ellipseX: 20 y: 20 rx: 15 ry: 15) color: Color white rule: #nonzero.
	area := self totalAlphaOf: form.
	self assert: (area - (Float pi * 225)) abs < 3.
	"a 2-pixel line 20 long with butt caps covers 40 pixels; round caps add a disc"
	form := Form width: 40 height: 40.
	(VectorPainter on: form) stroke: (VectorPath fromSVG: 'M10 20H30') width: 2 color: Color white join: #round cap: #butt.
	self assert: ((self totalAlphaOf: form) - 40) abs < 0.5.
	form := Form width: 40 height: 40.
	(VectorPainter on: form) stroke: (VectorPath fromSVG: 'M10 20H30') width: 2 color: Color white join: #round cap: #round.
	self assert: ((self totalAlphaOf: form) - (40 + Float pi)) abs < 0.2
!
testSVGDocument
	| svg form |
	svg := SVGImage fromString: '<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <title>logo</title>
  <defs><mask id="m"><rect width="10" height="10" fill="white"/></mask></defs>
  <g fill="#ff0000" transform="translate(1 1)">
    <rect width="4" height="4"/>
    <circle cx="6" cy="6" r="2" style="fill: currentColor; opacity: 0.5"/>
  </g>
  <path d="M0 9H10" stroke="blue" stroke-width="1" fill="none"/>
</svg>'.
	self assert: svg viewBox equals: (0 @ 0 extent: 10 @ 10).
	self assert: svg shapes size equals: 3.
	self assert: (svg shapes first at: #fill) equals: (Color hex: 16rFF0000).
	self assert: ((svg shapes at: 2) at: #fill) equals: #currentColor.
	self assert: (svg shapes last at: #fill) isNil.
	form := svg formWidth: 20 height: 20 color: Color white.
	"the red square, scaled by two, from (2, 2) to (10, 10)"
	self assert: (self redOf: form at: 5 @ 5) equals: 255.
	self assert: (self alphaOf: form at: 1 @ 1) equals: 0.
	"the blue line: y 8.5 to 9.5, rows 17 and 18"
	self assert: (self alphaOf: form at: 5 @ 18) equals: 255.
	self assert: (self alphaOf: form at: 5 @ 19) equals: 0.
	self assert: (SVGImage parseColor: '#abc') equals: (Color hex: 16rAABBCC).
	self assert: (SVGImage parseColor: 'none') isNil.
	self assert: (SVGImage parseColor: 'rgb(255, 0, 0)') equals: (Color r: 1 g: 0 b: 0)
! !
