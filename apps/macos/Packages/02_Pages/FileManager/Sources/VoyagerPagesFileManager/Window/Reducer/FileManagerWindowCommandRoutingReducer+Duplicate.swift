import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryOperations

private enum DuplicateFailureReason {
    case missingDirectory
    case missingCollectionFile
    case invalidAiChatSession
    case temporaryCollection
    case collectionOperationInProgress
    case tabLimitReached

    var message: String {
        switch self {
        case .missingDirectory: "The directory no longer exists."
        case .missingCollectionFile: "The collection file no longer exists."
        case .invalidAiChatSession: "The AI Chat session is no longer valid."
        case .temporaryCollection: "Cannot duplicate a temporary collection. Save the collection first."
        case .collectionOperationInProgress: "Wait for the current collection operation to finish, then try again."
        case .tabLimitReached: "The tab limit was reached."
        }
    }
}

private struct DuplicateSkip {
    let sourceTitle: String?
    let reason: DuplicateFailureReason
}

extension FileManagerWindowCommandRoutingReducer {
    func handleDuplicateContentTabRequested(sourceID: ContentTabID, state: inout State) -> Effect<Action> {
        guard state.pendingContentTabClose == nil, state.pendingContentTabTeardown == nil else { return .none }
        guard let source = state.contentTabs.tabs[id: sourceID],
              state.contentTabs.tabs.count < ContentTabConstants.maxTabs
        else {
            return .none
        }
        let sourceContentState: FileManagerContentFeature.State? = sourceID == state.contentTabs.activeTabID
            ? state.content
            : state.tabContentStates[sourceID]
        if let failureReason = duplicateFailureReason(for: source.anchor, contentState: sourceContentState) {
            return duplicateFailureFeedbackEffect(failureReason)
        }
        return .send(.contentTabs(.duplicate(sourceID: sourceID, duplicateID: ContentTabID())))
    }

    func handleDuplicateSelectedContentTabsRequested(state: inout State) -> Effect<Action> {
        guard state.pendingContentTabClose == nil, state.pendingContentTabTeardown == nil else { return .none }
        let orderedSources = state.contentTabs.orderedValidSelectedTabIDs.compactMap { state.contentTabs.tabs[id: $0] }
        guard orderedSources.count > 1 else { return .none }
        var validSources: [ContentTabItem] = []
        var skips: [DuplicateSkip] = []
        for source in orderedSources {
            let sourceContentState = source.id == state.contentTabs.activeTabID ? state.content : state
                .tabContentStates[source.id]
            if let failureReason = duplicateFailureReason(for: source.anchor, contentState: sourceContentState) {
                skips.append(DuplicateSkip(sourceTitle: source.title, reason: failureReason))
            } else {
                validSources.append(source)
            }
        }
        let remainingCapacity = max(0, ContentTabConstants.maxTabs - state.contentTabs.tabs.count)
        let successfulSources = Array(validSources.prefix(remainingCapacity))
        skips.append(contentsOf: validSources.dropFirst(successfulSources.count).map {
            DuplicateSkip(sourceTitle: $0.title, reason: .tabLimitReached)
        })
        var reservedIDs = Set(state.contentTabs.tabs.ids)
        let requests = successfulSources.map {
            ContentTabDuplicateRequest(sourceID: $0.id, duplicateID: makeFreshDuplicateID(reservedIDs: &reservedIDs))
        }
        let feedbackEffect = aggregateDuplicateFeedbackEffect(
            successCount: requests.count,
            skippedCount: skips.count,
            skips: skips,
            unavailableCount: 0,
        )
        guard !requests.isEmpty else { return feedbackEffect }
        let duplicateEffect: Effect<Action> = .send(.contentTabs(.duplicateSelected(requests)))
        guard !skips.isEmpty else { return duplicateEffect }
        return .concatenate(duplicateEffect, feedbackEffect)
    }

    func makeFreshDuplicateID(reservedIDs: inout Set<ContentTabID>) -> ContentTabID {
        let baseRawValue = uuid().uuidString
        let preferredID = ContentTabID(rawValue: baseRawValue)
        if reservedIDs.insert(preferredID).inserted { return preferredID }
        for suffix in 1 ... reservedIDs.count {
            let fallbackID = ContentTabID(rawValue: "\(baseRawValue)-\(suffix)")
            if reservedIDs.insert(fallbackID).inserted { return fallbackID }
        }
        let fallbackID = ContentTabID(rawValue: "\(baseRawValue)-\(reservedIDs.count + 1)")
        reservedIDs.insert(fallbackID)
        return fallbackID
    }

    private func duplicateFailureReason(
        for anchor: ContentTabPageAnchor,
        contentState: FileManagerContentFeature.State?,
    ) -> DuplicateFailureReason? {
        if let contentState,
           case let .collection(navigation) = contentState.navigation.navigationState,
           case .temporary = navigation.kind
        {
            return .temporaryCollection
        }
        switch anchor {
        case .homeDefault, .virtualCollection:
            return nil
        case let .directory(path):
            var isDirectory = ObjCBool(false)
            guard fileManagerClient.fileExistsWithIsDirectory(path, &isDirectory), isDirectory.boolValue else {
                return .missingDirectory
            }
            return nil
        case let .collectionFile(url):
            guard fileManagerClient.fileExistsWithIsDirectory(url.path, nil) else { return .missingCollectionFile }
            if let collection = contentState?.collection,
               collection.isSaving || collection.collectionSession.phase.isOpening
               || collection.collectionSession.phase.isInflightRefresh
               || collection.collectionSession.phase.isInflightWriteBack
            {
                return .collectionOperationInProgress
            }
            return nil
        case let .aiChat(sessionID):
            return UUID(uuidString: sessionID) == nil ? .invalidAiChatSession : nil
        }
    }

    private func duplicateFailureFeedbackEffect(_ reason: DuplicateFailureReason) -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert("Cannot Duplicate Tab", reason.message)
        }
    }

    private func aggregateDuplicateFeedbackEffect(
        successCount: Int,
        skippedCount: Int,
        skips: [DuplicateSkip],
        unavailableCount: Int,
    ) -> Effect<Action> {
        guard skippedCount > 0 else { return .none }
        let title = successCount > 0 ? "Some Tabs Couldn’t Be Duplicated" : "Cannot Duplicate Selected Tabs"
        var messageLines = [
            "Duplicated \(successCount) \(successCount == 1 ? "tab" : "tabs"). "
                + "Skipped \(skippedCount) \(skippedCount == 1 ? "tab" : "tabs").",
        ]
        messageLines.append(contentsOf: skips.map { skip in
            let sourceLabel = if let sourceTitle = skip.sourceTitle,
                                 !sourceTitle.isEmpty { sourceTitle } else { "Selected tab" }
            return "- \(sourceLabel): \(skip.reason.message)"
        })
        if unavailableCount > 0 {
            messageLines
                .append(unavailableCount == 1 ? "1 selected tab is unavailable." :
                    "\(unavailableCount) selected tabs are unavailable.")
        }
        let collectionAlertClient = collectionAlertClient
        let message = messageLines.joined(separator: "\n")
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(title, message)
        }
    }
}
