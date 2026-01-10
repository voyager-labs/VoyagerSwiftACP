import Darwin
import Dispatch
import Foundation
import Logging

actor HelperLifecycle {
    private let processRunner: ProcessRunner
    private var signalSources: [DispatchSourceSignal] = []
    private var didInstallSignalHandlers = false
    private var restartTask: Task<Void, Never>?
    private var stopRequested = false
    private let logger = Logger(label: "VoyagerHelper")
    private let backoffDelays: [TimeInterval] = [1, 2, 4, 8, 16]
    private let stableUptime: TimeInterval = 2
    private let signalQueue = DispatchQueue(label: "VoyagerHelper.Signal")

    init(processRunner: ProcessRunner) {
        self.processRunner = processRunner
    }

    func start() async {
        installSignalHandlersIfNeeded()
        if restartTask != nil {
            return
        }
        stopRequested = false
        restartTask = Task {
            await restartLoop()
        }
    }

    func stop() async {
        stopRequested = true
        restartTask?.cancel()
        restartTask = nil
        await processRunner.stop()
    }

    private func restartLoop() async {
        var attempt = 0
        while !stopRequested, !Task.isCancelled {
            let event: BackendTerminationEvent = await processRunner.startAndMonitor()

            if stopRequested || Task.isCancelled {
                return
            }

            logTermination(event: event, attempt: attempt)

            let wasStable = event.wasReady && event.uptime >= stableUptime
            if wasStable {
                attempt = 0
            } else {
                attempt += 1
            }

            if attempt > backoffDelays.count {
                logger.error("Max restart attempts exceeded (\(backoffDelays.count)). Exiting helper.")
                await processRunner.stop()
                exit(EXIT_FAILURE)
            }

            let delay = backoffDelays[max(attempt - 1, 0)]
            logger.info("Retrying backend start in \(delay)s (attempt \(attempt)/\(backoffDelays.count))")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func logTermination(event: BackendTerminationEvent, attempt: Int) {
        let reason = event.reason.map { "\($0)" } ?? "nil"
        let status = event.status.map { String($0) } ?? "nil"
        logger.warning(
            "Backend terminated: reason=\(reason), status=\(status), uptime=\(String(format: "%.2f", event.uptime))s, ready=\(event.wasReady), attempt=\(attempt)",
        )
    }

    private func installSignalHandlersIfNeeded() {
        if didInstallSignalHandlers {
            return
        }
        didInstallSignalHandlers = true

        let signals: [Int32] = [SIGINT, SIGTERM, SIGQUIT, SIGHUP]
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
            source.setEventHandler { [weak self] in
                guard let lifecycle = self else { return }
                Task { [lifecycle] in
                    await lifecycle.stop()
                    await MainActor.run {
                        CFRunLoopStop(CFRunLoopGetMain())
                    }
                    exit(EXIT_SUCCESS)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
