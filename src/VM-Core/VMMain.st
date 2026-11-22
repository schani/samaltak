VMCoreModule subclass: #VMMain
	instanceVariableNames: 'headless argc argv argsStart c4Requested c4Enabled c4Moving'
	classVariableNames: ''
	package: 'VM-Core'!

VMMain comment: 'The entry point: samaltak [--c4|--c4-moving|--c4-moving-forward] [--max-heap MB] [--eden MB] [--jit MODE] [--jit-threshold N] [--jit-osr N] [--jit-opt N] [--jit-flags a,b,-c] [--jit-cache MB] image [--headless] [image arguments...].'!

!VMMain class methodsFor: 'declaring'!
declarations
	^#((headless bool) (argc int32_t) (argv 'char **') (argsStart int32_t) (c4Requested bool) (c4Enabled bool) (c4Moving bool))
! !

!VMMain methodsFor: 'accessing'!
c4Requested
	^c4Requested
!
c4Enabled
	^c4Enabled
!
c4Moving
	^c4Moving
!
headless
	^headless
!
argc
	^argc
!
argv
	^argv
!
argsStart
	^argsStart
! !

!VMMain methodsFor: 'running'!
banner
	"What the VM calls itself (primitive vmBanner)."
	<function>
	^'Samaltak VM'
!
usage
	<noreturn>
	libc fputs: 'usage: samaltak [--c4|--c4-moving|--c4-moving-forward] [--max-heap MB] [--eden MB] [--jit none|baseline|opt (default)] [--jit-threshold N] [--jit-osr N]
	[--jit-opt N] [--jit-flags [-]flag,...] [--jit-cache MB] image [--headless] [arguments...]
  --c4              experimental headless heap (Linux x86-64)
                    NO_PLATFORM=1 supports optional --jit baseline
                    C4_PLATFORM_FILES=1 allows audited file I/O; interpreter only
                    C4_PLATFORM_SDL=1 adds SDL software presentation for --eval clients; explicit --jit none
  --c4-moving       --c4 with bounded relocation of selected exact fixed-layout instances
  --c4-moving-forward  --c4-moving with exact two-slot handle forwarding; headless interpreter only
  --jit-threshold N  activations before a method is compiled (0: the first one)
  --jit-osr N        backward jumps before a running method is compiled and entered
  --jit-opt N        with --jit opt: entries and backward jumps in compiled code before a method is optimized
  --jit-flags        ablations: baseline: ic pic mega regs arith fuse float access prims blocks quick
                     barrier; opt: inline blocks prims unbox calls alloc gvn hoist live; listings: notes;
                     stress: eager deopt (-name turns one off)
' to: libc stderr.
	libc exit: 64
!
main: n argv: v
	<function>
	<var: #n type: 'int'>
	<var: #v type: 'char **'>
	| maxHeap eden i image proc ctx explicitJit movingForward |
	jit defaults.
	explicitJit := movingForward := false.
	maxHeap := (4096 << 20) asUInt64.
	eden := (16 << 20) asUInt64.
	i := 1.
	[i < n and: [((v at: i) at: 0) = $- value]] whileTrue: [
		((libc strcmp: (v at: i) with: '--max-heap') = 0 and: [i + 1 < n])
			ifTrue: [
				i := i + 1.
				maxHeap := (libc atol: (v at: i)) asUInt64 << 20]
			ifFalse: [
				(libc strcmp: (v at: i) with: '--c4') = 0
					ifTrue: [c4Requested := true]
					ifFalse: [
						((libc strcmp: (v at: i) with: '--c4-moving') = 0 or: [
							(libc strcmp: (v at: i) with: '--c4-moving-forward') = 0])
							ifTrue: [
								(libc strcmp: (v at: i) with: '--c4-moving-forward') = 0 ifTrue: [movingForward := true].
								c4Requested := c4Moving := true]
							ifFalse: [
								((libc strcmp: (v at: i) with: '--eden') = 0 and: [i + 1 < n])
									ifTrue: [
										i := i + 1.
										eden := (libc atol: (v at: i)) asUInt64 << 20]
									ifFalse: [
										(libc strcmp: (v at: i) with: '--headless') = 0
											ifTrue: [headless := true]
											ifFalse: [
												(self jitOption: v at: i asInt32 count: n)
													ifTrue: [
														(libc strcmp: (v at: i) with: '--jit') = 0 ifTrue: [explicitJit := true].
														i := i + 1]
													ifFalse: [self usage]]]]]].
		i := i + 1].
	i >= n ifTrue: [self usage].
	image := v at: i.
	argc := n.
	argv := v.
	argsStart := (i + 1) asInt32.
	i + 1 to: n - 1 do: [:k | (libc strcmp: (v at: k) with: '--headless') = 0 ifTrue: [headless := true]].
	movingForward ifTrue: [
		(c4 supported and: [c4 platformFiles not]) ifFalse: [self fatal: '--c4-moving-forward requires Linux x86-64 with NO_PLATFORM=1'].
		(explicitJit and: [jit mode ~= 0]) ifTrue: [self fatal: '--c4-moving-forward requires --jit none']].
	c4 platformSDL ifTrue: [
		c4Requested ifFalse: [self fatal: 'C4_PLATFORM_SDL=1 requires --c4 or --c4-moving'].
		(explicitJit not or: [jit mode ~= 0]) ifTrue: [self fatal: 'C4 SDL requires --jit none explicitly'].
		"Require the exact interactive command, not an --eval token in another action or its operands."
		headless ifFalse: [
			(n - i = 3 and: [(libc strcmp: (v at: i + 1) with: '--eval') = 0 and: [
				((v at: i + 2) at: 0) ~= 0 and: [(((v at: i + 2) at: 0) = $- value and: [((v at: i + 2) at: 1) = $- value]) not]]])
				ifFalse: [self fatal: 'C4 SDL requires image --eval <expression> (World is not supported)']]].
	(c4 platformFiles and: [c4 platformSDL not]) ifTrue: [
		c4Requested ifFalse: [self fatal: 'C4_PLATFORM_FILES=1 requires --c4 or --c4-moving'].
		(explicitJit and: [jit mode ~= 0]) ifTrue: [self fatal: 'C4 platform files require --jit none']].
	c4Requested ifTrue: [
		c4 supported ifFalse: [self fatal: '--c4 requires Linux x86-64 with NO_PLATFORM=1 or C4_PLATFORM_FILES=1'].
		(headless or: [c4 platformSDL]) ifFalse: [self fatal: '--c4 requires --headless'].
		(explicitJit and: [jit mode = jit optMode]) ifTrue: [self fatal: '--c4 supports only --jit none or baseline'].
		eden = 0 ifTrue: [self fatal: '--c4 requires a positive --eden threshold'].
		explicitJit ifFalse: [jit mode: 0]].
	memory memoryInit: eden maxHeap: maxHeap.
	c4Requested ifTrue: [
		(c4Moving
			ifTrue: [c4 initMoving: (self ptr: gc oldLo) capacity: maxHeap]
			ifFalse: [c4 init: (self ptr: gc oldLo) capacity: maxHeap])
				ifFalse: [self fatal: 'cannot initialize C4 heap'].
		(movingForward and: [c4 enableMovingForward not])
			ifTrue: [self fatal: 'cannot enable C4 moving forwarding'].
		c4 threshold: eden].
	imageFile loadImage: image.
	c4Requested ifTrue: [
		c4 start ifFalse: [self fatal: 'cannot start C4 worker'].
		c4Enabled := true].
	scheduler init.
	jit start.
	headless ifFalse: [platform init].
	proc := self loadRef: (memory special: SO_PROCESSOR) at: SCHED_ACTIVE.
	ctx := self loadRef: proc at: PROC_SUSPENDED.
	((self isPtr: ctx) not or: [ctx = memory nilOop]) ifTrue: [self fatal: 'image has no active context'].
	interpreter activeCtx: ctx.
	self storeRef: proc at: PROC_SUSPENDED put: memory nilOop.
	c4Enabled ifFalse: [gc rememberIfOld: ctx].
	interpreter interpret.
	^0
!
jitOption: v at: i count: n
	"--jit MODE, --jit-threshold N, --jit-osr N, --jit-opt N, --jit-flags a,b,-c or --jit-cache MB at v[i]: answer whether it is one (its value is v[i + 1])."
	<function>
	| a m |
	i + 1 < n ifFalse: [^false].
	a := v at: i + 1.
	(libc strcmp: (v at: i) with: '--jit') = 0 ifTrue: [
		m := jit modeNamed: a.
		m < 0 ifTrue: [self usage].
		jit mode: m.
		^true].
	(libc strcmp: (v at: i) with: '--jit-threshold') = 0 ifTrue: [
		jit threshold: (libc atol: a).
		^true].
	(libc strcmp: (v at: i) with: '--jit-osr') = 0 ifTrue: [
		jit osrThreshold: (libc atol: a).
		^true].
	(libc strcmp: (v at: i) with: '--jit-opt') = 0 ifTrue: [
		jit optThreshold: (libc atol: a).
		^true].
	(libc strcmp: (v at: i) with: '--jit-flags') = 0 ifTrue: [
		(jit parseFlags: a) ifFalse: [self usage].
		^true].
	(libc strcmp: (v at: i) with: '--jit-cache') = 0 ifTrue: [
		jit cacheMB: (libc atol: a).
		^true].
	^false
! !
