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
        var environment = Environment()

        logger.info(
            "Starting (APP_ENV=\(environment.environmentType.rawValue), BACKEND_MODE=\(environment.backendMode.rawValue))",
        )

        let runner = ProcessRunner(environment: environment)

        // 포트 할당 시 Environment에 저장
        runner.onPortAssigned = { port in
            environment.backendPort = port
            if let url = environment.backendURL {
                logger.info("Backend URL: \(url)")
            }
        }

        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        lifecycle.start()
        RunLoop.current.run()
        lifecycle.stop()
    }
}
