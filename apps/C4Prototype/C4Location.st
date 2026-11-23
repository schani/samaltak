Object subclass: #C4Location
	instanceVariableNames: 'address owner entry sourceEpoch target nextFree'
	classVariableNames: ''
	package: 'C4Prototype'!

C4Location comment: 'A recyclable address cell. Validate a reference by matching the installed incarnation or the forwarding source, not by address alone.'!

!C4Location methodsFor: 'private - addressing'!
address: anInteger owner: aToken
	address := anInteger.
	owner := aToken.
	^self
!
address
	^address
!
owner
	^owner
!
entryFor: ref epoch: color
	entry notNil ifTrue: [
		^entry reference epoch = ref epoch ifTrue: [entry] ifFalse: [nil]].
	(sourceEpoch = ref epoch and: [target epoch = color]) ifFalse: [^nil].
	"Only one hop: the target was installed this cycle, and will not move again this cycle."
	^target location entryFor: target epoch: color
!
install: anEntry epoch: color
	| ref |
	nextFree := sourceEpoch := target := nil.
	ref := C4Ref location: self epoch: color.
	entry := anEntry.
	entry reference: ref.
	^ref
!
forward: oldRef to: newRef
	entry := nil.
	sourceEpoch := oldRef epoch.
	target := newRef
!
discard
	entry := nil
! !

!C4Location methodsFor: 'private - free list'!
nextFree
	^nextFree
!
nextFree: aLocation
	nextFree := aLocation
! !
