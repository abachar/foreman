# postgres — Study

## Goal

Feature `postgres` (folder `Postgres/`): explore a database's schema and run read queries without leaving the workspace. Right panel `postgres.schema` (`cmd+shift+b`), center tabs `postgres.query` (SQL editor + result grid, `cmd+shift+q` opens a new one — decision 2026-08-27). Client: PostgresNIO, lazy connection, secrets in the Keychain.

## User stories

- US1 — `cmd+shift+b`: I type the password once, and I see the schemas and their tables for the workspace's database.
- US2 — I expand a table: columns (type, null, default), indexes, constraints, foreign keys.
- US3 — `cmd+shift+q`, I write a query, `cmd+enter`: the first 500 rows in a grid, the execution time, the row count.
- US4 — I select two lines of SQL out of five: only the selection runs; without a selection, the whole buffer goes.
- US5 — *(deferred)* I export the result as CSV or JSON.
- US6 — I find my last queries again in the history.
- US7 — Double-clicking a table: `SELECT * FROM schema.table LIMIT 500` runs.

## Functional rules

### Connection

- R1 — Config (`config` R3, the `postgres` section): **a single object** = one connection per workspace; fields `host` (default `localhost`), `port` (5432), `database`, `user`, `sslmode` (`disable` | `prefer` | `require`, default `prefer`), `options` (`[String: String]`, e.g. `application_name`), `password` (optional, plaintext, local dev — `config` R11, decision 2026-08-27). A single source: the workspace's `.wraith/config.json` (`config` R4, config decision 2026-08-26: there is no global config).
- R2 — No picker: the header of both panels shows `user@host/database` and the state (R5). No `postgres` section configured → a panel with a message and a config example. Changing database = editing `config.json` (hot-reloaded, `config` R6: the previous connection is closed).
- R3 — Password: `config.password` when set (used as is, a refusal is shown and not retried); otherwise looked up in the Keychain (`config` R3), otherwise in `~/.pgpass` (standard format and permissions, only when the file is `0600`), otherwise asked for (an input sheet, with a *Save to the Keychain* option checked by default). A refused authentication invalidates the Keychain entry and asks again. The password is only held in memory for the lifetime of the connection.
- R4 — **Lazy** connection: established at the first action that needs it (expanding the schema, running a query), not when the panel is activated. One connection per window; closed when the schema panel is hidden and no query tab is running, or after 10 min of inactivity; reopened on demand. Connection timeout 10 s.
- R5 — The connection state is visible (a dot: disconnected / connecting / connected / error); an error is shown in a banner with the server's message (the feature's `PostgresError`, wrapping the NIO error).

### Schema

- R6 — Tree: schemas (excluding `pg_catalog`, `information_schema`, `pg_toast*`; a "system schemas" toggle) → **Tables**, **Views**, **Materialised views**, **Functions**, **Sequences**, **Types** (enums) → objects → for a table: **Columns** (name, formatted type, `NOT NULL`, default, PK), **Indexes** (name, definition), **Constraints** (PK, UNIQUE, CHECK, FK with its target), **Incoming foreign keys**. A view shows its columns and its definition.
- R7 — Loading **level by level** on expansion (laziness, `architecture.md`), through queries on `pg_catalog` (not `information_schema`, too slow), one query per level, bounded (10 s timeout). No automatic refresh: a *Refresh* button (per node or global).
- R8 — Actions on an object: *Copy the qualified name*, *SELECT * LIMIT 500* (double click or menu, run in the query panel), *Insert the name into the editor*, *View the DDL* (reconstructed client-side for tables/views/functions/indexes — best effort, read-only). Text search/filter over the loaded names.

### SQL editor and execution

- R9 — A `postgres.query` **center tab** (`cmd+shift+q` opens a new `Query N` tab, `cmd+w` closes it; decision 2026-08-27, replaces the bottom panel) is split vertically: the SQL editor on top (resizable), the results below. The editor is a monospaced text area of the feature's own, colored through the shared `Highlight/` folder (the `sql` grammar) — until that grammar resolves, by the feature's `SQLHighlighter` (decision 2026-08-27) —, with undo, indentation, and `cmd+/` for `--` comments. Each tab's content is persisted with the layout in `state.json` (`layout` R28).
- R10 — Execution (`cmd+enter`, a key of the tab): the **selection** if there is one, otherwise the **whole buffer**, sent as is as **a single statement** (no client-side splitting). PostgresNIO only exposes the extended protocol, which does not accept several statements in one message (decision 2026-08-27): a buffer holding several of them gets the server error `42601`, explained by a banner inviting the user to select the statement to run. No "statement under the cursor" (see the decisions).
- R11 — **Autocommit**, with a read-only session by default: the connection runs `SET default_transaction_read_only = on`; an *Allow writes* toggle (per session, not persisted, a red dot) lifts it. A `read-only transaction` error is explained by a banner pointing at the toggle.
- R12 — Every query is bounded: `statement_timeout` 30 s (adjustable with `statementTimeout` in the `postgres` section of `.wraith/config.json`). SQL **generated by Wraith** (R8) carries a `LIMIT 500`. **Free-form** SQL is read as a **stream** (rows consumed as they come, never all in memory) and stops at **50,000 rows**: the query is then cancelled (R13) and the grid shows a "result truncated at 50,000 rows, add a `LIMIT`" warning. The grid shows the rows in pages of 500 as they arrive. No cursor/portal.
- R13 — Cancellation: the *Stop* button / `cmd+.` cancels the task **and** sends `SELECT pg_cancel_backend(<pid>)` over a second short-lived connection (the pid is read at connection time by `SELECT pg_backend_pid()`), then closes the connection if the server does not answer within 5 s. `Task.cancel` alone only discards the rows client-side — PostgresNIO does not expose the protocol's cancel request (decision 2026-08-27).
- R14 — One execution at a time per window; `cmd+enter` during an execution is refused (a beep) and not queued.
- R15 — Parameters: no bound parameters in the free-form editor (it is SQL as is, like `psql`). SQL **generated by Wraith** (R8, R7, R12), on the other hand, quotes identifiers (`quote_ident` client-side) and binds its values (security, `architecture.md`).

### Results

- R16 — A read-only grid: headers (name, PG type), **client-side** sorting per column over the loaded page, adjustable column widths, cell/row selection, `cmd+c` copies as TSV (a cell, rows, or everything). Values: `NULL` visually distinguished, `bytea` as truncated hex, `json/jsonb` pretty-printed on a double click (a popover), dates in ISO 8601, arrays as `{…}` text.
- R17 — Status bar: `N rows (page 1/…) · 42 ms · user@database`. A statement with no result set (`UPDATE`, `CREATE`) shows `OK` (the row count is not exposed by PostgresNIO's async API, decision 2026-08-27). One execution = one statement (R10), so a single result is shown.
- R18 — *(deferred, decision 2026-08-27: not in v1)* Export: *CSV* (RFC 4180, headers, `NULL` empty) and *JSON* (an array of objects, native types where possible) of the **loaded** result or, as an option, of the whole query re-run and streamed to the file (capped at 1,000,000 rows). Destination through `NSSavePanel`.
- R19 — An execution error: a banner with the message, the `SQLSTATE`, and the position → the cursor is placed on the error in the editor.

### History

- R20 — Every query run (text, `user@host/database`, date, duration, row count / error) is appended to `.wraith/postgres-history.json` (max 500 entries, FIFO, never versioned: recommended in `.gitignore` alongside `state.json`). A history sheet (the clock button of a query tab, or the `postgres.history` action — no default shortcut, `cmd+opt+h` is macOS *Hide Others*, decision 2026-08-27): search, click → reload it into the editor, *Pin* (kept out of the FIFO). Nothing from the result is persisted.

## Edge cases

- Server unreachable: an error in < 10 s, no automatic retry; the schema already loaded stays visible (greyed out).
- Connection dropped mid-query: an error, reconnection on the next action.
- A database with thousands of tables: level-by-level loading + a filter; a level over 5,000 objects is truncated with a button.
- A very wide column (1 MB of text): the cell is truncated at 1,000 characters, the full content on a double click.
- Unknown types/extensions (PostGIS, etc.): shown as `<type> \x…` (PostgresNIO asks for the binary format on every column, decision 2026-08-27); cast to `::text` in the query to read them.
- `~/.pgpass` with wrong permissions: ignored with a warning (`libpq`'s behaviour).
- Two windows on the same database: two separate, independent connections.
- A result containing `\t`/`\n`: the TSV copy escapes them, the CSV quotes them.

## Out of scope for v1

- Editing data in the grid, generating `UPDATE`/`INSERT`.
- Explicit transactions in the UI (`BEGIN`/`COMMIT`/`ROLLBACK` can still be typed, but with no state handling).
- SQL autocompletion.
- ER diagrams, visual `EXPLAIN`, statistics, monitoring, role management.
- SSH tunnels, connecting through `DATABASE_URL`, other database engines.
- Modifying the schema through the UI.

## Technical options

- **Client**: PostgresNIO (SPM, pinned `.upToNextMinor`) imported into `Postgres/`, one `PostgresConnection` per window (not the library's `PostgresClient` pool, which needs a live `run()` task), behind a concrete `PostgresClient` type belonging to the feature (an `actor`: `connect`, `query(sql) -> AsyncThrowingStream<QueryEvent>`, `close`). No protocol: a single implementation (`architecture.md` P1). Rows are converted into `QueryValue` (`null`, `text`, `int`, `double`, `bool`, `date`, `json`, `bytes`, `raw(String)`) for the grid and the export; `QueryResult { columns: [ColumnInfo], rows: [[QueryValue]] }`.
- **Execution and bounds**: `PostgresConnection.query(_:logger:)` with `PostgresQuery(unsafeSQL:)` for the editor's buffer — the extended protocol, one statement per execution (R10); SQL generated by Wraith goes through the same API with bound parameters and a `LIMIT 500`. `PostgresRowSequence` (an `AsyncSequence` with back-pressure) feeds the grid; at 50,000 rows the query is cancelled (R13). No portal, no SQL tokenizer.
- **Cancellation**: `Task.cancel` (which discards the rows client-side) plus `pg_cancel_backend` over a second connection, the only public way to stop the query on the server side (R13).
- **Secrets**: `SecretStore` (the `Workspace/` folder) with the key `wraith.postgres.<host>:<port>/<database>/<user>`; an `InMemorySecretStore` double in the tests (justified: the Keychain cannot be tested hermetically).
- **Tests**: value formatting and CSV/JSON export (R16, R18), decoding the `postgres` section (R1, R12: defaults, bounds, unknown `sslmode`), reading `.pgpass` (R3), the `pg_catalog` queries and `quote_ident` (R7, R15), the history's FIFO/pinning (R20). The panels' logic is tested over hand-built `QueryResult` values, without a `PostgresClient` double.

## Decisions

See [decisions.md](decisions.md).
