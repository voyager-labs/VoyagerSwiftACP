import ComposableArchitecture
import Foundation

struct HelperExternalFileChangeEvent: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case live
        case replay
    }

    var paths: [String]
    var source: Source
}

struct HelperExternalFileChangeClient: Sendable {
    var observeChangedPaths: @Sendable () -> AsyncStream<HelperExternalFileChangeEvent>
    var acknowledgeDeliveredPaths: @Sendable ([String]) async -> Void
    var updateWatchRoots: @Sendable ([String]) async -> Void
}

extension HelperExternalFileChangeClient: DependencyKey {
    nonisolated static let liveValue = Self(
        observeChangedPaths: {
            AsyncStream { continuation in
                let center = DistributedNotificationCenter.default()
                final class ObserverBag: @unchecked Sendable {
                    var tokens: [NSObjectProtocol] = []
                }
                let bag = ObserverBag()

                let liveToken = center.addObserver(
                    forName: .voyagerHelperFSChanged,
                    object: nil,
                    queue: .main,
                ) { notification in
                    guard let payload = HelperExternalFileChangePayload.from(userInfo: notification.userInfo)
                    else { return }
                    continuation.yield(.init(paths: payload.paths, source: .live))
                }

                let replayToken = center.addObserver(
                    forName: .voyagerHelperFSReplay,
                    object: nil,
                    queue: .main,
                ) { notification in
                    guard let payload = HelperExternalFileChangePayload.from(userInfo: notification.userInfo)
                    else { return }
                    continuation.yield(.init(paths: payload.paths, source: .replay))
                }

                bag.tokens = [liveToken, replayToken]

                center.post(
                    name: .voyagerHelperFSReplayRequest,
                    object: nil,
                    userInfo: HelperExternalFileChangeReplayRequest(consume: false).asUserInfo(),
                )

                continuation.onTermination = { @Sendable _ in
                    let tokens = bag.tokens
                    let center = DistributedNotificationCenter.default()
                    tokens.forEach(center.removeObserver)
                }
            }
        },
        acknowledgeDeliveredPaths: { paths in
            let payload = HelperExternalFileChangePayload(paths: paths)
            DistributedNotificationCenter.default().post(
                name: .voyagerHelperFSReplayAck,
                object: nil,
                userInfo: payload.asUserInfo(),
            )
        },
        updateWatchRoots: { paths in
            let payload = HelperExternalFileChangePayload(paths: paths)
            DistributedNotificationCenter.default().post(
                name: .voyagerHelperFSWatchRootsChanged,
                object: nil,
                userInfo: payload.asUserInfo(),
            )
        },
    )

    nonisolated static let testValue = Self(
        observeChangedPaths: { AsyncStream { $0.finish() } },
        acknowledgeDeliveredPaths: { _ in },
        updateWatchRoots: { _ in },
    )
}

extension DependencyValues {
    nonisolated var helperExternalFileChangeClient: HelperExternalFileChangeClient {
        get { self[HelperExternalFileChangeClient.self] }
        set { self[HelperExternalFileChangeClient.self] = newValue }
    }
}
