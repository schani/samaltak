VMPrimitiveModule subclass: #DisplayPrimitives
	instanceVariableNames: 'display opened'
	classVariableNames: ''
	package: 'VM-Core'!

DisplayPrimitives comment: 'The guest display primitives (200-206): a 1-bit screen with a fixed-width font, and its input. Arguments are SmallIntegers (pixels, at most 32767 in size); the receiver is ignored; what falls outside the screen is clipped. Only a simulated VM has a guest display (GuestDisplay): in C displayOpen fails, and so does the rest.

	displayOpen	w h	open the screen, white; answer the character cell (a Point)
	displayFill	x y w h rule	rule 0 white, 1 black, 2 grey (the desk''s pattern), 3 inverted
	displayCopy	x y w h toX toY	the rectangle''s pixels to toX@toY (they may overlap)
	displayText	string x y rule	a byte string, one cell per character, its top left at x@y; rule 0 black on white, 1 white on black
	displayBits	bytes x y w h rule	w by h pixels, rows of (w + 7) // 8 bytes, the high bit leftmost; rule 0 opaque, 1 the set bits black, 2 the set bits inverted
	displayNextEvent	anArray	fill the 5-slot Array with the next input event and answer it, or answer nil
	displayFlush		the frame is complete: show it

Events: {type. x. y. key. modifiers}. type 1 mouse down, 2 up, 3 move (a button down), 4 key. key: the button (1 left, 2 right), or the character code (8 backspace, 9 tab, 13 return, 27 escape, 28-31 left right up down, 127 delete). modifiers: shift 1, ctrl 2, alt 4, cmd 8.'!

!DisplayPrimitives class methodsFor: 'declaring'!
declarations
	^#((display GuestDisplay) (opened bool))
! !

!DisplayPrimitives methodsFor: 'arguments'!
ints: n from: first
	"Whether the screen is open and arguments first .. first + n - 1 are the last ones and SmallIntegers of 16 bits."
	<function>
	| v |
	(opened and: [self argCount = (first + n)]) ifFalse: [^false].
	first to: first + n - 1 do: [:i |
		v := self arg: i.
		((self isInt: v) and: [(self intVal: v) >= -32768 and: [(self intVal: v) <= 32767]]) ifFalse: [^false]].
	^true
!
int: i
	^(self intVal: (self arg: i)) asInt32
!
rule: i below: n
	"Argument i, a rule, if it is below n; else -1."
	^((self int: i) >= 0 and: [(self int: i) < n]) ifTrue: [self int: i] ifFalse: [-1]
! !

!DisplayPrimitives methodsFor: 'primitives'!
primDisplayOpen
	<vmPrimitive: 200 name: 'displayOpen'>
	| cell p |
	opened := false.
	(self argCount = 2 and: [(self isInt: (self arg: 0)) and: [self isInt: (self arg: 1)]]) ifFalse: [^self fail].
	((self intVal: (self arg: 0)) < 1 or: [(self intVal: (self arg: 0)) > 4096]) ifTrue: [^self fail].
	((self intVal: (self arg: 1)) < 1 or: [(self intVal: (self arg: 1)) > 4096]) ifTrue: [^self fail].
	cell := self local: 'int32_t[2]'.
	(display open: (self int: 0) height: (self int: 1) cell: cell) ifFalse: [^self fail].
	opened := true.
	p := memory allocObj: memory clsPoint format: F_FIXED slots: 2.
	self storeRef: p at: 0 put: (self intOop: (cell at: 0)).
	self storeRef: p at: 1 put: (self intOop: (cell at: 1)).
	self answer: p
!
primDisplayFill
	<vmPrimitive: 201 name: 'displayFill'>
	<leaf>
	((self ints: 5 from: 0) and: [(self rule: 4 below: 4) >= 0]) ifFalse: [^self fail].
	display fillX: (self int: 0) y: (self int: 1) width: (self int: 2) height: (self int: 3) rule: (self int: 4).
	self answer: self receiver
!
primDisplayCopy
	<vmPrimitive: 202 name: 'displayCopy'>
	<leaf>
	(self ints: 6 from: 0) ifFalse: [^self fail].
	display copyX: (self int: 0) y: (self int: 1) width: (self int: 2) height: (self int: 3) toX: (self int: 4) y: (self int: 5).
	self answer: self receiver
!
primDisplayText
	<vmPrimitive: 203 name: 'displayText'>
	<leaf>
	| s |
	((self ints: 3 from: 1) and: [(self rule: 3 below: 2) >= 0]) ifFalse: [^self fail].
	s := self arg: 0.
	((self isPtr: s) and: [(self formatOf: s) >= F_BYTES]) ifFalse: [^self fail].
	display text: (self bytesOf: s) size: (memory byteSize: s) x: (self int: 1) y: (self int: 2) rule: (self int: 3).
	self answer: self receiver
!
primDisplayBits
	<vmPrimitive: 204 name: 'displayBits'>
	<leaf>
	| b |
	((self ints: 5 from: 1) and: [(self rule: 5 below: 3) >= 0 and: [(self int: 3) >= 0 and: [(self int: 4) >= 0]]]) ifFalse: [^self fail].
	b := self arg: 0.
	((self isPtr: b) and: [(self formatOf: b) >= F_BYTES and: [(memory byteSize: b) >= (((self int: 3) + 7 quo: 8) * (self int: 4)) asUInt64]]) ifFalse: [^self fail].
	display bits: (self bytesOf: b) x: (self int: 1) y: (self int: 2) width: (self int: 3) height: (self int: 4) rule: (self int: 5).
	self answer: self receiver
!
primDisplayNextEvent
	<vmPrimitive: 205 name: 'displayNextEvent'>
	<leaf>
	| a event |
	a := self arg0.
	(opened and: [self argCount = 1 and: [(self isPtr: a) and: [(self formatOf: a) = F_VAR and: [(self numSlots: a) = 5 and: [(self isImmutable: a) not]]]]]) ifFalse: [^self fail].
	event := self local: 'int64_t[5]'.
	(display nextEvent: event) ifFalse: [^self answer: memory nilOop].
	0 to: 4 do: [:i | self storeRef: a at: i put: (self intOop: (event at: i))].
	self answer: a
!
primDisplayFlush
	<vmPrimitive: 206 name: 'displayFlush'>
	<leaf>
	opened ifFalse: [^self fail].
	display flush.
	self answer: self receiver
! !
