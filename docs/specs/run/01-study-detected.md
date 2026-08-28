# Study — detected commands

> Feature `run`, second study (2026-08-28): fill the `cmd+r` palette from the project's own manifests without a `commands` section. Rules R14–R16; decisions in [`decisions.md`](decisions.md).

## Goal

Most repos already declare their commands: `package.json` scripts, a Maven `pom.xml`, a `Package.swift`. Wraith reads them and proposes the matching commands; nothing runs on its own, and `config.commands` stays the source for anything custom.

## Functional rules

- R14 — **Detection** per repo (`run` R2's repos: `.` and `config.repos`, plus the folders of `git` R1 auto-detection), at the repo root only, read-only:
  - `package.json` → one command per `scripts` entry: `<pm> run <name>` with `<pm>` = `pnpm` if `pnpm-lock.yaml` exists, `yarn` if `yarn.lock`, `bun` if `bun.lockb`/`bun.lock`, `npm` otherwise;
  - `pom.xml` → `mvn test`, `mvn package`, `mvn verify`;
  - `Package.swift` → `swift build`, `swift test`;
  - `Makefile` → one command per top-level target (`^[a-zA-Z0-9_-]+:` at column 0, not `.PHONY`, not starting with `.`): `make <target>`.
  A detected command's id is `<repo>:<name>` (`run` R3; `<name>` = the script or target, or `mvn-test`, `swift-build`…), `cwd` = the repo, no `env`.
- R15 — **Precedence**: a `config.commands` entry with the same id wins (`config` R4 spirit); a detected command never overrides a declared one. Detected commands are listed after the declared ones in the ▶ Run menu (a *Detected* separator) and in the palette with the manifest as subtitle (`package.json`); recents still come first (`run` R5).
- R16 — **Refresh**: on `Workspace.configChanges` (`run` R4) and when a manifest at a repo root changes (`FSWatchService`, the same debounce as the explorer). A malformed manifest → the repo's detection is skipped, one `debug` log, no banner.

## Edge cases

- A script named like a reserved word (`test`, `start`): `npm run test` works for all of them; no `npm test` shortcut.
- `package.json` without `scripts`: nothing.
- A Makefile with pattern rules (`%.o:`) or variables in targets (`$(X):`): skipped by the regex.

## Out of scope

- Gradle, Cargo, Poetry, Taskfile, Justfile (add a reader when needed; each is ~10 lines).
- Running anything to discover commands (`npm run` without a name, `mvn help`): read-only only.
- Editing `config.commands` from the UI.

## Technical options

- `RunCatalog.detect(root:repos:)` — a pure function over the file system (`FileManager`, `JSONDecoder` for `package.json`, a regex for the Makefile), tested on temporary folders. `RunFeature` merges it with `parse` (R15) and re-registers the palette items. No new type beyond a `source` field on `RunCommand`.
