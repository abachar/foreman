import Foundation
import SwiftUI

/// Root view of a workspace window: one window, one folder (product R1).
///
/// M0 has nothing to show yet — zones, panels and tabs arrive with the layout tasks — so the window
/// displays the folder it is rooted at, or a clear error when that folder disappeared between two
/// openings; the persisted state of that workspace is left untouched (product, edge cases).
struct WorkspaceView: View {
    let folder: URL
    let appDelegate: WraithAppDelegate

    @Environment(\.openWindow) private var openWindow
    @State private var isFolderReachable = true

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(folder.lastPathComponent)
            .task(id: folder) {
                isFolderReachable = await Self.isDirectory(folder)
            }
            .onAppear {
                appDelegate.adopt(openWindow)
            }
    }

    @ViewBuilder
    private var content: some View {
        if isFolderReachable {
            Text(folder.path(percentEncoded: false))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ContentUnavailableView(
                "Folder Not Found",
                systemImage: "questionmark.folder",
                description: Text(folder.path(percentEncoded: false))
            )
        }
    }

    /// Reading the folder is disk IO, so it runs off the main actor (coding rules, concurrency).
    private static func isDirectory(_ folder: URL) async -> Bool {
        let check = Task.detached {
            (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        return await check.value
    }
}
