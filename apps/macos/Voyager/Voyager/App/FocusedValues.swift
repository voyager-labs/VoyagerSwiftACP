import ComposableArchitecture
import SwiftUI

struct FileManagerStoreKey: FocusedValueKey {
    typealias Value = StoreOf<FileManagerFeature>
}

extension FocusedValues {
    var fileManagerStore: StoreOf<FileManagerFeature>? {
        get { self[FileManagerStoreKey.self] }
        set { self[FileManagerStoreKey.self] = newValue }
    }
}
