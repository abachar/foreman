import Testing

@testable import Foreman

/// postgres R15: `quote_ident` on the client.
struct SQLIdentifierTests {
    @Test(arguments: ["users", "order_items", "_tmp", "t1", "a$b"])
    func plainLowercaseNamesStayBare(name: String) {
        #expect(SQLIdentifier.quote(name) == name)
    }

    @Test(arguments: ["select", "user", "table", "order", "int", "varchar"])
    func keywordsAreQuoted(name: String) {
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
    }

    @Test func qualifiedNameQuotesEachPart() {
        #expect(SQLIdentifier.qualified("public", "users") == "public.users")
        #expect(SQLIdentifier.qualified("My Schema", "order") == "\"My Schema\".\"order\"")
    }
}
