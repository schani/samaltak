# C4Prototype

A cooperative C4-style reference collector implemented in Smalltalk. It is
not part of the default image and does not change the VM collector.

```sh
vm/build/samaltak build/samaltak.image --headless --load apps/C4Prototype \
  --eval "| h r | h := C4Heap new. r := h allocate: 1. h rootAt: #main put: r. h startCycle. [h step] whileTrue. (h rootAt: #main) address"
```

## API

| Message | Result |
| --- | --- |
| `allocate: slotCount` | Ref to a new object with nil slots; count may be zero. |
| `at: ref slot: index` | Read and heal a 1-based slot. |
| `at: ref slot: index put: refOrNil` | Store and return the canonical value. |
| `rootAt: key` | Read and heal a root; nil if absent. |
| `rootAt: key put: refOrNil` | Store and return the canonical value; nil removes the root. |
| `removeRoot: key` | Remove a root; returns nil. |
| `resolve: refOrNil` | Return the canonical ref, or nil for nil. |
| `identityHashOf: ref` | Hash of the logical object, stable across moves. |
| `startCycle` | Start a collection and advance the epoch; error unless idle. |
| `step` | Do one work unit and return true; return false if already idle. |
| `phase`, `epoch`, `objectCount` | Collection phase, current epoch (initially 0), and logical population (includes unswept garbage). |

A ref exposes `address` and `epoch`. Its equality and hash describe its
heap/address/epoch, not logical identity across moves. Canonicalize before
comparing references to an object. Slots and roots accept refs from this heap
or nil. Root keys use ordinary dictionary equality and must have stable,
non-reentrant hash and equality methods.

## Interleaving

Call from one Smalltalk process or serialize externally. Each API call is
atomic in the model; any mutator call can run between steps. Only registered
roots are scanned; Smalltalk locals are invisible. Register a reference you
need to keep and reacquire it from a root or slot after collection.

1. **Mark** (`#mark`): Scan root cells and shade references using a worklist.
   Reads, explicitly resolving a ref, and pointer/root stores shade their
   targets during this phase, even after the relevant slot has been scanned.
   New allocations survive this cycle; their initial slots are nil and
   subsequent stores shade what they install. Deleting an edge need not undo
   a mark, so floating garbage can survive until the next cycle.
2. **Move** (`#move`): Reject unmarked refs on every access, even before sweep.
   Move each marked pre-cycle object once. While copying, the copied prefix
   and untouched suffix each have a single authoritative buffer for both
   mutator and collector access. Publish a new address and forwarding together
   only after the copy finishes. The load barrier follows forwarding and
   writes back the canonical ref.
3. **Heal** (`#heal`): Canonicalize all roots and live slots that could still
   hold old refs. Moves are now done, so concurrent-in-the-model writes already
   store canonical refs.
4. **Retire** (`#retire`): Unlink unmarked objects and release their addresses
   together with forwarding sources to the free list when returning to idle.

Forwarding handles one hop. A forwarded alias is usable until the earlier
of reuse of its source address or the next cycle's start. A reused address
never denotes a new object to an old ref: its new incarnation has a different
epoch. Unmarked objects cannot be resurrected once mark closes.

The collector does not snapshot whole tables, resize a worklist, or allocate
large arrays in `step`. Each step processes at most one logical slot (including
a root or one slot's transfer) or a fixed amount of metadata. The two buffers
are reserved by `allocate:`; this model pays extra memory to avoid bulk
allocation during evacuation. Bounds apply to the model, not to the host VM's
own allocation or GC pauses.
