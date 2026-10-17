# M23 — Performance: main actor, concurrency, memory

Eighth round driven by use (2026-10-17), after [M22](m22-redesign-follow-up.md). Not a feature
milestone: the batch that closes [`audit-2026-10-17.md`](../audits/audit-2026-10-17.md) — the three
axes the author asked for (120 Hz budget, concurrency model, memory), sized against `ccoe` (four
repos, 2 002 files in scope, P95 file 49 KB, 2–3 agents at a time, session diffs up to 228 files).

The audit's own rule applies first: **measure before optimising** (`architecture.md` → Performance).
23.1 adds the intervals; 23.4 and 23.5 are decided on its trace, not on the reading.

Domains: [`terminal`](../specs/terminal/00-study.md) (R14, the surfaces' queue), [`git`](../specs/git/00-study.md)
(R13, R16: the diff's rendering), [`explorer`](../specs/explorer/00-study.md) (R9, R15: the reload on
a status), [`design`](../specs/design/00-study.md) (R8–R11: the tokens), [`layout`](../specs/layout/00-study.md)
(R27: the snapshot), [`editor`](../specs/editor/00-study.md) (R6, R54–R56: one `lineStarts`). No new
folder, no dependency.

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Tasks

One branch `feat/m23` from `main`, one commit per task; each commit cites its finding id in the body
(`audit U5`). Nothing starts before the author's go.

| # | Task | Findings | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 23.0 | **The audit is a record**: `docs/audits/audit-2026-10-17.md`, its row in the audits README, this milestone and its row in the backlog README | — | — | — | S | 🟡 | |
| 23.1 | **Measure**: three `os_signpost` intervals in `Perf` — `explorer.reload` (around `ExplorerOutlineView.Coordinator.sync`), `diff.render` (`GitDiffModel.render`, per file as an event), `editor.keystroke` (`CurrentLineTextView.didChangeText` to the end of `rebuildLines`) — then one `xctrace` run on `ccoe` with two agents streaming and the explorer unfolded; the numbers written in the `explorer`, `git` and `editor` decisions and in §5 of the audit's follow-up here | U1, U2, U4, M2 | `OSSignposter`, `xctrace` (attach, never `--launch`) | — (the numbers are the deliverable) | S | 🟡 | |
| 23.2 | **Diff rendered as it goes**: `GitDiffModel.render` renders the expanded files first and publishes `rendered[file.id]` as each completes; a folded file of a large diff is rendered when `expandedFiles` gains it, not before; the `for run in string.runs` recolouring moves into the `@concurrent` render | M2 | `@concurrent`, `Task` per expansion, `@Observable` dictionary | the order of rendering (expanded first), a folded file not rendered until expanded, a load superseded mid-render leaves no partial state | M | 🟢 | |
| 23.3 | **Derived values cached**: `ThemeService.tokens` stored, recomputed in `apply` and when `systemIsDark` changes (not per access); `GitRepo.canonicalPath` resolved once per `GitRepo` (a stored property, set at its creation) and an agent session's `canonicalCwd` once when it is built, so `GitModel.groups` and `agentSessions(in:)` do no syscall in a body; `GitModel.Section.sections` computed once per status | U5 | `@Observable` stored properties, `didSet` | `tokens` follows `apply` and is stable between reads, a repo's stored `canonicalPath` equals the static one, `owner(ofCanonicalPath:)` on strings, a section's lists follow its status | S | 🟢 | |
| 23.4 | **One `lineStarts`**: `LineNumberRulerView` and `StickyLinesView` read `CurrentLineTextView.lineStarts` instead of computing or copying their own; `TerminalTab.didSetTitle` tests equality before assigning; `ContentSearch.run` uses `Task {}` (or justifies `detached` in a comment); the criterion « a task is retained and cancelled by its owner when the user can see it end » written in `coding-rules.md` → Concurrency | U2, K2, K4 | — | the ruler's numbers after an edit (unchanged behaviour), `subtitle` not republished for an identical title | S | ⚪ | |
| 23.5 | **Explorer reload under an agent** — *only if 23.1 shows `explorer.reload` over ~2 ms*: `GitFeature.statusChanges()` and `Workspace.configChanges()` built with `bufferingPolicy: .bufferingNewest(1)` (never `TerminalService.events()`); `applyGitStatus` keeps `lastLoaded` when a status changes no visible row, so `sync` reloads the touched folders rather than the root | U4, K3 | `AsyncStream.Continuation.BufferingPolicy` | a rafale of three statuses applies the last one; a status with no change reloads nothing | M | ⚪ | |
| 23.6 | **Terminal parsing off the main thread** — *decided on 23.1's trace*: read `AppleTerminalView` / `LocalProcessTerminalView` for `usesMainQueue == false` (how the view reads the buffer while the parser mutates it); if the library supports it, `TerminalSurfaceView` hands `LocalProcess` a serial queue per surface; validated on Claude Code, OpenCode and a `cargo build`-class stream, with the 120 Hz trace before and after. If the library does not support it, the task is closed with the reading as its reason | U1 | SwiftTerm `LocalProcess(delegate:dispatchQueue:)` | the surface's output unchanged on a VT fixture; **by eye**: two agents streaming, the editor typing | L | ⚪ | |
| 23.7 | **Orders of magnitude written**: `architecture.md` → Performance gains the measured costs — a full terminal surface ≈ 30 MB, an editor tab ≈ 3× its file, the quick-open index ≈ 150 B a file — and the `ccoe` numbers of the audit's §5 as the reference workspace | M1, M3, M4 | — | — | S | ⚪ | |

## Closed without a change (2026-10-17, with the author)

- **U3** (`ensureLayout(documentRange)`): invisible under 50 KB, `ccoe`'s P95; kept on record, no task.
- **U7** (one-`stat` IOs on the main actor): harmless off a network volume; recorded.
- **U6** (`layout.snapshot()` per root body pass): the snapshot's reads are what makes SwiftUI persist a tab's cursor and scroll (editor R4) — a version counter on the layout alone would stop persisting them; the encode is a few microseconds per tab at ccoe's tab counts. Closed with the reason (2026-10-17).
- **K1** (state read before an `await`): no observable effect today; recorded.
- **K5** (`SearchModel.add` copy-on-write): bounded by the 2 000 cap; recorded.
- **M1** as a lever (`terminal.scrollback` key): 3–5 surfaces on `ccoe`, ≤ 150 MB; not a priority.
- **M3** (evicting hidden editor tabs): would reopen onto U3 for nothing at `ccoe`'s file sizes.
- **Not recommended by the audit** (§6): a dedicated `SerialExecutor`, a `Mutex` on model state, an incremental tree-sitter parse in `Folding`.

## Decided with the author (2026-10-17)

- 2–3 agents at a time is the nominal case: U1 is the only structural finding, instructed (23.6) before being decided.
- Commit sizes stand in for session diffs; the frontend's P90 already trips git R16's large mode: 23.2 is a necessity, not a comfort.
- File sizes (P95 49 KB) close every per-keystroke finding except the duplicated `lineStarts`.
- Code starts on the author's explicit go, after this milestone is read.

## Where it stands

Planned on 2026-10-17. 23.0 in progress (the audit and this file written, not yet committed).
