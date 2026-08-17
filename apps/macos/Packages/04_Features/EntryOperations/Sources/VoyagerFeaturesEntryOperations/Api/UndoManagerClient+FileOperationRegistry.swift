import Foundation

@MainActor
final class FileOperationUndoManagerHandler {
    private weak var registry: FileOperationUndoManagerRegistry?
    private weak var undoManager: UndoManager?
    private var scope: UndoManagerScope
    private let generation: FileOperationUndoManagerRegistry.Generation
    let recordID: UUID

    init(
        registry: FileOperationUndoManagerRegistry,
        scope: UndoManagerScope,
        generation: FileOperationUndoManagerRegistry.Generation,
        undoManager: UndoManager,
        recordID: UUID,
    ) {
        self.registry = registry
        self.scope = scope
        self.generation = generation
        self.undoManager = undoManager
        self.recordID = recordID
    }

    func handleUndo() {
        complete(.undo)
    }

    func handleRedo() {
        complete(.redo)
    }

    func rebind(to scope: UndoManagerScope) {
        self.scope = scope
    }

    private func complete(_ direction: FileOperationUndoDirection) {
        guard let registry, undoManager != nil else { return }
        registry.completeNativeTransition(
            scope: scope,
            generation: generation,
            direction: direction,
            recordID: recordID,
            handler: self,
        )
    }
}

enum FileOperationUndoManagerHandlerStoreKey {
    nonisolated(unsafe) static var value = 0
}

@MainActor
final class FileOperationUndoManagerHandlerStore {
    private var handlers: [FileOperationUndoManagerHandler] = []

    static func store(for undoManager: UndoManager) -> FileOperationUndoManagerHandlerStore {
        if let store = objc_getAssociatedObject(undoManager, &FileOperationUndoManagerHandlerStoreKey.value)
            as? FileOperationUndoManagerHandlerStore
        {
            return store
        }
        let store = FileOperationUndoManagerHandlerStore()
        objc_setAssociatedObject(
            undoManager,
            &FileOperationUndoManagerHandlerStoreKey.value,
            store,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
        return store
    }

    func add(_ handler: FileOperationUndoManagerHandler) {
        handlers.append(handler)
    }

    func clear() {
        handlers.removeAll()
    }

    func removeHandlers(recordIDs: Set<UUID>) -> [FileOperationUndoManagerHandler]? {
        let matchingHandlers = handlers.filter { recordIDs.contains($0.recordID) }
        guard Set(matchingHandlers.map(\.recordID)) == recordIDs else { return nil }
        handlers.removeAll { recordIDs.contains($0.recordID) }
        return matchingHandlers
    }

    func rebind(to scope: UndoManagerScope) {
        for handler in handlers {
            handler.rebind(to: scope)
        }
    }
}

public extension FileOperationUndoManagerClient {
    nonisolated static func live(
        registry: FileOperationUndoManagerRegistry,
    ) -> FileOperationUndoManagerClient {
        .init(
            activate: { scope in
                withRegistry(registry) { $0.activate(scope) }
            },
            deactivate: { scope in
                withRegistry(registry) { $0.deactivate(scope) }
            },
            moveScope: { source, target, targetPolicy in
                withRegistry(registry) {
                    $0.moveScope(from: source, to: target, targetPolicy: targetPolicy)
                }
            },
            moveScopes: { descriptors in
                withRegistry(registry) { $0.moveScopes(descriptors) }
            },
            reconcileFailedScopeMove: { receipts, reverseOutcome in
                withRegistry(registry) {
                    $0.reconcileFailedScopeMove(receipts, reverseOutcome: reverseOutcome)
                }
            },
            deactivateAll: { registry.deactivateAll(windowID: $0) },
            undoManager: { registry.undoManager(for: $0) },
            registerUndo: { scope, expectedGeneration, record in
                liveRegisterUndo(registry, scope, expectedGeneration, record)
            },
            performUndoRedo: { scope, expectedGeneration, direction, expectedRecordID in
                livePerformUndoRedo(registry, scope, expectedGeneration, direction, expectedRecordID)
            },
            generation: { scope in
                withRegistry(registry) { $0.generation(for: scope) }
            },
            registerUndoWithOwner: { scope, expectedGeneration, ownerID, record in
                liveRegisterUndoWithOwner(registry, scope, expectedGeneration, ownerID, record)
            },
        )
    }

    nonisolated private static func liveRegisterUndo(
        _ registry: FileOperationUndoManagerRegistry,
        _ scope: UndoManagerScope,
        _ expectedGeneration: FileOperationUndoManagerRegistry.Generation,
        _ record: EntryActionRecord,
    ) -> Bool {
        withRegistry(registry) {
            $0.registerUndo(scope, expectedGeneration: expectedGeneration, record: record)
        }
    }

    nonisolated private static func livePerformUndoRedo(
        _ registry: FileOperationUndoManagerRegistry,
        _ scope: UndoManagerScope,
        _ expectedGeneration: FileOperationUndoManagerRegistry.Generation,
        _ direction: FileOperationUndoDirection,
        _ expectedRecordID: UUID,
    ) -> FileOperationUndoTransitionOutcome {
        withRegistry(registry) {
            $0.performUndoRedo(
                scope,
                expectedGeneration: expectedGeneration,
                direction: direction,
                expectedRecordID: expectedRecordID,
            )
        }
    }

    nonisolated private static func liveRegisterUndoWithOwner(
        _ registry: FileOperationUndoManagerRegistry,
        _ scope: UndoManagerScope,
        _ expectedGeneration: FileOperationUndoManagerRegistry.Generation,
        _ ownerID: UUID,
        _ record: EntryActionRecord,
    ) -> Bool {
        withRegistry(registry) {
            $0.registerUndo(
                scope,
                expectedGeneration: expectedGeneration,
                ownerID: ownerID,
                record: record,
            )
        }
    }

    nonisolated private static func withRegistry<Value: Sendable>(
        _ registry: FileOperationUndoManagerRegistry,
        operation: @MainActor @Sendable (FileOperationUndoManagerRegistry) -> Value,
    ) -> Value {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { operation(registry) }
        }
        return DispatchQueue.main.sync { operation(registry) }
    }
}

public extension UndoManagerClient {
    static func live(
        registry: FileOperationUndoManagerRegistry,
        resolveScope: @escaping @MainActor @Sendable (_ windowID: UUID) -> UndoManagerScope?,
    ) -> UndoManagerClient {
        .init(
            registerUndo: { windowID, ownerID, record in
                await MainActor.run {
                    _ = registry.registerCompatibilityUndo(
                        resolveScope(windowID),
                        ownerID: ownerID,
                        record: record,
                        windowID: windowID,
                    )
                }
            },
            events: { registry.compatibilityEvents(windowID: $0) },
            undo: { windowID, expectedTarget in
                await MainActor.run {
                    registry.performCompatibilityUndoRedo(
                        windowID.flatMap(resolveScope),
                        expectedTarget: expectedTarget,
                        direction: .undo,
                    )
                }
            },
            redo: { windowID, expectedTarget in
                await MainActor.run {
                    registry.performCompatibilityUndoRedo(
                        windowID.flatMap(resolveScope),
                        expectedTarget: expectedTarget,
                        direction: .redo,
                    )
                }
            },
            availability: { windowID in
                await MainActor.run {
                    registry.compatibilityAvailability(windowID.flatMap(resolveScope))
                }
            },
            invalidateOwner: { windowID, ownerID in
                await MainActor.run {
                    registry.invalidateCompatibilityOwner(
                        resolveScope(windowID),
                        ownerID: ownerID,
                        windowID: windowID,
                    )
                }
            },
            invalidateWindow: { windowID in
                await MainActor.run {
                    registry.invalidateCompatibilityWindow(windowID)
                }
            },
        )
    }
}
