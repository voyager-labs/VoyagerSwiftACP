import Foundation
import PostHog

public actor PostHogProductAnalyticsProvider {
    struct ConfigurationSnapshot: Equatable {
        let projectToken: String
        let host: String
        let flushAt: Int
        let enableSwizzling: Bool
        let captureApplicationLifecycleEvents: Bool
        let captureScreenViews: Bool
        let captureElementInteractions: Bool
        let capturePushNotificationSubscriptions: Bool
        let capturePushNotificationOpened: Bool
        let sessionReplay: Bool
        let preloadFeatureFlags: Bool
        let surveys: Bool
        let rageClicks: Bool
        let errorTrackingAutoCapture: Bool
        let debug: Bool
        let sendFeatureFlagEvent: Bool
        let optOut: Bool
    }

    private let sdk: PostHogSDK

    public init?(
        projectToken: String,
        host: String,
        urlSessionConfiguration: URLSessionConfiguration? = nil,
        flushAt: Int = 20,
    ) {
        guard let configuration = Self.makeConfiguration(
            projectToken: projectToken,
            host: host,
            urlSessionConfiguration: urlSessionConfiguration,
            flushAt: flushAt,
        ) else {
            return nil
        }
        sdk = PostHogSDK.with(configuration)
    }

    public func capture(_ request: ProductAnalyticsCaptureRequest) {
        let event = request.event
        var properties = event.properties.mapValues(Self.postHogValue)
        properties["event_version"] = event.eventVersion.rawValue
        properties["occurred_at_utc"] = ISO8601DateFormatter().string(from: event.occurredAtUTC)
        properties["environment"] = event.environment
        properties["app_version"] = event.appVersion
        properties["platform"] = event.platform
        properties["source"] = event.source
        properties["source_project"] = event.sourceProject
        if let identifiers = event.identifiers {
            properties["interaction_id"] = identifiers.interactionID
            properties["feature_id"] = identifiers.featureID
        }

        sdk.capture(
            event.eventName.rawValue,
            distinctId: event.distinctID,
            properties: properties,
            timestamp: event.occurredAtUTC,
        )
    }

    public func flush() {
        sdk.flush()
    }

    nonisolated static func configurationForTesting(
        projectToken: String,
        host: String,
        flushAt: Int,
    ) -> ConfigurationSnapshot? {
        guard let configuration = makeConfiguration(
            projectToken: projectToken,
            host: host,
            urlSessionConfiguration: nil,
            flushAt: flushAt,
        ) else {
            return nil
        }
        return ConfigurationSnapshot(
            projectToken: configuration.projectToken,
            host: configuration.host.absoluteString,
            flushAt: configuration.flushAt,
            enableSwizzling: configuration.enableSwizzling,
            captureApplicationLifecycleEvents: configuration.captureApplicationLifecycleEvents,
            captureScreenViews: configuration.captureScreenViews,
            captureElementInteractions: false,
            capturePushNotificationSubscriptions: configuration.capturePushNotificationSubscriptions,
            capturePushNotificationOpened: configuration.capturePushNotificationOpened,
            sessionReplay: false,
            preloadFeatureFlags: configuration.preloadFeatureFlags,
            surveys: false,
            rageClicks: false,
            errorTrackingAutoCapture: configuration.errorTrackingConfig.autoCapture,
            debug: configuration.debug,
            sendFeatureFlagEvent: configuration.sendFeatureFlagEvent,
            optOut: configuration.optOut,
        )
    }

    nonisolated private static func makeConfiguration(
        projectToken: String,
        host: String,
        urlSessionConfiguration: URLSessionConfiguration?,
        flushAt: Int,
    ) -> PostHogConfig? {
        guard let projectToken = normalized(projectToken), let host = normalizedHost(host) else { return nil }
        let configuration = PostHogConfig(projectToken: projectToken, host: host)
        configuration.flushAt = flushAt
        configuration.enableSwizzling = false
        configuration.captureApplicationLifecycleEvents = false
        configuration.captureScreenViews = false
        configuration.capturePushNotificationSubscriptions = false
        configuration.capturePushNotificationOpened = false
        configuration.preloadFeatureFlags = false
        configuration.sendFeatureFlagEvent = false
        configuration.errorTrackingConfig.autoCapture = false
        configuration.urlSessionConfiguration = urlSessionConfiguration
        #if os(iOS)
        configuration.captureElementInteractions = false
        configuration.sessionReplay = false
        configuration.surveys = false
        #endif
        return configuration
    }

    nonisolated private static func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func normalizedHost(_ value: String) -> String? {
        guard let value = normalized(value), let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
        else {
            return nil
        }
        return url.absoluteString
    }

    nonisolated private static func postHogValue(_ value: ProductAnalyticsPropertyValue) -> Any {
        switch value {
        case let .string(value): value
        case let .integer(value): value
        case let .double(value): value
        case let .boolean(value): value
        }
    }
}
