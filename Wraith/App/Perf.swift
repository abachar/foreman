import Foundation
import os

/// The three budgets of `architecture.md` (Performance), as `os_signpost` intervals: free outside
/// a trace, read with Instruments or `xctrace` (M6 task 6.5, decision 2026-08-27).
///
/// `workspace.open`: the request (`WraithAppDelegate`) to the zones' first frame. `panel.show`:
/// `PanelManager.show` to the next main-queue turn, after SwiftUI's commit. Typing has no
/// interval: it is checked with the Time Profiler (nothing synchronous on the main thread).
nonisolated enum Perf {
    static let signposter = OSSignposter(subsystem: "dev.crafters.wraith", category: "perf")
}
