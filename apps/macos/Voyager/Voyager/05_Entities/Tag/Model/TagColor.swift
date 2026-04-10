import AppKit
import Foundation

public enum TagColor: Int, CaseIterable, Sendable, Hashable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    nonisolated static let colorOrder: [TagColor] = [.red, .orange, .yellow, .green, .blue, .purple, .gray]
    public var colorCode: Int { rawValue }

    public var nsColor: NSColor {
        switch self {
        case .none: .systemGray
        case .gray: .systemGray
        case .green: .systemGreen
        case .purple: .systemPurple
        case .blue: .systemBlue
        case .yellow: .systemYellow
        case .red: .systemRed
        case .orange: .systemOrange
        }
    }

    public nonisolated init(colorCode: Int) {
        self = TagColor(rawValue: colorCode) ?? .none
    }

    nonisolated init(finderFavoriteSlotIndex index: Int) {
        guard Self.colorOrder.indices.contains(index) else {
            self = .none
            return
        }

        self = Self.colorOrder[index]
    }
}
