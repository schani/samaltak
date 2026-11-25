VMPlatformModule subclass: #PlatformWindows
	instanceVariableNames: 'table videoOk cursors'
	classVariableNames: 'CURSOR_KINDS K_WINDOW'
	package: 'VM-Platform'!

PlatformWindows comment: 'SDL3 windows (handles of kind K_WINDOW, i = the SDL window id), the cursor, the clipboard.'!

!PlatformWindows class methodsFor: 'declaring'!
declarations
	^#((table 'pf_table[1]') (videoOk bool) (cursors 'SDL_Cursor *[CURSOR_KINDS]'))
!
initialize
	K_WINDOW := 1.
	CURSOR_KINDS := 11
! !

!PlatformWindows methodsFor: 'video'!
videoInit
	<export>
	videoOk ifTrue: [^true].
	sdl setHint: sdl SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE value: '0'.
	sdl setHint: sdl SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH value: '1'.
	"macOS goes on scrolling after the fingers leave the trackpad"
	sdl setHint: sdl SDL_HINT_MAC_SCROLL_MOMENTUM value: '1'.
	"The image draws the input method's composition (PF_EV_TEXT_EDITING)."
	sdl setHint: sdl SDL_HINT_IME_IMPLEMENTED_UI value: 'composition'.
	(sdl init: sdl SDL_INIT_VIDEO) ifFalse: [
		common setError: 'SDL_Init: %s' with: sdl getError.
		^false].
	videoOk := true.
	sdlPlatform catchQuitSignals.
	events updatePollInterval.
	^true
!
videoInited
	<export>
	^videoOk
! !

!PlatformWindows methodsFor: 'windows'!
sdlWindow: win
	"The SDL_Window of a window handle; NULL (and the error set) if it is none."
	<returns: 'SDL_Window *'>
	<export>
	| o |
	o := common table: table at: win kind: K_WINDOW.
	o isNull ifTrue: [
		common setError: 'bad window handle %d' with: win.
		^self null].
	^o ptr
!
open: w height: h title: title flags: flags
	<export>
	<var: #f type: 'SDL_WindowFlags'>
	| f sw handle |
	self videoInit ifFalse: [^0].
	f := 0.
	(flags bitAnd: PF_WIN_HIDDEN) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_HIDDEN].
	(flags bitAnd: PF_WIN_RESIZABLE) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_RESIZABLE].
	(flags bitAnd: PF_WIN_HIGH_DENSITY) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_HIGH_PIXEL_DENSITY].
	(flags bitAnd: PF_WIN_TRANSPARENT) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_TRANSPARENT].
	"A desktop window, unless hidden (offscreen) or the system has none: then an ordinary one."
	sw := ((flags bitAnd: PF_WIN_DESKTOP) ~= 0 and: [(flags bitAnd: PF_WIN_HIDDEN) = 0])
		ifTrue: [host openDesktopWindow: (title notNull ifTrue: [title] ifFalse: ['']) width: w height: h flags: f]
		ifFalse: [self null].
	sw isNull ifTrue: [sw := sdl createWindow: (title notNull ifTrue: [title] ifFalse: ['']) width: w height: h flags: f].
	sw isNull ifTrue: [
		common setError: 'SDL_CreateWindow: %s' with: sdl getError.
		^0].
	sdl startTextInput: sw.
	handle := common table: table add: K_WINDOW pointer: sw.
	(table v + handle) i: (sdl getWindowID: sw).
	^handle
!
close: win
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	gpu windowClosing: win.
	sdl stopTextInput: sw.
	host closingDesktopWindow: sw.
	sdl destroyWindow: sw.
	common table: table remove: win.
	^true
!
fromSDLId: id
	"The handle of the window with SDL window id, 0 if none."
	<export>
	1 to: table n - 1 do: [:h | ((table v + h) kind = K_WINDOW and: [(table v + h) i = id]) ifTrue: [^h]].
	^0
!
size: win width: w height: h
	"In points."
	<export>
	| sw |
	sw := self sdlWindow: win.
	^sw notNull and: [sdl getWindowSize: sw width: w height: h]
!
pixelSize: win width: w height: h
	<export>
	| sw |
	sw := self sdlWindow: win.
	^sw notNull and: [sdl getWindowSizeInPixels: sw width: w height: h]
!
displayScale: win
	"< 0 on error."
	<export>
	| sw s |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^-1.0].
	s := sdl getWindowDisplayScale: sw.
	^s > 0.0 ifTrue: [s] ifFalse: [1.0]
!
refreshRate: win
	"Hz, 0 if unknown, < 0 on error."
	<export>
	| sw m |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^-1.0].
	m := sdl getCurrentDisplayMode: (sdl getDisplayForWindow: sw).
	^m notNull ifTrue: [m refresh_rate] ifFalse: [0.0]
!
setTitle: win title: title
	<export>
	| sw |
	sw := self sdlWindow: win.
	^sw notNull and: [sdl setWindowTitle: sw title: title]
!
setBackground: win rgb: rgb
	"What the window shows where no frame is drawn (rgb 16rRRGGBB): while it is resized, where the system shows its new size and its new frame at different moments."
	<export>
	<var: #rgb type: 'uint32_t'>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	^host setWindowBackground: sw rgb: rgb
!
setMinimumSize: win width: w height: h
	"The window's content is never smaller than w × h points: the system's and the user's resizing keep it."
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	^sdl setWindowMinimumSize: sw w: w h: h
!
presenting: win width: w height: h
	"The image is about to present a frame of w × h points (before acquiring its drawable). Where the host sizes a window by its frames (macOS, while it is resized by its edges), the window takes that size now."
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	host presenting: sw width: w height: h.
	^true
!
setSize: win width: w height: h
	"Resize to w × h points; a window that is not resizable keeps the new size fixed."
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	(host resizeDesktopWindow: sw width: w height: h) ifTrue: [^true].
	^sdl setWindowSize: sw w: w h: h
!
setPosition: win x: x y: y
	"Move to x @ y points: a desktop window from the top left of the area the bar leaves free, another from the screen's (where the window manager lets an application place its windows). A PF_EV_WINDOW_MOVED event follows: for a desktop window once the system applied the move (between the pointer events relative to the old place and those relative to the new one), for another one at once."
	<export>
	| sw ev |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	(host moveDesktopWindow: sw x: x y: y) ifTrue: [^true].
	(sdl setWindowPosition: sw x: x y: y) ifFalse: [^false].
	ev := self local: 'pf_event'.
	ev type: PF_EV_WINDOW_MOVED.
	ev timeMs: common nowMs.
	ev x: x asFloat.
	ev y: y asFloat.
	ev window: win.
	events push: ev.
	^true
!
fillSurface: win x: x y: y width: w height: h rgba: rgba
	"Fill a rectangle of the window's own pixels (SDL_GetWindowSurface: a window drawn without the GPU; x, y, w, h in pixels) with rgba (16rRRGGBBAA, premultiplied by AA), shown by presentSurface:."
	<export>
	<var: #rgba type: 'uint32_t'>
	| sw surface r |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	surface := sdl getWindowSurface: sw.
	surface isNull ifTrue: [^false].
	r := self local: 'SDL_Rect'.
	r x: x.
	r y: y.
	r w: w.
	r h: h.
	^sdl fillSurfaceRect: surface rect: r color: (sdl mapSurfaceRGBA: surface
		r: ((rgba >> 24) bitAnd: 255) asUInt8 g: ((rgba >> 16) bitAnd: 255) asUInt8 b: ((rgba >> 8) bitAnd: 255) asUInt8 a: (rgba bitAnd: 255) asUInt8)
!
clearSurface: win
	"Make the window's own pixels transparent black."
	<export>
	| sw surface |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	surface := sdl getWindowSurface: sw.
	surface isNull ifTrue: [^false].
	^sdl fillSurfaceRect: surface rect: self null color: (sdl mapSurfaceRGBA: surface r: 0 g: 0 b: 0 a: 0)
!
presentSurface: win
	"Show the window's own pixels."
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	^sdl updateWindowSurface: sw
!
systemTheme
	"The appearance the system shows: 1 light, 2 dark, 0 if it does not tell."
	<export>
	<returns: 'int'>
	self videoInit ifFalse: [^0].
	^sdl getSystemTheme
!
cornerRadius: win
	"The radius (points) the system rounds the window's corners with; 0 if square."
	<export>
	<returns: 'int'>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^0].
	^host desktopWindowCornerRadius: sw
!
desktopAreaX: x y: y width: w height: h
	"The area of the primary display that docked bars (the menu bar, the Dock) leave free, in points from the top left of the screen."
	<export>
	<var: #x type: 'int *'>
	<var: #y type: 'int *'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	| r |
	self videoInit ifFalse: [^false].
	r := self local: 'SDL_Rect'.
	(sdl getDisplayUsableBounds: sdl getPrimaryDisplay rect: r) ifFalse: [
		common setError: 'SDL_GetDisplayUsableBounds: %s' with: sdl getError.
		^false].
	x value: r x.
	y value: r y.
	w value: r w.
	h value: r h.
	^true
!
setIcon: win pixels: pixels width: w height: h
	"The window's icon (the Dock's on macOS, the window manager's elsewhere): w × h pixels, 4 bytes each (red, green, blue, alpha; not premultiplied), rows top to bottom."
	<export>
	<var: #pixels type: 'const uint8_t *'>
	| sw surface ok |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	"SDL only reads the pixels: it copies them into the icon"
	surface := sdl createSurfaceFrom: w height: h format: sdl SDL_PIXELFORMAT_RGBA32 pixels: (self cCoerce: pixels to: 'void *') pitch: w * 4.
	surface isNull ifTrue: [^false].
	ok := sdl setWindowIcon: sw icon: surface.
	sdl destroySurface: surface.
	^ok
!
setOpacity: win permille: permille
	"Show the window at permille / 1000 opacity (where the system can)."
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	(host setDesktopWindowOpacity: sw permille: permille) ifTrue: [^true].
	^sdl setWindowOpacity: sw opacity: ((permille max: 0) min: 1000) asFloat / 1000.0
!
setTextInputArea: win x: x y: y width: w height: h cursor: cursor
	"Where the text being typed is (points): the input method puts its candidates next to it."
	<export>
	| sw r |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	r := self local: 'SDL_Rect'.
	r x: x.
	r y: y.
	r w: w.
	r h: h.
	^sdl setTextInputArea: sw rect: r cursor: cursor
!
show: win visible: show
	"Showing also raises the window and asks for the focus (the window manager may only mark it urgent)."
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	show ifFalse: [^sdl hideWindow: sw].
	"a desktop window is only raised above the other desktop windows"
	(host raiseDesktopWindow: sw) ifTrue: [^true].
	(sdl showWindow: sw) ifFalse: [^false].
	sdl raiseWindow: sw.
	^true
!
isHidden: win
	"Hidden or minimized (or no window)."
	<export>
	| sw |
	sw := self sdlWindow: win.
	^sw isNull or: [((sdl getWindowFlags: sw) bitAnd: (sdl SDL_WINDOW_HIDDEN bitOr: sdl SDL_WINDOW_MINIMIZED)) ~= 0]
!
shutdown
	<export>
	1 to: table n - 1 do: [:h | (table v + h) kind = K_WINDOW ifTrue: [self close: h]].
	0 to: CURSOR_KINDS - 1 do: [:i |
		(cursors at: i) notNull ifTrue: [
			sdl destroyCursor: (cursors at: i).
			cursors at: i put: self null]]
!
handleCount
	<export>
	^common table: table count: -1
! !

!PlatformWindows methodsFor: 'cursor and clipboard'!
systemCursor: kind
	^kind caseOf: {
		[0] -> [sdl SDL_SYSTEM_CURSOR_DEFAULT].
		[1] -> [sdl SDL_SYSTEM_CURSOR_TEXT].
		[2] -> [sdl SDL_SYSTEM_CURSOR_POINTER].
		[3] -> [sdl SDL_SYSTEM_CURSOR_EW_RESIZE].
		[4] -> [sdl SDL_SYSTEM_CURSOR_NS_RESIZE].
		[5] -> [sdl SDL_SYSTEM_CURSOR_NWSE_RESIZE].
		[6] -> [sdl SDL_SYSTEM_CURSOR_NESW_RESIZE].
		[7] -> [sdl SDL_SYSTEM_CURSOR_MOVE].
		[8] -> [sdl SDL_SYSTEM_CURSOR_WAIT].
		[9] -> [sdl SDL_SYSTEM_CURSOR_CROSSHAIR]} otherwise: [sdl SDL_SYSTEM_CURSOR_NOT_ALLOWED]
!
setCursor: kind
	"0 arrow, 1 ibeam, 2 hand, 3 resize-ew, 4 resize-ns, 5 resize-nwse, 6 resize-nesw, 7 move, 8 wait, 9 crosshair, 10 not-allowed"
	<export>
	(kind < 0 or: [kind >= CURSOR_KINDS]) ifTrue: [
		common setError: 'bad cursor %d' with: kind.
		^false].
	self videoInit ifFalse: [^false].
	(cursors at: kind) isNull ifTrue: [cursors at: kind put: (sdl createSystemCursor: (self systemCursor: kind))].
	(cursors at: kind) isNull ifTrue: [
		common setError: 'SDL_CreateSystemCursor: %s' with: sdl getError.
		^false].
	^sdl setCursor: (cursors at: kind)
!
clipboardGet
	"malloc'd."
	<export>
	| s r |
	self videoInit ifFalse: [^self null].
	s := sdl getClipboardText.
	r := libc strdup: (s notNull ifTrue: [s] ifFalse: ['']).
	sdl free: s.
	r isNull ifTrue: [common setError: 'out of memory'].
	^r
!
clipboardSet: s
	<export>
	self videoInit ifFalse: [^false].
	(sdl setClipboardText: s) ifFalse: [
		common setError: 'SDL_SetClipboardText: %s' with: sdl getError.
		^false].
	^true
! !

!PlatformWindows methodsFor: 'clipboard'!
clipboardData: mime size: size
	"SDL-owned result; the caller frees it with SDL_free."
	<export>
	self videoInit ifFalse: [^self null].
	^sdl getClipboardData: mime size: size
!
freeClipboardData: data
	<export>
	sdl free: data
! !
