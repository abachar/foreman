import Foundation
import SwiftTreeSitter
import Testing

@testable import Foreman

/// editor R12 (amended 2026-10-17, M25 25.1): Foreman's own Java highlights.
///
/// Written against IntelliJ's Java colour page. The captures on a fixture are pinned here so that
/// a grammar upgrade renaming a node fails in a test, not on screen.
struct JavaHighlightsTests {
    private let source = """
        package shop;

        import java.util.List;

        @Service
        public class OrderService extends Base implements Runnable {
            private static final int MAX_RETRIES = 3;
            private final OrderRepository repository;
            private List<String> names;

            public OrderService(OrderRepository repository) {
                this.repository = repository;
            }

            @Override
            public void run() {
                int count = names.size();
                String first = this.names.get(0);
                repository.save(first, count, true, null);
                super.run();
            }

            record Line(String sku, int quantity) {}
            enum Status { OPEN, CLOSED }
        }
        """

    /// Every (capture name, text) pair the query produces on the fixture.
    private func captures() throws -> [(name: String, text: String)] {
        let configuration = try Language.java.makeConfiguration()
        let query = try #require(configuration.queries[.highlights])
        let parser = Parser()
        try parser.setLanguage(configuration.language)
        let tree = try #require(parser.parse(source))
        let text = source as NSString
        // The `#match?` predicates are evaluated by the client, not by tree-sitter: without a
        // context every identifier would come out as a `constant`.
        let context = Predicate.Context(
            textProvider: { range, _ in text.substring(with: range) }, groupMembershipProvider: { _, _, _ in false })
        var result: [(String, String)] = []
        for match in query.execute(in: tree) where match.allowed(in: context) {
            for capture in match.captures {
                guard let name = capture.name else { continue }
                result.append((name, text.substring(with: capture.node.range)))
            }
        }
        return result
    }

    private func names(of text: String) throws -> Set<String> {
        Set(try captures().filter { $0.text == text }.map(\.name))
    }

    /// A field is a `property` at its declaration and behind a dot; a local and a parameter are
    /// plain text — unless the grammar cannot tell, which is the bare `names` in `run()`.
    @Test func fieldsArePropertiesLocalsAreNot() throws {
        let all = try captures()
        let properties = all.filter { $0.name == "property" }.map(\.text)
        #expect(properties.sorted() == ["MAX_RETRIES", "names", "names", "repository", "repository"])
        #expect(try names(of: "count").isEmpty)
        #expect(try names(of: "first").isEmpty)
    }

    /// A method declaration is coloured; its calls are plain text, like IntelliJ.
    @Test func declarationsAreColouredCallsAreNot() throws {
        #expect(try names(of: "run") == ["function.method"])
        #expect(try names(of: "OrderService") == ["type", "function.method"])
        #expect(try names(of: "size").isEmpty)
        #expect(try names(of: "save").isEmpty)
        #expect(try names(of: "get").isEmpty)
    }

    /// A type in use is plain text; a declared name is a `type`.
    @Test func onlyDeclaredTypesAreTypes() throws {
        #expect(try names(of: "OrderRepository").isEmpty)
        #expect(try names(of: "String").isEmpty)
        #expect(try names(of: "List").isEmpty)
        #expect(try names(of: "Base").isEmpty)
        #expect(try names(of: "Line") == ["type"])
        #expect(try names(of: "Status") == ["type"])
    }

    /// IntelliJ's keyword colour: `this`, `super`, the primitives and the literals.
    @Test func intelliJKeywords() throws {
        for word in ["this", "super", "int", "void", "true", "null", "class", "record", "enum", "static"] {
            #expect(try names(of: word) == ["keyword"], "\(word)")
        }
    }

    /// Constants, annotations with their `@`, and the string/number/comment basics.
    @Test func constantsAnnotationsAndLiterals() throws {
        #expect(try names(of: "MAX_RETRIES") == ["constant", "property"])
        #expect(try names(of: "OPEN") == ["constant"])
        #expect(try names(of: "Service") == ["attribute"])
        #expect(try names(of: "Override") == ["attribute"])
        #expect(try names(of: "@") == ["attribute"])
        #expect(try names(of: "3") == ["number"])
        #expect(try names(of: "0") == ["number"])
    }

    /// The file is Foreman's, found in the app's resources from the test host too.
    @Test func theQueryIsForemansOwn() throws {
        let configuration = try Language.java.makeConfiguration()
        let query = try #require(configuration.queries[.highlights])
        // The package's query has one `(identifier) @variable` pattern; ours has none.
        #expect(try captures().allSatisfy { $0.name != "variable" })
        #expect(query.patternCount > 10)
    }
}
