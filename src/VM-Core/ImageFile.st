VMCoreModule subclass: #ImageFile
	instanceVariableNames: 'imagePath'
	classVariableNames: ''
	package: 'VM-Core'!

ImageFile comment: 'Image load (with relocation) and snapshot. The file is a 64-byte ImageHeader and the old space''s objects as they were at base.'!

!ImageFile class methodsFor: 'declaring'!
declarations
	^#((imagePath 'char *'))
! !

!ImageFile methodsFor: 'accessing'!
imagePath
	^imagePath
! !

!ImageFile methodsFor: 'loading'!
loadImage: path
	<function>
	| f h delta p o s budget bytes |
	f := libc fopen: path mode: 'rb'.
	f isNull ifTrue: [self fatal: 'cannot open image %s' with: path].
	h := self local: 'ImageHeader'.
	((libc fread: h size: (self sizeof: 'ImageHeader') count: 1 file: f) ~= 1
		or: [(libc memcmp: h magic with: 'SAMALTK1' size: 8) ~= 0 or: [h version ~= 1]])
		ifTrue: [self fatal: '%s is not a Samaltak image' with: path].
	h heapBytes > gc maxHeapBytes ifTrue: [self fatal: 'image too large for heap limit'].
	(vmMain c4Moving and: [h heapBytes > c4 pinnedCapacity])
		ifTrue: [self fatal: 'image and C4 moving region pool exceed heap limit'].
	libc fseek: f offset: h headerSize asInt64 whence: libc SEEK_SET.
	(libc fread: (self ptr: gc oldLo) size: 1 count: h heapBytes file: f) ~= h heapBytes ifTrue: [
		self fatal: 'truncated image %s' with: path].
	libc fclose: f.
	delta := gc oldLo - h base.
	gc oldTop: gc oldLo + h heapBytes.
	p := gc oldLo.
	[p < gc oldTop] whileTrue: [
		o := p.
		(vmMain c4Requested and: [gc oldTop - p < 16]) ifTrue: [self fatal: 'truncated C4 image object header'].
		bytes := self objBytes: o.
		(vmMain c4Requested and: [bytes > (gc oldTop - p)]) ifTrue: [self fatal: 'bad C4 image object extent'].
		self header: o put: ((self header: o) bitClear: H_GCBITS).
		self rawClass: o put: ((self rawClass: o) + delta) asUInt64.
		(self fmtHasPointers: (self formatOf: o)) ifTrue: [
			s := self slotsOf: o.
			0 to: (self numSlots: o) asInt64 - 1 do: [:i |
				((self isPtr: (s at: i)) and: [(s at: i) ~= 0]) ifTrue: [s at: i put: ((s at: i) + delta) asUInt64]]].
		p := p + bytes].
	p := (h specials + delta) asUInt64.
	vmMain c4Requested ifTrue: [
		(p >= gc oldLo and: [p < gc oldTop and: [gc oldTop - p >= 16 and: [(p bitAnd: 7) = 0 and: [
			(self formatOf: p) = F_VAR and: [(self numSlots: p) > SO_COMPILEDMETHOD and: [(self objBytes: p) <= (gc oldTop - p)]]]]]])
			ifFalse: [self fatal: 'bad C4 image special objects array']].
	memory specialsOop: p.
	memory hashSeed: h hashSeed.
	"its hashed collections are by the String hash it was saved with (0: FNV-1a, images from before the other)"
	memory wordHash: h stringHash = 1.
	budget := 2 * h heapBytes.
	budget > gc oldBudget ifTrue: [gc oldBudget: (budget < gc maxHeapBytes ifTrue: [budget] ifFalse: [gc maxHeapBytes])].
	imagePath := posix realpath: path into: self null.
	imagePath isNull ifTrue: [imagePath := libc strdup: path].
	imagePath isNull ifTrue: [self fatal: 'out of memory'].
	memory refreshSpecials.
	vmMain c4Requested ifTrue: [self importC4]
!
importC4
	"Startup only: all image references have been relocated."
	<function>
	| p fmt bytes slots refs sp cls first association |
	c4 contextClass: memory clsContext.
	c4 methodClass: memory clsCompiledmethod.
	vmMain c4Moving ifTrue: [
		association := memory special: SO_ASSOCIATION.
		c4 plainPoint: memory clsPoint message: memory clsMessage association: association].
	c4 forwardByteClass: memory clsBytestring wideClass: (memory special: SO_WIDESTRING).
	c4 nilOop: memory nilOop.
	p := gc oldLo.
	[p < gc oldTop] whileTrue: [
		fmt := self formatOf: p.
		cls := self rawClass: p.
		slots := self numSlots: p.
		bytes := self objBytes: p.
		refs := (self fmtHasPointers: fmt) ifTrue: [slots] ifFalse: [0].
		first := 16rFFFFFFFF asUInt32. "C4_NO_WEAK"
		(fmt = F_WEAK or: [cls = memory clsContext]) ifTrue: [
			(cls >= gc oldLo and: [cls < gc oldTop and: [gc oldTop - cls >= 16 and: [(cls bitAnd: 7) = 0 and: [
				(self objBytes: cls) <= (gc oldTop - cls)]]]]) ifFalse: [self fatal: 'bad C4 image layout class'].
			fmt = F_WEAK ifTrue: [
				first := memory c4FixedFieldsFor: cls spec: F_WEAK slots: slots.
				first = 16rFFFFFFFF ifTrue: [self fatal: 'bad C4 image weak layout']]].
		cls = memory clsContext ifTrue: [
			(fmt = F_FIXVAR and: [(memory c4FixedFieldsFor: cls spec: F_FIXVAR slots: slots) = CTX_FIXED])
				ifFalse: [self fatal: 'bad C4 image Context layout'].
			sp := self loadRef: p at: CTX_STACKP.
			((self isInt: sp) and: [(sp >> 1) <= (slots - CTX_FIXED)]) ifFalse: [
				self fatal: 'bad C4 image Context stack pointer']].
		(c4 import: p bytes: bytes refs: refs weakStart: first asUInt32) ifFalse: [self fatal: 'cannot import object into C4 heap'].
		p := p + bytes]
! !

!ImageFile methodsFor: 'saving'!
writeSnapshot: path
	<function>
	| h f ok |
	vmMain c4Enabled ifTrue: [^false].
	gc fullGC.
	h := self local: 'ImageHeader'.
	h version: 1.
	h headerSize: 64.
	libc memcpy: h magic from: 'SAMALTK1' size: 8.
	h heapBytes: gc oldTop - gc oldLo.
	h base: gc oldLo.
	h specials: memory specialsOop.
	h hashSeed: memory hashSeed.
	h stringHash: (memory wordHash ifTrue: [1] ifFalse: [0]).
	f := libc fopen: path mode: 'wb'.
	f isNull ifTrue: [^false].
	ok := (libc fwrite: h size: (self sizeof: 'ImageHeader') count: 1 file: f) = 1
		and: [(libc fwrite: (self ptr: gc oldLo) size: 1 count: h heapBytes file: f) = h heapBytes].
	^(libc fclose: f) = 0 and: [ok]
! !

VMStruct subclass: #ImageHeader
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

ImageHeader comment: 'The 64 bytes at the start of an image file: magic SAMALTK1, version 1, header size, heap bytes, the address the heap was saved at, the special objects array''s address, the identity hash seed, the String hash its hashed collections are by (ObjectMemory>>stringHash:: 1 words of 8 bytes, 0 FNV-1a, as images saved before had).'!

!ImageHeader class methodsFor: 'declaring'!
fields
	^#((magic 'char[8]') (version uint64_t) (headerSize uint64_t) (heapBytes uint64_t) (base uint64_t) (specials uint64_t) (hashSeed uint64_t) (stringHash uint64_t))
! !
