Theme subclass: #OmarchyTheme
	instanceVariableNames: 'directory userShellPath palette shell regular bold italic sized stamp'
	classVariableNames: 'Watcher'
	package: 'UI-Omarchy'!

OmarchyTheme comment: 'I am the look of the Omarchy desktop (omarchy.org) for Samaltak''s widgets, read from the same files the Omarchy shell reads, so an application looks like the shell''s own panels and follows the user''s theme:

	~/.local/state/omarchy/current/theme/colors.toml   the palette (foreground, background, accent, muted, red: urgent)
	~/.local/state/omarchy/current/theme/shell.toml    the surfaces ([popups] background, text, border ...), [font] base-size and tokens, [spacing]
	~/.config/omarchy/shell.toml                       the user''s overrides of shell.toml
	fontconfig''s monospace                            the typeface (omarchy font set), e.g. JetBrainsMono Nerd Font

	OmarchyTheme install.                        "Theme current: the Omarchy theme, kept current with the desktop"
	Theme current shellColor: ''popups.background''
	Theme current font: #title                   "the shell''s type scale: #caption #bodySmall #body #subtitle #title #heading #display #displayLarge, #titleBold ..."
	Theme current fontOfSize: 56 bold: true
	Theme current space: 16                      "Style.space: scaled with the font''s base size"

The colors resolve as the shell''s Color.qml does: a surface key names a color, a role (foreground, accent, urgent, muted, background, transparent) or another key (hyprland.active-border), and its -alpha companion its opacity. Standard widget colors map onto the palette (#ink foreground, #paper background, #ultramarine accent) and the standard fonts onto the Omarchy typeface at their own sizes.

install starts a Process that checks the files once a second; when a theme switch (omarchy theme set), a font switch or an edit of the user''s shell.toml changed them, I read them again and every window redraws.'!

!OmarchyTheme methodsFor: 'initialization'!
setDirectory: aPath userShell: aShellPath
	"The theme in the directory aPath (Omarchy's current one: OmarchyTheme defaultDirectory) and the user's overrides in aShellPath."
	directory := aPath.
	userShellPath := aShellPath.
	self setName: 'omarchy'.
	self load
!
load
	"Read the theme's files and define my colors, fonts and metrics."
	palette := self readTOML: directory, '/colors.toml'.
	shell := self mergedShell.
	stamp := self currentStamp.
	regular := bold := italic := nil.
	terminal := nil.
	sized := Dictionary new.
	fonts := IdentityDictionary new.
	syntax := nil.
	self initializeBlueBook.
	self defineColors.
	metrics at: #panelPadding put: (self spacingToken: 'panel-padding' default: 18).
	(self file: directory, '/../theme.name') ifNotNil: [:text | name := text trimBoth]
!
readTOML: aPath
	"The TOML file at aPath as a Dictionary (empty if missing or not TOML)."
	^[TOMLReader readFile: aPath] on: Error do: [:e | e return: Dictionary new]
!
file: aPath
	^[File readText: aPath] on: Error do: [:e | e return: nil]
!
mergedShell
	"The theme's shell.toml with the user's ~/.config/omarchy/shell.toml over it, key by key."
	| merged |
	merged := self readTOML: directory, '/shell.toml'.
	(self readTOML: self userShellPath) keysAndValuesDo: [:section :values |
		values isDictionary
			ifTrue: [
				| target |
				target := merged at: section ifAbsent: [merged at: section put: Dictionary new].
				values keysAndValuesDo: [:k :v | target at: k put: v]]
			ifFalse: [merged at: section put: values]].
	^merged
!
userShellPath
	^userShellPath
!
defineColors
	| fg bg accent |
	fg := self foreground.
	bg := self background.
	accent := self accent.
	colors
		at: #foreground put: fg;
		at: #background put: bg;
		at: #accent put: accent;
		at: #urgent put: self urgent;
		at: #muted put: self muted;
		at: #ink put: fg;
		at: #ink2 put: (fg mixed: 0.25 with: bg);
		at: #ink3 put: (fg mixed: 0.45 with: bg);
		at: #ink4 put: (fg mixed: 0.65 with: bg);
		at: #hair put: (fg mixed: 0.8 with: bg);
		at: #paper put: bg;
		at: #rule put: fg;
		at: #ultramarine put: accent;
		at: #accentSoft put: (accent alpha: 0.12);
		at: #textSelection put: ((self paletteColor: 'selection') ifNil: [accent alpha: 0.22]);
		at: #textSelectionInactive put: (fg alpha: 0.07);
		at: #busySoft put: (accent alpha: 0.10);
		at: #wash put: (fg alpha: 0.06);
		at: #inverseMuted put: (bg alpha: 0.7);
		at: #inverseKey put: (bg alpha: 0.75);
		at: #comment put: (fg mixed: 0.4 with: bg);
		at: #l0 put: fg;
		at: #l1 put: accent;
		at: #l2 put: (accent mixed: 0.3 with: bg);
		at: #l3 put: (accent mixed: 0.5 with: bg);
		at: #l4 put: (accent mixed: 0.7 with: bg);
		at: #l5 put: (accent mixed: 0.85 with: bg);
		at: #shadow put: (self isDark ifTrue: [Color black] ifFalse: [fg]);
		at: #desk put: ((self paletteColor: 'dark_background') ifNil: [bg]);
		at: #deskDots put: self muted;
		at: #popupBackground put: (self composed: 'popups.background' alpha: 'popups.background-alpha' default: bg alpha: 1.0);
		at: #popupText put: (self flatColor: (self shellValue: 'popups.text') default: fg);
		at: #popupBorder put: (self composed: 'popups.border' alpha: 'popups.border-alpha' default: accent alpha: 1.0);
		at: #barBackground put: (self composed: 'bar.background' alpha: 'bar.background-alpha' default: bg alpha: 1.0);
		at: #barText put: (self flatColor: (self shellValue: 'bar.text') default: fg)
! !

!OmarchyTheme methodsFor: 'refreshing'!
refresh
	"My definition or my files changed: read them again (fonts too: the typeface may have changed)."
	self load.
	Theme current == self ifTrue: [
		self publishPalette.
		self applyFonts]
! !

!OmarchyTheme methodsFor: 'accessing'!
directory
	^directory
!
palette
	"colors.toml as a Dictionary."
	^palette
!
shell
	"shell.toml (with the user's overrides) as a Dictionary of sections."
	^shell
!
isDark
	^(palette at: 'mode' ifAbsent: ['dark']) ~= 'light'
! !

!OmarchyTheme methodsFor: 'palette'!
foreground
	^(self paletteColor: 'foreground') ifNil: [(self paletteColor: 'color7') ifNil: [Color hex: 16rCACCCC]]
!
background
	^(self paletteColor: 'background') ifNil: [(self paletteColor: 'color0') ifNil: [Color hex: 16r101315]]
!
accent
	^(self paletteColor: 'accent') ifNil: [(self paletteColor: 'color4') ifNil: [Color hex: 16rCACCCC]]
!
urgent
	^(self paletteColor: 'red') ifNil: [(self paletteColor: 'color1') ifNil: [Color hex: 16rA55555]]
!
muted
	^(self paletteColor: 'muted') ifNil: [(self paletteColor: 'color8') ifNil: [self foreground]]
!
paletteColor: aKey
	"The color colors.toml gives aKey, or nil."
	^self class parseColor: (palette at: aKey ifAbsent: [nil])
! !

!OmarchyTheme methodsFor: 'surfaces'!
shellValue: aDottedKey
	"The value shell.toml gives 'section.key' (a String or Number), or nil."
	| i section |
	i := aDottedKey indexOf: $..
	i = 0 ifTrue: [^nil].
	section := shell at: (aDottedKey first: i - 1) ifAbsent: [^nil].
	section isDictionary ifFalse: [^nil].
	^section at: (aDottedKey allButFirst: i) ifAbsent: [nil]
!
shellNumber: aDottedKey default: aNumber
	| v |
	v := self shellValue: aDottedKey.
	v isNumber ifTrue: [^v].
	v isString ifTrue: [^Number readFrom: v ifFail: [aNumber]].
	^aNumber
!
shellColor: aDottedKey
	"The color of a surface key, its -alpha companion applied: shellColor: 'popups.border'."
	^self composed: aDottedKey alpha: aDottedKey, '-alpha' default: self foreground alpha: 1.0
!
composed: colorKey alpha: alphaKey default: aColor alpha: aNumber
	| alpha |
	alpha := ((self shellNumber: alphaKey default: aNumber) max: 0) min: 1.
	^(self flatColor: (self shellValue: colorKey) default: aColor) alpha: alpha
!
flatColor: aValue default: aColor
	"aValue (a color, a role or another key; a gradient's first stop) as a Color, else aColor."
	| token role seen |
	aValue isString ifFalse: [^aColor].
	seen := Set new.
	token := self firstColorToken: aValue.
	role := token asLowercase.
	[(self shellValue: role) isString and: [(self shellValue: role) ~= token]] whileTrue: [
		(seen includes: role) ifTrue: [^aColor].
		seen add: role.
		token := self firstColorToken: (self shellValue: role).
		role := token asLowercase].
	(role = 'foreground' or: [role = 'text']) ifTrue: [^self foreground].
	role = 'accent' ifTrue: [^self accent].
	role = 'urgent' ifTrue: [^self urgent].
	role = 'muted' ifTrue: [^self muted].
	role = 'background' ifTrue: [^self background].
	role = 'transparent' ifTrue: [^Color transparent].
	^(self class parseColor: token) ifNil: [aColor]
!
firstColorToken: aString
	"The first word of aString that is no angle (a Hyprland gradient: 'rgba(33ccffee) rgba(00ff99ee) 45deg')."
	^aString substrings detect: [:each | (each endsWith: 'deg') not] ifNone: [aString trimBoth]
! !

!OmarchyTheme methodsFor: 'fonts'!
baseSize
	"[font] base-size: the rem of the type scale (12)."
	^((self shellNumber: 'font.base-size' default: 12) max: 1)
!
fontScale
	^self baseSize / 12 max: 1 / 12
!
pixelsOf: aToken
	"The pixel size of a token of the shell's type scale (Style.font): [font] overrides it, else base-size times its factor."
	| key factor override |
	key := self class tokenKeys at: aToken ifAbsent: [^nil].
	factor := self class tokenFactors at: aToken.
	override := self shellNumber: 'font.', key default: nil.
	(override notNil and: [override > 0]) ifTrue: [^override rounded].
	^(self baseSize * factor) rounded max: 1
!
regularFace
	^regular ifNil: [regular := self class fontconfigFace: 'monospace' fallback: 'JetBrainsMono-Regular']
!
boldFace
	^bold ifNil: [bold := self class fontconfigFace: 'monospace:bold' fallback: 'JetBrainsMono-Bold']
!
italicFace
	^italic ifNil: [italic := self class fontconfigFace: 'monospace:italic' fallback: 'JetBrainsMono-Italic']
!
applyFonts
	"Code is drawn in the Omarchy typeface (omarchy font set): it takes the place of Samaltak's code face, JetBrains Mono, wherever that is drawn; the UI face (Iosevka Etoile) stays."
	Font substituteFace: 'JetBrainsMono-Regular' with: self regularFace.
	Font substituteFace: 'JetBrainsMono-Bold' with: self boldFace.
	Font substituteFace: 'JetBrainsMono-Italic' with: self italicFace
!
terminalPalette
	"The 16 ANSI colors as Omarchy's terminals have them (default/themed/alacritty.toml.tpl): black the background, white the foreground, bright black muted."
	| bg fg |
	bg := self background.
	fg := self foreground.
	^#('background' 'red' 'green' 'yellow' 'blue' 'magenta' 'cyan' 'foreground'
		'muted' 'bright_red' 'bright_green' 'bright_yellow' 'bright_blue' 'bright_magenta' 'bright_cyan' 'bright_foreground')
		collect: [:key |
			key = 'background' ifTrue: [bg] ifFalse: [
				key = 'foreground' ifTrue: [fg] ifFalse: [
					key = 'muted' ifTrue: [self muted] ifFalse: [
						(self paletteColor: key) ifNil: [(self paletteColor: (key copyReplaceAll: 'bright_' with: '')) ifNil: [fg]]]]]]
!
fontOfSize: pixels bold: aBoolean
	"The Omarchy typeface at pixels, regular or bold."
	^self fontOfSize: pixels bold: aBoolean letterSpacing: 0
!
fontOfSize: pixels bold: aBoolean letterSpacing: points
	"The Omarchy typeface at pixels, regular or bold, with points between letters (the shell's tracked captions use 1)."
	^self fontOfSize: pixels style: (aBoolean ifTrue: [#bold] ifFalse: [#regular]) letterSpacing: points
!
fontOfSize: pixels style: aSymbol letterSpacing: points
	"The Omarchy typeface at pixels in aSymbol (#regular, #bold or #italic), with points between letters."
	| key |
	key := Array with: pixels with: aSymbol with: points with: Font deviceScale.
	^sized at: key ifAbsent: [
		| font |
		font := Font face: (aSymbol == #bold ifTrue: [self boldFace] ifFalse: [aSymbol == #italic ifTrue: [self italicFace] ifFalse: [self regularFace]]) size: pixels.
		points = 0 ifFalse: [font letterSpacing: points].
		sized at: key put: font]
!
makeFont: aSymbol
	"The shell's tokens (#title, #titleBold ...) in the Omarchy typeface; the standard fonts as the Blue Book has them (the UI in Iosevka Etoile, code in the Omarchy typeface: applyFonts)."
	| token isBold size |
	isBold := aSymbol endsWith: 'Bold'.
	token := isBold ifTrue: [(aSymbol allButLast: 4) asSymbol] ifFalse: [aSymbol].
	size := self pixelsOf: token.
	size isNil ifTrue: [^super makeFont: aSymbol].
	^Font face: (isBold ifTrue: [self boldFace] ifFalse: [self regularFace]) size: size
! !

!OmarchyTheme methodsFor: 'spacing'!
space: points
	"Style.space: points scaled with [spacing] scale (and the font's base size if scale-with-font), at least 1."
	| scale |
	points <= 0 ifTrue: [^0].
	scale := self shellNumber: 'spacing.scale' default: 1.0.
	(self shellValue: 'spacing.scale-with-font') == false ifFalse: [scale := scale * self fontScale].
	^(points * scale) rounded max: 1
!
spacingToken: aKey default: points
	| v |
	v := self shellNumber: 'spacing.', aKey default: nil.
	(v notNil and: [v >= 0]) ifTrue: [^v rounded].
	^self space: points
! !

!OmarchyTheme methodsFor: 'watching'!
currentStamp
	"What changes when the desktop's look does: the theme generation, the theme's and the user's files, fontconfig's configuration."
	^(Array with: directory, '/../theme.generation' with: directory, '/colors.toml' with: directory, '/shell.toml' with: self userShellPath),
		(Array with: (XDG config: 'fontconfig/fonts.conf'))
		collect: [:path | [File modificationTime: path] on: Error do: [:e | e return: nil]]
!
isStale
	^self currentStamp ~= stamp
! !

!OmarchyTheme class methodsFor: 'installing'!
defaultDirectory
	^XDG state: 'omarchy/current/theme'
!
defaultUserShell
	^XDG config: 'omarchy/shell.toml'
!
isAvailable
	"Whether this is an Omarchy desktop."
	^File exists: self defaultDirectory, '/colors.toml'
!
install
	"Make the Omarchy theme current (where there is one) and keep it current with the desktop: every window redraws in it; answer the current theme."
	self isAvailable ifFalse: [^Theme current].
	(Theme current isKindOf: self) ifFalse: [Theme current: (self new setDirectory: self defaultDirectory userShell: self defaultUserShell)].
	Theme current publishPalette; applyFonts.
	self startWatching.
	World restyleAll.
	^Theme current
!
uninstall
	"Back to the Blue Book."
	self stopWatching.
	(Theme current isKindOf: self) ifFalse: [^self].
	#('JetBrainsMono-Regular' 'JetBrainsMono-Bold' 'JetBrainsMono-Italic') do: [:each | Font substituteFace: each with: nil].
	Theme current: Theme blueBook.
	Theme current publishPalette.
	World restyleAll
!
wanted
	"Whether this image should follow the desktop's theme: on an Omarchy desktop, with a display, not running tests, and not told otherwise (--theme blue-book)."
	| choice |
	choice := Smalltalk argumentAfter: '--theme'.
	choice = 'blue-book' ifTrue: [^false].
	(Smalltalk isHeadless or: [Smalltalk vm arguments includes: '--test']) ifTrue: [^false].
	^self isAvailable
! !

!OmarchyTheme class methodsFor: 'system startup'!
startUp: resuming
	"Every start: follow the Omarchy theme where it is wanted, else the Blue Book (an image saved on an Omarchy desktop and started elsewhere)."
	self wanted ifTrue: [self install] ifFalse: [self uninstall]
! !

!OmarchyTheme class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self
!
startWatching
	(Watcher notNil and: [Watcher isTerminated not]) ifTrue: [^self].
	Watcher := [[(Delay forSeconds: 1) wait. self checkForChanges] repeat] newProcess.
	Watcher priority: Processor userBackgroundPriority; name: 'Omarchy theme watcher'.
	Watcher resume
!
stopWatching
	Watcher isNil ifFalse: [Watcher terminate. Watcher := nil]
!
checkForChanges
	"The desktop's theme or font changed: read it again, every window redraws."
	| theme |
	theme := Theme current.
	((theme isKindOf: self) and: [theme isStale]) ifFalse: [^self].
	[theme refresh] on: Error do: [:e | e return: nil].
	World restyleAll
! !

!OmarchyTheme class methodsFor: 'fonts'!
fontconfigFace: aPattern fallback: aFaceName
	"The TrueTypeFont fontconfig picks for aPattern (fc-match), else the image's face aFaceName."
	| path |
	path := [(OSProcess outputOf: 'fc-match -f ''%{file}'' ', (OSProcess quote: aPattern)) trimBoth]
		on: Error do: [:e | e return: ''].
	((path endsWith: '.ttf') and: [File exists: path]) ifTrue: [
		^[Font faceFromFile: path] on: Error do: [:e | e return: (Font faceNamed: aFaceName)]].
	^Font faceNamed: aFaceName
!
tokenKeys
	"The shell's type-scale tokens and their [font] keys."
	^Dictionary new
		at: #caption put: 'caption';
		at: #bodySmall put: 'body-small';
		at: #body put: 'body';
		at: #subtitle put: 'subtitle';
		at: #title put: 'title';
		at: #heading put: 'heading';
		at: #display put: 'display';
		at: #displayLarge put: 'display-large';
		yourself
!
tokenFactors
	^Dictionary new
		at: #caption put: 0.833;
		at: #bodySmall put: 0.917;
		at: #body put: 1.0;
		at: #subtitle put: 1.083;
		at: #title put: 1.167;
		at: #heading put: 1.333;
		at: #display put: 2.0;
		at: #displayLarge put: 2.333;
		yourself
! !

!OmarchyTheme class methodsFor: 'colors'!
parseColor: aString
	"#RGB, #RRGGBB, #RRGGBBAA, rgb(RRGGBB) or rgba(RRGGBBAA) (Hyprland's) as a Color, else nil."
	| s hex value |
	aString isString ifFalse: [^nil].
	s := aString trimBoth asLowercase.
	hex := (s beginsWith: '#')
		ifTrue: [s allButFirst]
		ifFalse: [((s beginsWith: 'rgba(') or: [s beginsWith: 'rgb(']) & (s endsWith: ')')
			ifTrue: [(s copyAfter: $() allButLast]
			ifFalse: [^nil]].
	(hex allSatisfy: [:c | c isDigit or: ['abcdef' includes: c]]) ifFalse: [^nil].
	hex size = 3 ifTrue: [hex := hex inject: '' into: [:acc :c | acc, (String with: c with: c)]].
	value := Integer readFrom: hex asUppercase base: 16.
	hex size = 6 ifTrue: [^Color hex: value].
	hex size = 8 ifTrue: [^Color hex: (value bitShift: -8) alpha: (value bitAnd: 255) / 255.0].
	^nil
! !
