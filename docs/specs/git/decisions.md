# git — Decisions

| Date | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 2026-08-25 | The `git` binary through `Process`, machine formats (`--porcelain=v2 -z`, `--format`) | libgit2 / SwiftGit2 | Hooks, signing, credential helpers, `pull.rebase`… honoured for free; no C to wrap; SwiftGit2 is barely maintained |
| 2026-08-25 | Full scope: status, stage/unstage/discard, commit/amend, per-hunk diff, log, fetch/pull/push, branches, stash | Read-only; stage+commit only | The terminal stays available, but the daily work fits in the panel |
| 2026-08-25 | Every repo stacked as collapsible sections | One repo at a time | An overview of a multi-repo workspace (the main use case) |
| 2026-08-25 | An inline unified diff in a center tab; a linear `--first-parent` log in a bottom panel | Side by side; a branch graph | Enough to review before committing; the graph is a large rendering project |
| 2026-08-26 | The diff colored through the shared `Highlight/` folder (replaces the "no highlighting" decision of 2026-08-25) | tree-sitter imported into `Git/`; +/− diff only | Highlighting is a shared component (`architecture.md`); `Git/` calls it directly |
| 2026-08-26 | `GIT_TERMINAL_PROMPT=0`; an interaction required → a banner with the command to copy, no terminal opened (replaces "switch to a terminal" of 2026-08-25) | Typing credentials into Wraith; an ephemeral terminal surface | No secret in the app (`architecture.md`, security); no free-form shell (`product` R4); the case is rare with a configured helper/SSH agent |
| 2026-08-25 | Discard, drop stash, `-D`, checking out a commit, reset, cherry-pick, revert: confirmed; `reset --hard` and `push --force` absent from the UI | Everything reachable; nothing destructive | The destructive stays explicit; the irreversible stays in the terminal |
| 2026-08-25 | Never an automatic `fetch`; refreshing through FSEvents (worktree + `.git/HEAD`, `index`, `refs/`) | Polling; a periodic fetch | No unrequested network, no disk polling (`architecture.md`) |
| 2026-08-26 | `GitCLI` a concrete type, no `GitService` protocol and no `FakeGitService` | A protocol + a test double | A single implementation (`architecture.md` P1); the parsers are tested over fixtures, the panel over hand-built `GitStatus` values |
| 2026-08-25 | Commit through `-F <temporary file>`, without `--no-verify` and without bypassing the config | The message as an argument; a "skip hooks" option | Safe multi-line messages; the user's hooks are their policy, not ours |
