Arm64Module subclass: #Amd64AssemblerCases
	instanceVariableNames: 'asm libc posix buffer'
	classVariableNames: ''
	package: 'Tests-VM'!

Amd64AssemblerCases comment: 'The x86-64 forms Amd64AssemblerTest checks, each with the source GNU as gets (Intel syntax, instructions separated by |; {load} picks the encoding with the register operand in ModRM.reg, {disp32} a 32-bit displacement, 1: 1f local labels; tools/amd64-reference.py assembles them into Amd64Reference): Amd64Assembler''s x86 encoders with x86 register numbers (0 rax, 1 rcx, 2 rdx, 3 rbx, 4 rsp, 5 rbp, 6 rsi, 7 rdi, 8-15 r8-r15), and the arm64 instructions the code generators write as what they are on x86 (x0-x5 rdi rsi rdx rcx r8 r9, x9 rax, x10 r14, x11 r15, x16 r10, x17 r12, x19 rbp, x20 rbx, x21 r13, r11 the scratch). Each case is emitted at the start of a 64 KB buffer, the JitState (x22) at 4 KB into it, so that pc-relative operands have the displacements of the source. A Lowtalk program: it prints each case''s source and the bytes the assembler emits for it, simulated and as C.'!

!Amd64AssemblerCases class methodsFor: 'declaring'!
declarations
	^#((asm Amd64Assembler) (libc LibC) (posix Posix) (buffer uint64_t))
! !

!Amd64AssemblerCases methodsFor: 'running'!
main: argc argv: argv
	<function>
	<var: #argc type: 'int'>
	<var: #argv type: 'char **'>
	buffer := self cCoerce: (posix mmap: self null length: 65536 protection: (posix PROT_READ bitOr: posix PROT_WRITE) flags: (posix MAP_PRIVATE bitOr: posix MAP_ANON) file: -1 offset: 0) to: 'uint64_t'.
	asm setState: buffer + 4096.
	self registerForms; memoryForms; indexedForms; pcRelativeForms; jumpForms; stackForms.
	self moves; arithmetic; logical; shifts; multiply; conditional; loadStore; state; branches; floatingPoint; runtime.
	^0
!
case: aString emit: aBlock
	asm beginAt: buffer limit: buffer + 65536.
	aBlock value.
	self print: aString error: asm finish
!
print: source error: error
	"source: the bytes emitted, or source: error n"
	<function>
	libc printf: '%s:' with: source.
	error = ASM_OK
		ifTrue: [0 to: asm codeSize asInt64 - 1 do: [:i | libc printf: ' %02x' with: (self uint8At: buffer + i)]]
		ifFalse: [libc printf: ' error %d' with: error].
	libc printf: '
'
! !

!Amd64AssemblerCases methodsFor: 'x86 encodings'!
registerForms
	"register direct: mov, the ALU group with immediates, shifts, the 32-bit and 64-bit constant moves"
	<function>
	self case: '{load} mov rax, rdi' emit: [asm movReg: 0 from: 7].
	self case: '{load} mov r15, rsp' emit: [asm movReg: 15 from: 4].
	self case: '{load} mov rsp, r12' emit: [asm movReg: 4 from: 12].
	self case: '{load} mov r13, r8' emit: [asm movReg: 13 from: 8].
	self case: '{load} mov ebx, r9d' emit: [asm op: 16r8B len: 1 pre: 0 w: 0 reg: 3 rm: 9 byte: false].
	self case: 'mov eax, 0' emit: [asm movReg32: 0 imm: 0].
	self case: 'mov edi, 0xffffffff' emit: [asm movReg32: 7 imm: 16rFFFFFFFF].
	self case: 'mov r11d, 5' emit: [asm movReg32: 11 imm: 5].
	self case: 'mov r15d, 0x80000000' emit: [asm movReg32: 15 imm: 16r80000000].
	self case: 'mov ecx, 5' emit: [asm movReg: 1 imm: 5].
	self case: 'mov esi, 0x7fffffff' emit: [asm movReg: 6 imm: 16r7FFFFFFF].
	self case: 'mov rdx, -1' emit: [asm movReg: 2 imm: -1].
	self case: 'mov r9, -0x80000000' emit: [asm movReg: 9 imm: -16r80000000].
	self case: 'movabs r10, 0x100000000' emit: [asm movReg: 10 imm: 16r100000000].
	self case: 'movabs rax, 0' emit: [asm movabs: 0 imm: 0].
	self case: 'movabs r15, 0xffffffffffffffff' emit: [asm movabs: 15 imm: -1].
	self case: 'movabs rsp, 0x123456789abcdef0' emit: [asm movabs: 4 imm: 16r123456789ABCDEF0].
	self case: 'movabs r8, 0x8000000000000000' emit: [asm movabs: 8 imm: 16r8000000000000000].
	self case: 'add rax, 1' emit: [asm alu: 0 w: 1 dst: 0 imm: 1].
	self case: 'add rdi, 128' emit: [asm alu: 0 w: 1 dst: 7 imm: 128].
	self case: 'or r12d, -128' emit: [asm alu: 1 w: 0 dst: 12 imm: -128].
	self case: 'and rdi, 0x7fffffff' emit: [asm alu: 4 w: 1 dst: 7 imm: 16r7FFFFFFF].
	self case: 'and r14, -0x80000000' emit: [asm alu: 4 w: 1 dst: 14 imm: -16r80000000].
	self case: 'sub rsp, 80' emit: [asm alu: 5 w: 1 dst: 4 imm: 80].
	self case: 'xor r8, 255' emit: [asm alu: 6 w: 1 dst: 8 imm: 255].
	self case: 'cmp r15, -1' emit: [asm alu: 7 w: 1 dst: 15 imm: -1].
	self case: 'cmp ebx, 1000' emit: [asm alu: 7 w: 0 dst: 3 imm: 1000].
	self case: 'cmp ebp, 0x80000000' emit: [asm alu: 7 w: 0 dst: 5 imm: 16r80000000].
	self case: '{load} add r11, rdi' emit: [asm alu: 16r03 w: 1 dst: 11 src: X0].
	self case: '{load} sub rcx, r13' emit: [asm alu: 16r2B w: 1 dst: 1 src: X21].
	self case: '{load} xor esi, edx' emit: [asm alu: 16r33 w: 0 dst: 6 src: W2].
	self case: 'test r14, rax' emit: [asm alu: 16r85 w: 1 dst: 0 src: X10].
	self case: 'cmp r11, 0' emit: [asm alu: 16r3B w: 1 dst: 11 src: XZR].
	self case: 'test rdi, 0' emit: [asm alu: 16r85 w: 1 dst: 7 src: XZR].
	self case: 'shl rdi, 1' emit: [asm shift: 4 w: 1 reg: 7 by: 1].
	self case: 'shr r11, 3' emit: [asm shift: 5 w: 1 reg: 11 by: 3].
	self case: 'sar eax, 31' emit: [asm shift: 7 w: 0 reg: 0 by: 31].
	self case: 'ror r13, 63' emit: [asm shift: 1 w: 1 reg: 13 by: 63].
	self case: 'sar r12, 1' emit: [asm shift: 7 w: 1 reg: 12 by: 1].
	self case: 'test spl, 1' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: 4 imm: 1 isz: 1].
	self case: 'test bpl, 2' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: 5 imm: 2 isz: 1].
	self case: 'test sil, 0x7f' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: 6 imm: 16r7F isz: 1].
	self case: 'test dil, 0x80' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: 7 imm: 16r80 isz: 1].
	self case: 'test bl, 7' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: 3 imm: 7 isz: 1].
	self case: 'test r9b, 7' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 rm: 9 imm: 7 isz: 1].
	self case: 'test r15d, 0x100' emit: [asm op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 rm: 15 imm: 16r100 isz: 4].
	self case: 'test rsi, -2' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 0 rm: 6 imm: -2 isz: 4].
	self case: 'mov r12, -16' emit: [asm op: 16rC7 len: 1 pre: 0 w: 1 reg: 0 rm: 12 imm: -16 isz: 4].
	self case: 'bt r11, 35' emit: [asm op: 16rBA0F len: 2 pre: 0 w: 1 reg: 4 rm: 11 imm: 35 isz: 1].
	self case: 'bt rax, 63' emit: [asm op: 16rBA0F len: 2 pre: 0 w: 1 reg: 4 rm: 0 imm: 63 isz: 1].
	self case: 'neg r11' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 3 rm: 11 byte: false].
	self case: 'not ecx' emit: [asm op: 16rF7 len: 1 pre: 0 w: 0 reg: 2 rm: 1 byte: false].
	self case: 'shl rdx, cl' emit: [asm op: 16rD3 len: 1 pre: 0 w: 1 reg: 4 rm: 2 byte: false].
	self case: 'sar r9d, cl' emit: [asm op: 16rD3 len: 1 pre: 0 w: 0 reg: 7 rm: 9 byte: false].
	self case: 'imul r11, r12' emit: [asm op: 16rAF0F len: 2 pre: 0 w: 1 reg: 11 rm: 12 byte: false].
	self case: 'imul rbx' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 5 rm: 3 byte: false].
	self case: 'mul r8' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 4 rm: 8 byte: false].
	self case: 'idiv r12' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 7 rm: 12 byte: false].
	self case: 'movsxd rdi, esi' emit: [asm op: 16r63 len: 1 pre: 0 w: 1 reg: 7 rm: 6 byte: false].
	self case: 'movsxd r11, r11d' emit: [asm op: 16r63 len: 1 pre: 0 w: 1 reg: 11 rm: 11 byte: false].
	self case: 'movzx edi, dil' emit: [asm op: 16rB60F len: 2 pre: 0 w: 0 reg: 7 rm: 7 byte: true].
	self case: 'movzx eax, al' emit: [asm op: 16rB60F len: 2 pre: 0 w: 0 reg: 0 rm: 0 byte: true].
	self case: 'movzx r9d, r9b' emit: [asm op: 16rB60F len: 2 pre: 0 w: 0 reg: 9 rm: 9 byte: true].
	self case: 'cmove rdi, rsi' emit: [asm op: 16r440F len: 2 pre: 0 w: 1 reg: 7 rm: 6 byte: false].
	self case: 'cmovg r14, r10' emit: [asm op: 16r4F0F len: 2 pre: 0 w: 1 reg: 14 rm: 10 byte: false].
	self case: 'sete al' emit: [asm op: 16r940F len: 2 pre: 0 w: 0 reg: 0 rm: 0 byte: true].
	self case: 'setb sil' emit: [asm op: 16r920F len: 2 pre: 0 w: 0 reg: 0 rm: 6 byte: true].
	self case: 'setnp r11b' emit: [asm op: 16r9B0F len: 2 pre: 0 w: 0 reg: 0 rm: 11 byte: true].
	self case: 'jmp r11' emit: [asm op: 16rFF len: 1 pre: 0 w: 0 reg: 4 rm: 11 byte: false].
	self case: 'call rax' emit: [asm op: 16rFF len: 1 pre: 0 w: 0 reg: 2 rm: 0 byte: false].
	self case: 'movapd xmm9, xmm2' emit: [asm op: 16r280F len: 2 pre: 16r66 w: 0 reg: 9 rm: 2 byte: false].
	self case: 'movq xmm0, r11' emit: [asm op: 16r6E0F len: 2 pre: 16r66 w: 1 reg: 0 rm: 11 byte: false].
	self case: 'movq r15, xmm12' emit: [asm op: 16r7E0F len: 2 pre: 16r66 w: 1 reg: 12 rm: 15 byte: false].
	self case: 'addsd xmm1, xmm15' emit: [asm sse: 16r58 rd: D1 rm: D15].
	self case: 'ucomisd xmm8, xmm0' emit: [asm op: 16r2E0F len: 2 pre: 16r66 w: 0 reg: 8 rm: 0 byte: false].
	self case: 'cvtsi2sd xmm3, r10' emit: [asm op: 16r2A0F len: 2 pre: 16rF2 w: 1 reg: 3 rm: 10 byte: false].
	self case: 'cvtsi2sd xmm11, ecx' emit: [asm op: 16r2A0F len: 2 pre: 16rF2 w: 0 reg: 11 rm: 1 byte: false].
	self case: 'cvttsd2si rbp, xmm7' emit: [asm op: 16r2C0F len: 2 pre: 16rF2 w: 1 reg: 5 rm: 7 byte: false]
!
memoryForms
	"[base + disp]: every base (rsp and r12 take a SIB byte, rbp and r13 a displacement), disp 0, 8 and 32 bits, loads, stores and immediates"
	<function>
	self case: 'mov rdi, QWORD PTR [rbx+8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 3 disp: 8 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rax]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 0 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rcx]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 1 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rdx]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 2 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rsp]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 4 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rbp]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 5 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rsi]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 6 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rdi]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 7 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 8 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r11]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 11 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r12]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 12 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r13]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 13 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r15]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 15 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rsp+8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 4 disp: 8 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r12-8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 12 disp: -8 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r13+127]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 13 disp: 127 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rbp-128]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 5 disp: -128 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rbp+128]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 5 disp: 128 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rsp+4096]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 4 disp: 4096 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r12-129]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 12 disp: -129 imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r15+0x7fffffff]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 15 disp: 16r7FFFFFFF imm: 0 isz: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r8-0x80000000]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 8 disp: -16r80000000 imm: 0 isz: 0 byte: false].
	self case: 'mov r15, QWORD PTR [rax]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 15 base: 0 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov r12, QWORD PTR [r12+16]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 12 base: 12 disp: 16 imm: 0 isz: 0 byte: false].
	self case: 'mov esp, DWORD PTR [r9+4]' emit: [asm op: 16r8B len: 1 pre: 0 w: 0 reg: 4 base: 9 disp: 4 imm: 0 isz: 0 byte: false].
	self case: 'mov QWORD PTR [rbx+8], rax' emit: [asm op: 16r89 len: 1 pre: 0 w: 1 reg: 0 base: 3 disp: 8 imm: 0 isz: 0 byte: false].
	self case: 'mov DWORD PTR [rsp+4], esi' emit: [asm op: 16r89 len: 1 pre: 0 w: 0 reg: 6 base: 4 disp: 4 imm: 0 isz: 0 byte: false].
	self case: 'mov QWORD PTR [r13], r10' emit: [asm op: 16r89 len: 1 pre: 0 w: 1 reg: 10 base: 13 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov BYTE PTR [rbx+1], sil' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 6 base: 3 disp: 1 imm: 0 isz: 0 byte: true].
	self case: 'mov BYTE PTR [rax], spl' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 4 base: 0 disp: 0 imm: 0 isz: 0 byte: true].
	self case: 'mov BYTE PTR [rax], bpl' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 5 base: 0 disp: 0 imm: 0 isz: 0 byte: true].
	self case: 'mov BYTE PTR [rax], dil' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 7 base: 0 disp: 0 imm: 0 isz: 0 byte: true].
	self case: 'mov BYTE PTR [rax], bl' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 3 base: 0 disp: 0 imm: 0 isz: 0 byte: true].
	self case: 'mov BYTE PTR [rsp], r12b' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 12 base: 4 disp: 0 imm: 0 isz: 0 byte: true].
	self case: 'mov WORD PTR [rbx+2], ax' emit: [asm op: 16r89 len: 1 pre: 16r66 w: 0 reg: 0 base: 3 disp: 2 imm: 0 isz: 0 byte: false].
	self case: 'mov WORD PTR [r13], r9w' emit: [asm op: 16r89 len: 1 pre: 16r66 w: 0 reg: 9 base: 13 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'movzx edi, BYTE PTR [rbx+3]' emit: [asm op: 16rB60F len: 2 pre: 0 w: 0 reg: 7 base: 3 disp: 3 imm: 0 isz: 0 byte: false].
	self case: 'movzx r10d, WORD PTR [r12+2]' emit: [asm op: 16rB70F len: 2 pre: 0 w: 0 reg: 10 base: 12 disp: 2 imm: 0 isz: 0 byte: false].
	self case: 'movsx rdi, BYTE PTR [rbx+1]' emit: [asm op: 16rBE0F len: 2 pre: 0 w: 1 reg: 7 base: 3 disp: 1 imm: 0 isz: 0 byte: false].
	self case: 'movsx rdi, WORD PTR [rbp]' emit: [asm op: 16rBF0F len: 2 pre: 0 w: 1 reg: 7 base: 5 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'movsxd rdi, DWORD PTR [rbx+4]' emit: [asm op: 16r63 len: 1 pre: 0 w: 1 reg: 7 base: 3 disp: 4 imm: 0 isz: 0 byte: false].
	self case: 'lea rsp, [rsp-16]' emit: [asm op: 16r8D len: 1 pre: 0 w: 1 reg: 4 base: 4 disp: -16 imm: 0 isz: 0 byte: false].
	self case: 'lea r11, [r11+1]' emit: [asm op: 16r8D len: 1 pre: 0 w: 1 reg: 11 base: 11 disp: 1 imm: 0 isz: 0 byte: false].
	self case: 'movsd xmm0, QWORD PTR [rbx+8]' emit: [asm op: 16r100F len: 2 pre: 16rF2 w: 0 reg: 0 base: 3 disp: 8 imm: 0 isz: 0 byte: false].
	self case: 'movsd QWORD PTR [rsp+56], xmm15' emit: [asm op: 16r110F len: 2 pre: 16rF2 w: 0 reg: 15 base: 4 disp: 56 imm: 0 isz: 0 byte: false].
	self case: 'movsd xmm8, QWORD PTR [r12]' emit: [asm op: 16r100F len: 2 pre: 16rF2 w: 0 reg: 8 base: 12 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'subsd xmm0, QWORD PTR [rsp]' emit: [asm op: 16r5C0F len: 2 pre: 16rF2 w: 0 reg: 0 base: 4 disp: 0 imm: 0 isz: 0 byte: false].
	self case: 'mov QWORD PTR [rbx+8], 0' emit: [asm op: 16rC7 len: 1 pre: 0 w: 1 reg: 0 base: 3 disp: 8 imm: 0 isz: 4 byte: false].
	self case: 'mov DWORD PTR [rsp], 0x12345678' emit: [asm op: 16rC7 len: 1 pre: 0 w: 0 reg: 0 base: 4 disp: 0 imm: 16r12345678 isz: 4 byte: false].
	self case: 'mov QWORD PTR [r13+0x1000], -1' emit: [asm op: 16rC7 len: 1 pre: 0 w: 1 reg: 0 base: 13 disp: 4096 imm: -1 isz: 4 byte: false].
	self case: 'cmp QWORD PTR [rbx+8], 5' emit: [asm op: 16r83 len: 1 pre: 0 w: 1 reg: 7 base: 3 disp: 8 imm: 5 isz: 1 byte: false].
	self case: 'cmp QWORD PTR [r12+8], 1000' emit: [asm op: 16r81 len: 1 pre: 0 w: 1 reg: 7 base: 12 disp: 8 imm: 1000 isz: 4 byte: false].
	self case: 'cmp rdi, QWORD PTR [rdi+8]' emit: [asm op: 16r3B len: 1 pre: 0 w: 1 reg: 7 base: 7 disp: 8 imm: 0 isz: 0 byte: false].
	self case: 'idiv QWORD PTR [rsp+8]' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 7 base: 4 disp: 8 imm: 0 isz: 0 byte: false].
	self case: 'imul QWORD PTR [rsp]' emit: [asm op: 16rF7 len: 1 pre: 0 w: 1 reg: 5 base: 4 disp: 0 imm: 0 isz: 0 byte: false]
!
indexedForms
	"[base + index * scale + disp]: rbp and r13 bases take a displacement, r12 is an index like the others"
	<function>
	self case: 'mov rdi, QWORD PTR [rbx+rsi*8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 3 index: 6 scale: 3 disp: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rbp+r12*1]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 5 index: 12 scale: 0 disp: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [r13+rax*2]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 13 index: 0 scale: 1 disp: 0 byte: false].
	self case: 'mov rax, QWORD PTR [rsp+rdi*4]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 0 base: 4 index: 7 scale: 2 disp: 0 byte: false].
	self case: 'mov r15, QWORD PTR [r12+r13*8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 15 base: 12 index: 13 scale: 3 disp: 0 byte: false].
	self case: 'mov rdi, QWORD PTR [rbx+rsi*1+8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 3 index: 6 scale: 0 disp: 8 byte: false].
	self case: 'mov rdi, QWORD PTR [rbx+rsi*1-0x1000]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 base: 3 index: 6 scale: 0 disp: -4096 byte: false].
	self case: 'mov r10, QWORD PTR [r12+r10*8]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 10 base: 12 index: 10 scale: 3 disp: 0 byte: false].
	self case: 'lea r11, [r11+rax*1]' emit: [asm op: 16r8D len: 1 pre: 0 w: 1 reg: 11 base: 11 index: 0 scale: 0 disp: 0 byte: false].
	self case: 'lea rdx, [r15+r15*1]' emit: [asm op: 16r8D len: 1 pre: 0 w: 1 reg: 2 base: 15 index: 15 scale: 0 disp: 0 byte: false].
	self case: 'mov QWORD PTR [rbx+rcx*8], rdi' emit: [asm op: 16r89 len: 1 pre: 0 w: 1 reg: 7 base: 3 index: 1 scale: 3 disp: 0 byte: false].
	self case: 'mov DWORD PTR [r8+r9*4], r10d' emit: [asm op: 16r89 len: 1 pre: 0 w: 0 reg: 10 base: 8 index: 9 scale: 2 disp: 0 byte: false].
	self case: 'mov BYTE PTR [rbx+rdi*1], sil' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 6 base: 3 index: 7 scale: 0 disp: 0 byte: true].
	self case: 'mov BYTE PTR [rbx+rdi*1], cl' emit: [asm op: 16r88 len: 1 pre: 0 w: 0 reg: 1 base: 3 index: 7 scale: 0 disp: 0 byte: true].
	self case: 'movzx edi, BYTE PTR [rbx+rsi*1]' emit: [asm op: 16rB60F len: 2 pre: 0 w: 0 reg: 7 base: 3 index: 6 scale: 0 disp: 0 byte: false].
	self case: 'movzx edi, WORD PTR [rbx+rsi*2]' emit: [asm op: 16rB70F len: 2 pre: 0 w: 0 reg: 7 base: 3 index: 6 scale: 1 disp: 0 byte: false].
	self case: 'mov WORD PTR [rbx+rsi*2], di' emit: [asm op: 16r89 len: 1 pre: 16r66 w: 0 reg: 7 base: 3 index: 6 scale: 1 disp: 0 byte: false].
	self case: 'movsd xmm1, QWORD PTR [rbx+rsi*8]' emit: [asm op: 16r100F len: 2 pre: 16rF2 w: 0 reg: 1 base: 3 index: 6 scale: 3 disp: 0 byte: false].
	self case: 'movsd QWORD PTR [r11+r14*8], xmm13' emit: [asm op: 16r110F len: 2 pre: 16rF2 w: 0 reg: 13 base: 11 index: 14 scale: 3 disp: 0 byte: false]
!
pcRelativeForms
	"[rip + disp32] to an address 256 bytes into the buffer (or before it): the displacement counts from the end of the instruction, immediate included"
	<function>
	self case: 'mov rdi, QWORD PTR [rip+0xf9]' emit: [asm op: 16r8B len: 1 pre: 0 w: 1 reg: 7 target: buffer + 256 imm: 0 isz: 0].
	self case: 'mov QWORD PTR [rip-0x107], r11' emit: [asm op: 16r89 len: 1 pre: 0 w: 1 reg: 11 target: buffer - 256 imm: 0 isz: 0].
	self case: 'mov r10d, DWORD PTR [rip+0xf9]' emit: [asm op: 16r8B len: 1 pre: 0 w: 0 reg: 10 target: buffer + 256 imm: 0 isz: 0].
	self case: 'lea rdi, [rip+0xf9]' emit: [asm op: 16r8D len: 1 pre: 0 w: 1 reg: 7 target: buffer + 256 imm: 0 isz: 0].
	self case: 'sub DWORD PTR [rip+0xf9], 1' emit: [asm op: 16r83 len: 1 pre: 0 w: 0 reg: 5 target: buffer + 256 imm: 1 isz: 1].
	self case: 'cmp QWORD PTR [rip+0xf8], 5' emit: [asm op: 16r83 len: 1 pre: 0 w: 1 reg: 7 target: buffer + 256 imm: 5 isz: 1].
	self case: 'cmp QWORD PTR [rip+0xf5], 1000' emit: [asm op: 16r81 len: 1 pre: 0 w: 1 reg: 7 target: buffer + 256 imm: 1000 isz: 4].
	self case: 'test BYTE PTR [rip+0xf9], 7' emit: [asm op: 16rF6 len: 1 pre: 0 w: 0 reg: 0 target: buffer + 256 imm: 7 isz: 1].
	self case: 'test DWORD PTR [rip+0xf6], 0x100' emit: [asm op: 16rF7 len: 1 pre: 0 w: 0 reg: 0 target: buffer + 256 imm: 16r100 isz: 4].
	self case: 'mov QWORD PTR [rip+0xf5], 5' emit: [asm op: 16rC7 len: 1 pre: 0 w: 1 reg: 0 target: buffer + 256 imm: 5 isz: 4].
	self case: 'push QWORD PTR [rip+0xfa]' emit: [asm op: 16rFF len: 1 pre: 0 w: 0 reg: 6 target: buffer + 256 imm: 0 isz: 0].
	self case: 'pop QWORD PTR [rip+0xfa]' emit: [asm op: 16r8F len: 1 pre: 0 w: 0 reg: 0 target: buffer + 256 imm: 0 isz: 0].
	self case: 'cmove rdi, QWORD PTR [rip+0xf8]' emit: [asm op: 16r440F len: 2 pre: 0 w: 1 reg: 7 target: buffer + 256 imm: 0 isz: 0].
	self case: 'imul r11, QWORD PTR [rip+0xf8]' emit: [asm op: 16rAF0F len: 2 pre: 0 w: 1 reg: 11 target: buffer + 256 imm: 0 isz: 0].
	self case: 'cmp QWORD PTR [rip+0xf9], rsi' emit: [asm op: 16r39 len: 1 pre: 0 w: 1 reg: 6 target: buffer + 256 imm: 0 isz: 0].
	self case: 'test QWORD PTR [rip+0xf9], r11' emit: [asm op: 16r85 len: 1 pre: 0 w: 1 reg: 11 target: buffer + 256 imm: 0 isz: 0].
	self case: 'ucomisd xmm0, QWORD PTR [rip+0xf8]' emit: [asm op: 16r2E0F len: 2 pre: 16r66 w: 0 reg: 0 target: buffer + 256 imm: 0 isz: 0].
	self case: 'movsd xmm12, QWORD PTR [rip+0xf7]' emit: [asm op: 16r100F len: 2 pre: 16rF2 w: 0 reg: 12 target: buffer + 256 imm: 0 isz: 0]
!
jumpForms
	"jcc: rel8 to a known label in reach, else rel32; jmp rel32"
	<function>
	self case: 'jo .+16|jno .+16|jb .+16|jae .+16|je .+16|jne .+16|jbe .+16|ja .+16|js .+16|jns .+16|jp .+16|jnp .+16|jl .+16|jge .+16|jle .+16|jg .+16' emit: [
		0 to: 15 do: [:cc | asm jcc: cc to: (asm labelAt: asm pc + 16)]].
	self case: 'je .+129' emit: [asm jcc: 4 to: (asm labelAt: asm pc + 129)].
	self case: '{disp32} je .+130' emit: [asm jcc: 4 to: (asm labelAt: asm pc + 130)].
	self case: 'jne .-126' emit: [asm jcc: 5 to: (asm labelAt: asm pc - 126)].
	self case: '{disp32} jne .-127' emit: [asm jcc: 5 to: (asm labelAt: asm pc - 127)].
	self case: 'jg .-0x1000' emit: [asm jcc: 15 to: (asm labelAt: asm pc - 4096)].
	self case: 'jl .+0x7fffffff' emit: [asm jcc: 12 to: (asm labelAt: asm pc + 16r7FFFFFFF)].
	self case: '{disp32} jmp .+16' emit: [asm jmpRel32To: (asm labelAt: asm pc + 16)].
	self case: '{disp32} jmp .-16' emit: [asm jmpRel32To: (asm labelAt: asm pc - 16)]
!
stackForms
	"push and pop of each register, int3 alignment"
	<function>
	self case: 'push rax|push rcx|push rdx|push rbx|push rsp|push rbp|push rsi|push rdi|push r8|push r9|push r10|push r11|push r12|push r13|push r14|push r15' emit: [
		0 to: 15 do: [:r | asm pushX64: r]].
	self case: 'pop rax|pop rcx|pop rdx|pop rbx|pop rsp|pop rbp|pop rsi|pop rdi|pop r8|pop r9|pop r10|pop r11|pop r12|pop r13|pop r14|pop r15' emit: [
		0 to: 15 do: [:r | asm popX64: r]].
	self case: 'ret|int3|int3|int3|int3|int3|int3|int3' emit: [asm ret. asm alignTo: 8]
! !

!Amd64AssemblerCases methodsFor: 'arm64 instructions'!
moves
	<function>
	self case: '{load} mov rdi, rsi' emit: [asm mov: X0 with: X1].
	self case: '{load} mov edi, esi' emit: [asm mov: W0 with: W1].
	self case: '{load} mov r10, rsp' emit: [asm mov: X16 with: SP].
	self case: '{load} mov rsp, rbp' emit: [asm mov: SP with: X19].
	self case: 'mov edi, 0' emit: [asm mov: X0 with: XZR].
	self case: 'mov edi, 5' emit: [asm mov: X0 imm: 5].
	self case: 'mov r14d, 5' emit: [asm mov: X10 imm: 5].
	self case: 'mov eax, 0xffffffff' emit: [asm mov: W9 imm: -1].
	self case: 'mov rdi, -5' emit: [asm mov: X0 imm: -5].
	self case: 'movabs rdi, 0x123456789' emit: [asm mov: X0 imm: 16r123456789].
	self case: 'movabs rdi, 5' emit: [asm mov: X0 imm64: 5].
	self case: 'movabs r10, 0x1122334455667788' emit: [asm mov: X16 imm64: 16r1122334455667788].
	self case: 'movabs r12, 0xfffffffffffffff0' emit: [asm mov: X17 imm64: -16].
	self case: 'mov ecx, 0x10000' emit: [asm movz: X3 imm: 1 shift: 16]
!
arithmetic
	<function>
	self case: 'lea rdi, [rsi+12]' emit: [asm add: X0 with: X1 imm: 12].
	self case: 'lea rdi, [rsi-5]' emit: [asm add: X0 with: X1 imm: -5].
	self case: 'lea rbx, [rbx+0x28]' emit: [asm add: X20 with: X20 imm: 40].
	self case: 'lea rbp, [rbp-0x40]' emit: [asm sub: X19 with: X19 imm: 64].
	self case: 'lea rsp, [rsp-16]' emit: [asm sub: SP with: SP imm: 16].
	self case: 'lea rdi, [rsp+32]' emit: [asm add: X0 with: SP imm: 32].
	self case: 'lea r12, [r13+0x1000]' emit: [asm add: X17 with: X21 imm: 4096].
	self case: '{load} mov rdi, rsi|lea edi, [rdi+1]' emit: [asm add: W0 with: W1 imm: 1].
	self case: 'lea rdi, [rsi+rdx*1]' emit: [asm add: X0 with: X1 with: X2].
	self case: 'lea rdi, [rsi+rdx*8]' emit: [asm add: X0 with: X1 with: X2 shift: SHIFT_LSL amount: 3].
	self case: 'lea r10, [rbx+r12*4]' emit: [asm add: X16 with: X20 with: X17 shift: SHIFT_LSL amount: 2].
	self case: '{load} mov rdi, rsi|add rdi, 5' emit: [asm adds: X0 with: X1 imm: 5].
	self case: 'add rdi, 1000' emit: [asm adds: X0 with: X0 imm: 1000].
	self case: 'sub rdi, 1' emit: [asm subs: X0 with: X0 imm: 1].
	self case: '{load} mov r10, rdi|sub r10, -128' emit: [asm subs: X16 with: X0 imm: -128].
	self case: 'cmp rdi, 5' emit: [asm cmp: X0 imm: 5].
	self case: 'cmp esi, 300' emit: [asm cmp: W1 imm: 300].
	self case: 'cmp r14, -1' emit: [asm cmp: X10 imm: -1].
	self case: 'cmp rsp, 0' emit: [asm cmp: SP imm: 0].
	self case: 'cmp rdi, -5' emit: [asm cmn: X0 imm: 5].
	self case: 'cmp rdi, 0' emit: [asm subs: XZR with: X0 imm: 0].
	self case: '{load} cmp rdi, rsi' emit: [asm cmp: X0 with: X1].
	self case: '{load} cmp esi, edi' emit: [asm cmp: W1 with: W0].
	self case: '{load} cmp rsp, r10' emit: [asm cmp: SP with: X16].
	self case: '{load} add rdi, rsi' emit: [asm adds: X0 with: X0 with: X1].
	self case: '{load} sub rdi, rsi' emit: [asm subs: X0 with: X0 with: X1].
	self case: '{load} mov rdi, rsi|{load} sub rdi, rdx' emit: [asm sub: X0 with: X1 with: X2].
	self case: '{load} mov rdi, rsi|{load} add rdi, rdx' emit: [asm adds: X0 with: X1 with: X2].
	self case: '{load} add rdi, rsi' emit: [asm adds: X0 with: X1 with: X0].
	self case: '{load} mov r11, rsi|{load} sub r11, rdi|{load} mov rdi, r11' emit: [asm sub: X0 with: X1 with: X0].
	self case: '{load} mov r11, rdx|shl r11, 3|{load} mov rdi, rsi|{load} sub rdi, r11' emit: [asm sub: X0 with: X1 with: X2 shift: SHIFT_LSL amount: 3].
	self case: '{load} mov r11, rcx|sar r11, 1|{load} cmp rdi, r11' emit: [asm cmp: X0 with: X3 shift: SHIFT_ASR amount: 1].
	self case: '{load} mov rdi, rsi|neg rdi' emit: [asm neg: X0 with: X1].
	self case: 'neg r10' emit: [asm neg: X16 with: X16].
	self case: '{load} mov r11, rdi|{load} add r11, rsi' emit: [asm cmn: X0 with: X1]
!
logical
	<function>
	self case: 'and rdi, 255' emit: [asm and: X0 with: X0 imm: 255].
	self case: 'and rdi, -8' emit: [asm and: X0 with: X0 imm: -8].
	self case: '{load} mov rdi, rsi|or rdi, 1' emit: [asm orr: X0 with: X1 imm: 1].
	self case: 'xor edi, 0x80000000' emit: [asm eor: W0 with: W0 imm: 16r80000000].
	self case: '{load} mov r10, rdi|and r10, 7' emit: [asm ands: X16 with: X0 imm: 7].
	self case: 'and rdi, -2' emit: [asm bic: X0 with: X0 imm: 1].
	self case: '{load} mov rdi, rsi|{load} mov edi, edi' emit: [asm and: X0 with: X1 imm: 16rFFFFFFFF].
	self case: '{load} mov rdi, rsi|movabs r11, 0xff00ff00ff00ff00|{load} and rdi, r11' emit: [asm and: X0 with: X1 imm: 16rFF00FF00FF00FF00].
	self case: 'test dil, 7' emit: [asm tst: X0 imm: 7].
	self case: 'test sil, 1' emit: [asm tst: W1 imm: 1].
	self case: 'test r14b, 1' emit: [asm tst: X10 imm: 1].
	self case: 'test bl, 0x7f' emit: [asm tst: X20 imm: 16r7F].
	self case: 'test edi, 0x80' emit: [asm tst: X0 imm: 16r80].
	self case: 'test r12d, 0x7fffffff' emit: [asm tst: X17 imm: 16r7FFFFFFF].
	self case: 'test rdi, -8' emit: [asm tst: X0 imm: -8].
	self case: 'test rdi, rsi' emit: [asm tst: X0 with: X1].
	self case: 'test esi, edi' emit: [asm tst: W1 with: W0].
	self case: 'test rdi, rsi' emit: [asm ands: XZR with: X0 with: X1].
	self case: '{load} and rdi, rsi' emit: [asm and: X0 with: X0 with: X1].
	self case: '{load} or rdi, rsi' emit: [asm orr: X0 with: X0 with: X1].
	self case: '{load} xor rdi, rsi' emit: [asm eor: X0 with: X0 with: X1].
	self case: '{load} mov rdi, rsi|{load} and rdi, rdx' emit: [asm and: X0 with: X1 with: X2].
	self case: '{load} mov r10, rdi|{load} and r10, rsi' emit: [asm ands: X16 with: X0 with: X1].
	self case: '{load} and rdi, rsi' emit: [asm and: X0 with: X1 with: X0].
	self case: '{load} mov r11, rdx|shr r11, 4|{load} mov rdi, rsi|{load} or rdi, r11' emit: [asm orr: X0 with: X1 with: X2 shift: SHIFT_LSR amount: 4].
	self case: '{load} mov rdi, rsi|not rdi' emit: [asm mvn: X0 with: X1]
!
shifts
	<function>
	self case: 'shl rdi, 3' emit: [asm lsl: X0 with: X0 imm: 3].
	self case: '{load} mov rdi, rsi|sar rdi, 1' emit: [asm asr: X0 with: X1 imm: 1].
	self case: 'shr edi, 4' emit: [asm lsr: W0 with: W0 imm: 4].
	self case: 'ror rdi, 7' emit: [asm ror: X0 with: X0 imm: 7].
	self case: 'shl r10, 63' emit: [asm lsl: X16 with: X16 imm: 63].
	self case: '{load} mov edi, edi' emit: [asm lsl: W0 with: W0 imm: 0].
	self case: 'shl rdi, cl' emit: [asm lsl: X0 with: X0 with: X3].
	self case: '{load} mov rdi, rsi|sar rdi, cl' emit: [asm asr: X0 with: X1 with: X3].
	self case: 'push rcx|{load} mov rcx, rdx|{load} mov rdi, rsi|sar rdi, cl|pop rcx' emit: [asm asr: X0 with: X1 with: X2].
	self case: 'push rcx|{load} mov rcx, rdx|mov r11, QWORD PTR [rsp]|shr r11, cl|pop rcx|{load} mov rcx, r11' emit: [asm lsr: X3 with: X3 with: X2].
	self case: '{load} mov rdi, rsi|shr rdi, 3|and edi, 255' emit: [asm ubfx: X0 with: X1 lsb: 3 width: 8].
	self case: 'and edi, 1' emit: [asm ubfx: X0 with: X0 lsb: 0 width: 1].
	self case: '{load} mov rdi, rsi|shl rdi, 56|sar rdi, 60' emit: [asm sbfx: X0 with: X1 lsb: 4 width: 4].
	self case: '{load} mov rdi, rsi|shl rdi, 60|shr rdi, 57' emit: [asm ubfiz: X0 with: X1 lsb: 3 width: 4].
	self case: 'movsxd rdi, esi' emit: [asm sxtw: X0 with: W1].
	self case: '{load} mov rdi, rsi|movzx edi, dil' emit: [asm uxtb: X0 with: X1]
!
multiply
	<function>
	self case: 'imul rdi, rsi' emit: [asm mul: X0 with: X0 with: X1].
	self case: '{load} mov rdi, rsi|imul rdi, rdx' emit: [asm mul: X0 with: X1 with: X2].
	self case: '{load} mov r11, rsi|imul r11d, edi|{load} mov r11d, r11d|{load} mov rdi, r11' emit: [asm mul: W0 with: W1 with: W0].
	self case: '{load} mov r11, rsi|imul r11, rdx|{load} add r11, rcx|{load} mov rdi, r11' emit: [asm madd: X0 with: X1 with: X2 add: X3].
	self case: '{load} mov r11, rsi|imul r11, rdx|{load} sub r11, rcx|neg r11|{load} mov rdi, r11' emit: [asm msub: X0 with: X1 with: X2 sub: X3].
	self case: 'push rax|push rdx|{load} mov rax, rsi|imul QWORD PTR [rsp]|{load} mov r11, rdx|pop rdx|pop rax|{load} mov rdi, r11' emit: [asm smulh: X0 with: X1 with: X2].
	self case: 'push rax|push rdx|mov rax, QWORD PTR [rsp]|mul rdi|{load} mov r11, rdx|pop rdx|pop rax|{load} mov rax, r11' emit: [asm umulh: X9 with: X2 with: X0].
	self case: 'cmp r8, 0|{disp32} je 3f|cmp r8, -1|{disp32} je 2f|push rax|push rdx|{load} mov rax, rsi|cqo|idiv r8|{load} mov r11, rax|pop rdx|pop rax|{load} mov rdi, r11|{disp32} jmp 4f|2:|{load} mov rdi, rsi|neg rdi|{disp32} jmp 4f|3:|mov edi, 0|4:' emit: [asm sdiv: X0 with: X1 with: X4]
!
conditional
	<function>
	self case: '{load} mov rdi, rdx|cmove rdi, rsi' emit: [asm csel: X0 with: X1 with: X2 cond: COND_EQ].
	self case: 'cmovne rdi, rdx' emit: [asm csel: X0 with: X0 with: X2 cond: COND_EQ].
	self case: '{load} cmp rdi, rsi|{load} mov rdi, rdx|cmovb rdi, rsi' emit: [asm cmp: X0 with: X1. asm csel: X0 with: X1 with: X2 cond: COND_LO].
	self case: '{load} cmp rdi, rsi|mov r11d, 0|cmovl r10, r11' emit: [asm cmp: X0 with: X1. asm csel: X16 with: X16 with: XZR cond: COND_GE].
	self case: '{load} mov rax, rdx|cmovg rax, rsi|{load} mov eax, eax' emit: [asm csel: W9 with: W1 with: W2 cond: COND_GT].
	self case: 'mov edi, 0|setne dil' emit: [asm cset: X0 cond: COND_NE].
	self case: 'mov eax, 0|setl al' emit: [asm cset: X9 cond: COND_LT].
	self case: 'mov r10d, 0|setg r10b' emit: [asm cset: X16 cond: COND_GT].
	self case: '{load} cmp rdi, rsi|mov edx, 0|seta dl' emit: [asm cmp: X0 with: X1. asm cset: X2 cond: COND_HI].
	self case: 'test dil, 1|mov ebx, 0|sete bl' emit: [asm tst: X0 imm: 1. asm cset: X20 cond: COND_EQ].
	self case: 'mov edi, 0|sete dil|neg rdi' emit: [asm csetm: X0 cond: COND_EQ].
	self case: '{load} mov r11, rdx|lea r11, [r11+1]|{load} mov rdi, rsi|cmovne rdi, r11' emit: [asm csinc: X0 with: X1 with: X2 cond: COND_EQ].
	self case: '{load} mov r11, rsi|lea r11, [r11+1]|{load} mov rdi, rsi|cmovne rdi, r11' emit: [asm cinc: X0 with: X1 cond: COND_NE].
	self case: 'ucomisd xmm0, xmm1|mov edi, 0|mov r11d, 0|setnp r11b|sete dil|{load} and edi, r11d' emit: [asm fcmp: D0 with: D1. asm cset: X0 cond: COND_EQ].
	self case: 'ucomisd xmm0, xmm1|mov edi, 0|mov r11d, 0|setp r11b|setne dil|{load} or edi, r11d' emit: [asm fcmp: D0 with: D1. asm cset: X0 cond: COND_NE].
	self case: 'ucomisd xmm2, xmm3|{load} mov rdi, rdx|cmova rdi, rsi' emit: [asm fcmp: D2 with: D3. asm csel: X0 with: X1 with: X2 cond: COND_GT].
	self case: 'ucomisd xmm2, xmm3|mov edi, 0|setae dil' emit: [asm fcmp: D2 with: D3. asm cset: X0 cond: COND_GE]
!
loadStore
	<function>
	self case: 'mov rdi, QWORD PTR [rbx+8]' emit: [asm ldr: X0 base: X20 offset: 8].
	self case: 'mov rdi, QWORD PTR [rbp]' emit: [asm ldr: X0 base: X19 offset: 0].
	self case: 'mov rdi, QWORD PTR [r12]' emit: [asm ldr: X0 base: X17 offset: 0].
	self case: 'mov rdi, QWORD PTR [r13]' emit: [asm ldr: X0 base: X21 offset: 0].
	self case: 'mov rdi, QWORD PTR [rsp+16]' emit: [asm ldr: X0 base: SP offset: 16].
	self case: 'mov rdi, QWORD PTR [rbx+4096]' emit: [asm ldr: X0 base: X20 offset: 4096].
	self case: 'mov rdi, QWORD PTR [rbx-8]' emit: [asm ldr: X0 base: X20 offset: -8].
	self case: 'mov r12, QWORD PTR [r13+128]' emit: [asm ldr: X17 base: X21 offset: 128].
	self case: 'mov r14, QWORD PTR [r12-0x1000]' emit: [asm ldur: X10 base: X17 offset: -4096].
	self case: 'mov edi, DWORD PTR [rbx+8]' emit: [asm ldr: W0 base: X20 offset: 8].
	self case: 'mov QWORD PTR [rbx+8], rdi' emit: [asm str: X0 base: X20 offset: 8].
	self case: 'mov QWORD PTR [rsp], r14' emit: [asm str: X10 base: SP offset: 0].
	self case: 'mov DWORD PTR [rbp+4], esi' emit: [asm str: W1 base: X19 offset: 4].
	self case: 'mov QWORD PTR [r12+0x100], r15' emit: [asm stur: X11 base: X17 offset: 256].
	self case: 'mov QWORD PTR [rbx+8], 0' emit: [asm str: XZR base: X20 offset: 8].
	self case: 'mov DWORD PTR [rsp+8], 0' emit: [asm str: WZR base: SP offset: 8].
	self case: 'movzx edi, BYTE PTR [rbx+3]' emit: [asm ldrb: X0 base: X20 offset: 3].
	self case: 'movzx r12d, BYTE PTR [r13]' emit: [asm ldrb: W17 base: X21 offset: 0].
	self case: 'mov BYTE PTR [rbx+3], dil' emit: [asm strb: X0 base: X20 offset: 3].
	self case: 'mov BYTE PTR [rbx+3], sil' emit: [asm strb: X1 base: X20 offset: 3].
	self case: 'mov BYTE PTR [rbx+3], al' emit: [asm strb: X9 base: X20 offset: 3].
	self case: 'mov BYTE PTR [rbx+3], r10b' emit: [asm strb: X16 base: X20 offset: 3].
	self case: 'mov BYTE PTR [rsp], dl' emit: [asm strb: W2 base: SP offset: 0].
	self case: 'movzx edi, WORD PTR [rbx+2]' emit: [asm ldrh: X0 base: X20 offset: 2].
	self case: 'mov WORD PTR [rbx+2], di' emit: [asm strh: X0 base: X20 offset: 2].
	self case: 'movsx rdi, BYTE PTR [rbx+1]' emit: [asm ldrsb: X0 base: X20 offset: 1].
	self case: 'movsx edi, BYTE PTR [rbx+1]' emit: [asm ldrsb: W0 base: X20 offset: 1].
	self case: 'movsx rdi, WORD PTR [rbx+2]' emit: [asm ldrsh: X0 base: X20 offset: 2].
	self case: 'movsxd rdi, DWORD PTR [rbx+4]' emit: [asm ldrsw: X0 base: X20 offset: 4].
	self case: 'movsd xmm0, QWORD PTR [rbx+8]' emit: [asm ldr: D0 base: X20 offset: 8].
	self case: 'movsd QWORD PTR [rsp+8], xmm9' emit: [asm str: D9 base: SP offset: 8].
	self case: 'movsd xmm15, QWORD PTR [r13+0x200]' emit: [asm ldr: D15 base: X21 offset: 512].
	self case: 'mov rdi, QWORD PTR [rbx+rsi*8]' emit: [asm ldr: X0 base: X20 index: X1 extend: EXT_LSL shift: 3].
	self case: 'mov rdi, QWORD PTR [rbp+r12*1]' emit: [asm ldr: X0 base: X19 index: X17 extend: EXT_LSL shift: 0].
	self case: 'mov rdi, QWORD PTR [rbx+rsi*1]' emit: [asm ldr: X0 base: X20 index: X1].
	self case: 'mov QWORD PTR [r13+rax*2], rdi' emit: [asm str: X0 base: X21 index: X9 extend: EXT_LSL shift: 1].
	self case: 'mov QWORD PTR [rbx+rsi*1], rdi' emit: [asm str: X0 base: X20 index: X1].
	self case: 'movzx edi, BYTE PTR [rbx+rsi*1]' emit: [asm ldrb: X0 base: X20 index: X1].
	self case: 'mov BYTE PTR [rbx+rdi*1], sil' emit: [asm strb: X1 base: X20 index: X0].
	self case: 'mov rdi, QWORD PTR [r13+r12*8+8]' emit: [asm ldr: X0 base: X21 index: X17 shift: 3 offset: 8].
	self case: 'mov QWORD PTR [r14+r12*8+24], rsi' emit: [asm str: X1 base: X10 index: X17 shift: 3 offset: 24].
	self case: 'mov r11, QWORD PTR [rip+0xff9]|mov QWORD PTR [r14+r12*8+16], r11' emit: [asm str: X23 base: X10 index: X17 shift: 3 offset: 16].
	self case: 'movzx r10d, BYTE PTR [rbp+r12*1+15]' emit: [asm ldrb: W16 base: X19 index: X17 offset: 15].
	self case: 'mov BYTE PTR [rax+r12*1+0x200], r10b' emit: [asm strb: W16 base: X9 index: X17 offset: 512].
	self case: 'movsxd r11, esi|lea r11, [rbx+r11*8]|mov rdi, QWORD PTR [r11]' emit: [asm ldr: X0 base: X20 index: W1 extend: EXT_SXTW shift: 3].
	self case: '{load} mov r11, rsi|{load} mov r11d, r11d|lea r11, [rbx+r11*4]|mov edi, DWORD PTR [r11]' emit: [asm ldr: W0 base: X20 index: W1 extend: EXT_UXTW shift: 2].
	self case: 'lea r11, [rbx+rsi*2]|movzx edi, WORD PTR [r11]' emit: [asm ldrh: X0 base: X20 index: X1 extend: EXT_LSL shift: 1].
	self case: 'lea r11, [rbx+rsi*2]|mov WORD PTR [r11], di' emit: [asm strh: X0 base: X20 index: X1 extend: EXT_LSL shift: 1].
	self case: 'lea r11, [rbx+rsi*8]|movsd xmm2, QWORD PTR [r11]' emit: [asm ldr: D2 base: X20 index: X1 extend: EXT_LSL shift: 3].
	self case: 'mov rdi, QWORD PTR [rbx]|lea rbx, [rbx+16]' emit: [asm ldr: X0 base: X20 postIndex: 16].
	self case: 'lea rbx, [rbx-8]|mov QWORD PTR [rbx], rdi' emit: [asm str: X0 base: X20 preIndex: -8].
	self case: 'mov QWORD PTR [rbx+16], rdi|mov QWORD PTR [rbx+24], rsi' emit: [asm stp: X0 with: X1 base: X20 offset: 16].
	self case: 'mov rsi, QWORD PTR [rdi+8]|mov rdi, QWORD PTR [rdi]' emit: [asm ldp: X0 with: X1 base: X0 offset: 0].
	self case: 'mov rdi, QWORD PTR [rip+0xf9]' emit: [asm ldr: X0 label: (asm labelAt: asm pc + 256)].
	self case: 'mov r12, QWORD PTR [rip-0x107]' emit: [asm ldr: X17 label: (asm labelAt: asm pc - 256)].
	self case: 'movsd xmm3, QWORD PTR [rip+0xf8]' emit: [asm ldr: D3 label: (asm labelAt: asm pc + 256)].
	self case: 'lea rdi, [rip+0xf9]' emit: [asm adr: X0 label: (asm labelAt: asm pc + 256)].
	self case: 'lea r14, [rip-0x8]' emit: [asm adr: X10 label: (asm labelAt: asm pc - 1)]
!
state
	"x22 is the JitState (4 KB into the buffer), x23-x25 its first three words (nil, true, false): pc-relative"
	<function>
	self case: 'mov rdi, QWORD PTR [rip+0x1011]' emit: [asm ldr: X0 base: X22 offset: 24].
	self case: 'mov QWORD PTR [rip+0x1019], rdi' emit: [asm str: X0 base: X22 offset: 32].
	self case: 'mov r10d, DWORD PTR [rip+0x1021]' emit: [asm ldr: W16 base: X22 offset: 40].
	self case: 'lea rdi, [rip+0x1009]' emit: [asm add: X0 with: X22 imm: 16].
	self case: '{load} cmp rdi, QWORD PTR [rip+0xff9]' emit: [asm cmp: X0 with: X23].
	self case: 'mov rdi, QWORD PTR [rip+0x1001]' emit: [asm mov: X0 with: X24].
	self case: 'mov rdi, QWORD PTR [rip+0x1009]' emit: [asm mov: X0 with: X25].
	self case: '{load} mov rdi, rsi|cmove rdi, QWORD PTR [rip+0xffd]' emit: [asm csel: X0 with: X24 with: X1 cond: COND_EQ].
	self case: 'mov QWORD PTR [rip+0x1035], 0' emit: [asm str: XZR base: X22 offset: 64]
!
branches
	<function>
	self case: 'jmp .+16' emit: [asm b: (asm labelAt: asm pc + 16)].
	self case: 'jmp .-16' emit: [asm b: (asm labelAt: asm pc - 16)].
	self case: 'jmp .+0x100' emit: [asm b: (asm labelAt: asm pc + 256)].
	self case: 'call .+0x1000' emit: [asm bl: (asm labelAt: asm pc + 4096)].
	self case: 'call .-0x1000' emit: [asm bl: (asm labelAt: asm pc - 4096)].
	self case: 'je .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_EQ].
	self case: 'jne .+0x100' emit: [asm b: (asm labelAt: asm pc + 256) if: COND_NE].
	self case: 'jl .-16' emit: [asm b: (asm labelAt: asm pc - 16) if: COND_LT].
	self case: 'jmp .+16' emit: [asm b: (asm labelAt: asm pc + 16) if: COND_AL].
	self case: '{load} cmp rdi, rsi|jae .+16' emit: [asm cmp: X0 with: X1. asm b: (asm labelAt: asm pc + 16) if: COND_HS].
	self case: '{load} cmp rdi, rsi|jbe .+16' emit: [asm cmp: X0 with: X1. asm b: (asm labelAt: asm pc + 16) if: COND_LS].
	self case: 'test rdi, rdi|je .+0x3d' emit: [asm cbz: X0 to: (asm labelAt: asm pc + 64)].
	self case: 'test esi, esi|jne .-0x42' emit: [asm cbnz: W1 to: (asm labelAt: asm pc - 64)].
	self case: 'test dil, 8|je .+12' emit: [asm tbz: X0 bit: 3 to: (asm labelAt: asm pc + 16)].
	self case: 'test edi, 0x100|jne .+10' emit: [asm tbnz: X0 bit: 8 to: (asm labelAt: asm pc + 16)].
	self case: 'bt rdi, 40|jb .+11' emit: [asm tbnz: X0 bit: 40 to: (asm labelAt: asm pc + 16)].
	self case: 'bt r10, 63|jae .+11' emit: [asm tbz: X16 bit: 63 to: (asm labelAt: asm pc + 16)].
	self case: 'ucomisd xmm0, xmm1|jp .+0x40|jne .+0x3e' emit: [asm fcmp: D0 with: D1. asm b: (asm labelAt: asm pc + 64) if: COND_NE].
	self case: 'ucomisd xmm0, xmm1|jp .+4|je .+0x3e' emit: [asm fcmp: D0 with: D1. asm b: (asm labelAt: asm pc + 64) if: COND_EQ].
	self case: 'ucomisd xmm0, xmm1|jp .+8|{disp32} jb .+0xbe' emit: [asm fcmp: D0 with: D1. asm b: (asm labelAt: asm pc + 64 + 128) if: COND_MI].
	self case: 'ucomisd xmm0, xmm1|ja .+16' emit: [asm fcmp: D0 with: D1. asm b: (asm labelAt: asm pc + 16) if: COND_GT].
	self case: 'jmp rdi' emit: [asm br: X0].
	self case: 'call r10' emit: [asm blr: X16].
	self case: 'ret' emit: [asm ret].
	self case: 'nop' emit: [asm nop].
	self case: 'int3' emit: [asm brk: 0]
!
floatingPoint
	<function>
	self case: 'addsd xmm0, xmm1' emit: [asm fadd: D0 with: D0 with: D1].
	self case: 'addsd xmm0, xmm1' emit: [asm fadd: D0 with: D1 with: D0].
	self case: 'movapd xmm2, xmm0|addsd xmm2, xmm1' emit: [asm fadd: D2 with: D0 with: D1].
	self case: 'subsd xmm8, xmm9' emit: [asm fsub: D8 with: D8 with: D9].
	self case: 'lea rsp, [rsp-16]|movsd QWORD PTR [rsp], xmm0|movapd xmm0, xmm1|subsd xmm0, QWORD PTR [rsp]|lea rsp, [rsp+16]' emit: [asm fsub: D0 with: D1 with: D0].
	self case: 'mulsd xmm3, xmm4' emit: [asm fmul: D3 with: D3 with: D4].
	self case: 'movapd xmm5, xmm6|divsd xmm5, xmm7' emit: [asm fdiv: D5 with: D6 with: D7].
	self case: 'sqrtsd xmm0, xmm1' emit: [asm fsqrt: D0 with: D1].
	self case: 'movapd xmm0, xmm1' emit: [asm fmov: D0 with: D1].
	self case: 'movapd xmm15, xmm8' emit: [asm fmov: D15 with: D8].
	self case: 'movq xmm0, rsi' emit: [asm fmov: D0 with: X1].
	self case: 'movq rdi, xmm1' emit: [asm fmov: X0 with: D1].
	self case: 'movq xmm8, r14' emit: [asm fmov: D8 with: X10].
	self case: 'movq r12, xmm15' emit: [asm fmov: X17 with: D15].
	self case: 'movabs r11, 0x3ff0000000000000|movq xmm2, r11' emit: [asm fmov: D2 imm: 1.0].
	self case: 'cvtsi2sd xmm0, rsi' emit: [asm scvtf: D0 with: X1].
	self case: 'cvtsi2sd xmm0, esi' emit: [asm scvtf: D0 with: W1].
	self case: 'cvtsi2sd xmm9, r10' emit: [asm scvtf: D9 with: X16].
	self case: 'cvttsd2si rdi, xmm1' emit: [asm fcvtzs: X0 with: D1].
	self case: 'cvttsd2si r10d, xmm8' emit: [asm fcvtzs: W16 with: D8].
	self case: 'ucomisd xmm0, xmm1' emit: [asm fcmp: D0 with: D1].
	self case: 'ucomisd xmm9, xmm12' emit: [asm fcmp: D9 with: D12]
!
runtime
	"x86's own: the C call, a polymorphic inline cache's case, the counter decrement, push and pop"
	<function>
	self case: '{load} mov r11, rsp|and rsp, -16|sub rsp, 80|mov QWORD PTR [rsp+64], r11|movsd QWORD PTR [rsp], xmm8|movsd QWORD PTR [rsp+8], xmm9|movsd QWORD PTR [rsp+16], xmm10|movsd QWORD PTR [rsp+24], xmm11|movsd QWORD PTR [rsp+32], xmm12|movsd QWORD PTR [rsp+40], xmm13|movsd QWORD PTR [rsp+48], xmm14|movsd QWORD PTR [rsp+56], xmm15|movabs rax, 0x123456789a|call rax|movsd xmm8, QWORD PTR [rsp]|movsd xmm9, QWORD PTR [rsp+8]|movsd xmm10, QWORD PTR [rsp+16]|movsd xmm11, QWORD PTR [rsp+24]|movsd xmm12, QWORD PTR [rsp+32]|movsd xmm13, QWORD PTR [rsp+40]|movsd xmm14, QWORD PTR [rsp+48]|movsd xmm15, QWORD PTR [rsp+56]|mov rsp, QWORD PTR [rsp+64]|{load} mov rdi, rax' emit: [asm callC: 16r123456789A].
	self case: 'cmp rdi, QWORD PTR [rip+0xf9]|jne .+7|{disp32} jmp .+0x1f7' emit: [asm picCaseX64: X0 classAt: buffer + 256 target: (asm labelAt: buffer + 512)].
	self case: 'sub DWORD PTR [rip+0xf9], 1' emit: [asm decrement32At: buffer + 256].
	self case: 'cmp rdi, QWORD PTR [rbx+8]' emit: [asm cmp: X0 withWordAt: X20 offset: 8].
	self case: 'mov rdi, QWORD PTR [rsp]' emit: [asm loadReturnAddress: X0].
	self case: 'push rdi|push r14|pop rax|pop r12' emit: [asm push: X0. asm push: X10. asm pop: X9. asm pop: X17].
	self case: 'push rsi|push rdi' emit: [asm stp: X0 with: X1 base: SP preIndex: -16].
	self case: 'pop rdi|pop rsi' emit: [asm ldp: X0 with: X1 base: SP postIndex: 16].
	self case: 'push rdi' emit: [asm stp: X29 with: X0 base: SP preIndex: -16].
	self case: 'pop rdi|lea rsp, [rsp+8]' emit: [asm ldr: X0 base: SP postIndex: 16]
! !
