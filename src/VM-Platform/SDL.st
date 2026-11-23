CLibrary subclass: #SDL
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

SDL comment: 'The SDL3 functions of the platform layer: video, events, windows, cursors, the clipboard, hints, the log. Not simulated.'!

!SDL class methodsFor: 'declaring'!
headers
	^#('<SDL3/SDL.h>')
!
typedefs
	^#((Uint8 uint8_t) (Uint16 uint16_t) (Uint32 uint32_t) (Uint64 uint64_t) (Sint32 int32_t)
		(SDL_Window opaque) (SDL_Cursor opaque) (SDL_DisplayID uint32_t) (SDL_WindowID uint32_t) (SDL_WindowFlags uint64_t)
		(SDL_InitFlags uint32_t) (SDL_Keymod uint16_t) (SDL_Keycode uint32_t) (SDL_MouseButtonFlags uint32_t)
		(SDL_MouseWheelDirection uint32_t) (SDL_EventAction uint32_t) (SDL_SystemCursor uint32_t) (SDL_LogPriority uint32_t)
		(SDL_LogOutputFunction 'void (*)(void *, int, SDL_LogPriority, const char *)'))
! !

!SDL methodsFor: 'simulation'!
notSimulated
	^self error: 'SDL is not simulated'
! !

!SDL methodsFor: 'init'!
init: flags
	<c: 'bool SDL_Init(SDL_InitFlags flags)'>
	^self notSimulated
!
quit
	<c: 'void SDL_Quit(void)'>
	^self notSimulated
!
SDL_INIT_VIDEO
	<cMacro: 'SDL_InitFlags SDL_INIT_VIDEO'>
	^self notSimulated
!
setHint: name value: value
	<c: 'bool SDL_SetHint(const char *name, const char *value)'>
	^self notSimulated
!
SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE
	<cMacro: 'const char *SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE'>
	^self notSimulated
!
SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH
	<cMacro: 'const char *SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH'>
	^self notSimulated
!
SDL_HINT_IME_IMPLEMENTED_UI
	<cMacro: 'const char *SDL_HINT_IME_IMPLEMENTED_UI'>
	^self notSimulated
!
getError
	<c: 'const char *SDL_GetError(void)'>
	^self notSimulated
!
clearError
	<c: 'bool SDL_ClearError(void)'>
	^self notSimulated
!
getTicksNS
	<c: 'Uint64 SDL_GetTicksNS(void)'>
	^self notSimulated
!
free: mem
	<c: 'void SDL_free(void *mem)'>
	^self notSimulated
!
strlcpy: dst from: src size: maxlen
	<c: 'size_t SDL_strlcpy(char *dst, const char *src, size_t maxlen)'>
	^self notSimulated
! !

!SDL methodsFor: 'log'!
getDefaultLogOutputFunction
	<c: 'SDL_LogOutputFunction SDL_GetDefaultLogOutputFunction(void)'>
	^self notSimulated
!
setLogOutputFunction: callback userdata: userdata
	<c: 'void SDL_SetLogOutputFunction(SDL_LogOutputFunction callback, void *userdata)'>
	^self notSimulated
!
SDL_LOG_PRIORITY_ERROR
	<cMacro: 'SDL_LogPriority SDL_LOG_PRIORITY_ERROR'>
	^self notSimulated
! !

!SDL methodsFor: 'events'!
pumpEvents
	<c: 'void SDL_PumpEvents(void)'>
	^self notSimulated
!
peepEvents: events count: numevents action: action minType: minType maxType: maxType
	<c: 'int SDL_PeepEvents(SDL_Event *events, int numevents, SDL_EventAction action, Uint32 minType, Uint32 maxType)'>
	^self notSimulated
!
pushEvent: event
	<c: 'bool SDL_PushEvent(SDL_Event *event)'>
	^self notSimulated
!
registerEvents: numevents
	<c: 'Uint32 SDL_RegisterEvents(int numevents)'>
	^self notSimulated
!
waitEvent: event timeout: timeoutMS
	<c: 'bool SDL_WaitEventTimeout(SDL_Event *event, Sint32 timeoutMS)'>
	^self notSimulated
!
getModState
	<c: 'SDL_Keymod SDL_GetModState(void)'>
	^self notSimulated
!
SDL_GETEVENT
	<cMacro: 'SDL_EventAction SDL_GETEVENT'>
	^self notSimulated
!
SDL_EVENT_FIRST
	<cMacro: 'Uint32 SDL_EVENT_FIRST'>
	^self notSimulated
!
SDL_EVENT_LAST
	<cMacro: 'Uint32 SDL_EVENT_LAST'>
	^self notSimulated
!
SDL_EVENT_QUIT
	<cMacro: 'Uint32 SDL_EVENT_QUIT'>
	^self notSimulated
!
SDL_EVENT_MOUSE_MOTION
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_MOTION'>
	^self notSimulated
!
SDL_EVENT_MOUSE_BUTTON_DOWN
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_BUTTON_DOWN'>
	^self notSimulated
!
SDL_EVENT_MOUSE_BUTTON_UP
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_BUTTON_UP'>
	^self notSimulated
!
SDL_EVENT_MOUSE_WHEEL
	<cMacro: 'Uint32 SDL_EVENT_MOUSE_WHEEL'>
	^self notSimulated
!
SDL_EVENT_KEY_DOWN
	<cMacro: 'Uint32 SDL_EVENT_KEY_DOWN'>
	^self notSimulated
!
SDL_EVENT_KEY_UP
	<cMacro: 'Uint32 SDL_EVENT_KEY_UP'>
	^self notSimulated
!
SDL_EVENT_TEXT_INPUT
	<cMacro: 'Uint32 SDL_EVENT_TEXT_INPUT'>
	^self notSimulated
!
SDL_EVENT_TEXT_EDITING
	<cMacro: 'Uint32 SDL_EVENT_TEXT_EDITING'>
	^self notSimulated
!
SDL_EVENT_WINDOW_RESIZED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_RESIZED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_CLOSE_REQUESTED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_CLOSE_REQUESTED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_FOCUS_GAINED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_FOCUS_GAINED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_FOCUS_LOST
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_FOCUS_LOST'>
	^self notSimulated
!
SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED'>
	^self notSimulated
!
SDL_EVENT_WINDOW_MOUSE_LEAVE
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_MOUSE_LEAVE'>
	^self notSimulated
!
SDL_EVENT_WINDOW_EXPOSED
	<cMacro: 'Uint32 SDL_EVENT_WINDOW_EXPOSED'>
	^self notSimulated
!
SDL_KMOD_SHIFT
	<cMacro: 'SDL_Keymod SDL_KMOD_SHIFT'>
	^self notSimulated
!
SDL_KMOD_CTRL
	<cMacro: 'SDL_Keymod SDL_KMOD_CTRL'>
	^self notSimulated
!
SDL_KMOD_ALT
	<cMacro: 'SDL_Keymod SDL_KMOD_ALT'>
	^self notSimulated
!
SDL_KMOD_GUI
	<cMacro: 'SDL_Keymod SDL_KMOD_GUI'>
	^self notSimulated
! !

!SDL methodsFor: 'windows'!
createWindow: title width: w height: h flags: flags
	<c: 'SDL_Window *SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags)'>
	^self notSimulated
!
destroyWindow: window
	<c: 'void SDL_DestroyWindow(SDL_Window *window)'>
	^self notSimulated
!
startTextInput: window
	<c: 'bool SDL_StartTextInput(SDL_Window *window)'>
	^self notSimulated
!
stopTextInput: window
	<c: 'bool SDL_StopTextInput(SDL_Window *window)'>
	^self notSimulated
!
setTextInputArea: window rect: rect cursor: cursor
	<c: 'bool SDL_SetTextInputArea(SDL_Window *window, const SDL_Rect *rect, int cursor)'>
	^self notSimulated
!
getWindowID: window
	<c: 'SDL_WindowID SDL_GetWindowID(SDL_Window *window)'>
	^self notSimulated
!
getWindowSize: window width: w height: h
	<c: 'bool SDL_GetWindowSize(SDL_Window *window, int *w, int *h)'>
	^self notSimulated
!
getWindowSizeInPixels: window width: w height: h
	<c: 'bool SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h)'>
	^self notSimulated
!
getWindowDisplayScale: window
	<c: 'float SDL_GetWindowDisplayScale(SDL_Window *window)'>
	^self notSimulated
!
getPrimaryDisplay
	<c: 'SDL_DisplayID SDL_GetPrimaryDisplay(void)'>
	^self notSimulated
!
getDisplayForWindow: window
	<c: 'SDL_DisplayID SDL_GetDisplayForWindow(SDL_Window *window)'>
	^self notSimulated
!
getCurrentDisplayMode: displayID
	<c: 'const SDL_DisplayMode *SDL_GetCurrentDisplayMode(SDL_DisplayID displayID)'>
	^self notSimulated
!
setWindowTitle: window title: title
	<c: 'bool SDL_SetWindowTitle(SDL_Window *window, const char *title)'>
	^self notSimulated
!
setWindowSize: window w: w h: h
	<c: 'bool SDL_SetWindowSize(SDL_Window *window, int w, int h)'>
	^self notSimulated
!
showWindow: window
	<c: 'bool SDL_ShowWindow(SDL_Window *window)'>
	^self notSimulated
!
raiseWindow: window
	<c: 'bool SDL_RaiseWindow(SDL_Window *window)'>
	^self notSimulated
!
hideWindow: window
	<c: 'bool SDL_HideWindow(SDL_Window *window)'>
	^self notSimulated
!
getWindowFlags: window
	<c: 'SDL_WindowFlags SDL_GetWindowFlags(SDL_Window *window)'>
	^self notSimulated
!
SDL_WINDOW_HIDDEN
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_HIDDEN'>
	^self notSimulated
!
SDL_WINDOW_MINIMIZED
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_MINIMIZED'>
	^self notSimulated
!
SDL_WINDOW_RESIZABLE
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_RESIZABLE'>
	^self notSimulated
!
SDL_WINDOW_HIGH_PIXEL_DENSITY
	<cMacro: 'SDL_WindowFlags SDL_WINDOW_HIGH_PIXEL_DENSITY'>
	^self notSimulated
! !

!SDL methodsFor: 'cursors'!
createSystemCursor: id
	<c: 'SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id)'>
	^self notSimulated
!
setCursor: cursor
	<c: 'bool SDL_SetCursor(SDL_Cursor *cursor)'>
	^self notSimulated
!
destroyCursor: cursor
	<c: 'void SDL_DestroyCursor(SDL_Cursor *cursor)'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_DEFAULT
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_DEFAULT'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_TEXT
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_TEXT'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_POINTER
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_POINTER'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_EW_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_EW_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NS_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NS_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NWSE_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NWSE_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NESW_RESIZE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NESW_RESIZE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_MOVE
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_MOVE'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_WAIT
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_WAIT'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_CROSSHAIR
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_CROSSHAIR'>
	^self notSimulated
!
SDL_SYSTEM_CURSOR_NOT_ALLOWED
	<cMacro: 'SDL_SystemCursor SDL_SYSTEM_CURSOR_NOT_ALLOWED'>
	^self notSimulated
! !

!SDL methodsFor: 'clipboard'!
getClipboardText
	<c: 'char *SDL_GetClipboardText(void)'>
	^self notSimulated
!
setClipboardText: text
	<c: 'bool SDL_SetClipboardText(const char *text)'>
	^self notSimulated
!
getClipboardData: mime size: size
	<c: 'void *SDL_GetClipboardData(const char *mime_type, size_t *size)'>
	^self notSimulated
! !

ExternStruct subclass: #SDLCommonEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLCommonEvent class methodsFor: 'declaring'!
cName
	^'SDL_CommonEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64))
! !

ExternStruct subclass: #SDLMouseMotionEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLMouseMotionEvent class methodsFor: 'declaring'!
cName
	^'SDL_MouseMotionEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (state SDL_MouseButtonFlags) (x float) (y float))
! !

ExternStruct subclass: #SDLMouseButtonEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLMouseButtonEvent class methodsFor: 'declaring'!
cName
	^'SDL_MouseButtonEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (button Uint8) (down bool) (clicks Uint8) (x float) (y float))
! !

ExternStruct subclass: #SDLMouseWheelEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLMouseWheelEvent class methodsFor: 'declaring'!
cName
	^'SDL_MouseWheelEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (x float) (y float) (direction SDL_MouseWheelDirection) (mouse_x float) (mouse_y float))
! !

ExternStruct subclass: #SDLKeyboardEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLKeyboardEvent class methodsFor: 'declaring'!
cName
	^'SDL_KeyboardEvent'
!
cNameOfField: aSymbol
	"repeat is a Lowtalk control structure."
	^aSymbol = #isRepeat ifTrue: ['repeat'] ifFalse: [super cNameOfField: aSymbol]
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (which Uint32) (scancode Uint32) (key SDL_Keycode) (mod SDL_Keymod) (raw Uint16) (down bool) (isRepeat bool))
! !

ExternStruct subclass: #SDLTextInputEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLTextInputEvent class methodsFor: 'declaring'!
cName
	^'SDL_TextInputEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (text 'const char *'))
! !

ExternStruct subclass: #SDLTextEditingEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLTextEditingEvent class methodsFor: 'declaring'!
cName
	^'SDL_TextEditingEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (text 'const char *') (start Sint32) (length Sint32))
! !

ExternStruct subclass: #SDLWindowEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLWindowEvent class methodsFor: 'declaring'!
cName
	^'SDL_WindowEvent'
!
fields
	^#((type Uint32) (reserved Uint32) (timestamp Uint64) (windowID SDL_WindowID) (data1 Sint32) (data2 Sint32))
! !

ExternStruct subclass: #SDLEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLEvent class methodsFor: 'declaring'!
cName
	^'SDL_Event'
!
fields
	^#((union (type Uint32) (common SDL_CommonEvent) (motion SDL_MouseMotionEvent) (button SDL_MouseButtonEvent)
		(wheel SDL_MouseWheelEvent) (key SDL_KeyboardEvent) (edit SDL_TextEditingEvent) (text SDL_TextInputEvent) (window SDL_WindowEvent) (padding 'Uint8[128]')))
! !

ExternStruct subclass: #SDLDisplayMode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLDisplayMode class methodsFor: 'declaring'!
cName
	^'SDL_DisplayMode'
!
fields
	^#((displayID SDL_DisplayID) (format Uint32) (w int) (h int) (pixel_density float) (refresh_rate float))
! !

ExternStruct subclass: #SDLRect
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLRect class methodsFor: 'declaring'!
cName
	^'SDL_Rect'
!
fields
	^#((x int) (y int) (w int) (h int))
! !

ExternStruct subclass: #SDLFColor
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!SDLFColor class methodsFor: 'declaring'!
cName
	^'SDL_FColor'
!
fields
	^#((r float) (g float) (b float) (a float))
! !
