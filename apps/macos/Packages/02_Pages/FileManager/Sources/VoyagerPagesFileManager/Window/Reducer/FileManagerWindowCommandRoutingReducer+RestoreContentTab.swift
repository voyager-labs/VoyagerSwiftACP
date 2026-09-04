import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

extension FileManagerWindowCommandRoutingReducer {
    // MARK: - Restore Last Closed Content Tab

    enum RestoreFailureReason {
        case missingDirectory
        case missingCollection
        case unsupportedAIChat
    }

    func handleRestoreLastClosedContentTab(
        state: inout State,
        actionSource: ContentTabActionSource = .contentTabBar,
    ) -> Effect<Action> {
        guard state.pendingContentTabClose == nil else { return .none }

        guard let snapshot = state.contentTabs.recentlyClosed else { return .none }

        guard state.contentTabs.tabs.count < ContentTabConstants.maxTabs else { return .none }

        if let reason = restoreFailureReason(for: snapshot, state: state) {
            state.contentTabs.recentlyClosed = nil
            return restoreFailureFeedbackEffect(reason)
        }

        let restoreEffect: Effect<Action> = actionSource == .contentTabBar
            ? .send(.contentTabs(.restore))
            : .send(.contentTabActionRequested(.restore, source: actionSource))
        return .concatenate(
            restoreEffect,
            .send(.contentTabs(.collapseSelectionToActive)),
        )
    }

    func restoreFailureReason(
        for snapshot: ClosedContentTabSnapshot,
        state _: State,
    ) -> RestoreFailureReason? {
        switch snapshot.anchor {
        case .homeDefault:
            return nil

        case let .directory(path):
            var isDirectory = ObjCBool(false)
            guard fileManagerClient.fileExistsWithIsDirectory(path, &isDirectory),
                  isDirectory.boolValue
            else { return .missingDirectory }
            return nil

        case let .collectionFile(url):
            guard fileManagerClient.fileExistsWithIsDirectory(url.path, nil)
            else { return .missingCollection }
            return nil

        case .virtualCollection:
            return nil

        case .aiChat:
            return .unsupportedAIChat
        }
    }

    func restoreFailureFeedbackEffect(_ reason: RestoreFailureReason) -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        let message = switch reason {
        case .missingDirectory, .missingCollection:
            "The recently closed tab is no longer available."
        case .unsupportedAIChat:
            "AI Chat tabs cannot be restored yet."
        }
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Restore Tab",
                message,
            )
        }
    }
}
