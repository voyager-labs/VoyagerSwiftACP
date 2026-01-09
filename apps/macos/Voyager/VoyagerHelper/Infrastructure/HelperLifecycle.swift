import Darwin
import Dispatch
import Foundation

final class HelperLifecycle {
    private let processRunner: ProcessRunner
    private var signalSources: [DispatchSourceSignal] = []

    init(processRunner: ProcessRunner) {
        self.processRunner = processRunner
    }

    func start() async {
        installSignalHandlers()
        await processRunner.startIfNeeded()
    }

    func stop() async {
        await processRunner.stop()
    }

    private func installSignalHandlers() {
        let signals: [Int32] = [SIGINT, SIGTERM, SIGQUIT, SIGHUP]
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    await self?.processRunner.stop()
                    CFRunLoopStop(CFRunLoopGetMain())
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
