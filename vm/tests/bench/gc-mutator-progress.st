"Run via --headless --eval with --eden 1; see docs/benchmarks.md."
| vm nodeCount batchCount batchSize warmup root cursor serial batch gaps
  before after fullBefore fullAfter started last now elapsed fullUs expected out reportGC |
vm := Smalltalk vm.
nodeCount := 16384.
batchCount := 10000.
batchSize := 256.
warmup := 64.
gaps := Array new: batchCount.

"Slot 1 keeps the ring intact; slot 2 gets a new back-linked record each visit."
root := Array new: 2.
cursor := root.
2 to: nodeCount do: [:i |
	cursor at: 1 put: (Array new: 2).
	cursor := cursor at: 1].
cursor at: 1 put: root.
cursor := root.
serial := 0.
batch := [
	| i scratch record |
	i := 0.
	[i < batchSize] whileTrue: [
		scratch := Array new: 8.
		scratch at: 1 put: (cursor at: 1).
		record := Array new: 3.
		record at: 1 put: cursor; at: 2 put: (scratch at: 1); at: 3 put: serial.
		cursor at: 2 put: record.
		cursor := scratch at: 1.
		serial := serial + 1.
		i := i + 1]].

"Tenure the ring, then warm up. Neither is part of the measurements."
vm garbageCollect.
warmup timesRepeat: batch.
before := vm statistics.
started := Time microsecondClockValue.
last := started.
1 to: batchCount do: [:i |
	batch value.
	now := Time microsecondClockValue.
	gaps at: i put: now - last.
	last := now].
elapsed := last - started.
after := vm statistics.

"Separately time a synchronous full GC on the still-live graph."
fullBefore := vm statistics.
started := Time microsecondClockValue.
vm garbageCollect.
fullUs := Time microsecondClockValue - started.
fullAfter := vm statistics.

"Verify the last lap's records after full GC, then summarize outside both windows."
expected := (warmup + batchCount) * batchSize - nodeCount.
nodeCount timesRepeat: [
	| record |
	record := cursor at: 2.
	((record at: 1) == cursor and: [(record at: 2) == (cursor at: 1)
		and: [(record at: 3) = expected]]) ifFalse: [self error: 'Unexpected live graph'].
	cursor := cursor at: 1.
	expected := expected + 1].
after := after - before.
fullAfter := fullAfter - fullBefore.
after gcCount > 0 ifFalse: [self error: 'No collections during batches; use --eden 1'].
fullAfter fullGCs > 0 ifFalse: [self error: 'No explicit full GC recorded'].

gaps sort.
out := WriteStream on: String new.
reportGC := [:stats |
	out nextPutAll: ' scavenges='; print: stats scavenges;
		nextPutAll: ' full_gcs='; print: stats fullGCs;
		nextPutAll: ' scavenge_us='; print: stats scavengeMicroseconds;
		nextPutAll: ' full_gc_us='; print: stats fullGCMicroseconds; lf].
out nextPutAll: 'mutator batches='; print: batchCount;
	nextPutAll: ' elapsed_us='; print: elapsed;
	nextPutAll: ' max_gap_us='; print: gaps last;
	nextPutAll: ' p99_gap_us='; print: (gaps at: batchCount * 99 + 99 // 100);
	nextPutAll: ' p99.9_gap_us='; print: (gaps at: batchCount * 999 + 999 // 1000).
reportGC value: after.
out nextPutAll: 'explicit_full_gc wall_us='; print: fullUs.
reportGC value: fullAfter.
vm stdoutWrite: out contents.
Smalltalk quit: 0
