import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// FSItem 드롭 동작을 제어하는 DropDelegate
struct FSItemDropDelegate: DropDelegate {
    let destinationPath: String
    let onDrop: ([NSItemProvider], String) -> Void
    let isDropTarget: Binding<Bool>?
    let draggingPaths: [String]

    init(store: StoreOf<FileManagerFeature>, fsStore: StoreOf<FSItemsFeature>) {
        destinationPath = store.currentPath
        onDrop = { providers, path in
            fsStore.send(.handleDrop(providers: providers, destinationPath: path))
        }
        isDropTarget = Binding(
            get: { fsStore.isDropTargeted },
            set: { fsStore.send(.setDropTargeted($0)) }
        )
        draggingPaths = fsStore.draggingPaths
    }

    init(
        item: FSItem,
        onDrop: @escaping ([NSItemProvider], String) -> Void,
        isDropTarget: Binding<Bool>,
        draggingPaths: [String]
    ) {
        destinationPath = item.fullPath
        self.onDrop = onDrop
        self.isDropTarget = isDropTarget
        self.draggingPaths = draggingPaths
    }

    func dropEntered(info _: DropInfo) {
        // 드래그 중인 파일이 드롭 대상에 포함되어 있으면 하이라이트 안 함
        if draggingPaths.contains(destinationPath) {
            return
        }
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
