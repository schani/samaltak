# Standalone native C4 milestone

A test arena, **not a VM mode**. One mutator owns the API; one persistent
pthread marks. The arena has 64 logical cells, two strong slots per cell,
eight explicit roots and a pointer-free 32-bit payload per cell. No raw
addresses, interior references, implicit roots, weak edges, finalizers, JIT,
image integration or legacy GC fallback. Lowtalk is translated and compiled
with `-pthread`; there is no handwritten C.

From the repository root:

```sh
make fresh-image && tests/vm/c4-native/run.sh build/samaltak.image
```

## Cycle and memory ordering

- **Begin:** The mutator records the 64-bit live bitmap and increments the
  epoch, then release-stores REQUESTED. The worker acquires that request
  before touching plain epoch, initial population and bank metadata. It can
  acknowledge PARKED for a gated test; that state is written and subsequently
  read by the same worker. A release/acquire gate controls when it proceeds.
- **Snapshot:** Each root and strong slot is a naturally aligned 64-bit word:
  epoch [63:32], first-overwrite reference [31:16], current reference [15:0].
  One mutator writes it. The first store of an epoch saves the old current
  ref; subsequent stores preserve that saved ref. The worker loads the word
  once: on an epoch match use the saved ref, otherwise the current ref. A
  racing load sees either the pre-overwrite word or a word preserving its
  value. Atomic word accesses can be relaxed: request publication makes
  pre-begin writes happen-before tracing, so a load cannot see an older word
  than that baseline. Epoch stamps cannot repeat while those words are live.
- **Mark:** Only the worker traverses. It visits eight roots and at most 64
  cells (two edge reads per cell), using two 64-bit work bitmaps. It checks
  membership in the initial population before reading a target's generation.
  The mutator never changes those generation entries or reuses those cells
  until finish; allocating outside the initial population touches disjoint
  cells. The worker never reads or writes the scalar payload. All accesses
  to edge words are atomic; opening checks lock-free 64-bit atomics.
- **Finish:** The worker stores `initial & ~marked` and release-stores
  DONE after its last arena read. An acquiring finish poll may accept the
  proposal; until then the snapshot barrier remains armed. This orders
  later cell reuse, relocation and publication of a new epoch after that
  worker's last read. Root/slot stores of an existing alias are also recorded
  in a mutator-only insertion bitmap. If any inserted target is white,
  finish keeps all cells that cycle: reclaiming even other whites could
  dangle a descendant of the newly published alias. With no such insertion,
  any edge from a survivor into an initial white would either have existed
  in the snapshot (so the target would be marked), or appeared via an
  insertion (so finish would have kept it). Plain local handles are not roots;
  normally root handles or reach them through strong slots before begin.
  Newborns are never in the dead bitmap and survive that cycle.

## Bounds, reuse and relocation

The mutator does not sleep, spin, lock, allocate backing memory, scan the heap
or drain work in begin, finish, accessors or the allocation slow path. Finish
retires the dead bitmap at once with a fixed number of word operations.
Allocation claims just its lowest free bit and initializes one cell. If none
is free, it immediately returns 0, whether the worker is idle, parked or busy;
the caller chooses when to begin and poll. `allocationStatus` distinguishes
available (0), no free cell now (1), all generations spent (2), and closed
(3). These are bounds on work, not on
scheduling delay. Only lifecycle calls start/join the pthread; the worker can
sleep while it polls, and the driver can wait for a test acknowledgement.

The low six handle bits identify a cell; the upper ten encode a nonzero
generation. Retirement invalidates that handle immediately; the next allocation
at that index increments the generation. At generation 1023 the index is
permanently excluded from future reuse, so exhaustion can be permanent even
with no live cells. Close/open invalidates all old handles but preserves
generation history. Begin rejects after epoch UINT32_MAX rather than wrapping;
a quiescent reopen restarts epochs only after joining the old worker, clearing
roots and making all old cells unreachable. Every new allocation clears its
selected cell's words before publication.

`relocate:` moves one complete live cell to its reserved twin in the opposite
physical bank. It copies the scalar and current edges, switches the handle's
placement bit and clears the old cell. The mutator can make ordinary progress
between calls; the stable handle and its generation do not change.
`cellIndexOf:` exposes a physical ordinal, not an address, for tests. Relocation
is refused while a cycle is active. The sole mutator publishes placement to
the worker only via the next begin; the old cell has no borrowers and needs no
retirement delay. This tests physical copying and handle indirection, **not**
concurrent evacuation, reference healing, compaction or reclaiming a whole bank.
The worker performs concurrent SATB marking, not the production C4 roadmap's
full moving collector.
