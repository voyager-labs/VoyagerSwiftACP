import Foundation

@MainActor
final class HelperExternalFileChangeBridge {
    nonisolated(unsafe) private var replayObserver: NSObjectProtocol?
    nonisolated(unsafe) private var replayAckObserver: NSObjectProtocol?
    private let store: HelperExternalFileChangeStore

    init(store: HelperExternalFileChangeStore = HelperExternalFileChangeStore()) {
        self.store = store
    }

    deinit {
        guard let replayObserver else { return }
        DistributedNotificationCenter.default().removeObserver(replayObserver)
        if let replayAckObserver {
            DistributedNotificationCenter.default().removeObserver(replayAckObserver)
        }
    }

    func startObservingReplayRequests() {
        guard replayObserver == nil else { return }
        replayObserver = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperFSReplayRequest,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }
            let request = HelperExternalFileChangeReplayRequest.from(userInfo: notification.userInfo) ?? .init()
            Task { @MainActor in
                await self.respondToReplayRequest(request)
            }
        }

        replayAckObserver = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperFSReplayAck,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }
            let acknowledgedPayload = HelperExternalFileChangePayload.from(
                userInfo: notification.userInfo,
                allowEmptyPaths: true,
            )
            Task { @MainActor in
                if let payload = acknowledgedPayload {
                    _ = try? await self.store.remove(payload.paths)
                } else {
                    try? await self.store.clear()
                }
            }
        }
    }

    func publishChangedPaths(_ paths: [String], generatedAt: Date = Date()) async {
        let payload = HelperExternalFileChangePayload(paths: paths, generatedAt: generatedAt)
        guard !payload.paths.isEmpty else { return }
        _ = try? await store.coalesce(payload.paths, generatedAt: generatedAt)

        DistributedNotificationCenter.default().post(
            name: .voyagerHelperFSChanged,
            object: nil,
            userInfo: payload.asUserInfo(),
        )
    }

    private func respondToReplayRequest(_ request: HelperExternalFileChangeReplayRequest) async {
        guard let payload = try? await store.payloadForReplay(request) else { return }
        DistributedNotificationCenter.default().post(
            name: .voyagerHelperFSReplay,
            object: nil,
            userInfo: payload.asUserInfo(),
        )
    }
}
