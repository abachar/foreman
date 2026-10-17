import CryptoKit
import Foundation

/// editor R63: where the text of a library class lives on disk, and what its tab is called.
///
/// The text goes under `<Caches>/Foreman/sources/<key>/<name>` — the platform's purgeable cache,
/// never the workspace — so the tab is an ordinary `editor.file` tab on a file nobody can write.
nonisolated struct LibrarySource: Equatable, Sendable {
    let uri: String
    let url: URL

    /// The file for `uri` under `caches`.
    ///
    /// `caches` is the user's caches folder in the app, a temporary folder in a test.
    init(uri: String, caches: URL) {
        self.uri = uri
        let digest = SHA256.hash(data: Data(uri.utf8)).map { String(format: "%02x", $0) }.joined()
        url = caches.appending(path: "Foreman/sources/\(digest.prefix(16))/\(Self.name(of: uri))")
    }

    /// editor R63: the URI's last path component kept to `[A-Za-z0-9._-]`, so no path component
    /// comes from the server's text. `jdtls` names the class file `Foo.class`; the text is Java.
    static func name(of uri: String) -> String {
        let path = uri.prefix { $0 != "?" && $0 != "#" }
        let last = (path.split(separator: "/").last.map(String.init) ?? "").removingPercentEncoding ?? ""
        let kept = String(
            last.unicodeScalars.filter {
                $0.isASCII && ($0.properties.isAlphabetic || "0123456789._-".unicodeScalars.contains($0))
            })
        guard kept.contains(where: { $0 != "." }) else { return "Class.java" }
        return kept.hasSuffix(".class") ? kept.dropLast("class".count) + "java" : kept
    }

    /// editor R63: `Foo.java — spring-web-6.1.jar`; the name alone when the URI names no jar
    /// (`jdt://contents/<jar>/<package>/<name>`).
    var title: String {
        let name = Self.name(of: uri)
        guard let parts = URL(string: uri), parts.host == "contents" else { return name }
        let components = parts.pathComponents.dropFirst()
        guard components.count >= 3, let jar = components.first else { return name }
        return "\(name) — \(jar)"
    }

    /// editor R63: the text, written without write permission (an older copy is replaced).
    func write(_ text: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: url)
        try Data(text.utf8).write(to: url)
        try manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path(percentEncoded: false))
    }
}
