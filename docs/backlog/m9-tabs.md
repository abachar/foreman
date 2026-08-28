# M9 — Tab menu

M9 = **closing several tabs at once**: a right-click on a tab of the center bar offers the IntelliJ closing actions. An extension of the `layout` domain (rule R35, decision 2026-08-28), no new domain, no new folder.

Domain covered: [`layout`](../specs/layout/).

The **Library / native** column is mandatory (`AGENTS.md`).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 9.1 | **Tab context menu**: *Close*, *Close Other Tabs*, *Close All Tabs*, *Close Unmodified Tabs*, *Close Tabs to the Left*, *Close Tabs to the Right* on every tab of the bar; entries with nothing to close disabled; the tabs close one by one through the existing `closeTab` (R15 confirmations, R10 group collapse) | layout R35, R15, R10 | SwiftUI `.contextMenu` (native `NSMenu`); `TabGroup.tabs(toClose:around:)` a pure function | the selection for each of the five multi-tab entries (pivot, dirty tabs, edges); the manager closes in bar order and stops at a refusal | S | 🟢 (2026-08-28) | |

## Definition of done

- The six entries behave as R35 says, checked by hand in the running app.
- No new type, no `…Manager`; the view only maps entries to `layout.closeTabs`.
