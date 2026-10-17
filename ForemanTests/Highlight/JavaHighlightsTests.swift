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
        // Sorted the way Neon applies them (SwiftTreeSitter's `highlights()`): by position, then
        // from the less specific capture to the more specific, the last applied winning.
        let captures = query.execute(in: tree).filter { $0.allowed(in: context) }.flatMap(\.captures).sorted()
        return captures.compactMap { capture in
            capture.name.map { ($0, text.substring(with: capture.node.range)) }
        }
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
        // editor R59: a local or a parameter is a `variable` token — the code's own colour — so
        // the server has a token to speak over; nothing else claims it.
        #expect(try names(of: "count") == ["variable"])
        #expect(try names(of: "first") == ["variable"])
    }

    /// A method declaration is coloured; its calls are plain text, like IntelliJ.
    @Test func declarationsAreColouredCallsAreNot() throws {
        #expect(try names(of: "run") == ["function.method", "variable"])
        #expect(try names(of: "OrderService") == ["type", "function.method", "variable"])
        #expect(try names(of: "size") == ["variable"])
        #expect(try names(of: "save") == ["variable"])
        #expect(try names(of: "get") == ["variable"])
    }

    /// A type in use is plain text; a declared name is a `type`.
    @Test func onlyDeclaredTypesAreTypes() throws {
        #expect(try names(of: "OrderRepository") == ["variable"])
        #expect(try names(of: "String") == ["variable"])
        #expect(try names(of: "List") == ["variable"])
        #expect(try names(of: "Base") == ["variable"])
        #expect(try names(of: "Line") == ["type", "variable"])
        #expect(try names(of: "Status") == ["type", "variable"])
    }

    /// IntelliJ's keyword colour: `this`, `super`, the primitives and the literals.
    @Test func intelliJKeywords() throws {
        for word in ["this", "super", "int", "void", "true", "null", "class", "record", "enum", "static"] {
            #expect(try names(of: word) == ["keyword"], "\(word)")
        }
    }

    /// Constants, annotations with their `@`, and the string/number/comment basics.
    @Test func constantsAnnotationsAndLiterals() throws {
        #expect(try names(of: "MAX_RETRIES") == ["constant", "property", "variable"])
        #expect(try names(of: "OPEN") == ["constant", "variable"])
        #expect(try names(of: "Service") == ["attribute", "variable"])
        #expect(try names(of: "Override") == ["attribute", "variable"])
        #expect(try names(of: "@") == ["attribute"])
        #expect(try names(of: "3") == ["number"])
        #expect(try names(of: "0") == ["number"])
    }

    /// The file is Foreman's, found in the app's resources from the test host too: the package's
    /// query captures `super` as `function.builtin` and `this` as `variable.builtin`; ours never.
    @Test func theQueryIsForemansOwn() throws {
        let configuration = try Language.java.makeConfiguration()
        let query = try #require(configuration.queries[.highlights])
        #expect(try captures().allSatisfy { !$0.name.hasSuffix(".builtin") })
        #expect(query.patternCount > 10)
    }

    /// editor R59: the specific capture is listed after the plain `variable` one, so Neon's last
    /// application wins — the order the package's own queries rely on.
    @Test func theSpecificCaptureComesAfterThePlainOne() throws {
        let all = try captures()
        let names = all.filter { $0.text == "repository" }.map(\.name)
        #expect(names.first == "variable")
        #expect(names.contains("property"))
    }
}
