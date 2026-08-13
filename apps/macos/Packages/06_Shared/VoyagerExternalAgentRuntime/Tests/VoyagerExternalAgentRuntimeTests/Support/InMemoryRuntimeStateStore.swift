import VoyagerExternalAgentRuntime

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
