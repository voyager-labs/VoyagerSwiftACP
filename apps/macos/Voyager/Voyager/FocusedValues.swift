import ComposableArchitecture
import SwiftUI

struct FileManagerStoreKey: FocusedValueKey {
    typealias Value = StoreOf<FileManagerFeature>
}

struct ColumnVisibilityKey: FocusedValueKey {
    typealias Value = Binding<NavigationSplitViewVisibility>
}

extension FocusedValues {
    var fileManagerStore: StoreOf<FileManagerFeature>? {
        get { self[FileManagerStoreKey.self] }
        set { self[FileManagerStoreKey.self] = newValue }
    }

    var columnVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[ColumnVisibilityKey.self] }
        set { self[ColumnVisibilityKey.self] = newValue }
    }
}
