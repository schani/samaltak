# Applications: Samaltak programs as Linux windows

A Samaltak application is a package directory of Smalltalk source that runs as a window of the host's window manager (Hyprland on Omarchy) instead of on the Samaltak desktop. It still draws through the same Canvas → Renderer → SDL_GPU (Vulkan) path as the World, and it runs straight from its source: the base image files it in at startup. The first ones are the Omarchy desktop cards as windows of their own: `apps/Weather`, `apps/Agents` (the agent subscriptions' rate limits) and `apps/Wodify` (the day's workouts at the gym).

    bin/samaltak run apps/Weather         # file in apps/Weather, run its Application in a floating window
    bin/samaltak test apps/Weather        # its tests, headless
    bin/samaltak install apps/Weather     # an XDG .desktop entry, so the app launcher lists it
    bin/samaltak run apps/Weather --control --control-port 4711   # drive it with samaltak-ctl, as the World
    bin/samaltak agent                    # the Agent (docs/agent.md) in a window of its own (install agent: in the launcher)

A right-click on an app opens its menu. **Agent** opens the agent on the app in a second window of the app's process: `self` is the app, and `window`, `content` (the card) and `world` are bound, with `service` too in Weather and Wodify. The agent can read the app, change it live, and write the changes to `apps/<Name>/`.

## Principles

- **The Window stays the unit.** An app's window is a `Window` (`AppWindow`) with its own Process, retained drawing, Widgets, events and animations. What differs is where it is placed: in an `AppWorld`, a World whose host window shows that one window, chromeless and filling it. The window manager decorates, places and closes it. The Compositor, InputDispatcher and Canvas are the World's own.
- **The platform does mechanism, the image does policy.** The VM gained one primitive, `windowSetSize`, so a window can follow its content's height. The Wayland `app_id` comes from SDL (`SDL_APP_ID`, set by `bin/samaltak` to `org.samaltak.<name>`). The window has a fixed size, so Hyprland floats it; `Application>>fitToContent` resizes it. Omarchy, TOML, XDG, time zones, cookies and SVG are Smalltalk.
- **Source is the truth.** An app directory has the format of `src/<package>/`: a class per file, plus `Class.extension.st` for methods on other packages' classes. `Compiler fileInPackage:` evaluates every class definition first (superclasses first, whatever the file names), then the rest of each file, then the class-side `initialize` methods. The base image is the runtime image, `build/runtime.image` (`make runtime`, the packages of `src/runtime.txt`); filing in the weather app (about 600 lines) adds about 85 ms to the VM's 20 ms start.
- **Linux citizenship.** The app uses the XDG base directories (`XDG`), an `app_id` and a `.desktop` entry, and reads Omarchy's own files for its look (`OmarchyTheme`).
- **Idle costs (almost) nothing, and holds little.** An AppWorld presents a frame only when something changed. The VM wakes only for real timers: time slicing arms its timer only while equal-priority Processes compete, and the idle Process sleeps until something is due (about 5 wakeups a second remain, the app's own timers). Applications pause the always-on sampling profiler (`--profile` keeps it). When no frame was presented for 2 s the AppWorld gives the memory of the burst before back to the system (`VirtualMachine>>releaseMemory`): eden's pages, the machine code, the JIT's type feedback and scratch areas.

## The pieces

| Where | What |
|---|---|
| `Compiler fileInPackage:` (Compiler) | Loads a package directory, as described above. |
| `--load <path>...`, `--app <dir>` (System-Support) | `--load` files in package directories or chunk files before `--test`/`--eval`/the main action, and may be given several times. `--app` loads a directory and remembers its classes (`Smalltalk appClasses`). |
| `UIWindows runApp` | With `--app`, runs the package's subclass of `Application` instead of the World. |
| `AppWorld`, `AppWindow` (UI-Windows) | An AppWorld has no desk and no top bar (`showsTopBar`), presents only changes (`presentsContinuously`) and has no opening animation. It quits when its window closes, or when the window manager closes the host window; a hidden one (in tests) stops instead. An app may open more host windows: AppWorlds that are not `isMain` (`openExtent:title:hidden:main:resizable:`). Closing one closes only it, `raise` brings it to the front, and `World all` lists every running World (a theme change restyles them all). An AppWindow opens its `menuBlock`'s menu on a right-click that no View takes. |
| `Application` (UI-Widgets) | The base class. Subclasses answer `content` (a View) and may override `title`, `extent` (default: the content's `preferredExtent`), `backgroundColor`, `isResizable`, `prepare`, `started` and `stopped`. Run one with `MyApp run`, or `runHidden` in tests. Its right-click menu (`contextMenu`) has the items of `addMenuItemsTo:`, then those other packages add to every app (`Application addMenuItem: #agent with: [:app :menu \| ...]`). `--run <class>` runs an Application of the image (`AgentApp`). |
| `AgentWindow`, `AgentApp` (UI-Agent) | The agent's window (docs/agent.md), in the runtime image. `AgentWindow openNativeFor: anApp` opens it on `anApp agentContext` in a resizable host window of its own, or raises the one already open. The sign-in is kept in `~/.local/state/samaltak/agent/account.json` (mode 600, `File writeSecret:to:`), shared by every app's process; a process re-reads it when it changes, so a refresh in one is not undone by another. `AgentApp` is the agent alone (`bin/samaltak agent`). |
| `XDG` (System-Files), `TOMLReader` (System-Support) | The base directories, and the configuration format of Omarchy, Alacritty and many other Linux programs. |
| `OmarchyTheme` (UI-Omarchy) | Reads `~/.local/state/omarchy/current/theme/{colors,shell}.toml`, the user's `~/.config/omarchy/shell.toml` and fontconfig's `monospace`, and resolves surface colors the way the shell's `Color.qml` does (roles, references to other keys, `-alpha` companions). Its type scale is `#caption` … `#displayLarge` from `[font] base-size`, and `space:` is `Style.space`. `install` makes it current and checks the files once a second. After `omarchy theme set`, `omarchy font set` or an edit of `shell.toml`, every window restyles. The whole system follows it, not only apps (docs/ui.md, Theme). |
| `OmarchyCard`, `Omarchy` (UI-Omarchy) | `OmarchyCard` is a desktop card as a Widget: the popup surface, the card's padding, its column's width (490 points less the padding), the shell's type scale, spacing and colors (muted, dim, accent, urgent), text laid out as Qt's Text does it (natural widths, eliding, wrapping at white space), the cards' Meter (rounded pills painted by VectorPainter), scrolling past `maxHeight` with an indicator, and click/middle-click hooks. `Omarchy` answers `path` (`$OMARCHY_PATH`), `cardSettings:` (a card's settings in `~/.config/omarchy/desktop-cards.json`), `screenExtent` (the focused monitor in points, from `hyprctl monitors -j`), `togglePanel:` and `launch:`. |
| `TimeZone` (System-Support) | Local time: the TZif file of `$TZ` or `/etc/localtime` (RFC 8536, its transitions and the POSIX rule in its footer for later times), read again when it changes; `utcSecondsOf:` reads ISO 8601. |
| `HTTPCookieJar` (System-Net) | Cookies as browsers keep them (RFC 6265: domains, paths, Secure, Expires and Max-Age), in memory; `HTTPResponse>>allAt:` keeps each `Set-Cookie`. |
| `apps/Weather` | `WeatherService` is a Process that reads `~/.local/state/omarchy/settings/weather.json`, detects the place through geo.omarchy.org or looks up a bare name with Open-Meteo's geocoding, and fetches Open-Meteo's forecast every 15 minutes (a minute after a failure). It checks the wall clock every 2 s, so suspend can't stall it. `WeatherReport` and `WeatherDay` hold the forecast, `WeatherIcons` holds the shell's Nerd Font glyphs, and `WeatherCard` draws the card's layout. A click opens the bar's weather panel, a middle click fetches again. |
| `apps/Agents` | `AgentUsage` reads the records `omarchy-agent-usage-update` writes to `~/.local/state/omarchy/agents/usage/` and names, times and paces their windows as the bar's Agents panel does; `AgentsCard` draws each agent's logo (the bar's SVGs, painted by `SVGImage`, the `-light` ones on light themes), name and plan, and a meter per window with its pace tick, percentage and time to reset, or the prepaid balance. It reads the records every minute; a click opens the bar's Agents panel, a middle click runs `omarchy-agent-usage-update --limits-only`. The card's `hide` setting leaves agents out. |
| `apps/Wodify` | `WodifyClient` talks to the gym's Wodify member app as the app does: OutSystems screen services, each action's `apiVersion` read from the app's current scripts, a login with email and password (and a switch to the configured gym), then `GetAllWorkoutData` per day. Its session (an `HTTPCookieJar` and the user's ids) lives in memory. `WodifyDay` shapes a day's response (`WodifyText` turns its HTML into text), `WodifyService` fetches today and tomorrow when the local day or `~/.config/omarchy/wodify.json` changes, every 30 minutes, and a minute after network trouble (not after a rejected password). It keeps the workouts in `~/.local/state/samaltak/wodify/last.json` for when Wodify cannot be reached. `WodifyCard` lays them out as the card does, with its settings (days, comments, notes, hide, level), and scrolls past 60 % of the screen's height. A click opens the member app (`xdg-open`), a middle click fetches again. Nothing of the member's profile is kept, and the password goes only to Wodify. |

## Memory

The weather app, measured on Asahi (16 KB pages) 8 s after it started, idle, against the same app in C (`tools/weather-c`: SDL3's GPU renderer on the same Vulkan driver, FreeType, libcurl) and the QML card it reproduces, alone in a quickshell:

| | RSS | private dirty |
|---|---|---|
| samaltak (runtime image, idle) | 58 MB | 32 MB |
| samaltak right after its startup burst | 71 MB | 47 MB |
| C | 46 MB | 13 MB |
| QML card in quickshell | 156 MB | 49 MB |

What made the difference (from 200 MB RSS, 168 MB private, on the desktop image; another 7 MB is glslang's static tables, see the follow-ups):

- **No shader compiler at run time** (‑71 MB): glslang keeps its symbol tables and pools for the life of a process that compiled once. Stage 2 compiles the shaders to SPIR-V, which the image keeps (`GPUShader`); `gpuCompileShader` still serves changed shader source.
- **The runtime image** (‑25 MB): `make runtime` builds `build/runtime.image` from the packages of `src/runtime.txt` (7.7 MB, the desktop image 50 MB); it keeps no font faces, nothing pre-rasterized, and smaller glyph atlas pages (1 MB).
- **Font files read as needed**: a face read at run time (`TrueTypeFont fromFile:`, the Omarchy fonts fontconfig names) reads its file 4 KB at a time (`FileBytes`), as a C program maps it: of the 2.5 MB JetBrainsMono Nerd Font the card reads 86 KB.
- **Memory given back when idle** (‑20 MB): after the startup burst (filing in, compiling, fetching, drawing) eden's touched pages, 9 MB of machine code, the type feedback table and the optimizer's arenas are released.

What remains beyond C is mostly the object memory (the image and the app, 8 MB, and eden's live part) and the JIT's tables.

## Follow-ups

- **inotify** (`fileWatch`): a file descriptor in the socket table that signals a Semaphore. It would replace the once-a-second checks of the theme and the weather settings, most of the remaining wakeups.
- **shaderc out of the VM**: linked, glslang's static constructors fill about 7 MB in every process, compiling or not. Loading it when first needed (dlopen) does not work where only static libraries are usable (Debian bookworm, CI); compiling with the `glslc` tool, run by the image, would take it out of the VM altogether.
- **wlr-layer-shell**, to sit on the desktop below the windows as the QML card does. This needs an SDL window with a custom Wayland role and `zwlr_layer_shell_v1` through libwayland-client in `PlatformWayland`, a Linux-only Lowtalk module.
- **A debugger in a host window of its own.** Apps can open more host windows (the agent does), but a Notifier still opens inside the app's window.
- **`--watch`**: file in an app's source again when it is saved, so the running window changes as you edit.
