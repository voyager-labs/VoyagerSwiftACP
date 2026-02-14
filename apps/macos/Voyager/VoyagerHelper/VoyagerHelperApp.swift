import Foundation
import Logging
import SwiftDotenv

@main
class VoyagerHelperApp {
    private static var indexingListener: IndexingRequestListener?
    private static var helperFolderAccessListener: HelperFolderAccessListener?

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
        let indexingListener = IndexingRequestListener(
            manager: DatabaseManager.shared,
            logger: logger,
        )
        let helperFolderAccessListener = HelperFolderAccessListener()

        logger.info(
            "Starting (APP_ENV=\(Dotenv.appEnv?.rawValue ?? "nil"))",
        )
        VoyagerHelperApp.indexingListener = indexingListener
        VoyagerHelperApp.helperFolderAccessListener = helperFolderAccessListener

        // 마이그레이션 등 DB 초기화가 오래 걸려도 메인 앱 타임아웃 전에 상태를 한 번 보내서 재시작되지 않도록 한다.
        stateBroadcaster.startObservingRequests()
        stateBroadcaster.postCurrentState()
        helperFolderAccessListener.startObservingRequests()

        Task {
            await runStartupTask(
                stateBroadcaster: stateBroadcaster,
                indexingListener: indexingListener,
                logger: logger,
            )
        }
        RunLoop.current.run()
    }

    private static func runStartupTask(
        stateBroadcaster: HelperStateBroadcaster,
        indexingListener: IndexingRequestListener,
        logger: Logger,
    ) async {
        do {
            try await DatabaseManager.shared.initialize()
        } catch {
            logger.error("Database initialization failed: \(error)")
            exit(EXIT_FAILURE)
        }
        stateBroadcaster.markHelperFullyReady()
        stateBroadcaster.postCurrentState()
        await indexingListener.prepare()
        indexingListener.startObservingRequests()
        Task {
            do {
                if await indexingListener.hasCompletedInitialIndexing() {
                    await IncrementalIndexingValidator.startIfReady(
                        manager: DatabaseManager.shared,
                        logger: logger,
                    )
                }
            } catch {
                logger.error("Initial indexing failed: \(error)")
                exit(EXIT_FAILURE)
            }
        }
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
