# design — Mockup prompt (Nano Banana / Gemini image)

> A **standalone** prompt: it stands on its own, it needs neither this spec nor the repository. Paste it as is into Nano Banana (Gemini image). The resulting image goes here under the name `mockup.png` and is cited in task 8.1 of [`../../backlog/m8-design.md`](../../backlog/m8-design.md).
>
> `mockup.png` **does not exist yet**: the environment in which this spec was written had no image generation tool. Only the prompt is delivered.

---

Generate a **flat, sharp interface screenshot** of a macOS development application called **Wraith**. Size **1600 × 1000 pixels**, 16:10 ratio, pixel-sharp, no perspective, no reflection, no desktop photo behind it, no MacBook mockup: the image is the window itself, filling the whole frame.

## Visual style

A **dark** theme, inspired by the "Islands" style of the IntelliJ IDEA IDE in its Dark theme. Mandatory rules:

- Window ground: a **flat, uniform dark fill**, a very dark blue-grey (around `#1B1D21`). No gradient, no texture, no noise.
- The working zones are **islands**: rectangles with **rounded corners** (radius about 8 px) laid on that ground, in a slightly lighter shade (around `#242628`). Between two islands, and between an island and the window edge, a **regular 8 px gutter** lets the ground show. **No separator line** between the islands: the space is what separates them.
- **No transparency, no blur, no glass effect, no translucent material.** Every surface is opaque.
- Flat bars: no shadow, no gradient, no relief, no pill-shaped button.
- **A single accent color** in the whole image: a clean, sober blue (around `#4C8DF6`). It is used only to mark focus and selection. The rest of the interface is grey.
- Text: a system sans-serif for the interface, a **monospaced font** for the code and the terminal. Primary text light grey (`#D8DADD`), secondary text medium grey (`#8A8F98`).
- Small colored status dots only where indicated: green, orange, red, blue, as 6 px dots.

## Exact layout

From top to bottom, the window contains four bands:

**1. Title bar and toolbar** (a single thin band, about 44 px tall, opaque background, no text title)

- At the far left: the three **macOS buttons** in red, yellow and green, in their usual place.
- Then, on the left: four **agent buttons**, flat, borderless, evenly spaced, each a small monochrome icon with no visible tooltip — just the icons: `Claude`, `OpenCode`, `Pi`, `Antigravity`. The first button carries a **green dot** at the bottom right of its icon (the agent is running).
- On the right side of the bar: a **`▶ Run`** button — a "play" triangle followed by the word *Run*, flat, discreet, with a small menu chevron and a **blue dot** in a corner (a command is running).
- Nothing else in this bar: no search field, no title, no tabs.

**2. The body of the window**, taking all the remaining space except the bottom band. It is made of three islands side by side:

- **Left island — Explorer**, about 260 px wide. At the top, a thin bar with the word **Explorer** in grey and two small icons on the right. Below, a **file tree** on the island's background: folders `backend`, `frontend`, `docs`, `.github`, and files `README.md`, `package.json`, `Dockerfile`, `UserController.java`. Two folders are expanded with their children indented, with disclosure chevrons. One file is **selected**: its whole row carries the blue accent as a background, with light text on top. Two entries (`node_modules`, `target`) are in a noticeably darker grey than the others (they are ignored).
- **Center island — Editor**, the widest one. At the top, a **flat tab bar**: four rectangular tabs, with no rounded corners and no tab shape — `UserController.java`, `README.md`, `Claude`, `backend:test`. The active tab (`UserController.java`) has the island's background and a **2 px blue rule along its top edge**; the others sit on the bar's background, with grey text. The `README.md` tab carries a small dot after its name (unsaved); the `Claude` tab carries a **green dot**; the `backend:test` tab carries a **blue dot**. Below the bar, a very thin separator line, then **highlighted Java code** in a monospaced font: a **line-number gutter** in dark grey on the left, about thirty lines of a `UserController` class with annotations, methods, strings and comments soberly colored (purple for keywords, orange for numbers, green-grey for comments, soft red for strings), a thin text cursor, and one line highlighted in a barely lighter grey.
- **Right island — Panel**, about 300 px wide. At the top, a thin bar with the word **Schema**. Below, a database tree: `public` expanded, then `Tables` expanded, then `users`, `orders`, `products`, `invoices`, each with a small table icon; `users` is expanded and shows four columns with their type on the right in grey (`id  bigint`, `email  varchar(255)`, `created_at  timestamptz`, `is_active  boolean`).

**3. Bottom island — Terminal**, across the full width below the three islands above, about 240 px tall, separated from them by the same 8 px gutter.

- At the top, a thin bar with two flat tabs: `Claude` (active, blue rule, green dot) and `backend:test` (blue dot).
- Below, **terminal content in a monospaced font** on **exactly the same background** as the island containing it — no darker or lighter rectangle inside the block. The content shows an agent session in progress: a few lines of output, a simple ASCII box, a progress line, and a blinking block cursor at the bottom. Sober terminal colors, in the same family as the rest.

**4. The command palette, open, floating above everything**

- A panel **horizontally centred**, anchored about 60 px below the toolbar, about 620 px wide and 380 px tall.
- Rounded corners (the same 8 px radius), an **opaque** island background, and **a soft drop shadow** — it is the only element in the image that carries a shadow.
- At the top, an **input field** on a slightly darker background than the panel, containing the text `usrctrl` with a cursor.
- Below, a **result list**: six rows. Each row has a title in light text and a path in smaller grey to its right or beneath it — `UserController.java` / `backend/src/main/java/…`, `UserControllerTest.java`, `UserService.java`, `user-controller.ts`, `users.sql`, `UserRepository.java`. Within the titles, the letters matching what was typed (`u`, `s`, `r`, `c`, `t`, `r`, `l`) are in **bolder, lighter** type, the rest normal.
- The **first row is selected**: a muted blue accent background, slightly rounded corners, light text on top.
- At the bottom of the panel, a very discreet help line in grey: `↑↓ navigate · ⏎ open · ⌘⏎ new group · esc close`.

## Do not

- No macOS menu bar at the top of the image (the window alone).
- No vertical icon sidebar in the VS Code style.
- No status bar at the bottom of the window.
- No logo, no mascot, no ghost, no illustration.
- No unreadable placeholder text: the code, the file names and the terminal lines must be plausible, readable words.
- No bright colors other than the blue accent and the four status dots.
- No translucency, no background blur, no gradient, no reflection, no rounded corners on the tabs.
