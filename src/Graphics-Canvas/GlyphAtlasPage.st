Object subclass: #GlyphAtlasPage
	instanceVariableNames: 'size pixels shelves dirty texture uploadedGeneration'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

GlyphAtlasPage comment: 'I am one square R8 page of a GlyphAtlas: the CPU copy of the coverage (pixels, a ByteArray, rows top to bottom), shelf packing state, and the GPU texture, which I upload when rows changed (only the dirty band) or when the texture lost its contents (new session).

A window''s Process stores a glyph while a compositor uploads, and two Worlds'' compositors upload at once: dirty, the rows changed since the last upload ({top. bottom}, or nil), is one object that store:width:height:at: replaces and textureOn: takes, never a pair of variables changed one after the other.'!

!GlyphAtlasPage methodsFor: 'initialization'!
setSize: anInteger
	size := anInteger.
	pixels := ByteArray new: anInteger * anInteger.
	shelves := OrderedCollection new.
	dirty := nil.
	uploadedGeneration := nil
! !

!GlyphAtlasPage methodsFor: 'accessing'!
size
	^size
!
pixels
	^pixels
!
coverageAtX: x y: y
	"0-based pixel coordinates."
	^pixels at: y * size + x + 1
!
usedHeight
	shelves isEmpty ifTrue: [^0].
	^(shelves last at: 1) + (shelves last at: 2)
! !

!GlyphAtlasPage methodsFor: 'packing'!
allocateWidth: w height: h
	"Answer the 0-based top-left (x@y) of a free w×h area (keeping 1 px of padding), or nil if I am full."
	| pw ph shelf y x |
	pw := w + 1.
	ph := h + 1.
	pw > size ifTrue: [^nil].
	shelves do: [:each |
		"each is {y. height. nextX}; reuse shelves no more than a third taller than needed"
		((each at: 2) >= ph and: [(each at: 2) * 3 <= (ph * 4 + 3) and: [(each at: 3) + pw <= size]]) ifTrue: [
			x := each at: 3.
			each at: 3 put: x + pw.
			^x @ (each at: 1)]].
	y := self usedHeight.
	y + ph > size ifTrue: [^nil].
	shelf := Array with: y with: ph with: pw.
	shelves add: shelf.
	^0 @ y
!
store: coverage width: w height: h at: aPoint
	"Copy a w×h coverage ByteArray into my pixels at aPoint (0-based). One Process at a time (GlyphAtlas>>add:width:height:); an upload may take the dirty rows meanwhile: mine are then dirty with those it took."
	| x y |
	x := aPoint x.
	y := aPoint y.
	0 to: h - 1 do: [:row |
		pixels replaceFrom: (y + row) * size + x + 1 to: (y + row) * size + x + w with: coverage startingAt: row * w + 1].
	self dirtyFrom: y to: y + h
!
dirtyFrom: top to: bottom
	"The rows top to bottom - 1 are to be uploaded, with those already dirty."
	| band |
	band := dirty.
	dirty := band isNil
		ifTrue: [Array with: top with: bottom]
		ifFalse: [Array with: (band first min: top) with: (band last max: bottom)]
! !

!GlyphAtlasPage methodsFor: 'rendering'!
textureOn: aDevice
	"Answer my GPU texture, uploading what changed since the last upload. The dirty rows are taken before they are uploaded: what is stored meanwhile is dirty again."
	| generation band top bottom |
	(texture isNil or: [texture device ~~ aDevice]) ifTrue: [
		texture := aDevice textureWidth: size height: size format: #r8 usage: #(#sampler).
		uploadedGeneration := nil].
	generation := texture generation.
	band := dirty.
	dirty := nil.
	uploadedGeneration = generation
		ifFalse: [
			texture upload: pixels.
			uploadedGeneration := generation]
		ifTrue: [
			band isNil ifFalse: [
				top := band first.
				bottom := band last.
				[texture upload: (pixels copyFrom: top * size + 1 to: bottom * size) x: 0 y: top width: size height: bottom - top bytesPerRow: size]
					ifCurtailed: [self dirtyFrom: top to: bottom]]].
	^texture
!
isLinearFiltered
	"Glyphs are placed on device pixels: sample them exactly."
	^false
! !

!GlyphAtlasPage class methodsFor: 'instance creation'!
size: anInteger
	^self new setSize: anInteger
! !
