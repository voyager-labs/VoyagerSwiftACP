import AppKit
import ComposableArchitecture
import ObjectiveC

public struct FileOperationUndoManagerClient: Sendable {
    public typealias Generation = FileOperationUndoManagerRegistry.Generation

    public var activate: @Sendable (UndoManagerScope) -> UndoManager?
    public var deactivate: @Sendable (UndoManagerScope) -> Void
    public var moveScope: @Sendable (
        UndoManagerScope,
        UndoManagerScope,
        FileOperationUndoScopeTargetPolicy,
    ) -> FileOperationUndoScopeMoveOutcome
    public var moveScopes: @Sendable (
        [FileOperationUndoScopeMoveDescriptor],
    ) -> FileOperationUndoScopesMoveOutcome
    public var reconcileFailedScopeMove: @Sendable (
        [FileOperationUndoScopeMoveReceipt],
        FileOperationUndoScopesMoveOutcome,
    ) -> FileOperationUndoScopeMoveReconciliationOutcome
    public var deactivateAll: @MainActor @Sendable (UUID) async -> Void
    public var undoManager: @MainActor @Sendable (UndoManagerScope) async -> UndoManager?
    public var registerUndo: @Sendable (UndoManagerScope, Generation, EntryActionRecord) -> Bool
    public var registerUndoWithOwner: @Sendable (
        UndoManagerScope,
        Generation,
        UUID,
        EntryActionRecord,
    ) -> Bool
    public var performUndoRedo: @Sendable (
        UndoManagerScope,
        Generation,
        FileOperationUndoDirection,
        UUID,
    ) -> FileOperationUndoTransitionOutcome
    public var generation: @Sendable (UndoManagerScope) -> Generation?

    nonisolated public init(
        activate: @escaping @Sendable (UndoManagerScope) -> UndoManager?,
        deactivate: @escaping @Sendable (UndoManagerScope) -> Void,
        moveScope: @escaping @Sendable (
            UndoManagerScope,
            UndoManagerScope,
            FileOperationUndoScopeTargetPolicy,
        ) -> FileOperationUndoScopeMoveOutcome,
        moveScopes: @escaping @Sendable (
            [FileOperationUndoScopeMoveDescriptor],
        ) -> FileOperationUndoScopesMoveOutcome,
        reconcileFailedScopeMove: @escaping @Sendable (
            [FileOperationUndoScopeMoveReceipt],
            FileOperationUndoScopesMoveOutcome,
        ) -> FileOperationUndoScopeMoveReconciliationOutcome,
        deactivateAll: @escaping @MainActor @Sendable (UUID) async -> Void,
        undoManager: @escaping @MainActor @Sendable (UndoManagerScope) async -> UndoManager?,
        registerUndo: @escaping @Sendable (UndoManagerScope, Generation, EntryActionRecord) -> Bool,
        performUndoRedo: @escaping @Sendable (
            UndoManagerScope,
            Generation,
            FileOperationUndoDirection,
            UUID,
        ) -> FileOperationUndoTransitionOutcome,
        generation: @escaping @Sendable (UndoManagerScope) -> Generation?,
        registerUndoWithOwner: (@Sendable (
            UndoManagerScope,
            Generation,
            UUID,
            EntryActionRecord,
        ) -> Bool)? = nil,
    ) {
        self.activate = activate
        self.deactivate = deactivate
        self.moveScope = moveScope
        self.moveScopes = moveScopes
        self.reconcileFailedScopeMove = reconcileFailedScopeMove
        self.deactivateAll = deactivateAll
        self.undoManager = undoManager
        self.registerUndo = registerUndo
        self.registerUndoWithOwner = registerUndoWithOwner ?? { scope, generation, _, record in
            registerUndo(scope, generation, record)
        }
        self.performUndoRedo = performUndoRedo
        self.generation = generation
    }
}

extension FileOperationUndoManagerClient: DependencyKey {
    nonisolated public static var liveValue: FileOperationUndoManagerClient {
        failClosed
    }

    nonisolated public static var testValue: FileOperationUndoManagerClient {
        failClosed
    }

    nonisolated private static var failClosed: FileOperationUndoManagerClient {
        .init(
            activate: { _ in nil },
            deactivate: { _ in },
            moveScope: { _, _, _ in .sourceMissing },
            moveScopes: { descriptors in
                guard let first = descriptors.first else { return .emptyBatch }
                return .sourceMissing(first.source)
            },
            reconcileFailedScopeMove: { _, reverseOutcome in .historyLost(reverseOutcome) },
            deactivateAll: { _ in },
            undoManager: { _ in nil },
            registerUndo: { _, _, _ in false },
            performUndoRedo: { _, _, _, _ in .rejected(.missingScope) },
            generation: { _ in nil },
        )
    }
}

public extension DependencyValues {
    nonisolated var fileOperationUndoManagerClient: FileOperationUndoManagerClient {
        get { self[FileOperationUndoManagerClient.self] }
        set { self[FileOperationUndoManagerClient.self] = newValue }
    }
}

// MARK: - Legacy window-scoped client

public struct UndoManagerClient: Sendable {
    public var registerUndo: @Sendable (
        _ windowID: UUID,
        _ ownerID: UUID,
        _ record: EntryActionRecord,
    ) async -> Void
    public var events: @Sendable (_ windowID: UUID) -> AsyncStream<UndoManagerEvent>
    private var undoHandler: @Sendable (
        _ windowID: UUID?,
        _ expectedTarget: UndoManagerRecordIdentity?,
    ) async -> UndoManagerInvocationResult
    private var redoHandler: @Sendable (
        _ windowID: UUID?,
        _ expectedTarget: UndoManagerRecordIdentity?,
    ) async -> UndoManagerInvocationResult
    public var availability: @Sendable (_ windowID: UUID?) async -> UndoManagerAvailability
    public var invalidateOwner: @Sendable (
        _ windowID: UUID,
        _ ownerID: UUID,
    ) async -> UndoManagerInvalidationResult
    public var invalidateWindow: @Sendable (_ windowID: UUID) async -> UndoManagerInvalidationResult

    nonisolated public init(
        registerUndo: @escaping @Sendable (
            _ windowID: UUID,
            _ ownerID: UUID,
            _ record: EntryActionRecord,
        ) async -> Void,
        events: @escaping @Sendable (_ windowID: UUID) -> AsyncStream<UndoManagerEvent> = { _ in
            AsyncStream { $0.finish() }
        },
        undo: @escaping @Sendable (
            _ windowID: UUID?,
            _ expectedTarget: UndoManagerRecordIdentity?,
        ) async -> UndoManagerInvocationResult,
        redo: @escaping @Sendable (
            _ windowID: UUID?,
            _ expectedTarget: UndoManagerRecordIdentity?,
        ) async -> UndoManagerInvocationResult,
        availability: @escaping @Sendable (_ windowID: UUID?) async -> UndoManagerAvailability = { _ in .init() },
        invalidateOwner: @escaping @Sendable (
            _ windowID: UUID,
            _ ownerID: UUID,
        ) async -> UndoManagerInvalidationResult = { _, _ in
            .init(succeeded: true, availability: .init())
        },
        invalidateWindow: @escaping @Sendable (_ windowID: UUID) async -> UndoManagerInvalidationResult = { _ in
            .init(succeeded: true, availability: .init())
        },
    ) {
        self.registerUndo = registerUndo
        self.events = events
        undoHandler = undo
        redoHandler = redo
        self.availability = availability
        self.invalidateOwner = invalidateOwner
        self.invalidateWindow = invalidateWindow
    }

    public func undo(
        _ windowID: UUID?,
        expectedTarget: UndoManagerRecordIdentity? = nil,
    ) async -> UndoManagerInvocationResult {
        await undoHandler(windowID, expectedTarget)
    }

    public func redo(
        _ windowID: UUID?,
        expectedTarget: UndoManagerRecordIdentity? = nil,
    ) async -> UndoManagerInvocationResult {
        await redoHandler(windowID, expectedTarget)
    }
}

extension UndoManagerClient: DependencyKey {
    nonisolated public static var liveValue: UndoManagerClient {
        .init(
            registerUndo: { _, _, _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
            },
            undo: { _, _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
                return .init(didInvoke: false, availability: .init())
            },
            redo: { _, _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
                return .init(didInvoke: false, availability: .init())
            },
            availability: { _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
                return .init()
            },
        )
    }

    nonisolated public static var testValue: UndoManagerClient {
        .init(
            registerUndo: { _, _, _ in
                fatalError("undoManagerClient.registerUndo test dependency is not configured")
            },
            undo: { _, _ in
                fatalError("undoManagerClient.undo test dependency is not configured")
            },
            redo: { _, _ in
                fatalError("undoManagerClient.redo test dependency is not configured")
            },
            availability: { _ in .init() },
        )
    }

    nonisolated public static var previewValue: UndoManagerClient {
        .init(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            availability: { _ in .init() },
        )
    }
}

public extension DependencyValues {
    nonisolated var undoManagerClient: UndoManagerClient {
        get { self[UndoManagerClient.self] }
        set { self[UndoManagerClient.self] = newValue }
    }
}

public extension UndoManagerClient {
    static func live(undoManager: UndoManager) -> UndoManagerClient {
        live(resolveUndoManager: { _ in undoManager })
    }

    static func live(
        resolveUndoManager: @escaping @Sendable (_ windowID: UUID?) async -> UndoManager?,
    ) -> UndoManagerClient {
        let eventBridge = UndoManagerEventBridge()
        return .init(
            registerUndo: { windowID, ownerID, record in
                await registerLegacyUndo(
                    windowID: windowID,
                    ownerID: ownerID,
                    record: record,
                    resolveUndoManager: resolveUndoManager,
                    eventBridge: eventBridge,
                )
            },
            events: { eventBridge.stream(windowID: $0) },
            undo: { windowID, expectedTarget in
                await invokeLegacyUndoManager(
                    windowID: windowID,
                    expectedTarget: expectedTarget,
                    direction: .undo,
                    resolveUndoManager: resolveUndoManager,
                )
            },
            redo: { windowID, expectedTarget in
                await invokeLegacyUndoManager(
                    windowID: windowID,
                    expectedTarget: expectedTarget,
                    direction: .redo,
                    resolveUndoManager: resolveUndoManager,
                )
            },
            availability: { windowID in
                await legacyUndoManagerAvailability(
                    windowID: windowID,
                    resolveUndoManager: resolveUndoManager,
                )
            },
            invalidateOwner: { windowID, ownerID in
                await invalidateLegacyUndoOwner(
                    windowID: windowID,
                    ownerID: ownerID,
                    resolveUndoManager: resolveUndoManager,
                )
            },
            invalidateWindow: { windowID in
                await invalidateLegacyUndoWindow(
                    windowID: windowID,
                    resolveUndoManager: resolveUndoManager,
                    eventBridge: eventBridge,
                )
            },
        )
    }
}

private enum UndoManagerInvocationDirection {
    case undo
    case redo
}

private func registerLegacyUndo(
    windowID: UUID,
    ownerID: UUID,
    record: EntryActionRecord,
    resolveUndoManager: @escaping @Sendable (_ windowID: UUID?) async -> UndoManager?,
    eventBridge: UndoManagerEventBridge,
) async {
    guard let undoManager = await resolveUndoManager(windowID) else {
        return
    }
    await MainActor.run {
        let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
        guard handlerStore.canRegister(windowID: windowID, ownerID: ownerID) else {
            return
        }
        let handler = UndoManagerHandler(
            undoManager: undoManager,
            windowID: windowID,
            ownerID: ownerID,
            eventBridge: eventBridge,
            handlerStore: handlerStore,
        )
        handlerStore.add(handler)
        undoManager.registerUndo(withTarget: handler) { target in
            target.handleUndo(record)
        }
        handlerStore.didRegister(
            windowID: windowID,
            identity: .init(ownerID: ownerID, recordID: record.id),
        )
    }
}

private func invokeLegacyUndoManager(
    windowID: UUID?,
    expectedTarget: UndoManagerRecordIdentity?,
    direction: UndoManagerInvocationDirection,
    resolveUndoManager: @escaping @Sendable (_ windowID: UUID?) async -> UndoManager?,
) async -> UndoManagerInvocationResult {
    guard let undoManager = await resolveUndoManager(windowID) else {
        return .init(didInvoke: false, availability: .init())
    }
    return await MainActor.run {
        let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
        let targetMatches = switch direction {
        case .undo:
            undoManager.canUndo && handlerStore.undoTarget(windowID: windowID) == expectedTarget
        case .redo:
            undoManager.canRedo && handlerStore.redoTarget(windowID: windowID) == expectedTarget
        }
        guard expectedTarget != nil, targetMatches else {
            return .init(
                didInvoke: false,
                availability: makeAvailability(
                    undoManager: undoManager,
                    handlerStore: handlerStore,
                    windowID: windowID,
                ),
            )
        }
        switch direction {
        case .undo:
            undoManager.undo()
        case .redo:
            undoManager.redo()
        }
        return .init(
            didInvoke: true,
            availability: makeAvailability(
                undoManager: undoManager,
                handlerStore: handlerStore,
                windowID: windowID,
            ),
        )
    }
}

private func legacyUndoManagerAvailability(
    windowID: UUID?,
    resolveUndoManager: @escaping @Sendable (_ windowID: UUID?) async -> UndoManager?,
) async -> UndoManagerAvailability {
    guard let undoManager = await resolveUndoManager(windowID) else {
        return .init()
    }
    return await MainActor.run {
        makeAvailability(
            undoManager: undoManager,
            handlerStore: UndoManagerHandlerStore.store(for: undoManager),
            windowID: windowID,
        )
    }
}

private func invalidateLegacyUndoOwner(
    windowID: UUID,
    ownerID: UUID,
    resolveUndoManager: @escaping @Sendable (_ windowID: UUID?) async -> UndoManager?,
) async -> UndoManagerInvalidationResult {
    guard let undoManager = await resolveUndoManager(windowID) else {
        return .init(succeeded: false, availability: .init())
    }
    return await MainActor.run {
        let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
        let handlers = handlerStore.invalidateOwner(windowID: windowID, ownerID: ownerID)
        for handler in handlers {
            undoManager.removeAllActions(withTarget: handler)
        }
        return .init(
            succeeded: true,
            availability: makeAvailability(
                undoManager: undoManager,
                handlerStore: handlerStore,
                windowID: windowID,
            ),
        )
    }
}

private func invalidateLegacyUndoWindow(
    windowID: UUID,
    resolveUndoManager: @escaping @Sendable (_ windowID: UUID?) async -> UndoManager?,
    eventBridge: UndoManagerEventBridge,
) async -> UndoManagerInvalidationResult {
    guard let undoManager = await resolveUndoManager(windowID) else {
        return .init(succeeded: false, availability: .init())
    }
    return await MainActor.run {
        let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
        let handlers = handlerStore.invalidateWindow(windowID: windowID)
        for handler in handlers {
            undoManager.removeAllActions(withTarget: handler)
        }
        eventBridge.finish(windowID: windowID)
        return .init(
            succeeded: true,
            availability: makeAvailability(
                undoManager: undoManager,
                handlerStore: handlerStore,
                windowID: windowID,
            ),
        )
    }
}

@MainActor
private func makeAvailability(
    undoManager: UndoManager,
    handlerStore: UndoManagerHandlerStore,
    windowID: UUID?,
) -> UndoManagerAvailability {
    UndoManagerAvailability(
        canUndo: undoManager.canUndo,
        canRedo: undoManager.canRedo,
        undoTarget: undoManager.canUndo ? handlerStore.undoTarget(windowID: windowID) : nil,
        redoTarget: undoManager.canRedo ? handlerStore.redoTarget(windowID: windowID) : nil,
    )
}

final class UndoManagerEventBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: [UUID: AsyncStream<UndoManagerEvent>.Continuation]] = [:]
    private var finishedWindowIDs: Set<UUID> = []

    func stream(windowID: UUID) -> AsyncStream<UndoManagerEvent> {
        let continuationID = UUID()
        return AsyncStream { continuation in
            lock.lock()
            let isFinished = finishedWindowIDs.contains(windowID)
            if !isFinished {
                continuations[windowID, default: [:]][continuationID] = continuation
            }
            lock.unlock()
            if isFinished {
                continuation.finish()
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(windowID: windowID, continuationID: continuationID)
            }
        }
    }

    func yield(_ event: UndoManagerEvent, windowID: UUID) {
        lock.lock()
        guard !finishedWindowIDs.contains(windowID) else {
            lock.unlock()
            return
        }
        let currentContinuations = Array(continuations[windowID]?.values ?? [:].values)
        lock.unlock()
        for continuation in currentContinuations {
            continuation.yield(event)
        }
    }

    func finish(windowID: UUID) {
        lock.lock()
        finishedWindowIDs.insert(windowID)
        let currentContinuations = Array(continuations.removeValue(forKey: windowID)?.values ?? [:].values)
        lock.unlock()
        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(windowID: UUID, continuationID: UUID) {
        lock.lock()
        continuations[windowID]?[continuationID] = nil
        if continuations[windowID]?.isEmpty == true {
            continuations[windowID] = nil
        }
        lock.unlock()
    }
}

private final class UndoManagerHandler {
    let windowID: UUID
    let ownerID: UUID
    private let undoManager: UndoManager
    private let eventBridge: UndoManagerEventBridge
    private let handlerStore: UndoManagerHandlerStore

    init(
        undoManager: UndoManager,
        windowID: UUID,
        ownerID: UUID,
        eventBridge: UndoManagerEventBridge,
        handlerStore: UndoManagerHandlerStore,
    ) {
        self.undoManager = undoManager
        self.windowID = windowID
        self.ownerID = ownerID
        self.eventBridge = eventBridge
        self.handlerStore = handlerStore
    }

    @MainActor
    func handleUndo(_ record: EntryActionRecord) {
        let identity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        undoManager.registerUndo(withTarget: self) { target in
            target.handleRedo(record)
        }
        handlerStore.didUndo(windowID: windowID, identity: identity)
        eventBridge.yield(
            UndoManagerEvent(ownerID: ownerID, record: record, direction: .undo),
            windowID: windowID,
        )
    }

    @MainActor
    func handleRedo(_ record: EntryActionRecord) {
        let identity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        undoManager.registerUndo(withTarget: self) { target in
            target.handleUndo(record)
        }
        handlerStore.didRedo(windowID: windowID, identity: identity)
        eventBridge.yield(
            UndoManagerEvent(ownerID: ownerID, record: record, direction: .redo),
            windowID: windowID,
        )
    }
}

private enum UndoManagerHandlerStoreKey {
    nonisolated(unsafe) static var value = 0
}

private final class UndoManagerHandlerStore: @unchecked Sendable {
    private struct OwnerIdentity: Hashable {
        let windowID: UUID
        let ownerID: UUID
    }

    private struct StoredRecordIdentity: Equatable {
        let windowID: UUID
        let target: UndoManagerRecordIdentity
    }

    private let lock = NSLock()
    private var handlers: [UndoManagerHandler] = []
    private var undoRecords: [StoredRecordIdentity] = []
    private var redoRecords: [StoredRecordIdentity] = []
    private var invalidatedOwners: Set<OwnerIdentity> = []
    private var invalidatedWindows: Set<UUID> = []

    static func store(for undoManager: UndoManager) -> UndoManagerHandlerStore {
        if let store = objc_getAssociatedObject(undoManager, &UndoManagerHandlerStoreKey.value)
            as? UndoManagerHandlerStore
        {
            return store
        }
        let store = UndoManagerHandlerStore()
        objc_setAssociatedObject(
            undoManager,
            &UndoManagerHandlerStoreKey.value,
            store,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
        return store
    }

    func canRegister(windowID: UUID, ownerID: UUID) -> Bool {
        lock.withLock {
            !invalidatedWindows.contains(windowID)
                && !invalidatedOwners.contains(OwnerIdentity(windowID: windowID, ownerID: ownerID))
        }
    }

    func add(_ handler: UndoManagerHandler) {
        lock.withLock {
            handlers.append(handler)
        }
    }

    func didRegister(windowID: UUID, identity: UndoManagerRecordIdentity) {
        lock.withLock {
            undoRecords.append(.init(windowID: windowID, target: identity))
            redoRecords.removeAll()
        }
    }

    func didUndo(windowID: UUID, identity: UndoManagerRecordIdentity) {
        transition(
            expected: .init(windowID: windowID, target: identity),
            source: &undoRecords,
            destination: &redoRecords,
        )
    }

    func didRedo(windowID: UUID, identity: UndoManagerRecordIdentity) {
        transition(
            expected: .init(windowID: windowID, target: identity),
            source: &redoRecords,
            destination: &undoRecords,
        )
    }

    func undoTarget(windowID: UUID?) -> UndoManagerRecordIdentity? {
        lock.withLock {
            targetLocked(from: undoRecords, windowID: windowID)
        }
    }

    func redoTarget(windowID: UUID?) -> UndoManagerRecordIdentity? {
        lock.withLock {
            targetLocked(from: redoRecords, windowID: windowID)
        }
    }

    func invalidateOwner(windowID: UUID, ownerID: UUID) -> [UndoManagerHandler] {
        lock.withLock {
            invalidatedOwners.insert(OwnerIdentity(windowID: windowID, ownerID: ownerID))
            removeRecordsLocked(windowID: windowID, ownerID: ownerID)
            return removeHandlersLocked(windowID: windowID, ownerID: ownerID)
        }
    }

    func invalidateWindow(windowID: UUID) -> [UndoManagerHandler] {
        lock.withLock {
            invalidatedWindows.insert(windowID)
            removeRecordsLocked(windowID: windowID)
            return removeHandlersLocked(windowID: windowID)
        }
    }

    private func transition(
        expected: StoredRecordIdentity,
        source: inout [StoredRecordIdentity],
        destination: inout [StoredRecordIdentity],
    ) {
        lock.withLock {
            guard source.last == expected else {
                source.removeAll()
                destination.removeAll()
                return
            }
            source.removeLast()
            destination.append(expected)
        }
    }

    private func targetLocked(
        from records: [StoredRecordIdentity],
        windowID: UUID?,
    ) -> UndoManagerRecordIdentity? {
        guard let record = records.last,
              windowID == nil || record.windowID == windowID
        else { return nil }
        return record.target
    }

    private func removeRecordsLocked(windowID: UUID, ownerID: UUID? = nil) {
        undoRecords.removeAll { record in
            record.windowID == windowID && (ownerID == nil || record.target.ownerID == ownerID)
        }
        redoRecords.removeAll { record in
            record.windowID == windowID && (ownerID == nil || record.target.ownerID == ownerID)
        }
    }

    private func removeHandlersLocked(windowID: UUID, ownerID: UUID? = nil) -> [UndoManagerHandler] {
        var removed: [UndoManagerHandler] = []
        handlers.removeAll { handler in
            let matches = handler.windowID == windowID && (ownerID == nil || handler.ownerID == ownerID)
            if matches {
                removed.append(handler)
            }
            return matches
        }
        return removed
    }
}
