import AppKit
import SwiftUI
import UniformTypeIdentifiers

protocol FileManagerSidebarDropPreflightInfo {
    func hasItemsConforming(to contentTypes: [UTType]) -> Bool
}

protocol FileManagerSidebarDropPerformInfo {
    func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider]
}

extension DropInfo: FileManagerSidebarDropPreflightInfo, FileManagerSidebarDropPerformInfo {}

struct FileManagerSidebarEntryDropDelegate: DropDelegate {
    @Binding var dropTarget: FileManagerSidebarEntryDropTarget?

    let target: FileManagerSidebarEntryDropTarget
    let allowsCopy: Bool
    let onDrop: (FileManagerSidebarEntryDropRequest) -> Void

    init(
        dropTarget: Binding<FileManagerSidebarEntryDropTarget?>,
        target: FileManagerSidebarEntryDropTarget,
        allowsCopy: Bool = true,
        onDrop: @escaping (FileManagerSidebarEntryDropRequest) -> Void,
    ) {
        _dropTarget = dropTarget
        self.target = target
        self.allowsCopy = allowsCopy
        self.onDrop = onDrop
    }

    static func target(
        for item: ContentTabProjection.ContentTabSidebarItem,
    ) -> FileManagerSidebarEntryDropTarget? {
        guard item.pageType == .directory else { return nil }
        return .contentTab(item.id)
    }

    static func proposalOperation(
        hasFileURLItems: Bool,
        isOptionDrag: Bool,
        allowsCopy: Bool = true,
    ) -> DropOperation {
        guard hasFileURLItems else {
            return .forbidden
        }
        return isOptionDrag && allowsCopy ? .copy : .move
    }

    func validateDrop(info: DropInfo) -> Bool {
        validateDrop(dropInfo: info)
    }

    func validateDrop(dropInfo: some FileManagerSidebarDropPreflightInfo) -> Bool {
        let isAccepted = acceptsCandidate(dropInfo: dropInfo)
        if !isAccepted {
            clearDropTarget()
        }
        return isAccepted
    }

    func dropEntered(info: DropInfo) {
        dropEntered(dropInfo: info)
    }

    func dropEntered(dropInfo: some FileManagerSidebarDropPreflightInfo) {
        if acceptsCandidate(dropInfo: dropInfo) {
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
        dropInfo: some FileManagerSidebarDropPreflightInfo,
        isOptionDrag: Bool,
    ) -> DropProposal? {
        let operation = Self.proposalOperation(
            hasFileURLItems: acceptsCandidate(dropInfo: dropInfo),
            isOptionDrag: isOptionDrag,
            allowsCopy: allowsCopy,
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
        dropInfo: some FileManagerSidebarDropPerformInfo,
        isOptionDrag: Bool,
    ) -> Bool {
        let providers = dropInfo.itemProviders(for: [.item])
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

    private func acceptsCandidate(
        dropInfo: some FileManagerSidebarDropPreflightInfo,
    ) -> Bool {
        let hasFileURLItems = dropInfo.hasItemsConforming(to: [.fileURL])
        let hasReorderItems = dropInfo.hasItemsConforming(to: [.fileManagerTopNavigationReorder])
        return hasFileURLItems && !hasReorderItems
    }

    private func clearDropTarget() {
        if dropTarget == target {
            dropTarget = nil
        }
    }
}
