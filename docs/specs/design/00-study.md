# design — Study

## Goal

Give Foreman a **chosen** visual identity, instead of the system default. Today's fully native rendering — translucent materials (`.bar`), macOS 26's Liquid Glass, system chrome — is not what the author wants to look at eight hours a day. The target is IntelliJ's **"Islands"** style in the **Dark** theme: a flat dark ground, zones (editor, panels, terminal) laid on it like rounded-corner islands separated by gutters, a flat opaque toolbar, flat tabs, thin bars, **a single accent**, and **no transparency at all**.

A **transverse** domain: it ships no feature. It defines the visual tokens and says which surface carries which. The code lives in `Foreman/App/` (an extension of `ThemeService`) and in the existing views; there is no `Design/` folder and no second theme service.

## User stories

- US1 — I open Foreman: the window is a flat dark ground, the editor, the explorer and the terminal are distinct rounded blocks, and nothing lets the desktop or a window underneath show through.
- US2 — I change a color in `.foreman/config.json`: it applies without a restart, like the rest of the config.
- US3 — The terminal has exactly the same black as the island containing it: I do not see a lighter or darker rectangle inside the block.
- US4 — I look at a window with four tabs and three panels: I can tell at a glance which group is active, because it is the only thing carrying the accent.
- US5 — I read grey text on a dark ground for an hour without straining.

## Functional rules

### Visual principles

- R1 — **No transparency and no system material in the app's chrome.** No `.bar`, no `.regularMaterial`/`.ultraThinMaterial`, no `NSVisualEffectView`, no vibrancy, no Liquid Glass. Every surface is an opaque fill taken from a token. A shadow is only allowed for the palette, which floats above the window.
- R2 — **Islands.** The window's ground is a flat, uniform fill, **lighter than the islands** (amended 2026-08-29: the islands used to be lighter than the ground; inverting puts the darkest fill under the text, where contrast matters, and the gutter stays readable). The center (tab groups), each visible panel and the palette are rounded-corner rectangles laid on it, separated from the window's edge and from each other by a **constant gutter**. It is the window ground visible in the gutter that separates the zones: **no separator line** between two islands. Inside an island, a thin separator is allowed (tab bar ↔ content, panel header ↔ list).
- R3 — **A single accent.** One accent color, and only one, marks what has the focus or the selection: the active group's border (`layout` R17), the selected row of the palette and of the lists, the active tab, the focused control. The only other colors in the interface are the four state badges already defined (`ToolbarBadge.BadgeColor`: green, orange, red, blue) and the highlighting colors (`editor` R12).
- R4 — **Thin, flat bars.** The toolbar, the tab bar, panel headers and status lines have a fixed height, a flat opaque background, **no gradient, no shadow, no border** other than the internal separator allowed by R2.
- R5 — **Flat tabs.** A tab is a rectangle with no shape and no rounded corner: active = the island's background + a 2 pt accent rule on its **bottom** edge, as on the validated mockups (amended 2026-08-27), inactive = transparent over the bar with secondary-colored text. No close button appears on an inactive tab until the mouse is over it.
- R6 — **Typography.** Two families, not three: the **interface font** for the chrome — the system font by default, `theme.interfaceFont` in `config.json` otherwise, at `theme.interfaceFontSize` (13 by default; amended 2026-08-28) — and `ThemeService.editorFont` (the monospaced font from `terminal` R14, **JetBrains Mono 13** by default since 2026-08-28) for code, terminal, diffs and SQL. Three interface sizes only, derived from the body size (`small` = body − 2, `body`, `title` = body + 1) and two weights (`regular`, `medium`). The **markdown preview** has its own scale (2026-08-29): body = `theme.readingFontSize` (**16**) with 4 pt of leading, H1–H6 = × 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85 in `medium`, small = × 0.875, code (blocks and inline) = the code font at × 0.85.
- R7 — **Measured contrast.** Primary text against its background: a ratio ≥ 4.5:1; secondary text and icons: ≥ 3:1; the accent against its background: ≥ 3:1. The ratio is computed, not estimated, and the function that computes it is tested.

### Tokens

- R8 — **Every** color, every radius, every gutter and every bar height in the chrome comes from a token exposed by `ThemeService`. No view names a system color (`.controlBackgroundColor`, `.labelColor`, `Color.accentColor`), a material, or a literal value. This is already the rule (`coding-rules`, UI: "colors, fonts, metrics: through `ThemeService`, never inline"); it is broken in fifteen places today, listed in the M8 backlog.
- R9 — The tokens form four families, and nothing else:
  | Family | Tokens |
  |---|---|
  | Backgrounds | `windowBackground` (the ground under the islands), `surface` (an island's background), `surfaceRaised` (tab bar, panel header, toolbar buttons), `surfaceSunken` (an input field, the current line), `surfaceOverlay` (the palette; added 2026-08-27). `windowBackground` is the lightest fill, `surfaceSunken` the darkest, `surfaceRaised` sits between the ground and the island (2026-08-29; tested); a SwiftUI `List` inside an island hides its own background (`scrollContentBackground(.hidden)`) so the island's `surface` shows |
  | Text and rules | `textPrimary`, `textSecondary`, `textDisabled`, `separator`, `border` |
  | Accent and states | `accent`, `accentText` (text laid on the accent), `statusGreen`, `statusOrange`, `statusRed`, `statusBlue` |
  | Metrics | `islandRadius`, `gutter`, `toolbarGap`, `barHeight`, `rowHeight`, `contentInset` |
  | Syntax (2026-08-27) | one color per `HighlightRole` (editor R12), so the editor follows Foreman's theme and not the macOS appearance |
  | Type (2026-08-28) | `interfaceFontName` (`nil` = the system font), `interfaceFontSize` (10…24), `readingFontSize` (10…32, the preview; 2026-08-29) — R6 |
- R10 — Two token sets, `dark` and `light`, with an identical structure, chosen by the mode from `terminal` R14 (`light` / `dark` / `system`). **Only `dark` is designed and validated in v1**; `light` is derived mechanically and is not a goal (see out of scope). The 16-color ANSI palette from `terminal` R14 is now part of the token set and must agree with it (R13).
- R11 — Tokens can be overridden through the `theme` section of `.foreman/config.json`: `{ "theme": { "accent": "#4C8DF6", "islandRadius": 10, "interfaceFont": "Inter", "interfaceFontSize": 15 } }` (the font keys since 2026-08-28: a family name that is not installed falls back on the system font). Unknown key → a warning, ignored; malformed value (a color outside `#rgb`/`#rrggbb`, a negative or out-of-range metric) → a warning, the default value kept; the whole section is optional (`config` R2, R5) and hot-reloaded (`config` R6). No separate theme file (see out of scope).

### What stays native

- R12 — These components are **not replaced**, only dressed (background, colors, row height, separator style): `NSSplitViewController` / `NSSplitView` (the zones, `layout`), `NSOutlineView` (the explorer), `NSTextView` on TextKit 2 (editor, diff, SQL editor), the SwiftTerm surface, `NSAlert`, `NSMenu`, `NSSavePanel`, `NSTextFinder`, the native find bar. `architecture.md` P3 holds: we reimplement none of them for a question of appearance.
- R13 — The SwiftTerm surface gets `nativeBackgroundColor` = the `surface` token of the island containing it, so that there is no boundary inside the block (US3); its ANSI palette and its `caretColor`/`selectedTextBackgroundColor` come from the same tokens (`installColors`, `terminal` R14).

### What changes

- R14 — **Window**: an opaque background at the `windowBackground` token; the title bar is indistinguishable from the rest (`titlebarAppearsTransparent`), the traffic lights stay the system's and in their place. The window's text title is hidden: the folder name is already in the interface. **One band only** above the islands (amended 2026-08-27): the traffic lights sit in the toolbar itself, there is no separate title band — the mockups drew two and the author keeps one.
- R15 — **Toolbar**: an opaque `surfaceRaised` background, a fixed height (R4), flat buttons with no border and no fill at rest, a `surfaceSunken` fill on hover and press, badges (`layout` R31) rendered with the state tokens. Two technical routes (the options below), settled in the M8 backlog. **Layout** (author, 2026-08-27, amends `layout` R30): far left, after the traffic lights, one toggle for the Explorer panel; centred, the agent buttons with their own icons (`Assets.xcassets/agent-*`); far right, `▶ Run` then a group of three toggles for the Database, Git and History panels. A toggle whose panel is visible carries a 1 pt accent outline.
- R16 — **Tab bar** (`layout` R16): `surfaceRaised`, tabs following R5, the `isDirty` marker and the dot badge kept, a thin separator under the bar only.
- R17 — **Panels**: each visible panel is an island (R2) with a `surfaceRaised` header carrying its title and its menu; the existing error banners (explorer R19, config R7, `git`, `postgres`) take the matching state token instead of `.background(.bar)` and `.red`.
- R18 — **Palette** (`Palette/`): a floating island, `surface`, `islandRadius`, a drop shadow (the only exception to R1), an input field on `surfaceSunken`, the selected row on the accent, subtitles in `textSecondary`. No title bar, no material.
- R19 — **Home screen** (`layout` R33): the same tokens, shortcuts shown in `textSecondary`, no illustration and no gradient.
- R20 — **Zone separators**: `NSSplitView`'s dividers are painted with the `windowBackground` color at the `gutter` thickness, which produces R2's gutter without drawing a line.
- R21 — **Toolbar gap (2026-08-29)**: the islands sit `toolbarGap` points under the toolbar (default 2), not `gutter`: the compact toolbar already keeps ~5 pt under its buttons, and the same `gutter` there read as buttons sitting higher than centred. Left, right and bottom edges keep `gutter`. Overridable like every metric (R11).
- R21 — **Splits stay inside the centre island** (author, 2026-08-27): splitting a group never creates a sibling island next to the panels. The centre zone is one island; its groups are laid out inside it and separated by a **1 pt `separator` line only** — no inner radius, no inner gutter — so that the panels keep one neighbour and the split reads as a subdivision of the centre (author, 2026-08-27, precised the same day). Mockup `08.jpeg` shows the rejected rendering (two islands of the same rank as the Explorer).
- R22 — **Current line**: the editor, the SQL editor and the diff highlight the caret's line with `surfaceSunken` across the full width (author, 2026-08-27).
- R23 — **File icons**: the explorer, the tabs, quick open and the recent list show a per-type icon from the **Material Icon Theme** set (MIT, SVG; the author's copy is in `docs/specs/design/00-icons/`), chosen by extension or file name, with a neutral file icon as the fallback; folders keep a single folder icon. The set ships in `Assets.xcassets`, only the entries a mapping references are copied.

## Edge cases

- macOS appearance changed during a session: the views already pass it to `ThemeService.isDark(systemIsDark:)` (`terminal` R14); the token set switches and every surface repaints, including the open SwiftTerm surfaces.
- Very small window: the gutter and the radius stay constant; it is the islands that shrink, down to the minimums in `layout` R19.
- Full screen: the gutter remains on all four edges; that is intended, it is what makes the island.
- Hidden panel: its gutter disappears with it, and the neighbouring island expands; no empty band.
- "Reduce transparency" and "Increase contrast" (Accessibility): there is nothing translucent to reduce (R1); increasing contrast is not handled in v1 (out of scope).
- An overridden token that breaks R7's contrast: the warning is shown once, and the user's value is **still applied** — it is their window.
- Printing, screenshots, "invert colors" mode: nothing special, everything is opaque.

## Out of scope for v1

- **A designed light theme**: `light` exists mechanically (R10), but it is neither worked on nor validated.
- User theme files, shared themes, a theme picker in the interface: the config's `theme` section is enough (the same policy as everything else, `config`, out of scope: no graphical preferences editor).
- A custom icon set: SF Symbols and the SVGs already present stay (`IconImage`).
- Animations, transitions, hover effects other than a background change.
- Replacing the traffic lights or the title bar with home-made controls.
- An accent per panel, a color per repo, coloring tabs by kind.
- Supporting "Increase contrast" and the accessibility color settings.
- Redrawing the native components of R12.

## Technical options

### `ThemeService` extended, not a second service

`ThemeService` (`Foreman/App/ThemeService.swift`) already carries: the decoded `terminal` section (`Settings`), the font (`editorFont`), the mode (`isDark(systemIsDark:)`), the two ANSI palettes (`TerminalPalette`) and the highlighting role colors (`color(for: HighlightRole)`). R9's tokens are added to the same type: one `struct Tokens` per set, two static constants, and a decoding of the `theme` section modelled on `Settings.decode(from:)`. A separate `DesignSystem` would be a second owner of the same information, which `architecture.md` forbids (shared services, created once in `App`).

### The toolbar: two routes

This is the only real technical choice, because `NSToolbar` gives no control over its background.

**Option A — keep `NSToolbar` and dress it.** What AppKit really allows, with long-standing APIs:

- `NSWindow.titlebarAppearsTransparent = true`: the title area no longer paints its own background, so the window's background shows through.
- `NSWindow.backgroundColor`: the opaque fill, so the `windowBackground` or `surfaceRaised` token depending on the look we want.
- `NSWindow.titleVisibility = .hidden`: no more text title (R14).
- `NSWindow.styleMask` with `.fullSizeContentView`: the content goes under the title area, which lets us control the space above the islands.
- `NSWindow.toolbarStyle`: `.unified` (the current one), `.unifiedCompact` (a thinner bar, which is what R4 wants), `.expanded`, `.preference`, `.automatic`.
- `NSToolbarItem.isBordered = false` and a custom `view` per item: flat buttons drawn by us.

What option A does not give: `NSToolbar` exposes no background-color property, and the way macOS 26 paints its area (material, a separator under the bar when scrolling) is not contractual. The result is therefore "very close" and **must be checked on the machine**; it may change with a macOS update. Cost: low, a few lines in `WorkspaceToolbar.attach(to:)` and one `view` per item.

**Option B — remove `NSToolbar` and draw the bar.** `window.toolbar = nil`, `styleMask.insert(.fullSizeContentView)`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, and a SwiftUI view at the top of the content rendering the `ToolbarItemDescriptor`s the features already declare (`layout` R30). Full control over the background, the height and the hover states.

What option B costs: the traffic-light area stays at the top left, so the bar has to reserve a left inset (~78 pt, to be measured, and it changes in full screen); dragging the window by the bar has to be restored (`NSWindow.isMovableByWindowBackground`, or a view calling `performDrag(with:)`); item overflow, standard tooltips and `NSToolbar` customisation disappear — with no consequence here, `layout` R30 already forbids them. `layout` R30 and `architecture.md` (which both say "a native `NSToolbar` toolbar") would have to be amended and dated. Cost: medium, ~150 lines plus the full-screen cases.

Both options are put side by side, with their cost, in the M8 backlog's "To decide" section. Settled: option A (2026-08-27). The reference images are the eight mockups in [`00-mockups/`](00-mockups/) (an inspiration, not a pixel target: their second title band and their toolbar order are explicitly rejected, see R14, R15, R21).

### The rest

- **Island backgrounds**: the content views take their `surface` and a `clipShape(RoundedRectangle(cornerRadius: islandRadius))`; it is the zone container (`ZonesViewController`) that lays out the gutter, through the thickness and the color of `NSSplitView`'s dividers (`dividerStyle`, `NSSplitView.drawDivider(in:)` in a subclass if the color alone is not enough).
- **Contrast**: the WCAG computation (relative luminance, ratio) is a pure function of about fifteen lines, tested over known pairs; no library.
- **Tests**: decoding the `theme` section (absent, partial, unknown key, malformed color, out-of-range metric), parsing `#rgb`/`#rrggbb`, the contrast ratio of each pair required by R7 over the `dark` set, the coherence of the token set (every token defined in both sets). The rendering itself **is validated by eye**: each task in the backlog says what to look at.

## Decisions

See [decisions.md](decisions.md).

Comparisons: [`01-markdown-vs-github.md`](01-markdown-vs-github.md) (2026-08-30, M16 16.3) — the markdown preview (R6, `editor` R14) construct by construct next to GitHub's, with its reference document and captures in [`01-markdown-reference/`](01-markdown-reference/).
