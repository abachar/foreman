# Open questions — browser

- [ ] A persistent session as an opt-in (`"browser": { "persistent": true }`) if logging in at every launch gets tiresome: `WKWebsiteDataStore(forIdentifier:)` with the UUID in `state.json`, ~15 lines.
- [ ] Downloads (`WKDownload`): refused in v1 (R5). If a dev flow needs them, the target would be `~/Downloads` with a banner naming the file.
- [ ] Find in page (`WKWebView.find(_:configuration:)`, macOS 13): ~40 lines when needed.
- [ ] Opening the markdown preview's external links inside Foreman (`editor` R14): a second URL would break R1; decide once the tab is used.
