Object subclass: #Omarchy
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Omarchy'!

Omarchy comment: 'I am what applications ask of the Omarchy desktop (omarchy.org), class side: where it is installed, the settings the desktop cards plugin keeps for a card, the size of the screen, and its shell''s panels. Colors, fonts and spacing are OmarchyTheme''s.

	Omarchy path                               "$OMARCHY_PATH, else /usr/share/omarchy"
	Omarchy cardSettings: ''wodify''           "the card''s settings in ~/.config/omarchy/desktop-cards.json"
	Omarchy screenExtent                       "the focused monitor in points (hyprctl), nil if unknown"
	Omarchy togglePanel: ''omarchy.agents''     "open or close a panel of the bar (omarchy-shell)"
	Omarchy launch: #(''xdg-open'' ''https://omarchy.org'')'!

!Omarchy class methodsFor: 'installation'!
path
	"Where Omarchy is installed."
	^(Smalltalk vm getenv: 'OMARCHY_PATH') ifNil: ['/usr/share/omarchy']
!
isAvailable
	^File exists: self path
! !

!Omarchy class methodsFor: 'desktop cards'!
cardsPath
	^XDG config: 'omarchy/desktop-cards.json'
!
cardSettings: anId
	"The settings of the desktop card anId (a Dictionary, empty if it has none)."
	^self cardSettings: anId in: ([File readText: self cardsPath] on: Error do: [:e | e return: nil])
!
cardSettings: anId in: aJSONString
	| layout cards |
	aJSONString isNil ifTrue: [^Dictionary new].
	layout := [JSON parse: aJSONString] on: Error do: [:e | e return: nil].
	(layout isKindOf: Dictionary) ifFalse: [^Dictionary new].
	cards := layout at: 'cards' ifAbsent: [#()].
	(cards isKindOf: Array) ifFalse: [^Dictionary new].
	cards do: [:each |
		((each isKindOf: Dictionary) and: [(each at: 'id' ifAbsent: [nil]) = anId]) ifTrue: [
			| settings |
			settings := each at: 'settings' ifAbsent: [nil].
			^(settings isKindOf: Dictionary) ifTrue: [settings] ifFalse: [Dictionary new]]].
	^Dictionary new
! !

!Omarchy class methodsFor: 'screen'!
screenExtent
	"The focused monitor's size in points (pixels over its scale, turned when it is), as Hyprland reports it; nil without Hyprland."
	| monitors |
	monitors := [JSON parse: (OSProcess outputOf: 'hyprctl monitors -j')] on: Error do: [:e | e return: nil].
	(monitors isKindOf: Array) ifFalse: [^nil].
	monitors isEmpty ifTrue: [^nil].
	^self extentOfMonitor: (monitors detect: [:m | (m at: 'focused' ifAbsent: [false]) == true] ifNone: [monitors first])
!
extentOfMonitor: aDictionary
	| w h scale transform |
	w := aDictionary at: 'width' ifAbsent: [^nil].
	h := aDictionary at: 'height' ifAbsent: [^nil].
	scale := (aDictionary at: 'scale' ifAbsent: [1]) max: 0.1.
	transform := aDictionary at: 'transform' ifAbsent: [0].
	"transforms 1, 3, 5 and 7 turn the monitor a quarter"
	(transform isInteger and: [transform odd]) ifTrue: [| t | t := w. w := h. h := t].
	^(w / scale) rounded @ (h / scale) rounded
! !

!Omarchy class methodsFor: 'shell'!
togglePanel: aName
	"Open or close a panel of the Omarchy bar (omarchy.weather, omarchy.agents ...), as a desktop card's click does."
	self launch: (Array with: 'omarchy-shell' with: '-q' with: 'shell' with: 'toggle' with: aName)
!
launch: anArrayOfStrings
	"Run a program without waiting for it."
	^self launch: anArrayOfStrings then: nil
!
launch: anArrayOfStrings then: aBlock
	"Run a program; when it ends, aBlock (if any) runs with its OSProcess, in a Process of its own."
	[| p |
	 p := OSProcess command: (OSProcess commandFor: anArrayOfStrings).
	 p start; wait.
	 aBlock isNil ifFalse: [aBlock value: p]] forkAt: Processor userBackgroundPriority
! !
