import AppKit
import Observation
import WebKit

/// The window's single web page (browser R1, R3): owns the `WKWebView` and answers WebKit.
///
/// Using `WKWebView` as is (the platform): navigation, zoom, the context menu and the Web
/// Inspector are its own; this only decides what may load (R5), shows dialogs (R8) and mirrors
/// the state the chrome draws.
@Observable
@MainActor
final class BrowserTab: NSObject {
    /// browser R5: what a request may do.
    nonisolated enum Policy: Equatable, Sendable {
        case load
        /// A non-web scheme another application handles (`mailto:`, `vscode:`), once the user agrees.
        case system
        case refuse(String)
    }

    /// browser R11: the page laid out at a device width, or at the tab's full size.
    nonisolated enum Viewport: String, CaseIterable, Sendable {
        case phone
        case tablet
        case desktop

        /// Logical points of the current iPhone Pro and iPad Air (2026); `nil` = fill.
        var size: CGSize? {
            switch self {
            case .phone: return CGSize(width: 393, height: 852)
            case .tablet: return CGSize(width: 820, height: 1180)
            case .desktop: return nil
            }
        }

        var symbol: String {
            switch self {
            case .phone: return "iphone"
            case .tablet: return "ipad"
            case .desktop: return "desktopcomputer"
            }
        }

        var title: String {
            switch self {
            case .phone: return "iPhone (393 × 852)"
            case .tablet: return "iPad (820 × 1180)"
            case .desktop: return "Desktop (full size)"
            }
        }
    }

    var viewport: Viewport = .desktop
    private(set) var url: URL
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// browser R5: the last refusal, cleared by the next navigation.
    private(set) var banner: String?
    private let store: WKWebsiteDataStore
    private var observations: [NSKeyValueObservation] = []
    private var webViewStorage: WKWebView?

    init(url: URL, store: WKWebsiteDataStore) {
        self.url = url
        self.store = store
    }

    /// browser R1: the page's title, else its host.
    nonisolated static func displayTitle(_ title: String, url: URL) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url.host() ?? "Browser") : trimmed
    }

    /// browser R5: `http`/`https` load, other well-formed schemes go to the system, the rest is refused.
    ///
    /// `blob:` is the page's own content under its own origin, so it loads; a top-level `data:`
    /// navigation is the classic address-bar spoof and is refused, as the other browsers do.
    nonisolated static func policy(for url: URL) -> Policy {
        switch url.scheme?.lowercased() {
        case "http", "https", "about", "blob": return .load
        case "file": return .refuse("Local files are not shown here.")
        case "data": return .refuse("This page cannot be shown.")
        case "javascript", nil: return .refuse("This link cannot be opened.")
        default: return .system
        }
    }

    /// browser R5 (amended 2026-08-30): whether the system may be asked to open a non-web URL.
    ///
    /// Opening one launches another application, so only the top page may ask, and only because
    /// the user acted: a redirect, a script or an `iframe` navigates with `.other` and is refused.
    nonisolated static func mayOpenInSystem(isMainFrame: Bool, navigationType: WKNavigationType) -> Bool {
        guard isMainFrame else { return false }
        switch navigationType {
        case .linkActivated, .formSubmitted: return true
        default: return false
        }
    }

    /// browser R5: what the confirmation says — the scheme is what picks the application, and the
    /// rest of the URL belongs to the page, so it is shown apart and bounded.
    nonisolated static func openPrompt(for url: URL) -> (title: String, detail: String) {
        let text = url.absoluteString
        let detail = text.count > 300 ? String(text.prefix(300)) + "\u{2026}" : text
        return ("Open a \u{201C}\(url.scheme?.lowercased() ?? "")\u{201D} link in another application?", detail)
    }

    /// browser R3: created at the first show, kept for the tab's life.
    var webView: WKWebView {
        if let webViewStorage { return webViewStorage }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let view = WKWebView(frame: .zero, configuration: configuration)
        // browser R7: Safari's Web Inspector through the context menu or the Develop menu.
        view.isInspectable = true
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        observations = [
            view.observe(\.title, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.title = view.title ?? "" }
            },
            view.observe(\.url, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { if let url = view.url { self?.url = url } }
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            view.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
        ]
        webViewStorage = view
        view.load(URLRequest(url: url))
        return view
    }

    /// browser R2: a new config URL loads in place.
    func load(_ url: URL) {
        self.url = url
        banner = nil
        webViewStorage?.load(URLRequest(url: url))
    }

    func reloadOrStop() {
        if isLoading { webViewStorage?.stopLoading() } else { webViewStorage?.reload() }
    }

    func goBack() { webViewStorage?.goBack() }
    func goForward() { webViewStorage?.goForward() }

    /// browser R6: everything the private session holds, then the page again.
    func clearWebsiteData() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        webViewStorage?.reload()
    }

    /// browser R3: the web view and its process go with the tab.
    func close() {
        observations = []
        webViewStorage?.stopLoading()
        webViewStorage?.navigationDelegate = nil
        webViewStorage?.uiDelegate = nil
        webViewStorage = nil
    }

    private var window: NSWindow? {
        webViewStorage?.window ?? NSApp.keyWindow
    }
}

extension BrowserTab: WKNavigationDelegate {
    /// browser R5: the policy above, applied to every navigation.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async
        -> WKNavigationActionPolicy
    {
        guard let url = navigationAction.request.url else { return .cancel }
        switch Self.policy(for: url) {
        case .load:
            banner = nil
            return .allow
        case .system:
            // The target frame is `nil` for a new window, so the source says where the click came
            // from; a subframe must reach neither the system nor a new window it asks for.
            let isMainFrame =
                navigationAction.sourceFrame.isMainFrame && navigationAction.targetFrame?.isMainFrame != false
            guard Self.mayOpenInSystem(isMainFrame: isMainFrame, navigationType: navigationAction.navigationType)
            else {
                banner = "Only a link you click can open another application."
                return .cancel
            }
            if await confirmOpen(url) {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        case .refuse(let reason):
            banner = reason
            return .cancel
        }
    }

    /// browser R5: another application is launched only when the user says so, as Safari asks.
    private func confirmOpen(_ url: URL) async -> Bool {
        guard let window else { return false }
        let prompt = Self.openPrompt(for: url)
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.detail
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    /// browser R5: a response the page cannot show is a download — refused.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
    ) async
        -> WKNavigationResponsePolicy
    {
        guard navigationResponse.canShowMIMEType else {
            banner = "Downloads are not supported here."
            return .cancel
        }
        return .allow
    }
}

extension BrowserTab: WKUIDelegate {
    /// browser R5: `window.open` and `target=_blank` navigate in the tab (one tab, R1).
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, Self.policy(for: url) == .load {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // browser R8: the page's dialogs as sheets.

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo
    ) async {
        _ = await dialog(message, buttons: ["OK"])
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await dialog(message, buttons: ["OK", "Cancel"]) == .alertFirstButtonReturn
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        let response = await dialog(prompt, buttons: ["OK", "Cancel"], accessory: field)
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func dialog(
        _ message: String, buttons: [String], accessory: NSView? = nil
    ) async
        -> NSApplication.ModalResponse
    {
        let alert = NSAlert()
        alert.messageText = url.host() ?? "Browser"
        alert.informativeText = message
        alert.accessoryView = accessory
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        guard let window else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }
}
