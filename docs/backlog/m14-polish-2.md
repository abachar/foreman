# M14 — Polish, second round

M14 = **small requests of the author on 2026-08-29**, each a spec amendment with its decision: reading markdown, the toolbar's vertical rhythm, the title area at first launch. No new folder, no dependency.

Domains: [`editor`](../specs/editor/) (R14), [`design`](../specs/design/) (R14, R21).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 14.1 | **Markdown opens in preview**: `EditorTab` defaults a new markdown tab to `preview`; a restored tab keeps its mode; `cmd+shift+v` unchanged | editor R14 (amended) | — | existing `EditorTabTests` (mode persisted) | S | 🟢 (2026-08-29) | |
| 14.2 | **`toolbarGap` token** (2 pt) for the top edge of the islands instead of `gutter`: the compact toolbar keeps ~5 pt under its buttons, the same gutter read as buttons off-centre; overridable through `theme.toolbarGap` | design R21, R11 | SwiftUI `EdgeInsets` | `ThemeTokensTests` (range, override) | S | 🟢 (2026-08-29; measured 7 pt / 7 pt after) | |
| 14.3 | **Title area at first launch**: the ground, `titlebarAppearsTransparent` and the separator re-asserted on every layout pass and by KVO when the bridge flips the property, not only on the next SwiftUI update | design R14 | KVO on `NSWindow` | — (checked by a capture right after launch) | S | 🟢 (2026-08-29) | |

## Definition of done

- A README opens rendered; `cmd+shift+v` shows the source; reopening the workspace brings the tab back in the mode it had.
- The toolbar buttons sit at the same distance from the top and from the islands (with `toolbarGap` 2, or 0 as the author uses).
- Launching on a workspace shows one uniform ground above the islands, before any click.
