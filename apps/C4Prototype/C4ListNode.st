Object subclass: #C4ListNode
	instanceVariableNames: 'previous next'
	classVariableNames: ''
	package: 'C4Prototype'!

!C4ListNode methodsFor: 'private - linking'!
next
	^next
!
next: aNode
	next := aNode
!
previous: aNode
	previous := aNode
!
insertBefore: head
	"Prepend; the heap owns the head pointer."
	next := head.
	head notNil ifTrue: [head previous: self].
	^self
!
unlink
	previous notNil ifTrue: [previous next: next].
	next notNil ifTrue: [next previous: previous].
	previous := next := nil
! !
