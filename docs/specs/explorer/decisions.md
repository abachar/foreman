# explorer — Decisions

| Date | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 2026-08-25 | Dotfiles visible; gitignored entries and folders on the exclusion list greyed out; `.git/` hidden; a toggle to hide the greyed-out ones | Dotfiles hidden (Finder); everything visible without greying | We often work in `.github`, `.env.example`…; greying gives the information without hiding it |
| 2026-08-25 | Basic CRUD (create, rename, delete to the trash, reveal, copy path), no drag and drop ("terminal here" removed on 2026-08-26, `product` R4) | Read-only; CRUD + D&D | The daily need without the cost of D&D; moving is done by the agent or outside Wraith |
| 2026-08-25 | Single click = preview tab (replaced), double click or an edit = pinned tab | Single click = pinned tab | The VS Code model, avoids piling up tabs |
| 2026-08-25 | The tree follows the active tab (a persisted toggle) and shows the git badges received from `Git.statusChanges` | An independent tree; an explorer that reads git itself | A single source of git status; the explorer never runs `git` |
| 2026-08-25 | Loading level by level, targeted reload of the parent folder on FSEvents, never a recursive walk | A full in-memory index of the workspace | Laziness (`architecture.md` P4); a `$HOME` workspace is possible |
| 2026-08-25 | Delete to the trash with confirmation, never a permanent delete | A direct `rm -rf` | Reversible; the terminal is there for the permanent kind |
| 2026-08-26 | View = `NSOutlineView` with a lazy data source; reloading through `reloadItem(_:reloadChildren:)`, no hand-written tree merge | SwiftUI `List`/`OutlineGroup`; a hand-merged tree model | Platform first (`architecture.md` P3): performance on large folders, state preservation for free |
| 2026-08-27 | New file / folder: the name typed in a sheet (`NSAlert` + a field); renaming stays inline in the cell | A ghost editable row in the `NSOutlineView` | A ghost row needs a fake item in the data source and its synchronisation; the sheet does the job in 20 lines |
