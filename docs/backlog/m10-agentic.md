# M10 — Agentic workflow

M10 = **the author's list of 2026-08-28**: talk to the agent from what is on screen, review and isolate what it does, fill the Run palette from the project, fold code. Five studies, no new domain, no new folder: `agents` (`01-study-send.md`, `02-study-worktrees.md`), `git` (`01-study-session-diff.md`), `run` (`01-study-detected.md`), `editor` (`02-study-folding.md`).

Two fixes shipped before the milestone on `main` (2026-08-28): TypeScript/TSX highlighting (editor decision), rename on double click (explorer decision). `config.agents` with a custom command (`"claude": { "command": "claude --dangerously-skip-permissions" }` or a custom id) already works as `agents` R3 says: checked in the running app, nothing to do. The `sql` grammar stays blocked upstream (`editor/questions.md`: `main` still on `.package(name:)`, last tag `v0.3.11`, checked 2026-08-28).

The **Library / native** column is mandatory (`AGENTS.md`).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 10.1 | **Send to the active agent**: `AgentsFeature.send(_:)` + the last activated agent tab; `cmd+e` in an editor tab (file or selection lines), in the tree and in a diff tab; *Send to Agent* in the explorer's context menu and on a diff line; the agent tab activated after the write | agents R10–R10d, explorer R20, `shortcuts.md` | `TerminalService.write` (SwiftTerm `send`); `NSMenu` entries already there; `NSString.lineRange` | the text for a file / folder / line / range and relative-vs-absolute paths (pure function); the active-agent choice (last activated, exited skipped, none); the selection's lines | S | 🟢 (2026-08-28; three ids `editor/explorer/git.sendToAgent`, checked with Claude Code: `@server/src/admin/views.tsx`, `@server/src/`) | |
| 10.2 | **Detected commands**: `RunCatalog.detect` over `package.json` scripts (pm by lockfile), `pom.xml`, `Package.swift`, `Makefile` targets; merged after the declared ones; palette subtitle = the manifest; refreshed on config changes and on manifest changes | run R14–R16 | `FileManager`, `JSONDecoder`, `Regex`; `FSWatchService` | detection on temporary folders (each manifest, the lockfile → pm, a malformed manifest skipped), precedence of a declared id | S | ⚪ | |
| 10.3 | **Session diff**: `GitCLI` env override; `snapshotTree(repo)` (temporary index + `write-tree`); `GitDiffPayload.Source.session`; taken at spawn/relaunch by `agents`, stored in the tab payload; *Session Changes* in the button menu; refreshed with the repo | git R30–R32, agents R4, R5, R8 | `git add -A` / `write-tree` / `diff <tree> <tree>` through `GitCLI`; the existing `GitDiffView` | the source's old/new object names; the payload round trip; `snapshotTree` on a temporary repo (untracked file included, the real index untouched) | M | ⚪ | |
| 10.4 | **Worktrees**: *New Session in a Worktree* (root / each repo), branch `wraith/<agent>-<stamp>`, folder under Application Support; the tab restored in it; *Remove Worktree* (confirmed, tab closed first, branch kept) | agents R12–R13 | `git worktree add/remove` through `GitCLI`; `NSAlert` | the branch and folder naming (pure), the menu entries for a repo/non-repo root, the payload round trip; `worktree add` on a temporary repo | M | ⚪ | |
| 10.5 | **Code folding**: regions from the syntax tree; a gutter chevron; `cmd+opt+[` / `cmd+opt+]`; a one-line custom `NSTextLayoutFragment` for a folded region; unfold on edit inside | editor R26–R28, `shortcuts.md` | SwiftTreeSitter `Node` walk; TextKit 2 `NSTextLayoutManagerDelegate` | the regions found on Swift / TS / JSON snippets (nesting, one-liners, `} else {`), the region containing a line | L | ⚪ | |

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

## Definition of done

- Each entry point of 10.1 checked by hand in the running app with Claude Code (the `@path` mention is taken).
- 10.2: a `package.json` workspace shows its scripts in `cmd+r` with no config; a declared command with the same id wins.
- 10.3: a file created by the agent appears in the session diff; the user's index is untouched (`git status` before/after).
- 10.4: a worktree agent edits a file → the main worktree is clean; *Remove Worktree* leaves the branch.
- 10.5: folding a function in `views.tsx` hides its body, the line numbers skip it, typing inside unfolds it.
- No new `…Manager`/`…Service`, no protocol, no dependency added.

## Decisions to take during the milestone

- 10.1: `cmd+e` vs a `cmd+shift+…` — `cmd+e` was free (`shortcuts.md`) and is one hand.
- 10.3: whether the current tree is rebuilt on every status change or only when the tab is visible (P4 says visible only).
- 10.5: whether Neon exposes its tree; otherwise a second parse.
