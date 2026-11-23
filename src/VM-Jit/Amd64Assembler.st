JitAssembler subclass: #Amd64Assembler
	instanceVariableNames: 'asmStart asmPc asmLimit asmError asmLabelCount asmLabels asmLabelFixups asmFixupCount asmFixupSites asmFixupNext asmUnresolved asmBinds asmBoundPc asmNoting asmNoteCount asmNoteOffsets asmNoteTexts asmNoteArgs asmFlags asmState asmRegs asmLabelFlags asmFlagsLabel asmJumpEnd asmR11Reg asmR11Pc'
	classVariableNames: 'ASM_MAX_FIXUPS ASM_MAX_LABELS ASM_MAX_NOTES X64_FL_ADD X64_FL_BT X64_FL_CLOBBERED X64_FL_FP X64_FL_LOGIC X64_FL_MUL X64_FL_NONE X64_FL_SUB X64_FL_UNSEEN X64_FL_READ X64_K_FP X64_K_LR X64_K_MEM X64_K_PHYS X64_K_SP X64_K_STATE X64_K_STATEMEM X64_K_ZERO X64_ARM_HI X64_ARM_LO X64_MAP_HI X64_MAP_LO X64_NONE X64_PHYS X64_R10 X64_R11 X64_R12 X64_R13 X64_R14 X64_R15 X64_R8 X64_R9 X64_RAX X64_RBP X64_RBX X64_RCX X64_RDI X64_RDX X64_RIP X64_RSI X64_RSP'
	package: 'VM-Jit'!

Amd64Assembler comment: 'I write x86-64 code: the instructions of Arm64Assembler, with its registers (Arm64Module), each as the x86-64 instructions that do what it does, so that the code generators (JitAssembler) emit for either CPU; isX64 tells them which one they write for, where they want code of x86''s own.

Registers. x0-x5 are rdi rsi rdx rcx r8 r9 (the C argument registers, in order), x9 rax, x10 r14, x11 r15, x16 r10, x17 r12, x19 rbp, x20 rbx, x21 r13, d0-d15 xmm0-xmm15; r11 is mine (each instruction''s scratch) and rsp is sp. x22 is the JitState (setState:): its loads and stores are pc-relative, and x23-x25 (nil, true, false) are its words, read where they are used. x29 and x30 have no register: call pushes the return address, so the native frame record is that word (8 bytes per activation), and stp/ldp/str/ldr of x29 or x30 with sp drop them. Any other register (x6-x8, x12-x15, x18, x26-x28) is a word of asmRegs, a register file in memory: correct, slower; asmRegs[31] stays 0 (a 0.0 to compare with).

Flags. x86 instructions set flags where arm64 ones do not; I track the kind of the last instruction that set them (sub, add, logical, floating point compare, multiply), map each condition to the x86 condition (the carry of a subtraction is inverted; a floating point compare needs the parity flag for an unordered result) and fail with ASM_ERR_FLAGS if code of mine changed the flags since and an instruction reads them, so that a code generator relying on arm64''s flags fails to compile rather than run wrong. A label forgets the kind: a condition that depends on it must follow its compare.

Labels and patching are as Arm64Assembler''s: a fixup is the address of a 32-bit displacement that ends its instruction (jmp, jcc, call, lea and mov from [rip]); patchBranchAt:to: points one at a target (the runtime relinks calls by their displacement: 4 bytes before the return address), mov:imm64: is movabs (its constant 2 bytes in).'!

!Amd64Assembler class methodsFor: 'declaring'!
targetArch
	^#x86_64
!
declarations
	^#((asmStart uint64_t) (asmPc uint64_t) (asmLimit uint64_t) (asmError int32_t) (asmLabelCount int32_t) (asmLabels 'uint64_t[ASM_MAX_LABELS]') (asmLabelFixups 'int32_t[ASM_MAX_LABELS]') (asmFixupCount int32_t) (asmFixupSites 'uint64_t[ASM_MAX_FIXUPS]') (asmFixupNext 'int32_t[ASM_MAX_FIXUPS]') (asmUnresolved int32_t) (asmBinds int32_t) (asmBoundPc uint64_t) (asmNoting bool) (asmNoteCount int32_t) (asmNoteOffsets 'uint32_t[ASM_MAX_NOTES]') (asmNoteTexts 'const char *[ASM_MAX_NOTES]') (asmNoteArgs 'int64_t[ASM_MAX_NOTES]')
		(asmFlags int32_t) (asmState uint64_t) (asmRegs 'uint64_t[32]') (asmLabelFlags 'uint8_t[ASM_MAX_LABELS]') (asmFlagsLabel int32_t) (asmJumpEnd uint64_t) (asmR11Reg int64_t) (asmR11Pc uint64_t))
!
initialize
	| map phys pairs inverse |
	ASM_MAX_LABELS := 16384.
	ASM_MAX_FIXUPS := 65536.
	ASM_MAX_NOTES := 8192.
	X64_RAX := 0. X64_RCX := 1. X64_RDX := 2. X64_RBX := 3. X64_RSP := 4. X64_RBP := 5. X64_RSI := 6. X64_RDI := 7.
	X64_R8 := 8. X64_R9 := 9. X64_R10 := 10. X64_R11 := 11. X64_R12 := 12. X64_R13 := 13. X64_R14 := 14. X64_R15 := 15.
	"in a memory operand: pc-relative, and no index"
	X64_RIP := 16.
	X64_NONE := 17.
	"arm64 register -> x86 register, 4 bits each (X64_MAP_LO x0-x15, X64_MAP_HI x16-x31); X64_PHYS: the arm64 registers that have one"
	pairs := #(0 7 1 6 2 2 3 1 4 8 5 9 9 0 10 14 11 15 16 10 17 12 19 5 20 3 21 13).
	map := Array new: 32 withAll: 0.
	phys := 0.
	1 to: pairs size by: 2 do: [:i |
		map at: (pairs at: i) + 1 put: (pairs at: i + 1).
		phys := phys bitOr: 1 << (pairs at: i)].
	X64_MAP_LO := 0.
	X64_MAP_HI := 0.
	0 to: 15 do: [:i |
		X64_MAP_LO := X64_MAP_LO bitOr: (map at: i + 1) << (4 * i).
		X64_MAP_HI := X64_MAP_HI bitOr: (map at: i + 17) << (4 * i)].
	X64_PHYS := phys.
	"x86 register -> arm64 register, a byte each (X64_ARM_LO rax-rdi, X64_ARM_HI r8-r15), 255 if none (rsp, r11)"
	inverse := Array new: 16 withAll: 255.
	1 to: pairs size by: 2 do: [:i | inverse at: (pairs at: i + 1) + 1 put: (pairs at: i)].
	X64_ARM_LO := 0.
	X64_ARM_HI := 0.
	0 to: 7 do: [:i |
		X64_ARM_LO := X64_ARM_LO bitOr: (inverse at: i + 1) << (8 * i).
		X64_ARM_HI := X64_ARM_HI bitOr: (inverse at: i + 9) << (8 * i)].
	"what an arm64 register is here"
	X64_K_PHYS := 0. X64_K_MEM := 1. X64_K_STATE := 2. X64_K_STATEMEM := 3. X64_K_ZERO := 4. X64_K_SP := 5. X64_K_FP := 6. X64_K_LR := 7.
	"what set the flags last"
	X64_FL_NONE := 0. X64_FL_SUB := 1. X64_FL_ADD := 2. X64_FL_LOGIC := 3. X64_FL_FP := 4. X64_FL_CLOBBERED := 5. X64_FL_MUL := 6. X64_FL_BT := 7.
	"a label's flags (asmLabelFlags): no branch to it yet; the flags were read after it"
	X64_FL_UNSEEN := 15.
	X64_FL_READ := 16
! !

!Amd64Assembler methodsFor: 'buffer'!
beginAt: start limit: limit
	"Assemble into [start, limit); forget all labels."
	<export>
	asmStart := start.
	asmPc := start.
	asmLimit := limit.
	asmError := ASM_OK.
	asmLabelCount := 0.
	asmFixupCount := 0.
	asmUnresolved := 0.
	asmNoteCount := 0.
	asmFlags := X64_FL_NONE.
	asmFlagsLabel := -1.
	asmJumpEnd := 0.
	asmR11Pc := 0
!
finish
	"Answer the error code: ASM_OK unless something did not encode, the buffer filled up or a label used was not bound."
	<export>
	asmUnresolved > 0 ifTrue: [self fail: ASM_ERR_LABEL].
	^asmError
!
pc
	"The address of the next instruction."
	^asmPc
!
codeStart
	^asmStart
!
codeSize
	^asmPc - asmStart
!
errorCode
	^asmError
!
failed
	^asmError ~= ASM_OK
!
isOK: aCode
	^aCode = ASM_OK
!
isFull: aCode
	"aCode (finish's answer) says the buffer filled up."
	^aCode = ASM_ERR_FULL
!
fail: aCode
	asmError = ASM_OK ifTrue: [asmError := aCode]
!
isX64
	"The code generators emit x86-64 through me."
	^true
!
setState: anAddress
	"Where the JitState is (x22, and nil, true, false in it): the code reaches it pc-relative."
	<export>
	<var: #anAddress type: 'uint64_t'>
	asmState := anAddress
!
regsAddress
	"asmRegs: the arm64 registers that have no x86 register."
	^self cCoerce: asmRegs to: 'uint64_t'
!
emitBytes: v count: n
	"Append the n (1 to 8) low bytes of v (little-endian; the word is stored whole, the rest is overwritten by what follows)."
	asmPc + 8 <= asmLimit
		ifTrue: [
			self uint64At: asmPc put: v.
			asmPc := asmPc + n]
		ifFalse: [self fail: ASM_ERR_FULL]
!
emit: aWord
	"Append 4 bytes of data."
	self emitBytes: (aWord asUInt64 bitAnd: 16rFFFFFFFF) count: 4
!
emit64: aValue
	"Append 8 bytes of data (a literal for ldr:label:)."
	self emitBytes: aValue asUInt64 count: 8
!
alignTo: n
	"int3 up to a multiple of n (a power of 2) of the address: before data that wants it (not past a full buffer)."
	[(asmPc bitAnd: n - 1) ~= 0 and: [asmError = ASM_OK]] whileTrue: [self emitBytes: 16rCC count: 1]
! !

!Amd64Assembler methodsFor: 'labels'!
newLabel
	<export>
	asmLabelCount >= ASM_MAX_LABELS ifTrue: [
		self fail: ASM_ERR_LABEL.
		^0].
	asmLabels at: asmLabelCount put: 0.
	asmLabelFixups at: asmLabelCount put: -1.
	asmLabelFlags at: asmLabelCount put: X64_FL_UNSEEN.
	asmLabelCount := asmLabelCount + 1.
	^asmLabelCount - 1
!
labelsBound
	^asmBinds
!
boundPc
	"Where the label bound last is."
	^asmBoundPc
!
hasBranchesTo: aLabel
	"aLabel, not bound yet, has branches to it."
	^(asmLabelFixups at: aLabel) >= 0
!
labelAt: anAddress
	"A label bound to anAddress."
	<export>
	<var: #anAddress type: 'uint64_t'>
	| label |
	label := self newLabel.
	asmLabels at: label put: anAddress.
	^label
!
bind: aLabel
	"Bind aLabel to the next instruction and patch the displacements to it. The flags here are what the branches to it brought and, if control falls in, the code before: their kind if they agree."
	<export>
	<var: #aLabel type: 'int32_t'>
	| f k |
	asmLabels at: aLabel put: asmPc.
	asmBinds := asmBinds + 1.
	asmBoundPc := asmPc.
	asmR11Pc := 0.
	k := (asmLabelFlags at: aLabel) asInt32.
	asmPc ~= asmJumpEnd ifTrue: [k := self flags: k merge: asmFlags].
	asmFlags := k = X64_FL_UNSEEN ifTrue: [X64_FL_NONE] ifFalse: [k].
	asmLabelFlags at: aLabel put: asmFlags asUInt8.
	asmFlagsLabel := aLabel.
	f := asmLabelFixups at: aLabel.
	[f >= 0] whileTrue: [
		(asmFixupSites at: f) < asmPc ifTrue: [self patchBranchAt: (asmFixupSites at: f) to: asmPc].
		asmUnresolved := asmUnresolved - 1.
		f := asmFixupNext at: f].
	asmLabelFixups at: aLabel put: -1
!
addressOf: aLabel
	"The address aLabel is bound to, 0 if it is not bound yet."
	^asmLabels at: aLabel
!
targetOf: aLabel site: site
	"The address of aLabel for the 32-bit displacement at site (the end of its instruction); if aLabel is not bound yet, site + 4 (a displacement of 0), patched when it is bound."
	<export>
	<var: #site type: 'uint64_t'>
	| a |
	a := asmLabels at: aLabel.
	a ~= 0 ifTrue: [^a].
	asmFixupCount >= ASM_MAX_FIXUPS ifTrue: [
		self fail: ASM_ERR_LABEL.
		^site + 4].
	asmFixupSites at: asmFixupCount put: site.
	asmFixupNext at: asmFixupCount put: (asmLabelFixups at: aLabel).
	asmLabelFixups at: aLabel put: asmFixupCount.
	asmFixupCount := asmFixupCount + 1.
	asmUnresolved := asmUnresolved + 1.
	^site + 4
! !

!Amd64Assembler methodsFor: 'notes'!
recordNotes: aBoolean
	"Record comment: and bytecode: notes from now on (or not); forget those recorded."
	<export>
	<var: #aBoolean type: 'bool'>
	asmNoting := aBoolean.
	asmNoteCount := 0
!
comment: aString
	"Say what the code from pc on does."
	asmNoting ifTrue: [self note: aString value: 0]
!
comment: aFormat with: anInteger
	"A comment with an integer, formatted when the code is disassembled ('spill stack slot %d')."
	asmNoting ifTrue: [self note: aFormat value: anInteger]
!
bytecode: aPc
	"The code of the bytecode at aPc starts at pc."
	asmNoting ifTrue: [self note: self null value: aPc]
!
note: aString value: anInteger
	"Record (pc - start, aString, anInteger); aString is NULL for a bytecode."
	<export>
	<var: #aString type: 'const char *'>
	<var: #anInteger type: 'int64_t'>
	asmNoteCount < ASM_MAX_NOTES ifTrue: [
		asmNoteOffsets at: asmNoteCount put: (asmPc - asmStart) asUInt32.
		asmNoteTexts at: asmNoteCount put: aString.
		asmNoteArgs at: asmNoteCount put: anInteger.
		asmNoteCount := asmNoteCount + 1]
!
noteCount
	^asmNoteCount
!
noteOffsetAt: i
	^asmNoteOffsets at: i
!
noteTextAt: i
	^asmNoteTexts at: i
!
noteValueAt: i
	^asmNoteArgs at: i
! !

!Amd64Assembler methodsFor: 'registers'!
isW: r
	^(r bitAnd: REG_W) ~= 0
!
isD: r
	^(r bitAnd: REG_D) ~= 0
!
wide: r
	"The REX.W bit of an operation on r: 1 for an X register, 0 for a W register."
	^(r bitAnd: REG_W) = 0 ifTrue: [1] ifFalse: [0]
!
isPhys: r
	"r is a general register that has an x86 register (not sp, xzr, a D register or one in asmRegs)."
	^(r bitAnd: REG_SP + REG_D) = 0 and: [((X64_PHYS >> (r bitAnd: 31)) bitAnd: 1) = 1]
!
isBase: r
	"r has an x86 register to address memory with: its own, or rsp."
	^(self isPhys: r) or: [(r bitAnd: 31 + REG_SP + REG_D) = (31 + REG_SP)]
!
gpr: r
	"The x86 register of r (isBase: r)."
	^(r bitAnd: REG_SP) ~= 0
		ifTrue: [X64_RSP]
		ifFalse: [((((r bitAnd: 16) = 0 ifTrue: [X64_MAP_LO] ifFalse: [X64_MAP_HI]) >> (4 * (r bitAnd: 15))) bitAnd: 15) asInt32]
!
xmm: r
	"The xmm register of D register r."
	^r bitAnd: 15
!
kind: r
	"What arm64 register r is here (X64_K_...)."
	<export>
	<var: #r type: 'int64_t'>
	(r bitAnd: REG_D) ~= 0 ifTrue: [^X64_K_PHYS].
	(r bitAnd: 31 + REG_SP) = (31 + REG_SP) ifTrue: [^X64_K_SP].
	(r bitAnd: 31) = 31 ifTrue: [^X64_K_ZERO].
	((X64_PHYS >> (r bitAnd: 31)) bitAnd: 1) = 1 ifTrue: [^X64_K_PHYS].
	(r bitAnd: 31) = 22 ifTrue: [^X64_K_STATE].
	((r bitAnd: 31) between: 23 and: 25) ifTrue: [^X64_K_STATEMEM].
	(r bitAnd: 31) = 29 ifTrue: [^X64_K_FP].
	(r bitAnd: 31) = 30 ifTrue: [^X64_K_LR].
	^X64_K_MEM
!
hw: r
	"The x86 register of a general register that has one (or sp: rsp), or a D register's xmm."
	^(r bitAnd: REG_D) ~= 0 ifTrue: [r bitAnd: 15] ifFalse: [self gpr: r]
!
homeOf: r
	"The address of r's word: asmRegs for a register without an x86 one, the JitState's nil, true or false for x23-x25."
	<export>
	<var: #r type: 'int64_t'>
	<returns: 'uint64_t'>
	(r bitAnd: 31) = 23 ifTrue: [^asmState + (self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #nilOop) to: 'uint64_t')].
	(r bitAnd: 31) = 24 ifTrue: [^asmState + (self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #trueOop) to: 'uint64_t')].
	(r bitAnd: 31) = 25 ifTrue: [^asmState + (self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #falseOop) to: 'uint64_t')].
	^self regsAddress + (8 * (r bitAnd: 31)) asUInt64
!
isWord: r
	"r is a word in memory (asmRegs or the JitState's nil, true, false)."
	| k |
	k := self kind: r.
	^k = X64_K_MEM or: [k = X64_K_STATEMEM]
!
dst: r
	"The x86 register to compute r into: its own, rsp for sp, else r11 (then store:into:)."
	<export>
	<var: #r type: 'int64_t'>
	| k |
	k := self kind: r.
	k = X64_K_PHYS ifTrue: [^self gpr: r].
	k = X64_K_SP ifTrue: [^X64_RSP].
	^X64_R11
!
store: t into: r
	"r := x86 register t, which dst: r answered."
	<export>
	<var: #t type: 'int64_t'>
	<var: #r type: 'int64_t'>
	| k |
	k := self kind: r.
	k = X64_K_PHYS ifTrue: [
		(self gpr: r) ~= t ifTrue: [self movReg: (self gpr: r) from: t].
		^self].
	k = X64_K_MEM ifTrue: [^self op: 16r89 len: 1 pre: 0 w: 1 reg: t target: (self homeOf: r) imm: 0 isz: 0].
	(k = X64_K_ZERO or: [k = X64_K_STATE or: [k = X64_K_STATEMEM]]) ifTrue: [^self].
	k = X64_K_SP ifTrue: [
		t ~= X64_RSP ifTrue: [self movReg: X64_RSP from: t].
		^self].
	self fail: ASM_ERR_OPERAND
!
load: r into: t
	"x86 register t := arm64 register r (64 bits)."
	<export>
	<var: #r type: 'int64_t'>
	<var: #t type: 'int64_t'>
	| k |
	k := self kind: r.
	k = X64_K_PHYS ifTrue: [
		(self gpr: r) ~= t ifTrue: [self movReg: t from: (self gpr: r)].
		^self].
	(k = X64_K_MEM or: [k = X64_K_STATEMEM]) ifTrue: [^self op: 16r8B len: 1 pre: 0 w: 1 reg: t target: (self homeOf: r) imm: 0 isz: 0].
	k = X64_K_ZERO ifTrue: [^self movReg32: t imm: 0].
	k = X64_K_SP ifTrue: [
		t ~= X64_RSP ifTrue: [self movReg: t from: X64_RSP].
		^self].
	k = X64_K_STATE ifTrue: [^self op: 16r8D len: 1 pre: 0 w: 1 reg: t target: asmState imm: 0 isz: 0].
	self fail: ASM_ERR_OPERAND
!
source: r
	"r as an x86 register: its own (rsp for sp), else r11 loaded with it."
	(self isBase: r) ifTrue: [^self gpr: r].
	self load: r into: X64_R11.
	^X64_R11
! !

!Amd64Assembler methodsFor: 'flags'!
setFlags: aKind
	asmFlags := aKind.
	asmFlagsLabel := -1
!
flags: a merge: b
	"The kind of flags that come both as a and as b."
	a = X64_FL_UNSEEN ifTrue: [^b].
	b = X64_FL_UNSEEN ifTrue: [^a].
	a = b ifTrue: [^a].
	"a compare's, an add's and a logical instruction's agree but on the carry; a floating point compare's, a multiply's and bt's with no other"
	(a = X64_FL_CLOBBERED or: [b = X64_FL_CLOBBERED or: [a >= X64_FL_FP or: [b >= X64_FL_FP]]]) ifTrue: [^X64_FL_CLOBBERED].
	^X64_FL_NONE
!
branchTo: aLabel
	"A branch to aLabel takes the flags along: to a label not bound yet they join its kind; one bound already must have the kind its code read."
	<export>
	<var: #aLabel type: 'int32_t'>
	| k |
	k := (asmLabelFlags at: aLabel) asInt32.
	(asmLabels at: aLabel) = 0 ifTrue: [
		asmLabelFlags at: aLabel put: (self flags: (k bitAnd: 15) merge: asmFlags) asUInt8.
		^self].
	((k bitAnd: X64_FL_READ) ~= 0 and: [(k bitAnd: 15) ~= asmFlags]) ifTrue: [self fail: ASM_ERR_FLAGS]
!
readFlags
	"An instruction reads the flags: if they are a label's (no setter since it), its branches must keep bringing that kind."
	asmFlagsLabel >= 0 ifTrue: [asmLabelFlags at: asmFlagsLabel put: ((asmLabelFlags at: asmFlagsLabel) bitOr: X64_FL_READ)]
!
clobberFlags
	"Code of mine changed the flags."
	asmFlags ~= X64_FL_NONE ifTrue: [asmFlags := X64_FL_CLOBBERED]
!
cc: c
	"The x86 condition (tttn) for arm64 condition c after what set the flags; -1 for a floating point compare's EQ, NE, MI, PL, HI, LS, LO, HS (two tests: fpPair:), -2 if it cannot be told, -3 for always."
	<export>
	<var: #c type: 'int64_t'>
	| k |
	k := asmFlags.
	c = COND_AL ifTrue: [^-3].
	self readFlags.
	k = X64_FL_CLOBBERED ifTrue: [^-2].
	"bt: the bit in the carry; imul: the overflow in OF (and CF)"
	k = X64_FL_BT ifTrue: [
		c = COND_EQ ifTrue: [^3].
		c = COND_NE ifTrue: [^2].
		^-2].
	k = X64_FL_MUL ifTrue: [
		c = COND_VS ifTrue: [^0].
		c = COND_VC ifTrue: [^1].
		^-2].
	k = X64_FL_FP ifTrue: [
		c = COND_GE ifTrue: [^3].
		c = COND_GT ifTrue: [^7].
		c = COND_LT ifTrue: [^2].
		c = COND_LE ifTrue: [^6].
		c = COND_VS ifTrue: [^10].
		c = COND_VC ifTrue: [^11].
		^-1].
	c = COND_EQ ifTrue: [^4].
	c = COND_NE ifTrue: [^5].
	(c = COND_HS or: [c = COND_LO or: [c = COND_HI or: [c = COND_LS]]]) ifTrue: [
		k = X64_FL_SUB ifTrue: [
			c = COND_HS ifTrue: [^3].
			c = COND_LO ifTrue: [^2].
			c = COND_HI ifTrue: [^7].
			^6].
		(c = COND_HS or: [c = COND_LO]) ifTrue: [
			(k = X64_FL_ADD or: [k = X64_FL_LOGIC]) ifTrue: [^c = COND_HS ifTrue: [2] ifFalse: [3]].
			^-2].
		"a logical instruction clears C (and V, which x86 clears too): HI never holds, LS always"
		k = X64_FL_LOGIC ifTrue: [^c = COND_HI ifTrue: [0] ifFalse: [1]].
		"an add's carry: HI is C and not Z, LS not C or Z (two tests)"
		k = X64_FL_ADD ifTrue: [^-1].
		^-2].
	c = COND_MI ifTrue: [^8].
	c = COND_PL ifTrue: [^9].
	c = COND_VS ifTrue: [^0].
	c = COND_VC ifTrue: [^1].
	c = COND_GE ifTrue: [^13].
	c = COND_LT ifTrue: [^12].
	c = COND_GT ifTrue: [^15].
	^14
!
fpPair: c
	"A condition c that takes two x86 tests (cc: answered -1): first << 8 | second, 16r10000 if both must hold (else either). A floating point compare's, or HI and LS after an add."
	<export>
	<var: #c type: 'int64_t'>
	asmFlags = X64_FL_ADD ifTrue: [^c = COND_HI ifTrue: [16r10205] ifFalse: [16r00304]].
	c = COND_EQ ifTrue: [^16r10B04].
	c = COND_NE ifTrue: [^16r00A05].
	(c = COND_MI or: [c = COND_LO]) ifTrue: [^16r10B02].
	c = COND_LS ifTrue: [^16r10B06].
	(c = COND_PL or: [c = COND_HS]) ifTrue: [^16r00A03].
	^16r00A07
! !

!Amd64Assembler methodsFor: 'x86 encoding'!
rex: w reg: reg index: x base: b
	"The REX bits (without 16r40): W, R, X, B."
	^(((w asInt64 << 3) bitOr: ((reg >> 3) bitAnd: 1) asInt64 << 2) bitOr: ((x >> 3) bitAnd: 1) asInt64 << 1) bitOr: ((b >> 3) bitAnd: 1)
!
modrm: mod reg: reg rm: rm
	^((mod asInt64 << 6) bitOr: (reg bitAnd: 7) asInt64 << 3) bitOr: (rm bitAnd: 7)
!
op: op len: olen pre: pre w: w reg: reg rm: rm byte: isByte
	"[pre] [REX] op (olen bytes, the first lowest) ModRM(11 reg rm). isByte: byte registers (spl-dil need a REX)."
	| rex v n |
	rex := self rex: w reg: reg index: 0 base: rm.
	v := pre asUInt64.
	n := pre = 0 ifTrue: [0] ifFalse: [1].
	(rex ~= 0 or: [isByte and: [(rm between: 4 and: 7) or: [reg between: 4 and: 7]]]) ifTrue: [
		v := v bitOr: (16r40 bitOr: rex) asUInt64 << (8 * n).
		n := n + 1].
	v := v bitOr: op asUInt64 << (8 * n).
	n := n + olen.
	v := v bitOr: (self modrm: 3 reg: reg rm: rm) asUInt64 << (8 * n).
	self emitBytes: v count: n + 1
!
op: op len: olen pre: pre w: w reg: reg rm: rm imm: imm isz: isz
	"Register direct with an immediate (isz 1 or 4 bytes); a test of spl-dil with an 8-bit immediate gets a REX."
	| rex v n |
	rex := self rex: w reg: reg index: 0 base: rm.
	v := pre asUInt64.
	n := pre = 0 ifTrue: [0] ifFalse: [1].
	(rex ~= 0 or: [op = 16rF6 and: [rm between: 4 and: 7]]) ifTrue: [
		v := v bitOr: (16r40 bitOr: rex) asUInt64 << (8 * n).
		n := n + 1].
	v := v bitOr: op asUInt64 << (8 * n).
	n := n + olen.
	v := v bitOr: (self modrm: 3 reg: reg rm: rm) asUInt64 << (8 * n).
	n := n + 1.
	v := v bitOr: (imm asUInt64 bitAnd: (isz = 1 ifTrue: [16rFF] ifFalse: [16rFFFFFFFF])) << (8 * n).
	self emitBytes: v count: n + isz
!
op: op len: olen pre: pre w: w reg: reg base: base disp: disp imm: imm isz: isz byte: isByte
	"[pre] [REX] op ModRM [SIB] [disp8/32] [imm]: the memory at base + disp (an x86 register)."
	| rex v n mod b3 tail tn d |
	d := disp asInt64.
	(d between: -16r80000000 and: 16r7FFFFFFF) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	b3 := base bitAnd: 7.
	rex := self rex: w reg: reg index: 0 base: base.
	v := pre asUInt64.
	n := pre = 0 ifTrue: [0] ifFalse: [1].
	(rex ~= 0 or: [isByte and: [reg between: 4 and: 7]]) ifTrue: [
		v := v bitOr: (16r40 bitOr: rex) asUInt64 << (8 * n).
		n := n + 1].
	v := v bitOr: op asUInt64 << (8 * n).
	n := n + olen.
	mod := (d = 0 and: [b3 ~= 5]) ifTrue: [0] ifFalse: [(d between: -128 and: 127) ifTrue: [1] ifFalse: [2]].
	v := v bitOr: (self modrm: mod reg: reg rm: b3) asUInt64 << (8 * n).
	n := n + 1.
	b3 = 4 ifTrue: [
		v := v bitOr: 16r24 asUInt64 << (8 * n).
		n := n + 1].
	tail := 0 asUInt64.
	tn := 0.
	mod = 1 ifTrue: [
		tail := d asUInt64 bitAnd: 16rFF.
		tn := 1].
	mod = 2 ifTrue: [
		tail := d asUInt64 bitAnd: 16rFFFFFFFF.
		tn := 4].
	isz > 0 ifTrue: [
		tail := tail bitOr: (imm asUInt64 bitAnd: (isz = 1 ifTrue: [16rFF] ifFalse: [16rFFFFFFFF])) << (8 * tn).
		tn := tn + isz].
	tn = 0 ifTrue: [^self emitBytes: v count: n].
	n + tn <= 8
		ifTrue: [self emitBytes: (v bitOr: tail << (8 * n)) count: n + tn]
		ifFalse: [
			self emitBytes: v count: n.
			self emitBytes: tail count: tn]
!
op: op len: olen pre: pre w: w reg: reg base: base index: index scale: s disp: disp byte: isByte
	"The memory at base + index << s + disp (index not rsp)."
	| rex v n mod b3 tail tn d |
	d := disp asInt64.
	(d between: -16r80000000 and: 16r7FFFFFFF) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	b3 := base bitAnd: 7.
	rex := self rex: w reg: reg index: index base: base.
	v := pre asUInt64.
	n := pre = 0 ifTrue: [0] ifFalse: [1].
	(rex ~= 0 or: [isByte and: [reg between: 4 and: 7]]) ifTrue: [
		v := v bitOr: (16r40 bitOr: rex) asUInt64 << (8 * n).
		n := n + 1].
	v := v bitOr: op asUInt64 << (8 * n).
	n := n + olen.
	mod := (d = 0 and: [b3 ~= 5]) ifTrue: [0] ifFalse: [(d between: -128 and: 127) ifTrue: [1] ifFalse: [2]].
	v := v bitOr: (self modrm: mod reg: reg rm: 4) asUInt64 << (8 * n).
	n := n + 1.
	v := v bitOr: (self modrm: s reg: index rm: b3) asUInt64 << (8 * n).
	n := n + 1.
	tail := 0 asUInt64.
	tn := 0.
	mod = 1 ifTrue: [
		tail := d asUInt64 bitAnd: 16rFF.
		tn := 1].
	mod = 2 ifTrue: [
		tail := d asUInt64 bitAnd: 16rFFFFFFFF.
		tn := 4].
	tn = 0 ifTrue: [^self emitBytes: v count: n].
	n + tn <= 8
		ifTrue: [self emitBytes: (v bitOr: tail << (8 * n)) count: n + tn]
		ifFalse: [
			self emitBytes: v count: n.
			self emitBytes: tail count: tn]
!
op: op len: olen pre: pre w: w reg: reg target: address imm: imm isz: isz
	"The memory at address, pc-relative: [rip + disp32]."
	<export>
	<var: #op type: 'int32_t'>
	<var: #olen type: 'int32_t'>
	<var: #pre type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #reg type: 'int64_t'>
	<var: #address type: 'uint64_t'>
	<var: #imm type: 'int64_t'>
	<var: #isz type: 'int32_t'>
	| rex v n disp |
	rex := self rex: w reg: reg index: 0 base: 0.
	v := pre asUInt64.
	n := pre = 0 ifTrue: [0] ifFalse: [1].
	rex ~= 0 ifTrue: [
		v := v bitOr: (16r40 bitOr: rex) asUInt64 << (8 * n).
		n := n + 1].
	v := v bitOr: op asUInt64 << (8 * n).
	n := n + olen.
	v := v bitOr: (self modrm: 0 reg: reg rm: 5) asUInt64 << (8 * n).
	n := n + 1.
	disp := (address - (asmPc + (n + 4 + isz) asUInt64)) asInt64.
	(disp between: -16r80000000 and: 16r7FFFFFFF) ifFalse: [^self fail: ASM_ERR_RANGE].
	self emitBytes: v count: n.
	self emitBytes: ((disp asUInt64 bitAnd: 16rFFFFFFFF) bitOr: (imm asUInt64 bitAnd: (isz = 1 ifTrue: [16rFF] ifFalse: [16rFFFFFFFF])) << 32) count: 4 + isz
!
op: op len: olen pre: pre w: w reg: reg label: aLabel
	"The memory at aLabel, pc-relative (its displacement ends the instruction: a fixup until aLabel is bound)."
	| rex v n |
	rex := self rex: w reg: reg index: 0 base: 0.
	v := pre asUInt64.
	n := pre = 0 ifTrue: [0] ifFalse: [1].
	rex ~= 0 ifTrue: [
		v := v bitOr: (16r40 bitOr: rex) asUInt64 << (8 * n).
		n := n + 1].
	v := v bitOr: op asUInt64 << (8 * n).
	n := n + olen.
	v := v bitOr: (self modrm: 0 reg: reg rm: 5) asUInt64 << (8 * n).
	self emitBytes: v count: n + 1.
	self emitRel32To: (self targetOf: aLabel site: asmPc)
!
emitRel32To: target
	"The 32-bit displacement at pc to target, counted from the end of the field."
	| disp |
	disp := (target - (asmPc + 4)) asInt64.
	(disp between: -16r80000000 and: 16r7FFFFFFF) ifFalse: [^self fail: ASM_ERR_RANGE].
	self emitBytes: (disp asUInt64 bitAnd: 16rFFFFFFFF) count: 4
!
movReg: dst from: src
	"mov dst, src (64 bits)."
	self op: 16r8B len: 1 pre: 0 w: 1 reg: dst rm: src byte: false
!
movReg32: dst imm: v
	"mov dst32, imm32 (zero-extended; the flags stay)."
	((dst >> 3) bitAnd: 1) ~= 0
		ifTrue: [self emitBytes: ((16r41 bitOr: (16rB8 + (dst bitAnd: 7)) asInt64 << 8) asUInt64 bitOr: (v asUInt64 bitAnd: 16rFFFFFFFF) << 16) count: 6]
		ifFalse: [self emitBytes: ((16rB8 + (dst bitAnd: 7)) asUInt64 bitOr: (v asUInt64 bitAnd: 16rFFFFFFFF) << 8) count: 5]
!
movReg: dst imm: v
	"dst := v (64 bits), the shortest way that keeps the flags."
	v asUInt64 <= 16rFFFFFFFF ifTrue: [^self movReg32: dst imm: v].
	(v asInt64 between: -16r80000000 and: 16r7FFFFFFF) ifTrue: [^self op: 16rC7 len: 1 pre: 0 w: 1 reg: 0 rm: dst imm: v isz: 4].
	self movabs: dst imm: v
!
movabs: dst imm: v
	"mov dst, imm64 (10 bytes, the constant 2 bytes in)."
	self emitBytes: ((16r48 bitOr: ((dst >> 3) bitAnd: 1)) bitOr: (16rB8 + (dst bitAnd: 7)) asInt64 << 8) asUInt64 count: 2.
	self emitBytes: v asUInt64 count: 8
!
alu: digit w: w dst: t imm: v
	"x86 group 1 (digit: 0 add, 1 or, 4 and, 5 sub, 6 xor, 7 cmp) of register t and the sign-extended immediate v."
	(v between: -128 and: 127) ifTrue: [^self op: 16r83 len: 1 pre: 0 w: w reg: digit rm: t imm: v isz: 1].
	(w = 0 or: [v asInt64 between: -16r80000000 and: 16r7FFFFFFF]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	self op: 16r81 len: 1 pre: 0 w: w reg: digit rm: t imm: v isz: 4
!
fitsImm32: v
	^v asInt64 between: -16r80000000 and: 16r7FFFFFFF
!
alu: op w: w dst: t src: r
	"x86 op (03 add, 0B or, 23 and, 2B sub, 33 xor, 3B cmp, 85 test) t, r for an arm64 register r: its register, its word, or 0."
	<export>
	<var: #op type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #t type: 'int64_t'>
	<var: #r type: 'int64_t'>
	| k |
	k := self kind: r.
	(k = X64_K_PHYS or: [k = X64_K_SP]) ifTrue: [^self op: op len: 1 pre: 0 w: w reg: t rm: (self gpr: r) byte: false].
	(k = X64_K_MEM or: [k = X64_K_STATEMEM]) ifTrue: [^self op: op len: 1 pre: 0 w: w reg: t target: (self homeOf: r) imm: 0 isz: 0].
	k = X64_K_ZERO ifTrue: [
		op = 16r85 ifTrue: [^self op: 16rF7 len: 1 pre: 0 w: w reg: 0 rm: t imm: 0 isz: 4].
		^self alu: ((op >> 3) bitAnd: 7) w: w dst: t imm: 0].
	self fail: ASM_ERR_OPERAND
!
shift: digit w: w reg: t by: n
	"x86 group 2 (4 shl, 5 shr, 7 sar, 1 ror) of t by n bits."
	n = 1 ifTrue: [^self op: 16rD1 len: 1 pre: 0 w: w reg: digit rm: t byte: false].
	self op: 16rC1 len: 1 pre: 0 w: w reg: digit rm: t imm: n isz: 1
!
jcc: cc to: aLabel
	"jcc: rel8 back to a near label, else rel32."
	| a d |
	self branchTo: aLabel.
	a := asmLabels at: aLabel.
	a ~= 0 ifTrue: [
		d := (a - (asmPc + 2)) asInt64.
		(d between: -128 and: 127) ifTrue: [^self emitBytes: ((16r70 + cc) asUInt64 bitOr: (d asUInt64 bitAnd: 16rFF) << 8) count: 2]].
	self emitBytes: (16r800F bitOr: cc asInt64 << 8) asUInt64 count: 2.
	self emitRel32To: (self targetOf: aLabel site: asmPc)
!
jmpRel32To: aLabel
	self branchTo: aLabel.
	self emitBytes: 16rE9 count: 1.
	self emitRel32To: (self targetOf: aLabel site: asmPc).
	asmJumpEnd := asmPc
! !

!Amd64Assembler methodsFor: 'x86'!
callC: function
	"Call the C function at address function, its arguments in x0-x5 (rdi rsi rdx rcx r8 r9): the native stack aligned to 16 (machine code keeps it 8-aligned), xmm8-xmm15 kept (baseline code's unboxed Floats: SysV saves no xmm register), its result in x0 (and x9, rax). x9, r11 and the registers SysV does not save are clobbered."
	<export>
	<var: #function type: 'uint64_t'>
	"mov r11, rsp; and rsp, -16; sub rsp, 80; mov [rsp + 64], r11"
	self movReg: X64_R11 from: X64_RSP.
	self op: 16r83 len: 1 pre: 0 w: 1 reg: 4 rm: X64_RSP imm: -16 isz: 1.
	self op: 16r83 len: 1 pre: 0 w: 1 reg: 5 rm: X64_RSP imm: 80 isz: 1.
	self op: 16r89 len: 1 pre: 0 w: 1 reg: X64_R11 base: X64_RSP disp: 64 imm: 0 isz: 0 byte: false.
	0 to: 7 do: [:k | self op: 16r110F len: 2 pre: 16rF2 w: 0 reg: 8 + k base: X64_RSP disp: 8 * k imm: 0 isz: 0 byte: false].
	self movabs: X64_RAX imm: function.
	self op: 16rFF len: 1 pre: 0 w: 0 reg: 2 rm: X64_RAX byte: false.
	0 to: 7 do: [:k | self op: 16r100F len: 2 pre: 16rF2 w: 0 reg: 8 + k base: X64_RSP disp: 8 * k imm: 0 isz: 0 byte: false].
	self op: 16r8B len: 1 pre: 0 w: 1 reg: X64_RSP base: X64_RSP disp: 64 imm: 0 isz: 0 byte: false.
	self movReg: X64_RDI from: X64_RAX.
	asmFlags := X64_FL_NONE
!
callCFromSend: function
	"callC: for a stub entered only where no unboxed Float has to stay in xmm8-xmm15 (a primitive's, entered by a send: baseline code boxes them before one, optimized code loads its doubles again after a call): they are not kept."
	<export>
	<var: #function type: 'uint64_t'>
	"mov r11, rsp; and rsp, -16; sub rsp, 16; mov [rsp + 8], r11"
	self movReg: X64_R11 from: X64_RSP.
	self op: 16r83 len: 1 pre: 0 w: 1 reg: 4 rm: X64_RSP imm: -16 isz: 1.
	self op: 16r83 len: 1 pre: 0 w: 1 reg: 5 rm: X64_RSP imm: 16 isz: 1.
	self op: 16r89 len: 1 pre: 0 w: 1 reg: X64_R11 base: X64_RSP disp: 8 imm: 0 isz: 0 byte: false.
	self movabs: X64_RAX imm: function.
	self op: 16rFF len: 1 pre: 0 w: 0 reg: 2 rm: X64_RAX byte: false.
	self op: 16r8B len: 1 pre: 0 w: 1 reg: X64_RSP base: X64_RSP disp: 8 imm: 0 isz: 0 byte: false.
	self movReg: X64_RDI from: X64_RAX.
	asmFlags := X64_FL_NONE
!
pushX64: r
	"push the x86 register r"
	r >= 8
		ifTrue: [self emitBytes: (16r41 bitOr: (16r50 + (r bitAnd: 7)) asInt64 << 8) asUInt64 count: 2]
		ifFalse: [self emitBytes: (16r50 + r) asUInt64 count: 1]
!
popX64: r
	"pop the x86 register r"
	r >= 8
		ifTrue: [self emitBytes: (16r41 bitOr: (16r58 + (r bitAnd: 7)) asInt64 << 8) asUInt64 count: 2]
		ifFalse: [self emitBytes: (16r58 + r) asUInt64 count: 1]
!
cmp: rn withWordAt: rb offset: off
	"cmp rn, [rb + off] (both with x86 registers): the flags of rn - the word."
	self op: 16r3B len: 1 pre: 0 w: 1 reg: (self gpr: rn) base: (self gpr: rb) disp: off imm: 0 isz: 0 byte: false.
	self setFlags: X64_FL_SUB
!
picCaseX64: r classAt: address target: aLabel
	"A polymorphic inline cache's case: cmp r, [address] (rip-relative, 7 bytes); jne over the jmp; jmp aLabel (rel32, its displacement 10 bytes in)."
	self op: 16r3B len: 1 pre: 0 w: 1 reg: (self gpr: r) target: address imm: 0 isz: 0.
	self emitBytes: 16r0575 count: 2.
	self jmpRel32To: aLabel
!
muls: rd with: rn with: rm
	"rd := rn * rm (imul), the flags saying whether the signed product overflowed 64 bits (VS): what arm64 tells by smulh."
	self mul: rd with: rn with: rm.
	self setFlags: X64_FL_MUL
!
cmp: rn withStateWordAt: off
	"cmp rn, [JitState + off] (pc-relative): the flags of rn - the word."
	self op: 16r3B len: 1 pre: 0 w: 1 reg: (self gpr: rn) target: asmState + off asUInt64 imm: 0 isz: 0.
	self setFlags: X64_FL_SUB
!
cmpStateWordAt: off imm: v
	"cmp qword [JitState + off], v (a signed byte): the flags of the word - v."
	self op: 16r83 len: 1 pre: 0 w: 1 reg: 7 target: asmState + off asUInt64 imm: v isz: 1.
	self setFlags: X64_FL_SUB
!
cmpStateWord32At: off imm: v
	"cmp dword [JitState + off], v (a signed byte)."
	self op: 16r83 len: 1 pre: 0 w: 0 reg: 7 target: asmState + off asUInt64 imm: v isz: 1.
	self setFlags: X64_FL_SUB
!
loadReturnAddress: r
	"r := the return address on top of the native stack (where a call into this code returns)."
	self ldr: r base: SP offset: 0
!
decrement32At: address
	"sub dword [address], 1 (pc-relative): the flags of the subtraction."
	self op: 16r83 len: 1 pre: 0 w: 0 reg: 5 target: address imm: 1 isz: 1.
	self setFlags: X64_FL_SUB
! !

!Amd64Assembler methodsFor: 'moves'!
mov: rd with: rm
	"A register move; x29 := sp (the frame pointer arm64 keeps) is nothing here."
	((self isPhys: rd) and: [self isPhys: rm]) ifTrue: [
		(self isW: rd)
			ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: (self gpr: rd) rm: (self gpr: rm) byte: false]
			ifFalse: [(self gpr: rd) ~= (self gpr: rm) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rm)]].
		^self].
	self moveAny: rd from: rm
!
moveAny: rd from: rm
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	| k t |
	((self isD: rd) or: [self isD: rm]) ifTrue: [^self fmov: rd with: rm].
	k := self kind: rd.
	(k = X64_K_ZERO or: [k = X64_K_FP or: [k = X64_K_STATE or: [k = X64_K_STATEMEM]]]) ifTrue: [^self].
	(self kind: rm) = X64_K_ZERO ifTrue: [^self mov: rd imm: 0].
	(self isW: rd) ifTrue: [
		t := self dst: rd.
		self load: rm into: X64_R11.
		self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: X64_R11 byte: false.
		^self store: t into: rd].
	(k = X64_K_PHYS or: [k = X64_K_SP]) ifTrue: [^self load: rm into: (self gpr: rd)].
	(self isPhys: rm) ifTrue: [^self store: (self gpr: rm) into: rd].
	self load: rm into: X64_R11.
	self store: X64_R11 into: rd
!
mov: rd imm: value
	"rd := value (a W register: its low 32 bits); the flags stay."
	(self isPhys: rd) ifTrue: [^self movReg: (self gpr: rd) imm: ((self isW: rd) ifTrue: [value asUInt64 bitAnd: 16rFFFFFFFF] ifFalse: [value asUInt64])].
	self moveAny: rd imm: value asUInt64
!
moveAny: rd imm: value
	<export>
	<var: #rd type: 'int64_t'>
	<var: #value type: 'uint64_t'>
	| t v |
	v := (self isW: rd) ifTrue: [value bitAnd: 16rFFFFFFFF] ifFalse: [value].
	(self kind: rd) = X64_K_ZERO ifTrue: [^self].
	(self isD: rd) ifTrue: [^self fmov: rd bits: v].
	((self kind: rd) = X64_K_MEM and: [self fitsImm32: v asInt64]) ifTrue: [
		^self op: 16rC7 len: 1 pre: 0 w: 1 reg: 0 target: (self homeOf: rd) imm: v asInt64 isz: 4].
	t := self dst: rd.
	self movReg: t imm: v.
	self store: t into: rd
!
mov: rd imm64: value
	"Always movabs (10 bytes, the constant 2 bytes in), so that patchMov64At:value: can rewrite it."
	(self isPhys: rd) ifTrue: [^self movabs: (self gpr: rd) imm: value].
	self movabs: X64_R11 imm: value.
	self store: X64_R11 into: rd
!
movz: rd imm: imm shift: s
	self mov: rd imm: imm asUInt64 << s
! !

!Amd64Assembler methodsFor: 'add and subtract'!
add: rd with: rn imm: imm
	"rd := rn + imm: lea (the flags stay)."
	((self isPhys: rd) and: [(self isBase: rn) and: [(self isW: rd) not]]) ifTrue: [
		(imm = 0 and: [(self gpr: rd) = (self gpr: rn)]) ifTrue: [^self].
		^self op: 16r8D len: 1 pre: 0 w: 1 reg: (self gpr: rd) base: (self gpr: rn) disp: imm imm: 0 isz: 0 byte: false].
	((self kind: rd) = X64_K_SP and: [(self kind: rn) = X64_K_SP]) ifTrue: [
		imm = 0 ifTrue: [^self].
		^self op: 16r8D len: 1 pre: 0 w: 1 reg: X64_RSP base: X64_RSP disp: imm imm: 0 isz: 0 byte: false].
	self addAny: rd with: rn imm: imm asInt64
!
addAny: rd with: rn imm: imm
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #imm type: 'int64_t'>
	| t k |
	(self kind: rd) = X64_K_FP ifTrue: [^self].
	t := self dst: rd.
	(self isW: rd) ifTrue: [
		self load: rn into: t.
		self op: 16r8D len: 1 pre: 0 w: 0 reg: t base: t disp: imm imm: 0 isz: 0 byte: false.
		^self store: t into: rd].
	k := self kind: rn.
	k = X64_K_STATE ifTrue: [
		self op: 16r8D len: 1 pre: 0 w: 1 reg: t target: asmState + imm asUInt64 imm: 0 isz: 0.
		^self store: t into: rd].
	(self isBase: rn)
		ifTrue: [
			(imm ~= 0 or: [(self gpr: rn) ~= t]) ifTrue: [
				self op: 16r8D len: 1 pre: 0 w: 1 reg: t base: (self gpr: rn) disp: imm imm: 0 isz: 0 byte: false]]
		ifFalse: [
			self load: rn into: t.
			imm ~= 0 ifTrue: [self op: 16r8D len: 1 pre: 0 w: 1 reg: t base: t disp: imm imm: 0 isz: 0 byte: false]].
	self store: t into: rd
!
sub: rd with: rn imm: imm
	self add: rd with: rn imm: imm asInt64 negated
!
adds: rd with: rn imm: imm
	"rd := rn + imm, the flags set (an add's carry)."
	self arith: 0 rd: rd rn: rn imm: imm.
	self setFlags: X64_FL_ADD
!
subs: rd with: rn imm: imm
	"rd := rn - imm, the flags set (a subtraction's carry)."
	(rd bitAnd: 31 + REG_SP + REG_D) = 31 ifTrue: [^self cmp: rn imm: imm].
	self arith: 5 rd: rd rn: rn imm: imm.
	self setFlags: X64_FL_SUB
!
arith: digit rd: rd rn: rn imm: imm
	"rd := rn op imm (x86 group 1)."
	((self isPhys: rd) and: [self isPhys: rn]) ifTrue: [
		(self gpr: rd) ~= (self gpr: rn) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rn)].
		^self alu: digit w: (self wide: rd) dst: (self gpr: rd) imm: imm].
	self arithAny: digit rd: rd rn: rn imm: imm asInt64
!
arithAny: digit rd: rd rn: rn imm: imm
	<export>
	<var: #digit type: 'int32_t'>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #imm type: 'int64_t'>
	| t |
	t := self dst: rd.
	self load: rn into: t.
	self alu: digit w: (self wide: rd) dst: t imm: imm.
	self store: t into: rd
!
cmp: rn imm: imm
	(self isPhys: rn)
		ifTrue: [self alu: 7 w: (self wide: rn) dst: (self gpr: rn) imm: imm]
		ifFalse: [self cmpAny: rn imm: imm asInt64].
	self setFlags: X64_FL_SUB
!
cmpAny: rn imm: imm
	<export>
	<var: #rn type: 'int64_t'>
	<var: #imm type: 'int64_t'>
	(self isWord: rn) ifTrue: [
		(imm between: -128 and: 127) ifTrue: [^self op: 16r83 len: 1 pre: 0 w: (self wide: rn) reg: 7 target: (self homeOf: rn) imm: imm isz: 1].
		^self op: 16r81 len: 1 pre: 0 w: (self wide: rn) reg: 7 target: (self homeOf: rn) imm: imm isz: 4].
	self alu: 7 w: (self wide: rn) dst: (self source: rn) imm: imm
!
cmn: rn imm: imm
	"The flags of rn + imm: those of rn - -imm (the same arithmetic, the carry as a subtraction's)."
	self cmp: rn imm: imm asInt64 negated
!
add: rd with: rn with: rm
	"rd := rn + rm (lea when it can: the flags stay)."
	((self isPhys: rd) and: [(self isBase: rn) and: [(self isPhys: rm) and: [(self isW: rd) not]]]) ifTrue: [
		^self op: 16r8D len: 1 pre: 0 w: 1 reg: (self gpr: rd) base: (self gpr: rn) index: (self gpr: rm) scale: 0 disp: 0 byte: false].
	self binary: 16r03 rd: rd rn: rn rm: rm commutes: true.
	self clobberFlags
!
adds: rd with: rn with: rm
	self binary: 16r03 rd: rd rn: rn rm: rm commutes: true.
	self setFlags: X64_FL_ADD
!
sub: rd with: rn with: rm
	self binary: 16r2B rd: rd rn: rn rm: rm commutes: false.
	self clobberFlags
!
subs: rd with: rn with: rm
	(rd bitAnd: 31 + REG_SP + REG_D) = 31 ifTrue: [^self cmp: rn with: rm].
	self binary: 16r2B rd: rd rn: rn rm: rm commutes: false.
	self setFlags: X64_FL_SUB
!
cmp: rn with: rm
	((self isBase: rn) and: [self isPhys: rm])
		ifTrue: [self op: 16r3B len: 1 pre: 0 w: (self wide: rn) reg: (self gpr: rn) rm: (self gpr: rm) byte: false]
		ifFalse: [self cmpAny: rn with: rm].
	self setFlags: X64_FL_SUB
!
cmpAny: rn with: rm
	<export>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	(self isBase: rn) ifTrue: [^self alu: 16r3B w: (self wide: rn) dst: (self gpr: rn) src: rm].
	((self isPhys: rm) and: [self isWord: rn]) ifTrue: [
		"cmp [rn's word], rm: the flags of rn - rm"
		^self op: 16r39 len: 1 pre: 0 w: (self wide: rn) reg: (self gpr: rm) target: (self homeOf: rn) imm: 0 isz: 0].
	self load: rn into: X64_R11.
	self alu: 16r3B w: (self wide: rn) dst: X64_R11 src: rm
!
cmn: rn with: rm
	self load: rn into: X64_R11.
	self alu: 16r03 w: (self wide: rn) dst: X64_R11 src: rm.
	self setFlags: X64_FL_ADD
!
neg: rd with: rm
	| t |
	t := self dst: rd.
	self load: rm into: t.
	self op: 16rF7 len: 1 pre: 0 w: (self wide: rd) reg: 3 rm: t byte: false.
	self store: t into: rd.
	self clobberFlags
!
binary: op rd: rd rn: rn rm: rm commutes: aBoolean
	"rd := rn op rm (x86 op t, r/m)."
	((self isPhys: rd) and: [(self isPhys: rn) and: [(self isPhys: rm) and: [(self gpr: rd) ~= (self gpr: rm) or: [(self gpr: rd) = (self gpr: rn)]]]]) ifTrue: [
		(self gpr: rd) ~= (self gpr: rn) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rn)].
		^self op: op len: 1 pre: 0 w: (self wide: rd) reg: (self gpr: rd) rm: (self gpr: rm) byte: false].
	self binaryAny: op rd: rd rn: rn rm: rm commutes: aBoolean
!
binaryAny: op rd: rd rn: rn rm: rm commutes: aBoolean
	<export>
	<var: #op type: 'int32_t'>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	| t w |
	w := self wide: rd.
	((self isPhys: rd) and: [(self isPhys: rm) and: [(self gpr: rd) = (self gpr: rm) and: [(self isPhys: rn) not or: [(self gpr: rd) ~= (self gpr: rn)]]]]) ifTrue: [
		aBoolean ifTrue: [^self alu: op w: w dst: (self gpr: rd) src: rn].
		"rd = rm: into r11"
		self load: rn into: X64_R11.
		self alu: op w: w dst: X64_R11 src: rm.
		^self store: X64_R11 into: rd].
	t := self dst: rd.
	self load: rn into: t.
	self alu: op w: w dst: t src: rm.
	self store: t into: rd
!
shifted: rm type: type amount: n into: t
	"t := rm shifted (arm64's shifted register operand)."
	<export>
	<var: #rm type: 'int64_t'>
	<var: #type type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #t type: 'int64_t'>
	self load: rm into: t.
	n ~= 0 ifTrue: [
		self shift: (type = SHIFT_LSL ifTrue: [4] ifFalse: [type = SHIFT_LSR ifTrue: [5] ifFalse: [type = SHIFT_ASR ifTrue: [7] ifFalse: [1]]]) w: (self wide: rm) reg: t by: n.
		self clobberFlags]
!
add: rd with: rn with: rm shift: type amount: n
	((type = SHIFT_LSL and: [n between: 0 and: 3]) and: [(self isPhys: rd) and: [(self isBase: rn) and: [(self isPhys: rm) and: [(self isW: rd) not]]]]) ifTrue: [
		^self op: 16r8D len: 1 pre: 0 w: 1 reg: (self gpr: rd) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: 0 byte: false].
	self shiftedOp: 16r03 rd: rd rn: rn rm: rm shift: type amount: n
!
shiftedOp: op rd: rd rn: rn rm: rm shift: type amount: n
	"rd := rn op (rm shifted); op 2B (sub) the only one that does not commute."
	<export>
	<var: #op type: 'int32_t'>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #type type: 'int64_t'>
	<var: #n type: 'int64_t'>
	| t |
	self shifted: rm type: type amount: n into: X64_R11.
	t := self dst: rd.
	t = X64_R11
		ifTrue: [
			self alu: op w: (self wide: rd) dst: X64_R11 src: rn.
			"r11 - rn: negate for rn - r11"
			op = 16r2B ifTrue: [self op: 16rF7 len: 1 pre: 0 w: (self wide: rd) reg: 3 rm: X64_R11 byte: false]]
		ifFalse: [
			self load: rn into: t.
			self op: op len: 1 pre: 0 w: (self wide: rd) reg: t rm: X64_R11 byte: false].
	self store: t into: rd.
	self clobberFlags
!
sub: rd with: rn with: rm shift: type amount: n
	self shiftedOp: 16r2B rd: rd rn: rn rm: rm shift: type amount: n
!
cmp: rn with: rm shift: type amount: n
	self cmpAny: rn with: rm shift: type amount: n.
	self setFlags: X64_FL_SUB
!
cmpAny: rn with: rm shift: type amount: n
	<export>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #type type: 'int64_t'>
	<var: #n type: 'int64_t'>
	self shifted: rm type: type amount: n into: X64_R11.
	(self isBase: rn) ifTrue: [^self op: 16r3B len: 1 pre: 0 w: (self wide: rn) reg: (self gpr: rn) rm: X64_R11 byte: false].
	(self isWord: rn) ifTrue: [^self op: 16r39 len: 1 pre: 0 w: (self wide: rn) reg: X64_R11 target: (self homeOf: rn) imm: 0 isz: 0].
	self fail: ASM_ERR_OPERAND
! !

!Amd64Assembler methodsFor: 'logical'!
logical: digit op: op rd: rd rn: rn imm: imm
	"rd := rn op imm (digit: 4 and, 1 or, 6 xor; op: the same with a register)."
	((self isPhys: rd) and: [(self isPhys: rn) and: [(self isW: rd) or: [self fitsImm32: imm asInt64]]]) ifTrue: [
		(self gpr: rd) ~= (self gpr: rn) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rn)].
		^self alu: digit w: (self wide: rd) dst: (self gpr: rd) imm: ((self isW: rd) ifTrue: [imm asUInt64 bitAnd: 16rFFFFFFFF] ifFalse: [imm asUInt64]) asInt64].
	self logicalAny: digit op: op rd: rd rn: rn imm: imm asUInt64
!
logicalAny: digit op: op rd: rd rn: rn imm: imm
	<export>
	<var: #digit type: 'int32_t'>
	<var: #op type: 'int32_t'>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #imm type: 'uint64_t'>
	| t w v |
	w := self wide: rd.
	v := w = 0 ifTrue: [imm bitAnd: 16rFFFFFFFF] ifFalse: [imm].
	t := self dst: rd.
	(digit = 4 and: [v = 16rFFFFFFFF and: [w = 1]]) ifTrue: [
		"and with the low 32 bits: a 32-bit move"
		self load: rn into: t.
		self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: t byte: false.
		^self store: t into: rd].
	(w = 0 or: [self fitsImm32: v asInt64])
		ifTrue: [
			self load: rn into: t.
			self alu: digit w: w dst: t imm: v asInt64]
		ifFalse: [
			t = X64_R11
				ifTrue: [
					self movReg: X64_R11 imm: v.
					self alu: op w: w dst: X64_R11 src: rn]
				ifFalse: [
					self load: rn into: t.
					self movReg: X64_R11 imm: v.
					self op: op len: 1 pre: 0 w: w reg: t rm: X64_R11 byte: false]].
	self store: t into: rd
!
and: rd with: rn imm: imm
	self logical: 4 op: 16r23 rd: rd rn: rn imm: imm.
	self clobberFlags
!
orr: rd with: rn imm: imm
	self logical: 1 op: 16r0B rd: rd rn: rn imm: imm.
	self clobberFlags
!
eor: rd with: rn imm: imm
	self logical: 6 op: 16r33 rd: rd rn: rn imm: imm.
	self clobberFlags
!
ands: rd with: rn imm: imm
	(rd bitAnd: 31 + REG_SP + REG_D) = 31 ifTrue: [^self tst: rn imm: imm].
	self logical: 4 op: 16r23 rd: rd rn: rn imm: imm.
	self setFlags: X64_FL_LOGIC
!
bic: rd with: rn imm: imm
	self and: rd with: rn imm: imm asUInt64 bitInvert64
!
tst: rn imm: imm
	"test: byte, 32-bit or 64-bit as the mask allows (a narrow form only if the mask's top bit is clear, so that the sign flag is the 64-bit one's); one bit beyond a sign-extended immediate's reach, bt (the bit in the carry: only EQ and NE can be read)."
	| v n |
	v := (self isW: rn) ifTrue: [imm asUInt64 bitAnd: 16rFFFFFFFF] ifFalse: [imm asUInt64].
	((self isW: rn) not and: [v > 16r7FFFFFFF and: [(v bitAnd: v - 1) = 0]]) ifTrue: [
		n := 31.
		[(v >> n) > 1] whileTrue: [n := n + 1].
		self op: 16rBA0F len: 2 pre: 0 w: 1 reg: 4 rm: (self source: rn) imm: n asInt64 isz: 1.
		^self setFlags: X64_FL_BT].
	((self isPhys: rn) and: [v <= 16r7FFFFFFF])
		ifTrue: [
			v <= 16r7F
				ifTrue: [self op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: (self gpr: rn) imm: v isz: 1]
				ifFalse: [self op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 rm: (self gpr: rn) imm: v isz: 4]]
		ifFalse: [self testAny: rn imm: v].
	self setFlags: X64_FL_LOGIC
!
testAny: rn imm: v
	<export>
	<var: #rn type: 'int64_t'>
	<var: #v type: 'uint64_t'>
	| r |
	(self isWord: rn) ifTrue: [
		v <= 16r7F ifTrue: [^self op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 target: (self homeOf: rn) imm: v asInt64 isz: 1].
		(v <= 16r7FFFFFFF or: [(self isW: rn) not and: [self fitsImm32: v asInt64]]) ifTrue: [
			^self op: 16rF7 len: 1 pre: 0 w: (v <= 16r7FFFFFFF ifTrue: [0] ifFalse: [1]) reg: 0 target: (self homeOf: rn) imm: v asInt64 isz: 4].
		self movReg: X64_R11 imm: v.
		^self op: 16r85 len: 1 pre: 0 w: (self wide: rn) reg: X64_R11 target: (self homeOf: rn) imm: 0 isz: 0].
	r := self source: rn.
	v <= 16r7F ifTrue: [^self op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: r imm: v asInt64 isz: 1].
	v <= 16r7FFFFFFF ifTrue: [^self op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 rm: r imm: v asInt64 isz: 4].
	((self isW: rn) not and: [self fitsImm32: v asInt64]) ifTrue: [^self op: 16rF7 len: 1 pre: 0 w: 1 reg: 0 rm: r imm: v asInt64 isz: 4].
	r = X64_R11 ifTrue: [^self fail: ASM_ERR_OPERAND].
	self movReg: X64_R11 imm: v.
	self op: 16r85 len: 1 pre: 0 w: (self wide: rn) reg: X64_R11 rm: r byte: false
!
and: rd with: rn with: rm
	self binary: 16r23 rd: rd rn: rn rm: rm commutes: true.
	self clobberFlags
!
orr: rd with: rn with: rm
	self binary: 16r0B rd: rd rn: rn rm: rm commutes: true.
	self clobberFlags
!
eor: rd with: rn with: rm
	self binary: 16r33 rd: rd rn: rn rm: rm commutes: true.
	self clobberFlags
!
ands: rd with: rn with: rm
	(rd bitAnd: 31 + REG_SP + REG_D) = 31 ifTrue: [^self tst: rn with: rm].
	self binary: 16r23 rd: rd rn: rn rm: rm commutes: true.
	self setFlags: X64_FL_LOGIC
!
tst: rn with: rm
	((self isPhys: rn) and: [self isPhys: rm])
		ifTrue: [self op: 16r85 len: 1 pre: 0 w: (self wide: rn) reg: (self gpr: rm) rm: (self gpr: rn) byte: false]
		ifFalse: [self testAny: rn with: rm].
	self setFlags: X64_FL_LOGIC
!
testAny: rn with: rm
	<export>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	"test r/m, reg: either may be the word"
	((self isWord: rn) and: [self isPhys: rm]) ifTrue: [^self op: 16r85 len: 1 pre: 0 w: (self wide: rn) reg: (self gpr: rm) target: (self homeOf: rn) imm: 0 isz: 0].
	self alu: 16r85 w: (self wide: rn) dst: (self source: rn) src: rm
!
and: rd with: rn with: rm shift: type amount: n
	self shiftedOp: 16r23 rd: rd rn: rn rm: rm shift: type amount: n
!
orr: rd with: rn with: rm shift: type amount: n
	self shiftedOp: 16r0B rd: rd rn: rn rm: rm shift: type amount: n
!
eor: rd with: rn with: rm shift: type amount: n
	self shiftedOp: 16r33 rd: rd rn: rn rm: rm shift: type amount: n
!
mvn: rd with: rm
	| t |
	t := self dst: rd.
	self load: rm into: t.
	self op: 16rF7 len: 1 pre: 0 w: (self wide: rd) reg: 2 rm: t byte: false.
	self store: t into: rd
! !

!Amd64Assembler methodsFor: 'shifts and bitfields'!
shift: digit rd: rd rn: rn imm: s
	| t |
	((self isPhys: rd) and: [self isPhys: rn]) ifTrue: [
		(self gpr: rd) ~= (self gpr: rn) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rn)].
		s ~= 0
			ifTrue: [
				self shift: digit w: (self wide: rd) reg: (self gpr: rd) by: s.
				self clobberFlags]
			ifFalse: [(self isW: rd) ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: (self gpr: rd) rm: (self gpr: rd) byte: false]].
		^self].
	t := self dst: rd.
	self load: rn into: t.
	s ~= 0
		ifTrue: [
			self shift: digit w: (self wide: rd) reg: t by: s.
			self clobberFlags]
		ifFalse: [(self isW: rd) ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: t byte: false]].
	self store: t into: rd
!
lsl: rd with: rn imm: s
	self shift: 4 rd: rd rn: rn imm: s
!
lsr: rd with: rn imm: s
	self shift: 5 rd: rd rn: rn imm: s
!
asr: rd with: rn imm: s
	self shift: 7 rd: rd rn: rn imm: s
!
ror: rd with: rn imm: s
	self shift: 1 rd: rd rn: rn imm: s
!
shift: digit rd: rd rn: rn rm: rm
	"rd := rn shifted by rm (modulo the width, as both arm64 and x86 do it): the count must be in cl (rcx, x3's), saved around it."
	<export>
	<var: #digit type: 'int32_t'>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	| t w rnIsRcx |
	w := self wide: rd.
	t := ((self isPhys: rd) and: [(self gpr: rd) ~= X64_RCX]) ifTrue: [self gpr: rd] ifFalse: [X64_R11].
	((self isPhys: rm) and: [(self gpr: rm) = X64_RCX]) ifTrue: [
		self load: rn into: t.
		self op: 16rD3 len: 1 pre: 0 w: w reg: digit rm: t byte: false.
		self clobberFlags.
		^self store: t into: rd].
	"push rcx; rcx := rm; t := rn (x3's old value from the stack); shift; pop rcx"
	rnIsRcx := (self isPhys: rn) and: [(self gpr: rn) = X64_RCX].
	self emitBytes: 16r51 count: 1.
	self load: rm into: X64_RCX.
	rnIsRcx
		ifTrue: [self op: 16r8B len: 1 pre: 0 w: 1 reg: t base: X64_RSP disp: 0 imm: 0 isz: 0 byte: false]
		ifFalse: [self load: rn into: t].
	self op: 16rD3 len: 1 pre: 0 w: w reg: digit rm: t byte: false.
	self emitBytes: 16r59 count: 1.
	self clobberFlags.
	self store: t into: rd
!
lsl: rd with: rn with: rm
	self shift: 4 rd: rd rn: rn rm: rm
!
lsr: rd with: rn with: rm
	self shift: 5 rd: rd rn: rn rm: rm
!
asr: rd with: rn with: rm
	self shift: 7 rd: rd rn: rn rm: rm
!
ror: rd with: rn with: rm
	self shift: 1 rd: rd rn: rn rm: rm
!
ubfx: rd with: rn lsb: lsb width: wd
	"rd := wd bits of rn from bit lsb, zero-extended."
	((self isPhys: rd) and: [(self isPhys: rn) and: [(self isW: rd) not and: [lsb + wd < 64 and: [wd < 32 and: [lsb >= 0 and: [wd >= 1]]]]]]) ifTrue: [
		(self gpr: rd) ~= (self gpr: rn) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rn)].
		lsb > 0 ifTrue: [self shift: 5 w: 1 reg: (self gpr: rd) by: lsb].
		self alu: 4 w: 0 dst: (self gpr: rd) imm: (1 asInt64 << wd) - 1.
		^self clobberFlags].
	self ubfxAny: rd with: rn lsb: lsb width: wd
!
ubfxAny: rd with: rn lsb: lsb width: wd
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #lsb type: 'int64_t'>
	<var: #wd type: 'int64_t'>
	| t bits |
	bits := (self isW: rd) ifTrue: [32] ifFalse: [64].
	((lsb >= 0 and: [wd >= 1]) and: [lsb + wd <= bits]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	t := self dst: rd.
	(lsb = 0 and: [wd = 32 and: [self isPhys: rn]]) ifTrue: [
		"the low half: mov t32, rn32 (zero-extends; the flags stay)"
		self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: (self gpr: rn) byte: false.
		^self store: t into: rd].
	self load: rn into: t.
	lsb + wd = bits
		ifTrue: [
			lsb > 0 ifTrue: [self shift: 5 w: (self wide: rd) reg: t by: lsb].
			(lsb = 0 and: [bits = 32]) ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: t byte: false]]
		ifFalse: [
			wd = 32
				ifTrue: [
					lsb > 0 ifTrue: [self shift: 5 w: 1 reg: t by: lsb].
					self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: t byte: false]
				ifFalse: [
					wd < 32
						ifTrue: [
							lsb > 0 ifTrue: [self shift: 5 w: (self wide: rd) reg: t by: lsb].
							self alu: 4 w: 0 dst: t imm: (1 asInt64 << wd) - 1]
						ifFalse: [
							self shift: 4 w: 1 reg: t by: 64 - lsb - wd.
							self shift: 5 w: 1 reg: t by: 64 - wd]]].
	self clobberFlags.
	self store: t into: rd
!
sbfx: rd with: rn lsb: lsb width: wd
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #lsb type: 'int64_t'>
	<var: #wd type: 'int64_t'>
	| t bits |
	bits := (self isW: rd) ifTrue: [32] ifFalse: [64].
	((lsb >= 0 and: [wd >= 1]) and: [lsb + wd <= bits]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	t := self dst: rd.
	self load: rn into: t.
	bits - lsb - wd > 0 ifTrue: [self shift: 4 w: (self wide: rd) reg: t by: bits - lsb - wd].
	bits - wd > 0 ifTrue: [self shift: 7 w: (self wide: rd) reg: t by: bits - wd].
	self clobberFlags.
	self store: t into: rd
!
ubfiz: rd with: rn lsb: lsb width: wd
	"rd := the low wd bits of rn, shifted to bit lsb."
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #lsb type: 'int64_t'>
	<var: #wd type: 'int64_t'>
	| t bits |
	bits := (self isW: rd) ifTrue: [32] ifFalse: [64].
	((lsb >= 0 and: [wd >= 1]) and: [lsb + wd <= bits]) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	t := self dst: rd.
	self load: rn into: t.
	bits - wd > 0 ifTrue: [self shift: 4 w: (self wide: rd) reg: t by: bits - wd].
	bits - wd - lsb > 0 ifTrue: [self shift: 5 w: (self wide: rd) reg: t by: bits - wd - lsb].
	self clobberFlags.
	self store: t into: rd
!
sxtw: rd with: rn
	"movsxd"
	| t |
	t := self dst: rd.
	self op: 16r63 len: 1 pre: 0 w: 1 reg: t rm: (self source: rn) byte: false.
	self store: t into: rd
!
uxtb: rd with: rn
	| t |
	t := self dst: rd.
	self load: rn into: t.
	self op: 16rB60F len: 2 pre: 0 w: 0 reg: t rm: t byte: true.
	self store: t into: rd
! !

!Amd64Assembler methodsFor: 'multiply and divide'!
mul: rd with: rn with: rm
	"imul (arm64's mul leaves the flags alone: these are destroyed)."
	((self isPhys: rd) and: [(self isPhys: rn) and: [(self isPhys: rm) and: [(self gpr: rd) ~= (self gpr: rm) or: [(self gpr: rd) = (self gpr: rn)]]]])
		ifTrue: [
			(self gpr: rd) ~= (self gpr: rn) ifTrue: [self movReg: (self gpr: rd) from: (self gpr: rn)].
			self op: 16rAF0F len: 2 pre: 0 w: (self wide: rd) reg: (self gpr: rd) rm: (self gpr: rm) byte: false]
		ifFalse: [self mulAny: rd with: rn with: rm].
	self clobberFlags
!
mulAny: rd with: rn with: rm
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	self load: rn into: X64_R11.
	(self isPhys: rm)
		ifTrue: [self op: 16rAF0F len: 2 pre: 0 w: (self wide: rd) reg: X64_R11 rm: (self gpr: rm) byte: false]
		ifFalse: [
			(self isWord: rm)
				ifTrue: [self op: 16rAF0F len: 2 pre: 0 w: (self wide: rd) reg: X64_R11 target: (self homeOf: rm) imm: 0 isz: 0]
				ifFalse: [
					(self kind: rm) = X64_K_ZERO ifFalse: [^self fail: ASM_ERR_OPERAND].
					self movReg32: X64_R11 imm: 0]].
	(self isW: rd) ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: X64_R11 rm: X64_R11 byte: false].
	self store: X64_R11 into: rd
!
madd: rd with: rn with: rm add: ra
	"rd := ra + rn * rm"
	self multiply: rn by: rm.
	self multiplyAdd: rd sub: false ra: ra
!
msub: rd with: rn with: rm sub: ra
	"rd := ra - rn * rm"
	self multiply: rn by: rm.
	self multiplyAdd: rd sub: true ra: ra
!
multiply: rn by: rm
	"r11 := rn * rm"
	<export>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	self load: rn into: X64_R11.
	(self isPhys: rm)
		ifTrue: [self op: 16rAF0F len: 2 pre: 0 w: 1 reg: X64_R11 rm: (self gpr: rm) byte: false]
		ifFalse: [
			(self isWord: rm)
				ifTrue: [self op: 16rAF0F len: 2 pre: 0 w: 1 reg: X64_R11 target: (self homeOf: rm) imm: 0 isz: 0]
				ifFalse: [
					(self kind: rm) = X64_K_ZERO ifFalse: [^self fail: ASM_ERR_OPERAND].
					self movReg32: X64_R11 imm: 0]]
!
multiplyAdd: rd sub: isSub ra: ra
	"rd := ra + r11 (or ra - r11)."
	<export>
	<var: #rd type: 'int64_t'>
	<var: #isSub type: 'bool'>
	<var: #ra type: 'int64_t'>
	isSub
		ifTrue: [
			self alu: 16r2B w: (self wide: rd) dst: X64_R11 src: ra.
			self op: 16rF7 len: 1 pre: 0 w: (self wide: rd) reg: 3 rm: X64_R11 byte: false]
		ifFalse: [self alu: 16r03 w: (self wide: rd) dst: X64_R11 src: ra].
	self store: X64_R11 into: rd.
	self clobberFlags
!
wide: digit rd: rd rn: rn rm: rm
	"The rdx:rax instructions (digit: 5 imul (smulh: rdx), 4 mul (umulh: rdx), 7 idiv (sdiv: rax)), 64-bit: rax and rdx are saved around them; rd gets the half the instruction wants."
	<export>
	<var: #digit type: 'int32_t'>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	| result |
	(self isW: rd) ifTrue: [^self fail: ASM_ERR_OPERAND].
	result := digit = 7 ifTrue: [X64_RAX] ifFalse: [X64_RDX].
	"push rax; push rdx: rm and rn are read from there if they are rax or rdx"
	self emitBytes: 16r5250 count: 2.
	self loadSaved: rn into: X64_RAX.
	"cqo"
	digit = 7 ifTrue: [self emitBytes: 16r9948 count: 2].
	((self isPhys: rm) and: [(self gpr: rm) = X64_RAX or: [(self gpr: rm) = X64_RDX]])
		ifTrue: [self op: 16rF7 len: 1 pre: 0 w: 1 reg: digit base: X64_RSP disp: ((self gpr: rm) = X64_RAX ifTrue: [8] ifFalse: [0]) imm: 0 isz: 0 byte: false]
		ifFalse: [
			(self isPhys: rm)
				ifTrue: [self op: 16rF7 len: 1 pre: 0 w: 1 reg: digit rm: (self gpr: rm) byte: false]
				ifFalse: [
					self load: rm into: X64_R11.
					self op: 16rF7 len: 1 pre: 0 w: 1 reg: digit rm: X64_R11 byte: false]].
	self movReg: X64_R11 from: result.
	"pop rdx; pop rax"
	self emitBytes: 16r585A count: 2.
	self clobberFlags.
	self store: X64_R11 into: rd
!
loadSaved: r into: t
	"t := r, where rax and rdx were pushed (rax at [rsp + 8], rdx at [rsp])."
	((self isPhys: r) and: [(self gpr: r) = X64_RAX or: [(self gpr: r) = X64_RDX]])
		ifTrue: [self op: 16r8B len: 1 pre: 0 w: 1 reg: t base: X64_RSP disp: ((self gpr: r) = X64_RAX ifTrue: [8] ifFalse: [0]) imm: 0 isz: 0 byte: false]
		ifFalse: [self load: r into: t]
!
smulh: rd with: rn with: rm
	self wide: 5 rd: rd rn: rn rm: rm
!
umulh: rd with: rn with: rm
	self wide: 4 rd: rd rn: rn rm: rm
!
sdiv: rd with: rn with: rm
	"rd := rn / rm, truncated, as arm64 has it: x / 0 = 0 and the most negative / -1 = itself, where idiv traps."
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	| zero minus done t |
	zero := self newLabel.
	minus := self newLabel.
	done := self newLabel.
	self cmp: rm imm: 0.
	self jcc: 4 to: zero.
	self cmp: rm imm: -1.
	self jcc: 4 to: minus.
	self wide: 7 rd: rd rn: rn rm: rm.
	self jmpRel32To: done.
	self bind: minus.
	self neg: rd with: rn.
	self jmpRel32To: done.
	self bind: zero.
	t := self dst: rd.
	self movReg32: t imm: 0.
	self store: t into: rd.
	self bind: done.
	asmFlags := X64_FL_CLOBBERED
! !

!Amd64Assembler methodsFor: 'conditional select'!
csel: rd with: rn with: rm cond: c
	"rd := c ? rn : rm (cmov: the flags stay)"
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #c type: 'int64_t'>
	| cc t |
	cc := self cc: c.
	cc = -2 ifTrue: [^self fail: ASM_ERR_FLAGS].
	cc = -3 ifTrue: [^self mov: rd with: rn].
	t := self dst: rd.
	(cc = -1 or: [t = X64_R11 and: [(self isPhys: rn) not and: [(self isWord: rn) not]]]) ifTrue: [^self cselByBranch: rd with: rn with: rm cond: c].
	((self isPhys: rd) and: [(self isPhys: rn) and: [(self gpr: rd) = (self gpr: rn)]])
		ifTrue: [
			"rd holds rn: take rm unless c"
			self cmov: (cc bitXor: 1) t: t src: rm]
		ifFalse: [
			((self isPhys: rm) and: [(self gpr: rm) = t]) ifFalse: [self load: rm into: t].
			self cmov: cc t: t src: rn].
	(self isW: rd) ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: t byte: false].
	self store: t into: rd
!
cmov: cc t: t src: r
	"cmovcc t, r (r's register or word; xzr: a zeroed r11, so t must not be r11)"
	| k |
	k := self kind: r.
	k = X64_K_PHYS ifTrue: [^self op: (16r400F bitOr: cc asInt64 << 8) len: 2 pre: 0 w: 1 reg: t rm: (self gpr: r) byte: false].
	(k = X64_K_MEM or: [k = X64_K_STATEMEM]) ifTrue: [^self op: (16r400F bitOr: cc asInt64 << 8) asInt32 len: 2 pre: 0 w: 1 reg: t target: (self homeOf: r) imm: 0 isz: 0].
	(k = X64_K_ZERO and: [t ~= X64_R11]) ifTrue: [
		self movReg32: X64_R11 imm: 0.
		^self op: (16r400F bitOr: cc asInt64 << 8) len: 2 pre: 0 w: 1 reg: t rm: X64_R11 byte: false].
	(k = X64_K_STATE and: [t ~= X64_R11]) ifTrue: [
		self load: r into: X64_R11.
		^self op: (16r400F bitOr: cc asInt64 << 8) len: 2 pre: 0 w: 1 reg: t rm: X64_R11 byte: false].
	self fail: ASM_ERR_OPERAND
!
cselByBranch: rd with: rn with: rm cond: c
	"csel on a floating point condition that takes two tests."
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #c type: 'int64_t'>
	| taken done flags |
	flags := asmFlags.
	taken := self newLabel.
	done := self newLabel.
	self b: taken if: c.
	self mov: rd with: rm.
	self jmpRel32To: done.
	self bind: taken.
	self mov: rd with: rn.
	self bind: done.
	"mov and jmp keep the flags"
	asmFlags := flags
!
cset: rd cond: c
	"rd := c ? 1 : 0 (mov keeps the flags, setcc reads them)"
	<export>
	<var: #rd type: 'int64_t'>
	<var: #c type: 'int64_t'>
	| cc t pair |
	cc := self cc: c.
	cc = -2 ifTrue: [^self fail: ASM_ERR_FLAGS].
	cc = -3 ifTrue: [^self mov: rd imm: 1].
	t := self dst: rd.
	cc = -1
		ifTrue: [
			pair := self fpPair: c.
			t = X64_R11 ifTrue: [^self csetByBranch: rd cond: c].
			self movReg32: t imm: 0.
			self movReg32: X64_R11 imm: 0.
			self op: (16r900F bitOr: ((pair >> 8) bitAnd: 15) asInt64 << 8) len: 2 pre: 0 w: 0 reg: 0 rm: X64_R11 byte: true.
			self op: (16r900F bitOr: (pair bitAnd: 15) asInt64 << 8) len: 2 pre: 0 w: 0 reg: 0 rm: t byte: true.
			self op: ((pair bitAnd: 16r10000) ~= 0 ifTrue: [16r23] ifFalse: [16r0B]) len: 1 pre: 0 w: 0 reg: t rm: X64_R11 byte: false.
			self clobberFlags]
		ifFalse: [
			self movReg32: t imm: 0.
			self op: (16r900F bitOr: cc asInt64 << 8) len: 2 pre: 0 w: 0 reg: 0 rm: t byte: true].
	self store: t into: rd
!
csetByBranch: rd cond: c
	"rd := c ? 1 : 0 by a branch (mov keeps the flags)."
	<export>
	<var: #rd type: 'int64_t'>
	<var: #c type: 'int64_t'>
	| set done t flags |
	flags := asmFlags.
	set := self newLabel.
	done := self newLabel.
	t := self dst: rd.
	self movReg32: t imm: 0.
	self b: set if: c.
	self jmpRel32To: done.
	self bind: set.
	self movReg32: t imm: 1.
	self bind: done.
	asmFlags := flags.
	self store: t into: rd
!
csetm: rd cond: c
	"rd := c ? -1 : 0"
	| t |
	self cset: rd cond: c.
	t := self dst: rd.
	self load: rd into: t.
	self op: 16rF7 len: 1 pre: 0 w: (self wide: rd) reg: 3 rm: t byte: false.
	self store: t into: rd.
	self clobberFlags
!
csinc: rd with: rn with: rm cond: c
	"rd := c ? rn : rm + 1"
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #c type: 'int64_t'>
	| cc t |
	cc := self cc: c.
	cc = -2 ifTrue: [^self fail: ASM_ERR_FLAGS].
	t := self dst: rd.
	(cc < 0 or: [t = X64_R11]) ifTrue: [^self csincByBranch: rd with: rn with: rm cond: c].
	"r11 := rm + 1 (lea), t := rn, cmov(not c) t, r11"
	self load: rm into: X64_R11.
	self op: 16r8D len: 1 pre: 0 w: 1 reg: X64_R11 base: X64_R11 disp: 1 imm: 0 isz: 0 byte: false.
	self load: rn into: t.
	self op: (16r400F bitOr: (cc bitXor: 1) asInt64 << 8) len: 2 pre: 0 w: 1 reg: t rm: X64_R11 byte: false.
	(self isW: rd) ifTrue: [self op: 16r8B len: 1 pre: 0 w: 0 reg: t rm: t byte: false].
	self store: t into: rd
!
csincByBranch: rd with: rn with: rm cond: c
	"rd := c ? rn : rm + 1 by a branch (mov and lea keep the flags)."
	<export>
	<var: #rd type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #c type: 'int64_t'>
	| taken done flags |
	flags := asmFlags.
	taken := self newLabel.
	done := self newLabel.
	self b: taken if: c.
	self addAny: rd with: rm imm: 1.
	(self isW: rd) ifTrue: [self mov: rd with: rd].
	self jmpRel32To: done.
	self bind: taken.
	self mov: rd with: rn.
	self bind: done.
	asmFlags := flags
!
cinc: rd with: rn cond: c
	self csinc: rd with: rn with: rn cond: (c bitXor: 1)
! !

!Amd64Assembler methodsFor: 'loads and stores'!
ldr: rt base: rn offset: off
	((self isPhys: rt) and: [self isBase: rn]) ifTrue: [
		^self op: 16r8B len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: false].
	((self isD: rt) and: [self isBase: rn]) ifTrue: [
		^self op: 16r100F len: 2 pre: 16rF2 w: 0 reg: (self xmm: rt) base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: false].
	self loadAny: 16r8B len: 1 w: (self wide: rt) rt: rt base: rn offset: off asInt64
!
ldur: rt base: rn offset: off
	self ldr: rt base: rn offset: off
!
ldrb: rt base: rn offset: off
	((self isPhys: rt) and: [self isBase: rn]) ifTrue: [
		^self op: 16rB60F len: 2 pre: 0 w: 0 reg: (self gpr: rt) base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: false].
	self loadAny: 16rB60F len: 2 w: 0 rt: rt base: rn offset: off asInt64
!
ldurb: rt base: rn offset: off
	self ldrb: rt base: rn offset: off
!
ldrh: rt base: rn offset: off
	self loadAny: 16rB70F len: 2 w: 0 rt: rt base: rn offset: off asInt64
!
ldrsb: rt base: rn offset: off
	self loadAny: 16rBE0F len: 2 w: (self wide: rt) rt: rt base: rn offset: off asInt64
!
ldrsh: rt base: rn offset: off
	self loadAny: 16rBF0F len: 2 w: (self wide: rt) rt: rt base: rn offset: off asInt64
!
ldrsw: rt base: rn offset: off
	self loadAny: 16r63 len: 1 w: 1 rt: rt base: rn offset: off asInt64
!
loadAny: op len: olen w: w rt: rt base: rn offset: off
	"rt := what x86 op loads from [rn + off], for any base and destination."
	<export>
	<var: #op type: 'int32_t'>
	<var: #olen type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #rt type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #off type: 'int64_t'>
	| t k |
	(self isD: rt) ifTrue: [^self memory: 16r100F len: 2 pre: 16rF2 w: 0 reg: (self xmm: rt) base: rn offset: off byte: false].
	(self isRecord: rt) ifTrue: [^self fail: ASM_ERR_OPERAND].
	"x22-x25 are the JitState and its words: loading them (after a call, where a collection may have moved nil, true, false) is nothing"
	((self kind: rt) = X64_K_STATE or: [(self kind: rt) = X64_K_STATEMEM]) ifTrue: [^self].
	t := self dst: rt.
	k := self kind: rn.
	(t = X64_R11 and: [k = X64_K_MEM or: [k = X64_K_STATEMEM]])
		ifTrue: [
			self load: rn into: X64_R11.
			self op: op len: olen pre: 0 w: w reg: X64_R11 base: X64_R11 disp: off imm: 0 isz: 0 byte: false]
		ifFalse: [self memory: op len: olen pre: 0 w: w reg: t base: rn offset: off byte: false].
	self store: t into: rt
!
memory: op len: olen pre: pre w: w reg: reg base: rn offset: off byte: isByte
	"x86 op reg, [rn + off] for any arm64 base rn: its register, rsp, the JitState (pc-relative), or a word (into r11 first: reg must not be r11 then)."
	<export>
	<var: #op type: 'int32_t'>
	<var: #olen type: 'int32_t'>
	<var: #pre type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #reg type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<var: #isByte type: 'bool'>
	| k |
	k := self kind: rn.
	(k = X64_K_PHYS or: [k = X64_K_SP]) ifTrue: [^self op: op len: olen pre: pre w: w reg: reg base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: isByte].
	k = X64_K_STATE ifTrue: [^self op: op len: olen pre: pre w: w reg: reg target: asmState + off asUInt64 imm: 0 isz: 0].
	(k = X64_K_MEM or: [k = X64_K_STATEMEM]) ifTrue: [
		reg = X64_R11 ifTrue: [^self fail: ASM_ERR_OPERAND].
		self load: rn into: X64_R11.
		^self op: op len: olen pre: pre w: w reg: reg base: X64_R11 disp: off imm: 0 isz: 0 byte: isByte].
	self fail: ASM_ERR_OPERAND
!
str: rt base: rn offset: off
	((self isPhys: rt) and: [self isBase: rn]) ifTrue: [
		^self op: 16r89 len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: false].
	((self isD: rt) and: [self isBase: rn]) ifTrue: [
		^self op: 16r110F len: 2 pre: 16rF2 w: 0 reg: (self xmm: rt) base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: false].
	self storeAny: 16r89 pre: 0 w: (self wide: rt) rt: rt base: rn offset: off asInt64 byte: false
!
stur: rt base: rn offset: off
	self str: rt base: rn offset: off
!
strb: rt base: rn offset: off
	((self isPhys: rt) and: [self isBase: rn]) ifTrue: [
		^self op: 16r88 len: 1 pre: 0 w: 0 reg: (self gpr: rt) base: (self gpr: rn) disp: off imm: 0 isz: 0 byte: true].
	self storeAny: 16r88 pre: 0 w: 0 rt: rt base: rn offset: off asInt64 byte: true
!
sturb: rt base: rn offset: off
	self strb: rt base: rn offset: off
!
strh: rt base: rn offset: off
	self storeAny: 16r89 pre: 16r66 w: 0 rt: rt base: rn offset: off asInt64 byte: false
!
storeAny: op pre: pre w: w rt: rt base: rn offset: off byte: isByte
	"[rn + off] := rt by x86 op (a mov to memory), for any base and source."
	<export>
	<var: #op type: 'int32_t'>
	<var: #pre type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #rt type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<var: #isByte type: 'bool'>
	| k kb |
	(self isD: rt) ifTrue: [^self memory: 16r110F len: 2 pre: 16rF2 w: 0 reg: (self xmm: rt) base: rn offset: off byte: false].
	k := self kind: rt.
	kb := self kind: rn.
	k = X64_K_PHYS ifTrue: [^self memory: op len: 1 pre: pre w: w reg: (self gpr: rt) base: rn offset: off byte: isByte].
	(k = X64_K_ZERO and: [op = 16r89 and: [pre = 0]]) ifTrue: [
		"mov dword or qword [m], 0"
		(kb = X64_K_PHYS or: [kb = X64_K_SP]) ifTrue: [^self op: 16rC7 len: 1 pre: 0 w: w reg: 0 base: (self gpr: rn) disp: off imm: 0 isz: 4 byte: false].
		kb = X64_K_STATE ifTrue: [^self op: 16rC7 len: 1 pre: 0 w: w reg: 0 target: asmState + off asUInt64 imm: 0 isz: 4].
		self load: rn into: X64_R11.
		^self op: 16rC7 len: 1 pre: 0 w: w reg: 0 base: X64_R11 disp: off imm: 0 isz: 4 byte: false].
	(kb = X64_K_PHYS or: [kb = X64_K_SP or: [kb = X64_K_STATE]]) ifTrue: [
		"r11 := rt, unless the instruction just before (no label since) stored rt from r11: nil, true or false into one slot after the other"
		(asmR11Pc = asmPc and: [asmR11Reg = rt]) ifFalse: [self load: rt into: X64_R11].
		self memory: op len: 1 pre: pre w: w reg: X64_R11 base: rn offset: off byte: isByte.
		(k = X64_K_STATEMEM or: [k = X64_K_MEM]) ifTrue: [
			asmR11Reg := rt.
			asmR11Pc := asmPc].
		^self].
	"base and value both without registers: push rax; rax := rn; r11 := rt; store; pop rax"
	self emitBytes: 16r50 count: 1.
	self load: rn into: X64_RAX.
	self load: rt into: X64_R11.
	self op: op len: 1 pre: pre w: w reg: X64_R11 base: X64_RAX disp: off imm: 0 isz: 0 byte: isByte.
	self emitBytes: 16r58 count: 1
!
isRecord: r
	"x29 or x30: the frame record, which the return address call pushed is here."
	^(r bitAnd: 31 + REG_SP + REG_D) = 29 or: [(r bitAnd: 31 + REG_SP + REG_D) = 30]
!
ldr: rt base: rn preIndex: off
	(self isRecord: rt) ifTrue: [^self].
	self add: rn with: rn imm: off.
	self ldr: rt base: rn offset: 0
!
ldr: rt base: rn postIndex: off
	"x30 popped (its push was nothing here): nothing."
	(self isRecord: rt) ifTrue: [^self].
	((rn bitAnd: 31 + REG_SP + REG_D) = (31 + REG_SP) and: [off = 16 and: [(self isD: rt) not and: [(self isW: rt) not]]]) ifTrue: [
		self pop: rt.
		^self add: rn with: rn imm: 8].
	self ldr: rt base: rn offset: 0.
	self add: rn with: rn imm: off
!
str: rt base: rn preIndex: off
	(self isRecord: rt) ifTrue: [^self].
	self add: rn with: rn imm: off.
	self str: rt base: rn offset: 0
!
str: rt base: rn postIndex: off
	(self isRecord: rt) ifTrue: [^self].
	self str: rt base: rn offset: 0.
	self add: rn with: rn imm: off
!
ldrb: rt base: rn postIndex: off
	self ldrb: rt base: rn offset: 0.
	self add: rn with: rn imm: off
!
strb: rt base: rn postIndex: off
	self strb: rt base: rn offset: 0.
	self add: rn with: rn imm: off
!
ldr: rt base: rn index: rm extend: ext shift: n
	((self isPhys: rt) and: [(self isBase: rn) and: [(self isPhys: rm) and: [ext = EXT_LSL]]]) ifTrue: [
		^self op: 16r8B len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: 0 byte: false].
	self indexedAny: 16r8B len: 1 pre: 0 w: (self wide: rt) rt: rt base: rn index: rm extend: ext shift: n load: true
!
ldr: rt base: rn index: rm
	self ldr: rt base: rn index: rm extend: EXT_LSL shift: 0
!
str: rt base: rn index: rm extend: ext shift: n
	((self isPhys: rt) and: [(self isBase: rn) and: [(self isPhys: rm) and: [ext = EXT_LSL]]]) ifTrue: [
		^self op: 16r89 len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: 0 byte: false].
	self indexedAny: 16r89 len: 1 pre: 0 w: (self wide: rt) rt: rt base: rn index: rm extend: ext shift: n load: false
!
str: rt base: rn index: rm
	self str: rt base: rn index: rm extend: EXT_LSL shift: 0
!
ldrb: rt base: rn index: rm
	self ldrb: rt base: rn index: rm extend: EXT_LSL shift: 0
!
ldrb: rt base: rn index: rm offset: d
	"x86's own (the code generators branch on isX64): rt := the byte at rn + rm + d, zero-extended; rt, rn and rm registers of x86's."
	((self isPhys: rt) and: [(self isBase: rn) and: [self isPhys: rm]]) ifFalse: [^self fail: ASM_ERR_OPERAND].
	self op: 16rB60F len: 2 pre: 0 w: 0 reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: 0 disp: d byte: false
!
strb: rt base: rn index: rm offset: d
	"x86's own: the byte at rn + rm + d := rt's low byte; registers of x86's."
	((self isPhys: rt) and: [(self isBase: rn) and: [self isPhys: rm]]) ifFalse: [^self fail: ASM_ERR_OPERAND].
	self op: 16r88 len: 1 pre: 0 w: 0 reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: 0 disp: d byte: true
!
ldr: rt base: rn index: rm shift: n offset: d
	"x86's own: rt := the word at rn + (rm << n) + d; registers of x86's."
	((self isPhys: rt) and: [(self isBase: rn) and: [self isPhys: rm]]) ifFalse: [^self fail: ASM_ERR_OPERAND].
	self op: 16r8B len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: d byte: false
!
str: rt base: rn index: rm shift: n offset: d
	"x86's own: the word at rn + (rm << n) + d := rt; rn and rm registers of x86's, rt any general register (one without, such as nil's x23, through r11)."
	((self isBase: rn) and: [self isPhys: rm]) ifFalse: [^self fail: ASM_ERR_OPERAND].
	(self isPhys: rt) ifFalse: [
		self load: rt into: X64_R11.
		^self op: 16r89 len: 1 pre: 0 w: (self wide: rt) reg: X64_R11 base: (self gpr: rn) index: (self gpr: rm) scale: n disp: d byte: false].
	self op: 16r89 len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: d byte: false
!
ldrb: rt base: rn index: rm extend: ext shift: n
	((self isPhys: rt) and: [(self isBase: rn) and: [(self isPhys: rm) and: [ext = EXT_LSL]]]) ifTrue: [
		^self op: 16rB60F len: 2 pre: 0 w: 0 reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: 0 byte: false].
	self indexedAny: 16rB60F len: 2 pre: 0 w: 0 rt: rt base: rn index: rm extend: ext shift: n load: true
!
strb: rt base: rn index: rm
	self strb: rt base: rn index: rm extend: EXT_LSL shift: 0
!
strb: rt base: rn index: rm extend: ext shift: n
	((self isPhys: rt) and: [(self isBase: rn) and: [(self isPhys: rm) and: [ext = EXT_LSL]]]) ifTrue: [
		^self op: 16r88 len: 1 pre: 0 w: 0 reg: (self gpr: rt) base: (self gpr: rn) index: (self gpr: rm) scale: n disp: 0 byte: true].
	self indexedAny: 16r88 len: 1 pre: 0 w: 0 rt: rt base: rn index: rm extend: ext shift: n load: false
!
ldrh: rt base: rn index: rm extend: ext shift: n
	self indexedAny: 16rB70F len: 2 pre: 0 w: 0 rt: rt base: rn index: rm extend: ext shift: n load: true
!
strh: rt base: rn index: rm extend: ext shift: n
	self indexedAny: 16r89 len: 1 pre: 16r66 w: 0 rt: rt base: rn index: rm extend: ext shift: n load: false
!
indexedAny: op len: olen pre: pre w: w rt: rt base: rn index: rm extend: ext shift: n load: isLoad
	"x86 op between rt and [rn + rm << n] (rm extended as ext says), for any registers: the address into r11 unless base and index have registers."
	<export>
	<var: #op type: 'int32_t'>
	<var: #olen type: 'int32_t'>
	<var: #pre type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #rt type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #ext type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #isLoad type: 'bool'>
	| reg isByte |
	isByte := op = 16r88.
	(self isD: rt)
		ifTrue: [reg := self xmm: rt]
		ifFalse: [
			(self isPhys: rt)
				ifTrue: [reg := self gpr: rt]
				ifFalse: [
					isLoad
						ifTrue: [reg := X64_R11]
						ifFalse: [
							"a store of a word or xzr: the address on the stack"
							^self storeIndexedWord: op pre: pre w: w rt: rt base: rn index: rm extend: ext shift: n]]].
	"r11 := rn + (rm extended) << n"
	self indexAddress: rn index: rm extend: ext shift: n.
	(self isD: rt)
		ifTrue: [self op: (op = 16r8B ifTrue: [16r100F] ifFalse: [16r110F]) len: 2 pre: 16rF2 w: 0 reg: reg base: X64_R11 disp: 0 imm: 0 isz: 0 byte: false]
		ifFalse: [self op: op len: olen pre: pre w: w reg: reg base: X64_R11 disp: 0 imm: 0 isz: 0 byte: isByte].
	(isLoad and: [(self isPhys: rt) not and: [(self isD: rt) not]]) ifTrue: [self store: X64_R11 into: rt]
!
storeIndexedWord: op pre: pre w: w rt: rt base: rn index: rm extend: ext shift: n
	"[rn + rm << n] := rt, a word or xzr: push the address, rt into r11, pop the address into... (no second scratch): via rsp."
	<export>
	<var: #op type: 'int32_t'>
	<var: #pre type: 'int32_t'>
	<var: #w type: 'int32_t'>
	<var: #rt type: 'int64_t'>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #ext type: 'int64_t'>
	<var: #n type: 'int64_t'>
	"push rax; rax := address; r11 := rt; store; pop rax"
	self emitBytes: 16r50 count: 1.
	self indexAddress: rn index: rm extend: ext shift: n.
	self movReg: X64_RAX from: X64_R11.
	self load: rt into: X64_R11.
	self op: op len: 1 pre: pre w: w reg: X64_R11 base: X64_RAX disp: 0 imm: 0 isz: 0 byte: op = 16r88.
	self emitBytes: 16r58 count: 1
!
indexAddress: rn index: rm extend: ext shift: n
	"r11 := rn + (rm, extended as ext says) << n"
	<export>
	<var: #rn type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #ext type: 'int64_t'>
	<var: #n type: 'int64_t'>
	| x b |
	(ext = EXT_UXTW or: [ext = EXT_SXTW])
		ifTrue: [
			ext = EXT_UXTW
				ifTrue: [
					self load: rm into: X64_R11.
					self op: 16r8B len: 1 pre: 0 w: 0 reg: X64_R11 rm: X64_R11 byte: false]
				ifFalse: [self op: 16r63 len: 1 pre: 0 w: 1 reg: X64_R11 rm: (self source: rm) byte: false].
			x := X64_R11]
		ifFalse: [x := self source: rm].
	(self isBase: rn)
		ifTrue: [b := self gpr: rn]
		ifFalse: [
			x = X64_R11 ifTrue: [
				"index first, then add the base's word"
				n > 0 ifTrue: [self shift: 4 w: 1 reg: X64_R11 by: n].
				self alu: 16r03 w: 1 dst: X64_R11 src: rn.
				^self clobberFlags].
			self load: rn into: X64_R11.
			b := X64_R11].
	self op: 16r8D len: 1 pre: 0 w: 1 reg: X64_R11 base: b index: x scale: n disp: 0 byte: false
!
push: r
	"push r (any general register)"
	<export>
	<var: #r type: 'int64_t'>
	| k |
	k := self kind: r.
	k = X64_K_PHYS ifTrue: [
		(self gpr: r) >= 8
			ifTrue: [^self emitBytes: (16r41 bitOr: (16r50 + ((self gpr: r) bitAnd: 7)) asInt64 << 8) asUInt64 count: 2]
			ifFalse: [^self emitBytes: (16r50 + (self gpr: r)) asUInt64 count: 1]].
	(k = X64_K_MEM or: [k = X64_K_STATEMEM]) ifTrue: [^self op: 16rFF len: 1 pre: 0 w: 0 reg: 6 target: (self homeOf: r) imm: 0 isz: 0].
	self load: r into: X64_R11.
	"push r11"
	self emitBytes: 16r5341 count: 2
!
pop: r
	<export>
	<var: #r type: 'int64_t'>
	| k |
	k := self kind: r.
	k = X64_K_PHYS ifTrue: [
		(self gpr: r) >= 8
			ifTrue: [^self emitBytes: (16r41 bitOr: (16r58 + ((self gpr: r) bitAnd: 7)) asInt64 << 8) asUInt64 count: 2]
			ifFalse: [^self emitBytes: (16r58 + (self gpr: r)) asUInt64 count: 1]].
	k = X64_K_MEM ifTrue: [^self op: 16r8F len: 1 pre: 0 w: 0 reg: 0 target: (self homeOf: r) imm: 0 isz: 0].
	self fail: ASM_ERR_OPERAND
!
ldp: rt with: rt2 base: rn offset: off
	"Two loads (the second first if the first's register is the base)."
	| step |
	step := (self isW: rt) ifTrue: [4] ifFalse: [8].
	((self isPhys: rt) and: [(self isPhys: rn) and: [(self gpr: rt) = (self gpr: rn)]])
		ifTrue: [
			self ldr: rt2 base: rn offset: off + step.
			self ldr: rt base: rn offset: off]
		ifFalse: [
			self ldr: rt base: rn offset: off.
			self ldr: rt2 base: rn offset: off + step]
!
stp: rt with: rt2 base: rn offset: off
	| step |
	step := (self isW: rt) ifTrue: [4] ifFalse: [8].
	self str: rt base: rn offset: off.
	self str: rt2 base: rn offset: off + step
!
stp: rt with: rt2 base: rn preIndex: off
	"Onto sp, 16 bytes: two pushes (x29 and x30 dropped: the return address call pushed is the frame record); else rn := rn + off and two stores."
	((rn bitAnd: 31 + REG_SP + REG_D) = (31 + REG_SP) and: [off = -16 and: [(self isD: rt) not]]) ifTrue: [
		(self isRecord: rt2) ifFalse: [self push: rt2].
		(self isRecord: rt) ifFalse: [self push: rt].
		^self].
	self add: rn with: rn imm: off.
	self stp: rt with: rt2 base: rn offset: 0
!
ldp: rt with: rt2 base: rn postIndex: off
	((rn bitAnd: 31 + REG_SP + REG_D) = (31 + REG_SP) and: [off = 16 and: [(self isD: rt) not]]) ifTrue: [
		(self isRecord: rt) ifFalse: [self pop: rt].
		(self isRecord: rt2) ifFalse: [self pop: rt2].
		^self].
	self ldp: rt with: rt2 base: rn offset: 0.
	self add: rn with: rn imm: off
!
stp: rt with: rt2 base: rn postIndex: off
	self stp: rt with: rt2 base: rn offset: 0.
	self add: rn with: rn imm: off
!
ldp: rt with: rt2 base: rn preIndex: off
	self add: rn with: rn imm: off.
	self ldp: rt with: rt2 base: rn offset: 0
!
ldr: rt label: aLabel
	"Load from a pc-relative literal."
	(self isD: rt) ifTrue: [^self op: 16r100F len: 2 pre: 16rF2 w: 0 reg: (self xmm: rt) label: aLabel].
	(self isPhys: rt) ifTrue: [^self op: 16r8B len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) label: aLabel].
	self op: 16r8B len: 1 pre: 0 w: 1 reg: X64_R11 label: aLabel.
	self store: X64_R11 into: rt
! !

!Amd64Assembler methodsFor: 'pc-relative'!
adr: rd label: aLabel
	(self isPhys: rd) ifTrue: [^self op: 16r8D len: 1 pre: 0 w: 1 reg: (self gpr: rd) label: aLabel].
	self op: 16r8D len: 1 pre: 0 w: 1 reg: X64_R11 label: aLabel.
	self store: X64_R11 into: rd
!
adrp: rd label: aLabel
	"rd := the 4 KB page of aLabel (a bound label)"
	<export>
	<var: #rd type: 'int64_t'>
	<var: #aLabel type: 'int32_t'>
	| t a |
	a := asmLabels at: aLabel.
	a = 0 ifTrue: [^self fail: ASM_ERR_LABEL].
	t := self dst: rd.
	self op: 16r8D len: 1 pre: 0 w: 1 reg: t target: (a bitClear: 16rFFF) imm: 0 isz: 0.
	self store: t into: rd
! !

!Amd64Assembler methodsFor: 'branches'!
b: aLabel
	"jmp: rel8 back to a near label, else rel32"
	| a d |
	a := asmLabels at: aLabel.
	a ~= 0 ifTrue: [
		d := (a - (asmPc + 2)) asInt64.
		(d between: -128 and: 127) ifTrue: [
			self branchTo: aLabel.
			self emitBytes: (16rEB asUInt64 bitOr: (d asUInt64 bitAnd: 16rFF) << 8) count: 2.
			asmJumpEnd := asmPc.
			^self]].
	self jmpRel32To: aLabel
!
bl: aLabel
	"call rel32 (the flags after it are the callee's: nothing to read)"
	self emitBytes: 16rE8 count: 1.
	self emitRel32To: (self targetOf: aLabel site: asmPc).
	asmFlags := X64_FL_NONE
!
b: aLabel if: c
	| cc |
	cc := self cc: c.
	cc >= 0 ifTrue: [^self jcc: cc to: aLabel].
	cc = -3 ifTrue: [^self b: aLabel].
	cc = -1 ifTrue: [^self condBranch: c to: aLabel].
	self fail: ASM_ERR_FLAGS
!
condBranch: c to: aLabel
	"A floating point compare's condition that takes two tests."
	<export>
	<var: #c type: 'int64_t'>
	<var: #aLabel type: 'int32_t'>
	| pair skip |
	pair := self fpPair: c.
	(pair bitAnd: 16r10000) ~= 0
		ifTrue: [
			"both: j(not first) over; jcc aLabel"
			self emitBytes: (16r70 + (((pair >> 8) bitAnd: 15) bitXor: 1)) asUInt64 count: 2.
			skip := asmPc.
			self jcc: (pair bitAnd: 15) to: aLabel.
			self uint8At: skip - 1 put: (asmPc - skip) asUInt8]
		ifFalse: [
			self jcc: ((pair >> 8) bitAnd: 15) to: aLabel.
			self jcc: (pair bitAnd: 15) to: aLabel]
!
cbz: rt to: aLabel
	(self isPhys: rt)
		ifTrue: [self op: 16r85 len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) rm: (self gpr: rt) byte: false]
		ifFalse: [self compareZero: rt].
	self clobberFlags.
	self jcc: 4 to: aLabel
!
cbnz: rt to: aLabel
	(self isPhys: rt)
		ifTrue: [self op: 16r85 len: 1 pre: 0 w: (self wide: rt) reg: (self gpr: rt) rm: (self gpr: rt) byte: false]
		ifFalse: [self compareZero: rt].
	self clobberFlags.
	self jcc: 5 to: aLabel
!
compareZero: rt
	<export>
	<var: #rt type: 'int64_t'>
	(self isWord: rt) ifTrue: [^self op: 16r83 len: 1 pre: 0 w: (self wide: rt) reg: 7 target: (self homeOf: rt) imm: 0 isz: 1].
	self fail: ASM_ERR_OPERAND
!
tbz: rt bit: n to: aLabel
	self testBit: n of: rt.
	self jcc: (n < 31 ifTrue: [4] ifFalse: [3]) to: aLabel
!
tbnz: rt bit: n to: aLabel
	self testBit: n of: rt.
	self jcc: (n < 31 ifTrue: [5] ifFalse: [2]) to: aLabel
!
testBit: n of: rt
	"ZF := whether bit n of rt is 0 (a test, bt beyond bit 30: CF := the bit)."
	((self isPhys: rt) and: [n < 31]) ifTrue: [
		n < 8
			ifTrue: [self op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: (self gpr: rt) imm: 1 asInt64 << n isz: 1]
			ifFalse: [self op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 rm: (self gpr: rt) imm: 1 asInt64 << n isz: 4].
		^self clobberFlags].
	self testBitAny: n of: rt
!
testBitAny: n of: rt
	<export>
	<var: #n type: 'int64_t'>
	<var: #rt type: 'int64_t'>
	(n between: 0 and: 63) ifFalse: [^self fail: ASM_ERR_IMMEDIATE].
	n < 31
		ifTrue: [
			(self isWord: rt)
				ifTrue: [
					n < 8
						ifTrue: [self op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 target: (self homeOf: rt) imm: 1 asInt64 << n isz: 1]
						ifFalse: [self op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 target: (self homeOf: rt) imm: 1 asInt64 << n isz: 4]]
				ifFalse: [
					n < 8
						ifTrue: [self op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: (self source: rt) imm: 1 asInt64 << n isz: 1]
						ifFalse: [self op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 rm: (self source: rt) imm: 1 asInt64 << n isz: 4]]]
		ifFalse: [
			"bt r, n"
			self op: 16rBA0F len: 2 pre: 0 w: 1 reg: 4 rm: (self source: rt) imm: n isz: 1].
	self clobberFlags
!
br: rn
	"jmp rn"
	self op: 16rFF len: 1 pre: 0 w: 0 reg: 4 rm: (self source: rn) byte: false.
	asmJumpEnd := asmPc
!
blr: rn
	"call rn"
	self op: 16rFF len: 1 pre: 0 w: 0 reg: 2 rm: (self source: rn) byte: false.
	asmFlags := X64_FL_NONE
!
ret
	self emitBytes: 16rC3 count: 1.
	asmJumpEnd := asmPc
!
nop
	self emitBytes: 16r90 count: 1
!
brk: imm
	"int3"
	self emitBytes: 16rCC count: 1
! !

!Amd64Assembler methodsFor: 'floating point'!
sse: op rd: d rm: m
	"F2 0F op: xmm d, xmm m"
	self op: (16r0F bitOr: op asInt64 << 8) len: 2 pre: 16rF2 w: 0 reg: (self xmm: d) rm: (self xmm: m) byte: false
!
fmov: rd with: rn
	"Between D registers, or between a D and a general register."
	((self isD: rd) and: [self isD: rn]) ifTrue: [
		(self xmm: rd) ~= (self xmm: rn) ifTrue: [self op: 16r280F len: 2 pre: 16r66 w: 0 reg: (self xmm: rd) rm: (self xmm: rn) byte: false].
		^self].
	(self isD: rd) ifTrue: [
		"movq xmm, r64"
		^self op: 16r6E0F len: 2 pre: 16r66 w: 1 reg: (self xmm: rd) rm: (self source: rn) byte: false].
	(self isPhys: rd) ifTrue: [
		"movq r64, xmm"
		^self op: 16r7E0F len: 2 pre: 16r66 w: 1 reg: (self xmm: rn) rm: (self gpr: rd) byte: false].
	self op: 16r7E0F len: 2 pre: 16r66 w: 1 reg: (self xmm: rn) rm: X64_R11 byte: false.
	self store: X64_R11 into: rd
!
fmov: rd bits: v
	"rd := the double with bits v"
	self movReg: X64_R11 imm: v.
	self op: 16r6E0F len: 2 pre: 16r66 w: 1 reg: (self xmm: rd) rm: X64_R11 byte: false
!
fmov: rd imm: aDouble
	self fmov: rd bits: (self bitsOfDouble: aDouble)
!
fop: op rd: d rn: n rm: m commutes: aBoolean
	"d := n op m (3 operands from x86's 2)"
	(self xmm: d) = (self xmm: n) ifTrue: [^self sse: op rd: d rm: m].
	((self xmm: d) = (self xmm: m) and: [aBoolean]) ifTrue: [^self sse: op rd: d rm: n].
	(self xmm: d) ~= (self xmm: m) ifTrue: [
		self fmov: d with: n.
		^self sse: op rd: d rm: m].
	self fopAliased: op rd: d rn: n
!
fopAliased: op rd: d rn: n
	"d := n op d, op not commutative: d to the stack, n into d, op with the stack (lea keeps the flags)."
	<export>
	<var: #op type: 'int32_t'>
	<var: #d type: 'int64_t'>
	<var: #n type: 'int64_t'>
	self op: 16r8D len: 1 pre: 0 w: 1 reg: X64_RSP base: X64_RSP disp: -16 imm: 0 isz: 0 byte: false.
	self op: 16r110F len: 2 pre: 16rF2 w: 0 reg: (self xmm: d) base: X64_RSP disp: 0 imm: 0 isz: 0 byte: false.
	self fmov: d with: n.
	self op: (16r0F bitOr: op asInt64 << 8) len: 2 pre: 16rF2 w: 0 reg: (self xmm: d) base: X64_RSP disp: 0 imm: 0 isz: 0 byte: false.
	self op: 16r8D len: 1 pre: 0 w: 1 reg: X64_RSP base: X64_RSP disp: 16 imm: 0 isz: 0 byte: false
!
fadd: rd with: rn with: rm
	self fop: 16r58 rd: rd rn: rn rm: rm commutes: true
!
fsub: rd with: rn with: rm
	self fop: 16r5C rd: rd rn: rn rm: rm commutes: false
!
fmul: rd with: rn with: rm
	self fop: 16r59 rd: rd rn: rn rm: rm commutes: true
!
fdiv: rd with: rn with: rm
	self fop: 16r5E rd: rd rn: rn rm: rm commutes: false
!
fsqrt: rd with: rn
	self sse: 16r51 rd: rd rm: rn
!
fcmp: rn with: rm
	"ucomisd: the flags of a floating point compare (X64_FL_FP)"
	self op: 16r2E0F len: 2 pre: 16r66 w: 0 reg: (self xmm: rn) rm: (self xmm: rm) byte: false.
	self setFlags: X64_FL_FP
!
fcmpZero: rn
	"ucomisd rn, [asmRegs[31]] (0.0)"
	self op: 16r2E0F len: 2 pre: 16r66 w: 0 reg: (self xmm: rn) target: self regsAddress + 248 imm: 0 isz: 0.
	self setFlags: X64_FL_FP
!
scvtf: rd with: rn
	"cvtsi2sd: the signed integer in rn (W or X) as a double"
	self op: 16r2A0F len: 2 pre: 16rF2 w: (self wide: rn) reg: (self xmm: rd) rm: (self source: rn) byte: false
!
fcvtzs: rd with: rn
	"cvttsd2si: toward zero; out of range or NaN gives the most negative integer (arm64 saturates): the code generators check the range first"
	(self isPhys: rd) ifTrue: [^self op: 16r2C0F len: 2 pre: 16rF2 w: (self wide: rd) reg: (self gpr: rd) rm: (self xmm: rn) byte: false].
	self op: 16r2C0F len: 2 pre: 16rF2 w: (self wide: rd) reg: X64_R11 rm: (self xmm: rn) byte: false.
	self store: X64_R11 into: rd
! !

!Amd64Assembler methodsFor: 'decoding'!
effectAt: address
	"What the instruction at address (one I emit) does to what general registers hold, for OptCodegen>>catchUp: its length | kind << 8 | register << 16 | second register << 24 | offset << 32, the registers arm64's (255: neither one of them nor anything, as r11 and rsp). Kinds: ASM_EF_NONE nothing; ASM_EF_LOAD a 64-bit load of [rbx + offset] (x20's slot) into the register; ASM_EF_STORE a 64-bit store of the register there; ASM_EF_MOVE a move into the register from the second; ASM_EF_WRITE a write of the register and of the second; ASM_EF_FORGET anything after which nothing is known: calls, jumps, pushes (my fallbacks address with what they push), other stores into the frame and through r11. Other stores (through registers into objects, rsp, rip) do nothing, as arm64's do. Length 0: an instruction I do not emit."
	<export>
	<var: #address type: 'uint64_t'>
	<returns: 'int64_t'>
	<var: #p type: 'uint64_t'>
	<var: #b type: 'int64_t'>
	<var: #pre type: 'int64_t'>
	<var: #rex type: 'int64_t'>
	<var: #op type: 'int64_t'>
	<var: #op2 type: 'int64_t'>
	<var: #modrm type: 'int64_t'>
	<var: #mod type: 'int64_t'>
	<var: #digit type: 'int64_t'>
	<var: #reg type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #base type: 'int64_t'>
	<var: #index type: 'int64_t'>
	<var: #disp type: 'int64_t'>
	<var: #len type: 'int64_t'>
	| p b pre rex op op2 modrm mod digit reg rm base index disp len |
	p := address.
	pre := 0.
	b := (self uint8At: p) asInt64.
	(b = 16r66 or: [b = 16rF2 or: [b = 16rF3]]) ifTrue: [
		pre := b.
		p := p + 1.
		b := (self uint8At: p) asInt64].
	rex := 0.
	(b bitAnd: 16rF0) = 16r40 ifTrue: [
		rex := b.
		p := p + 1.
		b := (self uint8At: p) asInt64].
	op := b.
	p := p + 1.
	op2 := -1.
	op = 16r0F ifTrue: [
		op2 := (self uint8At: p) asInt64.
		p := p + 1].
	len := (p - address) asInt64.
	op2 < 0 ifTrue: [
		(op between: 16rB8 and: 16rBF) ifTrue: [^self effect: len + ((rex bitAnd: 8) = 0 ifTrue: [4] ifFalse: [8]) kind: ASM_EF_WRITE reg: (self armOf: (op bitAnd: 7) + ((rex bitAnd: 1) * 8)) reg: 255 offset: 0].
		(op between: 16r58 and: 16r5F) ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: (self armOf: (op bitAnd: 7) + ((rex bitAnd: 1) * 8)) reg: 255 offset: 0].
		(op between: 16r50 and: 16r57) ifTrue: [^self effect: len kind: ASM_EF_FORGET reg: 255 reg: 255 offset: 0].
		(op between: 16r70 and: 16r7F) ifTrue: [^self shortJumpAt: address length: len + 1 conditional: true].
		op = 16rEB ifTrue: [^self shortJumpAt: address length: len + 1 conditional: false].
		(op = 16rE8 or: [op = 16rE9]) ifTrue: [^self effect: len + 4 kind: ASM_EF_FORGET reg: 255 reg: 255 offset: 0].
		op = 16rC3 ifTrue: [^self effect: len kind: ASM_EF_FORGET reg: 255 reg: 255 offset: 0].
		op = 16r99 ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: 2 reg: 255 offset: 0].
		(op = 16r90 or: [op = 16rCC]) ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0]].
	(op2 between: 16r80 and: 16r8F) ifTrue: [^self effect: len + 4 kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
	"ModRM, SIB, displacement"
	modrm := (self uint8At: p) asInt64.
	p := p + 1.
	mod := modrm >> 6.
	digit := (modrm >> 3) bitAnd: 7.
	reg := digit + (((rex >> 2) bitAnd: 1) * 8).
	rm := (modrm bitAnd: 7) + ((rex bitAnd: 1) * 8).
	base := rm.
	index := -1.
	disp := 0.
	mod ~= 3 ifTrue: [
		(modrm bitAnd: 7) = 4 ifTrue: [
			b := (self uint8At: p) asInt64.
			p := p + 1.
			index := ((b >> 3) bitAnd: 7) + (((rex >> 1) bitAnd: 1) * 8).
			index = X64_RSP ifTrue: [index := -1].
			base := (b bitAnd: 7) + ((rex bitAnd: 1) * 8).
			(mod = 0 and: [(b bitAnd: 7) = 5]) ifTrue: [
				base := -1.
				disp := (self int32At: p) asInt64.
				p := p + 4]].
		(mod = 0 and: [(modrm bitAnd: 7) = 5]) ifTrue: [
			base := X64_RIP.
			disp := (self int32At: p) asInt64.
			p := p + 4].
		mod = 1 ifTrue: [
			disp := (self uint8At: p) asInt64.
			disp >= 128 ifTrue: [disp := disp - 256].
			p := p + 1].
		mod = 2 ifTrue: [
			disp := (self int32At: p) asInt64.
			p := p + 4]].
	len := (p - address) asInt64.
	"byte registers 4-7 without REX are ah, ch, dh, bh"
	(rex = 0 and: [mod = 3 and: [(op2 < 0 and: [op = 16r88 or: [op = 16r80 or: [op = 16rC6 or: [op = 16rF6]]]]) or: [op2 between: 16r90 and: 16r9F]]]) ifTrue: [rm := rm bitAnd: 3].
	op2 >= 0 ifTrue: [^self effect0F: op2 pre: pre rex: rex length: len mod: mod digit: digit reg: reg rm: rm base: base index: index offset: disp].
	"immediates"
	(op = 16r80 or: [op = 16r83 or: [op = 16rC0 or: [op = 16rC1 or: [op = 16rC6 or: [op = 16r6B or: [op = 16rF6 and: [digit <= 1]]]]]]]) ifTrue: [len := len + 1].
	(op = 16r81 or: [op = 16rC7 or: [op = 16r69 or: [op = 16rF7 and: [digit <= 1]]]]) ifTrue: [len := len + (pre = 16r66 ifTrue: [2] ifFalse: [4])].
	op = 16r8B ifTrue: [
		mod = 3 ifTrue: [^self moveOrWrite: len rex: rex to: reg from: rm].
		((rex bitAnd: 8) ~= 0 and: [pre = 0 and: [base = X64_RBX and: [index < 0]]]) ifTrue: [^self effect: len kind: ASM_EF_LOAD reg: (self armOf: reg) reg: 255 offset: disp].
		^self effect: len kind: ASM_EF_WRITE reg: (self armOf: reg) reg: 255 offset: 0].
	op = 16r89 ifTrue: [
		mod = 3 ifTrue: [^self moveOrWrite: len rex: rex to: rm from: reg].
		((rex bitAnd: 8) ~= 0 and: [pre = 0 and: [base = X64_RBX and: [index < 0]]]) ifTrue: [^self effect: len kind: ASM_EF_STORE reg: (self armOf: reg) reg: 255 offset: disp].
		^self storeLength: len base: base].
	(op = 16r8D or: [op = 16r63 or: [op = 16r69 or: [op = 16r6B or: [op < 16r40 and: [(op bitAnd: 7) = 3 and: [op ~= 16r3B]]]]]]) ifTrue: [
		"lea, movsxd, imul, and op r, r/m (add or adc sbb and sub xor)"
		^self effect: len kind: ASM_EF_WRITE reg: (self armOf: reg) reg: 255 offset: 0].
	(op = 16r39 or: [op = 16r3B or: [op = 16r38 or: [op = 16r3A or: [op = 16r84 or: [op = 16r85]]]]]) ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
	((op between: 16r80 and: 16r83) and: [digit = 7]) ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
	((op = 16rF6 or: [op = 16rF7]) and: [digit <= 1]) ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
	((op = 16rF6 or: [op = 16rF7]) and: [digit >= 4]) ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: 9 reg: 2 offset: 0].
	(op = 16rFF and: [digit >= 2]) ifTrue: [^self effect: len kind: ASM_EF_FORGET reg: 255 reg: 255 offset: 0].
	(op = 16r88 or: [(op between: 16r80 and: 16r83) or: [(op between: 16rC0 and: 16rC1) or: [(op between: 16rD0 and: 16rD3) or: [op = 16rC6 or: [op = 16rC7 or: [op = 16rF6 or: [op = 16rF7 or: [op = 16r8F or: [op = 16rFF or: [op < 16r40 and: [(op bitAnd: 7) = 1 and: [op ~= 16r39]]]]]]]]]]]]) ifTrue: [
		"writes of r/m: mov, group 1 (but cmp), shifts, not, neg, pop, inc, dec, and op r/m, r"
		mod = 3 ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: (self armOf: rm) reg: 255 offset: 0].
		^self storeLength: len base: base].
	^0
!
effect0F: op2 pre: pre rex: rex length: len mod: mod digit: digit reg: reg rm: rm base: base index: index offset: disp
	"effectAt:'s two-byte opcodes (0F op2), the SSE ones among them."
	<var: #op2 type: 'int64_t'>
	<var: #pre type: 'int64_t'>
	<var: #rex type: 'int64_t'>
	<var: #len type: 'int64_t'>
	<var: #mod type: 'int64_t'>
	<var: #digit type: 'int64_t'>
	<var: #reg type: 'int64_t'>
	<var: #rm type: 'int64_t'>
	<var: #base type: 'int64_t'>
	<var: #index type: 'int64_t'>
	<var: #disp type: 'int64_t'>
	<returns: 'int64_t'>
	pre ~= 0 ifTrue: [
		"movsd, movapd, cvtsi2sd, ucomisd, sqrtsd, addsd, mulsd, subsd, divsd, movq xmm: xmm registers and the flags"
		(op2 = 16r10 or: [op2 = 16r28 or: [op2 = 16r2A or: [op2 = 16r2E or: [op2 = 16r51 or: [op2 = 16r58 or: [op2 = 16r59 or: [op2 = 16r5C or: [op2 = 16r5E or: [op2 = 16r6E]]]]]]]]]) ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
		"cvttsd2si"
		op2 = 16r2C ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: (self armOf: reg) reg: 255 offset: 0].
		"movsd m64, xmm; movq r/m64, xmm"
		(op2 = 16r11 or: [op2 = 16r7E and: [pre = 16r66]]) ifTrue: [
			mod = 3 ifTrue: [^self effect: len kind: (op2 = 16r11 ifTrue: [ASM_EF_NONE] ifFalse: [ASM_EF_WRITE]) reg: (op2 = 16r11 ifTrue: [255] ifFalse: [self armOf: rm]) reg: 255 offset: 0].
			^self storeLength: len base: base].
		^0].
	"cmovcc, imul, movzx, movsx"
	((op2 between: 16r40 and: 16r4F) or: [op2 = 16rAF or: [op2 = 16rB6 or: [op2 = 16rB7 or: [op2 = 16rBE or: [op2 = 16rBF]]]]]) ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: (self armOf: reg) reg: 255 offset: 0].
	"setcc"
	(op2 between: 16r90 and: 16r9F) ifTrue: [
		mod = 3 ifTrue: [^self effect: len kind: ASM_EF_WRITE reg: (self armOf: rm) reg: 255 offset: 0].
		^self storeLength: len base: base].
	"bt r/m, imm8 (bts, btr, btc write)"
	op2 = 16rBA ifTrue: [
		digit = 4 ifTrue: [^self effect: len + 1 kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
		mod = 3 ifTrue: [^self effect: len + 1 kind: ASM_EF_WRITE reg: (self armOf: rm) reg: 255 offset: 0].
		^self storeLength: len + 1 base: base].
	"nop r/m"
	op2 = 16r1F ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
	^0
!
shortJumpAt: address length: len conditional: aBoolean
	"A jump of 8 bits. Back: to a label (bound), NONE or (not conditional) FORGET. Forward: over code of mine (condBranch:to:, picCaseX64:classAt:target:), whose effect at the target I cannot tell from what is after it: if the jump is conditional and that code does nothing, NONE; else one FORGET over the jump and that code."
	<export>
	<var: #address type: 'uint64_t'>
	<var: #len type: 'int64_t'>
	<var: #aBoolean type: 'bool'>
	<returns: 'int64_t'>
	<var: #d type: 'int64_t'>
	<var: #target type: 'uint64_t'>
	<var: #q type: 'uint64_t'>
	<var: #e type: 'int64_t'>
	<var: #quiet type: 'bool'>
	| d target q e quiet |
	d := (self uint8At: address + len - 1) asInt64.
	d >= 128 ifTrue: [d := d - 256].
	d < 0 ifTrue: [^self effect: len kind: (aBoolean ifTrue: [ASM_EF_NONE] ifFalse: [ASM_EF_FORGET]) reg: 255 reg: 255 offset: 0].
	target := address + len + d.
	target > asmPc ifTrue: [^0].
	quiet := aBoolean.
	q := address + len.
	[q < target] whileTrue: [
		e := self effectAt: q.
		(e bitAnd: 255) = 0 ifTrue: [^0].
		((e >> 8) bitAnd: 255) ~= ASM_EF_NONE ifTrue: [quiet := false].
		q := q + (e bitAnd: 255)].
	q ~= target ifTrue: [^0].
	quiet ifTrue: [^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0].
	^self effect: (target - address) asInt64 kind: ASM_EF_FORGET reg: 255 reg: 255 offset: 0
!
moveOrWrite: len rex: rex to: rd from: rs
	"mov rd, rs (x86 registers): 64-bit, a move; 32-bit, a write."
	<var: #len type: 'int64_t'>
	<var: #rex type: 'int64_t'>
	<var: #rd type: 'int64_t'>
	<var: #rs type: 'int64_t'>
	<returns: 'int64_t'>
	(rex bitAnd: 8) ~= 0 ifTrue: [^self effect: len kind: ASM_EF_MOVE reg: (self armOf: rd) reg: (self armOf: rs) offset: 0].
	^self effect: len kind: ASM_EF_WRITE reg: (self armOf: rd) reg: 255 offset: 0
!
storeLength: len base: base
	"A store other than a 64-bit register's into the frame (x86 base register base, -1 none): into the frame (rbx), through r11 (addresses I compute, the frame's among them) or no register, FORGET; through rsp or rip, or another register (into an object), NONE."
	<var: #len type: 'int64_t'>
	<var: #base type: 'int64_t'>
	<returns: 'int64_t'>
	(base = X64_RBX or: [base = X64_R11 or: [base < 0]]) ifTrue: [^self effect: len kind: ASM_EF_FORGET reg: 255 reg: 255 offset: 0].
	^self effect: len kind: ASM_EF_NONE reg: 255 reg: 255 offset: 0
!
effect: len kind: kind reg: r reg: r2 offset: off
	<var: #len type: 'int64_t'>
	<var: #kind type: 'int64_t'>
	<var: #r type: 'int64_t'>
	<var: #r2 type: 'int64_t'>
	<var: #off type: 'int64_t'>
	<returns: 'int64_t'>
	^(((len asInt64 bitOr: kind asInt64 << 8) bitOr: r asInt64 << 16) bitOr: r2 asInt64 << 24) bitOr: (off asInt64 bitAnd: 16rFFFFFFFF) << 32
!
armOf: x
	"The arm64 register of x86 register x, 255 if none (r11, rsp): X64_ARM_LO and X64_ARM_HI hold a byte for each of rax-rdi and r8-r15."
	<var: #x type: 'int64_t'>
	<returns: 'int64_t'>
	^((x < 8 ifTrue: [X64_ARM_LO] ifFalse: [X64_ARM_HI]) >> (8 * (x bitAnd: 7))) bitAnd: 255
! !

!Amd64Assembler methodsFor: 'encoders'!
logicalImmediate: value width: width
	"Whether value is an immediate an x86 logical instruction takes (a sign-extended 32-bit one): 0 if so, -1 if not (Arm64Assembler answers its encoding)."
	<export>
	<var: #value type: 'uint64_t'>
	<var: #width type: 'int64_t'>
	(width = 32 or: [self fitsImm32: value asInt64]) ifTrue: [^0].
	^-1
!
fmovImmediate: aDouble
	"x86 has no floating point immediates: -1."
	<export>
	<var: #aDouble type: 'double'>
	^-1
! !

!Amd64Assembler methodsFor: 'patching'!
patchBranchAt: site to: target
	"Point the 32-bit displacement at site (of a jmp, jcc, call, lea or mov ending there) to target; answer whether it reaches."
	<export>
	<var: #site type: 'uint64_t'>
	<var: #target type: 'uint64_t'>
	| disp |
	disp := (target - (site + 4)) asInt64.
	(disp between: -16r80000000 and: 16r7FFFFFFF) ifFalse: [
		self fail: ASM_ERR_RANGE.
		^false].
	self uint32At: site put: (disp asUInt64 bitAnd: 16rFFFFFFFF) asUInt32.
	^true
!
branchTargetAt: site
	"The target of the 32-bit displacement at site."
	<var: #site type: 'uint64_t'>
	<export>
	^site + 4 + (self int32At: site) asInt64
!
patchMov64At: site value: value
	"Rewrite the constant of the mov:imm64: at site."
	<var: #site type: 'uint64_t'>
	<var: #value type: 'uint64_t'>
	<export>
	self uint32At: site + 2 put: (value bitAnd: 16rFFFFFFFF) asUInt32.
	self uint32At: site + 6 put: (value >> 32) asUInt32
!
mov64At: site
	"The constant of the mov:imm64: at site."
	<var: #site type: 'uint64_t'>
	<export>
	^(self uint32At: site + 2) asUInt64 bitOr: (self uint32At: site + 6) asUInt64 << 32
! !
