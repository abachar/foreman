import Foundation

/// The `browser` section of `.foreman/config.json` (browser R2): one URL, `http` or `https`.
nonisolated struct BrowserConfig: Decodable, Equatable, Sendable {
    var url: String?

    /// browser R2: the page to show, or why there is none (config R7: reported, never fatal).
    static func parse(_ section: BrowserConfig?) -> (url: URL?, warning: String?) {
        guard let text = section?.url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return (nil, nil)
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            url.host() != nil
        else {
            return (nil, "browser.url ignored: an http or https URL is expected, got \"\(text)\".")
        }
        return (url, nil)
    }
}
