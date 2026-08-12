import AppKit
import ComposableArchitecture
import ObjectiveC

public struct UndoManagerRecordIdentity: Equatable, Hashable, Sendable {
    public var ownerID: UUID
    public var recordID: EntryActionRecord.ID

    public init(ownerID: UUID, recordID: EntryActionRecord.ID) {
        self.ownerID = ownerID
        self.recordID = recordID
    }
}

public struct UndoManagerAvailability: Equatable, Sendable {
    public var canUndo: Bool
    public var canRedo: Bool
    public var undoTarget: UndoManagerRecordIdentity?
    public var redoTarget: UndoManagerRecordIdentity?

    public init(
        canUndo: Bool = false,
        canRedo: Bool = false,
        undoTarget: UndoManagerRecordIdentity? = nil,
        redoTarget: UndoManagerRecordIdentity? = nil,
    ) {
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.undoTarget = undoTarget
        self.redoTarget = redoTarget
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

public struct UndoManagerInvalidationResult: Equatable, Sendable {
    public var succeeded: Bool
    public var availability: UndoManagerAvailability

    public init(succeeded: Bool, availability: UndoManagerAvailability) {
        self.succeeded = succeeded
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

public enum FileOperationUndoScopeMoveOutcome: Equatable, Sendable {
    case moved
    case sourceMissing
    case targetOccupied
}

public enum FileOperationUndoScopeTargetPolicy: Equatable, Sendable {
    case requireVacant
    case replaceEmpty
}

public struct FileOperationUndoScopeMoveDescriptor: Equatable, Sendable {
    public let source: UndoManagerScope
    public let target: UndoManagerScope
    public let targetPolicy: FileOperationUndoScopeTargetPolicy

    public init(
        source: UndoManagerScope,
        target: UndoManagerScope,
        targetPolicy: FileOperationUndoScopeTargetPolicy = .requireVacant,
    ) {
        self.source = source
        self.target = target
        self.targetPolicy = targetPolicy
    }
}

public enum FileOperationUndoScopesMoveOutcome: Equatable, Sendable {
    case moved
    case emptyBatch
    case duplicateSource(UndoManagerScope)
    case duplicateTarget(UndoManagerScope)
    case sourceMissing(UndoManagerScope)
    case targetOccupied(UndoManagerScope)
}

public struct FileOperationUndoScopeMoveReceipt: Equatable, Sendable {
    public let descriptor: FileOperationUndoScopeMoveDescriptor
    public let targetGeneration: UInt64?

    public init(
        descriptor: FileOperationUndoScopeMoveDescriptor,
        targetGeneration: UInt64?,
    ) {
        self.descriptor = descriptor
        self.targetGeneration = targetGeneration
    }
}

public enum FileOperationUndoScopeMoveReconciliationOutcome: Equatable, Sendable {
    case restored
    case historyLost(FileOperationUndoScopesMoveOutcome)
}

@MainActor
public final class FileOperationUndoManagerRegistry {
    public typealias Generation = UInt64

    private final class Entry {
        let manager: UndoManager
        var generation: Generation
        var undoRecordIDs: [UUID] = []
        var redoRecordIDs: [UUID] = []
        var compatibilityRecords: [UUID: CompatibilityRecord] = [:]
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

    private struct CompatibilityRecord {
        let ownerID: UUID
        let record: EntryActionRecord
    }

    private struct CompatibilityOwnerIdentity: Hashable {
        let windowID: UUID
        let ownerID: UUID
    }

    private struct PlannedScopeMove {
        let descriptor: FileOperationUndoScopeMoveDescriptor
        let entry: Entry
        let replacedTarget: Entry?
    }

    private var entries: [UndoManagerScope: Entry] = [:]
    private var generation: Generation = 0
    private var invalidatedCompatibilityOwners: Set<CompatibilityOwnerIdentity> = []
    private var invalidatedCompatibilityWindows: Set<UUID> = []
    nonisolated private let compatibilityEventBridge = UndoManagerEventBridge()

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

    public func moveScope(
        from source: UndoManagerScope,
        to target: UndoManagerScope,
        targetPolicy: FileOperationUndoScopeTargetPolicy = .requireVacant,
    ) -> FileOperationUndoScopeMoveOutcome {
        let outcome = moveScopes([
            FileOperationUndoScopeMoveDescriptor(
                source: source,
                target: target,
                targetPolicy: targetPolicy,
            ),
        ])
        switch outcome {
        case .moved:
            return .moved
        case .sourceMissing:
            return .sourceMissing
        case .emptyBatch, .duplicateSource, .duplicateTarget, .targetOccupied:
            return .targetOccupied
        }
    }

    public func moveScopes(
        _ descriptors: [FileOperationUndoScopeMoveDescriptor],
    ) -> FileOperationUndoScopesMoveOutcome {
        guard !descriptors.isEmpty else { return .emptyBatch }
        if let failure = duplicateScopeFailure(in: descriptors) {
            return failure
        }

        let originalEntries = entries
        if let failure = originalEntryFailure(in: descriptors, entries: originalEntries) {
            return failure
        }

        let plannedMoves = makePlannedMoves(descriptors, entries: originalEntries)
        precondition(plannedMoves.count == descriptors.count, "Validated Undo scope source disappeared")
        commit(plannedMoves, originalEntries: originalEntries)
        return .moved
    }

    public func reconcileFailedScopeMove(
        _ receipts: [FileOperationUndoScopeMoveReceipt],
        reverseOutcome: FileOperationUndoScopesMoveOutcome,
    ) -> FileOperationUndoScopeMoveReconciliationOutcome {
        var updatedEntries = entries
        var restoredEntries: [(scope: UndoManagerScope, entry: Entry)] = []
        var discardedEntries: [Entry] = []
        var didLoseHistory = false

        for receipt in receipts {
            let source = receipt.descriptor.source
            let target = receipt.descriptor.target
            let sourceEntry = updatedEntries[source]
            let targetEntry = updatedEntries[target]
            let targetGenerationMatches = receipt.targetGeneration.map { generation in
                targetEntry?.generation == generation
            } ?? false

            if sourceEntry == nil, targetGenerationMatches, let targetEntry {
                updatedEntries.removeValue(forKey: target)
                updatedEntries[source] = targetEntry
                restoredEntries.append((source, targetEntry))
                continue
            }

            didLoseHistory = true
            if sourceEntry == nil {
                let manager = UndoManager()
                manager.groupsByEvent = false
                updatedEntries[source] = Entry(manager: manager, generation: nextGeneration())
            }
            if targetGenerationMatches, let targetEntry {
                updatedEntries.removeValue(forKey: target)
                discardedEntries.append(targetEntry)
            }
        }

        entries = updatedEntries
        for entry in discardedEntries {
            clearNativeHistory(entry)
        }
        for restored in restoredEntries {
            FileOperationUndoManagerHandlerStore.store(for: restored.entry.manager)
                .rebind(to: restored.scope)
        }
        return didLoseHistory ? .historyLost(reverseOutcome) : .restored
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
        for recordID in entry.redoRecordIDs {
            entry.compatibilityRecords[recordID] = nil
        }
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

    func completeNativeTransition(
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

    private func duplicateScopeFailure(
        in descriptors: [FileOperationUndoScopeMoveDescriptor],
    ) -> FileOperationUndoScopesMoveOutcome? {
        var seenSources: Set<UndoManagerScope> = []
        var seenTargets: Set<UndoManagerScope> = []
        for descriptor in descriptors {
            guard seenSources.insert(descriptor.source).inserted else {
                return .duplicateSource(descriptor.source)
            }
            guard seenTargets.insert(descriptor.target).inserted else {
                return .duplicateTarget(descriptor.target)
            }
        }
        return nil
    }

    private func originalEntryFailure(
        in descriptors: [FileOperationUndoScopeMoveDescriptor],
        entries originalEntries: [UndoManagerScope: Entry],
    ) -> FileOperationUndoScopesMoveOutcome? {
        let sourceScopes = Set(descriptors.map(\.source))
        for descriptor in descriptors {
            guard originalEntries[descriptor.source] != nil else {
                return .sourceMissing(descriptor.source)
            }
            guard descriptor.source != descriptor.target else {
                return .targetOccupied(descriptor.target)
            }
            guard let targetEntry = originalEntries[descriptor.target] else { continue }
            let replacesIndependentEmptyTarget = !sourceScopes.contains(descriptor.target)
                && descriptor.targetPolicy == .replaceEmpty
                && isHistoryEmpty(targetEntry)
            guard replacesIndependentEmptyTarget else {
                return .targetOccupied(descriptor.target)
            }
        }
        return nil
    }

    private func makePlannedMoves(
        _ descriptors: [FileOperationUndoScopeMoveDescriptor],
        entries originalEntries: [UndoManagerScope: Entry],
    ) -> [PlannedScopeMove] {
        descriptors.compactMap { descriptor in
            originalEntries[descriptor.source].map { entry in
                PlannedScopeMove(
                    descriptor: descriptor,
                    entry: entry,
                    replacedTarget: originalEntries[descriptor.target],
                )
            }
        }
    }

    private func commit(
        _ plannedMoves: [PlannedScopeMove],
        originalEntries: [UndoManagerScope: Entry],
    ) {
        var updatedEntries = originalEntries
        for move in plannedMoves {
            updatedEntries.removeValue(forKey: move.descriptor.source)
            updatedEntries.removeValue(forKey: move.descriptor.target)
            updatedEntries[move.descriptor.target] = move.entry
        }
        entries = updatedEntries

        for move in plannedMoves {
            if let replacedTarget = move.replacedTarget {
                clearNativeHistory(replacedTarget)
            }
            FileOperationUndoManagerHandlerStore.store(for: move.entry.manager)
                .rebind(to: move.descriptor.target)
        }
    }

    private func isHistoryEmpty(_ entry: Entry) -> Bool {
        entry.undoRecordIDs.isEmpty
            && entry.redoRecordIDs.isEmpty
            && entry.pendingTransition == nil
            && !entry.manager.canUndo
            && !entry.manager.canRedo
    }

    private func clearNativeHistory(_ entry: Entry) {
        entry.manager.removeAllActions()
        entry.undoRecordIDs.removeAll()
        entry.redoRecordIDs.removeAll()
        entry.compatibilityRecords.removeAll()
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

    private func makeCompatibilityAvailability(_ entry: Entry) -> UndoManagerAvailability {
        let undoTarget = entry.undoRecordIDs.last.flatMap { recordID in
            entry.compatibilityRecords[recordID].map {
                UndoManagerRecordIdentity(ownerID: $0.ownerID, recordID: recordID)
            }
        }
        let redoTarget = entry.redoRecordIDs.last.flatMap { recordID in
            entry.compatibilityRecords[recordID].map {
                UndoManagerRecordIdentity(ownerID: $0.ownerID, recordID: recordID)
            }
        }
        return UndoManagerAvailability(
            canUndo: entry.manager.canUndo && undoTarget != nil,
            canRedo: entry.manager.canRedo && redoTarget != nil,
            undoTarget: undoTarget,
            redoTarget: redoTarget,
        )
    }
}

public extension FileOperationUndoManagerRegistry {
    @discardableResult
    func registerCompatibilityUndo(
        _ scope: UndoManagerScope,
        ownerID: UUID,
        record: EntryActionRecord,
    ) -> Bool {
        let ownerIdentity = CompatibilityOwnerIdentity(windowID: scope.windowID, ownerID: ownerID)
        guard !invalidatedCompatibilityWindows.contains(scope.windowID),
              !invalidatedCompatibilityOwners.contains(ownerIdentity)
        else { return false }

        let canonicalScopes: [UndoManagerScope] = entries.compactMap { candidate in
            let (candidateScope, candidateEntry) = candidate
            guard candidateScope.windowID == scope.windowID,
                  candidateEntry.undoRecordIDs.contains(record.id)
                  || candidateEntry.redoRecordIDs.contains(record.id)
            else { return nil }
            return candidateScope
        }
        guard canonicalScopes.count <= 1 else { return false }
        let registrationScope = canonicalScopes.first ?? scope
        guard let entry = entries[registrationScope], entry.pendingTransition == nil else { return false }
        let isCanonicalRecord = entry.undoRecordIDs.contains(record.id)
            || entry.redoRecordIDs.contains(record.id)
        if !isCanonicalRecord {
            guard registerUndo(registrationScope, expectedGeneration: entry.generation, record: record) else {
                return false
            }
        }
        entry.compatibilityRecords[record.id] = CompatibilityRecord(ownerID: ownerID, record: record)
        return true
    }

    nonisolated func compatibilityEvents(windowID: UUID) -> AsyncStream<UndoManagerEvent> {
        compatibilityEventBridge.stream(windowID: windowID)
    }

    func compatibilityAvailability(_ scope: UndoManagerScope?) -> UndoManagerAvailability {
        guard let scope, let entry = entries[scope] else { return .init() }
        return makeCompatibilityAvailability(entry)
    }

    func performCompatibilityUndoRedo(
        _ scope: UndoManagerScope?,
        expectedTarget: UndoManagerRecordIdentity?,
        direction: FileOperationUndoDirection,
    ) -> UndoManagerInvocationResult {
        guard let scope, let entry = entries[scope] else {
            return .init(didInvoke: false, availability: .init())
        }
        let recordID = switch direction {
        case .undo:
            entry.undoRecordIDs.last
        case .redo:
            entry.redoRecordIDs.last
        }
        guard let recordID,
              let compatibilityRecord = entry.compatibilityRecords[recordID],
              expectedTarget == UndoManagerRecordIdentity(
                  ownerID: compatibilityRecord.ownerID,
                  recordID: recordID,
              )
        else {
            return .init(didInvoke: false, availability: makeCompatibilityAvailability(entry))
        }

        let outcome = performUndoRedo(
            scope,
            expectedGeneration: entry.generation,
            direction: direction,
            expectedRecordID: recordID,
        )
        guard outcome == .applied else {
            return .init(didInvoke: false, availability: makeCompatibilityAvailability(entry))
        }
        compatibilityEventBridge.yield(
            UndoManagerEvent(
                ownerID: compatibilityRecord.ownerID,
                record: compatibilityRecord.record,
                direction: direction == .undo ? .undo : .redo,
            ),
            windowID: scope.windowID,
        )
        return .init(didInvoke: true, availability: makeCompatibilityAvailability(entry))
    }

    func invalidateCompatibilityOwner(
        _ scope: UndoManagerScope?,
        ownerID: UUID,
        windowID: UUID? = nil,
    ) -> UndoManagerInvalidationResult {
        if let invalidatedWindowID = scope?.windowID ?? windowID {
            invalidatedCompatibilityOwners.insert(
                CompatibilityOwnerIdentity(windowID: invalidatedWindowID, ownerID: ownerID),
            )
        }
        guard let scope, let entry = entries[scope] else {
            return .init(succeeded: false, availability: .init())
        }
        let matchingRecordIDs = Set(entry.compatibilityRecords.compactMap { recordID, compatibilityRecord in
            compatibilityRecord.ownerID == ownerID ? recordID : nil
        })
        guard !matchingRecordIDs.isEmpty else {
            return .init(succeeded: true, availability: makeCompatibilityAvailability(entry))
        }
        guard entry.pendingTransition == nil else {
            invalidate(entry)
            return .init(succeeded: true, availability: makeCompatibilityAvailability(entry))
        }

        let handlerStore = FileOperationUndoManagerHandlerStore.store(for: entry.manager)
        guard let handlers = handlerStore.removeHandlers(recordIDs: matchingRecordIDs) else {
            invalidate(entry)
            return .init(succeeded: true, availability: makeCompatibilityAvailability(entry))
        }
        for handler in handlers {
            entry.manager.removeAllActions(withTarget: handler)
        }
        entry.undoRecordIDs.removeAll { matchingRecordIDs.contains($0) }
        entry.redoRecordIDs.removeAll { matchingRecordIDs.contains($0) }
        for recordID in matchingRecordIDs {
            entry.compatibilityRecords[recordID] = nil
        }
        return .init(succeeded: true, availability: makeCompatibilityAvailability(entry))
    }

    func invalidateCompatibilityWindow(_ windowID: UUID) -> UndoManagerInvalidationResult {
        invalidatedCompatibilityWindows.insert(windowID)
        let matchingEntries = entries
            .filter { $0.key.windowID == windowID }
            .map(\.value)
        for entry in matchingEntries {
            invalidate(entry)
        }
        compatibilityEventBridge.finish(windowID: windowID)
        return .init(succeeded: true, availability: .init())
    }
}

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
    ) {
        self.activate = activate
        self.deactivate = deactivate
        self.moveScope = moveScope
        self.moveScopes = moveScopes
        self.reconcileFailedScopeMove = reconcileFailedScopeMove
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

private final class UndoManagerEventBridge: @unchecked Sendable {
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
