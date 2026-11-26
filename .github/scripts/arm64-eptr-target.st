"The kernel and input match JitOptRuntimeTest>>testUncheckedPointerLoadAddressing."!

Object subclass: #EPtrArrayScan
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'EPtrArrayScan'!

!EPtrArrayScan methodsFor: 'benchmarking'!
checksumTagged: x to: n
	| s |
	s := 0.
	1 to: n do: [:i | s := s + (x at: i)].
	^s
!
run: laps
	| vm x before start elapsed result delta |
	vm := Smalltalk vm.
	x := (1 to: 20000) asArray.
	before := vm statistics.
	1 to: laps do: [:lap |
		start := vm threadCpuMicroseconds.
		512 timesRepeat: [
			result := self checksumTagged: x to: 20000.
			result = 200010000 ifFalse: [self error: 'Array scan checksum mismatch']].
		elapsed := vm threadCpuMicroseconds - start.
		Transcript show: 'EPtrArrayScan,', lap printString, ',', elapsed printString, ',', result printString; cr].
	delta := vm statistics - before.
	Transcript show: '# stats EPtrArrayScan optMethodsCompiled=', delta optMethodsCompiled printString,
		' optOsrEntries=', delta optOsrEntries printString,
		' optDeoptimizations=', delta optDeoptimizations printString; cr.
	Transcript show: '# listing EPtrArrayScan'; cr.
	Transcript show: ((self class >> #checksumTagged:to:) machineCodeFor: #opt); cr.
	Transcript show: '# end listing EPtrArrayScan'; cr
! !
