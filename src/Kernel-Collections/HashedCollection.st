Collection subclass: #HashedCollection
	instanceVariableNames: 'tally array'
	classVariableNames: ''
	package: 'Kernel-Collections'!

HashedCollection comment: 'I am the abstract class of hash tables with open addressing: an element (or, in a Dictionary, its key) lives at (hash \\ array size) + 1 or in the next free slot after it (linear probing, wrapping around). nil marks an empty slot. The capacity is at least twice tally and taken from a list of primes (see HashedCollection class>>capacities), so that every bit of a hash takes part in choosing the slot. This layout (exactly the fields tally and array) is shared with the image builder, which builds the seed dictionaries with power-of-two capacities and the same home slots (hash \\ array size + 1): they work as they are, where nothing rehashes them (the Smalltalk-80 guest, vm/tests/mini); the image''s startup rehashes all instances.'!

!HashedCollection methodsFor: 'accessing'!
size
	^tally
!
capacity
	^array size
! !

!HashedCollection methodsFor: 'testing'!
isEmpty
	^tally = 0
! !

!HashedCollection methodsFor: 'removing'!
removeAll
	self init: (self class capacityAtLeast: 0)
! !

!HashedCollection methodsFor: 'copying'!
postCopy
	array := array copy
! !

!HashedCollection methodsFor: 'private'!
init: capacity
	tally := 0.
	array := Array new: capacity
!
scanFor: anObject
	"Answer the index of the slot holding anObject (or its key), or of the empty slot where it would go."
	^self subclassResponsibility
!
keyOf: element
	"Answer what element is hashed by."
	^element
!
atNewIndex: index put: anObject
	array at: index put: anObject.
	tally := tally + 1.
	self fullCheck
!
fullCheck
	"Keep the load factor at most one half."
	tally * 2 > array size ifTrue: [self growTo: (self class capacityAtLeast: array size * 2)]
!
growTo: newCapacity
	"Reinsert every element into a fresh array of newCapacity slots."
	| oldArray |
	oldArray := array.
	array := Array new: newCapacity.
	1 to: oldArray size do: [:i |
		| element |
		element := oldArray at: i.
		element isNil ifFalse: [array at: (self scanFor: (self keyOf: element)) put: element]]
!
rehash
	"Reinsert all elements, e.g. after their hashes changed."
	self growTo: (self class capacityAtLeast: (tally * 2 max: array size))
!
removeIndex: index
	"Empty the slot at index and move the following elements of its cluster to where probing finds them."
	| i element newIndex |
	array at: index put: nil.
	tally := tally - 1.
	i := index.
	[(i := i + 1) > array size ifTrue: [i := 1].
	 (element := array at: i) isNil] whileFalse: [
		newIndex := self scanFor: (self keyOf: element).
		newIndex = i ifFalse: [
			array at: newIndex put: element.
			array at: i put: nil]]
!
array
	^array
! !

!HashedCollection class methodsFor: 'instance creation'!
new
	"Answer an empty instance of the smallest capacity, 7: room for 3 elements (most hashed collections stay that small)."
	^self new: 3
!
new: n
	"Answer an empty instance with room for n elements."
	^self basicNew init: (self capacityAtLeast: n * 2)
!
rehashAll
	"Rehash every instance of me and my subclasses (startup: the bootstrapper's hashes may differ from ours)."
	self withAllSubclassesDo: [:class | class allInstances do: [:each | each rehash]]
! !

!HashedCollection class methodsFor: 'private'!
capacities
	"Primes: 7 for empty instances, then about four per octave from 11 to above 2^31: for each i the smallest prime p at least 11 * 2^(i/4) that is not within 5% of a power of two and, so that keys made of bytes or packed into bit fields (x * 65536 + y) spread over the slots, above 288 divides no 256^k + a (1 <= k <= 8, |a| <= 32; Knuth, TAOCP 6.4) and above 1024 passes a two-dimensional spectral test: for each such k with 256^(2k) >= p, no c * 256^k = a (mod p) with 0 < (c * c) + (a * a) < (p / 4). tools/hash-capacities.py generates the list."
	^#(7 11 17 19 23 29 37 41 43 47 53 71 79 89 107 137 149 179 211 269 347 367 463 541 599 709 859 1097 1319
		1571 1721 2153 2417 2851 3389 4391 4787 5779 6823 8641 9661 11321 13477 17321 18973 22691 26821
		34429 38039 45179 53593 69029 75793 90197 107197 137659 151579 180463 214531 275323 303217 360649
		428677 550651 606323 721381 857567 1101179 1212703 1442393 1714631 2202329 2425669 2884537 3429193
		4404347 4850891 5768401 6858479 8808307 9700907 11536079 13716749 17616497 19400879 23071051
		27434189 35232683 38800523 46140671 54866923 70465151 77599001 92279351 109733821 140929909
		155195039 184556219 219467497 281858959 310385951 369108373 438935011 563716897 620769491 738211429
		877869799 1127432303 1241495383 1476414311 1755739589 2254862653)
!
capacityAtLeast: n
	"Answer the smallest of my capacities that is at least n (beyond them, an odd number)."
	| capacities |
	capacities := self capacities.
	1 to: capacities size do: [:i | (capacities at: i) >= n ifTrue: [^capacities at: i]].
	^n bitOr: 1
! !
