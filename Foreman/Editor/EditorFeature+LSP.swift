import AppKit
import Foundation
import LanguageServerProtocol

/// The editor's half of the language servers (editor R35–R39, R43, R44): who tells them what, and
/// what `cmd+click` does with the answer.
///
/// Everything that talks to a process lives in `LSPServers` and `LSPServer`; what is here is the
/// wiring — a tab's text events forwarded, and one action.
extension EditorFeature {
    /// editor R37: a tab that just loaded, changed or was saved tells its server.
    ///
    /// `EditorTab` knows nothing of LSP: it reports what its text did and this decides what that
    /// means (architecture: the owner of the information exposes it, the consumer subscribes).
    func bindLSP(_ tab: EditorTab) {
        tab.onTextEvent = { [weak self, weak tab] event in
            guard let self, let tab else { return }
            let servers = lsp
            switch event {
            case .opened:
                servers.opened(tab.url, text: tab.currentText)
            case .changed:
                servers.changed(tab.url) { tab.textView?.string ?? tab.currentText }
            case .saved:
                servers.saved(tab.url, text: tab.currentText)
            }
        }
        tab.onCommandClick = { [weak self, weak tab] location in
            guard let self, let tab else { return }
            goToDefinition(in: tab, at: location)
        }
    }

    /// editor R43: `ctrl+cmd+j` — the same jump from the keyboard, at the caret.
    func goToDefinitionAtCursor() {
        guard let tab = activeTab, let textView = tab.textView else { return }
        goToDefinition(in: tab, at: textView.selectedRange().location)
    }

    /// editor R43, R44: the definition of the symbol at `location`, opened as a preview.
    private func goToDefinition(in tab: EditorTab, at location: Int) {
        guard let textView = tab.textView else { return }
        let text = textView.string as NSString
        let url = tab.url
        Task { [weak self, weak tab] in
            guard let servers = self?.lsp else { return }
            let definition = await servers.definition(in: url, text: text, location: location)
            guard let self, let tab else { return }
            switch definition {
            case .none:
                break
            case .found(let target, let line):
                open(target, preview: true, line: line)
            case .refused(let reason):
                tab.message = reason
            }
        }
    }
}
