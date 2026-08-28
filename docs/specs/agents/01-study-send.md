# Study — send to the active agent

> Feature `agents`, second study (2026-08-28): put a file, a selection, a path or a diff line into the prompt of the agent the user is talking to, without retyping the path. Extends [`00-study.md`](00-study.md) (rules R10–R11 below); decisions in [`decisions.md`](decisions.md).

## Goal

The user reads a file, a diff or the tree, and wants to tell the agent "look at this". Today they type the path by hand. One shortcut / one menu entry writes `@<path>` (the mention syntax of Claude Code, OpenCode, Pi) into the PTY of the **active agent**; the user finishes the sentence and presses `enter` themselves.

## User stories

- US1 — I have a file open, I press `cmd+e`: `@server/src/admin/views.tsx ` appears in the agent's prompt.
- US2 — I select lines 12–30 and press `cmd+e`: `@server/src/admin/views.tsx:12-30 ` appears.
- US3 — In the explorer, right-click on a folder › *Send to Agent*: `@server/src/ ` appears.
- US4 — In a diff, right-click on a line › *Send to Agent*: `@path:line ` appears (the new file's line number; the old one for a removed line).
- US5 — Several agent tabs are open: the text goes to the one I used last.

## Functional rules

- R10 — **Active agent** = the `agent.*` tab most recently activated in the window (the `activated` event of `terminal` R16), whatever its state; with none ever activated, the first agent tab of the window in bar order. No agent tab → the entries are disabled and the shortcut does nothing (a `debug` log). Wraith never launches an agent to send it text.
- R10a — The text written: `@<path>` for a file or a folder (a folder keeps its trailing `/`), `@<path>:<line>` for one line, `@<path>:<from>-<to>` for a selection spanning several lines; a trailing space; never a newline (the user submits). The path is relative to the agent tab's cwd when the file is under it, absolute otherwise. It is written as is through `TerminalService.write` (`terminal` R16), no bracketed-paste, no quoting: a path with spaces is the user's problem, as in the agents' own prompts.
- R10b — Sources and their entry points:
  - editor tab (`editor.file`): `cmd+e` (`agents.send`, scope `tab(editor.file)`) — the selection's line range when it is not empty, the file otherwise;
  - explorer: the context menu (*Send to Agent*, `explorer` R20 extended) on a file or folder, and `cmd+e` while the tree has the focus (scope `panel`);
  - git diff tab (`git.diff`): the context menu on a line (*Send to Agent*: `path:line`), and `cmd+e` on the tab (scope `tab(git.diff)`: the file, or the commit's sha as `<sha>` when the tab shows a whole commit).
- R10c — The agent's tab is activated after the write (the user sees the text and types the rest). Its group takes the focus.
- R10d — The feature owning the source builds the text (it knows its paths); `AgentsFeature.send(_ text: String)` picks the tab and writes. No provider protocol: three direct calls.

## Edge cases

- The active agent tab has `exited`: the text is written to a dead PTY — refused: R10 skips exited tabs and falls back to the next most recent one; all exited → the entries are disabled.
- A selection whose end is at column 0 of the next line does not include that line.
- The diff of a whole commit (`git show <sha>`) has no single path: `cmd+e` sends `<sha>`; the line menu still sends `path:line`.

## Out of scope

- Sending the selection's **text** (the agent reads the file itself).
- A "send to a specific agent" submenu; the shortcut goes to the active one.
- Bracketed paste, multi-line prompts, auto-submit.

## Technical options

- `AgentsFeature` already tracks `agentOfTab`; R10 adds the last activated `TabID` fed by the existing `events()` stream (`activated`). ~20 lines.
- `TerminalService.write(_:to:)` exists (`terminal` R16). Nothing new in `Terminal/`.
- Editor: `NSTextView.selectedRange` → line numbers through `NSString.lineRange`. Explorer: the node's relative path. Diff: `GitDiffModel`'s rendered lines carry their numbers already.
