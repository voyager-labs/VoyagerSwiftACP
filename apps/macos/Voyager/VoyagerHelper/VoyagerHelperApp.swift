import Foundation
import Logging
import SwiftDotenv

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?

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
