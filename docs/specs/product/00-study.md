# product — Study

## Goal

Foreman is a native, **agentic** macOS development environment: one window = one folder = one workspace (IDE model). At its heart are the CLI agents (Claude Code, Antigravity, OpenCode…), each in its own tab on a terminal surface (SwiftTerm), one click away from the toolbar ([agents](../agents/)). **There is no free-form shell**: a terminal surface only exists to host an agent or a `run` command — no tab for typing `cd`, `ls`… Everything else (explorer, editor, git, Postgres, run) are features that attach panels around it (`architecture`).

## Target user

- A single user: the author. No release, no onboarding, no backward compatibility to guarantee in v1.
- Consequence: we optimise for iteration speed and personal comfort, not for generality.

## User stories

- US1 — As a user, I open a folder (`foreman .` or through the app) and I get a window dedicated to that folder.
- US2 — I can open several workspaces in parallel, each in its own window, without interference.
- US3 — In the center zone I work with tabs (agents, files, diffs, runs…) and I can split horizontally or vertically; each split has its own tab bar.
- US4 — I can show/hide the side and bottom panels from the keyboard, without ever losing the center zone.
- US5 — When I reopen a workspace, I find my tabs, splits and panels as I left them.
- US6 — With one click in the toolbar, I launch (or find again) my CLI agent in its tab, and I launch my project's commands.

## Functional rules

- R1 — A window corresponds to exactly one root folder (the workspace). Opening an already-open folder activates the existing window instead of creating a new one.
- R2 — Several windows/workspaces can coexist; the state (tabs, panels, config) is isolated per workspace.
- R3 — The center zone is a tree of splits (H/V) whose leaves are **tab groups**. The tab group is a single component, reused for every leaf.
- R4 — Every tab group accepts every kind of tab (agent, run, editor, diff…). There is **no default kind** and no free-form shell tab: a group without tabs shows the **home screen** (`layout` R33).
- R5 — The center zone always stays visible; the left/right/bottom panels are added around it, one visible panel per slot (detail in [layout](../layout/)).
- R6 — The workspace state is persisted on close and restored on open: split tree, tabs (kind + cwd/file), active tab per group, visible panels, zone sizes.
- R7 — Restored agent/run tabs are **recreated** (a new surface in the same cwd, the command not relaunched, `agents` R8 / `run` R13); the scrollback content is not restored in v1.
- R8 — **Amended 2026-08-30** (from use: launching from the Dock landed on `$HOME`, and the folder was then chosen by hand every time). Launching Foreman without a folder **reopens the last workspace**. The folder of a window is chosen in this order: the command-line argument, a folder handed by the system while launching (`open -a`, a folder dropped on the icon), the most recent workspace that still exists, then `$HOME`. Foreman notes every workspace it opens in the system's recent documents list, which also feeds *File ▸ Open Recent*. There is still no window without a folder: no welcome window, no chooser (decision 2026-08-30).
- R9 — Every workspace has a `.foreman/` folder at its root for the local config and the persisted state (detail in [config](../config/)).
- R10 — Local execution only: no signing, notarization, Homebrew, auto-update or telemetry in v1.
- R11 — Every window has a native **toolbar** above the zones: agent buttons on the left ([agents](../agents/)), the Run button on the right ([run](../run/)). Features declare their items there; the layout owns it (detail in [layout](../layout/)).

## Edge cases

- Folder deleted/moved between two openings: the window opens on a clear error, the persisted state is kept (not erased).
- `open -a Foreman <folder>` may deliver the folder after the launch window on `$HOME` was created (R8): that window is then replaced (closed without persisting anything), so there is only one window (R1).
- The file of an editor tab is gone at restoration: the tab is ignored (or opened empty and read-only — to be settled in editor).
- Closing the last tab group of a split: the split collapses; there is always at least one group in the center zone.

## Out of scope for v1

- Distribution (signed DMG, Homebrew tap, App Store) — see M6 in the README, deferred.
- Multi-user, state synchronisation between machines.
- Detached window / floating tabs.
- Restoring the terminals' scrollback.
- Third-party or runtime-loaded extensions: features are compiled into the app (`architecture`).

## Decisions

See [decisions.md](decisions.md).
