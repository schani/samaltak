!Process methodsFor: '*System-Profiling'!
cpuMicroseconds
	"Answer the microseconds of CPU time I have used so far, up to now (cpuTime lags: the VM settles it in batches, a fraction of a millisecond apart while Processes run)."
	<primitive: 'processCpuTime'>
	^self cpuTime
! !

!Process methodsFor: '*System-Profiling'!
profilerStackInto: anArray maxDepth: maxDepth
	"For the profiler (I must not be running). Write my innermost maxDepth frames bottom up into anArray as method, pc pairs (pc: the block's startpc, 0 for a method) after its first slot, which holds depth + (truncated << 16) of the stack written there last. Answer k + (depth << 8) + (truncated << 16) + (innermost frame just activated << 17, which only the primitive knows: the VM records whether it preempted me at an activation), where k counts the bottom frames equal to the previous content."
	<primitive: 'processStackInto'>
	| frames ctx closure n truncated prev k |
	frames := OrderedCollection new.
	ctx := suspendedContext.
	[ctx notNil and: [frames size < maxDepth]] whileTrue: [
		closure := ctx closureOrNil.
		frames addFirst: (Array with: ctx method with: (closure isNil ifTrue: [0] ifFalse: [closure startpc])).
		ctx := ctx sender].
	truncated := ctx isNil ifTrue: [0] ifFalse: [1].
	n := frames size.
	prev := anArray at: 1.
	k := 0.
	(prev notNil and: [((prev bitShift: -16) bitAnd: 1) = truncated]) ifTrue: [
		[k < ((prev bitAnd: 16rFFFF) min: n)
			and: [(anArray at: k * 2 + 2) == (frames at: k + 1) first and: [(anArray at: k * 2 + 3) = (frames at: k + 1) last]]]
				whileTrue: [k := k + 1]].
	k + 1 to: n do: [:j |
		anArray at: j * 2 put: (frames at: j) first.
		anArray at: j * 2 + 1 put: (frames at: j) last].
	anArray at: 1 put: n + (truncated bitShift: 16).
	^k + (n bitShift: 8) + (truncated bitShift: 16)
! !
