Object subclass: #GPUPlatform
	instanceVariableNames: ''
	classVariableNames: 'Device Display'
	package: 'Graphics-GPU'!

GPUPlatform comment: 'I am the private gateway of Graphics-GPU to the platform''s GPU and windows (docs/platform.md): every method forwards to a backend, the VM''s primitives (GPUPrimitives: SDL3, SDL_GPU) where it has them, else, where the image drives the machine itself (UEFI), the firmware''s display (FirmwareDisplay: windows and events) and a SoftwareGPU on it. They are chosen on first use after the image starts (reset). Failures signal a GPUError carrying the platform''s explanation. Only the classes of Graphics-GPU use me.'!

!GPUPlatform class methodsFor: 'backends'!
display
	"The windows and events."
	Display isNil ifTrue: [self chooseBackends].
	^Display
!
device
	"The GPU."
	Device isNil ifTrue: [self chooseBackends].
	^Device
!
chooseBackends
	FirmwareDisplay current
		ifNil: [Display := Device := GPUPrimitives]
		ifNotNil: [:d |
			Display := d.
			Device := SoftwareGPU on: d]
!
display: aDisplay device: aDevice
	"Use other backends (tests); answer the ones in use, {display. device}."
	| old |
	old := {Display. Device}.
	Display := aDisplay.
	Device := aDevice.
	^old
!
reset
	"Choose again on next use (a new VM process)."
	Display := Device := nil
! !

!GPUPlatform class methodsFor: 'device'!
createDevice: debug
	^self device createDevice: debug
!
shaderLanguage: dev
	"'msl' or 'glsl': the source gpuCreateShader takes on device."
	^self device shaderLanguage: dev
!
claim: dev window: window
	^self device claim: dev window: window
!
swapchainFormat: dev window: window
	^self device swapchainFormat: dev window: window
!
waitIdle: dev
	^self device waitIdle: dev
!
release: aHandle
	^self device release: aHandle
! !

!GPUPlatform class methodsFor: 'resources'!
createShader: dev source: msl entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	^self device createShader: dev source: msl entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
!
compileShader: glsl stage: stage
	^self device compileShader: glsl stage: stage
!
createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
	^self device createPipeline: dev vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
!
createTexture: dev width: w height: h format: format usage: usage
	^self device createTexture: dev width: w height: h format: format usage: usage
!
createSampler: dev linear: linear repeat: repeat
	^self device createSampler: dev linear: linear repeat: repeat
!
createBuffer: dev usage: usage size: size
	^self device createBuffer: dev usage: usage size: size
!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	^self device uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	^self device uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
!
download: texture x: x y: y width: w height: h into: bytes
	^self device download: texture x: x y: y width: w height: h into: bytes
!
textureSize: texture
	^self device textureSize: texture
! !

!GPUPlatform class methodsFor: 'commands'!
acquireCommandBuffer: dev
	^self device acquireCommandBuffer: dev
!
acquireSwapchain: commandBuffer window: window
	"Answer {texture. width. height}, or nil when the window cannot be drawn now."
	^self device acquireSwapchain: commandBuffer window: window
!
beginPass: commandBuffer target: texture clear: rgbaOrNil
	^self device beginPass: commandBuffer target: texture clear: rgbaOrNil
!
setViewport: pass x: x y: y width: w height: h
	^self device setViewport: pass x: x y: y width: w height: h
!
setScissor: pass x: x y: y width: w height: h
	^self device setScissor: pass x: x y: y width: w height: h
!
bindPipeline: pass pipeline: pipeline
	^self device bindPipeline: pass pipeline: pipeline
!
bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
	^self device bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
!
bindTexture: pass slot: slot texture: texture sampler: sampler
	^self device bindTexture: pass slot: slot texture: texture sampler: sampler
!
pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
	^self device pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
!
draw: pass count: vertexCount first: firstVertex
	^self device draw: pass count: vertexCount first: firstVertex
!
endPass: pass
	^self device endPass: pass
!
blit: commandBuffer source: src rect: srcRect destination: dst rect: dstRect linear: linear
	^self device blit: commandBuffer source: src rect: srcRect destination: dst rect: dstRect linear: linear
!
submit: commandBuffer fence: wantFence
	^self device submit: commandBuffer fence: wantFence
!
waitFence: fence
	^self device waitFence: fence
!
fenceDone: fence
	^self device fenceDone: fence
!
fenceElapsed: fence
	^self device fenceElapsed: fence
! !

!GPUPlatform class methodsFor: 'windows'!
openWindow: w height: h title: title flags: flags
	^self display openWindow: w height: h title: title flags: flags
!
closeWindow: window
	self display closeWindow: window.
	self device windowClosed: window
!
windowSize: window
	^self display windowSize: window
!
windowPixelSize: window
	^self display windowPixelSize: window
!
windowDisplayScale: window
	^self display windowDisplayScale: window
!
windowRefreshRate: window
	^self display windowRefreshRate: window
!
window: window title: aString
	^self display window: window title: aString
!
window: window width: w height: h
	^self display window: window width: w height: h
!
window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
	^self display window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
!
showWindow: window
	^self display showWindow: window
!
hideWindow: window
	^self display hideWindow: window
!
nextEvent: anArray
	"Fill anArray (8 slots) with the next platform event and answer it, or answer nil."
	^self display nextEvent: anArray
!
injectEvent: anArray
	^self display injectEvent: anArray
!
inputSemaphore: externalIndex
	^self display inputSemaphore: externalIndex
!
vsyncSemaphore: externalIndex
	^self display vsyncSemaphore: externalIndex
!
setCursor: kind
	^self display setCursor: kind
!
clipboardGet
	^self display clipboardGet
!
clipboardSet: aString
	^self display clipboardSet: aString
! !

!GPUPlatform class methodsFor: 'clipboard'!
clipboardData: mime
	^self display clipboardData: mime
! !
