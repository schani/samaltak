# Benchmarks

Same suite in three systems, methods compiled normally in each (`vm/tests/bench/suite-*.st`), on an Apple M2 Max, best of seven runs. Milliseconds, lower is better.

| benchmark | Samaltak (interpreter) | GNU Smalltalk 3.2.5 (interpreter) | Pharo 14 (Cog JIT) |
|---|---|---|---|
| `fib: 30` | 24 | 44 | 9 |
| loop 30M (`r := r + i`) | 109 | 167 | 57 |
| sends 10M (`self id: r`) | 103 | 164 | 21 |
| blocks 10M (`b value: r`) | 122 | 169 | 29 |
| floats 3M | 28 | 244 | 35 |
| Dictionary 300k (`at:put:`, `at:`) | 113 | 1657 | 158 |
| strings 300k (`printString` into a stream) | 145 | 220 | 69 |
| allocation 3M (`Array new: 4`) | 70 | 983 | 23 |
| `1000 factorial` ×30 | 1 | 5 | 6 |

All three do large-integer arithmetic in C (GMP, LargeIntegersPlugin, Samaltak's LargeIntegerPrimitives). Pharo compiles to native code, so it is a ceiling rather than a peer.

Run:

    vm/build/samaltak --jit none build/samaltak.image --headless --eval "$(cat vm/tests/bench/suite-samaltak.st)"
    gst vm/tests/bench/suite-gst.st
    Pharo --headless Pharo.image eval "$(cat vm/tests/bench/suite-pharo.st)"

## Are We Fast Yet

The suite for comparing JIT variants ([jit.md](jit.md)): the 14 [Are We Fast Yet](https://github.com/smarr/are-we-fast-yet) benchmarks (Marr, Daloze, Mössenböck, DLS 2016; MIT, `awfy/LICENSE.md`), the micro suite above (`Micro*`) and two Samaltak workloads: `Recompile` (compile every method of Kernel-Collections without installing it; checks the bytecodes match) and `TextRendering` (40 lines of text on a 900×500 Canvas, then `displayList`). The sources in `vm/tests/bench/awfy/` are filed into a built image; each benchmark runs in its own VM process. Pharo 14 runs the same sources except the Samaltak workloads, each method under its own `methodsFor:` preamble (`pharo14.awk`), the form Pharo 14 files in.

    vm/tests/bench/awfy.sh [--suite awfy|micro|workloads|realworld|all] [-n 30] [--vm-args '--jit none|baseline|opt'] [Bench[:inner] ...]
    vm/tests/bench/awfy.sh --pharo ...                  # $PHARO_VM, $PHARO_IMAGE (default ~/.cache/pharo14)
    vm/tests/bench/awfy.sh --summary results/*.csv      # median over invocations

Output: `benchmark,iteration,microseconds` per iteration; `# stats` lines with the VM statistics delta over all iterations (every counter the VM answers, unnamed ones as `counterN`); a summary of first iteration, steady state (median of the last half) and total. `-o` saves all of it.

Defaults: 30 iterations; inner iterations (`inner()` in `awfy.sh`) such that a steady-state iteration takes about 100 ms on the interpreter. CD (100 aircraft, 330 ms), Havlak (1, 710 ms), Mandelbrot (500, 500 ms) and NBody (250000 steps, 750 ms) run at the smallest non-trivial size upstream verifies. `--suite all` takes 2 minutes on the interpreter.

Changes from upstream (the Smalltalk variant, SOM class syntax with Pharo method bodies): class files converted to chunk format, class-side fields as class variables (as upstream's Pharo loader); `Scheduler` (Richards) and `Simulator` (CD) renamed `RBScheduler` and `CDSimulator`, Samaltak has those globals; Json's `isTrue || isFalse` (unused) written `isTrue | isFalse`; the harness prints CSV and VM statistics and does not exit; `awfy/Samaltak.st` adds the Pharo methods `Integer>>&` and `Number>>%`.

Steady state (median of the last half of 30 iterations) and first iteration, ms, median of 3 invocations interleaved `opt`, `baseline` and Pharo 14 (VM 12.0.6), the interpreter (`none`) after them (`vm/tests/bench/results/{samaltak-opt,samaltak-baseline,pharo14-cog,samaltak-none}-2026-11-14-*.csv`), 1-minute load at most 3 before each invocation, M2 Max:

| benchmark | `none` | `opt` | `baseline` | Pharo 14 | `opt` / Pharo | `baseline` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo | first `baseline` / Pharo |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bounce | 110.8 | 9.9 | 21.4 | 34.0 | 0.29 | 0.63 | 12.6 | 22.6 | 39.6 | 0.32 | 0.57 |
| CD | 363.3 | 45.8 | 85.5 | 200.6 | 0.23 | 0.43 | 66.5 | 87.5 | 205.2 | 0.32 | 0.43 |
| DeltaBlue | 107.2 | 10.9 | 26.7 | 78.3 | 0.14 | 0.34 | 88.3 | 29.6 | 86.3 | 1.02 | 0.34 |
| Havlak | 731.7 | 66.7 | 203.0 | 396.0 | 0.17 | 0.51 | 95.3 | 207.6 | 408.2 | 0.23 | 0.51 |
| Json | 97.4 | 8.0 | 32.9 | 55.8 | 0.14 | 0.59 | 42.5 | 34.9 | 53.7 | 0.79 | 0.65 |
| List | 122.9 | 10.2 | 17.5 | 23.3 | 0.44 | 0.75 | 11.1 | 17.5 | 23.4 | 0.48 | 0.75 |
| Mandelbrot | 512.3 | 100.4 | 191.0 | 348.7 | 0.29 | 0.55 | 103.8 | 189.4 | 348.9 | 0.30 | 0.54 |
| NBody | 765.3 | 144.1 | 317.9 | 353.1 | 0.41 | 0.90 | 144.1 | 318.2 | 364.5 | 0.40 | 0.87 |
| Permute | 114.9 | 13.4 | 21.7 | 33.5 | 0.40 | 0.65 | 13.4 | 21.4 | 33.1 | 0.40 | 0.65 |
| Queens | 110.9 | 10.7 | 19.5 | 42.5 | 0.25 | 0.46 | 13.6 | 20.0 | 42.3 | 0.32 | 0.47 |
| Richards | 97.3 | 8.9 | 17.3 | 22.6 | 0.40 | 0.77 | 10.8 | 17.6 | 23.2 | 0.47 | 0.76 |
| Sieve | 95.6 | 16.7 | 32.4 | 54.9 | 0.30 | 0.59 | 26.4 | 34.7 | 58.1 | 0.45 | 0.60 |
| Storage | 115.7 | 23.5 | 36.9 | 55.9 | 0.42 | 0.66 | 28.0 | 37.6 | 59.4 | 0.47 | 0.63 |
| Towers | 91.1 | 7.3 | 14.1 | 16.5 | 0.45 | 0.85 | 8.2 | 14.1 | 16.6 | 0.49 | 0.85 |
| geometric mean | | | | | 0.29 | 0.60 | | | | 0.43 | 0.60 |

The micro suite (`--suite micro`: the first table's benchmarks as AWFY benchmarks), the same way (`...-micro-2026-11-14-*.csv`):

| benchmark | `opt` | `baseline` | Pharo 14 | `opt` / Pharo | `baseline` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo | first `baseline` / Pharo |
|---|---|---|---|---|---|---|---|---|---|---|
| MicroFib | 3.9 | 5.1 | 10.1 | 0.39 | 0.50 | 4.0 | 5.1 | 10.2 | 0.39 | 0.50 |
| MicroLoop | 26.8 | 31.6 | 62.9 | 0.43 | 0.50 | 28.0 | 31.9 | 63.2 | 0.44 | 0.50 |
| MicroFloats | 5.6 | 19.0 | 37.9 | 0.15 | 0.50 | 5.8 | 18.9 | 38.1 | 0.15 | 0.50 |
| MicroSends | 8.6 | 21.7 | 21.9 | 0.40 | 0.99 | 8.8 | 21.7 | 21.8 | 0.40 | 1.00 |
| MicroBlocks | 14.0 | 28.7 | 30.0 | 0.47 | 0.95 | 16.3 | 28.9 | 29.8 | 0.55 | 0.97 |
| MicroDict | 15.9 | 28.1 | 132.1 | 0.12 | 0.21 | 15.6 | 38.7 | 190.3 | 0.08 | 0.20 |
| MicroStrings | 22.5 | 35.0 | 74.2 | 0.30 | 0.47 | 27.6 | 36.4 | 78.3 | 0.35 | 0.46 |
| MicroAlloc | 12.9 | 19.7 | 31.5 | 0.41 | 0.63 | 16.9 | 21.7 | 33.0 | 0.51 | 0.66 |
| MicroFactorial | 1.7 | 1.7 | 7.8 | 0.21 | 0.22 | 2.9 | 1.8 | 8.3 | 0.35 | 0.22 |
| geometric mean | | | | 0.29 | 0.49 | | | | 0.31 | 0.49 |

`opt` takes 0.29 of Pharo 14's time on AWFY (first iterations 0.43), `baseline` 0.60; on the micro suite 0.29 and 0.49. Both win every benchmark; of the first iterations `opt` loses DeltaBlue (1.02, most of it compiling) and `baseline` ties MicroSends (1.00). `baseline` comes closest on MicroSends (0.99) and MicroBlocks (0.95), a send or a block call per turn, the code Cog makes for them, and on NBody (0.90: Float arithmetic out of line, accessors sent). Pharo 14 runs these as fast as Pharo 12 (1.01 and 0.96 of its time, `results/pharo12-cog{,-micro}-2026-11-07-*.csv`) but DeltaBlue (1.72) and MicroStrings (1.21).

### x86-64

The same benchmarks on Linux x86-64: an AMD EPYC 7B13 (Zen 3) cloud VM with 2 vCPUs, the VM built with gcc -O2 (no profile); CPU time (`--cpu`), steady state as above, one invocation per mode, `none` 10 iterations, `baseline` and `opt` 30 (`vm/tests/bench/results/samaltak-x86-{none,baseline,opt}-2026-11-14.csv`), beside arm64's ratios of 2026-11-07 (M2 Max, `results/samaltak-{none,baseline,opt}-2026-11-07-*.csv`):

| benchmark | `none` | `baseline` | `opt` | `baseline` / `none` | `opt` / `none` | arm64 `baseline` / `none` | arm64 `opt` / `none` |
|---|---|---|---|---|---|---|---|
| Bounce | 309.9 | 42.3 | 14.4 | 0.14 | 0.05 | 0.19 | 0.09 |
| CD | 728.1 | 178.3 | 97.8 | 0.24 | 0.13 | 0.26 | 0.14 |
| DeltaBlue | 323.5 | 58.6 | 22.6 | 0.18 | 0.07 | 0.27 | 0.13 |
| Havlak | 1310.4 | 414.6 | 128.3 | 0.32 | 0.10 | 0.26 | 0.10 |
| Json | 171.3 | 70.3 | 20.5 | 0.41 | 0.12 | 0.37 | 0.09 |
| List | 248.7 | 32.8 | 17.4 | 0.13 | 0.07 | 0.15 | 0.10 |
| Mandelbrot | 745.9 | 199.6 | 146.5 | 0.27 | 0.20 | 0.39 | 0.22 |
| NBody | 1601.7 | 503.7 | 223.7 | 0.31 | 0.14 | 0.43 | 0.19 |
| Permute | 198.6 | 34.3 | 22.7 | 0.17 | 0.11 | 0.19 | 0.12 |
| Queens | 199.0 | 35.7 | 17.8 | 0.18 | 0.09 | 0.17 | 0.11 |
| Richards | 169.2 | 35.3 | 18.5 | 0.21 | 0.11 | 0.17 | 0.09 |
| Sieve | 236.7 | 46.2 | 33.9 | 0.20 | 0.14 | 0.33 | 0.17 |
| Storage | 213.1 | 54.3 | 31.9 | 0.25 | 0.15 | 0.31 | 0.21 |
| Towers | 149.0 | 22.9 | 13.1 | 0.15 | 0.09 | 0.15 | 0.09 |
| geometric mean | | | | 0.21 | 0.11 | 0.24 | 0.13 |

Over its interpreter each JIT gains as much on x86-64 as on arm64; this machine runs the interpreter 1.9× slower than the M2 Max. Compiling (the runs' counters): `baseline` 10.1 µs a method, 0.45 µs per bytecode byte; `opt` 0.78 ms a unit, 8.6 KB of code (the M2 Max: 4.3 µs, 0.20 µs, 0.34 ms, 6.1 KB). x86-64's code is about a third bigger than arm64's: two-operand instructions take a `mov` more, branches to out-of-line paths 6 bytes, nil, true and false a pc-relative word, 64-bit constants 10 bytes.

Against Pharo 12 on the same machine (its Linux x86-64 VM, Cog), all three suites: CPU time (`--cpu`; `awfy/PharoCPU.st` reads the thread's clock as on macOS), steady state as above, median of 3 invocations interleaved `opt`, `baseline`, Pharo (`vm/tests/bench/results/{samaltak-x86-opt,samaltak-x86-baseline,pharo12-cog-x86}{,-micro,-realworld}-2026-11-15-*.csv`), beside arm64's against Pharo 12 (M2 Max, `results/{samaltak-opt,samaltak-baseline,pharo12-cog}{,-micro,-realworld}-2026-11-07-*.csv`). Geometric means:

| | x86-64 `opt` / Pharo | arm64 `opt` / Pharo | x86-64 `baseline` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|
| Are We Fast Yet (14) | 0.43 | 0.33 | 0.82 | 0.64 |
| Micro (9) | 0.25 | 0.30 | 0.44 | 0.49 |
| CLBG (6 of the real-world workloads) | 0.48 | 0.50 | 0.63 | 0.66 |
| the other real-world workloads (10) | 0.46 | 0.37 | 0.58 | 0.46 |
| all 39 | 0.39 | 0.35 | 0.62 | 0.55 |

| Are We Fast Yet | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | arm64 `opt` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|---|---|---|
| Bounce | 15.6 | 36.1 | 44.3 | 0.35 | 0.81 | 0.31 | 0.67 |
| CD | 99.7 | 182.0 | 198.9 | 0.50 | 0.92 | 0.24 | 0.43 |
| DeltaBlue | 21.8 | 57.3 | 59.3 | 0.37 | 0.97 | 0.32 | 0.71 |
| Havlak | 137.9 | 418.2 | 404.4 | 0.34 | 1.03 | 0.21 | 0.55 |
| Json | 20.5 | 71.3 | 36.1 | 0.57 | 1.98 | 0.15 | 0.62 |
| List | 17.2 | 32.9 | 55.6 | 0.31 | 0.59 | 0.50 | 0.74 |
| Mandelbrot | 148.1 | 199.7 | 300.3 | 0.49 | 0.67 | 0.32 | 0.56 |
| NBody | 224.2 | 503.9 | 517.4 | 0.43 | 0.97 | 0.41 | 0.93 |
| Permute | 29.5 | 34.4 | 52.3 | 0.57 | 0.66 | 0.40 | 0.63 |
| Queens | 17.7 | 38.6 | 59.1 | 0.30 | 0.65 | 0.28 | 0.45 |
| Richards | 30.9 | 34.8 | 37.8 | 0.82 | 0.92 | 0.42 | 0.77 |
| Sieve | 33.3 | 46.3 | 88.7 | 0.38 | 0.52 | 0.32 | 0.60 |
| Storage | 30.9 | 54.7 | 91.6 | 0.34 | 0.60 | 0.43 | 0.64 |
| Towers | 12.9 | 24.4 | 27.9 | 0.46 | 0.87 | 0.48 | 0.84 |
| geometric mean | | | | 0.43 | 0.82 | 0.33 | 0.64 |

| Micro | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | arm64 `opt` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|---|---|---|
| MicroFib | 6.2 | 8.3 | 10.8 | 0.58 | 0.77 | 0.43 | 0.51 |
| MicroLoop | 29.1 | 38.7 | 115.0 | 0.25 | 0.34 | 0.43 | 0.51 |
| MicroFloats | 10.7 | 18.9 | 60.6 | 0.18 | 0.31 | 0.15 | 0.53 |
| MicroSends | 9.8 | 32.0 | 38.9 | 0.25 | 0.82 | 0.53 | 0.97 |
| MicroBlocks | 19.3 | 54.3 | 47.4 | 0.41 | 1.14 | 0.48 | 0.95 |
| MicroDict | 28.7 | 51.3 | 232.9 | 0.12 | 0.22 | 0.12 | 0.21 |
| MicroStrings | 45.4 | 63.7 | 98.4 | 0.46 | 0.65 | 0.38 | 0.60 |
| MicroAlloc | 16.9 | 35.3 | 82.7 | 0.20 | 0.43 | 0.35 | 0.60 |
| MicroFactorial | 1.7 | 1.8 | 14.2 | 0.12 | 0.12 | 0.17 | 0.17 |
| geometric mean | | | | 0.25 | 0.44 | 0.30 | 0.49 |

| Real-world | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo | arm64 `opt` / Pharo | arm64 `baseline` / Pharo |
|---|---|---|---|---|---|---|---|
| BinaryTrees | 421.3 | 720.4 | 925.5 | 0.46 | 0.78 | 0.45 | 0.79 |
| Fasta | 538.1 | 701.0 | 742.2 | 0.73 | 0.94 | 0.72 | 0.83 |
| KNucleotide | 623.5 | 784.1 | 1210.7 | 0.51 | 0.65 | 0.51 | 0.61 |
| ReverseComplement | 446.0 | 689.8 | 1235.0 | 0.36 | 0.56 | 0.35 | 0.55 |
| SpectralNorm | 729.1 | 845.6 | 1008.9 | 0.72 | 0.84 | 0.55 | 0.81 |
| Pidigits | 427.3 | 436.2 | 1579.0 | 0.27 | 0.28 | 0.48 | 0.45 |
| Strings | 431.7 | 559.4 | 1086.1 | 0.40 | 0.52 | 0.37 | 0.46 |
| Dictionaries | 522.8 | 879.3 | 1735.5 | 0.30 | 0.51 | 0.32 | 0.43 |
| OrderedCollections | 317.0 | 394.5 | 1140.9 | 0.28 | 0.35 | 0.28 | 0.32 |
| Sorting | 819.2 | 1172.9 | 1214.5 | 0.67 | 0.97 | 0.70 | 0.77 |
| Enumeration | 376.5 | 613.2 | 916.7 | 0.41 | 0.67 | 0.39 | 0.63 |
| PrintParse | 1073.1 | 1556.8 | 1363.6 | 0.79 | 1.14 | 0.57 | 0.85 |
| Exceptions | 823.7 | 818.4 | 1892.8 | 0.44 | 0.43 | 0.63 | 0.68 |
| Megamorphic | 320.6 | 265.6 | 281.6 | 1.14 | 0.94 | 0.15 | 0.15 |
| DeepRecursion | 346.2 | 405.2 | 1284.9 | 0.27 | 0.32 | 0.32 | 0.36 |
| Perform | 512.4 | 606.7 | 1249.7 | 0.41 | 0.49 | 0.33 | 0.39 |
| geometric mean | | | | 0.46 | 0.60 | 0.41 | 0.52 |

`opt` wins 38 of the 39; it loses Megamorphic (1.14: Pharo's x86 VM takes 282 ms where its arm64 one takes 704, Samaltak 321 where it takes 107; a fifth of its samples are in the shared megamorphic stub; its table is not the cause: 1024 or 16384 entries instead of 4096 change nothing). `baseline` loses Json (1.98), Havlak, MicroBlocks and PrintParse (1.03–1.14). Pharo runs these benchmarks 1.43× slower here than on the M2 Max, `opt` 1.58× and `baseline` 1.61× (built here with gcc and no profile, there with clang and its profile). The machine is shared: every VM had invocations that ran up to twice as slow (Pharo's Bounce 44, 87 and 44 ms); the best of the 3 invocations instead of their median moves no geometric mean by more than 0.02.

Pharo 14 (its Linux x86-64 download of 2026-11-14, `Pharo-14.0.0+SNAPSHOT.build.790`), the same way (`vm/tests/bench/results/pharo14-cog-x86{,-micro,-realworld}-2026-11-15-*.csv`), against the Samaltak medians above. Its Cog runs these benchmarks as fast as Pharo 12's (geometric mean 0.99 of Pharo 12's time; Json 1.17, Sorting and Enumeration 0.85, the rest within 12 %):

| | `opt` / Pharo 14 | `baseline` / Pharo 14 | `opt` / Pharo 12 | `baseline` / Pharo 12 |
|---|---|---|---|---|
| Are We Fast Yet (14) | 0.43 | 0.82 | 0.43 | 0.82 |
| Micro (9) | 0.25 | 0.44 | 0.25 | 0.44 |
| CLBG (6) | 0.48 | 0.63 | 0.48 | 0.63 |
| the other real-world workloads (10) | 0.47 | 0.60 | 0.46 | 0.58 |
| all 39 | 0.40 | 0.63 | 0.39 | 0.62 |

`opt` loses Megamorphic to Pharo 14 too (1.23); `baseline` Json (1.69), Havlak and Sorting (1.14), MicroBlocks, PrintParse, Megamorphic and NBody (1.01–1.07).

Pharo 12 collects old space when it has grown by a third since the last full GC (`Smalltalk vm parameterAt: 55`, 0.333); Samaltak when it reaches twice what the last one left live, at least 64 MB (`GarbageCollector`); both have a 16 MB eden (Pharo's parameter 44). Pharo 12 with 1.0 (`--pharo-init 'Smalltalk vm parameterAt: 55 put: 1.0'`) against its default, 3 invocations interleaved (`vm/tests/bench/results/pharo12-cog-x86-{gcdefault,gcratio1}{,-micro,-realworld}-2026-11-15-*.csv`; the default's times are 1.04 of the published ones above, geometric mean), takes 0.85 of the time on CLBG and 0.92 on the other real-world workloads: ReverseComplement 0.54, DeepRecursion 0.82 (196–199 full GCs in 30 iterations become 82–83), Enumeration 0.83 (102, 41), OrderedCollections 0.84, KNucleotide 0.87 (24, 10), BinaryTrees 0.88 (42–53, 16–17), Sorting 0.89 (43, 15–17). ReverseComplement is bimodal: one invocation does 341 full GCs and takes 1262 ms, as the default (351, 1243–1323 ms), the other two 90 and 654–676 ms. Pidigits (1.0–1.2 s per iteration) and Exceptions spend their GC time scavenging, which the parameter leaves alone (0.99, 0.98). 19 of the 23 AWFY and Micro benchmarks do no full GC under either setting, DeltaBlue, Havlak, MicroDict and MicroStrings 5–16 in 30 iterations (1–6 with 1.0); their geometric means (AWFY 1.06, Micro 1.00) are noise: the 10 AWFY benchmarks without a full GC give 0.96, 1.01 and 1.04 by invocation. With Pharo 12's published time scaled per real-world workload by its 1.0 / default ratio (AWFY and Micro unscaled):

| | `opt` / Pharo 12 | `opt` / Pharo 12 at 1.0 | `baseline` / Pharo 12 | `baseline` / Pharo 12 at 1.0 |
|---|---|---|---|---|
| CLBG (6) | 0.48 | 0.56 | 0.63 | 0.74 |
| the other real-world workloads (10) | 0.46 | 0.49 | 0.58 | 0.63 |
| all 39 | 0.39 | 0.41 | 0.62 | 0.65 |

`--cpu` times Samaltak by its thread's clock too (`awfy/SamaltakCPU.st`, `Smalltalk vm threadCpuMicroseconds`: all Processes, GC, JIT and the profiler's sampling); the x86-64 Samaltak times above were taken with the benchmark Process's CPU time plus the JIT's compiling, which leaves out the profiler's sampling Process. The thread's clock reads 1.3 % more under `opt`, 1.5 % under `baseline` (geometric means of medians of 3 interleaved invocations; MicroAlloc +11 % under `opt`, BinaryTrees and Pidigits +8 %, Storage +6 %), so 0.39 and 0.62 of Pharo 12 become 0.40 and 0.63.

## Real-world workloads

AWFY brings its own collections (`Vector`, `SomDictionary`, `SomSet` in `awfy/Core.st`), so it measures the compiler and VM, not the class library, its primitives or the GC at scale. These 16 workloads (`awfy/RealWorld.st`, `--suite realworld`, not part of `all`) are written once against each system's own class library; Pharo 14 runs the same source. Each answers a checksum that `verifyResult:` compares with one constant for both systems; at small sizes all 16 also answer the same on both. Sizes give 0.45–1 s per iteration on Pharo 12; an invocation takes 2.5 minutes under `opt`, 3.2 under `baseline`, 7.7 on Pharo 14.

| workload | what |
|---|---|
| BinaryTrees | CLBG binary-trees, depth 17; its long-lived tree 20 deep (2M nodes live throughout) |
| Fasta | CLBG fasta, n = 1,000,000, into a WriteStream |
| KNucleotide | CLBG k-nucleotide on fasta 75,000 read with `nextLine`: `copyFrom:to:` keys into Dictionaries of up to 375,000 Strings, frequencies sorted and printed with `printShowingDecimalPlaces:` |
| ReverseComplement | CLBG reverse-complement on fasta 1,000,000 (10 MB): `nextLine`, `reversed`, `collect:` through a table, 60-character lines |
| SpectralNorm | CLBG spectral-norm, n = 1000: Float arithmetic |
| Pidigits | CLBG pidigits, 4000 digits: LargeInteger `+`, `*`, `//` |
| Strings | 40,000 lines written with a WriteStream, then `lines`, `substrings:`, `asUppercase`, `asLowercase`, `sameAs:`, `<`, `beginsWith:`, `capitalized`, `join:`, `copyReplaceAll:with:`, `occurrencesOf:`, `includesSubstring:`, `indexOf:`, `,`, `format:` |
| Dictionaries | 200,000 String keys: Dictionary and Set insertion, hits, misses, updates, removal, enumeration; their Symbols (`asSymbol`) as keys of an IdentityDictionary and a Dictionary |
| OrderedCollections | 10 rounds of growth at both ends to 400,000, a FIFO rotated 400,000 times (`removeFirst`, `addLast:`) and a LIFO drain; breadth-first search on a 1000×1000 grid; `add:beforeIndex:`, `removeAt:` |
| Sorting | `sort:` with sort blocks on 200,000 Integers (both orders), Floats, digit Strings, Strings case-insensitively and two-key records; `asSortedCollection:`; SortedCollection `add:`, `removeFirst` |
| Enumeration | 200,000 order records, 5 passes of `select:`, `collect:`, `inject:into:`, `detect:ifNone:`, `reject:`, `count:`, `anySatisfy:`, `allSatisfy:`, `detectMax:`, `with:collect:`, `withIndexDo:`, a grouping into a Dictionary of OrderedCollections, `asSet`, `asBag` |
| PrintParse | 100,000 Integers printed (decimal, hex, padded) and read back; Floats printed and read back; CSV lines built and split |
| Exceptions | 40,000 × 14 cases: `return:`, `pass`, `retry`, `resume:` of a Warning, `outer`, `ensure:` and `ifCurtailed:` on normal and exceptional exits, a non-local return through `ensure:`, MessageNotUnderstood, ZeroDivide, a signal 20 frames deep, an ExceptionSet |
| Megamorphic | 40 random expression trees over 22 node classes, 20 passes: `evalIn:` (all classes at each send site) and a visitor (double dispatch) |
| DeepRecursion | linked lists built, mapped, summed and measured recursively 100, 1000, 10,000 and 100,000 deep (500,000 activations per depth and operation); a recursive flood fill 90,000 deep |
| Perform | 800,000 runs of a stack-machine program whose 26 instructions are selectors (`perform:`, `perform:with:`, `perform:with:with:`, `perform:withArguments:`); records copied through accessor selectors, with `respondsTo:` |

No shims: `RealWorld.st` runs unchanged on both, with the harness's platform files (`awfy/Samaltak.st`, `awfy/Pharo.st`) as for AWFY. Two Pharo 12 differences are avoided by selectors both have: `Character>>asInteger` (Pharo 12 has no `Character>>value`; `Object>>value` answers the Character) and `printStringBase:` (no `Integer>>printString:`). Pharo prints Floats from 10^6 on as `1.0e6`, Samaltak as `1000000.0`; PrintParse's Floats stay below 10^6. CLBG fannkuch-redux is left out: Array and SmallInteger code only, as AWFY's Permute.

Steady state (median of the last half of 30 iterations) and first iteration, ms, median of 3 invocations interleaved `opt`, `baseline`, Pharo 14 (`vm/tests/bench/results/{samaltak-opt,samaltak-baseline,pharo14-cog}-realworld-2026-11-14-*.csv`), 1-minute load at most 3 before each invocation, M2 Max.

| benchmark | `opt` | `baseline` | Pharo 14 | `opt` / Pharo | `baseline` / Pharo | first `opt` | first `baseline` | first Pharo | first `opt` / Pharo | first `baseline` / Pharo |
|---|---|---|---|---|---|---|---|---|---|---|
| BinaryTrees | 262.3 | 451.0 | 1640.1 | 0.16 | 0.27 | 252.9 | 443.5 | 1700.2 | 0.15 | 0.26 |
| Fasta | 395.8 | 457.1 | 562.5 | 0.70 | 0.81 | 399.7 | 467.7 | 608.4 | 0.66 | 0.77 |
| KNucleotide | 285.9 | 384.6 | 1308.9 | 0.22 | 0.29 | 303.1 | 382.2 | 1200.1 | 0.25 | 0.32 |
| ReverseComplement | 281.7 | 397.3 | 741.0 | 0.38 | 0.54 | 297.2 | 403.7 | 483.9 | 0.61 | 0.83 |
| SpectralNorm | 391.5 | 577.6 | 789.0 | 0.50 | 0.73 | 392.5 | 578.2 | 825.3 | 0.48 | 0.70 |
| Pidigits | 511.5 | 522.7 | 975.7 | 0.52 | 0.54 | 524.9 | 501.3 | 1279.9 | 0.41 | 0.39 |
| Strings | 234.9 | 303.0 | 920.6 | 0.26 | 0.33 | 248.4 | 297.9 | 912.9 | 0.27 | 0.33 |
| Dictionaries | 278.0 | 380.4 | 1482.8 | 0.19 | 0.26 | 308.6 | 476.4 | 1839.3 | 0.17 | 0.26 |
| OrderedCollections | 198.1 | 238.0 | 1211.0 | 0.16 | 0.20 | 214.3 | 240.0 | 1229.9 | 0.17 | 0.20 |
| Sorting | 469.9 | 555.3 | 702.4 | 0.67 | 0.79 | 478.8 | 556.0 | 732.7 | 0.65 | 0.76 |
| Enumeration | 194.4 | 317.5 | 657.0 | 0.30 | 0.48 | 216.2 | 315.9 | 663.3 | 0.33 | 0.48 |
| PrintParse | 464.4 | 701.2 | 1036.1 | 0.45 | 0.68 | 500.2 | 702.2 | 1056.1 | 0.47 | 0.66 |
| Exceptions | 395.9 | 427.5 | 677.5 | 0.58 | 0.63 | 403.6 | 427.1 | 719.0 | 0.56 | 0.59 |
| Megamorphic | 104.6 | 99.9 | 676.6 | 0.15 | 0.15 | 110.3 | 102.3 | 681.1 | 0.16 | 0.15 |
| DeepRecursion | 241.6 | 276.1 | 840.2 | 0.29 | 0.33 | 247.2 | 270.2 | 1009.5 | 0.24 | 0.27 |
| Perform | 251.7 | 302.1 | 771.4 | 0.33 | 0.39 | 255.2 | 302.5 | 755.1 | 0.34 | 0.40 |
| geometric mean | | | | 0.32 | 0.41 | | | | 0.33 | 0.41 |

`opt` takes 0.32 of Pharo 14's time (first iterations 0.33), `baseline` 0.41 (0.41). Both win all 16, both Fasta by the least (0.70 and 0.81). Part of the margin is GC: per iteration Pharo spends 423 ms in full GCs on ReverseComplement (its 10 MB Strings; Samaltak 15 ms), 482 ms in GC on DeepRecursion (60 ms), 414 ms on OrderedCollections (47 ms) and 285 ms scavenging on Pidigits (under 1 ms). Pharo 14 takes 1.19× Pharo 12's time on these (`results/pharo12-cog-realworld-2026-11-07-*.csv`): BinaryTrees 2.75×, OrderedCollections 1.78, Dictionaries 1.51, KNucleotide 1.44, Strings 1.32. Not in its GCs, which take as long as 12's, and not in its image: Pharo 12's image on Pharo 14's VM is as slow (BinaryTrees 1593 ms against 557 on its own VM, DeltaBlue 78 against 41).

Pidigits is LargeInteger arithmetic in C. Its iterations take 490 to 535 ms under either tier, the level changing between invocations and within one (`baseline`'s second: 495, then 525). Megamorphic: `opt` 104.6 ms, `baseline` 99.9; every send is megamorphic, so `opt` inlines nothing.

## The Benchmarks Game's Pharo programs

The [Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/)'s own Pharo programs, unchanged (`vm/tests/bench/benchmarksgame/`, Revised BSD, `LICENSE.md`): the 13 of its 15 that run on Pharo (knucleotide-pharo-5 and regexredux-pharo-1 fail there). Samaltak files in `benchmarksgame/Samaltak.st` first (Pharo's `Stdio` streams, Zinc's stream wrappers, ScaledDecimal printing, `asciiValue`, `findString:`, the global `newline` revcomp-pharo-1 reads undeclared) and reads each program with `d` exponents written `e` and `StdioStream instance methodsFor:` as `StdioStream methodsFor:`; Pharo files in the program as `benchmarksgame/pharo14.py` writes it (one method per preamble, the package `BenchmarksGame`: Pharo 14 rejects `benchmarks game`, `newline` declared). Each run is a fresh process; run is `BenchmarksGame do: N` timed inside the image (JIT and GC included), process the whole process (start, image load, file-in, quit). knucleotide and revcomp read fasta 2,500,000 (25 MB). Median of 3 rounds, Pharo 14 and `opt` alternating first, 1-minute load below 3 before each run, M2 Max (`vm/tests/bench/results/benchmarksgame-2026-11-15.txt`), ms:

| program | N | Pharo 14 run | Pharo 14 process | `opt` run | `opt` process | run `opt` / Pharo | process `opt` / Pharo |
|---|---|---|---|---|---|---|---|
| binarytrees-pharo-1 | 18 | 3873 | 4209 | 581 | 619 | 0.15 | 0.15 |
| fannkuchredux-pharo-1 | 10 | 1260 | 1586 | 419 | 456 | 0.33 | 0.29 |
| fasta-pharo-1 | 2,500,000 | 6340 | 6675 | 1099 | 1138 | 0.17 | 0.17 |
| fasta-pharo-2 | 2,500,000 | 2563 | 2912 | 1081 | 1123 | 0.42 | 0.39 |
| knucleotide-pharo-1 | | 29408 | 29787 | 8482 | 8533 | 0.29 | 0.29 |
| knucleotide-pharo-2 | | 24146 | 24492 | 8281 | 8333 | 0.34 | 0.34 |
| mandelbrot-pharo-1 | 4000 | 11725 | 12045 | 5162 | 5202 | 0.44 | 0.43 |
| mandelbrot-pharo-2 | 4000 | 11380 | 11722 | 5138 | 5175 | 0.45 | 0.44 |
| nbody-pharo-1 | 5,000,000 | 7118 | 7503 | 2946 | 2993 | 0.41 | 0.40 |
| pidigits-pharo-1 | 10,000 | 6187 | 6512 | 3079 | 3115 | 0.50 | 0.48 |
| revcomp-pharo-1 | | 9906 | 10250 | 1213 | 1253 | 0.12 | 0.12 |
| revcomp-pharo-2 | | 1775 | 2088 | 891 | 929 | 0.50 | 0.44 |
| spectralnorm-pharo-1 | 2000 | 2808 | 3130 | 1552 | 1587 | 0.55 | 0.51 |
| geometric mean | | | | | | 0.33 | 0.31 |

`opt` wins all 13 with the same output. Outside the timed run Pharo 14 spends about 330 ms (starting and quitting alone 230), Samaltak about 40 (16).

    vm/tests/bench/benchmarksgame.sh [-n 3] [-o file] [--small] [program ...]   # --small: sizes for checking output; VM, IMAGE, VMARGS; PHARO_VM, PHARO_IMAGE

## Where Pharo is faster

17 workloads chosen because Pharo 12 wins them (`awfy/Adverse.st`, `--suite adverse`, not part of `all`), the same source on both, each checksum one constant. On the x86-64 machine above: CPU time (`--cpu`), steady state, median of 3 invocations of 30 iterations interleaved `opt`, `baseline`, Pharo 12 (`vm/tests/bench/results/{samaltak-x86-opt,samaltak-x86-baseline,pharo12-cog-x86}-adverse-2026-11-15-*.csv`), ms. An invocation takes about 3 minutes under `opt`.

| benchmark | what | `opt` | `baseline` | Pharo 12 | `opt` / Pharo | `baseline` / Pharo |
|---|---|---|---|---|---|---|
| AdvPointDict | 70×70 grid, Points as Dictionary keys | 394.4 | 651.0 | 1.9 | 205 | 339 |
| AdvPackedKeys | 70×70 grid, `x * 65536 + y` as Dictionary keys and Set elements | 506.8 | 475.8 | 2.1 | 246 | 231 |
| AdvFloatSet | 15,000 Floats in hundredths: `asSet`, a histogram Dictionary, misses | 560.7 | 510.7 | 9.8 | 57 | 52 |
| AdvArrayKeys | 65×65 grid, `{x. y}` as Dictionary keys | 242.6 | 492.5 | 3.4 | 72 | 147 |
| AdvAlignedInts | 9,000 multiples of 4096 in a Set and a Dictionary | 378.1 | 355.7 | 3.7 | 101 | 95 |
| AdvHugePrint | `3 raisedTo: 100000` printed in decimal and hex | 282.3 | 282.8 | 84.0 | 3.36 | 3.37 |
| AdvBigPrint | `3 raisedTo: 20000` printed and read back 4 times, 3,000 51-digit Integers printed | 71.6 | 76.0 | 32.7 | 2.19 | 2.33 |
| AdvPingPong | 100,000 round trips between 2 Processes through 2 Semaphores | 224.1 | 221.4 | 22.1 | 10 | 10 |
| AdvDeepPingPong | 20,000 round trips, each Process 50 calls deep | 44.7 | 44.5 | 4.4 | 10 | 10 |
| AdvYield | 4 Processes, 25,000 `Processor yield` each | 103.1 | 102.5 | 9.8 | 11 | 11 |
| AdvForkJoin | 3,000 times `fork`, then wait for it | 519.7 | 422.9 | 8.1 | 64 | 52 |
| AdvFork | 3,000 Processes forked at once, a mutual-exclusion Semaphore | 439.7 | 430.0 | 8.2 | 53 | 52 |
| AdvBecome | 50 `becomeForward:` | 634.3 | 583.7 | 0.9 | 741 | 682 |
| AdvValueWithArguments | 2,000,000 `valueWithArguments:` of 1-argument blocks | 275.6 | 319.9 | 142.2 | 1.94 | 2.25 |
| AdvBlocks | blocks of 0–4 arguments from an Array, 150,000 rounds: `value…`, `valueWithArguments:`, `numArgs`, `cull:` | 120.8 | 133.6 | 81.4 | 1.48 | 1.64 |
| AdvPerform3 | 900,000 each of `perform:with:with:with:` and `perform:withArguments:` of 3 | 186.0 | 186.5 | 104.6 | 1.78 | 1.78 |
| AdvFractions | 40 rounds: a harmonic sum of 120 terms, a continued fraction 60 deep | 33.9 | 37.6 | 28.3 | 1.20 | 1.33 |

The hash-table workloads are quadratic on Samaltak and shrunk to 0.24–0.65 s an iteration; their ratios grow with size (a screening invocation, 3 iterations: AdvPointDict at 120×120 `opt` 5130 ms, Pharo 6.0, 855; AdvPackedKeys at 150×150 12,404 and 20.6, 602). `opt`'s steady states of AdvPointDict, AdvPackedKeys and AdvFloatSet range up to 1.7–1.8× between invocations (AdvPointDict 385–676 ms). AdvFractions' first iteration takes 101.4 ms under `opt` (2.71 of Pharo's 37.4): `opt` compiles 70–72 ms and deoptimizes 29 times in an invocation.

Causes:

- Hash tables: the capacity is a power of two and `scanFor:` probes linearly from `hash \\ size` without mixing (`Set.st:76-83`, `Dictionary.st:219-226`, `HashedCollection.st:6`), so hashes that share their low bits or fill a narrow range collide. From the hash functions (computed outside the VM): `Point>>hash` (`Point.st:68-69`) gives AdvPointDict's 4,900 Points 344 values; `SmallInteger>>hash` is the value (`SmallInteger.st:75-76`), so AdvPackedKeys' 4,900 keys start in 70 of 16,384 slots and AdvAlignedInts' 9,000 in 8 of 32,768; a non-integral Float hashes as its exact Fraction, numerator `bitXor:` denominator (`Float.st:65-69`, `Fraction.st:107-108`): AdvFloatSet's 12,840 start in 330 of 32,768; `SequenceableCollection>>hash` (`SequenceableCollection.st:178-182`) puts AdvArrayKeys' 4,225 `{x. y}` in 2,049 consecutive slots.
- Huge Integers: `LargePositiveInteger>>printString:` (`LargePositiveInteger.st:40-55`) divides the whole number twice (`\\`, `//`) per 9 digits; `NumberParser>>parseDigitsBase:` (`NumberParser.st:65`) multiplies the whole value by 10 per digit.
- Process switches: `Scheduler>>transferTo:` reads the thread's CPU clock at every switch (`Scheduler.st:424`, `threadCpuUs` `:101-110`, `CLOCK_THREAD_CPUTIME_ID`), a system call here: 825 ns against 26 for `CLOCK_MONOTONIC` (a C loop); AdvPingPong switches 200,000 times an iteration. With the clock shimmed to `CLOCK_MONOTONIC` (`LD_PRELOAD`; wall time, median of 7 runs) AdvPingPong takes 44 ms instead of 221, AdvDeepPingPong 8 instead of 44, AdvYield 22 instead of 103.
- Forks: `Process class>>register:` (`Process.st:227-238`) scans the registry WeakArray from its first slot for a free one at every fork; a terminated Process's slot frees when a GC clears it (79,600–89,400 slots over AdvForkJoin's 30 iterations, all by scavenges). With `register:` recompiled to answer its argument (wall time, median of 7 runs) AdvForkJoin takes 10 ms instead of 386, AdvFork 8 instead of 396.
- `becomeForward:` (`ObjectPrimitives.st:243-249`) does a full GC, then `GarbageCollector>>becomeForward:to:` (`GarbageCollector.st:529`) walks old space: 12.7 ms a call. Spur leaves a forwarder instead.
- Leaving machine code: `valueWithArguments:` (`ControlPrimitives.st:52-61`) activates the block in the interpreter and machine code calling it leaves (`JitBaselineRuntime.st:808-851`): AdvValueWithArguments counts one exit per call. Machine code's `perform:withArguments:` takes an Array of up to 2 (`JitBaselineCompiler.st:1040`, `JitBaselineRuntime.st:742`): AdvPerform3 counts one exit per `perform:withArguments:`, none per `perform:with:with:with:`.

Tried, and Samaltak won: large heaps, old→young stores, large objects, weak arrays, tenuring; strings, streams, sorting, deep copies; polymorphic sends to 4–8 classes, non-local returns, unwinding, context walks, reflection, LargeInteger hashing arithmetic.

## GC mutator progress

From the repository root, with a built VM and image:

```sh
vm/build/samaltak --eden 1 --jit none build/samaltak.image --headless \
    --eval "$(cat vm/tests/bench/gc-mutator-progress.st)"
```

After tenuring a 16,384-node ring and warming up, the benchmark runs 10,000
batches of 256 updates on a 1 MiB eden. Each update replaces a retained record
and allocates a scratch array that does not escape. The `mutator` line reports
completed batches, elapsed wall time and max/p99/p99.9 completion gaps (nearest
rank, in µs). The timed loop takes one monotonic clock reading per batch and
writes to a preallocated array; stats snapshots bracket the loop and reporting
follows both measurements.

Gaps include mutator work, any GC, and OS scheduling; they are not GC pause
measurements. Each line reports separate deltas for scavenge/full GC counts and
VM GC time counters. The `explicit_full_gc` line times a synchronous full GC
with the ring still live, outside the batch samples. A run without collections
in the batch window is invalid. For comparisons, use the same image, flags
and host, and repeat runs. This is observational, not a CI timing threshold.

## Extremem

[Extremem](https://github.com/corretto/heapothesys/tree/master/Extremem) (Amazon, Apache-2.0, `extremem/NOTICE`) is a GC workload modelled on an in-memory store. Simulated customers search 20 000 products by keyword, ponder a randomly written review of each match for 200 s, then buy (40 %), save for later (40 %, kept 10 minutes) or abandon. Server threads transact the sales, expire the saved products and every minute or so replace customers and products, which mutates the old generation. With its defaults, the 1440 customers' pending reviews are the bulk of a live set of ~110 MB (Java), refreshed at ~0.5–1 GB/s of allocation.

The port (`extremem/Extremem.st`, one source for Samaltak and Pharo; `extremem/Extremem.java`, its twin with Extremem's own data structures: `TreeMap`, `HashSet<Long>`, `String +=`) is a discrete-event simulation in virtual time. Every customer and server thread is an actor whose sleeps advance a virtual clock, in one process that runs as fast as it can. Objects live across the same work as in Extremem, and every system does the same work: all three answer the same tally and purchase hash. Differences from Extremem:

- One thread, virtual time; Extremem's locks, `PhasedUpdates` and `FastAndFurious` modes, and its memory accounting are left out. Decisions due after the end are not run.
- The dictionary is 25 000 generated words, with letters drawn by English frequency, instead of `/usr/share/dict/words`.
- Park-Miller random numbers (multiplier 48271), each actor its own stream, seeded from a second generator (multiplier 16807; consecutive outputs of one stream as seeds would make shifted copies of it).
- Search results are sorted by product id, since hash order differs between systems and decides which product gets which review.
- The fuzzy match of a review searches each substring once (Extremem twice) and multiplies Doubles (Extremem Floats).

Each event's wall time is a latency: a customer's preparation (search, reviews) or decision (ranking reviews by substring search). A GC pause on Samaltak and Pharo is the GC time the VM counted across an event with a GC (Pharo counts whole milliseconds); on the JVM, a collector's safepoint (time to safepoint included) or a ZGC allocation stall, from `-Xlog:safepoint` and `-Xlog:gc`.

    vm/tests/bench/extremem.sh [--pharo | --java PATH] [--vm-args ARGS] [--pharo-init EXPR] [-o FILE] [name=value ...]   # e.g. simulationMinutes=35 warmupMinutes=15
    vm/tests/bench/extremem_summary.py LABEL=FILE[,FILE...] ...

Linux x86-64, the AMD EPYC 7B13 cloud VM with 2 vCPUs as above; Samaltak built with gcc -O2 (no profile), Pharo 14 (`Pharo-14.0.0+SNAPSHOT.build.790`, VM 12.0.6), Temurin JDK 27.0.1 with fixed heaps: per collector the one at which its peak RSS is Samaltak's (275–328 MB), and 256 MB, 512 MB and 1 GB (2.3, 4.7 and 9.3 times the live set; below ~120 MB Serial collects without end). Samaltak does not get down to Pharo's 200 MB: its full GC copies the old space, and with `--max-heap 128` it still takes 294 MB and runs 189 full GCs instead of 7 (`--max-heap 96` is out of memory). So Pharo also runs with the full GC due when the old space has doubled, as on Samaltak, instead of grown by a third (`--pharo-init 'Smalltalk vm parameterAt: 55 put: 1.0'`). Extremem's defaults; 35 simulated minutes, the first 15 a warmup: decisions start at minute 3, saved products expire from minute 10. Medians of 3 invocations, interleaved (`vm/tests/bench/results/extremem-*-2026-11-17-*.txt`). The JVM's collectors use both vCPUs; Samaltak and Pharo collect in their one thread. Measured s: the 20 measured minutes; CPU s and peak RSS: the whole process, setup and warmup included.

| configuration | measured s | prep p50 | prep p99 | prep p99.9 | prep max | decision p50 | decision p99 | decision p99.9 | decision max | CPU s | peak RSS MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Samaltak `opt` | 13.8 | 0.56 | 1.70 | 2.9 | 51.3 | 1.08 | 3.36 | 5.3 | 50.0 | 25.6 | 386 |
| Samaltak `baseline` | 19.3 | 0.89 | 2.59 | 4.6 | 51.8 | 1.43 | 4.34 | 6.3 | 49.8 | 32.5 | 369 |
| Pharo 14 | 74.1 | 1.49 | 5.68 | 8.6 | 195.0 | 7.50 | 23.47 | 37.7 | 216.9 | 120.8 | 202 |
| Pharo 14, full GC at double | 73.4 | 1.61 | 6.31 | 8.9 | 254.3 | 7.30 | 22.82 | 36.4 | 63.7 | 119.9 | 280 |
| JDK 27 Serial, 328 MB | 13.1 | 0.47 | 10.04 | 11.8 | 205.5 | 0.89 | 2.93 | 11.5 | 196.2 | 25.8 | 387 |
| JDK 27 Parallel, 323 MB | 12.0 | 0.43 | 4.98 | 7.2 | 149.9 | 0.89 | 2.96 | 6.6 | 24.7 | 25.0 | 385 |
| JDK 27 G1, 307 MB | 14.3 | 0.53 | 2.17 | 25.3 | 34.9 | 1.02 | 3.67 | 16.6 | 28.5 | 36.5 | 384 |
| JDK 27 ZGC, 275 MB | 16.6 | 0.78 | 3.89 | 9.9 | 19.9 | 1.08 | 3.85 | 9.9 | 18.6 | 51.0 | 393 |
| JDK 27 Shenandoah, 312 MB | 28.8 | 0.59 | 2.74 | 300.7 | 385.7 | 1.20 | 4.34 | 217.4 | 374.2 | 77.1 | 390 |
| JDK 27 Shenandoah generational, 308 MB | 14.6 | 0.62 | 1.82 | 4.8 | 40.6 | 1.10 | 3.58 | 7.4 | 13.5 | 41.9 | 391 |
| JDK 27 Serial, 256 MB | 13.3 | 0.45 | 8.36 | 10.1 | 194.6 | 0.90 | 3.03 | 9.4 | 192.4 | 26.1 | 315 |
| JDK 27 Parallel, 256 MB | 12.4 | 0.45 | 4.59 | 6.6 | 158.0 | 0.90 | 3.04 | 6.1 | 147.3 | 25.5 | 319 |
| JDK 27 G1, 256 MB | 14.7 | 0.55 | 9.57 | 24.7 | 29.6 | 1.04 | 3.73 | 12.9 | 26.2 | 38.9 | 329 |
| JDK 27 ZGC, 256 MB | 17.7 | 0.86 | 4.71 | 10.5 | 25.8 | 1.15 | 4.56 | 9.8 | 21.3 | 56.6 | 372 |
| JDK 27 Shenandoah, 256 MB | 38.7 | 0.64 | 96.30 | 324.7 | 366.3 | 1.15 | 3.89 | 211.5 | 341.4 | 91.2 | 335 |
| JDK 27 Shenandoah generational, 256 MB | 15.4 | 0.68 | 2.14 | 9.1 | 45.7 | 1.12 | 3.75 | 6.0 | 12.9 | 44.7 | 337 |
| JDK 27 Serial, 512 MB | 12.7 | 0.45 | 1.99 | 16.7 | 231.4 | 0.89 | 2.87 | 16.3 | 27.4 | 24.9 | 567 |
| JDK 27 Parallel, 512 MB | 12.2 | 0.47 | 1.84 | 9.3 | 154.7 | 0.90 | 2.90 | 8.2 | 13.4 | 25.5 | 580 |
| JDK 27 G1, 512 MB | 13.0 | 0.50 | 1.62 | 22.7 | 41.6 | 0.93 | 3.03 | 20.7 | 32.7 | 29.4 | 592 |
| JDK 27 ZGC, 512 MB | 14.0 | 0.63 | 1.87 | 8.3 | 23.2 | 0.99 | 3.23 | 9.1 | 15.7 | 38.1 | 568 |
| JDK 27 Shenandoah, 512 MB | 18.0 | 0.69 | 2.60 | 31.5 | 380.5 | 1.20 | 4.00 | 12.0 | 33.2 | 59.3 | 594 |
| JDK 27 Shenandoah generational, 512 MB | 14.0 | 0.62 | 1.79 | 3.0 | 10.6 | 1.03 | 3.38 | 5.3 | 29.1 | 36.9 | 601 |
| JDK 27 Serial, 1 GB | 12.9 | 0.50 | 1.66 | 29.1 | 41.3 | 0.90 | 2.80 | 27.0 | 30.9 | 25.2 | 925 |
| JDK 27 Parallel, 1 GB | 11.9 | 0.48 | 1.47 | 14.8 | 22.3 | 0.90 | 2.83 | 14.2 | 25.9 | 25.1 | 956 |
| JDK 27 G1, 1 GB | 12.0 | 0.46 | 1.37 | 34.4 | 36.2 | 0.91 | 2.80 | 5.2 | 37.3 | 24.8 | 972 |
| JDK 27 ZGC, 1 GB | 12.9 | 0.57 | 1.66 | 3.7 | 12.5 | 0.94 | 2.96 | 4.8 | 20.6 | 33.3 | 954 |
| JDK 27 Shenandoah, 1 GB | 15.1 | 0.67 | 1.95 | 2.8 | 12.9 | 1.13 | 3.74 | 8.1 | 11.7 | 49.9 | 1123 |
| JDK 27 Shenandoah generational, 1 GB | 13.3 | 0.57 | 1.63 | 2.7 | 9.5 | 0.99 | 3.22 | 5.8 | 17.4 | 34.0 | 1134 |

GC pauses in the 20 measured minutes, per invocation; percentiles and maximum over the pauses of all 3, the last 9 columns how many pauses an invocation had per range of duration (ms):

| configuration | pauses | sum ms | % of time | p50 ms | p90 ms | p99 ms | p99.9 ms | max ms | <0.5 | 0.5–1 | 1–2 | 2–5 | 5–10 | 10–20 | 20–50 | 50–100 | ≥100 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Samaltak `opt` | 701 | 418 | 3.0 | 0.37 | 0.58 | 0.83 | 52.77 | 65.3 | 566 | 131 | 1 | 0 | 0 | 0 | 2 | 1 | 0 |
| Samaltak `baseline` | 736 | 416 | 2.2 | 0.35 | 0.55 | 0.74 | 50.17 | 51.6 | 621 | 113 | 0 | 0 | 0 | 0 | 2 | 1 | 0 |
| Pharo 14 | 685 | 3147 | 4.3 | 3.00 | 4.00 | 6.00 | 215.00 | 222.0 | 0 | 0 | 0 | 672 | 7 | 0 | 0 | 0 | 6 |
| Pharo 14, full GC at double | 685 | 2565 | 3.6 | 3.00 | 4.00 | 5.00 | 251.00 | 256.0 | 0 | 0 | 0 | 676 | 7 | 0 | 0 | 0 | 2 |
| JDK 27 Serial, 328 MB | 131 | 1610 | 12.4 | 9.19 | 10.29 | 204.38 | 214.51 | 214.5 | 0 | 0 | 0 | 1 | 109 | 19 | 0 | 0 | 2 |
| JDK 27 Parallel, 323 MB | 119 | 978 | 8.1 | 4.46 | 5.76 | 146.12 | 152.49 | 152.5 | 0 | 0 | 0 | 82 | 33 | 0 | 0 | 0 | 3 |
| JDK 27 G1, 307 MB | 127 | 1286 | 9.0 | 11.07 | 22.11 | 30.13 | 47.86 | 47.9 | 23 | 1 | 21 | 0 | 11 | 52 | 19 | 0 | 0 |
| JDK 27 ZGC, 275 MB | 1120 | 240 | 1.4 | 0.11 | 0.13 | 5.26 | 15.77 | 21.6 | 1079 | 4 | 4 | 3 | 9 | 2 | 0.3 | 0 | 0 |
| JDK 27 Shenandoah, 312 MB | 226 | 13665 | 47.1 | 0.21 | 218.87 | 334.20 | 419.02 | 419.0 | 133 | 0.7 | 3 | 4 | 9 | 15 | 8 | 0.3 | 57 |
| JDK 27 Shenandoah generational, 308 MB | 819 | 176 | 1.2 | 0.15 | 0.22 | 0.27 | 40.86 | 41.5 | 807 | 0.7 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| JDK 27 Serial, 256 MB | 168 | 1981 | 14.7 | 7.54 | 8.49 | 192.44 | 204.85 | 204.9 | 0 | 0 | 1 | 4 | 157 | 1 | 0.3 | 0 | 4 |
| JDK 27 Parallel, 256 MB | 151 | 1184 | 9.5 | 3.99 | 5.10 | 148.31 | 172.13 | 172.1 | 0 | 0 | 0.7 | 132 | 14 | 0 | 0 | 0 | 4 |
| JDK 27 G1, 256 MB | 161 | 1417 | 9.8 | 9.19 | 20.33 | 27.53 | 31.56 | 31.6 | 27 | 5 | 22 | 0.3 | 42 | 49 | 17 | 0 | 0 |
| JDK 27 ZGC, 256 MB | 1556 | 312 | 1.8 | 0.11 | 0.13 | 2.46 | 10.43 | 36.6 | 1742 | 7 | 7 | 13 | 5 | 2 | 0.3 | 0 | 0 |
| JDK 27 Shenandoah, 256 MB | 274 | 23478 | 60.7 | 0.20 | 246.52 | 342.17 | 365.15 | 365.1 | 145 | 0 | 0 | 0 | 0 | 0.3 | 2 | 39 | 87 |
| JDK 27 Shenandoah generational, 256 MB | 1151 | 360 | 2.4 | 0.14 | 0.20 | 0.28 | 42.95 | 52.7 | 1157 | 0.7 | 0.3 | 0.7 | 0.7 | 2 | 3 | 0.3 | 0 |
| JDK 27 Serial, 512 MB | 84 | 1423 | 10.9 | 14.50 | 16.52 | 229.28 | 257.87 | 257.9 | 0 | 0 | 0 | 0 | 2 | 81 | 0 | 0 | 1 |
| JDK 27 Parallel, 512 MB | 75 | 674 | 5.4 | 6.99 | 8.18 | 153.76 | 162.94 | 162.9 | 0 | 0 | 0 | 0.3 | 73 | 0.3 | 0 | 0 | 1 |
| JDK 27 G1, 512 MB | 54 | 932 | 7.1 | 19.48 | 28.39 | 40.74 | 43.06 | 43.1 | 6 | 0.3 | 6 | 0 | 0.3 | 22 | 20 | 0 | 0 |
| JDK 27 ZGC, 512 MB | 239 | 30 | 0.2 | 0.11 | 0.13 | 0.72 | 17.98 | 18.0 | 239 | 0.7 | 0.3 | 0.7 | 1 | 0.3 | 0 | 0 | 0 |
| JDK 27 Shenandoah, 512 MB | 164 | 2422 | 13.4 | 0.32 | 20.10 | 340.44 | 381.04 | 381.0 | 127 | 0 | 0.3 | 2 | 7 | 11 | 11 | 1 | 5 |
| JDK 27 Shenandoah generational, 512 MB | 279 | 60 | 0.4 | 0.20 | 0.33 | 0.38 | 0.42 | 0.4 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| JDK 27 Serial, 1 GB | 42 | 1172 | 9.1 | 27.52 | 29.86 | 40.44 | 59.17 | 59.2 | 0 | 0 | 0 | 0 | 0 | 0 | 42 | 0.3 | 0 |
| JDK 27 Parallel, 1 GB | 37 | 497 | 4.2 | 13.34 | 14.37 | 20.30 | 28.71 | 28.7 | 0 | 0 | 0 | 0 | 0 | 36 | 0.7 | 0 | 0 |
| JDK 27 G1, 1 GB | 20 | 677 | 5.6 | 33.97 | 35.52 | 47.54 | 47.54 | 47.5 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 0 |
| JDK 27 ZGC, 1 GB | 74 | 8 | 0.1 | 0.11 | 0.12 | 0.14 | 0.22 | 0.2 | 76 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| JDK 27 Shenandoah, 1 GB | 119 | 25 | 0.2 | 0.18 | 0.29 | 0.35 | 0.37 | 0.4 | 118 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| JDK 27 Shenandoah generational, 1 GB | 101 | 23 | 0.2 | 0.21 | 0.35 | 0.43 | 0.49 | 0.5 | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Samaltak's GC takes 3 % of the time and pauses 0.37 ms at the median, 0.83 ms at p99: a scavenge copies little, since what survives one (the pending reviews) is tenured. Its 3 full GCs (140 MB old space) take ~50 ms each and are its longest latencies. Of the collectors that stop the world, none pauses less: with the memory Samaltak takes, Serial and Parallel collect the young generation in 4–10 ms and the old in 150–215 ms, G1 in 11–48 ms, and spend 8–12 % of the time in pauses. The concurrent ones pause 0.11–0.15 ms at the median, for 1.7–2 times the CPU time of Parallel with that memory: ZGC up to 22 ms, generational Shenandoah 41 ms; they stay within 0.5 ms at 1 GB (generational Shenandoah from 512 MB on), for 1.3–1.5 times the CPU time. Non-generational Shenandoah degenerates below 512 MB (47–61 % of the time in pauses, 300 ms latencies). Pharo's scavenges take ~3 ms, its 6 full GCs ~200 ms (4 % of the time); with the full GC at double it runs 2, takes 280 MB and as long.

Samaltak `opt` runs the measured minutes 5.4 times faster than Pharo 14. With the same memory it is 15 % slower than the JVM with Parallel and 5 % slower than with Serial, and faster than with G1, ZGC or either Shenandoah. Without the pauses, the mutator takes 13.4 s against 11.0 s under Parallel: the decisions, substring searches in short Strings, take 1.2 times as long (1.08 against 0.89 ms at the median), the preparations, hashing and catenating Strings, 1.3 times. `baseline` is 40 % slower than `opt`.

## Against C

Basic C versions of the eight Shootout (CLBG) programs the suites run (`vm/tests/bench/clbg/*.c`: the six above and AWFY's Mandelbrot and NBody) do the Smalltalk versions' work, same sizes, same algorithm, same checksum: `malloc`/`free` per node in binary-trees, GMP in pidigits, a growing buffer where Smalltalk has a WriteStream, an open-addressing hash table of positions in k-nucleotide; inputs made before timing, as the benchmarks' `initialize`. `vm/tests/bench/clbg.sh [-n 10] [-o file] [program ...]` builds them with `cc -O2` and prints what `awfy.sh` prints. On the x86-64 machine above (gcc 12, CPU time, median of 3 invocations of 10 iterations, `vm/tests/bench/results/c-gcc-O2-x86-2026-11-15-*.csv`), against the Samaltak and Pharo 12 medians of the x86-64 tables:

| program | C | `opt` | `baseline` | Pharo 12 | `opt` / C | `baseline` / C | Pharo / C |
|---|---|---|---|---|---|---|---|
| BinaryTrees | 649.0 | 421.3 | 720.4 | 925.5 | 0.6 | 1.1 | 1.4 |
| Fasta | 162.6 | 538.1 | 701.0 | 742.2 | 3.3 | 4.3 | 4.6 |
| KNucleotide | 65.1 | 623.5 | 784.1 | 1210.7 | 9.6 | 12.0 | 18.6 |
| ReverseComplement | 27.0 | 446.0 | 689.8 | 1235.0 | 16.5 | 25.5 | 45.7 |
| SpectralNorm | 56.2 | 729.1 | 845.6 | 1008.9 | 13.0 | 15.1 | 18.0 |
| Pidigits | 131.0 | 427.3 | 436.2 | 1579.0 | 3.3 | 3.3 | 12.1 |
| Mandelbrot | 43.0 | 148.1 | 199.7 | 300.3 | 3.4 | 4.6 | 7.0 |
| NBody | 33.0 | 224.2 | 503.9 | 517.4 | 6.8 | 15.3 | 15.7 |

`opt` beats the C binary-trees: allocating from eden and scavenging costs less than `malloc` and `free`. At the benchmarks game's size (depth 21: 611 M nodes, `-DMAX_DEPTH=21 -DEXPECTED=611669342`, `BinaryTrees new run: 21 liveDepth: 20`) an iteration takes `opt` 13.4 s, 5.1 of them in 1149 scavenges and 26 full GCs; Pharo 12 23.5 s and Pharo 14 25.3 s, about 13 of them in their GCs; C 16.4 s.

The listings of the optimized SpectralNorm and Fasta loops show where the rest goes. A Float result is encoded as a SmallFloat64 after every operation (about 15 instructions), even where the next operation takes the double from its register. In a method whose arithmetic saw Floats, SmallInteger operations get a Float path too, loop counters included (`j + 1`, `i + j - 2`, `last * 3877 + 29573 \\ 139968`): tag checks on every operand. Comparisons with a Float path make `true` or `false` and test it instead of branching on the flags. Loop variables come from their frame slots at every use.

## Compile speed

How fast each JIT compiles the same code (`vm/tests/bench/compile-speed.sh`, `vm/tests/bench/results/compile-speed-2026-11-14.csv`; M2 Max, a fresh VM process per round, 1-minute load ≤ 3). Corpus: the 630 methods of the AWFY benchmark classes (`Core` and the 14 benchmarks), identical sources, each behind an early exit, `probeNil ifNil: [^0]. <the body>` (`compile_speed.py gen`): sent with nil it runs in O(1), while the JIT compiles every bytecode. The table is the 591 methods with no real block on either system, 30 rounds: Pharo's CompiledBlocks are compiled when they run, which here they do not. Bytes and instructions are each system's own bytecode. `opt` runs with `--jit-flags eager` and inlines only where a receiver's class is known statically (32 % more bytecode than the methods'; 57 of 593 units).

| | µs / method | µs / bytecode byte | µs / instruction | machine-code bytes / bytecode byte |
|---|---|---|---|---|
| `baseline` | 2.85 | 0.109 | 0.146 | 32.3 |
| Pharo 14 Cog | 3.14 | 0.128 | 0.135 | 20.4 |
| `opt`, no feedback | 18.5 | 0.71 | 0.95 | 33.9 |

`baseline` compiles as fast as Cog: 3.40 against 3.33 µs a method by the wall clock of the compiling send, 9 % less per method and 15 % less per bytecode byte by the counters (Cog's counts whole milliseconds), 8 % more per instruction (Samaltak has fewer, bigger instructions for the same source), and it emits 1.6× the machine code. Over all 630 methods: 3.25 against 3.74 µs a method. With real feedback (AWFY, default thresholds, 30 iterations, median of 3, `results/samaltak-opt-compile-2026-11-08-*.csv`) `opt` takes 170 ms for 507 units (methods, blocks, loops), 336 µs a unit: 56 bytecode bytes of its own and 330 inlined (a scratch VM build counted what the SSA builder translated, `results/compile-speed-2026-11-08-opt-units.txt`), so 6.0 µs per byte of the unit, 0.87 µs per byte with the inlined ones (about 7× `baseline`), 6.1 KB of machine code a unit, 16 bytes per byte with the inlined ones. Share of the AWFY first iteration (14 benchmarks, 5 rounds, the VMs' counters): `baseline` 3.1 of 1043 ms (0.3 %), Cog 2.4 of 1722 ms (0.1 %), `opt` 158 of 662 ms (24 %; DeltaBlue 80 %, Json 72 %).

Method. Samaltak: its counters around the compiler (`jitCompileMicroseconds`, `optCompileMicroseconds`). Cog: Pharo 14's own, `Smalltalk vm parameterAt:` 75–78 (methods and blocks, microseconds summed around `cogselector` and `cogFullBlockMethodnumCopied`, reported in whole milliseconds, so the mean of the rounds), with a 32 MB code zone (`--codeSize`) so that nothing compacts; the default 1.25 MB zone does. Probes are sent six times from interpreted drivers (Cog compiles at the second send, `baseline` and `opt` at the third). Two independent checks: the compiling send's wall clock, its time minus the last sends': Cog 3.33 µs a method against its counter's 3.14, `baseline` 3.40 against 2.85 (the send path and installing the code are outside its counter), `opt` 22.6 against 21.2 by its two compilers; native sampling (Pharo 12, 2026-11-08; `sample`, 1 ms, thousands of rounds in one process, code dropped between rounds): `cogselector` 28.6 % of the samples against 28.3 % of the run by the counter, `jit_runtime_compile` 75.2 against 70.4 % (the counter leaves out its clock reads). These methods compile in a row; one at a time in the AWFY runs, with tier-up counters under `opt`, the lower tier took 4.3 µs a method, 0.20 µs per bytecode byte.

    vm/tests/bench/compile-speed.sh [corpus|awfy|all] [-n 30] [-a 5] [-o results.csv]   # needs vm/build/samaltak, build/samaltak.image and Pharo 14 ($PHARO_VM, $PHARO_IMAGE)
