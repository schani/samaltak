VMCoreModule subclass: #GarbageCollector
	instanceVariableNames: 'youngLo youngHi edenLo edenHi edenBox survLo survTop survHi survOtherLo survOtherHi oldLo oldTop oldHi oldAltLo oldAltHi oldBudget maxHeapBytes oldReserve gcEpoch statScavenges statFullGcs statScavengeUs statFullUs statAllocated statTenured remset remsetCount remsetCap startBits vlo verify toLo toTop toHi weakList weakCount weakCap finalizationPending statWeakCleared ftTop becomeFrom becomeTo youngForwarders oldForwarders'
	classVariableNames: 'MIN_BUDGET TENURE_AGE'
	package: 'VM-Core'!

GarbageCollector comment: 'Generational GC: eden and two survivor spaces scavenged with a remembered set, copying full GC between two old-space reservations. Weak objects (format 4) have their indexable slots cleared when their referents die. Addresses of the spaces are plain integers.'!

!GarbageCollector class methodsFor: 'declaring'!
declarations
	^#((youngLo uint64_t) (youngHi uint64_t) (edenLo uint64_t) (edenHi uint64_t) (edenBox 'uint64_t[2]')
		(survLo uint64_t) (survTop uint64_t) (survHi uint64_t) (survOtherLo uint64_t) (survOtherHi uint64_t)
		(oldLo uint64_t) (oldTop uint64_t) (oldHi uint64_t) (oldAltLo uint64_t) (oldAltHi uint64_t)
		(oldBudget size_t) (maxHeapBytes size_t) (oldReserve size_t) (gcEpoch uint64_t)
		(statScavenges uint64_t) (statFullGcs uint64_t) (statScavengeUs uint64_t) (statFullUs uint64_t) (statAllocated uint64_t) (statTenured uint64_t)
		(remset 'oop *') (remsetCount size_t) (remsetCap size_t)
		(startBits 'uint8_t *') (vlo uint64_t) (verify int32_t -1)
		(toLo uint64_t) (toTop uint64_t) (toHi uint64_t)
		(weakList 'oop *') (weakCount size_t) (weakCap size_t) (finalizationPending bool) (statWeakCleared uint64_t)
		(ftTop uint64_t) (becomeFrom oop) (becomeTo oop) (youngForwarders uint64_t) (oldForwarders uint64_t))
!
initialize
	MIN_BUDGET := 64 << 20.
	TENURE_AGE := 2
! !

!GarbageCollector methodsFor: 'accessing'!
tenureAge
	^TENURE_AGE
!
youngLo
	^youngLo
!
youngHi
	^youngHi
!
edenLo
	^edenLo
!
edenHi
	^edenHi
!
edenTop
	^edenBox at: 0
!
edenTop: a
	edenBox at: 0 put: a
!
allocLimit
	^edenBox at: 1
!
allocLimit: a
	edenBox at: 1 put: a
!
edenBoxAddress
	"Where eden's top and the allocation limit are (machine code allocates there)."
	^self cCoerce: edenBox to: 'uint64_t'
!
survLo
	^survLo
!
survTop
	^survTop
!
oldLo
	^oldLo
!
oldTop
	^oldTop
!
oldTop: a
	oldTop := a
!
oldBudget
	^oldBudget
!
oldBudget: n
	oldBudget := n
!
maxHeapBytes
	^maxHeapBytes
!
gcEpoch
	^gcEpoch
!
gcEpoch: n
	gcEpoch := n
!
statScavenges
	^statScavenges
!
statFullGcs
	^statFullGcs
!
statScavengeUs
	^statScavengeUs
!
statFullUs
	^statFullUs
!
statAllocated
	^statAllocated
!
statAllocated: n
	statAllocated := n
!
statTenured
	^statTenured
!
remsetCount
	^remsetCount
!
finalizationPending
	^finalizationPending
!
finalizationPending: aBoolean
	finalizationPending := aBoolean
!
statWeakCleared
	^statWeakCleared
! !

!GarbageCollector methodsFor: 'spaces'!
reserve: n
	"Address space for a space, not memory: unaccounted (MAP_NORESERVE), so that forking (a pty, an external program) needs no RAM and swap for the whole maximum heap."
	<function>
	<var: #n type: 'size_t'>
	| p |
	p := posix mmap: self null length: n protection: (posix PROT_READ bitOr: posix PROT_WRITE) flags: ((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: posix MAP_NORESERVE) file: -1 offset: 0.
	p = posix MAP_FAILED ifTrue: [self fatal: 'cannot reserve %zu bytes' with: n].
	^self cCoerce: p to: 'uint64_t'
!
releasePages: address size: n
	"Tell the system the whole pages in [address, address + n) are not needed: their memory goes back to it until they are touched again. Their contents are undefined afterwards (zeroes on Linux, kept on macOS and UEFI): only for memory whose contents do not matter."
	<export>
	<var: #address type: 'void *'>
	<var: #n type: 'uint64_t'>
	| lo hi |
	lo := ((self cCoerce: address to: 'uint64_t') + 16383) bitClear: 16383.
	hi := ((self cCoerce: address to: 'uint64_t') + n) bitClear: 16383.
	hi > lo ifTrue: [posix madvise: (self ptr: lo) length: hi - lo advice: posix MADV_DONTNEED]
!
releaseFreeMemory
	"Scavenge, then give back the pages of eden and of the empty survivor space: what an idle program holds only because it once allocated. They are touched again as it allocates."
	<export>
	self scavenge.
	self releasePages: (self ptr: edenLo) size: edenHi - edenLo.
	self releasePages: (self ptr: survOtherLo) size: survOtherHi - survOtherLo
!
discard: p size: n
	"Give the pages back (a fresh anonymous mapping over them)."
	<function>
	| m |
	m := (n + 16383) bitClear: 16383.
	m ~= 0 ifTrue: [
		posix mmap: (self ptr: p) length: m protection: (posix PROT_READ bitOr: posix PROT_WRITE)
			flags: (((posix MAP_PRIVATE bitOr: posix MAP_ANON) bitOr: posix MAP_FIXED) bitOr: posix MAP_NORESERVE) file: -1 offset: 0]
!
init: edenBytes maxHeap: maxHeap
	<function>
	| surv young |
	surv := edenBytes quo: 4.
	young := edenBytes + (2 * surv).
	youngLo := self reserve: young.
	youngHi := youngLo + young.
	edenLo := youngLo.
	self edenTop: youngLo.
	edenHi := edenLo + edenBytes.
	self allocLimit: edenHi.
	survLo := survTop := edenHi.
	survHi := survLo + surv.
	survOtherLo := survHi.
	survOtherHi := survOtherLo + surv.
	maxHeapBytes := maxHeap.
	oldReserve := maxHeap + young + (1 << 20).
	oldLo := oldTop := self reserve: oldReserve.
	oldHi := oldLo + oldReserve.
	oldAltLo := self reserve: oldReserve.
	oldAltHi := oldAltLo + oldReserve.
	oldBudget := MIN_BUDGET
! !

!GarbageCollector methodsFor: 'remembered set'!
remember: o
	<function>
	self header: o put: ((self header: o) bitOr: H_REMEMBERED).
	remsetCount = remsetCap ifTrue: [
		remsetCap := remsetCap = 0 ifTrue: [4096] ifFalse: [remsetCap * 2].
		remset := self cCoerce: (libc realloc: remset size: remsetCap * 8) to: 'oop *'.
		remset isNull ifTrue: [self fatal: 'out of memory growing the remembered set to %zu entries' with: remsetCap]].
	remset at: remsetCount put: o.
	remsetCount := remsetCount + 1
!
rememberIfOld: o
	((self isPtr: o) and: [(self isYoung: o) not and: [((self header: o) bitAnd: H_REMEMBERED) = 0]]) ifTrue: [self remember: o]
! !

!GarbageCollector methodsFor: 'roots'!
forEachRoot: fn
	"The VM's roots: the variables holding oops (through a copy in memory, so fn gets pointers to them), the temporary roots, the pushed roots and the interpreter's frames."
	<function>
	| r |
	r := self local: 'oop[6]'.
	r at: 0 put: memory specialsOop.
	r at: 1 put: interpreter activeCtx.
	r at: 2 put: scheduler lastPreempted.
	r at: 3 put: scheduler allocSampleClass.
	r at: 4 put: interpreter primResult.
	r at: 5 put: interpreter resendSelector.
	0 to: 5 do: [:i | fn call: r + i].
	memory specialsOop: (r at: 0).
	interpreter activeCtx: (r at: 1).
	scheduler lastPreempted: (r at: 2).
	scheduler allocSampleClass: (r at: 3).
	interpreter primResult: (r at: 4).
	interpreter resendSelector: (r at: 5).
	0 to: 3 do: [:i | fn call: interpreter tmpRoots + i].
	0 to: memory rootCount - 1 do: [:i | fn call: (memory rootAt: i)].
	interpreter roots: fn
! !

!GarbageCollector methodsFor: 'verification'!
markStartsFrom: lo to: hi
	<function>
	| p k |
	p := lo.
	[p < hi] whileTrue: [
		k := (p - vlo) quo: 8.
		startBits at: (k quo: 8) put: ((startBits at: (k quo: 8)) bitOr: 1 << (k rem: 8)) asUInt8.
		p := p + (self objBytes: p)]
!
validRef: v
	<function>
	| inOld inSurv inEden k |
	(self isPtr: v) ifFalse: [^true].
	inOld := v >= oldLo and: [v < oldTop].
	inSurv := v >= survLo and: [v < survTop].
	inEden := v >= edenLo and: [v < self edenTop].
	inEden ifTrue: [^true].
	(inOld or: [inSurv]) ifFalse: [^false].
	k := (v - vlo) quo: 8.
	^((startBits at: (k quo: 8)) bitAnd: 1 << (k rem: 8)) ~= 0
!
verifySpaceFrom: lo to: hi old: isOld
	<function>
	| p young v |
	p := lo.
	[p < hi] whileTrue: [
		((self header: p) bitAnd: H_FORWARDED) ~= 0
			ifTrue: [
				"a forwarder: its target is valid, remembered if young and the forwarder old"
				v := self rawClass: p.
				((self formatOf: p) = F_FORWARDER and: [(v bitAnd: 7) = FWD_TAG and: [self validRef: (v bitClear: FWD_TAG)]]) ifFalse: [self fatal: 'verify: forwarded object %p' with: (self ptr: p)].
				young := self isYoung: (v bitClear: FWD_TAG)]
			ifFalse: [
				((self isPtr: (self rawClass: p)) and: [self validRef: (self rawClass: p)]) ifFalse: [self fatal: 'verify: bad class in %p' with: (self ptr: p)].
				young := self isYoung: (self rawClass: p).
				(self fmtHasPointers: (self formatOf: p)) ifTrue: [
					0 to: (self numSlots: p) asInt64 - 1 do: [:i |
						v := (self slotsOf: p) at: i.
						(self validRef: v) ifFalse: [self fatal: 'verify: bad slot in %p: %p' with: (self ptr: p) with: (self ptr: v)].
						((self isPtr: v) and: [self isYoung: v]) ifTrue: [young := true]]]].
		(isOld and: [young and: [((self header: p) bitAnd: H_REMEMBERED) = 0]]) ifTrue: [
			self fatal: 'verify: unremembered old object %p' with: (self ptr: p)].
		p := p + (self objBytes: p)]
!
verifyHeap
	<function>
	| lo hi n |
	lo := oldLo < youngLo ifTrue: [oldLo] ifFalse: [youngLo].
	hi := oldTop > youngHi ifTrue: [oldTop] ifFalse: [youngHi].
	vlo := lo.
	n := ((hi - lo) quo: 64) + 1.
	startBits := self cCoerce: (libc calloc: n size: 1) to: 'uint8_t *'.
	startBits isNull ifTrue: [self fatal: 'verify: out of memory'].
	self markStartsFrom: oldLo to: oldTop.
	self markStartsFrom: survLo to: survTop.
	self verifySpaceFrom: oldLo to: oldTop old: true.
	self verifySpaceFrom: survLo to: survTop old: false.
	((self validRef: memory specialsOop) and: [self validRef: interpreter activeCtx]) ifFalse: [self fatal: 'verify: bad root'].
	(interpreter framesValid: (self functionPointer: #validRef:)) ifFalse: [self fatal: 'verify: bad frame slot'].
	(jit headersValid: (self functionPointer: #validRef:)) ifFalse: [self fatal: 'verify: bad compiled method'].
	libc free: startBits
!
afterGC
	<function>
	verify < 0 ifTrue: [verify := (libc getenv: 'SAMALTAK_VERIFY_GC') notNull ifTrue: [1] ifFalse: [0]].
	verify ~= 0 ifTrue: [self verifyHeap].
	gcEpoch := gcEpoch + 1.
	memory refreshSpecials.
	interpreter flushMethodCache.
	interpreter afterGC.
	jit afterGC.
	memory resetAllocLimit
! !

!GarbageCollector methodsFor: 'scavenging'!
scavCopy: o
	<function>
	| h bytes age dst |
	h := self header: o.
	(h bitAnd: H_FORWARDED) ~= 0 ifTrue: [
		dst := self rawClass: o.
		(dst bitAnd: 7) = 0 ifTrue: [^dst].
		"a forwarder (becomeForward:): references to it go to its target, which moves if young"
		dst := dst bitClear: FWD_TAG.
		(self isYoung: dst) ifTrue: [dst := self scavCopy: dst].
		self rawClass: o put: dst.
		^dst].
	bytes := self objBytes: o.
	age := (((h >> H_AGE_SHIFT) bitAnd: 3) + 1) asUInt32.
	(age >= TENURE_AGE or: [toTop + bytes > toHi])
		ifTrue: [
			dst := oldTop.
			oldTop := oldTop + bytes.
			statTenured := statTenured + bytes.
			libc memcpy: (self ptr: dst) from: (self ptr: o) size: bytes.
			self header: dst put: (h bitClear: H_GCBITS)]
		ifFalse: [
			dst := toTop.
			toTop := toTop + bytes.
			libc memcpy: (self ptr: dst) from: (self ptr: o) size: bytes.
			self header: dst put: ((h bitClear: H_GCBITS) bitOr: age asUInt64 << H_AGE_SHIFT)].
	self header: o put: (h bitOr: H_FORWARDED).
	self rawClass: o put: dst.
	^dst
!
scavRoot: p
	<function>
	| v |
	v := p value.
	((self isPtr: v) and: [self isYoung: v]) ifTrue: [p value: (self scavCopy: v)]
!
isContext: o
	<function>
	| c ctx |
	c := self rawClass: o.
	ctx := memory clsContext.
	^c = ctx or: [((self header: ctx) bitAnd: H_FORWARDED) ~= 0 and: [c = (self rawClass: ctx)]]
!
tracedSlots: o
	"Number of leading slots the collector traces. A context's slots above stackp are stale and are cleared (the interpreter writes back stackp before anything can allocate); a weak object's indexable slots are left for clearWeakSlots."
	<function>
	| f sp n live |
	f := self formatOf: o.
	(self fmtHasPointers: f) ifFalse: [^0].
	(f = F_FIXVAR and: [self isContext: o]) ifTrue: [
		sp := (self slotsOf: o) at: CTX_STACKP.
		n := self numSlots: o.
		((self isInt: sp) not or: [(self intVal: sp) < 0 or: [(self intVal: sp) > (n - CTX_FIXED) asInt64]]) ifTrue: [^n].
		live := (CTX_FIXED + (self intVal: sp)) asUInt32.
		live to: n asInt64 - 1 do: [:i | (self slotsOf: o) at: i put: memory nilOop].
		^live].
	f ~= F_WEAK ifTrue: [^self numSlots: o].
	weakCount = weakCap ifTrue: [
		weakCap := weakCap = 0 ifTrue: [256] ifFalse: [weakCap * 2].
		weakList := self cCoerce: (libc realloc: weakList size: weakCap * 8) to: 'oop *'.
		weakList isNull ifTrue: [self fatal: 'out of memory growing the weak object list to %zu entries' with: weakCap]].
	weakList at: weakCount put: o.
	weakCount := weakCount + 1.
	^memory fixedFields: o
!
refersToYoung: o
	<function>
	| v |
	(self isYoung: (self rawClass: o)) ifTrue: [^true].
	0 to: (self numSlots: o) asInt64 - 1 do: [:i |
		v := (self slotsOf: o) at: i.
		((self isPtr: v) and: [self isYoung: v]) ifTrue: [^true]].
	^false
!
clearWeakSlots: isDead
	"isDead answers whether *v was not reached, updating *v to its new address otherwise."
	<function>
	| nl w s |
	nl := memory nilOop.
	0 to: weakCount asInt64 - 1 do: [:k |
		w := weakList at: k.
		s := self slotsOf: w.
		(memory fixedFields: w) to: (self numSlots: w) asInt64 - 1 do: [:i |
			((self isPtr: (s at: i)) and: [(s at: i) ~= 0]) ifTrue: [
				(isDead call: s + i) ifTrue: [
					s at: i put: nl.
					statWeakCleared := statWeakCleared + 1.
					finalizationPending := true]]]].
	finalizationPending ifTrue: [scheduler requestInterruptCheck]
!
scavDead: v
	<function>
	| c |
	((self isYoung: v value) not or: [v value >= toLo and: [v value < toHi]]) ifTrue: [^false].
	((self header: v value) bitAnd: H_FORWARDED) = 0 ifTrue: [^true].
	c := self rawClass: v value.
	(c bitAnd: 7) ~= 0 ifTrue: [
		"a forwarder only weak references reached: its target, if that lives"
		v value: (c bitClear: FWD_TAG).
		^self scavDead: v].
	v value: c.
	^false
!
scavScan: o
	"Copy young referents of o; answer whether o still refers to young objects (weak slots excluded)."
	<function>
	| young c s v |
	young := false.
	c := self rawClass: o.
	((self header: o) bitAnd: H_FORWARDED) ~= 0 ifTrue: [
		"an old forwarder, remembered for its young target"
		c := c bitClear: FWD_TAG.
		(self isYoung: c) ifTrue: [c := self scavCopy: c].
		self rawClass: o put: (c bitOr: FWD_TAG).
		^self isYoung: c].
	(self isYoung: c) ifTrue: [
		c := self scavCopy: c.
		self rawClass: o put: c.
		young := young or: [self isYoung: c]].
	s := self slotsOf: o.
	0 to: (self tracedSlots: o) asInt64 - 1 do: [:i |
		v := s at: i.
		((self isPtr: v) and: [self isYoung: v]) ifTrue: [
			v := self scavCopy: v.
			s at: i put: v.
			young := young or: [self isYoung: v]]].
	^young
!
scavenge
	<function>
	| t0 tenureScan kept o scan w |
	interpreter beforeGC.
	t0 := scheduler workClockHeldUs.
	statScavenges := statScavenges + 1.
	statAllocated := statAllocated + (self edenTop - edenLo).
	toLo := toTop := survOtherLo.
	toHi := survOtherHi.
	tenureScan := oldTop.
	weakCount := 0.
	self forEachRoot: (self functionPointer: #scavRoot:).
	jit youngRoots: (self functionPointer: #scavRoot:).
	kept := 0.
	0 to: remsetCount asInt64 - 1 do: [:i |
		o := remset at: i.
		self header: o put: ((self header: o) bitClear: H_REMEMBERED).
		((self scavScan: o) and: [(self formatOf: o) ~= F_WEAK]) ifTrue: [
			self header: o put: ((self header: o) bitOr: H_REMEMBERED).
			remset at: kept put: o.
			kept := kept + 1]].
	remsetCount := kept asUInt64.
	scan := toLo.
	[scan < toTop or: [tenureScan < oldTop]] whileTrue: [
		[scan < toTop] whileTrue: [
			self scavScan: scan.
			scan := scan + (self objBytes: scan)].
		[tenureScan < oldTop] whileTrue: [
			((self scavScan: tenureScan) and: [((self header: tenureScan) bitAnd: H_REMEMBERED) = 0]) ifTrue: [self remember: tenureScan].
			tenureScan := tenureScan + (self objBytes: tenureScan)]].
	self clearWeakSlots: (self functionPointer: #scavDead:).
	0 to: weakCount asInt64 - 1 do: [:k |
		w := weakList at: k.
		((self isYoung: w) not and: [((self header: w) bitAnd: H_REMEMBERED) = 0 and: [self refersToYoung: w]]) ifTrue: [self remember: w]].
	survOtherLo := survLo.
	survOtherHi := survHi.
	survLo := toLo.
	survTop := toTop.
	survHi := toHi.
	self edenTop: edenLo.
	self rememberIfOld: interpreter activeCtx.
	youngForwarders := 0.
	self afterGC.
	statScavengeUs := statScavengeUs + (scheduler workClockHeldUs - t0) asUInt64
! !

!GarbageCollector methodsFor: 'full GC'!
fullCopy: o
	<function>
	| h bytes dst |
	h := self header: o.
	(h bitAnd: H_FORWARDED) ~= 0 ifTrue: [
		dst := self rawClass: o.
		(dst bitAnd: 7) = 0 ifTrue: [^dst].
		"a forwarder (becomeForward:): references to it go to its target"
		dst := self fullCopy: (dst bitClear: FWD_TAG).
		self rawClass: o put: dst.
		^dst].
	bytes := self objBytes: o.
	dst := ftTop.
	ftTop := ftTop + bytes.
	libc memcpy: (self ptr: dst) from: (self ptr: o) size: bytes.
	self header: dst put: (h bitClear: H_GCBITS).
	self header: o put: (h bitOr: H_FORWARDED).
	self rawClass: o put: dst.
	^dst
!
fullRoot: p
	<function>
	| v |
	v := p value.
	((self isPtr: v) and: [v ~= 0]) ifTrue: [p value: (self fullCopy: v)]
!
fullDead: v
	<function>
	| c |
	((self header: v value) bitAnd: H_FORWARDED) = 0 ifTrue: [^true].
	c := self rawClass: v value.
	(c bitAnd: 7) ~= 0 ifTrue: [
		"a forwarder only weak references reached: its target, if that lives"
		v value: (c bitClear: FWD_TAG).
		^self fullDead: v].
	v value: c.
	^false
!
fullGC
	<function>
	| t0 oldUsed scan s lo hi live classSlot nl |
	interpreter beforeGC.
	t0 := scheduler workClockHeldUs.
	statFullGcs := statFullGcs + 1.
	statAllocated := statAllocated + (self edenTop - edenLo).
	oldUsed := oldTop - oldLo.
	ftTop := oldAltLo.
	weakCount := 0.
	nl := self local: 'oop'.
	nl value: memory nilOop.
	self fullRoot: nl.
	memory nilOop: nl value.
	self forEachRoot: (self functionPointer: #fullRoot:).
	jit allRoots: (self functionPointer: #fullRoot:).
	scan := oldAltLo.
	[scan < ftTop] whileTrue: [
		classSlot := self cCoerce: scan + 8 to: 'oop *'.
		self fullRoot: classSlot.
		s := self slotsOf: scan.
		0 to: (self tracedSlots: scan) asInt64 - 1 do: [:i | self fullRoot: s + i].
		scan := scan + (self objBytes: scan)].
	self clearWeakSlots: (self functionPointer: #fullDead:).
	self discard: oldLo size: oldUsed.
	lo := oldLo.
	hi := oldHi.
	oldLo := oldAltLo.
	oldHi := oldAltHi.
	oldTop := ftTop.
	oldAltLo := lo.
	oldAltHi := hi.
	self edenTop: edenLo.
	survTop := survLo.
	remsetCount := 0.
	live := oldTop - oldLo.
	oldBudget := live * 2 > MIN_BUDGET ifTrue: [live * 2] ifFalse: [MIN_BUDGET].
	oldBudget > maxHeapBytes ifTrue: [oldBudget := maxHeapBytes].
	self rememberIfOld: interpreter activeCtx.
	youngForwarders := 0.
	oldForwarders := 0.
	self afterGC.
	statFullUs := statFullUs + (scheduler workClockHeldUs - t0) asUInt64.
	live > maxHeapBytes ifTrue: [self fatal: 'out of memory (%llu MB live, limit %zu MB)' with: live >> 20 with: maxHeapBytes >> 20]
!
collectGarbage: need
	"Scavenge or full GC so that need bytes fit in eden."
	<function>
	| youngUsed oldUsed |
	youngUsed := (self edenTop - edenLo) + (survTop - survLo).
	oldUsed := oldTop - oldLo.
	oldUsed + youngUsed > oldBudget
		ifTrue: [self fullGC]
		ifFalse: [
			self scavenge.
			oldTop - oldLo > oldBudget ifTrue: [self fullGC]]
!
oldAllocTry: bytes
	"May full GC; 0 if it cannot fit in the heap limit."
	<function>
	| want p |
	bytes > maxHeapBytes ifTrue: [^0].
	(oldTop - oldLo) + bytes > oldBudget ifTrue: [
		self fullGC.
		want := 2 * ((oldTop - oldLo) + bytes).
		want > oldBudget ifTrue: [oldBudget := want < maxHeapBytes ifTrue: [want] ifFalse: [maxHeapBytes]]].
	(oldTop - oldLo) + bytes > maxHeapBytes ifTrue: [^0].
	p := oldTop.
	oldTop := oldTop + bytes.
	^p
! !

!GarbageCollector methodsFor: 'become'!
becomeRoot: p
	<function>
	p value = becomeFrom ifTrue: [p value: becomeTo]
!
forwardersExist
	"Some object is a forwarder: young ones until the next scavenge, old ones until the next full GC."
	^youngForwarders + oldForwarders ~= 0
!
forward: from to: to
	"Lazy one-way become: from becomes a forwarder to to. The frames and the VM's roots refer to to at once; any other reference when it is used (a send misses, a primitive fails and retries, ==, class and a block's receiver follow it) or when a collection copies the object holding it."
	<function>
	| h |
	h := self header: from.
	self header: from put: ((((h bitClear: H_FMT_MASK asUInt64 << H_FMT_SHIFT) bitClear: H_IMMUTABLE) bitOr: F_FORWARDER asUInt64 << H_FMT_SHIFT) bitOr: H_FORWARDED).
	self rawClass: from put: (to bitOr: FWD_TAG).
	(self isYoung: from)
		ifTrue: [youngForwarders := youngForwarders + 1]
		ifFalse: [
			oldForwarders := oldForwarders + 1.
			((self isYoung: to) and: [(h bitAnd: H_REMEMBERED) = 0]) ifTrue: [self remember: from]].
	jit forwarded: from.
	becomeFrom := from.
	becomeTo := to.
	self forEachRoot: (self functionPointer: #becomeRoot:).
	becomeFrom := memory nilOop.
	becomeTo := memory nilOop
!
becomeForward: from to: to
	"One-way become; call right after a full GC (no young objects)."
	<function>
	| p s |
	interpreter beforeGC.
	becomeFrom := from.
	becomeTo := to.
	jit becomeMethod: from.
	self forEachRoot: (self functionPointer: #becomeRoot:).
	jit allRoots: (self functionPointer: #becomeRoot:).
	p := oldLo.
	[p < oldTop] whileTrue: [
		self becomeRoot: (self cCoerce: p + 8 to: 'oop *').
		(self fmtHasPointers: (self formatOf: p)) ifTrue: [
			s := self slotsOf: p.
			0 to: (self numSlots: p) asInt64 - 1 do: [:i | (s at: i) = from ifTrue: [s at: i put: to]]].
		p := p + (self objBytes: p)].
	self afterGC
!
walkYoungSpace: fn data: data
	"fn on every object of the survivor space and of eden."
	<function>
	| p |
	p := survLo.
	[p < survTop] whileTrue: [
		fn call: p with: data.
		p := p + (self objBytes: p)].
	p := edenLo.
	[p < self edenTop] whileTrue: [
		fn call: p with: data.
		p := p + (self objBytes: p)]
!
walkOldSpace: fn data: data
	<function>
	| end p |
	end := oldTop.
	p := oldLo.
	[p < end] whileTrue: [
		fn call: p with: data.
		p := p + (self objBytes: p)]
! !
