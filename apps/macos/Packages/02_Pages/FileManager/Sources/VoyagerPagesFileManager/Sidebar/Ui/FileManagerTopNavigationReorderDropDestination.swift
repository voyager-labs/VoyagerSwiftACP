import AppKit
import SwiftUI

struct FileManagerTopNavigationReorderDropBoundary: Equatable, Identifiable {
    let id: Int
    let owner: FileManagerTopNavigationReorderBoundaryOwner
    let anchorID: FileManagerTopNavigationItemID
    let placement: FileManagerTopNavigationReorderPlacement

    static func make(
        for itemIDs: [FileManagerTopNavigationItemID],
        owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> [Self] {
        guard let firstID = itemIDs.first else { return [] }

        return [Self(id: 0, owner: owner, anchorID: firstID, placement: .before)]
            + itemIDs.enumerated().map { index, itemID in
                Self(id: index + 1, owner: owner, anchorID: itemID, placement: .after)
            }
    }
}

struct FileManagerTopNavigationReorderDropResult: Equatable {
    let sourceID: FileManagerTopNavigationItemID
    let anchorID: FileManagerTopNavigationItemID
    let placement: FileManagerTopNavigationReorderPlacement
}

struct FileManagerTopNavigationReorderDropDestination: NSViewRepresentable {
    @Binding var activeBoundaryID: Int?

    let boundary: FileManagerTopNavigationReorderDropBoundary
    let dragScopeID: FileManagerTopNavigationReorderDragScopeID
    let sessionStore: FileManagerTopNavigationReorderLocalSessionStore
    let boundaryOwnerForItem: @MainActor (FileManagerTopNavigationItemID)
        -> FileManagerTopNavigationReorderBoundaryOwner?
    let onReorder: @MainActor (FileManagerTopNavigationReorderDropResult) -> Void
    let onDropValidationCompleted: @MainActor (Bool) -> Void

    init(
        activeBoundaryID: Binding<Int?>,
        boundary: FileManagerTopNavigationReorderDropBoundary,
        dragScopeID: FileManagerTopNavigationReorderDragScopeID,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        boundaryOwnerForItem: @escaping @MainActor (FileManagerTopNavigationItemID)
            -> FileManagerTopNavigationReorderBoundaryOwner?,
        onReorder: @escaping @MainActor (FileManagerTopNavigationReorderDropResult) -> Void,
        onDropValidationCompleted: @escaping @MainActor (Bool) -> Void = { _ in },
    ) {
        _activeBoundaryID = activeBoundaryID
        self.boundary = boundary
        self.dragScopeID = dragScopeID
        self.sessionStore = sessionStore
        self.boundaryOwnerForItem = boundaryOwnerForItem
        self.onReorder = onReorder
        self.onDropValidationCompleted = onDropValidationCompleted
    }

    func makeNSView(context _: Context) -> FileManagerTopNavigationReorderDropDestinationView {
        FileManagerTopNavigationReorderDropDestinationView(configuration: configuration)
    }

    func updateNSView(_ nsView: FileManagerTopNavigationReorderDropDestinationView, context _: Context) {
        nsView.configuration = configuration
    }

    static func dismantleNSView(_ nsView: FileManagerTopNavigationReorderDropDestinationView, coordinator _: ()) {
        nsView.dismantle()
    }

    private var configuration: FileManagerTopNavigationReorderDropDestinationConfiguration {
        FileManagerTopNavigationReorderDropDestinationConfiguration(
            activeBoundaryID: $activeBoundaryID,
            boundary: boundary,
            dragScopeID: dragScopeID,
            sessionStore: sessionStore,
            boundaryOwnerForItem: boundaryOwnerForItem,
            onReorder: onReorder,
            onDropValidationCompleted: onDropValidationCompleted,
        )
    }
}

struct FileManagerTopNavigationReorderDropDestinationConfiguration {
    let activeBoundaryID: Binding<Int?>
    let boundary: FileManagerTopNavigationReorderDropBoundary
    let dragScopeID: FileManagerTopNavigationReorderDragScopeID
    let sessionStore: FileManagerTopNavigationReorderLocalSessionStore
    let boundaryOwnerForItem: @MainActor (FileManagerTopNavigationItemID)
        -> FileManagerTopNavigationReorderBoundaryOwner?
    let onReorder: @MainActor (FileManagerTopNavigationReorderDropResult) -> Void
    let onDropValidationCompleted: @MainActor (Bool) -> Void
}

struct FileManagerTopNavigationReorderPasteboardItem {
    let types: Set<NSPasteboard.PasteboardType>

    private let dataForType: (NSPasteboard.PasteboardType) -> Data?

    init(item: NSPasteboardItem) {
        types = Set(item.types)
        dataForType = { item.data(forType: $0) }
    }

    init(
        types: Set<NSPasteboard.PasteboardType>,
        dataForType: @escaping (NSPasteboard.PasteboardType) -> Data?,
    ) {
        self.types = types
        self.dataForType = dataForType
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        dataForType(type)
    }
}

@MainActor
final class FileManagerTopNavigationReorderDropDestinationView: NSView {
    var configuration: FileManagerTopNavigationReorderDropDestinationConfiguration

    private var acceptedAdvertisedShape = false

    init(configuration: FileManagerTopNavigationReorderDropDestinationConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        registerForDraggedTypes([.fileManagerTopNavigationReorder])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        configuration.sessionStore.entry == nil ? nil : self
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(pasteboard: sender.draggingPasteboard)
    }

    override func draggingUpdated(_: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated()
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        resetAcceptedStateAndClearOwnedBoundary()
    }

    override func draggingEnded(_: any NSDraggingInfo) {
        resetAcceptedStateAndClearOwnedBoundary()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        performDrop(pasteboard: sender.draggingPasteboard)
    }

    func draggingEntered(pasteboard: NSPasteboard) -> NSDragOperation {
        draggingEntered(pasteboardItems: pasteboardItems(from: pasteboard))
    }

    func draggingEntered(pasteboardItems: [FileManagerTopNavigationReorderPasteboardItem]) -> NSDragOperation {
        updateCandidateState(pasteboardItems: pasteboardItems)
    }

    func draggingUpdated() -> NSDragOperation {
        guard acceptedAdvertisedShape,
              targetBelongsToBoundary(),
              configuration.activeBoundaryID.wrappedValue == configuration.boundary.id
        else {
            resetAcceptedStateAndClearOwnedBoundary()
            return []
        }
        return .move
    }

    func draggingExited() {
        resetAcceptedStateAndClearOwnedBoundary()
    }

    func draggingEnded() {
        resetAcceptedStateAndClearOwnedBoundary()
    }

    func dismantle() {
        resetAcceptedStateAndClearOwnedBoundary()
    }

    func performDrop(pasteboard: NSPasteboard) -> Bool {
        performDrop(pasteboardItems: pasteboardItems(from: pasteboard))
    }

    func performDrop(pasteboardItems: [FileManagerTopNavigationReorderPasteboardItem]) -> Bool {
        var isValid = false
        let advertisesReorder = Self.advertisesReorderType(pasteboardItems)
        defer {
            if !isValid, advertisesReorder {
                configuration.sessionStore.clear()
            }
            resetAcceptedStateAndClearOwnedBoundary()
            configuration.onDropValidationCompleted(isValid)
        }

        guard let payload = resolvePayload(from: pasteboardItems),
              payload.dragScopeID == configuration.dragScopeID,
              payload.dragScopeID.boundaryOwner == configuration.boundary.owner,
              payload.sourceID != configuration.boundary.anchorID,
              configuration.boundaryOwnerForItem(payload.sourceID) == configuration.boundary.owner,
              targetBelongsToBoundary()
        else {
            return false
        }

        configuration.onReorder(FileManagerTopNavigationReorderDropResult(
            sourceID: payload.sourceID,
            anchorID: configuration.boundary.anchorID,
            placement: configuration.boundary.placement,
        ))
        isValid = true
        return true
    }

    private func pasteboardItems(from pasteboard: NSPasteboard) -> [FileManagerTopNavigationReorderPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map(FileManagerTopNavigationReorderPasteboardItem.init(item:))
    }

    private func targetBelongsToBoundary() -> Bool {
        configuration.boundaryOwnerForItem(configuration.boundary.anchorID) == configuration.boundary.owner
    }

    private func resolvePayload(
        from items: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> FileManagerTopNavigationReorderDragPayload? {
        guard items.count == 1, let item = items.first else { return nil }

        let types = item.types
        guard types.contains(.fileManagerTopNavigationReorder) else { return nil }

        if types.contains(.fileManagerTopNavigationReorderLocal) {
            guard types.isDisjoint(with: Self.competingSemanticTypes),
                  Self.localPasteboardTypes.contains(types),
                  let markerData = item.data(forType: .fileManagerTopNavigationReorderLocal),
                  let token = FileManagerTopNavigationReorderLocalToken(data: markerData)
            else {
                return nil
            }
            return configuration.sessionStore.consume(token: token)
        }

        guard types == [.fileManagerTopNavigationReorder],
              let payloadData = item.data(forType: .fileManagerTopNavigationReorder)
        else {
            return nil
        }
        return try? JSONDecoder().decode(FileManagerTopNavigationReorderDragPayload.self, from: payloadData)
    }

    private static let localRuntimePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        .fileManagerTopNavigationReorder,
        .fileManagerTopNavigationReorderLocal,
        .init("com.apple.NSFilePromiseItemMetaData"),
        .init("com.apple.pasteboard.NSFilePromiseID"),
        .init("com.apple.pasteboard.promised-file-content-type"),
        .init("com.apple.pasteboard.promised-file-name"),
        .init("com.apple.pasteboard.promised-file-url"),
        .init("com.apple.pasteboard.promised-suggested-file-name"),
        .init("dyn.ah62d4rv4gu8y6y4usm1044pxqzb085xyqz1hk64uqm10c6xenv61a3k"),
        .init("dyn.ah62d4rv4gu8yc6durvwwa3xmrvw1gkdusm1044pxqyuha2pxsvw0e55bsmwca7d3sbwu"),
    ]

    private static let nativePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        .fileManagerTopNavigationReorder,
        .fileManagerTopNavigationReorderLocal,
    ]

    private static let localPasteboardTypes: Set<Set<NSPasteboard.PasteboardType>> = [
        nativePasteboardTypes,
        localRuntimePasteboardTypes,
    ]

    private static let competingSemanticTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        .URL,
        .string,
        .init("public.filename"),
        .init("NSFilenamesPboardType"),
    ]

    private static func acceptsAdvertisedShape(
        _ items: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> Bool {
        guard items.count == 1, let item = items.first else { return false }
        return localPasteboardTypes.contains(item.types)
            || item.types == [.fileManagerTopNavigationReorder]
    }

    private static func advertisesReorderType(
        _ items: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> Bool {
        items.contains { $0.types.contains(.fileManagerTopNavigationReorder) }
    }

    private func updateCandidateState(
        pasteboardItems: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> NSDragOperation {
        guard targetBelongsToBoundary(), Self.acceptsAdvertisedShape(pasteboardItems) else {
            if Self.advertisesReorderType(pasteboardItems) {
                cancel()
            } else {
                resetAcceptedStateAndClearOwnedBoundary()
            }
            return []
        }
        acceptedAdvertisedShape = true
        publishActiveBoundary()
        return .move
    }

    private func publishActiveBoundary() {
        if configuration.activeBoundaryID.wrappedValue != configuration.boundary.id {
            configuration.activeBoundaryID.wrappedValue = configuration.boundary.id
        }
    }

    private func cancel() {
        configuration.sessionStore.clear()
        resetAcceptedStateAndClearOwnedBoundary()
    }

    private func resetAcceptedStateAndClearOwnedBoundary() {
        acceptedAdvertisedShape = false
        if configuration.activeBoundaryID.wrappedValue == configuration.boundary.id {
            configuration.activeBoundaryID.wrappedValue = nil
        }
    }
}
