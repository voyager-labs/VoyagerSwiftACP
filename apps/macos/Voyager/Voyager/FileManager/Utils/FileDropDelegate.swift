import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// 범용 드롭 동작을 제어하는 DropDelegate
struct FileDropDelegate: DropDelegate {
    let destinationPath: String
    let onDrop: ([NSItemProvider], String) -> Void
    let isDropTarget: Binding<Bool>?

    init(store: StoreOf<FileManagerFeature>, fsStore: StoreOf<FSItemsFeature>) {
        destinationPath = store.currentPath
        onDrop = { providers, path in
            fsStore.send(.handleDrop(providers: providers, destinationPath: path))
        }
        isDropTarget = Binding(
            get: { fsStore.isDropTargeted },
            set: { fsStore.send(.setDropTargeted($0)) }
        )
    }

    init(item: FSItem, onDrop: @escaping ([NSItemProvider], String) -> Void, isDropTarget: Binding<Bool>) {
        destinationPath = item.fullPath
        self.onDrop = onDrop
        self.isDropTarget = isDropTarget
    }

    func dropEntered(info _: DropInfo) {
        isDropTarget?.wrappedValue = true
    }

    func dropExited(info _: DropInfo) {
        isDropTarget?.wrappedValue = false
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        let isOptionPressed = NSEvent.modifierFlags.contains(.option)
        return DropProposal(operation: isOptionPressed ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        onDrop(providers, destinationPath)
        isDropTarget?.wrappedValue = false
        return true
    }
}
