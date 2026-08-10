import Darwin
import Dispatch
import Foundation
import os
@testable import VoyagerEntryCoreClient

enum ScriptedPollAction {
    case result(UnixSocketPollResult)
    case sleep(milliseconds: UInt32, result: UnixSocketPollResult)
    case waitForWake
}

enum ScriptedReceiveAction {
    case result(UnixSocketReceiveResult)
    case wait(DispatchSemaphore, UnixSocketReceiveResult)
}

final class ScriptedUnixSocketSystem: UnixSocketSystem {
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let wakeSemaphore = DispatchSemaphore(value: 0)

    struct State {
        var socketResult: UnixSocketCallResult = .success(20)
        var noSigPipeResult: UnixSocketCallResult = .success(0)
        var wakePipeResult: UnixSocketPairResult = .success(read: 10, write: 11)
        var wakePipeGate: DispatchSemaphore?
        var connectResults: [UnixSocketCallResult] = [.success(0)]
        var socketErrorResults: [UnixSocketCallResult] = [.success(0)]
        var sendResults: [UnixSocketCallResult] = []
        var shutdownResult: UnixSocketCallResult = .success(0)
        var receiveActions: [ScriptedReceiveAction] = [.result(.eof)]
        var pollActions: [ScriptedPollAction] = []
        var operations: [String] = []
        var sent = Data()
        var pollTimeouts: [Int32] = []
        var closeCounts: [Int32: Int] = [:]
        var connectedAddress: sockaddr_un?
        var connectedLength: socklen_t?
    }

    func configure(_ update: @Sendable (inout State) -> Void) {
        state.withLock { state in update(&state) }
    }

    func snapshot() -> State {
        state.withLock { state in state }
    }

    func makeSocket() -> UnixSocketCallResult {
        state.withLock { state in
            state.operations.append("socket")
            return state.socketResult
        }
    }

    func setNoSigPipe(_ fd: Int32) -> UnixSocketCallResult {
        state.withLock { state in
            state.operations.append("nosigpipe:\(fd)")
            return state.noSigPipeResult
        }
    }

    func makeWakePipe() -> UnixSocketPairResult {
        let (gate, result) = state.withLock { state -> (DispatchSemaphore?, UnixSocketPairResult) in
            state.operations.append("wake-pipe")
            return (state.wakePipeGate, state.wakePipeResult)
        }
        gate?.wait()
        return result
    }

    func connect(_ fd: Int32, address: sockaddr_un, length: socklen_t) -> UnixSocketCallResult {
        state.withLock { state in
            state.operations.append("connect:\(fd)")
            state.connectedAddress = address
            state.connectedLength = length
            return state.connectResults.removeFirst()
        }
    }

    func socketError(_ fd: Int32) -> UnixSocketCallResult {
        state.withLock { state in
            state.operations.append("socket-error:\(fd)")
            return state.socketErrorResults.removeFirst()
        }
    }

    func send(_ fd: Int32, bytes: Data) -> UnixSocketCallResult {
        state.withLock { state in
            state.operations.append("send:\(fd):\(bytes.count)")
            let result = state.sendResults.isEmpty ? .success(Int32(bytes.count)) : state.sendResults.removeFirst()
            if case let .success(count) = result, count > 0 {
                state.sent.append(bytes.prefix(Int(count)))
            }
            return result
        }
    }

    func shutdownWrite(_ fd: Int32) -> UnixSocketCallResult {
        state.withLock { state in
            state.operations.append("shutdown-write:\(fd)")
            return state.shutdownResult
        }
    }

    func receive(_ fd: Int32, maximumBytes: Int) -> UnixSocketReceiveResult {
        let action = state.withLock { state -> ScriptedReceiveAction in
            state.operations.append("receive:\(fd):\(maximumBytes)")
            return state.receiveActions.removeFirst()
        }
        switch action {
        case let .result(result):
            return result
        case let .wait(semaphore, result):
            semaphore.wait()
            return result
        }
    }

    func poll(networkFD: Int32, events: Int16, wakeFD: Int32, timeoutMilliseconds: Int32) -> UnixSocketPollResult {
        let action = state.withLock { state -> ScriptedPollAction in
            state.operations.append("poll:\(networkFD):\(events):\(wakeFD)")
            state.pollTimeouts.append(timeoutMilliseconds)
            return state.pollActions.removeFirst()
        }
        switch action {
        case let .result(result):
            return result
        case let .sleep(milliseconds, result):
            usleep(milliseconds * 1000)
            return result
        case .waitForWake:
            wakeSemaphore.wait()
            return .ready(networkEvents: 0, wakeEvents: Int16(POLLIN))
        }
    }

    func signalWake(_ fd: Int32) {
        state.withLock { state in state.operations.append("signal-wake:\(fd)") }
        wakeSemaphore.signal()
    }

    func drainWake(_ fd: Int32) {
        state.withLock { state in state.operations.append("drain-wake:\(fd)") }
    }

    func close(_ fd: Int32) {
        state.withLock { state in
            state.operations.append("close:\(fd)")
            state.closeCounts[fd, default: 0] += 1
        }
    }
}
