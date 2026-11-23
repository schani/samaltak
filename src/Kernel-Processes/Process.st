Link subclass: #Process
	instanceVariableNames: 'suspendedContext priority myList name cpuTime window errorHandler terminated overflowContext overflowLimit'
	classVariableNames: 'Registry RegistryCursor RegistryLap RegistryMutex'
	package: 'Kernel-Processes'!

Process comment: 'I am a green thread: a chain of Contexts (suspendedContext, while I am not running) scheduled by the ProcessorScheduler at my priority (1..80). myList is the LinkedList I wait in: a run queue of the scheduler or a Semaphore; nil while I am running or suspended. cpuTime counts the microseconds of CPU time I used (maintained by the VM, which settles it in batches; cpuMicroseconds settles it first). The first six fields are fixed by the VM; window and errorHandler belong to the UI (a window''s process, a per-process unhandled error handler). overflowContext and overflowLimit: the headroom a resumed StackOverflow left (see stackOverflowIn:depth:).'!

!Process methodsFor: 'accessing'!
suspendedContext
	^suspendedContext
!
suspendedContext: aContext
	suspendedContext := aContext
!
priority
	^priority
!
priority: anInteger
	"Set my priority; a runnable process moves to the run queue of the new priority."
	| wasRunnable |
	(anInteger between: Processor lowestPriority and: Processor highestPriority)
		ifFalse: [^self error: 'Invalid priority: ', anInteger printString].
	wasRunnable := self isRunnable.
	wasRunnable ifTrue: [self primSuspend].
	priority := anInteger.
	wasRunnable ifTrue: [self primResume]
!
suspendingList
	"Answer the run queue or Semaphore I am waiting in, or nil."
	^myList
!
name
	^name ifNil: ['a Process']
!
name: aString
	name := aString
!
cpuTime
	"Answer the microseconds of CPU time I have used so far."
	^cpuTime ifNil: [0]
!
window
	^window
!
window: aWindow
	window := aWindow
!
errorHandler
	"Answer a one-argument block that handles my unhandled errors, or nil for the system default."
	^errorHandler
!
errorHandler: aBlock
	errorHandler := aBlock
!
stack
	"Answer my contexts, innermost first."
	| top |
	top := self isActiveProcess ifTrue: [thisContext sender] ifFalse: [suspendedContext].
	^top isNil ifTrue: [#()] ifFalse: [top stack]
! !

!Process methodsFor: 'changing process state'!
resume
	"Make me runnable again. Answer myself."
	self isTerminated ifTrue: [^self error: 'Cannot resume a terminated process'].
	^self primResume
!
suspend
	"Stop me until resume. Answer the list I was waiting in (or nil)."
	^self primSuspend
!
terminate
	"Stop me for good after running my pending unwind blocks (ensure:, ifCurtailed:). My contexts end dead, so whoever still holds one of them (an exception's signal context) keeps only that one alive, not my stack."
	| ctx next unwindBlock |
	self isActiveProcess ifTrue: [
		ctx := thisContext.
		[(ctx := ctx findNextUnwindContextUpTo: nil) isNil] whileFalse: [
			(ctx tempAt: 2) isNil ifTrue: [
				ctx tempAt: 2 put: true.
				unwindBlock := ctx tempAt: 1.
				thisContext terminateTo: ctx.
				unwindBlock value]].
		thisContext terminateTo: nil.
		terminated := true.
		self primSuspend.
		^self].
	self isTerminated ifTrue: [^self].
	myList isNil ifFalse: [self primSuspend].
	terminated := true.
	overflowContext := nil.
	ctx := suspendedContext.
	suspendedContext := nil.
	[ctx isNil] whileFalse: [
		(ctx isUnwindContext and: [(ctx tempAt: 2) isNil]) ifTrue: [
			ctx tempAt: 2 put: true.
			(ctx tempAt: 1) value].
		next := ctx sender.
		ctx terminate.
		ctx := next]
!
signalException: anException
	"Signal anException in me. If I am waiting on a Semaphore I wake up to handle it and, if it is resumed, wait again."
	| oldList |
	self isActiveProcess ifTrue: [^anException signal].
	self isTerminated ifTrue: [^self].
	oldList := myList isNil ifTrue: [nil] ifFalse: [self primSuspend].
	suspendedContext := Context
		sender: suspendedContext
		receiver: self
		method: (Process >> #pvtSignal:list:)
		arguments: (Array with: anException with: oldList).
	oldList isNil ifFalse: [self primResume]
! !

!Process methodsFor: 'testing'!
isActiveProcess
	^self == Processor activeProcess
!
isTerminated
	self isActiveProcess ifTrue: [^false].
	^terminated == true or: [suspendedContext isNil]
!
isSuspended
	"Answer whether I am neither running, nor runnable, nor waiting, nor terminated."
	^myList isNil and: [self isActiveProcess not and: [self isTerminated not]]
!
isWaiting
	"Answer whether I am blocked on a Semaphore."
	^myList notNil and: [myList class ~~ LinkedList]
!
isRunnable
	"Answer whether I am in a run queue, ready to run."
	^myList notNil and: [myList class == LinkedList]
!
isRunning
	^self isActiveProcess
! !

!Process methodsFor: 'printing'!
printOn: aStream
	| ctx |
	aStream nextPutAll: 'a Process'.
	name isNil ifFalse: [aStream space; print: name].
	aStream nextPutAll: ' (priority '; print: priority; nextPut: $).
	ctx := self isActiveProcess ifTrue: [nil] ifFalse: [suspendedContext].
	ctx isNil ifFalse: [aStream nextPutAll: ' in '; print: ctx]
!
longPrintOn: aStream
	self printOn: aStream.
	aStream nextPut: Character lf.
	self stack do: [:ctx | aStream tab; print: ctx; nextPut: Character lf]
! !

!Process methodsFor: 'private'!
primResume
	<primitive: 'processResume'>
	^self primitiveFailed
!
primSuspend
	<primitive: 'processSuspend'>
	^nil
!
pvtSignal: anException list: aList
	"I run on top of my interrupted stack (see signalException:). Signal, wait again if I was waiting, then continue where I was interrupted."
	| interrupted |
	anException signal.
	(aList notNil and: [aList class ~~ LinkedList]) ifTrue: [aList wait].
	interrupted := thisContext sender.
	interrupted stackp > 0 ifTrue: [^interrupted jump].
	self continueAt: interrupted
!
stackOverflowIn: aContext depth: anInteger
	"Sent by Context>>stackOverflow: (the VM checks every few thousand activations): my stack is anInteger activations deep, aContext on top. Signal StackOverflow, unless an earlier one was resumed and I am still within the headroom that gave: maxStackDepth more activations, until the stack unwinds below the frame 100 under where it was signaled."
	| mark |
	(overflowContext notNil and: [overflowContext isDead not and: [anInteger <= overflowLimit]]) ifTrue: [^self].
	mark := aContext.
	100 timesRepeat: [mark sender isNil ifFalse: [mark := mark sender]].
	overflowContext := mark.
	overflowLimit := anInteger + Process maxStackDepth.
	^StackOverflow new context: aContext depth: anInteger; signal
!
continueAt: aContext
	"Abandon my current stack and continue aContext exactly as it is. A return (or jump) would push a value onto aContext, so a process switch does it: a helper sets my suspendedContext once I am suspended and resumes me."
	[[self isSuspended or: [self isTerminated]] whileFalse: [Processor yield].
	 self isTerminated ifFalse: [
		suspendedContext := aContext.
		self primResume]]
			forkAt: priority.
	self primSuspend
!
initialize
	cpuTime := 0
! !

!Process class methodsFor: 'instance creation'!
forContext: aContext priority: anInteger
	"Answer a suspended Process that runs aContext when resumed."
	^self register: (self new
		suspendedContext: aContext;
		setPriority: anInteger;
		yourself)
! !

!Process class methodsFor: 'stack depth'!
maxStackDepth
	"Answer how many activations (frames) a process may have before it signals StackOverflow; 0: no limit. The VM counts them every maxStackDepth / 8 activations it turns into Contexts, so the signal comes somewhat later; it also comes once a stack takes a quarter of the heap limit."
	<primitive: 'stackLimit'>
	^0
!
maxStackDepth: anInteger
	"Set the limit for every process, until the VM quits (it starts with 1000000); 0 turns it off. Answer the previous limit. Below 1000 the window system's own processes would overflow."
	(anInteger = 0 or: [anInteger >= 1000]) ifFalse: [^self error: 'maxStackDepth must be 0 or at least 1000'].
	^self primStackLimit: anInteger
!
primStackLimit: anInteger
	<primitive: 'stackLimit'>
	^self primitiveFailed
! !

!Process class methodsFor: 'registry'!
initialize
	"Register the processes created before the registry existed (the bootstrap process). Every later process registers itself in forContext:priority:."
	Registry := WeakArray new: 64.
	RegistryCursor := 0.
	RegistryLap := 0.
	RegistryMutex := Semaphore forMutualExclusion.
	Process allInstances do: [:each | self register: each]
!
register: aProcess
	"Remember aProcess weakly (a process that nobody references is collected and its slot cleared); answer it. It takes the next free slot after the last one handed out. At the end of the registry: if this lap through it found fewer than half of its slots free, double it and go on in the new half, else start again at 1. A lap costs O(size) and either registers size / 2 processes or doubles the size, so registering is O(1) amortized."
	RegistryMutex critical: [
		[RegistryCursor := RegistryCursor + 1.
		 RegistryCursor > Registry size ifTrue: [
			RegistryLap < (Registry size // 2)
				ifTrue: [
					Registry := (WeakArray new: Registry size * 2)
						replaceFrom: 1 to: Registry size with: Registry startingAt: 1;
						yourself]
				ifFalse: [RegistryCursor := 1].
			RegistryLap := 0].
		 (Registry at: RegistryCursor) isNil] whileFalse.
		Registry at: RegistryCursor put: aProcess.
		RegistryLap := RegistryLap + 1].
	^aProcess
!
allLive
	"Every process that has not terminated, from the registry: no heap scan (Process allInstances walks the whole heap inside one primitive, which nothing can preempt). The scan also tells how full the registry is: larger than the initial one and less than a quarter full, it is compacted, so that its capacity follows a burst of processes down again."
	^RegistryMutex critical: [
		| registered |
		registered := Registry asArray reject: [:each | each isNil].
		(Registry size > 64 and: [registered size < (Registry size // 4)]) ifTrue: [self compact: registered].
		registered reject: [:each | each isTerminated]]
!
compact: registered
	"Replace the registry by the smallest one (a power of two, at least the initial 64) that registered, every Process in it, fills at most half of, with them in its first slots; the caller holds RegistryMutex. The cursor is on the last of them and the lap counts them, as if register: had just put them there: with half the slots or more free ahead, the lap wraps at the end. Less than a quarter full before and more than a quarter (or the initial size) after, the registry is compacted again only when as many processes are gone again; the scan that found it so has paid for the move."
	| capacity |
	capacity := 64.
	[capacity < (registered size * 2)] whileTrue: [capacity := capacity * 2].
	Registry := (WeakArray new: capacity)
		replaceFrom: 1 to: registered size with: registered startingAt: 1;
		yourself.
	RegistryCursor := registered size.
	RegistryLap := registered size
! !

!Process methodsFor: 'private'!
setPriority: anInteger
	priority := anInteger
! !
