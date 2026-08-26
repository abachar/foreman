# AGENTS.md

Wraith is a native macOS app written in Swift 6, developed entirely by AI agents (Claude Code, Antigravity, OpenCode…). This file is what every agent reads first. It is short on purpose.

## Read before writing code

1. `docs/architecture.md` — how the app is assembled, which libraries are used and how.
2. `docs/coding-rules.md` — code conventions.
3. `docs/specs/<domain>/` — what to build (`00-study.md`), what was decided (`decisions.md`), what is still open (`questions.md`).
4. `docs/backlog/<milestone>.md` — the task you are implementing: rules covered, library/native component to use, tests expected. Update its status in your PR.

No code for a domain without its `00-study.md`. A behaviour change updates the spec in the same commit.

## Non-negotiable: do not reinvent, do not over-engineer

The failure mode we guard against is an agent rewriting what a library or Apple already provides, and wrapping everything in layers "just in case". Concretely:

- **Before writing any service, parser, manager, or component**: check whether a retained library (`docs/architecture.md` → *Dépendances retenues*) or an AppKit/SwiftUI/Foundation component does it. State the answer explicitly in your reply: *"using X because…"* or *"nothing exists, writing Y in ~N lines"*.
- **Use a library the way its documentation says.** Read the docs (`find-docs` / the package README), do not code from memory of what the library "probably" exposes. Do not wrap a library behind your own protocol.
- **A protocol exists only when two implementations exist in the same commit.** No `…Service` protocol with one `…Impl`. No `Fake…` for tests unless a plain value or closure cannot do the job.
- **No abstraction for a hypothetical future.** One user, no third-party plugins, no backward compatibility. If two features need the same thing, put it in a shared folder and call it directly.
- **When in doubt between two solutions, take the shorter one.** A component that does 90 % of the need is used; the need is adapted, not the component rewritten.
- **Any new type over ~200 lines, any new `…Manager`/`…Service`, any new dependency**: one sentence of justification in the commit body.

## Working rules

- Small commits, one feature at a time. A commit builds and passes tests (`xcodebuild test -scheme Wraith`), passes `swift format lint --strict --recursive Wraith WraithTests`.
- Conventional commits in English (`feat(git): …`), body says *why* and cites the spec.
- Never commit secrets, `.build/`, `.DS_Store`, `.wraith/state.json`.
- Git identity for commits: `a.bachar@hotmail.fr`.
- Never read or list private keys under `~/.ssh`.
- Use absolute paths in shell commands (the user's shell rewrites relative `cd`).
- The project requires Xcode 27 (project format 110). If `xcodebuild -version` reports an older Xcode, prefix commands with `DEVELOPER_DIR=<path to Xcode 27>/Contents/Developer`.
- Do not touch specs or docs unless the task is about them; when you do, keep rule numbers (`R1`, `R2`…) stable and date decisions.

## Before opening a PR — self-review with one question

*What in this diff could not exist?* List every protocol with one implementation, every type that duplicates a library or platform feature, every abstraction with a single caller. Remove them, then open the PR.
