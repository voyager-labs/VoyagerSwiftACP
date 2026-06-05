import AppKit
import ComposableArchitecture
import ObjectiveC

public struct UndoManagerClient: Sendable {
    public var registerUndo: @Sendable (
        _ windowID: UUID?,
        _ record: EntryActionRecord,
        _ onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        _ onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) async -> Void
    public var undo: @Sendable (_ windowID: UUID?) async -> Void
    public var redo: @Sendable (_ windowID: UUID?) async -> Void

    nonisolated public init(
        registerUndo: @escaping @Sendable (
            _ windowID: UUID?,
            _ record: EntryActionRecord,
            _ onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
            _ onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
        ) async -> Void,
        undo: @escaping @Sendable (_ windowID: UUID?) async -> Void,
        redo: @escaping @Sendable (_ windowID: UUID?) async -> Void,
    ) {
        self.registerUndo = registerUndo
        self.undo = undo
        self.redo = redo
    }
}

extension UndoManagerClient: DependencyKey {
    nonisolated public static var liveValue: UndoManagerClient {
        // Use `live(undoManager:)` at the composition root to inject a concrete UndoManager.
        // The default liveValue asserts to catch unconfigured usage.
        .init(
            registerUndo: { _, _, _, _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
            },
            undo: { _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
            },
            redo: { _ in
                assertionFailure(
                    "UndoManagerClient.liveValue not configured — use .live(undoManager:) at the composition root",
                )
            },
        )
    }

    nonisolated public static var testValue: UndoManagerClient {
        .init(
            registerUndo: { _, _, _, _ in
                fatalError("undoManagerClient.registerUndo test dependency is not configured")
            },
            undo: { _ in
                fatalError("undoManagerClient.undo test dependency is not configured")
            },
            redo: { _ in
                fatalError("undoManagerClient.redo test dependency is not configured")
            },
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
        .init(
            registerUndo: { windowID, record, onUndo, onRedo in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return
                }
                await MainActor.run {
                    let handlerStore = UndoManagerHandlerStore.store(for: undoManager)
                    let handler = UndoManagerHandler(
                        undoManager: undoManager,
                        onUndo: onUndo,
                        onRedo: onRedo,
                    )
                    // UndoManager가 target을 강하게 유지하지 않아 핸들러를 별도 보관한다.
                    handlerStore.add(handler)
                    undoManager.registerUndo(withTarget: handler) { target in
                        target.handleUndo(record)
                    }
                }
            },
            undo: { windowID in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return
                }
                await MainActor.run {
                    undoManager.undo()
                }
            },
            redo: { windowID in
                guard let undoManager = await resolveUndoManager(windowID) else {
                    return
                }
                await MainActor.run {
                    undoManager.redo()
                }
            },
        )
    }
}

private final class UndoManagerHandler {
    private let undoManager: UndoManager
    private let onUndo: @Sendable (EntryActionRecord) async -> Void
    private let onRedo: @Sendable (EntryActionRecord) async -> Void

    init(
        undoManager: UndoManager,
        onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) {
        self.undoManager = undoManager
        self.onUndo = onUndo
        self.onRedo = onRedo
    }

    @MainActor
    func handleUndo(_ record: EntryActionRecord) {
        undoManager.registerUndo(withTarget: self) { target in
            target.handleRedo(record)
        }
        Task {
            await onUndo(record)
        }
    }

    @MainActor
    func handleRedo(_ record: EntryActionRecord) {
        undoManager.registerUndo(withTarget: self) { target in
            target.handleUndo(record)
        }
        Task {
            await onRedo(record)
        }
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
}
