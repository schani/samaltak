| heapBase replacement |
Processor stopTimeSlicer.
heapBase := [
	thisContext == heapBase ifFalse: [Smalltalk quit: 3].
	"Try the primitive before any activation that might suspend this context."
	heapBase instVarAt: 4 put: replacement.
	heapBase method == replacement ifFalse: [Smalltalk quit: 4].
	Smalltalk vm stdoutWrite: 'active Context method written', String lf.
	Smalltalk quit: 0] asContext.
replacement := heapBase method shallowCopy.
(Process forContext: heapBase priority: Processor activeProcess priority + 1) resume.
Smalltalk quit: 3
