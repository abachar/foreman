import AppKit
import Neon
import SwiftTreeSitter
import SwiftUI
import TreeSitterClient
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
    /// One build per language, shared by every view asking for it while it runs.
    private var configurations: [Language: Task<LanguageConfiguration, Error>] = [:]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "highlight")

    init(theme: ThemeService) {
        self.theme = theme
    }

    /// The highlighter now driving `textView`, kept alive by the caller; `nil` means plain text
    /// (editor R13: a missing grammar or query is logged at `debug`, never shown).
    ///
    /// Compiling a grammar's queries takes up to a second (Swift, measured 1.06 s on the main
    /// thread, M6 6.5): it happens off the main actor, the view shows plain text meanwhile.
    func attach(to textView: NSTextView, language: Language) async -> TextViewHighlighter? {
        do {
            let configuration = try await self.configuration(for: language)
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

    /// A static string colored once (markdown preview, editor R14); `nil` when the grammar is
    /// unavailable (R13).
    func highlight(_ code: String, language: Language) async -> AttributedString? {
        guard let configuration = try? await configuration(for: language) else { return nil }
        guard
            var string = try? await TreeSitterClient.highlight(
                string: code, attributeProvider: { [theme] token in theme.attributes(forCapture: token.name) },
                rootLanguageConfig: configuration, languageProvider: { _ in nil })
        else { return nil }
        // Neon sets AppKit colors; SwiftUI's `Text` reads its own.
        for run in string.runs {
            if let color = run.appKit.foregroundColor {
                string[run.range].swiftUI.foregroundColor = Color(nsColor: color)
            }
        }
        return string
    }

    private func configuration(for language: Language) async throws -> LanguageConfiguration {
        if let task = configurations[language] {
            return try await task.value
        }
        let task = Task { try await Self.build(language) }
        configurations[language] = task
        do {
            return try await task.value
        } catch {
            // The next view asks again (a transient failure is not cached).
            configurations[language] = nil
            throw error
        }
    }

    /// architecture, Performance: parsing `highlights.scm` is the slow part; never on the main actor.
    @concurrent
    private static func build(_ language: Language) async throws -> LanguageConfiguration {
        let interval = Perf.signposter.beginInterval("highlight.configure", id: Perf.signposter.makeSignpostID())
        defer { Perf.signposter.endInterval("highlight.configure", interval) }
        return try language.makeConfiguration()
    }
}
