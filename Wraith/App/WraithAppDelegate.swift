import AppKit
import Foundation
import SwiftUI

/// The AppKit entry points SwiftUI does not cover, and the window opener they need.
///
/// A folder reaches Wraith through `open -a Wraith <folder>` — the `wraith` script, a folder
/// dropped on the icon — or as a command-line argument. Either way the window is created by
/// `WindowGroup(for: URL.self)`, which only `openWindow(value:)` drives; that action exists inside
/// SwiftUI only, so the first window hands it over (`adopt(_:)`). Folders that arrive before that,
/// while the app is launching, wait in `pendingFolders`: the window created at launch takes one
/// through `takeLaunchFolder()`, `adopt(_:)` opens the rest.
final class WraithAppDelegate: NSObject, NSApplicationDelegate {
    private var openWindow: OpenWindowAction?
    private var pendingFolders: [URL] = []
    private var hasTakenLaunchFolder = false

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            open(folder: WorkspaceFolder.canonical(url))
        }
    }

    /// Folder the window created at launch is rooted at: the command-line argument, the folder the
    /// system asked for while launching, or `$HOME` (product R8).
    func takeLaunchFolder() -> URL {
        guard !hasTakenLaunchFolder else { return homeFolder() }
        hasTakenLaunchFolder = true
        if let argument = WorkspaceFolder.argument(in: CommandLine.arguments) {
            return WorkspaceFolder.resolve(
                path: argument,
                currentDirectory: .currentDirectory(),
                home: .homeDirectory
            )
        }
        if !pendingFolders.isEmpty {
            return pendingFolders.removeFirst()
        }
        return homeFolder()
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
            pendingFolders.append(folder)
            return
        }
        openWindow(value: folder)
    }

    private func homeFolder() -> URL {
        WorkspaceFolder.resolve(path: nil, currentDirectory: .currentDirectory(), home: .homeDirectory)
    }
}
