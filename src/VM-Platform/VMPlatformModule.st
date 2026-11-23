VMPrimitiveModule subclass: #VMPlatformModule
	instanceVariableNames: 'common events windows gpu files sockets ptys tls vsync host sdlPlatform sdl sdlGpu posixIO posixProcesses posixSockets posixThreads machine raster'
	classVariableNames: 'PF_BLEND_ALPHA PF_BLEND_NONE PF_BLEND_PREMULTIPLIED PF_BUFUSE_INDEX PF_BUFUSE_STORAGE PF_BUFUSE_VERTEX PF_EVENT_QUEUE_MAX PF_EV_DISPLAY_SCALE_CHANGED PF_EV_FOCUS_GAINED PF_EV_FOCUS_LOST PF_EV_KEY_DOWN PF_EV_KEY_UP PF_EV_MOUSE_DOWN PF_EV_MOUSE_LEAVE PF_EV_MOUSE_MOVE PF_EV_MOUSE_UP PF_EV_QUIT PF_EV_TEXT_EDITING PF_EV_TEXT_INPUT PF_EV_WHEEL PF_EV_WINDOW_CLOSE_REQUEST PF_EV_WINDOW_EXPOSED PF_EV_WINDOW_RESIZED PF_FD_PTY PF_FD_SOCKET PF_FD_TLS PF_FILE_APPEND PF_FILE_CREATE_PRIVATE PF_FILE_CREATE_TRUNCATE PF_FILE_READ PF_FILE_READ_WRITE PF_HANDLE_COUNTS PF_MOD_ALT PF_MOD_CMD PF_MOD_CTRL PF_MOD_SHIFT PF_POLL_US PF_PRIM_LINES PF_PRIM_LINE_STRIP PF_PRIM_POINTS PF_PRIM_TRIANGLES PF_PRIM_TRIANGLE_STRIP PF_STAGE_FRAGMENT PF_STAGE_VERTEX PF_TEXUSE_COLOR_TARGET PF_TEXUSE_SAMPLER PF_TEX_BGRA8 PF_TEX_R8 PF_TEX_RGBA8 PF_VA_FLOAT PF_VA_FLOAT2 PF_VA_FLOAT3 PF_VA_FLOAT4 PF_VA_INT PF_VA_UBYTE4 PF_VA_UBYTE4_NORM PF_VA_UINT PF_WIN_HIDDEN PF_WIN_HIGH_DENSITY PF_WIN_RESIZABLE PF_X_BOOL PF_X_INT PF_X_NIL PF_X_POINT PF_X_TEXT'
	package: 'VM-Platform'!

VMPlatformModule comment: 'I am the abstract class of the platform layer''s modules (SDL3 windows and input, SDL_GPU, files, sockets, TLS, pseudo-terminals): I connect them to each other and to their C libraries and hold the constants of their C interface (the PF_ names). The internals use handles, small positive ints (0 = failure, see last_error_string), and run on the VM thread unless their comment says otherwise. PlatformPrimitives wraps them as primitives; SDLPlatform implements PlatformInterface with them; PlatformHost holds what differs between operating systems.

Handle tables and mutexes are one-element arrays, so that their names are pointers.'!

!VMPlatformModule class methodsFor: 'declaring'!
declarations
	^#((common PlatformCommon) (events PlatformEvents) (windows PlatformWindows) (gpu PlatformGPU) (files PlatformFiles)
		(sockets PlatformSockets) (ptys PlatformPtys) (tls PlatformTLS) (vsync PlatformVsync) (host PlatformHost) (sdlPlatform SDLPlatform)
		(sdl SDL) (sdlGpu SDLGPU) (posixIO PosixIO) (posixProcesses PosixProcesses)
		(posixSockets PosixSockets) (posixThreads PosixThreads) (machine PlatformMachine) (raster PlatformRaster))
!
isAbstractModule
	^self == VMPlatformModule
!
initialize
	"Events: type, modifiers, the kind of textOrDelta; the queue holds at most PF_EVENT_QUEUE_MAX (256 << k)."
	PF_EV_MOUSE_MOVE := 1.
	PF_EV_MOUSE_DOWN := 2.
	PF_EV_MOUSE_UP := 3.
	PF_EV_WHEEL := 4.
	PF_EV_KEY_DOWN := 5.
	PF_EV_KEY_UP := 6.
	PF_EV_TEXT_INPUT := 7.
	PF_EV_WINDOW_RESIZED := 8.
	PF_EV_WINDOW_CLOSE_REQUEST := 9.
	PF_EV_QUIT := 10.
	PF_EV_FOCUS_GAINED := 11.
	PF_EV_FOCUS_LOST := 12.
	PF_EV_DISPLAY_SCALE_CHANGED := 13.
	PF_EV_MOUSE_LEAVE := 14.
	PF_EV_WINDOW_EXPOSED := 15.
	PF_EV_TEXT_EDITING := 16.
	PF_MOD_SHIFT := 1.
	PF_MOD_CTRL := 2.
	PF_MOD_ALT := 4.
	PF_MOD_CMD := 8.
	PF_X_NIL := 0.
	PF_X_INT := 1.
	PF_X_BOOL := 2.
	PF_X_TEXT := 3.
	PF_X_POINT := 4.
	PF_EVENT_QUEUE_MAX := 4096.
	"windows"
	PF_WIN_HIDDEN := 1.
	PF_WIN_RESIZABLE := 2.
	PF_WIN_HIGH_DENSITY := 4.
	"GPU"
	PF_TEX_R8 := 1.
	PF_TEX_RGBA8 := 2.
	PF_TEX_BGRA8 := 3.
	PF_TEXUSE_SAMPLER := 1.
	PF_TEXUSE_COLOR_TARGET := 2.
	PF_BUFUSE_VERTEX := 1.
	PF_BUFUSE_INDEX := 2.
	PF_BUFUSE_STORAGE := 4.
	PF_STAGE_VERTEX := 0.
	PF_STAGE_FRAGMENT := 1.
	PF_BLEND_NONE := 0.
	PF_BLEND_ALPHA := 1.
	PF_BLEND_PREMULTIPLIED := 2.
	PF_PRIM_TRIANGLES := 0.
	PF_PRIM_TRIANGLE_STRIP := 1.
	PF_PRIM_LINES := 2.
	PF_PRIM_LINE_STRIP := 3.
	PF_PRIM_POINTS := 4.
	PF_VA_FLOAT := 1.
	PF_VA_FLOAT2 := 2.
	PF_VA_FLOAT3 := 3.
	PF_VA_FLOAT4 := 4.
	PF_VA_UBYTE4_NORM := 5.
	PF_VA_UBYTE4 := 6.
	PF_VA_UINT := 7.
	PF_VA_INT := 8.
	"files; sockets and pty masters share one handle table"
	PF_FILE_READ := 0.
	PF_FILE_READ_WRITE := 1.
	PF_FILE_APPEND := 2.
	PF_FILE_CREATE_TRUNCATE := 3.
	PF_FILE_CREATE_PRIVATE := 4.
	PF_FD_SOCKET := 1.
	PF_FD_PTY := 2.
	PF_FD_TLS := 3.
	"platform_interface_poll cadence while Smalltalk runs and OS events or sockets may arrive"
	PF_POLL_US := 1000.
	"live handles: files sockets windows gpuDevices shaders pipelines textures samplers buffers fences ptys"
	PF_HANDLE_COUNTS := 11
! !
