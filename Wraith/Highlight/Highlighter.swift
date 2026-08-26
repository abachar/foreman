import AppKit
import Neon
import SwiftTreeSitter
import os

/// Attaches Neon to a text view (editor R12), sharing one parsed `LanguageConfiguration` per
/// language across all views of the window.
///
/// Using Neon's `TextViewHighlighter` because it already does the whole job: it becomes the text
/// storage delegate, parses incrementally off the main actor, cancels on edits and applies the
/// attributes as TextKit 2 rendering attributes. Nothing here re-does any of it.
@MainActor
final class Highlighter {
    private let theme: ThemeService
    private var configurations: [Language: LanguageConfiguration] = [:]
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "highlight")

    init(theme: ThemeService) {
        self.theme = theme
    }

    /// The highlighter now driving `textView`, kept alive by the caller; `nil` means plain text
    /// (editor R13: a missing grammar or query is logged at `debug`, never shown).
    func attach(to textView: NSTextView, language: Language) -> TextViewHighlighter? {
        do {
            let configuration = try self.configuration(for: language)
            return try TextViewHighlighter(
                textView: textView,
                configuration: TextViewHighlighter.Configuration(
                    languageConfiguration: configuration,
                    attributeProvider: { [theme] token in theme.attributes(forCapture: token.name) },
                    locationTransformer: { _ in nil }))
        } catch {
            logger.debug(
                "no highlighting for \(language.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func configuration(for language: Language) throws -> LanguageConfiguration {
        if let configuration = configurations[language] {
            return configuration
        }
        let configuration = try language.makeConfiguration()
        configurations[language] = configuration
        return configuration
    }
}
