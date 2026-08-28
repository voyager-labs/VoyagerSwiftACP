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
        var ownerIdentities: [UUID: CompatibilityOwnerIdentity] = [:]
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
            rebindCompatibilityOwnerIdentities(restored.entry, to: restored.scope)
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
        registerUndo(
            scope,
            expectedGeneration: expectedGeneration,
            ownerIdentity: nil,
            record: record,
        )
    }

    @discardableResult
    public func registerUndo(
        _ scope: UndoManagerScope,
        expectedGeneration: Generation,
        ownerID: UUID,
        record: EntryActionRecord,
    ) -> Bool {
        let ownerIdentity = CompatibilityOwnerIdentity(windowID: scope.windowID, ownerID: ownerID)
        guard !invalidatedCompatibilityWindows.contains(scope.windowID),
              !invalidatedCompatibilityOwners.contains(ownerIdentity)
        else { return false }
        return registerUndo(
            scope,
            expectedGeneration: expectedGeneration,
            ownerIdentity: ownerIdentity,
            record: record,
        )
    }

    private func registerUndo(
        _ scope: UndoManagerScope,
        expectedGeneration: Generation,
        ownerIdentity: CompatibilityOwnerIdentity?,
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
        entry.ownerIdentities[record.id] = ownerIdentity
        for recordID in entry.redoRecordIDs {
            entry.ownerIdentities[recordID] = nil
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
            rebindCompatibilityOwnerIdentities(move.entry, to: move.descriptor.target)
            FileOperationUndoManagerHandlerStore.store(for: move.entry.manager)
                .rebind(to: move.descriptor.target)
        }
    }

    private func rebindCompatibilityOwnerIdentities(_ entry: Entry, to scope: UndoManagerScope) {
        for (recordID, ownerIdentity) in entry.ownerIdentities {
            entry.ownerIdentities[recordID] = CompatibilityOwnerIdentity(
                windowID: scope.windowID,
                ownerID: ownerIdentity.ownerID,
            )
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
        entry.ownerIdentities.removeAll()
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
}

public extension FileOperationUndoManagerRegistry {
    @discardableResult
    func registerCompatibilityUndo(
        _ scope: UndoManagerScope?,
        ownerID: UUID,
        record: EntryActionRecord,
        windowID: UUID? = nil,
    ) -> Bool {
        let canonicalScopes: [UndoManagerScope] = entries.compactMap { candidate in
            let (candidateScope, candidateEntry) = candidate
            guard candidateEntry.undoRecordIDs.contains(record.id)
                || candidateEntry.redoRecordIDs.contains(record.id)
            else { return nil }
            return candidateScope
        }
        guard canonicalScopes.count <= 1 else { return false }
        guard let registrationScope = canonicalScopes.first ?? scope else { return false }
        guard let entry = entries[registrationScope], entry.pendingTransition == nil else { return false }
        let recordedOwnerIdentity = entry.ownerIdentities[record.id]
        guard recordedOwnerIdentity?.ownerID == nil || recordedOwnerIdentity?.ownerID == ownerID else {
            return false
        }
        let ownerIdentity = recordedOwnerIdentity
            ?? CompatibilityOwnerIdentity(
                windowID: windowID ?? scope?.windowID ?? registrationScope.windowID,
                ownerID: ownerID,
            )
        guard !invalidatedCompatibilityWindows.contains(registrationScope.windowID),
              !invalidatedCompatibilityWindows.contains(ownerIdentity.windowID),
              !invalidatedCompatibilityOwners.contains(ownerIdentity)
        else { return false }
        let isCanonicalRecord = entry.undoRecordIDs.contains(record.id)
            || entry.redoRecordIDs.contains(record.id)
        if !isCanonicalRecord {
            guard registerUndo(
                registrationScope,
                expectedGeneration: entry.generation,
                ownerID: ownerID,
                record: record,
            ) else {
                return false
            }
        }
        entry.ownerIdentities[record.id] = ownerIdentity
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
        var ownerIdentities = Set(entries.values.flatMap { entry in
            entry.ownerIdentities.values.filter { $0.ownerID == ownerID }
        })
        if let invalidatedWindowID = scope?.windowID ?? windowID {
            ownerIdentities.insert(
                CompatibilityOwnerIdentity(windowID: invalidatedWindowID, ownerID: ownerID),
            )
        }
        for ownerIdentity in ownerIdentities {
            invalidatedCompatibilityOwners.insert(ownerIdentity)
            removeCompatibilityHistory(ownerIdentity: ownerIdentity)
        }
        guard let scope, let entry = entries[scope] else {
            return .init(succeeded: false, availability: .init())
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

    private func removeCompatibilityHistory(ownerIdentity: CompatibilityOwnerIdentity) {
        for entry in entries.values {
            let matchingRecordIDs = Set(entry.ownerIdentities.compactMap { recordID, identity in
                identity == ownerIdentity ? recordID : nil
            })
            guard !matchingRecordIDs.isEmpty else { continue }
            guard entry.pendingTransition == nil else {
                invalidate(entry)
                continue
            }

            let handlerStore = FileOperationUndoManagerHandlerStore.store(for: entry.manager)
            guard let handlers = handlerStore.removeHandlers(recordIDs: matchingRecordIDs) else {
                invalidate(entry)
                continue
            }
            for handler in handlers {
                entry.manager.removeAllActions(withTarget: handler)
            }
            entry.undoRecordIDs.removeAll { matchingRecordIDs.contains($0) }
            entry.redoRecordIDs.removeAll { matchingRecordIDs.contains($0) }
            for recordID in matchingRecordIDs {
                entry.ownerIdentities[recordID] = nil
                entry.compatibilityRecords[recordID] = nil
            }
        }
    }
}

private extension FileOperationUndoManagerRegistry {
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
