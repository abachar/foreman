# M23 — Performance: main actor, concurrency, memory

Eighth round driven by use (2026-10-17), after [M22](m22-redesign-follow-up.md). Not a feature
milestone: the batch that closes [`audit-2026-10-17.md`](../audits/audit-2026-10-17.md) — the three
axes the author asked for (120 Hz budget, concurrency model, memory), sized against `ccoe` (four
repos, 2 002 files in scope, P95 file 49 KB, 2–3 agents at a time, session diffs up to 228 files).

The audit's own rule applies first: **measure before optimising** (`architecture.md` → Performance).
23.1 adds the intervals; 23.5 and 23.6 are decided on its trace, not on the reading (see
[Measured](#measured-on-ccoe-2026-10-17)).

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
| 23.1 | **Measure**: three `os_signpost` intervals in `Perf` — `explorer.reload` (around `ExplorerOutlineView.Coordinator.sync`), `diff.render` (`GitDiffModel.render`, per file as an event), `editor.keystroke` (`CurrentLineTextView.didChangeText` to the end of `rebuildLines`) — then one `xctrace` run on `ccoe` with two agents streaming and the explorer unfolded; the numbers written in the `explorer`, `git` and `editor` decisions and in [Measured](#measured-on-ccoe-2026-10-17) here | U1, U2, U4, M2 | `OSSignposter`, `xctrace` (attach, never `--launch`) | — (the numbers are the deliverable) | S | 🟢 | |
| 23.2 | **Diff rendered as it goes**: `GitDiffModel.render` renders the expanded files first and publishes `rendered[file.id]` as each completes; a folded file of a large diff is rendered when `expandedFiles` gains it, not before; the `for run in string.runs` recolouring moves into the `@concurrent` render | M2 | `@concurrent`, `Task` per expansion, `@Observable` dictionary | the order of rendering (expanded first), a folded file not rendered until expanded, a load superseded mid-render leaves no partial state | M | 🟢 | |
| 23.3 | **Derived values cached**: `ThemeService.tokens` stored, recomputed in `apply` and when `systemIsDark` changes (not per access); `GitRepo.canonicalPath` resolved once per `GitRepo` (a stored property, set at its creation) and an agent session's `canonicalCwd` once when it is built, so `GitModel.groups` and `agentSessions(in:)` do no syscall in a body; `GitModel.Section.sections` computed once per status | U5 | `@Observable` stored properties, `didSet` | `tokens` follows `apply` and is stable between reads, a repo's stored `canonicalPath` equals the static one, `owner(ofCanonicalPath:)` on strings, a section's lists follow its status | S | 🟢 | |
| 23.4 | **One `lineStarts`**: `LineNumberRulerView` and `StickyLinesView` read `CurrentLineTextView.lineStarts` instead of computing or copying their own; `TerminalTab.didSetTitle` tests equality before assigning; `ContentSearch.run` uses `Task {}` (or justifies `detached` in a comment); the criterion « a task is retained and cancelled by its owner when the user can see it end » written in `coding-rules.md` → Concurrency | U2, K2, K4 | — | the ruler's numbers after an edit (unchanged behaviour), `subtitle` not republished for an identical title | S | 🟢 | |
| 23.5 | **Explorer reload under an agent** — *measured on 2026-10-17: a partial reload is 3.9 ms at the median and 42.8 ms at worst, the threshold is met*: `Workspace.configChanges()` built with `bufferingPolicy: .bufferingNewest(1)` (not `statusChanges()`, per repo; never `TerminalService.events()`); the model journals its changes (`ExplorerModel.Change`) and `Coordinator.sync` replays them: a status reloads the cells of the rows it changed, a status with no change bumps nothing | U4, K3 | `AsyncStream.Continuation.BufferingPolicy` | a rafale of three statuses applies the last one; a status with no change reloads nothing | M | 🟢 | |
| 23.6 | **Terminal rendering on the GPU** — *re-scoped on 23.1's trace (2026-10-17)*: the parser is 2.5 % of the main thread under two streaming agents, the CoreGraphics draw (`TerminalView.draw` → `drawTerminalContents`, one `NSAttributedString` per row per frame, the box-drawing renderer) is nine tenths of it; moving the parser off the main thread (U1 as written) would gain nothing visible. SwiftTerm ships a Metal renderer (`MacTerminalView.setUseMetal(_:)`, `metalBufferingMode`, `metalRendererStatus`, a documented API): `TerminalSurfaceView` enables it when the view enters its window (the library's documented moment), falls back to CoreGraphics when `setUseMetal` throws, and the surface's zoom and theme font keep working; validated on Claude Code, OpenCode and a `cargo build`-class stream, with the 120 Hz trace before and after. | U1 | SwiftTerm `setUseMetal(true)` | `isUsingMetalRenderer` after creation; **by eye**: two agents streaming, the editor typing, a zoomed surface, light and dark | M | 🟢 | |
| 23.7 | **Orders of magnitude written**: `architecture.md` → Performance gains the measured costs — a full terminal surface ≈ 30 MB, an editor tab ≈ 3× its file, the quick-open index ≈ 150 B a file — and the `ccoe` numbers of the audit's §5 and of [Measured](#measured-on-ccoe-2026-10-17) as the reference workspace | M1, M3, M4 | — | — | S | 🟢 | |
| 23.8 | **A keystroke scans bytes, not characters** — *found by 23.1*: `editor.keystroke` is 10 ms at the median and 19 ms at worst on a 55 KB Java file, over the 8.33 ms frame; the time is `IndentGuides.levels(of:)` — `String.split` then `for character in line`, a grapheme walk of the whole buffer — not `lineStarts`. `levels` walks `utf8` (a line's indentation is ASCII spaces and tabs, a non-ASCII byte ends it like any other). The ruler's one `offset(from:to:)` per draw (≈ 1 ms on the same file) is left as is: under the frame, noted. Found on the way: `String.split(separator: "\n")` never split a CRLF file (`\r\n` is one `Character`), so its levels were out of step with the line starts; the byte pass splits at every `\n` | U2 | `String.UTF8View`, `withContiguousStorageIfAvailable` | the levels unchanged on the existing fixtures (tabs, mixed, empty lines, non-ASCII leading text); measured 1.1 ms (Debug) on a 58 KB fixture | S | 🟢 | |
| 23.9 | **Scrolling a large diff** — *found by 23.1, to study*: scrolling the rendered diff gives frames of 8–15 ms, in `GitDiffView.hunkView` (one `HStack` of SwiftUI `Text` per line inside a `LazyVStack`, built as rows scroll in); the study weighs one `Text` per hunk (one attributed string with the gutter in a tab stop) against an `NSTextView` per file. Studied 2026-10-17 (git decisions): the rows' `LazyVStack` is nested in a `VStack` in the tab's `LazyVStack`, so it is not lazy — every row of every expanded hunk is built at once; first lever → 23.11 | M2 | — | — | S (study) | 🟢 | |
| 23.10 | **Quick open under typing** — *found on the way, 2026-10-17*: `QuickOpenIndex.build()` sets `isBuilt` before walking and yields every 512 files; the palette cancels the previous search at each keystroke, so the walk started by one keystroke sees `Task.isCancelled` at its next yield and **empties the index**, while the next keystroke's `search`, finding `isBuilt == true`, scores a half-built index and shows nothing (`cmd+p` then a full class name on `ccoe`: no result; the matcher itself finds the file at 0.96). The build becomes one shared `Task` on the actor, awaited by every search and cancelled by none of them; an unfinished build is restarted by the next search | — | `actor`, one retained `Task<Void, Never>` | two overlapping searches during a build both see the full index; a cancelled search leaves the index built; `setIgnored` during a build restarts it | S | 🟢 | |
| 23.11 | **One flat lazy stack for the diff** — *from 23.9*: `GitDiffView.content` becomes one `LazyVStack` whose direct children are the file headers, the hunk headers and the rows (a flattened `ForEach` over an array of `Row` enum values — `.file`, `.hunk`, `.row` — built from `diff.files` and `model.rendered`), so SwiftUI builds only the rows in and near the viewport; `fixedSize`, `textSelection`, the context menu and the height pairing of R13b unchanged. To measure by the reviewer: the `UpdateCycle.Stalls` count while scrolling a large diff, on the Release build | M2 | `LazyVStack`, `ForEach` over an `Identifiable` enum | the flattened rows of a diff (order, ids unique, a folded file contributes its header only); **by eye**: a large diff scrolled, selection and *Send to Agent* still work | S | 🟢 | |
| 23.12 | **An excluded file does not hide its siblings** — *found on the way, 2026-10-17*: `skipDescendants()` after a file or a symlink skips the folder enumerated right after it; `QuickOpenIndex` and `SelectorIndex` call it only after a directory (measured on `ccoe-backend`: 57 files indexed before, 800 after) | — | `FileManager.DirectoryEnumerator` | a folder with `.DS_Store` (or a symlink) and 200 sibling folders fully indexed; a `.css` next to a `.DS_Store` indexed | S | 🟢 | |

## Measured on `ccoe` (2026-10-17)

Two `xctrace` captures (Time Profiler + `os_signpost`, attached to the Release build `8ff2382`
installed in `/Applications`, the author at the keyboard), on `/Users/abachar/Projects/ThalesDigital/ccoe`,
explorer unfolded on both repos. Traces and the export scripts in the session's scratchpad
(`trace/m23.trace`, `trace/m23b.trace`, `profile2.py`, `signposts.py`), not kept in the repo.

**Capture 1 — 75 s, nothing running** (two Claude Code sessions open and idle, the author scrolling a
large diff): the main thread is busy 2.6 % of the time. Ten frames of 8–15 ms, all while scrolling
the diff, in `GitDiffView.hunkView` (23.9). One partial `explorer.reload` of 27 ms inside a 68 ms
frame.

**Capture 2 — 120 s, two Claude Code sessions streaming** (a full build asked in each), the author
typing in a 55 KB Java file and unfolding folders:

| What | Measure |
|---|---|
| Main thread busy | 17.9 % (21.7 s of 121 s) |
| AppKit update cycles over 8.33 ms (`UpdateCycle.Stalls`) | 1 007, median 17.9 ms, P95 26.9 ms, worst 213 ms |
| Main-thread samples entering through `TerminalView.draw` | 55 % (12 001 of 21 674) — CoreGraphics draw: `drawTerminalContents`, one `NSAttributedString` per row, `BoxDrawingRenderer` for the agents' frames |
| Main-thread samples with no Foreman frame (AppKit's own cycle: layer tree, tracking areas, autolayout, SwiftUI graph) | 37 % (7 949) — the cycle the terminal's invalidations run at 60 Hz |
| Main-thread samples in the VT parser (`LocalProcess.enqueueReceivedData` → `Terminal.feed`) | **2.5 %** (537) |
| `editor.keystroke` (42 keystrokes, 55 KB file) | median 10.1 ms, P95 17.2 ms, worst 19.4 ms — `IndentGuides.levels(of:)`'s character walk, not `lineStarts` |
| `explorer.reload` partial (5) | median 3.9 ms, worst 42.8 ms (inside the 213 ms frame, with the outline cells' creation) |
| `diff.render` (1) | 0.04 ms — a refresh with no changed file re-renders nothing (23.2 holds) |

What the trace decides: **U1 is not the main thread's problem** — the parser is 2.5 %, the
rendering is nine tenths, so 23.6 is re-scoped to SwiftTerm's Metal renderer (awaiting the author);
**23.5 goes** (3.9 ms median, 42.8 ms worst against a 2 ms threshold); **U2 reopens** on a part the
audit had not named (`levels`, 23.8); the audit's §5 numbers stand.

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

Planned on 2026-10-17 and built the same day on `feat/m23`, one commit per task: 23.0–23.4, then the
trace of 23.1 on `ccoe` with the author (two agents streaming), then 23.10, 23.8, 23.6 (the author
chose Metal), 23.5, 23.7, the study 23.9 and its lever 23.11. 740 tests green. Left: the « after »
trace on the installed Release build, with the author streaming two agents again, to compare with the
1 007 frames over budget of the « before » trace; and the by-eye checks of 23.6 (two agents
streaming, a zoomed surface, light and dark) and 23.11 (a large diff scrolled, selection and *Send
to Agent*). Pre-existing and out of scope: four warnings in `HoverPopover.swift:109–114`
(main-actor calls from a nonisolated context), present on `main` before M23.
