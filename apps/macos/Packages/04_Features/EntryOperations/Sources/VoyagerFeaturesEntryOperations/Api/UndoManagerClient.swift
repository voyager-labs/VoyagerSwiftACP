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

@MainActor
public final class FileOperationUndoManagerRegistry {
    public typealias Generation = UInt64

    private struct Entry {
        let manager: UndoManager
        var generation: Generation
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
        entries[scope] = Entry(manager: manager, generation: nextGeneration())
        return manager
    }

    public func deactivate(_ scope: UndoManagerScope) {
        guard var entry = entries[scope] else {
            return
        }

        entry.generation = nextGeneration()
        entries[scope] = entry
        entry.manager.removeAllActions()
        FileOperationUndoManagerHandlerStore.store(for: entry.manager).clear()
        objc_setAssociatedObject(
            entry.manager,
            &FileOperationUndoManagerHandlerStoreKey.value,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
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
        onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) -> Bool {
        guard let entry = entries[scope], entry.generation == expectedGeneration else {
            return false
        }

        let handler = FileOperationUndoManagerHandler(
            registry: self,
            scope: scope,
            generation: expectedGeneration,
            undoManager: entry.manager,
            onUndo: onUndo,
            onRedo: onRedo,
        )
        FileOperationUndoManagerHandlerStore.store(for: entry.manager).add(handler)
        entry.manager.registerUndo(withTarget: handler) { target in
            target.handleUndo(record)
        }
        return true
    }

    @discardableResult
    public func requestUndo(_ scope: UndoManagerScope) -> Bool {
        guard let manager = entries[scope]?.manager, manager.canUndo else {
            return false
        }
        manager.undo()
        return true
    }

    @discardableResult
    public func requestRedo(_ scope: UndoManagerScope) -> Bool {
        guard let manager = entries[scope]?.manager, manager.canRedo else {
            return false
        }
        manager.redo()
        return true
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
    public var registerUndo: @MainActor @Sendable (
        _ scope: UndoManagerScope,
        _ expectedGeneration: Generation,
        _ record: EntryActionRecord,
        _ onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        _ onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) async -> Bool
    public var requestUndo: @MainActor @Sendable (UndoManagerScope) async -> Bool
    public var requestRedo: @MainActor @Sendable (UndoManagerScope) async -> Bool
    public var generation: @Sendable (UndoManagerScope) -> Generation?
    public var isGenerationCurrent: @MainActor @Sendable (UndoManagerScope, Generation) async -> Bool

    nonisolated public init(
        activate: @escaping @Sendable (UndoManagerScope) -> UndoManager?,
        deactivate: @escaping @Sendable (UndoManagerScope) -> Void,
        deactivateAll: @escaping @MainActor @Sendable (UUID) async -> Void,
        undoManager: @escaping @MainActor @Sendable (UndoManagerScope) async -> UndoManager?,
        registerUndo: @escaping @MainActor @Sendable (
            _ scope: UndoManagerScope,
            _ expectedGeneration: Generation,
            _ record: EntryActionRecord,
            _ onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
            _ onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
        ) async -> Bool,
        requestUndo: @escaping @MainActor @Sendable (UndoManagerScope) async -> Bool,
        requestRedo: @escaping @MainActor @Sendable (UndoManagerScope) async -> Bool,
        generation: @escaping @Sendable (UndoManagerScope) -> Generation?,
        isGenerationCurrent: @escaping @MainActor @Sendable (UndoManagerScope, Generation) async -> Bool,
    ) {
        self.activate = activate
        self.deactivate = deactivate
        self.deactivateAll = deactivateAll
        self.undoManager = undoManager
        self.registerUndo = registerUndo
        self.requestUndo = requestUndo
        self.requestRedo = requestRedo
        self.generation = generation
        self.isGenerationCurrent = isGenerationCurrent
    }
}

public extension FileOperationUndoManagerClient {
    nonisolated static func live(
        registry: FileOperationUndoManagerRegistry,
    ) -> FileOperationUndoManagerClient {
        .init(
            activate: { scope in
                if Thread.isMainThread {
                    return MainActor.assumeIsolated { registry.activate(scope) }
                }
                return DispatchQueue.main.sync { registry.activate(scope) }
            },
            deactivate: { scope in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { registry.deactivate(scope) }
                } else {
                    DispatchQueue.main.sync { registry.deactivate(scope) }
                }
            },
            deactivateAll: { registry.deactivateAll(windowID: $0) },
            undoManager: { registry.undoManager(for: $0) },
            registerUndo: { scope, expectedGeneration, record, onUndo, onRedo in
                registry.registerUndo(
                    scope,
                    expectedGeneration: expectedGeneration,
                    record: record,
                    onUndo: onUndo,
                    onRedo: onRedo,
                )
            },
            requestUndo: { registry.requestUndo($0) },
            requestRedo: { registry.requestRedo($0) },
            generation: { scope in
                if Thread.isMainThread {
                    return MainActor.assumeIsolated { registry.generation(for: scope) }
                }
                return DispatchQueue.main.sync { registry.generation(for: scope) }
            },
            isGenerationCurrent: { registry.isCurrent($0, generation: $1) },
        )
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
            registerUndo: { _, _, _, _, _ in false },
            requestUndo: { _ in false },
            requestRedo: { _ in false },
            generation: { _ in nil },
            isGenerationCurrent: { _, _ in false },
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
    private let onUndo: @Sendable (EntryActionRecord) async -> Void
    private let onRedo: @Sendable (EntryActionRecord) async -> Void

    init(
        registry: FileOperationUndoManagerRegistry,
        scope: UndoManagerScope,
        generation: FileOperationUndoManagerRegistry.Generation,
        undoManager: UndoManager,
        onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) {
        self.registry = registry
        self.scope = scope
        self.generation = generation
        self.undoManager = undoManager
        self.onUndo = onUndo
        self.onRedo = onRedo
    }

    func handleUndo(_ record: EntryActionRecord) {
        guard isCurrent, let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { target in
            target.handleRedo(record)
        }
        invokeIfCurrent(onUndo, record: record)
    }

    func handleRedo(_ record: EntryActionRecord) {
        guard isCurrent, let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: self) { target in
            target.handleUndo(record)
        }
        invokeIfCurrent(onRedo, record: record)
    }

    private var isCurrent: Bool {
        registry?.isCurrent(scope, generation: generation) == true
    }

    private func invokeIfCurrent(
        _ callback: @escaping @Sendable (EntryActionRecord) async -> Void,
        record: EntryActionRecord,
    ) {
        Task { @MainActor [weak registry, scope, generation] in
            guard registry?.isCurrent(scope, generation: generation) == true else {
                return
            }
            await callback(record)
        }
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
