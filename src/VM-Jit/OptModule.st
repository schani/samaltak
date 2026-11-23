JitCompiler subclass: #OptModule
	instanceVariableNames: 'memory interpreter gc libc feedback'
	classVariableNames: 'BF_DEOPT BF_LIVE BF_LOOP BF_SEALED SI_PERFORMED LOC_CONST LOC_DREG LOC_INT LOC_RAW LOC_REG LOC_SLOT LOC_SMI LOC_SUNK NF_ALLOC NF_BLOCKCALL NF_REPLACE NF_W32 NF_PTRS NF_DEAD NF_EQONLY NF_FOLLOW NF_GUARD NF_HOISTED NF_LAZY NF_INRANGE NF_MUTABLE NF_NOBOUNDS NF_PURE O_BRANCH O_CALL O_CAST O_CHECKINT O_CLASSIS O_CLASSOF O_CLOSURE O_CONST O_OUTERLOAD O_OUTERSTORE O_UNBOXF O_BOXF O_FARITH O_FCMP O_BOTHINT O_FSQRT O_IMOD O_IDIV O_ISHIFT O_IXOR O_NOTINTS O_HOMESLOT O_LOADSLOT O_STORESLOT O_CHARCONV O_MKARRAY O_DEOPT O_EQ O_GOTO O_GUARDCLASS O_GUARDCLOSURE O_GUARDEQ O_GUARDINT O_GUARDLE O_GUARDMUTABLE E_BYTE E_CHAR E_PTR O_IADD O_IAND O_ICMP O_INDEXLOAD O_INDEXSTORE O_SIZE O_IMUL O_IOR O_ISUB O_LOADFIELD O_NE O_NOP O_OUTERSLOT O_PARAM O_PHI O_RETURN O_SEND O_STOREFIELD O_STRCMP O_STRHASH O_LAST OPT_ANA_MAX OPT_DEF_SIZE OPT_MAX_ACTS OPT_MAX_BLOCKS OPT_MAX_EDGES OPT_MAX_NODES OPT_MAX_OPERANDS OPT_MAX_STATES OPT_PCB_MAX R_DBL R_INT R_NONE R_OOP SP_ALLOC SP_CALL SP_ENTRY SP_GUARD SP_LOOP T_ANY T_BOOL T_CHAR T_FLOAT T_NIL T_OBJ T_SMI'
	package: 'VM-Jit'!

OptModule comment: 'I am the abstract class of the optimizing tier''s modules (docs/jit.md, Optimizing tier): I connect them to the VM and to each other, and hold their shared constants (the IR''s opcodes, representations, types, flags; the deoptimization metadata''s location kinds) and the object model''s helpers they need (as VMCoreModule does for the VM''s core).

The IR (OptIR): a control flow graph of blocks of SSA nodes. A node has an opcode (O_*), the representation of its result (R_OOP a tagged object pointer, R_INT an untagged 64-bit integer, R_DBL a raw double, R_NONE none), a static type (T_* and, for T_OBJ, an exact class), operands (a, b, c; variadic ones in the operand array), a frame state if it may deoptimize or is a safepoint, and its register allocation. Frame states (OptState) describe, for deoptimization, every inlined activation (OptAct) from the outermost: its method, pc, receiver, closure and slots.'!

!OptModule class methodsFor: 'declaring'!
declarations
	^#((memory ObjectMemory) (interpreter Interpreter) (gc GarbageCollector) (libc LibC) (feedback JitFeedback))
!
isAbstractModule
	^self == OptModule
!
initialize
	OPT_MAX_NODES := 16384.
	OPT_MAX_BLOCKS := 2048.
	OPT_MAX_EDGES := 8192.
	OPT_MAX_OPERANDS := 131072.
	OPT_MAX_STATES := 16384.
	OPT_MAX_ACTS := 512.
	OPT_DEF_SIZE := 131072.
	OPT_ANA_MAX := 65536.
	OPT_PCB_MAX := 131072.
	"opcodes"
	O_NOP := 0.
	O_CONST := 1.
	O_PARAM := 2.
	O_PHI := 3.
	O_LOADFIELD := 4.
	O_STOREFIELD := 5.
	O_CLASSOF := 6.
	O_EQ := 7.
	O_NE := 8.
	O_IADD := 9.
	O_ISUB := 10.
	O_IMUL := 11.
	O_ICMP := 12.
	O_IAND := 13.
	O_IOR := 14.
	O_GUARDCLASS := 15.
	O_GUARDINT := 16.
	O_SEND := 17.
	O_CALL := 18.
	O_CHECKINT := 19.
	O_CLASSIS := 20.
	O_CAST := 21.
	O_INDEXLOAD := 22.
	O_INDEXSTORE := 23.
	O_SIZE := 24.
	O_CLOSURE := 25.
	O_OUTERLOAD := 26.
	O_OUTERSTORE := 27.
	O_UNBOXF := 28.
	O_BOXF := 29.
	O_FARITH := 30.
	O_FCMP := 31.
	O_BOTHINT := 32.
	O_FSQRT := 33.
	O_IMOD := 34.
	O_IDIV := 35.
	O_ISHIFT := 36.
	O_IXOR := 37.
	O_NOTINTS := 38.
	O_HOMESLOT := 39.
	O_LOADSLOT := 40.
	O_STORESLOT := 41.
	"aux 0: a Character's code point; 1: the Character of a SmallInteger (deoptimizes out of range)"
	O_CHARCONV := 42.
	"0x94: an Array of the operands (args); a safepoint: eden full, the runtime makes it"
	O_MKARRAY := 43.
	"a guard: SmallInteger a (or, without one, the constant aux) is at most SmallInteger b (aux2 1: below it); before a loop for the bounds of its indexed accesses (OptPasses>>boundsOutOf:entry:index:)"
	O_GUARDLE := 44.
	"a guard: closure a's startpc is aux and its outerContext's method the constant b, neither of which ever changes; its result is a (the closure another frame made whose body follows inline: OptBuilder>>inlineForeignClosure:pc:act:rcvSlot:argc:)"
	O_GUARDCLOSURE := 45.
	"where the slots are of the frame that the Context aux levels out of closure a is married to, plus 1 (a SmallInteger to the collector), 0 if it is married to none. Before a loop that sends nothing, for its O_OUTERLOADs and O_OUTERSTOREs (their operand c: OptPasses>>outerSlotsOutOf:entry:)"
	O_OUTERSLOT := 46.
	"a guard: a is the constant b (a global still holds the class the code speculated on: OptBuilder>>global:pc:act:depth:)"
	O_GUARDEQ := 47.
	"a guard: object a is not immutable; before a loop for its stores into a (OptPasses>>mutabilityOutOf:entry:index:)"
	O_GUARDMUTABLE := 48.
	"String>>hash of bytes a (OptBuilder>>stringPrimitive:of:spec:argc:pc:act:rcvSlot:)"
	O_STRHASH := 49.
	O_GOTO := 50.
	O_BRANCH := 51.
	O_RETURN := 52.
	O_DEOPT := 53.
	"compareWith: of bytes a and b: -1, 0 or 1 (NF_GUARD: b checked to be bytes, else deoptimize)"
	O_STRCMP := 54.
	O_LAST := 54.
	"indexed element kinds"
	E_PTR := 0.
	E_BYTE := 1.
	E_CHAR := 2.
	"representations"
	R_NONE := 0.
	R_OOP := 1.
	R_INT := 2.
	R_DBL := 3.
	"types"
	T_ANY := 0.
	T_SMI := 1.
	T_FLOAT := 2.
	T_BOOL := 3.
	T_NIL := 4.
	T_OBJ := 5.
	T_CHAR := 6.
	"node flags"
	NF_PURE := 1.
	NF_DEAD := 2.
	NF_GUARD := 4.
	NF_ALLOC := 8.
	NF_BLOCKCALL := 16.
	"a value in a register whose home slot only interrupt checks need: stored on their slow path, not where it is defined; or a guard whose input already holds it in the slot"
	NF_LAZY := 32.
	"a guard moved before a loop: it deoptimizes to the loop's head"
	NF_HOISTED := 64.
	"a call of replaceFrom:to:with:startingAt: with a fast path that copies bytes, 32-bit words (NF_W32) or pointers (NF_PTRS)"
	NF_REPLACE := 128.
	NF_W32 := 256.
	NF_PTRS := 512.
	"an indexed load or store whose index is within bounds: its loop checked that once (O_GUARDLE)"
	NF_NOBOUNDS := 1024.
	"what it checks is known in range (OptPasses>>ranges): an add or subtract that cannot overflow, the Character of a code point, a store of a byte or of a Character below 256"
	NF_INRANGE := 2048.
	"an indexed store whose object its loop checked once not to be immutable (O_GUARDMUTABLE)"
	NF_MUTABLE := 4096.
	"a compareWith: of bytes (O_STRCMP) whose only use is = 0 or ~= 0: 0 if the bytes are equal, else 1"
	NF_EQONLY := 8192.
	"a field load whose value may be a forwarder (becomeForward:): its target (a Context's receiver)"
	NF_FOLLOW := 16384.
	"block flags"
	BF_SEALED := 1.
	BF_LOOP := 2.
	BF_DEOPT := 4.
	BF_LIVE := 8.
	"a send's info (argc | kind << 8 | special selector << 16): a perform: with a constant selector made it (the selector dropped)"
	SI_PERFORMED := 16r1000000.
	"safepoint kinds"
	SP_GUARD := 1.
	SP_CALL := 2.
	SP_LOOP := 3.
	SP_ENTRY := 4.
	SP_ALLOC := 5.
	"deoptimization metadata: where a value is (low 3 bits)"
	LOC_SLOT := 0.
	LOC_REG := 1.
	LOC_CONST := 2.
	LOC_SMI := 3.
	LOC_INT := 4.
	"a double in a d register (0-31; the register dump's 32 + it)"
	LOC_DREG := 5.
	LOC_SUNK := 6.
	"a double's IEEE bits in a raw slot of the frame"
	LOC_RAW := 7
! !

!OptModule methodsFor: 'object model'!
storeRef: o at: i put: v
	"The generational write barrier, as VMCoreModule's."
	self uint64At: o + 16 + (8 * i) put: v.
	((self isPtr: v) and: [(self isYoung: v) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]])
		ifTrue: [gc remember: o]
!
isInt: o
	^(o bitAnd: 1) ~= 0
!
intVal: o
	^o asInt64 >> 1
!
intOop: v
	^((v asInt64 << 1) bitOr: 1) asUInt64
!
isPtr: o
	^(o bitAnd: 7) = 0
!
header: o
	^self uint64At: o
!
numSlots: o
	^(self header: o) asUInt32
!
formatOf: o
	^(((self header: o) >> H_FMT_SHIFT) bitAnd: H_FMT_MASK) asInt32
!
hashOf: o
	^(((self header: o) >> H_HASH_SHIFT) bitAnd: H_HASH_MASK) asUInt32
!
rawClass: o
	^self uint64At: o + 8
!
slotsOf: o
	^self cCoerce: o + 16 to: 'oop *'
!
bytesOf: o
	^self cCoerce: o + 16 to: 'uint8_t *'
!
loadRef: o at: i
	^self uint64At: o + 16 + (8 * i)
!
isYoung: o
	^(o - gc youngLo) asUInt64 < (gc youngHi - gc youngLo)
!
classOf: o
	"The class of any oop."
	(o bitAnd: 1) ~= 0 ifTrue: [^memory clsSmallint].
	(o bitAnd: 7) = 0 ifTrue: [^self rawClass: o].
	(o bitAnd: 7) = 2 ifTrue: [^memory clsChar].
	(o bitAnd: 7) = 4 ifTrue: [^memory clsSmallfloat].
	^memory nilOop
!
methodBytecodes: m
	^self bytesOf: (self loadRef: m at: CM_BYTECODES)
!
methodSize: m
	^(memory byteSize: (self loadRef: m at: CM_BYTECODES)) asInt32
!
methodLiteral: m at: i
	^self loadRef: (self loadRef: m at: CM_LITERALS) at: i
!
methodPrimitive: m
	| p |
	p := self loadRef: m at: CM_PRIMITIVE.
	^(self isInt: p) ifTrue: [((self intVal: p) bitAnd: CM_PRIM_MASK) asInt32] ifFalse: [0]
! !
