# M9 — Tabs and home screen

M9 = **small layout comforts asked by the author after M8**: the IntelliJ closing actions on a tab, and a home screen that documents every shortcut. Extensions of the `layout` domain (R33 amended, R35; decisions 2026-08-28), no new domain, no new folder.

Domain covered: [`layout`](../specs/layout/).

The **Library / native** column is mandatory (`AGENTS.md`).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 9.1 | **Tab context menu**: *Close*, *Close Other Tabs*, *Close All Tabs*, *Close Unmodified Tabs*, *Close Tabs to the Left*, *Close Tabs to the Right* on every tab of the bar; entries with nothing to close disabled; the tabs close one by one through the existing `closeTab` (R15 confirmations, R10 group collapse) | layout R35, R15, R10 | SwiftUI `.contextMenu` (native `NSMenu`); `TabGroup.tabs(toClose:around:)` a pure function | the selection for each of the five multi-tab entries (pivot, dirty tabs, edges); the manager closes in bar order and stops at a refusal | S | 🟢 (2026-08-28) | |
| 9.2 | **Home screen on two columns**: agents + recent on the left; on the right every bound action of the registry grouped by feature, in registration order, rows performing the action, families folded into one row (`Tab N`, `Focus Group ←→↑↓`), the block centred; the `actions` home section and its two registrations (Open File, Run Command) removed | layout R33 (amended), design R19 | SwiftUI `HStack`/`ScrollView`; `ShortcutRegistry.documentation` (grouping by id prefix and folding, computed) | the grouping: feature prefix, registration order kept, an unbound action left out; the folding: digits → `N`, arrows → `←→↑↓`, a different modifier set or no shared title is not folded | S | 🟢 (2026-08-28) | |

## Definition of done

- The six entries behave as R35 says, checked by hand in the running app.
- No new type, no `…Manager`; the view only maps entries to `layout.closeTabs`.
- The home screen shows the same shortcuts as `docs/shortcuts.md` for the bound ids (checked by eye), and reflects a `config.shortcuts` override.
