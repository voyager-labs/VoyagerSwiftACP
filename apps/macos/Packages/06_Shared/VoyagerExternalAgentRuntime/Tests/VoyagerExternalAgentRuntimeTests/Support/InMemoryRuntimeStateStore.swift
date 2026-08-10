import VoyagerExternalAgentRuntime

actor InMemoryRuntimeStateStore: RuntimeStateStore {
    private var state: RuntimeStoredState?
    private let failingSaveNumbers: Set<Int>
    private let saveDelays: [Int: Duration]
    private(set) var saveCount = 0

    init(
        state: RuntimeStoredState? = nil,
        failingSaveNumbers: Set<Int> = [],
        saveDelays: [Int: Duration] = [:],
    ) {
        self.state = state
        self.failingSaveNumbers = failingSaveNumbers
        self.saveDelays = saveDelays
    }

    func load() async throws -> RuntimeStoredState? {
        state
    }

    func save(_ state: RuntimeStoredState) async throws {
        saveCount += 1
        if let delay = saveDelays[saveCount] {
            try await Task.sleep(for: delay)
        }
        if failingSaveNumbers.contains(saveCount) {
            throw StoreFailure.save
        }
        self.state = state
    }

    func currentState() -> RuntimeStoredState? {
        state
    }

    enum StoreFailure: Error { case save }
}
