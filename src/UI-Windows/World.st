Object subclass: #World
	instanceVariableNames: 'displayWindow extent scale windows overlays activeWindow compositor dispatcher topBar toasts tooltip lock windowCounter closingWindows needsFrame remotePointer hidden imageName clipboardText running curtain closingFrontWindows resizingSince'
	classVariableNames: 'All Current HelpHandler UserInterruptHandler WorldMenuBuilder QuitHandler'
	package: 'UI-Windows'!

World comment: 'I am the desktop: the host window (a DisplayWindow), the halftone desk, the windows (z-order, front to back), the active window, the top bar, and the overlays (menus, toasts, the tooltip, the remote pointer). The Compositor (priority 70, vsync) draws me; the InputDispatcher (priority 60) routes input and moves and resizes windows. World current is the running one (an application''s other host windows are Worlds of their own: World all).

	World current windows            "front to back"
	World current openMenu: aMenu at: aPoint
	World current toast: ''Saved''
	World worldMenuBuilder: [:world :point | aMenu or nil]   "a click on the desk"
	World userInterruptHandler: [:window | ...]             "⌘."

My window list is replaced, never mutated (copy on write under lock), so the compositor reads it without locking.'!

!World methodsFor: 'initialization'!
setDisplayWindow: aDisplayWindow hidden: aBoolean
	displayWindow := aDisplayWindow.
	hidden := aBoolean.
	extent := aDisplayWindow extent.
	scale := aDisplayWindow scale.
	windows := #().
	overlays := #().
	closingWindows := #().
	toasts := #().
	lock := Semaphore forMutualExclusion.
	windowCounter := 0.
	needsFrame := true.
	running := false.
	topBar := TopBar world: self.
	remotePointer := RemotePointer new.
	imageName := self class imageName
! !

!World methodsFor: 'accessing'!
displayWindow
	^displayWindow
!
extent
	^extent
!
bounds
	^0 @ 0 extent: extent
!
desktopBounds
	"The desk below the top bar."
	^0 @ topBar height corner: extent
!
displayScale
	^scale
!
windows
	"My windows, front to back."
	^windows
!
overlays
	"Open menus and other overlays, bottom to top."
	^overlays
!
closingWindows
	^closingWindows
!
activeWindow
	^activeWindow
!
topBar
	^topBar
!
compositor
	^compositor
!
dispatcher
	^dispatcher
!
toasts
	^toasts
!
tooltip
	^tooltip
!
curtain
	"What covers the screen while the image comes and goes (a WorldCurtain), or nil."
	^curtain
!
remotePointer
	^remotePointer
!
imageName
	^imageName
!
isHidden
	^hidden
!
isRunning
	^running
!
windowNamed: aString
	"The window whose remoteName (w3) or title is aString, or nil."
	^windows detect: [:w | w remoteName = aString or: [w title = aString]] ifNone: [nil]
!
windowAt: aScreenPoint
	"The frontmost window whose frame (with its resize margin) contains aScreenPoint, or nil."
	^windows detect: [:w | w containsPoint: aScreenPoint] ifNone: [nil]
!
overlayAt: aScreenPoint
	overlays reverseDo: [:o | (o bounds containsPoint: aScreenPoint) ifTrue: [^o]].
	^nil
!
keyTarget
	"Who gets keys: the topmost overlay, else the active window."
	overlays isEmpty ifFalse: [^overlays last].
	^activeWindow
! !

!World methodsFor: 'kind'!
showsTopBar
	"Whether the top bar shows (an AppWorld has none)."
	^true
!
presentsContinuously
	"Whether the compositor presents on every tick, changed or not: on screen, so the top bar's frame times stay live and a frame is always in flight. An AppWorld presents only what changed."
	^hidden not
! !

!World methodsFor: 'windows'!
addWindow: aWindow
	lock critical: [
		windowCounter := windowCounter + 1.
		aWindow remoteName isNil ifTrue: [aWindow remoteName: 'w', windowCounter printString].
		windows := (Array with: aWindow), windows].
	aWindow layer opacity: 0; scale: 0.97; waitForContent.
	aWindow layer animate: #opacity from: 0 to: 1 duration: 140 easing: #easeOutCubic.
	aWindow layer animate: #scale from: 0.97 to: 1 duration: 140 easing: #easeOutCubic.
	self activate: aWindow.
	self changed.
	^aWindow
!
removeWindow: aWindow
	| next |
	closingFrontWindows isNil ifTrue: [closingFrontWindows := IdentityDictionary new].
	closingFrontWindows at: aWindow put: (windows copyFrom: 1 to: (windows indexOf: aWindow) - 1).
	lock critical: [
		windows := windows copyWithout: aWindow.
		closingWindows := closingWindows copyWith: aWindow].
	aWindow layer animate: #opacity to: 0 duration: self closeMilliseconds easing: #easeInCubic.
	(aWindow layer animate: #scale to: 0.97 duration: self closeMilliseconds easing: #easeInCubic)
		whenDone: [self dropClosing: aWindow].
	activeWindow == aWindow ifTrue: [
		activeWindow := nil.
		next := windows detect: [:w | w isCollapsed not] ifNone: [windows isEmpty ifTrue: [nil] ifFalse: [windows first]].
		next isNil ifFalse: [self activate: next]].
	self changed
!
closeMilliseconds
	"How long a closing window fades out (and shrinks a little)."
	^110
!
dropClosing: aWindow
	"Called by the compositor when the close animation ended."
	lock critical: [closingWindows := closingWindows copyWithout: aWindow].
	closingFrontWindows isNil ifFalse: [closingFrontWindows removeKey: aWindow ifAbsent: []].
	aWindow layer release.
	"An on-demand compositor must present the frame without the closed layer."
	self changed
!
raise: aWindow
	(windows notEmpty and: [windows first == aWindow]) ifTrue: [^self].
	(windows includes: aWindow) ifFalse: [^self].
	lock critical: [windows := (Array with: aWindow), (windows copyWithout: aWindow)].
	self changed
!
activate: aWindow
	"Raise aWindow and give it the focus (title stripes and shadow cross-fade)."
	| old |
	self raise: aWindow.
	old := activeWindow.
	old == aWindow ifTrue: [^self].
	activeWindow := aWindow.
	old isNil ifFalse: [
		self animateFocusOf: old to: 0.
		old isOpen ifTrue: [old invalidate]].
	aWindow isNil ifFalse: [
		self animateFocusOf: aWindow to: 1.
		aWindow invalidate].
	self changed
!
animateFocusOf: aWindow to: aNumber
	"Cross-fade the title stripes, tab and shadow (in the compositor)."
	aWindow layer run: (Animation from: aWindow focusAmount to: aNumber duration: 120 easing: #easeOutQuad
		do: [:v | aWindow focusAmount: v])
!
openWindow: aWindow
	^aWindow openIn: self
!
newWindow
	"A new Window for code above the window system (Desktop newWindow): one with a title bar, which I place."
	^Window new
!
worldForNewWindow: aWindow
	"The World aWindow opens in when opened (Window>>open): me."
	^self
!
nextWindowPosition: anExtent
	"A cascading position for a new window of anExtent."
	| n x y |
	n := windows size \\ 8.
	x := 120 + (n * 28).
	y := topBar height + 44 + (n * 26).
	x := (x min: extent x - anExtent x - 8) max: 8.
	y := (y min: extent y - anExtent y - 8) max: topBar height + 8.
	^x @ y
!
closeAllWindows
	windows do: [:w | w close].
	overlays do: [:o | o close]
!
windowsInPaintOrder
	| order |
	order := windows reversed asOrderedCollection.
	closingWindows do: [:w |
		w isOverlay ifFalse: [
			| front index |
			front := closingFrontWindows at: w ifAbsent: [#()].
			index := order findFirst: [:each | front includes: each].
			index = 0
				ifTrue: [order add: w]
				ifFalse: [order add: w beforeIndex: index]]].
	^order
! !

!World methodsFor: 'overlays'!
addOverlay: anOverlay
	lock critical: [overlays := overlays copyWith: anOverlay].
	anOverlay layer offset: 0 @ -4; opacity: 0; waitForContent.
	anOverlay layer animate: #opacity from: 0 to: 1 duration: 90 easing: #easeOutCubic.
	anOverlay layer animate: #offset from: 0 @ -4 to: 0 @ 0 duration: 90 easing: #easeOutCubic.
	self changed
!
removeOverlay: anOverlay
	lock critical: [
		overlays := overlays copyWithout: anOverlay.
		closingWindows := closingWindows copyWith: anOverlay].
	(anOverlay layer animate: #opacity to: 0 duration: 70 easing: #easeInQuad)
		whenDone: [self dropClosing: anOverlay].
	self changed
!
openMenu: aMenu at: aPoint
	"Host aMenu (a View, or a model answering asMenuView) in an OverlayWindow at aPoint (screen); answer the overlay."
	| view size origin overlay |
	view := aMenu isView ifTrue: [aMenu] ifFalse: [aMenu asMenuView].
	size := view preferredExtent.
	origin := ((aPoint x min: extent x - size x - 4) max: 4) @ ((aPoint y min: extent y - size y - 4) max: topBar height + 2).
	overlay := OverlayWindow new.
	overlay title: 'menu'; bounds: (origin extent: size); invoker: activeWindow.
	overlay content: view.
	^overlay openIn: self
!
closeMenu: aMenuViewOrOverlay
	| overlay |
	overlay := aMenuViewOrOverlay isWindow ifTrue: [aMenuViewOrOverlay] ifFalse: [aMenuViewOrOverlay window].
	overlay isNil ifFalse: [overlay close]
!
closeMenus
	overlays do: [:each | each close]
!
toast: aString
	^self toast: aString duration: 2200
!
toast: aString duration: milliseconds
	| toast |
	toast := WorldToast world: self text: aString duration: milliseconds.
	lock critical: [toasts := (toasts reject: [:t | t isDone]) copyWith: toast].
	self changed.
	^toast
!
dropToast: aToast
	lock critical: [toasts := toasts copyWithout: aToast]
!
showTooltip: aString at: aPoint
	tooltip := WorldTooltip world: self text: aString at: aPoint.
	self changed
!
hideTooltip
	tooltip isNil ifTrue: [^self].
	tooltip := nil.
	self changed
! !

!World methodsFor: 'desk'!
desktopClickedAt: aPoint button: anInteger
	"A click on the desk opens the World menu (from worldMenuBuilder). It belongs to no window: its actions run in a Process of their own, not in the active window's (which may be busy)."
	| menu |
	(HelpHandler notNil and: [topBar helpRect containsPoint: aPoint]) ifTrue: [^[HelpHandler cull: self] fork].
	aPoint y < topBar height ifTrue: [^self].
	WorldMenuBuilder isNil ifTrue: [^self toast: 'No World menu installed yet (World worldMenuBuilder:)'].
	menu := WorldMenuBuilder cull: self cull: aPoint.
	menu isNil ifFalse: [(self openMenu: menu at: aPoint) invoker: nil]
!
userInterrupt
	"⌘. : the user interrupt key, handled by the InputDispatcher even when every window is busy."
	| target |
	target := activeWindow.
	UserInterruptHandler isNil ifFalse: [^UserInterruptHandler cull: target cull: self].
	(target notNil and: [target process notNil and: [target process respondsTo: #interrupt]])
		ifTrue: [^target process interrupt].
	self toast: 'User interrupt (⌘.)'
!
quitRequested
	"The window manager closed my host window."
	^self quitProcess
!
processQuitRequested
	"The process was asked to quit. Let the fade finish even on a paused recording clock."
	Smalltalk vm workClockRunning: true.
	^self quitProcess
!
quitProcess
	QuitHandler isNil ifFalse: [^QuitHandler cull: self].
	Smalltalk quit: 0
! !

!World methodsFor: 'host window'!
hostResized: aPoint
	extent := aPoint.
	windows do: [:w |
		| b |
		b := w bounds.
		(b top > (extent y - 26) or: [b left > (extent x - 60)]) ifTrue: [
			w moveTo: ((b left min: extent x - 60) max: 60 - b width) @ ((b top min: extent y - 26) max: topBar height)]].
	self changed
!
awaitsResize
	"Whether the compositor should hold the frame: a window was resized and has not drawn its new size yet. At most 100 ms."
	| now |
	(windows allSatisfy: [:w | w layer contentList isNil or: [w layer contentList extent = w extent]])
		ifTrue: [resizingSince := nil. ^false].
	now := Time millisecondClockValue.
	resizingSince isNil ifTrue: [resizingSince := now].
	^now - resizingSince < 100
!
debugged: aProcess changed: aSymbol
	"DebugSession process listener: a debugger holds aProcess (#held) or let it go (#released). If it is my compositor's or input dispatcher's, a stand-in runs meanwhile (StandIn)."
	dispatcher isNil ifFalse: [dispatcher debugged: aProcess changed: aSymbol].
	compositor isNil ifFalse: [compositor debugged: aProcess changed: aSymbol]
!
restyle
	"Drawing code or the look changed (SystemChanges): every window and overlay draws its content and chrome anew."
	(windows, overlays) do: [:w | w restyle].
	topBar resetFonts.
	self changed
!
displayScaleChanged: aNumber
	(aNumber isNil or: [aNumber = scale]) ifTrue: [^self].
	scale := aNumber.
	Font deviceScale: aNumber.
	topBar resetFonts.
	windows do: [:w | w layer chromeKey: nil. w layer markNeedsRender. w invalidate].
	self changed
!
clipboard
	^[DisplayWindow clipboard] on: Error do: [:e | e return: clipboardText]
!
clipboard: aString
	clipboardText := aString.
	[DisplayWindow clipboard: aString] on: Error do: [:e | e return: nil]
!
clipboardData: mime
	"The clipboard's contents as mime type mime (a ByteArray), or nil."
	^[DisplayWindow clipboardData: mime] on: Error do: [:e | e return: nil]
!
textInputArea: aRectangle cursor: x
	"Where text is being typed (screen points; x: the caret within aRectangle), for the input method's candidates."
	displayWindow isNil ifFalse: [[displayWindow textInputArea: aRectangle cursor: x] on: Error do: [:e | e return: nil]]
!
cursor: aSymbol
	| name |
	name := #(#arrow #arrow #ibeam #ibeam #hand #hand #resizeEW #ew #resizeNS #ns #resizeNWSE #nwse #resizeNESW #nesw #move #move #crosshair #crosshair #wait #wait #notAllowed #notAllowed).
	1 to: name size by: 2 do: [:i | (name at: i) == aSymbol ifTrue: [^DisplayWindow cursor: (name at: i + 1)]].
	^DisplayWindow cursor: #arrow
! !

!World methodsFor: 'drawing'!
drawDeskOn: aCanvas
	"The desk behind the windows, drawn by the compositor every frame: the Blue Book halftone, one dot in every 2×2-point cell (Color desk and deskDots: white and black, or the theme's)."
	aCanvas fillRect: self bounds color: Color desk.
	aCanvas pattern: #halftone in: self bounds color: Color deskDots
! !

!World methodsFor: 'frames'!
changed
	"Something visible changed: the compositor presents a new frame."
	needsFrame := true.
	compositor isNil ifFalse: [compositor wake]
!
consumeNeedsFrame
	| n |
	n := needsFrame.
	needsFrame := false.
	^n
!
needsFrame
	^needsFrame
! !

!World methodsFor: 'starting and stopping'!
start
	"Start the compositor and the input dispatcher."
	running ifTrue: [^self].
	running := true.
	All := (All ifNil: [#()]) copyWith: self.
	compositor := Compositor world: self.
	dispatcher := InputDispatcher world: self.
	compositor start.
	dispatcher start
!
stop
	"Close all windows, stop my processes and close the host window."
	running ifFalse: [^self].
	(windows, overlays) do: [:w | [w close] on: Error do: [:e | e return: nil]].
	dispatcher isNil ifFalse: [dispatcher stop].
	compositor isNil ifFalse: [compositor stop].
	running := false.
	All := (All ifNil: [#()]) copyWithout: self.
	(windows, overlays, closingWindows) do: [:w | w layer release].
	windows := #().
	overlays := #().
	closingWindows := #().
	[displayWindow close] on: Error do: [:e | e return: nil].
	Current == self ifTrue: [Current := nil]
!
abandon
	"After an image restart: my processes and handles are gone; forget them without touching the GPU."
	(windows, overlays) do: [:w | w process isNil ifFalse: [w process terminate]].
	dispatcher isNil ifFalse: [dispatcher abandon].
	compositor isNil ifFalse: [compositor abandon].
	running := false.
	All := (All ifNil: [#()]) copyWithout: self.
	Current == self ifTrue: [Current := nil]
!
resumeHidden: aBoolean
	"After an image restart from a snapshot taken while I ran: my host window, GPU objects, compositor and input dispatcher died with the old VM; my windows and their Processes did not. Re-open the host window (same size; hidden if aBoolean), start a new compositor and input dispatcher, and composite every window again. Animations and toasts ran on the old clock: animations jump to their end, toasts go."
	dispatcher isNil ifFalse: [dispatcher abandon].
	compositor isNil ifFalse: [compositor abandon].
	running := false.
	All := (All ifNil: [#()]) copyWithout: self.
	hidden := aBoolean.
	imageName := self class imageName.
	displayWindow hidden: aBoolean.
	toasts := #().
	tooltip := nil.
	closingWindows := #().
	(windows, overlays) do: [:w | w resumed].
	extent = displayWindow extent ifFalse: [self hostResized: displayWindow extent].
	self displayScaleChanged: displayWindow scale.
	aBoolean ifFalse: [self showRestartSplash].
	self start.
	self changed
!
showRestartSplash
	"Cover the screen with the restart splash until every window is composited again."
	curtain := WorldCurtain starting: self.
	self changed
!
leave
	"Before the VM goes away (a quit, the exec of a rebuilt VM): the screen fades to black; answer once it was shown. Not when nobody can see it (hidden and not recorded)."
	(running not or: [compositor isNil or: [hidden and: [compositor recorder isNil]]]) ifTrue: [^self].
	curtain := WorldCurtain leaving: self.
	self changed.
	Processor activeProcess == compositor process ifTrue: [^self].
	[curtain isBlack or: [curtain elapsed > (WorldCurtain fadeMilliseconds + 1000)]] whileFalse: [(Delay forMilliseconds: 10) wait].
	self waitForFrames: 2
!
stay
	"The VM did not go away after all: show me again."
	(curtain notNil and: [curtain isLeaving]) ifTrue: [curtain := nil].
	self changed
!
stepCurtain
	"Called by the compositor every frame: answer whether a curtain still needs frames."
	(curtain notNil and: [curtain isDone]) ifTrue: [
		curtain := nil.
		self changed].
	^curtain notNil
! !

!World methodsFor: 'waiting'!
isSettled
	"No input pending, no window handling or queueing events, nothing left to present, no layer animation running. Windows animating every frame (requestAnimationFrames: with a block) never settle; they are ignored."
	| all steady |
	curtain isNil ifFalse: [^false].
	dispatcher isNil ifFalse: [dispatcher isIdle ifFalse: [^false]].
	closingWindows isEmpty ifFalse: [^false].
	all := windows, overlays.
	steady := all reject: [:w | w isAnimatingForever].
	(steady anySatisfy: [:w | w hasPendingWork]) ifTrue: [^false].
	(steady anySatisfy: [:w | w layer isAnimating or: [w layer needsRender]]) ifTrue: [^false].
	steady size = all size ifFalse: [^true].
	needsFrame ifTrue: [^false].
	compositor isNil ifTrue: [^true].
	"Hidden (tests): also wait for the frames' GPU times. On screen the compositor presents continuously, so there is always a frame in flight."
	^compositor isPresenting not and: [hidden not or: [compositor gpuTimer isNil or: [compositor gpuTimer isIdle]]]
!
waitUntilSettled: milliseconds
	"Answer whether I settled (twice in a row, 10 ms apart) within milliseconds."
	| start streak |
	start := Time millisecondClockValue.
	streak := 0.
	[streak >= 2] whileFalse: [
		Time millisecondClockValue - start > milliseconds ifTrue: [^false].
		(Delay forMilliseconds: 10) wait.
		self isSettled ifTrue: [streak := streak + 1] ifFalse: [streak := 0]].
	^true
!
waitForFrames: n
	"Wait until n more frames were presented (at most 2 s)."
	| target start |
	compositor isNil ifTrue: [^self].
	target := compositor frameCount + n.
	start := Time millisecondClockValue.
	[compositor frameCount < target and: [Time millisecondClockValue - start < 2000]] whileTrue: [
		self changed.
		(Delay forMilliseconds: 5) wait]
! !

!World methodsFor: 'remote control'!
remoteRole
	^#screen
!
remoteLabel
	^extent x rounded printString, 'x', extent y rounded printString
!
remoteState
	| s |
	s := OrderedCollection new.
	s add: 'theme=blue-book'.
	activeWindow isNil ifFalse: [s add: 'focus=@', activeWindow remoteName].
	s add: 'processes=', topBar processCount printString.
	s add: 'busy=', (windows count: [:w | w isBusy]) printString.
	^s asArray
!
remoteChildren
	^(Array with: topBar), (overlays reverse), windows, (toasts reject: [:t | t isDone])
! !

!World methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a World('; print: extent; nextPutAll: ', '; print: windows size; nextPutAll: ' windows)'
! !

!World class methodsFor: 'accessing'!
current
	^Current
!
all
	"The running Worlds: the current one and an application's other host windows."
	^All ifNil: [#()]
!
allDo: aBlock
	self all do: aBlock
!
restyleAll
	"Drawing code or the look changed: every running World draws anew."
	self allDo: [:world | world restyle]
!
systemAppearance
	"#dark or #light, as the host system shows its windows (macOS); nil where it does not tell."
	^DisplayWindow systemAppearance
!
current: aWorld
	Current := aWorld
!
worldMenuBuilder
	^WorldMenuBuilder
!
worldMenuBuilder: aBlock
	"[:world :point | a menu (View or model answering asMenuView) or nil], for clicks on the desk."
	WorldMenuBuilder := aBlock
!
helpHandler: aBlockOrNil
	"[:world | ...] for the top bar's ? button (nil: no ? button)."
	HelpHandler := aBlockOrNil
!
helpHandler
	^HelpHandler
!
userInterruptHandler
	^UserInterruptHandler
!
userInterruptHandler: aBlock
	"[:activeWindow :world | ...] for ⌘. (default: interrupt the active window's Process)."
	UserInterruptHandler := aBlock
!
quitHandler: aBlock
	"[:world | ...] when the host window is closed (default: Smalltalk quit: 0)."
	QuitHandler := aBlock
!
imageName
	| path |
	path := Smalltalk vm imagePath ifNil: ['samaltak.image'].
	^path copyAfterLast: $/
! !

!World class methodsFor: 'instance creation'!
openExtent: aPoint hidden: aBoolean
	"Open a host window of aPoint points, start a World on it and make it current."
	| display world |
	display := DisplayWindow width: aPoint x height: aPoint y title: 'Samaltak' hidden: aBoolean.
	Font deviceScale = display scale ifFalse: [Font deviceScale: display scale].
	world := self new setDisplayWindow: display hidden: aBoolean.
	Current := world.
	world start.
	^world
!
openHidden: aPoint
	^self openExtent: aPoint hidden: true
! !

!World methodsFor: 'screenshots'!
screenshot
	"Capture the last submitted desktop frame in physical pixels."
	displayWindow isNil ifTrue: [self error: 'No display window'].
	^displayWindow surface readback
!
screenshot: aRectangle
	"Capture a desktop region in logical coordinates, clipped to the display."
	^self screenshot croppedTo: (aRectangle scaleBy: self displayScale)
! !
