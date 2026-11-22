VMModule subclass: #VMCoreModule
	instanceVariableNames: 'memory gc interpreter scheduler imageFile primitives platform vmMain c4 jit libc libm posix'
	classVariableNames: 'K_CONST K_JIT K_LEAF K_PRIM K_QUICK K_SETTER PS_FAIL PS_NONE PS_OK PS_RESEND PS_SWITCHED'
	package: 'VM-Core'!

VMCoreModule comment: 'I am the abstract class of the VM core''s modules: I connect them to each other and to the C libraries, and hold the object model''s inline helpers (tagging, headers, slot access with the GC''s load and store barriers) that every module uses.'!

!VMCoreModule class methodsFor: 'declaring'!
declarations
	^#((memory ObjectMemory) (gc GarbageCollector) (interpreter Interpreter) (scheduler Scheduler) (imageFile ImageFile) (primitives PrimitiveTable) (platform PlatformInterface) (vmMain VMMain) (c4 C4Heap) (jit JitRuntime) (libc LibC) (libm LibM) (posix Posix))
!
isAbstractModule
	^self == VMCoreModule
!
initialize
	"How a primitive ended (Interpreter's primStatus)."
	PS_NONE := 0.
	PS_OK := 1.
	PS_FAIL := 2.
	PS_SWITCHED := 3.
	PS_RESEND := 4.
	"What a method cache entry (CacheEntry kind) holds: bits."
	K_PRIM := 1.
	K_QUICK := 2.
	K_SETTER := 4.
	K_CONST := 8.
	K_LEAF := 16.
	K_JIT := 64
! !

!VMCoreModule methodsFor: 'immediates'!
isInt: o
	^(o bitAnd: 1) ~= 0
!
intVal: o
	^o asInt64 >> 1
!
intOop: v
	^((v asInt64 << 1) bitOr: 1) asUInt64
!
intFits: v
	^v >= VM_INT_MIN and: [v <= VM_INT_MAX]
!
isChar: o
	^(o bitAnd: 7) = 2
!
charVal: o
	^(o >> 3) asUInt32
!
charOop: codePoint
	^(codePoint asUInt64 << 3) bitOr: 2
!
isPtr: o
	^(o bitAnd: 7) = 0
!
isSmallFloat: o
	^(o bitAnd: 7) = 4
!
bool: aBoolean
	"The image's true or false."
	^aBoolean ifTrue: [memory trueOop] ifFalse: [memory falseOop]
! !

!VMCoreModule methodsFor: 'objects'!
canonicalOop: o
	"Resolve identity, not storage. Publish raw oops from root slots."
	(self unlikely: (vmMain c4Enabled and: [c4 hasForwarding])) ifTrue: [^c4 canonical: o].
	^o
!
objectAddress: o
	"Import/bootstrap and the legacy heap use address-as-oop."
	(self unlikely: (vmMain c4Enabled and: [vmMain c4Moving or: [c4 hasForwarding]]))
		ifTrue: [^c4 address: o].
	^o
!
header: o
	^self uint64At: (self objectAddress: o)
!
header: o put: h
	self uint64At: (self objectAddress: o) put: h
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
isImmutable: o
	^((self header: o) bitAnd: H_IMMUTABLE) ~= 0
!
rawClass: o
	^self uint64At: (self objectAddress: o) + 8
!
rawClass: o put: c
	vmMain c4Enabled ifTrue: [
		c4 storeClass: o value: c.
		^self].
	self uint64At: o + 8 put: c
!
objBytes: o
	^16 + (8 * (self numSlots: o) asUInt64)
!
fmtHasPointers: f
	^f >= 1 and: [f <= 4]
!
bodyAddress: o
	"Resolve for a scalar access only. Escaping interior views must use pinnedBodyAddress:."
	^(self objectAddress: o) + 16
!
pinnedBodyAddress: o
	| owner |
	(self unlikely: (vmMain c4Moving and: [c4 movable: o])) ifTrue: [self fatal: 'raw body view of a movable object'].
	owner := self canonicalOop: o.
	(self unlikely: vmMain c4Enabled) ifTrue: [c4 notePinnedView: owner].
	^owner + 16
!
slotsOf: o
	^self cCoerce: (self pinnedBodyAddress: o) to: 'oop *'
!
bytesOf: o
	^self cCoerce: (self pinnedBodyAddress: o) to: 'uint8_t *'
!
words32Of: o
	^self cCoerce: (self pinnedBodyAddress: o) to: 'uint32_t *'
!
isYoung: o
	^(o - gc youngLo) asUInt64 < (gc youngHi - gc youngLo)
!
contextPrefix: o
	"C4 Context slots past this prefix can contain reclaimed addresses."
	| sp slots |
	slots := self numSlots: o.
	slots < CTX_FIXED ifTrue: [^slots].
	sp := (self slotsOf: o) at: CTX_STACKP.
	((self isInt: sp) and: [(self intVal: sp) asUInt64 <= (slots - CTX_FIXED) asUInt64])
		ifTrue: [^(CTX_FIXED + (self intVal: sp)) asUInt32].
	^CTX_FIXED asUInt32
!
loadRef: o at: i
	"The scalar heap body reference load."
	((self unlikely: vmMain c4Enabled) and: [i >= CTX_FIXED or: [c4 hasForwarding or: [(self formatOf: o) = F_WEAK]]])
		ifTrue: [^memory c4LoadRef: o at: i asUInt32].
	^self uint64At: (self bodyAddress: o) + (8 * i)
!
storeRef: o at: i put: v
	"The scalar heap write barrier. For bulk copies see ObjectMemory's copyRefs: methods."
	(self unlikely: vmMain c4Enabled) ifTrue: [
		(self c4CodeStoreRejected: o at: i put: v) ifTrue: [self fatal: 'C4 cannot replace compiled method storage'].
		(i = CTX_STACKP and: [(self rawClass: o) = memory clsContext])
			ifTrue: [memory c4StoreContextStackp: o value: v]
			ifFalse: [c4 storeRef: o at: i asUInt32 put: v].
		^self].
	(self slotsOf: o) at: i put: v.
	((self isPtr: v) and: [(self isYoung: v) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]])
		ifTrue: [gc remember: o]
!
c4CodeStoreRejected: o at: i put: v
	"Even with frames above it, the heap base owns the code used to resume it."
	(i = CTX_METHOD and: [o = interpreter activeCtx and: [(self rawClass: o) = memory clsContext]])
		ifTrue: [^v ~= (self loadRef: o at: i)].
	^(i = CM_LITERALS or: [i = CM_BYTECODES or: [i = SO_COMPILEDMETHOD]]) and: [
		memory c4CannotReplaceCodeSlot: o at: i asUInt32 put: v]
!
ptr: anAddress
	"An address as a void * (for the C library)."
	^self cCoerce: anAddress to: 'void *'
! !

!VMCoreModule methodsFor: 'errors'!
fatal: aFormat
	"Print samaltak: fatal: and the message, the Smalltalk stack, and exit."
	interpreter fatalBegin.
	libc fprintf: libc stderr format: aFormat.
	interpreter fatalEnd
!
fatal: aFormat with: a
	interpreter fatalBegin.
	libc fprintf: libc stderr format: aFormat with: a.
	interpreter fatalEnd
!
fatal: aFormat with: a with: b
	interpreter fatalBegin.
	libc fprintf: libc stderr format: aFormat with: a with: b.
	interpreter fatalEnd
! !
