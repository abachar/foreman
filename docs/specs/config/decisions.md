# config — Decisions

| Date | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 2026-08-25 | A `.wraith/` folder at the workspace root: `config.json` (user) + `state.json` (app) | A single `.wraith.json` file (initial README) | Separate what the user writes from what the app writes; extensible |
| 2026-08-25 | Global config in `~/.config/wraith/config.json` | `~/.wraith/`, `~/Library/Application Support` | XDG convention, editable by hand, no collision with a `$HOME` workspace |
| 2026-08-25 | Secrets in the Keychain only | A plaintext `password` field | Security, the file may well be versioned |
| 2026-08-25 | Hot reload of `config.json`, not of `state.json` | Restart required | Comfort; `state.json` is written by the app only |
| 2026-08-26 | A config change is broadcast by an `AsyncStream` on `Workspace`, not by an event bus | `EventBus` + a `configChanged` event (2026-08-25) | `architecture`: no `EventBus`, the owner of the information exposes a stream |
| 2026-08-25 | Shortcuts as ASCII strings `"cmd+shift+g"` (modifiers `cmd`, `shift`, `alt`, `ctrl`, key in lowercase) | `⌘⇧G` notation | Readable, typable on a keyboard, no encoding ambiguity |
| 2026-08-26 | Global/workspace merge: an object section present in both files is merged key by key (one level, the workspace wins); any other value is replaced | Replacing the whole section; deep recursive merge | Override a single shortcut or a single command without copying the globals, without the complexity of a deep merge |
| 2026-08-26 | **No global configuration**: a single source, `<root>/.wraith/config.json` (cancels the "global config in `~/.config/wraith/config.json`" decision and the global/workspace merge of the same day) | XDG global config + merge by section | One source, one file next to the project: less code, no "where does this value come from" question |
| 2026-08-26 | `config.json` watched through **AsyncFileMonitor** (`FolderContentMonitor`, multicast over FSEvents); `FSWatchService` only keeps path filtering and debounced batches | A hand-written FSEvents wrapper (C callback, lifecycle); **swift-configuration** (Apple) ruled out: reloading by *polling* (forbidden by `architecture`), typed per-key reads without a `Decodable` section (R5), no error line (R7), designed for multi-source servers | `architecture` P2: the library does the risky part (casting the FSEvents callback already cost us a crash); what remains is the Wraith contract |
