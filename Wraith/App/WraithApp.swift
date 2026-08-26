import AppKit
import Foundation
import SwiftUI

@main
struct WraithApp: App {
    @NSApplicationDelegateAdaptor(WraithAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(for: URL.self) { $folder in
            WorkspaceView(folder: folder, appDelegate: appDelegate)
        } defaultValue: {
            appDelegate.takeLaunchFolder()
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenFolderButton()
            }
        }
    }
}

/// *File ▸ Open…*: choose a folder and open its window.
///
/// It replaces *New Window*: there is no window without a folder (product R8), and a folder already
/// open activates its window instead of opening a second one (product R1).
private struct OpenFolderButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open…") {
            guard let folder = WraithAppDelegate.chooseFolder() else { return }
            openWindow(value: WorkspaceFolder.canonical(folder))
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}
