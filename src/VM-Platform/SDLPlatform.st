PlatformInterface subclass: #SDLPlatform
	instanceVariableNames: 'common events windows gpu files sockets vsync sdl posixIO posixThreads initDone wakeEvent inWait wPipe wMu wCv wState wFds wNfds wStarted wStop'
	classVariableNames: 'POLL_FDS'
	package: 'VM-Platform'!

SDLPlatform comment: 'The platform of the GUI VM: SDL3 windows and input, sockets and pseudo-terminals polled while the VM runs and while it waits.

While Smalltalk runs, platform_interface_poll pumps SDL at most once per ms, polls the armed sockets and signals the semaphores. platform_interface_wait blocks in SDL_WaitEventTimeout; a watcher thread poll()s the armed sockets meanwhile and wakes SDL with the wake event, as wake does for any thread (the display link''s). Without video it poll()s the sockets and the wake pipe.'!

!SDLPlatform class methodsFor: 'declaring'!
declarations
	^#((common PlatformCommon) (events PlatformEvents) (windows PlatformWindows) (gpu PlatformGPU) (files PlatformFiles)
		(sockets PlatformSockets) (vsync PlatformVsync) (sdl SDL) (posixIO PosixIO) (posixThreads PosixThreads)
		(initDone bool) (wakeEvent atomic_int) (inWait atomic_bool) (wPipe 'int32_t[2]' #(-1 -1))
		(wMu 'pthread_mutex_t[1]') (wCv 'pthread_cond_t[1]') (wState int32_t) (wFds 'struct pollfd[POLL_FDS]') (wNfds int32_t)
		(wStarted bool) (wStop atomic_bool))
!
initialize
	"the wake pipe and up to 128 sockets"
	POLL_FDS := 129
! !

!SDLPlatform methodsFor: 'platform'!
init
	"Idempotent."
	<export>
	c4 platformSDL ifTrue: [
		(windows videoInit) ifFalse: [self fatal: 'C4 SDL display unavailable: %s' with: common lastErrorString].
		^self].
	c4 platformFiles ifTrue: [^self].
	initDone ifTrue: [^self].
	initDone := true.
	"broken sockets and FIFOs report EPIPE instead"
	posixIO signal: posixIO SIGPIPE handler: posixIO SIG_IGN.
	common nowMs.
	posixThreads mutexInit: wMu attributes: self null.
	posixThreads condInit: wCv attributes: self null.
	gpu init.
	(posixIO pipe: wPipe) = 0 ifTrue: [
		posixIO fcntl: (wPipe at: 0) command: posixIO F_SETFL value: posixIO O_NONBLOCK.
		posixIO fcntl: (wPipe at: 1) command: posixIO F_SETFL value: posixIO O_NONBLOCK]
!
poll
	<export>
	c4 platformSDL ifTrue: [
		(windows videoInited and: [sdl getTicksNS - events lastPumpNs >= 1000000]) ifTrue: [events pump].
		events signalReady.
		^self].
	c4 platformFiles ifTrue: [^self].
	"Pumping Cocoa costs tens of µs; at most once per ms is plenty for input."
	(windows videoInited and: [sdl getTicksNS - events lastPumpNs >= 1000000]) ifTrue: [events pump].
	sockets anyArmed ifTrue: [sockets poll: 0].
	events signalReady
!
wait: timeoutUs
	<export>
	| ms socks p n watching |
	c4 platformSDL ifTrue: [
		windows videoInited ifTrue: [
			events pump.
			(events inputReady not and: [timeoutUs ~= 0]) ifTrue: [
				"Bound idle latency without a pipe, watcher or SDL calls from the collector."
				ms := (timeoutUs < 0 or: [timeoutUs > 10000]) ifTrue: [10] ifFalse: [((timeoutUs + 999) quo: 1000) asInt32].
				sdl waitEvent: self null timeout: ms.
				events pump].
			events signalReady.
			^self].
		events signalReady].
	c4 platformFiles ifTrue: [
		timeoutUs < 0 ifTrue: [self fatal: 'deadlock: no runnable process and no pending timer'].
		posix usleep: (timeoutUs > 1000000 ifTrue: [1000000] ifFalse: [timeoutUs]) asUInt32.
		^self].
	self init.
	events pump.
	(windows videoInited and: [(self atomicLoad: #wakeEvent) = 0]) ifTrue: [
		self atomicStore: #wakeEvent value: (sdl registerEvents: 1) asInt32].
	self atomicStore: #inWait value: true.
	ms := (events pending or: [vsync pending])
		ifTrue: [0]
		ifFalse: [timeoutUs < 0 ifTrue: [-1] ifFalse: [((timeoutUs + 999) quo: 1000) asInt32]].
	socks := sockets anyArmed.
	windows videoInited
		ifTrue: [
			watching := socks and: [self watcherStart].
			ms ~= 0 ifTrue: [sdl waitEvent: self null timeout: ms].
			watching ifTrue: [self watcherStop].
			events pump]
		ifFalse: [
			p := self local: 'struct pollfd[POLL_FDS]'.
			p fd: (wPipe at: 0).
			p events: posixIO POLLIN.
			n := socks ifTrue: [1 + (sockets pollFds: p + 1 max: POLL_FDS - 1)] ifFalse: [1].
			ms ~= 0 ifTrue: [posixIO poll: p count: n asUInt32 timeout: ms]].
	self atomicStore: #inWait value: false.
	self drainPipe.
	socks ifTrue: [sockets poll: 0].
	events signalReady
!
shutdown
	<export>
	c4 platformSDL ifTrue: [
		windows shutdown.
		windows videoInited ifTrue: [sdl quit].
		events discardAll.
		^self].
	c4 platformFiles ifTrue: [^self].
	gpu shutdown.
	windows shutdown.
	windows videoInited ifTrue: [sdl quit]
! !

!SDLPlatform methodsFor: 'waking'!
wake
	"Any thread: end a platform_interface_wait in progress."
	<export>
	| t e |
	c4 platformFiles ifTrue: [^self].
	(self atomicLoad: #inWait) ifFalse: [^self].
	t := self atomicLoad: #wakeEvent.
	t ~= 0 ifTrue: [
		e := self local: 'SDL_Event'.
		e type: t asUInt32.
		sdl pushEvent: e].
	posixIO write: (wPipe at: 1) bytes: 'w' count: 1
!
drainPipe
	<function>
	| buf |
	buf := self local: 'char[64]'.
	[(posixIO read: (wPipe at: 0) into: buf count: 64) > 0] whileTrue
! !

!SDLPlatform methodsFor: 'watcher'!
watchMain: arg
	"The watcher thread: while the VM thread sleeps in SDL_WaitEventTimeout, poll() the armed sockets and wake SDL by pushing the wake event."
	<function>
	| r woken e |
	[posixThreads mutexLock: wMu.
	 [wState ~= 1] whileTrue: [posixThreads condWait: wCv mutex: wMu].
	 wState := 2.
	 posixThreads mutexUnlock: wMu.
	 "wStop is set before the stop byte is written, so a drained stop byte is always followed by seeing wStop"
	 woken := false.
	 [woken not and: [(self atomicLoad: #wStop) not]] whileTrue: [
		r := posixIO poll: wFds count: wNfds asUInt32 timeout: -1.
		1 to: wNfds - 1 do: [:i | (r > 0 and: [(wFds at: i) revents ~= 0]) ifTrue: [woken := true]].
		woken
			ifTrue: [
				e := self local: 'SDL_Event'.
				e type: (self atomicLoad: #wakeEvent) asUInt32.
				sdl pushEvent: e]
			ifFalse: [self drainPipe "a stop request or a stray wake byte"]].
	 posixThreads mutexLock: wMu.
	 wState := 0.
	 posixThreads condBroadcast: wCv.
	 posixThreads mutexUnlock: wMu] repeat
!
watcherStart
	"Hand the armed sockets to the watcher thread (started on first use)."
	<function>
	| t |
	wStarted ifFalse: [
		(wPipe at: 0) < 0 ifTrue: [^false].
		t := self local: 'pthread_t'.
		(posix pthreadCreate: t attributes: self null start: (self functionPointer: #watchMain:) argument: self null) ~= 0 ifTrue: [^false].
		wStarted := true].
	wFds fd: (wPipe at: 0).
	wFds events: posixIO POLLIN.
	wFds revents: 0.
	wNfds := 1 + (sockets pollFds: wFds + 1 max: POLL_FDS - 1).
	self atomicStore: #wStop value: false.
	posixThreads mutexLock: wMu.
	wState := 1.
	posixThreads condBroadcast: wCv.
	posixThreads mutexUnlock: wMu.
	^true
!
watcherStop
	<function>
	self atomicStore: #wStop value: true.
	posixIO write: (wPipe at: 1) bytes: 'x' count: 1.
	posixThreads mutexLock: wMu.
	[wState ~= 0] whileTrue: [posixThreads condWait: wCv mutex: wMu].
	posixThreads mutexUnlock: wMu
! !
