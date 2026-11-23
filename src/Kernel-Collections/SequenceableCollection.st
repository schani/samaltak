Collection subclass: #SequenceableCollection
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

SequenceableCollection comment: 'I am the abstract class of collections whose elements are ordered and accessed by integer index from 1 to size. Subclasses define size, at: and at:put:; copies are made with species new: and replaceFrom:to:with:startingAt:.'!

!SequenceableCollection methodsFor: 'accessing'!
size
	^self subclassResponsibility
!
first
	"Answer the first element; signal an error if I am empty."
	self emptyCheck.
	^self at: 1
!
last
	self emptyCheck.
	^self at: self size
!
second
	^self at: 2
!
third
	^self at: 3
!
fourth
	^self at: 4
!
fifth
	^self at: 5
!
first: n
	"Answer my first n elements."
	^self copyFrom: 1 to: n
!
last: n
	"Answer my last n elements."
	^self copyFrom: self size - n + 1 to: self size
!
allButFirst
	^self allButFirst: 1
!
allButFirst: n
	^self copyFrom: n + 1 to: self size
!
allButLast
	^self allButLast: 1
!
allButLast: n
	^self copyFrom: 1 to: self size - n
!
middle
	^self at: self size + 1 // 2
!
at: index ifAbsent: aBlock
	(index between: 1 and: self size) ifFalse: [^aBlock value].
	^self at: index
!
atRandom
	^self at: (Random new nextInt: self size)
!
indexOf: anObject
	"Answer the index of the first element equal to anObject, 0 if none."
	^self indexOf: anObject startingAt: 1 ifAbsent: [0]
!
indexOf: anObject ifAbsent: aBlock
	^self indexOf: anObject startingAt: 1 ifAbsent: aBlock
!
indexOf: anObject startingAt: start
	^self indexOf: anObject startingAt: start ifAbsent: [0]
!
indexOf: anObject startingAt: start ifAbsent: aBlock
	start to: self size do: [:i | (self at: i) = anObject ifTrue: [^i]].
	^aBlock value
!
identityIndexOf: anObject
	1 to: self size do: [:i | (self at: i) == anObject ifTrue: [^i]].
	^0
!
lastIndexOf: anObject
	self size to: 1 by: -1 do: [:i | (self at: i) = anObject ifTrue: [^i]].
	^0
!
indexOfSubCollection: aSubCollection startingAt: start
	"Answer the index where aSubCollection begins at or after start, 0 if it does not occur."
	| subSize first |
	subSize := aSubCollection size.
	subSize = 0 ifTrue: [^start].
	first := aSubCollection at: 1.
	start to: self size - subSize + 1 do: [:i |
		(self at: i) = first ifTrue: [
			| match |
			match := true.
			2 to: subSize do: [:j | (match and: [(self at: i + j - 1) ~= (aSubCollection at: j)]) ifTrue: [match := false]].
			match ifTrue: [^i]]].
	^0
!
indexOfSubCollection: aSubCollection
	^self indexOfSubCollection: aSubCollection startingAt: 1
!
findFirst: aBlock
	"Answer the index of the first element satisfying aBlock, 0 if none."
	1 to: self size do: [:i | (aBlock value: (self at: i)) ifTrue: [^i]].
	^0
!
findLast: aBlock
	self size to: 1 by: -1 do: [:i | (aBlock value: (self at: i)) ifTrue: [^i]].
	^0
!
after: anObject
	| i |
	i := self indexOf: anObject.
	(i = 0 or: [i = self size]) ifTrue: [^self errorNotFound: anObject].
	^self at: i + 1
!
before: anObject
	| i |
	i := self indexOf: anObject.
	i <= 1 ifTrue: [^self errorNotFound: anObject].
	^self at: i - 1
!
keys
	^1 to: self size
!
anyOne
	^self first
!
atAllPut: anObject
	1 to: self size do: [:i | self at: i put: anObject]
!
atAll: indices put: anObject
	indices do: [:i | self at: i put: anObject]
!
replaceAll: oldObject with: newObject
	1 to: self size do: [:i | (self at: i) = oldObject ifTrue: [self at: i put: newObject]]
!
replaceFrom: start to: stop with: replacement
	"Replace my elements start..stop with those of replacement (which must have the same size)."
	replacement size = (stop - start + 1) ifFalse: [^self error: 'Size of replacement doesn''t match'].
	^self replaceFrom: start to: stop with: replacement startingAt: 1
!
replaceFrom: start to: stop with: replacement startingAt: repStart
	"Copy replacement's elements from repStart into my elements start..stop."
	| delta |
	delta := repStart - start.
	(self == replacement and: [repStart < start])
		ifTrue: [stop to: start by: -1 do: [:i | self at: i put: (replacement at: i + delta)]]
		ifFalse: [start to: stop do: [:i | self at: i put: (replacement at: i + delta)]]
!
streamAt: index put: anObject
	"Store for a WriteStream (see String>>streamAt:put:)."
	self at: index put: anObject.
	^anObject
!
swap: i with: j
	| t |
	t := self at: i.
	self at: i put: (self at: j).
	self at: j put: t
! !

!SequenceableCollection methodsFor: 'comparing'!
= otherCollection
	"Answer whether otherCollection has the same species and equal elements in the same order."
	self == otherCollection ifTrue: [^true].
	otherCollection isSequenceable ifFalse: [^false].
	self species == otherCollection species ifFalse: [^false].
	^self hasEqualElements: otherCollection
!
hasEqualElements: otherCollection
	| size |
	size := self size.
	size = otherCollection size ifFalse: [^false].
	1 to: size do: [:i | (self at: i) = (otherCollection at: i) ifFalse: [^false]].
	^true
!
hash
	| h |
	h := self species hash bitXor: self size.
	1 to: (self size min: 16) do: [:i | h := (h + (self at: i) hash) hashMultiply].
	^h
!
beginsWith: aSequence
	aSequence size > self size ifTrue: [^false].
	1 to: aSequence size do: [:i | (self at: i) = (aSequence at: i) ifFalse: [^false]].
	^true
!
endsWith: aSequence
	| offset |
	offset := self size - aSequence size.
	offset < 0 ifTrue: [^false].
	1 to: aSequence size do: [:i | (self at: i + offset) = (aSequence at: i) ifFalse: [^false]].
	^true
! !

!SequenceableCollection methodsFor: 'testing'!
isSequenceable
	^true
!
includes: anObject
	1 to: self size do: [:i | (self at: i) = anObject ifTrue: [^true]].
	^false
!
isEmpty
	^self size = 0
! !

!SequenceableCollection methodsFor: 'enumerating'!
do: aBlock
	1 to: self size do: [:i | aBlock value: (self at: i)]
!
reverseDo: aBlock
	self size to: 1 by: -1 do: [:i | aBlock value: (self at: i)]
!
doWithIndex: aBlock
	"Evaluate aBlock with each element and its index."
	1 to: self size do: [:i | aBlock value: (self at: i) value: i]
!
withIndexDo: aBlock
	self doWithIndex: aBlock
!
keysAndValuesDo: aBlock
	"Evaluate aBlock with each index and element."
	1 to: self size do: [:i | aBlock value: i value: (self at: i)]
!
from: start to: stop do: aBlock
	start to: stop do: [:i | aBlock value: (self at: i)]
!
do: aBlock separatedBy: separatorBlock
	1 to: self size do: [:i |
		i > 1 ifTrue: [separatorBlock value].
		aBlock value: (self at: i)]
!
with: aCollection do: aBlock
	"Evaluate aBlock with corresponding elements of the receiver and aCollection."
	aCollection size = self size ifFalse: [^self error: 'Collections must have the same size'].
	1 to: self size do: [:i | aBlock value: (self at: i) value: (aCollection at: i)]
!
with: aCollection collect: aBlock
	| result |
	aCollection size = self size ifFalse: [^self error: 'Collections must have the same size'].
	result := self species new: self size.
	1 to: self size do: [:i | result at: i put: (aBlock value: (self at: i) value: (aCollection at: i))].
	^result
!
collect: aBlock
	| stream |
	stream := WriteStream on: (self species new: self size).
	1 to: self size do: [:i | stream nextPut: (aBlock value: (self at: i))].
	^stream contents
!
collectWithIndex: aBlock
	| stream |
	stream := WriteStream on: (self species new: self size).
	1 to: self size do: [:i | stream nextPut: (aBlock value: (self at: i) value: i)].
	^stream contents
!
withIndexCollect: aBlock
	^self collectWithIndex: aBlock
!
select: aBlock
	| stream |
	stream := WriteStream on: (self species new: self size).
	1 to: self size do: [:i |
		| each |
		each := self at: i.
		(aBlock value: each) ifTrue: [stream nextPut: each]].
	^stream contents
!
reject: aBlock
	^self select: [:each | (aBlock value: each) == false]
!
detect: aBlock ifNone: exceptionBlock
	1 to: self size do: [:i | (aBlock value: (self at: i)) ifTrue: [^self at: i]].
	^exceptionBlock value
!
pairsDo: aBlock
	"Evaluate aBlock with elements 1 and 2, then 3 and 4, ..."
	1 to: self size - 1 by: 2 do: [:i | aBlock value: (self at: i) value: (self at: i + 1)]
!
allButFirstDo: aBlock
	2 to: self size do: [:i | aBlock value: (self at: i)]
!
allButLastDo: aBlock
	1 to: self size - 1 do: [:i | aBlock value: (self at: i)]
!
readStream
	^ReadStream on: self
!
writeStream
	^WriteStream on: self
!
readWriteStream
	^ReadWriteStream on: self
! !

!SequenceableCollection methodsFor: 'copying'!
copyFrom: start to: stop
	"Answer a copy of my elements start..stop."
	| n result |
	n := stop - start + 1.
	n < 0 ifTrue: [^self error: 'copyFrom:to: with stop < start - 1'].
	result := self species new: n.
	n > 0 ifTrue: [result replaceFrom: 1 to: n with: self startingAt: start].
	^result
!
, aSequence
	"Answer my elements followed by those of aSequence."
	^self copyReplaceFrom: self size + 1 to: self size with: aSequence
!
copyReplaceFrom: start to: stop with: replacement
	"Answer a copy in which elements start..stop are replaced by replacement (which may have another size)."
	| result endReplacement newSize |
	newSize := self size - (stop - start + 1) + replacement size.
	endReplacement := start - 1 + replacement size.
	result := self species new: newSize.
	start > 1 ifTrue: [result replaceFrom: 1 to: start - 1 with: self startingAt: 1].
	replacement size > 0 ifTrue: [result replaceFrom: start to: endReplacement with: replacement startingAt: 1].
	stop < self size ifTrue: [result replaceFrom: endReplacement + 1 to: newSize with: self startingAt: stop + 1].
	^result
!
copyReplaceAll: oldSubCollection with: newSubCollection
	"Answer a copy in which every occurrence of oldSubCollection is replaced by newSubCollection."
	| stream index start |
	oldSubCollection isEmpty ifTrue: [^self copy].
	stream := WriteStream on: (self species new: self size).
	start := 1.
	[(index := self indexOfSubCollection: oldSubCollection startingAt: start) > 0] whileTrue: [
		stream nextPutAll: (self copyFrom: start to: index - 1).
		stream nextPutAll: newSubCollection.
		start := index + oldSubCollection size].
	stream nextPutAll: (self copyFrom: start to: self size).
	^stream contents
!
copyReplacing: oldObject with: newObject
	^self collect: [:each | each = oldObject ifTrue: [newObject] ifFalse: [each]]
!
copyWith: newElement
	| result |
	result := self species new: self size + 1.
	result replaceFrom: 1 to: self size with: self startingAt: 1.
	result at: self size + 1 put: newElement.
	^result
!
copyWithFirst: newElement
	^(self species with: newElement), self
!
copyWithout: oldElement
	^self reject: [:each | each = oldElement]
!
copyAfter: anElement
	| i |
	i := self indexOf: anElement.
	i = 0 ifTrue: [^self copyFrom: 1 to: 0].
	^self copyFrom: i + 1 to: self size
!
copyAfterLast: anElement
	| i |
	i := self lastIndexOf: anElement.
	i = 0 ifTrue: [^self copyFrom: 1 to: 0].
	^self copyFrom: i + 1 to: self size
!
copyUpTo: anElement
	| i |
	i := self indexOf: anElement.
	i = 0 ifTrue: [^self copy].
	^self copyFrom: 1 to: i - 1
!
copyUpToLast: anElement
	| i |
	i := self lastIndexOf: anElement.
	i = 0 ifTrue: [^self copy].
	^self copyFrom: 1 to: i - 1
!
reversed
	"Answer a copy with my elements in reverse order."
	| n result |
	n := self size.
	result := self species new: n.
	1 to: n do: [:i | result at: i put: (self at: n + 1 - i)].
	^result
!
reverse
	^self reversed
!
shuffled
	| copy random |
	copy := self asArray copy.
	random := Random new.
	copy size to: 2 by: -1 do: [:i | copy swap: i with: (random nextInt: i)].
	^copy
! !

!SequenceableCollection methodsFor: 'sorting'!
sort
	"Sort the receiver in place, ascending."
	^self sort: [:a :b | a <= b]
!
sort: aSortBlock
	"Sort the receiver in place with a stable merge sort; aSortBlock answers whether its first argument goes before (or equal to) the second."
	| n work buffer |
	n := self size.
	n < 2 ifTrue: [^self].
	work := Array new: n.
	1 to: n do: [:i | work at: i put: (self at: i)].
	buffer := Array new: n.
	work mergeSortFrom: 1 to: n buffer: buffer by: aSortBlock.
	1 to: n do: [:i | self at: i put: (work at: i)]
!
sorted: aSortBlock
	^(self species withAll: self) sort: aSortBlock; yourself
!
isSorted
	^self isSortedBy: [:a :b | a <= b]
!
isSortedBy: aSortBlock
	2 to: self size do: [:i | (aSortBlock value: (self at: i - 1) value: (self at: i)) ifFalse: [^false]].
	^true
!
mergeSortFrom: low to: high buffer: buffer by: aSortBlock
	"Stable merge sort of my elements low..high, using buffer (an Array of my size) as scratch space."
	| mid i j k |
	high - low < 8 ifTrue: [^self insertionSortFrom: low to: high by: aSortBlock].
	mid := low + high // 2.
	self mergeSortFrom: low to: mid buffer: buffer by: aSortBlock.
	self mergeSortFrom: mid + 1 to: high buffer: buffer by: aSortBlock.
	(aSortBlock value: (self at: mid) value: (self at: mid + 1)) ifTrue: [^self].
	low to: high do: [:n | buffer at: n put: (self at: n)].
	i := low.
	j := mid + 1.
	k := low.
	[i <= mid and: [j <= high]] whileTrue: [
		(aSortBlock value: (buffer at: i) value: (buffer at: j))
			ifTrue: [self at: k put: (buffer at: i). i := i + 1]
			ifFalse: [self at: k put: (buffer at: j). j := j + 1].
		k := k + 1].
	[i <= mid] whileTrue: [
		self at: k put: (buffer at: i).
		i := i + 1.
		k := k + 1]
!
insertionSortFrom: low to: high by: aSortBlock
	low + 1 to: high do: [:i |
		| x j |
		x := self at: i.
		j := i - 1.
		[j >= low and: [(aSortBlock value: (self at: j) value: x) not]] whileTrue: [
			self at: j + 1 put: (self at: j).
			j := j - 1].
		self at: j + 1 put: x]
! !

!SequenceableCollection methodsFor: 'converting'!
asArray
	| result |
	result := Array new: self size.
	1 to: self size do: [:i | result at: i put: (self at: i)].
	^result
!
join: aCollection
	"Answer the elements of aCollection (sequences) concatenated, with the receiver between them: ', ' join: #('a' 'b')."
	^self species new: 16 streamContents: [:stream |
		aCollection
			do: [:each | stream nextPutAll: each]
			separatedBy: [stream nextPutAll: self]]
! !
