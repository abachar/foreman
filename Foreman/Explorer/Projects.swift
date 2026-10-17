import Foundation
import Observation

/// explorer R24 (2026-10-17, M22 22.7): a real project of the workspace — a folder holding a
/// build manifest — as the Project view lists it.
nonisolated struct WorkspaceProject: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable, CaseIterable {
        case maven
        case gradle
        case node
        case swift
        case rust
        case go
        case make

        /// The manifests of each kind, the strongest first: a Maven module with a `package.json`
        /// for its front end is a Maven project.
        static let manifests: [(name: String, kind: Kind)] = [
            ("pom.xml", .maven), ("build.gradle", .gradle), ("build.gradle.kts", .gradle), ("package.json", .node),
            ("Package.swift", .swift), ("Cargo.toml", .rust), ("go.mod", .go), ("Makefile", .make),
        ]

        /// The file icon of the kind (design R23).
        var icon: String {
            switch self {
            case .maven: return "file-maven"
            case .gradle: return "file-gradle"
            case .node: return "file-npm"
            case .swift: return "file-swift"
            case .rust: return "file-rust"
            case .go: return "file-go"
            case .make: return "file-makefile"
            }
        }

        var title: String {
            switch self {
            case .maven: return "Maven"
            case .gradle: return "Gradle"
            case .node: return "Node"
            case .swift: return "Swift"
            case .rust: return "Rust"
            case .go: return "Go"
            case .make: return "Make"
            }
        }
    }

    let url: URL
    /// Relative to the root, `.` for the root itself.
    let path: String
    let kind: Kind
    /// explorer R24 (2026-10-17): the name the manifest gives (`artifactId`, `name`), else the
    /// folder's — a project in `ccoe-backend/src` reads as its artifact, not as `src`.
    var declaredName: String?

    var id: String {
        path
    }

    var name: String {
        declaredName ?? url.lastPathComponent
    }

    /// The name a manifest declares: a Maven project's own `artifactId` (its parent's left out),
    /// a Node package's `name`; `nil` for the other kinds or a manifest without one.
    static func declaredName(kind: Kind, manifest: String) -> String? {
        switch kind {
        case .maven:
            var text = manifest
            if let parent = text.range(of: "<parent>"),
                let end = text.range(of: "</parent>", range: parent.upperBound..<text.endIndex)
            {
                text.removeSubrange(parent.lowerBound..<end.upperBound)
            }
            guard let open = text.range(of: "<artifactId>"),
                let close = text.range(of: "</artifactId>", range: open.upperBound..<text.endIndex)
            else { return nil }
            let name = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        case .node:
            guard let data = manifest.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let name = object["name"] as? String, !name.isEmpty
            else { return nil }
            return name
        case .gradle, .swift, .rust, .go, .make:
            return nil
        }
    }

    /// explorer R24: the kind a folder's file names make it, `nil` for a folder that is not one.
    static func kind(of names: Set<String>) -> Kind? {
        Kind.manifests.first { names.contains($0.name) }?.kind
    }

    /// explorer R24: where projects are looked for — the root, the declared repos, and the first
    /// level of both — the excluded and hidden folders left out (`ExcludedPaths`).
    static func detect(root: URL, repos: [URL]) -> [WorkspaceProject] {
        let root = root.standardizedFileURL
        let rootIsHome = root == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let bases = [root] + repos.map(\.standardizedFileURL)
        var candidates: [URL] = []
        for base in bases {
            candidates.append(base)
            candidates += subfolders(of: base)
        }
        var seen: Set<String> = []
        var projects: [WorkspaceProject] = []
        for folder in candidates {
            let path = Workspace.persistedPath(for: folder, root: root)
            guard seen.insert(path).inserted, !ExcludedPaths.isExcluded(path, rootIsHome: rootIsHome),
                let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)),
                let kind = kind(of: Set(names))
            else { continue }
            let manifest = Kind.manifests.first { $0.kind == kind && names.contains($0.name) }?.name
            let text = manifest.flatMap { try? String(contentsOf: folder.appending(path: $0), encoding: .utf8) }
            projects.append(
                WorkspaceProject(
                    url: folder, path: path.isEmpty ? "." : path, kind: kind,
                    declaredName: text.flatMap { declaredName(kind: kind, manifest: $0) }))
        }
        return projects.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func subfolders(of folder: URL) -> [URL] {
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}

/// explorer R24, R25: the Project view's state — the projects found, the one unfolded, a tree
/// per project built when it is first unfolded.
@Observable
@MainActor
final class ProjectsModel {
    private(set) var projects: [WorkspaceProject] = []
    private(set) var isLoading = false
    /// The project unfolded on its files; one at a time.
    var expanded: String?
    /// explorer R25 (amended 2026-10-17): the view follows the active tab — the project holding
    /// its file unfolds and the file is revealed.
    var followsActiveTab = true

    private let root: URL
    private let repos: () -> [URL]
    private let fsWatch: FSWatchService?
    private var trees: [String: ExplorerModel] = [:]
    private var loading: Task<Void, Never>?

    init(root: URL, repos: @escaping () -> [URL], fsWatch: FSWatchService?) {
        self.root = root
        self.repos = repos
        self.fsWatch = fsWatch
    }

    isolated deinit {
        loading?.cancel()
    }

    /// layout R4: the folders are read when the view is shown, off the main actor.
    func activate() {
        reload()
        if let expanded {
            trees[expanded]?.activate()
        }
    }

    func deactivate() {
        loading?.cancel()
        for tree in trees.values {
            tree.deactivate()
        }
    }

    func reload() {
        loading?.cancel()
        isLoading = true
        let root = root
        let repos = repos()
        loading = Task { [weak self] in
            let found = await Self.detect(root: root, repos: repos)
            guard !Task.isCancelled, let self else { return }
            projects = found
            isLoading = false
        }
    }

    @concurrent
    private static func detect(root: URL, repos: [URL]) async -> [WorkspaceProject] {
        WorkspaceProject.detect(root: root, repos: repos)
    }

    /// explorer R25: a click unfolds a project, or folds the one unfolded.
    func toggle(_ project: WorkspaceProject) {
        if let current = expanded {
            trees[current]?.deactivate()
        }
        expanded = expanded == project.id ? nil : project.id
        if expanded != nil {
            tree(for: project).activate()
        }
    }

    /// explorer R25: the project holding `path` (relative to the workspace root) unfolds on it.
    func reveal(_ path: String) {
        guard let (project, relative) = Self.owner(of: path, among: projects) else { return }
        if expanded != project.id {
            if let current = expanded {
                trees[current]?.deactivate()
            }
            expanded = project.id
            tree(for: project).activate()
        }
        tree(for: project).revealRequest = relative
    }

    /// The deepest project whose folder holds `path`, and the path inside it.
    nonisolated static func owner(
        of path: String, among projects: [WorkspaceProject]
    ) -> (
        WorkspaceProject, String
    )? {
        let candidates = projects.filter { $0.path == "." || path.hasPrefix($0.path + "/") }
        guard let project = candidates.max(by: { $0.path.count < $1.path.count }) else { return nil }
        return (project, project.path == "." ? path : String(path.dropFirst(project.path.count + 1)))
    }

    /// The unfolded project, if any.
    var expandedProject: WorkspaceProject? {
        projects.first { $0.id == expanded }
    }

    /// The project's own tree, the explorer's model rooted at its folder.
    func tree(for project: WorkspaceProject) -> ExplorerModel {
        if let tree = trees[project.id] {
            return tree
        }
        let tree = ExplorerModel(root: project.url, fsWatch: fsWatch)
        trees[project.id] = tree
        return tree
    }
}
