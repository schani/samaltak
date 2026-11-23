# samaltak-ctl

Drives a running Samaltak image through its control service (`ControlServer`, `src/System-Remote/`). Node ≥ 18, no deps. Session: `--session` / `$SAMALTAK_SESSION`, default `samaltak`; session info lives in `$TMPDIR/samaltak-ctl/<session>.json`, the image's output in `<session>.log`.

    open [--headless] [--hidden] [--image path] [--port n] [--window-size WxH] [--source-dir d]
    open --uefi [--headless] [--port n] [--window-size WxH]   # the VM on UEFI in QEMU (make uefi-control, docs/uefi.md)
    snapshot [ref] [--depth n] [--bounds]       find <text>
    click|dblclick|rightclick <ref|x,y> [--mods Shift+Meta]      hover <ref|x,y> [--at spec]   (--at: e.g. a PixelView pixel 4,7)
    type <ref> <text> [--end|--start|--replace] [--delay ms] [--preedit]   (the image types one character every ms, default 45; --preedit: one input-method composition event, '' ends it)
    key <combo> [ref]   (Meta+p, Escape, Meta+.; Meta = platform modifier)
    drag <ref> <dx> <dy> | drag <ref> <ref>      resize <ref> <w> <h>      scroll <ref> [dy]
    select <ref> <text|all|end|from-to|line:n>  (editor selection, or list item by label)
    eval <smalltalk> [--timeout ms]    wait <json|@ref|idle|text|ms> [timeout]    advance <ms>|<n>f    bounds <ref>    state
    screenshot [ref] <path> [--scale 1|2] [--pointer]     close
    record start <out.mp4> [--size WxH] [--fps n] [--raw]    record stop

Input commands (click, hover, type, key, drag, select, scroll, resize) wait until the image has settled — no user Process runnable, the UI idle — for at most 2 s; `--settle ms` changes that limit (`--settle 0`: return at once; useful while a window computes for a long time, as nothing settles then). A target in an inactive window gets focus through a click on that window's title bar, so the caret and the selection stay where they are.

`open` starts `vm/build/samaltak <image> --control --control-port <n> --control-port-file <tmp>` (default image `build/samaltak.image`, default port: a free one) and waits until it listens. Commands the image has not registered (without a UI only ping, commands, eval, wait, state and quit exist) fail with a clear message. Exit codes: 1 error, 2 not found / wait timed out, 3 Smalltalk error (the error JSON, with stack, on stdout). While the session's process lives but its port refuses (World menu › Rebuild VM & reboot execs a new VM in the same process, on the same port), commands retry for up to 60 s.

    export SAMALTAK_SESSION=remote
    samaltak-ctl open --headless
    samaltak-ctl eval '3 + 4'                    # 7
    samaltak-ctl eval '[300 factorial] fork' && samaltak-ctl wait idle
    samaltak-ctl snapshot --depth 1
    samaltak-ctl close

## Protocol

JSON lines over TCP on 127.0.0.1. Request `{"id": 1, "cmd": "eval", "source": "3+4"}`, response `{"id": 1, "ok": true, "printString": "7", "className": "SmallInteger"}` or `{"id": 1, "ok": false, "error": "…", "code": 2}`. One connection may carry many requests; they are answered in order. Commands and their arguments:

| cmd | arguments | answer |
|---|---|---|
| `ping`, `commands` | | `pong`, `commands` |
| `eval` | `source`, `timeout` | `printString`, `className`; errors: code 3, `errorClass`, `stack` |
| `wait` | `idle`, `ms`, `text`, `ref`, `gone`, … , `timeout` (10000) | `ms` |
| `state` | | `processes`, `windows`, `theme`, `idle`, … |
| `quit` | `code` | |
| `snapshot` | `ref`, `depth`, `bounds`, `maxItems` | `text` |
| `find` | `text` | `matches` [{ref, role, label}] |
| `click` | `target`, `button` (left/middle/right), `count`, `mods`, `settle` (ms, all input commands) | `at`, `settled` |
| `hover` | `target`, `at` (a spec the widget turns into a point: `remotePointAt:`) | `at` |
| `type` | `target`, `text`, `at` (end/start), `replace`, `delay` (ms between characters), `preedit` (an input method's composition instead) | `typed` |
| `key` | `combo` (String or Array), `target` | |
| `drag` | `target`, `to` or `dx`/`dy`, `mods` | `from`, `to` |
| `resize` | `target`, `w`, `h` | `bounds` |
| `select` | `target`, `spec` | |
| `scroll` | `target`, `dx`, `dy` | |
| `bounds` | `target` | `x`, `y`, `w`, `h` |
| `screenshot` | `target`, `path`, `scale` (default: display scale), `pointer`, `now` | `path`, `w`, `h` |
| `record` | `action` (start/stop), `path` (FIFO or file), `w`, `h`, `fps` | `recording` / `frames` |
| `advance` | `ms` or `frames` | `ms` / `frames` |

`record start` makes a FIFO, starts `ffmpeg -f rawvideo -pix_fmt rgba -s WxH -r FPS -i <fifo> … out.mp4` and has the image write the composited screen (downsampled on the GPU, remote pointer included) into it; `record stop` ends both; `--raw` writes the frames to the file itself. A recording runs on the recording clock (below). Screenshots leave the remote pointer out unless `--pointer`.

Targets are refs (`@w6.packages.kernel-numbers`, `@w6.packages#3` = 4th child) or points (`{"x":10,"y":20}` or `"10,20"`). The image side (registration API, snapshot contract, input planning) is documented in the class comments of `RemoteControl`, `RemoteSnapshot`, `RemoteInputPlanner` and `RemoteInputDevice`.

Tests: `vm/build/samaltak <image> --headless --test Tests-Remote`, `tests/remote/cli_test.sh [image]`.

## The recording clock

A recording does not depend on the machine's load, the display or the app's role: it comes out the same on an idle machine and at load 200, it only takes longer to make. For that the image runs on the *recording clock* (the work clock of the VM's Scheduler), from the start of the session with `open --work-clock`, or from `record start` to `record stop` if the image was started without it. Pass `--hidden` too: a hidden window needs no display and no display link.

- The clock counts the VM thread's cycles at a nominal 3.3 GHz (`thread_selfcounts`, a private macOS call used only while it is on; if it is missing, CPU time, with a warning on stderr). The clock is not real time: when nothing can run it jumps to the next deadline (a Delay, a frame).
- **The driver owns time.** Between commands the clock stands still and only the Processes of priority 50 and above (the control server) run. `advance <ms>` (or `<n>f`: n more video frames) lets it run; every command that acts (`click`, `type`, `wait`, `eval`, `record`, ...) lets it run while it is in flight; queries (`state`, `snapshot`, `find`, `bounds`, `ping`, `commands`) see the image as it is, at no cost. A `wait` or `eval --timeout` timeout is on this clock, so the driver's speed does not matter: a script says how long things take, with `advance`, and nothing else.
- **Frames are stepped.** A hidden window has no display link; the clock ticks at 60 Hz on its millisecond grid (it never passes a tick) and the compositor presents every tick, as it does on a display. The recorder writes one frame per video slot (1/fps s), waiting for the GPU and for ffmpeg, so a slow encoder delays the recording but drops nothing, and the frame of a tick shows exactly that tick's time.
- A command's own preparation does not count, and it ends on the next tick, so the clock stands on the same value at every command boundary, whatever cycle noise the commands cost.

What the on-screen numbers are, while recording. They are measured, not constants, but they are **work at a nominal 3.3 GHz, not wall time**:

| Number | Meaning on the recording clock |
|---|---|
| top bar: ms, fps, sparkline | the time between frame ends on the clock: a tick (16.7 ms), more when a frame's CPU work did not fit in a tick (it then misses ticks, as on a screen, and the video repeats a frame) |
| Process Browser, System Monitor: CPU %, process times | cycles of each Process at 3.3 GHz over the clock |
| Profiler: samples, tally, frame timeline | samples every 1 ms of the clock; a frame's draw and raster times are its CPU cycles at 3.3 GHz; GPU time is the fence latency measured in real time (it does not move the clock) |
| `timeToRun`, `Time millisecondsToRun:` and `microsecondsToRun:`, Mandelbrot's render time, a do-it's reported ms | the block's cycles at 3.3 GHz |
| a Terminal's output, lap times printed by a program in it, the VM Rebuild's seconds | real: those programs ran for real, in real time (see below) |
| dates | real time |

On a performance core of the M2 Max cycles at 3.3 GHz are CPU time, to about 1% (3290-3335 cycles per µs over six workloads). Under load they are the same work; on the efficiency cores of the Background role a compute-bound stretch shows up to about a third slower (high-IPC code; +3% on low-IPC code) because those cores need more cycles for the same work, and the numbers above say so.

Programs outside the image cannot be stepped. While one is at work (a Terminal's foreground job or 300 ms of real time after a terminal's input or output; an `OSProcess`: cc, make) the clock moves at least at real-time pace and does not stand still between commands: the program's speed is the machine's, and its output, printed times and how long it takes on screen depend on the load. Nothing else does.

What matches between recordings, and what does not: the frame count and every frame, except the measured numbers above (a few pixels of the top bar and the Process Browser's CPU column), and, rarely, an event whose work ends within noise of a tick and shows one tick (1/60 s) earlier or later. The first run after a rebuild can differ a little more (cold image pages cost cycles).

Video scripts (`tools/video-lib.mjs`) use this: `sleep` is `advance`, video times and cues are frame numbers (`state.videoFrames`), `S.cue`'s `when` is `wait` on the condition (`{"eval": "..."}`).

## Walkthrough video

    make video     # = the three steps below, then copies the result to docs/media/walkthrough.mp4

    node tools/narrate.mjs <dir>        # ElevenLabs narration per step (eleven_v4, voice Roger; ELEVENLABS_API_KEY in .env), cached
    node tools/walkthrough.mjs <dir>    # drives a hidden image through samaltak-ctl, on the recording clock; records <dir>/raw.mp4 + captions.json
    python3 tools/compose-video.py <dir>   # caption band + narration → <dir>/walkthrough.mp4

`<dir>` defaults to `.context/video-real`. Steps, captions and spoken text: `narration.json`; each step lasts at least as long as its clip. The recording is the compositor's own output (`record start`), 1440×900 at 30 fps.

## Hash table capacities

    python3 tools/hash-capacities.py    # the primes of HashedCollection class>>capacities, on one line (stderr: how many, the largest step)
