# Samaltak design notes

Working decisions. Open questions marked **?**.

## Core

- The VM (object memory, GC, interpreter, scheduler, primitives, image I/O) and the platform layer (SDL3 windows and input, SDL_GPU on Metal or Vulkan, files, sockets, ptys) are written in **Lowtalk** (docs/lowtalk.md): a subset of Smalltalk that is also plain Smalltalk. Running it directly is the simulator (debuggable and profilable with the image's own tools, the VM Simulator window); `VMTranslator` turns it into C. There is no hand-written C.
- The generated C (`vm/gen/`) is checked in, so a fresh checkout builds without a working VM; `make test` checks that it is what the sources translate to. Built with PGO it is as fast as the hand-written C VM it replaced.
- Images are built from the sources by `ImageBuilder` (Smalltalk), which allocates the new image's objects with the VM's own object memory, simulated, so the object format has one definition (`VMConstants`). It runs in a checked-in seed image (`boot/seed.image`), after filing in its current sources; the seed only needs updating when the builder needs something the seed's kernel lacks.
- Next: a native-code backend for the translator's typed tree, and a JIT in the image.

## Language

- Smalltalk-80 semantics and syntax.
- Source of truth: text files in git; images built from source by ImageBuilder.
- Immutable literals; per-object immutability bit.
- **?** Modules/namespaces vs. single global namespace.

## Concurrency

- Green threads: Smalltalk `Process`es on one OS thread, priority-preemptive at safepoints (sends, backward jumps). Squeak semantics.
- Every window runs in its own Process, so one busy window does not block others.
- The compositor is a high-priority Process woken by the vsync Semaphore.
- GC today: stop-the-world, generational, on the mutator thread. A concurrent GC on its own thread(s) is the goal; the rules below keep it possible.

## GC: keep the door open for pauseless (C4-style)

The VM currently collects synchronously on its one mutator. `loadRef:at:` is a plain load and `storeRef:at:put:` implements the generational barrier for many body accesses. Neither covers all reference traffic: class words, heap Context stacks and literals, bulk operations and JIT code also have direct paths.

The [C4 roadmap](c4.md) separates current behavior from the target: complete mutator load/store barriers, precise roots at bounded checkpoints, region-based relocation, and no stop-the-world fallback in C4 mode. Keep identity hashes independent of addresses and use handles or off-heap buffers for retained native state. See [implementation.md](implementation.md#object-memory) for the current heap format and collector.

## Debugging and profiling

Only features with no significant memory, performance or complexity cost.

1. **Contexts are heap objects**, so every frame is inspectable, restartable and editable. Smalltalk's `thisContext` requires this anyway; a future JIT must map frames to Contexts on demand.
2. **One safepoint mechanism** serves preemption, GC handshakes, profiler sampling and interrupts.
3. **Sampling profiler**: a timer interrupt records the active Process's stack at the next safepoint into a fixed ring buffer (≈1 MB). Always on, attributed per Process (i.e. per window).
4. **Allocation sampling** piggybacks on the bump allocator's limit check: the limit is lowered to the next sample point, so the fast path is unchanged.
5. **Watchpoints use the immutability bit** stores already check: mark the object read-only, catch the failed store, report, retry.
6. **Breakpoints, logpoints, conditional and per-object breakpoints are image-side**: recompiled methods or a per-object anonymous subclass. No VM support.
7. **Frame timeline**: per frame, a small record of which Processes ran, draw/raster times, GPU timestamp queries and GC phases.
8. **The debugger never runs in the debugged Process.** Any window's Process can be stopped while the rest stays live.
   By default breakpoints and watchpoints stop only user Processes; scoped ones (`inProcess:`, `inAllProcesses`, `scope: #all`) also stop a window's, a debugger's or the window system's own. While a debugger holds the input dispatcher or the compositor, a stand-in Process runs the same object's loop (breakpoints ignored there), so input, remote control and drawing go on; it retires when the original resumes and takes over if it is abandoned.
9. Profile data are ordinary objects behind a Kernel-level API; tools never call raw primitives.
10. **Runaway recursion is an error, not a crash**: a stack deeper than `Process maxStackDepth` (or a quarter of the heap) signals the resumable `StackOverflow` with the stack intact, so a debugger shows it. The VM counts a process's activations only after it has flushed enough frames into Contexts, so sends pay nothing.

Rejected as too costly: record/replay and time-travel debugging, always-on send/allocation tracing, read watchpoints, remote debugging.

The debugger steps with an in-image bytecode simulator (`Simulator`, System-Debugging): it interprets the debugged Process's contexts in Smalltalk, so stepping needs no VM support.

## Remote control

The whole UI must be drivable by an agent (Claude) without a human, at no cost when unused.

- **Virtual input device** (Platform layer): synthetic pointer/key events enter the same input path as OS events, so remote input behaves exactly like real input and punches no hole through the layers.
- **Frame readback** (Platform layer): PNG of the screen or one window's layer texture.
- **Control service** (image, System-Remote in layer 0; UI-Windows plugs the World in through `UIRemote`): a Process blocked on a local socket. Commands:
  - `snapshot`: the widget tree as structured text (window, role, label, bounds, state, stable ref per widget), like an accessibility tree;
  - `click` / `type` / `key` / `drag` on a ref or coordinate, sent through the virtual input device;
  - `eval`: run a Smalltalk expression, return its printString;
  - `screenshot`;
  - `wait`: until a condition holds (widget exists, Process idle, frame presented).
- A small CLI (`samaltak-ctl`) wraps the socket, modeled on `agent-browser`.
- Same channel later serves automated UI tests.

## Graphics and UI layering

A package may use packages of its own layer, the layer directly below, and layer 0 (Kernel, System, Compiler). One exception: from layer 3 up, Graphics-Canvas' drawing vocabulary (`Canvas`, `Color`, `Font`, `Form`; `Point` and `Rectangle` are Kernel) may be used directly, since every widget and tool draws. Tools reach the window system through UI-Widgets' `Desktop` facade, never through `Window`/`World`. Lower layers reach higher ones only late-bound (`Smalltalk at: #Name ifAbsent:`). The image builder enforces this; `src/packages.txt` holds the layers and the allow-list (`export` lines for the vocabulary, `uses` for test fixtures).

| Layer | Package | Responsibility |
|---|---|---|
| 5 | Tools | Browser, Workspace, Inspector, Debugger |
| 4 | UI-Widgets | Widgets, layout, events. What normal UI code uses. |
| 3 | UI-Windows, Demos | Window (owns a Process), Compositor; demo views and the Canvas demo |
| 2 | Graphics-Canvas | 2D paths, text, images → immutable DisplayLists; GPU compute rasterizer |
| 1 | Graphics-GPU | WebGPU-shaped 3D API: devices, buffers, pipelines, command encoders |
| 0 | Kernel, System, Compiler | Language, processes, files, profiling, debugging, remote control |
| — | Platform (C) | SDL3 windows and input, SDL_GPU (Metal, Vulkan), files, sockets |

Widgets draw on a `Canvas`; they never see `GPUDevice`.

## Deferred

- Bare metal beyond UEFI's services (docs/uefi.md): drivers of our own for what the firmware drives (the image drives the display and the input, through the firmware's protocols), networking.

## UI direction

Classic revival (`prototypes/1-classic/`): overlapping windows, Smalltalk-80 tools. Blue Book theme (black on white, hard frames, halftone desk, ultramarine as the only color) with pi-orb typography: Iosevka Etoile for UI, JetBrains Mono for code.
