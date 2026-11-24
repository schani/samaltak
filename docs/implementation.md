# Samaltak implementation spec

The contract between the VM (written in Lowtalk, docs/lowtalk.md, and translated to C), the image builder and the Smalltalk image. `docs/design.md` says *why*; this says *exactly what*. Change this file first, then code.

## Layout

```
src/                Smalltalk sources, one directory per package; src/packages.txt = load order + layer
  VM-Core/          the VM in Lowtalk: object memory, GC, interpreter, scheduler, primitives, image I/O, main
  VM-Platform/      the platform layer in Lowtalk: SDL3 window/input, SDL_GPU, files, sockets, ptys, clipboard
  VM-Lowtalk/       Lowtalk's runtime: C types, simulated memory, modules, structs, C library bindings, VMSimulation
  VM-Translator/    VMTranslator: Lowtalk → C
  VM-ImageBuilder/  ImageBuilder: a source tree → a seed image
vm/gen/             the C translated from VM-Core, VM-Jit and VM-Platform (checked in; make translate regenerates it)
vm/Makefile         → vm/build/samaltak (profile-guided with vm/pgo.profdata)
boot/seed.image     the checked-in seed image that runs ImageBuilder (boot/build-image.sh)
st80/               the VM Simulator's Smalltalk-80 guest: links to src/'s Kernel and Compiler packages, and ST80-UI
fonts/              TTF files (OFL; Twemoji: Apache-2.0 and CC-BY-4.0, twemoji-LICENSE.md)
tests/              integration tests (headless Smalltalk runs, samaltak-ctl UI scenarios)
tools/              samaltak-ctl (Node ≥18, no deps), video scripts
build/              generated, git-ignored
```

`make` (top level) builds the VM, the seed image, then the full image:

1. `boot/build-image.sh src build/seed.image` — the checked-in `boot/seed.image` files in the current sources of the image builder (VM-Lowtalk, VM-Core, VM-Platform, VM-Translator, VM-ImageBuilder, VMConstants, the compiler's code generator) and runs `ImageBuilder buildFrom: 'src' to: …`, which compiles every method with the Smalltalk compiler and creates the objects with the VM's ObjectMemory, simulated. Builds are reproducible byte for byte.
2. `vm/build/samaltak build/seed.image --headless --stage2 build/samaltak.image` — the image initializes its classes, **recompiles every method with the Smalltalk compiler**, loads the fonts into the image and rasterizes their atlases, builds the World, and snapshots.
3. `make translate` — after changing VM-Core or VM-Platform: the image translates them into `vm/gen` (`VMTranslator generateVM`); then `make` rebuilds the VM.
4. `make test` — everything, from a fresh image: `test-vm` (mini kernel, also under the GC verifier), the check that `vm/gen` is what the sources translate to (`tests/vm/gen_test.sh`), the image builder's layering check (`tests/boot/layering_test.sh`), the full Smalltalk suite (`tests/st_suite.sh`, incl. the compiler fixpoint: recompiling the stage-2 image yields identical methods), Tests-Kernel and Tests-Compiler again with a 1 MB eden under the heap verifier (`SAMALTAK_VERIFY_GC=1 --eden 1`), and once more, with Tests-VM, with every object a scavenge copies that `becomeForward:` would forward lazily a forwarder (`SAMALTAK_FORWARD_STRESS=1`), the suite again under the JITs (`make test-jit`: `--jit baseline` and `--jit opt` with `--jit-threshold 0`, opt also with deoptimization stress, Tests-Kernel also with a 1 MB code cache), the platform tests (`vm/platform`: C and Smalltalk), and the samaltak-ctl scenarios (`tests/remote/cli_test.sh` headless, `tests/tools/desktop_test.sh` in a hidden window, `tests/tools/snapshot_test.sh`: save with a Debugger mid-step, relaunch, step on; `tests/tools/reboot_test.sh`: edit the VM, rebuild and reboot, docs/lowtalk.md). It fails on any failure, on a skipped test, and on a VM built without the platform layer.

Tests (`TestCase`, System-Support) must pass on a loaded machine and with several runs at once: each runs in its own Process with a time limit; they wait for asynchronous effects with `waitFor:timeout:` (polls, answers false at the timeout; asserted) instead of fixed sleeps, start Processes with `fork:` / `fork:named:at:` (or register them with `track:`), which are terminated after `tearDown`, and write files only into `scratchDirectory` (a fresh `/tmp/samaltak-<class>-<UTC µs>-<n>`, made with mkdir so concurrent runs never share it, deleted after the test).

## Object memory

64-bit words, little-endian. An *oop* is a tagged 64-bit value:

| low bits | kind | value |
|---|---|---|
| `…1` | SmallInteger | `(int64)oop >> 1` (63-bit signed) |
| `…010` | Character | code point = `oop >> 3` |
| `…100` | SmallFloat64 | Spur encoding (below) |
| `…000` | object pointer | 8-byte aligned address, never 0 |

**SmallFloat64** (Spur): let `b` be the IEEE bits. If `b` is ±0.0: `oop = (sign << 3) | 4` (sign in bit 3). Else `e = (b >> 52) & 0x7FF`; immediate iff `896 < e < 1151`; then `r = rotl64(b, 1) - (896 << 53)`; `oop = (r << 3) | 4`. Decode: `r = oop >> 3`; if `r <= 1` → ±0.0 (sign = r); else `b = rotr64(r + (896 << 53), 1)`. Other doubles (inf, NaN, huge, tiny) are **BoxedFloat64** objects (format 9, one 64-bit slot of IEEE bits). Float primitives accept both and return immediate when possible.

**Object header** — two words before the body:

word 0:

| bits | field |
|---|---|
| 0–31 | `numSlots`: body size in 8-byte words |
| 32–36 | `format` |
| 37–58 | `identityHash` (22 bits, assigned at allocation, never 0, never derived from the address) |
| 59 | immutable |
| 60–62 | GC private (marks, age, remembered) |
| 63 | forwarded: while a collection copies, the object's copy is in word 1; outside one, the object is a forwarder (below) |

word 1: class oop.

**Formats**

| format | meaning |
|---|---|
| 0 | no fields |
| 1 | fixed pointer fields |
| 2 | indexable pointers, no fixed fields (Array) |
| 3 | fixed + indexable pointers (Context) |
| 4 | weak: fixed fields strong, indexable slots weak (see Weak references) |
| 5 | forwarder (`becomeForward:`, below) |
| 7 | immediate class marker (SmallInteger, Character, SmallFloat64: no instances) |
| 9 | 64-bit indexable (BoxedFloat64) |
| 10–11 | 32-bit indexable; `format - 10` unused trailing 32-bit units (WideString, Bitmap) |
| 16–23 | 8-bit indexable; `format - 16` unused trailing bytes (ByteString, ByteSymbol, ByteArray, LargeInts) |

Element count: bytes = `numSlots*8 - (format-16)`; 32-bit units = `numSlots*2 - (format-10)`.

**Class format** (a Behavior's `format` slot, SmallInteger): `(instSpec << 16) | instSize` where `instSpec ∈ {0,1,2,3,4,7,9,10,16}` and `instSize` = fixed field count. `basicNew:` derives the object format (adding unused-unit counts).

**Pointer discipline** (keeps a pauseless, moving GC possible — see design.md): every heap pointer load goes through `loadRef:at:`, every pointer store through `storeRef:at:put:` (VMCoreModule); VM code never holds a raw oop across an allocation or safepoint unless it is registered as a root; identity hash lives in the header.

**GC**: generational. Eden (bump allocation) + survivor semispaces, scavenged by copying with a remembered set maintained by `store_ref`; tenured objects in old space; full GC when old space exceeds its budget (implementation's choice: copying or mark-compact). Objects larger than an eighth of eden are allocated directly in old space. Contexts (flushed frames) are ordinary objects allocated in eden; most die there. A context's slots above `stackp` are not roots: the collector sets them to nil, so code that builds or grows a context must raise `stackp` before storing into the new slots.

**Weak references**: the indexable slots of a format-4 object do not keep their referents alive (its fixed fields do). After tracing, a scavenge sets to nil every weak slot whose young referent was not reached (old referents survive a scavenge), and a full GC every weak slot whose referent was not reached; weak objects stay in the remembered set while they refer to young objects. If any slot was cleared, the VM signals the finalization Semaphore (special object 35) at the next safepoint. Smalltalk: `WeakArray` (Kernel-Collections); `WeakRegistry` (System-Support) maps objects to executors, run (`finalize`, or `value` for a Block) by the 'finalization' Process at priority 50; an executor must not reference its object. GPU resources and fences, FileStreams, RemoteSockets and PseudoTerminals register themselves and release their platform handle when collected unreleased.

## Image file

```
offset  size  field
0       8     magic "SAMALTK1"
8       8     version = 1
16      8     header size = 64
24      8     heap bytes (N)
32      8     base address the heap was written at (B, nonzero, 8-aligned)
40      8     special objects array oop (an address in [B, B+N))
48      8     identity hash seed (VM continues from here)
56      8     String hash the hashed collections are by: 1 words of 8 bytes, 0 FNV-1a (images saved before the other)
64      N     objects, contiguous, each: 2 header words + numSlots words
```

The loader places the heap in old space and adds `(newBase - B)` to every pointer oop (class words and pointer-format slots). The image builder writes with B = where the simulated old space was. The VM hashes Strings for an image as its String hash field says (`ObjectMemory>>wordHash`), and saves it so: an image from before the word hash keeps FNV-1a (its optimized code calls the primitive for `hash`); the image builder writes 1.

## Special objects array

An Array (format 2). Indices (0-based) the VM relies on:

| # | object | # | object |
|---|---|---|---|
| 0 | nil | 17 | Process class |
| 1 | false | 18 | Semaphore class |
| 2 | true | 19 | Point class |
| 3 | Processor (the ProcessorScheduler) | 20 | LargePositiveInteger class |
| 4 | Smalltalk (SystemDictionary) | 21 | LargeNegativeInteger class |
| 5 | SmallInteger class | 22 | Message class |
| 6 | Character class | 23 | Association class |
| 7 | SmallFloat64 class | 24 | Bitmap class (32-bit) |
| 8 | BoxedFloat64 class | 25 | #doesNotUnderstand: |
| 9 | Array class | 26 | #mustBeBoolean |
| 10 | ByteArray class | 27 | #cannotReturn: |
| 11 | ByteString class | 28 | #aboutToReturn:through: |
| 12 | ByteSymbol class | 29 | #attemptToAssign:withIndex: |
| 13 | WideString class | 30 | specialSelectors (Array, below) |
| 14 | CompiledMethod class | 31 | timer Semaphore (signaled at the requested ms) |
| 15 | Context class | 32 | externalObjects (Array; VM signals Semaphores by index; `Smalltalk vm registerExternalSemaphore:` / `unregisterExternalSemaphore:` manage the slots, growing the Array when full) |
| 16 | BlockClosure class | 33 | WideSymbol class |
| | | 34 | #primitiveFailed (answered by `tryPrimitiveWithArgs`) |
| | | 35 | finalization Semaphore (signaled after a GC cleared weak slots) |
| | | 36 | #stackOverflow: |

**Constants, defined once.** The special-object indices, object formats, header bits, the class format word's shift and mask, the VM-known instance variable indices, the CompiledMethod primitive mask and error flag, the marker primitive numbers and `CTX_SLACK` are class variables of `VMConstants` (Kernel-Objects), set in its `initialize`, in their C spelling (`SO_EXTERNAL_OBJECTS`, `F_W32`). The VM's Lowtalk modules inherit them, the translator writes them into `vm/gen/samaltak.h` as `#define`s, the image builder uses them, and the image reads the ones it needs through `VMConstants`' class-side accessors (`VMConstants fW32`; `so…` indices are 1-based for `at:`).

`specialSelectors` is an Array of 32 selectors, in bytecode order (`0xA0 + i`):
`+ - < > <= >= = ~= * / \\ @ bitShift: // bitAnd: bitOr: at: at:put: size == ~~ value value: isNil notNil new new: x y class value:value: max:` (the VM knows each one's arg count from the selector). `==` and `~~` never send. Others have VM fast paths (SmallInteger/Float arithmetic and comparisons, `at:`/`at:put:`/`size` on Arrays, ByteArrays and Strings, `value`/`value:` on BlockClosures, `x`/`y` on Points, `class`) and otherwise do a normal send.

## VM-known class layouts (fixed fields, in order)

| class | fields |
|---|---|
| Behavior | superclass methodDict format |
| ClassDescription | (Behavior) instanceVariables organization |
| Class | (ClassDescription) subclasses name classPool sharedPools package comment |
| Metaclass | (ClassDescription) thisClass |
| MethodDictionary | tally keys values — `keys`/`values` Arrays, capacity a power of two, slot = `identityHash(selector) & (cap-1)`, linear probing, nil key = empty |
| CompiledMethod | selector methodClass literals bytecodes numArgs numTemps frameSize primitive source category pragmas sourceMap properties |
| Context (format 3) | sender pc stackp method closureOrNil receiver, then indexable: args, temps, stack |
| BlockClosure | outerContext startpc numArgs numTemps frameSize |
| Process | nextLink suspendedContext priority myList name cpuTime (µs, SmallInteger, VM-maintained) |
| ProcessorScheduler | quiescentProcessLists (Array of 80 LinkedLists, index = priority) activeProcess |
| LinkedList | firstLink lastLink |
| Semaphore | firstLink lastLink excessSignals |
| Association | key value |
| Message | selector arguments |
| Point | x y |

Other kernel classes are Smalltalk's business. `numTemps` excludes args. `frameSize` = numArgs + numTemps + max stack depth.

## Method execution

**Smalltalk sees every activation as a heap Context**, inspectable and modifiable at any safepoint (debugger, simulator, exceptions, `jump`, `terminateTo:`). The VM runs most activations in **frames** instead: a C stack of argument/temp/operand slots plus one frame record (method, closure, slot base, saved ip and stack depth) per activation, above a base Context (`active_ctx`). A send pushes a frame, its receiver and arguments become the callee's slots in place, and a return pops it; no object is allocated. A frame's receiver sits just below its slots, as `receiver` does in a Context.

A frame gets its Context lazily, by **marriage** (as in Cog): creating a closure in it (the closure's `outerContext`), `thisContext` (the top frame), reading the `sender` of a married Context (the caller's frame; frame 0's sender is `active_ctx`, so senders are married one read at a time), and the primitives that answer handler and unwind contexts. The Context, of the size a flush would give it, has `method`, `closureOrNil` and `receiver` set and `sender` the frame's index (a SmallInteger, the mark of a married Context); pc, stackp, temps and stack stay in the frame, and the VM answers for them. Context's methods (and its subclasses') read `sender`, `pc` and `stackp` with the long-form push 0x81 and store into any instance variable with 0x88, the compiler's forms for them: on a married Context 0x81 answers from the frame and 0x88 flushes first. `at:`, `at:put:` (hence `tempAt:`, `tempAt:put:`), `instVarAt:` and `instVarAt:put:` reach the frame's slots, nil above its stack pointer (a store there or into a fixed field flushes first); `shallowCopy` fails for a married Context, whose fallback copies what they answer. Outer temp bytecodes reaching a married Context use the frame's slots. When the frame returns or is unwound, its Context becomes an ordinary dead Context holding the frame's final slots, which blocks that outlive the activation keep using. A non-local return to a married home pops the frames down to it unless one of them is an `ensureMarker` activation: then the block's Context sends `aboutToReturn:through:` from its frame.

Exception handling and unwinding walk the frames, then the Contexts below them, in primitives (Pharo's numbers): `nextHandlerContext` (197, the first `on:do:` activation among a Context's senders) and `findNextUnwindContextUpTo:` (195, the first `ensure:`/`ifCurtailed:` one) answer it married if it is a frame; `terminateTo:` (196) sent to the top frame's Context moves that frame down to just above its target's frame (or to frame 0, the target becoming `active_ctx`), widowing the frames in between, and fails in other cases, where Smalltalk does it. The exception system resumes the activation that waits for the answer (on:do:'s protected block, signal's handler search, outer's pass) rather than returning from it, so it never asks for a sender that may be an optimized frame.

Frames are **flushed** into Contexts only where a Context must stand on its own: a process switch (a suspended process is always a chain of Contexts), a snapshot, C-stack overflow and the stack-depth check, a store that may change how a married Context continues (above; `restart`, hence `retry`, and `jump` store so), `changeClassTo:`, `becomeForward:` of an object an optimized frame holds or that it forwards eagerly, `tryPrimitive` of one, Smalltalk looking into an optimized frame (docs/jit.md), a return into a dead base Context, and the `terminateTo:` cases its primitive leaves to Smalltalk. Then **all** frames are flushed, bottom up, into Contexts with the right `sender` chain, pc and stack (a married frame into its own Context); the stack is emptied and the top activation continues in its Context. When there are no frames the interpreter executes `active_ctx` itself, caching its ip/sp in registers and writing them back before any send, primitive, allocation or context switch, so a non-active Context is always coherent; a send from it pushes a frame. Smalltalk thus never sees a frame; a flushed activation goes back into a frame only under a JIT, which marries a Context it continues in machine code to a new bottom frame (its sender becomes the base). GC roots are precise: the frame records and the live C-stack slots. Frame records hold raw pointers into their methods' bytecodes and literals, converted to offsets while a GC moves objects.

Under a JIT (`--jit`, docs/jit.md) compiled methods run the same frames: a frame's `code` names its machine code, which keeps the frame's pc and sp current at safepoints; the interpreter enters it when it activates such a method, returns into such a frame or jumps back in one, and machine code leaves to the interpreter at any bytecode.

The interpreter dispatches with computed goto. Sends use a monomorphic inline cache per send site (direct-mapped by the site's address) backed by the global (class, selector) cache; sends whose selector the site does not determine (`doesNotUnderstand:`, `perform:` resends, `cannotReturn:`, `aboutToReturn:through:`) use the global cache. A cached method that only answers an instance variable, a constant or self, or only stores its arguments into instance variables, runs without a frame (sends stay safepoints). Leaf primitives (no allocation, process switch or Context access) are called without writing back the registers. The SmallInteger/Float special selectors have inline paths; a comparison followed by a conditional jump branches directly, an arithmetic result followed by a pop-store goes straight into the temp, and `push 1` / push of a small integer constant followed by `+ - < > <= >=` on SmallIntegers execute as one step. Methods keep their bytecodes: these are decisions at dispatch time.

- `pc` is a 0-based index into `method bytecodes` (a ByteArray), or nil once the context has returned ("dead").
- `stackp` is the count of used indexable slots (args + temps + stack).
- On return the VM sets the returning context's `pc` and `sender` to nil.
- **Method activation** (as Smalltalk sees it): an activation of `frameSize` (+ `CTX_SLACK`) slots, receiver and args, temps nil, pc 0, stackp = numArgs + numTemps; flushed into a Context of that size.
- **Block activation** (`value…`): `method = closure outerContext method`, `receiver = outerContext receiver`, `closureOrNil = closure`, pc = `startpc`, args then `numTemps` nil temps.
- **Primitives**: a method whose `primitive` ≠ 0 runs its primitive first; on success it returns without a context; on failure the method body runs (with an optional error code in the first temp, if the method declares `<primitive: … error: ec>`). The marker primitives `ensureMarker` (`ensure:`/`ifCurtailed:`, `PRIM_ENSURE_MARKER`) and `onDoMarker` (`on:do:`, `PRIM_ONDO_MARKER`) always fail; the context primitives and Smalltalk find those activations by `method primitive`.
- **Non-local return** (`^` in a block): home = follow `closureOrNil outerContext` until a context with `closureOrNil == nil`. If home is dead → send `#cannotReturn:` (value) to the active context. Else, if any context between the active one and home (exclusive of home's sender) has a method with the `ensureMarker` primitive → send `#aboutToReturn: value through: firstMarkedContext` to the active context (Smalltalk runs the unwind blocks and completes the return). Else return value to `home sender`, killing every context from the active one up to home.
- **doesNotUnderstand**: the VM builds a `Message` (selector, arguments Array) and sends `#doesNotUnderstand:` to the receiver; if that is not understood either, the VM aborts with a printed stack.
- **Non-boolean in conditional jump**: the VM leaves the context's pc *at the jump bytecode*, pops the value, and sends `#mustBeBoolean` to it; the result is pushed and the jump re-executes with it.
- **Store into an immutable object** (`storeInstVar`): instead of storing, the VM sends `#attemptToAssign: value withIndex: index` (index 1-based) to the receiver, leaving the value on the stack for the following `pop`. (The compiler never uses a popping inst-var store.) `at:put:`-style primitives fail on immutable receivers.
- **Stack overflow**: a process may have `stackLimit` activations (frames and Contexts; primitive `stackLimit`, Smalltalk `Process maxStackDepth` / `maxStackDepth:`; 1,000,000 at VM start, 0 = no limit). Only flushed activations make a stack deep, so after an eighth of the limit's worth of flushed frames (fewer if a quarter of the heap limit holds fewer of the smallest Contexts) the flushing process's next interrupt check (a switch flushes the outgoing process: its check waits until it runs again), before handling interrupts, counts its activations. If they exceed the limit, or their Contexts take more than a quarter of the heap limit, the VM flushes the frames and activates `#stackOverflow: depth` (special object 36) on the top Context as if its next instruction had sent it: that Context is receiver and sender, its own stack unchanged; the interrupts stay pending until the next safepoint. The depth found may exceed the limit by the C stack's frames (up to ~64K) plus the check interval. Smalltalk (`Context>>stackOverflow:`) signals the resumable Error `StackOverflow`, then continues the interrupted Context with `jump` (with an empty stack: a process switch), never by returning, which would push a value onto its stack. A resumed StackOverflow gives its process `maxStackDepth` activations of headroom until the stack unwinds below the overflow (`Process>>stackOverflowIn:depth:`).
- **Method lookup**: receiver class → `methodDict` → superclass chain; per-site inline caches over a global cache keyed by (class, selector); primitive `flushMethodCache` (and `flushCacheFor: selector`, which clears the inline caches too) is called by Smalltalk whenever a method dictionary changes.

### Bytecodes

One opcode byte, then operand bytes (unsigned unless noted, `int16` = little-endian signed, relative to the pc after the instruction).

| opcode | operands | meaning |
|---|---|---|
| 0x00–0x0F | | push temp 0–15 |
| 0x10–0x1F | | push inst var 0–15 |
| 0x20–0x3F | | push literal constant 0–31 |
| 0x40–0x5F | | push literal variable 0–31 (value of the Association) |
| 0x60–0x67 | | pop & store temp 0–7 |
| 0x70 | | push self |
| 0x71 / 0x72 / 0x73 | | push true / false / nil |
| 0x74 / 0x75 | | push SmallInteger 0 / 1 |
| 0x76 | | push thisContext |
| 0x77 | | dup |
| 0x78 | | pop |
| 0x79 | | return top (from method; or from block to its caller when executed in a block context — see 0x7B) |
| 0x7A | | return self |
| 0x7B | | block return top (to the block context's sender) |
| 0x7C | | non-local return top (`^` inside a block) |
| 0x80 i | i | push temp i |
| 0x81 i | i | push inst var i; `sender`, `pc`, `stackp` (i ≤ 2) of a married Context come from its frame |
| 0x82 i | i | push literal constant i |
| 0x83 i | i | push literal variable i |
| 0x84 i | i | store temp i (no pop) |
| 0x85 i | i | store inst var i (no pop; immutability check) |
| 0x86 i | i | store literal variable i (no pop) |
| 0x87 i | i | pop & store temp i |
| 0x88 i | i | store inst var i (no pop); a married Context's frames are flushed first |
| 0x89 i | i | pop & store literal variable i |
| 0x8A d i | depth, index | push outer temp: context = `closureOrNil outerContext` repeated d times (d ≥ 1) |
| 0x8B d i | | store outer temp (no pop) |
| 0x8C d i | | pop & store outer temp |
| 0x8D l n | literal index, argc | send selector `literals[l]` |
| 0x8E l n | literal index, argc | super send: lookup starts at `method methodClass superclass` |
| 0x8F a t f s1 s0 | numArgs, numTemps, frameSize, size (big-endian 16 bit) | push a BlockClosure (outerContext = active context, startpc = pc after this instruction) and skip the `size`-byte block body |
| 0x90 o | int16 | jump |
| 0x91 o | int16 | pop, jump if true |
| 0x92 o | int16 | pop, jump if false |
| 0x93 v | int16 | push SmallInteger v |
| 0x94 n | n | pop n values into a new Array, push it |
| 0x97 a b op | temp, temp, opcode | superinstruction: push temp a, push temp b, then bytecode op (a special-selector send 0xA0–0xB0 with one argument) |
| 0x98 a l op | temp, literal, opcode | push temp a, push literal constant l, then op |
| 0x99 a c op | temp, int8, opcode | push temp a, push SmallInteger c (signed byte), then op |
| 0x9A+k a b | temp, temp | push temp a, push temp b, send special selector k (k = 0–5: `+ - < > <= >=`) |
| 0xF0+k a l | temp, literal | push temp a, push literal constant l, send special selector k (k = 0–5) |
| 0xF6+k a c | temp, int8 | push temp a, push SmallInteger c (signed byte), send special selector k (k = 0–5) |
| 0xA0–0xBF | | send special selector i |
| 0xC0–0xCF | | send literal 0–15, 0 args |
| 0xD0–0xDF | | send literal 0–15, 1 arg |
| 0xE0–0xEF | | send literal 0–15, 2 args |

Methods of Context and its subclasses read `sender`, `pc` and `stackp` with 0x81 and store into instance variables with 0x88; elsewhere the compilers use 0x10–0x1F and 0x85. The compilers emit 0x97–0x99 for "push temp; push temp | literal | small integer; binary special send" (`+ - < > <= >= = ~= * / \\ bitShift: // bitAnd: bitOr: at:`), and 0x9A–0x9F / 0xF0–0xFB instead for `+ - < > <= >=`, when no jump target or recorded pc falls inside the sequence; the source map entry of the send moves to the superinstruction. Each behaves exactly as its three parts: a send it makes returns to the instruction after it.

Inlined `to:do:` tests before the loop and again at its bottom (a conditional jump back), `[...] whileTrue` / `whileFalse` jump back conditionally: one jump per iteration. A block of an inlined loop that declares a variable a closure captures (itself or in a block inlined into it, the loop variable included) is compiled as a real block and evaluated in place with `value` / `value:`, so each iteration has variables of its own, as in the loop's non-inlined form (Pharo's and Squeak's compilers give them per iteration with temp vectors).

Backward jumps and sends are **safepoints**: the VM checks its interrupt flag there.

In the image only `InstructionStream` (System-Debugging) decodes bytecodes: it turns each instruction into a message (`pushTemporaryVariable:`, `send:super:numArgs:`, `jump:if:`, ...) sent to a client — the `Simulator` executes them, the `Disassembler` (`CompiledMethod>>symbolic`) prints them. `BytecodeEncoder` (Compiler) encodes.

## Processes and interrupts

- Run queues: `Processor quiescentProcessLists at: priority` (1–80). `activeProcess` is not in a run queue.
- `resume`: if the process's priority is higher than the active one, the active process is **preempted to the back of its queue** (this gives round-robin among equals whenever a higher-priority process runs; wakeups of the sampler and allocation-sample semaphores put it at the front instead, so profiling does not change the schedule) and recorded as `lastPreemptedProcess`, with whether it was preempted at an activation's interrupt check, its top frame just activated (`processStackInto` answers that; the pc cannot tell: a loop may jump back to the first bytecode); otherwise the resumed process goes to the back of its queue.
- `suspend`, `yield`, `Semaphore>>signal`/`wait` are primitives with Squeak semantics. `terminate` is Smalltalk.
- Processes are charged the VM thread's CPU time (µs, `CLOCK_THREAD_CPUTIME_ID`): wall time would charge them for the time the OS ran other threads. Reading that clock is a system call, so the VM charges in batches: a process switch adds the outgoing process's slice, timed by the CPU's counter (the time-stamp counter on x86-64, `cntvct_el0` on arm64: no system call, a third of the monotonic clock's cost), to a ledger of 16 entries; once the ledger is full or its window is 200 µs old (in counter ticks, measured against the monotonic clock at each reconcile), and when the VM waits or compiles or `processCpuTime` asks about a process in it or running, the thread clock's advance over the window is split among the ledger's processes in proportion to their slices, exactly, into their `cpuTime` (`vmStats` 42 counts these reconciles). Totals are exact; a process's share of a window is right to within the window's length. Waits and the JIT's compiling are charged to no process (`vmStats` 17, CPU µs).
- **Interrupts**: an atomic "check" flag, set when something is due: by a ticker thread (`Ticker`: on macOS a kqueue timer, critical: in the background role macOS would coalesce a 1 ms timer to about 60 ms; on Linux a timerfd per timer, each with its thread) at the timer's and the CPU sampler's next deadline and, if the platform asked for it (`request_periodic_poll`: windows exist or sockets have semaphores), every 1 ms; by allocation when the allocation-sample threshold is crossed; by GCs that cleared weak slots; by external semaphore signals and injected events. The ticker is disarmed while the VM waits in `platform_interface_wait` (the wait's timeout covers the timer and the sampler; events and sockets end the wait), so an idle VM gets no ticks. At the next safepoint the VM: signals the timer semaphore if its time has come; signals the sampler semaphore at the configured interval; polls platform events and sockets and signals their registered semaphores; signals the allocation-sample semaphore (recording the allocated object's class and size). Signaling may preempt.
- **Idle**: Smalltalk's idle process (priority 1) calls `relinquishProcessorForMicroseconds:`, which blocks in the platform's event wait until an event, socket activity, the next timer or the next sampler tick (the always-on profiler samples idle time too, so an idle image still wakes once per sampler interval).

**`becomeForward:` and forwarders** (`ObjectPrimitives>>primBecomeForward`, `GarbageCollector>>forward:to:`; Spur's lazy become, its partial read barrier). `a becomeForward: b` turns `a` into a forwarder: header bit 63 set, format 5, word 1 `b + 6` (tag 6, unused by immediates; `memory isForwarder:` and `follow:`), its size unchanged, its old body no longer traced. `b` takes `a`'s identity hash, as in Pharo (not when `b` is a Symbol: method dictionaries are hashed by it). The VM's roots and every frame slot that hold `a` are rewritten to `b` at once; the running Context's slots too when the interpreter runs on one; optimized code with `a` among its constants is invalidated, and optimized frames that hold `a` (they may know its class) become Contexts first. Nothing else is: heap objects and Contexts keep `a` until the next scavenge (young `a`) or full GC (old `a`), which copy referrers to `b`; `gc forwardersExist` (the JitState's `forwarders` word) is true until then.

Every use of a reference that may be a forwarder follows it:
- sends: no inline cache, polymorphic or megamorphic cache or class guard matches `b + 6`, so the miss follows the receiver and writes it back (`sendDoesNotUnderstand`, `JitBaselineRuntime>>miss:receiver:ret:`, `OptRuntime>>send:index:site:`);
- C primitives: one that fails while forwarders exist follows its receiver and arguments in place and runs again (`Interpreter>>followArgs:at:`); objects inside an argument (an Array's elements, a Point's coordinates) are read through `VMPrimitiveModule>>element:at:`, which follows;
- `==` and `~~` (interpreter, both JIT tiers, primitive 79) follow both operands while forwarders exist, unless one is an immediate, nil, true or false (optimized code follows copies: a register must keep what the value's slot holds, which code after a call reloads); `class` follows a receiver whose class word is tagged;
- a block's receiver (read from its outer Context), a Context's receiver when it is resumed or deoptimized, method dictionaries' key and value Arrays in lookup, a method's literal Array where the VM keeps a pointer into it (`literalsOf:`), its bytecodes where their size or format is read (`bytecodesOf:`; pcs stay offsets from the unfollowed bytes, `methodBcs:`, since a forwarder's old body keeps its bytes until the collection that redirects the pointers). While forwarders exist, an activation takes its literals through `literalsOf:`, and a lazy become refreshes the frames' pointers. Forwarding a method's own bytecodes reaches activations only at that collection, and machine code compiled before keeps the literals it embedded;
- the optimizing tier follows constants it reads at compile time and never takes a forwarder's tagged class for a class.

The objects the VM reads without any of these checks are never forwarders: `becomeForward:` replaces references to them eagerly, with a full GC and a scan of old space, when either object is one (`ObjectMemory>>forwardsEagerly:`): nil, true, false and the other special objects, the Processor's lists Array, classes and metaclasses, Symbols, and instances of CompiledMethod, Context, BlockClosure, Association, Process, LinkedList (so Semaphore), ProcessorScheduler, Message and MethodDictionary. The collectors follow forwarders as they copy (`scavCopy:`, `fullCopy:`, weak slots, an old forwarder stays remembered while its target is young); the heap verifier accepts them; a snapshot has none (it follows a full GC).

VM code that reads a field of an object it did not get as a send's receiver must follow it, check its class or format first (a forwarder fails both, and a failing primitive is retried), or only handle eager kinds. `SAMALTAK_FORWARD_STRESS=n` checks that: every scavenge turns every n-th object it copies that `becomeForward:` would forward lazily into a forwarder to a copy of itself, and makes the roots refer to the copy, as `becomeForward:` does; any code that reads a forwarder fails the tests run under it (`make test-core`: Tests-Kernel, Tests-Compiler and Tests-VM).

## Primitive interface

A primitive is a method `<vmPrimitive: n name: 'intAdd'>` of a `VMPrimitiveModule` subclass (VM-Core, VM-Platform), a `void` function in C. Its inline helpers (`receiver`, `arg: i`, `argCount`, `answer:`, `answerInt:`, `answerBool:`, `fail`, `failCode:`) use the interpreter's primitive plumbing; allocation (`memory allocSlots:count:`, `allocBytes:count:`, `stringFromUtf8:size:`), conversions (`memory floatOop:`, `int64Oop:`, `utf8Of:`, `utf8BytesOf:size:`) and slot access (`self loadRef:at:`, `storeRef:at:put:` — the barriers) are ObjectMemory's and VMCoreModule's. Any allocation may move objects: oops held across one must be pushed as roots (`memory pushRoot:` with a pointer from `self local: 'oop'`). `<leaf>` primitives never allocate, switch processes or look at Contexts: the interpreter calls them without saving its registers. `<notTryable>` ones are not offered to the debugger's `tryPrimitiveWithArgs`.

Strings cross to C as UTF-8 with Python's *surrogateescape*, so OS names that are not UTF-8 (paths, directory entries, argv, the environment) round-trip: `stringFromUtf8:size:` decodes each byte of an ill-formed sequence (overlong, surrogate, above U+10FFFF, truncated, stray continuation) alone, to U+DC80 + byte; `utf8BytesOf:size:` writes U+DC80–DCFF back as that byte and other surrogates as U+FFFD. `utf8Of:` (a C string) answers NULL for a String holding U+0000, so such a path, argument or name fails the primitive instead of being cut short; `stdoutWrite`/`stderrWrite` write every byte. In the image, `ByteArray>>utf8Decoded` and text-mode FileStreams decode each maximal ill-formed subpart to one U+FFFD (never signaling) and `String>>utf8Encoded` writes surrogates as U+FFFD, so text is always well-formed UTF-8.

Error codes for `failCode:` are `VMConstants` class variables (`PRIM_ERR_NO_MEMORY` = 1: the object can never fit in the heap, even after a full GC — size beyond the heap limit or the object size limit, or a LargePositiveInteger size). `basicNew:` and `shallowCopy` fail with it and their Smalltalk fallbacks signal `OutOfMemory` (Kernel-Exceptions; `requestedClass`, `requestedSize`). Other allocations that cannot be satisfied (contexts, small objects when the heap is full) are fatal; runaway recursion is stopped before that by the stack depth limit (Method execution, Stack overflow).

The `vmPrimitive:name:` pragmas are the single source of truth: the translator emits the table (`vm/gen/primitive_entries.c`; the platform layer's rows are left out of a headless build), the image builder numbers `<primitive: 'name'>` from them, and `Smalltalk vm primitiveNames` returns them to the Smalltalk compiler. Core primitives are numbered 1–399, the platform layer's 400–699. Source refers to primitives by name: `<primitive: 'basicNew'>` (a bare number also works).

## Core primitives (names are fixed; numbers are the VM's choice)

A primitive fails (method body runs) on wrong argument types or ranges. Indices are 1-based and count indexable fields only (after fixed fields).

| area | names |
|---|---|
| object | `class` `identical` (==) `identityHash` `basicNew` `basicNew:` `basicSize` `at` `atPut` (pointers → oops, bytes/words → SmallIntegers, BoxedFloat64 → bits) `instVarAt` `instVarAtPut` `shallowCopy` `perform` (selector + up to 4 args on the stack) `performWithArguments` `isImmutable` `setImmutable:` (answers the old flag) `changeClassTo:` `allInstances` (Behavior receiver) `tryPrimitiveWithArgs` (Context receiver: `tryPrimitive: index receiver: r args: array` answers the result, or the special object `#primitiveFailed` symbol on failure — for the debugger's simulator) |
| SmallInteger | `intAdd` `intSub` `intMul` `intDiv` (exact only) `intQuo` `intRem` `intFloorDiv` (//) `intMod` (\\) `intLess` `intGreater` `intLessEq` `intGreaterEq` `intEq` `intNotEq` `intBitAnd` `intBitOr` `intBitXor` `intBitShift` `intAsFloat` — fail on overflow (Smalltalk falls back to the LargeInteger primitives) |
| LargeInteger | `largeAdd` `largeSub` `largeMul` `largeQuo` `largeRem` `largeFloorDiv` (//) `largeMod` (\\) `largeCompare` (answers -1/0/1) `largeBitAnd` `largeBitOr` `largeBitXor` (two's complement) `largeBitShift` — SmallInteger or LargeInteger operands (a LargeInteger's slots its magnitude's 64-bit limbs: products and Knuth's division step by 128-bit multiplications and divisions; the division estimates from the top limbs shifted, subtracting from the remainder unshifted); the result is a SmallInteger if it fits, else a LargeInteger without leading zero bytes (its slots written from the result, not zeroed first); fail on other operands and zero divisors, with `PRIM_ERR_NO_MEMORY` if the result can never fit the heap |
| Float | `floatAdd` `floatSub` `floatMul` `floatDiv` `floatLess` `floatGreater` `floatLessEq` `floatGreaterEq` `floatEq` `floatNotEq` `floatTruncated` (fails outside SmallInteger range) `floatFractionPart` `floatExponent` `floatTimesTwoPower` `floatSqrt` `floatSin` `floatCos` `floatArcTan` `floatLn` `floatExp` `floatPrintString` (shortest round-trip) `floatAsIEEEBits` `floatFromIEEEBits` (class side) `floatHash` (murmur3's fmix64 of the bits, 30 of them; constants for NaN and the infinities; fails for integral values) |
| Character | `charValue` `charFromValue` (class side; 0 to 16r10FFFF, `CHAR_VALUE_MAX`, surrogates included) |
| strings & bytes | `stringAt` `stringAtPut` (Characters; ByteString/WideString/Symbols) `stringHash` `stringCompare` (`String>>compareWith:`: -1/0/1 by code point) `stringCaseInsensitiveCompare` (the same for the code points' lowercase, A–Z and À–Þ but × up 32; ByteStrings and ByteSymbols only; `String>>caseInsensitiveCompare:` folds µ to U+03BC, so it takes an answer other than 0 only for strings without µ) `stringIndexOf` (a Character's first index at or after start, 0 if none) `stringIndexOfSubstring` (where a String next begins at or after start) `stringAsUppercase` `stringAsLowercase` (a new ByteString of a ByteString's or ByteSymbol's characters with a–z and à–þ but ÷ down 32, or A–Z and À–Þ but × up 32; fail for ÿ, whose uppercase is wide; `String>>asUppercase` does not use it for strings with µ, whose uppercase is U+039C) `replaceFromToWithStartingAt` (same-format bulk copy) `bytesUint16At` `bytesUint32At` `bytesInt16At` `bytesFloat32At` `bytesFloat32AtPut` `bytesUint32AtPut` `bytesFloat64At` `bytesFloat64AtPut` (byte offset 1-based, little-endian) `bytesUint16BigEndianAt` `bytesInt16BigEndianAt` `bytesUint32BigEndianAt` (for TrueType) |
| blocks | `closureValue` (0–4 args) `closureValueWithArguments` — markers `ensureMarker` (`ensure:`/`ifCurtailed:`), `onDoMarker` (`on:do:`) |
| contexts | `nextHandlerContext` `findNextUnwindContext` `terminateTo` (Context receiver; Method execution) |
| processes | `processResume` `processSuspend` `processorYield` `semaphoreSignal` `semaphoreWait` `processorLastPreempted` `processorRelinquish` (µs) `signalAtMilliseconds` (timer semaphore) `samplerInterval` (µs, external semaphore index; 0 stops) `allocationSampling` (byte interval, external semaphore index) `allocationSampleInfo` (Array: class, size) `processCpuTime` (cpuTime, settled first if the process is running or has unsettled slices) `processStackInto` (profiler: a non-running process's frames as method, pc pairs into an Array; see ControlPrimitives) `stackLimit` (optional new limit, 0 = none; answers the previous one; see Stack overflow) |
| time | `millisecondClock` `microsecondClock` (monotonic) `utcMicroseconds` `threadCpuTime` (µs, the VM thread's CPU time) |
| display | `displayOpen` `displayFill` `displayCopy` `displayText` `displayBits` `displayNextEvent` `displayFlush` — the guest display (DisplayPrimitives): a 1-bit screen, a fixed-width font, its input; only a simulated VM has one (GuestDisplay), in C they fail |
| system | `quit` `snapshot` (path; answers true when resumed from the snapshot, false right after writing) `gc` (full GC) `scavenge` (young generation only; a full GC, if old space then exceeds its budget, happens at the next allocation) `vmStats` (Array of counters, documented in SystemPrimitives; `Smalltalk vm statistics` wraps it in a VMStatistics with named accessors) `flushMethodCache` `flushCacheForSelector` `vmArguments` `imagePath` `stdoutWrite` `stderrWrite` `primitiveNames` `getenv` `vmBanner` (`VMMain>>banner`, shown in the top bar) `jitParameters` (`{mode. flags. threshold. osr. cache MB}`, settable) `jitCode` (a method's machine code with its compiler's notes, JitPrimitives) |

## Sources

`src/packages.txt`: one line per package, `Name layer [uses Package…]`, in load order, plus `export Package layer Global…` lines (the layering allow-list, see Layers in the image). Each class lives in `src/<Package>/<Class>.st`; methods a package adds to another package's class go in `src/<Package>/<Class>.extension.st`. Classic chunk format (`!` terminates a chunk, `!!` escapes):

```
Object subclass: #Point
	instanceVariableNames: 'x y'
	classVariableNames: ''
	package: 'Kernel-Numbers'!

Point comment: 'I am a two-dimensional point.'!

Point class instanceVariableNames: 'cache'!

!Point methodsFor: 'accessing'!
x
	^x
!
x: aNumber
	x := aNumber
! !

!Point class methodsFor: 'instance creation'!
x: ax y: ay
	^self basicNew setX: ax setY: ay
! !
```

Definition variants: `subclass:`, `variableSubclass:`, `variableByteSubclass:`, `variableWordSubclass:`, `weakSubclass:`, `immediateSubclass:`, and `nil subclass:` for roots. Files are UTF-8 (a leading byte order mark is dropped, as by `File readText:`); strings with code points > 255 become WideStrings. Symbols are unique (`Symbol` interns them); a Symbol and a String with the same characters are equal either way round (`#abc = 'abc'`, as in Squeak and Pharo); `String>>hash` and `Symbol>>hash` are the same function of the code points, primitive `stringHash` (`ObjectMemory>>stringHash:`): up to 8 of them FNV-1a (`h = 2166136261; for cp: h = ((h ^ cp) * 16777619) mod 2^32`), result `& 16r3FFFFFFF` (a byte at a time: keys that differ in the low bits of their last code point stay apart in a small table); more than 8, all below 256 (any ByteString, and a WideString holding only such), them as bytes in 64-bit little-endian words, the last zero-padded, `h = size; for word: h = (h ^ word) * 0x5851F42D4C957F2D; h ^= h >> 32; h *= 0x2545F4914F6CDD1D; h ^= h >> 29` (modulo 2^64), result `& 16r3FFFFFFF`: 8 bytes a multiply; with code points above 255, FNV-1a again. The image builder hashes the seed image's symbols and bindings the same way; a seed image's first start rebuilds the symbol table and rehashes every hashed collection anyway. An image saved before the word hash (its header's String hash field 0) keeps FNV-1a for every String (Image file).

Characters follow Unicode (`Unicode`, answering from `UnicodeTables`, which `tools/unicode-tables.py` generates from the pinned version of the Unicode Character Database; it takes code points with Squeak's selectors, `isLetterCode:` `toUppercaseCode:` `generalCategoryTagOf:`…, and Characters with Pharo's, `isLetter:` `toUppercase:`…): classification by general category (`isLetter` L*, `isDigit` Nd, whose value `digitValue` answers, `isMark` M*, `isUppercase` Lu) and White_Space (`isWhiteSpace`, which the Scanner and the text editor's word logic use; `isSeparator`, `trimBoth`, `substrings` and `skipSeparators` take only space, tab, cr, lf and form feed, as in Squeak and Pharo), the simple one-to-one case mappings, caseless comparison (`sameAs:`, `caseInsensitiveCompare:`, `match:`) by simple case folding, display width in terminal columns (`Character>>displayWidth`, as wcwidth), extended grapheme cluster boundaries (UAX #29: `String>>graphemeClusterEndAfter:`, `graphemeClusterStartBefore:`, `graphemeClustersDo:`), Emoji_Presentation (`isEmojiPresentationCode:`, for choosing color emoji). Identifiers start with a letter or `_` and go on with letters, digits, marks and `_`; binary selectors may use non-ASCII math symbols (Sm: `×` `≠` `≤`); non-ASCII White_Space and U+FEFF separate tokens; number literals use ASCII digits, as do `Number readFrom:` and `asNumber` (`NumberParser`), while `String>>asInteger` reads the first run of decimal digits of any script, as in Squeak and Pharo. `src/` is compiled by the seed image's Scanner, which reads only ASCII names: non-ASCII names appear there only in strings.

The string and character protocol follows Squeak and Pharo: `compareWith:` answers -1/0/1 by code points (what `<` and `=` use), `compare:` and `compare:caseSensitive:` answer 1/2/3 and ignore case by default, `<=>` answers -1/0/1 ignoring case; `String>>encodeWith:` and `ByteArray>>decodeWith:` take Pharo's encoding names for UTF-8 and Latin-1 (`#utf8`, `'UTF-8'`, `#latin1`, `'ISO-8859-1'`; case and punctuation ignored). Deliberate differences: `utf8Decoded` turns each ill-formed sequence into U+FFFD and keeps a U+FEFF inside the text (Squeak and Pharo signal an error, Pharo drops every U+FEFF; a leading byte order mark is dropped only by `File readText:` and the image builder); `utf8Encoded` writes a surrogate as U+FFFD (Pharo signals); `encodeWith:`/`decodeWith:` signal an error for any other encoding (Zinc falls back to UTF-8); `Character value:` takes only code points up to 16r10FFFF (theirs take 30 bits, the high ones a legacy leadingChar); `WideString>>asByteArray`, like `String>>asByteArray`, takes one byte per character and fails above 255 (theirs answers the 4 big-endian bytes of each character); case mapping and folding use the simple mappings of Unicode 17 everywhere, for byte and wide strings alike (`asUppercase`, `asLowercase`, `sameAs:`, `caseInsensitiveCompare:`, `compare:`, Character `sameAs:` by folding, `capitalized` to titlecase; theirs map Latin-1 by table, wider characters by an older UnicodeData, compare lowercase and capitalize to uppercase); `isPunctuation` is `.,:;!?` (Pharo: the open and close punctuation categories Ps and Pe); `copyFrom:to:` of a WideString answers a WideString (theirs narrows to a ByteString when it can); the extended grapheme cluster protocol has no counterpart in either.

Hashed collections (Set, Dictionary and their identity variants; not MethodDictionary) use open addressing with linear probing: an element's home slot is `hash \\ capacity + 1`, the capacity a prime at least twice the tally from `HashedCollection class>>capacities` (about four per octave; no near-powers of two, no divisors of `256^k ± a`, and a two-dimensional spectral test so that keys packed into bytes or bit fields spread out). `SmallInteger>>hash` is the integer itself, so consecutive integers fill consecutive slots. Composite objects combine their parts' hashes with `hashMultiply` (Pharo's: × 1664525 mod 2^28, the bits above 28 folded in first): `Point`, sequences (species, size and the first 16 elements), `Rectangle`, `Complex`, `Message`, `Time`. Numbers that are equal hash alike: an integral Float like its Integer, other Floats by murmur3's fmix64 of their bits (primitive `floatHash`), a Fraction a Float represents exactly like that Float, other Fractions by `hashMultiply` of numerator and denominator; LargeIntegers by FNV-1a over their bytes.

## Seed startup

The image builder builds the class graph (classes, metaclasses, method dictionaries, globals in `Smalltalk`, class pools, interned symbols), compiles every method, creates `Processor` with 80 empty LinkedLists, and one Process at priority 40 whose context runs `Smalltalk bootstrapStartUp` (with receiver `Smalltalk`). `bootstrapStartUp` (Smalltalk) rehashes hashed collections (the builder's have power-of-two capacities), runs class-side `initialize` in load order, and continues with stage 2 (when `--stage2` is given) or the normal startup.

## Graphics (platform layer, Smalltalk-facing)

SDL3 windows and events; SDL_GPU (Metal on macOS, Vulkan on Linux) for rendering. Shaders are source strings owned by Smalltalk (Graphics-Canvas): MSL, or GLSL compiled to SPIR-V by the platform layer (`GPUDevice>>shaderLanguage`); the platform layer only wraps SDL_GPU calls with integer handles. Events reach Smalltalk as 8-slot Arrays `[type, timeMs, x, y, buttonOrKey, modifiers, textOrDelta, windowId]`; `injectEvent:` pushes an Array in the same format into the same queue (the virtual input device used by remote control). Frame readback (`gpuDownload…`) feeds screenshots (PNG encoded in Smalltalk) and video recording (raw frames written to a FIFO read by ffmpeg).

## Layers in the image

`Kernel-*`/`System-*`/`Compiler` (layer 0) → `Graphics-GPU` (thin wrapper over GPU primitives) → `Graphics-Canvas` (fonts, glyph atlases, display lists, the 2D renderer) → `UI-Windows` (World, Compositor, Window with its own Process, animation), `Demos` → `UI-Widgets` (incl. the `Desktop` facade) → `Tools`. A package uses its own layer, the one directly below and layer 0, plus the exceptions declared in `src/packages.txt` (`export` lines: Graphics-Canvas' Canvas/Color/Font/Form from layer 3 up; `uses`: test fixtures). The image builder checks every global a method or class definition references and fails listing each violation as file:line (docs/ui.md).
