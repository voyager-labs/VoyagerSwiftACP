import AppKit
import ComposableArchitecture
import ObjectiveC

struct UndoManagerClient: Sendable {
    var registerUndo: @Sendable (
        _ windowID: UUID?,
        _ record: EntryActionRecord,
        _ onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        _ onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) async -> Void
    var undo: @Sendable (_ windowID: UUID?) async -> Void
    var redo: @Sendable (_ windowID: UUID?) async -> Void

    nonisolated init(
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
    nonisolated static var liveValue: UndoManagerClient {
        .init(
            registerUndo: { _, _, _, _ in
                fatalError("undoManagerClient.registerUndo live dependency is not configured")
            },
            undo: { _ in
                fatalError("undoManagerClient.undo live dependency is not configured")
            },
            redo: { _ in
                fatalError("undoManagerClient.redo live dependency is not configured")
            },
        )
    }

    nonisolated static var testValue: UndoManagerClient {
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

extension DependencyValues {
    nonisolated var undoManagerClient: UndoManagerClient {
        get { self[UndoManagerClient.self] }
        set { self[UndoManagerClient.self] = newValue }
    }
}

extension UndoManagerClient {
    static func live(undoManager: UndoManager) -> UndoManagerClient {
        .init(
            registerUndo: { _, record, onUndo, onRedo in
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
            undo: { _ in
                await MainActor.run {
                    undoManager.undo()
                }
            },
            redo: { _ in
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
    static var value = 0
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
