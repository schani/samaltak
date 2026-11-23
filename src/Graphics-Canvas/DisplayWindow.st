Object subclass: #DisplayWindow
	instanceVariableNames: 'window swapchain surface renderer'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayWindow comment: 'I am a host window that shows DisplayLists: each frame is rendered into my offscreen Surface (RGBA8, the window''s pixel size, readable) and blitted to the swapchain. Present at most 60 Hz (vm/platform/README.md).

	| w | w := DisplayWindow width: 900 height: 560 title: ''Samaltak''.
	w show: aDisplayList clear: Color white'!

!DisplayWindow methodsFor: 'initialization'!
setWindow: aHostWindow
	window := aHostWindow.
	renderer := Renderer default.
	swapchain := renderer device swapchainFor: aHostWindow
! !

!DisplayWindow methodsFor: 'accessing'!
hostWindow
	^window
!
extent
	"Size in points."
	^window extent
!
scale
	^window scale
!
surface
	"The offscreen surface of the last frame (its size follows the window)."
	| pixels |
	pixels := window pixelExtent.
	(surface isNil or: [surface pixelExtent ~= pixels]) ifTrue: [
		surface isNil ifFalse: [surface release].
		surface := Surface width: pixels x height: pixels y scale: window scale].
	^surface
!
refreshRate
	"The display's refresh rate in Hz (0 if unknown)."
	^window refreshRate
!
title: aString
	window title: aString
!
extent: aPoint
	"Resize the host window to aPoint points; answer whether it did."
	^window extent: aPoint
!
hidden: aBoolean
	"Hidden or shown when my host window opens next (after an image restart)."
	window hidden: aBoolean
!
textInputArea: aRectangle cursor: x
	window textInputArea: aRectangle cursor: x
! !

!DisplayWindow methodsFor: 'presenting'!
show: aDisplayList clear: aColorOrNil
	"Render aDisplayList and present it. Answer false if the window could not be drawn (hidden, minimized, too many frames in flight)."
	| cmd target swap |
	target := self surface.
	cmd := renderer device commandBuffer.
	renderer render: aDisplayList into: target texture clear: aColorOrNil commandBuffer: cmd.
	swap := cmd acquireSwapchainTexture: swapchain.
	swap isNil ifFalse: [cmd blit: target texture to: swap].
	cmd submit.
	^swap notNil
!
close
	surface isNil ifFalse: [surface release. surface := nil].
	window close
! !

!DisplayWindow class methodsFor: 'instance creation'!
width: w height: h title: aString
	^self new setWindow: (HostWindow width: w height: h title: aString)
!
width: w height: h title: aString hidden: aBoolean
	"A resizable high-density window; hidden ones render offscreen only (tests, readback)."
	^self new setWindow: (HostWindow width: w height: h title: aString flags: (aBoolean ifTrue: [7] ifFalse: [6]))
!
width: w height: h title: aString flags: anInteger
	"flags: 1 hidden, 2 resizable, 4 highDensity (HostWindow)."
	^self new setWindow: (HostWindow width: w height: h title: aString flags: anInteger)
!
on: aHostWindow
	^self new setWindow: aHostWindow
! !

!DisplayWindow methodsFor: 'events'!
windowId
	"The id platform events for me carry in slot 8."
	^window windowId
! !

!DisplayWindow class methodsFor: 'events'!
nextEventInto: anArray
	"Fill anArray (8 slots: type timeMs x y buttonOrKey modifiers textOrDelta windowId; see vm/platform/README.md) with the next platform event and answer it, or answer nil."
	^HostWindow nextEventInto: anArray
!
injectEvent: anArray
	^HostWindow injectEvent: anArray
!
inputSemaphoreIndex: anInteger
	"Signal external semaphore anInteger when events are pending (drain with nextEventInto: until nil, then wait)."
	^HostWindow inputSemaphoreIndex: anInteger
!
vsyncSemaphoreIndex: anInteger
	^HostWindow vsyncSemaphoreIndex: anInteger
!
cursor: aSymbol
	^HostWindow cursor: aSymbol
!
clipboard
	^HostWindow clipboard
!
clipboard: aString
	^HostWindow clipboard: aString
!
clipboardData: mime
	^HostWindow clipboardData: mime
! !
