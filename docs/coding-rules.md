# Code conventions

> How Foreman's code is written, whichever agent or human writes it. The *what* is in [`specs/`](specs/), the *with what* and the *how it is assembled* in [`architecture.md`](architecture.md).

## Language

| Item | Language |
|---|---|
| Identifiers, comments, logs, UI text, commits, PRs | English |
| `docs/**` | English |

No accents and no non-ASCII characters in code identifiers and file names.

## Toolchain

- Swift 6, language mode 6, strict concurrency. Apple Silicon. Deployment target = **the latest stable version of macOS** (26 when the project was created); we move up when the author's machine moves up, never any conditional code for an earlier version.
- The Xcode project (`Foreman.xcodeproj`, format 110, created with Xcode 27 beta) is the source of truth for the build; SwiftPM is only used for dependencies. Settings frozen in the project: Swift 6, strict concurrency `complete`, warnings as errors, approachable concurrency + `MainActor` isolation by default, App Sandbox disabled.
- Warnings = errors. `swift format lint --strict --recursive Foreman ForemanTests` must pass (`.swift-format` at the root: 4 spaces, width 120).

## Files

- One file = one main type, named after it. Extensions in `<Type>+<Subject>.swift`.
- Order within a file: `import`, main type, extensions, private helper types.
- `import`: only what is used; sorted system → Apple → third-party → Foreman. No `@_exported import`, no `@testable` outside tests.
- No dead code: no "just in case" file, no commented-out block, no `#if` other than `#if DEBUG`.

## Naming

- `UpperCamelCase` for types, `lowerCamelCase` for everything else. Acronyms treated as words: `urlForFile`, `sqlGrammar`, `PtyHandle`.
- No invented abbreviation (`cfg`, `mgr`). Established ones: `cwd`, `pty`, `fs`, `url`, `id`, `sql`, `pg`.
- Reserved suffixes: `…Service` (injected capability), `…Manager` (owner of a state machine), `…Store` (persistence), `…View` (SwiftUI), `…Error` (typed error).
- No `get` prefix. Readable booleans: `isVisible`, `hasChanges`, `canClose`.
- One test = one behaviour, named after the behaviour: `hidesPanelWhenSameShortcutPressedTwice`.

## Declarations

- `let` by default. Value types by default; `class`/`actor` when identity or isolation is required. A `class` is `final` unless justified.
- `internal` by default, `private` as soon as possible. `public`/`open`: useless (a single target).
- No tuple with more than two components in a signature: a named `struct`.
- `switch` on a Foreman `enum`: no `default`. `default` allowed on a third-party `enum`.
- `guard` and early exit; no more than 3 levels of nesting.

## Comments

- They explain the *why*; the *what* is read in the code.
- `///` on non-trivial types and functions. `// MARK: -` allowed, ASCII banners not.
- `// TODO(<domain>): …` must cite a spec; without a reference it is not committed.
- An implemented functional rule is cited: `// layout R10: last group never closes`.

## Errors and logs

- One `enum … : Error` per feature, which may wrap the third-party error (`case underlying(Error)`). No thrown `String`, no hand-made `NSError`.
- `try!`, `as!`, force unwrap: forbidden outside tests and commented constant literals. `fatalError`: programming invariants only, never on external data.
- No silent `catch {}`: handle, propagate, or log with context.
- `os.Logger`, one per feature, `subsystem: "dev.crafters.foreman"`. `print` forbidden outside the CLI script. No logging in a hot loop.
- Never a secret, file content, full SQL or terminal output in a log. Paths as `privacy: .private`.

## Concurrency

- Views, observed models, layout managers: `@MainActor`. Disk IO, git, network, parsing: `actor` or task off the main actor. No blocking IO on the main actor.
- `Sendable` at isolation boundaries. `@unchecked Sendable`: only on a C handle wrapper, with the comment saying what serialises access.
- Every long-running task is retained and cancelled by its owner; long loops check for cancellation.
- No `DispatchSemaphore`/`NSLock` for business logic. No `Task { @MainActor in }` to hide an isolation error. No synchronous waiting on async. No `Task.detached` without justification.
- Streams are `AsyncStream`, not callbacks stored by the consumer. Debouncing happens at the producer.
- A child process's pipes are read and written through `PipeIO` (`DispatchIO`), never `FileHandle.bytes`: Foundation runs every `AsyncBytes` iteration on one shared serial queue, so two pipes read at once take turns and the quiet one blocks the busy one until the child wedges (verified 2026-08-30, audit M2).

## UI

- SwiftUI by default; AppKit through `NSViewRepresentable` when the native component is better (toolbar, split view, outline view, text view, terminal).
- State through `@Observable`. Unidirectional flow: the view reads the state and sends intents to the manager; it never mutates the state of another component.
- No business logic, IO or expensive sorting in a `body`.
- Stable identities in lists (persistent `Identifiable`, not an index or a recreated `UUID`).
- Colors, fonts, metrics: through `ThemeService`, never inline.
- A shortcut is declared to the `ShortcutRegistry`, never captured ad hoc in a view.
- Every data view handles empty / loading / error / content.

## Files and paths

- Paths as `URL`; `String` only at the boundary (display, `Process` arguments).
- Internal paths relative to the workspace root, absolute otherwise.
- Atomic state writing (temporary + `replaceItem`), off the main actor.
- JSON: `Codable`, explicit `CodingKeys` when the name differs, sorted keys, tolerant of unknown keys, strict on types.

## Tests

- Swift Testing (`@Test`, `#expect`).
- We test what can break: parsers, state machines, config precedence, split tree, serialisation. Not views, not libraries.
- Hermetic: no network, no server, no `$HOME`, disk only in a temporary directory created and cleaned up by the test.
- A double only exists if it makes a test possible; we do not introduce a protocol in production *for* a test when a closure or an injected value is enough.
- A fixed bug comes with its test. No disabled test committed.

## Git

- Branches `feat/<domain>-<subject>`, `fix/…`, `docs/…`, `chore/…`; `<domain>` = spec folder.
- Conventional commits `type(scope): subject`, imperative, ≤ 72 characters; the body says *why* and cites the spec.
- A commit builds and passes the tests. No "wip" and no history rewriting on a shared branch.
- Never committed: `xcuserdata/`, `DerivedData/`, `.build/`, `.DS_Store`, `.foreman/state.json`, secrets. `Package.resolved` (inside the `.xcodeproj`) is committed.
- A behaviour change updates the spec (rule, decision) in the same commit.

## Checklist before pushing

- [ ] Builds without warnings, tests green, lint clean.
- [ ] No `print`, `try!`, force unwrap, empty `catch {}`, `TODO` without a spec.
- [ ] No IO on the main actor, no orphan task, no unjustified `@unchecked Sendable`.
- [ ] No protocol, adapter or double without a second real implementation ([`architecture.md`](architecture.md)).
- [ ] Tests for what can break; specs up to date in the same commit.
