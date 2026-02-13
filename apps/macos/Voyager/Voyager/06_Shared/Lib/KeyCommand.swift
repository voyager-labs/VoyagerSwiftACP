import AppKit

struct KeyCommand: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: KeyModifiers
    let characters: String?
    let charactersIgnoringModifiers: String?
}

struct KeyModifiers: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let control = KeyModifiers(rawValue: 1 << 2)
    static let shift = KeyModifiers(rawValue: 1 << 3)
    static let capsLock = KeyModifiers(rawValue: 1 << 4)
    static let function = KeyModifiers(rawValue: 1 << 5)
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        if flags.contains(.function) { result.insert(.function) }
        self = result
    }
}
