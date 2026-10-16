import AppKit
import SwiftUI

/// layout R30 (amended 2026-10-16), product R8: the toolbar's first widget — the workspace's
/// initials and name; its menu opens another folder, a recent one, or reveals this one.
enum ProjectWidget {
    @MainActor
    static func register(
        in layout: LayoutManager, folder: URL, theme: ThemeService, appDelegate: ForemanAppDelegate,
        open: @escaping (URL) -> Void
    ) {
        let name = folder.lastPathComponent
        layout.register(
            toolbarItem: ToolbarItemDescriptor(
                id: WorkspaceToolbar.projectID, title: name, icon: "folder", placement: .leading,
                kind: .widget(
                    view: { openMenu in
                        AnyView(
                            ToolbarWidgetLabel(
                                theme: theme, title: name, help: folder.path(percentEncoded: false),
                                openMenu: openMenu
                            ) {
                                Text(initials(of: name))
                                    .font(theme.font(.small, weight: .medium))
                                    .foregroundStyle(theme.tokens.accentText.color)
                                    .frame(width: 20, height: 20)
                                    .background(theme.tokens.accent.color, in: RoundedRectangle(cornerRadius: 5))
                            })
                    },
                    menu: {
                        ToolbarMenu(
                            entries: entries(
                                recents: ForemanAppDelegate.recentFolders().filter { $0 != folder },
                                choose: {
                                    guard let chosen = ForemanAppDelegate.chooseFolder() else { return }
                                    open(WorkspaceFolder.canonical(chosen))
                                },
                                openRecent: { appDelegate.openRecent($0) },
                                reveal: { NSWorkspace.shared.activateFileViewerSelecting([folder]) }))
                    })))
    }

    /// The menu, as a value: *Open…*, *Open Recent ▸* (product R8), *Reveal in Finder*.
    @MainActor
    static func entries(
        recents: [URL], choose: @escaping () -> Void, openRecent: @escaping (URL) -> Void,
        reveal: @escaping () -> Void
    ) -> [ToolbarMenuEntry] {
        [
            ToolbarMenuEntry(id: "project.open", title: "Open…", shortcut: Shortcut(parsing: "cmd+o"), perform: choose),
            ToolbarMenuEntry(
                id: "project.recent", title: "Open Recent",
                children: recents.map { folder in
                    ToolbarMenuEntry(
                        id: "project.recent.\(folder.path(percentEncoded: false))", title: folder.lastPathComponent,
                        subtitle: folder.deletingLastPathComponent().path(percentEncoded: false)
                    ) { openRecent(folder) }
                },
                isEnabled: !recents.isEmpty, perform: {}),
            ToolbarMenuEntry(
                id: "project.reveal", title: "Reveal in Finder", startsSection: true, perform: reveal),
        ]
    }

    /// The two letters of the mark: the first letters of the first two words, or the first two
    /// letters of a single word (`orders-api` → `OA`, `foreman` → `FO`).
    nonisolated static func initials(of name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        let letters: [Character] =
            words.count >= 2 ? words.prefix(2).compactMap(\.first) : Array((words.first ?? "").prefix(2))
        return String(letters).uppercased()
    }
}
