import Foundation
import os

final class EntryCoreRequestContext: Sendable {
    private struct TerminalState {
        let result: Result<Data, EntryCoreClientError>
        let continuation: CheckedContinuation<Data, Error>?
        let descriptors: [Int32]
    }

    private struct State {
        var isCancelled = false
        var isFinished = false
        var networkFD: Int32 = -1
        var wakeReadFD: Int32 = -1
        var wakeWriteFD: Int32 = -1
        var continuation: CheckedContinuation<Data, Error>?
    }

    private let system: any UnixSocketSystem
    private let worker = DispatchQueue(label: "VoyagerEntryCoreClient.request", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(system: any UnixSocketSystem) {
        self.system = system
    }

    func execute(
        _ operation: @escaping @Sendable (EntryCoreRequestContext) -> Result<Data, EntryCoreClientError>,
    ) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.withLock { state in
                    state.continuation = continuation
                }
                worker.async { [self] in
                    let result = isCancelled ? .failure(EntryCoreClientError.cancelled) : operation(self)
                    finish(result)
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func registerWakePipe(read: Int32, write: Int32) {
        state.withLock { state in
            state.wakeReadFD = read
            state.wakeWriteFD = write
        }
    }

    func registerNetworkFD(_ fd: Int32) {
        state.withLock { state in
            state.networkFD = fd
        }
    }

    var isCancelled: Bool {
        state.withLock { state in state.isCancelled }
    }

    var wakeReadDescriptor: Int32 {
        state.withLock { state in state.wakeReadFD }
    }

    private func cancel() {
        state.withLock { state in
            guard !state.isCancelled, !state.isFinished else { return }
            state.isCancelled = true
            if state.wakeWriteFD >= 0 {
                system.signalWake(state.wakeWriteFD)
            }
        }
    }

    private func finish(_ proposedResult: Result<Data, EntryCoreClientError>) {
        let terminal = state.withLock { state -> TerminalState? in
            guard !state.isFinished else { return nil }
            state.isFinished = true
            let result: Result<Data, EntryCoreClientError> = state.isCancelled ? .failure(.cancelled) : proposedResult
            let continuation = state.continuation
            state.continuation = nil
            let descriptors = [state.networkFD, state.wakeReadFD, state.wakeWriteFD].filter { $0 >= 0 }
            state.networkFD = -1
            state.wakeReadFD = -1
            state.wakeWriteFD = -1
            return TerminalState(result: result, continuation: continuation, descriptors: descriptors)
        }
        guard let terminal else { return }
        for descriptor in terminal.descriptors {
            system.close(descriptor)
        }
        terminal.continuation?.resume(with: terminal.result.mapError { $0 as Error })
    }
}
