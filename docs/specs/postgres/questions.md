# Open questions

- [x] Manual verification against a real server (M5 backlog, task 5.9), done 2026-08-27 by the author on **PostgreSQL 18.3** (aarch64, Alpine/musl, Docker, TLS off), databases `ccoe_portal` and `linstant_gourmand`. Every item passed:
  1. Password: `postgres.password` in `config.json` connects directly; without it the sheet asks once, saves to the Keychain, and is not asked again after a relaunch; a wrong password is refused and asked again.
  2. `~/.pgpass` at `0600` connects with nothing typed; at `0644` the file is ignored with the warning and the sheet asks.
  3. `sslmode` `require` against the TLS-less server fails in under 10 s with a clear error; `prefer` and `disable` connect.
  4. The whole schema of `ccoe_portal` expands (schemas, tables, views, materialized views, functions, sequences, types; columns, indexes, constraints, incoming foreign keys); the DDL of a table, a view and a function reads right.
  5. `generate_series(1, 1000000)`: pages arrive, the app stays responsive, the run stops at 50,000 with the warning, and `pg_stat_activity` no longer shows it active.
  6. `pg_sleep(60)` + `cmd+.`: "Cancelled", gone from `pg_stat_activity`.
  7. `statementTimeout: 2` cuts `pg_sleep(5)` with the server's `57014`.
  8. An `UPDATE` fails with `25006` and the hint while *Allow writes* is off; on, it goes through; the toggle does not survive the tab.
  9. Two statements give `42601` with the hint; selecting one runs it.
  10. `timestamptz`, `date`, `interval`, `inet`, `jsonb` (pretty-printed on a double click), `bytea`, `text[]`, `numeric`, `"char"`, `NULL` all render as expected.
  11. Server stopped: an error in under 10 s, the loaded tree stays; restarted: the next query reconnects.
  12. Two windows on the same folder: two connections.
  13. Changing `database` hot: headers and tree root follow, the old connection is closed.
  14. History: every run listed with duration and error, search, pin, reload into the editor.
  Not verified (no such server at hand): a TLS server for `require`/`prefer`, a database with several thousand tables, an extension type such as PostGIS (expected `<type> \x…`, decision 2026-08-27).
