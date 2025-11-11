import SwiftUI

struct VisibleTopItemKey: PreferenceKey {
    static let defaultValue: String = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        let newValue = nextValue()

        if value.isEmpty {
            value = newValue
        }
    }
}

struct ItemPositionKey: PreferenceKey {
    typealias Value = [String: CGRect]

    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
