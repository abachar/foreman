import Foundation
import os

/// The three budgets of `architecture.md` (Performance), as `os_signpost` intervals: free outside
/// a trace, read with Instruments or `xctrace` (M6 task 6.5, decision 2026-08-27).
///
/// `workspace.open`: the request (`ForemanAppDelegate`) to the zones' first frame. `panel.show`:
/// `PanelManager.show` to the next main-queue turn, after SwiftUI's commit. Typing has no
/// interval: it is checked with the Time Profiler (nothing synchronous on the main thread).
///
/// The hot paths of the 2026-10-17 audit (M23 task 23.1), measured before anything is optimised:
/// `explorer.reload`, one outline reload (message `full` or `partial`); `diff.render`, one diff's
/// rendering, with one `diff.render.file` event per file; `editor.keystroke`, the synchronous work
/// after one edit.
nonisolated enum Perf {
    static let signposter = OSSignposter(subsystem: "dev.crafters.foreman", category: "perf")
}
