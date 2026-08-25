import Foundation
import VoyagerShared

private actor ProductAnalyticsRuntime {
    private let provider: PostHogProductAnalyticsProvider
    private let registry: ProductAnalyticsRegistry
    private var cachedDeviceIdentity: String?
    private let continuation: AsyncStream<Work>.Continuation

    fileprivate enum Work {
        case metric(ProductAnalyticsMetricRequest)
        case setDeviceIdentity(String?, CheckedContinuation<Void, Never>)
    }

    init(
        provider: PostHogProductAnalyticsProvider,
        registry: ProductAnalyticsRegistry,
        deviceIdentity: String,
    ) {
        self.provider = provider
        self.registry = registry
        cachedDeviceIdentity = deviceIdentity
        var continuation: AsyncStream<Work>.Continuation!
        let stream = AsyncStream<Work> {
            continuation = $0
        }
        self.continuation = continuation
        Task { await self.consume(stream) }
    }

    @discardableResult
    nonisolated fileprivate func enqueue(_ work: Work) -> AsyncStream<Work>.Continuation.YieldResult {
        continuation.yield(work)
    }

    private func consume(_ stream: AsyncStream<Work>) async {
        for await work in stream {
            switch work {
            case let .metric(request):
                let result = registry.resolve(
                    metricKey: request.metricKey,
                    identity: .device(cachedDeviceIdentity),
                    context: request.context,
                    properties: request.properties,
                    eventVersion: request.eventVersion,
                    operationID: request.operationID,
                )
                if case let .capture(captureRequest) = result {
                    await provider.capture(captureRequest)
                }
            case let .setDeviceIdentity(deviceID, acknowledgement):
                cachedDeviceIdentity = deviceID
                acknowledgement.resume()
            }
        }
    }

    func setDeviceIdentity(_ deviceID: String?) async {
        await withCheckedContinuation { acknowledgement in
            let result = enqueue(.setDeviceIdentity(deviceID, acknowledgement))
            switch result {
            case .enqueued:
                break
            case .dropped:
                acknowledgement.resume()
            case .terminated:
                acknowledgement.resume()
            @unknown default:
                acknowledgement.resume()
            }
        }
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

    static let installationIDKey = "ProductAnalytics.installationID"

    @MainActor
    public static func makeClient(
        environment: [String: String]? = nil,
        urlSessionConfiguration: URLSessionConfiguration? = nil,
        flushAt: Int = 20,
        registry: ProductAnalyticsRegistry = .load(),
        userDefaults: UserDefaults = .standard,
        makeInstallationID: @escaping @Sendable () -> UUID = UUID.init,
    ) -> ProductAnalyticsClient {
        let installationID = persistedInstallationID(in: userDefaults, makeInstallationID: makeInstallationID)
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
        let runtime = ProductAnalyticsRuntime(
            provider: provider,
            registry: registry,
            deviceIdentity: installationID,
        )
        return ProductAnalyticsClient(captureMetric: { request in
            switch runtime.enqueue(.metric(request)) {
            case .enqueued, .dropped, .terminated:
                break
            @unknown default:
                break
            }
        }, setDeviceIdentity: { deviceID in
            await runtime.setDeviceIdentity(deviceID)
        }, deviceIdentity: {
            await runtime.deviceIdentity()
        })
    }

    static func persistedInstallationID(
        in userDefaults: UserDefaults,
        makeInstallationID: @escaping @Sendable () -> UUID = UUID.init,
    ) -> String {
        if let value = userDefaults.string(forKey: installationIDKey), !value.isEmpty {
            return value
        }
        let value = makeInstallationID().uuidString
        userDefaults.set(value, forKey: installationIDKey)
        return value
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
