import Foundation
import Logging

@main
struct FilterSearchXPCServiceMain {
    static func main() {
        bootstrapLogging()
        let logger = Logger(label: "Voyager.FilterSearchXPC")
        loadEnvironment(logger: logger)

        let service = initializeService(logger: logger)
        let delegate = FilterSearchXPCServiceDelegate(logger: logger, service: service)
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        logger.info("Filter search XPC service started")
        listener.resume()
        RunLoop.current.run()
    }

    private static func loadEnvironment(logger: Logger) {
        do {
            try EnvironmentLoader.loadEnvFilesWithProjectRootInference(
                environment: ProcessInfo.processInfo.environment,
                bundle: .main,
            )
        } catch {
            logger.error("Filter search env load failed: \(error)")
        }
    }

    private static func initializeService(logger: Logger) -> FilterSearchService? {
        let semaphore = DispatchSemaphore(value: 0)
        let serviceBox = ServiceBox()
        Task(priority: .userInitiated) { @Sendable in
            do {
                try await DatabaseManager.shared.initialize()
                try serviceBox.setService(FilterSearchService(manager: DatabaseManager.shared))
            } catch {
                logger.error("Filter search service init failed: \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        return serviceBox.service
    }

    private static func bootstrapLogging() {
        LoggingSystem.bootstrap { label in
            let oslogHandler = VoyagerOSLogHandler(label: label)
            #if DEBUG
            let stderrHandler = StreamLogHandler.standardError(label: label)
            return MultiplexLogHandler([oslogHandler, stderrHandler])
            #else
            return oslogHandler
            #endif
        }
    }
}

private final class ServiceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FilterSearchService?

    var service: FilterSearchService? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func setService(_ service: FilterSearchService?) {
        lock.lock()
        stored = service
        lock.unlock()
    }
}

final class FilterSearchXPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let logger: Logger
    private let service: FilterSearchService?

    init(logger: Logger, service: FilterSearchService?) {
        self.logger = logger
        self.service = service
        super.init()
    }

    nonisolated func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection,
    ) -> Bool {
        guard let service else {
            logger.error("Filter search service unavailable")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: FilterSearchXPCServiceProtocol.self)
        newConnection.exportedObject = FilterSearchXPCService(service: service, logger: logger)
        newConnection.resume()
        return true
    }
}
