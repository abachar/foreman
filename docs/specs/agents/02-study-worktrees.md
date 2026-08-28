# Study — an agent in its own git worktree

> Feature `agents`, third study (2026-08-28): launch an agent on a throwaway branch in a dedicated `git worktree`, so two agents (or the agent and the user) never edit the same files. Rules R12–R13; decisions in [`decisions.md`](decisions.md).

## Goal

Two agents on the same worktree step on each other; one agent on the user's worktree makes the user wait to edit. A worktree is git's answer: a second checkout of the same repo, on its own branch, with a shared object store. Wraith creates it, launches the agent in it, and lets the user review its work (session diff, [`../git/01-study-session-diff.md`](../git/01-study-session-diff.md)) and remove it.

## User stories

- US1 — Right-click on the Claude button › *New Session in a Worktree*: a worktree and a branch `wraith/claude-20260828-1432` are created, Claude starts in it, the tab title says `Claude (wraith/claude-20260828-1432)`.
- US2 — When the agent is done, I open the session diff of that tab and read what it changed.
- US3 — I merge the branch (terminal or git panel), then *Remove Worktree* from the button menu: the folder goes away, the branch stays.

## Functional rules

- R12 — Entry: the button menu (`agents` R5) gets *New Session in a Worktree* for the workspace root when it is a git repo, and one per repo of `config.repos` (`git` R1) otherwise (`… in <repo>`). Creation = `git worktree add -b wraith/<agent>-<yyyyMMdd-HHmm> <folder> HEAD` through `GitCLI` (`git` R26); then `spawn` (`agents` R4) with `cwd` = the worktree folder, `primary: false`. Failure (dirty index is not one; a branch name clash is) → the error in an alert, no tab.
- R12a — The folder: `~/Library/Application Support/Wraith/worktrees/<workspace folder name>/<branch name without the prefix>`. Never under the workspace root (it would show as untracked in the main repo and in the explorer; `git` R29 forbids touching `.git/info/exclude`).
- R12b — The tab is an ordinary agent tab (`agents` R6–R8): restored `idle` in the worktree folder; a missing folder at relaunch is the banner of `terminal` R8. Its title carries the branch in parentheses.
- R13 — *Remove Worktree* (the button menu, one entry per worktree tab of the window, confirmed with the folder and the branch name): the tab is closed first (`terminal` R10, R11), then `git worktree remove --force <folder>` (uncommitted changes in the worktree are lost: the confirmation says so). The branch is **kept**; deleting it is `git` R23. `git worktree prune` is never run by Wraith.

## Edge cases

- The repo is bare or the root is not a repo: the entry is absent.
- The user deletes the folder by hand: the tab shows `terminal` R8's banner; *Remove Worktree* still runs (`--force` handles a missing folder) and prunes the entry.
- Two workspaces on the same repo: the folder name includes the workspace folder, the branch name the minute; a clash within the minute fails on `-b` and is reported.

## Out of scope

- Merging, rebasing, cherry-picking the branch from the menu (`git` R19, R23, the terminal).
- Opening the worktree as a workspace (`File › Open…` does it).
- Listing worktrees not created by Wraith.

## Technical options

- `git worktree add/remove` through the existing `GitCLI` (`Process`, `arguments: [String]`); no library.
- The worktree folder and branch live in the agent tab's payload (`agents` R8) so restoration and *Remove Worktree* survive a relaunch.
