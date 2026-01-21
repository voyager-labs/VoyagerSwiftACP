import Foundation
import Logging
import SwiftDotenv

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?

    @MainActor
    static func main() {
        LoggingSystem.bootstrap { label in
            let oslogHandler = VoyagerOSLogHandler(label: label)
            #if DEBUG
            let stderrHandler = StreamLogHandler.standardError(label: label)
            return MultiplexLogHandler([oslogHandler, stderrHandler])
            #else
            return oslogHandler
            #endif
        }
        let logger = Logger(label: "VoyagerHelper")
        let environment = Environment()
        let stateBroadcaster = HelperStateBroadcaster()

        logger.info(
            "Starting (APP_ENV=\(Dotenv.appEnv?.rawValue ?? "nil"), BACKEND_MODE=\(Dotenv.backendMode?.rawValue ?? "nil"))",
        )

        let runner = ProcessRunner(environment: environment, stateBroadcaster: stateBroadcaster)
        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        Task {
            do {
                try await DatabaseManager.shared.initialize()
            } catch {
                logger.error("Database initialization failed: \(error)")
                exit(EXIT_FAILURE)
            }
            await stateBroadcaster.startObservingRequests()
            await stateBroadcaster.postCurrentState()
            Task {
                do {
                    _ = try await InitialIndexingRunner.indexHomeDirectoryIfNeeded(
                        manager: DatabaseManager.shared,
                        logger: logger
                    )
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
}
