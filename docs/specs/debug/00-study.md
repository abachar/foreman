# debug — Study

> Domain `debug`, first study (2026-10-17): breakpoints, a paused program, its stack and its variables, through the Debug Adapter Protocol (DAP). Depends on `editor` (the gutter, `Editor.open`, [`06-study-library-sources.md`](../editor/06-study-library-sources.md) for a frame inside a library), `run` (a session is a command of the ▶ Run menu), `terminal` (the program's output) and `layout` (a panel in the bottom slot). Rules R1–R12; decisions in [`decisions.md`](decisions.md), open points in [`questions.md`](questions.md).

## Goal

The one thing that separates a text editor with LSP from an IDE: stop the program on a line, look at the variables, step. Foreman writes **no debugger**: every language has a debug adapter speaking DAP — `java-debug` inside `jdtls`, `lldb-dap` inside Xcode, `js-debug` for Node — and Foreman is their client, as it is the client of the language servers. The adapter is declared in the config, like a server (`editor` R35) and a command (`run` R1); nothing is detected, nothing runs unasked.

The first targets are the author's own projects: a **Spring Boot backend under Maven** (`ccoe-backend`, attached through JDWP, then launched by the adapter) and **Foreman itself** (Swift, `lldb-dap`, which ships in the selected Xcode and needs no install — the client is developed against it, the way the LSP client was developed against `sourcekit-lsp`). Node is declarable from day one; the Angular frontend in the browser is out of scope (see below).

**Nothing of this domain is written under the workspace root**: breakpoints go to `state.json`, the adapters' paths to the config the user writes. The author will commit `.foreman/` to share the config (2026-10-17).

## User stories

- *I click in the gutter on a line of a service, press ▶ on the backend's command, call the endpoint, and Foreman stops there*: the line is marked, the Debug panel shows the thread, the frames, the variables of the frame.
- *I step over, step into, step out, continue*, from the panel's buttons or Xcode's keys.
- *I step into a Spring class*: its source opens read-only (`editor` R63) with the paused line marked, like my own code.
- *I expand a variable*: its fields come when I ask, not before; a list of a thousand elements does not freeze the panel.
- *I type an expression in the console* and read its value in the paused frame.
- *I stop the session*: an attached program keeps running, a launched one is terminated; the Run sub-tab says which.
- *I debug Foreman from Foreman*: ▶ on a `launch` command, `lldb-dap` starts the built app, a breakpoint in `EditorFeature` stops it.
- *The adapter is missing or dies*: a banner in words, the program I was running is untouched, no crash (P5).

## Functional rules

### Declaring an adapter and a session

- R1 — **Adapters** are declared in `config.debug`, one per lowercased extension, the `lsp` section's shape (`editor` R35): the value is either `{ "command": "<text>" }`, an adapter speaking DAP on **stdio**, the user's text run by `$SHELL -l -c` with the login environment (`xcrun lldb-dap`, `node <path>/dapDebugServer.js` being a TCP server is the second form), or `{ "server": "<command id>" }`, a `workspace/executeCommand` sent to the language server of the same extension (`editor` R35), which answers the **TCP port** of an adapter it hosts — `jdtls` with the `java-debug` bundle answers `vscode.java.startDebugSession` with a port (verified 2026-10-17 on the upstream source). A `timeout` key (seconds, default `10`, `1…60`) bounds `initialize` and the TCP connection, as `lsp.timeout` does. Nothing is detected; without a section there is no Debug panel, no shortcut and no 🐞 (`layout` R36). Every key in `config.md`.
- R2 — **A session is a command** of `config.commands` (`run` R1–R3) carrying a `debug` object: `{ "adapter": "<ext>", "request": "attach" | "launch", "arguments": { … } }`. `arguments` goes to the adapter **verbatim** as the body of its `attach` or `launch` request — the adapter's own names, nothing translated (`editor` R57's policy for `settings`): `hostName` and `port` for `java-debug`'s attach, `program`, `args`, `env` for `lldb-dap`'s launch, `mainClass`, `classPaths`, `projectName` for `java-debug`'s launch. A command may have `run` **and** `debug` (attach: the command starts the program, Foreman attaches to it) or `debug` alone (launch: the adapter starts the program). An `adapter` naming no entry of `config.debug` is a config warning (`config` R7) and the command runs without debugging. Detected commands (`run` R14) carry no `debug`.
- R3 — **Starting**: the ▶ of the Run widget, the menu and the palette run the command as today; a command with `debug` is also offered as **Debug** — a 🐞 entry next to it in the menu and the palette, `ctrl+cmd+r` for the widget's current command (Xcode's key) — which, for an attach, runs the command then connects the adapter and sends `attach` at once (the adapter does the waiting: `java-debug` retries for its `timeout`, `lldb-dap` has `waitFor`; Foreman polls nothing), and for a launch sends `launch` without running anything. Running a command with `debug` through the plain ▶ debugs nothing: the breakpoints stay grey. One session per command at a time; ▶ or Debug on a command whose session runs stops it and starts again (`run` R7's reuse).
- R4 — **Breakpoints** are toggled by a click in the gutter's **number area** (the fold markers keep the right part, `editor` R27) or by `cmd+\` on the caret's line (`tab(editor.file)`): a dot in `statusRed`, filled when the adapter verified it, hollow before a session and when the adapter refused it. Stored in the `debug` section of `state.json` per file (`layout` R27; the file's path relative to the root), never in `config.json`; sent to the adapter with `setBreakpoints` for every file at the start of a session and again for a file whose set changes while one runs. Only on `editor.file` tabs under the root: a library tab (`editor` R63) and a diff tab take none in v1. A breakpoint on a line that no longer exists after an edit moves with the text while the tab is open and is dropped past the end of the file at restoration.
- R5 — **Stopped**: on the adapter's `stopped` event Foreman asks `threads`, `stackTrace` of the stopping thread and `scopes` of its top frame; the top frame's source opens through `Editor.open(…, line:)` — a path under the root as today, a path outside it or a `jdt://` URI through `editor` R62–R64, the adapter's `source.path` being what `jdtls` would answer a definition with — and the line is painted across the full width in a second colour, `statusOrange` at the current line's alpha (`design` R6: no new token). The mark goes on `continued`, `terminated` and `exited`. Selecting another frame in the panel opens its source and moves the mark; the caret is not moved by a step unless the line is off screen (the user may be reading elsewhere).
- R6 — **The Debug panel**, bottom slot, after Problems (`order: 4`), `cmd+shift+y` (Xcode's debug area), registered only while `config.debug` and a `debug` command exist (`layout` R36; `makeView` lazy, P4). Three columns under the panel's own row of controls: **threads and frames** (one section per thread, its frames in order; the stopping thread expanded), **variables** (the top frame's scopes, each a tree whose children are fetched with `variables(variablesReference)` on expansion — never ahead, never the whole graph; `indexedVariables` past 100 paged by 100), **console** (the adapter's `output` events, `stdout`/`stderr`/`console` categories distinguished by colour, and a field sending `evaluate { expression, frameId, context: "repl" }` whose answer is appended). The controls: ▶ continue / ⏸ pause, step over, step into, step out, ■ stop, and the session's state in words (`attaching to localhost:5005`, `paused in Foo.bar() line 42`, `running`, `ended`). The program's own output stays in the Run sub-tab (R8).
- R7 — **Shortcuts** (every row in `shortcuts.md`, Xcode's keys, all free on 2026-10-17): `ctrl+cmd+r` `debug.start` (global), `cmd+\` `debug.toggleBreakpoint` (`tab(editor.file)`), `ctrl+cmd+y` `debug.continue`, `f6` `debug.stepOver`, `f7` `debug.stepInto`, `f8` `debug.stepOut` (global while a session is paused, bound to nothing otherwise), `cmd+shift+y` `debug.panel`.

### The session and the program

- R8 — **The program's output** is the Run sub-tab's: for an attach it is the command's terminal as today; for a launch the adapter is asked for `console: "integratedTerminal"` (its own name, written by the user in `arguments` or absent — `java-debug` defaults to it, `lldb-dap` needs it) and answers with a `runInTerminal` reverse request, which Foreman serves by a terminal session of the command's sub-tab (`TerminalService.start`): the request's `args` are each single-quoted and joined into one command line for `$SHELL -l -c` (`terminal` R3; a six-line quoting function, tested on a quote and a space), `cwd` and `env` passed as the request says, and the reply carries the `processId` the service knows (`terminal` R16). An adapter that launches without a terminal (`internalConsole`) sends its output as `output` events, shown in the console of R6.
- R9 — **Lifecycle**, the protocol's and nothing more: `initialize` (`clientID: "foreman"`, `linesStartAt1`, `columnsStartAt1`, `pathFormat: "path"`, `supportsRunInTerminalRequest: true`, `supportsVariablePaging: true`), then the `attach`/`launch` request, then on the `initialized` event the breakpoints of R4 and `configurationDone`; the request's answer ends the start. `initialize` and the TCP connection are bounded by `debug.timeout`. Stop = `disconnect` with `terminateDebuggee: true` for a launch and `false` for an attach; an adapter that does not answer within the timeout is `SIGTERM`ed, then `SIGKILL`ed a second later, the ladder of `editor` R36. A session ends on `terminated`, on `exited`, when the adapter's process dies, and when the Run sub-tab is closed (`run` R12 asks first while the program runs). The adapter's `stderr` goes to a `debug` log, as a server's does.
- R10 — **Nothing runs before ▶**: no adapter, no port, no panel work (P4). The adapter process (or the TCP connection) lives for one session and is released at its end; `jdtls`'s hosted adapter is asked for a new port each session.
- R11 — **Failures degrade** (`editor` R39's policy): adapter binary missing from the `PATH` (`FormatterCatalog.isBinaryAvailable`), the language server without the `server` command (no bundle), `initialize` or the connection past the timeout, `launch`/`attach` answered with an error — one banner on the Run sub-tab carrying the adapter's own message (`message` of the error response, else the last line of `stderr`), the session ends, **the program is left alone**: an attached process keeps running, and a command run for an attach stays in its sub-tab. No modal, no crash (P5). A `stopped` event naming a source Foreman cannot open (a scheme no server provides, R62) marks nothing and says so in the panel's state line.
- R12 — **Security**: the adapter's command is the user's text (`$SHELL -l -c`, `architecture.md`); `arguments` is the user's object, passed as is; the TCP connection goes to `localhost` and the port the user's server answered, nowhere else; what the adapter sends — variable values, output, source paths, `runInTerminal` arguments — is **untrusted displayed content**, rendered as text, except the two things the protocol makes it do: open a source (R5, validated as a `file:` path or a scheme a declared server provides) and run a program in a terminal (R8, from an adapter the user declared, the same trust as a language server's `workspace/executeCommand` today). No telemetry, no network beyond `localhost`.

## Edge cases

- Two commands with `debug` on the same port: the second attach fails with the adapter's message (R11); nothing in Foreman guesses ports.
- A breakpoint set while a session is paused: `setBreakpoints` for the file at once, the dot filled or hollow by the answer.
- The window closes with a session running: a launched program is terminated with the session (`terminateDebuggee`), an attached one keeps running; `layout` R15's confirmation is the Run sub-tab's.
- A `stopped` event with no `threadId` (`allThreadsStopped`): the first thread's top frame.
- A frame without a source (`<unknown>`, a JIT stub): listed greyed, selecting it opens nothing.
- The adapter answers `stackTrace` with hundreds of frames: `levels: 100`, a *more* row for the rest.
- `jdtls` restarts (`editor` R39) while a Java session runs: the hosted adapter dies with it, the session ends with the banner of R11; the program keeps running.
- A launch command whose `arguments.program` does not exist: the adapter says so (`lldb-dap`'s message), R11.
- `lldb-dap` on a signed app needs `get-task-allow` (a Debug build has it); a Release build refuses to attach — the adapter's message says so, Foreman adds nothing.

## Out of scope for v1

- **The Angular frontend in the browser**: `js-debug` can drive Chrome, but that is launching a browser Foreman does not own, a second page beside `browser` R1's `WKWebView` — whose Web Inspector already debugs the page served (`browser` decisions 2026-08-28). Node processes (an SSR server, a script) are declarable through `js-debug`'s DAP server from day one.
- Launching Java **without** `mainClass` and `classPaths` written by the user: resolving them through `vscode.java.resolveMainClass` and `vscode.java.resolveClasspath` is the second Java task ([M27](../../backlog/m27-debug.md) 27.5), the attach being enough to debug a Spring Boot backend from the first day.
- Conditional breakpoints, hit counts, logpoints, exception breakpoints (`setExceptionBreakpoints` — `java-debug` offers *caught/uncaught*, a later toggle), data breakpoints, function breakpoints.
- Watch expressions, hover showing a variable's value, inline values next to the code.
- Hot swap / hot reload (`java-debug`'s `redefineClasses`), Spring DevTools.
- Several sessions at once, a session per worktree, remote hosts other than `localhost`.
- Breakpoints inside a library source (`editor` R63), and `jdt://` sources in `setBreakpoints`.
- Fetching the `java-debug` bundle: the user downloads the jar from Maven Central (`com.microsoft.java:com.microsoft.java.debug.plugin`, 0.53.1 of 2024-11-04 there, 0.53.2 on GitHub) and names it in `lsp.java.settings.bundles`, the way the Lombok agent is named today — the `config.md` example shows it.

## Technical options

### The client — written, ~600 lines, no dependency

DAP is JSON framed by `Content-Length` headers like LSP, but **not JSON-RPC**: a message is `{ seq, type: "request" | "response" | "event", command | event, arguments | body, request_seq, success, message }`. Two Swift packages were read on 2026-10-17 and both are refused: **`ChimeHQ/DebugAdapterProtocol`** (eight files, three commits, the last one "prepare for transfer" of 2026-09-14, no release, "a work in progress" by its author, server-side `Initialize` and `Capabilities` only) and **`noellee/SwiftDAP`** (the adapter side, "alpha, features are incomplete"). Neither has the client session, the requests or the events this study needs, and the types are the small part.

What is written, in `Debug/`:

- `DAPMessage.swift` — the envelope and the `Codable` bodies of the fifteen requests this study uses (`initialize`, `launch`, `attach`, `setBreakpoints`, `configurationDone`, `threads`, `stackTrace`, `scopes`, `variables`, `continue`, `next`, `stepIn`, `stepOut`, `pause`, `evaluate`, `disconnect`), the six events (`initialized`, `stopped`, `continued`, `output`, `terminated`, `exited`) and the one reverse request (`runInTerminal`). The verbatim `arguments` of R2 is an `LSPAny`-like JSON value — `LSPAny` itself, from `LanguageServerProtocol`, already retained and already what `settings` is. ~250 lines.
- `DAPSession.swift` — an actor: a `seq` counter, the pending responses by `request_seq` (continuations), the events as an `AsyncStream`, the reverse requests answered by the owner; `initialize` → `launch`/`attach` → `initialized` → breakpoints → `configurationDone` in that order (R9). ~150 lines. The framing is `JSONRPC`'s `DataChannel.withMessageFraming()` — it frames bytes, it does not care that the content is not JSON-RPC — on the two `Pipe`s of a stdio adapter exactly as `LSPServer` builds its channel, or on an `NWConnection` (Network.framework, the platform) for a TCP adapter, a `DataChannel` of ~40 lines.
- `DebugFeature.swift` — the owner: the config section, the ▶/🐞 entries, the panel, the breakpoints store, the paused mark. Reads `config.commands` through `RunFeature.command(_:)`, starts the attach's command through `RunFeature.launch`, serves `runInTerminal` through `TerminalService.start`.

### What the platform and the app already give

- The gutter click and the dots: `LineNumberRulerView` (`editor` R6, R27, R41) draws numbers, fold markers and diagnostic dots and takes the click; a breakpoint is a third set of dots and the left half of the click.
- The paused line: `CurrentLineTextView` paints the caret's paragraph across the width (`design` R22); a second paragraph in a second colour is the same drawing.
- The panel: a `PanelDescriptor` in the bottom slot like Run's and Problems'; the trees are SwiftUI `List`s with `OutlineGroup` fed lazily.
- The terminal: `TerminalService.start(command:cwd:env:kind:title:)`, `pid(of:)`, the Run sub-tab (`run` R7, R13).
- The config: `LSPCatalog`'s decoding as the model for `DebugCatalog` (the same `timeout` rule, an invalid entry dropped with a warning, never the section); `RunCatalog` gains the `debug` key of a command.

### The adapters, verified on 2026-10-17

| Language | Adapter | Transport | Note |
|---|---|---|---|
| Java | `java-debug` (Microsoft), the `com.microsoft.java.debug.plugin` jar loaded by `jdtls` through `initializationOptions.bundles` — `lsp.java.settings.bundles`, verbatim, works today | `vscode.java.startDebugSession` → a TCP port | `attach { hostName, port, timeout }`; `launch { mainClass, projectName, classPaths, modulePaths, args, vmArgs, env, cwd, console, stopOnEntry }`; the compatibility of 0.53.x with `jdtls` 1.62 under JDK 27 is the one thing to try first (27.4) |
| Swift | `lldb-dap`, `/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-dap` | stdio | `launch { program, args, cwd, env, stopOnEntry }`, `attach { pid | program, waitFor }` |
| Node | `vscode-js-debug`'s standalone DAP server (`js-debug-dap` release asset) | a TCP port it prints | declarable, not a target of M27 |

### Rejected

- JDWP directly for Java (no adapter): a second protocol, binary, and only for Java; `java-debug` is what every editor uses.
- `lldb` through its Python or C++ API: a dependency on the toolchain's framework for one language; `lldb-dap` is the same `lldb` behind the protocol the others speak.
- A `launch.json`: the session is a command of `config.commands`, which the ▶ menu already lists, with one more object — nothing new to learn and nothing new to persist.
- Resolving ports, main classes or class paths in Foreman: the adapter's job (27.5 asks the server, Foreman stores nothing).

## Implementation order

[M27](../../backlog/m27-debug.md): the client against `lldb-dap` on Foreman's own Debug build first — no install, the log says a breakpoint stopped the app; then the breakpoints and the paused line; then the panel; then Java attach on `ccoe-backend`; then Java launch with the server's resolution. Each a commit that builds.
