import AppKit
import CoreGraphics
import Foundation
import IdentifiedCollections
import SwiftUI

struct ItemPositionKey: PreferenceKey {
    typealias Value = [String: CGRect]

    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum LassoSelectionUtils {
    static func calculateDragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    static func detectModifierFlags() -> ModifierFlags {
        if NSEvent.modifierFlags.contains(.command) {
            return .command
        } else if NSEvent.modifierFlags.contains(.shift) {
            return .shift
        } else {
            return .none
        }
    }

    static func calculateItemsInRect(
        _ rect: CGRect,
        items: IdentifiedArrayOf<FSItem>,
        itemPositions: [String: CGRect]
    ) -> Set<String> {
        items
            .filter { item in
                let iconRect = itemPositions[item.id + "_icon"]
                let textRect = itemPositions[item.id + "_text"]
                let itemRect = itemPositions[item.id]

                if let iconRect = iconRect, rect.intersects(iconRect) {
                    return true
                }
                if let textRect = textRect, rect.intersects(textRect) {
                    return true
                }
                if let itemRect = itemRect, rect.intersects(itemRect) {
                    return true
                }
                return false
            }
            .map(\.id)
            .reduce(into: Set<String>()) { result, id in
                result.insert(id)
            }
    }

    static func calculateFinalSelection(
        itemsInLasso: Set<String>,
        initialSelected: Set<String>,
        modifierFlags: ModifierFlags
    ) -> Set<String> {
        switch modifierFlags {
        case .none:
            return itemsInLasso

        case .command:
            return initialSelected.symmetricDifference(itemsInLasso)

        case .shift:
            return initialSelected.union(itemsInLasso)
        }
    }

    static func isPointOverAnyItem(
        _ point: CGPoint,
        itemPositions: [String: CGRect]
    ) -> Bool {
        itemPositions.values.contains { rect in
            rect.contains(point)
        }
    }
}
