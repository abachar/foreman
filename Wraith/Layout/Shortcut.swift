import AppKit
import Foundation

/// A key combination in the `config` notation: `"cmd+shift+g"`, `"escape"`, `"cmd+alt+left"`.
nonisolated struct Shortcut: Hashable, Sendable, CustomStringConvertible {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1)
        static let shift = Modifiers(rawValue: 2)
        static let option = Modifiers(rawValue: 4)
        static let control = Modifiers(rawValue: 8)
    }

    /// Lowercase character, or one of `Shortcut.namedKeys`.
    let key: String
    let modifiers: Modifiers

    static let namedKeys: Set<String> = ["left", "right", "up", "down", "escape", "return", "tab", "space", "delete"]

    private static let modifierNames: [(String, Modifiers)] = [
        ("cmd", .command), ("shift", .shift), ("alt", .option), ("ctrl", .control),
    ]

    /// `nil` for anything that is not `modifier(+modifier)*+key` with known names.
    init?(parsing text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        guard last.count == 1 || Self.namedKeys.contains(last) else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            guard let (_, modifier) = Self.modifierNames.first(where: { $0.0 == part }), !modifiers.contains(modifier)
            else { return nil }
            modifiers.insert(modifier)
        }
        key = last
        self.modifiers = modifiers
    }

    /// The shortcut a key event stands for, or `nil` for a bare modifier or an unnamed key.
    init?(event: NSEvent) {
        guard event.type == .keyDown, let characters = event.characters(byApplyingModifiers: []),
            let scalar = characters.unicodeScalars.first
        else { return nil }
        let named: [UInt32: String] = [
            UInt32(NSLeftArrowFunctionKey): "left", UInt32(NSRightArrowFunctionKey): "right",
            UInt32(NSUpArrowFunctionKey): "up", UInt32(NSDownArrowFunctionKey): "down",
            0x1B: "escape", 0x0D: "return", 0x09: "tab", 0x20: "space", 0x7F: "delete",
        ]
        if let name = named[scalar.value] {
            key = name
        } else if characters.count == 1, !scalar.properties.isWhitespace, scalar.value >= 0x20 {
            key = characters.lowercased()
        } else {
            return nil
        }
        var modifiers: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self.modifiers = modifiers
    }

    /// layout R25: only `cmd+…` shortcuts are taken from a focused terminal.
    var requiresCommand: Bool {
        modifiers.contains(.command)
    }

    var description: String {
        let names = Self.modifierNames.filter { modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "+")
    }
}
