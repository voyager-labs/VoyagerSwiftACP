import Foundation

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?

    static func main() {
        var environment = Environment()

        fputs(
            "[VoyagerHelper] Starting (APP_ENV=\(environment.environmentType.rawValue), BACKEND_MODE=\(environment.backendMode.rawValue))\n",
            stderr,
        )

        let runner = ProcessRunner(environment: environment)

        // 포트 할당 시 Environment에 저장
        runner.onPortAssigned = { port in
            environment.backendPort = port
            if let url = environment.backendURL {
                fputs("[VoyagerHelper] Backend URL: \(url)\n", stderr)
            }
        }

        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        lifecycle.start()
        RunLoop.current.run()
        lifecycle.stop()
    }
}
