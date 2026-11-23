Object subclass: #FirmwareDisplay
	instanceVariableNames: 'firmware screen queue clock devices open clipboard'
	classVariableNames: 'Current'
	package: 'System-Devices'!

FirmwareDisplay comment: 'I am the windows and the input where the image drives the machine itself (UEFI): what the window and event primitives are elsewhere, with their protocol (GPUPlatform''s backend for them, docs/platform.md). One window, handle 1, the whole screen (FirmwareScreen) at one pixel a point; opening it a second time answers it again. Opening it starts the input devices: the firmware''s keyboard, and a virtio tablet or mouse (VirtioInput) if there is one, else the firmware''s pointer; they report into my InputQueue, the pointer also to the screen, which moves the arrow. The refresh is a RefreshClock; the clipboard a string. FirmwareDisplay current is nil on an operating system; a resumed image starts a new one (the old one''s devices are the previous VM''s).'!

!FirmwareDisplay methodsFor: 'initialization'!
setFirmware: aFirmware
	firmware := aFirmware.
	screen := FirmwareScreen firmware: aFirmware.
	queue := InputQueue new.
	clock := RefreshClock new.
	devices := #().
	open := false
! !

!FirmwareDisplay methodsFor: 'accessing'!
queue
	^queue
!
screen
	^screen
!
extent
	^screen extent
!
pointerPosition
	^queue position
! !

!FirmwareDisplay methodsFor: 'devices'!
startDevices
	| virtio keyboard pointer |
	keyboard := FirmwareKeyboard firmware: firmware queue: queue.
	virtio := VirtioInput firmware: firmware display: self.
	pointer := FirmwarePointer firmware: firmware display: self.
	devices := {keyboard. virtio} select: [:d | d start].
	(devices includes: virtio) ifFalse: [pointer start ifTrue: [devices := devices copyWith: pointer]]
!
pointerAt: aPoint buttons: mask wheel: dy
	"Where a pointing device puts the pointer: events, and the arrow."
	(queue pointerAt: aPoint buttons: mask wheel: dy) ifTrue: [screen moveCursorTo: queue position truncated]
!
stop
	"Stop the devices and the refresh."
	devices do: [:d | d stop].
	devices := #().
	clock stop
!
abandon
	"Stop the devices' Processes: the devices are the previous VM's."
	devices do: [:d | d abandon].
	devices := #().
	clock stop
! !

!FirmwareDisplay methodsFor: 'windows'!
check: window
	(open and: [window = 1]) ifFalse: [^self error: 'no such window'].
	^window
!
openWindow: w height: h title: aString flags: flags
	"The screen, in its mode of w x h if it has one."
	open ifTrue: [^1].
	(screen start: w @ h) ifFalse: [^self error: 'no graphics output with a framebuffer'].
	queue extent: screen extent.
	open := true.
	self startDevices.
	^1
!
closeWindow: window
	"The screen stays."
	self check: window
!
windowSize: window
	"Points: one a pixel."
	self check: window.
	^{screen extent x. screen extent y}
!
windowPixelSize: window
	^self windowSize: window
!
windowDisplayScale: window
	self check: window.
	^1.0
!
windowRefreshRate: window
	self check: window.
	^60.0
!
window: window title: aString
	self check: window
!
window: window width: w height: h
	"The screen keeps its size."
	self check: window.
	^false
!
window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
	self check: window
!
showWindow: window
	self check: window
!
hideWindow: window
	self check: window
!
windowClosed: window
!
presentWindow: window pixels: address width: w height: h
	"A frame of the window (BGRA8 rows at address) onto the screen."
	self check: window.
	screen present: address width: w height: h
!
setCursor: kind
	"The arrow whatever the kind."
	^self
!
clipboardGet
	^clipboard ifNil: ['']
!
clipboardSet: aString
	clipboard := aString
!
clipboardData: mime
	"No data but text."
	^nil
! !

!FirmwareDisplay methodsFor: 'events'!
nextEvent: anArray
	^queue next: anArray
!
injectEvent: anArray
	^queue inject: anArray
!
inputSemaphore: anInteger
	queue semaphoreIndex: anInteger
!
vsyncSemaphore: anInteger
	clock semaphoreIndex: anInteger
!
droppedEvents
	^queue dropped
! !

!FirmwareDisplay class methodsFor: 'accessing'!
current
	"The display, or nil on an operating system."
	Current isNil ifTrue: [Firmware current ifNotNil: [:f |
		Current := self new setFirmware: f.
		InputQueue current: Current queue]].
	^Current
! !

!FirmwareDisplay class methodsFor: 'system startup'!
initialize
	Smalltalk addToStartUpList: self
!
startUp: resuming
	resuming ifTrue: [
		Current isNil ifFalse: [Current abandon].
		Current := nil.
		InputQueue current: nil]
! !
