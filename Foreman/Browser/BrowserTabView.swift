import SwiftUI
import WebKit

/// The `browser.page` tab (browser R4, R11): the page alone on the island, a floating viewport
/// switcher over it, a banner when a navigation was refused (R5).
struct BrowserTabView: View {
    let tab: BrowserTab
    let theme: ThemeService

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            if let banner = tab.banner {
                BannerView(text: banner, icon: "hand.raised", tone: .warning, theme: theme)
            }
            GeometryReader { geometry in
                // browser R11: a device size is centred on the ground and never exceeds the tab.
                let size = tab.viewport.size.map { device in
                    CGSize(
                        width: min(device.width, geometry.size.width), height: min(device.height, geometry.size.height))
                }
                WebView(tab: tab)
                    .frame(width: size?.width, height: size?.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(tokens.surfaceSunken.color)
        .overlay(alignment: .topTrailing) {
            // browser R11: the floating switcher, one button per viewport, the current one on the accent.
            HStack(spacing: 2) {
                ForEach(BrowserTab.Viewport.allCases, id: \.self) { viewport in
                    Button {
                        tab.viewport = viewport
                    } label: {
                        Image(systemName: viewport.symbol)
                            .frame(width: 26, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(tab.viewport == viewport ? tokens.accentText.color : tokens.textSecondary.color)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(tab.viewport == viewport ? tokens.accent.color : .clear)
                    )
                    .help(viewport.title)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 7).fill(tokens.surfaceRaised.color))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(tokens.separator.color, lineWidth: 1))
            .padding(10)
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
