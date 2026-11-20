Object subclass: #Watchpoint
	instanceVariableNames: 'object fieldName fieldIndex hits enabled scope'
	classVariableNames: 'Watches ReadOnlyBefore Listeners Lock'
	package: 'System-Debugging'!

Watchpoint comment: 'I halt the process that stores into a field of a watched object ("halt on write"). Watching sets the object''s immutability bit, so the VM''s existing store check catches the write (ModificationForbidden): no cost for anything else. A store into my field signals WatchpointHit; proceeding then performs the store and the object stays watched. Stores into other fields of a watched object are performed silently. unwatch makes the object writable again (unless it was read-only before).

Processes store into a watched object while another adds or removes its watchpoints (a window''s Process handles events while the Debugger''s unwatches the window): Lock makes watching, unwatching, the decision about a refused store and the store itself exclude each other, and a store refused while the object was watched is performed even if the watchpoint has gone by then.

	w := Watchpoint on: aPoint instVarNamed: #x.
	w := Watchpoint on: anArray.	"any write"
	w unwatch

Like breakpoints, I act in user processes unless targeted (see Breakpoint): inAllProcesses also halts the window system''s processes (the input dispatcher moving a window), inProcess: only that one.

	(Watchpoint on: aWindow instVarNamed: #bounds) inAllProcesses'!

!Watchpoint methodsFor: 'accessing'!
object
	^object
!
fieldName
	"The watched instance variable, nil for any write."
	^fieldName
!
fieldIndex
	^fieldIndex
!
hits
	^hits
!
isEnabled
	^enabled
!
enable
	enabled := true.
	self class changed: self
!
disable
	enabled := false.
	self class changed: self
!
label
	^(fieldName isNil
		ifTrue: ['watchpoint on any write']
		ifFalse: ['watchpoint on #', fieldName]),
	(scope isNil ifTrue: [''] ifFalse: [scope == #all ifTrue: [' in all processes'] ifFalse: [' in ', scope name printString]])
!
description
	| text |
	text := [object printString] on: Error do: [:e | e return: 'an object'].
	text size > 40 ifTrue: [text := (text copyFrom: 1 to: 40), '...'].
	^self label, ' of ', text
!
isWatchpoint
	^true
!
scope
	"nil: user processes; #all: every process; a Process: only that one (see Breakpoint)."
	^scope
!
scope: aScope
	scope := aScope.
	self class changed: self
!
inAllProcesses
	self scope: #all
!
inProcess: aProcess
	self scope: aProcess
!
inUserProcesses
	self scope: nil
!
isTargeted
	^scope notNil
! !

!Watchpoint methodsFor: 'testing'!
matches: aModificationForbidden
	fieldIndex isNil ifTrue: [^true].
	^aModificationForbidden retrySelector == #instVarAt:put:
		and: [aModificationForbidden fieldIndex = fieldIndex]
! !

!Watchpoint methodsFor: 'removing'!
unwatch
	"Stop watching; the object becomes writable again unless it was read-only before or other watchpoints remain."
	| list |
	Lock critical: [
		list := Watches at: object ifAbsent: [^self].
		list remove: self ifAbsent: [^self].
		list isEmpty ifTrue: [
			Watches removeKey: object.
			(ReadOnlyBefore at: object ifAbsent: [false]) ifFalse: [object beWritableObject].
			ReadOnlyBefore removeKey: object ifAbsent: [nil]]].
	self class changed: self
!
remove
	self unwatch
! !

!Watchpoint methodsFor: 'private'!
setObject: anObject fieldName: aStringOrNil
	| index |
	object := anObject.
	hits := 0.
	enabled := true.
	aStringOrNil isNil ifTrue: [^self].
	index := anObject class allInstVarNames indexOf: aStringOrNil asString.
	index = 0 ifTrue: [^self error: anObject class name, ' has no instance variable ', aStringOrNil asString].
	fieldName := aStringOrNil asString.
	fieldIndex := index
!
install
	| list |
	Lock critical: [
		list := Watches at: object ifAbsent: [nil].
		list isNil ifTrue: [
			ReadOnlyBefore at: object put: object isReadOnlyObject.
			list := OrderedCollection new.
			Watches at: object put: list].
		list add: self.
		object beReadOnlyObject].
	self class changed: self
!
hit
	hits := hits + 1.
	self class changed: self
! !

!Watchpoint methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Watchpoint('; nextPutAll: self description; nextPut: $)
! !

!Watchpoint class methodsFor: 'class initialization'!
initialize
	Watches isNil ifTrue: [Watches := IdentityDictionary new].
	ReadOnlyBefore isNil ifTrue: [ReadOnlyBefore := IdentityDictionary new].
	Listeners isNil ifTrue: [Listeners := OrderedCollection new].
	Lock isNil ifTrue: [Lock := Mutex new].
	Exception signalHook: [:anException | Watchpoint diversionFor: anException]
! !

!Watchpoint class methodsFor: 'diverting stores'!
diversionFor: anException
	"Exception signal hook: a store into a watched object goes to its Watchpoints instead of the handlers (a watched field halts with a WatchpointHit, other fields are stored silently). So does a store whose object is not read-only any more: it was refused while the object was watched, and another process has removed the watchpoint since. Answer nil to let anException be handled as usual, else the block that handles it (its value is the stored value)."
	| target watchpoint |
	(anException isKindOf: ModificationForbidden) ifFalse: [^nil].
	target := anException object.
	^Lock critical: [
		(self isWatching: target)
			ifTrue: [
				watchpoint := self watchpointFor: anException.
				(watchpoint isNil and: [self wasReadOnlyBeforeWatching: target]) ifFalse: [
					[self handleModification: anException watchpoint: watchpoint]]]
			ifFalse: [
				(target isReadOnlyObject or: [anException retrySelector isNil]) ifFalse: [
					[self performStore: anException]]]]
! !

!Watchpoint class methodsFor: 'instance creation'!
on: anObject instVarNamed: aString
	"Halt whenever a process stores into instance variable aString of anObject."
	^self basicNew setObject: anObject fieldName: aString; install; yourself
!
on: anObject
	"Halt whenever a process stores into any field of anObject."
	^self basicNew setObject: anObject fieldName: nil; install; yourself
! !

!Watchpoint class methodsFor: 'registry'!
all
	| result |
	result := OrderedCollection new.
	Watches do: [:list | result addAll: list].
	^result asArray
!
forObject: anObject
	^(Watches at: anObject ifAbsent: [#()]) asArray
!
isWatching: anObject
	^Watches notNil and: [Watches includesKey: anObject]
!
removeAll
	self all do: [:each | each unwatch]
!
watchpointFor: aModificationForbidden
	"Answer the enabled watchpoint that matches the failed store, or nil."
	^(Watches at: aModificationForbidden object ifAbsent: [^nil])
		detect: [:each | each isEnabled and: [each matches: aModificationForbidden]]
		ifNone: [nil]
!
wasReadOnlyBeforeWatching: anObject
	^ReadOnlyBefore at: anObject ifAbsent: [false]
! !

!Watchpoint class methodsFor: 'change notification'!
addListener: aBlock
	"aBlock receives a Watchpoint whenever one is added, removed, hit, enabled or disabled."
	Listeners add: aBlock
!
removeListener: aBlock
	Listeners remove: aBlock ifAbsent: [nil]
!
changed: aWatchpoint
	Listeners copy do: [:each | each cull: aWatchpoint]
! !

!Watchpoint class methodsFor: 'private'!
handleModification: aModificationForbidden watchpoint: aWatchpointOrNil
	"A store into a watched object failed. Halt for a matching watchpoint, then perform the store and answer the stored value."
	(aWatchpointOrNil notNil and: [Breakpoint scope: aWatchpointOrNil scope accepts: Processor activeProcess]) ifTrue: [
		aWatchpointOrNil hit.
		WatchpointHit new
			watchpoint: aWatchpointOrNil;
			modification: aModificationForbidden;
			signal: aWatchpointOrNil label].
	^self performStore: aModificationForbidden
!
performStore: aModificationForbidden
	"Perform the refused store, the read-only bit lifted for it if the object has it (it is still watched), and answer the stored value. No watchpoint comes or goes meanwhile. An error of the store itself (an index out of bounds) is signaled once the object is as it was."
	| target error |
	target := aModificationForbidden object.
	error := Lock critical: [ | wasReadOnly |
		wasReadOnly := target isReadOnlyObject.
		target beWritableObject.
		[[aModificationForbidden fieldIndex isNil
			ifTrue: [target perform: aModificationForbidden retrySelector with: aModificationForbidden newValue]
			ifFalse: [target perform: aModificationForbidden retrySelector with: aModificationForbidden fieldIndex with: aModificationForbidden newValue].
		  nil] on: Error do: [:e | e return: e]]
			ensure: [wasReadOnly ifTrue: [target beReadOnlyObject]]].
	error isNil ifFalse: [^error signal].
	^aModificationForbidden newValue
! !
