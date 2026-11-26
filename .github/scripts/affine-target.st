"The two at: sends have independent loop-invariant dynamic offsets, as in
 JitOptRuntimeTest>>testAffineCountedLoopBounds. No setup or disassembly is timed."!

Object subclass: #AffineBoundsBench
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AffineBoundsBench'!

!AffineBoundsBench methodsFor: 'kernels'!
checksum: x at: i0 with: y at: j0 count: n
	| sum |
	sum := 0.
	1 to: n do: [:i |
		sum := sum + (x at: i0 + i - 1) + (y at: j0 + i - 1)].
	^sum
!
checksumTagged: x to: n
	| sum |
	sum := 0.
	1 to: n do: [:i | sum := sum + (x at: i)].
	^sum
! !

!AffineBoundsBench methodsFor: 'benchmarking'!
runAffine: laps
	| vm x y before start elapsed result |
	vm := Smalltalk vm.
	x := ByteArray new: 12004.
	y := ByteArray new: 12008.
	1 to: x size do: [:i | x at: i put: i \\ 251].
	1 to: y size do: [:i | y at: i put: (3 * i + 11) \\ 253].
	before := vm statistics.
	1 to: laps do: [:lap |
		start := vm threadCpuMicroseconds.
		512 timesRepeat: [
			result := self checksum: x at: 5 with: y at: 9 count: 12000.
			result = 3006848 ifFalse: [self error: 'AffineByteScan checksum mismatch']].
		elapsed := vm threadCpuMicroseconds - start.
		self printLap: 'AffineByteScan' lap: lap us: elapsed checksum: result].
	self printStats: 'AffineByteScan' delta: vm statistics - before
!
runArray: laps
	| vm x before start elapsed result |
	vm := Smalltalk vm.
	x := (1 to: 20000) asArray.
	before := vm statistics.
	1 to: laps do: [:lap |
		start := vm threadCpuMicroseconds.
		512 timesRepeat: [
			result := self checksumTagged: x to: 20000.
			result = 200010000 ifFalse: [self error: 'EPtrArrayScan checksum mismatch']].
		elapsed := vm threadCpuMicroseconds - start.
		self printLap: 'EPtrArrayScan' lap: lap us: elapsed checksum: result].
	self printStats: 'EPtrArrayScan' delta: vm statistics - before
!
printLap: name lap: lap us: elapsed checksum: result
	Transcript show: name, ',', lap printString, ',', elapsed printString, ',', result printString; cr
!
printStats: name delta: delta
	Transcript show: '# stats ', name, ' optMethodsCompiled=', delta optMethodsCompiled printString,
		' optOsrEntries=', delta optOsrEntries printString,
		' optDeoptimizations=', delta optDeoptimizations printString; cr
!
printListing: selector of: name
	Transcript show: '# listing ', name; cr.
	Transcript show: ((self class >> selector) machineCodeFor: #opt); cr.
	Transcript show: '# end listing ', name; cr
! !
