public nonisolated struct HelperRunningStateTracker: Equatable, Sendable {
    public nonisolated enum Edge: Equatable, Sendable {
        case started
        case stopped
    }

    var hasSeenRunning = false
    var lastKnownIsRunning: Bool?

    public nonisolated init() {}

    public nonisolated mutating func update(isRunning: Bool) -> Edge? {
        defer {
            lastKnownIsRunning = isRunning
            if isRunning {
                hasSeenRunning = true
            }
        }

        if lastKnownIsRunning == isRunning {
            return nil
        }

        if isRunning {
            return .started
        }

        guard hasSeenRunning else {
            return nil
        }

        return .stopped
    }
}
