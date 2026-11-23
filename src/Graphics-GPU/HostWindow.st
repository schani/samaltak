Object subclass: #HostWindow
	instanceVariableNames: 'handle session width height title flags'
	classVariableNames: ''
	package: 'Graphics-GPU'!

HostWindow comment: 'I am a native window of the host (SDL3; on UEFI the screen, FirmwareDisplay). I am opened on first use in each session, with the size and title I keep, so I survive image restarts like the GPU objects do. Sizes are in points; pixelExtent and scale give the backing store.'!

!HostWindow methodsFor: 'private'!
setWidth: w height: h title: aString flags: anInteger
	width := w.
	height := h.
	title := aString.
	flags := anInteger
! !

!HostWindow methodsFor: 'accessing'!
handle
	(handle notNil and: [session == GPUDevice currentSession]) ifTrue: [^handle].
	handle := GPUPlatform openWindow: width height: height title: title flags: flags.
	session := GPUDevice currentSession.
	^handle
!
isOpen
	^handle notNil and: [session == GPUDevice currentSession]
!
extent
	"Answer my size in points."
	| size |
	size := GPUPlatform windowSize: self handle.
	width := size first.
	height := size last.
	^width @ height
!
pixelExtent
	| size |
	size := GPUPlatform windowPixelSize: self handle.
	^size first @ size last
!
scale
	^GPUPlatform windowDisplayScale: self handle
!
refreshRate
	"Answer the display refresh rate in Hz (0 if unknown)."
	^GPUPlatform windowRefreshRate: self handle
!
title
	^title
!
title: aString
	title := aString.
	self isOpen ifTrue: [GPUPlatform window: handle title: aString]
!
extent: aPoint
	"Resize me to aPoint points (rounded up); answer whether the host did. Opened later, I open at that size."
	width := aPoint x ceiling.
	height := aPoint y ceiling.
	^self isOpen and: [(GPUPlatform window: handle width: width height: height) ~~ false]
!
hidden: aBoolean
	"Open hidden (offscreen) or shown when my handle is created next (first use, new session)."
	flags := (flags bitAnd: -2) + (aBoolean ifTrue: [1] ifFalse: [0])
!
textInputArea: aRectangle cursor: x
	"Where text is being typed (points; x: the caret within aRectangle): the input method shows its candidates there."
	self isOpen ifTrue: [
		GPUPlatform window: handle textInputAreaX: aRectangle left rounded y: aRectangle top rounded
			width: aRectangle width ceiling height: aRectangle height ceiling cursor: x rounded]
! !

!HostWindow methodsFor: 'showing'!
show
	"Show me, raised to the front with the focus (as far as the window manager lets an application)."
	GPUPlatform showWindow: self handle
!
hide
	GPUPlatform hideWindow: self handle
!
close
	self isOpen ifTrue: [GPUPlatform closeWindow: handle].
	handle := nil
! !

!HostWindow class methodsFor: 'instance creation'!
width: w height: h title: aString
	"A resizable high-density window."
	^self width: w height: h title: aString flags: 6
!
width: w height: h title: aString flags: anInteger
	"flags: 1 hidden, 2 resizable, 4 highDensity."
	^self new setWidth: w height: h title: aString flags: anInteger
! !

!HostWindow methodsFor: 'events'!
windowId
	"The id platform events carry in slot 8 (nil if I am not open)."
	^self isOpen ifTrue: [handle] ifFalse: [nil]
! !

!HostWindow class methodsFor: 'events'!
nextEventInto: anArray
	"Fill anArray (8 slots: type timeMs x y buttonOrKey modifiers textOrDelta windowId) with the next event, or answer nil."
	^GPUPlatform nextEvent: anArray
!
injectEvent: anArray
	"Queue an event (same format; timeMs nil = now) as if it came from the host."
	^GPUPlatform injectEvent: anArray
!
inputSemaphoreIndex: anInteger
	"Signal the external semaphore anInteger when events are pending (0 = none); re-armed by nextEventInto:."
	^GPUPlatform inputSemaphore: anInteger
!
vsyncSemaphoreIndex: anInteger
	"Signal the external semaphore anInteger on every display refresh (0 = stop)."
	^GPUPlatform vsyncSemaphore: anInteger
! !

!HostWindow class methodsFor: 'cursor and clipboard'!
cursor: aSymbol
	"#arrow #ibeam #hand #ew #ns #nwse #nesw #move #wait #crosshair #notAllowed"
	| kind |
	kind := #(#arrow #ibeam #hand #ew #ns #nwse #nesw #move #wait #crosshair #notAllowed) indexOf: aSymbol.
	kind = 0 ifTrue: [^self error: 'Unknown cursor ', aSymbol printString].
	^GPUPlatform setCursor: kind - 1
!
clipboard
	^GPUPlatform clipboardGet
!
clipboard: aString
	^GPUPlatform clipboardSet: aString
!
clipboardData: mime
	^GPUPlatform clipboardData: mime
! !
