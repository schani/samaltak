VMPrimitiveModule subclass: #ObjectPrimitives
	instanceVariableNames: 'instancesClass instancesResult instancesCount search'
	classVariableNames: ''
	package: 'VM-Core'!

ObjectPrimitives comment: 'Object, string and byte-access primitives. Indices are 1-based over indexable fields; byte offsets 1-based, little-endian unless BigEndian.'!

!ObjectPrimitives class methodsFor: 'declaring'!
declarations
	^#((instancesClass oop) (instancesResult oop) (instancesCount size_t) (search ByteSearch))
! !

!ObjectPrimitives methodsFor: 'object'!
primClass
	<vmPrimitive: 78 name: 'class'>
	<leaf>
	self answer: (memory classOf: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]))
!
primIdentical
	<vmPrimitive: 79 name: 'identical'>
	<leaf>
	self answerBool: self receiver = self arg0
!
primIdentityHash
	<vmPrimitive: 77 name: 'identityHash'>
	<leaf>
	| r |
	r := self receiver.
	(self isPtr: r) ifTrue: [^self answer: (self intOop: (self hashOf: r))].
	(self isInt: r) ifTrue: [^self answer: r].
	(self isChar: r) ifTrue: [^self answer: (self intOop: (self charVal: r))].
	self answer: (self intOop: ((r >> 3) bitAnd: 16r3FFFFFFF))
!
primBasicNew
	<vmPrimitive: 70 name: 'basicNew'>
	| err o |
	err := self local: 'int'.
	o := memory instantiate: self receiver size: 0 error: err.
	err value ~= 0 ifTrue: [^err value > 0 ifTrue: [self failCode: err value] ifFalse: [self fail]].
	self answer: o
!
primBasicNewSize
	"A size no object can have (a LargePositiveInteger too) fails with PRIM_ERR_NO_MEMORY."
	<vmPrimitive: 71 name: 'basicNew:'>
	| n u err o |
	n := self arg0.
	u := self local: 'uint64_t'.
	(memory u64Of: n into: u) ifFalse: [
		((self isPtr: n) and: [(self rawClass: n) = (memory special: SO_LARGEPOS)]) ifFalse: [^self fail].
		u value: 16rFFFFFFFFFFFFFFFF].
	err := self local: 'int'.
	o := memory instantiate: self receiver size: u value error: err.
	err value ~= 0 ifTrue: [^err value > 0 ifTrue: [self failCode: err value] ifFalse: [self fail]].
	self answer: o
!
primBasicSize
	<vmPrimitive: 72 name: 'basicSize'>
	<leaf>
	self answer: (self intOop: (memory indexableSize: self receiver) asInt64)
!
primAt
	<vmPrimitive: 73 name: 'at'>
	| r k f v |
	r := self receiver.
	(self isPtr: r) ifFalse: [^self fail].
	k := self indexOf: self arg0 limit: (memory indexableSize: r).
	k < 0 ifTrue: [^self fail].
	"a married Context's slots are its frame's"
	(interpreter isMarried: r) ifTrue: [
		v := interpreter contextSlot: k asInt64 of: r.
		v ~= 0 ifTrue: [^self answer: v].
		r := self receiver].
	f := self formatOf: r.
	(self fmtHasPointers: f) ifTrue: [^self answer: (self loadRef: r at: (memory fixedFields: r) + k asUInt32)].
	f = F_W64 ifTrue: [
		v := (self slotsOf: r) at: k.
		^self answer: (v <= VM_INT_MAX asUInt64 ifTrue: [self intOop: v asInt64] ifFalse: [memory largeIntFrom: v negative: false])].
	(f = 10 or: [f = 11]) ifTrue: [^self answer: (self intOop: ((self words32Of: r) at: k))].
	f >= F_BYTES ifTrue: [^self answer: (self intOop: ((self bytesOf: r) at: k))].
	self fail
!
primAtPut
	<vmPrimitive: 74 name: 'atPut'>
	| r k v f u |
	r := self receiver.
	(self argCount < 2 or: [(self isPtr: r) not or: [self isImmutable: r]]) ifTrue: [^self fail].
	k := self indexOf: (self arg: 0) limit: (memory indexableSize: r).
	k < 0 ifTrue: [^self fail].
	v := self arg: 1.
	(interpreter isMarried: r) ifTrue: [
		(interpreter context: r slot: k asInt64 put: v) ifTrue: [^self answer: v].
		r := self receiver.
		v := self arg: 1].
	f := self formatOf: r.
	(self fmtHasPointers: f)
		ifTrue: [
			k := (memory fixedFields: r) asInt64 + k.
			(vmMain c4Enabled and: [self c4CodeStoreRejected: r at: k put: v]) ifTrue: [^self fail].
			(self c4InactiveContext: r at: k) ifTrue: [
				^v = memory nilOop ifTrue: [self answer: v] ifFalse: [self fail]].
			self storeRef: r at: k put: v]
		ifFalse: [
			f = F_W64
				ifTrue: [
					u := self local: 'uint64_t'.
					(memory u64Of: v into: u) ifFalse: [^self fail].
					(self slotsOf: r) at: k put: u value]
				ifFalse: [
					(f = 10 or: [f = 11])
						ifTrue: [
							((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 16rFFFFFFFF]]) ifFalse: [^self fail].
							(self words32Of: r) at: k put: (self intVal: v) asUInt32]
						ifFalse: [
							f >= F_BYTES ifFalse: [^self fail].
							((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 255]]) ifFalse: [^self fail].
							(self bytesOf: r) at: k put: (self intVal: v) asUInt8]]].
	self answer: v
!
primInstVarAt
	<vmPrimitive: 75 name: 'instVarAt'>
	| r k v |
	r := self receiver.
	((self isPtr: r) and: [self fmtHasPointers: (self formatOf: r)]) ifFalse: [^self fail].
	k := self indexOf: self arg0 limit: (self numSlots: r).
	k < 0 ifTrue: [^self fail].
	"a married Context's sender, pc, stackp and slots are its frame's"
	((interpreter isMarried: r) and: [k <= CTX_STACKP or: [k >= CTX_FIXED]]) ifTrue: [
		v := k <= CTX_STACKP
			ifTrue: [interpreter contextField: k asInt64 of: r]
			ifFalse: [interpreter contextSlot: k asInt64 - CTX_FIXED of: r].
		v ~= 0 ifTrue: [^self answer: v].
		r := self receiver].
	self answer: (self loadRef: r at: k)
!
primInstVarAtPut
	<vmPrimitive: 76 name: 'instVarAtPut'>
	| r k v |
	r := self receiver.
	(self argCount < 2 or: [(self isPtr: r) not or: [(self isImmutable: r) or: [(self fmtHasPointers: (self formatOf: r)) not]]]) ifTrue: [^self fail].
	k := self indexOf: (self arg: 0) limit: (self numSlots: r).
	k < 0 ifTrue: [^self fail].
	v := self arg: 1.
	(vmMain c4Enabled and: [
		(k = CTX_STACKP and: [(self rawClass: r) = memory clsContext]) or: [
			self c4CodeStoreRejected: r at: k put: v]]) ifTrue: [^self fail].
	"a married Context: a slot goes to its frame; a fixed field may change how it continues, its frames are flushed first"
	(interpreter isMarried: r) ifTrue: [
		k >= CTX_FIXED
			ifTrue: [(interpreter context: r slot: k asInt64 - CTX_FIXED put: v) ifTrue: [^self answer: v]]
			ifFalse: [interpreter materializeAll].
		r := self receiver.
		v := self arg: 1].
	(self c4InactiveContext: r at: k) ifTrue: [
		^v = memory nilOop ifTrue: [self answer: v] ifFalse: [self fail]].
	self storeRef: r at: k put: v.
	self answer: v
!
c4InactiveContext: o at: k
	^vmMain c4Enabled and: [k >= CTX_FIXED and: [
		(self rawClass: o) = memory clsContext and: [k asUInt64 >= (self contextPrefix: o)]]]
!
primShallowCopy
	<vmPrimitive: 80 name: 'shallowCopy'>
	| r c n |
	r := self receiver.
	(self isPtr: r) ifFalse: [^self answer: r].
	"a married Context's state is its frame's: Context>>shallowCopy copies what Smalltalk reads"
	(interpreter isMarried: r) ifTrue: [^self fail].
	c := memory allocObjTry: (self rawClass: r) format: (self formatOf: r) slots: (self numSlots: r) asUInt64.
	c = 0 ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	r := self receiver.
	n := self numSlots: r.
	(self fmtHasPointers: (self formatOf: r))
		ifTrue: [
			(vmMain c4Enabled and: [(self rawClass: r) = memory clsContext])
				ifTrue: [memory copyC4Context: c from: r]
				ifFalse: [memory copyRefs: c at: 0 from: r at: 0 count: n]]
		ifFalse: [libc memcpy: (self bytesOf: c) from: (self bytesOf: r) size: n asUInt64 * 8].
	self answer: c
!
primIsImmutable
	<vmPrimitive: 83 name: 'isImmutable'>
	| r |
	r := self receiver.
	self answerBool: ((self isPtr: r) not or: [self isImmutable: r])
!
primSetImmutable
	<vmPrimitive: 84 name: 'setImmutable:'>
	| r v old |
	r := self receiver.
	v := self arg0.
	(v ~= memory trueOop and: [v ~= memory falseOop]) ifTrue: [^self fail].
	(self isPtr: r) ifFalse: [
		v = memory trueOop ifTrue: [^self answer: memory trueOop].
		^self fail].
	old := self isImmutable: r.
	v = memory trueOop
		ifTrue: [self header: r put: ((self header: r) bitOr: H_IMMUTABLE)]
		ifFalse: [self header: r put: ((self header: r) bitClear: H_IMMUTABLE)].
	self answerBool: old
!
primChangeClassTo
	<vmPrimitive: 85 name: 'changeClassTo:'>
	| r c spec isize f nf |
	vmMain c4Enabled ifTrue: [^self fail].
	r := self receiver.
	c := self arg0.
	((self isPtr: r) and: [(self isPtr: c) and: [(self numSlots: c) > BEH_FORMAT and: [self isInt: (self loadRef: c at: BEH_FORMAT)]]]) ifFalse: [^self fail].
	(interpreter isMarried: r) ifTrue: [
		interpreter materializeAll.
		r := self receiver.
		c := self arg0].
	spec := (self intVal: (self loadRef: c at: BEH_FORMAT)) >> CLS_SPEC_SHIFT.
	isize := (self intVal: (self loadRef: c at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	f := self formatOf: r.
	nf := f.
	spec <= 1
		ifTrue: [
			(f > 1 or: [(self numSlots: r) asInt64 ~= isize]) ifTrue: [^self fail].
			nf := isize ~= 0 ifTrue: [1] ifFalse: [0]]
		ifFalse: [
			spec <= 4
				ifTrue: [
					(f < 2 or: [f > 4 or: [(memory fixedFields: r) asInt64 ~= isize]]) ifTrue: [^self fail].
					nf := (spec = 2 and: [isize ~= 0]) ifTrue: [3] ifFalse: [spec asInt32]]
				ifFalse: [
					spec = 9
						ifTrue: [f ~= 9 ifTrue: [^self fail]]
						ifFalse: [
							spec = 10
								ifTrue: [(f ~= 10 and: [f ~= 11]) ifTrue: [^self fail]]
								ifFalse: [
									spec = 16 ifFalse: [^self fail].
									f < 16 ifTrue: [^self fail]]]]].
	self header: r put: (((self header: r) bitClear: 16r1F asUInt64 << H_FMT_SHIFT) bitOr: nf asUInt64 << H_FMT_SHIFT).
	self rawClass: r put: c.
	(self isYoung: c) ifTrue: [gc rememberIfOld: r].
	jit classChanged.
	self answer: r
!
countInstance: o data: d
	<function>
	((self rawClass: o) = instancesClass and: [o ~= instancesResult]) ifTrue: [
		(instancesResult ~= 0 and: [instancesCount >= (self numSlots: instancesResult)]) ifTrue: [^self].
		instancesResult ~= 0 ifTrue: [self storeRef: instancesResult at: instancesCount put: o].
		instancesCount := instancesCount + 1]
!
primAllInstances
	<vmPrimitive: 86 name: 'allInstances'>
	| a |
	vmMain c4Enabled ifTrue: [^self fail].
	gc fullGC.
	instancesClass := self receiver.
	instancesResult := 0.
	instancesCount := 0.
	gc walkOldSpace: (self functionPointer: #countInstance:data:) data: self null.
	a := memory allocOld: memory clsArray format: F_VAR slots: instancesCount asUInt32.
	instancesClass := self receiver.
	instancesResult := a.
	instancesCount := 0.
	gc walkOldSpace: (self functionPointer: #countInstance:data:) data: self null.
	instancesResult := 0.
	self answer: a
!
primBecomeForward
	<vmPrimitive: 88 name: 'becomeForward'>
	vmMain c4Enabled ifTrue: [^self fail].
	((self isPtr: self receiver) and: [(self isPtr: self arg0) and: [self receiver ~= memory nilOop]]) ifFalse: [^self fail].
	interpreter flushIfMarried: self receiver.
	gc fullGC.
	gc becomeForward: self receiver to: self arg0.
	self answer: self receiver
!
primSpecialObjectsArray
	<vmPrimitive: 89 name: 'specialObjectsArray'>
	self answer: memory specialsOop
! !

!ObjectPrimitives methodsFor: 'strings'!
isStringLike: o
	| f |
	(self isPtr: o) ifFalse: [^false].
	f := self formatOf: o.
	^f >= F_BYTES or: [f = 10 or: [f = 11]]
!
primStringAt
	<vmPrimitive: 100 name: 'stringAt'>
	<leaf>
	| r k |
	r := self receiver.
	(self isStringLike: r) ifFalse: [^self fail].
	k := self indexOf: self arg0 limit: (memory stringSize: r).
	k < 0 ifTrue: [^self fail].
	self answer: (self charOop: (memory stringCharAt: r index: k asUInt64))
!
primStringAtPut
	<vmPrimitive: 101 name: 'stringAtPut'>
	<leaf>
	| r k c |
	r := self receiver.
	(self argCount < 2 or: [(self isStringLike: r) not or: [self isImmutable: r]]) ifTrue: [^self fail].
	k := self indexOf: (self arg: 0) limit: (memory stringSize: r).
	k < 0 ifTrue: [^self fail].
	c := self arg: 1.
	(self isChar: c) ifFalse: [^self fail].
	(self formatOf: r) >= F_BYTES
		ifTrue: [
			(self charVal: c) > 255 ifTrue: [^self fail].
			(self bytesOf: r) at: k put: (self charVal: c) asUInt8]
		ifFalse: [(self words32Of: r) at: k put: (self charVal: c)].
	self answer: c
!
primStringHash
	<vmPrimitive: 102 name: 'stringHash'>
	<leaf>
	| s |
	s := self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver].
	(self isStringLike: s) ifFalse: [^self fail].
	self answer: (self intOop: (memory stringHash: s))
!
primStringCompare
	<vmPrimitive: 103 name: 'stringCompare'>
	<leaf>
	| a b na nb n x y |
	a := self receiver.
	b := self arg0.
	((self isStringLike: a) and: [self isStringLike: b]) ifFalse: [^self fail].
	na := memory stringSize: a.
	nb := memory stringSize: b.
	n := na < nb ifTrue: [na] ifFalse: [nb].
	0 to: n asInt64 - 1 do: [:i |
		x := memory stringCharAt: a index: i asUInt64.
		y := memory stringCharAt: b index: i asUInt64.
		x ~= y ifTrue: [^self answer: (self intOop: (x < y ifTrue: [-1] ifFalse: [1]))]].
	self answer: (self intOop: (na < nb ifTrue: [-1] ifFalse: [na > nb ifTrue: [1] ifFalse: [0]]))
!
isByteString: o
	"A ByteString or ByteSymbol."
	^(self isPtr: o) and: [(self rawClass: o) = memory clsBytestring or: [(self rawClass: o) = (memory special: SO_BYTESYMBOL)]]
!
lowercase: c
	"Character>>asLowercase of the byte c: A-Z and À-Þ but × go up 32."
	^((c >= 65 and: [c <= 90]) or: [c >= 192 and: [c <= 222 and: [c ~= 215]]]) ifTrue: [c + 32] ifFalse: [c]
!
primStringCaseInsensitiveCompare
	"stringCompare of the characters' asLowercase, for ByteStrings and ByteSymbols (String>>caseInsensitiveCompare: loops for wide ones)."
	<vmPrimitive: 116 name: 'stringCaseInsensitiveCompare'>
	<leaf>
	| a b na nb pa pb x y |
	a := self receiver.
	b := self arg0.
	((self isByteString: a) and: [self isByteString: b]) ifFalse: [^self fail].
	na := memory byteSize: a.
	nb := memory byteSize: b.
	pa := self bytesOf: a.
	pb := self bytesOf: b.
	0 to: (na < nb ifTrue: [na] ifFalse: [nb]) asInt64 - 1 do: [:i |
		x := (pa at: i) asInt32.
		y := (pb at: i) asInt32.
		x ~= y ifTrue: [
			x := self lowercase: x.
			y := self lowercase: y.
			x ~= y ifTrue: [^self answer: (self intOop: (x < y ifTrue: [-1] ifFalse: [1]))]]].
	self answer: (self intOop: (na < nb ifTrue: [-1] ifFalse: [na > nb ifTrue: [1] ifFalse: [0]]))
!
uppercase: c
	"Character>>asUppercase of the byte c (not ÿ, whose uppercase is wide): a-z and à-þ but ÷ go down 32."
	^((c >= 97 and: [c <= 122]) or: [c >= 224 and: [c <= 254 and: [c ~= 247]]]) ifTrue: [c - 32] ifFalse: [c]
!
convertCase: upper
	"asUppercase (upper) or asLowercase of a ByteString or ByteSymbol: a new ByteString. Fails for others and for ÿ going up."
	<function>
	| r n s a b c |
	r := self receiver.
	(self isByteString: r) ifFalse: [^self fail].
	n := memory byteSize: r.
	s := memory allocBytes: memory clsBytestring count: n.
	r := self receiver.
	a := self bytesOf: r.
	b := self bytesOf: s.
	0 to: n asInt64 - 1 do: [:i |
		c := (a at: i) asInt32.
		upper
			ifTrue: [
				c = 255 ifTrue: [^self fail].
				c := self uppercase: c]
			ifFalse: [c := self lowercase: c].
		b at: i put: c asUInt8].
	self answer: s
!
primStringAsUppercase
	<vmPrimitive: 92 name: 'stringAsUppercase'>
	self convertCase: true
!
primStringAsLowercase
	<vmPrimitive: 93 name: 'stringAsLowercase'>
	self convertCase: false
!
primStringIndexOf
	"indexOf: aCharacter startingAt: start: the index of its first occurrence at or after start, 0 if none. Fails for a start below 1 or anything but a Character."
	<vmPrimitive: 117 name: 'stringIndexOf'>
	<leaf>
	| r c s v w |
	r := self receiver.
	c := self arg: 0.
	s := self arg: 1.
	(self argCount = 2 and: [(self isStringLike: r) and: [(self isChar: c) and: [(self isInt: s) and: [(self intVal: s) >= 1]]]]) ifFalse: [^self fail].
	v := self charVal: c.
	(self formatOf: r) >= F_BYTES
		ifTrue: [
			v < 256 ifTrue: [
				^self answer: (self intOop: (search indexOfByte: v asUInt8 in: (self bytesOf: r) size: (memory byteSize: r) asInt64 from: (self intVal: s) - 1) + 1)]]
		ifFalse: [
			w := self words32Of: r.
			(self intVal: s) - 1 to: (memory word32Size: r) asInt64 - 1 do: [:i |
				(w at: i) = v ifTrue: [^self answer: (self intOop: i + 1)]]].
	self answer: (self intOop: 0)
!
primStringIndexOfSubstring
	"indexOfSubCollection: aString startingAt: start: where aString next begins at or after start, 0 if it does not (start if it is empty). Fails for a start below 1 or anything but a String."
	<vmPrimitive: 118 name: 'stringIndexOfSubstring'>
	<leaf>
	| r p s n m k w v |
	r := self receiver.
	p := self arg: 0.
	s := self arg: 1.
	(self argCount = 2 and: [(self isStringLike: r) and: [(memory isKindOfString: p) and: [(self isInt: s) and: [(self intVal: s) >= 1]]]]) ifFalse: [^self fail].
	n := (memory stringSize: r) asInt64.
	m := (memory stringSize: p) asInt64.
	m = 0 ifTrue: [^self answer: s].
	((self formatOf: r) >= F_BYTES and: [(self formatOf: p) >= F_BYTES]) ifTrue: [
		^self answer: (self intOop: (search indexOfBytes: (self bytesOf: p) size: m in: (self bytesOf: r) size: n from: (self intVal: s) - 1) + 1)].
	((self formatOf: r) < F_BYTES and: [(self formatOf: p) < F_BYTES]) ifTrue: [
		w := self words32Of: r.
		v := self words32Of: p.
		(self intVal: s) - 1 to: n - m do: [:i |
			((w at: i) = (v at: 0) and: [(libc memcmp: w + i with: v size: m asUInt64 * 4) = 0]) ifTrue: [^self answer: (self intOop: i + 1)]].
		^self answer: (self intOop: 0)].
	(self intVal: s) - 1 to: n - m do: [:i |
		k := 0.
		[k < m and: [(memory stringCharAt: r index: (i + k) asUInt64) = (memory stringCharAt: p index: k asUInt64)]] whileTrue: [k := k + 1].
		k = m ifTrue: [^self answer: (self intOop: i + 1)]].
	self answer: (self intOop: 0)
!
elementKindOf: o
	| f |
	f := self formatOf: o.
	(self fmtHasPointers: f) ifTrue: [^1].
	f = F_W64 ifTrue: [^2].
	(f = 10 or: [f = 11]) ifTrue: [^3].
	f >= F_BYTES ifTrue: [^4].
	^0
!
primReplaceFromTo
	<vmPrimitive: 104 name: 'replaceFromToWithStartingAt'>
	<leaf>
	| r src so eo ro kind start stop rstart n fr fs |
	self argCount < 4 ifTrue: [^self fail].
	r := self receiver.
	src := self arg: 2.
	so := self arg: 0.
	eo := self arg: 1.
	ro := self arg: 3.
	((self isPtr: r) and: [(self isPtr: src) and: [(self isImmutable: r) not and: [(self isInt: so) and: [(self isInt: eo) and: [self isInt: ro]]]]]) ifFalse: [^self fail].
	kind := self elementKindOf: r.
	(kind = 0 or: [kind ~= (self elementKindOf: src)]) ifTrue: [^self fail].
	"a married Context's slots are in its frame: the fallback reads them"
	(kind = 1 and: [(interpreter isMarried: src) or: [interpreter isMarried: r]]) ifTrue: [^self fail].
	start := self intVal: so.
	stop := self intVal: eo.
	rstart := self intVal: ro.
	n := stop - start + 1.
	(n = 0 and: [start >= 1]) ifTrue: [^self answer: r].
	(start < 1 or: [n < 0 or: [stop > (memory indexableSize: r) asInt64 or: [rstart < 1 or: [rstart + n - 1 > (memory indexableSize: src) asInt64]]]]) ifTrue: [^self fail].
	kind = 1 ifTrue: [
		fr := memory fixedFields: r.
		fs := memory fixedFields: src.
		(self c4InactiveContext: r at: fr asInt64 + stop - 1) ifTrue: [^self fail].
		(vmMain c4Enabled and: [r = memory specialsOop and: [
			fr asInt64 + start - 1 <= SO_COMPILEDMETHOD and: [fr asInt64 + stop - 1 >= SO_COMPILEDMETHOD]]]) ifTrue: [^self fail].
		memory copyRefs: r at: (fr + start - 1) asUInt64 from: src at: (fs + rstart - 1) asUInt64 count: n asUInt64].
	kind = 2 ifTrue: [libc memmove: (self bytesOf: r) + ((start - 1) * 8) from: (self bytesOf: src) + ((rstart - 1) * 8) size: n asUInt64 * 8].
	kind = 3 ifTrue: [libc memmove: (self words32Of: r) + start - 1 from: (self words32Of: src) + rstart - 1 size: n asUInt64 * 4].
	kind = 4 ifTrue: [libc memmove: (self bytesOf: r) + start - 1 from: (self bytesOf: src) + rstart - 1 size: n asUInt64].
	self answer: r
! !

!ObjectPrimitives methodsFor: 'bytes'!
rawByteSize: o
	| f |
	f := self formatOf: o.
	f >= F_BYTES ifTrue: [^memory byteSize: o].
	(f = 10 or: [f = 11]) ifTrue: [^(memory word32Size: o) * 4].
	f = F_W64 ifTrue: [^(self numSlots: o) asUInt64 * 8].
	^0 asUInt64
!
byteAt: width put: isPut
	"The address of width bytes of the receiver at the 1-based offset argument, or 0."
	| r n i |
	r := self receiver.
	((self isPtr: r) not or: [isPut and: [self isImmutable: r]]) ifTrue: [^0 asUInt64].
	n := self rawByteSize: r.
	i := self arg0.
	((self isInt: i) and: [(self intVal: i) >= 1 and: [((self intVal: i) - 1) asUInt64 + width <= n]]) ifFalse: [^0 asUInt64].
	^r + 16 + ((self intVal: i) - 1) asUInt64
!
storedFloat: v
	"The Float or SmallInteger v as a double; the caller checked it."
	^(self isInt: v) ifTrue: [(self intVal: v) asFloat] ifFalse: [memory floatVal: v]
!
primBytesUint16At
	<vmPrimitive: 105 name: 'bytesUint16At'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (self uint16At: p))
!
primBytesUint32At
	<vmPrimitive: 106 name: 'bytesUint32At'>
	<leaf>
	| p |
	p := self byteAt: 4 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (self uint32At: p))
!
primBytesInt16At
	<vmPrimitive: 107 name: 'bytesInt16At'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (self int16At: p))
!
primBytesFloat32At
	<vmPrimitive: 108 name: 'bytesFloat32At'>
	| p |
	p := self byteAt: 4 put: false.
	p = 0 ifTrue: [^self fail].
	self answerFloat: (self float32At: p)
!
primBytesFloat32AtPut
	<vmPrimitive: 109 name: 'bytesFloat32AtPut'>
	<leaf>
	| p v |
	p := self byteAt: 4 put: true.
	(p = 0 or: [self argCount < 2]) ifTrue: [^self fail].
	v := self arg: 1.
	((memory isFloat: v) or: [self isInt: v]) ifFalse: [^self fail].
	self float32At: p put: (self storedFloat: v).
	self answer: v
!
primBytesUint32AtPut
	<vmPrimitive: 110 name: 'bytesUint32AtPut'>
	<leaf>
	| p v |
	p := self byteAt: 4 put: true.
	(p = 0 or: [self argCount < 2]) ifTrue: [^self fail].
	v := self arg: 1.
	((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 16rFFFFFFFF]]) ifFalse: [^self fail].
	self uint32At: p put: (self intVal: v) asUInt32.
	self answer: v
!
primBytesFloat64At
	<vmPrimitive: 111 name: 'bytesFloat64At'>
	| p |
	p := self byteAt: 8 put: false.
	p = 0 ifTrue: [^self fail].
	self answerFloat: (self float64At: p)
!
primBytesFloat64AtPut
	<vmPrimitive: 112 name: 'bytesFloat64AtPut'>
	<leaf>
	| p v |
	p := self byteAt: 8 put: true.
	(p = 0 or: [self argCount < 2]) ifTrue: [^self fail].
	v := self arg: 1.
	((memory isFloat: v) or: [self isInt: v]) ifFalse: [^self fail].
	self float64At: p put: (self storedFloat: v).
	self answer: v
!
primBytesUint16BigEndianAt
	<vmPrimitive: 113 name: 'bytesUint16BigEndianAt'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: ((self uint8At: p) asInt64 << 8 bitOr: (self uint8At: p + 1)))
!
primBytesInt16BigEndianAt
	<vmPrimitive: 114 name: 'bytesInt16BigEndianAt'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: ((self uint8At: p) asInt64 << 8 bitOr: (self uint8At: p + 1)) asInt16)
!
primBytesUint32BigEndianAt
	<vmPrimitive: 115 name: 'bytesUint32BigEndianAt'>
	<leaf>
	| p |
	p := self byteAt: 4 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: ((((self uint8At: p) asUInt64 << 24 bitOr: (self uint8At: p + 1) asUInt64 << 16) bitOr: (self uint8At: p + 2) asUInt64 << 8) bitOr: (self uint8At: p + 3)))
! !
