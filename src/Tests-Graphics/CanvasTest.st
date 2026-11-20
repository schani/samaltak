TestCase subclass: #CanvasTest
	instanceVariableNames: 'canvas'
	classVariableNames: ''
	package: 'Tests-Graphics'!

CanvasTest comment: 'I check what a Canvas records into a DisplayList (no GPU needed): device-pixel snapping, translation, clipping into scissored batches and culling, texture batching, opacity; a record: cut short (an exception, its Process terminated by another) leaves its drawing to the segment around it and the Canvas recording.'!

!CanvasTest methodsFor: 'running'!
setUp
	canvas := Canvas extent: 200 @ 100 scale: 2
! !

!CanvasTest methodsFor: 'tests'!
testColorEmojiQuads
	"A color emoji is a quad per layer in its palette colors, whatever the text color, at a whole pixel; the text goes on where widthOf: says."
	| s f list colors last other |
	f := Font face: Font code face size: 13 scale: 2.
	s := 'a' , (String withAll: (#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466) collect: [:cp | Character value: cp])) , 'x'.
	canvas drawString: s at: 0.3 @ 0 font: f color: Color black.
	list := canvas displayList.
	self assert: list quadCount equals: 2 + ((f colorLayersOf: (f colorGlyphsFrom: 2 to: 8 in: s) first) size // 2).
	colors := (2 to: list quadCount - 1) collect: [:i | (list quadAt: i) at: #color].
	self assert: colors asSet size > 3.
	self assert: ((list quadAt: 2) at: #origin) x equals: ((0.3 + (f widthOf: 'a')) * 2) rounded.
	last := list quadAt: list quadCount.
	self assert: ((last at: #origin) x - ((0.3 + (f widthOf: s from: 1 to: 8)) * 2)) abs <= 0.5.
	other := Canvas extent: 200 @ 100 scale: 2.
	other drawString: s at: 0.3 @ 0 font: f color: Color red.
	list := other displayList.
	self assert: ((2 to: list quadCount - 1) collect: [:i | (list quadAt: i) at: #color]) equals: colors
!
testFillRectSnapsToDevicePixels
	| list q |
	canvas fillRect: (0.3 @ 0.3 extent: 10 @ 10) color: Color black.
	list := canvas displayList.
	self assert: list quadCount equals: 1.
	q := list quadAt: 1.
	self assert: (q at: #rect) equals: (Rectangle left: 1 right: 21 top: 1 bottom: 21).
	self assert: (q at: #color) equals: 16rFF000000.
	self assert: (q at: #mode) equals: 0
!
testHairlineIsTwoDevicePixels
	| q |
	canvas line: 10 @ 20 to: 60 @ 20 color: Color black width: 1.
	q := canvas displayList quadAt: 1.
	self assert: (q at: #rect) equals: (Rectangle left: 20 right: 120 top: 40 bottom: 42)
!
testStrokeRectIsInside
	| list rects |
	canvas strokeRect: (10 @ 10 extent: 20 @ 10) color: Color black width: 1.
	list := canvas displayList.
	self assert: list quadCount equals: 4.
	rects := (1 to: 4) collect: [:i | (list quadAt: i) at: #rect].
	self assert: (rects inject: rects first into: [:a :b | a merge: b]) equals: (Rectangle left: 20 right: 60 top: 20 bottom: 40)
!
testTranslation
	| q |
	canvas translateBy: 5 @ 7 during: [
		canvas fillRect: (0 @ 0 extent: 1 @ 1) color: Color black].
	canvas fillRect: (0 @ 0 extent: 1 @ 1) color: Color black.
	q := canvas displayList.
	self assert: ((q quadAt: 1) at: #rect) equals: (Rectangle left: 10 right: 12 top: 14 bottom: 16).
	self assert: ((q quadAt: 2) at: #rect) equals: (Rectangle left: 0 right: 2 top: 0 bottom: 2)
!
testClipMakesScissoredBatchesAndCulls
	| list |
	canvas fillRect: (0 @ 0 extent: 200 @ 100) color: Color white.
	canvas clip: (10 @ 10 extent: 50 @ 20) during: [
		canvas fillRect: (0 @ 0 extent: 30 @ 30) color: Color black.
		canvas fillRect: (100 @ 50 extent: 10 @ 10) color: Color black].
	canvas fillRect: (0 @ 0 extent: 5 @ 5) color: Color black.
	list := canvas displayList.
	self assert: list quadCount equals: 3.
	self assert: list batches size equals: 3.
	self assert: (list batches at: 2) scissor equals: #(20 20 100 40).
	self assert: (list batches at: 1) scissor isNil.
	self assert: (list batches at: 3) scissor isNil
!
testNestedClipsIntersect
	canvas clip: (0 @ 0 extent: 50 @ 50) during: [
		canvas clip: (25 @ 25 extent: 50 @ 50) during: [
			canvas fillRect: (0 @ 0 extent: 100 @ 100) color: Color black.
			self assert: canvas clipRect equals: (25 @ 25 corner: 50 @ 50)]].
	self assert: canvas displayList batches first scissor equals: #(50 50 50 50)
!
testTextBatchesWithAtlasAndSolids
	| list |
	canvas fillRect: (0 @ 0 extent: 200 @ 100) color: Color white.
	canvas drawString: 'Hello' at: 10 @ 10 font: Font ui color: Color black.
	canvas fillRect: (0 @ 50 extent: 200 @ 1) color: Color black.
	canvas drawString: 'world' at: 10 @ 60 font: Font code color: Color black.
	list := canvas displayList.
	self assert: list batches size equals: 1.
	self assert: list batches first texture identicalTo: GlyphAtlas default pages first.
	self assert: list quadCount equals: 12
!
testGlyphsSitOnDevicePixels
	| list q info |
	canvas drawString: 'x' at: 10.3 @ 10.2 font: Font code color: Color black.
	list := canvas displayList.
	q := list quadAt: 1.
	info := Font code glyphForCodePoint: $x value phase: 2.
	"pen 20.6 device px = 20 + 2/4 (rounded to quarter pixels): whole-pixel origin, phase 2"
	self assert: (q at: #origin) equals: 20.0 @ 49.0.
	self assert: (q at: #mode) equals: 1.
	self assert: ((q at: #rect) left) equals: info left
!
testImageStartsANewBatch
	| form list |
	form := Form width: 2 height: 2.
	canvas drawString: 'a' at: 0 @ 0 font: Font ui color: Color black.
	canvas image: form in: (0 @ 0 extent: 1 @ 1).
	canvas drawString: 'b' at: 0 @ 0 font: Font ui color: Color black.
	list := canvas displayList.
	self assert: list batches size equals: 3.
	self assert: (list batches at: 2) texture identicalTo: form
!
testOpacity
	| list |
	canvas alpha: 0.5 during: [canvas fillRect: (0 @ 0 extent: 1 @ 1) color: Color white].
	list := canvas displayList.
	self assert: ((list quadAt: 1) at: #color) equals: 16r80808080
!
testMeasureAndAlign
	| size list q |
	size := canvas measure: 'abc' font: Font code.
	self assert: size x closeTo: 3 * 7.8.
	self assert: size y equals: 20.
	canvas drawString: 'abc' in: (0 @ 0 extent: 100 @ 40) font: Font code color: Color black align: #right.
	list := canvas displayList.
	q := list quadAt: 1.
	"right aligned: pen starts at (100 - 23.4) * 2 = 153.2 device px; baseline (10 + 14.5) * 2"
	self assert: (q at: #origin) y equals: 49.0.
	self assert: ((q at: #origin) x between: 152 and: 154)
!
testCullsInvisibleText
	| list |
	canvas drawString: 'invisible' at: 10 @ 500 font: Font ui color: Color black.
	canvas drawString: 'clipped at the right edge of the canvas, which is narrow' at: 180 @ 0 font: Font ui color: Color black.
	list := canvas displayList.
	self assert: list quadCount < 6
!
testRecordedVerticesStayCompactAfterReplay
	| segment storage list |
	segment := canvas record: [
		canvas fillRect: (0 @ 0 extent: 10 @ 10) color: Color black].
	self assert: segment vertices size equals: segment vertexCount * 40.
	storage := segment vertices.
	canvas := Canvas extent: 200 @ 100 scale: 2.
	canvas append: segment dx: 0 dy: 0.
	self assert: segment vertices identicalTo: storage.
	list := canvas displayList.
	self assert: ((list quadAt: 1) at: #rect) equals: (Rectangle left: 0 right: 20 top: 0 bottom: 20)
!
testNestedRecordingPacksSharedVertices
	| inner outer list |
	outer := canvas record: [
		canvas fillRect: (0 @ 0 extent: 1 @ 1) color: Color black.
		inner := canvas record: [
			canvas fillRect: (2 @ 0 extent: 1 @ 1) color: Color black].
		canvas fillRect: (4 @ 0 extent: 1 @ 1) color: Color black].
	self assert: inner vertices size equals: 3 * inner vertexCount * 40.
	canvas := Canvas extent: 200 @ 100 scale: 2.
	canvas append: outer dx: 0 dy: 0.
	list := canvas displayList.
	self assert: ((list quadAt: 2) at: #rect) equals: (Rectangle left: 4 right: 6 top: 0 bottom: 2)
!
testScratchBufferCanBeReusedAfterConsumption
	| storage first segment second |
	storage := ByteArray new: 4096.
	canvas := Canvas extent: 200 @ 100 scale: 2 buffer: storage.
	segment := canvas record: [
		canvas fillRect: (0 @ 0 extent: 1 @ 1) color: Color black].
	first := canvas displayList.
	self assert: first vertices identicalTo: storage.
	canvas := Canvas extent: 200 @ 100 scale: 2 buffer: storage.
	canvas fillRect: (10 @ 10 extent: 1 @ 1) color: Color black.
	second := canvas displayList.
	self assert: second vertices identicalTo: storage.
	canvas := Canvas extent: 200 @ 100 scale: 2.
	canvas append: segment dx: 0 dy: 0.
	self assert: (((canvas displayList) quadAt: 1) at: #rect) equals: (Rectangle left: 0 right: 2 top: 0 bottom: 2)
!
testRecordCutShortLeavesItsDrawingToTheOuterSegment
	| outer list |
	outer := canvas record: [
		canvas fillRect: (0 @ 0 extent: 4 @ 4) color: Color black.
		[canvas record: [
			canvas fillRect: (4 @ 0 extent: 4 @ 4) color: Color black.
			1 / 0]] on: ZeroDivide do: [:e | e return: nil].
		canvas fillRect: (8 @ 0 extent: 4 @ 4) color: Color black].
	self assert: outer quadCount equals: 3.
	canvas := Canvas extent: 200 @ 100 scale: 2.
	self assert: (canvas replay: outer).
	list := canvas displayList.
	self assert: list quadCount equals: 3.
	self assert: ((list quadAt: 2) at: #rect) equals: (Rectangle left: 8 right: 16 top: 0 bottom: 8)
!
testTerminatedWhereAnInnerRecordEnds
	"Another Process terminates one stopped where an inner record: ends, its segment not yet popped (as Window>>close may): the outer record: still unwinds, and I record again."
	| p sim pops segment |
	p := [canvas record: [
		canvas fillRect: (0 @ 0 extent: 4 @ 4) color: Color black.
		canvas record: [canvas fillRect: (4 @ 0 extent: 4 @ 4) color: Color black].
		canvas record: [canvas fillRect: (8 @ 0 extent: 4 @ 4) color: Color black]]] newProcess.
	sim := Simulator new process: p.
	pops := 0.
	"To the end of the second inner record:, before it pops its segment."
	[sim isStopped or: [(sim top method == (Canvas >> #record:)
		and: [sim top instructionStream peekInstruction arguments includes: #removeLast]) and: [(pops := pops + 1) = 2]]]
			whileFalse: [sim stepProcess].
	self deny: sim isStopped.
	p terminate.
	segment := canvas record: [canvas fillRect: (12 @ 0 extent: 4 @ 4) color: Color black].
	self assert: segment isLeaf.
	self assert: segment quadCount equals: 1.
	self assert: canvas displayList quadCount equals: 4
!
testTerminatedWhileASegmentTakesAPart
	"Another Process terminates one stopped while the segment it records takes a part, the part added but not yet its move (as Window>>close may, the window's Process drawing): the unwinding reads no segment, and I record again."
	| p sim adds segment |
	p := [canvas record: [canvas record: []]] newProcess.
	sim := Simulator new process: p.
	adds := 0.
	[sim isStopped or: [(sim top method == (DisplaySegment >> #addPart:dx:dy:)
		and: [sim top instructionStream peekInstruction arguments includes: #add:]) and: [(adds := adds + 1) = 2]]]
			whileFalse: [sim stepProcess].
	self deny: sim isStopped.
	p terminate.
	segment := canvas record: [canvas fillRect: (0 @ 0 extent: 4 @ 4) color: Color black].
	self assert: segment isLeaf.
	self assert: segment quadCount equals: 1.
	self assert: canvas displayList quadCount equals: 1
! !
