TestCase subclass: #FileTest
	instanceVariableNames: 'dir'
	classVariableNames: ''
	package: 'Tests-Kernel'!

FileTest comment: 'Tests File, FileStream and Directory against a scratch directory in /tmp (TestCase>>scratchDirectory).'!

!FileTest methodsFor: 'running'!
setUp
	dir := self scratchDirectory
! !

!FileTest methodsFor: 'tests'!
testWriteReadDelete
	| path |
	path := dir / 'hello.txt'.
	self deny: (File exists: path).
	File writeText: 'Hello, World!!' to: path.
	self assert: (File exists: path).
	self assert: (File isFile: path).
	self assert: (File sizeOf: path) = 13.
	self assert: (File readText: path) = 'Hello, World!!'.
	self assert: (File modificationTime: path) > 0.
	File delete: path.
	self deny: (File exists: path).
	self should: [File readText: path] raise: FileDoesNotExist
!
testBinary
	| path bytes |
	path := dir / 'data.bin'.
	bytes := (0 to: 255) asByteArray , ((1 to: 10000) collect: [:i | i \\ 251]) asByteArray.
	File writeBytes: bytes to: path.
	self assert: (File readBytes: path) = bytes.
	self assert: (File sizeOf: path) = bytes size
!
testUTF8
	| path text |
	path := dir / 'utf8.txt'.
	text := 'héllo ', (String with: (Character value: 955)), ' wörld'.
	File writeText: text to: path.
	self assert: (File readText: path) = text.
	self assert: (File sizeOf: path) = text utf8Encoded size.
	FileStream readOnlyFileNamed: path do: [:s |
		self assert: (s next: 2) = 'hé'.
		self assert: s position = 3]
!
testUTF8IllFormed
	"FileStream decodes as ByteArray>>utf8Decoded: one U+FFFD per maximal ill-formed subpart, also across its 8 KB buffer's boundary and at the end of the file."
	| path fffd check |
	path := dir / 'bad.txt'.
	fffd := Character value: 16rFFFD.
	check := [:bytes :expected |
		File writeBytes: bytes to: path.
		self assert: (File readText: path) equals: expected.
		FileStream readOnlyFileNamed: path do: [:s |
			self assert: (s next: expected size + 1) equals: expected.
			self assert: s atEnd]].
	check value: #[16r61 16rE9 16r62 16rED 16rA0 16r80 16rF1 16r80 16r80] value: (String withAll: {$a. fffd. $b. fffd. fffd. fffd. fffd}).
	check value: (ByteArray new: 8190 withAll: 16r61) , #[16rF0 16r9F 16r98 16r80 16r62]
		value: (String new: 8190 withAll: $a) , (String with: (Character value: 16r1F600) with: $b).
	check value: (ByteArray new: 8191 withAll: 16r61) , #[16rE2 16r82 16r41]
		value: (String new: 8191 withAll: $a) , (String with: fffd with: $A).
	check value: (ByteArray new: 8191 withAll: 16r61) , #[16rF0 16r9F 16r98]
		value: (String new: 8191 withAll: $a) , (String with: fffd).
	FileStream readOnlyFileNamed: path do: [:s |
		s position: 8191.
		self assert: s next equals: fffd.
		self assert: s position equals: 8194.
		self assert: s next isNil]
!
testByteOrderMark
	"File readText: and file-in drop a leading U+FEFF; a FileStream keeps it."
	| path |
	path := dir / 'bom.st'.
	File writeBytes: #[16rEF 16rBB 16rBF] , 'Smalltalk at: #FileTestBomProbe put: 42!!' asByteArray to: path.
	self assert: (File readText: path) equals: 'Smalltalk at: #FileTestBomProbe put: 42!!'.
	self assert: (FileStream readOnlyFileNamed: path) contentsAndClose first value equals: 16rFEFF.
	[Compiler fileIn: path.
	 self assert: (Smalltalk at: #FileTestBomProbe) equals: 42]
		ensure: [Smalltalk removeKey: #FileTestBomProbe ifAbsent: []]
!
testNamesThatAreNotUTF8
	"The VM decodes OS names with surrogateescape: each byte of an ill-formed sequence is U+DC80-DCFF, written back as that byte."
	| raw name |
	raw := (dir , '/') utf8Encoded , #[16r62 16rFF 16rED 16rA0 16r80 16rC3 16rA9].
	File writeBytes: #[1 2 3] to: raw.
	name := String withAll: ({$b. 16rDCFF. 16rDCED. 16rDCA0. 16rDC80. 16rE9} collect: [:c | c isCharacter ifTrue: [c] ifFalse: [Character value: c]]).
	self assert: (Directory entries: dir) asArray equals: {name}.
	self assert: (File readBytes: dir / name) equals: #[1 2 3].
	File delete: dir / name.
	self deny: (File exists: raw).
	"Other surrogates are written as U+FFFD."
	File writeText: 'x' to: dir / (String with: $s with: (Character value: 16rD800)).
	self assert: (Directory entries: dir) asArray equals: {String with: $s with: (Character value: 16rFFFD)}
!
testNulInPathIsRefused
	| path |
	path := dir / (String with: $a with: (Character value: 0) with: $b).
	self should: [File writeText: 'x' to: path] raise: FileError.
	self deny: (File exists: dir / 'a').
	self should: [File writeText: 'x' to: (dir / 'a') utf8Encoded , #[0 16r62]] raise: FileError.
	self deny: (File exists: dir / 'a')
!
testStreamOperations
	| path |
	path := dir / 'lines.txt'.
	FileStream newFileNamed: path do: [:s |
		s nextPutAll: 'one'; nextPut: Character lf; nextPutAll: 'two'; nextPut: Character lf; print: 3].
	self should: [FileStream newFileNamed: path] raise: FileExists.
	FileStream readOnlyFileNamed: path do: [:s |
		self assert: s size = 9.
		self assert: s nextLine = 'one'.
		self assert: s peek = $t.
		self assert: s nextLine = 'two'.
		self deny: s atEnd.
		self assert: s upToEnd = '3'.
		self assert: s atEnd.
		self assert: s next isNil.
		s position: 4.
		self assert: (s upTo: Character lf) = 'two'].
	FileStream fileNamed: path do: [:s |
		s setToEnd.
		s nextPutAll: 'xyz'.
		s position: 0.
		s nextPutAll: 'ONE'].
	self assert: (File readText: path) = ('ONE', (String with: Character lf), 'two', (String with: Character lf), '3xyz').
	(FileStream appendingFileNamed: path) nextPutAll: '!!'; close.
	self assert: ((FileStream readOnlyFileNamed: path) contentsAndClose endsWith: 'xyz!!')
!
testRenameAndDirectories
	| a b sub |
	a := dir / 'a.txt'.
	b := dir / 'b.txt'.
	File writeText: 'x' to: a.
	File rename: a to: b.
	self deny: (File exists: a).
	self assert: (File readText: b) = 'x'.
	sub := dir / 'sub'.
	Directory create: sub.
	self assert: (Directory exists: sub).
	self assert: (File isDirectory: sub).
	self assert: (Directory entries: dir) = #('b.txt' 'sub').
	self assert: (Directory fileNames: dir) = #('b.txt').
	self assert: (Directory directoryNames: dir) = #('sub').
	self assert: Directory current notEmpty.
	self should: [Directory entries: dir / 'missing'] raise: FileError
!
testWriteSecret
	"A secret replaces the file whole (through a temporary file, gone afterwards); the file is created private (mode 600, not checked here: File stat has no mode)."
	| path |
	path := dir / 'secret.json'.
	File writeSecret: 'one' to: path.
	self assert: (File readText: path) equals: 'one'.
	File writeSecret: 'two' to: path.
	self assert: (File readText: path) equals: 'two'.
	self deny: (File exists: path, '.tmp').
	FileStream forceNewPrivateFileNamed: path do: [:s | s nextPutAll: 'three'].
	self assert: (File readText: path) equals: 'three'
!
testPaths
	self assert: 'a' / 'b' = 'a/b'.
	self assert: 'a/' / 'b' = 'a/b'.
	self assert: (File baseName: '/x/y/z.st') = 'z.st'.
	self assert: (File directoryOf: '/x/y/z.st') = '/x/y'.
	self assert: (File extensionOf: 'z.tar.gz') = 'gz'.
	self assert: (File extensionOf: 'Makefile') = ''
!
testClosedStream
	| s |
	s := FileStream forceNewFileNamed: dir / 'c.txt'.
	s close.
	self assert: s isClosed.
	self should: [s nextPutAll: 'x'] raise: FileError
! !
