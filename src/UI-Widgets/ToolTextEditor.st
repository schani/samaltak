TextEditor subclass: #ToolTextEditor
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

ToolTextEditor comment: 'I am the tools'' text editor: a TextEditor that also takes the keys when remote control selects text in me (samaltak-ctl select), as selecting with the mouse does, so a following key command (⌘P) acts on that selection instead of first clicking somewhere into me.'!

!ToolTextEditor methodsFor: 'remote control'!
remoteSelect: aSpec
	^self inWindowWait: [self selectAndFocus: aSpec]
!
remoteSelect: aSpec then: aBlock
	self inWindowDo: [aBlock value: (self selectAndFocus: aSpec)]
!
selectAndFocus: aSpec
	| answer w |
	answer := self selectSpec: aSpec.
	w := self window.
	w isNil ifFalse: [
		w keyboardFocus == self ifFalse: [w keyboardFocus: self].
		w isFocused ifFalse: [w focus]].
	^answer
! !
