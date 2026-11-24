Arm64Module subclass: #JitCompiler
	instanceVariableNames: 'asm runtime analysis stubs cache brt'
	classVariableNames: ''
	package: 'VM-Jit'!

JitCompiler comment: 'I am the abstract class of the code generators (JitStubs and the compilers): Arm64Modules, so they name registers; what they know of the VM they ask JitRuntime and BytecodeAnalysis (inline accessors). My helpers are the conventions every compiler''s code follows (docs/jit.md, Shared runtime):

x19 the Frame, x20 its slots (fp: slot k at [x20, #8k], the receiver at [x20, #-8]), x21 the receiver, x22 the JitState, x0-x7 and x16-x17 scratch. Code entered with its frame pushed (by the runtime, by optimized code) starts with the prologue (from a caller whose frame is x19: x19 := the next Frame, x29/x30 pushed, x20 and x21 loaded; JIT_PROLOGUE_BYTES long); start follows it. Before a call into the runtime that is a safepoint the code stores the frame''s pc and sp (sync:depth:); afterwards it reloads x21 (the receiver may have moved) and leaves to the interpreter if the runtime answered 1.'!

!JitCompiler class methodsFor: 'declaring'!
declarations
	^#((asm JitAssembler) (runtime JitRuntime) (analysis BytecodeAnalysis) (stubs JitStubs) (cache CodeCache) (brt JitBaselineRuntime))
!
isAbstractModule
	^self == JitCompiler
! !

!JitCompiler methodsFor: 'layout'!
frameBytes
	^self sizeof: 'Frame'
!
fpOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #fp) to: 'int64_t'
!
litsOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #lits) to: 'int64_t'
!
closureOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #closure) to: 'int64_t'
!
pcOffset
	"pc and sp (int32 each) are stored together."
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #pc) to: 'int64_t'
!
ctxOffset
	^self cCoerce: ((self cCoerce: 0 to: 'Frame *') fieldAddress: #ctx) to: 'int64_t'
!
nilOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #nilOop) to: 'int64_t'
!
trueOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #trueOop) to: 'int64_t'
!
falseOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #falseOop) to: 'int64_t'
!
interruptOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #interrupt) to: 'int64_t'
!
forwardersOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #forwarders) to: 'int64_t'
!
framesOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #frames) to: 'int64_t'
!
exitSpOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #exitSp) to: 'int64_t'
!
youngLoOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #youngLo) to: 'int64_t'
!
youngHiOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #youngHi) to: 'int64_t'
!
arrayClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #arrayClass) to: 'int64_t'
!
pointClassOffset
	^self cCoerce: ((self cCoerce: 0 to: 'JitState *') fieldAddress: #pointClass) to: 'int64_t'
!
slot: k
	"The offset of slot k from x20."
	^8 * k
!
fieldOffset: i
	"The offset of field i of an object."
	^16 + (8 * i)
! !

!JitCompiler methodsFor: 'conventions'!
emitPrologue
	"The entry from a compiled caller: its frame is x19, ours the next one."
	asm isX64 ifTrue: [^self emitPrologueX64].
	asm comment: 'entry: x19 := the callee''s Frame, push x29/x30, x20 := fp, x21 := receiver'.
	asm add: X19 with: X19 imm: self frameBytes.
	asm stp: X29 with: X30 base: SP preIndex: -16.
	asm mov: X29 with: SP.
	asm ldr: X20 base: X19 offset: self fpOffset.
	asm ldr: X21 base: X20 offset: -8
!
emitPrologueX64
	"x86: the call pushed the return address, the native frame record; JIT_PROLOGUE_BYTES_X64 long."
	<arch: #x86_64>
	| start |
	start := asm pc.
	asm comment: 'entry: x19 := the callee''s Frame, x20 := fp, x21 := receiver'.
	asm add: X19 with: X19 imm: self frameBytes.
	asm ldr: X20 base: X19 offset: self fpOffset.
	asm ldr: X21 base: X20 offset: -8.
	asm pc - start = runtime prologueBytes ifFalse: [asm fail: ASM_ERR_RANGE]
!
emitSync: pc depth: d
	"The frame's pc and sp, for the runtime and for the interpreter if it takes over."
	asm comment: 'spill: frame pc %d' with: pc.
	asm mov: X16 imm: ((d asInt64 << 32) bitOr: pc).
	asm str: X16 base: X19 offset: self pcOffset
!
emitInterruptTestTo: aLabel
	"Branch to aLabel if an interrupt is pending (the JitState's interrupt word)."
	asm isX64
		ifTrue: [
			asm cmpStateWord32At: self interruptOffset imm: 0.
			asm b: aLabel if: COND_NE]
		ifFalse: [
			asm ldr: W16 base: X22 offset: self interruptOffset.
			asm cbnz: W16 to: aLabel]
!
emitForwardersTestTo: aLabel
	"Branch to aLabel if some object is a forwarder (becomeForward:: the JitState's forwarders word)."
	asm isX64
		ifTrue: [
			asm cmpStateWord32At: self forwardersOffset imm: 0.
			asm b: aLabel if: COND_NE]
		ifFalse: [
			asm ldr: W16 base: X22 offset: self forwardersOffset.
			asm cbnz: W16 to: aLabel]
!
emitNoForwardersTestTo: aLabel
	"Branch to aLabel unless some object is a forwarder."
	asm isX64
		ifTrue: [
			asm cmpStateWord32At: self forwardersOffset imm: 0.
			asm b: aLabel if: COND_EQ]
		ifFalse: [
			asm ldr: W16 base: X22 offset: self forwardersOffset.
			asm cbz: W16 to: aLabel]
!
emitFollow: r
	"r := the object r forwards to (becomeForward:), r itself if it is no forwarder (x16 scratch)."
	| loop done |
	loop := asm newLabel.
	done := asm newLabel.
	asm comment: 'follow a forwarder: its class word is its target + 6'.
	asm bind: loop.
	asm tst: r imm: 7.
	asm b: done if: COND_NE.
	asm ldr: X16 base: r offset: 0.
	asm tbz: X16 bit: 63 to: done.
	asm ldr: r base: r offset: 8.
	asm sub: r with: r imm: FWD_TAG.
	asm b: loop.
	asm bind: done
!
emitReloadReceiver
	asm comment: 'reload the receiver (a GC may have moved it)'.
	asm ldr: X21 base: X20 offset: -8
!
constantDouble: v
	"The IEEE bits of the SmallInteger or SmallFloat64 constant v."
	| r b |
	(v bitAnd: 1) ~= 0 ifTrue: [^self bitsOfDouble: (v asInt64 >> 1) asFloat].
	r := v asUInt64 >> 3.
	r <= 1 ifTrue: [^r << 63].
	b := r + (896 asUInt64 << 53).
	^(b >> 1) bitOr: (b << 63)
!
emitCountDown: address to: slowLabel
	"Decrement the int32 counter at address (in the VM's data, within adrp's range of the code), branch to slowLabel when it is no longer positive (--jit opt: the lower tier counts method entries and backward jumps; the slow path calls the tier-up stub)."
	asm isX64 ifTrue: [
		asm comment: 'count toward optimization'.
		asm decrement32At: address.
		^asm b: slowLabel if: COND_LE].
	asm comment: 'count toward optimization'.
	asm adrp: X16 label: (asm labelAt: address).
	asm ldr: W17 base: X16 offset: (address bitAnd: 16rFFF) asInt64.
	asm subs: W17 with: W17 imm: 1.
	asm str: W17 base: X16 offset: (address bitAnd: 16rFFF) asInt64.
	asm b: slowLabel if: COND_LE
! !
