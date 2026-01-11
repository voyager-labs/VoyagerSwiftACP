import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

public struct BackendEndpointClient: Sendable {
    public var resolve: @Sendable () async -> URL?

    public nonisolated init(resolve: @escaping @Sendable () async -> URL?) {
        self.resolve = resolve
    }
}

extension BackendEndpointClient: DependencyKey {
    public nonisolated static var liveValue: BackendEndpointClient {
        let resolver = BackendEndpointResolver()
        return BackendEndpointClient(resolve: {
            await resolver.resolveEndpoint()
        })
    }

    public nonisolated static var testValue: BackendEndpointClient {
        BackendEndpointClient(resolve: { nil })
    }

    public nonisolated static var previewValue: BackendEndpointClient {
        BackendEndpointClient(resolve: { nil })
    }
}

public extension DependencyValues {
    nonisolated var backendEndpointClient: BackendEndpointClient {
        get { self[BackendEndpointClient.self] }
        set { self[BackendEndpointClient.self] = newValue }
    }
}

private actor BackendEndpointResolver {
    private let logger = Logger(label: "Voyager")
    private var cachedEndpoint: URL?
    private var waiters: [CheckedContinuation<URL?, Never>] = []
    private var observer: NotificationObserver?
    private var warningTask: Task<Void, Never>?

    deinit {
        guard let observer else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(observer.token)
        }
    }

    func resolveEndpoint() async -> URL? {
        await ensureObserver()
        if let cachedEndpoint {
            return cachedEndpoint
        }
        scheduleMissingNotificationWarning()

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func handle(endpoint: URL?) async {
        guard let endpoint else {
            logger.error("Failed to parse backend endpoint notification")
            return
        }

        cachedEndpoint = endpoint
        cancelMissingNotificationWarning()
        updateDotenv(endpoint: endpoint)

        if !waiters.isEmpty {
            let currentWaiters = waiters
            waiters.removeAll()
            currentWaiters.forEach { $0.resume(returning: endpoint) }
        }
    }

    private func scheduleMissingNotificationWarning() {
        guard warningTask == nil else { return }
        warningTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await self?.logMissingNotificationWarningIfNeeded()
        }
    }

    private func cancelMissingNotificationWarning() {
        warningTask?.cancel()
        warningTask = nil
    }

    private func logMissingNotificationWarningIfNeeded() async {
        guard cachedEndpoint == nil else {
            warningTask = nil
            return
        }
        if Task.isCancelled {
            warningTask = nil
            return
        }
        logger.warning("Backend endpoint notification not received yet; waiting.")
        warningTask = nil
    }

    private func ensureObserver() async {
        guard observer == nil else { return }
        let token = await MainActor.run {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: .backendEndpointDidUpdate,
                object: nil,
                queue: .main,
            ) { [weak self] notification in
                guard let self else { return }
                let endpoint = Self.parseEndpoint(from: notification.userInfo)
                Task { await self.handle(endpoint: endpoint) }
            }
            return NotificationObserver(token: observer)
        }
        observer = token
    }

    private nonisolated static func parseEndpoint(from info: [AnyHashable: Any]?) -> URL? {
        let info = info ?? [:]

        if let urlString = info["url"] as? String,
           let url = URL(string: urlString)
        {
            return url
        }

        let host = info["host"] as? String
        let port = parsePort(from: info["port"])

        guard let host, let port else {
            return nil
        }

        return URL(string: "http://\(host):\(port)")
    }

    private nonisolated static func parsePort(from value: Any?) -> Int? {
        if let port = value as? Int {
            return port
        }

        if let portString = value as? String {
            return Int(portString)
        }

        return nil
    }

    private func updateDotenv(endpoint: URL) {
        if let host = endpoint.host, !host.isEmpty {
            Dotenv.set(value: host, forKey: "PUBLIC_BACKEND_HOST", overwrite: true)
        }

        if let port = endpoint.port {
            Dotenv.set(value: String(port), forKey: "PUBLIC_BACKEND_PORT", overwrite: true)
        }

        Dotenv.set(value: endpoint.absoluteString, forKey: "PUBLIC_BACKEND_URL", overwrite: true)
        logger.info("Backend endpoint updated: \(endpoint.absoluteString)")
    }
}

private struct NotificationObserver: @unchecked Sendable {
    let token: NSObjectProtocol
}
