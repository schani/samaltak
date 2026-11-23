C4ListNode subclass: #C4Object
	instanceVariableNames: 'reference mark grayNext slots destination copied'
	classVariableNames: ''
	package: 'C4Prototype'!

C4Object comment: 'A logical resident with two buffers, allocated by the mutator. During evacuation, the copied prefix lives in destination and the remaining suffix in slots. The split gives each slot a single authoritative home between any two steps.'!

!C4Object methodsFor: 'private - initialization'!
initializeSlots: slotCount
	slots := Array new: slotCount.
	destination := Array new: slotCount.
	copied := 0.
	^self
! !

!C4Object methodsFor: 'private - metadata'!
reference
	^reference
!
reference: ref
	reference := ref
!
mark
	^mark
!
mark: color
	mark := color
!
grayNext
	^grayNext
!
grayNext: entry
	grayNext := entry
! !

!C4Object methodsFor: 'private - slots'!
size
	^slots size
!
bufferAt: index
	index isInteger ifFalse: [self error: 'Invalid slot index'].
	^index <= copied ifTrue: [destination] ifFalse: [slots]
!
slotAt: index
	^(self bufferAt: index) at: index
!
slotAt: index put: ref
	^(self bufferAt: index) at: index put: ref
!
copyComplete
	^copied = slots size
!
copySlot
	| index |
	index := copied + 1.
	destination at: index put: (slots at: index).
	slots at: index put: nil.
	copied := index
!
finishCopy
	| old |
	old := slots.
	slots := destination.
	destination := old.
	copied := 0
! !
