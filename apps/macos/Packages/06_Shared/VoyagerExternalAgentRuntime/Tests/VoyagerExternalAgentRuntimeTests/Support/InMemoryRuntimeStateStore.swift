import VoyagerExternalAgentRuntime

actor InMemoryRuntimeStateStore: RuntimeStateStore {
    private var state: RuntimeStoredState?
    private let failingSaveNumbers: Set<Int>
    private let saveDelays: [Int: Duration]
    private let saveGates: [Int: RuntimeTestGate]
    private(set) var saveCount = 0
    private var saveCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        state: RuntimeStoredState? = nil,
        failingSaveNumbers: Set<Int> = [],
        saveDelays: [Int: Duration] = [:],
        saveGates: [Int: RuntimeTestGate] = [:],
    ) {
        self.state = state
        self.failingSaveNumbers = failingSaveNumbers
        self.saveDelays = saveDelays
        self.saveGates = saveGates
    }

    func load() async throws -> RuntimeStoredState? {
        state
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

    func waitForSaveCount(_ minimumCount: Int) async {
        guard saveCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            saveCountWaiters.append((minimumCount, continuation))
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
