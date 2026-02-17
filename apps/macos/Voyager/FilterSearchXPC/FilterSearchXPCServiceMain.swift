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

    private static func initializeService(logger: Logger) -> SpotlightSearchService {
        logger.info("Filter search service initialized with SpotlightSearchService")
        return SpotlightSearchService()
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

final class FilterSearchXPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let logger: Logger
    private let service: SpotlightSearchService

    init(logger: Logger, service: SpotlightSearchService) {
        self.logger = logger
        self.service = service
        super.init()
    }

    nonisolated func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection,
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FilterSearchXPCServiceProtocol.self)
        newConnection.exportedObject = XPCSearchService(service: service, logger: logger)
        newConnection.resume()
        return true
    }
}
