Object subclass: #GlyphAtlasPageTestTexture
	instanceVariableNames: 'height uploads'
	classVariableNames: ''
	package: 'Tests-Graphics'!

GlyphAtlasPageTestTexture comment: 'The device and the texture of a GlyphAtlasPage under test: I keep the rows of each upload ({top. bottom}; the whole page is {0. height}).'!

!GlyphAtlasPageTestTexture methodsFor: 'device'!
textureWidth: w height: h format: aSymbol usage: anArray
	height := h.
	uploads := OrderedCollection new.
	^self
! !

!GlyphAtlasPageTestTexture methodsFor: 'texture'!
device
	^self
!
generation
	^1
!
upload: bytes
	uploads add: {0. height}
!
upload: bytes x: x y: y width: w height: h bytesPerRow: anInteger
	uploads add: {y. y + h}
!
uploads
	^uploads
! !

TestCase subclass: #GlyphAtlasPageTest
	instanceVariableNames: 'page texture'
	classVariableNames: ''
	package: 'Tests-Graphics'!

GlyphAtlasPageTest comment: 'I check what a GlyphAtlasPage uploads (no GPU needed): the whole page first, then the rows stored since; and that Processes storing and uploading at once lose no rows: a store an upload falls into, two uploads at once.'!

!GlyphAtlasPageTest methodsFor: 'running'!
setUp
	page := GlyphAtlasPage size: 64.
	texture := GlyphAtlasPageTestTexture new
! !

!GlyphAtlasPageTest methodsFor: 'support'!
storeWidth: w height: h
	"Store a w×h glyph; answer its top row."
	| position |
	position := page allocateWidth: w height: h.
	page store: (ByteArray new: w * h withAll: 255) width: w height: h at: position.
	^position y
!
stop: aProcess before: aSelector
	"Run aProcess (simulated) up to its send of aSelector to something in my page's methods."
	| sim |
	sim := Simulator new process: aProcess.
	[sim isStopped or: [sim top receiver == page
		and: [sim top instructionStream peekInstruction arguments includes: aSelector]]] whileFalse: [sim stepProcess].
	self deny: sim isStopped
! !

!GlyphAtlasPageTest methodsFor: 'tests'!
testUploadsTheWholePageThenTheRowsStored
	| top |
	self storeWidth: 2 height: 2.
	page textureOn: texture.
	self assert: texture uploads asArray equals: #(#(0 64)).
	page textureOn: texture.
	self assert: texture uploads size equals: 1.
	self storeWidth: 2 height: 2.
	top := self storeWidth: 2 height: 8.
	page textureOn: texture.
	self assert: texture uploads last equals: {0. top + 8}
!
testAStoreAnUploadFallsIntoStaysDirty
	"A window's Process stores a glyph on a new shelf, rows of an earlier one still dirty; a compositor uploads while the store notes its rows: they are uploaded the next time."
	| top writer |
	self storeWidth: 2 height: 2.
	page textureOn: texture.
	self storeWidth: 2 height: 2.
	writer := [top := self storeWidth: 2 height: 8] newProcess.
	self track: writer.
	self stop: writer before: #min:.
	page textureOn: texture.
	writer resume.
	self assert: (self waitFor: [writer isTerminated]) description: 'the store did not finish'.
	page textureOn: texture.
	self assert: (texture uploads last first <= top and: [texture uploads last last >= (top + 8)])
		description: 'the rows ', top printString, ' to ', (top + 8) printString, ' were stored, the uploads are ', texture uploads asArray printString
!
testTwoUploadsAtOnce
	"Two Worlds' compositors upload the same dirty rows at once: neither fails, the rows are uploaded."
	| top failure uploader |
	self storeWidth: 2 height: 2.
	page textureOn: texture.
	top := self storeWidth: 2 height: 8.
	uploader := [[page textureOn: texture] on: Error do: [:e | failure := e messageText]] newProcess.
	self track: uploader.
	self stop: uploader before: #copyFrom:to:.
	page textureOn: texture.
	uploader resume.
	self assert: (self waitFor: [uploader isTerminated]) description: 'the upload did not finish'.
	self assert: failure isNil description: 'the upload failed: ', failure printString.
	self assert: (texture uploads anySatisfy: [:each | each first <= top and: [each last >= (top + 8)]])
		description: 'the uploads are ', texture uploads asArray printString
! !
