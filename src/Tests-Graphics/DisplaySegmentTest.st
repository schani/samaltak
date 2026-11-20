GraphicsTestCase subclass: #DisplaySegmentTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

DisplaySegmentTest comment: 'I check retained drawing on the Canvas: a recorded DisplaySegment replayed on a later canvas draws the same quads as drawing anew, also moved by whole device pixels (the batch carries the move) and nested; replay: refuses a segment when the clip, opacity or scale differs, when the move is not whole device pixels, inside drawFresh:, for volatile segments and when replaying is off; the GPU draws moved batches pixel for pixel like drawing there.'!

!DisplaySegmentTest methodsFor: 'support'!
scene: c
	"Rectangles, a pattern, a diagonal line, text and a clip."
	c fillRect: (2 @ 3 extent: 40 @ 12) color: Color ultramarine.
	c pattern: #halftone in: (0 @ 20 extent: 30 @ 10).
	c line: 0 @ 0 to: 30 @ 18 color: Color black width: 1.
	c clip: (0 @ 0 extent: 60 @ 40) during: [
		c drawString: 'Retained' at: 4 @ 22 font: Font ui color: Color black]
!
drawAt: aPoint with: aBlock
	"A fresh canvas: aBlock (receiving it) drawn translated to aPoint and clipped to 60 @ 40 there."
	| c |
	c := Canvas extent: 200 @ 100 scale: 2.
	c translateBy: aPoint during: [c clip: (0 @ 0 extent: 60 @ 40) during: [aBlock value: c]].
	^c
!
record
	| segment |
	self drawAt: 10 @ 10 with: [:c | segment := c record: [self scene: c]].
	^segment
! !

!DisplaySegmentTest methodsFor: 'tests'!
testReplayDrawsLikeDrawingAnew
	| segment replayed drawn |
	segment := self record.
	replayed := self drawAt: 10 @ 10 with: [:c | self assert: (c replay: segment)].
	drawn := self drawAt: 10 @ 10 with: [:c | self scene: c].
	self assert: (replayed displayList drawsLike: drawn displayList).
	self assert: replayed displayList quadCount equals: drawn displayList quadCount
!
testReplayMovedByWholeDevicePixels
	| segment replayed drawn |
	segment := self record.
	"35.5 points at scale 2: 71 device pixels."
	replayed := self drawAt: 45.5 @ 30 with: [:c | self assert: (c replay: segment)].
	drawn := self drawAt: 45.5 @ 30 with: [:c | self scene: c].
	self assert: (replayed displayList drawsLike: drawn displayList).
	self assert: (replayed displayList batches anySatisfy: [:b | b dx = 71 and: [b dy = 40]])
!
testReplayRefusesAnotherState
	| segment c |
	segment := self record.
	self drawAt: 10.25 @ 10 with: [:canvas | self deny: (canvas replay: segment)].
	c := Canvas extent: 200 @ 100 scale: 2.
	c translateBy: 10 @ 10 during: [c clip: (0 @ 0 extent: 50 @ 40) during: [self deny: (c replay: segment)]].
	self drawAt: 10 @ 10 with: [:canvas | canvas alpha: 0.5 during: [self deny: (canvas replay: segment)]].
	self drawAt: 10 @ 10 with: [:canvas | canvas drawFresh: [self deny: (canvas replay: segment)]].
	c := Canvas extent: 200 @ 100 scale: 1.
	c translateBy: 10 @ 10 during: [c clip: (0 @ 0 extent: 60 @ 40) during: [self deny: (c replay: segment)]].
	self assert: c displayList isEmpty
!
testGlyphsRasterizedAnewAreNotReplayed
	"After the glyphs are rasterized anew (a rasterizer or font change), segments refer to atlas entries the fonts no longer use."
	| segment |
	segment := self record.
	Canvas glyphsChanged.
	self drawAt: 10 @ 10 with: [:c | self deny: (c replay: segment)].
	segment := self record.
	self drawAt: 10 @ 10 with: [:c | self assert: (c replay: segment)]
!
testOneAtlasEntryPerGlyph
	"Processes drawing concurrently rasterize a glyph once: they all get the same atlas entry."
	| font results done |
	font := Font faceNamed: 'IosevkaEtoile-Regular' size: 17.
	results := Array new: 4.
	done := Semaphore new.
	#(1 2 3 4) do: [:i |
		[results at: i put: ((33 to: 126) collect: [:cp | Processor yield. font glyphForCodePoint: cp phase: 1]).
		 done signal] forkAt: Processor activePriority].
	4 timesRepeat: [self deny: (done waitTimeoutMSecs: 10000)].
	2 to: 4 do: [:i | self assert: ((results at: i) with: results first collect: [:a :b | a == b]) asSet equals: (Set with: true)]
!
testReplayingCanBeTurnedOff
	| segment |
	segment := self record.
	[Canvas replaysSegments: false.
	 self drawAt: 10 @ 10 with: [:c | self deny: (c replay: segment)]]
		ensure: [Canvas replaysSegments: true].
	self drawAt: 10 @ 10 with: [:c | self assert: (c replay: segment)]
!
testVolatileSegmentsAreNotReplayed
	| outer inner |
	self drawAt: 10 @ 10 with: [:c |
		outer := c record: [
			c fillRect: (0 @ 0 extent: 5 @ 5) color: Color black.
			inner := c record: [c noteVolatile. c fillRect: (5 @ 5 extent: 5 @ 5) color: Color black]]].
	self assert: inner isVolatile.
	self assert: outer isVolatile.
	self drawAt: 10 @ 10 with: [:c | self deny: (c replay: outer)]
!
testNestedSegmentsAreParts
	| inner outer replayed drawn |
	self drawAt: 0 @ 0 with: [:c |
		inner := c record: [self scene: c]].
	self drawAt: 0 @ 0 with: [:c |
		outer := c record: [
			c fillRect: (0 @ 0 extent: 60 @ 2) color: Color black.
			c translateBy: 3 @ 2 during: [self deny: (c replay: inner)].
			c translateBy: 0 @ 0 during: [self assert: (c replay: inner)].
			c fillRect: (0 @ 38 extent: 60 @ 2) color: Color black]].
	self deny: outer isLeaf.
	self assert: outer vertexCount equals: inner vertexCount + 12.
	replayed := self drawAt: 20 @ 30 with: [:c | self assert: (c replay: outer)].
	drawn := self drawAt: 20 @ 30 with: [:c |
		c fillRect: (0 @ 0 extent: 60 @ 2) color: Color black.
		self scene: c.
		c fillRect: (0 @ 38 extent: 60 @ 2) color: Color black].
	self assert: (replayed displayList drawsLike: drawn displayList)
!
testMovedBatchesRenderLikeDrawingThere
	| segment replayed drawn |
	segment := self record.
	replayed := self render: [:c | c translateBy: 45.5 @ 30 during: [c clip: (0 @ 0 extent: 60 @ 40) during: [self assert: (c replay: segment)]]] extent: 200 @ 100.
	drawn := self render: [:c | c translateBy: 45.5 @ 30 during: [c clip: (0 @ 0 extent: 60 @ 40) during: [self scene: c]]] extent: 200 @ 100.
	self assert: replayed bits = drawn bits.
	self assert: (self grayAt: 100 @ 70 in: replayed) < 255
! !
