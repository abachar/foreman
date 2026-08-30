import AppKit
import Foundation

/// A key combination in the `config` notation: `"cmd+shift+g"`, `"escape"`, `"cmd+opt+left"`.
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

    /// `opt` is the Option key (layout, decision 2026-08-26); `alt` stays accepted in `config.json`.
    private static let modifierNames: [(String, Modifiers)] = [
        ("cmd", .command), ("shift", .shift), ("opt", .option), ("alt", .option), ("ctrl", .control),
    ]

    init(key: String, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

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

    /// layout R37: what an `NSMenuItem` shows on its right.
    ///
    /// Shown, never bound: the registry's monitor takes the key event before the main menu's
    /// `performKeyEquivalent:` (checked 2026-08-30), and a menu item out of scope is disabled.
    var keyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return (Self.equivalentKeys[key] ?? key, flags)
    }

    /// The characters AppKit draws as ← → ↑ ↓ ⎋ ↩ ⇥ ␣ ⌫.
    private static let equivalentKeys: [String: String] = [
        "left": character(NSLeftArrowFunctionKey), "right": character(NSRightArrowFunctionKey),
        "up": character(NSUpArrowFunctionKey), "down": character(NSDownArrowFunctionKey),
        "escape": "\u{1B}", "return": "\r", "tab": "\t", "space": " ", "delete": "\u{8}",
    ]

    /// One of AppKit's `NS…FunctionKey` constants as the string a key equivalent takes.
    static func character(_ functionKey: Int) -> String {
        UnicodeScalar(UInt32(functionKey)).map(String.init) ?? ""
    }

    var description: String {
        let names = Self.modifierNames.filter { $0.0 != "alt" && modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "+")
    }
}
