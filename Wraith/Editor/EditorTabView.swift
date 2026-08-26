import AppKit
import SwiftUI

/// The content of an `editor.file` tab: banners, then the text, or why there is none.
struct EditorTabView: View {
    let tab: EditorTab
    let theme: ThemeService
    let highlighter: Highlighter

    var body: some View {
        VStack(spacing: 0) {
            switch tab.content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text(let document):
                banners(for: document)
                EditorTextView(tab: tab, document: document, theme: theme, highlighter: highlighter)
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.description, systemImage: "doc.questionmark")
                } actions: {
                    // editor R15: a binary is not opened; the Finder is one click away.
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([tab.url])
                    }
                }
            }
        }
        .task(id: tab.url) {
            await tab.load()
        }
    }

    @ViewBuilder
    private func banners(for document: FileDocument) -> some View {
        if document.isReadOnly {
            // editor R16 and edge cases: over 2 MB or without write permission.
            banner(
                document.bytes > FileDocument.readOnlyThreshold
                    ? "Large file: read-only, no highlighting" : "Read-only: no write permission",
                icon: "lock")
        }
        if document.encoding == .latin1 {
            banner("Not UTF-8: read as Latin-1, will be saved as UTF-8", icon: "textformat.abc")
        }
    }

    private func banner(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }
}
