import AppKit
import SwiftUI

/// The content of an `editor.file` tab: banners, then the text, or why there is none.
struct EditorTabView: View {
    let tab: EditorTab
    let theme: ThemeService
    let highlighter: Highlighter
    let root: URL
    /// Called on every change of `isDirty`; the feature mirrors it on the layout's tab.
    let onDirtyChange: () -> Void
    /// editor R14: a link to a workspace file opens it in Foreman.
    let onOpenFile: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch tab.content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text(let document):
                banners(for: document)
                if tab.mode == .preview {
                    MarkdownPreviewView(
                        text: tab.currentText, file: tab.url, root: root, theme: theme, highlighter: highlighter,
                        firstBlock: Bindable(tab).previewBlock, onOpenFile: onOpenFile)
                } else {
                    EditorTextView(
                        tab: tab, document: document, theme: theme, highlighter: highlighter,
                        diagnostics: tab.diagnostics)
                }
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
        .onChange(of: tab.isDirty) { _, _ in
            onDirtyChange()
        }
    }

    @ViewBuilder
    private func banners(for document: FileDocument) -> some View {
        switch tab.diskState {
        case .current:
            EmptyView()
        case .modified:
            // editor R9: the file changed on disk while this tab has unsaved changes.
            HStack {
                Label {
                    Text("Modified on disk")
                        .foregroundStyle(theme.tokens.textPrimary.color)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(theme.tokens.statusOrange.color)
                }
                Spacer()
                Button("Keep My Changes") { tab.keepChanges() }
                Button("Reload") { Task { await tab.reload() } }
            }
            .font(theme.font())
            .padding(6)
            // design R17: the same tinted band as `BannerView`, with its two actions.
            .background(theme.tokens.statusOrange.color.opacity(BannerView.tintOpacity))
            .background(theme.tokens.surfaceRaised.color)
        case .deleted:
            banner("Deleted on disk — ⌘S recreates it", icon: "trash")
        }
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
        if let message = tab.message {
            // editor R28, R30, R32: the formatter's verdict, gone at the next keystroke — and
            // R39's, which has no keystroke to wait for, so it closes by hand (2026-08-31).
            BannerView(text: message, icon: "text.alignleft", theme: theme) {
                tab.message = nil
            }
        }
    }

    private func banner(_ text: String, icon: String) -> some View {
        BannerView(text: text, icon: icon, theme: theme)
    }
}
