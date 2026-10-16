# M20 — History: the files of a commit

Fifth round driven by use (2026-10-16), right after [M19](m19-worktrees.md): reading a commit file by file from the History panel, one diff layout instead of two, one file tree for the whole app, and the commit area always in reach.

Domains: [`git`](../specs/git/00-study.md) — R10, R19 and R13b amended, R19b new — and `design` R23 (the shared tree). No dependency, no new folder; `Layout/FileTree.swift` is new.

Size: S < ½ an agent-day, M ≈ 1 day, L ≈ 2 days. Status: ⚪ to do · 🟡 in progress · 🟢 done.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 20.1 | **The commit's files**: a click on a commit splits the panel, the log on top and the commit's files below as an R6b tree (`show --name-status -z -M`, parsed by `CommitFilesParser`); a click on a file previews its diff in the center, a double click pins it; a double click on the commit opens it whole | git R19, R19b | SwiftUI `VSplitView`, `PathTree` (R6b) | `CommitFilesParser` over statuses, renames and copies; a real commit with a rename and a new file | M | 🟢 (2026-10-16) | |
| 20.3 | **One tree everywhere**: `Layout/FileTree.swift` — `FileTreeStyle` (the outline's setup), `FileTreeCell` (icon, name in the status colour, grey detail, hover buttons, the status letter), `FileTreeView` (a read-only tree, sized to its rows in the Changes panel); the explorer builds on the style and the cell; the Changes groups and the commit files are `FileTreeView`s; `PathTree` and the SwiftUI rows removed | design R23, git R6b, R19b | `NSOutlineView`, `TokenRowView`, `FileIcon` | `FileTreeNode.build` (nesting, folded chains, order, a rename's detail) | M | 🟢 (2026-10-16) | |
| 20.4 | **The commit area at the bottom**: one message area under the Changes list, a picker of the working copies, following the last one worked in | git R10 | SwiftUI `Picker` | the target's default, its follow-up and its fallback | S | 🟢 (2026-10-16) | |
| 20.2 | **Side by side only**: the inline layout, its control and its rendering removed from the diff tab | git R13b | — | the existing diff tests | S | 🟢 (2026-10-16) | |

## Where it stands

Built and tested on 2026-10-16; to be checked by hand by the author.
