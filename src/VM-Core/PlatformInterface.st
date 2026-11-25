VMCoreModule subclass: #PlatformInterface
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

PlatformInterface comment: 'What the core needs from a platform layer: start up, poll at interrupt checks, wait while idle, shut down. HeadlessPlatform implements it in the core; VM-Platform''s SDL layer instead. The build links one (the C names are the same); a simulation connects one.'!

!PlatformInterface class methodsFor: 'declaring'!
isAbstractModule
	^self == PlatformInterface
!
isInterface
	^self == PlatformInterface
! !

!PlatformInterface methodsFor: 'platform'!
init
	"At startup unless --headless."
	self subclassResponsibility
!
poll
	"At interrupt checks."
	self subclassResponsibility
!
wait: timeoutUs
	"Idle wait; < 0 = forever."
	self subclassResponsibility
!
shutdown
	"At quit."
	self subclassResponsibility
!
ffiTarget: id
	"An approved fixed-ABI downcall target in this platform profile, or zero."
	<var: #id type: 'int32_t'>
	<returns: 'uint64_t'>
	self subclassResponsibility
!
ffiApprovedPlatform: approvedName signature: packedSignature into: targetOut
	<var: #approvedName type: 'const char *'>
	<var: #packedSignature type: 'uint32_t'>
	<var: #targetOut type: 'uint64_t *'>
	<returns: 'int32_t'>
	self subclassResponsibility
!
quitStatus: code
	"At quit, before shutdown: the status the VM exits with when the image quits with code."
	self subclassResponsibility
! !

PlatformInterface subclass: #HeadlessPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

HeadlessPlatform comment: 'The platform of a VM without windows: waiting sleeps; nothing to poll.'!

!HeadlessPlatform methodsFor: 'platform'!
init
	<export>
!
poll
	<export>
!
wait: timeoutUs
	<export>
	timeoutUs < 0 ifTrue: [self fatal: 'deadlock: no runnable process and no pending timer'].
	posix usleep: (timeoutUs > 1000000 ifTrue: [1000000] ifFalse: [timeoutUs]) asUInt32
!
shutdown
	<export>
!
ffiTarget: id
	<export>
	<var: #id type: 'int32_t'>
	<returns: 'uint64_t'>
	^0
!
ffiApprovedPlatform: approvedName signature: packedSignature into: targetOut
	<export>
	<var: #approvedName type: 'const char *'>
	<var: #packedSignature type: 'uint32_t'>
	<var: #targetOut type: 'uint64_t *'>
	<returns: 'int32_t'>
	^0
!
quitStatus: code
	<export>
	<var: #code type: 'int'>
	<returns: 'int'>
	^code
! !
