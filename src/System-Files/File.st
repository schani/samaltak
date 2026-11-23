Object subclass: #File
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Files'!

File comment: 'I am the facade for the platform''s file primitives; everything is on my class side. Paths are Strings (UTF-8 on the OS side), joined with /. Handles are SmallIntegers owned by FileStream. Failures signal FileError with the platform''s reason.'!

!File class methodsFor: 'testing'!
exists: aPath
	^(self stat: aPath) first
!
isDirectory: aPath
	^(self stat: aPath) second
!
isFile: aPath
	| st |
	st := self stat: aPath.
	^st first and: [st second not]
! !

!File class methodsFor: 'accessing'!
stat: aPath
	"Answer {exists. isDirectory. size. modification time in UTC microseconds}."
	^self primStat: aPath
!
sizeOf: aPath
	| st |
	st := self stat: aPath.
	st first ifFalse: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
	^st third
!
modificationTime: aPath
	"Answer the modification time in microseconds since 1970 (UTC)."
	| st |
	st := self stat: aPath.
	st first ifFalse: [^FileDoesNotExist signal: 'No such file: ', aPath path: aPath].
	^st fourth
! !

!File class methodsFor: 'reading and writing'!
readBytes: aPath
	"Answer the whole file as a ByteArray."
	^(FileStream readOnlyFileNamed: aPath) binary; contentsAndClose
!
readText: aPath
	"Answer the whole file decoded from UTF-8, without a leading byte order mark (U+FEFF)."
	| text |
	text := (FileStream readOnlyFileNamed: aPath) contentsAndClose.
	^(text notEmpty and: [text first value = 16rFEFF]) ifTrue: [text allButFirst] ifFalse: [text]
!
writeBytes: aByteArray to: aPath
	"Replace the file's contents with aByteArray."
	FileStream forceNewFileNamed: aPath do: [:s | s binary; nextPutAll: aByteArray]
!
writeText: aString to: aPath
	"Replace the file's contents with aString, UTF-8 encoded."
	FileStream forceNewFileNamed: aPath do: [:s | s nextPutAll: aString]
!
writeSecret: aString to: aPath
	"Replace the file with aString, UTF-8 encoded, as a file only its owner may read and write (mode 600, whatever mode it had), written whole or not at all: a new file next to it, renamed over it."
	| tmp |
	tmp := aPath, '.tmp'.
	self deleteIfExists: tmp.
	FileStream forceNewPrivateFileNamed: tmp do: [:s | s nextPutAll: aString].
	self rename: tmp to: aPath
!
lineCountOf: aPath
	"Answer the number of line feeds in the file, as wc -l counts lines."
	^(self readBytes: aPath) occurrencesOf: 10
! !

!File class methodsFor: 'file operations'!
delete: aPath
	(self primDelete: aPath) isNil ifTrue: [^self signalErrorFor: aPath]
!
deleteIfExists: aPath
	(self exists: aPath) ifTrue: [self delete: aPath]
!
rename: oldPath to: newPath
	(self primRename: oldPath to: newPath) isNil ifTrue: [^self signalErrorFor: oldPath]
! !

!File class methodsFor: 'paths'!
join: aPath with: aName
	"Answer aPath / aName with exactly one separator."
	aPath isEmpty ifTrue: [^aName].
	(aName notEmpty and: [aName first = $/]) ifTrue: [^aName].
	^(aPath last = $/ ifTrue: [aPath] ifFalse: [aPath, '/']), aName
!
baseName: aPath
	"Answer the last component of aPath."
	| i |
	i := aPath lastIndexOf: $/.
	^aPath copyFrom: i + 1 to: aPath size
!
directoryOf: aPath
	"Answer aPath without its last component ('.' if there is none)."
	| i |
	i := aPath lastIndexOf: $/.
	i = 0 ifTrue: [^'.'].
	i = 1 ifTrue: [^'/'].
	^aPath copyFrom: 1 to: i - 1
!
extensionOf: aPath
	| name i |
	name := self baseName: aPath.
	i := name lastIndexOf: $..
	i <= 1 ifTrue: [^''].
	^name copyFrom: i + 1 to: name size
! !

!File class methodsFor: 'errors'!
lastError
	"Answer the platform's description of the last failure."
	^self primLastError ifNil: ['unknown error']
!
signalErrorFor: aPath
	^FileError signal: self lastError path: aPath
! !

!File class methodsFor: 'primitives'!
primOpen: aPath mode: mode
	"mode: 0 read, 1 read/write (created if missing), 2 append, 3 create/truncate, 4 create/truncate, created with mode 600. Answer a handle or nil."
	<primitive: 'fileOpen'>
	^nil
!
primClose: handle
	<primitive: 'fileClose'>
	^nil
!
primRead: handle into: aByteArray startingAt: start count: count
	"Answer the number of bytes read (0 at the end of the file), or nil."
	<primitive: 'fileRead'>
	^nil
!
primWrite: handle from: aByteArray startingAt: start count: count
	<primitive: 'fileWrite'>
	^nil
!
primSize: handle
	<primitive: 'fileSize'>
	^nil
!
primPosition: handle
	<primitive: 'filePosition'>
	^nil
!
primSeek: handle to: position
	<primitive: 'fileSeek'>
	^nil
!
primFlush: handle
	<primitive: 'fileFlush'>
	^nil
!
primDelete: aPath
	<primitive: 'fileDelete'>
	^nil
!
primRename: oldPath to: newPath
	<primitive: 'fileRename'>
	^nil
!
primStat: aPath
	<primitive: 'fileStat'>
	^Array with: false with: false with: 0 with: 0
!
primDirEntries: aPath
	<primitive: 'dirEntries'>
	^nil
!
primDirCreate: aPath
	<primitive: 'dirCreate'>
	^nil
!
primCwd
	<primitive: 'cwd'>
	^nil
!
primLastError
	<primitive: 'platformLastError'>
	^nil
!
primSpawn: argv
	"Start argv first (looked up in PATH) with the other Strings as arguments, sharing the VM's standard streams. Answer its pid or nil."
	<primitive: 'spawnProcess'>
	^nil
!
primWait: pid blocking: aBoolean
	"Answer the exit status of the child pid (128 + signal number if killed), nil while it runs (aBoolean false); fail: nil."
	<primitive: 'processWait'>
	^nil
!
primExec: argv
	"Replace the VM's process by argv first (looked up in PATH) with the other Strings as arguments: same pid and standard streams, all other descriptors closed. Answers nil only if that failed."
	<primitive: 'execProcess'>
	^nil
! !
