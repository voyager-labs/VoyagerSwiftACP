import Foundation

@MainActor
final class HelperExternalFileChangeBridge {
    private nonisolated(unsafe) var replayObserver: NSObjectProtocol?
    private let store: HelperExternalFileChangeStore

    init(store: HelperExternalFileChangeStore = HelperExternalFileChangeStore()) {
        self.store = store
    }

    deinit {
        guard let replayObserver else { return }
        Task { @MainActor in
            DistributedNotificationCenter.default().removeObserver(replayObserver)
        }
    }

    func startObservingReplayRequests() {
        guard replayObserver == nil else { return }

        replayObserver = DistributedNotificationCenter.default().addObserver(
            forName: .voyagerHelperExternalFSReplayRequest,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }
            let request = HelperExternalFileChangeReplayRequest.from(userInfo: notification.userInfo) ?? .init()
            Task { @MainActor in
                await self.respondToReplayRequest(request)
            }
        }
    }

    func publishChangedPaths(_ paths: [String], generatedAt: Date = Date()) async {
        let payload = HelperExternalFileChangePayload(paths: paths, generatedAt: generatedAt)
        guard !payload.paths.isEmpty else { return }

        _ = try? await store.coalesce(payload.paths, generatedAt: generatedAt)

        DistributedNotificationCenter.default().post(
            name: .voyagerHelperExternalFSDidUpdate,
            object: nil,
            userInfo: payload.asUserInfo(),
        )
    }

    private func respondToReplayRequest(_ request: HelperExternalFileChangeReplayRequest) async {
        guard let payload = try? await store.payloadForReplay(request) else { return }

        DistributedNotificationCenter.default().post(
            name: .voyagerHelperExternalFSReplayDidUpdate,
            object: nil,
            userInfo: payload.asUserInfo(),
        )
    }
}
