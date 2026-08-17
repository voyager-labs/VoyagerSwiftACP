import Foundation

struct HelperMonitor {
    let helperClient: HelperAppClient
    let stateClient: HelperStateClient
    let clock: any Clock<Duration>
    let now: @Sendable () -> Date
    let canRestart: @MainActor @Sendable () -> Bool

    func run(mainBundleVersion: String?) async {
        async let monitor: Void = monitorTerminationEvents()

        _ = await helperClient.resolveAlignedState(
            stateClient: stateClient,
            mainBundleVersion: mainBundleVersion,
            canRestart: {
                !Task.isCancelled && canRestart()
            },
        )
        _ = await monitor
    }

    private func monitorTerminationEvents() async {
        var policy = HelperSupervisionPolicy()

        for await _ in helperClient.terminationEvents() {
            guard !Task.isCancelled else { return }
            guard canRestart() else { continue }

            switch policy.recordRestartAttempt(at: now()) {
            case .allowed:
                await ensureRunningIfAllowed()

            case let .cooldown(activeUntil), let .graceWindow(activeUntil):
                guard let updatedPolicy = await waitAndRetryIfNeeded(
                    policy: policy,
                    activeUntil: activeUntil,
                ) else { return }
                policy = updatedPolicy
            }
        }
    }

    private func waitAndRetryIfNeeded(
        policy: HelperSupervisionPolicy,
        activeUntil: Date,
    ) async -> HelperSupervisionPolicy? {
        var policy = policy
        let delay = activeUntil.timeIntervalSince(now())

        if delay > 0 {
            do {
                try await clock.sleep(for: .seconds(delay))
            } catch is CancellationError {
                return nil
            } catch {
                return nil
            }
        }

        guard await !(helperClient.isRunning()) else { return policy }
        guard case .allowed = policy.recordRestartAttempt(at: now()) else { return policy }

        await ensureRunningIfAllowed()
        return policy
    }

    private func ensureRunningIfAllowed() async {
        await helperClient.ensureRunning {
            !Task.isCancelled && canRestart()
        }
    }
}
