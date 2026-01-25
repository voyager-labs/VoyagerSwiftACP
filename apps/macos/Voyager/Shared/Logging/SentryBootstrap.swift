import Foundation
import Sentry
import SwiftDotenv

enum SentryBootstrap {
    static func startIfNeeded(
        appVersion: String?,
        userId: String?,
        component: String,
    ) {
        guard let dsn = Dotenv["SENTRY_DSN"]?.stringValue, !dsn.isEmpty else {
            return
        }
        let tracesSampleRate = Double(Dotenv["SENTRY_TRACES_SAMPLE_RATE"]?.stringValue ?? "") ?? 0.05
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.tracesSampleRate = NSNumber(value: tracesSampleRate)
            options.enableLogs = true
        }
        // 공통 태그/유저 식별자 설정
        SentrySDK.configureScope { scope in
            if let appVersion {
                scope.setTag(value: appVersion, key: "app_version")
            }
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            scope.setTag(value: osVersion, key: "os_version")
            scope.setTag(value: component, key: "app_component")
            if let userId {
                scope.setUser(Sentry.User(userId: userId))
            }
        }
    }
}
