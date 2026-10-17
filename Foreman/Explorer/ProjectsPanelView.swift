import SwiftUI

/// explorer R25 (2026-10-17, M22 22.7): the left slot's *Project* tab — the workspace's real
/// projects, each its type's icon, name and folder; a click unfolds one on its files with the
/// explorer's tree, the others staying listed under it.
struct ProjectsPanelView: View {
    let model: ProjectsModel
    let layout: LayoutManager
    let theme: ThemeService
    /// A file of a project was chosen: open it (explorer R12, R13).
    let onOpen: (URL, ExplorerOpenMode) -> Void
    /// The actions of a project's tree, rooted at its folder.
    let actions: (WorkspaceProject) -> ExplorerActions

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(panels: layout.panels, current: ExplorerFeature.projectsPanelID, theme: theme) {
                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Look for projects again")
            }
            if model.projects.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No Project", systemImage: "shippingbox",
                        description: Text(
                            "No pom.xml, build.gradle, package.json, Package.swift, Cargo.toml, go.mod or Makefile at the "
                                + "root, in the repos or one level under them.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ForEach(model.projects) { project in
                    row(project)
                    if model.expanded == project.id {
                        ExplorerOutlineView(
                            model: model.tree(for: project), theme: theme, font: theme.interfaceFont(),
                            isFocused: layout.panels.focus == .panel(ExplorerFeature.projectsPanelID),
                            onOpen: { node, mode in onOpen(project.url.appending(path: node.relativePath), mode) },
                            operations: actions(project)
                        )
                        .id(project.id)
                        .frame(maxHeight: .infinity)
                    }
                }
                if model.expanded == nil {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func row(_ project: WorkspaceProject) -> some View {
        let tokens = theme.tokens
        let isExpanded = model.expanded == project.id
        return Button {
            model.toggle(project)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(tokens.textSecondary.color)
                    .frame(width: 12)
                if let icon = FileIcon.image(named: project.kind.icon) {
                    Image(nsImage: icon)
                }
                Text(project.name)
                    .font(theme.font(.body, weight: isExpanded ? .medium : .regular))
                    .foregroundStyle(tokens.textPrimary.color)
                    .lineLimit(1)
                if project.path != project.name, project.path != "." {
                    Text(project.path)
                        .font(theme.font(.small))
                        .foregroundStyle(tokens.textSecondary.color)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                Text(project.kind.title)
                    .font(theme.font(.small))
                    .foregroundStyle(tokens.textSecondary.color)
            }
            .padding(.horizontal, 10)
            .frame(height: tokens.rowHeight)
            .background(isExpanded ? tokens.surfaceRaised.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(project.url.path(percentEncoded: false))
    }
}
