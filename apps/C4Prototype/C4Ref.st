Object subclass: #C4Ref
	instanceVariableNames: 'location epoch'
	classVariableNames: ''
	package: 'C4Prototype'!

C4Ref comment: 'An immutable colored address. Equality identifies an address incarnation, not logical object identity across moves. Canonicalize with the heap before comparing refs across a move.'!

!C4Ref class methodsFor: 'private - instance creation'!
location: aLocation epoch: color
	^self basicNew initializeLocation: aLocation epoch: color
! !

!C4Ref methodsFor: 'private - addressing'!
initializeLocation: aLocation epoch: color
	location := aLocation.
	epoch := color.
	^self
!
location
	^location
! !

!C4Ref methodsFor: 'accessing'!
address
	^location address
!
epoch
	^epoch
! !

!C4Ref methodsFor: 'comparing'!
= another
	self == another ifTrue: [^true].
	^another class == C4Ref and: [location == another location and: [epoch = another epoch]]
!
hash
	^location identityHash bitXor: epoch hash
! !
