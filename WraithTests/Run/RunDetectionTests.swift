import Foundation
import Testing

@testable import Wraith

/// run R14–R15: the manifests read, the package manager, the precedence.
struct RunDetectionTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RunDetectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "api"), withIntermediateDirectories: true)
    }

    private func write(_ name: String, _ text: String, in folder: String? = nil) throws {
        let base = folder.map { root.appending(path: $0) } ?? root
        try text.write(to: base.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func detect(_ repos: [String] = []) -> [RunCommand] {
        defer { try? FileManager.default.removeItem(at: root) }
        return RunCatalog.detect(root: root, repos: repos.map { root.appending(path: $0) })
    }

    @Test func packageScriptsUseTheLockfilesPackageManager() throws {
        try write("package.json", #"{ "scripts": { "dev": "vite", "build:prod": "vite build" } }"#)
        try write("pnpm-lock.yaml", "")
        let commands = detect()
        #expect(commands.map(\.id) == ["root:build:prod", "root:dev"])
        #expect(commands.map(\.command) == ["pnpm run build:prod", "pnpm run dev"])
        #expect(commands.first?.source == "package.json")
        // The folder is gone by now: compare paths, not URLs (a live folder gets a trailing slash).
        #expect(commands.first?.cwd.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)) == true)
        #expect(commands.first?.subtitle == "pnpm run build:prod · package.json")
    }

    @Test func mavenSwiftAndMakeInADeclaredRepo() throws {
        try write("pom.xml", "<project/>", in: "api")
        try write("Package.swift", "// swift-tools-version:6.0", in: "api")
        try write(
            "Makefile", ".PHONY: all\nall: build\n\tmake build\nbuild:\n\techo\n%.o: %.c\n$(X):\nCFLAGS:=1\n", in: "api"
        )
        let commands = detect(["api"])
        #expect(
            commands.map(\.id) == [
                "api:mvn-test", "api:mvn-package", "api:mvn-verify", "api:swift-build", "api:swift-test", "api:all",
                "api:build",
            ])
        #expect(commands.last?.command == "make build")
        #expect(commands.allSatisfy { $0.repo == "api" })
    }

    @Test func firstLevelFoldersAreReadTooExceptExcludedOnes() throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: "node_modules"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".hidden"), withIntermediateDirectories: true)
        try write("package.json", #"{ "scripts": { "dev": "x" } }"#, in: "api")
        try write("package.json", #"{ "scripts": { "dev": "x" } }"#, in: "node_modules")
        try write("package.json", #"{ "scripts": { "dev": "x" } }"#, in: ".hidden")
        #expect(detect().map(\.id) == ["api:dev"])
    }

    @Test func aMalformedManifestYieldsNothing() throws {
        try write("package.json", "{ not json")
        try write("Makefile", "CFLAGS := -O2\n")
        #expect(detect().isEmpty)
    }

    @Test func declaredCommandsWin() {
        let declared = RunCommand(
            id: "root:dev", repo: ".", name: "dev", command: "make dev", cwd: root, env: [:], problem: nil)
        let detected = [
            RunCommand(
                id: "root:dev", repo: ".", name: "dev", command: "npm run dev", cwd: root, env: [:], problem: nil,
                source: "package.json"),
            RunCommand(
                id: "root:test", repo: ".", name: "test", command: "npm run test", cwd: root, env: [:], problem: nil,
                source: "package.json"),
        ]
        let merged = RunCatalog.merge(declared: [declared], detected: detected)
        #expect(merged.map(\.command) == ["make dev", "npm run test"])
    }

    @Test func packageManagerFollowsTheLockfile() throws {
        #expect(RunCatalog.packageManager(in: root) == "npm")
        try write("yarn.lock", "")
        #expect(RunCatalog.packageManager(in: root) == "yarn")
        try write("bun.lock", "")
        #expect(RunCatalog.packageManager(in: root) == "yarn")
        try FileManager.default.removeItem(at: root)
    }
}
