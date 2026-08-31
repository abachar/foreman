import AppKit
import Foundation

/// Go to selector (editor R47–R49): `cmd+click` on a class or an id in an HTML file opens the
/// `.css` rule that defines it.
///
/// Deliberately not LSP — no language server makes this jump (`04-study-selectors.md`) — and it
/// shares only the arrival with R43: the same `Editor.open(…, line:)`.
extension EditorFeature {
    /// editor R48: the class or id under `location`, resolved through the index.
    ///
    /// Nothing found is **silence** (R49): with Tailwind or any utility framework almost no class
    /// is defined in a local `.css`, so a banner here would fire on nearly every click.
    func goToSelector(in tab: EditorTab, at location: Int) {
        guard let textView = tab.textView else { return }
        let html = textView.string
        Task { [weak self] in
            guard let reference = Selectors.reference(at: location, in: html), let self else { return }
            let sites = await selectors.sites(of: reference.name, kind: reference.kind)
            // editor R48: the first in walk order, no picker in v1.
            guard let site = sites.first else { return }
            open(site.url, preview: true, line: site.line)
        }
    }
}
