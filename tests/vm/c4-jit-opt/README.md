# C4 checked optimizing tier

`run.sh IMAGE VM` uses the standard stage-2 image and the normal Linux
x86-64 `NO_PLATFORM=1` VM. Entry, guard and edit checks run without any
selection/reporting environment. The pressure run enables the existing C4
stats reporter to check optimized returns, collection, weak clearing and
moving relocation. No cases run display code.

For a throughput comparison, alternate these commands on the same VM:

```sh
for heap in c4 c4-moving; do
  for tier in baseline opt; do
    "$vm" --"$heap" --jit "$tier" --eden 16 --max-heap 128 "$image" --headless \
      --eval "$(cat tests/vm/c4-jit-opt/bench.st)"
  done
done
```

Five paired runs (3M calls, same result 135): median pinned 1725 → 2499 ms
(+45%); moving 2412 → 3450 ms (+43%). This is a correctness milestone,
not a speedup. Leaving baseline native execution, validating the method,
replaying canonical operand slots and executing the return in the
interpreter are included in this comparison. There is no optimized OSR.
