# Open questions

- [x] **Toolbar: a dressed `NSToolbar` or a SwiftUI view?** Settled 2026-08-27: **option A** (`decisions.md`). Both options and their costs are described in [00-study.md](00-study.md) (*Technical options*) and set side by side in [`../../backlog/m8-design.md`](../../backlog/m8-design.md). To be settled after the mockup (task 8.1), with the author: option B gives the exact look but takes Wraith out of `NSToolbar`, which `layout` R30 and `architecture.md` currently assert.
- [ ] **The exact values of the `dark` set** (R9): the tokens are not numbered yet. They come out of the mockup (8.1) and are frozen in 8.2; until then, no color is written into a spec.
- [ ] **Radius and gutter**: `islandRadius` and `gutter` in points. Proposal to confirm by eye: radius 8, gutter 8, bars at 30 pt (the current tab bar is already 30, `CenterView.swift`).
- [ ] **The toolbar's background**: should it be `surfaceRaised` (the bar is one more island, stuck to the top) or `windowBackground` (the bar floats on the ground, as in IntelliJ)? To be seen on the mockup.
- [ ] **Generated mockup**: the standalone Nano Banana prompt is in [mockup-prompt.md](mockup-prompt.md). The image `mockup.png` **could not be produced** in the environment where this spec was written (no image generation tool available); it is for the author to generate and to drop here under the name `mockup.png`.
