# explorer — Study

## Goal

Left panel `explorer.tree`: the workspace's file tree, lazy, refreshed by FSEvents, from which files are opened (as a preview or pinned) and basic CRUD is done. It shows the git states provided by `git`, without depending on it.

## User stories

- US1 — `cmd+shift+e`: the tree appears on the workspace root, folders collapsed; I expand on demand, without waiting.
- US2 — I create/rename/delete a file in the terminal: the tree updates on its own in less than a second.
- US3 — Clicking a file opens it as a preview in the active group; double-clicking pins it. Clicking another file replaces the preview.
- US4 — When I switch tabs, the tree expands to and selects the matching file.
- US5 — I can tell at a glance what is modified (git) and what is ignored (greyed out).
- US6 — Right-click: new file/folder, rename, delete, reveal in Finder, copy the path.

## Functional rules

### Content and filtering

- R1 — The root of the tree is the workspace root; it is not shown as a node, its children are the first level.
- R2 — Sorting: folders first, then files, each by case-insensitive name (`localizedStandardCompare` order, so `file2 < file10`).
- R3 — Everything is visible except `.git/` (and `.wraith/state.json`, `.DS_Store`). Dotfiles are shown.
- R4 — Entries **ignored by git** (information received from `git`, R15) are greyed out. Folders on the shared exclusion list (`architecture.md`: `node_modules`, `target`, `.build`…) are greyed out even without git information, and never expanded automatically (R11).
- R5 — A "hide ignored files" toggle (the panel menu, persisted in `state.json`) hides the greyed-out entries. Default: visible.
- R6 — Symlinks: shown with a dedicated icon, expandable when they point to a folder, never followed during a recursive operation (deletion, refresh).

### Loading and refreshing

- R7 — Loading is **level by level**: a folder's content is read at its first expansion (laziness, `architecture.md` P4). No recursive read, ever.
- R8 — The first level is read when the panel is shown (`layout` R4), off the main actor, and rendered as soon as it is available. A folder with more than 5,000 entries is shown truncated ("… and N more") with a button to load everything.
- R9 — Refreshing through `FSWatchService` (the single FSEvents stream, `architecture.md`): on an event on a path, only the parent folder concerned is reloaded (`reloadItem(_:reloadChildren:)`), and only if it is expanded (a collapsed folder is re-read at its next expansion). The subscription is only active while the panel is visible; on reactivation, the expanded folders are reloaded once.
- R10 — Reloading a folder keeps the expanded state, the selection and the scroll for the items still present; that is `NSOutlineView`'s behaviour with items that have a stable identity (the relative path), nothing to merge by hand.
- R11 — The expanded state is persisted in `state.json` (a list of relative paths) and restored; greyed-out folders (R4) are never restored expanded.

### Opening

- R12 — Single click on a file: opens a **preview** tab in the active group through `Editor.open(path, preview: true)`; one preview tab per group, replaced by the next preview. `cmd+↓`, `cmd+k`, or any edit in the tab, pins it (`editor` defines the tab; the double click renames since 2026-08-28, R17). Clicking a file that is already open: activates its tab.
- R13 — `opt+click` (or a menu entry): opens in a **new group** on the right (`layout` R9) when you want to compare.
- R14 — Following the active tab (`Layout.activeTab`): when the active tab changes and matches a file under the root, the tree expands the path and selects the file (without scrolling if it is already visible). Can be turned off by a panel toggle (persisted). A file outside the root expands nothing.
- R15 — Git badges: the explorer subscribes to `Git.statusChanges` (an `AsyncStream` of `(repo, [path: GitFileStatus])`); it colors the files (modified, added, untracked, conflicted) and propagates a dot onto the ancestor folders. Outside a repo: no badge, no error.

### Operations

- R16 — New file / new folder: created in the selected folder (or the parent of the selected file, or the root), the name typed in a sheet (decision 2026-08-27), then the file is opened (pinned). The name may contain `/` to create the intermediate folders.
- R17 — Rename: inline editing (`enter` on the item, a double click, or the menu; never a single click on a selected row, decision 2026-08-28). The explorer calls `Editor.fileRenamed(old, new)` so that the open tabs follow.
- R18 — Delete: to the **trash** (`trashItem`), with a confirmation listing the number of items for a non-empty folder. The explorer calls `Editor.fileDeleted(path)`.
- R19 — Any operation is refused if the target path is not under the root (`architecture.md`, security) or if the name is empty, `.`/`..`, or contains a forbidden character. An IO error (permission, already exists) is shown in the panel's banner and does not modify the tree.
- R20 — Context menu: New file, New folder, Rename, Delete, Reveal in Finder, Copy path (relative to the root), Copy absolute path, Send to Agent (`agents` `01-study-send.md` R10b, 2026-08-28). No "terminal here" (`product` R4), no file copy/cut/paste, no drag and drop.
- R21 — Keyboard navigation in the tree: `↑↓` move, `→` expands / `←` collapses or goes up, `enter` renames, `space` opens as a preview, `cmd+↓` opens pinned, `cmd+delete` deletes, `escape` gives the focus back to the center (`layout` R6).

## Edge cases

- Unreadable folder (permissions): shown with a lock icon, expanding does nothing, no blocking error.
- A burst of events (`git checkout`, `npm install`): `FSWatchService`'s debounce (~300 ms) coalesces them; the explorer re-reads each folder concerned once per burst.
- The selected file is deleted from outside: the selection is lost, no message.
- A rename that only changes the case (`Foo` → `foo`) on case-insensitive APFS: allowed, done through a temporary name.
- Network or slow volume: reading off the main actor keeps the UI responsive; a folder being read shows a "loading" state.
- Workspace = `$HOME`: a huge but lazy tree; `Library` is greyed out through the shared exclusion list.

## Out of scope for v1

- Drag and drop, file copy/cut/paste, moving between folders.
- Searching in the tree (`cmd+p` quick open is in `editor`).
- Icons per file type (one file / folder / link icon is enough).
- Multi-selection and batch operations.
- Opening a file with an external application (other than "reveal in Finder").
- Watching files outside the root.

## Technical options

- **Folder**: `Sources/Wraith/Explorer/`.
- **View**: `NSOutlineView` in an `NSViewRepresentable` (platform first, `architecture.md` P3), with a lazy data source: `numberOfChildren`/`child(index:)` read the level at the first expansion, `reloadItem(_:reloadChildren:)` for R9. An item's identity is its relative path.
- **Model**: `FileNode` (a `struct`, `Identifiable` by relative path): name, kind (file/dir/symlink), isIgnored, children loaded or not. `ExplorerModel` (`@MainActor @Observable`) holds the selection, the badges and the toggles; reading a level is a plain `FileManager.contentsOfDirectory(resourceKeys: isDirectory, isSymbolicLink, isHidden)` in a `Task` off the main actor.
- **Operations**: `FileManager` (`createDirectory`, `moveItem`, `trashItem`), errors wrapped in `ExplorerError`.
- **Links with the other features** (direct calls, `architecture.md`): consumes `FSWatchService`, `Layout.activeTab`, `Git.statusChanges`; calls `Editor.open(path, preview:, newGroup:)`, `Editor.fileRenamed`, `Editor.fileDeleted`.
- **Tests**: sorting (R2), filtering (R3–R5), name and path validation (R19), badge propagation (R15), on a temporary directory.

## Decisions

See [decisions.md](decisions.md).
