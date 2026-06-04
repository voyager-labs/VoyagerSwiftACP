import Foundation
@testable import VoyagerPagesOnboarding

actor EventLog {
    private var events: [String] = []
    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

final class EventLogSyncBox: @unchecked Sendable {
    private var events: [String] = []
    private let lock = NSLock()
    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

actor CloseRecorder {
    private var count = 0

    func record() {
        count += 1
    }

    func snapshot() -> Int {
        count
    }
}

enum WindowClient {
    static var successMock: OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {},
            openMainWindow: { _ in true },
        )
    }

    static var failureMock: OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {},
            openMainWindow: { _ in false },
        )
    }

    static func recording(
        pathRecorder: PathRecorder,
        closeRecorder: CloseRecorder? = nil,
        eventLog: EventLogSyncBox? = nil,
    ) -> OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {
                eventLog?.record("close")
                await closeRecorder?.record()
            },
            openMainWindow: { request in
                eventLog?.record("open")
                await pathRecorder.append(request)
                return true
            },
        )
    }

    static func recordingFailure(
        pathRecorder: PathRecorder,
        closeRecorder: CloseRecorder? = nil,
        eventLog: EventLogSyncBox? = nil,
    ) -> OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {
                eventLog?.record("close")
                await closeRecorder?.record()
            },
            openMainWindow: { request in
                eventLog?.record("open")
                await pathRecorder.append(request)
                return false
            },
        )
    }
}
