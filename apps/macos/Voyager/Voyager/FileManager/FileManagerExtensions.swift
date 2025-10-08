import SwiftUI

enum FileManagerExtensions {}

struct TabManagerKey: FocusedValueKey {
    typealias Value = TabManager
}

struct IsSidebarVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var tabManager: TabManager? {
        get { self[TabManagerKey.self] }
        set { self[TabManagerKey.self] = newValue }
    }

    var isSidebarVisible: Binding<Bool>? {
        get { self[IsSidebarVisibleKey.self] }
        set { self[IsSidebarVisibleKey.self] = newValue }
    }
}

private struct IsSidebarVisibleEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isSidebarVisible: Bool {
        get { self[IsSidebarVisibleEnvironmentKey.self] }
        set { self[IsSidebarVisibleEnvironmentKey.self] = newValue }
    }
}
