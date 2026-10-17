import Foundation
import Testing

@testable import Foreman

/// editor R63, R64: the library tab's file and title, no window and no server.
@Suite struct LibrarySourceTests {
    private let caches = URL(filePath: "/caches")
    private let jdt = "jdt://contents/spring-web-6.1.jar/org.springframework.http/ResponseEntity.class?=ccoe/%5C/m2"

    private func source(_ uri: String) -> LibrarySource { LibrarySource(uri: uri, caches: caches) }

    @Test func keysTwoUrisWithTheSameNameApart() {
        let a = source("jdt://contents/a.jar/p/Foo.class")
        let b = source("jdt://contents/b.jar/p/Foo.class")
        #expect(a.url != b.url)
        #expect(a.url.lastPathComponent == "Foo.java")
        #expect(a.url == source("jdt://contents/a.jar/p/Foo.class").url)
    }

    @Test func keyIsSixteenHexDigitsUnderTheSourcesFolder() {
        let folder = source(jdt).url.deletingLastPathComponent()
        #expect(folder.deletingLastPathComponent().path(percentEncoded: false) == "/caches/Foreman/sources/")
        let key = folder.lastPathComponent
        #expect(key.count == 16)
        #expect(key.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test(arguments: [
        ("jdt://contents/a.jar/p/..", "Class.java"), ("jdt://contents/a.jar/p/", "p"),
        ("jdt://contents/a.jar/p/Foo(1) bar.java", "Foo1bar.java"), ("jdt://x/a/b/../c%2F..%2Fd.java", "c..d.java"),
        ("", "Class.java"), ("jdt://contents/a.jar/p/Foo.java?=x/y#z", "Foo.java"), ("jdt://a/.", "Class.java"),
    ])
    func sanitisesTheName(uri: String, expected: String) {
        #expect(LibrarySource.name(of: uri) == expected)
        #expect(source(uri).url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "sources")
    }

    @Test func titleNamesTheJar() {
        #expect(
            source("jdt://contents/spring-web-6.1.jar/org.springframework.http/ResponseEntity.java?=a").title
                == "ResponseEntity.java — spring-web-6.1.jar")
        #expect(source(jdt).title == "ResponseEntity.java — spring-web-6.1.jar")
    }

    @Test func titleIsTheNameAloneWithoutAJar() {
        #expect(source("jdt://other/Foo.java").title == "Foo.java")
        #expect(source("file:///usr/lib/Foo.swift").title == "Foo.swift")
    }

    @Test func writesWithoutWritePermissionAndReplacesTheText() throws {
        let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let folder = repository.appending(path: "DerivedData/library-source-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = LibrarySource(uri: jdt, caches: folder)
        try source.write("first")
        let path = source.url.path(percentEncoded: false)
        #expect(try String(contentsOf: source.url, encoding: .utf8) == "first")
        #expect(!FileManager.default.isWritableFile(atPath: path))
        try source.write("second")
        #expect(try String(contentsOf: source.url, encoding: .utf8) == "second")
        #expect(!FileManager.default.isWritableFile(atPath: path))
        // editor R63: read back, the document is read-only.
        let document = try FileDocument.decode(Data(contentsOf: source.url), isWritable: false)
        #expect(document.isReadOnly)
    }

    /// editor R4: an absolute path restores as itself; the title survives the payload.
    @Test func aLibraryTabsPayloadKeepsItsTitleAndAbsolutePath() throws {
        let root = URL(filePath: "/w")
        let path = Workspace.persistedPath(for: source(jdt).url, root: root)
        #expect(path.hasPrefix("/caches/"))
        #expect(Workspace.url(forPersistedPath: path, root: root) == source(jdt).url)
        let payload = EditorTab.Payload(path: path, pinned: false, title: "Foo.java — a.jar")
        let decoded = try JSONDecoder().decode(EditorTab.Payload.self, from: JSONEncoder().encode(payload))
        #expect(decoded == payload)
        let old = try JSONDecoder().decode(EditorTab.Payload.self, from: Data(#"{"path":"a","pinned":true}"#.utf8))
        #expect(old.title == nil)
    }
}
