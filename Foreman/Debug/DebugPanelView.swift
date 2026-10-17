import SwiftUI

/// debug R6 (M27 27.3): the bottom slot's Debug tab — the controls, then threads and frames,
/// variables and console side by side.
struct DebugPanelView: View {
    let debug: DebugFeature
    @Bindable var model: DebugPanelModel
    let panels: PanelManager
    let theme: ThemeService
    @State private var expression = ""

    var body: some View {
        let tokens = theme.tokens
        VStack(spacing: 0) {
            PanelHeaderView(panels: panels, current: DebugFeature.panelID, theme: theme) { EmptyView() }
            controls
            tokens.separator.color.frame(height: 1)
            HSplitView {
                frames.frame(minWidth: 160, idealWidth: 280)
                variables.frame(minWidth: 160, idealWidth: 320)
                console.frame(minWidth: 200, idealWidth: 360)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        let tokens = theme.tokens
        let state = model.state
        return HStack(spacing: 4) {
            if state.canPause {
                button("pause.fill", help: "Pause", tint: tokens.statusOrange) { debug.pause() }
            } else {
                button(
                    "play.fill", help: "Continue (\u{2303}\u{2318}Y)", tint: tokens.statusGreen,
                    isEnabled: state.isPaused
                ) {
                    debug.resume(.resume)
                }
            }
            button(
                "arrow.turn.down.right", help: "Step Over (F6)", tint: tokens.textSecondary, isEnabled: state.isPaused
            ) {
                debug.resume(.stepOver)
            }
            button("arrow.down.to.line", help: "Step Into (F7)", tint: tokens.textSecondary, isEnabled: state.isPaused)
            {
                debug.resume(.stepInto)
            }
            button("arrow.up.to.line", help: "Step Out (F8)", tint: tokens.textSecondary, isEnabled: state.isPaused) {
                debug.resume(.stepOut)
            }
            button("stop.fill", help: "Stop", tint: tokens.statusRed, isEnabled: state.canStop) {
                Task { await debug.stop() }
            }
            Text([state.text, model.notice].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                .font(theme.font(.small))
                .foregroundStyle((state.isFailed ? tokens.statusRed : tokens.textSecondary).color)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    private func button(
        _ symbol: String, help: String, tint: ThemeColor, isEnabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle((isEnabled ? tint : theme.tokens.textDisabled).color)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(help)
    }

    // MARK: - Threads and frames

    private var frames: some View {
        let tokens = theme.tokens
        return Group {
            if model.threads.isEmpty {
                placeholder("No frames", "They appear when the program stops.")
            } else {
                List {
                    ForEach(model.threads) { thread in
                        DisclosureGroup(isExpanded: expansion(of: thread)) {
                            ForEach(thread.frames ?? []) { frame in
                                frameRow(frame)
                            }
                            if thread.hasMore {
                                Button("more\u{2026}") { Task { await model.loadFrames(of: thread.id) } }
                                    .buttonStyle(.link)
                            }
                        } label: {
                            Text(thread.name)
                                .font(theme.font(.body, weight: .medium))
                                .foregroundStyle(tokens.textPrimary.color)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Opening a thread asks its frames, once.
    private func expansion(of thread: DebugThread) -> Binding<Bool> {
        Binding(
            get: { model.expandedThreads.contains(thread.id) },
            set: { isOpen in
                if isOpen {
                    model.expandedThreads.insert(thread.id)
                    Task { await model.loadFrames(of: thread.id) }
                } else {
                    model.expandedThreads.remove(thread.id)
                }
            })
    }

    private func frameRow(_ frame: DebugFrame) -> some View {
        let tokens = theme.tokens
        let isSelected = model.selectedFrame == frame.id
        return Button {
            debug.select(frame)
        } label: {
            HStack(spacing: 6) {
                Text(frame.name)
                    .foregroundStyle((frame.isSelectable ? tokens.textPrimary : tokens.textDisabled).color)
                    .lineLimit(1)
                if let location = frame.location {
                    Text(location)
                        .foregroundStyle(tokens.textSecondary.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
            .background(isSelected ? tokens.surfaceRaised.color : .clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!frame.isSelectable)
        .help(frame.frame.source?.path ?? frame.name)
    }

    // MARK: - Variables

    private var variables: some View {
        Group {
            if model.scopes.isEmpty {
                placeholder("No variables", "Select a frame of a stopped program.")
            } else {
                List {
                    ForEach(model.scopes) { scope in
                        DebugVariableRow(node: scope, model: model, theme: theme)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Console

    private var console: some View {
        let tokens = theme.tokens
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.console.lines) { line in
                            Text(line.text)
                                .font(theme.codeFont(.small))
                                .foregroundStyle(color(of: line.kind).color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: model.console.lines.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            tokens.separator.color.frame(height: 1)
            TextField("Evaluate", text: $expression)
                .textFieldStyle(.plain)
                .font(theme.codeFont(.small))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .onSubmit {
                    let text = expression
                    expression = ""
                    Task { await model.evaluate(text) }
                }
        }
    }

    private func color(of kind: DebugConsole.Kind) -> ThemeColor {
        let tokens = theme.tokens
        switch kind {
        case .plain: return tokens.textPrimary
        case .error: return tokens.statusRed
        case .secondary: return tokens.textSecondary
        }
    }

    private func placeholder(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).foregroundStyle(theme.tokens.textSecondary.color)
            Text(detail).font(theme.font(.small)).foregroundStyle(theme.tokens.textDisabled.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One scope or variable: a disclosure whose children are asked when it first opens, and a
/// *more…* row below a paged one (debug R6).
///
/// `OutlineGroup` takes a `nil` children key path for a leaf, so a node whose children are not
/// asked yet would show no arrow; a recursive `DisclosureGroup` has the arrow and the hook.
private struct DebugVariableRow: View {
    @Bindable var node: DebugVariable
    let model: DebugPanelModel
    let theme: ThemeService

    var body: some View {
        if node.isExpandable {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { child in
                    DebugVariableRow(node: child, model: model, theme: theme)
                }
                if node.hasMore {
                    Button("more\u{2026}") { Task { await model.load(node) } }
                        .buttonStyle(.link)
                }
            } label: {
                label
            }
            .onChange(of: node.isExpanded) { _, isOpen in
                if isOpen { Task { await model.load(node) } }
            }
        } else {
            label
        }
    }

    private var label: some View {
        let tokens = theme.tokens
        return HStack(spacing: 6) {
            Text(node.name)
                .foregroundStyle(tokens.textPrimary.color)
            if !node.value.isEmpty {
                Text(node.value)
                    .font(theme.codeFont(.small))
                    .foregroundStyle(tokens.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let type = node.type {
                Text(type)
                    .foregroundStyle(tokens.textSecondary.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .help(node.value)
    }
}
