import AppKit
import SwiftUI

/// The content of a terminal tab: the surface, a banner when its folder is gone, and the
/// status line with `Relaunch` once the process ended (terminal R8, edge cases).
struct TerminalTabView: View {
    let id: TabID
    let service: TerminalService

    var body: some View {
        if let tab = service.tab(id) {
            content(tab)
                .onAppear {
                    // terminal R7: showing the tab clears its mark.
                    service.activated(id)
                }
        }
    }

    @ViewBuilder
    private func content(_ tab: TerminalTab) -> some View {
        VStack(spacing: 0) {
            if tab.isCwdMissing {
                banner("Folder not found: \(tab.cwd.path(percentEncoded: false))", symbol: "questionmark.folder")
            }
            // design R13: the surface's colors are the island's; the appearance is the theme's.
            TerminalSurfaceRepresentable(
                id: id, service: service, font: service.theme.editorFont, palette: service.theme.terminalPalette
            )
            // One native view per tab and per process: two terminal tabs are views of the same
            // type, SwiftUI would otherwise update the first surface instead of making the second.
            .id("\(id.uuid)-\(tab.generation)")
            .help(tab.subtitle ?? "")
            if case .exited(let exit) = tab.state {
                service.theme.tokens.separator.color.frame(height: 1)
                HStack {
                    Text("exited · \(exit.label)")
                        .font(.callout)
                        .foregroundStyle(service.theme.tokens.textSecondary.color)
                    Spacer()
                    Button("Relaunch") {
                        // Refused only for a missing folder, and the button is disabled then.
                        try? service.relaunch(id)
                    }
                    .disabled(tab.isCwdMissing)
                }
                .padding(6)
                .background(service.theme.tokens.surfaceRaised.color)
            }
        }
    }

    private func banner(_ text: String, symbol: String) -> some View {
        BannerView(text: text, icon: symbol, tone: .error, theme: service.theme)
    }
}

/// Hosts the SwiftTerm view the service keeps for the tab.
private struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let id: TabID
    let service: TerminalService
    let font: NSFont
    let palette: ThemeService.TerminalPalette

    func makeNSView(context: Context) -> NSView {
        guard let surface = service.surface(for: id) else { return NSView() }
        surface.apply(palette, font: font)
        // The surface takes the keyboard when its tab is shown (layout R25).
        DispatchQueue.main.async { [weak surface] in
            surface?.window?.makeFirstResponder(surface)
        }
        return surface
    }

    /// terminal R14: config reload or appearance change.
    func updateNSView(_ view: NSView, context: Context) {
        (view as? TerminalSurfaceView)?.apply(palette, font: font)
    }
}
