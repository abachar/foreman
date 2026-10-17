import SwiftUI

/// layout R30 (amended 2026-10-16), git R40 (amended 2026-10-17): the toolbar's branch widget —
/// the branch of the working copy holding the active tab's file and how many worktrees its repo
/// has; a click opens the menu.
struct GitBranchWidget: View {
    let model: GitModel
    let layout: LayoutManager
    let theme: ThemeService
    /// Asked for the working copy of the tab just activated (`nil`: none active).
    let followTab: (TabID?) -> Void
    let openMenu: () -> Void

    var body: some View {
        let label = Self.label(of: model)
        ToolbarWidgetLabel(
            theme: theme, title: label.title, detail: label.detail, help: "Branches and worktrees",
            openMenu: openMenu
        ) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(theme.tokens.textSecondary.color)
        }
        // git R40 (amended 2026-10-17): the widget follows the active tab, like explorer R25.
        .onChange(of: layout.model.active.active?.id, initial: true) { _, id in followTab(id) }
    }

    /// The widget's text.
    ///
    /// `main` and `2 worktrees`; the repo's name first when the window holds several repos
    /// (`ccoe-backend / main`). A worktree shows its own branch, its repo's name and its repo's
    /// worktree count.
    static func label(of model: GitModel) -> (title: String, detail: String?) {
        let tops = model.sections.filter { $0.repo.parent == nil }
        guard let shown = model.shownCopy else { return ("No branch", nil) }
        let top = shown.repo.parent.flatMap(model.section) ?? shown
        let worktrees = model.children(of: top.id).count
        return text(
            repo: tops.count > 1 ? top.repo.name : nil,
            head: shown.status.map(GitRepoSectionView.headText) ?? "…", worktrees: worktrees)
    }

    nonisolated static func text(repo: String?, head: String, worktrees: Int) -> (title: String, detail: String?) {
        let title = repo.map { "\($0) / \(head)" } ?? head
        switch worktrees {
        case 0: return (title, nil)
        case 1: return (title, "1 worktree")
        default: return (title, "\(worktrees) worktrees")
        }
    }
}
