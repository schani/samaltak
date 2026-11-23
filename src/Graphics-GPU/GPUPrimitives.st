Object subclass: #GPUPrimitives
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Graphics-GPU'!

GPUPrimitives comment: 'I am the VM''s GPU and window primitives (SDL3, SDL_GPU; docs/platform.md): GPUPlatform''s backend where the VM has them. Every method is a primitive; on failure I signal a GPUError carrying the platform''s last error message.'!

!GPUPrimitives class methodsFor: 'errors'!
lastError
	"Answer the platform''s message for the last failed primitive."
	<primitive: 'platformLastError'>
	^''
!
fail: operation
	^GPUError new operation: operation; platformLastError: self lastError; signal
! !

!GPUPrimitives class methodsFor: 'device'!
createDevice: debug
	<primitive: 'gpuCreateDevice'>
	^self fail: 'gpuCreateDevice'
!
shaderLanguage: device
	"'msl' or 'glsl': the source gpuCreateShader takes on device."
	<primitive: 'gpuShaderLanguage'>
	^self fail: 'gpuShaderLanguage'
!
claim: device window: window
	<primitive: 'gpuClaimWindow'>
	^self fail: 'gpuClaimWindow'
!
swapchainFormat: device window: window
	<primitive: 'gpuSwapchainFormat'>
	^self fail: 'gpuSwapchainFormat'
!
waitIdle: device
	<primitive: 'gpuWaitIdle'>
	^self fail: 'gpuWaitIdle'
!
release: aHandle
	<primitive: 'gpuRelease'>
	^self fail: 'gpuRelease'
! !

!GPUPrimitives class methodsFor: 'resources'!
createShader: device source: msl entry: entryName stage: stage samplers: samplers uniformBuffers: uniforms storageBuffers: storageBuffers storageTextures: storageTextures
	<primitive: 'gpuCreateShader'>
	^self fail: 'gpuCreateShader'
!
compileShader: glsl stage: stage
	"GLSL source -> the SPIR-V ByteArray it compiles to (stage 0 vertex, 1 fragment); fails where GLSL is not compiled (macOS)."
	<primitive: 'gpuCompileShader'>
	^self fail: 'gpuCompileShader'
!
createPipeline: device vertex: vs fragment: fs stride: stride attributes: attributes primitive: primitiveType blend: blend format: targetFormat
	<primitive: 'gpuCreatePipeline'>
	^self fail: 'gpuCreatePipeline'
!
createTexture: device width: w height: h format: format usage: usage
	<primitive: 'gpuCreateTexture'>
	^self fail: 'gpuCreateTexture'
!
createSampler: device linear: linear repeat: repeat
	<primitive: 'gpuCreateSampler'>
	^self fail: 'gpuCreateSampler'
!
createBuffer: device usage: usage size: size
	<primitive: 'gpuCreateBuffer'>
	^self fail: 'gpuCreateBuffer'
!
uploadBuffer: buffer bytes: bytes count: byteCount offset: dstOffset
	<primitive: 'gpuUploadBuffer'>
	^self fail: 'gpuUploadBuffer'
!
uploadTexture: texture bytes: bytes x: x y: y width: w height: h bytesPerRow: bytesPerRow
	<primitive: 'gpuUploadTexture'>
	^self fail: 'gpuUploadTexture'
!
download: texture x: x y: y width: w height: h into: bytes
	<primitive: 'gpuDownload'>
	^self fail: 'gpuDownload'
!
textureSize: texture
	<primitive: 'gpuTextureSize'>
	^self fail: 'gpuTextureSize'
! !

!GPUPrimitives class methodsFor: 'commands'!
acquireCommandBuffer: device
	<primitive: 'gpuAcquireCommandBuffer'>
	^self fail: 'gpuAcquireCommandBuffer'
!
acquireSwapchain: commandBuffer window: window
	"Answer {texture. width. height}, or nil when the window cannot be drawn now."
	<primitive: 'gpuAcquireSwapchain'>
	^self fail: 'gpuAcquireSwapchain'
!
beginPass: commandBuffer target: texture clear: rgbaOrNil
	<primitive: 'gpuBeginPass'>
	^self fail: 'gpuBeginPass'
!
setViewport: pass x: x y: y width: w height: h
	<primitive: 'gpuSetViewport'>
	^self fail: 'gpuSetViewport'
!
setScissor: pass x: x y: y width: w height: h
	<primitive: 'gpuSetScissor'>
	^self fail: 'gpuSetScissor'
!
bindPipeline: pass pipeline: pipeline
	<primitive: 'gpuBindPipeline'>
	^self fail: 'gpuBindPipeline'
!
bindVertexBuffer: pass slot: slot buffer: buffer offset: offset
	<primitive: 'gpuBindVertexBuffer'>
	^self fail: 'gpuBindVertexBuffer'
!
bindTexture: pass slot: slot texture: texture sampler: sampler
	<primitive: 'gpuBindTexture'>
	^self fail: 'gpuBindTexture'
!
pushUniforms: commandBufferOrPass stage: stage slot: slot bytes: bytes
	<primitive: 'gpuPushUniforms'>
	^self fail: 'gpuPushUniforms'
!
draw: pass count: vertexCount first: firstVertex
	<primitive: 'gpuDraw'>
	^self fail: 'gpuDraw'
!
endPass: pass
	<primitive: 'gpuEndPass'>
	^self fail: 'gpuEndPass'
!
blit: commandBuffer source: src rect: srcRect destination: dst rect: dstRect linear: linear
	<primitive: 'gpuBlit'>
	^self fail: 'gpuBlit'
!
submit: commandBuffer fence: wantFence
	<primitive: 'gpuSubmit'>
	^self fail: 'gpuSubmit'
!
waitFence: fence
	<primitive: 'gpuWaitFence'>
	^self fail: 'gpuWaitFence'
!
fenceDone: fence
	<primitive: 'gpuFenceDone'>
	^self fail: 'gpuFenceDone'
!
fenceElapsed: fence
	<primitive: 'gpuFenceElapsed'>
	^self fail: 'gpuFenceElapsed'
! !

!GPUPrimitives class methodsFor: 'windows'!
openWindow: w height: h title: title flags: flags
	<primitive: 'windowOpen'>
	^self fail: 'windowOpen'
!
closeWindow: window
	<primitive: 'windowClose'>
	^self fail: 'windowClose'
!
windowSize: window
	<primitive: 'windowSize'>
	^self fail: 'windowSize'
!
windowPixelSize: window
	<primitive: 'windowPixelSize'>
	^self fail: 'windowPixelSize'
!
windowDisplayScale: window
	<primitive: 'windowDisplayScale'>
	^self fail: 'windowDisplayScale'
!
windowRefreshRate: window
	<primitive: 'windowRefreshRate'>
	^self fail: 'windowRefreshRate'
!
window: window title: aString
	<primitive: 'windowSetTitle'>
	^self fail: 'windowSetTitle'
!
window: window width: w height: h
	"Resize window to w × h points; false where the VM cannot (it predates the primitive, or the platform refused)."
	<primitive: 'windowSetSize'>
	^false
!
window: window textInputAreaX: x y: y width: w height: h cursor: cursorX
	<primitive: 'windowSetTextInputArea'>
	^self fail: 'windowSetTextInputArea'
!
showWindow: window
	<primitive: 'windowShow'>
	^self fail: 'windowShow'
!
hideWindow: window
	<primitive: 'windowHide'>
	^self fail: 'windowHide'
!
nextEvent: anArray
	"Fill anArray (8 slots) with the next platform event and answer it, or answer nil."
	<primitive: 'nextEvent'>
	^self fail: 'nextEvent'
!
injectEvent: anArray
	<primitive: 'injectEvent'>
	^self fail: 'injectEvent'
!
inputSemaphore: externalIndex
	<primitive: 'inputSemaphore'>
	^self fail: 'inputSemaphore'
!
vsyncSemaphore: externalIndex
	<primitive: 'vsyncSemaphore'>
	^self fail: 'vsyncSemaphore'
!
setCursor: kind
	<primitive: 'setCursor'>
	^self fail: 'setCursor'
!
clipboardGet
	<primitive: 'clipboardGet'>
	^self fail: 'clipboardGet'
!
clipboardSet: aString
	<primitive: 'clipboardSet'>
	^self fail: 'clipboardSet'
! !

!GPUPrimitives class methodsFor: 'clipboard'!
clipboardData: mime
	<primitive: 'clipboardData'>
	^nil
! !

!GPUPrimitives class methodsFor: 'windows'!
windowClosed: window
	"The VM releases the window's swapchain itself."
! !
