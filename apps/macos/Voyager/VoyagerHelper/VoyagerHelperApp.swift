import Foundation
import Logging
import SwiftDotenv

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?

    static func main() {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardError(label: label)
        }
        let logger = Logger(label: "VoyagerHelper")
        let environment = Environment()

        logger.info(
            "Starting (APP_ENV=\(Dotenv.appEnv?.rawValue ?? "nil"), BACKEND_MODE=\(Dotenv.backendMode?.rawValue ?? "nil"))",
        )

        let runner = ProcessRunner(environment: environment)
        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        Task {
            await lifecycle.start()
        }
        RunLoop.current.run()
        Task {
            await lifecycle.stop()
        }
    }
}
