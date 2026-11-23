VMModule subclass: #VMCoreModule
	instanceVariableNames: 'memory gc interpreter scheduler imageFile primitives platform vmMain jit libc libm posix'
	classVariableNames: 'K_CONST K_JIT K_LEAF K_PRIM K_QUICK K_SETTER PS_FAIL PS_NONE PS_OK PS_RESEND PS_SWITCHED'
	package: 'VM-Core'!

VMCoreModule comment: 'I am the abstract class of the VM core''s modules: I connect them to each other and to the C libraries, and hold the object model''s inline helpers (tagging, headers, slot access with the GC''s load and store barriers) that every module uses.'!

!VMCoreModule class methodsFor: 'declaring'!
declarations
	^#((memory ObjectMemory) (gc GarbageCollector) (interpreter Interpreter) (scheduler Scheduler) (imageFile ImageFile) (primitives PrimitiveTable) (platform PlatformInterface) (vmMain VMMain) (jit JitRuntime) (libc LibC) (libm LibM) (posix Posix))
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
header: o
	^self uint64At: o
!
header: o put: h
	self uint64At: o put: h
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
	^self uint64At: o + 8
!
rawClass: o put: c
	self uint64At: o + 8 put: c
!
isForwarder: o
	"o was forwarded by becomeForward: (outside a collection only forwarders have H_FORWARDED set)."
	^(self isPtr: o) and: [((self header: o) bitAnd: H_FORWARDED) ~= 0]
!
follow: o
	"The object o forwards to, o if it is not a forwarder."
	| p |
	p := o.
	[self isForwarder: p] whileTrue: [p := (self rawClass: p) bitClear: FWD_TAG].
	^p
!
objBytes: o
	^16 + (8 * (self numSlots: o) asUInt64)
!
fmtHasPointers: f
	^f >= 1 and: [f <= 4]
!
slotsOf: o
	"The body of o as oops."
	^self cCoerce: o + 16 to: 'oop *'
!
bytesOf: o
	^self cCoerce: o + 16 to: 'uint8_t *'
!
words32Of: o
	^self cCoerce: o + 16 to: 'uint32_t *'
!
isYoung: o
	^(o - gc youngLo) asUInt64 < (gc youngHi - gc youngLo)
!
loadRef: o at: i
	"Every load of an object pointer from the heap goes through here (the GC's load barrier, see docs/design.md)."
	^self uint64At: o + 16 + (8 * i)
!
storeRef: o at: i put: v
	"Every store of an object pointer into the heap goes through here: the generational write barrier."
	self uint64At: o + 16 + (8 * i) put: v.
	((self isPtr: v) and: [(self isYoung: v) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]])
		ifTrue: [gc remember: o]
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
