import Testing

@testable import Foreman

/// postgres R15: `quote_ident` on the client.
struct SQLIdentifierTests {
    /// Every name is quoted, keyword or not: `"users"` and `users` name the same object, so the
    /// only thing an exception would buy is a keyword list to maintain.
    @Test(arguments: ["users", "order_items", "_tmp", "t1", "a$b", "select", "user", "table", "int"])
    func everyNameIsQuoted(name: String) {
        #expect(SQLIdentifier.quote(name) == "\"\(name)\"")
    }

    @Test func uppercaseAndSpecialCharactersAreQuoted() {
        #expect(SQLIdentifier.quote("Users") == "\"Users\"")
        #expect(SQLIdentifier.quote("my table") == "\"my table\"")
        #expect(SQLIdentifier.quote("1abc") == "\"1abc\"")
        #expect(SQLIdentifier.quote("") == "\"\"")
        #expect(SQLIdentifier.quote("café") == "\"café\"")
    }

    @Test func doubleQuotesAreDoubled() {
        #expect(SQLIdentifier.quote("a\"b") == "\"a\"\"b\"")
        #expect(SQLIdentifier.quote("x\"y'; DROP TABLE t; --") == "\"x\"\"y'; DROP TABLE t; --\"")
    }

    @Test func qualifiedNameQuotesEachPart() {
        #expect(SQLIdentifier.qualified("public", "users") == "\"public\".\"users\"")
        #expect(SQLIdentifier.qualified("My Schema", "order") == "\"My Schema\".\"order\"")
    }
}
