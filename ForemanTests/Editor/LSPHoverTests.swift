import Foundation
import LanguageServerProtocol
import Testing

@testable import Foreman

/// editor R42: the text of a hover, whichever of the protocol's three shapes it arrives in.
struct LSPHoverTests {
    private func hover(_ contents: ThreeTypeOption<MarkedString, [MarkedString], MarkupContent>) -> HoverResponse {
        Hover(contents: contents, range: nil)
    }

    @Test func readsAMarkupContent() {
        let response = hover(.optionC(MarkupContent(kind: .markdown, value: "`let a: Int`")))
        #expect(LSPServers.markdown(of: response) == "`let a: Int`")
    }

    /// Plain text is not markdown: fenced, so a signature full of `<`, `*` or `_` reads as typed.
    @Test func fencesPlainTextContent() {
        let response = hover(.optionC(MarkupContent(kind: .plaintext, value: "Array<T> *not* markdown")))
        #expect(LSPServers.markdown(of: response) == "```\nArray<T> *not* markdown\n```")
    }

    /// The deprecated `MarkedString`, still what several servers send.
    @Test func readsABareMarkedString() {
        #expect(LSPServers.markdown(of: hover(.optionA(.optionA("**bold**")))) == "**bold**")
    }

    /// Its language/value pair is a code block by another name.
    @Test func fencesALanguagePair() {
        let pair = LanguageStringPair(language: .swift, value: "func greet()")
        #expect(LSPServers.markdown(of: hover(.optionA(.optionB(pair)))) == "```swift\nfunc greet()\n```")
    }

    @Test func joinsAListOfMarkedStrings() {
        let pair = LanguageStringPair(language: .swift, value: "let a: Int")
        let response = hover(.optionB([.optionB(pair), .optionA("The count.")]))
        #expect(LSPServers.markdown(of: response) == "```swift\nlet a: Int\n```\n\nThe count.")
    }

    /// A server with nothing to say must not open an empty popover.
    @Test func hasNoTextForAnEmptyAnswer() {
        #expect(LSPServers.markdown(of: nil) == nil)
        #expect(LSPServers.markdown(of: hover(.optionC(MarkupContent(kind: .markdown, value: "   \n ")))) == nil)
        #expect(LSPServers.markdown(of: hover(.optionB([]))) == nil)
    }

    /// editor R39: hover is offered only when the server announced it.
    @Test func offersHoverOnlyWhenAnnounced() {
        #expect(LSPServer.providesHover(nil) == false)
        var capabilities = ServerCapabilities()
        #expect(LSPServer.providesHover(capabilities) == false)
        capabilities.hoverProvider = .optionA(false)
        #expect(LSPServer.providesHover(capabilities) == false)
        capabilities.hoverProvider = .optionA(true)
        #expect(LSPServer.providesHover(capabilities) == true)
        capabilities.hoverProvider = .optionB(HoverOptions())
        #expect(LSPServer.providesHover(capabilities) == true)
    }
}
