Object subclass: #VMConstants
	instanceVariableNames: ''
	classVariableNames: 'H_FMT_SHIFT H_FMT_MASK H_HASH_SHIFT H_HASH_MASK H_IMMUTABLE H_REMEMBERED H_AGE_SHIFT H_AGE_MASK H_FORWARDED H_GCBITS F_EMPTY F_FIXED F_VAR F_FIXVAR F_WEAK F_IMMEDIATE F_W64 F_W32 F_BYTES CLS_SPEC_SHIFT CLS_INSTSIZE_MASK VM_INT_MAX VM_INT_MIN CHAR_VALUE_MAX CM_PRIM_MASK CM_PRIM_ERROR_FLAG PRIM_ENSURE_MARKER PRIM_ONDO_MARKER PRIM_ERR_NO_MEMORY CTX_SLACK EXTERNAL_OBJECTS_SIZE SO_NIL SO_FALSE SO_TRUE SO_PROCESSOR SO_SMALLTALK SO_SMALLINTEGER SO_CHARACTER SO_SMALLFLOAT SO_BOXEDFLOAT SO_ARRAY SO_BYTEARRAY SO_BYTESTRING SO_BYTESYMBOL SO_WIDESTRING SO_COMPILEDMETHOD SO_CONTEXT SO_BLOCKCLOSURE SO_PROCESS SO_SEMAPHORE SO_POINT SO_LARGEPOS SO_LARGENEG SO_MESSAGE SO_ASSOCIATION SO_BITMAP SO_SEL_DNU SO_SEL_MUSTBEBOOLEAN SO_SEL_CANNOTRETURN SO_SEL_ABOUTTORETURN SO_SEL_ATTEMPTTOASSIGN SO_SPECIAL_SELECTORS SO_TIMER_SEMAPHORE SO_EXTERNAL_OBJECTS SO_WIDESYMBOL SO_SEL_PRIMITIVEFAILED SO_FINALIZATION_SEMAPHORE SO_SEL_STACKOVERFLOW SO_INTERVAL SO_COUNT BEH_SUPERCLASS BEH_METHODDICT BEH_FORMAT CD_INSTVARS CD_ORGANIZATION CLS_SUBCLASSES CLS_NAME CLS_CLASSPOOL META_THISCLASS MD_TALLY MD_KEYS MD_VALUES CM_SELECTOR CM_CLASS CM_LITERALS CM_BYTECODES CM_NUMARGS CM_NUMTEMPS CM_FRAMESIZE CM_PRIMITIVE CTX_SENDER CTX_PC CTX_STACKP CTX_METHOD CTX_CLOSURE CTX_RECEIVER CTX_FIXED BC_OUTER BC_STARTPC BC_NUMARGS BC_NUMTEMPS BC_FRAMESIZE PROC_NEXT PROC_SUSPENDED PROC_PRIORITY PROC_MYLIST PROC_NAME PROC_CPUTIME SCHED_LISTS SCHED_ACTIVE LL_FIRST LL_LAST SEM_EXCESS ASSOC_KEY ASSOC_VALUE MSG_SELECTOR MSG_ARGS'
	package: 'Kernel-Objects'!

VMConstants comment: 'I am the single definition of the object model the VM and the image share: header bits, object formats, the special objects array, the VM-known instance variables, marker primitives and primitive error codes. My class variables are the C names; the VM (written in Lowtalk, docs/lowtalk.md) inherits them, and the translator writes them as #defines. The image reads them through my class-side accessors; special-object indices (so…) answer 1-based indices, ready for at:.'!

!VMConstants class methodsFor: 'class initialization'!
initialize
	"header word 0: numSlots (bits 0-31), format, identity hash, immutable bit, GC bits"
	H_FMT_SHIFT := 32.
	H_FMT_MASK := 16r1F.
	H_HASH_SHIFT := 37.
	H_HASH_MASK := 16r3FFFFF.
	H_IMMUTABLE := 1 << 59.
	H_REMEMBERED := 1 << 60.
	H_AGE_SHIFT := 61.
	H_AGE_MASK := 3 << 61.
	H_FORWARDED := 1 << 63.
	H_GCBITS := (H_REMEMBERED bitOr: H_AGE_MASK) bitOr: H_FORWARDED.
	"object formats; F_W32 + unused 32-bit units (0-1), F_BYTES + unused bytes (0-7)"
	F_EMPTY := 0.
	F_FIXED := 1.
	F_VAR := 2.
	F_FIXVAR := 3.
	F_WEAK := 4.
	F_IMMEDIATE := 7.
	F_W64 := 9.
	F_W32 := 10.
	F_BYTES := 16.
	"class format word: (instSpec << CLS_SPEC_SHIFT) | instSize"
	CLS_SPEC_SHIFT := 16.
	CLS_INSTSIZE_MASK := 16rFFFF.
	"SmallInteger range"
	VM_INT_MAX := 16r3FFFFFFFFFFFFFFF.
	VM_INT_MIN := VM_INT_MAX negated - 1.
	"Character values: the Unicode code points (surrogates included)"
	CHAR_VALUE_MAX := 16r10FFFF.
	"CompiledMethod primitive slot: primitive number | CM_PRIM_ERROR_FLAG when the method declares error: ec; marker primitives (always fail; Smalltalk finds these contexts by method primitive); primitive error codes"
	CM_PRIM_MASK := 16rFFFF.
	CM_PRIM_ERROR_FLAG := 16r10000.
	PRIM_ENSURE_MARKER := 198.
	PRIM_ONDO_MARKER := 199.
	PRIM_ERR_NO_MEMORY := 1.
	"extra stack slots above frameSize for VM-synthesized sends; slots of the externalObjects Array"
	CTX_SLACK := 2.
	EXTERNAL_OBJECTS_SIZE := 64.
	"the special objects array, 0-based (SO_COUNT: its size)"
	SO_NIL := 0.
	SO_FALSE := 1.
	SO_TRUE := 2.
	SO_PROCESSOR := 3.
	SO_SMALLTALK := 4.
	SO_SMALLINTEGER := 5.
	SO_CHARACTER := 6.
	SO_SMALLFLOAT := 7.
	SO_BOXEDFLOAT := 8.
	SO_ARRAY := 9.
	SO_BYTEARRAY := 10.
	SO_BYTESTRING := 11.
	SO_BYTESYMBOL := 12.
	SO_WIDESTRING := 13.
	SO_COMPILEDMETHOD := 14.
	SO_CONTEXT := 15.
	SO_BLOCKCLOSURE := 16.
	SO_PROCESS := 17.
	SO_SEMAPHORE := 18.
	SO_POINT := 19.
	SO_LARGEPOS := 20.
	SO_LARGENEG := 21.
	SO_MESSAGE := 22.
	SO_ASSOCIATION := 23.
	SO_BITMAP := 24.
	SO_SEL_DNU := 25.
	SO_SEL_MUSTBEBOOLEAN := 26.
	SO_SEL_CANNOTRETURN := 27.
	SO_SEL_ABOUTTORETURN := 28.
	SO_SEL_ATTEMPTTOASSIGN := 29.
	SO_SPECIAL_SELECTORS := 30.
	SO_TIMER_SEMAPHORE := 31.
	SO_EXTERNAL_OBJECTS := 32.
	SO_WIDESYMBOL := 33.
	SO_SEL_PRIMITIVEFAILED := 34.
	SO_FINALIZATION_SEMAPHORE := 35.
	SO_SEL_STACKOVERFLOW := 36.
	SO_INTERVAL := 37.
	SO_COUNT := 38.
	"the VM-known instance variables (slot indices, 0-based)"
	"Behavior, ClassDescription, Class, Metaclass"
	BEH_SUPERCLASS := 0.
	BEH_METHODDICT := 1.
	BEH_FORMAT := 2.
	CD_INSTVARS := 3.
	CD_ORGANIZATION := 4.
	CLS_SUBCLASSES := 5.
	CLS_NAME := 6.
	CLS_CLASSPOOL := 7.
	META_THISCLASS := 5.
	"MethodDictionary"
	MD_TALLY := 0.
	MD_KEYS := 1.
	MD_VALUES := 2.
	"CompiledMethod"
	CM_SELECTOR := 0.
	CM_CLASS := 1.
	CM_LITERALS := 2.
	CM_BYTECODES := 3.
	CM_NUMARGS := 4.
	CM_NUMTEMPS := 5.
	CM_FRAMESIZE := 6.
	CM_PRIMITIVE := 7.
	"Context (CTX_FIXED: the first indexable slot)"
	CTX_SENDER := 0.
	CTX_PC := 1.
	CTX_STACKP := 2.
	CTX_METHOD := 3.
	CTX_CLOSURE := 4.
	CTX_RECEIVER := 5.
	CTX_FIXED := 6.
	"BlockClosure"
	BC_OUTER := 0.
	BC_STARTPC := 1.
	BC_NUMARGS := 2.
	BC_NUMTEMPS := 3.
	BC_FRAMESIZE := 4.
	"Process"
	PROC_NEXT := 0.
	PROC_SUSPENDED := 1.
	PROC_PRIORITY := 2.
	PROC_MYLIST := 3.
	PROC_NAME := 4.
	PROC_CPUTIME := 5.
	"ProcessorScheduler, LinkedList, Semaphore"
	SCHED_LISTS := 0.
	SCHED_ACTIVE := 1.
	LL_FIRST := 0.
	LL_LAST := 1.
	SEM_EXCESS := 2.
	"Association, Message"
	ASSOC_KEY := 0.
	ASSOC_VALUE := 1.
	MSG_SELECTOR := 0.
	MSG_ARGS := 1
! !

!VMConstants class methodsFor: 'accessing'!
fEmpty
	^F_EMPTY
!
fFixed
	^F_FIXED
!
fVar
	^F_VAR
!
fFixvar
	^F_FIXVAR
!
fWeak
	^F_WEAK
!
fImmediate
	^F_IMMEDIATE
!
fW64
	^F_W64
!
fW32
	^F_W32
!
fBytes
	^F_BYTES
!
clsSpecShift
	^CLS_SPEC_SHIFT
!
clsInstsizeMask
	^CLS_INSTSIZE_MASK
!
cmPrimMask
	^CM_PRIM_MASK
!
cmPrimErrorFlag
	^CM_PRIM_ERROR_FLAG
!
primEnsureMarker
	^PRIM_ENSURE_MARKER
!
primOndoMarker
	^PRIM_ONDO_MARKER
!
primErrNoMemory
	^PRIM_ERR_NO_MEMORY
!
ctxSlack
	^CTX_SLACK
!
soFinalizationSemaphore
	^SO_FINALIZATION_SEMAPHORE + 1
!
soExternalObjects
	^SO_EXTERNAL_OBJECTS + 1
! !
