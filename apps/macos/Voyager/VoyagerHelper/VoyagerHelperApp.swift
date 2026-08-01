import AppKit
import Darwin
import Foundation
import Logging
import SwiftDotenv
import VoyagerShared

@main
@MainActor
final class VoyagerHelperApp: NSObject, NSApplicationDelegate {
    private static let appDelegate = VoyagerHelperApp()
    private static var didStart = false
    private static var helperFolderAccessListener: HelperFolderAccessListener?
    private static var stateBroadcaster: HelperStateBroadcaster?
    private static var fileChangeGateway: HelperFileChangeGateway?
    private static var terminationSignalSource: DispatchSourceSignal?

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !Self.didStart else { return }
        Self.didStart = true
        Self.start()
    }

    private static func start() {
        bootstrapLogging()
        let logger = Logger(label: "VoyagerHelper")
        try? EnvironmentLoader.loadEnvFiles()
        EnvironmentLoader.requireAppEnv()
        SentryBootstrap.startIfNeeded(
            appVersion: helperAppVersion(),
            userId: nil,
            component: "helper",
            enableAppHangTracking: false,
        )
        let stateBroadcaster = HelperStateBroadcaster()
        let helperFolderAccessListener = HelperFolderAccessListener()
        let fileChangeGateway = HelperFileChangeGateway(logger: logger)
        logger.info(
            "Starting (APP_ENV=\(Dotenv.appEnv?.rawValue ?? "nil"))",
        )
        VoyagerHelperApp.helperFolderAccessListener = helperFolderAccessListener
        VoyagerHelperApp.stateBroadcaster = stateBroadcaster
        VoyagerHelperApp.fileChangeGateway = fileChangeGateway

        // 마이그레이션 등 DB 초기화가 오래 걸려도 메인 앱 타임아웃 전에 상태를 한 번 보내서 재시작되지 않도록 한다.
        stateBroadcaster.startObservingRequests()
        stateBroadcaster.postCurrentState()
        helperFolderAccessListener.startObservingRequests()
        fileChangeGateway.start()
        installTerminationSignalHandler(logger: logger)

        Task {
            await runStartupTask(
                stateBroadcaster: stateBroadcaster,
            )
        }
    }

    private static func installTerminationSignalHandler(logger: Logger) {
        guard terminationSignalSource == nil else { return }
        signal(SIGTERM, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource.setEventHandler {
            MainActor.assumeIsolated {
                logger.info("Received SIGTERM; stopping helper runtime and exiting helper")
                stop()
                Darwin.exit(0)
            }
        }
        terminationSignalSource = signalSource
        signalSource.resume()
    }

    func applicationWillTerminate(_: Notification) {
        Self.stop()
    }

    private static func stop() {
        stateBroadcaster?.stopObservingRequests()
        stateBroadcaster = nil
        fileChangeGateway?.stop()
    }

    private static func runStartupTask(
        stateBroadcaster: HelperStateBroadcaster,
    ) async {
        stateBroadcaster.markHelperFullyReady()
        stateBroadcaster.postCurrentState()
    }

    /// 로깅 핸들러 구성
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

    private static func helperAppVersion() -> String? {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (shortVersion, build) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        case let (nil, build?):
            return build
        default:
            return nil
        }
    }
}
