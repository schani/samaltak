# Checked prefix — standalone draft test

From the repository root, with a full stage-2 image and GNU build tools on
Linux x86-64:

```sh
OUT=build tests/vm/c4-opt-slice/run.sh /path/to/samaltak.image
```

The runner builds two fresh headless binaries. The draft uses
`make -C vm NO_PLATFORM=1 C4_OPT_SLICE_TEST=1 BUILD=/separate/path`.
Only that build reads `SAMALTAK_OPT_SLICE` (the fixture selector, with
`--jit none`) and `SAMALTAK_OPT_SLICE_TRACE`. C4's public `--jit opt`
rejection is unchanged. No platform, ARM, UEFI or moving-forward execution
is enabled.

The link-only probe traps both ordinary tier-up entry points; at checked
replay it checks that baseline and legacy optimizing counters are zero.
The fixtures require native exit rows and interpreter parity for tagged
arithmetic, failed guards, overflow and the return boundary. Controls
require no checked replay or diagnostics in the default build, or when the
draft is unselected or outside its runtime lane. The moving witness also
checks an entry interrupt, physical register replay, blocked reentry and
stable registered code-root addresses until all ranges seal, a relocated
weak referent and cleared weak-only control, then a fresh native entry.
Separate fixtures cover wide frames, a rejected loop and stale bytecode
and literal edits. Logs stay under the fresh `OUT` subdirectory.
