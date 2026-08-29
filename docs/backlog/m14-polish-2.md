# M14 — Polish, second round

M14 = **small requests of the author on 2026-08-29**, each a spec amendment with its decision: reading markdown, the toolbar's vertical rhythm, the title area at first launch, the inverted ground, the config reference, the preview's reading size, the conditional features. No new folder, no dependency.

Domains: [`editor`](../specs/editor/) (R14), [`design`](../specs/design/) (R2, R6, R14, R21), [`layout`](../specs/layout/) (R36), [`git`](../specs/git/) (R1b), [`postgres`](../specs/postgres/) (R2), [`run`](../specs/run/) (R6b), [`config`](../specs/config/).

| # | Task | Rules | Library / native | Tests | Size | Status | PR |
|---|---|---|---|---|---|---|---|
| 14.1 | **Markdown opens in preview**: `EditorTab` defaults a new markdown tab to `preview`; a restored tab keeps its mode; `cmd+shift+v` unchanged | editor R14 (amended) | — | existing `EditorTabTests` (mode persisted) | S | 🟢 (2026-08-29) | |
| 14.2 | **`toolbarGap` token** (2 pt) for the top edge of the islands instead of `gutter`: the compact toolbar keeps ~5 pt under its buttons, the same gutter read as buttons off-centre; overridable through `theme.toolbarGap` | design R21, R11 | SwiftUI `EdgeInsets` | `ThemeTokensTests` (range, override) | S | 🟢 (2026-08-29; measured 7 pt / 7 pt after) | |
| 14.3 | **Title area at first launch**: the ground, `titlebarAppearsTransparent` and the separator re-asserted on every layout pass and by KVO when the bridge flips the property, not only on the next SwiftUI update | design R14 | KVO on `NSWindow` | — (checked by a capture right after launch) | S | 🟢 (2026-08-29) | |

| 14.4 | **Inverted ground**: the ground lighter than the islands, the five background tokens re-ordered (dark and light); the panel `List`s (Changes, Search, query history) hide their system background so the island's `surface` shows | design R2 (amended) | `scrollContentBackground(.hidden)` | `ThemeTokensTests` (contrast pairs, ladder order) | S | 🟢 (2026-08-29) | |
| 14.5 | **Config reference**: `docs/config.md` (every key, type, default, decoding file); the repo's `.foreman/config.json` untracked and ignored | config (locations) | — | — | S | 🟢 (2026-08-29) | |
| 14.6 | **Preview type scale**: `readingFontSize` token (16), headings × 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85, small × 0.875, code blocks and inline code in the code font × 0.85, 4 pt of leading | design R6 (amended), R11 | SwiftUI `lineSpacing`, `AttributedString` runs | `ThemeTokensTests` (override range) | S | 🟢 (2026-08-29) | |
| 14.7 | **Conditional features**: git panels only with a repo, Schema panel + query shortcuts only with a `postgres` section, ▶ Run + `cmd+r` only with a command; `Layout.unregister(panel:)`, `ShortcutRegistry.unregister`, late registration takes the restored slot | layout R36, git R1b, postgres R2, run R6b | — | `PanelManagerTests` (unregister, late restore), `ShortcutRegistryTests` (unregister) | M | 🟢 (2026-08-29) | |
## Definition of done

- A README opens rendered; `cmd+shift+v` shows the source; reopening the workspace brings the tab back in the mode it had.
- The toolbar buttons sit at the same distance from the top and from the islands (with `toolbarGap` 2, or 0 as the author uses).
- Launching on a workspace shows one uniform ground above the islands, before any click.
- A README's text reads at 16 while the chrome stays at 13.
- A workspace without repo, `postgres` section or command shows neither the Git / History / Database toggles nor ▶ Run, and their shortcuts are absent from the home screen.
- The ground reads lighter than every island; the Changes panel is the same fill as the Explorer.
