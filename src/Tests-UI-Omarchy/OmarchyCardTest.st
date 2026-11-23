TestCase subclass: #OmarchyCardTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Omarchy'!

OmarchyCardTest comment: 'Tests what desktop-card apps share: OmarchyCard''s wrapping as Qt''s Text wraps, truncating, scrolling past maxHeight, and drawing a meter; Omarchy''s card settings and monitor sizes.'!

!OmarchyCardTest methodsFor: 'support'!
font
	^Font face: (Font faceNamed: 'JetBrainsMono-Regular') size: 12
! !

!OmarchyCardTest methodsFor: 'tests'!
testWrapAtSpaces
	| f w lines |
	f := self font.
	w := f naturalWidthOf: 'aaaa bbbb'.
	lines := OmarchyCard lines: 'aaaa bbbb cccc dd' width: w font: f.
	self assert: lines equals: #('aaaa bbbb' 'cccc dd').
	"paragraphs and empty lines stay"
	lines := OmarchyCard lines: 'one
' , '
two' width: w font: f.
	self assert: lines equals: #('one' '' 'two').
	"a word longer than a line is broken where it no longer fits"
	lines := OmarchyCard lines: 'abcdefghijklmnop' width: (f naturalWidthOf: 'abcdef') font: f.
	self assert: lines first equals: 'abcdef'.
	self assert: (lines inject: '' into: [:a :b | a, b]) equals: 'abcdefghijklmnop'.
	self assert: (OmarchyCard lines: '' width: w font: f) equals: #('')
!
testTruncate
	| f |
	f := self font.
	self assert: (OmarchyCard truncate: 'short' to: 200 font: f) equals: 'short'.
	self assert: (OmarchyCard truncate: 'a rather long title' to: (f naturalWidthOf: 'a rather…') font: f) equals: 'a rather…'
!
testCardSettings
	| json |
	json := '{"cards": [{"id": "agents", "column": 0}, {"id": "wodify", "settings": {"hide": ["Warm Up"], "days": 1}}]}'.
	self assert: ((Omarchy cardSettings: 'wodify' in: json) at: 'days') equals: 1.
	self assert: (Omarchy cardSettings: 'agents' in: json) isEmpty.
	self assert: (Omarchy cardSettings: 'weather' in: json) isEmpty.
	self assert: (Omarchy cardSettings: 'wodify' in: 'not json') isEmpty.
	self assert: (Omarchy cardSettings: 'wodify' in: nil) isEmpty
!
testMonitorExtent
	| m |
	m := Dictionary new at: 'width' put: 3024; at: 'height' put: 1964; at: 'scale' put: 2; at: 'transform' put: 0; yourself.
	self assert: (Omarchy extentOfMonitor: m) equals: 1512 @ 982.
	m at: 'transform' put: 1.
	self assert: (Omarchy extentOfMonitor: m) equals: 982 @ 1512
! !
