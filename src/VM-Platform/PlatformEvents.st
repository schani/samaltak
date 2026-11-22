VMPlatformModule subclass: #PlatformEvents
	instanceVariableNames: 'q qHead qLen qCap qDropped inputSem inputArmed lastPumpNs mouseX mouseY keyMods'
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformEvents comment: 'The event queue: one FIFO holds translated SDL events and injected ones, so remote input is indistinguishable from real input. The input semaphore is signaled once when events are pending and re-armed by every platform_events_next. The FIFO holds at most PF_EVENT_QUEUE_MAX events; further events are dropped and counted.'!

!PlatformEvents class methodsFor: 'declaring'!
declarations
	^#((q 'pf_event *') (qHead int32_t) (qLen int32_t) (qCap int32_t) (qDropped int64_t) (inputSem int32_t) (inputArmed bool true)
		(lastPumpNs uint64_t) (mouseX double) (mouseY double) (keyMods SDL_Keymod))
! !

!PlatformEvents methodsFor: 'accessing'!
lastPumpNs
	^lastPumpNs
!
pending
	^qLen ~= 0
! !

!PlatformEvents methodsFor: 'queue'!
push: e
	"Copies the text; drops the event if the queue is full."
	<export>
	<var: #text type: 'char *'>
	| cap n text d |
	qLen = qCap ifTrue: [
		cap := qCap ~= 0 ifTrue: [qCap * 2] ifFalse: [256].
		cap > PF_EVENT_QUEUE_MAX ifTrue: [
			qDropped := qDropped + 1.
			^self].
		n := self cCoerce: (libc malloc: (self sizeof: 'pf_event') * cap asUInt64) to: 'pf_event *'.
		n isNull ifTrue: [
			qDropped := qDropped + 1.
			^self].
		0 to: qLen - 1 do: [:i | (n + i) copyStructFrom: q + ((qHead + i) rem: qCap)].
		libc free: q.
		q := n.
		qCap := cap.
		qHead := 0].
	text := self null.
	e xkind = PF_X_TEXT ifTrue: [
		text := libc strdup: (e text notNull ifTrue: [e text] ifFalse: ['']).
		text isNull ifTrue: [
			qDropped := qDropped + 1.
			^self]].
	d := q + ((qHead + qLen) rem: qCap).
	qLen := qLen + 1.
	d copyStructFrom: e.
	d text: text
!
dropped
	"Events dropped since startup."
	<export>
	^qDropped
!
next: out
	"The caller frees out text."
	<export>
	inputArmed := true.
	[qLen ~= 0] whileTrue: [
		out copyStructFrom: q + qHead.
		qHead := (qHead + 1) rem: qCap.
		qLen := qLen - 1.
		(c4 platformSDL not or: [out window = 0 or: [windows isLive: out window]]) ifTrue: [^true].
		libc free: out text].
	^false
!
discardAll
	<function>
	| e |
	e := self local: 'pf_event'.
	[self next: e] whileTrue: [libc free: e text].
	libc free: q.
	q := self null.
	qHead := qCap := 0
!
setSemaphore: index
	"0 = none."
	<export>
	inputSem := index.
	inputArmed := true
!
signalReady
	"Signal the vsync semaphore if a refresh is due, and the input semaphore if events are pending."
	<function>
	c4 platformSDL ifFalse: [vsync poll].
	self inputReady ifTrue: [
		inputArmed := false.
		scheduler signalExternalSemaphore: inputSem]
!
inputReady
	<function>
	^qLen ~= 0 and: [inputSem ~= 0 and: [inputArmed]]
!
updatePollInterval
	"After video init or socket semaphore changes."
	<export>
	scheduler requestPeriodicPoll: ((windows videoInited or: [sockets anyArmed]) ifTrue: [PF_POLL_US] ifFalse: [0])
! !

!PlatformEvents methodsFor: 'SDL events'!
modsOf: m
	<function>
	^((((m bitAnd: sdl SDL_KMOD_SHIFT) ~= 0 ifTrue: [PF_MOD_SHIFT] ifFalse: [0])
		bitOr: ((m bitAnd: sdl SDL_KMOD_CTRL) ~= 0 ifTrue: [PF_MOD_CTRL] ifFalse: [0]))
		bitOr: ((m bitAnd: host altKeymod) ~= 0 ifTrue: [PF_MOD_ALT] ifFalse: [0]))
		bitOr: ((m bitAnd: host cmdKeymod) ~= 0 ifTrue: [PF_MOD_CMD] ifFalse: [0])
!
translate: e
	"Queue the pf_event of an SDL event (others, the wake event among them, are ignored)."
	<export>
	| ev now age t |
	ev := self local: 'pf_event'.
	now := sdl getTicksNS.
	age := now > e common timestamp ifTrue: [now - e common timestamp] ifFalse: [0].
	ev timeMs: common nowMs - (age quo: 1000000) asInt64.
	ev mods: (self modsOf: sdl getModState).
	ev x: mouseX.
	ev y: mouseY.
	t := e type.
	t = sdl SDL_EVENT_MOUSE_MOTION ifTrue: [
		ev type: PF_EV_MOUSE_MOVE.
		mouseX := e motion x.
		mouseY := e motion y.
		ev x: mouseX.
		ev y: mouseY.
		ev key: e motion state.
		ev window: (windows fromSDLId: e motion windowID).
		(c4 platformSDL and: [ev window = 0]) ifTrue: [^self].
		^self push: ev].
	(t = sdl SDL_EVENT_MOUSE_BUTTON_DOWN or: [t = sdl SDL_EVENT_MOUSE_BUTTON_UP]) ifTrue: [
		ev type: (t = sdl SDL_EVENT_MOUSE_BUTTON_DOWN ifTrue: [PF_EV_MOUSE_DOWN] ifFalse: [PF_EV_MOUSE_UP]).
		mouseX := e button x.
		mouseY := e button y.
		ev x: mouseX.
		ev y: mouseY.
		ev key: e button button.
		ev xkind: PF_X_INT.
		ev ival: e button clicks.
		ev window: (windows fromSDLId: e button windowID).
		(c4 platformSDL and: [ev window = 0]) ifTrue: [^self].
		^self push: ev].
	t = sdl SDL_EVENT_MOUSE_WHEEL ifTrue: [
		ev type: PF_EV_WHEEL.
		mouseX := e wheel mouse_x.
		mouseY := e wheel mouse_y.
		ev x: mouseX.
		ev y: mouseY.
		ev xkind: PF_X_POINT.
		ev dx: e wheel x.
		ev dy: e wheel y.
		ev window: (windows fromSDLId: e wheel windowID).
		(c4 platformSDL and: [ev window = 0]) ifTrue: [^self].
		^self push: ev].
	(t = sdl SDL_EVENT_KEY_DOWN or: [t = sdl SDL_EVENT_KEY_UP]) ifTrue: [
		ev type: (t = sdl SDL_EVENT_KEY_DOWN ifTrue: [PF_EV_KEY_DOWN] ifFalse: [PF_EV_KEY_UP]).
		ev key: e key key.
		ev mods: (self modsOf: e key mod).
		t = sdl SDL_EVENT_KEY_DOWN ifTrue: [keyMods := e key mod].
		ev xkind: PF_X_BOOL.
		ev ival: (e key isRepeat ifTrue: [1] ifFalse: [0]).
		ev window: (windows fromSDLId: e key windowID).
		(c4 platformSDL and: [ev window = 0]) ifTrue: [^self].
		^self push: ev].
	t = sdl SDL_EVENT_TEXT_INPUT ifTrue: [
		"A key pressed with cmd is a command, not text (as on macOS, where it produces none): on Linux cmd is alt, whose keys do type."
		(keyMods bitAnd: host cmdKeymod) ~= 0 ifTrue: [^self].
		ev type: PF_EV_TEXT_INPUT.
		ev xkind: PF_X_TEXT.
		"platform_events_push copies it"
		ev text: (self cCoerce: e text text to: 'char *').
		ev window: (windows fromSDLId: e text windowID).
		(c4 platformSDL and: [ev window = 0]) ifTrue: [^self].
		^self push: ev].
	t = sdl SDL_EVENT_TEXT_EDITING ifTrue: [
		"The input method's composition; x and y carry the cursor and the length of its selected part."
		ev type: PF_EV_TEXT_EDITING.
		ev xkind: PF_X_TEXT.
		ev text: (self cCoerce: e edit text to: 'char *').
		ev x: e edit start asFloat.
		ev y: e edit length asFloat.
		ev window: (windows fromSDLId: e edit windowID).
		(c4 platformSDL and: [ev window = 0]) ifTrue: [^self].
		^self push: ev].
	t = sdl SDL_EVENT_QUIT ifTrue: [
		ev type: PF_EV_QUIT.
		^self push: ev].
	(t = sdl SDL_EVENT_WINDOW_RESIZED or: [t = sdl SDL_EVENT_WINDOW_CLOSE_REQUESTED or: [t = sdl SDL_EVENT_WINDOW_FOCUS_GAINED
		or: [t = sdl SDL_EVENT_WINDOW_FOCUS_LOST or: [t = sdl SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED
		or: [t = sdl SDL_EVENT_WINDOW_MOUSE_LEAVE or: [t = sdl SDL_EVENT_WINDOW_EXPOSED]]]]]]) ifTrue: [
			ev window: (windows fromSDLId: e window windowID).
			"Closed before its events were pumped: as events of no window they would reach any World."
			ev window = 0 ifTrue: [^self].
			t = sdl SDL_EVENT_WINDOW_RESIZED
				ifTrue: [
					ev type: PF_EV_WINDOW_RESIZED.
					ev x: e window data1 asFloat.
					ev y: e window data2 asFloat]
				ifFalse: [
					t = sdl SDL_EVENT_WINDOW_CLOSE_REQUESTED ifTrue: [ev type: PF_EV_WINDOW_CLOSE_REQUEST].
					t = sdl SDL_EVENT_WINDOW_FOCUS_GAINED ifTrue: [ev type: PF_EV_FOCUS_GAINED].
					t = sdl SDL_EVENT_WINDOW_FOCUS_LOST ifTrue: [ev type: PF_EV_FOCUS_LOST].
					t = sdl SDL_EVENT_WINDOW_MOUSE_LEAVE ifTrue: [ev type: PF_EV_MOUSE_LEAVE].
					t = sdl SDL_EVENT_WINDOW_EXPOSED ifTrue: [ev type: PF_EV_WINDOW_EXPOSED].
					t = sdl SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED ifTrue: [
						ev type: PF_EV_DISPLAY_SCALE_CHANGED.
						ev x: (windows displayScale: ev window).
						ev y: 0.0]].
			^self push: ev]
!
pump
	"Translate the pending SDL events."
	<function>
	| e |
	windows videoInited ifFalse: [^self].
	e := self local: 'SDL_Event'.
	sdl pumpEvents.
	[(sdl peepEvents: e count: 1 action: sdl SDL_GETEVENT minType: sdl SDL_EVENT_FIRST maxType: sdl SDL_EVENT_LAST) > 0]
		whileTrue: [self translate: e].
	lastPumpNs := sdl getTicksNS
! !

VMStruct subclass: #PfEvent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfEvent comment: 'An event: type (PF_EV_*), platform time, x and y in points, buttonOrKey, modifiers, textOrDelta (xkind PF_X_*: ival, dx and dy, or text, malloc''d), window handle (0 = none).'!

!PfEvent class methodsFor: 'declaring'!
fields
	^#((type int32_t) (timeMs int64_t) (x double) (y double) (key int64_t) (mods int32_t) (xkind int32_t) (ival int64_t)
		(dx double) (dy double) (text 'char *') (window int32_t))
! !
