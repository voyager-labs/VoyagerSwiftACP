import Foundation

public enum ClipboardOperation: Equatable, Sendable {
    case copy
    case cut
}

enum EntryActionDirection: Sendable {
    case undo
    case redo
}
