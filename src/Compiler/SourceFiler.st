Object subclass: #SourceFiler
	instanceVariableNames: 'sourceDirectory enabled'
	classVariableNames: 'Default'
	package: 'Compiler'!

SourceFiler comment: 'I write what the browser (or the agent) accepts back into the image''s sources (src/<package>/<Class>.st, or <Class>.extension.st for a method in a ''*Package'' category; a package filed in from a directory, as an application is, in that directory), changing only that method, comment or definition chunk (ChunkFile), so unchanged methods stay byte-for-byte the same and git shows exactly the edit.

The source directory is --source-dir <dir>, else the first of <image dir>/../../src, <image dir>/../src, <image dir>/src, <current dir>/src that holds packages.txt. --no-source-write turns me off; so does a directory I cannot write (the browser then only changes the image).

	SourceFiler default writeMethod: (Integer >> #gcd:)'!

!SourceFiler methodsFor: 'accessing'!
sourceDirectory
	^sourceDirectory
!
sourceDirectory: aPathOrNil
	sourceDirectory := aPathOrNil
!
enabled: aBoolean
	enabled := aBoolean
!
isEnabled
	enabled == false ifTrue: [^false].
	(Smalltalk vm arguments includes: '--no-source-write') ifTrue: [^false].
	^sourceDirectory notNil
!
packageDirectory: aPackageName
	"src/<package>, or the directory the package was filed in from (an application's)."
	^(Compiler packageDirectoryOf: aPackageName) ifNil: [sourceDirectory, '/', aPackageName]
!
pathForClass: aClass
	^(self packageDirectory: aClass theNonMetaClass packageName), '/', aClass theNonMetaClass name, '.st'
!
pathForMethod: aCompiledMethod
	"The file a method lives in: its class's file, or the extension file of the package its *category names."
	| cat cls |
	cat := aCompiledMethod category ifNil: [''].
	cls := aCompiledMethod methodClass theNonMetaClass.
	(cat beginsWith: '*') ifTrue: [
		^(self packageDirectory: (self packageOfExtensionCategory: cat)), '/', cls name, '.extension.st'].
	^self pathForClass: cls
!
packageOfExtensionCategory: aString
	"'*System-Profiling' names the package System-Profiling (a longer name like '*System-Profiling-private' names the longest package it starts with)."
	| name best |
	name := aString allButFirst.
	best := nil.
	Smalltalk packages do: [:p |
		((name = p name or: [name beginsWith: p name, '-']) and: [best isNil or: [p name size > best size]])
			ifTrue: [best := p name]].
	^best ifNil: [name]
! !

!SourceFiler methodsFor: 'files'!
chunkFileAt: aPath
	^ChunkFile on: ((File exists: aPath) ifTrue: [File readText: aPath] ifFalse: [''])
!
save: aChunkFile to: aPath
	| dir |
	dir := File directoryOf: aPath.
	(File isDirectory: dir) ifFalse: [Directory create: dir].
	File writeText: aChunkFile text to: aPath
! !

!SourceFiler methodsFor: 'writing'!
writeMethod: aCompiledMethod
	"Write the method's source into its file. Answer the path if the file changed, nil if it was already up to date or I am off."
	| path file cls |
	self isEnabled ifFalse: [^nil].
	path := self pathForMethod: aCompiledMethod.
	cls := aCompiledMethod methodClass.
	file := self chunkFileAt: path.
	(file putMethod: aCompiledMethod source
		selector: aCompiledMethod selector
		className: cls theNonMetaClass name
		meta: cls isMeta
		category: (aCompiledMethod category ifNil: ['as yet unclassified'])) ifFalse: [^nil].
	self save: file to: path.
	^path
!
removeMethod: aSelector class: aBehavior category: aCategory
	"Remove a method from the file it lived in (when the browser moves it to another file)."
	| path file entry |
	self isEnabled ifFalse: [^nil].
	path := (aCategory notNil and: [aCategory beginsWith: '*'])
		ifTrue: [(self packageDirectory: (self packageOfExtensionCategory: aCategory)), '/', aBehavior theNonMetaClass name, '.extension.st']
		ifFalse: [self pathForClass: aBehavior].
	(File exists: path) ifFalse: [^nil].
	file := self chunkFileAt: path.
	entry := file methodEntryFor: aSelector className: aBehavior theNonMetaClass name meta: aBehavior isMeta.
	entry isNil ifTrue: [^nil].
	file removeMethodEntry: entry.
	self save: file to: path.
	^path
!
writeDefinition: aString of: aClass
	| path file |
	self isEnabled ifFalse: [^nil].
	path := self pathForClass: aClass.
	file := self chunkFileAt: path.
	(file putDefinition: aString className: aClass name) ifFalse: [^nil].
	self save: file to: path.
	^path
!
writeCommentOf: aClass
	| path file |
	self isEnabled ifFalse: [^nil].
	path := self pathForClass: aClass.
	file := self chunkFileAt: path.
	(file putComment: (aClass comment ifNil: ['']) className: aClass name) ifFalse: [^nil].
	self save: file to: path.
	^path
!
definitionInFileOf: aClass
	"The class definition chunk as written in its file, or nil."
	| path file k |
	sourceDirectory isNil ifTrue: [^nil].
	path := self pathForClass: aClass.
	(File exists: path) ifFalse: [^nil].
	file := self chunkFileAt: path.
	k := file definitionChunkFor: aClass name.
	^k isNil ifTrue: [nil] ifFalse: [file chunkBody: k]
! !

!SourceFiler class methodsFor: 'instance creation'!
default
	^Default ifNil: [Default := self new sourceDirectory: self findSourceDirectory; yourself]
!
default: aSourceFilerOrNil
	Default := aSourceFilerOrNil
!
reset
	Default := nil
!
findSourceDirectory
	| explicit image dir candidates |
	explicit := Smalltalk argumentAfter: '--source-dir'.
	explicit isNil ifFalse: [^explicit].
	candidates := OrderedCollection new.
	image := Smalltalk vm imagePath.
	image isNil ifFalse: [
		dir := File directoryOf: image.
		candidates add: dir, '/../../src'; add: dir, '/../src'; add: dir, '/src'].
	File primCwd ifNotNil: [:cwd | candidates add: cwd, '/src'].
	^candidates detect: [:each | File exists: each, '/packages.txt'] ifNone: [nil]
! !

!SourceFiler class methodsFor: 'class initialization'!
startUp: resuming
	"The image may have moved: look for the sources again."
	Default := nil
!
initialize
	Smalltalk addToStartUpList: self
! !
