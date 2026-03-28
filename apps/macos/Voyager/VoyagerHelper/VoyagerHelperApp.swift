import Foundation
import Logging
import SwiftDotenv

@main
class VoyagerHelperApp {
    private static var helperFolderAccessListener: HelperFolderAccessListener?
    private static var helperExternalFileChangeBridge: HelperExternalFileChangeBridge?
    private static var helperExternalFileSystemWatcher: HelperExternalFileSystemWatcher?

    @MainActor
    static func main() {
        bootstrapLogging()
        let logger = Logger(label: "VoyagerHelper")
        try? EnvironmentLoader.loadEnvFiles()
        SentryBootstrap.startIfNeeded(
            appVersion: helperAppVersion(),
            userId: nil,
            component: "helper",
        )
        let stateBroadcaster = HelperStateBroadcaster()
        let helperFolderAccessListener = HelperFolderAccessListener()
        let helperExternalFileChangeBridge = HelperExternalFileChangeBridge()
        let helperExternalFileSystemWatcher = HelperExternalFileSystemWatcher { paths in
            await helperExternalFileChangeBridge.publishChangedPaths(paths)
        }

        logger.info(
            "Starting (APP_ENV=\(Dotenv.appEnv?.rawValue ?? "nil"))",
        )
        VoyagerHelperApp.helperFolderAccessListener = helperFolderAccessListener
        VoyagerHelperApp.helperExternalFileChangeBridge = helperExternalFileChangeBridge
        VoyagerHelperApp.helperExternalFileSystemWatcher = helperExternalFileSystemWatcher

        // 마이그레이션 등 DB 초기화가 오래 걸려도 메인 앱 타임아웃 전에 상태를 한 번 보내서 재시작되지 않도록 한다.
        stateBroadcaster.startObservingRequests()
        stateBroadcaster.postCurrentState()
        helperFolderAccessListener.startObservingRequests()
        helperExternalFileChangeBridge.startObservingReplayRequests()
        helperExternalFileSystemWatcher.start()

        Task {
            await runStartupTask(
                stateBroadcaster: stateBroadcaster,
            )
        }
        RunLoop.current.run()
    }

    private static func runStartupTask(
        stateBroadcaster: HelperStateBroadcaster,
    ) async {
        stateBroadcaster.markHelperFullyReady()
        stateBroadcaster.postCurrentState()
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
