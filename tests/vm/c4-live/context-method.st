| heapBase replacement |
Processor stopTimeSlicer.
heapBase := [
	(thisContext == heapBase and: [heapBase method ~~ replacement]) ifFalse: [Smalltalk quit: 2].
	Smalltalk vm stdoutWrite: 'running in heap base', (String with: Character lf).
	heapBase method: replacement.
	heapBase method == replacement ifFalse: [Smalltalk quit: 3].
	Smalltalk quit: 0] asContext.
replacement := heapBase method shallowCopy.
(Process forContext: heapBase priority: Processor activeProcess priority + 1) resume.
Smalltalk quit: 2
