| check root sub old new target name bytes buf h st weak pressure keep stats names denied |
check := [:ok :why | ok ifFalse: [
	Smalltalk vm stderrWrite: why, (String with: Character lf).
	Smalltalk quit: 1]].
#('baseline' 'opt') do: [:mode |
	check value: (thisContext tryPrimitive: 180 receiver: Smalltalk vm args: {{mode. nil. 0. 0}}) == #primitiveFailed
		value: 'image enabled the JIT'].
root := Smalltalk vm getenv: 'SAMALTAK_C4_SCRATCH'.
check value: Directory current notEmpty value: 'cwd failed'.
names := Smalltalk vm primitiveNames.
check value: ((names at: 500) = 'fileOpen' and: [(names at: 511) = 'dirEntries'])
	value: 'file capability missing'.
check value: (#('windowOpen' 'gpuCreateDevice' 'socketListen' 'spawnProcess' 'mkfifo' 'machineAllocate')
	noneSatisfy: [:n | names includes: n]) value: 'unexpected platform capability'.
denied := File join: root with: 'must-not-exist'.
File class compile: 'c4PlatformTestMkfifo: path
	<primitive: 514>
	^#denied'.
check value: (File c4PlatformTestMkfifo: denied) == #denied value: 'numeric dispatch ran mkfifo'.
check value: (thisContext tryPrimitive: 514 receiver: File args: {denied}) == #primitiveFailed
	value: 'tryPrimitive ran mkfifo'.
check value: (File exists: denied) not value: 'mkfifo left a side effect'.
check value: (File primOpen: (File join: root with: 'host-fifo') mode: 0) isNil
	value: 'opened nonregular file'.
check value: (File lastError includesSubstring: 'host-fifo') value: 'missing platform error'.

sub := File join: root with: 'files'.
Directory create: sub.
check value: (Directory exists: sub) value: 'mkdir/stat failed'.
old := File join: sub with: 'before'.
bytes := ByteArray new: 257.
1 to: bytes size do: [:i | bytes at: i put: i \\ 251].
bytes at: 1 put: 65; at: 2 put: 0; at: 3 put: 0; at: 4 put: 0.
File writeBytes: bytes to: old.
check value: (File readBytes: old) = bytes value: 'FileStream failed'.
name := 'after-', (String with: (Character value: 955)).
target := File join: sub with: name.
new := 'forwarded-path' copy.
new becomeForward: target.
target := nil.
File rename: old to: new.
check value: (File exists: old) not value: 'rename left old file'.

weak := WeakArray new: 1.
weak at: 1 put: (ByteArray new: 2097153).
pressure := ByteArray new: 3145731.
keep := Array new: 30000.
buf := ByteArray new: 260.
buf at: 1 put: 254; at: 260 put: 255.
h := File primOpen: new mode: 1.
check value: h notNil value: 'open of forwarded wide path failed'.
check value: (File primClose: h + (1 bitShift: 32)) isNil value: 'handle narrowing'.
check value: (File primRead: h into: buf startingAt: 16r7FFFFFFFFFFFFFFF count: 16r7FFFFFFFFFFFFFFF) isNil
	value: 'out-of-bounds range accepted'.
check value: (File primRead: h into: 'literal' startingAt: 1 count: 1) isNil
	value: 'immutable buffer accepted'.
check value: (thisContext tryPrimitive: 504 receiver: File args: {h}) = 257 value: 'tryPrimitive size failed'.

1 to: 36 do: [:i |
	| forwardedBuffer |
	forwardedBuffer := 'ignored' copy.
	"Borrow the word buffer of the canonical WideString, not the source bytes."
	forwardedBuffer becomeForward: (WideString new: 1).
	check value: (File primSeek: h to: 0) notNil value: 'seek failed'.
	check value: (File primRead: h into: forwardedBuffer startingAt: 1 count: 4) = 4 value: 'forwarded read failed'.
	check value: (forwardedBuffer first = $A)
		value: 'forwarded read data'.
	check value: (File primRead: h into: buf startingAt: 2 count: 253) = 253 value: 'read failed'.
	check value: ((buf at: 1) = 254 and: [(buf at: 260) = 255 and: [(buf at: 2) = (bytes at: 5)
		and: [(buf at: 254) = bytes last]]]) value: 'offset copy failed'.
	check value: (File primPosition: h) = 257 value: 'position incorrect'.
	check value: (File primRead: h into: buf startingAt: 2 count: 8) = 0 value: 'EOF failed'.
	check value: (File primSeek: h to: 4) notNil value: 'seek before write failed'.
	check value: (File primWrite: h from: buf startingAt: 2 count: 253) = 253 value: 'write failed'.
	st := File stat: new.
	check value: (st first and: [st second not and: [st third = 257 and: [st fourth > 0]]]) value: 'stat failed'.
	check value: (Directory entries: sub) = {name} value: 'dirEntries failed'.
	ByteArray new: 1048579.
	1 to: 1500 do: [:j | | point |
		point := i@j.
		(j \\ 50) = 0 ifTrue: [keep at: j put: point]]].
check value: (File primFlush: h) notNil value: 'flush failed'.
check value: (File primClose: h) notNil value: 'close failed'.
check value: (File readBytes: new) = bytes value: 'final file content failed'.
(Delay forMilliseconds: 200) wait.
check value: (weak at: 1) isNil value: 'weak referent not cleared'.
check value: ((pressure size = 3145731) and: [(keep at: 1500) = (36@1500)]) value: 'lost live roots'.
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0 and: [(stats at: 15) = 0 and: [(stats at: 20) = 0]]])
	value: 'legacy GC or JIT touched C4 file run'.
File delete: new.
File delete: sub.
check value: (Directory exists: sub) not value: 'delete failed'.
Smalltalk vm stdoutWrite: 'C4 platform files ok', (String with: Character lf).
Smalltalk quit: 0
