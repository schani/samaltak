Application subclass: #TestApplication
	instanceVariableNames: 'label log'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

TestApplication comment: 'An Application for ApplicationTest: a fixed-size Label that logs its hooks.'!

!TestApplication methodsFor: 'accessing'!
title
	^'Test application'
!
content
	label isNil ifTrue: [label := Label text: 'Hello' font: #ui].
	^label
!
extent
	^240 @ 90
!
log
	^(log ifNil: [#()]) asArray
! !

!TestApplication methodsFor: 'hooks'!
prepare
	log := OrderedCollection with: #prepare
!
started
	log add: #started
!
stopped
	log add: #stopped
!
addMenuItemsTo: aMenu
	aMenu add: 'Own item' action: [log add: #ownItem]
! !
