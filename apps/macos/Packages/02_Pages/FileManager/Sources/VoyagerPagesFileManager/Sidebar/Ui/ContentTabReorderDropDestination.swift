import AppKit
import SwiftUI

struct ContentTabReorderDropBoundary: Equatable, Identifiable {
    let id: Int
    let targetID: ContentTabID
    let placement: ContentTabReorderPlacement

    static func make(for itemIDs: [ContentTabID]) -> [Self] {
        guard let firstID = itemIDs.first else { return [] }

        return [Self(id: 0, targetID: firstID, placement: .before)]
            + itemIDs.enumerated().map { index, itemID in
                Self(id: index + 1, targetID: itemID, placement: .after)
            }
    }
}

struct ContentTabReorderDropDestination: NSViewRepresentable {
    @Binding var activeBoundaryID: Int?

    let boundary: ContentTabReorderDropBoundary
    let dragScopeID: ContentTabReorderDragScopeID
    let sessionStore: ContentTabReorderLocalSessionStore
    let pinState: @MainActor (ContentTabID) -> Bool?
    let onReorder: @MainActor (
        ContentTabID,
        ContentTabID,
        ContentTabReorderPlacement,
    ) -> Void
    let onDropValidationCompleted: @MainActor (Bool) -> Void

    init(
        activeBoundaryID: Binding<Int?>,
        boundary: ContentTabReorderDropBoundary,
        dragScopeID: ContentTabReorderDragScopeID,
        sessionStore: ContentTabReorderLocalSessionStore,
        pinState: @escaping @MainActor (ContentTabID) -> Bool?,
        onReorder: @escaping @MainActor (
            ContentTabID,
            ContentTabID,
            ContentTabReorderPlacement,
        ) -> Void,
        onDropValidationCompleted: @escaping @MainActor (Bool) -> Void = { _ in },
    ) {
        _activeBoundaryID = activeBoundaryID
        self.boundary = boundary
        self.dragScopeID = dragScopeID
        self.sessionStore = sessionStore
        self.pinState = pinState
        self.onReorder = onReorder
        self.onDropValidationCompleted = onDropValidationCompleted
    }

    func makeNSView(context _: Context) -> ContentTabReorderDropDestinationView {
        ContentTabReorderDropDestinationView(configuration: configuration)
    }

    func updateNSView(_ nsView: ContentTabReorderDropDestinationView, context _: Context) {
        nsView.configuration = configuration
    }

    static func dismantleNSView(_ nsView: ContentTabReorderDropDestinationView, coordinator _: ()) {
        nsView.dismantle()
    }

    private var configuration: ContentTabReorderDropDestinationConfiguration {
        ContentTabReorderDropDestinationConfiguration(
            activeBoundaryID: $activeBoundaryID,
            boundary: boundary,
            dragScopeID: dragScopeID,
            sessionStore: sessionStore,
            pinState: pinState,
            onReorder: onReorder,
            onDropValidationCompleted: onDropValidationCompleted,
        )
    }
}

struct ContentTabReorderDropDestinationConfiguration {
    let activeBoundaryID: Binding<Int?>
    let boundary: ContentTabReorderDropBoundary
    let dragScopeID: ContentTabReorderDragScopeID
    let sessionStore: ContentTabReorderLocalSessionStore
    let pinState: @MainActor (ContentTabID) -> Bool?
    let onReorder: @MainActor (
        ContentTabID,
        ContentTabID,
        ContentTabReorderPlacement,
    ) -> Void
    let onDropValidationCompleted: @MainActor (Bool) -> Void
}

struct ContentTabReorderPasteboardItem {
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
final class ContentTabReorderDropDestinationView: NSView {
    var configuration: ContentTabReorderDropDestinationConfiguration

    private var acceptedAdvertisedShape = false

    init(configuration: ContentTabReorderDropDestinationConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        registerForDraggedTypes([.contentTabReorder])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        let items = (pasteboard.pasteboardItems ?? []).map(ContentTabReorderPasteboardItem.init(item:))
        return draggingEntered(pasteboardItems: items)
    }

    func draggingEntered(pasteboardItems: [ContentTabReorderPasteboardItem]) -> NSDragOperation {
        updateCandidateState(pasteboardItems: pasteboardItems)
    }

    func draggingUpdated() -> NSDragOperation {
        guard acceptedAdvertisedShape else { return [] }
        guard configuration.pinState(configuration.boundary.targetID) == false else {
            resetAcceptedStateAndClearOwnedBoundary()
            return []
        }
        guard configuration.activeBoundaryID.wrappedValue == configuration.boundary.id else {
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
        let items = (pasteboard.pasteboardItems ?? []).map(ContentTabReorderPasteboardItem.init(item:))
        return performDrop(pasteboardItems: items)
    }

    func performDrop(pasteboardItems: [ContentTabReorderPasteboardItem]) -> Bool {
        var isValid = false
        defer {
            resetAcceptedStateAndClearOwnedBoundary()
            configuration.onDropValidationCompleted(isValid)
        }

        guard let payload = resolvePayload(from: pasteboardItems),
              payload.dragScopeID == configuration.dragScopeID,
              payload.sourceID != configuration.boundary.targetID,
              configuration.pinState(payload.sourceID) == false,
              configuration.pinState(configuration.boundary.targetID) == false
        else {
            return false
        }

        configuration.onReorder(
            payload.sourceID,
            configuration.boundary.targetID,
            configuration.boundary.placement,
        )
        isValid = true
        return true
    }

    private func resolvePayload(from items: [ContentTabReorderPasteboardItem]) -> ContentTabReorderDragPayload? {
        guard items.count == 1, let item = items.first else { return nil }

        let types = item.types
        guard types.contains(.contentTabReorder) else {
            return nil
        }

        if types.contains(.contentTabReorderLocal) {
            let markerData = item.data(forType: .contentTabReorderLocal)
            guard let markerData,
                  let token = ContentTabReorderLocalToken(data: markerData)
            else {
                return nil
            }
            guard types.isDisjoint(with: Self.competingSemanticTypes) else {
                return nil
            }
            guard types == Self.localRuntimePasteboardTypes else {
                return nil
            }
            guard let payload = configuration.sessionStore.consume(token: token) else {
                return nil
            }
            return payload
        }

        guard types == [.contentTabReorder] else {
            return nil
        }
        let payloadData = item.data(forType: .contentTabReorder)
        guard let payloadData else { return nil }
        return try? JSONDecoder().decode(ContentTabReorderDragPayload.self, from: payloadData)
    }

    private static let localRuntimePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        .contentTabReorder,
        .contentTabReorderLocal,
        .init("com.apple.NSFilePromiseItemMetaData"),
        .init("com.apple.pasteboard.NSFilePromiseID"),
        .init("com.apple.pasteboard.promised-file-content-type"),
        .init("com.apple.pasteboard.promised-file-name"),
        .init("com.apple.pasteboard.promised-file-url"),
        .init("com.apple.pasteboard.promised-suggested-file-name"),
        .init("dyn.ah62d4rv4gu8y6y4usm1044pxqzb085xyqz1hk64uqm10c6xenv61a3k"),
        .init("dyn.ah62d4rv4gu8yc6durvwwa3xmrvw1gkdusm1044pxqyuha2pxsvw0e55bsmwca7d3sbwu"),
    ]

    private static let competingSemanticTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        .URL,
        .string,
        .init("public.filename"),
        .init("NSFilenamesPboardType"),
    ]

    private static func acceptsAdvertisedShape(_ items: [ContentTabReorderPasteboardItem]) -> Bool {
        guard items.count == 1, let item = items.first else { return false }
        return item.types == localRuntimePasteboardTypes || item.types == [.contentTabReorder]
    }

    private func updateCandidateState(
        pasteboardItems: [ContentTabReorderPasteboardItem],
    ) -> NSDragOperation {
        guard configuration.pinState(configuration.boundary.targetID) == false,
              Self.acceptsAdvertisedShape(pasteboardItems)
        else {
            resetAcceptedStateAndClearOwnedBoundary()
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

    private func resetAcceptedStateAndClearOwnedBoundary() {
        acceptedAdvertisedShape = false
        if configuration.activeBoundaryID.wrappedValue == configuration.boundary.id {
            configuration.activeBoundaryID.wrappedValue = nil
        }
    }
}
