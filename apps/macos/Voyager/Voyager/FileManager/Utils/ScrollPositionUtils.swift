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
