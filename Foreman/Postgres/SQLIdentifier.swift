import Foundation

/// `quote_ident` on the client side (postgres R15): every identifier Foreman puts into SQL text
/// goes through here; values never do, they are bound.
///
/// Nothing in PostgresNIO quotes identifiers (it binds values only), so this is the server's rule
/// in two lines: every name is quoted and a `"` inside is doubled. Quoting a name that would have
/// been legal bare changes nothing for the server — `"users"` and `users` name the same object —
/// and it spares us a reserved-keyword list to keep in step with each PostgreSQL release. Rows
/// that show a name to the user build it from the raw catalog strings instead.
nonisolated enum SQLIdentifier {
    static func quote(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func qualified(_ schema: String, _ name: String) -> String {
        quote(schema) + "." + quote(name)
    }
}
