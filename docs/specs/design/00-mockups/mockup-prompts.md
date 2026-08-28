# design — Mockup prompts, one per scene (Nano Banana / Gemini image)

> The first image, [`00-mockup.jpeg`](00-mockup.jpeg) (2026-08-27, from [`mockup-prompt.md`](mockup-prompt.md)), validated the style but showed one imagined layout. The author found the gap with the real app too large to read the tokens off a single picture, so this file gives **one prompt per scene the app actually has**. Every prompt is standalone: paste the **style block** first, then **one scene**, into Nano Banana. Keep the same seed / "same style as the previous image" when the tool allows it, so the eight images agree.
>
> Toolbar layout fixed by the author on 2026-08-27 (it differs from the first image): far left `▶ Run`, then a button group toggling the **Database**, **Git**, **History** panels; centre the four **agents**; far right a button toggling the **Explorer**. A pressed toggle carries a thin accent outline.

---

## Style block (paste before every scene)

Generate a **flat, sharp interface screenshot** of a macOS development application called **Foreman**. Size **1600 × 1000 pixels**, 16:10, pixel-sharp, no perspective, no reflection, no desktop behind it, no MacBook frame: the window itself fills the whole frame. No macOS menu bar, no status bar, no logo, no illustration, no VS Code-style vertical icon strip.

Visual style, mandatory — the "Islands" style of IntelliJ IDEA's Dark theme:

- Window ground: a **flat uniform** very dark blue-grey, `#1E1F22`. No gradient, no texture.
- Working zones are **islands**: rectangles with **8 px rounded corners** in `#2B2D30`, laid on the ground, separated from each other and from the window edge by a **constant 8 px gutter** where the ground shows. **No line** between islands; inside an island a thin `#393B40` separator is allowed under a bar.
- **No transparency, no blur, no glass, no translucent material, no shadow** (one exception: the floating command palette).
- Bars (toolbar, tab bars, panel headers) are **flat and opaque**, 36 px tall, no gradient, no border, no pill buttons.
- **One accent colour** only: blue `#3574F0`, used solely for focus and selection. Everything else is grey. Small 6 px status dots may be green `#5FB865`, orange `#E0A63B`, red `#E5534B` or blue `#3574F0`, only where a scene says so.
- Text: a system sans-serif for the interface, a **monospaced** font for code and terminals. Primary text `#DFE1E5`, secondary `#9DA0A8`, disabled `#6F737A`. Input fields and the highlighted current line use a sunken `#1E1F22`.
- **Tabs are flat rectangles**, no rounded corners, no tab shape: the active tab has the island's background `#2B2D30` and primary text, inactive tabs sit on the bar in secondary text; a close `×` appears only on the tab under the mouse.
- All file names, code, SQL, git output and terminal lines must be **plausible, readable English words** — no gibberish.

**Toolbar** (the same in every scene, one 36 px opaque band on the ground colour, no text title): far left the three macOS traffic lights; then a flat **`▶ Run`** button with a small chevron; then a **group of three flat toggle buttons** with monochrome icons — a database cylinder, a git branch, a clock (history); centred in the bar, **four flat agent buttons** with monochrome icons and their names `Claude`, `OpenCode`, `Pi`, `Antigravity`; far right a single toggle button with a folder-tree icon (the explorer). A toggle whose panel is visible has a **thin 1 px blue outline**. A running agent carries a green dot at the bottom right of its icon.

---

## Scene 1 — The everyday window

Body: three islands side by side, no bottom island. The `Explorer` and `Database` toggles are outlined; the `Claude` button has a green dot.

- **Left island, 260 px — Explorer.** Header bar with the word `Explorer` and, on the right, four small monochrome icons (new file, new folder, sort, collapse). Below, a file tree: folders `backend`, `frontend`, `docs`, `.github`; files `README.md`, `package.json`, `Dockerfile`, `UserController.java`. `backend` is expanded two levels deep (`src`, `main`, `java`). One row is **selected**: full-width blue background, light text. `node_modules` and `target` are in disabled grey. A small orange `M` after `package.json` and a green `A` after a new file (git status).
- **Centre island — Editor.** Tab bar with `UserController.java` (active), `README.md ●` (an unsaved dot), `Claude` (green dot), `backend:test` (blue dot). Under the bar a thin separator, then a **line-number gutter** in secondary grey and ~30 lines of highlighted Java (keywords soft purple, strings soft red, comments green-grey, numbers orange), the **current line** on the sunken shade, a thin text cursor.
- **Right island, 300 px — Schema.** Header `Schema` with a refresh icon. Tree: `public` › `Tables` › `users`, `orders`, `products`, `invoices`; `users` expanded with `id bigint`, `email varchar(255)`, `created_at timestamptz`, `is_active boolean`, types in secondary grey.

## Scene 2 — The command palette

Exactly scene 1, with the **palette open** above everything: centred horizontally, 60 px under the toolbar, 620 × 380 px, 8 px radius, opaque `#2B2D30`, **a soft drop shadow** (the only shadow). Top: an input field on the sunken shade with `usrctrl` and a cursor. Six rows: `UserController.java` — `backend/src/main/java/app/users`, `UserControllerTest.java`, `UserService.java`, `user-controller.ts`, `users.sql`, `UserRepository.java`; within each title the matched letters are bolder and lighter. The first row is selected: blue background, light text. Bottom: a discreet help line `↑↓ navigate · ⏎ open · ⌘⏎ new group · esc close`. Behind it the window is dimmed by nothing — no blur, no veil.

## Scene 3 — Two groups, the active one carries the accent

Only the `Explorer` toggle is outlined; no right island. The centre island is **split vertically into two tab groups** separated by an 8 px gutter of the ground colour, each its own island.

- **Left group**: tabs `OrderService.kt` (active), `application.yaml ●`; Kotlin code with the gutter and the current line.
- **Right group**: tabs `Claude` (active, green dot), `backend:test` (blue dot); an **agent terminal** in monospace on **exactly the island's background** — no darker rectangle — showing a Claude Code session: a prompt box drawn in box-drawing characters, a short assistant answer, a tool line `⏺ Read(OrderService.kt)`, a progress line and a block cursor. This group is the **active** one: a **1 px blue border** all around its island, the only place the accent appears.
- **Bottom island, 220 px — Search.** Header `Search` and a field on the sunken shade containing `OrderStatus`; below, results grouped by file (`OrderService.kt`, `OrderRepository.kt`, `orders.sql`) with the matching word in bolder text and line numbers in secondary grey; a footer line `27 matches in 3 files`.

## Scene 4 — Git

Toggles `Explorer` and `Git` outlined. Left: the Explorer as in scene 1. Right island, 320 px — **Changes**: header `Changes` with a menu icon; two sections `Staged (2)` and `Unstaged (5)`, rows with a status letter in colour (`M` orange, `A` green, `D` red, `?` secondary) then the path; below, a commit message field on the sunken shade with `feat(orders): retry on timeout` and a flat `Commit` button; a `Push` button with a blue dot. Centre island: tabs `OrderService.kt` and `OrderService.kt (diff)` (active); a **side-by-side diff**, two monospace columns, removed lines on a very dark red tint, added lines on a very dark green tint, line numbers on both sides, a hunk header `@@ -42,7 +42,9 @@` in secondary grey.

## Scene 5 — Postgres query

Toggles `Explorer` and `Database` outlined. Right island: the Schema as in scene 1. Centre island: tabs `users.sql`, `Query 1` (active). The tab shows, top half, a monospaced **SQL editor** (`select u.id, u.email, count(o.id) as orders from users u join orders o on o.user_id = u.id where u.is_active group by 1, 2 order by 3 desc limit 20;`) with keywords in soft purple; a thin bar with `▶ Run  ⌘⏎` and `localhost · ccoe_portal` in secondary grey; bottom half, a **results grid** with header row `id`, `email`, `orders` on the raised shade, ten rows of plausible data in monospace, zebra-free, a footer `20 rows · 38 ms`.

## Scene 6 — A run tab and a failed run

Only `Explorer` outlined; the `▶ Run` button has a **red dot**. Centre island: tabs `README.md`, `backend:test` (active, **red dot**). A terminal on the island's background showing a Maven test run ending with `Tests run: 48, Failures: 1` and `BUILD FAILURE` in the terminal's red, a `[Process exited with code 1]` line in secondary grey, then a thin bar at the bottom of the tab with two flat buttons `Rerun ⌘R` and `Close`.

## Scene 7 — The home screen

Only `Explorer` outlined. Left: the Explorer. Centre island **without tabs**: an empty group showing the home screen, everything centred on the island's background — the folder name `foreman` in title size; a row of four flat agent buttons; a list `Open file ⌘P`, `Run command ⌘R`, `Explorer ⌘⇧E`, `Git ⌘⇧G`, `History ⌘⇧H`, `Database ⌘⇧B`, `Split ⌘D` with the shortcuts in secondary grey; below, `Recent` with five file paths in secondary grey. No illustration, no logo.

## Scene 8 — Banners and the markdown preview

`Explorer` outlined. Centre split in two groups. Left group: tab `config.json ●` (active); at the top of the tab, under the tab bar, **two full-width banners** on the raised shade with a thin separator between them: `⟳ Modified on disk` with two flat buttons `Keep My Changes` and `Reload` on the right; then `Formatter (status 2): SyntaxError: Unexpected token at line 12` with a small icon on the left; below, JSON code. Right group: tab `README.md` (active) showing the **rendered markdown preview** on the island's background: a title, a paragraph, a bullet list, a fenced code block on the sunken shade in monospace, a link in the accent blue.

---

## What to read off the images (task 8.1)

The token values in the style block are the starting point (IntelliJ Dark's own), not the result: after the eight images are validated, confirm or adjust each of `windowBackground`, `surface`, `surfaceRaised`, `surfaceSunken`, `separator`, `textPrimary/Secondary/Disabled`, `accent`, the four status colours, `islandRadius` 8, `gutter` 8, `barHeight` 36 in `questions.md` → `decisions.md`.
