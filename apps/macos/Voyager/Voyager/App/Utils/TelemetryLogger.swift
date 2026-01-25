import Foundation
import Sentry

enum MetricLogLevel {
    case trace
    case debug
    case info
    case warn
    case error
    case fatal
}

enum TelemetryLogger {
    static func logMetric(
        _ name: String,
        value: Double,
        tags: [String: String]? = nil,
        level: MetricLogLevel = .info,
    ) {
        var attributes: [String: Any] = [
            "metric.name": name,
            "metric.value": value,
        ]
        if let deviceId = DeviceIdentifierProvider.current() {
            attributes["metric.user_id"] = deviceId
        }
        if let tags {
            for (key, tagValue) in tags {
                attributes["metric.tag.\(key)"] = tagValue
            }
        }
        switch level {
        case .trace:
            SentrySDK.logger.trace("metric", attributes: attributes)
        case .debug:
            SentrySDK.logger.debug("metric", attributes: attributes)
        case .info:
            SentrySDK.logger.info("metric", attributes: attributes)
        case .warn:
            SentrySDK.logger.warn("metric", attributes: attributes)
        case .error:
            SentrySDK.logger.error("metric", attributes: attributes)
        case .fatal:
            SentrySDK.logger.fatal("metric", attributes: attributes)
        }
    }
}
