import Foundation
import Sentry
import SwiftDotenv

public enum SentryBootstrap {
    public static func startIfNeeded(
        appVersion: String?,
        userId: String?,
        component: String,
        enableAppHangTracking: Bool = true,
    ) {
        guard let dsn = Dotenv["PUBLIC_SENTRY_DSN"]?.stringValue, !dsn.isEmpty else {
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            if let tracesSampleRateValue = Dotenv["PUBLIC_SENTRY_TRACES_SAMPLE_RATE"]?.stringValue,
               let tracesSampleRate = Double(tracesSampleRateValue)
            {
                options.tracesSampleRate = NSNumber(value: tracesSampleRate)
            }
            options.enableLogs = true
            options.enableAppHangTracking = enableAppHangTracking
            if let environment = Dotenv["APP_ENV"]?.stringValue, !environment.isEmpty {
                options.environment = environment
            }
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
