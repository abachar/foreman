# M24 — LSP: a server's settings

Ninth round driven by use (2026-10-17), after [M23](m23-performance.md). Found on `ccoe` the day
`jdtls` was declared for the backend: Foreman sends `initializationOptions: nil`, never
`workspace/didChangeConfiguration`, and ignores the server's `workspace/configuration` requests
(`LSPServer.handle`, `case .notification, .request: break`). The server therefore runs with **no
setting at all**, and everything a real server expects to be told is out of reach:

- `jdtls` writes `.project`, `.classpath`, `.factorypath` and `.settings/` **inside the team's
  repository** (`java.import.generatesMetadataFilesAtProjectRoot`, true by default) — four untracked
  entries in the Changes panel of a repo whose `.gitignore` knows IntelliJ and VS Code, not Eclipse;
- it imports the Gradle project that `openapi-generator` leaves under `target/generated-sources/`
  and fails on it at every start (`java.import.exclusions`);
- it has no JDK to pair with the project's `JavaSE-21` (`java.configuration.runtimes`) and runs on
  the 27 it needs for itself;
- its diagnostics on generated sources cannot be turned down (`java.errors.*`, the ECJ severities).

`typescript-language-server`, `ngserver` and `sourcekit-lsp` take settings the same way
(`preferences`, `angular.*`, `sourcekit-lsp.*`). The key is the smallest thing that unlocks all of
it, and the client already has the two shapes it needs: `InitializeParams.initializationOptions`
and `ServerRequest.workspaceConfiguration(ConfigurationParams, Handler<[LSPAny]>)` in
`LanguageServerProtocol`.

Domain: [`editor`](../specs/editor/) — [`03-study-lsp.md`](../specs/editor/03-study-lsp.md) (R35,
R36, R46; one new rule, R57). No new folder, no dependency.

Size: S < ½ an agent-day, M ≈ 1 day. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Tasks

One branch `feat/m24` from `main`, one commit per task. Nothing starts before the author's go.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 24.1 | **`lsp.<ext>.settings`**: a third key of the detailed form, any JSON object, kept verbatim as an `LSPAny` on `LSPCatalog.Entry` (a string entry has none). It reaches the server by the three channels the protocol defines, with **no translation** — the user writes what the server's documentation names: (1) `initializationOptions` of `initialize`; (2) `workspace/didChangeConfiguration` `{ "settings": <object> }` right after `initialized`, and again when the entry's `settings` change in `config.json` without changing its command or `cwd` (a change of those restarts the server, R36, unchanged); (3) an answer to the server's `workspace/configuration` request — one value per item, the sub-object at the item's `section` path (`"java.import"` → `settings.java.import`, dotted keys walked), `null` when absent or without `settings`; the request is answered **today too**, with `null`s, instead of being left pending. `settings` takes part in the server's identity (R36) only through its content: two extensions naming the same command and `cwd` but different `settings` are a config warning, the first wins. `config.md` and `03-study-lsp.md` (R57: the key, the three channels, verbatim) updated in the same commit, with the `ccoe` example below | editor R35, R36, R46, new R57 | `LanguageServerProtocol`: `InitializeParams.initializationOptions`, `ServerRequest.workspaceConfiguration`, `ServerNotification` for `didChangeConfiguration`, `LSPAny` | decoding (`settings` absent, an object, a non-object → warning, dropped; a string entry has none); the `initialize` params carry the object; `didChangeConfiguration` sent once after `initialized` and once per settings-only change, not on a command change; `workspace/configuration` answered: a dotted section, a missing one, no settings at all, several items; no server launched (the params of `initialize` and the answer to `workspace/configuration` are pure functions, which is where the rule lives) | S/M | 🟢 (2026-10-17) | |

The `ccoe` example (`config.md`), the one the task is checked against by hand:

```json
{
  "lsp": {
    "java": {
      "command": "env JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home jdtls --jvm-arg=-javaagent:/Users/me/.m2/repository/org/projectlombok/lombok/1.18.46/lombok-1.18.46.jar -data /Users/me/Projects/ccoe/.foreman/jdtls",
      "cwd": "ccoe-backend/src",
      "settings": {
        "java": {
          "import": {
            "generatesMetadataFilesAtProjectRoot": false,
            "exclusions": ["**/target/**"]
          },
          "configuration": {
            "runtimes": [{ "name": "JavaSE-21", "path": "/Library/Java/JavaVirtualMachines/openjdk-21.jdk/Contents/Home", "default": true }]
          }
        }
      }
    }
  }
}
```

Checked by hand when: the backend repo shows no `.project`/`.classpath`/`.settings/` after a fresh
`-data`, the Gradle import error is gone from the server's log, and the Problems panel's count on the
backend drops to the diagnostics of `src/`.

## Out of scope

- A Foreman-side filter of diagnostics by path (`target/`, `node_modules/`): the server's own
  settings do it where they exist; a client-side filter is a separate question for the Problems
  panel (R51), to be asked from use.
- Two servers on one extension (`questions.md`, 2026-08-31): unchanged.
- Any default settings per known server: Foreman declares, never guesses (R35).

## Where it stands

Planned on 2026-10-17 from the `ccoe` backend's `jdtls` setup (958 false errors from the
Lombok × ECJ 4.42 bug — [projectlombok #4086](https://github.com/projectlombok/lombok/issues/4086),
not Foreman's to fix — on top of the four settings-shaped frictions above). Built the same day on
`feat/m24`, one commit: `LSPCatalog.Entry.settings` (an `LSPAny`, shared per server with the
first-declares-wins rule), `LSPServer.initializeParams` (channel 1, and `workspace.configuration`
announced), the `didChangeConfiguration` after `initialized` and on `update(settings:)` (channel 2,
called by `LSPServers` on an existing server), `LSPServer.configuration(for:in:)` answering
`workspace/configuration` (channel 3, always). Found on the way: a file matching the cases of a
type from a module it does not import (`JSONValue` from `JSONRPC`, seen through
`LanguageServerProtocol`'s `LSPAny`) gets the Hashable method instead of the case — the import is
the fix, not the pattern. Left: the by-hand check on `ccoe` with the example above, by the author.
