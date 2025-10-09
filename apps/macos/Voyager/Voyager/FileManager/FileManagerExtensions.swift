import SwiftUI

enum FileManagerExtensions {}

struct TabManagerKey: FocusedValueKey {
    typealias Value = TabManager
}

struct ColumnVisibilityKey: FocusedValueKey {
    typealias Value = Binding<NavigationSplitViewVisibility>
}

extension FocusedValues {
    var tabManager: TabManager? {
        get { self[TabManagerKey.self] }
        set { self[TabManagerKey.self] = newValue }
    }

    var columnVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[ColumnVisibilityKey.self] }
        set { self[ColumnVisibilityKey.self] = newValue }
    }
}
