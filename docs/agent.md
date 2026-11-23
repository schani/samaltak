# Agent

A coding agent inside the image, written in Smalltalk, driving the image it lives in. ⌘J in a tool opens a conversation window on that tool's context. Model: OpenAI `gpt-6.2-sol` ("Codex 6.2 Sol"; the Codex catalog's slug) through a ChatGPT device-code login. Design: `prototypes/5-agent/6-chosen.html` (the target; version 1 is a subset).

No persistence code: the account and its tokens, conversations and their objects are ordinary objects, saved with the image.

## Version 1

The smallest agent that works end to end. Each item names the seam later work extends.

### Platform (Lowtalk, `src/VM-Platform`, `make translate`)
1. **TLS** (`PlatformTLS`, OpenSSL 3 on macOS and Linux): `tlsStart` (a connected socket → handle in the socket table), `tlsHandshake` (certificate verification against the OS trust store), `tlsRecv`, `tlsSend`, `tlsClose`, `tlsSemaphore`; host names through `socketResolve` (a lookup thread), TCP through `socketConnect`/`socketConnected`. Nothing blocks: each primitive completes or arms a semaphore with the sockets' convention, and Smalltalk waits with one timeout for the whole connect (docs/platform.md), so neither connecting nor a minute-long stream stops the VM.

### System-Net (new, layer 0)
2. `HTTPClient`: HTTP/1.1 over TLS or plain TCP, keep-alive, `Content-Length` and chunked bodies, no compression; `post:json:headers:`, `post:form:headers:`, and a streaming variant handing body chunks to a block. Cancelled by closing from another Process.
3. `SSEReader`: `text/event-stream` chunks → `{event. data}`.
4. `Base64` (decoding, URL alphabet: JWT claims).

JSON: System-Remote's `JSON` (already layer 0).

### System-Agent (new, layer 0, no UI)
5. **OpenAIAccount** (`OpenAIAccount default`): device login, refresh before expiry and on a 401, account id and email from the id token, sign out.
6. **CodexProvider**: builds the Responses request, streams it, decodes events into items and deltas. The one place that knows the backend; an API-key provider is a sibling class later.
7. **AgentConversation**: the item list (developer instructions, messages, reasoning items echoed back, tool calls and outputs), its object table (`oN` ↔ object, strong references, an object keeps its ID), its context, the turn loop (send, run tool calls, send again until no tool call; Stop cancels), `onChange:` the window redraws from.
8. **AgentContext**: what ⌘J bound — receiver, named bindings, optionally a frame — and how a cell compiles against it: `Compiler evaluate:for:bindings:`, or for a frame `Context>>evaluateInFrame:` (extended with bindings, for `oN` and the context's variables; the frame's temps win on a name clash). Default: receiver nil.
9. **AgentTool** (abstract: Responses spec, `run: aCall in: aConversation`) and two subclasses. New tools are subclasses.
   - **code-mode**: a freeform tool (raw Smalltalk, no JSON; the shape of Codex's own code mode). Runs in a fresh Process `agent code-mode` at the priority of a do-it, with `o1 … oN` and the context's bindings bound. Answers `oN` and the printString (cut to 4,000 characters). A syntax error answers the compiler's message; an error answers the exception, its message and the top 10 frames, and the Process ends. After 60 s the Process is terminated and the result says so.
   - **show-object** (`{"id": "o2"}`): adds a show item for the object to the conversation.
10. **AgentInstructions**: one hand-written developer message — code-mode and `oN`, the context, layering (`src/packages.txt`), and that code changes go through `SourceFiler default writeMethod:` so they reach `src/`.

### Tools-Agent (new, layer 5; the window moved to UI-Agent, see In applications)
11. **⌘J** in `ToolPane`, the Debugger, the Breakpoints window and the Profiler: `self agentContext`, then open the Agent window for that tool, or bring it back. `self` is the tool's subject when it is an object in the image; the selection and what is outside the image are named variables (omitted when nothing is selected); `describe` gives the model each variable's name, class and bounded printString. Contexts in version 1:
    - Workspace: its receiver; its variables (shared); the selected text.
    - Inspector: the object; `field` (the selected field's value).
    - Debugger: the selected frame (cells run in it: `self` and temps).
    - Notifier (`ToolsNotifier`): the selected frame, as the Debugger; `session`, `exception`.
    - Process Browser: the selected Process; `context` (the selected frame, an object: cells do not run in it).
    - System Browser: the selected class (the metaclass on the class side); `selector`, `method`, `package`; the selected text.
    - Method Browser: `methods`, `method`; the selected text.
    - Profiler: its `ProfilerData`; `range`, `bar`, `picked`, `process` (the filter).
    - File Browser: `path`, `entry` (the selected file or folder); the text selected in the previewed file.
    - Terminal: `terminal` (`terminal view send: 'ls', (String with: Character cr)` types into it), `text` (the screen); the selected text.
    - Transcript: `text`; the selected text.
    - VM Rebuild, VM Simulator: `output`; the selected text.
    - Breakpoints: the breakpoints and watchpoints listed; `breakpoint` (the selected one).
    - System Monitor: its samples (`SystemMonitorData`).
    - Other tools: the default context (nothing bound).
12. **AgentWindow** (proposal 1's layout): context strip, transcript, ASK prompt with Send and Stop, status bar (model, account, tokens, Sign out). Signed out, the transcript shows the login card (URL, code, Copy).
13. Transcript items: message, code cell (highlighted source, result with its `oN`), error, show-object. Show-object draws a Form as an image, anything else as printString plus an Inspect button that opens the Inspector. Item views are found by `AgentItemView for: anItem`, the seam for richer views.

### Tests
14. **Tests-Net**: HTTP and SSE against a plain-HTTP server in the image.
15. **Tests-Agent**: the conversation against a scripted provider (a turn with two cells and a show-object, an error, Stop); the provider and account against a plain-HTTP server in the image replaying recorded streams (a refresh after a 401).

### Milestones
1. **Spike**: device login and one `/responses` call by hand with `curl`; record the streams as fixtures.
2. **TLS and System-Net** (1–4, 14): `HTTPClient` fetches an `https://` URL from a Workspace while the UI stays live.
3. **Headless agent** (5–10, 15): `(AgentConversation new ask: 'how many classes are in UI-Widgets?') wait` from a Workspace or `samaltak-ctl eval`.
4. **Window and ⌘J** (11–13).

## In applications

The agent also runs in the apps' processes (docs/apps.md), in windows of the host's window manager. A right-click on an app → **Agent** opens it on the app; `bin/samaltak agent` opens it alone.

- **Packages.** The window and its views are `UI-Agent` (layer 4, in the runtime image with System-Agent). `Tools-Agent` keeps what needs the desktop's tools: ⌘J (`AgentTools`, `AgentWindow openFor:context:`) and the tools' `agentContext` extensions. In an app the Inspect button of a shown object is hidden; ? and ⌘C/⌘J/⌘I/⌘B reach the tools only where they exist. `SourceFiler` and `ChunkFile` moved to Compiler (layer 0). `SourceFiler>>packageDirectory:` answers the directory a package was filed in from (`Compiler packageDirectoryOf:`), so an app's changes are written to `apps/<Name>/`.
- **Windows.** `AgentWindow openNativeFor: anApp` opens an AppWorld that is not the app's main one. It is resizable, so Hyprland tiles it, and closing it closes only it. A second **Agent** raises the window already open.
- **Context.** `Application>>agentContext` binds the app (`self`), `window`, `content` and `world`, and its `notes`, which `AgentInstructions` adds after the variables. They tell the model it runs in an app's process on the runtime image: no tools and no desktop World; widget code goes through `window do:`; and where the source is. Apps add bindings: `service` in Weather and Wodify.
- **Sign-in.** Each app is its own process started from the runtime image, so the tokens cannot live in an image. `OpenAIAccount>>keepIn:` keeps them in `~/.local/state/samaltak/agent/account.json` (mode 600). A process reads the file again when its modification time or size changed; a refresh in another process (refresh tokens rotate) is taken from the file instead of being refreshed again; sign-out deletes the file. The desktop image keeps its tokens in the image as before.

## Later

Each builds on a version 1 seam; none changes its shape.

- **Cells**: keep a failed cell's Process suspended (per-process `DebugSession` opener), its session an object with an ID and a Debug button; yield after 10 s and answer the running cell as an object the model waits on or terminates (`o7 waitFor:`); capture the cell's Transcript output.
- **Show-object kinds**: `anObject agentPresentationKind` (`#bars #table #source #flameGraph` …), declared by each package for its classes.
- **Contexts**: an AGENT tag on the origin tool; top bar Agents ▾.
- **Edits**: proposed edits as diff cells (Accept writes `src/`, Accept & Restart frame through `DebugSession>>recompile:inFrame:`); an approval mode that shows each cell before it runs.
- **Platform**: `openURL` for the login card.
- **Moves**: JSON to System-Support, when the core needs it (`SourceFiler`/`ChunkFile` are in Compiler now).
- **Provider**: API-key provider; context compaction; generated instructions (image facts, docs excerpts).
- **Remote control**: roles for the window, a `tests/remote` scenario.

## How it fits

**The agent is a layer-0 service; windows are views of it.** System-Agent knows no windows, like `DebugSession` and `Profiler`; the window observes a conversation. The core runs headless (tests, `samaltak-ctl eval`), and Tools-Agent stays thin, as the Debugger is on DebugSession.

**A conversation starts where the user is.** ⌘J hands it the tool's context, so `self`, the frame or the selection are bound rather than described. The core sees the context, never the tool.

**Code-mode is a do-it.** Same compiler path as `CodeEvaluator`, same Process discipline: visible in the Process Browser, profiled, stoppable. No sandbox: the agent has the powers of a user typing in a Workspace.

**Objects cross the model boundary by reference.** The model sees `oN` and a bounded printString; the object stays in the image and is bound in every later cell. Results compose without parsing, prompts stay small, identity is kept.

**Changes go to source.** The image is built from `src/`; the instructions send edits through `SourceFiler`, so they are live and appear in `git diff`.

**The provider is a risk.** `CodexProvider` uses an undocumented backend while presenting itself as the Codex CLI (its `client_id`, `originator`). It can break without notice and may not be allowed for third-party clients; decide before use beyond personal. Everything above it is the standard Responses API.

**Secrets live in the image.** Saving the image saves the refresh token. `build/` is git-ignored, but anyone with the image file has the account. Sign out clears the tokens. Apps keep them in a file only the user can read (see In applications).

## Protocol (from `openai/codex` at `b7056f3`, 2026-11-15)

Device login, issuer `https://auth.openai.com`, client id `app_EMoamEEZ73f0CkXaXp7hrann`:
1. `POST /api/accounts/deviceauth/usercode` `{"client_id"}` → `device_auth_id`, `user_code`, `interval` (a string). Show `https://auth.openai.com/codex/device` and the code; it expires after 15 min.
2. Poll `POST /api/accounts/deviceauth/token` `{"device_auth_id","user_code"}` every `interval` s: 403/404 = pending; 2xx → `authorization_code`, `code_verifier` (the server makes the PKCE pair).
3. `POST /oauth/token`, form-encoded: `grant_type=authorization_code`, `client_id`, `code`, `redirect_uri=https://auth.openai.com/deviceauth/callback`, `code_verifier` → `id_token`, `access_token`, `refresh_token`.
4. Account id: id-token claim `"https://api.openai.com/auth".chatgpt_account_id`; email: `email`.
5. Refresh: `POST /oauth/token`, JSON `{"client_id","grant_type":"refresh_token","refresh_token","refresh_reason"}` when `exp` is under 5 min away, and on a 401. Refresh tokens rotate (keep every token returned); `refresh_token_reused/expired/invalidated` or `invalid_grant` → signed out.

Model call: `POST https://chatgpt.com/backend-api/codex/responses`, `Accept: text/event-stream`; headers `Authorization: Bearer`, `chatgpt-account-id`, `originator`, `version: 1.0.0` (older versions are refused the model), `session-id`, `User-Agent`. Body: `model:"gpt-6.2-sol"`, `stream:true`, `store:false`, `input` (first item a `developer` message with our instructions; there is no `instructions` field), `tools`, `tool_choice:"auto"`, `parallel_tool_calls:false`, `reasoning:{effort}`, `include:["reasoning.encrypted_content"]`. Events: `response.output_text.delta`, `response.output_item.done` (complete items, tool calls), `response.completed` (usage), `response.incomplete`, `response.failed`, `error`; others ignored.

Verified by hand (2026-11-15): HTTP/1.1 with a chunked event stream works; plain `tools` and our own developer message are accepted (Codex itself sends this model its tools in an `additional_tools` input item and a 63 KB instruction template). A code-mode call arrives as a `custom_tool_call` item (`input`: the source) and is answered with `custom_tool_call_output`; show-object as `function_call` / `function_call_output`. Output items are echoed back verbatim in the next request.

Code-mode results as the model sees them:

    o2 an Array(TextEditor->157 Widget->89 ListView->86 TextLayout->48 MenuView->38)

    error: MessageNotUnderstood: TextEditor class>>keyBindings
      TextEditor class(Object)>>doesNotUnderstand: #keyBindings
      UndefinedObject>>DoIt
