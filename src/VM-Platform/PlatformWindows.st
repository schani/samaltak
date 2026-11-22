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
	"The image draws the input method's composition (PF_EV_TEXT_EDITING)."
	sdl setHint: sdl SDL_HINT_IME_IMPLEMENTED_UI value: 'composition'.
	(c4 platformSDL ifTrue: [sdl initSoftwareVideo] ifFalse: [sdl init: sdl SDL_INIT_VIDEO]) ifFalse: [
		common setError: 'SDL_Init: %s' with: sdl getError.
		^false].
	videoOk := true.
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
	(c4 platformSDL and: [table n > 4096 or: [self handleCount >= 32]]) ifTrue: [
		common setError: 'C4 SDL window handle limit'.
		^0].
	self videoInit ifFalse: [^0].
	f := 0.
	(flags bitAnd: PF_WIN_HIDDEN) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_HIDDEN].
	(flags bitAnd: PF_WIN_RESIZABLE) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_RESIZABLE].
	(flags bitAnd: PF_WIN_HIGH_DENSITY) ~= 0 ifTrue: [f := f bitOr: sdl SDL_WINDOW_HIGH_PIXEL_DENSITY].
	sw := sdl createWindow: (title notNull ifTrue: [title] ifFalse: ['']) width: w height: h flags: f.
	sw isNull ifTrue: [
		common setError: 'SDL_CreateWindow: %s' with: sdl getError.
		^0].
	handle := common table: table add: K_WINDOW pointer: sw.
	handle = 0 ifTrue: [
		sdl destroyWindow: sw.
		common setError: 'out of window handles'.
		^0].
	sdl startTextInput: sw.
	(table v + handle) i: (sdl getWindowID: sw).
	^handle
!
close: win
	<export>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	c4 platformSDL ifFalse: [gpu windowClosing: win].
	sdl stopTextInput: sw.
	sdl destroyWindow: sw.
	common table: table remove: win.
	"Interactive C4 never reissues a token within this process."
	c4 platformSDL ifTrue: [table freeHead: 0].
	^true
!
isLive: win
	<function>
	^((common table: table at: win kind: K_WINDOW) notNull)
!
presentRGBA: win width: w height: h pixels: pixels
	<export>
	<var: #pixels type: 'uint8_t *'>
	| sw |
	sw := self sdlWindow: win.
	sw isNull ifTrue: [^false].
	(sdl presentRGBA: sw width: w height: h pixels: pixels) ifTrue: [^true].
	common setError: 'SDL software present: %s' with: sdl getError.
	^false
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
setSize: win width: w height: h
	"Resize to w × h points; a window that is not resizable keeps the new size fixed."
	<export>
	| sw |
	sw := self sdlWindow: win.
	^sw notNull and: [sdl setWindowSize: sw w: w h: h]
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
			cursors at: i put: self null]].
	c4 platformSDL ifTrue: [
		libc free: table v.
		libc memset: table value: 0 size: (self sizeof: 'pf_table')]
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
