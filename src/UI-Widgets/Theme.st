Object subclass: #Theme
	instanceVariableNames: 'name colors fonts metrics syntax terminal'
	classVariableNames: 'Current'
	package: 'UI-Widgets'!

Theme comment: 'I am the look of the widgets: named colors, fonts and metrics. "Theme current" is the Blue Book theme with pi-orb typography (prototypes/1-classic/themes/blue-book.css, types/pi-orb.css): black on white, 1-point black rules, inversion for selection, ultramarine as the only accent.

	Theme current color: #ink3.
	Theme current font: #code.
	Theme current metric: #rowHeight.

Widgets ask me instead of hard-coding values, so a theme switch is "Theme current: aTheme" followed by a redraw. Fonts are created lazily, and again for another Font deviceScale. The current theme publishes its accent and inks as Color''s named colors, which the window system''s chrome draws with.

Change me while the system runs: when a method of mine (or Color''s) is accepted, the current theme defines its colors and metrics again (refresh) and every window redraws (SystemChanges).'!

!Theme methodsFor: 'initialization'!
setName: aString
	name := aString.
	colors := IdentityDictionary new.
	fonts := IdentityDictionary new.
	metrics := IdentityDictionary new
!
initializeBlueBook
	| ultra |
	ultra := Color hex: 16r1B3A8C.
	colors
		at: #ink put: Color black;
		at: #ink2 put: (Color hex: 16r3A3A3A);
		at: #ink3 put: (Color hex: 16r6B6B6B);
		at: #ink4 put: (Color hex: 16rA6A6A6);
		at: #hair put: (Color hex: 16rC9C9C9);
		at: #paper put: Color white;
		at: #rule put: Color black;
		at: #ultramarine put: ultra;
		at: #accentSoft put: (ultra alpha: 0.12);
		at: #textSelection put: (ultra alpha: 0.22);
		at: #textSelectionInactive put: (Color black alpha: 0.07);
		at: #busySoft put: (ultra alpha: 0.10);
		at: #wash put: (Color black alpha: 0.06);
		at: #inverseMuted put: (Color white alpha: 0.7);
		at: #inverseKey put: (Color white alpha: 0.75);
		at: #comment put: (Color hex: 16r5E5E5E);
		at: #l0 put: Color black;
		at: #l1 put: ultra;
		at: #l2 put: (Color hex: 16r4A63A6);
		at: #l3 put: (Color hex: 16r7D8FBF);
		at: #l4 put: (Color hex: 16rB4BDD8);
		at: #l5 put: (Color hex: 16rDDE1EC);
		at: #shadow put: Color black;
		at: #desk put: Color white;
		at: #deskDots put: Color black.
	metrics
		at: #rowHeight put: 19;
		at: #groupRowHeight put: 20;
		at: #listPaddingX put: 8;
		at: #listPaddingY put: 1;
		at: #paneHeaderHeight put: 20;
		at: #paneHeaderPaddingX put: 8;
		at: #statusBarHeight put: 20;
		at: #statusBarPaddingX put: 8;
		at: #buttonHeight put: 20;
		at: #buttonPaddingX put: 10;
		at: #segmentHeight put: 18;
		at: #segmentBarPadding put: 3;
		at: #tabHeight put: 20;
		at: #tabPaddingX put: 10;
		at: #editorPaddingX put: 12;
		at: #editorPaddingY put: 7;
		at: #tabWidth put: 4;
		at: #scrollBarWidth put: 11;
		at: #splitterThickness put: 4;
		at: #menuItemHeight put: 21;
		at: #menuPaddingX put: 12;
		at: #menuTitleHeight put: 21;
		at: #menuMinWidth put: 210;
		at: #toastPaddingX put: 12;
		at: #toastPaddingY put: 7;
		at: #shadowOffset put: 2;
		at: #caretWidth put: 1.5;
		at: #caretBlinkMs put: 530;
		at: #glideMs put: 100;
		at: #fadeMs put: 120;
		at: #flashMs put: 90
! !

!Theme methodsFor: 'refreshing'!
refresh
	"My definition changed: define my colors and metrics again (fonts are kept), forget the syntax styles and publish the palette."
	self initializeBlueBook.
	syntax := nil.
	terminal := nil.
	self publishPalette
!
publishPalette
	"Make my colors Color's named colors where both have the name (the window system's chrome draws with those)."
	| named |
	named := Color namedColors.
	colors keysAndValuesDo: [:key :color |
		(named includesKey: key) ifTrue: [Color named: key put: color]]
! !

!Theme methodsFor: 'accessing'!
name
	^name
!
color: aSymbol
	^colors at: aSymbol ifAbsent: [Color named: aSymbol]
!
color: aSymbol put: aColor
	colors at: aSymbol put: aColor.
	syntax := nil
!
metric: aSymbol
	^metrics at: aSymbol
!
metric: aSymbol put: aNumber
	metrics at: aSymbol put: aNumber
!
font: aSymbol
	"Answer a font by role: the standard ones (ui uiBold uiItalic code codeBold codeItalic header title small smallItalic) and the theme's own sizes (button buttonBold menuKey mono11 codeSmall codeSmallBold toast chip readout)."
	| font |
	font := fonts at: aSymbol ifAbsent: [nil].
	(font isNil or: [font scale ~= Font deviceScale]) ifTrue: [font := fonts at: aSymbol put: (self makeFont: aSymbol)].
	^font
!
makeFont: aSymbol
	| spec font |
	spec := self extraFontSpecs detect: [:each | each first == aSymbol] ifNone: [nil].
	spec isNil ifTrue: [^Font named: aSymbol].
	font := Font faceNamed: (spec at: 2) size: (spec at: 3).
	font lineHeight: (spec at: 4).
	^font
!
extraFontSpecs
	"name, face, pixel size, line height (prototype CSS: .btn 12.5px, .menu-item .k 12.5px, statusbar .mono 11px, debugger stack 12.5px mono)"
	^#(
		#(#button 'IosevkaEtoile-Regular' 12.5 16)
		#(#buttonBold 'IosevkaEtoile-Bold' 12.5 16)
		#(#menuKey 'IosevkaEtoile-Regular' 12.5 16)
		#(#mono11 'JetBrainsMono-Regular' 11 14)
		#(#codeSmall 'JetBrainsMono-Regular' 12.5 18)
		#(#codeSmallBold 'JetBrainsMono-Bold' 12.5 18)
		#(#toast 'IosevkaEtoile-Italic' 13 17)
		#(#chip 'JetBrainsMono-Bold' 10 12)
		#(#readout 'IosevkaEtoile-Bold' 17 20))
!
reset
	"Forget the fonts (after Font deviceScale: changed)."
	fonts := IdentityDictionary new.
	syntax := nil
!
prepareFonts
	"Create the theme's own fonts and rasterize their ASCII glyphs into the atlas (stage 2), so the first menu or button does not stall."
	| chars |
	chars := Font prerasterizedCharacters.
	self extraFontSpecs do: [:spec | (self font: spec first) prerasterize: chars].
	self buildSyntaxStyles
! !

!Theme methodsFor: 'colors'!
ink
	^self color: #ink
!
paper
	^self color: #paper
!
rule
	^self color: #rule
!
ultramarine
	^self color: #ultramarine
!
muted
	^self color: #ink3
!
layerColor: anInteger
	^self color: (#(#l0 #l1 #l2 #l3 #l4 #l5) at: ((anInteger max: 0) min: 5) + 1)
!
ansiColors
	"The 16 ANSI colors of the Terminal (kept until my colors change)."
	^terminal ifNil: [terminal := self terminalPalette]
!
terminalPalette
	"The 16 ANSI colors: tuned for black on white with ultramarine as blue."
	^#(16r000000 16rB3261E 16r2E7D32 16r8A6A00 16r1B3A8C 16r8E3B8E 16r1E7A84 16rB8B8B8
		16r6B6B6B 16rD7372C 16r3C9A46 16rB08A00 16r4A63A6 16rB052B0 16r2A9AA8 16rFFFFFF) collect: [:hex | Color hex: hex]
! !

!Theme methodsFor: 'syntax'!
syntaxStyleFor: aTokenType
	"Answer {font. color} for a Scanner highlight type (Blue Book: comments italic grey, keywords bold, globals ultramarine, pseudo-variables italic, return bold ultramarine)."
	syntax isNil ifTrue: [syntax := self buildSyntaxStyles].
	^syntax at: aTokenType ifAbsent: [syntax at: #identifier]
!
buildSyntaxStyles
	| d plain |
	d := IdentityDictionary new.
	plain := Array with: (self font: #code) with: self ink.
	#(#identifier #string #symbol #number #character #binary #assignment #punctuation #literalArrayStart #error)
		do: [:each | d at: each put: plain].
	d at: #comment put: (Array with: (self font: #codeItalic) with: (self color: #comment)).
	d at: #keyword put: (Array with: (self font: #codeBold) with: self ink).
	d at: #global put: (Array with: (self font: #code) with: self ultramarine).
	#(#self #super #true #false #nil #thisContext)
		do: [:each | d at: each put: (Array with: (self font: #codeItalic) with: self ink)].
	d at: #return put: (Array with: (self font: #codeBold) with: self ultramarine).
	d at: #pattern put: (Array with: (self font: #codeBold) with: self ink).
	^d
! !

!Theme class methodsFor: 'instance creation'!
blueBook
	^self new setName: 'blue-book'; initializeBlueBook; yourself
! !

!Theme class methodsFor: 'class initialization'!
initialize
	Smalltalk addStage2Step: [
		Current := nil.
		Smalltalk isRuntimeImage ifFalse: [self current prepareFonts]] named: 'Widget fonts'.
	SystemChanges subscribe: #Theme do: [:change |
		((change affects: Theme) or: [change affects: Color]) ifTrue: [self themeChanged]]
! !

!Theme class methodsFor: 'current'!
current
	^Current ifNil: [Current := self blueBook]
!
current: aTheme
	Current := aTheme
!
themeChanged
	"My methods or Color's changed: the current theme defines itself again and everything redraws."
	Current isNil ifFalse: [Current refresh].
	World restyleAll
!
reset
	Current isNil ifFalse: [Current reset]
! !
