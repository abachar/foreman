# The markdown preview beside GitHub's

> M16 task 16.3 (2026-08-30). What Foreman's markdown preview (`editor` R14, `design` R6) does,
> construct by construct, next to what GitHub does — so the author decides what is adopted, and
> what is deliberately not. **This document changes no code.** What 16.4 takes from it is written
> in `design` R6 and in [`decisions.md`](decisions.md) at that point, not here.

## What was compared, and how

The reference document is [`01-markdown-reference/reference.md`](01-markdown-reference/reference.md):
every construct `editor` R14 claims to render, and nothing else. It is rendered on both sides at
the defaults, light theme:

- **Foreman** — `readingFontSize` 16, `editorFont` JetBrains Mono 13, the light token set
  (`ThemeService+Tokens.swift`). Values read from `MarkdownPreviewView.swift` and
  `ThemeService+Fonts.swift`.
- **GitHub** — `github-markdown-css` v5 (`cdn.jsdelivr.net/npm/github-markdown-css@5`, fetched
  2026-08-30, the milestone's one network access). Values read from the stylesheet itself, so
  they are the rule as it ships and not a measurement off a screenshot. `1rem` = 16 px, so `em`
  and `px` are the same unit as Foreman's points here.

GitHub's page adds one thing the stylesheet does not carry: the README column, ~1012 px wide,
which is where the maximum reading width comes from.

### The captures

In [`01-markdown-reference/`](01-markdown-reference/), both sides **in the dark theme** (the author's
system setting, which both renderers follow):

| | Top of the document | Quotes, code, tables |
|---|---|---|
| Foreman | [`foreman.png`](01-markdown-reference/foreman.png) | [`foreman-2.png`](01-markdown-reference/foreman-2.png) |
| GitHub | [`github.png`](01-markdown-reference/github.png) | [`github-2.png`](01-markdown-reference/github-2.png) |

The Foreman captures are the preview **as it was before 16.4** — this document is the record of the
gap, so they are not refreshed when the gap is closed.

The GitHub side is the reference document as HTML under **`github-markdown.css` itself**, in a
1012 px column — the stylesheet the task names, applied to the markup GitHub's pipeline produces
(`ol start`, `li.task-list-item` with a real checkbox, `pre > code.language-…`). It is not a
screenshot of github.com: nothing was published to do this. If the author wants a capture of the
real page, the document goes in a gist and the two files are replaced; no measurement in this
document would change, since all of them come from the stylesheet.

**The numbers below are the light sets** (the defaults both sides ship). Where a colour behaves
differently in dark, the row says so — the code block's ground is the one place it matters.

## Construct by construct

Every row is a fact from one of the two sources above. **Gap** says what a reader would notice;
*none* means the two agree closely enough that no one would see it.

### Type scale and leading

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Body font | system, 16 pt | system sans stack, 16 px | none |
| Body leading | `lineSpacing(4)` → ≈ 23 pt line (≈ 1.44) | `line-height: 1.5` → 24 px | none |
| h1 | 16 × 2 = **32**, weight `medium` (500) | **32**, weight 600, `line-height: 1.25` | **weight**: 500 vs 600 |
| h2 | 16 × 1.5 = **24**, `medium` | **24**, 600 | weight |
| h3 | 16 × 1.25 = **20**, `medium` | **20**, 600 | weight |
| h4 | 16 × 1 = **16**, `medium` | **16**, 600 | weight |
| h5 | 16 × 0.875 = **14**, `medium` | **14**, 600 | weight |
| h6 | 16 × 0.85 = 13.6 → **14**, `medium` | 13.6, 600, **`fgColor-muted`** | weight, and h6 is **grey** on GitHub |
| Heading leading | the body's `lineSpacing(4)` on a 32 pt h1 → very loose | `line-height: 1.25`, tightening as the size grows | **a wrapped h1 is visibly airier in Foreman** |

The scale itself matches GitHub's exactly, ratio for ratio — `design` R6 was written from it. The
two differences are the weight (Apple's `medium` against GitHub's `semibold`) and the leading,
which Foreman applies as a constant 4 pt at every size instead of a ratio.

### Space between blocks

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Between two blocks | `LazyVStack(spacing: 12)`, uniform | `margin-bottom: 16` on p, ul, ol, table, pre, blockquote | **12 vs 16** everywhere |
| Above a heading | 12 + `padding(.top, 8)` for h1–h2, + 4 for h3–h6 → **20 / 16** | `margin-top: 24` | **h1–h6 sit 4–8 px tighter** |
| Below a heading | 12 | `margin-bottom: 16` | 12 vs 16 |
| Between list items | `VStack(spacing: 4)` | `li + li { margin-top: .25em }` = 4 | none |
| A paragraph inside a list item | 4 | `li > p { margin-top: 16 }` | **4 vs 16** |
| Around a rule | 12 above and below | `margin: 24 0` | **12 vs 24** |

Foreman's page is uniformly tighter. One number — the `LazyVStack` spacing — drives almost all of
it.

### The rule under h1 and h2

| | Foreman | GitHub |
|---|---|---|
| h1 | nothing | `padding-bottom: .3em` then `border-bottom: 1px solid` `borderColor-muted` (`#d1d9e0b3`) |
| h2 | nothing | same |

**The most visible single gap.** GitHub's document reads as sections because of these two rules;
Foreman's reads as a run of paragraphs.

### Quotes

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Bar | `Rectangle` 3 pt, `.tertiary` | `border-left: .25em` = **4 px**, `borderColor-default` (`#d1d9e0`) | 3 vs 4, and the tint |
| Gap bar → text | `HStack(spacing: 10)` | `padding: 0 1em` = **16** | **10 vs 16** |
| Text colour | `.secondary` | `fgColor-muted` (`#59636e`) | none in effect |
| Nested quote | the same bar again, indented | the same | none |

### Lists

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Indent | `padding(.leading, 8)` + an 8 pt gap after the marker | `padding-left: 2em` = **32** | **16 vs 32** — Foreman's lists sit much closer to the margin |
| Bullet | `•` in `.secondary` | `list-style: disc`, the text colour | a Foreman bullet is grey, GitHub's is not |
| Nested bullet | `•` at every depth | disc → circle → square | **no depth marker in Foreman** |
| Ordered | `1.` `2.`, honours `start` | decimal, honours `start` | none |
| Nested ordered | decimal again | **lower-roman**, then lower-alpha | **no depth marker in Foreman** |
| Task list | SF Symbol `checkmark.square` / `square`, in the marker column, `.secondary` | a real `input[type=checkbox]`, pulled into the margin (`margin-left: -1.4em`), the item's bullet removed | shape and colour differ; Foreman keeps the marker column, GitHub hangs the box in the margin |

### Code

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Inline code, font | JetBrains Mono at 16 × 0.85 → **14** | the mono stack at **85 %** = 13.6 | none |
| Inline code, background | **none** | `bgColor-neutral-muted` (`#818b981f`, ~12 % grey) | **the run is invisible as code beyond the typeface** |
| Inline code, padding | none | `.2em .4em` | with no background, moot |
| Inline code, radius | none | 6 px | as above |
| Block, font | JetBrains Mono 14 | 85 % = 13.6 | none |
| Block, padding | **10** | **16** | 10 vs 16 |
| Block, background, light | `surfaceSunken` `#DDDFE4` on a `#F2F3F5` page — **a step down of ~21** | `#f6f8fa` on a `#ffffff` page — a step down of ~9 | **Foreman's slab is far heavier** |
| Block, background, dark | `#151618` on a `#1E1F22` page — **darker than the page** | `#151b23` on a `#0d1117` page — **lighter than the page** | **the two go in opposite directions**: GitHub lifts the block out of the page, Foreman sinks it in |
| Block, radius | 6 | 6 | none |
| Block, leading | the body's `lineSpacing(4)` | `line-height: 1.45` | none worth naming |
| Block, overflow | horizontal `ScrollView` | `overflow: auto` | none |
| Highlighting | tree-sitter through `Highlight/` when the language is known | GitHub's own | out of scope for a layout comparison |

### Tables

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Cell borders | **none** | `1px solid` `borderColor-default` on **every** cell | **the largest structural gap after the heading rules** |
| Header | bold, one `Divider` under it | `font-weight: 600`, and the cell borders | Foreman has no grid at all |
| Cell padding | `horizontalSpacing: 16`, `verticalSpacing: 6` | `padding: 6px 13px` | close in effect |
| Zebra rows | none | `tr:nth-child(2n)` → `bgColor-muted` | **no alternating rows in Foreman** |
| Overflow | `Grid`, no scroll of its own | `display: block; width: max-content; overflow: auto` | **a wide table stretches Foreman's layout instead of scrolling** |

### Rules, links, images, width

| | Foreman | GitHub | Gap |
|---|---|---|---|
| Horizontal rule | `Divider()` — 1 pt hairline | **4 px** (`height: .25em`) in `borderColor-default` | **a hairline against a bar** |
| Link colour | `tint` = `accent` `#3574F0` (light) | `fgColor-accent` `#0969da` | both blue; GitHub's is deeper |
| Link underline | none (SwiftUI's default) | none at rest, **underlined on hover** | Foreman has no hover state |
| Image | `scaledToFit`, capped at 800 pt | `max-width: 100%` | close; the cap is a Foreman invention |
| Maximum reading width | **none** — the text runs the whole tab, `padding(20)` | ~1012 px column | **on a wide window a Foreman line is unreadably long** |
| Page padding | 20 | the column's own margin | — |

## What the comparison says, in order

Read as "what a reader notices first", not as a decision — 16.4 decides.

1. **No rule under h1/h2.** The document loses its sections.
2. **No maximum reading width.** On a wide tab the body runs the full width; every other gap is
   cosmetic next to this one.
3. **No table grid, no zebra.** A table reads as loose columns rather than a table.
4. **Inline code has no background.** It is set in the code font and nothing else.
5. **The horizontal rule is a hairline** where GitHub draws a 4 px bar.
6. **Everything is tighter**: 12 pt between blocks against 16, 20/16 above a heading against 24,
   12 each side of a rule against 24, list indent 16 against 32.
7. **The code block's ground goes the wrong way in dark.** GitHub lifts a code block *out* of the
   page (lighter); Foreman sinks it *into* the page (darker), and in light its step is twice
   GitHub's. Seen in the captures, this is the difference the eye reads as "a slab" against "a
   panel".
8. **Headings are `medium` where GitHub is `semibold`**, and h6 is not greyed.
9. **Nested lists lose their depth marker** (disc/circle/square, decimal/roman/alpha).
10. **A wide table stretches the layout** instead of scrolling inside itself.

Where the two already agree, and where nothing should change: the **type scale** (32/24/20/16/14/13.6
from a 16 pt body), the **body leading**, the **inline and block code size** (85 %), the **code block
radius** (6), the **spacing between list items** (4), and the **link colour family**.

## What this document does not answer

- Whether Foreman *should* look like GitHub at all, or only borrow its structure (the rules, the
  grid, the reading width) and keep its own palette. That is 16.4, and `design` R6 is amended
  there.
- Dark mode: GitHub's dark tokens are listed in the stylesheet, but the comparison was made in
  light. The gaps above are structural and hold in both; the colour rows would need their own pass.
- Anything `editor` R14 does not render (footnotes, alerts, `<details>`, mermaid, emoji shortcodes,
  autolinked issue references). Out of scope, and not in the reference document.
