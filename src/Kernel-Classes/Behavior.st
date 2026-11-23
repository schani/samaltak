Object subclass: #Behavior
	instanceVariableNames: 'superclass methodDict format'
	classVariableNames: ''
	package: 'Kernel-Classes'!

Behavior comment: 'I am the minimal description of a class that the VM needs: a superclass, a MethodDictionary and an instance format. format is (instSpec << 16) | instSize, where instSpec is 0 (no fields), 1 (fixed pointers), 2 (indexable pointers), 3 (fixed + indexable pointers), 4 (weak), 7 (immediate), 9 (64-bit), 10 (32-bit) or 16 (8-bit indexable). My field order is fixed by the VM.'!

!Behavior methodsFor: 'accessing'!
superclass
	^superclass
!
methodDict
	^methodDict
!
format
	^format
!
instSize
	"Answer the number of named instance variables."
	^format bitAnd: VMConstants clsInstsizeMask
!
instSpec
	^format bitShift: VMConstants clsSpecShift negated
!
name
	^self subclassResponsibility
!
classPool
	^nil
!
sharedPools
	^nil
!
environment
	^Smalltalk
! !

!Behavior methodsFor: 'private'!
superclass: aClass
	superclass := aClass
!
methodDict: aMethodDictionary
	methodDict := aMethodDictionary
!
format: anInteger
	format := anInteger
!
superclass: aClass methodDictionary: aMethodDictionary format: anInteger
	superclass := aClass.
	methodDict := aMethodDictionary.
	format := anInteger
!
flushCache
	"Forget every cached method lookup in the VM."
	<primitive: 'flushMethodCache'>
!
flushCacheFor: aSelector
	"Forget the VM's cached lookups of aSelector."
	<primitive: 'flushCacheForSelector'>
	self flushCache
! !

!Behavior methodsFor: 'testing'!
isBehavior
	^true
!
isMeta
	^false
!
isVariable
	"Answer whether instances have indexable fields."
	| spec |
	spec := self instSpec.
	^spec >= VMConstants fVar and: [spec ~= VMConstants fImmediate]
!
isFixed
	^self isVariable not
!
isPointers
	"Answer whether instances hold object pointers (as opposed to raw bits)."
	^self instSpec <= VMConstants fWeak
!
isBits
	^self isPointers not and: [self instSpec ~= VMConstants fImmediate]
!
isBytes
	^self instSpec >= VMConstants fBytes
!
isWords
	^self instSpec = VMConstants fW32
!
isDoubleWords
	^self instSpec = VMConstants fW64
!
isWeak
	^self instSpec = VMConstants fWeak
!
isImmediateClass
	^self instSpec = VMConstants fImmediate
!
instancesAreImmutable
	^self isImmediateClass
! !

!Behavior methodsFor: 'instance creation'!
basicNew
	"Answer a new instance with all fields nil (or zero for bits)."
	<primitive: 'basicNew'>
	self isVariable ifTrue: [^self basicNew: 0].
	^self primitiveFailed
!
basicNew: size
	"Answer a new instance with size indexable fields."
	<primitive: 'basicNew:' error: ec>
	self isVariable ifFalse: [^self error: self name, ' cannot have indexable fields'].
	(size isInteger and: [size >= 0]) ifFalse: [^self error: 'bad size'].
	ec = VMConstants primErrNoMemory ifTrue: [^OutOfMemory signalForClass: self size: size].
	^self primitiveFailed
!
new
	^self basicNew initialize
!
new: size
	^(self basicNew: size) initialize
! !

!Behavior methodsFor: 'accessing method dictionary'!
compiledMethodAt: aSelector
	^methodDict at: aSelector
!
compiledMethodAt: aSelector ifAbsent: aBlock
	^methodDict at: aSelector ifAbsent: aBlock
!
>> aSelector
	"Answer my method for aSelector."
	^self compiledMethodAt: aSelector
!
includesSelector: aSelector
	^methodDict includesKey: aSelector
!
selectors
	"Answer the selectors I define (not inherited), sorted."
	^methodDict keys asSortedCollection asArray
!
selectorsDo: aBlock
	methodDict keysDo: aBlock
!
methodsDo: aBlock
	"Evaluate aBlock for each of my CompiledMethods."
	methodDict valuesDo: aBlock
!
methods
	^methodDict values
!
allSelectors
	"Answer every selector instances understand."
	| set |
	set := IdentitySet new.
	self withAllSuperclassesDo: [:c | c selectorsDo: [:s | set add: s]].
	^set
!
lookupSelector: aSelector
	"Answer the method instances of mine run for aSelector, or nil."
	| c m |
	c := self.
	[c == nil] whileFalse: [
		m := c methodDict at: aSelector ifAbsent: [nil].
		m == nil ifFalse: [^m].
		c := c superclass].
	^nil
!
canUnderstand: aSelector
	^(self lookupSelector: aSelector) notNil
!
whichClassIncludesSelector: aSelector
	| c |
	c := self.
	[c == nil] whileFalse: [
		(c includesSelector: aSelector) ifTrue: [^c].
		c := c superclass].
	^nil
!
sourceCodeAt: aSelector
	^(self compiledMethodAt: aSelector) sourceCode
!
sourceCodeAt: aSelector ifAbsent: aBlock
	| m |
	m := self compiledMethodAt: aSelector ifAbsent: [^aBlock value].
	^m sourceCode
!
thoroughWhichSelectorsReferTo: aLiteral
	^self selectors select: [:sel | (self compiledMethodAt: sel) refersToLiteral: aLiteral]
!
whichSelectorsReferTo: aLiteral
	^self thoroughWhichSelectorsReferTo: aLiteral
! !

!Behavior methodsFor: 'adding/removing methods'!
addSelector: aSelector withMethod: aCompiledMethod
	"Install aCompiledMethod under aSelector, make the VM forget stale lookups and announce the change (SystemChanges)."
	| old |
	old := methodDict at: aSelector ifAbsent: [nil].
	self addSelectorSilently: aSelector withMethod: aCompiledMethod.
	self organizationChanged.
	SystemChanges methodAdded: aCompiledMethod in: self replacing: old
!
addSelectorSilently: aSelector withMethod: aCompiledMethod
	methodDict at: aSelector put: aCompiledMethod.
	self flushCacheFor: aSelector
!
removeSelector: aSelector
	"Remove my method for aSelector, if any. Answer it or nil."
	| method |
	method := methodDict at: aSelector ifAbsent: [^nil].
	methodDict removeKey: aSelector.
	self flushCacheFor: aSelector.
	self organizationChanged.
	SystemChanges method: method removedFrom: self.
	^method
!
organizationChanged
	"My methods changed; ClassDescription drops its cached organization."
!
compile: sourceString
	^self compile: sourceString classified: 'as yet unclassified'
!
compile: sourceString classified: aCategory
	"Compile sourceString with the Smalltalk compiler and install the method. Answer its selector."
	| compiler |
	compiler := Smalltalk at: #Compiler ifAbsent: [nil].
	compiler isNil ifTrue: [^self error: 'No compiler in this image'].
	^compiler compile: sourceString in: self classified: aCategory
!
recompile
	"Recompile all my methods from source."
	| compiler |
	compiler := Smalltalk at: #Compiler ifAbsent: [^self].
	self methods do: [:m |
		m sourceCode isNil ifFalse: [
			compiler compile: m sourceCode in: self classified: m category]]
! !

!Behavior methodsFor: 'class hierarchy'!
allSuperclasses
	"Answer my superclasses, nearest first."
	| result c |
	result := OrderedCollection new.
	c := superclass.
	[c == nil] whileFalse: [result add: c. c := c superclass].
	^result
!
withAllSuperclasses
	^(OrderedCollection with: self) addAll: self allSuperclasses; yourself
!
allSuperclassesDo: aBlock
	| c |
	c := superclass.
	[c == nil] whileFalse: [aBlock value: c. c := c superclass]
!
withAllSuperclassesDo: aBlock
	aBlock value: self.
	self allSuperclassesDo: aBlock
!
inheritsFrom: aClass
	"Answer whether aClass is one of my superclasses."
	| c |
	c := superclass.
	[c == nil] whileFalse: [
		c == aClass ifTrue: [^true].
		c := c superclass].
	^false
!
includesBehavior: aClass
	^self == aClass or: [self inheritsFrom: aClass]
!
subclasses
	^self subclassResponsibility
!
allSubclasses
	"Answer all my subclasses, breadth first."
	| result index |
	result := OrderedCollection new.
	result addAll: self subclasses.
	index := 1.
	[index <= result size] whileTrue: [
		result addAll: (result at: index) subclasses.
		index := index + 1].
	^result
!
withAllSubclasses
	^(OrderedCollection with: self) addAll: self allSubclasses; yourself
!
allSubclassesDo: aBlock
	self subclasses do: [:c |
		aBlock value: c.
		c allSubclassesDo: aBlock]
!
withAllSubclassesDo: aBlock
	aBlock value: self.
	self allSubclassesDo: aBlock
! !

!Behavior methodsFor: 'instance variables'!
instVarNames
	^#()
!
allInstVarNames
	"Answer the names of all named instance variables, inherited ones first."
	| names |
	names := superclass == nil
		ifTrue: [OrderedCollection new]
		ifFalse: [superclass allInstVarNames asOrderedCollection].
	names addAll: self instVarNames.
	^names asArray
!
instVarIndexFor: aString
	^self allInstVarNames indexOf: aString asString
! !

!Behavior methodsFor: 'accessing instances'!
allInstances
	"Answer an Array of all my (direct) instances."
	<primitive: 'allInstances'>
	| done carrier |
	done := Semaphore new.
	carrier := Array new: 1.
	(self c4AllInstancesSignal: done into: carrier) == self ifFalse: [^self primitiveFailed].
	done wait.
	^carrier first ifNil: [self primitiveFailed]
!
c4AllInstancesSignal: aSemaphore into: anArray
	"Internal to allInstances; the scheduler fills the carrier before signaling."
	<primitive: 94>
	^nil
!
allInstancesDo: aBlock
	self allInstances do: aBlock
!
instanceCount
	^self allInstances size
! !

!Behavior methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: self name
!
storeOn: aStream
	aStream nextPutAll: self name
! !

!Behavior methodsFor: 'copying'!
shallowCopy
	"Classes are unique."
	^self
!
deepCopy
	^self
! !
