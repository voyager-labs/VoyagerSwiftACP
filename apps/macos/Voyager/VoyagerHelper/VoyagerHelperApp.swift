import Foundation
import Logging
import SwiftDotenv

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?
    private static var indexingListener: HelperIndexingRequestListener?

    @MainActor
    static func main() {
        bootstrapLogging()
        let logger = Logger(label: "VoyagerHelper")
        let environment = Environment()
        let stateBroadcaster = HelperStateBroadcaster()
        let indexingListener = HelperIndexingRequestListener(
            manager: DatabaseManager.shared,
            logger: logger
        )

        logger.info(
            "Starting (APP_ENV=\(Dotenv.appEnv?.rawValue ?? "nil"), BACKEND_MODE=\(Dotenv.backendMode?.rawValue ?? "nil"))",
        )

        let runner = ProcessRunner(environment: environment, stateBroadcaster: stateBroadcaster)
        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle
        VoyagerHelperApp.indexingListener = indexingListener

        Task {
            do {
                try await DatabaseManager.shared.initialize()
            } catch {
                logger.error("Database initialization failed: \(error)")
                exit(EXIT_FAILURE)
            }
            await stateBroadcaster.startObservingRequests()
            await stateBroadcaster.postCurrentState()
            await indexingListener.prepare()
            await indexingListener.startObservingRequests()
            Task {
                do {
                    if await indexingListener.hasCompletedInitialIndexing() {
                        await IncrementalIndexingValidator.startIfReady(
                            manager: DatabaseManager.shared,
                            logger: logger
                        )
                    }
                } catch {
                    logger.error("Initial indexing failed: \(error)")
                    exit(EXIT_FAILURE)
                }
            }
            await lifecycle.start()
        }
        RunLoop.current.run()
        Task {
            await lifecycle.stop()
        }
    }

    // 로깅 핸들러 구성
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
