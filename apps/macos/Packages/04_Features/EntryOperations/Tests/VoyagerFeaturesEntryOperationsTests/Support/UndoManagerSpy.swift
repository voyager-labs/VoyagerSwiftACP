import Foundation
@testable import VoyagerFeaturesEntryOperations

/// UndoManagerClient 호출을 기록하는 spy.
/// invokeUndo(at:) / invokeRedo(at:) 로 등록된 핸들러를 외부에서 실행할 수 있다.
final class UndoManagerSpy: @unchecked Sendable {
    private let lock = NSLock()

    struct RegisterUndoCall {
        let windowID: UUID?
        let record: EntryActionRecord
        let onUndo: @Sendable (EntryActionRecord) async -> Void
        let onRedo: @Sendable (EntryActionRecord) async -> Void
    }

    private var _registerUndoCalls: [RegisterUndoCall] = []

    var registerUndoCalls: [RegisterUndoCall] {
        lock.lock()
        defer { lock.unlock() }
        return _registerUndoCalls
    }

    /// registerUndo로 전달된 record 목록
    var registeredRecords: [EntryActionRecord] {
        registerUndoCalls.map(\.record)
    }

    private var _undoCalls: [UUID?] = []
    private var _redoCalls: [UUID?] = []

    var undoCalls: [UUID?] {
        lock.lock()
        defer { lock.unlock() }
        return _undoCalls
    }

    var redoCalls: [UUID?] {
        lock.lock()
        defer { lock.unlock() }
        return _redoCalls
    }

    func recordRegisterUndo(
        windowID: UUID?,
        record: EntryActionRecord,
        onUndo: @escaping @Sendable (EntryActionRecord) async -> Void,
        onRedo: @escaping @Sendable (EntryActionRecord) async -> Void,
    ) {
        lock.lock()
        defer { lock.unlock() }
        _registerUndoCalls.append(.init(
            windowID: windowID,
            record: record,
            onUndo: onUndo,
            onRedo: onRedo,
        ))
    }

    func recordUndo(windowID: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        _undoCalls.append(windowID)
    }

    func recordRedo(windowID: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        _redoCalls.append(windowID)
    }

    private func getCall(at index: Int) -> RegisterUndoCall? {
        lock.withLock {
            guard index < _registerUndoCalls.count else { return nil }
            return _registerUndoCalls[index]
        }
    }

    /// `index`번째 registerUndo의 onUndo 핸들러를 실행한다.
    func invokeUndo(at index: Int = 0) async {
        guard let call = getCall(at: index) else { return }
        await call.onUndo(call.record)
    }

    /// `index`번째 registerUndo의 onRedo 핸들러를 실행한다.
    func invokeRedo(at index: Int = 0) async {
        guard let call = getCall(at: index) else { return }
        await call.onRedo(call.record)
    }

    var client: UndoManagerClient {
        UndoManagerClient(
            registerUndo: { [weak self] windowID, record, onUndo, onRedo in
                self?.recordRegisterUndo(
                    windowID: windowID,
                    record: record,
                    onUndo: onUndo,
                    onRedo: onRedo,
                )
            },
            undo: { [weak self] windowID in
                self?.recordUndo(windowID: windowID)
            },
            redo: { [weak self] windowID in
                self?.recordRedo(windowID: windowID)
            },
        )
    }
}
