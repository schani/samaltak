Object subclass: #Point
	instanceVariableNames: 'x y'
	classVariableNames: ''
	package: 'Kernel-Objects'!

Point comment: 'I am a two-dimensional Cartesian point; x grows to the right and y grows downwards (screen coordinates). Create me with x@y. Arithmetic with a Number applies it to both coordinates. My field order (x y) is fixed by the VM.'!

!Point methodsFor: 'accessing'!
x
	^x
!
y
	^y
!
x: aNumber
	x := aNumber
!
y: aNumber
	y := aNumber
!
setX: xValue setY: yValue
	x := xValue.
	y := yValue
! !

!Point methodsFor: 'arithmetic'!
+ arg
	| p |
	p := arg asPoint.
	^(x + p x) @ (y + p y)
!
- arg
	| p |
	p := arg asPoint.
	^(x - p x) @ (y - p y)
!
* arg
	| p |
	p := arg asPoint.
	^(x * p x) @ (y * p y)
!
/ arg
	| p |
	p := arg asPoint.
	^(x / p x) @ (y / p y)
!
// arg
	| p |
	p := arg asPoint.
	^(x // p x) @ (y // p y)
!
\\ arg
	| p |
	p := arg asPoint.
	^(x \\ p x) @ (y \\ p y)
!
abs
	^x abs @ y abs
!
negated
	^x negated @ y negated
! !

!Point methodsFor: 'comparing'!
= aPoint
	^aPoint isPoint and: [x = aPoint x and: [y = aPoint y]]
!
hash
	^(x hash hashMultiply + y hash) hashMultiply
!
< aPoint
	^x < aPoint x and: [y < aPoint y]
!
<= aPoint
	^x <= aPoint x and: [y <= aPoint y]
!
> aPoint
	^x > aPoint x and: [y > aPoint y]
!
>= aPoint
	^x >= aPoint x and: [y >= aPoint y]
!
max: aPoint
	^(x max: aPoint x) @ (y max: aPoint y)
!
min: aPoint
	^(x min: aPoint x) @ (y min: aPoint y)
! !

!Point methodsFor: 'point functions'!
dist: aPoint
	| dx dy |
	dx := aPoint x - x.
	dy := aPoint y - y.
	^((dx * dx) + (dy * dy)) sqrt
!
dotProduct: aPoint
	^(x * aPoint x) + (y * aPoint y)
!
r
	^((x * x) + (y * y)) sqrt
!
normalized
	| r |
	r := self r.
	^(x / r) @ (y / r)
!
transposed
	^y @ x
!
rounded
	^x rounded @ y rounded
!
truncated
	^x truncated @ y truncated
!
floor
	^x floor @ y floor
!
ceiling
	^x ceiling @ y ceiling
!
scaleBy: aPoint
	^self * aPoint
!
translateBy: aPoint
	^self + aPoint
!
isZero
	^x isZero and: [y isZero]
! !

!Point methodsFor: 'converting'!
asPoint
	^self
!
corner: aPoint
	^Rectangle origin: self corner: aPoint
!
extent: aPoint
	^Rectangle origin: self extent: aPoint
!
@ aNumber
	^self error: 'Points cannot be coordinates of points'
! !

!Point methodsFor: 'testing'!
isPoint
	^true
! !

!Point methodsFor: 'printing'!
printOn: aStream
	"3@4, as in the Blue Book."
	aStream print: x; nextPut: $@.
	(y isNumber and: [y negative]) ifTrue: [aStream space].
	aStream print: y
!
storeOn: aStream
	aStream nextPut: $(; store: x; nextPut: $@; store: y; nextPut: $)
! !

!Point class methodsFor: 'instance creation'!
x: xValue y: yValue
	^self basicNew setX: xValue setY: yValue
! !
