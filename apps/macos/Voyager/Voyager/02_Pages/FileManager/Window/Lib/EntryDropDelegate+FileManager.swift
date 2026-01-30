import ComposableArchitecture
import SwiftUI

extension EntryDropDelegate {
    init(store: StoreOf<FileManagerFeature>, fsStore: StoreOf<EntriesFeature>) {
        destinationPath = store.currentPath
        onDrop = { providers, path in
            fsStore.send(.handleDrop(providers: providers, destinationPath: path))
        }
        isDropTarget = Binding(
            get: { fsStore.isDropTargeted },
            set: { fsStore.send(.setDropTargeted($0)) },
        )
        draggingPaths = fsStore.draggingPaths
    }
}
