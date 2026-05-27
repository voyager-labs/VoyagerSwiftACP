import AppKit

public struct KeyCommand: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: KeyModifiers
    public let characters: String?
    public let charactersIgnoringModifiers: String?

    public init(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        characters: String?,
        charactersIgnoringModifiers: String?,
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }
}

public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let capsLock = KeyModifiers(rawValue: 1 << 4)
    public static let function = KeyModifiers(rawValue: 1 << 5)
}

public extension KeyModifiers {
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
