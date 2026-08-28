# M13 — Explorer

M13 = **two requests of the author on 2026-08-28** for the file tree: open like IntelliJ, move by drag and drop. Domain [`explorer`](../specs/explorer/) (R12, R17, R21 amended; R22 added), [`editor`](../specs/editor/) R2 touched.

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 13.1 | **IntelliJ opening**: a click selects, a double click or `enter` opens pinned (`opt`: new group), no preview from the tree, rename from the menu or `shift+F6` (`space`, `cmd+↓` removed) | explorer R12, R17, R21; editor R2 | `NSOutlineView` `doubleAction`, `keyDown` | — (view only) | S | 🟢 (2026-08-28) | |
| 13.2 | **Drag and drop**: `ExplorerOperations.move` + `canMove` (itself, parent, descendant, clash refused), the outline's own pasteboard type, drop on a folder or the root, tabs follow | explorer R22, R17, R19 | `NSOutlineView` drag and drop (`registerForDraggedTypes`, `validateDrop`, `acceptDrop`), `FileManager.moveItem` | `canMove` rules; a move and a clash on a temporary folder | S | 🟢 (2026-08-28) | |

## Definition of done

- A double click on a file opens a normal tab; a second double click activates it; a click alone does nothing.
- Dragging `a.txt` onto `lib/` moves it, its open tab is renamed; dragging `lib/` onto itself shows no drop indicator.
