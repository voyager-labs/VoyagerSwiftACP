@testable import VoyagerExternalAgentRuntime

actor InMemoryRuntimeStateStore: RuntimeStateStore {
    private var state: RuntimeStoredState?
    private let failingLoadNumbers: Set<Int>
    private let loadErrors: [Int: RuntimeStateStoreError]
    private let failingSaveNumbers: Set<Int>
    private let conflictingSaveNumbers: Set<Int>
    private let committedSaveStates: [Int: RuntimeStoredState]
    private let loadGates: [Int: RuntimeTestGate]
    private let saveDelays: [Int: Duration]
    private let saveGates: [Int: RuntimeTestGate]
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var applyCount = 0
    private var loadCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var saveCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var applyCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        state: RuntimeStoredState? = nil,
        failingLoadNumbers: Set<Int> = [],
        loadErrors: [Int: RuntimeStateStoreError] = [:],
        failingSaveNumbers: Set<Int> = [],
        conflictingSaveNumbers: Set<Int> = [],
        committedSaveStates: [Int: RuntimeStoredState] = [:],
        loadGates: [Int: RuntimeTestGate] = [:],
        saveDelays: [Int: Duration] = [:],
        saveGates: [Int: RuntimeTestGate] = [:],
    ) {
        self.state = state
        self.failingLoadNumbers = failingLoadNumbers
        self.loadErrors = loadErrors
        self.failingSaveNumbers = failingSaveNumbers
        self.conflictingSaveNumbers = conflictingSaveNumbers
        self.committedSaveStates = committedSaveStates
        self.loadGates = loadGates
        self.saveDelays = saveDelays
        self.saveGates = saveGates
    }

    func load() async throws -> RuntimeStoredState? {
        loadCount += 1
        resumeLoadCountWaiters()
        await loadGates[loadCount]?.wait()
        if let error = loadErrors[loadCount] {
            throw error
        }
        if failingLoadNumbers.contains(loadCount) {
            throw RuntimeStateStoreError.unavailable
        }
        return state
    }

    func seed(_ state: RuntimeStoredState) async throws {
        saveCount += 1
        resumeSaveCountWaiters()
        if let delay = saveDelays[saveCount] {
            try await Task.sleep(for: delay)
        }
        await saveGates[saveCount]?.wait()
        if failingSaveNumbers.contains(saveCount) {
            throw RuntimeStateStoreError.unavailable
        }
        self.state = state
    }

    func apply(_ mutation: RuntimeStateMutation) async throws -> RuntimeStateMutationResult {
        applyCount += 1
        resumeApplyCountWaiters()
        guard mutation.host.rawValue.isRuntimeBounded,
              mutation.expected?.externalAgentSessionReference == nil || mutation.expected?
              .externalAgentSessionReference == mutation.host,
              mutation.replacement?.externalAgentSessionReference == nil || mutation.replacement?
              .externalAgentSessionReference == mutation.host
        else { throw RuntimeStateStoreError.invalidSnapshot }
        saveCount += 1
        resumeSaveCountWaiters()
        if let delay = saveDelays[saveCount] { try await Task.sleep(for: delay) }
        await saveGates[saveCount]?.wait()
        if failingSaveNumbers.contains(saveCount) { throw RuntimeStateStoreError.unavailable }
        let loaded = state
        let current = loaded ?? RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [])
        let existing = current.sessions.first { $0.externalAgentSessionReference == mutation.host }
        if conflictingSaveNumbers.contains(saveCount) { return .conflict(loaded) }
        if let committed = committedSaveStates[saveCount] {
            state = committed
            return .committed(committed)
        }
        guard existing == mutation.expected else { return .conflict(loaded) }
        if let replacement = mutation.replacement,
           current.sessions
           .contains(where: {
               $0.externalAgentSessionReference != mutation.host && $0.runReference == replacement.runReference
           })
        {
            return .conflict(loaded)
        }
        let sessions = current.sessions
            .filter { $0.externalAgentSessionReference != mutation.host } + (mutation.replacement.map { [$0] } ?? [])
        let committed = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: sessions
                .sorted { $0.externalAgentSessionReference.rawValue < $1.externalAgentSessionReference.rawValue },
        )
        state = committed
        return .committed(committed)
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

    func waitForApplyCount(_ minimumCount: Int) async {
        guard applyCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            applyCountWaiters.append((minimumCount, continuation))
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

    private func resumeApplyCountWaiters() {
        let ready = applyCountWaiters.filter { $0.0 <= applyCount }
        applyCountWaiters.removeAll { $0.0 <= applyCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }
}

actor DeterministicHostMutationRuntimeStateStore: RuntimeStateStore {
    private var state: RuntimeStoredState?
    private let failingLoadNumbers: Set<Int>
    private let loadStates: [Int: RuntimeStoredState]
    private let failingUpdateNumbers: Set<Int>
    private let conflictingUpdateStates: [Int: RuntimeStoredState]
    private let updateGates: [Int: RuntimeTestGate]
    private(set) var loadCount = 0
    private(set) var updateCount = 0
    private var updateCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        state: RuntimeStoredState? = nil,
        failingLoadNumbers: Set<Int> = [],
        loadStates: [Int: RuntimeStoredState] = [:],
        failingUpdateNumbers: Set<Int> = [],
        conflictingUpdateStates: [Int: RuntimeStoredState] = [:],
        updateGates: [Int: RuntimeTestGate] = [:],
    ) {
        self.state = state
        self.failingLoadNumbers = failingLoadNumbers
        self.loadStates = loadStates
        self.failingUpdateNumbers = failingUpdateNumbers
        self.conflictingUpdateStates = conflictingUpdateStates
        self.updateGates = updateGates
    }

    func load() async throws -> RuntimeStoredState? {
        loadCount += 1
        if failingLoadNumbers.contains(loadCount) {
            throw RuntimeStateStoreError.unavailable
        }
        if let loadState = loadStates[loadCount] {
            state = loadState
        }
        return state
    }

    func seed(_ state: RuntimeStoredState) async throws {
        self.state = state
    }

    func apply(_ mutation: RuntimeStateMutation) async throws -> RuntimeStateMutationResult {
        updateCount += 1
        resumeUpdateCountWaiters()
        await updateGates[updateCount]?.wait()
        if failingUpdateNumbers.contains(updateCount) {
            throw RuntimeStateStoreError.unavailable
        }

        let loaded = state
        if let conflictingState = conflictingUpdateStates[updateCount] {
            state = conflictingState
            return .conflict(conflictingState)
        }
        var sessions = loaded?.sessions ?? []
        let current = sessions.first { $0.externalAgentSessionReference == mutation.host }
        guard current == mutation.expected else { return .conflict(loaded) }
        if let replacement = mutation.replacement,
           sessions
           .contains(where: {
               $0.externalAgentSessionReference != mutation.host && $0.runReference == replacement.runReference
           })
        {
            return .conflict(loaded)
        }
        sessions.removeAll { $0.externalAgentSessionReference == mutation.host }
        if let replacement = mutation.replacement { sessions.append(replacement) }
        sessions.sort { $0.externalAgentSessionReference.rawValue < $1.externalAgentSessionReference.rawValue }
        let committed = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: sessions,
        )
        state = committed
        return .committed(committed)
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
}

extension RuntimeFileStateStore {
    func seed(_ state: RuntimeStoredState) async throws {
        let current = try await load()
        for session in current?.sessions ?? [] {
            _ = try await apply(RuntimeStateMutation(
                host: session.externalAgentSessionReference,
                expected: session,
                replacement: nil,
            ))
        }
        for session in state.sessions {
            _ = try await apply(RuntimeStateMutation(
                host: session.externalAgentSessionReference,
                expected: nil,
                replacement: session,
            ))
        }
    }
}
