# Study — worktrees as child sections

> Feature `git`, third study (2026-10-16): every worktree of a repo, whoever created it, shows up in the Changes panel as a child section of that repo, with its branch and its uncommitted changes, and its branch can be taken back into the main folder in one action. Rules R33–R39; decisions in [`decisions.md`](decisions.md).

## Goal

Agents work more and more in worktrees of their own — Foreman's (`agents` R12) and the ones an agent creates by itself (Claude Code puts them wherever its project says). Today the Changes panel shows a repo's main folder only: a branch checked out in a worktree is a name in the branch list, its uncommitted work is invisible, and *Checkout* is refused by git ("already used by worktree"). Reading what the agent is doing means opening its folder in a second window.

A worktree is a second working copy of the same repo, on its own branch. The panel already knows how to show a working copy (a section); this study shows each worktree as one, under its repo, and adds the two actions git does not give in one step: take the branch back into the main folder, and remove the worktree.

## User stories

- US1 — An agent works in `~/Projects/…/worktrees/ccoe-frontend-scroll-top` on `fix/TGSCCPAG-467/…`. Under the `ccoe-frontend` section, a child section `fix/TGSCCPAG-467/… · ccoe-frontend-scroll-top` lists `M src/main.ts`; a click opens the diff, as for any change.
- US2 — The agent commits in its worktree: the child section empties and shows `↑1`, without my touching anything.
- US3 — The agent is done. From the child section's menu (or the branch list) › *Check Out Here*: the worktree folder goes away and its branch is checked out in my main folder, where I test it with my usual tools.
- US4 — I drop the attempt: *Remove Worktree*, the folder goes away, the branch stays.
- US5 — I want to edit in it myself: *Open as Workspace* opens the worktree folder in a new window.
- US6 — Before taking the branch, I review it: *Compare with main* lists only the agent's commits and opens one diff of everything the branch would bring, without checking anything out.

## Functional rules

### Discovery

- R33 — For every repo of R1, `git worktree list --porcelain -z` (`GitCLI`, a read, R26–R27) lists its worktrees; every entry other than the repo's own folder is a **child** of that repo. Entries marked `bare` or `prunable` (the folder is gone) are skipped; Foreman never runs `git worktree prune` (`agents` R13). The list is read at discovery and again whenever the repo's git folder changes under `worktrees/` (R35). Whoever created the worktree does not matter: the ones of `agents` R12 are children like any other.
- R33a — A repo that R1's scan finds and that is itself a linked worktree of another repo found by R1 is shown as that repo's **child**, not as a top-level section (no duplicate). A workspace opened on a linked worktree keeps its root as the top-level repo; the main folder and the other worktrees are its children.

### The child section

- R34 — A child is a full section (R2–R12) — status, stage/unstage/discard, commit, fetch/pull/push, stash, branches — run with `cwd` = the worktree folder; it sits indented under its parent, its header shows the **branch first** (or `detached HEAD @ abc1234`), then `↑n ↓m`, the folder name in grey, and a `worktree` badge (`lock` too when the entry is `locked`) — a worktree holds one branch at a time and a branch is held by one worktree at most, so the branch names the row (**amended 2026-10-16**, from review). Layout: branch, `↑n ↓m` and folder on the left; the badges **right-aligned**, just before the pull/push buttons and the menu, so they line up from one child to the next. When the panel is narrow, the folder name is truncated first (tail), then the branch (middle, the full name in the tooltip); the badges and buttons never are. R2's automatic collapsing applies as to any section; the manual one is persisted under the child's id = the worktree folder's persisted path (`Workspace.persistedPath`, absolute outside the root).
- R34b — **A repo with children becomes a group** (2026-10-16, from review: the main folder's changes must fold on their own). Its header keeps the repo name and *Fetch* (repo-wide); its chevron folds the whole group. The menu (branches, stash, the worktree actions) belongs to each working copy, since those commands run in its folder. Its own working copy becomes the **first child**, a section like the others headed by its branch and `↑n ↓m`, without the `worktree` badge, with its own pull/push, so each working copy folds on its own. A repo without children keeps R2's single section, no extra level. The group's fold is persisted under the repo id, the main working copy's under `<repo id>#main`; R2's automatic collapsing applies to each working copy, never to the group.
- R34c — **Which agent works where** (2026-10-16, from review: several agents, each in its own worktree, watched from one window). `agents` publishes the window's agent sessions (tab, agent, title, cwd, state, bell; `agents` R6); a working copy (a child, or the main one of R34b, or a plain R2 section) whose folder contains a session's cwd carries one **agent badge** per session: the agent's icon and title, a dot while `running`, the bell when the tab rang (`terminal` R7). Clicking a badge activates that tab (`agents` R4's activation). Several sessions in the same folder → several badges, by title. Worktree children with at least one session come first, then the others, each group by folder name; the order changes when a session opens or closes, never on a state change (no rows jumping while agents work). An agent that moved to a worktree of its own making while its tab started elsewhere is matched on the tab's starting cwd only (see questions.md).
- R34a — Opening a changed file of a child opens it by its absolute URL (`editor`: opening an absolute path); the explorer does not follow it outside the root (`explorer` R14). The diff tab (R13–R17) works unchanged, its payload carrying the child's id. The history panel's repo picker (R18) lists the children under their parent.
- R35 — Refreshing (R4): a child's git folder (`<repo>/.git/worktrees/<name>/`) is inside the parent's `.git`, already observed when the parent is under the root; the worktree folder itself is observed by a dedicated FSEvents stream when it lies outside the root. A change under `<repo>/.git/worktrees/` re-reads R33 for that repo (a worktree added or removed by the terminal or an agent appears or disappears without a relaunch). A hidden panel observes nothing (R4).

### Actions

- R36 — The branch list (R23): a branch checked out in a worktree carries the worktree's folder name as a badge; *Checkout* is replaced by *Check Out Here* (R37) and *Show Changes* (expands and scrolls to the child section); *Delete* stays refused by git, Foreman shows its message.
- R36b — *Compare with <base>* (child header menu, 2026-10-16 from review: read a worktree's work without checking it out). Base = the parent's current branch (its main working copy, R34b); *Compare with…* asks for another one among the repo's local branches (a pop-up, the parent's branch selected), the choice not persisted. Detached parent → only *Compare with…*. Two results:
  - the history panel (R18) opens on the child with the range `<base>..<head>` (`git log --first-parent <base>..<head>`): only the commits the branch adds; a `vs <base>` chip above the list, its `×` going back to R18's plain log. R19's click and menu work unchanged.
  - a `git.diff` tab (R13) of `git diff <base>...<head>` (three dots: since the merge base, what a merge would bring), titled `<head> vs <base>`; refreshed when either ref moves (R4 already observes `.git/refs/` and the child's `HEAD`), never on the working tree — uncommitted changes stay in the section itself. Old side = `<merge base>:<path>`, new side = `<head>:<path>`.
  `<head>` = the child's branch, or its sha when detached. Nothing is written: two reads (R26). Base and head equal or no commit ahead → the tab says "no difference" and the history is empty.
- R37 — *Check Out Here* (child header menu, R36): `git worktree remove <folder>` **without** `--force` (git refuses when the worktree has modified or untracked files: its message is shown in the parent's banner, nothing else happens), then `git checkout <branch>` in the parent (R23: git decides, a refusal is shown). If the checkout is refused after the removal, the banner says so: the branch is intact, nothing was lost (the worktree was clean). Not offered for a detached child (no branch to take).
- R38 — *Remove Worktree* (child header menu): confirmed with the folder and the branch name, then `git worktree remove <folder>` without `--force` (refusal shown as in R37). The branch is kept; deleting it is R23. A `locked` worktree: the entry is disabled with git's lock reason as its tooltip. `agents` R13 keeps its own `--force` removal for the worktrees it created.
- R39 — *Open as Workspace* (child header menu): the worktree folder opens in a new window, the same path as *File › Open…*.

## Edge cases

- A worktree under the root (inside the workspace): R33a makes it a child; the explorer still shows its files as part of the tree, as today.
- The worktree folder is deleted by hand: the entry turns `prunable` and the child disappears at the next R33 read; the branch is untouched.
- Two worktrees of the same repo: two children, ordered by folder name.
- A submodule's worktrees: listed only when the submodule is itself a repo of R1 (`config.repos`), like the submodule.
- `git worktree list -z` needs git ≥ 2.36: the minimum version checked at first call (00-study, edge cases) moves from 2.35 to 2.36.

## Out of scope

- Creating a worktree from the panel (`agents` R12 creates the agents' ones; otherwise the terminal).
- Merging a worktree's branch into another one (R23, the terminal).
- `git worktree move`, `lock`/`unlock`, `repair`, `prune`.
- Excluding a worktree outside the root from tracking (R1's `!` entries are paths under the root).

## Technical options

- `GitFeature` gains `worktrees(of:)` (`worktree list --porcelain -z` through `GitCLI`, parsed by a pure `WorktreeParser` over `\0`-separated `key value` lines → `[GitWorktree { folder, head, branch?, locked, prunable }]`); the existing `removeWorktree(in:folder:)` gains a `force` argument (`agents` R13 keeps `true`, R37–R38 pass `false`). No library: ~60 lines.
- `GitRepo` gains `parent: String?` (the parent's id); `GitModel.setRepos` orders children right after their parent. The section view indents when `parent != nil`; nothing else in the panel changes.
- R35's stream: a second `FSWatchService` owned by `GitFeature`, rooted at the children outside the root, rebuilt when R33 changes the list (the shared service's roots are fixed at creation). `GitModel.reposToRefresh` learns `.git/worktrees/` as relevant (re-read R33) and maps `.git/worktrees/<name>/HEAD|index` to the child.
- R39: `ForemanAppDelegate.open(folder:)`, the call *File › Open…* already ends in.
- R36b: `GitDiffPayload.Source` gains `.range(base:, head:)` (mutable like `.session`: refreshed on ref changes, its old side the merge base read by `git merge-base` at each refresh); `GitHistoryModel` gains an optional `range` prepended to its `log` arguments. No new view.
- R34c: `AgentsFeature` publishes `sessions: AsyncStream<[AgentSession { tab, agent, title, cwd, state, bell }]>`; `WorkspaceView` hands it to `GitFeature` as it hands `Git.statusChanges` to the explorer, so `Git/` never imports `Agents/` (`agents` already calls `git`). Matching a session to a working copy = the longest working-copy folder that is a prefix of the cwd (pure). `AgentsFeature.primaryTabs` and `buttonAction` go away (`agents` R4 amended).
- Tests: `WorktreeParser` over real `-z` fixtures (main, a branch, a detached, a locked with reason, a prunable, a bare); R33a's parent/child pairing over a temporary repo with `git worktree add`; R37 on a temporary repo (clean → branch in the parent; dirty → refused, folder kept); `reposToRefresh` with `.git/worktrees/` paths; R36b on a temporary repo (two commits on the branch, one on the base after the fork → the range log lists the two, the three-dot diff ignores the base's own commit); the `.range` payload round trip; R34c's matching (nested folders, a cwd outside every repo, two sessions in one folder) and ordering (a state change keeps the order, a closed session moves its child down); `agents` R4's titles (`Claude`, `Claude 2` after the first is still open).
