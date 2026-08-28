# Open questions — browser

- [ ] Downloads (`WKDownload`): refused in v1 (R7). If a dev flow needs them (an export button), the target would be `~/Downloads` with a banner naming the file.
- [ ] Find in page: `WKWebView.find(_:configuration:)` exists (macOS 13); a small field in the chrome on `cmd+f` is ~40 lines. Wait for the need.
- [ ] Should the `run` feature offer *Open in Browser* on a command whose output prints a `http://localhost:…` URL? Would need to read the terminal output (`terminal` R4 says the process's output is never parsed). Probably a bookmark is enough.
- [ ] Opening the markdown preview's external links inside Foreman instead of the system browser (`editor` R14): decide once the tab exists and is used.
