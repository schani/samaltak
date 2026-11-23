VMPlatformModule subclass: #UefiNoDisplay
	instanceVariableNames: 'nic'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiNoDisplay comment: 'Windows, events, the refresh clock and the GPU on UEFI: none in the VM (in place of PlatformWindows, PlatformEvents, PlatformVsync and PlatformGPU). The image drives the screen and the input devices itself and renders with its software GPU over the raster primitives (System-Devices, SoftwareGPU; docs/uefi.md). Every call fails with the error ''not on UEFI''; the event queue is always empty. updatePollInterval asks for periodic polls while events are watched (UefiMachine) or the image waits for frames (UefiSnp).'!

!UefiNoDisplay class methodsFor: 'declaring'!
declarations
	^#((nic PlatformNic))
!
targetOS
	^#uefi
!
replaces
	^{PlatformWindows. PlatformEvents. PlatformVsync. PlatformGPU}
!
isSimulated
	^false
! !

!UefiNoDisplay methodsFor: 'polling'!
updatePollInterval
	"After the watched events or the NIC's semaphore changed: polls every PF_POLL_US while either wants them."
	<function>
	scheduler requestPeriodicPoll: ((machine isWatching or: [nic wantsPolling]) ifTrue: [PF_POLL_US] ifFalse: [0])
! !

!UefiNoDisplay methodsFor: 'unsupported'!
isLive: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'bool'>
	^false
!
presentRGBA: win width: w height: h pixels: pixels
	<function>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #pixels type: 'uint8_t *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
dropped
	<function>
	<returns: 'int64_t'>
	^0
!
next: out
	<function>
	<var: #out type: 'pf_event *'>
	<returns: 'bool'>
	^false
!
push: e
	<function>
	<var: #e type: 'pf_event *'>
!
setSemaphore: index
	<function>
	<var: #index type: 'int32_t'>
!
acquireCommandBuffer: dev
	<function>
	<var: #dev type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
acquireSwapchain: cmd window: win width: w height: h
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
beginPass: cmd target: tex clear: clear
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<var: #clear type: 'float *'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^0
!
bindPipeline: pass pipeline: pipe
	<function>
	<var: #pass type: 'int32_t'>
	<var: #pipe type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
bindTexture: pass slot: slot texture: tex sampler: sampler
	<function>
	<var: #pass type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #tex type: 'int32_t'>
	<var: #sampler type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
bindVertexBuffer: pass slot: slot buffer: buf offset: offset
	<function>
	<var: #pass type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #buf type: 'int32_t'>
	<var: #offset type: 'uint32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
blit: cmd source: src rect: sr destination: dst rect: dr linear: linear
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #src type: 'int32_t'>
	<var: #sr type: 'int *'>
	<var: #dst type: 'int32_t'>
	<var: #dr type: 'int *'>
	<var: #linear type: 'bool'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
claimWindow: dev window: win
	<function>
	<var: #dev type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
compileShader: source stage: stage size: sizeOut
	<function>
	<var: #source type: 'char *'>
	<var: #stage type: 'int32_t'>
	<var: #sizeOut type: 'size_t *'>
	<returns: 'void *'>
	common setError: 'not on UEFI'.
	^self null
!
createBuffer: dev usage: usage size: size
	<function>
	<var: #dev type: 'int32_t'>
	<var: #usage type: 'int32_t'>
	<var: #size type: 'uint32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
createDevice: debug
	<function>
	<var: #debug type: 'bool'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
createPipeline: dev vertexShader: vs fragmentShader: fs stride: stride attributes: attrs count: nattrs primitive: prim blend: blend targetFormat: targetFormat
	<function>
	<var: #dev type: 'int32_t'>
	<var: #vs type: 'int32_t'>
	<var: #fs type: 'int32_t'>
	<var: #stride type: 'int32_t'>
	<var: #attrs type: 'pf_vattr *'>
	<var: #nattrs type: 'int32_t'>
	<var: #prim type: 'int32_t'>
	<var: #blend type: 'int32_t'>
	<var: #targetFormat type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
createSampler: dev linear: linear repeat: repeat
	<function>
	<var: #dev type: 'int32_t'>
	<var: #linear type: 'bool'>
	<var: #repeat type: 'bool'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
createShader: dev source: source entry: entry stage: stage samplers: samplers uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
	<function>
	<var: #dev type: 'int32_t'>
	<var: #source type: 'char *'>
	<var: #entry type: 'char *'>
	<var: #stage type: 'int32_t'>
	<var: #samplers type: 'int32_t'>
	<var: #uniformBuffers type: 'int32_t'>
	<var: #storageBuffers type: 'int32_t'>
	<var: #storageTextures type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
createShader: dev spirv: code size: n entry: entry stage: stage samplers: samplers uniformBuffers: uniformBuffers storageBuffers: storageBuffers storageTextures: storageTextures
	<function>
	<var: #dev type: 'int32_t'>
	<var: #code type: 'const uint8_t *'>
	<var: #n type: 'size_t'>
	<var: #entry type: 'char *'>
	<var: #stage type: 'int32_t'>
	<var: #samplers type: 'int32_t'>
	<var: #uniformBuffers type: 'int32_t'>
	<var: #storageBuffers type: 'int32_t'>
	<var: #storageTextures type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
createTexture: dev width: w height: h format: format usage: usage
	<function>
	<var: #dev type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #format type: 'int32_t'>
	<var: #usage type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
download: tex x: x y: y width: w height: h into: dst length: dstLen
	<function>
	<var: #tex type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #dst type: 'void *'>
	<var: #dstLen type: 'size_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
draw: pass vertices: vertexCount first: firstVertex
	<function>
	<var: #pass type: 'int32_t'>
	<var: #vertexCount type: 'int32_t'>
	<var: #firstVertex type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
endPass: pass
	<function>
	<var: #pass type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
fenceDone: fence
	<function>
	<var: #fence type: 'int32_t'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^-1
!
fenceElapsed: fence
	<function>
	<var: #fence type: 'int32_t'>
	<returns: 'int64_t'>
	common setError: 'not on UEFI'.
	^-2
!
pushUniforms: cmdOrPass stage: stage slot: slot data: data count: n
	<function>
	<var: #cmdOrPass type: 'int32_t'>
	<var: #stage type: 'int32_t'>
	<var: #slot type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
releaseHandle: h
	<function>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
setScissor: pass x: x y: y width: w height: h
	<function>
	<var: #pass type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
setViewport: pass x: x y: y width: w height: h
	<function>
	<var: #pass type: 'int32_t'>
	<var: #x type: 'float'>
	<var: #y type: 'float'>
	<var: #w type: 'float'>
	<var: #h type: 'float'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
shaderLanguage: dev
	<function>
	<var: #dev type: 'int32_t'>
	<returns: 'char *'>
	common setError: 'not on UEFI'.
	^self null
!
submit: cmd fence: wantFence ok: ok
	<function>
	<var: #cmd type: 'int32_t'>
	<var: #wantFence type: 'bool'>
	<var: #ok type: 'bool *'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	ok value: false.
	^0
!
swapchainFormat: dev window: win
	<function>
	<var: #dev type: 'int32_t'>
	<var: #win type: 'int32_t'>
	<returns: 'int'>
	common setError: 'not on UEFI'.
	^0
!
textureSize: tex width: w height: h format: format
	<function>
	<var: #tex type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<var: #format type: 'int *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
uploadBuffer: buf data: data count: n offset: dstOffset
	<function>
	<var: #buf type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #n type: 'uint32_t'>
	<var: #dstOffset type: 'uint32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
uploadTexture: tex data: data length: len x: x y: y width: w height: h bytesPerRow: bytesPerRow
	<function>
	<var: #tex type: 'int32_t'>
	<var: #data type: 'const void *'>
	<var: #len type: 'size_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #bytesPerRow type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
waitFence: fence
	<function>
	<var: #fence type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
waitIdle: dev
	<function>
	<var: #dev type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
semaphore: index
	<function>
	<var: #index type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
clipboardData: mime size: size
	<function>
	<var: #mime type: 'char *'>
	<var: #size type: 'size_t *'>
	<returns: 'void *'>
	common setError: 'not on UEFI'.
	^self null
!
clipboardGet
	<function>
	<returns: 'char *'>
	common setError: 'not on UEFI'.
	^self null
!
clipboardSet: s
	<function>
	<var: #s type: 'char *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
close: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
displayScale: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'double'>
	common setError: 'not on UEFI'.
	^-1.0
!
freeClipboardData: data
	<function>
	<var: #data type: 'void *'>
	libc free: data
!
open: w height: h title: title flags: flags
	<function>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #title type: 'char *'>
	<var: #flags type: 'int32_t'>
	<returns: 'int32_t'>
	common setError: 'not on UEFI'.
	^0
!
pixelSize: win width: w height: h
	<function>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
refreshRate: win
	<function>
	<var: #win type: 'int32_t'>
	<returns: 'double'>
	common setError: 'not on UEFI'.
	^-1.0
!
setCursor: kind
	<function>
	<var: #kind type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
setTextInputArea: win x: x y: y width: w height: h cursor: c
	<function>
	<var: #win type: 'int32_t'>
	<var: #x type: 'int32_t'>
	<var: #y type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<var: #c type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
setSize: win width: w height: h
	<function>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #h type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
setTitle: win title: title
	<function>
	<var: #win type: 'int32_t'>
	<var: #title type: 'char *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
show: win visible: visible
	<function>
	<var: #win type: 'int32_t'>
	<var: #visible type: 'bool'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
size: win width: w height: h
	<function>
	<var: #win type: 'int32_t'>
	<var: #w type: 'int *'>
	<var: #h type: 'int *'>
	<returns: 'bool'>
	common setError: 'not on UEFI'.
	^false
!
handleCount
	<function>
	<returns: 'int32_t'>
	^0
!
handleCounts: out
	"devices shaders pipelines textures samplers buffers fences: none"
	<function>
	<var: #out type: 'int64_t *'>
	0 to: 6 do: [:i | out at: i put: 0]
! !
