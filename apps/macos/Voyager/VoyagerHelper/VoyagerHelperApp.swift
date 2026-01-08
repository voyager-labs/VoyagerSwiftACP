import Foundation
import Logging

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
            "Starting (APP_ENV=\(environment.appEnv.rawValue), BACKEND_MODE=\(environment.backendMode.rawValue))",
        )

        let runner = ProcessRunner(environment: environment)
        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        lifecycle.start()
        RunLoop.current.run()
        lifecycle.stop()
    }
}
