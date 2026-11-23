Object subclass: #Rectangle
	instanceVariableNames: 'origin corner'
	classVariableNames: ''
	package: 'Kernel-Objects'!

Rectangle comment: 'I am an axis-aligned rectangle from origin (top left, inclusive) to corner (bottom right, exclusive). Both are Points.'!

!Rectangle methodsFor: 'accessing'!
origin
	^origin
!
corner
	^corner
!
setOrigin: topLeft corner: bottomRight
	origin := topLeft.
	corner := bottomRight
!
origin: topLeft corner: bottomRight
	origin := topLeft.
	corner := bottomRight
!
extent
	^corner - origin
!
width
	^corner x - origin x
!
height
	^corner y - origin y
!
left
	^origin x
!
right
	^corner x
!
top
	^origin y
!
bottom
	^corner y
!
topLeft
	^origin
!
topRight
	^corner x @ origin y
!
bottomLeft
	^origin x @ corner y
!
bottomRight
	^corner
!
center
	^(origin + corner) // 2
!
area
	^self width * self height
! !

!Rectangle methodsFor: 'testing'!
containsPoint: aPoint
	^origin <= aPoint and: [aPoint < corner]
!
containsRect: aRectangle
	^aRectangle origin >= origin and: [aRectangle corner <= corner]
!
intersects: aRectangle
	| rOrigin rCorner |
	rOrigin := aRectangle origin.
	rCorner := aRectangle corner.
	rCorner x <= origin x ifTrue: [^false].
	rCorner y <= origin y ifTrue: [^false].
	rOrigin x >= corner x ifTrue: [^false].
	rOrigin y >= corner y ifTrue: [^false].
	^true
!
isEmpty
	^self width <= 0 or: [self height <= 0]
!
isRectangle
	^true
! !

!Rectangle methodsFor: 'rectangle functions'!
insetBy: delta
	"Answer a Rectangle shrunk by delta (a Number, a Point, or a Rectangle of four insets)."
	delta isRectangle ifTrue: [
		^Rectangle origin: origin + delta origin corner: corner - delta corner].
	^Rectangle origin: origin + delta corner: corner - delta
!
outsetBy: delta
	delta isRectangle ifTrue: [
		^Rectangle origin: origin - delta origin corner: corner + delta corner].
	^Rectangle origin: origin - delta corner: corner + delta
!
expandBy: delta
	^self outsetBy: delta
!
intersect: aRectangle
	^Rectangle
		origin: (origin max: aRectangle origin)
		corner: (corner min: aRectangle corner)
!
merge: aRectangle
	^Rectangle
		origin: (origin min: aRectangle origin)
		corner: (corner max: aRectangle corner)
!
quickMerge: aRectangle
	^self merge: aRectangle
!
translateBy: delta
	^Rectangle origin: origin + delta corner: corner + delta
!
moveTo: aPoint
	^Rectangle origin: aPoint extent: self extent
!
scaleBy: scale
	^Rectangle origin: origin * scale corner: corner * scale
!
rounded
	^Rectangle origin: origin rounded corner: corner rounded
!
areasOutside: aRectangle
	"Answer the parts of the receiver not covered by aRectangle (at most four rectangles)."
	| areas yOrigin yCorner |
	(self intersects: aRectangle) ifFalse: [^Array with: self].
	areas := OrderedCollection new.
	aRectangle origin y > origin y
		ifTrue: [areas add: (origin corner: corner x @ (yOrigin := aRectangle origin y))]
		ifFalse: [yOrigin := origin y].
	aRectangle corner y < corner y
		ifTrue: [areas add: (origin x @ (yCorner := aRectangle corner y) corner: corner)]
		ifFalse: [yCorner := corner y].
	aRectangle origin x > origin x
		ifTrue: [areas add: (origin x @ yOrigin corner: aRectangle origin x @ yCorner)].
	aRectangle corner x < corner x
		ifTrue: [areas add: (aRectangle corner x @ yOrigin corner: corner x @ yCorner)].
	^areas asArray
! !

!Rectangle methodsFor: 'comparing'!
= aRectangle
	^aRectangle isRectangle and: [origin = aRectangle origin and: [corner = aRectangle corner]]
!
hash
	^(origin hash hashMultiply + corner hash) hashMultiply
! !

!Rectangle methodsFor: 'printing'!
printOn: aStream
	aStream print: origin; nextPutAll: ' corner: '; print: corner
! !

!Rectangle class methodsFor: 'instance creation'!
origin: topLeft corner: bottomRight
	^self basicNew setOrigin: topLeft corner: bottomRight
!
origin: topLeft extent: aPoint
	^self basicNew setOrigin: topLeft corner: topLeft + aPoint
!
left: l right: r top: t bottom: b
	^self origin: l @ t corner: r @ b
!
encompassing: aCollection
	| min max |
	aCollection do: [:p |
		min isNil
			ifTrue: [min := max := p]
			ifFalse: [min := min min: p. max := max max: p]].
	^self origin: min corner: max
! !
