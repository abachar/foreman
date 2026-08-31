import AppKit
import Foundation
import LanguageServerProtocol

/// The editor's half of the language servers (editor R35–R39, R43, R44): who tells them what, and
/// what `cmd+click` does with the answer.
///
/// Everything that talks to a process lives in `LSPServers` and `LSPServer`; what is here is the
/// wiring — a tab's text events forwarded, and one action.
extension EditorFeature {
    /// editor R42: how long the pointer must rest before anything is asked.
    static let hoverDelay = Duration.milliseconds(300)

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
                // editor R42: a keystroke cancels the popover, pending or shown.
                dismissHover()
                servers.changed(tab.url) { tab.textView?.string ?? tab.currentText }
            case .saved:
                servers.saved(tab.url, text: tab.currentText)
            }
        }
        tab.onCommandClick = { [weak self, weak tab] location in
            guard let self, let tab else { return }
            goToDefinition(in: tab, at: location)
        }
        // editor R42: the pointer at rest asks, any movement cancels.
        tab.onPointerMoved = { [weak self, weak tab] location in
            guard let self, let tab else { return }
            pointerMoved(to: location, in: tab)
        }
        tab.onPointerLeft = { [weak self] in self?.dismissHover() }
    }

    // MARK: - Hover (editor R41, R42)

    /// editor R42: one request in flight per tab, `hoverDelay` after the pointer came to rest.
    ///
    /// A move inside the character the popover is already about changes nothing: a server answers
    /// per position, and the pointer crosses many pixels of the same character.
    private func pointerMoved(to location: Int, in tab: EditorTab) {
        guard location != hoverLocation else { return }
        hoverLocation = location
        hoverTask?.cancel()
        hoverPopover.hide()
        hoverTask = Task { [weak self, weak tab] in
            guard (try? await Task.sleep(for: Self.hoverDelay)) != nil, let self, let tab else { return }
            await showHover(at: location, in: tab)
        }
    }

    func dismissHover() {
        hoverTask?.cancel()
        hoverTask = nil
        hoverLocation = nil
        hoverPopover.hide()
    }

    /// editor R41, R42: the diagnostic under the pointer, the server's markdown, or both.
    private func showHover(at location: Int, in tab: EditorTab) async {
        guard let textView = tab.textView as? CurrentLineTextView else { return }
        let text = textView.string as NSString
        let diagnostic = EditorDiagnostic.first(at: location, among: tab.diagnostics, in: text)
        let markdown = await lsp.hover(in: tab.url, text: text, location: location)
        guard !Task.isCancelled else { return }
        // editor R14's rule comes with the renderer: a server's markdown fetches nothing.
        var blocks: [MarkdownBlock] = []
        if let markdown {
            blocks = await MarkdownBlocks.make(markdown, file: tab.url, root: workspace.root)
        }
        guard !Task.isCancelled, diagnostic != nil || !blocks.isEmpty, textView.window?.isKeyWindow == true,
            let rect = textView.rect(forCharacterAt: location)
        else { return }
        hoverPopover.show(
            blocks: blocks, diagnostic: diagnostic, relativeTo: rect, of: textView, theme: theme,
            highlighter: highlighter)
    }

    /// editor R40, R41: a batch reaches every tab showing that file, whichever group it is in.
    ///
    /// Installed once, with the feature: the servers are the workspace's, not a tab's.
    func routeDiagnostics() {
        lsp.onDiagnostics = { [weak self] url, diagnostics in
            guard let self else { return }
            for tab in tabsShowing(url) {
                tab.diagnostics = diagnostics
            }
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
