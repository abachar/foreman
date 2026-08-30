# M17 — Audit follow-up

Third round driven by use (2026-08-30), after [M16](m16-new-file-markdown.md). Not a feature
milestone: the batch that closes [`audit-2026-08-30.md`](../audits/audit-2026-08-30.md) — 5 critical
findings, 15 medium, ~60 minor, and 12 hand-rolled mechanisms with a native replacement.

The fixes were written in one 63-commit run outside this backlog. They are **landed back through
it**, task by task: each task below cherry-picks its commits in order, builds, lints and tests, and
amends what does not hold. Nothing is taken on trust — the run never compiled once (four Swift
errors), never linted once (eleven violations) and left one of its own tests failing.

Domains: every one. No new folder, no dependency.

## Tasks

Each task depends only on the previous ones. One task = one PR.

| # | Task | Findings | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 17.0 | **The audit is a record**: `docs/audits/` with the 2026-08-30 read kept verbatim, its README saying how an audit is worked (a finding becomes a backlog task, a fix commit cites its id, a wrong finding is closed with its reason), `AGENTS.md` pointing at the folder, and this milestone | — | — | — | S | 🟢 | |
| 17.1 | **Workspace and app**: path containment under the root, a login-shell resolution that cannot hang forever, the quit flush, and eleven minors — FSWatch latency, overlapping config reloads, `.pgpass` read like `libpq`, an unreadable config no longer read as absent, paths logged `.private`, `ThemeColor` and the terminal section. Plus four wheels: `state.json` through `Data`'s atomic option, font weights through `NSFontDescriptor`, the Keychain updated in place, the theme overrides through key-path tables — and `SecretStore` reduced to a struct of closures | M1, M2a, M6, W1–W11, R1, R3, R10, arch §1 | `Data.write(options: .atomic)`, `NSFontDescriptor`, `SecItemUpdate` | `WorkspaceStateTests`, `WorkspaceConfigTests`, `PgPassTests`, `SecretStoreTests`, `FSWatchServiceTests`, `ThemeServiceTests` | L | 🟢 | |
| 17.2 | **Editor and highlight**: the two retain cycles that leaked every closed tab, the stale-file guard defused by a tab switch, keystrokes lost around a save, silent search failures, and the main-actor work — gutter, preview images, `stat`, caret repaint. The quick-open walk yields and honours cancellation; the fold walk runs on an explicit stack; `splitLines` uses the standard split | C1, M2c, M2d, M3d, M3e, M4, M5, M13, E1–E7, R9 | `String.split`, `NSTextContentStorageDelegate` | `EditorTabTests`, `EditorFeatureTests`, `ContentSearchTests`, `QuickOpenIndexTests`, `MarkdownTests`, `FoldingTests` | L | ⚪ | |
| 17.3 | **Git**: the stash list that never parsed, the branches sheet invisible to SwiftUI, the pipes streamed and the kill gated on the live process, the paths git actually prints in a diff, merge commits against their first parent, history pagination and order, and nine minors — literal filters, superseded loads, rename origins, the snapshot run as a write, quoted auth arguments, dropped clients, weak panel descriptors, sheets on the right window, one formatter instead of one per row | C3, C5, M2b, M8, M10, M14, G1–G5, G7–G9, R7 | `@Observable`, `Date(_, strategy: .iso8601)`, `--fixed-strings` | `GitRemoteTests`, `DiffParserTests`, `LogParserTests`, `GitCLITests`, and golden tests against the real binary (17.15) | L | ⚪ | |
| 17.4 | **Postgres**: the retain cycle that kept the connection from ever closing, a connection held while a query still streams, the busy state told to the lifecycle rule, a live session left alone when its section did not change, the password resolved off the main actor, the clipboard handed rows instead of a joined TSV, and the value bugs — `money` under one unit, a zero-row select, the SQL editor's pending edits, the history's atomic write, identifiers quoted unconditionally | M3a, M3c, M9a–d, P1–P5, R12, arch §1 | `Mutex`, `Data.write(options: .atomic)` | `QueryValueTests`, `PostgresClientTests`, `SQLIdentifierTests` | L | ⚪ | |
| 17.5 | **The window stops leaking its layout graph**: the shortcut monitor's context closure captures `LayoutManager` strongly and `NSEvent.removeMonitor` only runs in a `deinit` AppKit keeps unreachable | C2 | `NSEvent.removeMonitor` on an explicit teardown | **deallocation tests** — a `LayoutManager` on a real `NSWindow`, closed, must go nil | M | ⚪ | |
| 17.6 | **A restored agent tab can be started**: agents R8 promises an `idle` tab with a *Relaunch* button, `buttonAction` maps `.idle` to `.activate` and the bar renders only for `.exited`. `RunFeature` already does it right; the current test pins the bug | C4 | — | `buttonAction(.idle)` → `.relaunch`, fixing the test that pins the bug | S | ⚪ | |
| 17.7 | **The browser stops opening arbitrary schemes**: every non-web scheme goes to `NSWorkspace.open` with no prompt and no user-gesture requirement, iframes included; `<input type="file">` is dead and the `dialog` fallback blocks app-modally | M7, T4 | `WKUIDelegate.runOpenPanelWith…` | `decidePolicyFor` on a `.system` scheme from a subframe | S | ⚪ | |
| 17.8 | **Layout focus and shortcuts**: `PanelManager.focusPanel` has no caller while `ZonesViewController.apply` re-asserts modelled focus on every update — a theme change yanks the keyboard out of a panel being typed in. With it, the layout minors: double confirm-close, the stale "reserved by layout" banner, write-only `Palette.query`, the missing duplicate-id guard, the tab button without a maximum width | M11, L1, L2, L4, L5, L7 | — | the banner after an override to another key; one confirmation per double `⌘W` | M | ⚪ | |
| 17.9 | **Explorer, terminal, run, agents**: a case-only rename safe against a crash and a collision, terminal zoom surviving the next `updateNSView`, the explorer activation loop honouring cancellation, bounded outline caches, control characters sanitised out of a mention before the PTY, an out-of-root symlink caught by the root check, a mention no longer swallowed by an idle tab, and the two catalog slips | M12, T1–T3, T5, T7, T8, A1, A2, R11 | `DateFormatter` with a fixed format | the sanitised mention, a symlinked operation contained, `AgentCatalog.isValid` | M | ⚪ | |
| 17.10 | **Render budget**: the layout snapshot JSON-encoded on every root body pass, the toolbar re-resolving every icon on every update, `IconImage.resolve` mutating the shared `NSImage(named:)` instance, and the full diff rendered to `AttributedString` on the main actor | M15, M3b | a dirty flag, `NSImage.copy()`, `@concurrent` | the snapshot encoded once per real change | M | ⚪ | |
| 17.11 | **The wheels still standing**: the greedy fuzzy-highlight walker disagreeing with the ranking while FuzzyMatch's own ranges are computed then discarded, raw key-code interception, and the divider-drag heuristic through `NSApp.currentEvent` | R4, R5, R6 | `control(_:textView:doCommandBy:)`, `NSSplitViewDelegate` | the highlight matches the ranking | M | ⚪ | |
| 17.12 | **Two points kept from the second review**: `isDirectory` spawns a `Task.detached` for one `getattrlist` — no cancellation from the parent `.task`, no inherited priority — where `@concurrent` does it structurally. And `KeychainSecretStore` sets no `kSecAttrAccessible`: prospective only, since on macOS the attribute binds in the data protection keychain and the default is already `WhenUnlocked` — set it in the write attributes, never in the search query | — | `@concurrent`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | a write then a read still finds the item | S | ⚪ | |
| 17.13 | **The two methodology gaps**: fixtures encode our assumptions instead of the tools' real output, and nothing checks deallocation. Golden tests drive the **real `git`** on a scratch repo and round-trip every parser; deallocation tests cover the tab, the layout and the Postgres feature; containment, editor concurrency, and rates and bounds get theirs | audit §4 | Swift Testing | the tests themselves | M | ⚪ | |

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done (with the PR number).

## How 17.1 to 17.4 are landed

The 63 commits live on `claude/swift-macos-code-audit-0haokz`. Each task cherry-picks its range **in
order**, then builds, lints and runs the suite before the task is called done. What is already known
to need amending:

| Amendment | Where | Why |
|---|---|---|
| `nonisolated extension SecretStore` | 17.1, `677e34b` | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes the extension's members main-actor; the closures call them from a `nonisolated` context |
| `String($0) + "\n"` in `splitLines` | 17.2, `a1db90f` | `Substring + String` does not type-check |
| `PipeIO` instead of `FileHandle.bytes` | 17.2 `cc4d803`, 17.3 `fa22ec3`, 17.1 `0e6e891` | Foundation runs every `AsyncBytes` iteration on one shared serial queue: stdout and stderr read at once take turns, the idle pipe holds the queue in a blocking `read(2)`, the other fills, and the child deadlocks. `GitCLIRunTests.readsAnOutputLargerThanThePipeBuffer` and two formatter tests fail on the run as pushed |
| `offset:` label on `DispatchIO.write` | 17.2, `cc4d803` | the call does not compile |
| a local binding before `[weak workspace]` | 17.1, `93e0631` | a `@State` property captured weakly conflicts with the implicit strong capture of the view |
| eleven `///` summaries split in two | 17.1–17.4 | `swift format lint --strict` is blocking in CI and fails on the run as pushed |

## Findings closed without a fix

- **R8 — fold queries on Neon's incremental tree.** Already decided against on 2026-08-28
  (`specs/editor/decisions.md`): Neon keeps its tree private, and the packages do not ship the
  queries. Verified 2026-08-30: of the fourteen tree-sitter grammars vendored here, **only
  `tree-sitter-swift` carries a `folds.scm`**. The replacement would mean writing and maintaining
  thirteen query files to replace thirty language-agnostic lines. The audit also overstates the
  cost: `EditorTab.refreshFolds` is debounced and cancels its predecessor, so the parse runs 300 ms
  after the typing stops, not every 300 ms, and it runs `@concurrent`.
- **W4 — side-effectful `@State` initial values in `WorkspaceView.init`.** Accepted and documented
  as a trap.
- **T6 — scattered synchronous `stat` on the main actor.** Accepted on local volumes.
- **L6 — layout reservation ignoring an override of the layout action itself.** Intended; the
  decision is written down.
- **E8 — `.jsonc` highlighted with the JSON grammar.** Needs a grammar decision, not code; open in
  `specs/editor/questions.md`.

## Definition of done

- Every commit of M17 builds, lints `--strict` and passes the suite — checked, not assumed.
- The stash list shows the stashes; a diff on a path with an accent opens the right file; a merge
  commit renders its changes.
- Closing a window releases its `LayoutManager`, proven by a test.
- An agent tab restored after a quit has a *Relaunch* button that works.
- No `git` command, formatter or login shell can wedge another through a shared queue.
- Every finding of the audit is either fixed, or closed above with its reason.

## Decisions to take during the milestone

- Whether Foreman moves to the data protection keychain (`kSecUseDataProtectionKeychain`), which
  would make the accessibility attribute of 17.12 real but requires an entitlement the app does not
  have and a migration of the secrets already stored.
- The `.jsonc` grammar (E8).
