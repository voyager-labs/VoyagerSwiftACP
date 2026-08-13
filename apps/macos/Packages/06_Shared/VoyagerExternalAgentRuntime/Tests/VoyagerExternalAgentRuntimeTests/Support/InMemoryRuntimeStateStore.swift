@testable import VoyagerExternalAgentRuntime

actor InMemoryRuntimeStateStore: RuntimeStateStore {
    private var state: RuntimeStoredState?
    private let failingSaveNumbers: Set<Int>
    private let loadGates: [Int: RuntimeTestGate]
    private let saveDelays: [Int: Duration]
    private let saveGates: [Int: RuntimeTestGate]
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private var loadCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var saveCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        state: RuntimeStoredState? = nil,
        failingSaveNumbers: Set<Int> = [],
        loadGates: [Int: RuntimeTestGate] = [:],
        saveDelays: [Int: Duration] = [:],
        saveGates: [Int: RuntimeTestGate] = [:],
    ) {
        self.state = state
        self.failingSaveNumbers = failingSaveNumbers
        self.loadGates = loadGates
        self.saveDelays = saveDelays
        self.saveGates = saveGates
    }

    func load() async throws -> RuntimeStoredState? {
        loadCount += 1
        resumeLoadCountWaiters()
        await loadGates[loadCount]?.wait()
        return state
    }

    func save(_ state: RuntimeStoredState) async throws {
        saveCount += 1
        resumeSaveCountWaiters()
        if let delay = saveDelays[saveCount] {
            try await Task.sleep(for: delay)
        }
        await saveGates[saveCount]?.wait()
        if failingSaveNumbers.contains(saveCount) {
            throw StoreFailure.save
        }
        self.state = state
    }

    func currentState() -> RuntimeStoredState? {
        state
    }

    func replaceState(_ state: RuntimeStoredState) {
        self.state = state
    }

    func waitForSaveCount(_ minimumCount: Int) async {
        guard saveCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            saveCountWaiters.append((minimumCount, continuation))
        }
    }

    func waitForLoadCount(_ minimumCount: Int) async {
        guard loadCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            loadCountWaiters.append((minimumCount, continuation))
        }
    }

    private func resumeLoadCountWaiters() {
        let ready = loadCountWaiters.filter { $0.0 <= loadCount }
        loadCountWaiters.removeAll { $0.0 <= loadCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    private func resumeSaveCountWaiters() {
        let ready = saveCountWaiters.filter { $0.0 <= saveCount }
        saveCountWaiters.removeAll { $0.0 <= saveCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    enum StoreFailure: Error { case save }
}

actor DeterministicHostMutationRuntimeStateStore: RuntimeStateStore, RuntimeStateStoreHostMutation {
    private var state: RuntimeStoredState?
    private let failingLoadNumbers: Set<Int>
    private let failingUpdateNumbers: Set<Int>
    private let updateGates: [Int: RuntimeTestGate]
    private(set) var loadCount = 0
    private(set) var updateCount = 0
    private var updateCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        state: RuntimeStoredState? = nil,
        failingLoadNumbers: Set<Int> = [],
        failingUpdateNumbers: Set<Int> = [],
        updateGates: [Int: RuntimeTestGate] = [:],
    ) {
        self.state = state
        self.failingLoadNumbers = failingLoadNumbers
        self.failingUpdateNumbers = failingUpdateNumbers
        self.updateGates = updateGates
    }

    func load() async throws -> RuntimeStoredState? {
        loadCount += 1
        if failingLoadNumbers.contains(loadCount) {
            throw StoreFailure.load
        }
        return state
    }

    func save(_ state: RuntimeStoredState) async throws {
        self.state = state
    }

    func updateHost(
        _ host: ExternalAgentSessionReference,
        expected: RuntimeStoredSession?,
        replacement: RuntimeStoredSession?,
    ) async throws -> RuntimeStoredState {
        updateCount += 1
        resumeUpdateCountWaiters()
        await updateGates[updateCount]?.wait()
        if failingUpdateNumbers.contains(updateCount) {
            throw StoreFailure.update
        }

        var sessions = state?.sessions ?? []
        let current = sessions.first { $0.externalAgentSessionReference == host }
        guard RuntimeStoredSession.hasSamePersistedState(current, expected) else {
            throw StoreFailure.update
        }
        sessions.removeAll { $0.externalAgentSessionReference == host }
        if let replacement {
            sessions.append(replacement)
        }
        sessions.sort { $0.externalAgentSessionReference.rawValue < $1.externalAgentSessionReference.rawValue }
        let committed = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: sessions,
        )
        state = committed
        return committed
    }

    func currentState() -> RuntimeStoredState? {
        state
    }

    func replaceState(_ state: RuntimeStoredState) {
        self.state = state
    }

    func waitForUpdateCount(_ minimumCount: Int) async {
        guard updateCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            updateCountWaiters.append((minimumCount, continuation))
        }
    }

    private func resumeUpdateCountWaiters() {
        let ready = updateCountWaiters.filter { $0.0 <= updateCount }
        updateCountWaiters.removeAll { $0.0 <= updateCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    enum StoreFailure: Error { case load, update }
}
