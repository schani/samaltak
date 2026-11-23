Object subclass: #Complex
	instanceVariableNames: 'real imaginary'
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Complex comment: 'I am a complex number real + imaginary i (Floats), immutable by convention: arithmetic answers new instances. The Mandelbrot window iterates z := z squared + c with me, so its Process''s profile shows Complex>>squared and Complex>>+.'!

!Complex methodsFor: 'accessing'!
real
	^real
!
imaginary
	^imaginary
!
setReal: aNumber imaginary: anotherNumber
	real := aNumber.
	imaginary := anotherNumber
! !

!Complex methodsFor: 'arithmetic'!
+ aComplex
	"(Results are made with basicNew setReal:imaginary: directly: one activation less per result, which the Mandelbrot's inner loop feels.)"
	^Complex basicNew setReal: real + aComplex real imaginary: imaginary + aComplex imaginary
!
- aComplex
	^Complex real: real - aComplex real imaginary: imaginary - aComplex imaginary
!
* aComplex
	^Complex
		real: (real * aComplex real) - (imaginary * aComplex imaginary)
		imaginary: (real * aComplex imaginary) + (imaginary * aComplex real)
!
squared
	^Complex basicNew setReal: (real * real) - (imaginary * imaginary) imaginary: 2.0 * real * imaginary
!
squaredMagnitude
	^(real * real) + (imaginary * imaginary)
!
abs
	^self squaredMagnitude sqrt
! !

!Complex methodsFor: 'comparing'!
= aComplex
	^(aComplex isKindOf: Complex) and: [real = aComplex real and: [imaginary = aComplex imaginary]]
!
hash
	^(real hash hashMultiply + imaginary hash) hashMultiply
! !

!Complex methodsFor: 'printing'!
printOn: aStream
	aStream print: real.
	imaginary negative
		ifTrue: [aStream nextPutAll: ' - '; print: imaginary negated]
		ifFalse: [aStream nextPutAll: ' + '; print: imaginary].
	aStream nextPut: $i
! !

!Complex class methodsFor: 'instance creation'!
real: aNumber imaginary: anotherNumber
	^self basicNew setReal: aNumber imaginary: anotherNumber
!
zero
	^self real: 0.0 imaginary: 0.0
! !
