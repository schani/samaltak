Stream subclass: #FileStream
	instanceVariableNames: 'name handle binary readBuffer readIndex readCount writeBuffer'
	classVariableNames: ''
	package: 'System-Files'!

FileStream comment: 'I read and write a file through a platform handle. In text mode (ascii, the default) I read and write Characters, UTF-8 encoded (an ill-formed sequence reads as U+FFFD, as ByteArray>>utf8Decoded; positions count bytes); in binary mode bytes (SmallIntegers, ByteArrays). Reads go through readBuffer, writes collect in writeBuffer until flush, close, a seek or a read. Close me when done; the ...do: and contentsAndClose forms do it for you, even on errors. A FileStream that is garbage collected unclosed is flushed and closed by the finalization process (WeakRegistry).'!

!FileStream methodsFor: 'initialization'!
open: aPath mode: mode
	name := aPath.
	handle := File primOpen: aPath mode: mode.
	handle isNil ifTrue: [
		^(mode = 0 and: [(File exists: aPath) not])
			ifTrue: [FileDoesNotExist signal: 'No such file: ', aPath path: aPath]
			ifFalse: [File signalErrorFor: aPath]].
	binary := false.
	readBuffer := ByteArray new: 8192.
	readIndex := 1.
	readCount := 0.
	writeBuffer := WriteStream on: (ByteArray new: 4096).
	WeakRegistry default add: self executor: self shallowCopy
! !

!FileStream methodsFor: 'accessing'!
name
	^name
!
binary
	"Read and write bytes."
	binary := true
!
ascii
	"Read and write Characters as UTF-8 (the default)."
	binary := false
!
text
	self ascii
!
isBinary
	^binary
!
next
	"Answer the next byte or Character, or nil at the end."
	| b |
	b := self nextByte.
	(binary or: [b isNil]) ifTrue: [^b].
	^self decodeCharacterStartingWith: b
!
next: anInteger
	"Answer up to anInteger next bytes (a ByteArray) or Characters (a String)."
	| stream element |
	binary ifTrue: [^self nextBytes: anInteger].
	stream := WriteStream on: (String new: anInteger).
	[stream position < anInteger and: [(element := self next) notNil]] whileTrue: [stream nextPut: element].
	^stream contents
!
peek
	| pos element |
	pos := self position.
	element := self next.
	element isNil ifFalse: [self position: pos].
	^element
!
upToEnd
	"Answer the rest of the file."
	| bytes |
	bytes := self nextBytes: (self size - self position max: 0).
	^binary ifTrue: [bytes] ifFalse: [bytes utf8Decoded]
!
upTo: anObject
	| stream element |
	stream := WriteStream on: (binary ifTrue: [ByteArray new: 64] ifFalse: [String new: 64]).
	[(element := self next) isNil or: [element = anObject]] whileFalse: [stream nextPut: element].
	^stream contents
!
nextLine
	"Answer the characters up to the next line end (lf, cr or crlf), or nil at the end."
	| stream c |
	self atEnd ifTrue: [^nil].
	stream := WriteStream on: (String new: 80).
	[(c := self next) isNil or: [c = Character lf or: [c = Character cr]]] whileFalse: [stream nextPut: c].
	(c = Character cr and: [self peek = Character lf]) ifTrue: [self next].
	^stream contents
!
contents
	"Answer the whole file."
	self position: 0.
	^self upToEnd
!
contentsAndClose
	^[self contents] ensure: [self close]
!
nextPut: anObject
	"Append a byte (binary) or Character (text)."
	self discardReadBuffer.
	anObject isCharacter
		ifTrue: [
			anObject value < 128
				ifTrue: [writeBuffer nextPut: anObject value]
				ifFalse: [writeBuffer nextPutAll: (String with: anObject) utf8Encoded]]
		ifFalse: [writeBuffer nextPut: anObject].
	writeBuffer position >= 4096 ifTrue: [self flush].
	^anObject
!
nextPutAll: aCollection
	"Append a String (UTF-8 encoded) or bytes."
	| bytes |
	self discardReadBuffer.
	bytes := aCollection isString
		ifTrue: [(aCollection isByteString and: [aCollection allSatisfy: [:c | c value < 128]])
			ifTrue: [aCollection asByteArray]
			ifFalse: [aCollection utf8Encoded]]
		ifFalse: [aCollection asByteArray].
	bytes size > 4096
		ifTrue: [self flush; writeBytes: bytes]
		ifFalse: [
			writeBuffer nextPutAll: bytes.
			writeBuffer position >= 4096 ifTrue: [self flush]].
	^aCollection
! !

!FileStream methodsFor: 'positioning'!
position
	"Answer the 0-based byte position."
	| osPosition |
	self flushWriteBuffer.
	osPosition := File primPosition: handle.
	osPosition isNil ifTrue: [^File signalErrorFor: name].
	^osPosition - (readCount - readIndex + 1)
!
position: anInteger
	self flushWriteBuffer.
	readIndex := 1.
	readCount := 0.
	(File primSeek: handle to: anInteger) isNil ifTrue: [^File signalErrorFor: name]
!
skip: anInteger
	self position: self position + anInteger
!
setToEnd
	self position: self size
!
size
	| size |
	self flushWriteBuffer.
	size := File primSize: handle.
	size isNil ifTrue: [^File signalErrorFor: name].
	^size
!
reset
	self position: 0
! !

!FileStream methodsFor: 'testing'!
atEnd
	readIndex <= readCount ifTrue: [^false].
	^self position >= self size
!
isClosed
	^handle isNil
! !

!FileStream methodsFor: 'flushing'!
flush
	self flushWriteBuffer.
	handle isNil ifFalse: [File primFlush: handle]
!
close
	"Write pending data and release the handle."
	handle isNil ifTrue: [^self].
	self flushWriteBuffer.
	File primClose: handle.
	handle := nil.
	WeakRegistry default remove: self
!
finalize
	"I am the executor of a collected FileStream (its shallow copy, sharing the write buffer): write its pending data and close the file."
	self close
! !

!FileStream methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FileStream('; nextPutAll: name; nextPut: $)
! !

!FileStream methodsFor: 'private'!
checkOpen
	handle isNil ifTrue: [^FileError signal: 'File is closed: ', name path: name]
!
nextByte
	readIndex > readCount ifTrue: [self fillReadBuffer ifFalse: [^nil]].
	readIndex := readIndex + 1.
	^readBuffer at: readIndex - 1
!
fillReadBuffer
	"Read the next chunk; answer false at the end of the file."
	| count |
	self checkOpen.
	self flushWriteBuffer.
	count := File primRead: handle into: readBuffer startingAt: 1 count: readBuffer size.
	count isNil ifTrue: [^File signalErrorFor: name].
	readIndex := 1.
	readCount := count.
	^count > 0
!
nextBytes: anInteger
	"Answer a ByteArray with up to anInteger next bytes."
	| result filled available n |
	result := ByteArray new: anInteger.
	filled := 0.
	[filled < anInteger] whileTrue: [
		readIndex > readCount ifTrue: [
			self fillReadBuffer ifFalse: [^result copyFrom: 1 to: filled]].
		available := readCount - readIndex + 1.
		n := available min: anInteger - filled.
		result replaceFrom: filled + 1 to: filled + n with: readBuffer startingAt: readIndex.
		readIndex := readIndex + n.
		filled := filled + n].
	^result
!
decodeCharacterStartingWith: firstByte
	"firstByte was just read: answer the Character of the UTF-8 sequence it begins, consumed, as ByteArray>>utf8Decoded decodes it (U+FFFD for an ill-formed one, a truncated one at the end of the file too)."
	| start n |
	firstByte < 16r80 ifTrue: [^Character value: firstByte].
	readCount - readIndex < 2 ifTrue: [self keepReadBufferFrom: readIndex - 1].
	start := readIndex - 1.
	n := readBuffer utf8LengthAt: start to: readCount.
	readIndex := start + n abs.
	^readBuffer utf8CharacterAt: start length: n
!
keepReadBufferFrom: start
	"Move the buffered bytes from start on to the front and read more after them, until 4 are buffered or the file ends: a UTF-8 sequence at start is then whole."
	| count |
	readBuffer replaceFrom: 1 to: readCount - start + 1 with: readBuffer startingAt: start.
	readIndex := readIndex - start + 1.
	readCount := readCount - start + 1.
	[readCount < 4 and: [
		count := File primRead: handle into: readBuffer startingAt: readCount + 1 count: readBuffer size - readCount.
		count isNil ifTrue: [^File signalErrorFor: name].
		readCount := readCount + count.
		count > 0]] whileTrue
!
discardReadBuffer
	"Before writing: move the OS position back to the logical position."
	self checkOpen.
	readIndex <= readCount ifTrue: [self position: self position].
	readIndex := 1.
	readCount := 0
!
flushWriteBuffer
	writeBuffer position = 0 ifTrue: [^self].
	self checkOpen.
	self writeBytes: writeBuffer contents.
	writeBuffer resetContents
!
writeBytes: aByteArray
	| written count |
	written := 0.
	[written < aByteArray size] whileTrue: [
		count := File primWrite: handle from: aByteArray startingAt: written + 1 count: aByteArray size - written.
		(count isNil or: [count = 0]) ifTrue: [^File signalErrorFor: name].
		written := written + count]
! !

!FileStream class methodsFor: 'instance creation'!
readOnlyFileNamed: aPath
	"Open an existing file for reading."
	^self basicNew open: aPath mode: 0
!
fileNamed: aPath
	"Open aPath for reading and writing, creating it if needed; the position is at the start."
	^self basicNew open: aPath mode: 1
!
newFileNamed: aPath
	"Create aPath; signal FileExists if it exists."
	(File exists: aPath) ifTrue: [^FileExists signal: 'File exists: ', aPath path: aPath].
	^self basicNew open: aPath mode: 3
!
forceNewFileNamed: aPath
	"Create aPath, truncating it if it exists."
	^self basicNew open: aPath mode: 3
!
appendingFileNamed: aPath
	^self basicNew open: aPath mode: 2
!
forceNewPrivateFileNamed: aPath
	"Create aPath, truncating it if it exists; a file this creates only its owner may read and write (mode 600)."
	^self basicNew open: aPath mode: 4
! !

!FileStream class methodsFor: 'evaluating'!
readOnlyFileNamed: aPath do: aBlock
	"Evaluate aBlock with the open stream and close it afterwards; answer the block's value."
	^self withStream: (self readOnlyFileNamed: aPath) do: aBlock
!
fileNamed: aPath do: aBlock
	^self withStream: (self fileNamed: aPath) do: aBlock
!
newFileNamed: aPath do: aBlock
	^self withStream: (self newFileNamed: aPath) do: aBlock
!
forceNewFileNamed: aPath do: aBlock
	^self withStream: (self forceNewFileNamed: aPath) do: aBlock
!
forceNewPrivateFileNamed: aPath do: aBlock
	^self withStream: (self forceNewPrivateFileNamed: aPath) do: aBlock
!
withStream: aFileStream do: aBlock
	^[aBlock value: aFileStream] ensure: [aFileStream close]
! !
