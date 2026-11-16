OptModule subclass: #OptIR
	instanceVariableNames: 'optNodes optNodeCount optBlocks optBlockCount optEdges optEdgeCount optOperands optOperandCount optStates optStateCount optActs optActCount optFull optCurAct optCurPc optOsrEntry optOsrState optOsrNumbers optOsrFloats'
	classVariableNames: ''
	package: 'VM-Jit'!

OptIR comment: 'The optimizing tier''s IR (OptModule): nodes, blocks, predecessor edges, the operand array (phi inputs, send arguments, frame state values), frame states and inlined activations, all in fixed arrays reset for each compilation. A node belongs to a block''s doubly linked list; a block ends with a control node (O_GOTO, O_BRANCH, O_RETURN, O_DEOPT). Running out of room sets full: the compilation is abandoned.'!

!OptIR class methodsFor: 'declaring'!
declarations
	^#((optNodes 'OptNode[OPT_MAX_NODES]') (optNodeCount int32_t)
		(optBlocks 'OptBlock[OPT_MAX_BLOCKS]') (optBlockCount int32_t)
		(optEdges 'OptEdge[OPT_MAX_EDGES]') (optEdgeCount int32_t)
		(optOperands 'int32_t[OPT_MAX_OPERANDS]') (optOperandCount int32_t)
		(optStates 'OptState[OPT_MAX_STATES]') (optStateCount int32_t)
		(optActs 'OptAct[OPT_MAX_ACTS]') (optActCount int32_t)
		(optFull bool) (optCurAct int32_t) (optCurPc int32_t) (optOsrEntry int32_t) (optOsrState int32_t) (optOsrNumbers uint64_t) (optOsrFloats uint64_t))
! !

!OptIR methodsFor: 'accessing'!
node: n
	^optNodes + n
!
block: b
	^optBlocks + b
!
edge: e
	^optEdges + e
!
state: s
	^optStates + s
!
act: a
	^optActs + a
!
operand: i
	^optOperands at: i
!
operand: i put: v
	optOperands at: i put: v
!
operands
	^optOperands
!
nodeCount
	^optNodeCount
!
blockCount
	^optBlockCount
!
stateCount
	^optStateCount
!
actCount
	^optActCount
!
full
	^optFull
!
fail
	optFull := true
!
originPc
	^optCurPc
!
originAct
	^optCurAct
!
origin: a pc: pc
	"New nodes come from the instruction at a's pc."
	optCurAct := a.
	optCurPc := pc
!
osrEntry
	"A loop unit's entry block (its parameters are the frame's slots at the loop head), -1 for other units."
	^optOsrEntry
!
osrState
	"The frame state at the loop head in the entry block, where a guard there deoptimizes to."
	^optOsrState
!
osrNumbers
	"Bit i: the frame's slot i held a number when the loop unit was compiled."
	^optOsrNumbers
!
osrFloats
	"Bit i: the frame's slot i held a SmallFloat64 when the loop unit was compiled."
	^optOsrFloats
!
osrEntry: b state: s numbers: bits
	optOsrEntry := b.
	optOsrState := s.
	optOsrNumbers := bits
!
osrFloats: bits
	optOsrFloats := bits
! !

!OptIR methodsFor: 'building'!
reset
	<function>
	optNodeCount := 0.
	optBlockCount := 0.
	optEdgeCount := 0.
	optOperandCount := 0.
	optStateCount := 0.
	optActCount := 0.
	optFull := false.
	optCurAct := 0.
	optCurPc := 0.
	optOsrEntry := -1.
	optOsrState := -1.
	optOsrNumbers := 0.
	optOsrFloats := 0
!
newBlock
	"A new empty block."
	<function>
	| b |
	optBlockCount >= OPT_MAX_BLOCKS ifTrue: [
		optFull := true.
		^0].
	b := optBlocks + optBlockCount.
	libc memset: b value: 0 size: (self sizeof: 'OptBlock').
	b first: -1.
	b last: -1.
	b preds: -1.
	b succ0: -1.
	b succ1: -1.
	b idom: -1.
	b loop: -1.
	b act: -1.
	b label: -1.
	b entryState: -1.
	optBlockCount := optBlockCount + 1.
	^optBlockCount - 1
!
newNode: op rep: rep
	"A new node, in no block."
	<function>
	| n |
	optNodeCount >= OPT_MAX_NODES ifTrue: [
		optFull := true.
		^0].
	n := optNodes + optNodeCount.
	libc memset: n value: 0 size: (self sizeof: 'OptNode').
	n op: op asUInt16.
	n rep: rep asUInt8.
	n block: -1.
	n next: -1.
	n prev: -1.
	n a: -1.
	n b: -1.
	n c: -1.
	n args: -1.
	n state: -1.
	n fwd: -1.
	n reg: -1.
	n slot: -1.
	n lo: VM_INT_MIN.
	n hi: VM_INT_MAX.
	n bcact: optCurAct.
	n bcpc: optCurPc.
	optNodeCount := optNodeCount + 1.
	^optNodeCount - 1
!
append: n to: b
	"n becomes b's last node."
	<function>
	| bl nd |
	bl := optBlocks + b.
	nd := optNodes + n.
	nd block: b.
	nd prev: bl last.
	nd next: -1.
	bl last >= 0
		ifTrue: [(optNodes + bl last) next: n]
		ifFalse: [bl first: n].
	bl last: n
!
prepend: n to: b
	"n becomes b's first node (phis)."
	<function>
	| bl nd |
	bl := optBlocks + b.
	nd := optNodes + n.
	nd block: b.
	nd next: bl first.
	nd prev: -1.
	bl first >= 0
		ifTrue: [(optNodes + bl first) prev: n]
		ifFalse: [bl last: n].
	bl first: n
!
insert: n before: m
	<function>
	| nd md |
	md := optNodes + m.
	nd := optNodes + n.
	nd block: md block.
	nd next: m.
	nd prev: md prev.
	md prev >= 0
		ifTrue: [(optNodes + md prev) next: n]
		ifFalse: [(optBlocks + md block) first: n].
	md prev: n
!
unlink: n
	"Take n out of its block."
	<function>
	| nd bl |
	nd := optNodes + n.
	nd block < 0 ifTrue: [^self].
	bl := optBlocks + nd block.
	nd prev >= 0
		ifTrue: [(optNodes + nd prev) next: nd next]
		ifFalse: [bl first: nd next].
	nd next >= 0
		ifTrue: [(optNodes + nd next) prev: nd prev]
		ifFalse: [bl last: nd prev].
	nd block: -1.
	nd next: -1.
	nd prev: -1
!
addPred: from to: to
	"from becomes to's last predecessor; answer its index."
	<function>
	<returns: 'int32_t'>
	| e b p i |
	optEdgeCount >= OPT_MAX_EDGES ifTrue: [
		optFull := true.
		^0].
	e := optEdges + optEdgeCount.
	e from: from.
	e next: -1.
	b := optBlocks + to.
	i := 0.
	b preds < 0
		ifTrue: [b preds: optEdgeCount]
		ifFalse: [
			p := b preds.
			i := 1.
			[(optEdges + p) next >= 0] whileTrue: [
				p := (optEdges + p) next.
				i := i + 1].
			(optEdges + p) next: optEdgeCount].
	b npreds: b npreds + 1.
	optEdgeCount := optEdgeCount + 1.
	^i
!
pred: i of: b
	"The block of b's i-th predecessor edge."
	<function>
	| p |
	p := (optBlocks + b) preds.
	i timesRepeat: [p := (optEdges + p) next].
	^(optEdges + p) from
!
replacePred: old with: new in: b
	"Every edge from old into b now comes from new."
	<function>
	| p |
	p := (optBlocks + b) preds.
	[p >= 0] whileTrue: [
		(optEdges + p) from = old ifTrue: [(optEdges + p) from: new].
		p := (optEdges + p) next]
!
allocOperands: n
	"Room for n operands; answer the first index."
	<function>
	| i |
	optOperandCount + n > OPT_MAX_OPERANDS ifTrue: [
		optFull := true.
		^0].
	i := optOperandCount.
	optOperandCount := optOperandCount + n.
	0 to: n - 1 do: [:k | optOperands at: i + k put: -1].
	^i
!
newState
	<function>
	| s |
	optStateCount >= OPT_MAX_STATES ifTrue: [
		optFull := true.
		^0].
	s := optStates + optStateCount.
	libc memset: s value: 0 size: (self sizeof: 'OptState').
	s parent: -1.
	s vals: -1.
	optStateCount := optStateCount + 1.
	^optStateCount - 1
!
newAct
	"-1 when the table is full: act 0 is the root, a parent pointing to it from below would make a cycle."
	<function>
	| a |
	optActCount >= OPT_MAX_ACTS ifTrue: [
		optFull := true.
		^-1].
	a := optActs + optActCount.
	libc memset: a value: 0 size: (self sizeof: 'OptAct').
	a parent: -1.
	a outer: -1.
	a closure: -1.
	a receiver: -1.
	a retBlock: -1.
	a home: -1.
	optActCount := optActCount + 1.
	^optActCount - 1
! !

!OptIR methodsFor: 'queries'!
resolve: n
	"n, or what replaced it."
	<function>
	| m |
	n < 0 ifTrue: [^n].
	m := n.
	[(optNodes + m) fwd >= 0] whileTrue: [m := (optNodes + m) fwd].
	^m
!
isControl: op
	^op >= O_GOTO
!
opOf: n
	^(optNodes + n) op asInt32
!
argAt: i of: n
	^optOperands at: (optNodes + n) args + i
! !

!OptIR methodsFor: 'printing'!
print
	"The IR on stderr (SAMALTAK_OPT_TRACE)."
	<function>
	| bl n nd e |
	0 to: optBlockCount - 1 do: [:b |
		bl := optBlocks + b.
		libc fprintf: libc stderr format: 'B%d (act %d pc %d flags %d) preds:' with: b with: bl act with: bl pc with: bl flags.
		e := bl preds.
		[e >= 0] whileTrue: [
			libc fprintf: libc stderr format: ' B%d' with: (optEdges + e) from.
			e := (optEdges + e) next].
		libc fprintf: libc stderr format: ' succ: %d %d' with: bl succ0 with: bl succ1.
		libc fputc: 10 to: libc stderr.
		n := bl first.
		[n >= 0] whileTrue: [
			nd := optNodes + n.
			self printNode: n.
			n := nd next]]
!
printNode: n
	<function>
	| nd |
	nd := optNodes + n.
	libc fprintf: libc stderr format: '  v%d = op%d' with: n with: nd op asInt32.
	libc fprintf: libc stderr format: ' rep%d t%d' with: nd rep asInt32 with: nd tkind asInt32.
	nd a >= 0 ifTrue: [libc fprintf: libc stderr format: ' a=v%d' with: nd a].
	nd b >= 0 ifTrue: [libc fprintf: libc stderr format: ' b=v%d' with: nd b].
	nd c >= 0 ifTrue: [libc fprintf: libc stderr format: ' c=v%d' with: nd c].
	nd nargs > 0 ifTrue: [
		libc fputs: ' [' to: libc stderr.
		0 to: nd nargs asInt32 - 1 do: [:i | libc fprintf: libc stderr format: ' v%d' with: (optOperands at: nd args + i)].
		libc fputs: ' ]' to: libc stderr].
	libc fprintf: libc stderr format: ' aux=%lld' with: nd aux.
	nd state >= 0 ifTrue: [libc fprintf: libc stderr format: ' st=%d' with: nd state].
	nd reg >= 0 ifTrue: [libc fprintf: libc stderr format: ' r%d' with: nd reg asInt32].
	nd slot >= 0 ifTrue: [libc fprintf: libc stderr format: ' s%d' with: nd slot asInt32].
	libc fprintf: libc stderr format: ' [%d,%d]' with: nd lstart with: nd lend.
	libc fputc: 10 to: libc stderr
! !

VMStruct subclass: #OptNode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptNode comment: 'An IR node (OptModule): opcode, result representation, type kind and flags; its block and neighbours there; fixed operands a b c and nargs operands from args in the operand array; a frame state; aux and aux2 (constants, field indices, selectors, sites); tcls (an exact class it is known to have, or 0); fwd (what replaces it, -1); uses; the integer range lo..hi; register allocation (reg, slot, the live interval lstart..lend, pos).'!

!OptNode class methodsFor: 'declaring'!
fields
	^#((op uint16_t) (rep uint8_t) (tkind uint8_t) (flags uint16_t) (nargs uint16_t)
		(block int32_t) (next int32_t) (prev int32_t)
		(a int32_t) (b int32_t) (c int32_t) (args int32_t) (state int32_t) (fwd int32_t) (uses int32_t)
		(aux int64_t) (aux2 int64_t) (tcls uint64_t) (lo int64_t) (hi int64_t)
		(reg int16_t) (slot int16_t) (pos int32_t) (lstart int32_t) (lend int32_t) (live int32_t) (nlive int32_t) (bcact int32_t) (bcpc int32_t))
! !

VMStruct subclass: #OptBlock
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptBlock comment: 'An IR block (OptModule): its first and last node, predecessor edges (preds, a list of OptEdges, npreds of them), up to two successors (succ0 the taken or only one, succ1 the other of a branch), flags, the activation and pc it starts, its order, immediate dominator, innermost loop header, loop depth, linear positions from..to, its code label and, if it heads a loop, its frame state at the head.'!

!OptBlock class methodsFor: 'declaring'!
fields
	^#((first int32_t) (last int32_t) (preds int32_t) (npreds int32_t) (succ0 int32_t) (succ1 int32_t)
		(flags int32_t) (act int32_t) (pc int32_t) (rpo int32_t) (idom int32_t) (loop int32_t) (depth int32_t)
		(from int32_t) (to int32_t) (label int32_t) (live int32_t) (loopEnd int32_t) (entryState int32_t))
! !

VMStruct subclass: #OptEdge
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptEdge comment: 'A predecessor edge: the block it comes from, the next edge into the same block (-1).'!

!OptEdge class methodsFor: 'declaring'!
fields
	^#((from int32_t) (next int32_t))
! !

VMStruct subclass: #OptState
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptState comment: 'A frame state (OptModule): what deoptimization rebuilds for one activation, with its caller''s state as parent (-1 for the outermost). act: the activation (method, closure, receiver); pc: where it continues; depth: its slots (arguments, temps, stack), whose values are the operands vals + 1 .. vals + depth (vals + 0: the receiver).'!

!OptState class methodsFor: 'declaring'!
fields
	^#((parent int32_t) (act int32_t) (pc int32_t) (depth int32_t) (vals int32_t) (flags int32_t))
! !

VMStruct subclass: #OptAct
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

OptAct comment: 'An activation in a compilation (OptModule): the outermost method''s, or one inlined into it (a method sent, or a block evaluated). method (a block''s home method); parent: the activation that sent or evaluated it; outer: a block''s defining activation, home: its method activation (where ^ returns from); closure and receiver: their values; varBase: its first SSA variable (one per slot); nslots, numArgs, numTemps; startpc..endpc: its bytecodes; ana: its method''s analysis in the builder''s arena; pcb: its pc-to-block map there; retBlock: where its returns go (inlined), result in variable retVar; sendPc, sendArgc: the call in its parent.'!

!OptAct class methodsFor: 'declaring'!
fields
	^#((method oop) (parent int32_t) (outer int32_t) (home int32_t) (closure int32_t) (receiver int32_t)
		(varBase int32_t) (nslots int32_t) (numArgs int32_t) (numTemps int32_t) (startpc int32_t) (endpc int32_t)
		(ana int32_t) (pcb int32_t) (retBlock int32_t) (retVar int32_t) (sendPc int32_t) (sendArgc int32_t) (depth int32_t) (rcvClass uint64_t))
! !
