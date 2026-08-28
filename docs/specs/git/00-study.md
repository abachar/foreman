# git — Study

## Goal

Feature `git` (folder `Git/`): an overview of the changes across every repo in the workspace, stage/unstage/discard, commit, inline diff, linear history, and the everyday operations (fetch/pull/push, branches, stash) — all of it by calling the user's `git` binary, so that their config (hooks, signing, credential helpers; aliases excluded) is honoured.

Surfaces: right panel `git.changes` (decision 2026-08-27: next to the explorer, not instead of it) (`cmd+shift+g`), right panel `git.history` (`cmd+shift+h`, the same slot as the changes: one replaces the other, decision 2026-08-27), center tab `git.diff`.

## User stories

- US1 — `cmd+shift+g`: I see, per repo, what is modified, staged, untracked, conflicted, with the branch and how far ahead/behind its upstream it is.
- US2 — I stage two files, write a message, `cmd+enter`: the commit is made with my usual hooks and my usual GPG/SSH signature.
- US3 — I click a modified file: the diff opens in the center, as a preview, side by side.
- US4 — `cmd+shift+h`: the current branch's log; a click shows the commit's diff.
- US5 — I fetch/pull/push from the repo's bar; if git asks for interactive authentication, the error tells me clearly, with the command to run.
- US6 — I switch branches, create one, stash/unstash without opening the terminal.
- US7 — I run `git commit` in the terminal: the panel updates on its own.

## Functional rules

### Repos

- R1 — Repos = `config.repos` (`config` R3), otherwise auto-detection (`.git/` up to depth 2, shared exclusions). The workspace root itself, if it is a repo, is the repo `"."`. A `.git` file (worktree/submodule) is accepted.
- R2 — Each repo is a **section** of the changes panel: a header (name, current branch or `detached HEAD @ abc1234`, `↑n ↓m` against the upstream, fetch/pull/push buttons, a menu), and a body = the list of changes. A section is automatically collapsed when there is no change; a manual collapse is persisted.
- R3 — No work before the panel is activated (laziness, `architecture.md`). On activation: `status` on every repo in parallel; the panel shows each section as soon as its result arrives. No automatic `fetch`, ever (no unrequested network access, `architecture.md`).
- R4 — Refreshing: through `FSWatchService`, on the repo's paths **and** on `.git/HEAD`, `.git/index`, `.git/refs/`, `.git/MERGE_HEAD`; one event → a `status` on the repo concerned, coalesced (one run at a time per repo, the next one waits). A hidden panel listens to nothing; reactivation = a full `status`.
- R5 — The feature exposes `Git.statusChanges` (`AsyncStream<(repo, [path: GitFileStatus])>`), emitted after every `status` (consumed by `explorer` R15, `editor` R18). The status includes the ignored entries through `--ignored=matching` (decision 2026-08-27: measured free; a folder ignored as a whole is listed once, as `dir/`).

### Changes

- R6 — Two lists per repo: **Staged** and **Changes** (worktree + untracked), plus **Conflicts** at the top when there are any. Each row: status (`M A D R C U ?`), path relative to the repo (name in bold, folder in grey), buttons on hover: stage/unstage, discard, open the file.
- R7 — Per-file actions: stage (`git add -- <path>`), unstage (`git restore --staged -- <path>`), discard (`git restore -- <path>`; untracked → `git clean -f -- <path>`), open the file (`Editor.open(url, preview:)` — the API takes the file's `URL`, not the relative path), open the diff (R12). Per-section actions: stage all / unstage all / discard all.
- R8 — **Discard always asks for confirmation** (one file or all of them), with the number of files and the word "irreversible". No other action is destructive in the git sense (everything stays in the reflog).
- R9 — Conflicts: the row offers *Mark as resolved* (`git add`) and opens the file with its markers; no merge tool in v1. A `MERGING`/`REBASING`/`CHERRY-PICKING` state is shown in the header with *Abort* and *Continue* (`git merge --abort`, `rebase --continue`, etc.).

### Commit

- R10 — A message area at the bottom of the section (multi-line, the first line is the subject, a 72-character counter), a *Commit* button and `cmd+enter` (scope: the message field). Commit = `git commit -F <temporary file>` on the index as it is; nothing to stage → the button is disabled. An *Amend* option (a checkbox, prefills the message from `HEAD`).
- R11 — The commit goes through the user's hooks and signature (the `git` binary, config not bypassed: never `--no-verify`, never `-c commit.gpgsign=false`). Hook failure: the output is shown in the section's banner, the message is kept.
- R12 — An uncommitted message is kept per repo in `state.json` (not versioned: `config`), until the commit.

### Diff

- R13 — Center tab `git.diff` (a preview, `explorer` R12 by analogy; pinned on a double click): an **inline unified** diff, a header per file, numbered hunks, added/removed lines colored, old/new line numbers, **syntax highlighting** through the shared `Highlight/` folder (the grammar is derived from the extension, degradable to +/− colors alone). Read-only.
- R13b — A **side-by-side** layout (old on the left, new on the right, a removed run facing the added run that follows it) is the default of the diff tab; a segmented control switches to inline. Both use the same highlighting and tint (author's request, 2026-08-27).
- R14 — Sources: the worktree file against the index (`git diff -- <path>`), the index against HEAD (`git diff --cached`), a whole commit (`git show <sha>`), a file of a commit. Title: `path (working tree)`, `path (staged)`, `abc1234 subject`.
- R15 — **Removed on 2026-08-27** (the author does not stage by hunk): no per-hunk stage/unstage/discard, no line-by-line editing; staging is per file (R7). The number is kept so the other rules do not move.
- R16 — Binary file: "binary, N KB → M KB". A diff over 5,000 lines: collapsed per file, expanded on demand. Renames detected (`-M`).
- R17 — The diff of a worktree file refreshes with R4 (the file is edited again); a commit's diff is immutable.

### History

- R18 — Right panel `git.history` (same slot as `git.changes`): a repo picker (the one from the active section of the changes panel by default), a **linear log** of the current branch (`git log --first-parent`), pagination by 200 commits ("load more"), columns: short sha, subject, author, relative date, ref badges (branches, tags, `HEAD`). A text filter on subject/author (`--grep`/`--author`).
- R19 — Click: the commit's diff (R14) as a preview. Menu: copy the sha, *Checkout* (detached HEAD, confirmed), *Create a branch here*, *Cherry-pick* (confirmed), *Revert* (confirmed, creates a commit), *Reset soft/mixed* (confirmed; `--hard` is **absent** from the UI, terminal only).
- R20 — A file's history: from a file's menu (explorer or changes) → the same panel, filtered (`git log --follow -- <path>`).

### Remote, branches, stash

- R21 — Fetch/pull/push (the section header): `git fetch --prune`, `git pull` (honours the user's `pull.rebase`), `git push` (`-u origin <branch>` when there is no upstream, after a confirmation naming the remote). An activity indicator in the header; error output in the banner. **One remote operation at a time per repo.**
- R22 — Every command is launched with `GIT_TERMINAL_PROMPT=0` and without `SSH_ASKPASS`: if git needs an interaction (passphrase, an interactive credential helper, 2FA), the failure is detected and shown in an "authentication required" banner with the exact command (`git push`, the repo's cwd) and a *Copy the command* button — to be run through the agent or outside Wraith. No terminal surface is opened by `git` (`product` R4). No secret is ever typed into Wraith. The lasting remedy: a non-interactive credential helper / SSH agent.
- R23 — Branches (the header menu, or a click on the branch): a list of local + remote branches with a search field; *Checkout* (refused with an explanation when the worktree has changes that conflict with the target — git decides, Wraith shows), *New branch from HEAD*, *Rename*, *Delete* (local only, `-d`; `-D` asks for confirmation with the name), *Set the upstream*. No deletion of remote branches in v1.
- R24 — Stash: *Stash* (an optional message, includes untracked files with `-u` as an option), the section's stash list (collapsed), *Apply* / *Pop* / *Drop* (drop confirmed). Conflict on apply: R9 applies.
- R25 — Tags: shown in the log; creating/deleting them is out of scope (terminal).

### Running git commands

- R26 — A single `GitCLI` type (no protocol: a single implementation): `Process` with `arguments: [String]`, the executable resolved once per window (in the login shell's `PATH`, `Workspace.loginEnvironment()`; overridable through `git.path` in the `git` section of `.wraith/config.json` — there is no global config, config decision 2026-08-26), `cwd` = the repo root, a minimal env + `LC_ALL=C`, `GIT_EDITOR=true` (git's prepared messages are accepted as they are: the commit message always comes through `-F`, R10), `GIT_OPTIONAL_LOCKS=0` for reads, stdout/stderr separated, a **timeout** (30 s for reads, 10 min for writes — the user's hooks — and remote operations), cancellation = `SIGTERM` then `SIGKILL`.
- R27 — Machine formats only: `status --porcelain=v2 -z --branch`, `log --format=<fields separated by \x1f> -z`, `diff` with `--no-color --no-ext-diff -M`, `for-each-ref --format`, `stash list --format`. Never parse output meant for humans; no user output is ever fed back into a command except as an argument after `--`.
- R28 — Errors translated into `GitError` (`notARepo`, `commandFailed(stderr)`, `needsInteraction`, `timeout`, `conflict`, `gitNotFound`, `cancelled` when the user stops a command); `git` not found → the feature shows a single banner and stays inert (nothing breaks the opening, `architecture.md`).
- R29 — The feature **never writes** into `.git/` other than through the binary, and never modifies the user's git config.

## Edge cases

- A repo declared but missing: ignored with a warning (`config`). A repo without a commit (unborn `HEAD`): a "no commit" section, committing is possible.
- Submodules: listed as repos only when they are in `config.repos`; otherwise they appear as a modified entry of the parent.
- A huge repo (`status` > 30 s): timeout, with a banner offering to remove the repo from `config.repos`.
- A modern `git` is required (≥ 2.35 for stable `--porcelain=v2` and for `restore`): the version is checked on the first call, otherwise a banner.
- Two windows on workspaces sharing a repo: each has its own instance of the feature; git's index lock arbitrates, and an `index.lock` error is retried once after 500 ms.
- A slow hook (tests in pre-commit): an activity indicator, cancellable (kills the hook).
- Files with `\n` or non-UTF-8 in their name: `-z` everywhere, paths handled as bytes → `URL`.

## Out of scope for v1

- A three-way merge tool, assisted conflict resolution.
- A branch graph, a multi-branch log, blame, bisect, interactive rebase.
- Managing remotes, tags, remote branches (deletion), LFS, submodules (init/update).
- `reset --hard`, `push --force`: terminal only, deliberately.
- GitHub/GitLab (PRs, issues).

## Technical options

- **Execution**: `GitCLI` (a concrete type, an `actor`) in `Git/`, one per repo, serialising write commands, concurrent reads allowed. Parsing in pure functions (`StatusParser`, `LogParser`, `DiffParser`) → `GitStatus`, `GitCommit`, `GitDiff`, types belonging to the feature; only `GitFileStatus` leaves `Git/` (R5).
- **Diff**: `git diff` is already structured by hunks (`@@ … @@`); a minimal unified-diff parser (~150 lines) is enough to produce `GitDiff { files: [FileDiff { hunks: [Hunk { lines }] }] }` — we keep the simplest thing, no library. Highlighting: `Highlight.highlight(text, language)` (the shared folder) applied per file to the "new" and "old" text of the hunks; `Git/` does not import tree-sitter.
- **Tests**: parsers (status v2, log, diff, for-each-ref) over real fixtures; argument construction (never a shell, `--` before paths); `needsInteraction` detection on stderr. The panel's logic (R6–R9) is tested over hand-built `GitStatus` values, without a `GitCLI` double.

## Decisions

See [decisions.md](decisions.md).

Later study: [`01-study-session-diff.md`](01-study-session-diff.md) (R30–R32, session diff).
