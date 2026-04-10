import AppKit
import Foundation

public struct Tag: Equatable, Sendable, Hashable {
    public let name: String
    public let colorCode: Int
    public var tagColor: TagColor { TagColor(colorCode: colorCode) }
    public var color: NSColor { tagColor.nsColor }

    public nonisolated init(name: String, colorCode: Int) {
        self.name = name
        self.colorCode = colorCode
    }
}
