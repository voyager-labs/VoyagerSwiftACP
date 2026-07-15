import AppKit
import SwiftUI
import UniformTypeIdentifiers

protocol FileManagerSidebarEntryDropInfo {
    func hasItemsConforming(to contentTypes: [UTType]) -> Bool
    func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider]
}

extension DropInfo: FileManagerSidebarEntryDropInfo {}

struct FileManagerSidebarEntryDropDelegate: DropDelegate {
    @Binding var dropTarget: FileManagerSidebarEntryDropTarget?

    let target: FileManagerSidebarEntryDropTarget
    let onDrop: (FileManagerSidebarEntryDropRequest) -> Void

    static func target(
        for item: ContentTabProjection.ContentTabSidebarItem,
    ) -> FileManagerSidebarEntryDropTarget? {
        guard item.pageType == .directory else { return nil }
        return .contentTab(item.id)
    }

    static func proposalOperation(
        hasFileURLItems: Bool,
        isOptionDrag: Bool,
    ) -> DropOperation {
        guard hasFileURLItems else {
            return .forbidden
        }
        return isOptionDrag ? .copy : .move
    }

    func validateDrop(info: DropInfo) -> Bool {
        validateDrop(dropInfo: info)
    }

    func validateDrop(dropInfo: some FileManagerSidebarEntryDropInfo) -> Bool {
        let isAccepted = dropInfo.hasItemsConforming(to: [.fileURL])
        if !isAccepted {
            clearDropTarget()
        }
        return isAccepted
    }

    func dropEntered(info: DropInfo) {
        dropEntered(dropInfo: info)
    }

    func dropEntered(dropInfo: some FileManagerSidebarEntryDropInfo) {
        if dropInfo.hasItemsConforming(to: [.fileURL]) {
            dropTarget = target
        } else {
            clearDropTarget()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let isOptionDrag = NSEvent.modifierFlags.contains(.option)
        return dropUpdated(dropInfo: info, isOptionDrag: isOptionDrag)
    }

    func dropUpdated(
        dropInfo: some FileManagerSidebarEntryDropInfo,
        isOptionDrag: Bool,
    ) -> DropProposal? {
        let operation = Self.proposalOperation(
            hasFileURLItems: dropInfo.hasItemsConforming(to: [.fileURL]),
            isOptionDrag: isOptionDrag,
        )
        if operation == .forbidden {
            clearDropTarget()
        }
        return DropProposal(operation: operation)
    }

    func dropExited(info _: DropInfo) {
        dropExited()
    }

    func dropExited() {
        clearDropTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        let isOptionDrag = NSEvent.modifierFlags.contains(.option)
        return performDrop(dropInfo: info, isOptionDrag: isOptionDrag)
    }

    func performDrop(
        dropInfo: some FileManagerSidebarEntryDropInfo,
        isOptionDrag: Bool,
    ) -> Bool {
        let providers = dropInfo.itemProviders(for: [.fileURL])
        return performDrop(providers: providers, isOptionDrag: isOptionDrag)
    }

    func performDrop(providers: [NSItemProvider], isOptionDrag: Bool) -> Bool {
        clearDropTarget()
        guard FileManagerSidebarEntryDropClassifier.accepts(providers) else {
            return false
        }

        let request = FileManagerSidebarEntryDropRequest(
            target: target,
            providers: providers,
            isOptionDrag: isOptionDrag,
        )
        onDrop(request)
        return true
    }

    private func clearDropTarget() {
        if dropTarget == target {
            dropTarget = nil
        }
    }
}
