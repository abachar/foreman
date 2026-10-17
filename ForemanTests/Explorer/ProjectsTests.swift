import Foundation
import Testing

@testable import Foreman

/// The Project view's detection (explorer R24, M22 22.7).
struct ProjectsTests {
    @Test func theStrongestManifestNamesTheKind() {
        #expect(WorkspaceProject.kind(of: ["pom.xml", "package.json"]) == .maven)
        #expect(WorkspaceProject.kind(of: ["build.gradle.kts"]) == .gradle)
        #expect(WorkspaceProject.kind(of: ["package.json", "README.md"]) == .node)
        #expect(WorkspaceProject.kind(of: ["Makefile"]) == .make)
        #expect(WorkspaceProject.kind(of: ["README.md", "src"]) == nil)
    }

    @Test func projectsAreFoundAtTheRootInTheReposAndOneLevelUnder() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "foreman-projects-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func file(_ path: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "".write(to: url, atomically: true, encoding: .utf8)
        }
        try file("backend/pom.xml")
        try file("backend/api/pom.xml")
        try file("backend/api/deep/package.json")
        try file("frontend/package.json")
        try file("frontend/node_modules/lib/package.json")
        try file("docs/README.md")
        try file(".hidden/package.json")

        let projects = WorkspaceProject.detect(root: root, repos: [root.appending(path: "backend")])
        #expect(projects.map(\.path) == ["backend", "backend/api", "frontend"])
        #expect(projects.map(\.kind) == [.maven, .maven, .node])
        #expect(projects.first?.name == "backend")
    }

    @Test func theManifestNamesTheProject() {
        let pom = """
            <project><parent><artifactId>spring-boot-parent</artifactId></parent>
              <artifactId> portal-api </artifactId></project>
            """
        #expect(WorkspaceProject.declaredName(kind: .maven, manifest: pom) == "portal-api")
        #expect(WorkspaceProject.declaredName(kind: .node, manifest: #"{"name": "ccoe-frontend"}"#) == "ccoe-frontend")
        #expect(WorkspaceProject.declaredName(kind: .node, manifest: "not json") == nil)
        #expect(WorkspaceProject.declaredName(kind: .go, manifest: "module x") == nil)
    }
}
