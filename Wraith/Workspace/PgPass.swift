import Foundation

/// `~/.pgpass`, read the way `libpq` reads it (postgres R3, edge cases): a read-only fallback
/// between the Keychain and the input sheet.
///
/// Nothing exists in Foundation for the format, so it is ~60 lines of pure functions here.
nonisolated enum PgPass {
    /// One line: `host:port:database:user:password`, each field `*` or a literal.
    struct Entry: Equatable, Sendable {
        let host: String
        let port: String
        let database: String
        let user: String
        let password: String
    }

    /// The default file, or `$PGPASSFILE` when set (libpq's convention).
    static func defaultFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["PGPASSFILE"], !path.isEmpty {
            return URL(filePath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".pgpass")
    }

    /// The password for the connection read from `file`, or `nil`.
    ///
    /// `nil` when the file is missing or has no matching line. A file readable by group or others
    /// is ignored, like `libpq` does, and said in `warnings`.
    static func password(
        in file: URL, host: String, port: Int, database: String, user: String, warnings: inout [String]
    ) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        else { return nil }
        let mode = (attributes[.posixPermissions] as? Int) ?? 0
        guard isSecure(mode: mode) else {
            warnings.append(
                "\(file.lastPathComponent) ignored: permissions should be u=rw (0600), not \(String(mode, radix: 8))."
            )
            return nil
        }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return password(in: parse(text), host: host, port: port, database: database, user: user)
    }

    /// `libpq`: the file is refused as soon as group or others have any right.
    static func isSecure(mode: Int) -> Bool {
        mode & 0o077 == 0
    }

    /// Lines with fewer than five fields and `#` comments are skipped; `\:` and `\\` are
    /// unescaped inside a field.
    static func parse(_ text: String) -> [Entry] {
        text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let fields = split(line)
            guard fields.count >= 5 else { return nil }
            return Entry(
                host: fields[0], port: fields[1], database: fields[2], user: fields[3],
                password: fields[4...].joined(separator: ":"))
        }
    }

    /// The first line matching every field, `*` matching anything.
    static func password(in entries: [Entry], host: String, port: Int, database: String, user: String) -> String? {
        entries.first { entry in
            matches(entry.host, host) && matches(entry.port, String(port)) && matches(entry.database, database)
                && matches(entry.user, user)
        }?.password
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        pattern == "*" || pattern == value
    }

    private static func split(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isEscaped = false
        for character in line {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == ":" {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }
}
