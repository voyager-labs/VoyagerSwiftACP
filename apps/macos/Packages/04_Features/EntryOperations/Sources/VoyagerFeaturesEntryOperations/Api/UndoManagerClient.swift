import AppKit
import ComposableArchitecture
import ObjectiveC

public struct UndoManagerScope: Hashable, Sendable {
    public let windowID: UUID
    public let contentTabID: String

    public init(windowID: UUID, contentTabID: String) {
        self.windowID = windowID
        self.contentTabID = contentTabID
    }
}

public enum FileOperationUndoDirection: Equatable, Sendable {
    case undo
    case redo
}

public enum FileOperationUndoTransitionRejection: Equatable, Sendable {
    case missingScope
    case staleGeneration
    case unavailable
}

public enum FileOperationUndoTransitionOutcome: Equatable, Sendable {
    case applied
    case rejected(FileOperationUndoTransitionRejection)
    case invalidated
}

@MainActor
public final class FileOperationUndoManagerRegistry {
    public typealias Generation = UInt64

    private final class Entry {
        let manager: UndoManager
        var generation: Generation
        var undoRecordIDs: [UUID] = []
        var redoRecordIDs: [UUID] = []
        var pendingTransition: PendingTransition?

        init(manager: UndoManager, generation: Generation) {
            self.manager = manager
            self.generation = generation
        }
    }

    private struct PendingTransition: Equatable {
        let direction: FileOperationUndoDirection
        let recordID: UUID
        var didComplete = false
    }

    private var entries: [UndoManagerScope: Entry] = [:]
    private var generation: Generation = 0

    public init() {}

    @discardableResult
    public func activate(_ scope: UndoManagerScope) -> UndoManager {
        if let entry = entries[scope] {
            return entry.manager
        }

        let manager = UndoManager()
        manager.groupsByEvent = false
        entries[scope] = Entry(manager: manager, generation: nextGeneration())
        return manager
    }

    public func deactivate(_ scope: UndoManagerScope) {
        guard let entry = entries[scope] else { return }
        entry.generation = nextGeneration()
        clearNativeHistory(entry)
        entries.removeValue(forKey: scope)
    }

    public func deactivateAll(windowID: UUID) {
        let scopes = entries.keys
            .filter { $0.windowID == windowID }
            .sorted { $0.contentTabID < $1.contentTabID }
        for scope in scopes {
            deactivate(scope)
        }
    }

    public func undoManager(for scope: UndoManagerScope) -> UndoManager? {
        entries[scope]?.manager
    }

    public func generation(for scope: UndoManagerScope) -> Generation? {
        entries[scope]?.generation
    }

    public func isCurrent(_ scope: UndoManagerScope, generation: Generation) -> Bool {
        entries[scope]?.generation == generation
    }

    @discardableResult
    public func registerUndo(
        _ scope: UndoManagerScope,
        expectedGeneration: Generation,
        record: EntryActionRecord,
    ) -> Bool {
        guard let entry = entries[scope], entry.generation == expectedGeneration,
              entry.pendingTransition == nil
        else { return false }

        let handler = FileOperationUndoManagerHandler(
            registry: self,
            scope: scope,
            generation: expectedGeneration,
            undoManager: entry.manager,
            recordID: record.id,
        )
        FileOperationUndoManagerHandlerStore.store(for: entry.manager).add(handler)
        entry.manager.beginUndoGrouping()
        entry.manager.registerUndo(withTarget: handler) { target in
            target.handleUndo()
        }
        entry.manager.endUndoGrouping()
        entry.undoRecordIDs.append(record.id)
        entry.redoRecordIDs.removeAll()
        return true
    }

    public func performUndoRedo(
        _ scope: UndoManagerScope,
        expectedGeneration: Generation,
        direction: FileOperationUndoDirection,
        expectedRecordID: UUID,
    ) -> FileOperationUndoTransitionOutcome {
        guard let entry = entries[scope] else {
            return .rejected(.missingScope)
        }
        guard entry.generation == expectedGeneration else {
            return .rejected(.staleGeneration)
        }
        guard entry.pendingTransition == nil else {
            invalidate(entry)
            return .invalidated
        }

        let recordIDs = direction == .undo ? entry.undoRecordIDs : entry.redoRecordIDs
        let isAvailable = direction == .undo ? entry.manager.canUndo : entry.manager.canRedo
        guard recordIDs.last == expectedRecordID, isAvailable else {
            invalidate(entry)
            return .invalidated
        }

        entry.pendingTransition = PendingTransition(direction: direction, recordID: expectedRecordID)
        switch direction {
        case .undo:
            entry.manager.undo()
        case .redo:
            entry.manager.redo()
        }

        guard entry.generation == expectedGeneration else {
            return .invalidated
        }
        guard entry.pendingTransition?.didComplete == true else {
            invalidate(entry)
            return .invalidated
        }
        entry.pendingTransition = nil
        return .applied
    }

    fileprivate func completeNativeTransition(
        scope: UndoManagerScope,
        generation: Generation,
        direction: FileOperationUndoDirection,
        recordID: UUID,
        handler: FileOperationUndoManagerHandler,
    ) {
        guard let entry = entries[scope], entry.generation == generation else { return }
        guard entry.pendingTransition == PendingTransition(direction: direction, recordID: recordID) else {
            invalidate(entry)
            return
        }

        switch direction {
        case .undo:
            entry.manager.registerUndo(withTarget: handler) { target in
                target.handleRedo()
            }
            _ = entry.undoRecordIDs.popLast()
            entry.redoRecordIDs.append(recordID)
        case .redo:
            entry.manager.registerUndo(withTarget: handler) { target in
                target.handleUndo()
            }
            _ = entry.redoRecordIDs.popLast()
            entry.undoRecordIDs.append(recordID)
        }
        entry.pendingTransition?.didComplete = true
    }

    private func invalidate(_ entry: Entry) {
        clearNativeHistory(entry)
        entry.generation = nextGeneration()
    }

    private func clearNativeHistory(_ entry: Entry) {
        entry.manager.removeAllActions()
        entry.undoRecordIDs.removeAll()
        entry.redoRecordIDs.removeAll()
        entry.pendingTransition = nil
        FileOperationUndoManagerHandlerStore.store(for: entry.manager).clear()
        objc_setAssociatedObject(
            entry.manager,
            &FileOperationUndoManagerHandlerStoreKey.value,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
    }

    private func nextGeneration() -> Generation {
        precondition(generation < .max, "Undo manager generation exhausted")
        generation += 1
        return generation
    }
}

public struct FileOperationUndoManagerClient: Sendable {
    public typealias Generation = FileOperationUndoManagerRegistry.Generation

    public var activate: @Sendable (UndoManagerScope) -> UndoManager?
    public var deactivate: @Sendable (UndoManagerScope) -> Void
    public var deactivateAll: @MainActor @Sendable (UUID) async -> Void
    public var undoManager: @MainActor @Sendable (UndoManagerScope) async -> UndoManager?
    public var registerUndo: @Sendable (UndoManagerScope, Generation, EntryActionRecord) -> Bool
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
    ) {
        self.activate = activate
        self.deactivate = deactivate
        self.deactivateAll = deactivateAll
        self.undoManager = undoManager
        self.registerUndo = registerUndo
        self.performUndoRedo = performUndoRedo
        self.generation = generation
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
            deactivateAll: { registry.deactivateAll(windowID: $0) },
            undoManager: { registry.undoManager(for: $0) },
            registerUndo: { scope, expectedGeneration, record in
                withRegistry(registry) {
                    $0.registerUndo(scope, expectedGeneration: expectedGeneration, record: record)
                }
            },
            performUndoRedo: { scope, expectedGeneration, direction, expectedRecordID in
                withRegistry(registry) {
                    $0.performUndoRedo(
                        scope,
                        expectedGeneration: expectedGeneration,
                        direction: direction,
                        expectedRecordID: expectedRecordID,
                    )
                }
            },
            generation: { scope in
                withRegistry(registry) { $0.generation(for: scope) }
            },
        )
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

@MainActor
private final class FileOperationUndoManagerHandler {
    private weak var registry: FileOperationUndoManagerRegistry?
    private weak var undoManager: UndoManager?
    private let scope: UndoManagerScope
    private let generation: FileOperationUndoManagerRegistry.Generation
    private let recordID: UUID

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

private enum FileOperationUndoManagerHandlerStoreKey {
    nonisolated(unsafe) static var value = 0
}

@MainActor
private final class FileOperationUndoManagerHandlerStore {
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
}

// MARK: - Legacy window-scoped client

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
