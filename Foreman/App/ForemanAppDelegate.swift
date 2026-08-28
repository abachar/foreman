import AppKit
import Foundation
import Observation
import SwiftUI
import os

/// The AppKit entry points SwiftUI does not cover, and the window opener they need.
///
/// A folder reaches Foreman through `open -a Foreman <folder>` — the `foreman` script, a folder
/// dropped on the icon — or as a command-line argument. Either way the window is created by
/// `WindowGroup(for: URL.self)`, which only `openWindow(value:)` drives; that action exists inside
/// SwiftUI only, so the first window hands it over (`adopt(_:)`). Folders that arrive before that,
/// while the app is launching, wait in `pendingFolders`: the window created at launch takes one
/// through `takeLaunchFolder()`, `adopt(_:)` opens the rest.
///
/// `open -a Foreman <folder>` may deliver the folder *after* the launch window was created on
/// `$HOME` (product R8): that window is then superseded and closes itself, so `foreman .` opens
/// exactly one window (product R1).
@Observable
final class ForemanAppDelegate: NSObject, NSApplicationDelegate {
    /// The `$HOME` window created at launch that a folder replaced right away, if any.
    private(set) var supersededLaunchFolder: URL?

    @ObservationIgnored private var openWindow: OpenWindowAction?
    @ObservationIgnored private var pendingFolders: [URL] = []
    @ObservationIgnored private var hasTakenLaunchFolder = false
    @ObservationIgnored private var launchedOnHome: Date?
    /// architecture, Performance: one `workspace.open` interval per requested window (M6 6.5).
    @ObservationIgnored private var openIntervals: [URL: OSSignpostIntervalState] = [:]

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            open(folder: WorkspaceFolder.canonical(url))
        }
        // A folder right after launch is the folder the app was launched for, not a second one.
        if let launchedOnHome, Date.now.timeIntervalSince(launchedOnHome) < 2, !urls.isEmpty {
            supersededLaunchFolder = homeFolder()
        }
        launchedOnHome = nil
    }

    /// Folder the window created at launch is rooted at: the command-line argument, the folder the
    /// system asked for while launching, or `$HOME` (product R8).
    func takeLaunchFolder() -> URL {
        guard !hasTakenLaunchFolder else { return homeFolder() }
        hasTakenLaunchFolder = true
        if let argument = WorkspaceFolder.argument(in: CommandLine.arguments) {
            return measured(
                WorkspaceFolder.resolve(
                    path: argument,
                    currentDirectory: .currentDirectory(),
                    home: .homeDirectory
                ))
        }
        if !pendingFolders.isEmpty {
            return pendingFolders.removeFirst()
        }
        launchedOnHome = .now
        return measured(homeFolder())
    }

    /// The window rooted at `folder` drew its first frame: closes its `workspace.open` interval.
    func firstFrame(of folder: URL) {
        guard let interval = openIntervals.removeValue(forKey: folder) else { return }
        Perf.signposter.endInterval("workspace.open", interval)
    }

    private func measured(_ folder: URL) -> URL {
        if let previous = openIntervals[folder] {
            // The window already exists (product R1): the request is over as soon as it is activated.
            Perf.signposter.endInterval("workspace.open", previous)
        }
        openIntervals[folder] = Perf.signposter.beginInterval("workspace.open", id: Perf.signposter.makeSignpostID())
        return folder
    }

    /// `cmd+shift+n` (layout R23): the same panel as *File > Open…*.
    func openFolderFromPanel() {
        guard let folder = Self.chooseFolder() else { return }
        open(folder: WorkspaceFolder.canonical(folder))
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose the folder to open as a workspace."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Called by the first window: from now on the app opens windows by itself.
    func adopt(_ action: OpenWindowAction) {
        guard openWindow == nil else { return }
        openWindow = action
        let folders = pendingFolders
        pendingFolders = []
        for folder in folders {
            action(value: folder)
        }
    }

    /// product R1: SwiftUI activates the window already presenting this folder instead of opening a
    /// second one, which is why the URL is canonical.
    private func open(folder: URL) {
        guard let openWindow else {
            pendingFolders.append(measured(folder))
            return
        }
        openWindow(value: measured(folder))
    }

    private func homeFolder() -> URL {
        WorkspaceFolder.resolve(path: nil, currentDirectory: .currentDirectory(), home: .homeDirectory)
    }
}
