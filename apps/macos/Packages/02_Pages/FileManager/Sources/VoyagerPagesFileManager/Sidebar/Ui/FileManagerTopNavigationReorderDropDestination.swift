import AppKit
import SwiftUI

struct FileManagerTopNavigationReorderDropBoundary: Equatable, Identifiable {
    let id: Int
    let owner: FileManagerTopNavigationReorderBoundaryOwner
    let anchorID: FileManagerTopNavigationItemID
    let placement: FileManagerTopNavigationReorderPlacement
    let contentTabDomain: ContentTabDomain?

    init(
        id: Int,
        owner: FileManagerTopNavigationReorderBoundaryOwner,
        anchorID: FileManagerTopNavigationItemID,
        placement: FileManagerTopNavigationReorderPlacement,
        contentTabDomain: ContentTabDomain? = nil,
    ) {
        self.id = id
        self.owner = owner
        self.anchorID = anchorID
        self.placement = placement
        self.contentTabDomain = contentTabDomain
    }

    static func make(
        for itemIDs: [FileManagerTopNavigationItemID],
        owner: FileManagerTopNavigationReorderBoundaryOwner,
        contentTabDomain: ContentTabDomain? = nil,
    ) -> [Self] {
        guard let firstID = itemIDs.first else { return [] }

        return [
            Self(
                id: 0,
                owner: owner,
                anchorID: firstID,
                placement: .before,
                contentTabDomain: contentTabDomain,
            ),
        ]
            + itemIDs.enumerated().map { index, itemID in
                Self(
                    id: index + 1,
                    owner: owner,
                    anchorID: itemID,
                    placement: .after,
                    contentTabDomain: contentTabDomain,
                )
            }
    }

    static func empty(
        id: Int,
        owner: FileManagerTopNavigationReorderBoundaryOwner,
        domain: ContentTabDomain,
    ) -> Self {
        Self(
            id: id,
            owner: owner,
            anchorID: .contentTab(.init(rawValue: "voyager.empty-content-tab-drop.\(domain.rawValue)")),
            placement: .after,
            contentTabDomain: domain,
        )
    }

    var semanticPlacement: ContentTabPlacement? {
        guard contentTabDomain != nil else { return nil }
        if case let .contentTab(anchorID) = anchorID,
           !anchorID.rawValue.hasPrefix("voyager.empty-content-tab-drop.")
        {
            return placement == .before ? .before(anchorID) : .after(anchorID)
        }
        return .empty
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
    let targetWindowID: UUID?
    let contentTabIDsInDomain: @MainActor (ContentTabDomain) -> [ContentTabID]
    let onDomainTransition: @MainActor (ContentTabDomainTransitionRequest) -> Void
    /// 외부 창 explicit same/opposite-domain 경계 drop이 정확히 한 번 dispatch하는 typed transfer callback.
    /// preserve-domain transfer와 동일한 canonical `ContentTabMoveRequest` lifecycle으로 합쳐진다.
    let onForeignExplicitTransfer: @MainActor (
        ContentTabDragPayload, ContentTabDomain, ContentTabPlacement,
    ) -> Void
    let onDropValidationCompleted: @MainActor (Bool) -> Void

    init(
        activeBoundaryID: Binding<Int?>,
        boundary: FileManagerTopNavigationReorderDropBoundary,
        dragScopeID: FileManagerTopNavigationReorderDragScopeID,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        boundaryOwnerForItem: @escaping @MainActor (FileManagerTopNavigationItemID)
            -> FileManagerTopNavigationReorderBoundaryOwner?,
        onReorder: @escaping @MainActor (FileManagerTopNavigationReorderDropResult) -> Void,
        targetWindowID: UUID? = nil,
        contentTabIDsInDomain: @escaping @MainActor (ContentTabDomain) -> [ContentTabID] = { _ in [] },
        onDomainTransition: @escaping @MainActor (ContentTabDomainTransitionRequest) -> Void = { _ in },
        onForeignExplicitTransfer: @escaping @MainActor (
            ContentTabDragPayload, ContentTabDomain, ContentTabPlacement,
        ) -> Void = { _, _, _ in },
        onDropValidationCompleted: @escaping @MainActor (Bool) -> Void = { _ in },
    ) {
        _activeBoundaryID = activeBoundaryID
        self.boundary = boundary
        self.dragScopeID = dragScopeID
        self.sessionStore = sessionStore
        self.boundaryOwnerForItem = boundaryOwnerForItem
        self.onReorder = onReorder
        self.targetWindowID = targetWindowID
        self.contentTabIDsInDomain = contentTabIDsInDomain
        self.onDomainTransition = onDomainTransition
        self.onForeignExplicitTransfer = onForeignExplicitTransfer
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
            targetWindowID: targetWindowID,
            contentTabIDsInDomain: contentTabIDsInDomain,
            onDomainTransition: onDomainTransition,
            onForeignExplicitTransfer: onForeignExplicitTransfer,
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
    let targetWindowID: UUID?
    let contentTabIDsInDomain: @MainActor (ContentTabDomain) -> [ContentTabID]
    let onDomainTransition: @MainActor (ContentTabDomainTransitionRequest) -> Void
    let onForeignExplicitTransfer: @MainActor (
        ContentTabDragPayload, ContentTabDomain, ContentTabPlacement,
    ) -> Void
    let onDropValidationCompleted: @MainActor (Bool) -> Void

    init(
        activeBoundaryID: Binding<Int?>,
        boundary: FileManagerTopNavigationReorderDropBoundary,
        dragScopeID: FileManagerTopNavigationReorderDragScopeID,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        boundaryOwnerForItem: @escaping @MainActor (FileManagerTopNavigationItemID)
            -> FileManagerTopNavigationReorderBoundaryOwner?,
        onReorder: @escaping @MainActor (FileManagerTopNavigationReorderDropResult) -> Void,
        targetWindowID: UUID? = nil,
        contentTabIDsInDomain: @escaping @MainActor (ContentTabDomain) -> [ContentTabID] = { _ in [] },
        onDomainTransition: @escaping @MainActor (ContentTabDomainTransitionRequest) -> Void = { _ in },
        onForeignExplicitTransfer: @escaping @MainActor (
            ContentTabDragPayload, ContentTabDomain, ContentTabPlacement,
        ) -> Void = { _, _, _ in },
        onDropValidationCompleted: @escaping @MainActor (Bool) -> Void = { _ in },
    ) {
        self.activeBoundaryID = activeBoundaryID
        self.boundary = boundary
        self.dragScopeID = dragScopeID
        self.sessionStore = sessionStore
        self.boundaryOwnerForItem = boundaryOwnerForItem
        self.onReorder = onReorder
        self.targetWindowID = targetWindowID
        self.contentTabIDsInDomain = contentTabIDsInDomain
        self.onDomainTransition = onDomainTransition
        self.onForeignExplicitTransfer = onForeignExplicitTransfer
        self.onDropValidationCompleted = onDropValidationCompleted
    }
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
        // token-owned cleanup: 현재 entry가 이 drag의 token과 일치할 때만 지운다.
        // shared session store에서 broad clear는 다른 창/최신 drag token을 덮어쓰지 않도록 한다.
        let droppedLocalToken = pasteboardItems.first?.data(forType: .fileManagerTopNavigationReorderLocal)
            .flatMap(FileManagerTopNavigationReorderLocalToken.init(data:))
        defer {
            if !isValid, advertisesReorder, let droppedLocalToken {
                configuration.sessionStore.clear(token: droppedLocalToken)
            }
            resetAcceptedStateAndClearOwnedBoundary()
            configuration.onDropValidationCompleted(isValid)
        }

        // 모든 semantic dispatch는 consumed process-local token(resolved.reorder)을 요구한다.
        // foreign explicit 포함 — consume은 파괴적이므로 동일 token 재전송(replay)은 0회 dispatch된다.
        guard let resolved = resolvePayloads(from: pasteboardItems),
              let payload = resolved.reorder,
              targetBelongsToBoundary()
        else {
            return false
        }

        // 외부 창 explicit same/opposite-domain 경계 drop: consumed token 위에서 semantic route를
        // 분류한 뒤 정확히 하나의 typed transfer callback을 dispatch한다. canonical ContentTabMoveRequest
        // lifecycle으로 합쳐지므로 transfer-then-pin 두 단계를 만들지 않는다.
        if handleForeignExplicitTransfer(movePayload: resolved.move) {
            isValid = true
            return true
        }

        if handleDomainTransition(movePayload: resolved.move) {
            isValid = true
            return true
        }

        guard payload.dragScopeID == configuration.dragScopeID,
              payload.dragScopeID.boundaryOwner == configuration.boundary.owner,
              payload.sourceID != configuration.boundary.anchorID,
              configuration.boundaryOwnerForItem(payload.sourceID) == configuration.boundary.owner
        else { return false }

        configuration.onReorder(FileManagerTopNavigationReorderDropResult(
            sourceID: payload.sourceID,
            anchorID: configuration.boundary.anchorID,
            placement: configuration.boundary.placement,
        ))
        isValid = true
        return true
    }

    private func handleForeignExplicitTransfer(
        movePayload: ContentTabDragPayload?,
    ) -> Bool {
        guard let movePayload,
              let targetWindowID = configuration.targetWindowID,
              let targetDomain = configuration.boundary.contentTabDomain,
              let placement = configuration.boundary.semanticPlacement,
              movePayload.sourceWindowID != targetWindowID,
              movePayload.sourceDomain != nil,
              movePayload.operationID != nil,
              !movePayload.orderedTabIDs.isEmpty,
              Set(movePayload.orderedTabIDs).count == movePayload.orderedTabIDs.count,
              movePayload.orderedTabIDs.contains(movePayload.initiatingTabID),
              validTarget(placement: placement, domain: targetDomain)
        else { return false }

        let route = ContentTabDropRouteProjection.route(
            payload: movePayload,
            targetWindowID: targetWindowID,
            targetDomain: targetDomain,
            placement: placement,
            targetSurface: .contentTabDomain,
        )
        switch route {
        case .foreignExplicitSameDomainTransfer, .foreignExplicitOppositeDomainTransfer:
            configuration.onForeignExplicitTransfer(movePayload, targetDomain, placement)
            return true
        default:
            return false
        }
    }

    private func handleDomainTransition(
        movePayload: ContentTabDragPayload?,
    ) -> Bool {
        guard let movePayload,
              let targetWindowID = configuration.targetWindowID,
              let targetDomain = configuration.boundary.contentTabDomain,
              let sourceDomain = movePayload.sourceDomain,
              let operationID = movePayload.operationID,
              sourceDomain != targetDomain,
              let placement = configuration.boundary.semanticPlacement,
              !movePayload.orderedTabIDs.isEmpty,
              Set(movePayload.orderedTabIDs).count == movePayload.orderedTabIDs.count,
              movePayload.orderedTabIDs.contains(movePayload.initiatingTabID),
              movePayload.sourceWindowID == targetWindowID,
              validTarget(placement: placement, domain: targetDomain)
        else { return false }

        configuration.onDomainTransition(.init(
            operationID: operationID,
            sourceWindowID: movePayload.sourceWindowID,
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            initiatingTabID: movePayload.initiatingTabID,
            orderedTabIDs: movePayload.orderedTabIDs,
            placement: placement,
        ))
        return true
    }

    private func pasteboardItems(from pasteboard: NSPasteboard) -> [FileManagerTopNavigationReorderPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map(FileManagerTopNavigationReorderPasteboardItem.init(item:))
    }

    private func targetBelongsToBoundary() -> Bool {
        if let domain = configuration.boundary.contentTabDomain,
           configuration.boundary.semanticPlacement == .empty
        {
            return configuration.contentTabIDsInDomain(domain).isEmpty
        }
        return configuration.boundaryOwnerForItem(configuration.boundary.anchorID) == configuration.boundary.owner
    }

    private func validTarget(placement: ContentTabPlacement, domain: ContentTabDomain) -> Bool {
        let targetIDs = configuration.contentTabIDsInDomain(domain)
        switch placement {
        case let .before(anchorID), let .after(anchorID):
            return targetIDs.contains(anchorID)
        case .empty:
            return targetIDs.isEmpty
        }
    }

    private func resolvePayload(
        from items: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> FileManagerTopNavigationReorderDragPayload? {
        guard items.count == 1, let item = items.first else { return nil }

        let types = item.types.subtracting([.contentTabMove])
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

    private func resolvePayloads(
        from items: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> (reorder: FileManagerTopNavigationReorderDragPayload?, move: ContentTabDragPayload?)? {
        guard items.count == 1, let item = items.first else { return nil }
        let movePayload = item.data(forType: .contentTabMove).flatMap {
            try? JSONDecoder().decode(ContentTabDragPayload.self, from: $0)
        }
        return (resolvePayload(from: items), movePayload)
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
        let types = item.types.subtracting([.contentTabMove])
        return localPasteboardTypes.contains(types)
            || types == [.fileManagerTopNavigationReorder]
    }

    private static func advertisesReorderType(
        _ items: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> Bool {
        items.contains { $0.types.contains(.fileManagerTopNavigationReorder) }
    }

    private func updateCandidateState(
        pasteboardItems: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> NSDragOperation {
        guard targetBelongsToBoundary(),
              Self.acceptsAdvertisedShape(pasteboardItems),
              acceptsDragScope(pasteboardItems: pasteboardItems)
        else {
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

    private func acceptsDragScope(
        pasteboardItems: [FileManagerTopNavigationReorderPasteboardItem],
    ) -> Bool {
        guard pasteboardItems.count == 1, let item = pasteboardItems.first else { return false }
        let types = item.types.subtracting([.contentTabMove])
        // local marker가 없는 외부 창 generic drop은 preserve-domain transfer 경로가 받는다.
        guard types.contains(.fileManagerTopNavigationReorderLocal) else { return true }

        // explicit domain 경계 분류를 위해 move payload와 process-local token을 함께 decode한다.
        // token이 decode되면 process-local semantic drag임이 보장되어 Location/Entry/File URL과 구분된다.
        guard let targetWindowID = configuration.targetWindowID,
              let targetDomain = configuration.boundary.contentTabDomain,
              let moveData = item.data(forType: .contentTabMove),
              let movePayload = try? JSONDecoder().decode(ContentTabDragPayload.self, from: moveData),
              let markerData = item.data(forType: .fileManagerTopNavigationReorderLocal),
              let token = FileManagerTopNavigationReorderLocalToken(data: markerData)
        else {
            return configuration.sessionStore.entry?.payload.dragScopeID == configuration.dragScopeID
        }

        // 외부 창 explicit same/opposite-domain 경계: process-local token이 shared session store의
        // 현재 entry와 정확히 일치해야 받는다 (token UUID == operationID 불필요). mismatch/replay는 reject.
        if movePayload.sourceWindowID != targetWindowID, movePayload.sourceDomain != nil {
            return configuration.sessionStore.entry?.token == token
        }

        // 동일 창 반대 domain 전환 (기존): local session store token match가 필요하다.
        if movePayload.sourceWindowID == targetWindowID,
           movePayload.sourceDomain != nil,
           movePayload.sourceDomain != targetDomain
        {
            return configuration.sessionStore.entry?.token == token
        }

        // 동일 창 동일 domain reorder (기존): local session dragScopeID match가 필요하다.
        return configuration.sessionStore.entry?.payload.dragScopeID == configuration.dragScopeID
    }

    private func publishActiveBoundary() {
        if configuration.activeBoundaryID.wrappedValue != configuration.boundary.id {
            configuration.activeBoundaryID.wrappedValue = configuration.boundary.id
        }
    }

    private func cancel() {
        resetAcceptedStateAndClearOwnedBoundary()
    }

    private func resetAcceptedStateAndClearOwnedBoundary() {
        acceptedAdvertisedShape = false
        if configuration.activeBoundaryID.wrappedValue == configuration.boundary.id {
            configuration.activeBoundaryID.wrappedValue = nil
        }
    }
}
