import ComposableArchitecture
import Foundation
import os
import VoyagerShared

public struct FileChangeGatewayClient: Sendable {
    public var observeEvents: @Sendable () -> AsyncStream<[FileChangeGatewayEvent]>
    public var updateInterests: @Sendable ([FileChangeWatchInterest]) -> Void
    public var removeInterests: @Sendable ([String]) -> Void
    public var currentDeliveryChainToken: @Sendable () -> String?

    nonisolated public init(
        observeEvents: @escaping @Sendable () -> AsyncStream<[FileChangeGatewayEvent]>,
        updateInterests: @escaping @Sendable ([FileChangeWatchInterest]) -> Void,
        removeInterests: @escaping @Sendable ([String]) -> Void,
        currentDeliveryChainToken: @escaping @Sendable () -> String? = { nil },
    ) {
        self.observeEvents = observeEvents
        self.updateInterests = updateInterests
        self.removeInterests = removeInterests
        self.currentDeliveryChainToken = currentDeliveryChainToken
    }
}

private final class FileChangeGatewayDeliveryContext: @unchecked Sendable {
    private let lock = NSLock()
    private var chainToken: String?

    func update(_ chainToken: String) {
        lock.lock()
        self.chainToken = chainToken
        lock.unlock()
    }

    func current() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return chainToken
    }
}

extension FileChangeGatewayClient: DependencyKey {
    nonisolated public static let liveValue = FileChangeGatewayClient.live()

    nonisolated public static let testValue = FileChangeGatewayClient(
        observeEvents: { AsyncStream { _ in } },
        updateInterests: { _ in },
        removeInterests: { _ in },
    )

    nonisolated private static func live() -> FileChangeGatewayClient {
        let deliveryContext = FileChangeGatewayDeliveryContext()
        return FileChangeGatewayClient(
            observeEvents: {
                AsyncStream { continuation in
                    final class ObserverBox: @unchecked Sendable {
                        var token: (any NSObjectProtocol)?
                    }

                    let box = ObserverBox()
                    box.token = DistributedNotificationCenter.default().addObserver(
                        forName: .voyagerFileChangeGatewayEvents,
                        object: nil,
                        queue: .main,
                    ) { notification in
                        let events = FileChangeGatewayPayload.events(from: notification.userInfo)
                        guard !events.isEmpty else { return }
                        if let chainToken = fileChangeGatewayDeliveryChainToken(from: notification.userInfo) {
                            deliveryContext.update(chainToken)
                            logFileChangeGatewayDeliveryMarker(
                                "fs_notification_received",
                                events: events,
                                chainToken: chainToken,
                                latencyFrom: events.map(\.emittedAt).min(),
                            )
                        }
                        continuation.yield(events)
                    }

                    continuation.onTermination = { @Sendable _ in
                        if let token = box.token {
                            DistributedNotificationCenter.default().removeObserver(token)
                        }
                    }
                }
            },
            updateInterests: { interests in
                DistributedNotificationCenter.default().post(
                    name: .voyagerFileChangeGatewayInterestsUpdated,
                    object: nil,
                    userInfo: FileChangeGatewayPayload.userInfo(forInterests: interests),
                )
            },
            removeInterests: { ids in
                DistributedNotificationCenter.default().post(
                    name: .voyagerFileChangeGatewayInterestsRemoved,
                    object: nil,
                    userInfo: FileChangeGatewayPayload.userInfo(forRemovedInterestIDs: ids),
                )
            },
            currentDeliveryChainToken: { deliveryContext.current() },
        )
    }
}

public extension DependencyValues {
    nonisolated var fileChangeGatewayClient: FileChangeGatewayClient {
        get { self[FileChangeGatewayClient.self] }
        set { self[FileChangeGatewayClient.self] = newValue }
    }
}

nonisolated func fileChangeGatewayDeliveryChainToken(
    from userInfo: [AnyHashable: Any]?,
) -> String? {
    guard let token = userInfo?["deliveryChainToken"] as? String,
          UUID(uuidString: token) != nil
    else {
        return nil
    }
    return token.lowercased()
}

private let fileChangeGatewayDeliveryLogger = os.Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "fm.voyager.Voyager",
    category: "FileChangeGateway",
)

private func logFileChangeGatewayDeliveryMarker(
    _ marker: String,
    events: [FileChangeGatewayEvent],
    chainToken: String,
    latencyFrom: Date?,
    timestamp: Date = Date(),
) {
    let flags = events.reduce(UInt32(0)) { $0 | $1.flags }
    var message = "voyager.fs.delivery marker=\(marker) ts=\(timestamp.timeIntervalSince1970)"
    message += " eventCount=\(events.count) flagsSummary=\(String(format: "0x%llx", UInt64(flags)))"
    let latencyMs = max(0, timestamp.timeIntervalSince(latencyFrom ?? timestamp) * 1000)
    message += " latencyMs=\(latencyMs) chainToken=\(chainToken)"
    fileChangeGatewayDeliveryLogger.info("\(message, privacy: .public)")
}
