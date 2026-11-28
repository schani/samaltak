World subclass: #AppWorld
	instanceVariableNames: 'deskColor idleWatcher releasedAtFrame isMain resizedBlock'
	classVariableNames: ''
	package: 'UI-Windows'!

AppWorld comment: 'I am the World of an application that runs as a window of the host''s window manager (Hyprland on Linux, the Dock on macOS) instead of on the Samaltak desktop. My host window shows one AppWindow, chromeless and filling me, and its overlays (menus, tooltips, toasts); there is no desk and no top bar. The window manager places, decorates and closes the host window: closing it, or my last window, quits. My Compositor presents only frames in which something changed, so an idle application costs no CPU.

	| world |
	world := AppWorld openExtent: 480 @ 200 title: ''Weather''.
	(AppWindow new title: ''Weather''; content: aView) openIn: world

When no frame was presented for idleSeconds (2), I give back to the system the memory the burst before held: eden''s pages, the machine code and the JIT''s scratch areas (VirtualMachine>>releaseMemory), once per burst; an application that wakes up every quarter of an hour to redraw holds only what it keeps.

The host window has a fixed size (the content''s), so a tiling window manager such as Hyprland floats it. On Linux the Wayland app_id comes from SDL_APP_ID (bin/samaltak sets it).

An application may open more host windows (the Agent on it, AgentWindow): each is an AppWorld of its own, not the main one (isMain), and closing it closes only it; it may be resizable, and then the window manager tiles it.

	AppWorld openExtent: 720 @ 640 title: ''Agent — Weather'' hidden: false main: false resizable: true

A desktop host window (desktop: true) sits on the desktop instead: above the wallpaper, below every window, without decorations or the keyboard focus (on Wayland a layer surface; where the system has no such thing, an ordinary window). Its application places it (moveTo:, from the top left of the area the bar leaves free), learns its new size (whenResized:), raises it above the other desktop windows (raise) and fades it (opacity:); OmarchyDesk lays out and drags the desktop cards so. Pointer events know where on the screen they happened while the host window moves under the pointer (PointerEvent>>screenPosition).

	AppWorld openExtent: 490 @ 200 title: ''Weather'' hidden: false main: false resizable: false desktop: true'!

!AppWorld methodsFor: 'kind'!
showsTopBar
	^false
!
presentsContinuously
	^false
! !

!AppWorld methodsFor: 'accessing'!
isMain
	"Whether I am the application's main host window: closing me ends it."
	^isMain ~~ false
!
isMain: aBoolean
	isMain := aBoolean
!
deskColor
	"What shows where no window is (before the first frame, or while my window redraws after a resize)."
	^deskColor ifNil: [Color paper]
!
deskColor: aColor
	deskColor := aColor.
	displayWindow background: aColor.
	self changed
! !

!AppWorld methodsFor: 'windows'!
addWindow: aWindow
	"No opening animation: my window fills me from its first frame."
	lock critical: [
		windowCounter := windowCounter + 1.
		aWindow remoteName isNil ifTrue: [aWindow remoteName: 'w', windowCounter printString].
		windows := (Array with: aWindow), windows].
	aWindow bounds: self bounds.
	aWindow layer waitForContent.
	self activate: aWindow.
	self changed.
	^aWindow
!
removeWindow: aWindow
	"The application ends with its last window: on screen it quits, hidden (tests) I stop. Another host window of the application (not isMain) just closes."
	super removeWindow: aWindow.
	windows isEmpty ifTrue: [
		[(hidden or: [self isMain not]) ifTrue: [self stop] ifFalse: [self quitRequested]] forkAt: Processor userBackgroundPriority]
!
closeMilliseconds
	"No fade: the window manager animates my host window away (or not), as for any other application."
	^0
!
quitRequested
	"The window manager closed my host window: the application quits, unless I am one of its other host windows."
	self isMain ifTrue: [^self quitProcess].
	[self stop] forkAt: Processor userBackgroundPriority
!
nextWindowPosition: anExtent
	^0 @ 0
!
newWindow
	"A window the host's window manager decorates: no title bar of mine."
	^AppWindow new
!
worldForNewWindow: aWindow
	"Mine shows one window: another (a tool the application opens: an Inspector, a Browser, the Agent) gets a host window of its own, of its size, resizable, closing only it."
	| extent world |
	windows isEmpty ifTrue: [^self].
	extent := (aWindow bounds isNil or: [aWindow bounds extent x < 100 or: [aWindow bounds extent y < 60]])
		ifTrue: [600 @ 400]
		ifFalse: [aWindow bounds extent].
	world := AppWorld openExtent: extent title: (aWindow title ifNil: ['Samaltak']) hidden: hidden main: false resizable: true.
	world deskColor: self deskColor.
	^world
! !

!AppWorld methodsFor: 'desk'!
desktopClickedAt: aPoint button: anInteger
	"There is no desk to click: no World menu."
! !

!AppWorld methodsFor: 'host window'!
leave
	"Before a quit: no fade to black; the window manager takes my host window away as it does any other application's."
!
raise
	"Bring my host window to the front, with the focus (as far as the window manager lets an application); a desktop one above the other desktop windows. Not when hidden."
	hidden ifFalse: [displayWindow hostWindow show]
!
moveTo: aPoint
	"Move my host window to aPoint points: a desktop one from the top left of the area the bar leaves free, another on the screen (if the window manager lets it). Answer whether the host did."
	^displayWindow hostWindow moveTo: aPoint
!
whenResized: aBlock
	"Run aBlock (with me) when the host reported a new size for my host window."
	resizedBlock := aBlock
!
opacity: aNumber
	"Show my host window at aNumber (0 to 1) opacity, where the system can (a desktop one on Wayland: the compositor's alpha modifier). Answer whether it did."
	^displayWindow hostWindow opacity: aNumber
!
cornerRadius
	"The radius (points) the system rounds my host window's corners with (a desktop one on macOS); 0 if square."
	^displayWindow hostWindow cornerRadius
!
minimumExtent: aPoint
	"Keep my host window at least aPoint points, also when the user resizes it."
	displayWindow minimumExtent: aPoint
!
resizeTo: aPoint
	"Ask the host window to become aPoint points (it stays fixed-size); my window follows when the host reports the new size. Answer whether the host took it."
	^displayWindow extent: aPoint
!
hostResized: aPoint
	extent := aPoint.
	windows do: [:w | w bounds: self bounds].
	self changed.
	resizedBlock isNil ifFalse: [resizedBlock cull: self]
! !

!AppWorld methodsFor: 'starting and stopping'!
start
	super start.
	(idleWatcher notNil and: [idleWatcher isTerminated not]) ifTrue: [^self].
	idleWatcher := [self watchIdle] newProcess.
	idleWatcher priority: Processor userBackgroundPriority; name: 'idle memory release'.
	idleWatcher resume
!
stop
	idleWatcher isNil ifFalse: [idleWatcher terminate. idleWatcher := nil].
	super stop
! !

!AppWorld methodsFor: 'idle'!
idleSeconds
	"How long no frame was presented before I give memory back."
	^2
!
watchIdle
	"Once a second: if no frame was presented for idleSeconds since the last release, release memory (VirtualMachine>>releaseMemory)."
	| frames since |
	frames := -1.
	since := Time millisecondClockValue.
	[running] whileTrue: [
		(Delay forSeconds: 1) wait.
		compositor isNil ifFalse: [
			compositor frameCount = frames
				ifTrue: [
					(releasedAtFrame ~= frames and: [Time millisecondClockValue - since >= (self idleSeconds * 1000)]) ifTrue: [
						releasedAtFrame := frames.
						Smalltalk vm releaseMemory]]
				ifFalse: [
					frames := compositor frameCount.
					since := Time millisecondClockValue]]]
!
releasedAtFrame
	"The frame count at my last release of memory (nil before the first)."
	^releasedAtFrame
! !

!AppWorld methodsFor: 'drawing'!
drawDeskOn: aCanvas
	aCanvas fillRect: self bounds color: self deskColor
! !

!AppWorld methodsFor: 'remote control'!
remoteRole
	^#app
! !

!AppWorld class methodsFor: 'desktop windows'!
desktopWindowExtent: aPoint title: aString
	"A bare desktop host window (flag 8: above the wallpaper, below every window) of aPoint points, opened after the others, so above them; a DisplayWindow for code above UI-Windows, which does not name it (show:clear:, hostWindow moveTo:, hostWindow opacity:, close)."
	^DisplayWindow width: aPoint x ceiling height: aPoint y ceiling title: aString flags: 8
!
desktopArea
	"The part of the primary display that docked bars (the menu bar, the Dock) leave free, a Rectangle in points from the top left of the screen; nil where the host cannot tell."
	^DisplayWindow desktopArea
! !

!AppWorld class methodsFor: 'instance creation'!
openExtent: aPoint title: aString
	^self openExtent: aPoint title: aString hidden: false
!
openExtent: aPoint title: aString hidden: aBoolean
	"Open the application's host window of aPoint points (fixed) with the title aString, start an AppWorld on it and make it current."
	^self openExtent: aPoint title: aString hidden: aBoolean main: true resizable: false
!
openExtent: aPoint title: aString hidden: aBoolean main: mainBoolean resizable: resizableBoolean
	^self openExtent: aPoint title: aString hidden: aBoolean main: mainBoolean resizable: resizableBoolean desktop: false
!
openExtent: aPoint title: aString hidden: aBoolean main: mainBoolean resizable: resizableBoolean desktop: desktopBoolean
	"Open a host window of aPoint points with the title aString (on the desktop, below the windows, if desktopBoolean) and start an AppWorld on it; the main one becomes current, another one only when none is."
	| display world |
	display := DisplayWindow width: aPoint x ceiling height: aPoint y ceiling title: aString
		flags: ((4 bitOr: (aBoolean ifTrue: [1] ifFalse: [0])) bitOr: ((resizableBoolean ifTrue: [2] ifFalse: [0]) bitOr: (desktopBoolean ifTrue: [8] ifFalse: [0]))).
	Font deviceScale = display scale ifFalse: [Font deviceScale: display scale].
	world := self new setDisplayWindow: display hidden: aBoolean.
	world isMain: mainBoolean.
	(mainBoolean or: [Current isNil]) ifTrue: [Current := world].
	world start.
	^world
! !
