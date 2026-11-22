VMCoreModule subclass: #ObjectMemory
	instanceVariableNames: 'nilOop trueOop falseOop specialsOop clsSmallint clsChar clsSmallfloat clsBoxedfloat clsArray clsContext clsBlock clsPoint clsBytestring clsBytearray clsMessage clsCompiledmethod hashBox rootStack rootCount largeObjectBytes sampleMark wordHash'
	classVariableNames: 'MAX_ROOTS'
	package: 'VM-Core'!

ObjectMemory comment: 'Object memory: special objects, allocation (bump allocation in eden, large objects directly in old space, allocation sampling at the limit check), object access, floats, integers and strings. The spaces and the collector are the GarbageCollector''s.'!

!ObjectMemory class methodsFor: 'declaring'!
declarations
	^#((nilOop oop) (trueOop oop) (falseOop oop) (specialsOop oop)
		(clsSmallint oop) (clsChar oop) (clsSmallfloat oop) (clsBoxedfloat oop) (clsArray oop) (clsContext oop)
		(clsBlock oop) (clsPoint oop) (clsBytestring oop) (clsBytearray oop) (clsMessage oop) (clsCompiledmethod oop)
		(hashBox 'uint64_t[1]' #(16r5A4D414C54414B))
		(rootStack 'oop *[MAX_ROOTS]') (rootCount int32_t)
		(largeObjectBytes size_t 262144)
		(sampleMark uint64_t)
		(wordHash bool true))
!
initialize
	MAX_ROOTS := 1024
! !

!ObjectMemory methodsFor: 'accessing'!
nilOop
	^nilOop
!
nilOop: o
	nilOop := o
!
trueOop
	^trueOop
!
falseOop
	^falseOop
!
specialsOop
	^specialsOop
!
specialsOop: o
	specialsOop := o
!
clsSmallint
	^clsSmallint
!
clsChar
	^clsChar
!
clsSmallfloat
	^clsSmallfloat
!
clsBoxedfloat
	^clsBoxedfloat
!
clsArray
	^clsArray
!
clsContext
	^clsContext
!
clsBlock
	^clsBlock
!
clsPoint
	^clsPoint
!
clsBytestring
	^clsBytestring
!
clsBytearray
	^clsBytearray
!
clsCompiledmethod
	^clsCompiledmethod
!
clsMessage
	^clsMessage
!
hashSeed
	^hashBox at: 0
!
hashSeed: anInteger
	hashBox at: 0 put: anInteger
!
wordHash
	"String>>hash of this image: 8 bytes a word (true), or FNV-1a over the code points, as images saved before it have their hashed collections (ImageHeader's stringHash)."
	^wordHash
!
wordHash: aBoolean
	wordHash := aBoolean
!
hashBoxAddress
	"Where the identity hash generator's state is (machine code allocates too)."
	^self cCoerce: hashBox to: 'uint64_t'
!
rootCount
	^rootCount
!
rootAt: i
	^rootStack at: i
! !

!ObjectMemory methodsFor: 'special objects'!
refreshSpecials
	<function>
	| s |
	s := self slotsOf: specialsOop.
	nilOop := s at: SO_NIL.
	falseOop := s at: SO_FALSE.
	trueOop := s at: SO_TRUE.
	clsSmallint := s at: SO_SMALLINTEGER.
	clsChar := s at: SO_CHARACTER.
	clsSmallfloat := s at: SO_SMALLFLOAT.
	clsBoxedfloat := s at: SO_BOXEDFLOAT.
	clsArray := s at: SO_ARRAY.
	clsContext := s at: SO_CONTEXT.
	clsBlock := s at: SO_BLOCKCLOSURE.
	clsPoint := s at: SO_POINT.
	clsBytestring := s at: SO_BYTESTRING.
	clsBytearray := s at: SO_BYTEARRAY.
	clsMessage := s at: SO_MESSAGE.
	clsCompiledmethod := s at: SO_COMPILEDMETHOD
!
special: index
	"The special objects array, 0-based."
	<function>
	(index < 0 or: [index asUInt32 >= (self numSlots: specialsOop)]) ifTrue: [^nilOop].
	^self loadRef: specialsOop at: index
!
pushRoot: p
	<function>
	rootCount >= MAX_ROOTS ifTrue: [self fatal: 'root stack overflow'].
	rootStack at: rootCount put: p.
	rootCount := rootCount + 1
!
popRoot
	<function>
	rootCount := rootCount - 1
! !

!ObjectMemory methodsFor: 'floats'!
rotl1: x
	^(x << 1) asUInt64 bitOr: x >> 63
!
rotr1: x
	^(x >> 1) bitOr: (x << 63) asUInt64
!
isFloat: o
	<function>
	^(o bitAnd: 7) = 4 or: [(self isPtr: o) and: [(self rawClass: o) = clsBoxedfloat]]
!
floatVal: o
	"o must be a Float."
	<function>
	| b r |
	(o bitAnd: 7) = 4
		ifTrue: [
			r := o >> 3.
			b := r <= 1 ifTrue: [r << 63] ifFalse: [self rotr1: r + (896 << 53)]]
		ifFalse: [b := (self slotsOf: o) at: 0].
	^self doubleFromBits: b
!
floatOop: d
	"A SmallFloat64 if d has one, else a new BoxedFloat64 (may allocate)."
	<function>
	| b e f |
	b := self bitsOfDouble: d.
	(b << 1) asUInt64 = 0 ifTrue: [^((b >> 63) << 3) bitOr: 4].
	e := ((b >> 52) bitAnd: 16r7FF) asUInt32.
	(e > 896 and: [e < 1151]) ifTrue: [^(((self rotl1: b) - (896 << 53)) << 3) bitOr: 4].
	f := self allocObj: clsBoxedfloat format: F_W64 slots: 1.
	(self slotsOf: f) at: 0 put: b.
	^f
! !

!ObjectMemory methodsFor: 'object access'!
classOf: o
	<function>
	(o bitAnd: 1) ~= 0 ifTrue: [^clsSmallint].
	^(o bitAnd: 7) caseOf: {
		[0] -> [self rawClass: o].
		[2] -> [clsChar].
		[4] -> [clsSmallfloat]}
		otherwise: [nilOop]
!
byteSize: o
	"Element count of a byte object (formats 16-23); body bytes otherwise."
	<function>
	<returns: 'size_t'>
	| f |
	f := self formatOf: o.
	f >= F_BYTES ifTrue: [^((self numSlots: o) * 8) - (f - F_BYTES)].
	(f >= F_W32 and: [f < F_BYTES]) ifTrue: [^(self word32Size: o) * 4].
	^(self numSlots: o) * 8
!
word32Size: o
	"Element count of a 32-bit object (formats 10-11)."
	<function>
	<returns: 'size_t'>
	| f |
	f := self formatOf: o.
	(f = 10 or: [f = 11]) ifTrue: [^((self numSlots: o) * 2) - (f - F_W32)].
	^0
!
fixedFields: o
	"Fixed (non-indexable) pointer fields."
	<function>
	| f |
	f := self formatOf: o.
	f = F_FIXED ifTrue: [^self numSlots: o].
	vmMain c4Enabled ifTrue: [
		f = F_WEAK ifTrue: [^c4 weakStart: o].
		(self rawClass: o) = clsContext ifTrue: [^CTX_FIXED asUInt32]].
	(f = F_FIXVAR or: [f = F_WEAK]) ifTrue: [
		^((self intVal: (self loadRef: (self rawClass: o) at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK) asUInt32].
	^0
!
indexableSize: o
	<function>
	<returns: 'size_t'>
	| f |
	(self isPtr: o) ifFalse: [^0].
	f := self formatOf: o.
	f = F_VAR ifTrue: [^self numSlots: o].
	(f = F_FIXVAR or: [f = F_WEAK]) ifTrue: [^(self numSlots: o) - (self fixedFields: o)].
	f = F_W64 ifTrue: [^self numSlots: o].
	(f = 10 or: [f = 11]) ifTrue: [^self word32Size: o].
	f >= F_BYTES ifTrue: [^self byteSize: o].
	^0
! !

!ObjectMemory methodsFor: 'C4 references'!
c4FixedFieldsFor: cls spec: expected slots: n
	"For import and allocation: class + fixed prefix are strong. UINT32_MAX
	is invalid (larger than any object this VM fits in its C4 arena)."
	<function>
	<var: #n type: 'uint32_t'>
	<returns: 'uint32_t'>
	| fo spec fixed f |
	((self isPtr: cls) and: [cls ~= 0 and: [(self numSlots: cls) > BEH_FORMAT]]) ifFalse: [^16rFFFFFFFF].
	f := self formatOf: cls.
	(f >= F_FIXED and: [f <= F_FIXVAR]) ifFalse: [^16rFFFFFFFF].
	fo := self loadRef: cls at: BEH_FORMAT.
	(self isInt: fo) ifFalse: [^16rFFFFFFFF].
	spec := (self intVal: fo) >> CLS_SPEC_SHIFT.
	fixed := ((self intVal: fo) bitAnd: CLS_INSTSIZE_MASK) asUInt32.
	(fixed > n or: [spec ~= expected]) ifTrue: [^16rFFFFFFFF].
	^fixed
!
c4LoadRef: o at: i
	<function>
	<var: #o type: 'oop'>
	<var: #i type: 'uint32_t'>
	(self formatOf: o) = F_WEAK ifTrue: [^c4 loadRef: o at: i].
	(i >= CTX_FIXED and: [(self rawClass: o) = clsContext and: [i >= (self contextPrefix: o)]]) ifTrue: [^nilOop].
	^self uint64At: (self bodyAddress: o) + (8 * i asUInt64)
!
c4CannotReplaceCodeSlot: o at: i put: v
	"Interpreter activations borrow interior pointers into method storage."
	<function>
	<var: #o type: 'oop'>
	<var: #i type: 'uint32_t'>
	<var: #v type: 'oop'>
	i = SO_COMPILEDMETHOD ifTrue: [^o = specialsOop and: [v ~= clsCompiledmethod]].
	(self rawClass: o) = clsCompiledmethod ifFalse: [^false].
	(c4 movable: v) ifTrue: [^true].
	^((self slotsOf: o) at: i) ~= nilOop and: [((self slotsOf: o) at: i) ~= v]
!
c4StoreContextStackp: o value: v
	"Smalltalk's Context constructor and push may extend the live range. Do not re-expose stale slots. VM-internal stack writes publish separately."
	<function>
	<var: #o type: 'oop'>
	<var: #v type: 'oop'>
	(self c4TryStoreContextStackp: o value: v)
		ifFalse: [self fatal: 'invalid or unsupported C4 Context stack pointer'].
!
c4TryStoreContextStackp: o value: v
	"Initialize newly live slots before publishing stackp; a shrink does not
	read or clear the tail. Bound the work of a single reflective store."
	<function>
	<var: #o type: 'oop'>
	<var: #v type: 'oop'>
	| old end slots |
	slots := self numSlots: o.
	(slots >= CTX_FIXED and: [(self isInt: v) and: [(self intVal: v) asUInt64 <= (slots - CTX_FIXED) asUInt64]])
		ifFalse: [^false].
	end := CTX_FIXED + (self intVal: v).
	old := self contextPrefix: o.
	end - old asInt64 > 256 ifTrue: [^false].
	old asInt64 to: end - 1 do: [:i | c4 storeRef: o at: i asUInt32 put: nilOop].
	c4 storeRef: o at: CTX_STACKP put: v.
	^true
! !

!ObjectMemory methodsFor: 'bulk reference stores'!
copyC4Context: dst from: src
	"Clone into a fresh Context; only the live prefix is meaningful."
	<function>
	<var: #dst type: 'oop'>
	<var: #src type: 'oop'>
	0 to: (self contextPrefix: src) asInt64 - 1 do: [:i |
		c4 storeRef: dst at: i asUInt32 put: (self loadRef: src at: i)]
!
copyRefs: dst at: di from: src at: si count: n
	"Copy validated pointer slots between heap objects (including weak slots). Indices are zero-based; ranges may overlap. Does not collect."
	<function>
	<var: #dst type: 'oop'>
	<var: #di type: 'size_t'>
	<var: #src type: 'oop'>
	<var: #si type: 'size_t'>
	<var: #n type: 'size_t'>
	| i |
	vmMain c4Enabled ifTrue: [
		(dst = src and: [di > si and: [di - si < n]])
			ifTrue: [
				i := n.
				[i > 0] whileTrue: [
					i := i - 1.
					self storeRef: dst at: di + i put: (self loadRef: src at: si + i)]]
			ifFalse: [
				0 to: n asInt64 - 1 do: [:j |
					self storeRef: dst at: di + j put: (self loadRef: src at: si + j)]].
		^self].
	libc memmove: (self slotsOf: dst) + di from: (self slotsOf: src) + si size: n * 8.
	gc rememberIfOld: dst
!
copyRefs: dst at: di fromBuffer: src count: n
	"Copy from a non-overlapping buffer of oops, not heap slots or raw frame words. Does not collect. Remember old destinations even for an empty copy: Context flushes batch their fixed-field writes with this copy."
	<function>
	<var: #dst type: 'oop'>
	<var: #di type: 'size_t'>
	<var: #src type: 'oop *'>
	<var: #n type: 'size_t'>
	vmMain c4Enabled ifTrue: [
		0 to: n asInt64 - 1 do: [:i | self storeRef: dst at: di + i put: (src at: i)].
		^self].
	libc memcpy: (self slotsOf: dst) + di from: src size: n * 8.
	gc rememberIfOld: dst
! !

!ObjectMemory methodsFor: 'allocation'!
nextHash
	<function>
	| h s |
	s := ((self hashSeed * 6364136223846793005) + 1442695040888963407) asUInt64.
	self hashSeed: s.
	h := ((s >> 40) bitAnd: H_HASH_MASK) asUInt32.
	^h = 0 ifTrue: [1] ifFalse: [h]
!
initObjectAt: p class: cls format: fmt slots: n
	"Initialize private storage. C4 does not see the object until publish."
	| s nl |
	self initHeaderAt: p class: cls format: fmt slots: n.
	(self fmtHasPointers: fmt)
		ifTrue: [
			s := self cCoerce: p + 16 to: 'oop *'.
			nl := nilOop.
			0 to: n asInt64 - 1 do: [:i | s at: i put: nl]]
		ifFalse: [libc memset: (self ptr: p + 16) value: 0 size: n asUInt64 * 8]
!
oldOverBudget
	^gc oldTop - gc oldLo > gc oldBudget
!
resetAllocLimit
	"Fast-path limit: eden's end or the next allocation sample; eden_top while old space is over its budget (after the scavenge primitive), so that the next allocation collects."
	<function>
	vmMain c4Enabled ifTrue: [^self].
	gc allocLimit: gc edenHi.
	sampleMark := gc edenTop.
	(scheduler allocSampleInterval > 0 and: [gc edenTop + scheduler allocSampleCountdown < gc edenHi]) ifTrue: [
		gc allocLimit: gc edenTop + scheduler allocSampleCountdown].
	self oldOverBudget ifTrue: [gc allocLimit: gc edenTop]
!
allocSlow: cls bytes: bytes
	"Slow path: account allocation sampling, collect if eden is full."
	<function>
	| p |
	scheduler allocSampleInterval > 0 ifTrue: [
		scheduler allocSampleCountdown: scheduler allocSampleCountdown - (gc edenTop - sampleMark) asInt64.
		sampleMark := gc edenTop.
		scheduler allocSampleCountdown <= bytes asInt64 ifTrue: [
			scheduler allocSampleCountdown: scheduler allocSampleInterval + bytes asInt64.
			scheduler allocSampleHit: cls value bytes: bytes]].
	(gc edenTop + bytes > gc edenHi or: [self oldOverBudget]) ifTrue: [
		self pushRoot: cls.
		gc collectGarbage: bytes.
		self popRoot].
	p := gc edenTop.
	gc edenTop: p + bytes.
	scheduler allocSampleInterval > 0 ifTrue: [scheduler allocSampleCountdown: scheduler allocSampleCountdown - bytes asInt64].
	self resetAllocLimit.
	^p
!
allocC4Try: cls format: fmt slots: n
	"No cycle start, root enumeration or wait on allocation pressure."
	<function>
	<var: #n type: 'uint32_t'>
	| o addr bytes refs first plain |
	refs := (self fmtHasPointers: fmt) ifTrue: [n] ifFalse: [0].
	first := 16rFFFFFFFF asUInt32. "C4_NO_WEAK"
	cls = clsContext ifTrue: [
		(fmt = F_FIXVAR and: [(self c4FixedFieldsFor: cls spec: F_FIXVAR slots: n) = CTX_FIXED])
			ifFalse: [^0]].
	fmt = F_WEAK ifTrue: [
		first := self c4FixedFieldsFor: cls spec: F_WEAK slots: n.
		first = 16rFFFFFFFF ifTrue: [^0]].
	bytes := 16 + (8 * n asUInt64).
	addr := self local: 'uint64_t'.
	plain := (vmMain c4Moving and: [cls = clsPoint and: [fmt = F_FIXED and: [n = 2]]]) ifTrue: [1] ifFalse: [0].
	o := c4 reserve: bytes plain: plain into: addr.
	o = 0 ifTrue: [^0].
	self initObjectAt: addr value class: cls format: fmt slots: n.
	cls = clsContext ifTrue: [
		self uint64At: addr value + 16 + (8 * CTX_STACKP) put: (self intOop: 0)].
	c4 publish: o refs: refs weakStart: first asUInt32.
	gc statAllocated: gc statAllocated + bytes.
	scheduler allocSampleInterval > 0 ifTrue: [
		bytes > largeObjectBytes
			ifTrue: [scheduler allocSampleHit: cls bytes: bytes]
			ifFalse: [
				scheduler allocSampleCountdown <= bytes asInt64
					ifTrue: [
						scheduler allocSampleCountdown: scheduler allocSampleInterval.
						scheduler allocSampleHit: cls bytes: bytes]
					ifFalse: [scheduler allocSampleCountdown: scheduler allocSampleCountdown - bytes asInt64]]].
	^o
!
allocC4: cls format: fmt slots: n
	<function>
	| p |
	p := self allocC4Try: cls format: fmt slots: n.
	p = 0 ifTrue: [self fatal: 'C4 out of memory allocating %llu bytes' with: 16 + (8 * n asUInt64)].
	^p
!
allocOldTry: cls format: fmt slots: n
	<function>
	| p clsRoot |
	vmMain c4Enabled ifTrue: [^self allocC4Try: cls format: fmt slots: n].
	clsRoot := self local: 'oop'.
	clsRoot value: cls.
	self pushRoot: clsRoot.
	p := gc oldAllocTry: 16 + (8 * n asUInt64).
	self popRoot.
	p = 0 ifTrue: [^0].
	self initObjectAt: p class: clsRoot value format: fmt slots: n.
	gc statAllocated: gc statAllocated + 16 + (8 * n asUInt64).
	((self isPtr: clsRoot value) and: [self isYoung: clsRoot value]) ifTrue: [gc remember: p].
	^p
!
allocOld: cls format: fmt slots: n
	"Directly in old space."
	<function>
	| o |
	vmMain c4Enabled ifTrue: [^self allocC4: cls format: fmt slots: n].
	o := self allocOldTry: cls format: fmt slots: n.
	o = 0 ifTrue: [self fatal: 'out of memory allocating %llu bytes' with: 16 + (8 * n asUInt64)].
	^o
!
allocObj: cls format: fmt slots: n
	"Pointer formats nil-filled, others zeroed. May GC."
	<function>
	| bytes p clsRoot |
	vmMain c4Enabled ifTrue: [^self allocC4: cls format: fmt slots: n].
	bytes := 16 + (8 * n asUInt64).
	bytes > largeObjectBytes ifTrue: [
		scheduler allocSampleInterval > 0 ifTrue: [scheduler allocSampleHit: cls bytes: bytes].
		^self allocOld: cls format: fmt slots: n].
	p := gc edenTop.
	p + bytes > gc allocLimit
		ifTrue: [
			clsRoot := self local: 'oop'.
			clsRoot value: cls.
			p := self allocSlow: clsRoot bytes: bytes.
			self initObjectAt: p class: clsRoot value format: fmt slots: n]
		ifFalse: [
			gc edenTop: p + bytes.
			self initObjectAt: p class: cls format: fmt slots: n].
	^p
!
initHeaderAt: p class: cls format: fmt slots: n
	self uint64At: p put: ((n asUInt64 bitOr: fmt asUInt64 << H_FMT_SHIFT) bitOr: self nextHash asUInt64 << H_HASH_SHIFT).
	self uint64At: p + 8 put: cls
!
allocUnfilledTry: cls format: fmt slots: n
	"allocObjTry: of an object without pointers (fmt) whose slots the caller writes, every one, before anything else runs: in eden its header and class only, not zeroed (the collector never reads such slots); large ones as allocObjTry: makes them. 0 if it can never fit in the heap."
	<function>
	| bytes p clsRoot |
	n > 16rFFFFFFFF ifTrue: [^0].
	bytes := 16 + (8 * n).
	bytes > largeObjectBytes ifTrue: [^self allocObjTry: cls format: fmt slots: n].
	p := gc edenTop.
	p + bytes > gc allocLimit
		ifTrue: [
			clsRoot := self local: 'oop'.
			clsRoot value: cls.
			p := self allocSlow: clsRoot bytes: bytes.
			self initHeaderAt: p class: clsRoot value format: fmt slots: n asUInt32]
		ifFalse: [
			gc edenTop: p + bytes.
			self initHeaderAt: p class: cls format: fmt slots: n asUInt32].
	^p
!
allocObjTry: cls format: fmt slots: n
	"alloc_obj, 0 if it can never fit in the heap."
	<function>
	| bytes |
	n > 16rFFFFFFFF ifTrue: [^0].
	vmMain c4Enabled ifTrue: [^self allocC4Try: cls format: fmt slots: n asUInt32].
	bytes := 16 + (8 * n).
	bytes <= largeObjectBytes ifTrue: [^self allocObj: cls format: fmt slots: n asUInt32].
	scheduler allocSampleInterval > 0 ifTrue: [scheduler allocSampleHit: cls bytes: bytes].
	^self allocOldTry: cls format: fmt slots: n asUInt32
!
allocContext: n
	"Indexable slots; may GC."
	<function>
	^self allocObj: clsContext format: F_FIXVAR slots: CTX_FIXED + n
!
allocSlots: cls count: n
	"n = indexable slot count (0 for non-indexable classes); fields nil."
	<export>
	<var: #cls type: 'oop'>
	<var: #n type: 'uint32_t'>
	| err o |
	err := self local: 'int'.
	o := self instantiate: cls size: n asUInt64 error: err.
	^err value ~= 0 ifTrue: [nilOop] ifFalse: [o]
!
allocBytes: cls count: n
	"n bytes, zeroed."
	<function>
	^self allocObj: cls format: F_BYTES + ((8 - (n rem: 8)) rem: 8) asInt32 slots: (n + 7 quo: 8) asUInt32
!
allocWords32: cls count: n
	"n 32-bit units, zeroed."
	<function>
	^self allocObj: cls format: F_W32 + (n bitAnd: 1) asInt32 slots: (n + 1 quo: 2) asUInt32
!
instantiate: cls size: n error: err
	"basicNew: semantics; *err 0, PRIM_ERR_NO_MEMORY or -1."
	<function>
	| fo spec isize fmt nslots o |
	err value: -1.
	((self isPtr: cls) not or: [(self numSlots: cls) <= BEH_FORMAT]) ifTrue: [^nilOop].
	fo := self loadRef: cls at: BEH_FORMAT.
	(self isInt: fo) ifFalse: [^nilOop].
	spec := (self intVal: fo) >> CLS_SPEC_SHIFT.
	isize := (self intVal: fo) bitAnd: CLS_INSTSIZE_MASK.
	spec <= 1
		ifTrue: [
			n ~= 0 ifTrue: [^nilOop].
			fmt := isize ~= 0 ifTrue: [F_FIXED] ifFalse: [F_EMPTY].
			nslots := isize asUInt64]
		ifFalse: [
			(spec >= 2 and: [spec <= 4])
				ifTrue: [
					fmt := (isize ~= 0 and: [spec = 2]) ifTrue: [F_FIXVAR] ifFalse: [spec asInt32].
					nslots := isize asUInt64 + n]
				ifFalse: [
					spec = 9
						ifTrue: [fmt := F_W64. nslots := n]
						ifFalse: [
							spec = 10
								ifTrue: [
									fmt := F_W32 + (n bitAnd: 1) asInt32.
									nslots := (n quo: 2) + (n bitAnd: 1)]
								ifFalse: [
									spec = 16 ifFalse: [^nilOop].
									fmt := F_BYTES + ((8 - (n rem: 8)) rem: 8) asInt32.
									nslots := (n quo: 8) + ((n rem: 8) ~= 0 ifTrue: [1] ifFalse: [0])]]]].
	o := n > 16r7FFFFFF0 ifTrue: [0] ifFalse: [self allocObjTry: cls format: fmt slots: nslots].
	err value: (o ~= 0 ifTrue: [0] ifFalse: [PRIM_ERR_NO_MEMORY]).
	^o ~= 0 ifTrue: [o] ifFalse: [nilOop]
! !

!ObjectMemory methodsFor: 'integers'!
largeIntFrom: v negative: negative
	<function>
	| n t o |
	n := 0.
	t := v.
	[t ~= 0] whileTrue: [
		n := n + 1.
		t := t >> 8].
	n = 0 ifTrue: [n := 1].
	o := self allocBytes: (self special: (negative ifTrue: [SO_LARGENEG] ifFalse: [SO_LARGEPOS])) count: n asUInt64.
	0 to: n - 1 do: [:i | (self bytesOf: o) at: i put: ((v >> (8 * i)) bitAnd: 255) asUInt8].
	^o
!
int64Oop: v
	"SmallInteger or LargeInteger (may allocate)."
	<export>
	<var: #v type: 'int64_t'>
	(self intFits: v) ifTrue: [^self intOop: v].
	^v < 0
		ifTrue: [self largeIntFrom: (0 - v) asUInt64 negative: true]
		ifFalse: [self largeIntFrom: v asUInt64 negative: false]
!
largeMagnitude: o into: mag negative: neg
	<function>
	| c n b m |
	((self isPtr: o) not or: [(self formatOf: o) < F_BYTES]) ifTrue: [^false].
	c := self rawClass: o.
	c = (self special: SO_LARGEPOS)
		ifTrue: [neg value: false]
		ifFalse: [
			c = (self special: SO_LARGENEG) ifFalse: [^false].
			neg value: true].
	n := self byteSize: o.
	b := self bytesOf: o.
	[n > 0 and: [(b at: n - 1) = 0]] whileTrue: [n := n - 1].
	n > 8 ifTrue: [^false].
	m := 0 asUInt64.
	0 to: n asInt64 - 1 do: [:i | m := m bitOr: (b at: i) asUInt64 << (8 * i)].
	mag value: m.
	^true
!
u64Of: o into: out
	"Non-negative Integer fitting 64 bits."
	<function>
	| neg |
	(self isInt: o) ifTrue: [
		(self intVal: o) < 0 ifTrue: [^false].
		out value: (self intVal: o) asUInt64.
		^true].
	neg := self local: 'bool'.
	^(self largeMagnitude: o into: out negative: neg) and: [neg value not]
!
int64Of: o into: out
	"SmallInteger or LargeInteger fitting int64."
	<export>
	<var: #o type: 'oop'>
	<var: #out type: 'int64_t *'>
	| m neg |
	(self isInt: o) ifTrue: [
		out value: (self intVal: o).
		^true].
	m := self local: 'uint64_t'.
	neg := self local: 'bool'.
	(self largeMagnitude: o into: m negative: neg) ifFalse: [^false].
	(neg value not and: [m value > 16r7FFFFFFFFFFFFFFF]) ifTrue: [^false].
	(neg value and: [m value > 16r8000000000000000]) ifTrue: [^false].
	out value: (neg value ifTrue: [(0 - m value) asUInt64 asInt64] ifFalse: [m value asInt64]).
	^true
! !

!ObjectMemory methodsFor: 'strings'!
isKindOfString: o
	<function>
	| c |
	(self isPtr: o) ifFalse: [^false].
	c := self rawClass: o.
	^c = clsBytestring or: [c = (self special: SO_BYTESYMBOL) or: [c = (self special: SO_WIDESTRING) or: [c = (self special: SO_WIDESYMBOL)]]]
!
stringSize: s
	<function>
	<returns: 'size_t'>
	| f |
	f := self formatOf: s.
	f >= F_BYTES ifTrue: [^self byteSize: s].
	(f = 10 or: [f = 11]) ifTrue: [^self word32Size: s].
	^0
!
stringCharAt: s index: i
	"0-based code point."
	<function>
	(self formatOf: s) >= F_BYTES ifTrue: [^(self bytesOf: s) at: i].
	^(self words32Of: s) at: i
!
stringHash: s
	"String>>hash, the same for equal Strings and Symbols. Of more than 8 code points all below 256 (bytes, or 32-bit units that hold none above): them as bytes in 64-bit little-endian words, the last zero-padded; from h := their count, h := (h bitXor: word) * 16r5851F42D4C957F2D for each word, then h := h bitXor: h >> 32, h := h * 16r2545F4914F6CDD1D, h := h bitXor: h >> 29 (modulo 2^64), the low 30 bits. Else (up to 8, one word: a byte at a time keeps keys that differ in their last code point's low bits apart in small tables; code points above 255, which no byte string has; an image saved before this hash, wordHash false) FNV-1a over them, the low 30 bits. The optimizing tier's string hash stub does the same for bytes, String>>hash's fallback and ImageBuilder>>stringHash: in Smalltalk."
	<function>
	<returns: 'uint32_t'>
	<var: #n type: 'uint64_t'>
	<var: #i type: 'uint64_t'>
	<var: #h type: 'uint64_t'>
	<var: #w type: 'uint64_t'>
	| n i h w p |
	n := self stringSize: s.
	(wordHash not or: [n <= 8]) ifTrue: [^self fnvHash: s].
	i := 0.
	h := n.
	(self formatOf: s) >= F_BYTES
		ifTrue: [
			p := self pinnedBodyAddress: s.
			[i + 8 <= n] whileTrue: [
				h := ((h bitXor: (self uint64At: p + i)) * 16r5851F42D4C957F2D) asUInt64.
				i := i + 8]]
		ifFalse: [
			0 to: n asInt64 - 1 do: [:j |
				(self stringCharAt: s index: j asUInt64) > 255 ifTrue: [^self fnvHash: s]]].
	"what is left (bytes after the whole words, or 32-bit units below 256): up to 8 a word"
	w := 0.
	[i < n] whileTrue: [
		w := w bitOr: ((self stringCharAt: s index: i) asUInt64 << (8 * (i bitAnd: 7))).
		i := i + 1.
		((i bitAnd: 7) = 0 or: [i = n]) ifTrue: [
			h := ((h bitXor: w) * 16r5851F42D4C957F2D) asUInt64.
			w := 0]].
	h := h bitXor: h >> 32.
	h := (h * 16r2545F4914F6CDD1D) asUInt64.
	h := h bitXor: h >> 29.
	^(h bitAnd: 16r3FFFFFFF) asUInt32
!
fnvHash: s
	"FNV-1a over s's code points, the low 30 bits (stringHash:)."
	<function>
	<returns: 'uint32_t'>
	<var: #f type: 'uint32_t'>
	| f |
	f := 2166136261 asUInt32.
	0 to: (self stringSize: s) asInt64 - 1 do: [:k | f := ((f bitXor: (self stringCharAt: s index: k asUInt64)) * 16777619) asUInt32].
	^f bitAnd: 16r3FFFFFFF
!
utf8Decode: s size: n at: index
	"Decode the code point at *index, advancing it. A byte that does not begin a well-formed sequence (an overlong form, a surrogate, above 10FFFF, truncated, a stray continuation byte) decodes alone, to U+DC80-DCFF (Python's surrogateescape: utf8Of: writes the byte back, so OS names that are not UTF-8 round-trip)."
	<function>
	<returns: 'size_t'>
	<var: #lo type: 'uint32_t'>
	<var: #hi type: 'uint32_t'>
	| i c len cp d lo hi |
	i := index value.
	c := (s at: i) asUInt32.
	index value: i + 1.
	c < 16r80 ifTrue: [^c].
	len := 0.
	lo := 16r80.
	hi := 16rBF.
	(c >= 16rC2 and: [c <= 16rDF]) ifTrue: [len := 2].
	(c >= 16rE0 and: [c <= 16rEF]) ifTrue: [
		len := 3.
		c = 16rE0 ifTrue: [lo := 16rA0].
		c = 16rED ifTrue: [hi := 16r9F]].
	(c >= 16rF0 and: [c <= 16rF4]) ifTrue: [
		len := 4.
		c = 16rF0 ifTrue: [lo := 16r90].
		c = 16rF4 ifTrue: [hi := 16r8F]].
	(len = 0 or: [i + len asUInt64 > n]) ifTrue: [^16rDC00 + c].
	cp := c bitAnd: (16r7F >> len).
	1 to: len - 1 do: [:k |
		d := (s at: i + k asUInt64) asUInt32.
		(d < lo or: [d > hi]) ifTrue: [^16rDC00 + c].
		cp := (cp << 6) bitOr: (d bitAnd: 16r3F).
		lo := 16r80.
		hi := 16rBF].
	index value: i + len asUInt64.
	^cp
!
stringFromUtf8: str size: n
	"ByteString or WideString."
	<function>
	| s count i max cp r b w |
	s := self cCoerce: str to: 'uint8_t *'.
	count := 0 asUInt64.
	max := 0 asUInt64.
	i := self local: 'size_t'.
	i value: 0.
	[i value < n] whileTrue: [
		cp := self utf8Decode: s size: n at: i.
		cp > max ifTrue: [max := cp].
		count := count + 1].
	max < 256 ifTrue: [
		r := self allocBytes: clsBytestring count: count.
		b := self bytesOf: r.
		i value: 0.
		[i value < n] whileTrue: [
			b value: (self utf8Decode: s size: n at: i) asUInt8.
			b := b + 1].
		^r].
	r := self allocWords32: (self special: SO_WIDESTRING) count: count.
	w := self words32Of: r.
	i value: 0.
	[i value < n] whileTrue: [
		w value: (self utf8Decode: s size: n at: i) asUInt32.
		w := w + 1].
	^r
!
utf8Of: s
	"utf8BytesOf:size: as a C string: NULL also if s holds a U+0000 (a NUL byte), which would cut it short."
	<function>
	| n r |
	n := self local: 'size_t'.
	r := self utf8BytesOf: s size: n.
	(r notNull and: [(libc strlen: r) ~= n value]) ifTrue: [
		libc free: r.
		^self null].
	^r
!
utf8BytesOf: s size: size
	"malloc'd, NUL-terminated (NULL if out of memory), its length in *size; ByteString/Symbol/WideString/ByteArray (its bytes). U+DC80-DCFF become the byte they escape (utf8Decode:), other surrogates and code points above 10FFFF U+FFFD."
	<function>
	| n r p c |
	(self isPtr: s) ifFalse: [
		size value: 0.
		^libc strdup: ''].
	(self rawClass: s) = clsBytearray ifTrue: [
		n := self byteSize: s.
		size value: n.
		r := self cCoerce: (libc malloc: n + 1) to: 'uint8_t *'.
		r isNull ifTrue: [^self null].
		libc memcpy: r from: (self bytesOf: s) size: n.
		r at: n put: 0.
		^self cCoerce: r to: 'char *'].
	n := self stringSize: s.
	r := self cCoerce: (libc malloc: (n * 4) + 1) to: 'uint8_t *'.
	r isNull ifTrue: [^self null].
	p := r.
	0 to: n asInt64 - 1 do: [:i |
		c := self stringCharAt: s index: i asUInt64.
		(c > 16r10FFFF or: [c >= 16rD800 and: [c <= 16rDFFF and: [c < 16rDC80 or: [c > 16rDCFF]]]]) ifTrue: [c := 16rFFFD].
		(c < 16r80 or: [c >= 16rDC80 and: [c <= 16rDCFF]])
			ifTrue: [p value: (c bitAnd: 16rFF) asUInt8. p := p + 1]
			ifFalse: [
				c < 16r800
					ifTrue: [
						p value: (16rC0 bitOr: c >> 6) asUInt8.
						(p + 1) value: (16r80 bitOr: (c bitAnd: 16r3F)) asUInt8.
						p := p + 2]
					ifFalse: [
						c < 16r10000
							ifTrue: [
								p value: (16rE0 bitOr: c >> 12) asUInt8.
								(p + 1) value: (16r80 bitOr: ((c >> 6) bitAnd: 16r3F)) asUInt8.
								(p + 2) value: (16r80 bitOr: (c bitAnd: 16r3F)) asUInt8.
								p := p + 3]
							ifFalse: [
								p value: (16rF0 bitOr: c >> 18) asUInt8.
								(p + 1) value: (16r80 bitOr: ((c >> 12) bitAnd: 16r3F)) asUInt8.
								(p + 2) value: (16r80 bitOr: ((c >> 6) bitAnd: 16r3F)) asUInt8.
								(p + 3) value: (16r80 bitOr: (c bitAnd: 16r3F)) asUInt8.
								p := p + 4]]]].
	p value: 0.
	size value: (p - r) asUInt64.
	^self cCoerce: r to: 'char *'
! !

!ObjectMemory methodsFor: 'initialization'!
memoryInit: edenBytes maxHeap: maxHeap
	<function>
	gc init: edenBytes maxHeap: maxHeap.
	largeObjectBytes := (edenBytes quo: 8) > (64 * 1024) ifTrue: [edenBytes quo: 8] ifFalse: [64 * 1024].
	self resetAllocLimit
! !
