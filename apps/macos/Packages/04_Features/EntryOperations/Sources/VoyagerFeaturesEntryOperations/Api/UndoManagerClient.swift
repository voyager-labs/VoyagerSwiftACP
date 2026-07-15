import AppKit
import ComposableArchitecture
import ObjectiveC

public struct UndoManagerAvailability: Equatable, Sendable {
    public var canUndo: Bool
    public var canRedo: Bool

    public init(canUndo: Bool = false, canRedo: Bool = false) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

public struct UndoManagerInvocationResult: Equatable, Sendable {
    public var didInvoke: Bool
    public var availability: UndoManagerAvailability

    public init(didInvoke: Bool, availability: UndoManagerAvailability) {
        self.didInvoke = didInvoke
        self.availability = availability
    }
}

public struct UndoManagerEvent: Equatable, Sendable {
    public var ownerID: UUID
    public var record: EntryActionRecord
    public var direction: EntryActionDirection

    public init(ownerID: UUID, record: EntryActionRecord, direction: EntryActionDirection) {
        self.ownerID = ownerID
        self.record = record
        self.direction = direction
    }
}

public struct UndoManagerClient: Sendable {
    public var registerUndo: @Sendable (
        _ windowID: UUID,
        _ ownerID: UUID,
        _ record: EntryActionRecord,
    ) async -> Void
    public var events: @Sendable (_ windowID: UUID) -> AsyncStream<UndoManagerEvent>
    public var undo: @Sendable (_ windowID: UUID?) async -> UndoManagerInvocationResult
    public var redo: @Sendable (_ windowID: UUID?) async -> UndoManagerInvocationResult
    public var availability: @Sendable (_ windowID: UUID?) async -> UndoManagerAvailability
    public var invalidateOwner: @Sendable (_ windowID: UUID, _ ownerID: UUID) async -> Void
    public var invalidateWindow: @Sendable (_ windowID: UUID) async -> Void

    nonisolated public init(
        registerUndo: @escaping @Sendable (
            _ windowID: UUID,
            _ ownerID: UUID,
            _ record: EntryActionRecord,
        ) async -> Void,
        events: @escaping @Sendable (_ windowID: UUID) -> AsyncStream<UndoManagerEvent> = { _ in
            AsyncStream { $0.finish() }
        },
        undo: @escaping @Sendable (_ windowID: UUID?) async -> UndoManagerInvocationResult,
        redo: @escaping @Sendable (_ windowID: UUID?) async -> UndoManagerInvocationResult,
        availability: @escaping @Sendable (_ windowID: UUID?) async -> UndoManagerAvailability = { _ in .init() },
        invalidateOwner: @escaping @Sendable (_ windowID: UUID, _ ownerID: UUID) async -> Void = { _, _ in },
        invalidateWindow: @escaping @Sendable (_ windowID: UUID) async -> Void = { _ in },
    ) {
        self.registerUndo = registerUndo
        self.events = events
        self.undo = undo
        self.redo = redo
        self.availability = availability
        self.invalidateOwner = invalidateOwner
        self.invalidateWindow = invalidateWindow
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
            undo: { _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
                return .init(didInvoke: false, availability: .init())
            },
            redo: { _ in
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
            undo: { _ in
                fatalError("undoManagerClient.undo test dependency is not configured")
            },
            redo: { _ in
                fatalError("undoManagerClient.redo test dependency is not configured")
            },
            availability: { _ in .init() },
        )
    }

    nonisolated public static var previewValue: UndoManagerClient {
        .init(
            registerUndo: { _, _, _ in },
            undo: { _ in .init(didInvoke: false, availability: .init()) },
            redo: { _ in .init(didInvoke: false, availability: .init()) },
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
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return
                }
                await MainActor.run {
                    let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
                    let handler = UndoManagerHandler(
                        undoManager: undoManager,
                        windowID: windowID,
                        ownerID: ownerID,
                        eventBridge: eventBridge,
                    )
                    handlerStore.add(handler)
                    undoManager.registerUndo(withTarget: handler) { target in
                        target.handleUndo(record)
                    }
                }
            },
            events: { windowID in
                eventBridge.stream(windowID: windowID)
            },
            undo: { windowID in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return .init(didInvoke: false, availability: .init())
                }
                return await MainActor.run {
                    guard undoManager.canUndo else {
                        return .init(
                            didInvoke: false,
                            availability: .init(canUndo: undoManager.canUndo, canRedo: undoManager.canRedo),
                        )
                    }
                    undoManager.undo()
                    return .init(
                        didInvoke: true,
                        availability: .init(canUndo: undoManager.canUndo, canRedo: undoManager.canRedo),
                    )
                }
            },
            redo: { windowID in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return .init(didInvoke: false, availability: .init())
                }
                return await MainActor.run {
                    guard undoManager.canRedo else {
                        return .init(
                            didInvoke: false,
                            availability: .init(canUndo: undoManager.canUndo, canRedo: undoManager.canRedo),
                        )
                    }
                    undoManager.redo()
                    return .init(
                        didInvoke: true,
                        availability: .init(canUndo: undoManager.canUndo, canRedo: undoManager.canRedo),
                    )
                }
            },
            availability: { windowID in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return .init()
                }
                return await MainActor.run {
                    UndoManagerAvailability(
                        canUndo: undoManager.canUndo,
                        canRedo: undoManager.canRedo,
                    )
                }
            },
            invalidateOwner: { windowID, ownerID in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return
                }
                await MainActor.run {
                    let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
                    for handler in handlerStore.removeHandlers(windowID: windowID, ownerID: ownerID) {
                        undoManager.removeAllActions(withTarget: handler)
                    }
                }
            },
            invalidateWindow: { windowID in
                eventBridge.finish(windowID: windowID)
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return
                }
                await MainActor.run {
                    let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
                    for handler in handlerStore.removeHandlers(windowID: windowID) {
                        undoManager.removeAllActions(withTarget: handler)
                    }
                }
            },
        )
    }
}

private final class UndoManagerEventBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: [UUID: AsyncStream<UndoManagerEvent>.Continuation]] = [:]

    func stream(windowID: UUID) -> AsyncStream<UndoManagerEvent> {
        let continuationID = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuations[windowID, default: [:]][continuationID] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(windowID: windowID, continuationID: continuationID)
            }
        }
    }

    func yield(_ event: UndoManagerEvent, windowID: UUID) {
        lock.lock()
        let currentContinuations = Array(continuations[windowID]?.values ?? [:].values)
        lock.unlock()
        for continuation in currentContinuations {
            continuation.yield(event)
        }
    }

    func finish(windowID: UUID) {
        lock.lock()
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

    init(
        undoManager: UndoManager,
        windowID: UUID,
        ownerID: UUID,
        eventBridge: UndoManagerEventBridge,
    ) {
        self.undoManager = undoManager
        self.windowID = windowID
        self.ownerID = ownerID
        self.eventBridge = eventBridge
    }

    @MainActor
    func handleUndo(_ record: EntryActionRecord) {
        undoManager.registerUndo(withTarget: self) { target in
            target.handleRedo(record)
        }
        eventBridge.yield(
            UndoManagerEvent(ownerID: ownerID, record: record, direction: .undo),
            windowID: windowID,
        )
    }

    @MainActor
    func handleRedo(_ record: EntryActionRecord) {
        undoManager.registerUndo(withTarget: self) { target in
            target.handleUndo(record)
        }
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
    private let lock = NSLock()
    private var handlers: [UndoManagerHandler] = []

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

    func add(_ handler: UndoManagerHandler) {
        lock.lock()
        handlers.append(handler)
        lock.unlock()
    }

    func removeHandlers(windowID: UUID, ownerID: UUID? = nil) -> [UndoManagerHandler] {
        lock.lock()
        defer { lock.unlock() }
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
