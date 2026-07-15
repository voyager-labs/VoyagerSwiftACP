import Foundation
@testable import VoyagerFeaturesEntryOperations

/// UndoManagerClient 호출과 typed event를 기록하는 spy.
final class UndoManagerSpy: @unchecked Sendable {
    private let lock = NSLock()

    struct RegisterUndoCall {
        let windowID: UUID
        let ownerID: UUID
        let record: EntryActionRecord
    }

    private var _registerUndoCalls: [RegisterUndoCall] = []
    private var _undoCalls: [UUID?] = []
    private var _redoCalls: [UUID?] = []
    private var continuations: [UUID: [AsyncStream<UndoManagerEvent>.Continuation]] = [:]

    var registerUndoCalls: [RegisterUndoCall] {
        lock.withLock { _registerUndoCalls }
    }

    var registeredRecords: [EntryActionRecord] {
        registerUndoCalls.map(\.record)
    }

    var undoCalls: [UUID?] {
        lock.withLock { _undoCalls }
    }

    var redoCalls: [UUID?] {
        lock.withLock { _redoCalls }
    }

    func recordRegisterUndo(windowID: UUID, ownerID: UUID, record: EntryActionRecord) {
        lock.withLock {
            _registerUndoCalls.append(.init(windowID: windowID, ownerID: ownerID, record: record))
        }
    }

    func recordUndo(windowID: UUID?) {
        lock.withLock { _undoCalls.append(windowID) }
    }

    func recordRedo(windowID: UUID?) {
        lock.withLock { _redoCalls.append(windowID) }
    }

    func events(windowID: UUID) -> AsyncStream<UndoManagerEvent> {
        AsyncStream { continuation in
            lock.withLock {
                continuations[windowID, default: []].append(continuation)
            }
        }
    }

    func invokeUndo(at index: Int = 0) {
        emit(direction: .undo, at: index)
    }

    func invokeRedo(at index: Int = 0) {
        emit(direction: .redo, at: index)
    }

    private func emit(direction: EntryActionDirection, at index: Int) {
        let payload = lock.withLock { () -> (RegisterUndoCall, [AsyncStream<UndoManagerEvent>.Continuation])? in
            guard _registerUndoCalls.indices.contains(index) else { return nil }
            let call = _registerUndoCalls[index]
            return (call, continuations[call.windowID] ?? [])
        }
        guard let (call, currentContinuations) = payload else { return }
        let event = UndoManagerEvent(ownerID: call.ownerID, record: call.record, direction: direction)
        for continuation in currentContinuations {
            continuation.yield(event)
        }
    }

    var client: UndoManagerClient {
        UndoManagerClient(
            registerUndo: { [weak self] windowID, ownerID, record in
                self?.recordRegisterUndo(windowID: windowID, ownerID: ownerID, record: record)
            },
            events: { [weak self] windowID in
                self?.events(windowID: windowID) ?? AsyncStream { $0.finish() }
            },
            undo: { [weak self] windowID in
                self?.recordUndo(windowID: windowID)
                return .init(didInvoke: true, availability: .init(canUndo: false, canRedo: true))
            },
            redo: { [weak self] windowID in
                self?.recordRedo(windowID: windowID)
                return .init(didInvoke: true, availability: .init(canUndo: true, canRedo: false))
            },
        )
    }
}
