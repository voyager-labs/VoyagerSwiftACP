import Foundation

public final class MainThreadThrottler {
    private let interval: TimeInterval
    private let latest: Bool

    private var isThrottling = false
    private var pendingAction: (() -> Void)?
    private var cooldownWorkItem: DispatchWorkItem?

    public init(intervalMs: Int, latest: Bool) {
        interval = TimeInterval(intervalMs) / 1000
        self.latest = latest
    }

    public func schedule(_ action: @escaping () -> Void) {
        if !isThrottling {
            isThrottling = true
            action()
            startCooldown()
            return
        }

        guard latest else { return }
        pendingAction = action
    }

    private func startCooldown() {
        cooldownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            isThrottling = false

            guard let pendingAction else { return }
            self.pendingAction = nil
            schedule(pendingAction)
        }
        cooldownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }
}

public final class MainThreadDebouncer {
    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?

    public init(intervalMs: Int) {
        interval = TimeInterval(intervalMs) / 1000
    }

    public func schedule(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let next = DispatchWorkItem(block: action)
        workItem = next
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: next)
    }
}
