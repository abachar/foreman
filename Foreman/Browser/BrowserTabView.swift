import SwiftUI
import WebKit

/// The `browser.page` tab (browser R4): a flat chrome on the island, the page below, a banner
/// when a navigation was refused (R5).
struct BrowserTabView: View {
    let tab: BrowserTab
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    tab.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!tab.canGoBack)
                Button {
                    tab.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!tab.canGoForward)
                Button {
                    tab.reloadOrStop()
                } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                }
                .help(tab.isLoading ? "Stop" : "Reload (cmd+shift+r)")
                // browser R4: the URL is the config's; shown, selectable, not editable.
                Text(tab.url.absoluteString)
                    .font(theme.font(.small))
                    .foregroundStyle(tokens.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if tab.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(tokens.textPrimary.color)
            .padding(.horizontal, 8)
            .frame(height: tokens.barHeight)
            .background(tokens.surfaceRaised.color)
            tokens.separator.color.frame(height: 1)
            if let banner = tab.banner {
                BannerView(text: banner, icon: "hand.raised", tone: .warning, theme: theme)
            }
            WebView(tab: tab)
        }
    }
}

/// The `WKWebView` the tab owns, placed in the SwiftUI tree; rebuilt views reuse it (R3).
private struct WebView: NSViewRepresentable {
    let tab: BrowserTab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
