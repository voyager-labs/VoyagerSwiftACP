import Foundation

@main
class VoyagerHelperApp {
    private static var lifecycle: HelperLifecycle?

    static func main() {
        let environment = Environment()
        let runner = ProcessRunner(environment: environment)
        let lifecycle = HelperLifecycle(processRunner: runner)
        VoyagerHelperApp.lifecycle = lifecycle

        lifecycle.start()
        RunLoop.current.run()
        lifecycle.stop()
    }
}
