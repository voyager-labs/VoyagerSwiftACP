import ComposableArchitecture
import Foundation
import os
import VoyagerShared

public struct FileChangeGatewayClient: Sendable {
    public var observeEvents: @Sendable () -> AsyncStream<FileChangeGatewayEventBatch>
    public var updateInterests: @Sendable ([FileChangeWatchInterest]) -> Void
    public var removeInterests: @Sendable ([String]) -> Void

    nonisolated public init(
        observeEvents: @escaping @Sendable () -> AsyncStream<FileChangeGatewayEventBatch>,
        updateInterests: @escaping @Sendable ([FileChangeWatchInterest]) -> Void,
        removeInterests: @escaping @Sendable ([String]) -> Void,
    ) {
        self.observeEvents = observeEvents
        self.updateInterests = updateInterests
        self.removeInterests = removeInterests
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
        FileChangeGatewayClient(
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
                        let deliveryChainToken = fileChangeGatewayDeliveryChainToken(from: notification.userInfo)
                        if let deliveryChainToken {
                            logFileChangeGatewayDeliveryMarker(
                                "fs_notification_received",
                                events: events,
                                chainToken: deliveryChainToken,
                                latencyFrom: events.map(\.emittedAt).min(),
                            )
                        }
                        continuation.yield(.init(
                            events: events,
                            deliveryChainToken: deliveryChainToken,
                        ))
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
