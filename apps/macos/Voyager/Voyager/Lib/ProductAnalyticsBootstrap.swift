import Foundation
import VoyagerShared

private actor ProductAnalyticsRuntime {
    private let provider: PostHogProductAnalyticsProvider
    private var cachedDeviceIdentity: String?

    init(provider: PostHogProductAnalyticsProvider) {
        self.provider = provider
    }

    func capture(_ request: ProductAnalyticsCaptureRequest) async {
        await provider.capture(request)
    }

    func setDeviceIdentity(_ deviceID: String?) {
        cachedDeviceIdentity = deviceID
    }

    func deviceIdentity() -> String? {
        cachedDeviceIdentity
    }
}

public enum ProductAnalyticsBootstrap {
    struct Configuration: Equatable {
        let projectToken: String
        let host: String
    }

    @MainActor
    public static func makeClient(
        environment: [String: String]? = nil,
        urlSessionConfiguration: URLSessionConfiguration? = nil,
        flushAt: Int = 20,
    ) -> ProductAnalyticsClient {
        guard let configuration = configuration(environment: environment) else {
            return .disabled
        }
        guard let provider = PostHogProductAnalyticsProvider(
            projectToken: configuration.projectToken,
            host: configuration.host,
            urlSessionConfiguration: urlSessionConfiguration,
            flushAt: flushAt,
        ) else {
            return .disabled
        }
        let runtime = ProductAnalyticsRuntime(provider: provider)
        return ProductAnalyticsClient(capture: { request in
            Task { await runtime.capture(request) }
        }, setDeviceIdentity: { deviceID in
            await runtime.setDeviceIdentity(deviceID)
        }, deviceIdentity: {
            await runtime.deviceIdentity()
        })
    }

    static func configuration(environment: [String: String]?) -> Configuration? {
        let projectToken: String?
        let host: String?
        if let environment {
            projectToken = environment["PUBLIC_POSTHOG_PROJECT_TOKEN"]
            host = environment["PUBLIC_POSTHOG_HOST"]
        } else {
            projectToken = EnvironmentLoader.stringValue(forKey: "PUBLIC_POSTHOG_PROJECT_TOKEN")
            host = EnvironmentLoader.stringValue(forKey: "PUBLIC_POSTHOG_HOST")
        }
        guard let projectToken = normalized(projectToken), let host = normalizedHost(host) else { return nil }
        return Configuration(projectToken: projectToken, host: host)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func normalizedHost(_ value: String?) -> String? {
        guard let value = normalized(value), let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
        else {
            return nil
        }
        return url.absoluteString
    }
}
