import Foundation

struct RuntimeRestorationClock {
    let now: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void

    static let live = Self(
        now: { Date() },
        sleep: { duration in
            try await Task.sleep(for: duration)
        },
    )
}

extension RuntimeRestorationClock: Sendable {}
