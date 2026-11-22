ToolsTestCase subclass: #FileBrowserTest
	instanceVariableNames: 'window browser'
	classVariableNames: ''
	package: 'Tests-Tools'!

FileBrowserTest comment: 'I test the File Browser, a column browser, on the repository and on scratch folders: it opens from the World menu''s registry at the working directory; a column lists folders first, sorted, with line counts, dot files left out, a FIFO not opened; selecting a folder opens the next column and closes those after it, selecting a file previews it; up, down, right, left and clicks move as a user does (injected events), a double click enters a folder only if both presses are on its row; Interpreter.st and interpreter.c preview with the right header, line count, date and highlighting; a large file opens fast and only the rows shown are drawn; deep columns scroll sideways; a binary file shows as a hex dump; the widgets are named for remote control; drawing is retained.'!

!FileBrowserTest methodsFor: 'running'!
setUp
	super setUp.
	window := self open: [FileBrowser openOn: nil at: 60 @ 60].
	browser := window content.
	self opened: window.
	window focus.
	self assert: (self waitFor: [window isFocused]) description: 'the window did not get the focus'
!
tearDown
	window isNil ifFalse: [window close].
	super tearDown
! !

!FileBrowserTest methodsFor: 'support'!
opened: aWindow
	"Wait for aWindow's Process to have browsed: its queue may be empty while it still does."
	self in: aWindow do: [nil]
!
namesIn: anInteger
	^((browser listAt: anInteger) items collect: [:each | each name]) asArray
!
directories
	^(browser lists collect: [:each | each directory]) asArray
!
reveal: aPath
	self in: window do: [browser reveal: aPath]
!
tokenTypeAt: anInteger
	"The viewer scans its text when it draws, in its window's Process: read there."
	^self in: window do: [browser viewer tokenTypeAt: anInteger]
!
select: aName in: anInteger
	self in: window do: [ | list |
		list := browser listAt: anInteger.
		list select: (list entryNamed: aName)]
!
press: aKey thenWaitFor: aBlock
	self key: aKey modifiers: 0.
	self waitUntil: aBlock description: aKey printString, ' did not take effect'
!
waitUntil: aBlock description: aString
	"Wait for aBlock, then for the window to finish the event: aBlock may hold before it has."
	self assert: (self waitFor: aBlock) description: aString.
	self in: window do: [nil]
!
pointOf: aName in: anInteger
	^(((browser listAt: anInteger) remoteChildren detect: [:each | each remoteLabel = aName]) remoteClickPoint) rounded
!
pointOfSegment: anIndex
	^((browser pathBar remoteChildren at: anIndex) remoteClickPoint) rounded
!
focused
	^window keyboardFocus
!
headerFor: aPath kind: aString
	| full |
	full := browser root / aPath.
	self assert: (File readBytes: full) last equals: 10.
	^aString, ' · ', (ProfilerFormat count: (File lineCountOf: full)), ' lines · ', (ProfilerFormat bytes: (File sizeOf: full))
!
revealCFixture
	| dir lf |
	dir := self scratchDirectory.
	lf := String with: Character lf.
	Directory create: dir / 'vm'; create: dir / 'vm' / 'gen'.
	File writeText: '/* Preview fixture */', lf, '#include "samaltak.h"', lf, 'static int count;', lf
		to: dir / 'vm' / 'gen' / 'preview.c'.
	self in: window do: [browser browse: dir].
	self reveal: 'vm/gen/preview.c'
! !

!FileBrowserTest methodsFor: 'tests'!
testOpensAtTheWorkingDirectory
	| labels other |
	labels := ((ToolsMenu worldMenuAt: nil) items select: [:i | i isItem]) collect: [:i | i label].
	self assert: (labels includes: 'File Browser').
	self assert: browser root equals: Directory current.
	self assert: self directories equals: (Array with: Directory current).
	self assert: ((self namesIn: 1) includesAll: #('src' 'vm' 'Makefile')).
	self deny: ((self namesIn: 1) includes: '.gitignore').
	self assert: browser pathBar labels equals: (Array with: (File baseName: Directory current)).
	self assert: (self waitFor: [(browser listAt: 1) isFocused]) description: 'the first column has no keyboard focus'.
	other := self open: [Tools open: #files with: 'src/VM-Core'].
	[self opened: other.
	 self assert: (other content lists collect: [:each | each directory]) asArray
		equals: (Array with: Directory current with: Directory current, '/src' with: Directory current, '/src/VM-Core').
	 self assert: (other content listAt: 2) selection name equals: 'VM-Core'.
	 self assert: other content pathBar labels equals: (Array with: (File baseName: Directory current) with: 'src' with: 'VM-Core')]
		ensure: [self settle. other close]
!
testListsFoldersFirstWithLines
	| dir lf list |
	dir := self scratchDirectory.
	lf := String with: Character lf.
	Directory create: dir / 'beta'; create: dir / 'Alpha'.
	File writeText: 'one', lf, 'two', lf, 'three' to: dir / 'notes.txt'.
	File writeText: 'Object subclass: #Foo', lf to: dir / 'Foo.st'.
	File writeBytes: (ByteArray with: 1 with: 0 with: 2) to: dir / 'data.bin'.
	File writeText: 'secret' to: dir / '.hidden'.
	"Not opened: a FIFO without a writer would block the VM."
	self assert: (OSProcess run: (OSProcess commandFor: (Array with: 'mkfifo' with: dir / 'pipe'))) exitCode equals: 0.
	self in: window do: [browser browse: dir].
	self assert: (self namesIn: 1) equals: #('Alpha' 'beta' 'data.bin' 'Foo.st' 'notes.txt' 'pipe').
	list := browser listAt: 1.
	self assert: (list entryNamed: 'Alpha') isDirectory.
	self assert: (list entryNamed: 'notes.txt') lines equals: 3.
	self assert: (list entryNamed: 'notes.txt') size equals: 13.
	self assert: (list entryNamed: 'Foo.st') kind equals: #smalltalk.
	self assert: (list entryNamed: 'data.bin') kind equals: #binary.
	self assert: (list entryNamed: 'data.bin') lines isNil.
	self assert: (list entryNamed: 'pipe') lines equals: 0.
	self assert: (list rightTextOf: (list entryNamed: 'Alpha')) equals: (String with: (Character value: 16r25B8)).
	self assert: (list rightTextOf: (list entryNamed: 'notes.txt')) equals: '3'.
	self assert: browser pathBar labels equals: (Array with: (File baseName: dir)).
	self assert: (browser pathBar remoteState includes: 'summary="2 folders · 4 files"')
!
testSelectingOpensAndClosesColumns
	| root |
	root := browser root.
	self select: 'vm' in: 1.
	self assert: self directories equals: (Array with: root with: root, '/vm').
	self select: 'gen' in: 2.
	self assert: self directories equals: (Array with: root with: root, '/vm' with: root, '/vm/gen').
	self select: 'interpreter.c' in: 3.
	self assert: browser file name equals: 'interpreter.c'.
	self assert: browser columns preview notNil.
	"A selection further left closes the columns after it, and the preview."
	self select: 'src' in: 1.
	self assert: self directories equals: (Array with: root with: root, '/src').
	self assert: browser file isNil.
	self assert: browser columns preview isNil.
	self assert: browser pathBar labels equals: (Array with: (File baseName: root) with: 'src')
!
testKeysAndClicksMoveAsInFinder
	self click: (self pointOf: 'vm' in: 1).
	self waitUntil: [browser lists size = 2] description: 'the click did not open vm'.
	self press: #right thenWaitFor: [self focused == (browser listAt: 2)].
	self assert: (browser listAt: 2) selectionIndex equals: 1.
	self select: 'gen' in: 2.
	self press: #right thenWaitFor: [self focused == (browser listAt: 3)].
	self assert: browser file name equals: (browser listAt: 3) items first name.
	self press: #down thenWaitFor: [browser file notNil and: [browser file name = ((browser listAt: 3) items at: 2) name]].
	self press: #left thenWaitFor: [self focused == (browser listAt: 2)].
	self assert: (browser listAt: 2) selection name equals: 'gen'.
	self assert: (browser listAt: 3) selection isNil.
	self assert: browser file isNil.
	self assert: self directories size equals: 3.
	self press: #left thenWaitFor: [self focused == (browser listAt: 1)].
	self assert: (browser listAt: 1) selection name equals: 'vm'.
	"Return on a file: its text takes the keys."
	self reveal: 'vm/gen/interpreter.c'.
	self press: #return thenWaitFor: [self focused == browser viewer].
	"The path's first segment: back to the first column."
	self click: (self pointOfSegment: 1).
	self waitUntil: [browser lists size = 1] description: 'the path''s first segment did not go back'.
	self assert: (browser listAt: 1) selection isNil.
	self assert: self focused == (browser listAt: 1)
!
testDoubleClickEntersOnlyTheFolderOfBothPresses
	"Presses 4 points apart across the border of the rows a and b, the platform counting them as a double click: b is selected, not entered."
	| dir list r a b |
	dir := self scratchDirectory.
	Directory create: dir / 'a'; create: dir / 'b'.
	File writeText: 'x' to: dir / 'b' / 'x.txt'.
	self in: window do: [browser browse: dir].
	list := browser listAt: 1.
	r := list rowRect: 1.
	a := list localToScreen: (r left + 60) @ (r bottom - 2).
	b := a + (0 @ 4).
	self click: a platformCount: 1; click: b platformCount: 2.
	self settle.
	self assert: list selection name equals: 'b'.
	self assert: self focused == list.
	self click: b platformCount: 1; click: b platformCount: 2.
	self waitUntil: [self focused == (browser listAt: 2)] description: 'the double click did not enter b'.
	self assert: (browser listAt: 2) selection name equals: 'x.txt'
!
testPreviewsASmalltalkFile
	| path |
	path := 'src/VM-Core/Interpreter.st'.
	self reveal: path.
	self assert: browser file name equals: 'Interpreter.st'.
	self assert: browser header title equals: 'Interpreter.st'.
	self assert: browser header rightText equals: (self headerFor: path kind: 'Smalltalk').
	self assert: (browser info fullText beginsWith: 'modified ', (Date fromDays: (File modificationTime: browser root / path) // 86400000000) printString).
	self assert: (browser info fullText includesSubstring: ' UTC opened in ').
	self assert: browser viewer text equals: (File readText: browser root / path).
	self assert: (browser viewer text beginsWith: 'VMCoreModule subclass: #Interpreter').
	self assert: (self tokenTypeAt: 1) equals: #global.
	self assert: (self tokenTypeAt: 15) equals: #keyword.
	self assert: window title equals: 'File Browser: Interpreter.st'.
	self assert: self focused == (browser listAt: 3)
!
testPreviewsACFile
	| path text i |
	path := 'vm/gen/preview.c'.
	self revealCFixture.
	self assert: browser header title equals: 'preview.c'.
	self assert: browser header rightText equals: (self headerFor: path kind: 'C').
	text := browser viewer text.
	self assert: (text beginsWith: '/* Preview fixture */').
	self assert: (self tokenTypeAt: 1) equals: #comment.
	i := text indexOfSubCollection: '#include "samaltak.h"'.
	self assert: (self tokenTypeAt: i) equals: #keyword.
	self assert: (self tokenTypeAt: i + 10) equals: #global.
	i := text indexOfSubCollection: (String with: Character lf), 'static '.
	self assert: (self tokenTypeAt: i + 1) equals: #keyword.
	self assert: (self tokenTypeAt: i + 8) equals: #identifier
!
testCSourceScanner
	| source tokens |
	source := 'int x = 1; // one', (String with: Character lf), '  # define S "a /* b" ''\''''', (String with: Character lf), 'return /* two */ x;'.
	tokens := OrderedCollection new.
	CSourceScanner highlight: source do: [:type :start :stop | tokens add: type -> (source copyFrom: start to: stop)].
	self assert: (tokens inject: '' into: [:all :each | all, each value]) equals: source.
	self assert: ((tokens reject: [:each | each key == #identifier]) collect: [:each | each key]) asArray
		equals: #(#keyword #global #comment #keyword #global #global #keyword #comment).
	self assert: ((tokens reject: [:each | each key == #identifier]) collect: [:each | each value]) asArray
		equals: {'int'. '1'. '// one'. '# define'. '"a /* b"'. '''\'''''. 'return'. '/* two */'}.
	tokens := OrderedCollection new.
	CSourceScanner highlight: 'g (1x);' do: [:type :start :stop | tokens add: type].
	self assert: (tokens reject: [:each | each == #identifier]) asArray equals: #(#return #global)
!
testMachineCodeScanner
	| lf source tokens typeOf |
	lf := String with: Character lf.
	source := 'Complex>>+  opt, 16 bytes at 16r100', lf, lf,
		'pc 5: send: #+  -- real + aComplex real', lf,
		'L3:', lf,
		'  +0198  f240083f  tst x1, #0x7                     ; guard: its class', lf,
		'                                                    ; its pc 0', lf,
		'  +01b4  f9400885  ldr x5, [x4, #-0x10]!!', lf,
		'  +01bc  a9bf7bfd  stp x29, x30, [sp, #-0x10]!!      ; frame', lf,
		'  +01c0  97ff841d  bl 0x102bf0148 <baseline miss>   ; call', lf,
		'  +01c4  54000121  b.ne L12', lf,
		'  +01c8  9a960050  csel x16, x2, xzr, eq', lf,
		'  +01cc  001a4b58  .word 0x001a4b58'.
	tokens := OrderedCollection new.
	MachineCodeScanner highlight: source do: [:type :start :stop | tokens add: type -> (source copyFrom: start to: stop)].
	self assert: (tokens inject: '' into: [:all :each | all, each value]) equals: source.
	typeOf := [:text | (tokens detect: [:each | each value = text]) key].
	#(
		'Complex>>+  opt, 16 bytes at 16r100' #pattern
		'pc 5: send: #+' #return
		'-- real + aComplex real' #global
		'L3:' #keyword
		'+0198' #self
		'f240083f' #self
		'tst' #keyword
		'x1' #symbol
		'#0x7' #global
		'; guard: its class' #comment
		'; its pc 0' #comment
		'x4' #symbol
		'#-0x10' #global
		'sp' #symbol
		'0x102bf0148' #global
		'<baseline miss>' #global
		'b.ne' #keyword
		'L12' #global
		'xzr' #symbol
		'.word' #keyword
		'0x001a4b58' #global)
		pairsDo: [:text :type | self assert: (typeOf value: text) equals: type].
	"The rest stays #identifier: condition codes and punctuation."
	self assert: (typeOf value: ', ') equals: #identifier
!
testLargeFileOpensFastAndDrawsOnlyTheRowsShown
	| ms canvas viewer |
	self reveal: 'vm/gen'.
	"The best of three (some 70 ms each), so a busy machine does not fail it."
	ms := (1 to: 3) inject: SmallInteger maxVal into: [:best :i |
		best min: (self in: window do: [ | t0 list |
			t0 := Time millisecondClockValue.
			list := browser listAt: 3.
			list selectIndex: 0.
			list select: (list entryNamed: 'interpreter.c').
			Time millisecondClockValue - t0])].
	viewer := browser viewer.
	self assert: viewer lineCount > 10000.
	self runsOnTheDefaultJit ifTrue: [self assert: ms < 1000 description: 'interpreter.c opened in ', ms printString, ' ms'].
	self in: window do: [viewer scrollOffset: viewer scrollTotal].
	self assert: viewer topLine > 12000.
	self assert: viewer remoteChildren size < 60.
	canvas := self in: window do: [ | c |
		c := Canvas extent: viewer extent scale: 2.
		c drawFresh: [viewer drawOn: c].
		c].
	self assert: canvas vertexCount < 50000 description: canvas vertexCount printString, ' vertices'
!
testColumnsScrollSideways
	| columns |
	columns := browser columns.
	self in: window do: [window bounds: (window bounds origin extent: 900 @ 500)].
	"Three columns and the preview: the preview at the right edge, the first column out of view."
	self reveal: 'src/Tools/FileBrowser.st'.
	self assert: columns scrollTotal > columns width.
	self assert: columns scrollOffset equals: columns scrollTotal - columns width.
	self assert: columns preview bounds right equals: columns width.
	self assert: (browser listAt: 1) bounds right <= 0.
	"Wider, then narrower again: the end stays in view."
	self in: window do: [window bounds: (window bounds origin extent: 1300 @ 500)].
	self in: window do: [window bounds: (window bounds origin extent: 900 @ 500)].
	self assert: columns preview bounds right equals: columns width.
	"Four columns: left, left brings the first back."
	self reveal: 'vm/platform/tests'.
	self assert: browser lists size equals: 4.
	self assert: columns scrollOffset > 0.
	self assert: self focused == (browser listAt: 3).
	self press: #left thenWaitFor: [self focused == (browser listAt: 2)].
	self press: #left thenWaitFor: [self focused == (browser listAt: 1)].
	self assert: (browser listAt: 1) bounds left equals: 0.
	self reveal: 'src'.
	self assert: columns scrollOffset equals: 0
!
testBinaryFileShowsAHexDump
	| path bytes lines |
	path := self scratchDirectory / 'blob.bin'.
	bytes := ByteArray new: 2000.
	1 to: bytes size do: [:i | bytes at: i put: i \\ 256].
	bytes at: 1 put: 16r89; at: 2 put: $P value; at: 3 put: $N value; at: 4 put: $G value.
	File writeBytes: bytes to: path.
	self reveal: path.
	self assert: browser root equals: self scratchDirectory.
	lines := browser viewer text lines.
	self assert: lines first equals: '00000000  89 50 4e 47 05 06 07 08  09 0a 0b 0c 0d 0e 0f 10  |.PNG............|'.
	self assert: lines size equals: 65.
	self assert: lines last equals: '…'.
	self assert: browser header rightText equals: 'binary · 1 KB · first KB shown'.
	self assert: browser viewer tokens isEmpty
!
testRemoteNames
	| text |
	self revealCFixture.
	text := (RemoteSnapshot root: world refTable: RemoteRefTable new) renderDepth: 6 bounds: false maxItems: 3000.
	#('.path ' '.path.vm ' '.path.gen ' '.column-1 ' '.column-1.vm ' '.column-2.gen ' '.column-3.preview-c ' '.file ' '.viewer ' '.info ') do: [:s |
		self assert: (text includesSubstring: s) description: 'snapshot lacks ', s].
	self assert: (text includesSubstring: '"preview.c" lines=3 selected').
	self assert: (text includesSubstring: '"vm" dir selected').
	self assert: (text includesSubstring: 'top=1').
	self assert: (text includesSubstring: '| /* Preview fixture */')
!
testRetainedDrawing
	| mismatch |
	View verifyDrawing: true.
	[self in: window do: [window bounds: (window bounds origin extent: 900 @ 500)].
	 self reveal: 'vm/gen/interpreter.c'.
	 self in: window do: [browser viewer scrollOffset: 4000; selectFrom: 9000 to: 9400].
	 self moveTo: (self pointOfSegment: 2).
	 self settle.
	 self assert: View staleDrawings isEmpty description: View staleDrawings size printString, ' stale replays'.
	 mismatch := window retainedDrawingMismatchAfter: [browser columns scrollOffset: 0].
	 self assert: mismatch isNil description: mismatch printString.
	 mismatch := window retainedDrawingMismatchAfter: [browser leave: (browser listAt: 3)].
	 self assert: mismatch isNil description: mismatch printString]
		ensure: [View verifyDrawing: false]
! !
