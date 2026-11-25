VMPlatformModule subclass: #PlatformHost
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformHost comment: 'What the platform layer does differently on each operating system: the display-refresh thread behind PlatformVsync, the process environment and a UTF-8 locale in it, socket setup, which keys are cmd and alt, the shader formats asked of SDL_GPU and compiling GLSL for them. DarwinPlatformHost and LinuxPlatformHost implement me under the same C names; the build links the one of its OS (targetOS).'!

!PlatformHost class methodsFor: 'declaring'!
isAbstractModule
	^self == PlatformHost
!
isInterface
	^self == PlatformHost
! !

!PlatformHost methodsFor: 'host'!
vsyncStart
	"Call vsync refreshed (from a thread of mine) at each display refresh from now on; false (and the error set) if that cannot be done."
	self subclassResponsibility
!
vsyncStop
	self subclassResponsibility
!
environment
	"The process's environment (NAME=value strings, NULL-terminated)."
	self subclassResponsibility
!
videoStarted
	"SDL's video has just started (SDL_Init): what this OS needs done then."
	self subclassResponsibility
!

socketOpened: fd
	"A new socket: a write to it after the peer closed must fail (EPIPE), not kill the VM with SIGPIPE."
	self subclassResponsibility
!
cmdKeymod
	"The SDL modifier that is the image's cmd (PF_MOD_CMD)."
	self subclassResponsibility
!
altKeymod
	"The SDL modifier that is the image's alt (PF_MOD_ALT)."
	self subclassResponsibility
!
shaderFormats
	"The shader formats a GPU device is created for."
	self subclassResponsibility
!
utf8Ctype
	"The environment entry LC_CTYPE=… of a UTF-8 locale every system has."
	self subclassResponsibility
!
compileShader: source stage: stage size: sizeOut
	"SPIR-V compiled from GLSL source for stage (PF_STAGE_*, with SAMALTAK_VERTEX or SAMALTAK_FRAGMENT defined), malloc'd, its size in sizeOut; NULL with the error set (the compiler's log) if it does not compile."
	self subclassResponsibility
! !

!PlatformHost methodsFor: 'desktop windows'!
openDesktopWindow: title width: w height: h flags: flags
	"A window on the desktop (PF_WIN_DESKTOP): above the wallpaper, below every window, placed by moveDesktopWindow:x:y:, never taking the keyboard focus; NULL where the system has none (PlatformWindows then opens an ordinary window)."
	self subclassResponsibility
!
resizeDesktopWindow: sw width: w height: h
	"Resize desktop window sw to w × h points; false if sw is no desktop window."
	self subclassResponsibility
!
moveDesktopWindow: sw x: x y: y
	"Place desktop window sw x @ y points from the top left of the area the bar and docks leave free; false if sw is no desktop window."
	self subclassResponsibility
!
raiseDesktopWindow: sw
	"Put desktop window sw above the other desktop windows; false if it is none."
	self subclassResponsibility
!
setDesktopWindowOpacity: sw permille: permille
	"Show desktop window sw at permille / 1000 opacity; false if it is none or the system cannot."
	self subclassResponsibility
!
desktopWindowCornerRadius: sw
	"The radius (points) the system rounds desktop window sw's corners with; 0 if they are square or sw is none."
	self subclassResponsibility
!
wheelPointScale
	"What turns the wheel deltas SDL just reported into points, if they came from a device that scrolls by points (a trackpad); 0 if they are a wheel's steps."
	self subclassResponsibility
!
presenting: sw width: w height: h
	"The image is about to present a frame of w × h points in SDL window sw (before it acquires the frame's drawable)."
	self subclassResponsibility
!
eventsPumped
	"SDL pumped the system's events."
	self subclassResponsibility
!
ownsSizeOf: sw
	"Whether the image learns SDL window sw's size from me rather than from SDL now."
	self subclassResponsibility
!
setWindowBackground: sw rgb: rgb
	"Show rgb (16rRRGGBB) in SDL window sw where no frame is drawn; false where the system does not tell."
	self subclassResponsibility
!
desktopMovedEvent
	"The SDL event type that reports where a desktop window was moved (data1: its window id, x and y as int32_t, malloc'd), once the system applied the move; 0 if none."
	self subclassResponsibility
!
closingDesktopWindow: sw
	"SDL window sw is about to be destroyed."
	self subclassResponsibility
! !

PlatformHost subclass: #DarwinPlatformHost
	instanceVariableNames: 'coreVideo darwin displayLink'
	classVariableNames: ''
	package: 'VM-Platform'!

DarwinPlatformHost comment: 'The platform layer on macOS: a CVDisplayLink thread for the refreshes, _NSGetEnviron, SO_NOSIGPIPE, the command key as cmd, MSL shaders (SDL_GPU on Metal; GLSL is not compiled here), desktop windows as borderless windows on every Space at the level just above Finder''s desktop.'!

!DarwinPlatformHost class methodsFor: 'declaring'!
declarations
	^#((coreVideo CoreVideo) (darwin DarwinPlatform) (displayLink CVDisplayLinkRef))
!
targetOS
	^#darwin
! !

!DarwinPlatformHost methodsFor: 'host'!
onRefresh: link now: now output: outputTime flags: flagsIn flagsOut: flagsOut context: context
	"The display link's thread."
	<function>
	vsync refreshed.
	^coreVideo kCVReturnSuccess
!
vsyncStart
	<export>
	| link ref |
	darwin installPaste.
	link := self local: 'CVDisplayLinkRef'.
	(coreVideo createWithActiveCGDisplays: link) ~= coreVideo kCVReturnSuccess ifTrue: [
		common setError: 'CVDisplayLinkCreateWithActiveCGDisplays failed'.
		^false].
	ref := link value.
	(coreVideo setOutputCallback: ref callback: (self functionPointer: #onRefresh:now:output:flags:flagsOut:context:) userInfo: self null) ~= coreVideo kCVReturnSuccess ifTrue: [
		coreVideo release: ref.
		common setError: 'CVDisplayLinkSetOutputCallback failed'.
		^false].
	(coreVideo start: ref) ~= coreVideo kCVReturnSuccess ifTrue: [
		coreVideo release: ref.
		common setError: 'CVDisplayLinkStart failed'.
		^false].
	displayLink := ref.
	^true
!
vsyncStop
	<export>
	coreVideo stop: displayLink.
	coreVideo release: displayLink.
	displayLink := self null
!
environment
	<export>
	^darwin environment value
!
videoStarted
	<export>
	^self
!

socketOpened: fd
	<export>
	| one |
	one := self local: 'int'.
	one value: 1.
	posixSockets setsockopt: fd level: posixSockets SOL_SOCKET option: posixSockets SO_NOSIGPIPE value: one length: (self sizeof: 'int') asUInt32
!
cmdKeymod
	<export>
	^sdl SDL_KMOD_GUI
!
altKeymod
	<export>
	^sdl SDL_KMOD_ALT
!
shaderFormats
	<export>
	^sdlGpu SDL_GPU_SHADERFORMAT_MSL
!
utf8Ctype
	<export>
	^'LC_CTYPE=UTF-8'
!
compileShader: source stage: stage size: sizeOut
	<export>
	common setError: 'GLSL is compiled only on Linux (SDL_GPU on Vulkan); on Metal shaders are MSL'.
	^self null
! !

!DarwinPlatformHost methodsFor: 'desktop windows'!
openDesktopWindow: title width: w height: h flags: flags
	"A borderless window that never takes the focus, on every Space at the level just above Finder's desktop; a transparent one (SDL_WINDOW_TRANSPARENT) lets the pointer through."
	<export>
	<returns: 'SDL_Window *'>
	<var: #flags type: 'SDL_WindowFlags'>
	| sw |
	sw := sdl createWindow: title width: w height: h
		flags: (flags bitOr: ((sdl SDL_WINDOW_BORDERLESS bitOr: sdl SDL_WINDOW_NOT_FOCUSABLE) bitOr: sdl SDL_WINDOW_HIDDEN)).
	sw isNull ifTrue: [^sw].
	darwin configureDesktop: sw passThrough: (flags bitAnd: sdl SDL_WINDOW_TRANSPARENT) ~= 0.
	sdl setHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN value: '0'.
	sdl showWindow: sw.
	sdl resetHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN.
	^sw
!
resizeDesktopWindow: sw width: w height: h
	"SDL resizes it."
	<export>
	<var: #sw type: 'SDL_Window *'>
	^false
!
moveDesktopWindow: sw x: x y: y
	"From the top left of the primary display's area the menu bar and the Dock leave free. The move is applied at once, so PF_EV_WINDOW_MOVED follows at once."
	<export>
	<var: #sw type: 'SDL_Window *'>
	| r ev |
	(darwin isDesktop: sw) ifFalse: [^false].
	r := self local: 'SDL_Rect'.
	(sdl getDisplayUsableBounds: sdl getPrimaryDisplay rect: r) ifFalse: [^false].
	(sdl setWindowPosition: sw x: r x + x y: r y + y) ifFalse: [^false].
	ev := self local: 'pf_event'.
	ev type: PF_EV_WINDOW_MOVED.
	ev timeMs: common nowMs.
	ev x: x asFloat.
	ev y: y asFloat.
	ev window: (windows fromSDLId: (sdl getWindowID: sw)).
	events push: ev.
	^true
!
raiseDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	(darwin isDesktop: sw) ifFalse: [^false].
	((sdl getWindowFlags: sw) bitAnd: sdl SDL_WINDOW_HIDDEN) ~= 0 ifTrue: [
		sdl setHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN value: '0'.
		sdl showWindow: sw.
		sdl resetHint: sdl SDL_HINT_WINDOW_ACTIVATE_WHEN_SHOWN].
	darwin orderFront: sw.
	^true
!
setDesktopWindowOpacity: sw permille: permille
	"SDL sets it."
	<export>
	<var: #sw type: 'SDL_Window *'>
	^false
!
desktopWindowCornerRadius: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	<returns: 'int'>
	^darwin cornerRadius: sw
!
wheelPointScale
	<export>
	<returns: 'double'>
	^darwin wheelPointScale
!
presenting: sw width: w height: h
	"A window being resized by its edges takes the size of the frame."
	<export>
	<var: #sw type: 'SDL_Window *'>
	<var: #w type: 'int'>
	<var: #h type: 'int'>
	darwin presenting: sw width: w height: h
!
eventsPumped
	"The image learns the size a window being resized by its edges is asked for, as a resize of the window."
	<export>
	| sw w h ev |
	sw := self local: 'SDL_Window *'.
	w := self local: 'int'.
	h := self local: 'int'.
	(darwin resizeRequest: sw width: w height: h) ifFalse: [^self].
	ev := self local: 'pf_event'.
	ev type: PF_EV_WINDOW_RESIZED.
	ev timeMs: common nowMs.
	ev x: w value asFloat.
	ev y: h value asFloat.
	ev window: (windows fromSDLId: (sdl getWindowID: sw value)).
	ev window = 0 ifFalse: [events push: ev]
!
ownsSizeOf: sw
	"While it is resized by its edges."
	<export>
	<var: #sw type: 'SDL_Window *'>
	^darwin ownsSizeOf: sw
!
setWindowBackground: sw rgb: rgb
	<export>
	<var: #sw type: 'SDL_Window *'>
	<var: #rgb type: 'uint32_t'>
	^darwin background: sw rgb: rgb
!
desktopMovedEvent
	<export>
	<returns: 'Uint32'>
	^0
!
closingDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
! !

PlatformHost subclass: #LinuxPlatformHost
	instanceVariableNames: 'linux desktop shaderc compiler vertexOptions fragmentOptions vsyncOn vsyncPeriodUs vsyncStarted xPrevious'
	classVariableNames: ''
	package: 'VM-Platform'!

LinuxPlatformHost comment: 'The platform layer on Linux: a thread that wakes at the display''s refresh rate (absolute CLOCK_MONOTONIC deadlines) for the refreshes, environ, SIGPIPE ignored (there is no SO_NOSIGPIPE), the alt key as cmd and the super key as alt (the window manager keeps most super combinations), GLSL compiled to SPIR-V with shaderc (SDL_GPU on Vulkan), desktop windows as Wayland layer surfaces (WaylandDesktop; none under X11).'!

!LinuxPlatformHost class methodsFor: 'declaring'!
declarations
	^#((linux LinuxPlatform) (desktop WaylandDesktop) (shaderc Shaderc) (compiler shaderc_compiler_t) (vertexOptions shaderc_compile_options_t)
		(fragmentOptions shaderc_compile_options_t) (vsyncOn atomic_bool) (vsyncPeriodUs atomic_int) (vsyncStarted bool)
		(xPrevious x_error_handler))
!
typedefs
	"XSetErrorHandler's handler and XSetErrorHandler itself (Xlib, found with dlsym: no X11 headers needed)"
	^#((x_error_handler 'int (*)(void *, void *)') (x_set_error_handler 'x_error_handler (*)(x_error_handler)'))
!
targetOS
	^#linux
! !

!LinuxPlatformHost methodsFor: 'host'!
vsyncStart
	<export>
	| mode rate t |
	mode := sdl getCurrentDisplayMode: sdl getPrimaryDisplay.
	rate := (mode notNull and: [mode refresh_rate > 0.0]) ifTrue: [mode refresh_rate asFloat] ifFalse: [60.0].
	self atomicStore: #vsyncPeriodUs value: (1000000.0 / rate) truncated asInt32.
	self atomicStore: #vsyncOn value: true.
	vsyncStarted ifFalse: [
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #vsyncRun:) argument: self null) ~= 0 ifTrue: [
			common setError: 'cannot start the vsync thread'.
			^false].
		posix pthreadDetach: t value.
		vsyncStarted := true].
	^true
!
vsyncStop
	<export>
	self atomicStore: #vsyncOn value: false
!
vsyncRun: arg
	"The vsync thread: refreshed every vsyncPeriodUs, on absolute deadlines (no drift; one that has fallen behind by more than a period starts again from now); naps of 100 ms while stopped."
	<function>
	| next now nap period |
	next := self local: 'Timespec'.
	now := self local: 'Timespec'.
	nap := self local: 'Timespec'.
	nap tv_nsec: 100000000.
	posix clockGettime: posix CLOCK_MONOTONIC into: next.
	[true] whileTrue: [
		(self atomicLoad: #vsyncOn)
			ifTrue: [
				period := (self atomicLoad: #vsyncPeriodUs) asInt64 * 1000.
				next tv_nsec: next tv_nsec + period.
				[next tv_nsec >= 1000000000] whileTrue: [
					next tv_sec: next tv_sec + 1.
					next tv_nsec: next tv_nsec - 1000000000].
				posix clockGettime: posix CLOCK_MONOTONIC into: now.
				((now tv_sec - next tv_sec) * 1000000000) + (now tv_nsec - next tv_nsec) > period ifTrue: [now copyStructFrom: next].
				linux clockNanosleep: posix CLOCK_MONOTONIC flags: linux TIMER_ABSTIME request: next remain: self null.
				vsync refreshed]
			ifFalse: [
				posixThreads nanosleep: nap remaining: self null.
				posix clockGettime: posix CLOCK_MONOTONIC into: next]].
	^self null
!
environment
	<export>
	^linux environ
!
videoStarted
	"On X11, an X error ends the process unless an error handler says otherwise, and SDL causes one it cannot help: it
	wakes a wait (SDL_PushEvent from another thread: the vsync thread's wake) with a client message to a window of the
	wait, sent on a connection of its own, which can reach the server after that window was destroyed on the main
	connection: a BadWindow of X_SendEvent (it reproduces opening and closing a window in a loop on a loaded machine).
	So onXError:event: ignores that one and passes every other error on to Xlib's handler. libX11 is SDL's (dlopen
	RTLD_NOLOAD: nothing when SDL is not on X11)."
	<export>
	| x11 set |
	x11 := linux dlopen: 'libX11.so.6' mode: (linux RTLD_NOW bitOr: linux RTLD_NOLOAD).
	x11 isNull ifTrue: [^self].
	set := self cCoerce: (linux dlsym: x11 name: 'XSetErrorHandler') to: 'x_set_error_handler'.
	set isNull ifFalse: [xPrevious := set call: (self functionPointer: #onXError:event:)]
!
onXError: display event: event
	"Xlib's error handler (videoStarted): a BadWindow (3) of X_SendEvent (25) is ignored, any other error goes to the
	handler before (Xlib's: prints it and exits). In an XErrorEvent (LP64) error_code is byte 32, request_code byte 33."
	<function>
	<var: #display type: 'void *'>
	<var: #event type: 'void *'>
	<returns: 'int'>
	| e |
	e := self cCoerce: event to: 'uint8_t *'.
	((e at: 32) = 3 and: [(e at: 33) = 25]) ifTrue: [^0].
	xPrevious isNull ifTrue: [^0].
	^xPrevious call: display with: event
!

socketOpened: fd
	<export>
	posixIO signal: posixIO SIGPIPE handler: posixIO SIG_IGN
!
cmdKeymod
	<export>
	^sdl SDL_KMOD_ALT
!
altKeymod
	<export>
	^sdl SDL_KMOD_GUI
!
shaderFormats
	<export>
	^sdlGpu SDL_GPU_SHADERFORMAT_SPIRV
!
utf8Ctype
	<export>
	^'LC_CTYPE=C.UTF-8'
!
compileShader: source stage: stage size: sizeOut
	<export>
	| fragment r n code |
	compiler isNull ifTrue: [
		compiler := shaderc compilerInitialize.
		vertexOptions := self optionsDefining: 'SAMALTAK_VERTEX'.
		fragmentOptions := self optionsDefining: 'SAMALTAK_FRAGMENT'].
	(compiler isNull or: [vertexOptions isNull or: [fragmentOptions isNull]]) ifTrue: [
		common setError: 'cannot initialize shaderc'.
		^self null].
	fragment := stage = PF_STAGE_FRAGMENT.
	r := shaderc compile: compiler source: source size: (libc strlen: source)
		kind: (fragment ifTrue: [shaderc shaderc_fragment_shader] ifFalse: [shaderc shaderc_vertex_shader])
		file: (fragment ifTrue: ['fragment'] ifFalse: ['vertex']) entry: 'main'
		options: (fragment ifTrue: [fragmentOptions] ifFalse: [vertexOptions]).
	r isNull ifTrue: [
		common setError: 'shaderc: out of memory'.
		^self null].
	(shaderc resultStatus: r) ~= shaderc shaderc_compilation_status_success ifTrue: [
		common setError: (shaderc resultErrorMessage: r).
		shaderc resultRelease: r.
		^self null].
	n := shaderc resultLength: r.
	code := libc malloc: n.
	code isNull
		ifTrue: [common setError: 'out of memory']
		ifFalse: [
			libc memcpy: code from: (shaderc resultBytes: r) size: n.
			sizeOut value: n].
	shaderc resultRelease: r.
	^code
!
optionsDefining: macro
	"Compile options for Vulkan: optimized, with macro defined (to 1)."
	| o |
	o := shaderc optionsInitialize.
	o notNull ifTrue: [
		shaderc options: o optimization: shaderc shaderc_optimization_level_performance.
		shaderc options: o define: macro length: (libc strlen: macro) value: '1' length: 1].
	^o
! !

CLibrary subclass: #DarwinPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

DarwinPlatform comment: 'The macOS calls of DarwinPlatformHost. Not simulated.'!

!DarwinPlatform class methodsFor: 'declaring'!
headers
	^#('<crt_externs.h>')
!
targetOS
	^#darwin
! !

!DarwinPlatform methodsFor: 'functions'!
environment
	"The environ of the process: the address of the environment array."
	<c: 'char ***_NSGetEnviron(void)'>
	^self error: 'not simulated'
! !

!LinuxPlatformHost methodsFor: 'desktop windows'!
openDesktopWindow: title width: w height: h flags: flags
	<export>
	<returns: 'SDL_Window *'>
	<var: #flags type: 'SDL_WindowFlags'>
	^desktop openSurface: title width: w height: h flags: flags
!
resizeDesktopWindow: sw width: w height: h
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop resizeSurface: sw width: w height: h
!
moveDesktopWindow: sw x: x y: y
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop placeSurface: sw x: x y: y
!
raiseDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop raiseSurface: sw
!
setDesktopWindowOpacity: sw permille: permille
	<export>
	<var: #sw type: 'SDL_Window *'>
	^desktop setSurfaceOpacity: sw permille: permille
!
desktopWindowCornerRadius: sw
	"Layer surfaces are square."
	<export>
	<var: #sw type: 'SDL_Window *'>
	<returns: 'int'>
	^0
!
wheelPointScale
	"SDL does not tell a touchpad's points from a wheel's steps."
	<export>
	<returns: 'double'>
	^0.0
!
presenting: sw width: w height: h
	"The window manager sizes the windows."
	<export>
	<var: #sw type: 'SDL_Window *'>
	<var: #w type: 'int'>
	<var: #h type: 'int'>
!
eventsPumped
	<export>
!
ownsSizeOf: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	^false
!
setWindowBackground: sw rgb: rgb
	"A window is never shown without its frame."
	<export>
	<var: #sw type: 'SDL_Window *'>
	<var: #rgb type: 'uint32_t'>
	^false
!
desktopMovedEvent
	<export>
	<returns: 'Uint32'>
	^desktop movedEventType
!
closingDesktopWindow: sw
	<export>
	<var: #sw type: 'SDL_Window *'>
	desktop destroySurface: sw
! !

CLibrary subclass: #LinuxPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

LinuxPlatform comment: 'The Linux calls of LinuxPlatformHost (environ needs _GNU_SOURCE). Not simulated.'!

!LinuxPlatform class methodsFor: 'declaring'!
headers
	^#('<unistd.h>' '<time.h>' '<dlfcn.h>')
!
targetOS
	^#linux
! !

!LinuxPlatform methodsFor: 'functions'!
environ
	<cVariable: 'char **environ'>
	^self error: 'not simulated'
!
clockNanosleep: clock flags: flags request: request remain: remain
	<c: 'int clock_nanosleep(clockid_t clock, int flags, const struct timespec *request, struct timespec *remain)'>
	^self error: 'not simulated'
!
TIMER_ABSTIME
	<cMacro: 'int TIMER_ABSTIME'>
	^1
!
dlopen: file mode: mode
	<c: 'void *dlopen(const char *file, int mode)'>
	^self error: 'not simulated'
!
dlsym: handle name: name
	<c: 'void *dlsym(void *handle, const char *name)'>
	^self error: 'not simulated'
!
RTLD_NOW
	<cMacro: 'int RTLD_NOW'>
	^2
!
RTLD_NOLOAD
	<cMacro: 'int RTLD_NOLOAD'>
	^4
! !


CLibrary subclass: #Shaderc
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

Shaderc comment: 'The shaderc C API (libshaderc_shared): GLSL to SPIR-V for LinuxPlatformHost. Not simulated.'!

!Shaderc class methodsFor: 'declaring'!
headers
	^#('<shaderc/shaderc.h>')
!
typedefs
	^#((shaderc_compiler_t 'void *') (shaderc_compile_options_t 'void *') (shaderc_compilation_result_t 'void *')
		(shaderc_shader_kind int32_t) (shaderc_compilation_status int32_t) (shaderc_optimization_level int32_t))
!
targetOS
	^#linux
! !

!Shaderc methodsFor: 'simulation'!
notSimulated
	^self error: 'shaderc is not simulated'
! !

!Shaderc methodsFor: 'compiling'!
compilerInitialize
	<c: 'shaderc_compiler_t shaderc_compiler_initialize(void)'>
	^self notSimulated
!
optionsInitialize
	<c: 'shaderc_compile_options_t shaderc_compile_options_initialize(void)'>
	^self notSimulated
!
options: options optimization: level
	<c: 'void shaderc_compile_options_set_optimization_level(shaderc_compile_options_t options, shaderc_optimization_level level)'>
	^self notSimulated
!
options: options define: name length: nameLength value: value length: valueLength
	<c: 'void shaderc_compile_options_add_macro_definition(shaderc_compile_options_t options, const char *name, size_t name_length, const char *value, size_t value_length)'>
	^self notSimulated
!
compile: compiler source: source size: size kind: kind file: fileName entry: entryName options: options
	<c: 'shaderc_compilation_result_t shaderc_compile_into_spv(shaderc_compiler_t compiler, const char *source, size_t size, shaderc_shader_kind kind, const char *file_name, const char *entry_name, shaderc_compile_options_t options)'>
	^self notSimulated
!
resultStatus: result
	<c: 'shaderc_compilation_status shaderc_result_get_compilation_status(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultLength: result
	<c: 'size_t shaderc_result_get_length(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultBytes: result
	<c: 'const char *shaderc_result_get_bytes(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultErrorMessage: result
	<c: 'const char *shaderc_result_get_error_message(shaderc_compilation_result_t result)'>
	^self notSimulated
!
resultRelease: result
	<c: 'void shaderc_result_release(shaderc_compilation_result_t result)'>
	^self notSimulated
!
shaderc_vertex_shader
	<cMacro: 'shaderc_shader_kind shaderc_vertex_shader'>
	^0
!
shaderc_fragment_shader
	<cMacro: 'shaderc_shader_kind shaderc_fragment_shader'>
	^1
!
shaderc_compilation_status_success
	<cMacro: 'shaderc_compilation_status shaderc_compilation_status_success'>
	^0
!
shaderc_optimization_level_performance
	<cMacro: 'shaderc_optimization_level shaderc_optimization_level_performance'>
	^2
! !

!DarwinPlatformHost class methodsFor: 'translation'!
cPreamble
	"CVDisplayLink is deprecated (CADisplayLink needs a view). Preserve event-local modifiers on shortcuts synthesized by clipboard managers."
	^'#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#ifdef __APPLE__
#include <SDL3/SDL.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>
#include <CoreGraphics/CoreGraphics.h>
static IMP samaltak_application_send_event;
static double samaltak_wheel_scale;
static id samaltak_ns_window(SDL_Window *sw);
static id samaltak_resizing;
static SDL_Window *samaltak_resizing_sdl;
static unsigned samaltak_resize_edges;
static CGRect samaltak_resize_frame;
static CGSize samaltak_resize_decoration;
static CGPoint samaltak_resize_mouse;
static CGSize samaltak_resize_requested;
static CGSize samaltak_resize_sent;
static bool samaltak_resize_released;
static Uint64 samaltak_resize_released_at;
static CGRect samaltak_frame_of(id object)
{
#if defined(__x86_64__)
    CGRect r;
    ((void (*)(CGRect *, id, SEL))objc_msgSend_stret)(&r, object, sel_registerName("frame"));
    return r;
#else
    return ((CGRect (*)(id, SEL))objc_msgSend)(object, sel_registerName("frame"));
#endif
}
static CGPoint samaltak_mouse_location(void)
{
    return ((CGPoint (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSEvent"), sel_registerName("mouseLocation"));
}
static unsigned samaltak_resize_edges_at(id window, CGPoint m)
{
    /* the edges (1 left, 2 right, 4 bottom, 8 top; y up) a press at m (screen) resizes: exactly where AppKit would start its live resize (its frame view''s resize region), those within its corner thickness of m; none where AppKit does not tell */
    unsigned long style = ((unsigned long (*)(id, SEL))objc_msgSend)(window, sel_registerName("styleMask"));
    id frameView = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView")), sel_registerName("superview"));
    SEL inRegion = sel_registerName("_isInResizeRegion:"), cornerSel = sel_registerName("_windowResizeCornerThickness");
    CGRect f = samaltak_frame_of(window);
    CGPoint p = CGPointMake(m.x - f.origin.x, m.y - f.origin.y);
    double corner, dl, dr, db, dt;
    unsigned edges = 0;
    /* titled and resizable, not full screen */
    if (!!(style & 1UL) || !!(style & (1UL << 3)) || (style & (1UL << 14)) || !!frameView) return 0;
    if (!!((BOOL (*)(id, SEL, SEL))objc_msgSend)(frameView, sel_registerName("respondsToSelector:"), inRegion)
        || !!((BOOL (*)(id, SEL, SEL))objc_msgSend)(frameView, sel_registerName("respondsToSelector:"), cornerSel)) return 0;
    if (!!((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(frameView, inRegion,
        ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(frameView, sel_registerName("convertPoint:fromView:"), p, nil))) return 0;
    corner = ((double (*)(id, SEL))objc_msgSend)(frameView, cornerSel);
    dl = p.x; dr = f.size.width - p.x; db = p.y; dt = f.size.height - p.y;
    if (fmin(dl, dr) < corner) edges |= dl <= dr ? 1 : 2;
    if (fmin(db, dt) < corner) edges |= db <= dt ? 4 : 8;
    if (!!edges) edges = fmin(dl, dr) <= fmin(db, dt) ? (dl <= dr ? 1 : 2) : (db <= dt ? 4 : 8);
    return edges;
}
static void samaltak_resize_cursor(unsigned edges)
{
    const char *name = (edges & 3) && (edges & 12)
        ? (((edges & 1) !!= 0) == ((edges & 8) !!= 0) ? "_windowResizeNorthWestSouthEastCursor" : "_windowResizeNorthEastSouthWestCursor")
        : (edges & 3) ? "_windowResizeEastWestCursor" : "_windowResizeNorthSouthCursor";
    id cls = (id)objc_getClass("NSCursor");
    SEL sel = sel_registerName(name);
    if (!!((BOOL (*)(id, SEL, SEL))objc_msgSend)(cls, sel_registerName("respondsToSelector:"), sel))
        sel = sel_registerName((edges & 3) ? "resizeLeftRightCursor" : "resizeUpDownCursor");
    ((void (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(cls, sel), sel_registerName("set"));
}
/* Resizing a window by its edges. AppKit''s live resize is a modal loop inside SDL_PumpEvents, in which the image cannot draw, so the VM tracks the drag itself. The size has one owner, the image''s frames: the drag only requests a size (clamped to the window''s content minimum and maximum), which the image learns as a window resize; the window takes a size when the image presents a frame of it, and the frame is presented once the window server has that size (samaltak_presenting). Until the new drawable arrives, the old one shows against the edges that stay, never scaled (samaltak_resize_pin), and where it does not reach, the window''s background (samaltak_background). SDL''s own resize events of the window are dropped meanwhile: the image already has the size. */
static CGSize samaltak_content_size(id window)
{
    return samaltak_frame_of(((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView"))).size;
}
static SDL_Window *samaltak_sdl_window(id window)
{
    int i, n = 0;
    SDL_Window **all = SDL_GetWindows(&n), *found = NULL;
    for (i = 0; all && i < n; i++) if (samaltak_ns_window(all[i]) == window) found = all[i];
    SDL_free(all);
    return found;
}
static void samaltak_resize_pin(id window, unsigned e)
{
    /* a drawable of another size than the window (the old one, until the new frame arrives) shows at its size against the edges that stay, never scaled */
    id views = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView")), sel_registerName("subviews"));
    id gravity = ((id (*)(id, SEL, const char *))objc_msgSend)((id)objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
        e & 8 ? (e & 1 ? "bottomRight" : "bottomLeft") : (e & 1 ? "topRight" : "topLeft"));
    unsigned long i, n = ((unsigned long (*)(id, SEL))objc_msgSend)(views, sel_registerName("count"));
    for (i = 0; i < n; i++) {
        id layer = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL, unsigned long))objc_msgSend)(views, sel_registerName("objectAtIndex:"), i), sel_registerName("layer"));
        if (layer) ((void (*)(id, SEL, id))objc_msgSend)(layer, sel_registerName("setContentsGravity:"), gravity);
    }
}
static void samaltak_resize_request(CGPoint m)
{
    /* the content size the pointer asks for, in whole points */
    id window = samaltak_resizing;
    CGSize min = ((CGSize (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentMinSize"));
    CGSize max = ((CGSize (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentMaxSize"));
    CGRect start = samaltak_resize_frame;
    double dx = m.x - samaltak_resize_mouse.x, dy = m.y - samaltak_resize_mouse.y;
    double w = start.size.width - samaltak_resize_decoration.width;
    double h = start.size.height - samaltak_resize_decoration.height;
    unsigned e = samaltak_resize_edges;
    if (e & 1) w -= dx;
    if (e & 2) w += dx;
    if (e & 4) h -= dy;
    if (e & 8) h += dy;
    w = fmin(fmax(round(w), fmax(min.width, 1)), max.width);
    h = fmin(fmax(round(h), fmax(min.height, 1)), max.height);
    samaltak_resize_requested = CGSizeMake(w, h);
}
static void samaltak_resize_apply(CGSize content)
{
    /* the frame of that content size whose fixed edges are where they were at the press */
    CGRect start = samaltak_resize_frame, f;
    unsigned e = samaltak_resize_edges;
    f.size.width = content.width + samaltak_resize_decoration.width;
    f.size.height = content.height + samaltak_resize_decoration.height;
    f.origin.x = e & 1 ? start.origin.x + start.size.width - f.size.width : start.origin.x;
    f.origin.y = e & 8 ? start.origin.y : start.origin.y + start.size.height - f.size.height;
    ((void (*)(id, SEL, CGRect, BOOL))objc_msgSend)(samaltak_resizing, sel_registerName("setFrame:display:"), f, YES);
}
static void samaltak_resize_end(void)
{
    samaltak_resizing = nil;
    samaltak_resizing_sdl = NULL;
}
static bool samaltak_resize_event(id event, unsigned long type)
{
    if (type == 1) { /* NSEventTypeLeftMouseDown */
        id window = ((id (*)(id, SEL))objc_msgSend)(event, sel_registerName("window"));
        CGPoint m = samaltak_mouse_location();
        unsigned edges = window ? samaltak_resize_edges_at(window, m) : 0;
        SDL_Window *sw = edges ? samaltak_sdl_window(window) : NULL;
        CGSize content;
        if (!!sw) return false;
        if (samaltak_resizing) samaltak_resize_apply(samaltak_resize_sent);
        samaltak_resizing = window;
        samaltak_resizing_sdl = sw;
        samaltak_resize_edges = edges;
        samaltak_resize_frame = samaltak_frame_of(window);
        content = samaltak_content_size(window);
        samaltak_resize_decoration = CGSizeMake(samaltak_resize_frame.size.width - content.width, samaltak_resize_frame.size.height - content.height);
        samaltak_resize_mouse = m;
        samaltak_resize_requested = samaltak_resize_sent = content;
        samaltak_resize_released = false;
        samaltak_resize_pin(window, edges);
        samaltak_resize_cursor(edges);
        return true;
    }
    if (!!samaltak_resizing || samaltak_resize_released) return false;
    if (type == 6 || type == 2) { /* NSEventTypeLeftMouseDragged, NSEventTypeLeftMouseUp */
        samaltak_resize_request(samaltak_mouse_location());
        samaltak_resize_cursor(samaltak_resize_edges);
        if (type == 2) {
            samaltak_resize_released = true;
            samaltak_resize_released_at = SDL_GetTicks();
            ((void (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSCursor"), sel_registerName("arrowCursor")), sel_registerName("set"));
        }
        return true;
    }
    return false;
}
static void samaltak_resize_hover(id event)
{
    /* the resize cursor where a press would resize (AppKit''s, at the edges, is covered by SDL''s, which spans the window); SDL''s again elsewhere */
    static bool shown;
    id window = ((id (*)(id, SEL))objc_msgSend)(event, sel_registerName("window"));
    unsigned edges = window && !!samaltak_resizing ? samaltak_resize_edges_at(window, samaltak_mouse_location()) : 0;
    if (edges) samaltak_resize_cursor(edges);
    else if (shown) SDL_SetCursor(NULL);
    shown = edges !!= 0;
}
static void samaltak_send_event(id receiver, SEL selector, id event)
{
    unsigned long type = ((unsigned long (*)(id, SEL))objc_msgSend)(event, sel_registerName("type"));
    if (samaltak_resize_event(event, type)) return;
    if (type == 22) /* NSEventTypeScrollWheel: SDL''s Cocoa driver divides a precise device''s points by 10 */
        samaltak_wheel_scale = ((BOOL (*)(id, SEL))objc_msgSend)(event, sel_registerName("hasPreciseScrollingDeltas")) ? 10.0 : 0.0;
    if (type == 10 || type == 11) { /* NSEventTypeKeyDown / KeyUp */
        unsigned long flags = ((unsigned long (*)(id, SEL))objc_msgSend)(event, sel_registerName("modifierFlags"));
        SDL_Keymod saved = SDL_GetModState();
        SDL_Keymod mods = saved & ~(SDL_KMOD_SHIFT | SDL_KMOD_CTRL | SDL_KMOD_ALT | SDL_KMOD_GUI | SDL_KMOD_CAPS);
        if (flags & (1UL << 16)) mods |= SDL_KMOD_CAPS;
        if (flags & (1UL << 17)) mods |= (saved & SDL_KMOD_SHIFT) ? (saved & SDL_KMOD_SHIFT) : SDL_KMOD_LSHIFT;
        if (flags & (1UL << 18)) mods |= (saved & SDL_KMOD_CTRL) ? (saved & SDL_KMOD_CTRL) : SDL_KMOD_LCTRL;
        if (flags & (1UL << 19)) mods |= (saved & SDL_KMOD_ALT) ? (saved & SDL_KMOD_ALT) : SDL_KMOD_LALT;
        if (flags & (1UL << 20)) mods |= (saved & SDL_KMOD_GUI) ? (saved & SDL_KMOD_GUI) : SDL_KMOD_LGUI;
        SDL_SetModState(mods);
        ((void (*)(id, SEL, id))samaltak_application_send_event)(receiver, selector, event);
        SDL_SetModState(saved);
    } else {
        ((void (*)(id, SEL, id))samaltak_application_send_event)(receiver, selector, event);
    }
    if (type == 5 || type == 17) samaltak_resize_hover(event); /* NSEventTypeMouseMoved, NSEventTypeCursorUpdate (in which SDL sets its cursor) */
}
static double samaltak_wheel_point_scale(void)
{
    return samaltak_wheel_scale;
}
static void samaltak_install_paste(void)
{
    static bool installed = false;
    if (installed) return;
    Class application = objc_getClass("SDL3Application");
    Method method = application ? class_getInstanceMethod(application, sel_registerName("sendEvent:")) : NULL;
    if (!!method) return;
    samaltak_application_send_event = method_setImplementation(method, (IMP)samaltak_send_event);
    installed = true;
}
#include <CoreGraphics/CoreGraphics.h>
static id samaltak_ns_window(SDL_Window *sw)
{
    return (id)SDL_GetPointerProperty(SDL_GetWindowProperties(sw), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
}
static long samaltak_desktop_level(void)
{
    /* above Finder''s desktop (its icons take the clicks below them), below every window */
    return (long)CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) + 1;
}
static double samaltak_system_corner_radius(void)
{
    /* the corners of the system''s titled windows (NSWindow''s _cornerRadius: 16 points on macOS 26, 10 before) */
    static double radius = -1;
    if (radius < 0) {
        SEL sel = sel_registerName("_cornerRadius");
        id window = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSWindow"), sel_registerName("alloc"));
        window = ((id (*)(id, SEL, CGRect, unsigned long, unsigned long, BOOL))objc_msgSend)(window,
            sel_registerName("initWithContentRect:styleMask:backing:defer:"), CGRectMake(0, 0, 100, 100), 1, 2, YES);
        radius = window && ((BOOL (*)(id, SEL, SEL))objc_msgSend)(window, sel_registerName("respondsToSelector:"), sel)
            ? ((double (*)(id, SEL))objc_msgSend)(window, sel) : 10;
        if (window) ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("release"));
    }
    return radius;
}
static void samaltak_round_corners(id window)
{
    /* clip the content (SDL''s Metal layer is a sublayer) to the system''s corners; the window is clear outside them */
    id view = ((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView"));
    id layer;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(view, sel_registerName("setWantsLayer:"), YES);
    layer = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layer"));
    ((void (*)(id, SEL, double))objc_msgSend)(layer, sel_registerName("setCornerRadius:"), samaltak_system_corner_radius());
    ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, sel_registerName("setMasksToBounds:"), YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setOpaque:"), NO);
    ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setBackgroundColor:"),
        ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSColor"), sel_registerName("clearColor")));
}
static void samaltak_ignore_mouse(id self, SEL cmd, BOOL ignores)
{
    struct objc_super parent = { self, class_getSuperclass(object_getClass(self)) };
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&parent, cmd, YES);
}
static void samaltak_pass_through(id window)
{
    /* the pointer always passes through: SDL clears ignoresMouseEvents of a transparent window without a shape when the pointer moves in it */
    static Class passThrough;
    if (!!passThrough) {
        passThrough = objc_allocateClassPair(object_getClass(window), "SamaltakPassThroughWindow", 0);
        class_addMethod(passThrough, sel_registerName("setIgnoresMouseEvents:"), (IMP)samaltak_ignore_mouse, "v@:c");
        objc_registerClassPair(passThrough);
    }
    object_setClass(window, passThrough);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setIgnoresMouseEvents:"), YES);
}
static int samaltak_corner_radius(SDL_Window *sw)
{
    id window = samaltak_ns_window(sw);
    id view = window ? ((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView")) : nil;
    id layer = view ? ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layer")) : nil;
    return layer ? (int)((double (*)(id, SEL))objc_msgSend)(layer, sel_registerName("cornerRadius")) : 0;
}
static void samaltak_desktop_configure(SDL_Window *sw, bool passThrough)
{
    id window = samaltak_ns_window(sw);
    id app = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    SEL prevents = sel_registerName("_setPreventsActivation:");
    if (!!window) return;
    ((void (*)(id, SEL, long))objc_msgSend)(window, sel_registerName("setLevel:"), samaltak_desktop_level());
    /* on every Space, left in place by Mission Control, not cycled through */
    ((void (*)(id, SEL, unsigned long))objc_msgSend)(window, sel_registerName("setCollectionBehavior:"), (1UL << 0) | (1UL << 4) | (1UL << 6));
    ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setHasShadow:"), NO);
    if (passThrough) samaltak_pass_through(window);
    else samaltak_round_corners(window);
    /* a process with desktop windows has no Dock icon and is not in the app switcher (NSApplicationActivationPolicyAccessory) */
    ((BOOL (*)(id, SEL, long))objc_msgSend)(app, sel_registerName("setActivationPolicy:"), 1);
    /* a click does not activate the process (and take the focus from the active app) */
    if (((BOOL (*)(id, SEL, SEL))objc_msgSend)(window, sel_registerName("respondsToSelector:"), prevents))
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, prevents, YES);
}
static bool samaltak_is_desktop(SDL_Window *sw)
{
    id window = samaltak_ns_window(sw);
    return window && ((long (*)(id, SEL))objc_msgSend)(window, sel_registerName("level")) == samaltak_desktop_level();
}
static void samaltak_order_front(SDL_Window *sw)
{
    id window = samaltak_ns_window(sw);
    if (window) ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("orderFrontRegardless"));
}
static bool samaltak_background(SDL_Window *sw, unsigned rgb)
{
    /* what the window shows where its drawable does not reach: SDL''s Metal layer''s background and (not a desktop window, clear outside its rounded corners) the window''s */
    id window = samaltak_ns_window(sw);
    double r = ((rgb >> 16) & 255) / 255.0, g = ((rgb >> 8) & 255) / 255.0, b = (rgb & 255) / 255.0;
    id views;
    unsigned long i, n;
    CGColorRef color;
    if (!!window) return false;
    if (!!samaltak_is_desktop(sw))
        ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setBackgroundColor:"),
            ((id (*)(id, SEL, double, double, double, double))objc_msgSend)((id)objc_getClass("NSColor"), sel_registerName("colorWithSRGBRed:green:blue:alpha:"), r, g, b, 1.0));
    color = CGColorCreateSRGB(r, g, b, 1);
    views = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("contentView")), sel_registerName("subviews"));
    n = ((unsigned long (*)(id, SEL))objc_msgSend)(views, sel_registerName("count"));
    for (i = 0; i < n; i++) {
        id layer = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL, unsigned long))objc_msgSend)(views, sel_registerName("objectAtIndex:"), i), sel_registerName("layer"));
        if (layer) ((void (*)(id, SEL, CGColorRef))objc_msgSend)(layer, sel_registerName("setBackgroundColor:"), color);
    }
    CGColorRelease(color);
    return true;
}
static bool samaltak_resize_request_of(SDL_Window **sw, int *w, int *h)
{
    /* the size the drag requests of its window, once, if the image does not have it yet; after the release the drag ends when the image presented it, or after a second without the image applies it */
    CGSize c;
    if (!!samaltak_resizing) return false;
    c = samaltak_content_size(samaltak_resizing);
    if (!!CGSizeEqualToSize(samaltak_resize_requested, samaltak_resize_sent)) {
        samaltak_resize_sent = samaltak_resize_requested;
        *sw = samaltak_resizing_sdl;
        *w = (int)samaltak_resize_sent.width;
        *h = (int)samaltak_resize_sent.height;
        return true;
    }
    if (samaltak_resize_released && (CGSizeEqualToSize(c, samaltak_resize_sent) || SDL_GetTicks() - samaltak_resize_released_at > 1000)) {
        if (!!CGSizeEqualToSize(c, samaltak_resize_sent)) samaltak_resize_apply(samaltak_resize_sent);
        samaltak_resize_end();
    }
    return false;
}
static id samaltak_string(const char *s)
{
    return ((id (*)(id, SEL, const char *))objc_msgSend)((id)objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), s);
}
static CGSize samaltak_server_size(id window)
{
    /* the window''s size as the window server has it */
    long number = ((long (*)(id, SEL))objc_msgSend)(window, sel_registerName("windowNumber"));
    id list = (id)CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, (CGWindowID)number);
    CGSize size = CGSizeZero;
    if (list && ((unsigned long (*)(id, SEL))objc_msgSend)(list, sel_registerName("count")) > 0) {
        id info = ((id (*)(id, SEL, unsigned long))objc_msgSend)(list, sel_registerName("objectAtIndex:"), 0);
        id bounds = ((id (*)(id, SEL, id))objc_msgSend)(info, sel_registerName("objectForKey:"), samaltak_string("kCGWindowBounds"));
        size.width = ((double (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL, id))objc_msgSend)(bounds, sel_registerName("objectForKey:"), samaltak_string("Width")), sel_registerName("doubleValue"));
        size.height = ((double (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL, id))objc_msgSend)(bounds, sel_registerName("objectForKey:"), samaltak_string("Height")), sel_registerName("doubleValue"));
    }
    if (list) ((void (*)(id, SEL))objc_msgSend)(list, sel_registerName("release"));
    return size;
}
static void samaltak_await_server(id window)
{
    /* until the window server has the window''s new frame, which AppKit hands it in a pass of the run loop (about one refresh); at most 50 ms */
    CGSize f = samaltak_frame_of(window).size, s;
    Uint64 start = SDL_GetTicksNS();
    id loop = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSRunLoop"), sel_registerName("currentRunLoop"));
    id past = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSDate"), sel_registerName("distantPast"));
    for (;;) {
        s = samaltak_server_size(window);
        if ((fabs(s.width - f.width) < 0.5 && fabs(s.height - f.height) < 0.5) || SDL_GetTicksNS() - start > 50000000) return;
        ((BOOL (*)(id, SEL, id, id))objc_msgSend)(loop, sel_registerName("runMode:beforeDate:"), samaltak_string("kCFRunLoopDefaultMode"), past);
    }
}
static void samaltak_presenting(SDL_Window *sw, int w, int h)
{
    /* the image presents a frame of w × h points in the window being resized by its edges: the window takes that size, and the frame is presented once the window server has it, before its drawable is acquired (so that the drawable has the size) */
    CGSize size = CGSizeMake(w, h);
    if (!!samaltak_resizing || sw !!= samaltak_resizing_sdl) return;
    if (!!CGSizeEqualToSize(samaltak_content_size(samaltak_resizing), size)) {
        samaltak_resize_apply(size);
        samaltak_await_server(samaltak_resizing);
    }
    if (samaltak_resize_released && CGSizeEqualToSize(size, samaltak_resize_sent)) samaltak_resize_end();
}
static bool samaltak_sizes(SDL_Window *sw)
{
    return samaltak_resizing && sw == samaltak_resizing_sdl;
}
#endif'
! !


!DarwinPlatform methodsFor: 'paste'!
installPaste
	<c: 'void samaltak_install_paste(void)'>
	^self error: 'not simulated'
! !

!DarwinPlatform methodsFor: 'desktop windows'!
configureDesktop: sw passThrough: aBoolean
	"Make SDL window sw a desktop window: on every Space above Finder's desktop, below every window, without a shadow; the pointer passes through it if aBoolean, else its corners are rounded as the system's windows are."
	<c: 'void samaltak_desktop_configure(SDL_Window *sw, bool passThrough)'>
	^self error: 'not simulated'
!
isDesktop: sw
	<c: 'bool samaltak_is_desktop(SDL_Window *sw)'>
	^self error: 'not simulated'
!
orderFront: sw
	"Put sw above the other windows of its level, without activating the process."
	<c: 'void samaltak_order_front(SDL_Window *sw)'>
	^self error: 'not simulated'
!
cornerRadius: sw
	"The radius (points) sw's corners are rounded with, 0 if square."
	<c: 'int samaltak_corner_radius(SDL_Window *sw)'>
	^self error: 'not simulated'
! !

!DarwinPlatform methodsFor: 'wheel'!
wheelPointScale
	"10 if the last scroll came from a device that scrolls by points (SDL reports a tenth of them), else 0."
	<c: 'double samaltak_wheel_point_scale(void)'>
	^self error: 'not simulated'
! !

!DarwinPlatform methodsFor: 'resizing'!
presenting: sw width: w height: h
	"The image presents a frame of w × h points in sw: if sw is being resized by its edges, it takes that size."
	<c: 'void samaltak_presenting(SDL_Window *sw, int w, int h)'>
	^self error: 'not simulated'
!
resizeRequest: sw width: w height: h
	"The window being resized by its edges (into sw) and the size its drag requests (into w and h) if the image was not told yet; false if none."
	<c: 'bool samaltak_resize_request_of(SDL_Window **sw, int *w, int *h)'>
	^self error: 'not simulated'
!
ownsSizeOf: sw
	"Whether sw is being resized by its edges."
	<c: 'bool samaltak_sizes(SDL_Window *sw)'>
	^self error: 'not simulated'
!
background: sw rgb: rgb
	"Show rgb (16rRRGGBB) where sw's drawable does not reach."
	<c: 'bool samaltak_background(SDL_Window *sw, unsigned rgb)'>
	^self error: 'not simulated'
! !
