# Study — session diff

> Feature `git`, second study (2026-08-28): the cumulative diff of what an agent changed since it was launched, to read before committing. Rules R30–R32; decisions in [`decisions.md`](decisions.md).

## Goal

The changes panel shows the worktree against the index: after a long agent session it mixes the user's own edits, earlier commits and the agent's work. The session diff answers "what did *this* agent do": a snapshot of the working tree at spawn, then a diff of the current working tree against it.

## User stories

- US1 — I launch Claude, it works for ten minutes; the button menu › *Session Changes* opens a diff tab listing every file it touched, refreshed as it keeps working.
- US2 — Claude created a new file: it is in the diff (untracked files count).
- US3 — I relaunch the agent in the same tab: the snapshot is taken again.

## Functional rules

- R30 — **Snapshot** = a tree object of the whole working tree (tracked, modified and untracked, minus ignored), built without touching the user's index: `GIT_INDEX_FILE=<temporary file> git add -A` then `git write-tree` (`git` R26, R29: the binary, a temporary index outside `.git/`). Taken by `agents` on the tab's `started` event (`terminal` R16: spawn, and every relaunch whether from the button or from the surface), for the repo containing the tab's cwd (`git` R1; a worktree of `agents` R12 is its own repo). No repo → no snapshot, the entry is absent.
- R31 — **Session diff** = `git diff <snapshot tree> <current tree>` where the current tree is built the same way at every refresh (`git` R4: the repo's status changes trigger it, coalesced). Shown in a `git.diff` tab (`git` R13, R13b: side by side, highlighted, read only) whose source is `.session(base:, title:)`; the tab title is `<agent title> · session`. Old side = `<base tree>:<path>`, new side = `<current tree>:<path>`.
- R31a — Entry points: the agent button menu (`agents` R5) gets *Session Changes* when the button's tab has a snapshot; the agent tab's own view gets nothing (the terminal is SwiftTerm's). One session-diff tab per agent tab (reused, `layout` R12 by analogy).
- R32 — The snapshot's sha lives in the agent tab's payload (`agents` R8): restoration keeps the diff readable as long as the object exists (`git gc` prunes dangling trees after two weeks by default; a pruned base → the tab shows `git` R28's error, and the next relaunch takes a new one).

## Edge cases

- The agent committed part of its work: the session diff still shows it (the base is the worktree at spawn, not `HEAD`). The changes panel shows the rest.
- The user edits files while the agent runs: those edits are in the session diff too — the diff is "what changed since spawn", the title says so.
- A very large repo: `add -A` into a temporary index costs a `status`-like walk; it runs on the same coalescing as `git` R4, off the main actor.

## Out of scope

- Per-hunk actions (`git` R15 removed them).
- A diff between two arbitrary points (the terminal).
- Snapshots for `run` tabs.

## Technical options

- `GitCLI` runs `add -A`/`write-tree` with an `env` override (`GIT_INDEX_FILE`) — the existing `Process` runner gains one optional argument.
- `GitDiffPayload.Source` gains `.session(base: String, current: String?, title: String)`; `GitDiffModel` computes the current tree before diffing and uses the existing old/new object naming. The view does not change.
