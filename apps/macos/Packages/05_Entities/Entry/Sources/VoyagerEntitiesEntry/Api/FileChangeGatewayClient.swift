import ComposableArchitecture
import Foundation
import VoyagerShared

public struct FileChangeGatewayClient: Sendable {
    public var observeEvents: @Sendable () -> AsyncStream<[FileChangeGatewayEvent]>
    public var updateInterests: @Sendable ([FileChangeWatchInterest]) -> Void
    public var removeInterests: @Sendable ([String]) -> Void

    nonisolated public init(
        observeEvents: @escaping @Sendable () -> AsyncStream<[FileChangeGatewayEvent]>,
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
        )
    }
}

public extension DependencyValues {
    nonisolated var fileChangeGatewayClient: FileChangeGatewayClient {
        get { self[FileChangeGatewayClient.self] }
        set { self[FileChangeGatewayClient.self] = newValue }
    }
}
