import Foundation

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?

    static func main() {
        let environment = Environment()

        fputs(
            "[VoyagerHelper] Starting (APP_ENV=\(environment.environmentType.rawValue), BACKEND_MODE=\(environment.backendMode.rawValue))\n",
            stderr
        )

        let runner = ProcessRunner(environment: environment)
        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        lifecycle.start()
        RunLoop.current.run()
        lifecycle.stop()
    }
}
