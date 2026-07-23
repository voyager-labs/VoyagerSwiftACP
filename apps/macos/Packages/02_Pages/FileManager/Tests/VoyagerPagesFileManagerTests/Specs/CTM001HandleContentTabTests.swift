import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

private struct BatchDirectoryCollectionOwnerFixture {
    let directoryID: ContentTabID
    let collectionID: ContentTabID
    let directoryDuplicateID: ContentTabID
    let collectionDuplicateID: ContentTabID
    let collectionURL: URL
    let state: FileManagerFeature.State
}

private struct BatchSameSessionAiFixture {
    let firstSourceID: ContentTabID
    let secondSourceID: ContentTabID
    let firstDuplicateID: ContentTabID
    let secondDuplicateID: ContentTabID
    let sessionID: AiChatSessionID
    let requestLock: AiChatRequestLock
    let state: FileManagerFeature.State
}

private struct BatchPendingCloseFixture {
    let firstSourceID: ContentTabID
    let secondSourceID: ContentTabID
    let thirdSourceID: ContentTabID
    let pendingTargetID: ContentTabID
    let firstDuplicateID: ContentTabID
    let secondDuplicateID: ContentTabID
    let truncatedDuplicateID: ContentTabID
    let state: FileManagerFeature.State
}

@MainActor
private func makeBatchDirectorySourceContent() -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State.initialContent(
        for: .directory(path: "/Users/test/Documents"),
        inheritingWindowContextFrom: .init(),
    )
    content.navigation.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
    content.navigation.forwardHistory = [
        ContentPageNavigationHistorySnapshot(navigationState: .folder("/Users/test/Desktop")),
    ]
    content.pendingSelectEntryID = "directory-entry"
    content.composer.isPresented = true
    content.composer.text = "directory draft"
    content.entryViewLayout.entryOperations.selectedEntryIDs = ["directory-selected"]
    return content
}

@MainActor
private func makeBatchCollectionSourceContent(
    inheritingWindowContextFrom directoryContent: FileManagerContentFeature.State,
) -> FileManagerContentFeature.State {
    let collectionURL = URL(fileURLWithPath: "/tmp/saved.voycoll")
    let baselineContext = CollectionContext(query: "kind:document", scopes: ["/tmp"], conditions: [])
    var content = FileManagerContentFeature.State.initialContent(
        for: .collectionFile(url: collectionURL),
        inheritingWindowContextFrom: directoryContent,
    )
    content.navigation.backHistory = [
        ContentPageNavigationHistorySnapshot(navigationState: .folder("/Users/test")),
    ]
    content.navigation.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .recents)]
    content.entryViewLayout.isCollectionMode = true
    content.collection.collectionContext = CollectionContext(query: "kind:image", scopes: ["/tmp"], conditions: [])
    content.collection.collectionSession.document = .init(url: collectionURL, name: "Saved Collection")
    content.collection.collectionSession.metadata.baseline = .init(context: baselineContext)
    content.collection.isSaving = true
    content.composer.isPresented = true
    content.composer.text = "collection draft"
    return content
}

@MainActor
private func makeBatchDirectoryCollectionOwnerFixture() -> BatchDirectoryCollectionOwnerFixture {
    let directoryID = ContentTabID(rawValue: "directory-source")
    let collectionID = ContentTabID(rawValue: "collection-source")
    let directoryContent = makeBatchDirectorySourceContent()
    let collectionContent = makeBatchCollectionSourceContent(inheritingWindowContextFrom: directoryContent)
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(
        tabs: [
            ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                isPinned: false,
                title: "Documents",
                iconName: "folder",
            ),
            ContentTabItem(
                id: collectionID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/saved.voycoll")),
                isPinned: false,
                title: "Saved Collection",
                iconName: "rectangle.stack",
            ),
        ],
        activeTabID: directoryID,
    )
    state.contentTabs.selectedTabIDs = [directoryID, collectionID]
    state.contentTabs.selectionAnchorID = collectionID
    state.content = directoryContent
    var staleDirectoryCache = directoryContent
    staleDirectoryCache.navigation.backHistory = []
    staleDirectoryCache.navigation.forwardHistory = []
    state.tabContentStates = [directoryID: staleDirectoryCache, collectionID: collectionContent]
    state.inspector.inspectorVisible = true
    state.syncActiveTabInspectorState()
    var collectionInspector = FileManagerInspectorFeature.State()
    collectionInspector.inspectorVisible = true
    state.tabInspectorStates[collectionID] = collectionInspector.tabSnapshot()
    state.syncContentTabSidebarItems()
    return BatchDirectoryCollectionOwnerFixture(
        directoryID: directoryID,
        collectionID: collectionID,
        directoryDuplicateID: ContentTabID(rawValue: "directory-duplicate"),
        collectionDuplicateID: ContentTabID(rawValue: "collection-duplicate"),
        collectionURL: URL(fileURLWithPath: "/tmp/saved.voycoll"),
        state: state,
    )
}

private func makeBatchAiRequestLock(sessionID: AiChatSessionID) -> AiChatRequestLock {
    let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
    let modelRow = AiModelCatalogRow(
        handle: modelHandle,
        displayName: "GPT-4.1 Mini",
        authMethod: .apiKey,
        sortOrder: 10,
    )
    let requestID = AiChatRequestID(rawValue: UUID())
    let runID = AiChatRunID(rawValue: UUID())
    let context = AiChatRequestContextSnapshot(
        sessionID: sessionID,
        requestID: requestID,
        runID: runID,
        provider: .openai,
        model: modelHandle,
        selectedModel: AiProviderModel(
            id: modelHandle,
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
        ),
        selectedModelRow: modelRow,
        sessionStatus: .active,
        promptSummary: "shared request",
        submittedAtMs: 0,
    )
    return AiChatRequestLock(
        kind: .submit,
        requestID: requestID,
        runID: runID,
        context: context,
        request: AiChatRequest(
            context: context,
            messages: [AiChatMessage(role: .user, content: "shared request")],
        ),
        persistenceTranscriptHistory: nil,
        selectedModelHandle: modelHandle,
        selectedModelRow: modelRow,
        assistantReplacementIndex: nil,
    )
}

@MainActor
private func makeBatchSameSessionAiFixture() -> BatchSameSessionAiFixture {
    let firstSourceID = ContentTabID(rawValue: "ai-source-active")
    let secondSourceID = ContentTabID(rawValue: "ai-source-inactive")
    let sessionID = AiChatSessionID(rawValue: UUID())
    let requestLock = makeBatchAiRequestLock(sessionID: sessionID)
    let sessionIDString = sessionID.rawValue.uuidString
    var sharedContent = FileManagerContentFeature.State()
    sharedContent.navigation.navigationState = .aiChat(sessionIDString)
    sharedContent.aiChat.sessionID = sessionID
    sharedContent.aiChat.sessionStatus = .active
    sharedContent.aiChat.executionPhase = .processing(requestLock)
    sharedContent.aiChat.transcriptHistory = requestLock.request.messages
    sharedContent.aiChat.draftText = "shared draft"
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(
        tabs: [
            ContentTabItem(
                id: firstSourceID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionIDString),
                isPinned: false,
                title: "AI Active",
                iconName: "sparkles",
            ),
            ContentTabItem(
                id: secondSourceID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionIDString),
                isPinned: false,
                title: "AI Inactive",
                iconName: "sparkles",
            ),
        ],
        activeTabID: firstSourceID,
    )
    state.contentTabs.selectedTabIDs = [firstSourceID, secondSourceID]
    state.contentTabs.selectionAnchorID = secondSourceID
    state.content = sharedContent
    state.tabContentStates = [firstSourceID: sharedContent, secondSourceID: sharedContent]
    state.syncContentTabSidebarItems()
    return BatchSameSessionAiFixture(
        firstSourceID: firstSourceID,
        secondSourceID: secondSourceID,
        firstDuplicateID: ContentTabID(rawValue: "ai-duplicate-active"),
        secondDuplicateID: ContentTabID(rawValue: "ai-duplicate-inactive"),
        sessionID: sessionID,
        requestLock: requestLock,
        state: state,
    )
}

private func makeBatchPendingCloseTabs() -> IdentifiedArrayOf<ContentTabItem> {
    var tabs: IdentifiedArrayOf<ContentTabItem> = [
        ContentTabItem(
            id: ContentTabID(rawValue: "pending-source-a"),
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "A",
            iconName: "house",
        ),
        ContentTabItem(
            id: ContentTabID(rawValue: "pending-source-b"),
            page: .directory,
            anchor: .directory(path: "/b"),
            isPinned: false,
            title: "B",
            iconName: "folder",
        ),
        ContentTabItem(
            id: ContentTabID(rawValue: "pending-source-c"),
            page: .directory,
            anchor: .directory(path: "/c"),
            isPinned: false,
            title: "C",
            iconName: "folder",
        ),
        ContentTabItem(
            id: ContentTabID(rawValue: "pending-target"),
            page: .directory,
            anchor: .directory(path: "/c"),
            isPinned: false,
            title: "C",
            iconName: "folder",
        ),
    ]
    let fillerCount = ContentTabConstants.maxTabs - tabs.count - 2
    for index in 0 ..< fillerCount {
        tabs.append(ContentTabItem(
            id: ContentTabID(rawValue: "pending-filler-\(index)"),
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: nil,
            iconName: nil,
        ))
    }
    return tabs
}

@MainActor
private func makeBatchPendingCloseFixture() -> BatchPendingCloseFixture {
    let firstSourceID = ContentTabID(rawValue: "pending-source-a")
    let secondSourceID = ContentTabID(rawValue: "pending-source-b")
    let thirdSourceID = ContentTabID(rawValue: "pending-source-c")
    let pendingTargetID = ContentTabID(rawValue: "pending-target")
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(tabs: makeBatchPendingCloseTabs(), activeTabID: firstSourceID)
    state.contentTabs.selectedTabIDs = [firstSourceID, secondSourceID, thirdSourceID]
    state.contentTabs.selectionAnchorID = thirdSourceID
    state.content.pendingSelectEntryID = "active-source"
    state.tabContentStates[firstSourceID] = state.content
    var secondSourceContent = FileManagerContentFeature.State()
    secondSourceContent.pendingSelectEntryID = "second-source"
    state.tabContentStates[secondSourceID] = secondSourceContent
    var thirdSourceContent = FileManagerContentFeature.State()
    thirdSourceContent.pendingSelectEntryID = "third-source"
    state.tabContentStates[thirdSourceID] = thirdSourceContent
    let pendingTargetContent = FileManagerContentFeature.State()
    state.tabContentStates[pendingTargetID] = pendingTargetContent
    state.inspector.inspectorVisible = true
    state.syncActiveTabInspectorState()
    let pendingTargetInspector = FileManagerInspectorFeature.State()
    state.tabInspectorStates[pendingTargetID] = pendingTargetInspector
    state.pendingContentTabClose = PendingContentTabClose(
        tabID: pendingTargetID,
        previousActiveTabID: firstSourceID,
        previousActiveContent: state.content,
        targetContent: pendingTargetContent,
        previousActiveInspector: state.inspector,
        targetInspector: pendingTargetInspector,
    )
    state.syncContentTabSidebarItems()
    return BatchPendingCloseFixture(
        firstSourceID: firstSourceID,
        secondSourceID: secondSourceID,
        thirdSourceID: thirdSourceID,
        pendingTargetID: pendingTargetID,
        firstDuplicateID: ContentTabID(rawValue: "pending-duplicate-a"),
        secondDuplicateID: ContentTabID(rawValue: "pending-duplicate-b"),
        truncatedDuplicateID: ContentTabID(rawValue: "pending-duplicate-c"),
        state: state,
    )
}

private struct SelectedContentTabCloseFixture {
    let tabA: ContentTabID
    let tabB: ContentTabID
    let tabC: ContentTabID
    let tabD: ContentTabID
    let state: FileManagerFeature.State
}

private func makeSelectedContentTabCloseFixture() -> SelectedContentTabCloseFixture {
    let tabA = ContentTabID(rawValue: "batch-close-a")
    let tabB = ContentTabID(rawValue: "batch-close-b")
    let tabC = ContentTabID(rawValue: "batch-close-c")
    let tabD = ContentTabID(rawValue: "batch-close-d")
    func tab(_ id: ContentTabID, isPinned: Bool = false) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .home,
            anchor: .homeDefault,
            isPinned: isPinned,
            title: id.rawValue,
            iconName: "house",
        )
    }
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(
        tabs: [tab(tabA), tab(tabB), tab(tabC), tab(tabD, isPinned: true)],
        activeTabID: tabC,
    )
    state.contentTabs.selectedTabIDs = [tabA, tabB, tabC]
    state.contentTabs.selectionAnchorID = tabB
    state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
        page: .directory,
        anchor: .directory(path: "/batch-close-restored"),
        wasPinned: false,
        closedAt: Date(timeIntervalSince1970: 453),
    )
    state.syncContentTabSidebarItems()
    return SelectedContentTabCloseFixture(
        tabA: tabA,
        tabB: tabB,
        tabC: tabC,
        tabD: tabD,
        state: state,
    )
}

private struct SelectedCloseFallbackCase {
    let survivorIDs: [ContentTabID]
    let preferredIDs: [ContentTabID]
    let expectedActiveID: ContentTabID
}

private struct SelectedCloseTerminalCase {
    let actions: [FileManagerWindowAction]
    let expectedOutcome: SelectedContentTabCloseOutcome
}

private struct SelectedClosePersistenceError: Error {}

@MainActor
final class CTM001HandleContentTabTests: XCTestCase {
    private func verifyStaleAndCompetingSelectedCloseActions(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
        wrongOperationID: UUID,
    ) async {
        var state = fixture.state
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabD,
            batchOperationID: wrongOperationID,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.uuid = .constant(operationID)
        }
        let staleTerminals = makeStaleSelectedCloseTerminals(
            operationID: operationID,
            wrongOperationID: wrongOperationID,
            currentTabID: fixture.tabA,
            wrongTabID: fixture.tabB,
        )
        for action in staleTerminals + makeCompetingSelectedCloseActions(fixture: fixture) {
            await store.send(action)
            XCTAssertEqual(store.state, state)
        }
    }

    private func verifyDirtySelectedCloseTerminalsRejectWrongCorrelation(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
        wrongOperationID: UUID,
    ) async {
        var state = fixture.state
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabC],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabA,
            batchOperationID: operationID,
        )
        let feedback = CollectionSaveFeedback(
            stage: .saveFailed,
            category: .saveFailed,
            title: "Save Failed",
            message: "Unable to save collection.",
            isRetryable: true,
        )
        let contentActions: [FileManagerContentAction] = [
            .collection(.savePanelResponse(nil)),
            .collection(.saveCompleted(.failure(SelectedClosePersistenceError()))),
            .collection(.writeBackFailed),
            .collection(.delegate(.saveFeedback(feedback))),
        ]
        let staleCorrelations = [
            (wrongOperationID, fixture.tabA),
            (operationID, fixture.tabB),
        ]
        let store = TestStore(initialState: state) { FileManagerFeature() }

        for (receivedOperationID, receivedTabID) in staleCorrelations {
            for contentAction in contentActions {
                await store.send(.performBatchCloseContentAction(
                    operationID: receivedOperationID,
                    tabID: receivedTabID,
                    action: contentAction,
                ))
                XCTAssertEqual(store.state, state)
            }
        }
    }

    private func verifySelectedCloseGapRejectsCompetingActions(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
    ) async {
        var state = fixture.state
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            cursor: 1,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.uuid = .constant(operationID)
        }
        for action in makeCompetingSelectedCloseActions(fixture: fixture) {
            await store.send(action)
            XCTAssertEqual(store.state, state)
        }
    }

    private func verifyMissingSelectedCloseTargetAdvances(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
    ) async {
        let missingID = ContentTabID(rawValue: "missing-during-processing")
        var state = fixture.state
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [missingID],
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD],
        )
        let store = TestStore(initialState: state) { FileManagerWindowRoutingReducer() }
        await store.send(.processNextSelectedContentTabClose(operationID: operationID)) {
            $0.pendingSelectedContentTabClose?.currentTabID = missingID
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(receivedOperationID, tabID, outcome) = action
            else { return false }
            return receivedOperationID == operationID && tabID == missingID && outcome == .missing
        } assert: {
            $0.pendingSelectedContentTabClose?.cursor = 1
            $0.pendingSelectedContentTabClose?.currentTabID = nil
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID) {
            $0.pendingSelectedContentTabClose = nil
        }
        XCTAssertEqual(
            store.state.contentTabs.recentlyClosed?.anchor,
            .directory(path: "/batch-close-restored"),
        )
    }

    private func makeSelectedCloseTerminalCases(
        operationID: UUID,
        tabID: ContentTabID,
    ) -> [SelectedCloseTerminalCase] {
        [
            SelectedCloseTerminalCase(
                actions: [
                    .performBatchCloseContentAction(
                        operationID: operationID,
                        tabID: tabID,
                        action: .collection(.savePanelResponse(nil)),
                    ),
                ],
                expectedOutcome: .cancelled,
            ),
            SelectedCloseTerminalCase(
                actions: [
                    .performBatchCloseContentAction(
                        operationID: operationID,
                        tabID: tabID,
                        action: .collection(.saveCompleted(.failure(SelectedClosePersistenceError()))),
                    ),
                    .performBatchCloseContentAction(
                        operationID: operationID,
                        tabID: tabID,
                        action: .collection(.delegate(.saveFeedback(CollectionSaveFeedback(
                            stage: .saveFailed,
                            category: .saveFailed,
                            title: "Save Failed",
                            message: "Unable to save collection.",
                            isRetryable: true,
                        )))),
                    ),
                ],
                expectedOutcome: .failed,
            ),
        ]
    }

    private func makeSelectedCloseFallbackCases(
        fixture: SelectedContentTabCloseFixture,
    ) -> [SelectedCloseFallbackCase] {
        [
            SelectedCloseFallbackCase(
                survivorIDs: [fixture.tabA, fixture.tabD],
                preferredIDs: [fixture.tabD, fixture.tabA],
                expectedActiveID: fixture.tabD,
            ),
            SelectedCloseFallbackCase(
                survivorIDs: [fixture.tabA],
                preferredIDs: [fixture.tabD, fixture.tabA],
                expectedActiveID: fixture.tabA,
            ),
            SelectedCloseFallbackCase(
                survivorIDs: [fixture.tabB],
                preferredIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
                expectedActiveID: fixture.tabB,
            ),
        ]
    }

    private func makePinnedFirstInterleavedSelectedCloseState(
        activeID: ContentTabID,
        pinnedID: ContentTabID,
        visualRightID: ContentTabID,
        targetID: ContentTabID,
    ) -> FileManagerWindowState {
        func tab(_ id: ContentTabID, isPinned: Bool = false) -> ContentTabItem {
            ContentTabItem(
                id: id,
                page: .home,
                anchor: .homeDefault,
                isPinned: isPinned,
                title: id.rawValue,
                iconName: "house",
            )
        }

        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: [
                tab(activeID),
                tab(pinnedID, isPinned: true),
                tab(visualRightID),
                tab(targetID),
            ],
            activeTabID: activeID,
        )
        state.contentTabs.selectedTabIDs = [activeID, targetID]
        state.contentTabs.selectionAnchorID = targetID
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeUndoRedoBlockedSelectedCloseStates(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
    ) -> [FileManagerWindowState] {
        let undoRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/undo/old", afterPath: "/undo/new")],
        )
        let redoRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/redo/old", afterPath: "/redo/new")],
        )
        var baseState = fixture.state
        let ownerID = baseState.content.entryViewLayout.entryOperations.undoOwnerID
        baseState.content.entryViewLayout.entryOperations.undoRecords = [undoRecord]
        baseState.content.entryViewLayout.entryOperations.redoRecords = [redoRecord]
        baseState.tabContentStates = [fixture.tabC: baseState.content]
        baseState.undoManagerAvailability = .init(
            canUndo: true,
            canRedo: true,
            undoTarget: .init(ownerID: ownerID, recordID: undoRecord.id),
            redoTarget: .init(ownerID: ownerID, recordID: redoRecord.id),
        )

        var currentState = baseState
        currentState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD],
        )
        currentState.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabA,
            batchOperationID: operationID,
        )

        var gapState = baseState
        gapState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            cursor: 1,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD],
        )
        return [currentState, gapState]
    }

    private func makeStaleSelectedCloseTerminals(
        operationID: UUID,
        wrongOperationID: UUID,
        currentTabID: ContentTabID,
        wrongTabID: ContentTabID,
    ) -> [FileManagerWindowAction] {
        [
            .selectedContentTabCloseItemCompleted(
                operationID: wrongOperationID,
                tabID: currentTabID,
                outcome: .removed,
            ),
            .selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: wrongTabID,
                outcome: .removed,
            ),
        ]
    }

    private func makeCompetingSelectedCloseActions(
        fixture: SelectedContentTabCloseFixture,
    ) -> [FileManagerWindowAction] {
        [
            .requestCloseSelectedContentTabs,
            .closeContentTabRequested(fixture.tabD),
            .request(.duplicateContentTab(fixture.tabA)),
            .sidebar(.delegate(.contentTabReorderRequested(
                sourceID: fixture.tabA,
                targetID: fixture.tabD,
                placement: .after,
            ))),
            .request(.openNewContentTab),
            .request(.restoreLastClosedContentTab),
            .sidebar(.delegate(.pinContentTab(fixture.tabA))),
            .sidebar(.delegate(.unpinContentTab(fixture.tabD))),
            .sidebar(.delegate(.selectContentTab(fixture.tabD))),
            .contentTabCloseAlertResponse(.cancel),
        ]
    }

    private func makeBlockedDirectContentTabActions(
        fixture: SelectedContentTabCloseFixture,
        duplicateID: ContentTabID,
    ) -> [FileManagerWindowAction] {
        [
            .contentTabs(.setCurrent(fixture.tabD)),
            .contentTabs(.open(.homeDefault)),
            .contentTabs(.restore),
            .contentTabs(.reorder(
                sourceID: fixture.tabA,
                targetID: fixture.tabB,
                placement: .after,
            )),
            .contentTabs(.pin(fixture.tabA)),
            .contentTabs(.unpin(fixture.tabD)),
            .contentTabs(.duplicate(sourceID: fixture.tabA, duplicateID: duplicateID)),
            .contentTabs(.requestClose(fixture.tabA)),
            .contentTabs(.close(fixture.tabA)),
            .contentTabs(.commitClose(fixture.tabA)),
            .contentTabs(.updateActivePageAnchor(
                fixture.tabC,
                .directory(path: "/blocked-anchor"),
            )),
        ]
    }

    private func makeDirtyBatchPendingState(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
    ) -> FileManagerFeature.State {
        var state = fixture.state
        state.contentTabs.selectedTabIDs = [fixture.tabA]
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabC],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabA,
            batchOperationID: operationID,
            requiresWriteBackFailureTerminal: false,
        )
        return state
    }

    private func makeSelectedCloseSaveFeedback() -> CollectionSaveFeedback {
        CollectionSaveFeedback(
            stage: .saveFailed,
            category: .saveFailed,
            title: "Save Failed",
            message: "Unable to save collection.",
            isRetryable: true,
        )
    }

    private func makeDisappearingSelectedCloseState(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
        requestID: UUID,
        ownerID: UUID,
    ) -> FileManagerFeature.State {
        let previousContent = fixture.state.content
        var targetContent = makeDirtySelectedCloseContentState()
        targetContent.collection.isSaving = true
        targetContent.collection.pendingSaveContext = CollectionContext(
            query: "pending",
            scopes: ["/tmp"],
            conditions: [],
        )
        targetContent.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        var state = fixture.state
        state.contentTabs.activeTabID = fixture.tabA
        state.contentTabs.previousActiveTabID = fixture.tabC
        state.content = targetContent
        state.tabContentStates[fixture.tabC] = previousContent
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabC],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabA,
            previousActiveTabID: fixture.tabC,
            previousActiveContent: previousContent,
            targetContent: targetContent,
            batchOperationID: operationID,
        )
        state.deferredPinnedContentTabs = fixture.state.contentTabs
        state.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: requestID,
            tabID: fixture.tabA,
            ownerID: ownerID,
        )
        state.undoRedoPhase = .tearingDownTab(requestID: requestID, ownerID: ownerID)
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        return state
    }

    private func makeDirtySelectedCloseContentState() -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true
        content.collection.collectionContext = CollectionContext(
            query: "current",
            scopes: ["/tmp"],
            conditions: [],
        )
        content.collection.collectionSession.metadata.baseline = .init(
            context: CollectionContext(query: "baseline", scopes: ["/tmp"], conditions: []),
        )
        return content
    }

    private func receiveRemovedSelectedCloseLifecycle(
        _ store: TestStoreOf<FileManagerFeature>,
        operationID: UUID,
        tabID: ContentTabID,
    ) async {
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(
                receivedOperationID,
                receivedTabID,
                .requestClose(requestedID),
            ) = action else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && requestedID == tabID
        }
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(
                receivedOperationID,
                receivedTabID,
                .commitClose(committedID),
            ) = action else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && committedID == tabID
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(receivedOperationID, receivedTabID, outcome) = action
            else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && outcome == .removed
        }
    }

    private func receivePinnedSelectedCloseLifecycle(
        _ store: TestStoreOf<FileManagerFeature>,
        operationID: UUID,
        tabID: ContentTabID,
    ) async {
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(
                receivedOperationID,
                receivedTabID,
                .close(closedID),
            ) = action
            else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && closedID == tabID
        }
        XCTAssertEqual(store.state.pendingSelectedContentTabClose?.currentTabID, tabID)
        XCTAssertFalse(store.state.contentTabs.tabs[id: tabID]?.isPinned ?? true)
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(
                receivedOperationID,
                receivedTabID,
                .pinnedRecordSaveSucceeded(successID, _),
            ) = action else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && successID == tabID
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(receivedOperationID, receivedTabID, outcome) = action
            else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && outcome == .unpinned
        }
    }

    private func verifyPinnedPersistenceFailureRetainsSelectedTarget(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
    ) async {
        var state = fixture.state
        state.contentTabs.selectedTabIDs = [fixture.tabD]
        state.contentTabs.selectionAnchorID = fixture.tabD
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabD],
            currentTabID: fixture.tabD,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabC],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabD,
            batchOperationID: operationID,
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SelectedClosePersistenceError() }
        }
        // store.exhaustivity = .off: rollback 내부 field diff보다 wrapped failure와 최종 identity를 검증한다.
        store.exhaustivity = .off

        await store.send(.performSelectedContentTabCloseMutation(
            operationID: operationID,
            tabID: fixture.tabD,
            action: .close(fixture.tabD),
        ))
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(
                receivedOperationID,
                tabID,
                .pinnedRecordSaveFailed(failedID, _, _, _, _),
            ) = action else { return false }
            return receivedOperationID == operationID && tabID == fixture.tabD && failedID == fixture.tabD
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabD && outcome == .failed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        XCTAssertTrue(store.state.contentTabs.tabs[id: fixture.tabD]?.isPinned ?? false)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [fixture.tabD])
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
    }

    private func verifyTeardownFailureRetainsSelectedTarget(
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
        requestID: UUID,
        ownerID: UUID,
    ) async {
        var state = fixture.state
        state.contentTabs.selectedTabIDs = [fixture.tabA]
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabC],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabA,
            batchOperationID: operationID,
        )
        state.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: requestID,
            tabID: fixture.tabA,
            ownerID: ownerID,
        )
        state.undoRedoPhase = .tearingDownTab(requestID: requestID, ownerID: ownerID)
        let store = TestStore(initialState: state) { FileManagerFeature() }
        // store.exhaustivity = .off: undo phase와 terminal identity를 명시 검증하고 projection 파생 state는 최종 equality로 확인한다.
        store.exhaustivity = .off

        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: ownerID,
            result: UndoManagerInvalidationResult(succeeded: false, availability: .init()),
        )))
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == .failed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [fixture.tabA])
        XCTAssertNil(store.state.pendingContentTabTeardown)
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
    }

    private func verifyRetainedSelectedCloseTerminal(
        _ testCase: SelectedCloseTerminalCase,
        fixture: SelectedContentTabCloseFixture,
        operationID: UUID,
    ) async {
        var state = fixture.state
        state.contentTabs.selectedTabIDs = [fixture.tabA]
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabC],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabA,
            batchOperationID: operationID,
            requiresWriteBackFailureTerminal: false,
        )
        let store = TestStore(initialState: state) { FileManagerWindowRoutingReducer() }
        // store.exhaustivity = .off: terminal outcome과 최종 identity만 검증한다.
        store.exhaustivity = .off

        for action in testCase.actions {
            await store.send(action)
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == testCase.expectedOutcome
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [fixture.tabA])
        XCTAssertEqual(
            store.state.contentTabs.recentlyClosed?.anchor,
            .directory(path: "/batch-close-restored"),
        )
    }

    private func receiveDirectoryNavigation(
        _ store: TestStoreOf<FileManagerFeature>,
        path: String,
    ) async {
        await store.receive { action in
            guard case let .navigation(.view(.navigateToPath(receivedPath))) = action else { return false }
            return receivedPath == path
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performNavigateToPath(receivedPath))) = action else { return false }
            return receivedPath == path
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.folder(receivedPath)))) = action
            else { return false }
            return receivedPath == path
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.folder(receivedPath)))) = action
            else { return false }
            return receivedPath == path
        }
    }

    private func makeReorderDirectoryTab(_ id: String, isPinned: Bool) -> ContentTabItem {
        ContentTabItem(
            id: ContentTabID(rawValue: id),
            page: .directory,
            anchor: .directory(path: "/\(id.lowercased())"),
            isPinned: isPinned,
            title: "Title \(id)",
            iconName: "icon.\(id.lowercased())",
        )
    }

    private func makePinnedRecord(_ tab: ContentTabItem, pinnedAt: TimeInterval) -> ContentTabPinnedRecord {
        ContentTabPinnedRecord(
            id: tab.id.rawValue,
            page: tab.page,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
            pinnedAt: Date(timeIntervalSince1970: pinnedAt),
        )
    }

    // MARK: - CTM-001-open_new_content_tab

    /// CTM-001-open_new_content_tab: 빈 상태와 FileManager window 초기 상태는 Home Content Tab을 활성화함
    /// 기능스펙의 새 Content Tab 기본 진입점이 `home_default` Page work unit인지 검증한다.
    /// - 검증 내용: 빈 CTM 상태에서 Home open, FileManagerWindowState 기본 Home tab, FileManagerFeature scope routing
    /// - 사전 조건: 빈 `ContentTabState`, 기본 `FileManagerWindowState`, 기본 `FileManagerFeature.State`
    /// - 기대 결과: Home tab이 생성되어 active가 되고 FileManager scope를 통해 Directory tab도 열 수 있음
    func testOpenNewContentTab_startsFromHomeAndRoutesThroughFileManagerScope() async throws {
        var state = ContentTabState(tabs: [], activeTabID: nil, recentlyClosed: nil)
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .open(.homeDefault))

        let openedHomeTab = try XCTUnwrap(state.tabs.first)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, openedHomeTab.id)
        XCTAssertEqual(openedHomeTab.page, .home)
        XCTAssertEqual(openedHomeTab.anchor, .homeDefault)
        XCTAssertFalse(openedHomeTab.isPinned)

        let windowState = FileManagerWindowState()
        let initialHomeTab = try XCTUnwrap(windowState.contentTabs.tabs.first)
        XCTAssertEqual(windowState.contentTabs.tabs.count, 1)
        XCTAssertEqual(windowState.contentTabs.activeTabID, initialHomeTab.id)
        XCTAssertEqual(initialHomeTab.page, .home)
        XCTAssertEqual(initialHomeTab.anchor, .homeDefault)

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // exhaustivity = .off로 전환 검증에 집중한다.
        store.exhaustivity = .off

        let initialCount = store.state.contentTabs.tabs.count
        await store.send(.contentTabs(.open(.directory(path: "/test"))))
        XCTAssertEqual(store.state.contentTabs.tabs.count, initialCount + 1)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.page, .directory)
        XCTAssertEqual(store.state.contentTabs.activeTabID, store.state.contentTabs.tabs.last?.id)
    }

    /// CTM-001-open_new_content_tab: `FileManagerWindowState.makeInitial(path:)`가 정확히 하나의 활성 Home tab을 생성함
    /// AC1과 AC2의 makeInitial(path: nil) 진입점을 검증한다.
    /// - 검증 내용: makeInitial(path: nil) 결과 contentTabs.tabs.count == 1, activeTabID != nil, anchor == .homeDefault, page
    /// == .home
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: nil)
    /// - 기대 결과: 정확히 하나의 Home tab이 active 상태로 생성됨
    func testOpenNewContentTab_bootstrapFromMakeInitial_hasExactlyOneActiveHomeTab() {
        let state = FileManagerWindowState.makeInitial(path: nil)

        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertNotNil(state.contentTabs.activeTabID)
        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .homeDefault)
        XCTAssertEqual(state.contentTabs.tabs.first?.page, .home)
    }

    /// CTM-001-open_new_content_tab: path seed가 initial tab을 directory anchor로 동기화함
    /// path 기반 FileManager window 생성 시 chrome/source-of-truth anchor가 folder route와 일치하는지 검증한다.
    /// - 검증 내용: path seed("/tmp")에서 contentTabs.tabs.first?.anchor == .directory(path: "/tmp"), count == 1
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: "/tmp")
    /// - 기대 결과: path seed window가 Home tab metadata로 남지 않고 directory tab으로 표시됨
    func testOpenNewContentTab_pathSeed_syncsDirectoryAnchor() {
        let state = FileManagerWindowState.makeInitial(path: "/tmp")

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .directory(path: "/tmp"))
        XCTAssertEqual(state.contentTabs.tabs.count, 1)
    }

    /// CTM-001-open_new_content_tab: path seed가 navigation currentPath를 설정함
    /// path 기반 FileManager window 생성이 기존 navigation seed 동작을 유지하는지 검증한다.
    /// - 검증 내용: makeInitial(path: "/tmp") 결과 content.navigation.currentPath가 존재함
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: "/tmp")
    /// - 기대 결과: directory tab anchor와 navigation seed가 함께 적용됨
    func testOpenNewContentTab_pathSeed_appliesNavigationSeed() {
        let state = FileManagerWindowState.makeInitial(path: "/tmp")

        XCTAssertNotNil(state.content.navigation.currentPath)
    }

    /// CTM-001-open_new_content_tab: makeInitial restored state는 Home tab을 중복 추가하지 않음
    /// 복원된 ContentTabState가 주어질 때 새 window bootstrap seam이 복원 상태를 우선하는지 검증한다.
    /// - 검증 내용: Directory tab 복원 상태를 makeInitial(path:contentTabs:)에 전달하면 count == 1, directory anchor 유지, activeTabID
    /// 존재
    /// - 사전 조건: Directory tab 하나를 가진 restored ContentTabState
    /// - 기대 결과: Home tab 추가 없이 restored tab이 유지되고 active id가 설정됨
    func testOpenNewContentTab_makeInitialWithRestoredState_usesRestoredTabsNoDuplicateHome() {
        let restoredID = ContentTabID()
        let restoredState = ContentTabState(
            tabs: [ContentTabItem(
                id: restoredID,
                page: .directory,
                anchor: .directory(path: "/restored"),
                isPinned: false,
                title: nil,
                iconName: nil,
            )],
            activeTabID: restoredID,
            recentlyClosed: nil,
        )

        let state = FileManagerWindowState.makeInitial(path: nil, contentTabs: restoredState)

        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .directory(path: "/restored"))
        XCTAssertNotNil(state.contentTabs.activeTabID)
        XCTAssertEqual(state.content.navigation.currentPath, "/restored")
    }

    func testOpenNewContentTab_makeInitialWithRestoredCollectionState_seedsActiveContentFromAnchor() {
        let restoredID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/restored.voycoll")
        let restoredState = ContentTabState(
            tabs: [ContentTabItem(
                id: restoredID,
                page: .collection,
                anchor: .collectionFile(url: collectionURL),
                isPinned: false,
                title: "restored",
                iconName: "rectangle.stack",
            )],
            activeTabID: restoredID,
            recentlyClosed: nil,
        )

        let state = FileManagerWindowState.makeInitial(path: nil, contentTabs: restoredState)

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .collectionFile(url: collectionURL))
        if case let .collection(navigation) = state.content.navigation.navigationState {
            XCTAssertEqual(navigation.kind, .file(url: collectionURL, name: "restored"))
            XCTAssertEqual(navigation.context, CollectionContext(query: "", scopes: [], conditions: []))
        } else {
            XCTFail("restored collection tab should seed collection navigation")
        }
        XCTAssertEqual(
            state.tabContentStates[restoredID]?.navigation.navigationState,
            state.content.navigation.navigationState,
        )
    }

    func testOpenNewContentTab_makeInitialWithRestoredVirtualState_seedsActiveContentFromAnchor() {
        let restoredID = ContentTabID()
        let restoredState = ContentTabState(
            tabs: [ContentTabItem(
                id: restoredID,
                page: .collection,
                anchor: .virtualCollection(id: "Important"),
                isPinned: false,
                title: "Important",
                iconName: "tag",
            )],
            activeTabID: restoredID,
            recentlyClosed: nil,
        )

        let state = FileManagerWindowState.makeInitial(path: nil, contentTabs: restoredState)

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .virtualCollection(id: "Important"))
        let expectedRoute = ContentPageNavigationRoute.tags("Important")
        XCTAssertEqual(state.content.navigation.navigationState, expectedRoute)
        XCTAssertEqual(state.tabContentStates[restoredID]?.navigation.navigationState, expectedRoute)
    }

    /// CTM-001-open_new_content_tab: makeInitial empty restored state는 Home tab으로 fallback함
    /// 빈 ContentTabState가 주어질 때 새 window bootstrap seam이 Home fallback invariant를 유지하는지 검증한다.
    /// - 검증 내용: 빈 state를 makeInitial(path:contentTabs:)에 전달하면 Home tab 1개와 activeTabID가 생성됨
    /// - 사전 조건: tabs == [], activeTabID == nil인 ContentTabState
    /// - 기대 결과: active Home .homeDefault ContentTab 하나로 fallback됨
    func testOpenNewContentTab_makeInitialWithEmptyState_fallsBackToHomeTab() {
        let state = FileManagerWindowState.makeInitial(
            path: nil,
            contentTabs: ContentTabState(tabs: [], activeTabID: nil, recentlyClosed: nil),
        )

        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .homeDefault)
        XCTAssertNotNil(state.contentTabs.activeTabID)
    }

    /// CTM-001-open_new_content_tab: restored bootstrap의 invalid active id는 첫 tab을 active로 사용함
    /// 복원된 tab 목록이 있으나 activeTabID가 nil 또는 유효하지 않을 때 fallback active 선택을 검증한다.
    /// - 검증 내용: non-empty restoredTabs에서 Home 추가 없이 첫 tab id가 activeTabID가 됨
    /// - 사전 조건: Directory tab과 Collection tab 복원 목록, invalid activeTabID 또는 nil activeTabID
    /// - 기대 결과: tabs count는 유지되고 첫 restored tab이 active 상태가 됨
    func testOpenNewContentTab_restoredBootstrap_invalidActiveIdUsesFirstTab() {
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let directoryTab = ContentTabItem(
            id: firstID,
            page: .directory,
            anchor: .directory(path: "/first"),
            isPinned: false,
            title: nil,
            iconName: nil,
        )
        let collectionTab = ContentTabItem(
            id: secondID,
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/restored.voycoll")),
            isPinned: false,
            title: nil,
            iconName: nil,
        )

        let invalidActiveState = ContentTabState.bootstrapping(
            restoredTabs: [directoryTab, collectionTab],
            activeTabID: ContentTabID(),
        )

        XCTAssertEqual(invalidActiveState.tabs.count, 2)
        XCTAssertEqual(invalidActiveState.activeTabID, firstID)

        let nilActiveState = ContentTabState.bootstrapping(
            restoredTabs: [directoryTab],
            activeTabID: nil,
        )

        XCTAssertEqual(nilActiveState.activeTabID, firstID)
    }

    /// CTM-001-open_new_content_tab: bootstrapping으로 복원된 tab list에 중복 Home tab이 추가되지 않음
    /// AC4의 restored bootstrap이 중복 Home을 방지하는 정책을 검증한다.
    /// - 검증 내용: Directory tab 복원 시 count == 1, anchor == .directory(path: "/restored"), activeTabID == restored tab id;
    /// 빈 목록 시 count == 1, .homeDefault fallback
    /// - 사전 조건: ContentTabState.bootstrapping(restoredTabs:activeTabID:)로 복원된 상태와 빈 상태
    /// - 기대 결과: Non-empty 복원은 그대로 사용되고 empty는 Home fallback을 생성함
    func testOpenNewContentTab_restoredBootstrap_doesNotAppendDuplicateHomeTab() {
        let restoredID = ContentTabID()
        let restoredTabs: IdentifiedArrayOf<ContentTabItem> = [ContentTabItem(
            id: restoredID,
            page: .directory,
            anchor: .directory(path: "/restored"),
            isPinned: false,
            title: nil,
            iconName: nil,
        )]

        let nonEmptyState = ContentTabState.bootstrapping(
            restoredTabs: restoredTabs,
            activeTabID: restoredID,
        )

        XCTAssertEqual(nonEmptyState.tabs.count, 1)
        XCTAssertEqual(nonEmptyState.tabs.first?.anchor, .directory(path: "/restored"))
        XCTAssertEqual(nonEmptyState.activeTabID, restoredID)

        let emptyState = ContentTabState.bootstrapping(restoredTabs: [], activeTabID: nil)

        XCTAssertEqual(emptyState.tabs.count, 1)
        XCTAssertEqual(emptyState.tabs.first?.anchor, .homeDefault)
        XCTAssertNotNil(emptyState.activeTabID)
    }

    // MARK: - CTM-001-duplicate_selected_content_tabs

    /// CTM-001-duplicate_selected_content_tabs: selected row 메뉴는 bulk command를 한 번만 실행함
    /// 선택된 row의 context menu가 selection을 건드리지 않고 bulk duplicate presentation과 callback을 사용하는지 검증한다.
    /// - 검증 내용: pure projection의 title/identifier/command와 native NSMenu target-action 1회 dispatch
    /// - 사전 조건: clicked tab을 포함한 non-empty selection, 남은 tab capacity, 실제 ContentTabSidebarButton menu
    /// - 기대 결과: bulk label/identifier가 노출되고 menu open은 무효과, 실행은 bulk callback만 정확히 한 번 호출함
    func testDuplicateSidebarMenu_selectedRowUsesBulkPresentationAndDispatchesOnce() throws {
        let clickedID = ContentTabID(rawValue: "selected-clicked")
        let selectedIDs: Set<ContentTabID> = [clickedID, ContentTabID(rawValue: "selected-peer")]
        let presentation = ContentTabDuplicatePresentation(
            clickedTabID: clickedID,
            selectedTabIDs: selectedIDs,
            currentTabIDs: Array(selectedIDs),
            tabCount: 2,
        )

        XCTAssertEqual(presentation.title, "Duplicate 2 Tabs")
        XCTAssertEqual(presentation.accessibilityIdentifier, "duplicate-selected-content-tabs")
        XCTAssertTrue(presentation.isEnabled)
        guard case .duplicateSelectedContentTabs = presentation.command else {
            return XCTFail("selected clicked row should project the bulk command")
        }
        guard case .duplicateSelectedContentTabs = presentation.delegateAction else {
            return XCTFail("bulk projection should map to the Sidebar bulk delegate")
        }

        _ = NSApplication.shared
        let button = ContentTabSidebarButton(frame: .zero)
        var primaryActionCount = 0
        var duplicateActionCount = 0
        button.update(
            rootView: AnyView(EmptyView()),
            accessibilityLabel: "Selected Content Tab",
            accessibilityValue: "Active, Selected",
            duplicateAccessibilityIdentifier: presentation.accessibilityIdentifier,
            isPinned: false,
            isEnabled: true,
            reorderDragSource: nil,
            onActivate: { primaryActionCount += 1 },
            onToggleSelection: { primaryActionCount += 1 },
            onSelectRange: { primaryActionCount += 1 },
            onDuplicate: { duplicateActionCount += 1 },
            onPin: {},
            onUnpin: {},
            onClose: {},
            duplicateTitle: presentation.title,
            isDuplicateEnabled: presentation.isEnabled,
        )

        let menu = try XCTUnwrap(button.menu)
        let duplicateItem = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(duplicateItem.title, "Duplicate 2 Tabs")
        XCTAssertEqual(duplicateItem.identifier?.rawValue, "duplicate-selected-content-tabs")
        XCTAssertTrue(duplicateItem.isEnabled)
        XCTAssertEqual(primaryActionCount, 0)
        XCTAssertEqual(duplicateActionCount, 0)

        let action = try XCTUnwrap(duplicateItem.action)
        XCTAssertTrue(NSApp.sendAction(action, to: duplicateItem.target, from: duplicateItem))
        XCTAssertEqual(primaryActionCount, 0)
        XCTAssertEqual(duplicateActionCount, 1)
    }

    /// CTM-001-duplicate_selected_content_tabs: unselected row와 empty selection은 clicked-row single command를 유지함
    /// 기존 selection이 다른 row에 있거나 비어 있을 때 우클릭 row 하나만 복제하는 fallback을 검증한다.
    /// - 검증 내용: pure projection의 single title/identifier와 clicked ID delegate mapping
    /// - 사전 조건: clicked tab은 selection 밖이며 selected peer가 있는 경우와 selection이 비어 있는 경우
    /// - 기대 결과: 두 경우 모두 기존 `Duplicate`와 clicked-row `.duplicateContentTab` route를 사용함
    func testDuplicateSidebarMenu_unselectedOrEmptySelectionUsesClickedRowSinglePresentation() {
        let clickedID = ContentTabID(rawValue: "unselected-clicked")
        let selections: [Set<ContentTabID>] = [
            [ContentTabID(rawValue: "selected-peer")],
            [],
        ]

        for selectedIDs in selections {
            let presentation = ContentTabDuplicatePresentation(
                clickedTabID: clickedID,
                selectedTabIDs: selectedIDs,
                currentTabIDs: [clickedID] + Array(selectedIDs),
                tabCount: 2,
            )

            XCTAssertEqual(presentation.title, "Duplicate")
            XCTAssertEqual(
                presentation.accessibilityIdentifier,
                "duplicate-content-tab-\(clickedID)",
            )
            XCTAssertTrue(presentation.isEnabled)
            guard case let .duplicateContentTab(projectedID) = presentation.command else {
                return XCTFail("unselected clicked row should project the single command")
            }
            XCTAssertEqual(projectedID, clickedID)
            guard case let .duplicateContentTab(delegateID) = presentation.delegateAction else {
                return XCTFail("single projection should map to the clicked-row Sidebar delegate")
            }
            XCTAssertEqual(delegateID, clickedID)
        }
    }

    /// CTM-001-duplicate_selected_content_tabs: active baseline count 1의 capacity zero는 single menu를 비활성화함
    /// tab limit에 도달한 active-row context menu가 non-bulk label을 유지하면서 duplicate만 실행하지 않는지 검증한다.
    /// - 검증 내용: pure projection enabled state, NSMenuItem disabled state, guarded target-action callback
    /// - 사전 조건: clicked row가 selected이고 current tab count가 ContentTabConstants.maxTabs임
    /// - 기대 결과: single title/identifier는 유지되지만 duplicate item은 disabled이고 callback은 호출되지 않음
    func testDuplicateSidebarMenu_zeroCapacityDisablesDuplicateItemAndCallback() throws {
        let clickedID = ContentTabID(rawValue: "capacity-clicked")
        let presentation = ContentTabDuplicatePresentation(
            clickedTabID: clickedID,
            selectedTabIDs: [clickedID],
            currentTabIDs: [clickedID],
            tabCount: ContentTabConstants.maxTabs,
        )
        XCTAssertEqual(presentation.title, "Duplicate")
        guard case .duplicateContentTab(clickedID) = presentation.command else {
            return XCTFail("active baseline must retain the single-row route")
        }
        XCTAssertFalse(presentation.isEnabled)

        _ = NSApplication.shared
        let button = ContentTabSidebarButton(frame: .zero)
        var duplicateActionCount = 0
        button.update(
            rootView: AnyView(EmptyView()),
            accessibilityLabel: "Selected Content Tab",
            accessibilityValue: "Active, Selected",
            duplicateAccessibilityIdentifier: presentation.accessibilityIdentifier,
            isPinned: false,
            isEnabled: true,
            reorderDragSource: nil,
            onActivate: {},
            onToggleSelection: {},
            onSelectRange: {},
            onDuplicate: { duplicateActionCount += 1 },
            onPin: {},
            onUnpin: {},
            onClose: {},
            duplicateTitle: presentation.title,
            isDuplicateEnabled: presentation.isEnabled,
        )

        let duplicateItem = try XCTUnwrap(button.menu?.items.first)
        XCTAssertFalse(duplicateItem.isEnabled)
        let action = try XCTUnwrap(duplicateItem.action)
        XCTAssertTrue(NSApp.sendAction(action, to: duplicateItem.target, from: duplicateItem))
        XCTAssertEqual(duplicateActionCount, 0)
    }

    /// CTM-001-duplicate_selected_content_tabs: Sidebar bulk delegate는 Window request로만 전달됨
    /// context command routing이 active tab과 selected IDs를 선행 변경하지 않고 canonical batch request에 수렴하는지 검증한다.
    /// - 검증 내용: Sidebar delegate→Window request action과 routing 전후 whole-state equality
    /// - 사전 조건: active A와 selected A/B를 가진 FileManager Window state
    /// - 기대 결과: `.duplicateSelectedContentTabs` request가 정확히 한 번 수신되고 active/selection/window state는 불변임
    func testDuplicateSelectedSidebarDelegate_routesToWindowRequestWithoutStateMutation() async {
        let tabA = ContentTabID(rawValue: "sidebar-route-a")
        let tabB = ContentTabID(rawValue: "sidebar-route-b")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabA,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "A",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: tabB,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "B",
                    iconName: "house",
                ),
            ],
            activeTabID: tabA,
        )
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        let initialState = state
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.duplicateSelectedContentTabs)))
        await store.receive { action in
            guard case .request(.duplicateSelectedContentTabs) = action else { return false }
            return true
        }

        XCTAssertEqual(store.state, initialState)
        // store.finish() 불필요: 모든 effect가 receive로 소비됨
    }

    /// CTM-001-duplicate_selected_content_tabs: raw Cmd-D는 Content semantic delegate로 전달됨
    /// key-command focus가 Content로 복귀해도 entry duplicate를 직접 실행하지 않는 boundary를 검증한다.
    /// - 검증 내용: Cmd-D keyboard action이 `.requestDuplicate` delegate를 정확히 한 번 방출함
    /// - 사전 조건: 기본 Content 상태와 command modifier가 설정된 D key command
    /// - 기대 결과: EntryViewLayout action 없이 parent-owned duplicate request만 수신됨
    func testDuplicateKeyCommand_routesThroughContentDelegate() async {
        let command = KeyCommand(
            keyCode: 2,
            modifiers: .command,
            characters: "d",
            charactersIgnoringModifiers: "d",
        )
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(command)))
        await store.receive(\.delegate.requestDuplicate)
        await store.finish()
    }

    /// CTM-001-duplicate_selected_content_tabs: Content duplicate delegate는 Window selection policy를 따름
    /// 동일한 Cmd-D intent가 single selection에서는 entry, multi selection에서는 selected tabs duplicate로 분기되는지 검증한다.
    /// - 검증 내용: selected tab count별 Content delegate→Window request mapping
    /// - 사전 조건: active A와 single A 또는 multi A/B selection을 가진 Window state
    /// - 기대 결과: single은 `.duplicate`, multi는 `.duplicateSelectedContentTabs` request를 수신함
    func testDuplicateContentDelegate_routesBySelectedContentTabCount() async {
        let tabA = ContentTabID(rawValue: "content-route-a")
        let tabB = ContentTabID(rawValue: "content-route-b")
        for (selectedTabIDs, expectsBulkDuplicate) in [
            (Set([tabA]), false),
            (Set([tabA, tabB]), true),
        ] {
            var state = FileManagerFeature.State()
            state.contentTabs = ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabA,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: false,
                        title: "A",
                        iconName: "house",
                    ),
                    ContentTabItem(
                        id: tabB,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: false,
                        title: "B",
                        iconName: "house",
                    ),
                ],
                activeTabID: tabA,
            )
            state.contentTabs.selectedTabIDs = selectedTabIDs
            let initialState = state
            let store = TestStore(initialState: state) {
                FileManagerWindowRoutingReducer()
            }

            await store.send(.content(.delegate(.requestDuplicate)))
            await store.receive { action in
                if expectsBulkDuplicate {
                    guard case .request(.duplicateSelectedContentTabs) = action else { return false }
                } else {
                    guard case .request(.duplicate) = action else { return false }
                }
                return true
            }
            XCTAssertEqual(store.state, initialState)
        }
    }

    /// CTM-001-duplicate_selected_content_tabs: mixed pinned selection을 source-adjacent 위치로 복제함
    /// 선택된 source의 ordered request를 적용할 때 pinned boundary와 unpinned source adjacency를 검증한다.
    /// - 검증 내용: pinned boundary block, 각 unpinned source 직후 insertion, metadata copy, first duplicate active transition
    /// - 사전 조건: pinned source 하나와 unpinned source 둘, 기존 active/selection/anchor runtime state
    /// - 기대 결과: pinned copy는 boundary, unpinned copy는 각 source 직후이며 active duplicate만 selection에 추가됨
    func testDuplicateSelected_mixedSourcesInsertAdjacentCopiesAndPreserveSourceSelection() throws {
        let firstUnpinnedID = ContentTabID(rawValue: "first-unpinned")
        let pinnedID = ContentTabID(rawValue: "pinned")
        let lastUnpinnedID = ContentTabID(rawValue: "last-unpinned")
        let tailID = ContentTabID(rawValue: "tail")
        let pinnedDuplicateID = ContentTabID(rawValue: "pinned-copy")
        let firstDuplicateID = ContentTabID(rawValue: "first-copy")
        let lastDuplicateID = ContentTabID(rawValue: "last-copy")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: .directory(path: "/pinned"),
                    isPinned: true,
                    title: "Pinned",
                    iconName: "pin",
                ),
                ContentTabItem(
                    id: firstUnpinnedID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "First",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: lastUnpinnedID,
                    page: .collection,
                    anchor: .virtualCollection(id: "Recents"),
                    isPinned: false,
                    title: "Recents",
                    iconName: "clock",
                ),
                ContentTabItem(
                    id: tailID,
                    page: .directory,
                    anchor: .directory(path: "/tail"),
                    isPinned: false,
                    title: "Tail",
                    iconName: "folder",
                ),
            ],
            activeTabID: tailID,
            previousActiveTabID: pinnedID,
            pinnedRecordPersistenceError: "sentinel",
        )
        state.selectedTabIDs = [pinnedID, firstUnpinnedID, lastUnpinnedID, tailID]
        state.selectionAnchorID = firstUnpinnedID

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicateSelected([
                ContentTabDuplicateRequest(sourceID: pinnedID, duplicateID: pinnedDuplicateID),
                ContentTabDuplicateRequest(sourceID: firstUnpinnedID, duplicateID: firstDuplicateID),
                ContentTabDuplicateRequest(sourceID: lastUnpinnedID, duplicateID: lastDuplicateID),
            ]),
        )

        XCTAssertEqual(
            state.tabs.map(\.id),
            [pinnedID, pinnedDuplicateID, firstUnpinnedID, firstDuplicateID,
             lastUnpinnedID, lastDuplicateID, tailID],
        )
        XCTAssertEqual(state.activeTabID, pinnedDuplicateID)
        XCTAssertEqual(state.previousActiveTabID, tailID)
        XCTAssertEqual(
            state.selectedTabIDs,
            Set([pinnedID, firstUnpinnedID, lastUnpinnedID, tailID]),
        )
        XCTAssertEqual(state.selectionAnchorID, firstUnpinnedID)
        XCTAssertEqual(state.pinnedRecordPersistenceError, "sentinel")

        let duplicateItems = try [pinnedDuplicateID, firstDuplicateID, lastDuplicateID].map {
            try XCTUnwrap(state.tabs[id: $0])
        }
        XCTAssertEqual(duplicateItems.map(\.page), [.directory, .home, .collection])
        XCTAssertEqual(
            duplicateItems.map(\.anchor),
            [.directory(path: "/pinned"), .homeDefault, .virtualCollection(id: "Recents")],
        )
        XCTAssertEqual(duplicateItems.map(\.title), ["Pinned", "First", "Recents"])
        XCTAssertEqual(duplicateItems.map(\.iconName), ["pin", "house", "clock"])
        XCTAssertTrue(duplicateItems.allSatisfy { !$0.isPinned })
        XCTAssertFalse(state.selectedTabIDs.contains(pinnedDuplicateID))
        XCTAssertFalse(state.selectedTabIDs.contains(firstDuplicateID))
        XCTAssertFalse(state.selectedTabIDs.contains(lastDuplicateID))
    }

    /// CTM-001-duplicate_selected_content_tabs: omitted invalid selected row는 successful source adjacency를 바꾸지 않음
    /// planner가 복제 불가능한 selected row를 request에서 제외해도 successful source 직후에 삽입하는지 검증한다.
    /// - 검증 내용: successful request source 기반 insertion과 invalid selection 보존
    /// - 사전 조건: valid source 뒤에 incompatible unpinned selected row가 있고 request에는 valid source만 포함됨
    /// - 기대 결과: duplicate가 valid source 직후에 삽입되고 invalid selected row는 그대로 유지됨
    func testDuplicateSelected_omittedInvalidSelectionDoesNotMoveSuccessfulCopy() {
        let validSourceID = ContentTabID(rawValue: "valid-source")
        let incompatibleSelectedID = ContentTabID(rawValue: "incompatible-selected")
        let tailID = ContentTabID(rawValue: "tail")
        let duplicateID = ContentTabID(rawValue: "duplicate")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: validSourceID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Valid",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: incompatibleSelectedID,
                    page: .home,
                    anchor: .directory(path: "/incompatible"),
                    isPinned: false,
                    title: "Invalid",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: tailID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Tail",
                    iconName: "house",
                ),
            ],
            activeTabID: tailID,
        )
        state.selectedTabIDs = [validSourceID, incompatibleSelectedID, tailID]
        state.selectionAnchorID = incompatibleSelectedID

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicateSelected([
                ContentTabDuplicateRequest(sourceID: validSourceID, duplicateID: duplicateID),
            ]),
        )

        XCTAssertEqual(state.tabs.map(\.id), [validSourceID, duplicateID, incompatibleSelectedID, tailID])
        XCTAssertEqual(
            state.selectedTabIDs,
            Set([validSourceID, incompatibleSelectedID, tailID]),
        )
        XCTAssertEqual(state.selectionAnchorID, incompatibleSelectedID)
    }

    /// CTM-001-duplicate_selected_content_tabs: all-pinned selection은 pinned/unpinned boundary에 복제함
    /// pinned source만 선택된 batch가 기존 tab의 상대 순서를 바꾸지 않는지 검증한다.
    /// - 검증 내용: pinned boundary insertion과 duplicate block 순서
    /// - 사전 조건: pinned tab 둘 뒤에 unpinned tab 둘이 있는 canonical raw tab list
    /// - 기대 결과: 두 duplicate가 pinned 영역 직후 하나의 unpinned block으로 삽입되고 첫 duplicate가 active가 됨
    func testDuplicateSelected_allPinnedSourcesInsertAtPinnedBoundary() {
        let pinnedA = ContentTabID(rawValue: "pinned-a")
        let pinnedB = ContentTabID(rawValue: "pinned-b")
        let unpinnedA = ContentTabID(rawValue: "unpinned-a")
        let unpinnedB = ContentTabID(rawValue: "unpinned-b")
        let duplicateB = ContentTabID(rawValue: "copy-b")
        let duplicateA = ContentTabID(rawValue: "copy-a")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: pinnedA, page: .home, anchor: .homeDefault, isPinned: true,
                               title: "Pinned A", iconName: "a"),
                ContentTabItem(id: pinnedB, page: .directory, anchor: .directory(path: "/b"), isPinned: true,
                               title: "Pinned B", iconName: "b"),
                ContentTabItem(id: unpinnedA, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "A", iconName: "a"),
                ContentTabItem(id: unpinnedB, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "B", iconName: "b"),
            ],
            activeTabID: unpinnedB,
        )
        state.selectedTabIDs = [pinnedA, pinnedB, unpinnedB]
        state.selectionAnchorID = pinnedB

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicateSelected([
                ContentTabDuplicateRequest(sourceID: pinnedB, duplicateID: duplicateB),
                ContentTabDuplicateRequest(sourceID: pinnedA, duplicateID: duplicateA),
            ]),
        )

        XCTAssertEqual(state.tabs.map(\.id), [pinnedA, pinnedB, duplicateB, duplicateA, unpinnedA, unpinnedB])
        XCTAssertEqual(state.activeTabID, duplicateB)
        XCTAssertEqual(state.previousActiveTabID, unpinnedB)
        XCTAssertEqual(state.selectedTabIDs, Set([pinnedA, pinnedB, unpinnedB]))
        XCTAssertEqual(state.selectionAnchorID, pinnedB)
    }

    /// CTM-001-duplicate_selected_content_tabs: malformed direct requests는 valid request만 보존함
    /// 중복 identity와 잘못된 source/anchor가 batch 전체를 오염시키지 않는지 검증한다.
    /// - 검증 내용: missing source, repeated source/duplicate, existing collision, page-anchor mismatch skip
    /// - 사전 조건: valid source 둘, incompatible source 하나, existing tab identity와 malformed request sequence
    /// - 기대 결과: request 순서의 valid unique pair만 생성되고 state identity invariant가 유지됨
    func testDuplicateSelected_malformedRequestsSkipOnlyInvalidPairs() {
        let validA = ContentTabID(rawValue: "valid-a")
        let validB = ContentTabID(rawValue: "valid-b")
        let incompatible = ContentTabID(rawValue: "incompatible")
        let existing = ContentTabID(rawValue: "existing")
        let duplicateA = ContentTabID(rawValue: "duplicate-a")
        let duplicateB = ContentTabID(rawValue: "duplicate-b")
        let ignored = ContentTabID(rawValue: "ignored")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: validA, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "A", iconName: "a"),
                ContentTabItem(id: incompatible, page: .home, anchor: .directory(path: "/wrong"), isPinned: false,
                               title: "Wrong", iconName: "wrong"),
                ContentTabItem(id: validB, page: .directory, anchor: .directory(path: "/b"), isPinned: false,
                               title: "B", iconName: "b"),
                ContentTabItem(id: existing, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "Existing", iconName: "existing"),
            ],
            activeTabID: existing,
        )

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicateSelected([
                ContentTabDuplicateRequest(sourceID: ContentTabID(rawValue: "missing"), duplicateID: ignored),
                ContentTabDuplicateRequest(sourceID: validA, duplicateID: duplicateA),
                ContentTabDuplicateRequest(sourceID: validA, duplicateID: ContentTabID(rawValue: "repeat-source")),
                ContentTabDuplicateRequest(sourceID: validB, duplicateID: duplicateA),
                ContentTabDuplicateRequest(sourceID: incompatible, duplicateID: ContentTabID(rawValue: "bad-anchor")),
                ContentTabDuplicateRequest(sourceID: validB, duplicateID: existing),
                ContentTabDuplicateRequest(sourceID: validB, duplicateID: duplicateB),
            ]),
        )

        XCTAssertEqual(state.tabs.map(\.id), [validA, duplicateA, incompatible, validB, duplicateB, existing])
        XCTAssertEqual(state.activeTabID, duplicateA)
        XCTAssertEqual(state.previousActiveTabID, existing)
        XCTAssertEqual(Set(state.tabs.ids).count, state.tabs.count)
    }

    /// CTM-001-duplicate_selected_content_tabs: invalid requests는 capacity를 소비하지 않고 zero-success는 no-op임
    /// 남은 slot을 valid ordered prefix에만 적용하는 core 방어와 성공 없는 batch의 원자성을 검증한다.
    /// - 검증 내용: invalid-before-capacity filtering, valid prefix truncation, zero-success whole-state equality
    /// - 사전 조건: maxTabs-2 상태의 valid source 셋과 별도 collision-only request
    /// - 기대 결과: 앞의 invalid request를 제외한 valid 두 개만 생성되고 collision-only batch는 state를 전혀 바꾸지 않음
    func testDuplicateSelected_capacityUsesValidPrefixAndZeroSuccessIsWholeStateNoOp() {
        let sourceA = ContentTabID(rawValue: "source-a")
        let sourceB = ContentTabID(rawValue: "source-b")
        let sourceC = ContentTabID(rawValue: "source-c")
        let duplicateA = ContentTabID(rawValue: "duplicate-a")
        let duplicateB = ContentTabID(rawValue: "duplicate-b")
        let duplicateC = ContentTabID(rawValue: "duplicate-c")
        var tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(id: sourceA, page: .home, anchor: .homeDefault, isPinned: false,
                           title: "A", iconName: "a"),
            ContentTabItem(id: sourceB, page: .directory, anchor: .directory(path: "/b"), isPinned: false,
                           title: "B", iconName: "b"),
            ContentTabItem(id: sourceC, page: .collection, anchor: .virtualCollection(id: "Recents"), isPinned: false,
                           title: "C", iconName: "c"),
        ]
        for index in 0 ..< ContentTabConstants.maxTabs - 5 {
            tabs.append(ContentTabItem(
                id: ContentTabID(rawValue: "filler-\(index)"),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
        }
        var state = ContentTabState(tabs: tabs, activeTabID: sourceC, previousActiveTabID: sourceA)
        state.selectedTabIDs = [sourceA, sourceB, sourceC]
        state.selectionAnchorID = sourceC

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicateSelected([
                ContentTabDuplicateRequest(
                    sourceID: ContentTabID(rawValue: "missing"),
                    duplicateID: ContentTabID(rawValue: "missing-copy"),
                ),
                ContentTabDuplicateRequest(sourceID: sourceA, duplicateID: duplicateA),
                ContentTabDuplicateRequest(sourceID: sourceB, duplicateID: duplicateB),
                ContentTabDuplicateRequest(sourceID: sourceC, duplicateID: duplicateC),
            ]),
        )

        XCTAssertEqual(state.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(Array(state.tabs.prefix(5)).map(\.id), [sourceA, duplicateA, sourceB, duplicateB, sourceC])
        XCTAssertNotNil(state.tabs[id: duplicateA])
        XCTAssertNotNil(state.tabs[id: duplicateB])
        XCTAssertNil(state.tabs[id: duplicateC])
        XCTAssertEqual(state.activeTabID, duplicateA)
        XCTAssertEqual(state.previousActiveTabID, sourceC)

        let beforeNoOp = state
        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicateSelected([
                ContentTabDuplicateRequest(sourceID: sourceA, duplicateID: duplicateA),
                ContentTabDuplicateRequest(
                    sourceID: ContentTabID(rawValue: "still-missing"),
                    duplicateID: ContentTabID(rawValue: "unused"),
                ),
            ]),
        )
        XCTAssertEqual(state, beforeNoOp)
    }

    /// CTM-001-duplicate_selected_content_tabs: ordered validation 후 valid prefix만 capacity에 적용함
    /// 선택 Set 순서와 무관하게 pinned-first 표시 순서로 모든 source를 검증하고 부분 성공 피드백을 집계한다.
    /// - 검증 내용: stale count, missing directory, valid-before-capacity filtering, fresh deterministic IDs, aggregate
    /// alert 1회
    /// - 사전 조건: pinned invalid Directory와 valid Home/Collection/AI source, stale selection, 남은 capacity 2
    /// - 기대 결과: Home과 Collection request만 한 batch action으로 전달되고 AI는 capacity skip, alert은 success 2/skipped 3을 표시함
    func testDuplicateSelectedCommand_plansOrderedValidPrefixAndShowsOneAggregateAlert() async throws {
        let homeID = ContentTabID(rawValue: "home")
        let missingDirectoryID = ContentTabID(rawValue: "missing-directory")
        let collectionID = ContentTabID(rawValue: "collection")
        let aiID = ContentTabID(rawValue: "ai")
        let staleID = ContentTabID(rawValue: "stale")
        let collectionURL = URL(fileURLWithPath: "/collections/saved.voycoll")
        let aiSessionID = "11111111-1111-1111-1111-111111111111"
        let homeDuplicateUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let collectionDuplicateUUID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let generatedUUIDs = LockIsolated([homeDuplicateUUID, collectionDuplicateUUID])
        let ordering = LockIsolated<[String]>([])
        let alerts = LockIsolated<[(title: String, message: String)]>([])
        var tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(id: homeID, page: .home, anchor: .homeDefault, isPinned: false,
                           title: "Home", iconName: "house"),
            ContentTabItem(id: missingDirectoryID, page: .directory, anchor: .directory(path: "/missing"),
                           isPinned: true, title: "Missing Directory", iconName: "folder"),
            ContentTabItem(id: collectionID, page: .collection, anchor: .collectionFile(url: collectionURL),
                           isPinned: false, title: "Saved Collection", iconName: "rectangle.stack"),
            ContentTabItem(id: aiID, page: .aiChat, anchor: .aiChat(sessionID: aiSessionID), isPinned: false,
                           title: "AI Chat", iconName: "sparkles"),
        ]
        for index in 0 ..< ContentTabConstants.maxTabs - 6 {
            tabs.append(ContentTabItem(
                id: ContentTabID(rawValue: "planner-filler-\(index)"),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
        }
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: tabs, activeTabID: homeID)
        state.contentTabs.selectedTabIDs = [aiID, staleID, collectionID, missingDirectoryID, homeID]
        state.tabContentStates[collectionID] = .init()

        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case .contentTabs(.duplicateSelected) = action {
                    ordering.withValue { $0.append("action") }
                }
                return FileManagerWindowCommandRoutingReducer().reduce(into: &state, action: action)
            }
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                generatedUUIDs.withValue { $0.removeFirst() }
            }
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                if path == "/missing" { return false }
                isDirectory?.pointee = ObjCBool(path != collectionURL.path)
                return true
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                ordering.withValue { $0.append("alert") }
                alerts.withValue { $0.append((title, message)) }
            }
        }

        await store.send(.request(.duplicateSelectedContentTabs))
        await store.receive { action in
            guard case let .contentTabs(.duplicateSelected(requests)) = action else { return false }
            return requests == [
                ContentTabDuplicateRequest(
                    sourceID: homeID,
                    duplicateID: ContentTabID(rawValue: homeDuplicateUUID.uuidString),
                ),
                ContentTabDuplicateRequest(
                    sourceID: collectionID,
                    duplicateID: ContentTabID(rawValue: collectionDuplicateUUID.uuidString),
                ),
            ]
        }
        await store.finish()

        XCTAssertEqual(ordering.value, ["action", "alert"])
        let recordedAlerts = alerts.value
        XCTAssertEqual(recordedAlerts.count, 1)
        XCTAssertEqual(recordedAlerts[0].title, "Some Tabs Couldn’t Be Duplicated")
        XCTAssertTrue(recordedAlerts[0].message.contains("Duplicated 2 tabs. Skipped 2 tabs."))
        XCTAssertTrue(recordedAlerts[0].message.contains("Missing Directory: The directory no longer exists."))
        XCTAssertTrue(recordedAlerts[0].message.contains("AI Chat: The tab limit was reached."))
        XCTAssertFalse(recordedAlerts[0].message.contains("selected tab is unavailable"))
    }

    /// CTM-001-duplicate_selected_content_tabs: repeated UUID collision은 bounded fallback으로 해소함
    /// 기존 tab ID와 충돌하는 constant UUID가 모든 request에 반복되어도 planner가 종료하고 unique ID를 만든다.
    /// - 검증 내용: existing collision, repeated UUID, multi-request uniqueness, deterministic suffix fallback
    /// - 사전 조건: UUID rawValue tab이 이미 존재하고 두 valid Home source가 selected, uuid dependency는 constant
    /// - 기대 결과: planner가 hang 없이 `UUID-1`, `UUID-2` distinct ID를 가진 batch action을 전달함
    func testDuplicateSelectedCommand_repeatedUUIDCollisionUsesDistinctBoundedFallbacks() async throws {
        let collisionUUID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let collisionID = ContentTabID(rawValue: collisionUUID.uuidString)
        let firstSourceID = ContentTabID(rawValue: "first-source")
        let secondSourceID = ContentTabID(rawValue: "second-source")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(id: collisionID, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "Existing", iconName: "house"),
                ContentTabItem(id: firstSourceID, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "First", iconName: "house"),
                ContentTabItem(id: secondSourceID, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "Second", iconName: "house"),
            ],
            activeTabID: firstSourceID,
        )
        state.contentTabs.selectedTabIDs = [secondSourceID, firstSourceID]
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.uuid = .constant(collisionUUID)
        }

        await store.send(.request(.duplicateSelectedContentTabs))
        await store.receive { action in
            guard case let .contentTabs(.duplicateSelected(requests)) = action else { return false }
            return requests == [
                ContentTabDuplicateRequest(
                    sourceID: firstSourceID,
                    duplicateID: ContentTabID(rawValue: "\(collisionUUID.uuidString)-1"),
                ),
                ContentTabDuplicateRequest(
                    sourceID: secondSourceID,
                    duplicateID: ContentTabID(rawValue: "\(collisionUUID.uuidString)-2"),
                ),
            ]
        }
    }

    /// CTM-001-duplicate_selected_content_tabs: active/inactive source Content state를 각각 검증함
    /// temporary active Collection과 inactive saving Collection을 포함한 전부 invalid selection을 source별 feedback으로 집계한다.
    /// - 검증 내용: active `state.content`, inactive `tabContentStates`, missing Collection, invalid AI validation
    /// - 사전 조건: temporary active Directory, missing Collection file, malformed AI session, saving inactive Collection
    /// - 기대 결과: child batch action 없이 zero-success aggregate alert 한 번에 네 source label/reason이 포함됨
    func testDuplicateSelectedCommand_allInvalidUsesPerSourceContentAndShowsOneFailureAlert() async {
        let temporaryID = ContentTabID(rawValue: "temporary")
        let missingCollectionID = ContentTabID(rawValue: "missing-collection")
        let invalidAIID = ContentTabID(rawValue: "invalid-ai")
        let savingCollectionID = ContentTabID(rawValue: "saving-collection")
        let missingCollectionURL = URL(fileURLWithPath: "/collections/missing.voycoll")
        let savingCollectionURL = URL(fileURLWithPath: "/collections/saving.voycoll")
        let alerts = LockIsolated<[(title: String, message: String)]>([])
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(id: temporaryID, page: .directory, anchor: .directory(path: "/temporary"),
                               isPinned: false, title: "Temporary Collection", iconName: "folder"),
                ContentTabItem(id: missingCollectionID, page: .collection,
                               anchor: .collectionFile(url: missingCollectionURL), isPinned: false,
                               title: "Missing Collection", iconName: "rectangle.stack"),
                ContentTabItem(id: invalidAIID, page: .aiChat, anchor: .aiChat(sessionID: "not-a-uuid"),
                               isPinned: false, title: "Broken AI Chat", iconName: "sparkles"),
                ContentTabItem(id: savingCollectionID, page: .collection,
                               anchor: .collectionFile(url: savingCollectionURL), isPinned: false,
                               title: "Saving Collection", iconName: "rectangle.stack"),
            ],
            activeTabID: temporaryID,
        )
        state.contentTabs.selectedTabIDs = [temporaryID, missingCollectionID, invalidAIID, savingCollectionID]
        state.content.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: .init(),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var savingContent = FileManagerContentFeature.State()
        savingContent.collection.isSaving = true
        state.tabContentStates[savingCollectionID] = savingContent

        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { path, isDirectory in
                if path == missingCollectionURL.path { return false }
                isDirectory?.pointee = ObjCBool(path == "/temporary")
                return true
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }

        await store.send(.request(.duplicateSelectedContentTabs))
        await store.finish()

        let recordedAlerts = alerts.value
        XCTAssertEqual(recordedAlerts.count, 1)
        XCTAssertEqual(recordedAlerts[0].title, "Cannot Duplicate Selected Tabs")
        XCTAssertTrue(recordedAlerts[0].message.contains("Duplicated 0 tabs. Skipped 4 tabs."))
        XCTAssertTrue(recordedAlerts[0].message.contains(
            "Temporary Collection: Cannot duplicate a temporary collection. Save the collection first.",
        ))
        XCTAssertTrue(recordedAlerts[0].message.contains(
            "Missing Collection: The collection file no longer exists.",
        ))
        XCTAssertTrue(recordedAlerts[0].message.contains(
            "Broken AI Chat: The AI Chat session is no longer valid.",
        ))
        XCTAssertTrue(recordedAlerts[0].message.contains(
            "Saving Collection: Wait for the current collection operation to finish, then try again.",
        ))
    }

    /// CTM-001-duplicate_selected_content_tabs: empty selection과 pending lifecycle은 no-op임
    /// bulk command가 selection 또는 안전한 window lifecycle 없이 child mutation/feedback을 만들지 않는지 검증한다.
    /// - 검증 내용: empty selection, pending close, pending teardown command guard
    /// - 사전 조건: 각각 selection 없음, selected Home + pending close, selected Home + pending teardown
    /// - 기대 결과: 세 command 모두 emitted child action과 aggregate alert 없이 종료됨
    func testDuplicateSelectedCommand_emptyOrPendingLifecycleIsNoOp() async {
        let sourceID = ContentTabID(rawValue: "source")
        let source = ContentTabItem(id: sourceID, page: .home, anchor: .homeDefault, isPinned: false,
                                    title: "Home", iconName: "house")
        let alerts = LockIsolated<[(title: String, message: String)]>([])

        var emptyState = FileManagerFeature.State()
        emptyState.contentTabs = ContentTabState(tabs: [source], activeTabID: sourceID)
        let emptyStore = TestStore(initialState: emptyState) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }
        await emptyStore.send(.request(.duplicateSelectedContentTabs))
        await emptyStore.finish()

        var closingState = emptyState
        closingState.contentTabs.selectedTabIDs = [sourceID]
        closingState.pendingContentTabClose = PendingContentTabClose(tabID: sourceID)
        let closingStore = TestStore(initialState: closingState) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }
        await closingStore.send(.request(.duplicateSelectedContentTabs))
        await closingStore.finish()

        var teardownState = emptyState
        teardownState.contentTabs.selectedTabIDs = [sourceID]
        teardownState.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: UUID(),
            tabID: sourceID,
            ownerID: UUID(),
        )
        let teardownStore = TestStore(initialState: teardownState) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }
        await teardownStore.send(.request(.duplicateSelectedContentTabs))
        await teardownStore.finish()

        XCTAssertTrue(alerts.value.isEmpty)
    }

    /// CTM-001-duplicate_selected_content_tabs: capacity zero는 aggregate failure만 표시함
    /// selected source가 있어도 tab limit에 도달한 경우 child mutation 없이 distinct capacity reason을 제공한다.
    /// - 검증 내용: zero remaining capacity, zero-success title, capacity skip reason
    /// - 사전 조건: maxTabs개의 Home tab 중 active와 다른 현재 tab이 selected
    /// - 기대 결과: batch child action 없이 `Cannot Duplicate Selected Tabs` alert 한 번에 skipped 2를 표시함
    func testDuplicateSelectedCommand_zeroCapacityShowsOneAggregateFailure() async {
        let sourceID = ContentTabID(rawValue: "source")
        let alerts = LockIsolated<[(title: String, message: String)]>([])
        var tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(id: sourceID, page: .home, anchor: .homeDefault, isPinned: false,
                           title: "Home", iconName: "house"),
        ]
        for index in 1 ..< ContentTabConstants.maxTabs {
            tabs.append(ContentTabItem(
                id: ContentTabID(rawValue: "capacity-filler-\(index)"),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
        }
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: tabs, activeTabID: sourceID)
        let secondSourceID = ContentTabID(rawValue: "capacity-filler-1")
        state.contentTabs.selectedTabIDs = [sourceID, secondSourceID]

        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }

        await store.send(.request(.duplicateSelectedContentTabs))
        await store.finish()

        let recordedAlerts = alerts.value
        XCTAssertEqual(recordedAlerts.count, 1)
        guard let alert = recordedAlerts.first else { return }
        XCTAssertEqual(alert.title, "Cannot Duplicate Selected Tabs")
        XCTAssertTrue(alert.message.contains("Duplicated 0 tabs. Skipped 2 tabs."))
        XCTAssertEqual(alert.message.components(separatedBy: "The tab limit was reached.").count - 1, 2)
    }

    /// CTM-001-duplicate_selected_content_tabs: batch는 모든 source owner를 handoff 전에 snapshot함
    /// Directory와 saved Collection source를 함께 복제해 history-only fresh owner와 Inspector 경계를 검증한다.
    /// - 검증 내용: active/inactive source snapshot, duplicate cache population, single active handoff, default Inspector
    /// - 사전 조건: live Directory owner, dirty saved Collection cache, source별 history와 non-default Inspector state
    /// - 기대 결과: 첫 Directory duplicate만 active이고 Collection duplicate는 fresh cache이며 source owner는 보존됨
    func testDuplicateSelectedBatch_snapshotsDirectoryAndCollectionOwnersBeforeSingleHandoff() async throws {
        let fixture = makeBatchDirectoryCollectionOwnerFixture()
        let directorySource = fixture.state.content
        let collectionSource = try XCTUnwrap(fixture.state.tabContentStates[fixture.collectionID])
        let collectionInspectorBefore = fixture.state.tabInspectorStates[fixture.collectionID]
        let store = TestStore(initialState: fixture.state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: batch handoff가 navigation child action을 방출하므로 owner 경계 결과에 집중한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicateSelected([
            ContentTabDuplicateRequest(
                sourceID: fixture.directoryID,
                duplicateID: fixture.directoryDuplicateID,
            ),
            ContentTabDuplicateRequest(
                sourceID: fixture.collectionID,
                duplicateID: fixture.collectionDuplicateID,
            ),
        ])))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.directoryDuplicateID)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, fixture.directoryID)
        XCTAssertEqual(
            store.state.contentTabs.selectedTabIDs,
            Set([fixture.directoryID, fixture.collectionID]),
        )
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, fixture.collectionID)
        XCTAssertEqual(store.state.content.navigation.backHistory, directorySource.navigation.backHistory)
        XCTAssertEqual(store.state.content.navigation.forwardHistory, directorySource.navigation.forwardHistory)
        XCTAssertNil(store.state.content.pendingSelectEntryID)
        XCTAssertFalse(store.state.content.composer.isPresented)
        XCTAssertTrue(store.state.content.composer.text.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.selectedEntryIDs.isEmpty)
        XCTAssertEqual(
            store.state.tabContentStates[fixture.directoryID]?.navigation.backHistory,
            directorySource.navigation.backHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[fixture.directoryID]?.navigation.forwardHistory,
            directorySource.navigation.forwardHistory,
        )
        XCTAssertEqual(store.state.tabContentStates[fixture.directoryID]?.pendingSelectEntryID, "directory-entry")

        let duplicate = try XCTUnwrap(store.state.tabContentStates[fixture.collectionDuplicateID])
        XCTAssertEqual(duplicate.navigation.backHistory, collectionSource.navigation.backHistory)
        XCTAssertEqual(duplicate.navigation.forwardHistory, collectionSource.navigation.forwardHistory)
        XCTAssertFalse(duplicate.entryViewLayout.isCollectionMode)
        XCTAssertNil(duplicate.collection.collectionContext)
        XCTAssertNil(duplicate.collection.collectionSession.document)
        XCTAssertNil(duplicate.collection.collectionSession.metadata.baseline)
        XCTAssertFalse(duplicate.collection.isSaving)
        XCTAssertFalse(duplicate.composer.isPresented)
        XCTAssertTrue(duplicate.composer.text.isEmpty)
        XCTAssertEqual(
            store.state.contentTabs.tabs[id: fixture.collectionDuplicateID]?.anchor,
            .collectionFile(url: fixture.collectionURL),
        )
        XCTAssertEqual(store.state.tabContentStates[fixture.collectionID], collectionSource)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(
            store.state.tabInspectorStates[fixture.directoryDuplicateID],
            FileManagerInspectorFeature.State().tabSnapshot(),
        )
        XCTAssertNil(store.state.tabInspectorStates[fixture.collectionDuplicateID])
        XCTAssertEqual(store.state.tabInspectorStates[fixture.directoryID]?.inspectorVisible, true)
        XCTAssertEqual(store.state.tabInspectorStates[fixture.collectionID], collectionInspectorBefore)
        await store.finish()
    }

    /// CTM-001-duplicate_selected_content_tabs: same-session AI sources는 lifecycle owner를 한 번만 보존함
    /// 동일한 in-flight session을 가리키는 두 source의 batch가 restore/cancel을 중복 생성하지 않는지 검증한다.
    /// - 검증 내용: pre-handoff source snapshot, session-keyed background owner dedup, disk restore 미호출
    /// - 사전 조건: active/inactive AI source가 같은 session과 processing request lock을 공유함
    /// - 기대 결과: 두 duplicate는 같은 anchor를 유지하고 source generation은 processing이며 background owner key는 하나임
    func testDuplicateSelectedBatch_sameSessionAiPreservesOneLifecycleOwnerWithoutRestoreOrCancel() async {
        let fixture = makeBatchSameSessionAiFixture()
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: fixture.sessionID,
            status: .active,
            provider: fixture.requestLock.context.provider,
            model: fixture.requestLock.selectedModelHandle,
            selectedModelRow: fixture.requestLock.selectedModelRow,
            selectedThinking: fixture.requestLock.context.selectedThinking,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "shared request"),
                AiChatMessage(role: .assistant, content: "latest done"),
            ],
            lastRequestID: fixture.requestLock.requestID,
            lastRunID: fixture.requestLock.runID,
            lastRequestContext: fixture.requestLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        )
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let store = TestStore(initialState: fixture.state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { requestedSessionID in
                loadedSessionIDs.withValue { $0.append(requestedSessionID) }
                return nil
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: AI handoff의 provider/navigation action보다 lifecycle owner dedup 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicateSelected([
            ContentTabDuplicateRequest(
                sourceID: fixture.firstSourceID,
                duplicateID: fixture.firstDuplicateID,
            ),
            ContentTabDuplicateRequest(
                sourceID: fixture.secondSourceID,
                duplicateID: fixture.secondDuplicateID,
            ),
        ])))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.firstDuplicateID)
        XCTAssertEqual(
            store.state.contentTabs.tabs[id: fixture.secondDuplicateID]?.anchor,
            .aiChat(sessionID: fixture.sessionID.rawValue.uuidString),
        )
        XCTAssertEqual(
            store.state.tabContentStates[fixture.firstSourceID]?.aiChat.executionPhase,
            .processing(fixture.requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[fixture.secondSourceID]?.aiChat.executionPhase,
            .processing(fixture.requestLock),
        )
        XCTAssertEqual(store.state.backgroundAiChatStates.count, 1)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[fixture.sessionID]?.aiChat.executionPhase,
            .processing(fixture.requestLock),
        )
        XCTAssertEqual(store.state.content.aiChat.sessionID, fixture.sessionID)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .idle)
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
        XCTAssertTrue(store.state.content.aiChat.draftText.isEmpty)
        XCTAssertNil(store.state.tabContentStates[fixture.secondDuplicateID]?.aiChat.sessionID)
        XCTAssertEqual(loadedSessionIDs.value, [])

        await store.send(.backgroundAiChatSnapshotPersisted(finalSnapshot))

        XCTAssertEqual(store.state.content.aiChat.sessionID, fixture.sessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertEqual(
            store.state.tabContentStates[fixture.firstDuplicateID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[fixture.firstSourceID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[fixture.secondSourceID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[fixture.sessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])
        await store.finish()
    }

    /// CTM-001-duplicate_selected_content_tabs: pending close direct batch는 생성 row/cache만 exact rollback함
    /// malformed existing-ID request와 capacity-truncated request가 pending target/source state를 제거하지 않는지 검증한다.
    /// - 검증 내용: created-ID filtering, all-duplicate rollback, pending active/previous 복원, selection/source cache 보존
    /// - 사전 조건: pending inactive close, 남은 capacity 2, existing target collision과 세 valid source request
    /// - 기대 결과: 두 generated duplicate만 제거되고 pending target, source rows/caches, selection은 원본과 동일함
    func testDuplicateSelectedBatch_pendingCloseRollsBackEveryCreatedDuplicateOnly() async {
        let fixture = makeBatchPendingCloseFixture()
        let originalTabIDs = Array(fixture.state.contentTabs.tabs.ids)
        let originalSelection = fixture.state.contentTabs.selectedTabIDs
        let originalSelectionAnchor = fixture.state.contentTabs.selectionAnchorID
        let originalContent = fixture.state.content
        let originalInspector = fixture.state.inspector
        let originalSourceCaches = fixture.state.tabContentStates
        let originalInspectorCaches = fixture.state.tabInspectorStates
        let originalPendingClose = fixture.state.pendingContentTabClose
        let store = TestStore(initialState: fixture.state) {
            FileManagerFeature()
        }
        // store.exhaustivity = .off: defensive rollback의 exact 최종 state와 보존 경계를 직접 비교한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicateSelected([
            ContentTabDuplicateRequest(sourceID: fixture.firstSourceID, duplicateID: fixture.firstDuplicateID),
            ContentTabDuplicateRequest(sourceID: fixture.secondSourceID, duplicateID: fixture.secondDuplicateID),
            ContentTabDuplicateRequest(sourceID: fixture.thirdSourceID, duplicateID: fixture.pendingTargetID),
            ContentTabDuplicateRequest(sourceID: fixture.thirdSourceID, duplicateID: fixture.truncatedDuplicateID),
        ])))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(Array(store.state.contentTabs.tabs.ids), originalTabIDs)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.pendingTargetID])
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.firstDuplicateID])
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.secondDuplicateID])
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.truncatedDuplicateID])
        XCTAssertNil(store.state.tabContentStates[fixture.firstDuplicateID])
        XCTAssertNil(store.state.tabContentStates[fixture.secondDuplicateID])
        XCTAssertNil(store.state.tabInspectorStates[fixture.firstDuplicateID])
        XCTAssertNil(store.state.tabInspectorStates[fixture.secondDuplicateID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.pendingTargetID)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, fixture.firstSourceID)
        XCTAssertEqual(
            store.state.contentTabs.selectedTabIDs,
            originalSelection,
        )
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, originalSelectionAnchor)
        XCTAssertEqual(store.state.content, originalContent)
        XCTAssertEqual(store.state.inspector, originalInspector)
        XCTAssertEqual(store.state.tabContentStates, originalSourceCaches)
        XCTAssertEqual(store.state.tabInspectorStates, originalInspectorCaches)
        XCTAssertEqual(store.state.pendingContentTabClose, originalPendingClose)
        await store.finish()
    }

    /// CTM-001-duplicate_selected_content_tabs: identical active collision은 generated duplicate로 오인하지 않음
    /// Core가 거부한 existing ID와 source metadata가 같아도 Window owner state를 handoff/삭제하지 않는지 검증한다.
    /// - 검증 내용: zero-success existing-ID collision의 row, live Content/Inspector, owner cache 보존
    /// - 사전 조건: source와 동일 metadata를 가진 existing active tab 및 source/active owner caches
    /// - 기대 결과: routing reducer가 existing active row를 generated duplicate로 분류하지 않고 owner state를 유지함
    func testDuplicateSelectedBatch_identicalActiveCollisionPreservesExistingOwnerState() async {
        let sourceID = ContentTabID(rawValue: "collision-source")
        let existingID = ContentTabID(rawValue: "collision-existing")
        let sourceItem = ContentTabItem(
            id: sourceID,
            page: .directory,
            anchor: .directory(path: "/same"),
            isPinned: false,
            title: "Same",
            iconName: "folder",
        )
        let existingItem = ContentTabItem(
            id: existingID,
            page: sourceItem.page,
            anchor: sourceItem.anchor,
            isPinned: false,
            title: sourceItem.title,
            iconName: sourceItem.iconName,
        )
        var sourceContent = FileManagerContentFeature.State()
        sourceContent.pendingSelectEntryID = "source-owner"
        var existingContent = FileManagerContentFeature.State()
        existingContent.pendingSelectEntryID = "existing-owner"
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: [sourceItem, existingItem], activeTabID: existingID)
        state.contentTabs.previousActiveTabID = sourceID
        state.content = existingContent
        state.tabContentStates = [sourceID: sourceContent]
        state.inspector.inspectorVisible = true
        state.tabInspectorStates[sourceID] = FileManagerInspectorFeature.State().tabSnapshot()
        state.syncContentTabSidebarItems()
        let originalTabs = state.contentTabs
        let originalContent = state.content
        let originalInspector = state.inspector
        let originalContentCaches = state.tabContentStates
        let originalInspectorCaches = state.tabInspectorStates
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // store.exhaustivity = .off: malformed direct action의 owner-state no-op 경계만 비교한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicateSelected([
            ContentTabDuplicateRequest(sourceID: sourceID, duplicateID: existingID),
        ])))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs, originalTabs)
        XCTAssertEqual(store.state.content, originalContent)
        XCTAssertEqual(store.state.inspector, originalInspector)
        XCTAssertEqual(store.state.tabContentStates, originalContentCaches)
        XCTAssertEqual(store.state.tabInspectorStates, originalInspectorCaches)
        await store.finish()
    }

    /// CTM-001-duplicate_selected_content_tabs: core가 거부한 repeated source는 owner snapshot에 참여하지 않음
    /// 동일 metadata source 사이에서 rejected request와 accepted request의 duplicate ID가 같아도 owner를 정확히 연결한다.
    /// - 검증 내용: core seenSourceIDs replay와 inactive duplicate source-history ownership
    /// - 사전 조건: A→X 성공, repeated-source A→Y 거부, identical-metadata B→Y 성공 요청 순서
    /// - 기대 결과: X는 A history, Y는 B history를 가진 fresh owner로 초기화됨
    func testDuplicateSelectedBatch_replaysCoreRequestUniquenessForOwnerMapping() async {
        let firstSourceID = ContentTabID(rawValue: "mapping-source-a")
        let secondSourceID = ContentTabID(rawValue: "mapping-source-b")
        let firstDuplicateID = ContentTabID(rawValue: "mapping-duplicate-x")
        let secondDuplicateID = ContentTabID(rawValue: "mapping-duplicate-y")
        let anchor = ContentTabPageAnchor.directory(path: "/same-source-metadata")
        let firstItem = ContentTabItem(
            id: firstSourceID,
            page: .directory,
            anchor: anchor,
            isPinned: false,
            title: "Same",
            iconName: "folder",
        )
        let secondItem = ContentTabItem(
            id: secondSourceID,
            page: firstItem.page,
            anchor: firstItem.anchor,
            isPinned: false,
            title: firstItem.title,
            iconName: firstItem.iconName,
        )
        var firstContent = FileManagerContentFeature.State()
        firstContent.navigation.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        var secondContent = FileManagerContentFeature.State()
        secondContent.navigation.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .recents)]
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: [firstItem, secondItem], activeTabID: firstSourceID)
        state.contentTabs.selectedTabIDs = [firstSourceID, secondSourceID]
        state.contentTabs.selectionAnchorID = secondSourceID
        state.content = firstContent
        state.tabContentStates = [firstSourceID: firstContent, secondSourceID: secondContent]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: owner mapping 결과 외 handoff navigation action은 이 시나리오 범위가 아니다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicateSelected([
            ContentTabDuplicateRequest(sourceID: firstSourceID, duplicateID: firstDuplicateID),
            ContentTabDuplicateRequest(sourceID: firstSourceID, duplicateID: secondDuplicateID),
            ContentTabDuplicateRequest(sourceID: secondSourceID, duplicateID: secondDuplicateID),
        ])))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs.activeTabID, firstDuplicateID)
        XCTAssertEqual(store.state.content.navigation.backHistory, firstContent.navigation.backHistory)
        XCTAssertEqual(
            store.state.tabContentStates[secondDuplicateID]?.navigation.backHistory,
            secondContent.navigation.backHistory,
        )
        XCTAssertEqual(store.state.tabContentStates[secondSourceID], secondContent)
        await store.finish()
    }

    /// CTM-001-duplicate_selected_content_tabs: 한 Window의 batch owner mutation은 다른 Window state를 변경하지 않음
    /// File Manager window별 reducer state가 독립 value owner로 유지되는지 검증한다.
    /// - 검증 내용: 첫 Window direct batch reduce 전후 두 번째 Window whole-state equality
    /// - 사전 조건: 서로 다른 tab identity와 Content history를 가진 두 FileManagerWindowState value
    /// - 기대 결과: 첫 Window에 duplicate가 생성되어도 두 번째 Window는 전체 state가 동일함
    func testDuplicateSelectedBatch_doesNotMutateSecondWindowState() {
        let firstSourceID = ContentTabID(rawValue: "first-window-source")
        let firstDuplicateID = ContentTabID(rawValue: "first-window-duplicate")
        var firstWindow = FileManagerFeature.State()
        firstWindow.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: firstSourceID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "First Window",
                iconName: "house",
            )],
            activeTabID: firstSourceID,
        )
        firstWindow.contentTabs.selectedTabIDs = [firstSourceID]
        firstWindow.contentTabs.selectionAnchorID = firstSourceID
        firstWindow.syncActiveTabContentState()

        let secondSourceID = ContentTabID(rawValue: "second-window-source")
        var secondWindow = FileManagerFeature.State()
        secondWindow.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: secondSourceID,
                page: .directory,
                anchor: .directory(path: "/second-window"),
                isPinned: false,
                title: "Second Window",
                iconName: "folder",
            )],
            activeTabID: secondSourceID,
        )
        secondWindow.content.navigation.backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .home),
        ]
        secondWindow.syncActiveTabContentState()
        secondWindow.syncActiveTabInspectorState()
        secondWindow.syncContentTabSidebarItems()
        let secondWindowBefore = secondWindow

        _ = FileManagerFeature().reduce(
            into: &firstWindow,
            action: .contentTabs(.duplicateSelected([
                ContentTabDuplicateRequest(sourceID: firstSourceID, duplicateID: firstDuplicateID),
            ])),
        )

        XCTAssertNotNil(firstWindow.contentTabs.tabs[id: firstDuplicateID])
        XCTAssertEqual(secondWindow, secondWindowBefore)
    }

    // MARK: - CTM-001-close_selected_content_tabs

    /// CTM-001-close_selected_content_tabs: batch coordinator 전체 lifetime은 topology menu capability를 차단함
    /// current item 처리 중과 inter-item gap 모두 동일한 Window-owned topology gate를 투영하는지 검증한다.
    /// - 검증 내용: New Tab, Pin/Unpin, Duplicate selected/active, Restore capability false
    /// - 사전 조건: A/B가 선택되고 restore candidate가 있으며 batch current 또는 current nil gap 상태
    /// - 기대 결과: 두 coordinator 상태 모두 topology command capability가 비활성화됨
    func testCloseSelectedContentTabs_disablesTopologyMenuCapabilitiesForCurrentAndGap() {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = UUID()

        for currentTabID in [fixture.tabA, nil] {
            var state = fixture.state
            state.contentTabs.selectedTabIDs = [fixture.tabA, fixture.tabB]
            state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
                operationID: operationID,
                orderedTargetIDs: [fixture.tabA, fixture.tabB],
                cursor: currentTabID == nil ? 1 : 0,
                currentTabID: currentTabID,
                originalActiveTabID: fixture.tabC,
                preferredFallbackIDs: [fixture.tabC],
            )
            if let currentTabID {
                state.pendingContentTabClose = PendingContentTabClose(
                    tabID: currentTabID,
                    batchOperationID: operationID,
                )
            }

            let projection = state.menuCommandProjection
            XCTAssertFalse(projection.canOpenNewContentTab)
            XCTAssertFalse(projection.canToggleActiveContentTabPin)
            XCTAssertFalse(projection.canDuplicateSelectedContentTabs)
            XCTAssertFalse(projection.canDuplicateActiveContentTab)
            XCTAssertFalse(projection.canRestoreLastClosedTab)
        }
    }

    /// CTM-001-close_selected_content_tabs: undo/redo busy phase는 batch close 시작 capability를 차단함
    /// Sidebar, menu, direct request가 하나의 Window-owned 시작 capability를 공유하는지 검증한다.
    /// - 검증 내용: busy phase의 두 UI projection 비활성화와 direct request whole-state no-start
    /// - 사전 조건: A/B/C가 선택되고 undo/redo가 invoking/replaying/refreshing/recovering/tearingDownTab 중임
    /// - 기대 결과: 세 pending close/teardown은 nil이고 idle/desynchronized에서만 batch 시작이 허용됨
    func testCloseSelectedContentTabs_undoRedoPhaseControlsSharedStartCapability() throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let ownerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        let busyPhases: [FileManagerUndoRedoPhase] = [
            .invoking(requestID: requestID, direction: .undo),
            .replaying(requestID: requestID, direction: .redo),
            .refreshing(requestID: requestID),
            .recovering(requestID: requestID, direction: .undo, ownerID: ownerID),
            .tearingDownTab(requestID: requestID, ownerID: ownerID),
        ]

        for phase in busyPhases {
            var state = fixture.state
            state.undoRedoPhase = phase

            XCTAssertFalse(state.contentTabRowInteractionSurface.isCloseEnabled)
            XCTAssertFalse(state.menuCommandProjection.canCloseSelectedContentTabs)
            _ = withDependencies {
                $0.uuid = .constant(requestID)
            } operation: {
                FileManagerWindowRoutingReducer().reduce(
                    into: &state,
                    action: .requestCloseSelectedContentTabs,
                )
            }
            XCTAssertNil(state.pendingSelectedContentTabClose)
            XCTAssertNil(state.pendingContentTabClose)
            XCTAssertNil(state.pendingContentTabTeardown)
        }

        for phase in [FileManagerUndoRedoPhase.idle, .desynchronized] {
            var state = fixture.state
            state.undoRedoPhase = phase

            XCTAssertTrue(state.contentTabRowInteractionSurface.isCloseEnabled)
            XCTAssertTrue(state.menuCommandProjection.canCloseSelectedContentTabs)
            _ = withDependencies {
                $0.uuid = .constant(requestID)
            } operation: {
                FileManagerWindowRoutingReducer().reduce(
                    into: &state,
                    action: .requestCloseSelectedContentTabs,
                )
            }
            XCTAssertNotNil(state.pendingSelectedContentTabClose)
            XCTAssertNil(state.pendingContentTabClose)
            XCTAssertNil(state.pendingContentTabTeardown)
        }
    }

    /// CTM-001-close_selected_content_tabs: batch coordinator 수명 동안 Undo/Redo를 역방향 차단함
    /// current item과 inter-item gap 모두 menu projection과 direct command가 동일한 Window guard를 사용하는지 검증한다.
    /// - 검증 내용: undo/redo capability false와 direct request 뒤 phase/coordinator/pending state 불변
    /// - 사전 조건: 유효한 local record/manager target과 current 또는 gap 상태의 selected-close coordinator
    /// - 기대 결과: 두 방향 모두 invoking으로 진입하지 않고 batch lifecycle state가 그대로 유지됨
    func testCloseSelectedContentTabs_blocksUndoRedoDuringCurrentAndGap() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        let blockedStates = makeUndoRedoBlockedSelectedCloseStates(
            fixture: fixture,
            operationID: operationID,
        )
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            availability: { _ in .init() },
        )

        for initialState in blockedStates {
            var availableState = initialState
            availableState.pendingSelectedContentTabClose = nil
            availableState.pendingContentTabClose = nil
            XCTAssertTrue(availableState.menuCommandProjection.canUndo)
            XCTAssertTrue(availableState.menuCommandProjection.canRedo)
            XCTAssertFalse(initialState.menuCommandProjection.canUndo)
            XCTAssertFalse(initialState.menuCommandProjection.canRedo)

            for command in [
                FileManagerWindowAction.WindowCommand.requestUndo,
                .requestRedo,
            ] {
                let store = TestStore(initialState: initialState) {
                    FileManagerWindowCommandRoutingReducer()
                } withDependencies: {
                    $0.undoManagerClient = client
                    $0.uuid = .constant(requestID)
                }

                await store.send(.request(command))
                XCTAssertEqual(store.state.undoRedoPhase, initialState.undoRedoPhase)
                XCTAssertEqual(
                    store.state.pendingSelectedContentTabClose,
                    initialState.pendingSelectedContentTabClose,
                )
                XCTAssertEqual(store.state.pendingContentTabClose, initialState.pendingContentTabClose)
                XCTAssertEqual(store.state.pendingContentTabTeardown, initialState.pendingContentTabTeardown)
            }
        }
    }

    /// CTM-001-close_selected_content_tabs: active fallback snapshot은 pinned-first Sidebar 순서를 사용함
    /// raw storage에 pinned tab이 interleave되어도 사용자가 보는 active 오른쪽 survivor가 우선하는지 검증한다.
    /// - 검증 내용: frozen fallback identity와 active target 제거 뒤 최종 active tab
    /// - 사전 조건: raw 순서 active/pinned/right/target, visual 순서 pinned/active/right/target, active와 target 선택
    /// - 기대 결과: raw에서 먼저 보이는 pinned 후보가 아니라 visual right survivor가 active가 됨
    func testCloseSelectedContentTabs_fallbackUsesPinnedFirstSidebarOrder() async throws {
        let activeID = ContentTabID(rawValue: "interleaved-active")
        let pinnedID = ContentTabID(rawValue: "interleaved-pinned")
        let visualRightID = ContentTabID(rawValue: "interleaved-visual-right")
        let targetID = ContentTabID(rawValue: "interleaved-target")
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let initialState = makePinnedFirstInterleavedSelectedCloseState(
            activeID: activeID,
            pinnedID: pinnedID,
            visualRightID: visualRightID,
            targetID: targetID,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Date(timeIntervalSince1970: 453))
        }
        // store.exhaustivity = .off: 모든 batch lifecycle action을 receive하고 frozen fallback과 최종 identity를 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.requestCloseSelectedContentTabs)
        XCTAssertEqual(
            store.state.pendingSelectedContentTabClose?.preferredFallbackIDs.first,
            visualRightID,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receiveRemovedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: targetID,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receiveRemovedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: activeID,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, visualRightID)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: pinnedID])
    }

    /// CTM-001-close_selected_content_tabs: 선택 identity를 고정하고 active tab을 마지막으로 직렬 처리함
    /// 사용자가 두 개 이상의 Content Tab을 닫을 때 Window가 한 번에 하나의 target만 진행하는 계약을 검증한다.
    /// - 검증 내용: 0/1개 no-start, frozen original order, active-last ordering, current cursor의 단일 진행과 종료 clear
    /// - 사전 조건: Sidebar 순서 A/B/C/D, active C, selected A/B/C와 고정 UUID dependency
    /// - 기대 결과: coordinator가 [A, B, C]를 고정하고 current A부터 terminal마다 정확히 한 칸 진행한 뒤 clear됨
    func testCloseSelectedContentTabs_freezesOrderAndAdvancesSerially() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))

        for selectedIDs in [Set<ContentTabID>(), Set([fixture.tabA])] {
            var noStartState = fixture.state
            noStartState.contentTabs.selectedTabIDs = selectedIDs
            let noStartStore = TestStore(initialState: noStartState) {
                FileManagerWindowRoutingReducer()
            } withDependencies: {
                $0.uuid = .constant(operationID)
            }

            await noStartStore.send(.requestCloseSelectedContentTabs)
            XCTAssertEqual(noStartStore.state, noStartState)
        }

        var startedState = fixture.state
        _ = withDependencies {
            $0.uuid = .constant(operationID)
        } operation: {
            FileManagerWindowRoutingReducer().reduce(
                into: &startedState,
                action: .requestCloseSelectedContentTabs,
            )
        }
        XCTAssertEqual(
            startedState.pendingSelectedContentTabClose,
            PendingSelectedContentTabClose(
                operationID: operationID,
                orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
                originalActiveTabID: fixture.tabC,
                preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
            ),
        )
    }

    /// CTM-001-close_selected_content_tabs: Sidebar bulk delegate는 Window request로 전달되고 pending direct injection은
    /// no-op임
    /// Sidebar context-menu semantic intent가 canonical Window command에 수렴하고 lifecycle guard를 우회하지 않는지 검증한다.
    /// - 검증 내용: bulk delegate→`.request(.closeSelectedContentTabs)` explicit receive와 single/bulk direct injection
    /// whole-state no-op
    /// - 사전 조건: available Window와 batch/single/teardown/closing 네 unavailable Window states
    /// - 기대 결과: available bridge는 request 한 개만 방출하고 unavailable states는 action/state를 모두 보존함
    func testSidebarCloseRouting_bulkBridgeAndPendingDirectInjectionGuards() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let bridgeState = fixture.state
        let bridgeStore = TestStore(initialState: bridgeState) {
            FileManagerWindowRoutingReducer()
        }

        await bridgeStore.send(.sidebar(.delegate(.closeSelectedContentTabs)))
        await bridgeStore.receive { action in
            guard case .request(.closeSelectedContentTabs) = action else { return false }
            return true
        }
        XCTAssertEqual(bridgeStore.state, bridgeState)
        // store.finish() 불필요: 모든 effect가 receive로 소비됨

        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var blockedStates: [FileManagerWindowState] = []

        var batchState = fixture.state
        batchState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB],
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD],
        )
        blockedStates.append(batchState)

        var singleState = fixture.state
        singleState.pendingContentTabClose = PendingContentTabClose(tabID: fixture.tabA)
        blockedStates.append(singleState)

        var teardownState = fixture.state
        teardownState.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: operationID,
            tabID: fixture.tabA,
            ownerID: operationID,
        )
        blockedStates.append(teardownState)

        var closingState = fixture.state
        closingState.isClosing = true
        blockedStates.append(closingState)

        let directActions: [FileManagerWindowAction] = [
            .sidebar(.delegate(.closeContentTab(fixture.tabB))),
            .sidebar(.delegate(.closeSelectedContentTabs)),
            .requestCloseSelectedContentTabs,
            .sidebar(.delegate(.unpinContentTab(fixture.tabB))),
        ]
        for blockedState in blockedStates {
            let store = TestStore(initialState: blockedState) {
                FileManagerWindowRoutingReducer()
            }
            for action in directActions {
                await store.send(action)
                XCTAssertEqual(store.state, blockedState)
            }
            await store.finish()
        }
    }

    /// CTM-001-close_selected_content_tabs: stale terminal과 경쟁 topology mutation을 전체 상태 no-op으로 격리함
    /// batch 수명 동안 잘못된 correlation과 외부 tab mutation이 coordinator 또는 tab identity를 오염시키지 않는지 검증한다.
    /// - 검증 내용: wrong operation/tab, duplicate/late terminal, missing skip, second trigger, topology/lifecycle gate
    /// - 사전 조건: current item 처리 중 coordinator, current가 비어 있는 batch gap, processing 직전 missing target
    /// - 기대 결과: 유효 terminal과 missing만 한 칸 진행하며 stale/경쟁 action은 whole-state no-op임
    func testCloseSelectedContentTabs_rejectsStaleTerminalsAndCompetingMutations() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let wrongOperationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        await verifyStaleAndCompetingSelectedCloseActions(
            fixture: fixture,
            operationID: operationID,
            wrongOperationID: wrongOperationID,
        )
        await verifyDirtySelectedCloseTerminalsRejectWrongCorrelation(
            fixture: fixture,
            operationID: operationID,
            wrongOperationID: wrongOperationID,
        )
        await verifySelectedCloseGapRejectsCompetingActions(
            fixture: fixture,
            operationID: operationID,
        )
        await verifyMissingSelectedCloseTargetAdvances(
            fixture: fixture,
            operationID: operationID,
        )
    }

    /// CTM-001-close_selected_content_tabs: coordinator-owned child mutation은 operation과 current target을 검증함
    /// Task 3이 사용할 typed seam이 stale operation 또는 다른 tab의 mutation을 child reducer 전에 거부하는지 검증한다.
    /// - 검증 내용: wrong operation, wrong current tab, child target mismatch no-op과 valid setCurrent 전달
    /// - 사전 조건: operation 453의 current target A를 가진 coordinator와 unpinned A/B/C tabs
    /// - 기대 결과: 세 stale wrapper는 whole-state no-op이고 valid A activation만 active identity를 변경함
    func testCloseSelectedContentTabs_correlatedChildMutationValidatesBeforeReducing() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let wrongOperationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        var initialState = fixture.state
        initialState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 453))
        }

        let staleActions: [FileManagerWindowAction] = [
            .performSelectedContentTabCloseMutation(
                operationID: wrongOperationID,
                tabID: fixture.tabA,
                action: .commitClose(fixture.tabA),
            ),
            .performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: fixture.tabB,
                action: .commitClose(fixture.tabB),
            ),
            .performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: fixture.tabA,
                action: .commitClose(fixture.tabB),
            ),
        ]
        for action in staleActions {
            await store.send(action)
            XCTAssertEqual(store.state, initialState)
        }

        var expectedContentTabs = initialState.contentTabs
        _ = ContentTabFeature().reduce(into: &expectedContentTabs, action: .setCurrent(fixture.tabA))
        await store.send(.performSelectedContentTabCloseMutation(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .setCurrent(fixture.tabA),
        )) {
            $0.contentTabs = expectedContentTabs
        }
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.tabA)
    }

    /// CTM-001-close_selected_content_tabs: direct child topology action은 parent gate 이전에 차단됨
    /// Window semantic route를 우회한 ContentTab action도 batch current와 gap 전체에서 state를 변경하지 않는지 검증한다.
    /// - 검증 내용: setCurrent/open/restore/reorder/pin/unpin/duplicate/requestClose/close/commit/anchor topology action
    /// - 사전 조건: current A인 coordinator와 cursor 1/current nil인 inter-item gap coordinator
    /// - 기대 결과: 각 direct child action 처리 후 FileManagerWindowState 전체가 초기값과 동일함
    func testCloseSelectedContentTabs_blocksDirectContentTabTopologyActionsBeforeChildMutation() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let duplicateID = ContentTabID(rawValue: "blocked-direct-duplicate")
        let directActions = makeBlockedDirectContentTabActions(
            fixture: fixture,
            duplicateID: duplicateID,
        )

        var currentState = fixture.state
        currentState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            currentTabID: fixture.tabA,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
        )
        var gapState = fixture.state
        gapState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            cursor: 1,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
        )

        for initialState in [currentState, gapState] {
            for action in directActions {
                let store = TestStore(initialState: initialState) {
                    FileManagerFeature()
                } withDependencies: {
                    $0.contentTabPinnedRecordClient.updateStore = { _, _ in }
                    $0.date = .constant(Date(timeIntervalSince1970: 453))
                }
                await store.send(action)
                await store.finish()
                XCTAssertEqual(store.state, initialState)
            }
        }
    }

    /// CTM-001-close_selected_content_tabs: unrelated child terminal은 reduce되지만 cursor를 진행하지 않음
    /// batch wrapper 밖에서 도착한 Content/Navigation/pin persistence terminal이 각 child state만 정리하는지 검증한다.
    /// - 검증 내용: save-panel 취소, navigation state, pin success/failure child reduction과 batch identity 불변
    /// - 사전 조건: A가 current인 batch와 별도 pin persistence state 및 in-flight save transient
    /// - 기대 결과: child state는 갱신되지만 cursor/current/per-item close correlation은 그대로 유지된다.
    func testCloseSelectedContentTabs_unrelatedChildTerminalsReduceWithoutProgression() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var initialState = makeDirtyBatchPendingState(fixture: fixture, operationID: operationID)
        initialState.content.collection.isSaving = true
        initialState.content.collection.pendingSaveContext = CollectionContext(
            query: "pending",
            scopes: ["/tmp"],
            conditions: [],
        )
        initialState.contentTabs.pendingPinnedRecordIDs = [fixture.tabD]
        initialState.contentTabs.pinnedRecordPersistenceError = "sentinel"
        let expectedBatch = initialState.pendingSelectedContentTabClose
        let expectedPendingClose = initialState.pendingContentTabClose
        let store = TestStore(initialState: initialState) { FileManagerFeature() }

        await store.send(.content(.collection(.savePanelResponse(nil)))) {
            $0.content.collection.isSaving = false
            $0.content.collection.pendingSaveContext = nil
        }
        await store.send(.navigation(.internal(.setNavigationState(.folder("/unrelated"))))) {
            $0.content.navigation.navigationState = .folder("/unrelated")
        }
        let successIntentID = store.state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: fixture.tabB)
        await store.send(.contentTabs(.pinnedRecordSaveSucceeded(
            tabID: fixture.tabB,
            intentID: successIntentID,
        ))) {
            $0.contentTabs.pinnedRecordPersistenceError = nil
        }
        let failureIntentID = store.state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: fixture.tabD)
        await store.send(.contentTabs(.pinnedRecordSaveFailed(
            tabID: fixture.tabD,
            intentID: failureIntentID,
            previousIsPinned: true,
            previousPinnedRecord: nil,
            previousTabIndex: nil,
        ))) {
            $0.contentTabs.pendingPinnedRecordIDs.remove(fixture.tabD)
            $0.contentTabs.pinnedRecordPersistenceError = "pinned_record_save_failed"
        }

        XCTAssertEqual(store.state.pendingSelectedContentTabClose, expectedBatch)
        XCTAssertEqual(store.state.pendingContentTabClose, expectedPendingClose)
    }

    /// CTM-001-close_selected_content_tabs: 시작과 Save surface는 batch 관련 busy state를 공유함
    /// save/open/refresh/write-back/pin persistence 중에는 시작을 막고 진행 중 batch에서는 모든 Save surface를 차단하는지 검증한다.
    /// - 검증 내용: canStart gate, command/content routing no-op, menu·Composer canSaveCollection false
    /// - 사전 조건: 선택 tab 3개와 saving/open/refresh/write-back/pending pin 시작 상태 및 dirty batch 상태
    /// - 기대 결과: busy 상태는 coordinator를 만들지 않고 batch 중 Save command·직접 액션·capability가 모두 비활성화된다.
    func testCloseSelectedContentTabs_blocksStartAndSaveSurfacesWhileBusy() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var savingState = fixture.state
        savingState.content.collection.isSaving = true
        var openingState = fixture.state
        openingState.content.collection.collectionSession.phase = .reopening(
            kind: .definition,
            base: .ready,
            inflight: .none,
        )
        var refreshingState = fixture.state
        refreshingState.content.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        var writeBackState = fixture.state
        writeBackState.content.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        var pinState = fixture.state
        pinState.contentTabs.pendingPinnedRecordIDs = [fixture.tabD]

        for initialState in [savingState, openingState, refreshingState, writeBackState, pinState] {
            XCTAssertFalse(initialState.canStartSelectedContentTabClose)
            XCTAssertFalse(initialState.contentTabRowInteractionSurface.isCloseEnabled)
            XCTAssertFalse(initialState.menuCommandProjection.canCloseSelectedContentTabs)
            let store = TestStore(initialState: initialState) { FileManagerWindowRoutingReducer() } withDependencies: {
                $0.uuid = .constant(operationID)
            }
            await store.send(.requestCloseSelectedContentTabs)
            XCTAssertNil(store.state.pendingSelectedContentTabClose)
        }

        var batchState = makeDirtyBatchPendingState(fixture: fixture, operationID: operationID)
        batchState.content = makeDirtySelectedCloseContentState()
        XCTAssertTrue(batchState.content.canSaveCollection)
        XCTAssertFalse(batchState.menuCommandProjection.canSaveCollection)
        XCTAssertFalse(FileManagerContentChromePropsBuilder.makeContentOverlayProps(
            from: batchState,
            fileManagerClient: .testValue,
        ).canSaveCollection)
        for command in [
            FileManagerWindowAction.WindowCommand.saveCollection,
            .saveCollectionAs,
        ] {
            let store = TestStore(initialState: batchState) { FileManagerWindowCommandRoutingReducer() }
            await store.send(.request(command))
            XCTAssertEqual(store.state, batchState)
        }
        let contentStore = TestStore(initialState: batchState) { FileManagerFeature() }
        await contentStore.send(.content(.composer(.view(.saveCollection))))
        await contentStore.send(.content(.composer(.view(.saveCollectionAs))))
        await contentStore.finish()
        XCTAssertEqual(contentStore.state, batchState)
    }

    /// CTM-001-close_selected_content_tabs: selected inactive busy owner만 batch 시작을 차단함
    /// 실행 대상 retained content의 save/open/refresh/write-back은 거부하되 선택되지 않은 inactive owner는 무관한지 검증한다.
    /// - 검증 내용: selected inactive busy no-start와 unselected inactive busy start 허용
    /// - 사전 조건: active C, selected A/B/C, unselected D와 각 inactive retained content
    /// - 기대 결과: A가 busy면 coordinator가 없고 D만 busy면 frozen selected coordinator가 생성된다.
    func testCloseSelectedContentTabs_selectedInactiveBusyControlsStartGate() throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var savingContent = FileManagerContentFeature.State()
        savingContent.collection.isSaving = true
        var openingContent = FileManagerContentFeature.State()
        openingContent.collection.collectionSession.phase = .reopening(
            kind: .definition,
            base: .ready,
            inflight: .none,
        )
        var refreshingContent = FileManagerContentFeature.State()
        refreshingContent.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        var writeBackContent = FileManagerContentFeature.State()
        writeBackContent.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )

        for busyContent in [savingContent, openingContent, refreshingContent, writeBackContent] {
            var state = fixture.state
            state.tabContentStates[fixture.tabA] = busyContent
            XCTAssertFalse(state.canStartSelectedContentTabClose)
            _ = withDependencies {
                $0.uuid = .constant(operationID)
            } operation: {
                FileManagerWindowRoutingReducer().reduce(
                    into: &state,
                    action: .requestCloseSelectedContentTabs,
                )
            }
            XCTAssertNil(state.pendingSelectedContentTabClose)
        }

        var unrelatedBusyState = fixture.state
        unrelatedBusyState.tabContentStates[fixture.tabD] = writeBackContent
        XCTAssertTrue(unrelatedBusyState.canStartSelectedContentTabClose)
        _ = withDependencies {
            $0.uuid = .constant(operationID)
        } operation: {
            FileManagerWindowRoutingReducer().reduce(
                into: &unrelatedBusyState,
                action: .requestCloseSelectedContentTabs,
            )
        }
        XCTAssertEqual(unrelatedBusyState.pendingSelectedContentTabClose?.operationID, operationID)
    }

    /// CTM-001-close_selected_content_tabs: window disappearance는 operation state를 원자적으로 정리함
    /// inactive target staging과 undo teardown 중 window가 사라져도 이전 active owner를 복원하고 늦은 action을 무시하는지 검증한다.
    /// - 검증 내용: staged owner restore, save transient/cursor/deferred/teardown clear, undo desync, stale progression
    /// no-op
    /// - 사전 조건: A target이 active로 staging되고 save/teardown/deferred snapshot이 남은 batch operation
    /// - 기대 결과: C owner 복원 뒤 closing 상태가 되며 onAppear 후에도 이전 operation action은 batch를 되살리지 않는다.
    func testCloseSelectedContentTabs_onDisappearCleansOperationAndIgnoresLateActions() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        let ownerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000455"))
        let initialState = makeDisappearingSelectedCloseState(
            fixture: fixture,
            operationID: operationID,
            requestID: requestID,
            ownerID: ownerID,
        )
        let previousContent = fixture.state.content
        let store = TestStore(initialState: initialState) { FileManagerWindowRoutingReducer() }
        // store.exhaustivity = .off: cancellation effect보다 lifecycle owner state와 stale action 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.onDisappear)
        XCTAssertTrue(store.state.isClosing)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.tabC)
        XCTAssertEqual(store.state.content, previousContent)
        XCTAssertFalse(store.state.tabContentStates[fixture.tabA]?.collection.isSaving ?? true)
        XCTAssertNil(store.state.tabContentStates[fixture.tabA]?.collection.pendingSaveContext)
        XCTAssertFalse(
            store.state.tabContentStates[fixture.tabA]?.collection.collectionSession.phase.isInflightWriteBack
                ?? true,
        )
        XCTAssertFalse(
            store.state.tabContentStates[fixture.tabA]?.collection.collectionSession.phase.isInflightRefresh
                ?? true,
        )
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.deferredPinnedContentTabs)
        XCTAssertNil(store.state.pendingContentTabTeardown)
        XCTAssertEqual(store.state.undoRedoPhase, .desynchronized)
        XCTAssertEqual(store.state.undoManagerAvailability, .init())

        await store.send(.onAppear) { $0.isClosing = false }
        let stableState = store.state
        let lateActions: [FileManagerWindowAction] = [
            .processNextSelectedContentTabClose(operationID: operationID),
            .selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: fixture.tabA,
                outcome: .removed,
            ),
            .selectedContentTabCloseAlertResponse(
                operationID: operationID,
                tabID: fixture.tabA,
                choice: .discard,
            ),
            .performSelectedContentTabCloseMutation(
                operationID: operationID,
                tabID: fixture.tabA,
                action: .commitClose(fixture.tabA),
            ),
        ]
        for action in lateActions {
            await store.send(action)
            XCTAssertEqual(store.state, stableState)
        }
    }

    /// CTM-001-close_selected_content_tabs: current item은 기존 single-close lifecycle로 진입함
    /// 선택 탭 일괄 닫기가 cursor 진행만 흉내 내지 않고 실제 ContentTab close 요청을 상관된 child mutation으로 전달하는지 검증한다.
    /// - 검증 내용: processNext가 operationID와 current tabID를 유지한 `.requestClose` mutation을 방출한다.
    /// - 사전 조건: A/B/C가 선택되고 C가 active인 frozen coordinator 시작 상태
    /// - 기대 결과: current A 설정 직후 A의 correlated requestClose action이 수신된다.
    func testCloseSelectedContentTabs_currentItemEntersCorrelatedSingleCloseLifecycle() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var initialState = fixture.state
        initialState.contentTabs.selectedTabIDs = [fixture.tabA, fixture.tabB]
        initialState.contentTabs.selectionAnchorID = fixture.tabB
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Date(timeIntervalSince1970: 453))
        }
        // store.exhaustivity = .off: Window 통합 state의 파생 projection 대신 모든 batch lifecycle action과 최종 identity를 검증한다.
        store.exhaustivity = .off

        await store.send(.requestCloseSelectedContentTabs)
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receiveRemovedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: fixture.tabA,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receiveRemovedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: fixture.tabB,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.tabB])
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.tabC)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [])
        XCTAssertNil(store.state.contentTabs.selectionAnchorID)
        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.anchor, .homeDefault)
        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.title, fixture.tabB.rawValue)
        XCTAssertNotNil(store.state.contentTabs.recentlyClosed?.closedAt)
    }

    /// CTM-001-close_selected_content_tabs: pinned item은 persistence 성공 뒤에만 다음 item으로 진행함
    /// 선택된 pinned tab의 optimistic unpin을 완료로 오인하지 않고 tabID가 포함된 저장 성공 terminal을 기다리는지 검증한다.
    /// - 검증 내용: correlated close 이후 current 유지, pinnedRecordSaveSucceeded(tabID:) 뒤 unpinned terminal과 다음 ordinary
    /// close
    /// - 사전 조건: pinned D와 ordinary A가 선택되고 active C는 target 밖인 상태
    /// - 기대 결과: D는 row를 유지한 채 unpin/deselect되고 A만 제거되며 active C와 마지막 ordinary snapshot이 유지된다.
    func testCloseSelectedContentTabs_pinnedWaitsForPersistenceSuccess() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var initialState = fixture.state
        initialState.contentTabs.selectedTabIDs = [fixture.tabD, fixture.tabA]
        initialState.contentTabs.selectionAnchorID = fixture.tabD
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in }
        }
        // store.exhaustivity = .off: persistence와 Window projection의 파생 state보다 명시 terminal 순서와 최종 tab identity를 검증한다.
        store.exhaustivity = .off

        await store.send(.requestCloseSelectedContentTabs)
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receivePinnedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: fixture.tabD,
        )
        XCTAssertEqual(
            store.state.contentTabs.recentlyClosed?.anchor,
            .directory(path: "/batch-close-restored"),
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receiveRemovedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: fixture.tabA,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabD])
        XCTAssertFalse(store.state.contentTabs.tabs[id: fixture.tabD]?.isPinned ?? true)
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.tabC)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [])
        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.anchor, .homeDefault)
    }

    /// CTM-001-close_selected_content_tabs: dirty Cancel은 target을 유지하고 다음 clean item을 계속 처리함
    /// 사용자가 첫 dirty Collection alert를 취소해도 frozen batch의 나머지 item이 deadlock 없이 진행되는지 검증한다.
    /// - 검증 내용: operation/tab이 포함된 alert response, cancelled terminal, 다음 ordinary removed terminal
    /// - 사전 조건: dirty inactive A와 clean B가 선택되고 alert dependency는 Cancel을 반환함
    /// - 기대 결과: A와 A selection은 유지되고 B만 제거된 뒤 coordinator가 종료된다.
    func testCloseSelectedContentTabs_dirtyCancelRetainsTargetAndAdvances() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let dirtyContent = makeDirtySelectedCloseContentState()
        var initialState = fixture.state
        initialState.contentTabs.tabs[id: fixture.tabA]?.page = .collection
        initialState.contentTabs.tabs[id: fixture.tabA]?.anchor = .collectionFile(
            url: URL(fileURLWithPath: "/tmp/batch-dirty.voycoll"),
        )
        initialState.contentTabs.selectedTabIDs = [fixture.tabA, fixture.tabB]
        initialState.contentTabs.selectionAnchorID = fixture.tabA
        initialState.contentTabs.previousActiveTabID = fixture.tabD
        initialState.tabContentStates[fixture.tabA] = dirtyContent
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.collectionAlertClient.showUnsavedNavigationAlert = { .cancel }
        }
        // store.exhaustivity = .off: alert/completion action을 모두 관찰하고 최종 partial-result identity에 집중한다.
        store.exhaustivity = .off

        await store.send(.requestCloseSelectedContentTabs)
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await store.receive { action in
            guard case let .selectedContentTabCloseAlertResponse(receivedOperationID, tabID, choice) = action
            else { return false }
            return receivedOperationID == operationID && tabID == fixture.tabA && choice == .cancel
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == .cancelled
        }
        XCTAssertEqual(
            store.state.contentTabs.recentlyClosed?.anchor,
            .directory(path: "/batch-close-restored"),
        )
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, fixture.tabD)
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await receiveRemovedSelectedCloseLifecycle(
            store,
            operationID: operationID,
            tabID: fixture.tabB,
        )
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.tabB])
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [fixture.tabA])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, fixture.tabA)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.tabC)
    }

    /// CTM-001-close_selected_content_tabs: pinned rollback과 teardown failure는 current item만 실패 처리함
    /// persistence/undo 비동기 실패가 target을 제거하지 않고 selection을 유지한 채 queue를 종료하는지 검증한다.
    /// - 검증 내용: pinnedRecordSaveFailed rollback 및 requestID/ownerID가 일치하는 teardown failure의 correlated failed terminal
    /// - 사전 조건: pinned D current state와 ordinary A tearingDownTab current state
    /// - 기대 결과: 두 target 모두 존재/선택 상태로 남고 pending coordinator와 per-item context만 clear된다.
    func testCloseSelectedContentTabs_asyncFailuresRetainOnlyCurrentTarget() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        await verifyPinnedPersistenceFailureRetainsSelectedTarget(
            fixture: fixture,
            operationID: operationID,
        )
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        let ownerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000455"))
        await verifyTeardownFailureRetainsSelectedTarget(
            fixture: fixture,
            operationID: operationID,
            requestID: requestID,
            ownerID: ownerID,
        )
    }

    /// CTM-001-close_selected_content_tabs: 일반 dirty Save 실패는 terminal 순서와 무관하게 정산됨
    /// write-back phase가 아닌 Save는 feedback과 saveCompleted가 모두 도착하면 추가 terminal 없이 실패 처리되는지 검증한다.
    /// - 검증 내용: saveFeedback 선행 no-advance, saveCompleted 후 failed terminal과 queue 종료
    /// - 사전 조건: A가 batch current이고 일반 Save phase의 PendingContentTabClose가 operationID를 보유함
    /// - 기대 결과: 두 terminal 전까지 current가 유지되고 완료 뒤 A/selection은 유지된 채 pending만 clear된다.
    func testCloseSelectedContentTabs_saveFailureWaitsForFeedbackTerminal() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let initialState = makeDirtyBatchPendingState(
            fixture: fixture,
            operationID: operationID,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerWindowRoutingReducer()
        }
        // store.exhaustivity = .off: batch failure terminal의 순서 독립성과 최종 identity에 집중한다.
        store.exhaustivity = .off

        let feedback = makeSelectedCloseSaveFeedback()
        await store.send(.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .collection(.delegate(.saveFeedback(feedback))),
        ))
        XCTAssertTrue(store.state.pendingContentTabClose?.didReceiveSaveFeedbackFailure ?? false)
        XCTAssertNotNil(store.state.pendingSelectedContentTabClose)

        let error = NSError(domain: "batch-save", code: 453)
        await store.send(.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .collection(.saveCompleted(.failure(error))),
        ))
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == .failed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [fixture.tabA])
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
    }

    /// CTM-001-close_selected_content_tabs: write-back phase Save 실패는 전용 terminal까지 기다림
    /// Save dispatch 직전 phase를 캡처해 feedback과 saveCompleted 뒤에도 writeBackFailed 전에는 batch를 유지하는지 검증한다.
    /// - 검증 내용: phase 기반 requiresWriteBackFailureTerminal 캡처와 세 failure terminal의 공통 finalizer
    /// - 사전 조건: A가 batch current이고 Collection session이 writingBackRefreshedSnapshot phase임
    /// - 기대 결과: writeBackFailed 전에는 current가 유지되고 마지막 terminal 뒤에만 failed 정산과 queue 종료가 발생한다.
    func testCloseSelectedContentTabs_writeBackFailureWaitsForWriteBackTerminal() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var initialState = makeDirtyBatchPendingState(fixture: fixture, operationID: operationID)
        initialState.content.collection.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        let store = TestStore(initialState: initialState) { FileManagerWindowRoutingReducer() }
        // store.exhaustivity = .off: phase capture와 failure terminal 경계만 명시 검증한다.
        store.exhaustivity = .off

        await store.send(.selectedContentTabCloseAlertResponse(
            operationID: operationID,
            tabID: fixture.tabA,
            choice: .save,
        )) {
            $0.pendingContentTabClose?.requiresWriteBackFailureTerminal = true
        }
        await store.receive { action in
            guard case let .performBatchCloseContentAction(receivedID, tabID, contentAction) = action,
                  case .composer(.view(.saveCollection)) = contentAction
            else { return false }
            return receivedID == operationID && tabID == fixture.tabA
        }

        let feedback = makeSelectedCloseSaveFeedback()
        await store.send(.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .collection(.saveCompleted(.failure(SelectedClosePersistenceError()))),
        ))
        await store.send(.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .collection(.delegate(.saveFeedback(feedback))),
        ))
        XCTAssertEqual(store.state.pendingSelectedContentTabClose?.currentTabID, fixture.tabA)
        XCTAssertNotNil(store.state.pendingContentTabClose)

        await store.send(.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .collection(.writeBackFailed),
        ))
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == .failed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
    }

    /// CTM-001-close_selected_content_tabs: save-blocked feedback만으로 current item을 실패 정산함
    /// payload validation이 saveCompleted를 만들지 않는 경우에도 batch가 멈추지 않고 정확히 한 번 진행하는지 검증한다.
    /// - 검증 내용: saveBlocked feedback 단독 failed terminal, queue 종료, duplicate stale feedback no-op
    /// - 사전 조건: A가 batch current이고 write-back terminal expectation이 true인 pending close
    /// - 기대 결과: feedback 직후 A는 유지된 채 pending이 clear되고 같은 늦은 feedback은 상태를 바꾸지 않는다.
    func testCloseSelectedContentTabs_saveBlockedFeedbackCompletesWithoutSaveCompleted() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var initialState = makeDirtyBatchPendingState(fixture: fixture, operationID: operationID)
        initialState.pendingContentTabClose?.requiresWriteBackFailureTerminal = true
        let store = TestStore(initialState: initialState) { FileManagerWindowRoutingReducer() }
        // store.exhaustivity = .off: feedback-only terminal 수와 최종 batch identity를 직접 검증한다.
        store.exhaustivity = .off
        let feedback = CollectionSaveFeedback(
            stage: .saveBlocked,
            category: .emptyContent,
            title: "Nothing to Save",
            message: "Add a query, scope, or condition before saving.",
            isRetryable: false,
        )
        let action = FileManagerWindowAction.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .collection(.delegate(.saveFeedback(feedback))),
        )

        await store.send(action)
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == .failed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabA])

        let completedState = store.state
        await store.send(action)
        XCTAssertEqual(store.state, completedState)
    }

    /// CTM-001-close_selected_content_tabs: dirty Save는 두 write-back terminal 뒤에만 close를 재개함
    /// Save 성공 action 자체가 아니라 composer/navigation write-back이 모두 완료된 뒤 기존 close lifecycle로 복귀하는지 검증한다.
    /// - 검증 내용: 첫 write-back no-advance, 둘째 write-back 후 requestClose→commitClose→removed
    /// - 사전 조건: A가 batch current이고 PendingContentTabClose의 두 completion flag가 false임
    /// - 기대 결과: A는 두 terminal 전까지 유지되고 이후 한 번만 제거되며 coordinator가 종료된다.
    func testCloseSelectedContentTabs_saveSuccessWaitsForBothWriteBackTerminals() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let initialState = makeDirtyBatchPendingState(
            fixture: fixture,
            operationID: operationID,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        // store.exhaustivity = .off: write-back terminal과 batch lifecycle action은 모두 receive하고 child projection diff만
        // 생략한다.
        store.exhaustivity = .off

        await store.send(.performBatchCloseContentAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .composer(.internal(.syncCollectionState(
                context: nil,
                url: nil,
                compatibility: nil,
                isCollectionMode: false,
            ))),
        ))
        XCTAssertTrue(store.state.pendingContentTabClose?.didReceiveWriteBackComposerSync ?? false)
        XCTAssertFalse(store.state.pendingContentTabClose?.didReceiveWriteBackNavigationState ?? true)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: fixture.tabA])

        await store.send(.performBatchCloseNavigationAction(
            operationID: operationID,
            tabID: fixture.tabA,
            action: .internal(.setNavigationState(.home)),
        ))
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(_, tabID, .requestClose(requestedID)) = action
            else { return false }
            return tabID == fixture.tabA && requestedID == fixture.tabA
        }
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(_, tabID, .commitClose(committedID)) = action
            else { return false }
            return tabID == fixture.tabA && committedID == fixture.tabA
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == fixture.tabA && outcome == .removed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.contentTabs.tabs[id: fixture.tabA])
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.pendingSelectedContentTabClose)
    }

    /// CTM-001-close_selected_content_tabs: Discard와 save-panel/write-back failure는 실제 terminal에서 정산됨
    /// dirty close의 나머지 Phase 1 terminal이 current item만 완료하고 selection/recentlyClosed 정책을 지키는지 검증한다.
    /// - 검증 내용: active Discard의 discard action과 ordinary lifecycle, save-panel Cancel, writeBackFailed
    /// - 사전 조건: C active dirty pending과 A current pending 두 terminal fixture
    /// - 기대 결과: Discard는 C를 제거하고 Cancel/failed는 A와 selection을 유지하며 기존 snapshot을 덮어쓰지 않는다.
    func testCloseSelectedContentTabs_discardAndSaveTerminalsUsePhaseOneCompletionPoints() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var discardState = fixture.state
        discardState.contentTabs.selectedTabIDs = [fixture.tabC]
        discardState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabC],
            currentTabID: fixture.tabC,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD],
        )
        discardState.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.tabC,
            batchOperationID: operationID,
        )
        let discardStore = TestStore(initialState: discardState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 453))
        }
        // store.exhaustivity = .off: discard child projection을 제외하고 discard/request/commit/removed를 모두 receive한다.
        discardStore.exhaustivity = .off

        await discardStore.send(.selectedContentTabCloseAlertResponse(
            operationID: operationID,
            tabID: fixture.tabC,
            choice: .discard,
        ))
        await discardStore.receive(\.content.view.discardCollectionChanges)
        await receiveRemovedSelectedCloseLifecycle(
            discardStore,
            operationID: operationID,
            tabID: fixture.tabC,
        )
        await discardStore.receive(\.processNextSelectedContentTabClose, operationID)
        XCTAssertNil(discardStore.state.contentTabs.tabs[id: fixture.tabC])
        XCTAssertEqual(discardStore.state.contentTabs.activeTabID, fixture.tabD)

        let terminalCases = makeSelectedCloseTerminalCases(
            operationID: operationID,
            tabID: fixture.tabA,
        )
        for testCase in terminalCases {
            await verifyRetainedSelectedCloseTerminal(
                testCase,
                fixture: fixture,
                operationID: operationID,
            )
        }
    }

    /// CTM-001-close_selected_content_tabs: fallback priority를 모든 survivor 범주에서 재검증함
    /// active target 성공 뒤 live tabs 변화에 따라 right/left non-target과 unpinned survivor를 순서대로 선택하는지 검증한다.
    /// - 검증 내용: right 우선, right 소멸 시 left, non-target 소멸 시 unpinned target fallback
    /// - 사전 조건: C가 제거된 active current이고 A/B/D survivor 조합이 서로 다른 세 case
    /// - 기대 결과: D, A, B 순으로 active가 결정되며 fallback은 selected set에 자동 삽입되지 않는다.
    func testCloseSelectedContentTabs_fallbackUsesRightLeftThenUnpinnedSurvivor() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let cases = makeSelectedCloseFallbackCases(fixture: fixture)

        for testCase in cases {
            let survivorIDs = testCase.survivorIDs
            let preferredIDs = testCase.preferredIDs
            let expectedActiveID = testCase.expectedActiveID
            var state = fixture.state
            state.contentTabs.tabs.removeAll { !survivorIDs.contains($0.id) }
            state.contentTabs.activeTabID = nil
            state.contentTabs.selectedTabIDs = []
            state.contentTabs.selectionAnchorID = fixture.tabC
            let orderedTargets = expectedActiveID == fixture.tabB
                ? [fixture.tabB, fixture.tabC]
                : [fixture.tabC]
            state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
                operationID: operationID,
                orderedTargetIDs: orderedTargets,
                cursor: orderedTargets.count - 1,
                currentTabID: fixture.tabC,
                originalActiveTabID: fixture.tabC,
                preferredFallbackIDs: preferredIDs,
            )
            let store = TestStore(initialState: state) {
                FileManagerWindowRoutingReducer()
            }
            // store.exhaustivity = .off: fallback identity, selection, anchor와 종료 action을 직접 검증한다.
            store.exhaustivity = .off

            await store.send(.selectedContentTabCloseItemCompleted(
                operationID: operationID,
                tabID: fixture.tabC,
                outcome: .removed,
            ))
            await store.receive(\.processNextSelectedContentTabClose, operationID)
            XCTAssertEqual(store.state.contentTabs.activeTabID, expectedActiveID)
            XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [])
            XCTAssertNil(store.state.contentTabs.selectionAnchorID)
        }
    }

    /// CTM-001-close_selected_content_tabs: active target fallback은 failed survivor를 unpinned survivor보다 우선함
    /// original non-target survivor가 사라진 partial-result에서 retained selection이 fallback priority를 결정하는지 검증한다.
    /// - 검증 내용: live preferred IDs를 non-target, failed/cancelled selected, unpinned 순으로 재검증함
    /// - 사전 조건: A는 failed selected survivor, B는 successfully-unpinned unselected survivor, active C는 제거된 current target
    /// - 기대 결과: active fallback은 A이고 새 active가 selected set에 자동 삽입되지 않으며 기존 A selection만 유지된다.
    func testCloseSelectedContentTabs_fallbackPrefersFailedSurvivorOverUnpinnedSurvivor() async throws {
        let fixture = makeSelectedContentTabCloseFixture()
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        var initialState = fixture.state
        initialState.contentTabs.tabs.remove(id: fixture.tabD)
        initialState.contentTabs.tabs.remove(id: fixture.tabC)
        initialState.contentTabs.activeTabID = nil
        initialState.contentTabs.selectedTabIDs = [fixture.tabA, fixture.tabC]
        initialState.contentTabs.selectionAnchorID = fixture.tabC
        initialState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [fixture.tabA, fixture.tabB, fixture.tabC],
            cursor: 2,
            currentTabID: fixture.tabC,
            originalActiveTabID: fixture.tabC,
            preferredFallbackIDs: [fixture.tabD, fixture.tabA, fixture.tabB],
        )
        let store = TestStore(initialState: initialState) {
            FileManagerWindowRoutingReducer()
        }
        // store.exhaustivity = .off: fallback owner의 identity/selection 정산과 종료 action만 검증한다.
        store.exhaustivity = .off

        await store.send(.selectedContentTabCloseItemCompleted(
            operationID: operationID,
            tabID: fixture.tabC,
            outcome: .removed,
        ))
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.tabA)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [fixture.tabA])
        XCTAssertNil(store.state.contentTabs.selectionAnchorID)
    }

    // MARK: - CTM-001-close_content_tab

    /// CTM-001-close_content_tab: 일반 close는 restore snapshot을 남기고 마지막 탭 close는 Window handoff 상태로 비워둠
    /// 기능스펙의 surface close 정책과 window lifecycle handoff 경계를 함께 검증한다.
    /// - 검증 내용: unpinned close snapshot 저장, active fallback, 마지막 active close의 빈 tab list 전이
    /// - 사전 조건: Home+Directory 두 탭 상태와 Directory 단일 active 상태
    /// - 기대 결과: 닫힌 탭은 snapshot으로 보존되고 마지막 탭 close는 replacement Home을 만들지 않음
    func testCloseContentTab_savesRestoreSnapshotAndLeavesLastCloseForWindowHandoff() throws {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: directoryAnchor,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(directoryID))

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].id, homeID)
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertEqual(state.recentlyClosed?.page, .directory)
        XCTAssertEqual(state.recentlyClosed?.anchor, directoryAnchor)
        XCTAssertFalse(try XCTUnwrap(state.recentlyClosed?.wasPinned))
        XCTAssertNotNil(state.recentlyClosed?.closedAt)

        let lastID = ContentTabID()
        var lastTabState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: lastID,
                    page: .directory,
                    anchor: directoryAnchor,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: lastID,
            recentlyClosed: nil,
        )

        lastTabState.selectedTabIDs = [lastID]
        lastTabState.selectionAnchorID = lastID

        _ = reducer.reduce(into: &lastTabState, action: .commitClose(lastID))

        // 마지막 tab은 제거되지 않고 Home tab으로 reset됨
        XCTAssertEqual(lastTabState.tabs.count, 1)
        XCTAssertEqual(lastTabState.tabs[0].page, .home)
        XCTAssertEqual(lastTabState.tabs[0].anchor, .homeDefault)
        XCTAssertEqual(lastTabState.tabs[0].title, "Home")
        XCTAssertEqual(lastTabState.tabs[0].iconName, "house")
        XCTAssertEqual(lastTabState.activeTabID, lastID)
        XCTAssertEqual(lastTabState.selectedTabIDs, [lastID])
        XCTAssertEqual(lastTabState.selectionAnchorID, lastID)
        XCTAssertNil(lastTabState.recentlyClosed)
    }

    /// CTM-001-close_content_tab: 실제 identity 삭제는 닫힌 selected ID와 anchor만 정리함
    /// 일반 multi-tab close가 surviving selection과 unrelated metadata를 유지하면서 stale identity를 제거하는지 검증한다.
    /// - 검증 내용: selected+anchor close와 unselected anchor-only close의 reconciliation
    /// - 사전 조건: A/B/C 탭 중 닫힐 A 또는 C가 anchor이고 surviving B가 selected인 두 상태
    /// - 기대 결과: 닫힌 ID만 selection에서 제거되고 닫힌 anchor는 nil, surviving B와 metadata는 유지됨
    func testCloseContentTab_reconcilesOnlyRemovedIdentitySelectionAndAnchor() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let tabs = closeReconciliationTabs(tabA: tabA, tabB: tabB, tabC: tabC)
        let reducer = ContentTabFeature()

        var selectedAnchorState = ContentTabState(
            tabs: tabs,
            activeTabID: tabB,
            previousActiveTabID: tabC,
            pinnedRecordPersistenceError: "selected-anchor-sentinel",
        )
        selectedAnchorState.selectedTabIDs = [tabA, tabB]
        selectedAnchorState.selectionAnchorID = tabA
        _ = reducer.reduce(into: &selectedAnchorState, action: .commitClose(tabA))

        XCTAssertEqual(selectedAnchorState.tabs.map(\.id), [tabB, tabC])
        XCTAssertEqual(selectedAnchorState.selectedTabIDs, [tabB])
        XCTAssertNil(selectedAnchorState.selectionAnchorID)
        XCTAssertEqual(selectedAnchorState.activeTabID, tabB)
        XCTAssertEqual(selectedAnchorState.pinnedRecordPersistenceError, "selected-anchor-sentinel")

        var anchorOnlyState = ContentTabState(
            tabs: tabs,
            activeTabID: tabB,
            previousActiveTabID: tabA,
            pinnedRecordPersistenceError: "anchor-only-sentinel",
        )
        anchorOnlyState.selectedTabIDs = [tabB]
        anchorOnlyState.selectionAnchorID = tabC
        _ = reducer.reduce(into: &anchorOnlyState, action: .commitClose(tabC))

        XCTAssertEqual(anchorOnlyState.tabs.map(\.id), [tabA, tabB])
        XCTAssertEqual(anchorOnlyState.selectedTabIDs, [tabB])
        XCTAssertNil(anchorOnlyState.selectionAnchorID)
        XCTAssertEqual(anchorOnlyState.activeTabID, tabB)
        XCTAssertEqual(anchorOnlyState.pinnedRecordPersistenceError, "anchor-only-sentinel")
    }

    /// CTM-001-close_content_tab: pinned tab close는 restore snapshot을 생성하지 않음
    /// pinned tab close는 unpin transition이며 recentlyClosed 후보를 남기지 않음을 검증한다.
    /// - 검증 내용: close 후 recentlyClosed == nil, tab 유지, isPinned false 전환
    /// - 사전 조건: active pinned Home tab 하나
    /// - 기대 결과: pinned close가 unpin만 수행하고 snapshot 미생성
    func testCloseContentTab_pinnedCloseDoesNotCreateRestoreCandidate() {
        let pinnedID = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: true,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: pinnedID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .unpin(pinnedID))

        XCTAssertNil(state.recentlyClosed)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertFalse(state.tabs.first?.isPinned ?? true)
    }

    func testCloseLastAiChatTabPreservesRecentlyClosedSnapshot() async {
        let sessionID = "chat-1"
        let aiChatTabID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: aiChatTabID,
                        page: .aiChat,
                        anchor: .aiChat(sessionID: sessionID),
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: aiChatTabID,
                recentlyClosed: nil,
            ),
        ) {
            ContentTabFeature()
        }
        store.exhaustivity = .off

        await store.send(.commitClose(aiChatTabID))

        XCTAssertEqual(store.state.recentlyClosed?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertNotNil(store.state.activeTabID)
        XCTAssertEqual(store.state.tabs.count, 1)
        guard let tab = store.state.tabs.first else {
            return XCTFail("Expected at least one tab after close")
        }
        XCTAssertEqual(tab.page, .home)
        XCTAssertEqual(tab.anchor, .homeDefault)
    }

    // MARK: - CTM-001-restore_last_closed_tab

    /// CTM-001-restore_last_closed_tab: 단일 recently closed snapshot을 fresh identity로 복원함
    /// 기능스펙의 Restore Last Closed가 lightweight snapshot 후보 하나만 소비하는지 검증한다.
    /// - 검증 내용: restore 후 새 tab ID 생성, page/anchor 복원, recentlyClosed 초기화, 재호출 no-op
    /// - 사전 조건: Home tab 하나와 Directory recentlyClosed snapshot 하나
    /// - 기대 결과: Directory tab이 새 identity로 active 복원되고 후보는 비워짐
    func testRestoreLastClosedTab_consumesSingleSnapshotWithFreshIdentity() throws {
        let homeID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        let closedSnapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: directoryAnchor,
            wasPinned: false,
            closedAt: Date(),
        )
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: closedSnapshot,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .restore)

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.recentlyClosed)
        XCTAssertEqual(state.activeTabID, state.tabs.last?.id)
        XCTAssertNotEqual(state.tabs.last?.id, homeID)
        XCTAssertEqual(state.tabs.last?.page, .directory)
        XCTAssertEqual(state.tabs.last?.anchor, directoryAnchor)
        XCTAssertFalse(try XCTUnwrap(state.tabs.last?.isPinned))

        _ = reducer.reduce(into: &state, action: .restore)
        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.recentlyClosed)
    }

    /// CTM-001-restore_last_closed_tab: open과 restore의 새 identity는 기존 selection/anchor를 상속하지 않음
    /// 새 tab 생성 lifecycle이 active identity만 전환하고 runtime selection intent를 보존하는지 검증한다.
    /// - 검증 내용: open과 restore 각각의 fresh ID가 unselected이며 기존 selected set/anchor가 동일함
    /// - 사전 조건: selected/anchored Home tab과 Directory recentlyClosed snapshot
    /// - 기대 결과: 두 새 tab은 active로 생성되지만 Home selection/anchor만 유지되고 metadata sentinel도 보존됨
    func testOpenAndRestore_preserveExplicitSelectionAndAnchor() throws {
        let homeID = ContentTabID(rawValue: "home")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: ClosedContentTabSnapshot(
                page: .directory,
                anchor: .directory(path: "/restored"),
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 451),
                title: "Restored",
                iconName: "folder",
            ),
            pinnedRecordPersistenceError: "sentinel",
        )
        state.selectedTabIDs = [homeID]
        state.selectionAnchorID = homeID
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .open(.homeDefault))
        let openedID = try XCTUnwrap(state.activeTabID)
        XCTAssertNotEqual(openedID, homeID)
        XCTAssertFalse(state.selectedTabIDs.contains(openedID))
        XCTAssertEqual(state.selectedTabIDs, [homeID])
        XCTAssertEqual(state.selectionAnchorID, homeID)

        _ = reducer.reduce(into: &state, action: .restore)
        let restoredID = try XCTUnwrap(state.activeTabID)
        XCTAssertNotEqual(restoredID, openedID)
        XCTAssertFalse(state.selectedTabIDs.contains(restoredID))
        XCTAssertEqual(state.selectedTabIDs, [homeID])
        XCTAssertEqual(state.selectionAnchorID, homeID)
        XCTAssertEqual(state.pinnedRecordPersistenceError, "sentinel")
    }

    /// CTM-001-restore_last_closed_tab: candidate가 없으면 restore는 no-op
    /// recentlyClosed가 nil일 때 restore가 tabs와 activeTabID를 변경하지 않음을 검증한다.
    /// - 검증 내용: restore 후 tabs.count, activeTabID, recentlyClosed 불변
    /// - 사전 조건: recentlyClosed == nil, Home tab 하나
    /// - 기대 결과: restore 호출 후 tabs와 activeTabID가 변경되지 않고 recentlyClosed == nil 유지
    func testRestoreLastClosedTab_noCandidateIsNoOp() {
        let homeID = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .restore)

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertNil(state.recentlyClosed)
    }

    /// CTM-001-restore_last_closed_tab: snapshot의 title/iconName metadata가 restore된 tab에 우선 사용됨
    /// close 시 저장된 title과 iconName이 restore에서 title(for:)/iconName(for:)보다 우선 적용됨을 검증한다.
    /// - 검증 내용: restore된 tab의 title == snapshot.title, iconName == snapshot.iconName
    /// - 사전 조건: recentlyClosed에 title과 iconName이 설정된 snapshot
    /// - 기대 결과: restore된 tab이 snapshot metadata를 그대로 사용함
    func testRestoreLastClosedTab_preservesSnapshotMetadata() throws {
        let homeID = ContentTabID()
        let snapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/custom"),
            wasPinned: false,
            closedAt: Date(),
            title: "Custom Title",
            iconName: "custom.icon",
        )
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: snapshot,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .restore)

        let restoredTab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(restoredTab.title, "Custom Title")
        XCTAssertEqual(restoredTab.iconName, "custom.icon")
    }

    /// CTM-001-restore_last_closed_tab: close A → close B → restore는 B만 복원함
    /// 연속 close 시 마지막 snapshot만 보존되고 restore가 가장 최근 snapshot을 소비함을 검증한다.
    /// - 검증 내용: close(A) → close(B) → restore 후 restored tab의 anchor == B의 anchor
    /// - 사전 조건: Home + A + B 세 tab, A와 B 순서로 close
    /// - 기대 결과: B의 snapshot만 restore되고 A는 복원되지 않음
    func testRestoreLastClosedTab_overwritesOnMultipleClose() throws {
        let homeID = ContentTabID()
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let anchorB = ContentTabPageAnchor.directory(path: "/b")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabA,
                    page: .directory,
                    anchor: .directory(path: "/a"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(id: tabB, page: .directory, anchor: anchorB, isPinned: false, title: nil, iconName: nil),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(tabA))
        _ = reducer.reduce(into: &state, action: .commitClose(tabB))
        _ = reducer.reduce(into: &state, action: .restore)

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.recentlyClosed)
        let restoredTab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(restoredTab.anchor, anchorB)
        XCTAssertEqual(restoredTab.page, .directory)
    }

    // MARK: - CTM-001-pin_content_tab_s

    /// CTM-001-pin_content_tab_s: pinned tab close는 제거가 아니라 unpin transition임
    /// 기능스펙과 lifecycle contract의 `pinned_tab_close_means_unpin` 정책을 검증한다.
    /// - 검증 내용: close(pinnedID) 후 tab 유지, isPinned=false, recentlyClosed 미생성
    /// - 사전 조건: active pinned Home tab 하나
    /// - 기대 결과: 탭은 남고 pinned 상태만 해제됨
    func testPinContentTabs_pinnedCloseOnlyUnpins() async {
        let pinnedID = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: true,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: pinnedID,
            recentlyClosed: nil,
        )
        state.selectedTabIDs = [pinnedID]
        state.selectionAnchorID = pinnedID
        let store = TestStore(initialState: state) {
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.close(pinnedID)) {
            $0.tabs[id: pinnedID]?.isPinned = false
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.finish()

        XCTAssertEqual(store.state.selectedTabIDs, [pinnedID])
        XCTAssertEqual(store.state.selectionAnchorID, pinnedID)
    }

    // MARK: - CTM-001-restore_last_closed_tab_routing

    /// CTM-001-restore_last_closed_tab_routing: 유효한 Directory anchor restore는 recentlyClosed snapshot을 소비하고 tab을 복원함
    /// FileManagerWindowCommandRoutingReducer.handleRequestedCommand(.restoreLastClosedContentTab) 경로를 통해
    /// anchor 유효성 검증 → ContentTabFeature.restore() 전달까지의 command-level routing을 검증한다.
    /// - 검증 내용: tabs.count == 2 (기존 Home + 복원된 Directory), recentlyClosed == nil, 복원된 tab의 anchor와 page가 snapshot과 일치
    /// - 사전 조건: Home tab 하나, 최근 닫힌 Directory tab snapshot, fileManagerClient.fileExistsWithIsDirectory → (true,
    /// isDirectory=true)
    /// - 기대 결과: restore 후 새 Directory tab이 active로 추가되고 recentlyClosed가 비워짐
    func testRestoreLastClosedTabCommand_validDirectoryRestoresAndConsumesSnapshot() async throws {
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/Users/test/Documents")
        var state = FileManagerFeature.State()
        let originalActiveID = try XCTUnwrap(state.contentTabs.activeTabID)
        let selectedSiblingID = ContentTabID(rawValue: "restore-selected-sibling")
        state.contentTabs.tabs.append(ContentTabItem(
            id: selectedSiblingID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Selected Sibling",
            iconName: "house",
        ))
        state.contentTabs.selectedTabIDs = [originalActiveID, selectedSiblingID]
        state.contentTabs.selectionAnchorID = selectedSiblingID
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: directoryAnchor,
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, isDirectory in
                isDirectory?.pointee = true
                return true
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action과 restore 후
        // handoff/navigation child effect를 방출하므로 최종 상태 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count

        await store.send(.request(.restoreLastClosedContentTab))
        await store.receive(\.contentTabs.restore)
        await store.receive(\.contentTabs.collapseSelectionToActive)
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount + 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let restoredTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(restoredTab.anchor, directoryAnchor)
        XCTAssertEqual(restoredTab.page, .directory)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [restoredTab.id])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, restoredTab.id)
        XCTAssertEqual(store.state.menuCommandProjection.selectedContentTabCount, 1)
        XCTAssertFalse(store.state.menuCommandProjection.canDuplicateSelectedContentTabs)
    }

    /// CTM-001-restore_last_closed_tab_routing: 삭제된 Directory anchor restore는 snapshot을 소비하고 feedback alert을 표시함
    /// handleRestoreLastClosedContentTab에서 fileManagerClient.fileExistsWithIsDirectory가 false를 반환하면
    /// recentlyClosed를 초기화하고 collectionAlertClient로 사용자 피드백을 전송하는 경로를 검증한다.
    /// - 검증 내용: tabs.count 불변 (1), recentlyClosed == nil,
    ///   collectionAlertClient에 "Cannot Restore Tab" / "The recently closed tab is no longer available." alert 전송
    /// - 사전 조건: Home tab 하나, 삭제된 경로의 Directory snapshot, fileManagerClient.fileExistsWithIsDirectory → false
    /// - 기대 결과: recentlyClosed가 소비되고 alert이 표시되며 tab 목록은 변경되지 않음
    func testRestoreLastClosedTabCommand_invalidDirectoryConsumesSnapshotAndShowsFeedback() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/Users/test/Deleted"),
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in false }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear 및 restore failure effect(.run)가
        // 여러 action을 방출하므로 snapshot 소비와 alert 전송 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let alerts = collectionAlertRecorder.value
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cannot Restore Tab")
        XCTAssertEqual(alerts[0].message, "The recently closed tab is no longer available.")
    }

    /// CTM-001-restore_last_closed_tab_routing: 삭제된 CollectionFile anchor restore는 snapshot을 소비하고 feedback alert을 표시함
    /// Directory와 동일한 실패 경로를 collectionFile anchor(.collectionFile)에서 검증한다.
    /// - 검증 내용: tabs.count 불변, recentlyClosed == nil,
    ///   collectionAlertClient에 "Cannot Restore Tab" / "The recently closed tab is no longer available." alert 전송
    /// - 사전 조건: Home tab 하나, 존재하지 않는 collectionFile 경로의 snapshot, fileManagerClient.fileExistsWithIsDirectory → false
    /// - 기대 결과: recentlyClosed가 소비되고 "Cannot Restore Tab" alert이 표시됨
    func testRestoreLastClosedTabCommand_missingCollectionConsumesSnapshotAndShowsFeedback() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        let collectionURL = URL(fileURLWithPath: "/Users/test/Deleted.voyagercollection")
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .collection,
            anchor: .collectionFile(url: collectionURL),
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in false }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear 및 restore failure effect 방출로 인해
        // collection anchor missing 경로 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let alerts = collectionAlertRecorder.value
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cannot Restore Tab")
        XCTAssertEqual(alerts[0].message, "The recently closed tab is no longer available.")
    }

    /// CTM-001-restore_last_closed_tab_routing: Virtual Collection restore candidate는 소비하지 않고 복원됨
    /// Recents/Tags/Computer 계열 virtualCollection anchor는 기존 content 초기화 경로에서 `.tags(id)`로 복원 가능하므로 실패 feedback 대상이
    /// 아니다.
    /// - 검증 내용: restore command 실행 후 새 tab 생성, active 전환, recentlyClosed 소비
    /// - 사전 조건: Home tab 하나, virtualCollection("Important") snapshot 1개
    /// - 기대 결과: 새 tab이 `.virtualCollection(id: "Important")` anchor로 추가되고 alert 없이 복원됨
    func testRestoreLastClosedTabCommand_virtualCollectionRestoresAndConsumesSnapshot() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        let anchor = ContentTabPageAnchor.virtualCollection(id: "Important")
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .collection,
            anchor: anchor,
            wasPinned: false,
            closedAt: Date(),
            title: "Important",
            iconName: "tag",
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear와 restore 후 content handoff child action은
        // 기존 lifecycle 테스트가 담당하므로 command-level candidate 소비/복원만 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.receive(\.contentTabs)
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(store.state.contentTabs.activeTabID, store.state.contentTabs.tabs.last?.id)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.page, .collection)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.anchor, anchor)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.title, "Important")
        XCTAssertEqual(store.state.contentTabs.tabs.last?.iconName, "tag")
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        XCTAssertTrue(collectionAlertRecorder.value.isEmpty)
    }

    /// CTM-001-restore_last_closed_tab_routing: AI Chat anchor restore는 snapshot을 소비하고 feedback alert을 표시함
    /// AI Chat anchor(.aiChat)는 restoreFailureReason에서 .unsupportedAIChat으로 분류되어
    /// recentlyClosed가 소비되고 사용자에게 "AI Chat tabs cannot be restored yet." 피드백이 전달됨을 검증한다.
    /// - 검증 내용: tabs.count 불변, recentlyClosed == nil,
    ///   collectionAlertClient에 "Cannot Restore Tab" / "AI Chat tabs cannot be restored yet." alert 전송
    /// - 사전 조건: Home tab 하나, AI Chat session snapshot (sessionID: "chat-1")
    /// - 기대 결과: snapshot이 소비되고 비활성 anchor에 대한 alert이 표시됨
    func testRestoreLastClosedTabCommand_aiChatConsumesSnapshotAndShowsFeedback() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .aiChat,
            anchor: .aiChat(sessionID: "chat-1"),
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear 및 restore failure effect 방출로 인해
        // AI Chat anchor unsupported 경로 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let alerts = collectionAlertRecorder.value
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cannot Restore Tab")
        XCTAssertEqual(alerts[0].message, "AI Chat tabs cannot be restored yet.")
    }

    // MARK: - CTM-001-close_restore_lifecycle

    /// CTM-001-close_restore_lifecycle: active close가 previousActiveTabID를 valid fallback으로 사용함
    /// close 시 previousActiveTabID가 closing tab이 아니고 tabs에 존재하면 해당 id가 active로 설정되는 정책을 검증한다.
    /// - 검증 내용: previousActiveTabID가 closing tab이 아니고 tabs에 존재하면 해당 id가 activeTabID로 설정됨
    /// - 사전 조건: [A(active), B, C] 상태, previousActiveTabID = C
    /// - 기대 결과: close(A) 후 activeTabID == C (C가 previous로서 우선)
    func testCloseContentTab_activeCloseWithPreviousActiveFallback() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .directory,
                    anchor: .directory(path: "/c"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabA,
            previousActiveTabID: tabC,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(tabA))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, tabC)
    }

    /// CTM-001-close_restore_lifecycle: active close의 previous가 closing tab이면 nearest right이 fallback됨
    /// close 시 previousActiveTabID가 nil 또는 closing id일 때 nearest right tab이 active로 설정되는 정책을 검증한다.
    /// - 검증 내용: previousActiveTabID == closing id일 때 nearest right tab이 activeTabID로 설정됨
    /// - 사전 조건: [A(active), B, C] 상태, previousActiveTabID = A
    /// - 기대 결과: close(A) 후 activeTabID == B (nearest right)
    func testCloseContentTab_activeCloseNearestRight() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .directory,
                    anchor: .directory(path: "/c"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabA,
            previousActiveTabID: tabA,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(tabA))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, tabB)
    }

    /// CTM-001-close_restore_lifecycle: active close의 previous가 closing tab이고 right이 out of bounds이면 left가 fallback됨
    /// close 시 previousActiveTabID가 nullish이고 right neighbor가 없으면 left neighbor가 active로 설정되는 정책을 검증한다.
    /// - 검증 내용: previousActiveTabID == closing id이고 right이 없으면 left neighbor tab이 activeTabID로 설정됨
    /// - 사전 조건: [A, B, C(active)] 상태, previousActiveTabID = C
    /// - 기대 결과: close(C) 후 activeTabID == B (left neighbor)
    func testCloseContentTab_activeCloseNearestLeft() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .directory,
                    anchor: .directory(path: "/c"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabC,
            previousActiveTabID: tabC,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(tabC))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, tabB)
    }

    /// CTM-001-close_restore_lifecycle: inactive close는 activeTabID를 변경하지 않고 previousActiveTabID를 nil로 초기화함
    /// inactive tab close 시 active tab이 보존되고 previousActiveTabID가 초기화되는 정책을 검증한다.
    /// - 검증 내용: inactive tab close 후 activeTabID가 변경되지 않고 previousActiveTabID == nil
    /// - 사전 조건: [A(active), B] 상태
    /// - 기대 결과: close(B) 후 activeTabID == A (불변), previousActiveTabID == nil
    func testCloseContentTab_inactiveClosePreservesActive() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabA,
            previousActiveTabID: tabA,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(tabB))

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, tabA)
        XCTAssertNil(state.previousActiveTabID)
    }

    /// CTM-001-close_restore_lifecycle: 연속 close는 recentlyClosed를 마지막 close snapshot으로 overwrite함
    /// close 후보가 overwrite되는 single candidate 정책을 검증한다.
    /// - 검증 내용: close(B) 후 close(C)를 연속 수행하면 recentlyClosed가 C의 snapshot을 가리킴
    /// - 사전 조건: [A(active), B, C] 상태
    /// - 기대 결과: close(B) → close(C) 후 recentlyClosed의 anchor와 page가 C에 해당함
    func testCloseContentTab_singleCandidateOverwrite() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        let anchorC = ContentTabPageAnchor.directory(path: "/c")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(id: tabC, page: .directory, anchor: anchorC, isPinned: false, title: nil, iconName: nil),
            ],
            activeTabID: tabA,
            previousActiveTabID: nil,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .commitClose(tabB))
        _ = reducer.reduce(into: &state, action: .commitClose(tabC))

        XCTAssertEqual(state.recentlyClosed?.anchor, anchorC)
        XCTAssertEqual(state.recentlyClosed?.page, .directory)
    }

    // MARK: - CTM-001-reorder_content_tab

    /// CTM-001-reorder_content_tab: 첫 unpinned tab을 마지막 target 뒤로 이동함
    /// semantic ID와 after placement로 forward reorder할 때 tab 순서 외 상태와 metadata가 보존되는지 검증한다.
    /// - 검증 내용: `[A, B, C]`에서 `A after C`가 `[B, C, A]`가 되고 전체 state는 기대 tabs 외 동일함
    /// - 사전 조건: 서로 다른 page/anchor/title/icon metadata와 active/previous/recentlyClosed를 가진 unpinned tab 3개
    /// - 기대 결과: A가 마지막 경계로 이동하고 모든 tab value 및 non-tab state가 원본과 동일함
    func testReorderContentTab_movesForwardAfterLastTargetAndPreservesMetadata() {
        let tabA = ContentTabItem(
            id: ContentTabID(rawValue: "A"),
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home A",
            iconName: "house.a",
        )
        let tabB = ContentTabItem(
            id: ContentTabID(rawValue: "B"),
            page: .directory,
            anchor: .directory(path: "/b"),
            isPinned: false,
            title: "Directory B",
            iconName: "folder.b",
        )
        let tabC = ContentTabItem(
            id: ContentTabID(rawValue: "C"),
            page: .collection,
            anchor: .virtualCollection(id: "C"),
            isPinned: false,
            title: "Collection C",
            iconName: "rectangle.stack.c",
        )
        let recentlyClosed = ClosedContentTabSnapshot(
            page: .aiChat,
            anchor: .aiChat(sessionID: "closed-session"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 1_234_567_890),
            title: "Closed Chat",
            iconName: "sparkles",
        )
        let original = ContentTabState(
            tabs: [tabA, tabB, tabC],
            activeTabID: tabB.id,
            previousActiveTabID: tabA.id,
            recentlyClosed: recentlyClosed,
            pinnedRecordPersistenceError: "existing_error",
        )
        var state = original
        var expected = original
        expected.tabs = [tabB, tabC, tabA]

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .reorder(sourceID: tabA.id, targetID: tabC.id, placement: .after),
        )

        XCTAssertEqual(state, expected)
    }

    /// CTM-001-reorder_content_tab: 마지막 unpinned tab을 첫 target 앞으로 이동함
    /// semantic ID와 before placement로 backward reorder할 때 첫 삽입 경계와 whole-state 보존을 검증한다.
    /// - 검증 내용: `[A, B, C]`에서 `C before A`가 `[C, A, B]`가 되고 전체 state는 기대 tabs 외 동일함
    /// - 사전 조건: active/previous identity를 가진 unpinned tab 3개
    /// - 기대 결과: C가 첫 경계로 이동하고 active/previous identity 및 tab metadata가 원본과 동일함
    func testReorderContentTab_movesBackwardBeforeFirstTarget() {
        let tabA = ContentTabItem(
            id: ContentTabID(rawValue: "A"),
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "A",
            iconName: "a",
        )
        let tabB = ContentTabItem(
            id: ContentTabID(rawValue: "B"),
            page: .directory,
            anchor: .directory(path: "/b"),
            isPinned: false,
            title: "B",
            iconName: "b",
        )
        let tabC = ContentTabItem(
            id: ContentTabID(rawValue: "C"),
            page: .directory,
            anchor: .directory(path: "/c"),
            isPinned: false,
            title: "C",
            iconName: "c",
        )
        let original = ContentTabState(
            tabs: [tabA, tabB, tabC],
            activeTabID: tabC.id,
            previousActiveTabID: tabB.id,
        )
        var state = original
        var expected = original
        expected.tabs = [tabC, tabA, tabB]

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .reorder(sourceID: tabC.id, targetID: tabA.id, placement: .before),
        )

        XCTAssertEqual(state, expected)
    }

    /// CTM-001-reorder_content_tab: 인접 tab의 동일 결과 placement는 완전 no-op임
    /// source 제거 후 계산된 ID 순서가 원본과 같으면 원본 tabs와 전체 state를 유지하는지 검증한다.
    /// - 검증 내용: `[A, B, C]`에서 `A before B`와 `B after A`가 모두 원본 ID 순서를 유지함
    /// - 사전 조건: 인접한 unpinned A와 B를 포함한 tab 3개
    /// - 기대 결과: 각 action 후 state가 action 전 원본과 정확히 동일함
    func testReorderContentTab_adjacentSameResultPlacementsAreNoOps() {
        let tabA = ContentTabItem(
            id: ContentTabID(rawValue: "A"),
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "A",
            iconName: "a",
        )
        let tabB = ContentTabItem(
            id: ContentTabID(rawValue: "B"),
            page: .directory,
            anchor: .directory(path: "/b"),
            isPinned: false,
            title: "B",
            iconName: "b",
        )
        let tabC = ContentTabItem(
            id: ContentTabID(rawValue: "C"),
            page: .directory,
            anchor: .directory(path: "/c"),
            isPinned: false,
            title: "C",
            iconName: "c",
        )
        let original = ContentTabState(tabs: [tabA, tabB, tabC], activeTabID: tabA.id)
        let reducer = ContentTabFeature()

        var beforeState = original
        _ = reducer.reduce(
            into: &beforeState,
            action: .reorder(sourceID: tabA.id, targetID: tabB.id, placement: .before),
        )
        XCTAssertEqual(beforeState, original)

        var afterState = original
        _ = reducer.reduce(
            into: &afterState,
            action: .reorder(sourceID: tabB.id, targetID: tabA.id, placement: .after),
        )
        XCTAssertEqual(afterState, original)
    }

    /// CTM-001-reorder_content_tab: missing, same-ID, pinned source/target 입력은 완전 no-op임
    /// 유효하지 않거나 pinned divider를 넘는 semantic reorder가 어떤 state field도 변경하지 않는지 검증한다.
    /// - 검증 내용: missing source/target, same ID, pinned source, pinned target action 각각의 whole-state equality
    /// - 사전 조건: raw `[U1, P1, U2]`와 P1 persistence metadata, pending/error state
    /// - 기대 결과: 모든 거부 action에서 state가 원본과 정확히 동일하고 tab identity 중복/누락이 없음
    func testReorderContentTab_invalidAndPinnedInputsAreCompleteNoOps() {
        let unpinned1 = makeReorderDirectoryTab("U1", isPinned: false)
        let pinned1 = makeReorderDirectoryTab("P1", isPinned: true)
        let unpinned2 = makeReorderDirectoryTab("U2", isPinned: false)
        let pinnedRecord = makePinnedRecord(pinned1, pinnedAt: 123)
        let original = ContentTabState(
            tabs: [unpinned1, pinned1, unpinned2],
            activeTabID: unpinned2.id,
            previousActiveTabID: unpinned1.id,
            pinnedRecords: [pinned1.id: pinnedRecord],
            pendingPinnedRecordIDs: [pinned1.id],
            pinnedRecordPersistenceError: "existing_error",
        )
        let missingID = ContentTabID(rawValue: "missing")
        let actions: [ContentTabAction] = [
            .reorder(sourceID: missingID, targetID: unpinned1.id, placement: .before),
            .reorder(sourceID: unpinned1.id, targetID: missingID, placement: .after),
            .reorder(sourceID: unpinned1.id, targetID: unpinned1.id, placement: .before),
            .reorder(sourceID: pinned1.id, targetID: unpinned1.id, placement: .before),
            .reorder(sourceID: unpinned1.id, targetID: pinned1.id, placement: .after),
        ]
        let reducer = ContentTabFeature()

        for action in actions {
            var state = original
            _ = reducer.reduce(into: &state, action: action)
            XCTAssertEqual(state, original)
            XCTAssertEqual(state.tabs.map(\.id), [unpinned1.id, pinned1.id, unpinned2.id])
        }
    }

    /// CTM-001-reorder_content_tab: raw interleaving에서 unpinned 표시 순서만 semantic하게 변경함
    /// pinned-first 정규화 없이 U3를 U1 앞으로 이동하면서 pinned raw slot과 persistence state를 보존하는지 검증한다.
    /// - 검증 내용: raw `[U1, P1, U2, P2, U3]`에서 `U3 before U1` 후 pinned slot과 unpinned 표시 순서 검증
    /// - 사전 조건: P1/P2가 interleaved된 raw tabs와 두 pinned record, active/previous/recentlyClosed state
    /// - 기대 결과: raw `[U3, P1, U1, P2, U2]`, pinned raw slot과 나머지 state 불변
    func testReorderContentTab_interleavedRawOrderPreservesPinnedSubsequenceAndPersistence() {
        let unpinned1 = makeReorderDirectoryTab("U1", isPinned: false)
        let pinned1 = makeReorderDirectoryTab("P1", isPinned: true)
        let unpinned2 = makeReorderDirectoryTab("U2", isPinned: false)
        let pinned2 = makeReorderDirectoryTab("P2", isPinned: true)
        let unpinned3 = makeReorderDirectoryTab("U3", isPinned: false)
        let pinnedRecords = [
            pinned1.id: makePinnedRecord(pinned1, pinnedAt: 1),
            pinned2.id: makePinnedRecord(pinned2, pinnedAt: 2),
        ]
        let recentlyClosed = ClosedContentTabSnapshot(
            page: .home,
            anchor: .homeDefault,
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 3),
            title: "Closed Home",
            iconName: "house",
        )
        var original = ContentTabState(
            tabs: [unpinned1, pinned1, unpinned2, pinned2, unpinned3],
            activeTabID: unpinned2.id,
            previousActiveTabID: unpinned1.id,
            recentlyClosed: recentlyClosed,
            pinnedRecords: pinnedRecords,
            pendingPinnedRecordIDs: [pinned2.id],
            pinnedRecordPersistenceError: "existing_error",
        )
        original.selectedTabIDs = [pinned1.id, unpinned3.id]
        original.selectionAnchorID = unpinned1.id
        var state = original
        var expected = original
        expected.tabs = [unpinned3, pinned1, unpinned1, pinned2, unpinned2]

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .reorder(sourceID: unpinned3.id, targetID: unpinned1.id, placement: .before),
        )

        XCTAssertEqual(state, expected)
        XCTAssertEqual(state.tabs.filter(\.isPinned).map(\.id), [pinned1.id, pinned2.id])
        XCTAssertEqual(state.tabs.filter { !$0.isPinned }.map(\.id), [unpinned3.id, unpinned1.id, unpinned2.id])
    }

    /// CTM-001-reorder_content_tab: 화면상 인접한 unpinned placement는 pinned raw slot을 포함한 완전 no-op임
    /// Sidebar에서 이미 U1 다음에 보이는 U2를 U1 뒤로 다시 놓을 때 hidden pinned raw 위치가 바뀌지 않는지 검증한다.
    /// - 검증 내용: raw `[U1, P1, U2]`에서 `U2 after U1` 후 whole-state equality 검증
    /// - 사전 조건: U1/U2 사이에 pinned P1이 interleaved되어 있지만 Sidebar unpinned 표시 순서는 `[U1, U2]`
    /// - 기대 결과: raw tabs와 pinned record를 포함한 전체 state가 기존과 동일함
    func testReorderContentTab_displayNoOpPreservesInterleavedPinnedRawSlot() {
        let unpinned1 = makeReorderDirectoryTab("U1", isPinned: false)
        let pinned1 = makeReorderDirectoryTab("P1", isPinned: true)
        let unpinned2 = makeReorderDirectoryTab("U2", isPinned: false)
        let original = ContentTabState(
            tabs: [unpinned1, pinned1, unpinned2],
            activeTabID: unpinned2.id,
            previousActiveTabID: unpinned1.id,
            pinnedRecords: [pinned1.id: makePinnedRecord(pinned1, pinnedAt: 1)],
        )
        var state = original

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .reorder(sourceID: unpinned2.id, targetID: unpinned1.id, placement: .after),
        )

        XCTAssertEqual(state, original)
        XCTAssertEqual(state.tabs.map(\.id), [unpinned1.id, pinned1.id, unpinned2.id])
    }

    // MARK: - CTM-001-handle_content_tab_invariants

    /// CTM-001-handle_content_tab_invariants: invalid id와 max tab limit은 상태 invariant를 깨지 않는 no-op임
    /// 기능스펙의 invalid tab id 보존 요구와 Phase 1 max tab guardrail을 검증한다.
    /// - 검증 내용: unknown id actions no-op, maxTabs 도달 후 open/restore no-op
    /// - 사전 조건: active Home tab 하나, 또는 maxTabs만큼 채워진 tab list
    /// - 기대 결과: activeTabID와 tabs list가 기존 invariant를 유지함
    func testHandleContentTabInvariants_invalidIDAndMaxLimitAreNoOps() async {
        let activeID = ContentTabID()
        let invalidID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: activeID,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: activeID,
                recentlyClosed: nil,
            ),
        ) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(invalidID))
        await store.send(.close(invalidID))
        await store.send(.pin(invalidID))
        await store.send(.unpin(invalidID))
        await store.finish()

        var tabs = IdentifiedArrayOf<ContentTabItem>()
        for _ in 0 ..< ContentTabConstants.maxTabs {
            tabs.append(ContentTabItem(
                id: ContentTabID(),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
        }
        let firstID = tabs[0].id
        let maxLimitStore = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: firstID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await maxLimitStore.send(.open(.homeDefault))
        XCTAssertEqual(maxLimitStore.state.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(maxLimitStore.state.activeTabID, firstID)
        await maxLimitStore.finish()

        let restoreSnapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/restore"),
            wasPinned: false,
            closedAt: Date(),
        )
        let restoreMaxLimitStore = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: firstID, recentlyClosed: restoreSnapshot),
        ) {
            ContentTabFeature()
        }

        await restoreMaxLimitStore.send(.restore)
        XCTAssertEqual(restoreMaxLimitStore.state.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(restoreMaxLimitStore.state.activeTabID, firstID)
        XCTAssertEqual(restoreMaxLimitStore.state.recentlyClosed, restoreSnapshot)
        await restoreMaxLimitStore.finish()
    }

    // MARK: - CTM-001-content_tab_scope_integrity

    /// CTM-001-content_tab_scope_integrity: 새 Content Tab은 별도 FileManager content session을 만들고 기존 session을 보존함
    /// CTM action이 sidebar/inspector shell state를 침범하지 않으면서 active content만 tab session으로 swap하는지 검증한다.
    /// - 검증 내용: contentTabs.open(.directory) 후 active content는 새 path로 전환되고 기존 content는 tabContentStates에 보존됨
    /// - 사전 조건: `FileManagerWindowState.makeInitial(path:)` 기반 FileManagerFeature TestStore
    /// - 기대 결과: 새 Directory tab이 active가 되고 sidebar visibility, inspector visibility는 유지됨
    func testFileManagerContentTabScope_swapsContentSessionAndPreservesShellState() async throws {
        let initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let initialActiveID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        let initialNavigationPath = initialState.content.navigation.currentPath
        let initialSidebarVisible = initialState.sidebar.sidebarVisible
        let initialInspectorVisible = initialState.inspector.inspectorVisible
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 새 tab id는 reducer 내부에서 생성되므로 최종 invariant만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.directory(path: "/different"))))

        XCTAssertEqual(store.state.content.navigation.currentPath, "/different")
        XCTAssertEqual(store.state.tabContentStates[initialActiveID]?.navigation.currentPath, initialNavigationPath)
        XCTAssertEqual(store.state.sidebar.sidebarVisible, initialSidebarVisible)
        XCTAssertEqual(store.state.inspector.inspectorVisible, initialInspectorVisible)
    }

    // MARK: - CTM-001-open_new_content_tab_routing

    /// CTM-001-open_new_content_tab_routing: WindowCommand.openNewContentTab이 explicit selection을 보존하고 Home tab을 활성화함
    /// - 검증 내용: `.request(.openNewContentTab)`은 `.open(.homeDefault)`만 방출하고 selection collapse를 방출하지 않음
    /// - 사전 조건: 선택 및 anchor가 설정된 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: 기존 selection/anchor를 유지하면서 새 Home tab이 list 끝에 추가되어 active가 됨
    func testOpenNewContentTab_commandRouting_createsHomeTabAppendedActive() async throws {
        var initialState = FileManagerFeature.State()
        let selectedID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.contentTabs.selectedTabIDs = [selectedID]
        initialState.contentTabs.selectionAnchorID = selectedID
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로
        // routing layer의 명령 순서와 최종 상태 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count
        let beforeActiveID = store.state.contentTabs.activeTabID

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)
        await store.skipReceivedActions(strict: false)

        let afterCount = store.state.contentTabs.tabs.count
        XCTAssertEqual(afterCount, beforeCount + 1, "tabs count must increment by 1")
        let lastTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(lastTab.anchor, .homeDefault, "new tab must have homeDefault anchor")
        XCTAssertEqual(lastTab.page, .home, "new tab must have home page")
        XCTAssertEqual(store.state.contentTabs.activeTabID, lastTab.id, "new tab must be active")
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [selectedID])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, selectedID)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, beforeActiveID, "active tab ID must change to new tab")
    }

    /// CTM-001-open_new_content_tab_routing: 기존 active Directory/Collection anchor가 새 tab에 복제되지 않음
    /// VOY-447 AC3와 CTM contract의 "copy 방지" 정책을 검증한다.
    /// - 검증 내용: Directory tab이 active인 상태에서 openNewContentTab 전송 시 last.anchor == .homeDefault
    /// - 사전 조건: Directory anchor를 가진 active tab (makeInitial(path:)로 ContentTab과 별도로 navigation path만 설정)
    /// - 기대 결과: 새 tab anchor는 .homeDefault이며 기존 anchor를 복사하지 않음
    func testOpenNewContentTab_commandRouting_doesNotCloneExistingAnchor() async throws {
        var initialState = FileManagerFeature.State()
        initialState.contentTabs.tabs[0].anchor = .directory(path: "/test")
        initialState.contentTabs.tabs[0].page = .directory
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // anchor 복제 방지 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)

        let lastTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(lastTab.anchor, .homeDefault, "new tab must NOT clone existing Directory anchor")
        XCTAssertEqual(lastTab.page, .home, "new tab must start as Home, not Directory")
    }

    /// CTM-001-open_new_content_tab_routing: 기존 active tab은 새 tab 생성 후 inactive로 전환됨
    /// 새 tab이 active가 되면 이전 active tab이 더 이상 active가 아님을 검증한다.
    /// - 검증 내용: openNewContentTab 전후 이전 activeTabID가 tabs에 존재하지만 activeTabID와 다름
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: 이전 active tab은 tabs에 남아있고 activeTabID는 새 tab을 가리킴
    func testOpenNewContentTab_commandRouting_existingTabTransitionsInactive() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // tab active 전환 검증에 집중한다.
        store.exhaustivity = .off

        let previousActiveID = try XCTUnwrap(store.state.contentTabs.activeTabID)

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)

        let newActiveID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotNil(
            store.state.contentTabs.tabs[id: previousActiveID],
            "previous active tab must still exist in tabs",
        )
        XCTAssertNotEqual(newActiveID, previousActiveID, "active tab ID must change")
    }

    // MARK: - CTM-001-open_new_content_tab_invariants

    /// CTM-001-open_new_content_tab_invariants: ContentTabProjection.sidebarItems에 새 Home tab이 반영됨
    /// VOY-447 Sidebar projection refresh 정책을 검증한다.
    /// - 검증 내용: .request(.openNewContentTab) 후 ContentTabProjection.sidebarItems(from:) count +1 및 마지막 항목 pageType ==
    /// .home
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: projection output에 새 tab이 마지막 항목으로 포함됨
    func testOpenNewContentTab_projection_sidebarItemsIncludesNewHomeTab() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로 projection 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = ContentTabProjection.sidebarItems(from: store.state.contentTabs).count

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)

        let sidebarItems = ContentTabProjection.sidebarItems(from: store.state.contentTabs)
        XCTAssertEqual(sidebarItems.count, beforeCount + 1, "projection must reflect new tab count")
        let lastItem = try XCTUnwrap(sidebarItems.last)
        XCTAssertEqual(lastItem.pageType, .home, "last projection item pageType must be home")
    }

    /// CTM-001-open_new_content_tab_invariants: maxTabs 상태에서 openNewContentTab은 전체 Content Tab 상태를 보존함
    /// VOY-447 AC4 failure 정책을 검증한다.
    /// - 검증 내용: maxTabs 도달 후 command가 selection, anchor, active identity, previous identity, tabs를 변경하지 않음
    /// - 사전 조건: 선택 및 anchor가 설정되고 ContentTabConstants.maxTabs만큼 채워진 tab list
    /// - 기대 결과: command-level guard가 cleanup과 open을 모두 차단하여 contentTabs 전체가 불변임
    func testOpenNewContentTab_maxTabsNoOp_preservesState() async {
        var tabs = IdentifiedArrayOf<ContentTabItem>()
        for _ in 0 ..< ContentTabConstants.maxTabs {
            tabs.append(ContentTabItem(
                id: ContentTabID(),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
        }
        let firstID = tabs[0].id
        let lastID = tabs[tabs.count - 1].id
        var state = FileManagerFeature.State()
        state.contentTabs.tabs = tabs
        state.contentTabs.activeTabID = firstID
        state.contentTabs.previousActiveTabID = lastID
        state.contentTabs.selectedTabIDs = [firstID, lastID]
        state.contentTabs.selectionAnchorID = lastID
        state.content.entryViewLayout.entryOperations.isLoading = true
        state.content.entryViewLayout.entryOperations.isReloading = true
        state.content.composer.isLoadingSearch = true
        let originalContentTabs = state.contentTabs

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: maxTabs guard의 whole-state no-op과 unrelated loading 상태 불변 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.openNewContentTab))

        XCTAssertEqual(store.state.contentTabs, originalContentTabs)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.isLoading)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.isReloading)
        XCTAssertTrue(store.state.content.composer.isLoadingSearch)
    }

    /// CTM-001-open_new_content_tab_invariants: 연속 openNewContentTab은 중복되지 않는 ID를 생성함
    /// VOY-447 repeated rapid creation 방지 정책을 검증한다.
    /// - 검증 내용: .request(.openNewContentTab) 2회 연속 후 모든 tab ID가 유일함
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: 모든 tab의 id가 유일함 (Set count == count)
    func testOpenNewContentTab_repeatedCreation_usesUniqueIDs() async {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로 ID uniqueness 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)

        let allIDs = store.state.contentTabs.tabs.map(\.id)
        let uniqueIDs = Set(allIDs)
        XCTAssertEqual(uniqueIDs.count, allIDs.count, "all tab IDs must be unique")
    }

    // MARK: - CTM-001-home_selection_page_conversion

    /// CTM-001-home_selection_page_conversion: 고정 Desktop 선택이 active Home tab을 Directory anchor로 변환함
    /// VOY-438 AC1의 고정 디렉터리 → ContentTabPageAnchor.directory(path:) 변환을 검증한다.
    /// - 검증 내용: tabs.count 불변, activeTabID 불변, tab.anchor가 Desktop 경로를 포함, tab.page == .directory
    /// - 사전 조건: FileManagerFeature.State 기본 Home tab 하나, fileManagerClient.urlsForDirectory → live FileManager
    /// - 기대 결과: Home tab의 anchor가 Desktop 파일시스템 경로로 변경되고 page가 directory로 전환됨
    func testHomeSelection_fixedDesktop_convertsToDirectoryAnchor() async throws {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "/"
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { FileManager.default.urls(for: $0, in: $1) }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로 anchor 변환 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count
        let beforeActiveID = store.state.contentTabs.activeTabID

        await store.send(.content(.view(.homeSelectionTapped(.fixedDirectory(.desktop)))))
        await store.receive(\.contentTabs)
        await receiveDirectoryNavigation(store, path: desktopPath)

        XCTAssertEqual(store.state.content.navigation.currentPath, desktopPath)
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(store.state.content.entryViewLayout.currentPath, desktopPath)
        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount)
        XCTAssertEqual(store.state.contentTabs.activeTabID, beforeActiveID)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: desktopPath))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: 고정 Documents 선택이 active Home tab을 Directory anchor로 변환함
    /// VOY-438 AC1의 Documents 고정 디렉터리 → ContentTabPageAnchor.directory(path:) 변환을 검증한다.
    /// - 검증 내용: tabs.count 불변, tab.anchor가 Documents 경로를 포함, tab.page == .directory
    /// - 사전 조건: FileManagerFeature.State 기본 Home tab 하나, fileManagerClient.urlsForDirectory → live FileManager
    /// - 기대 결과: Home tab의 anchor가 Documents 파일시스템 경로로 변경되고 page가 directory로 전환됨
    func testHomeSelection_fixedDocuments_convertsToDirectoryAnchor() async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "/"
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { FileManager.default.urls(for: $0, in: $1) }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // Documents anchor 변환 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.fixedDirectory(.documents)))))
        await store.receive(\.contentTabs)
        await receiveDirectoryNavigation(store, path: documentsPath)

        XCTAssertEqual(store.state.content.navigation.currentPath, documentsPath)
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(store.state.content.entryViewLayout.currentPath, documentsPath)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: documentsPath))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: 디렉터리 피커 성공 시 active tab anchor가 변환됨
    /// VOY-438 AC2a의 openDirectory 피커 성공 → ContentTabPageAnchor.directory(path:) 변환을 검증한다.
    /// - 검증 내용: homePickerClient.pickDirectory mock이 .selected("/tmp/test") 반환 후 tab.anchor == .directory(path:
    /// "/tmp/test"),
    ///   tab.page == .directory
    /// - 사전 조건: homePickerClient.pickDirectory → .selected("/tmp/test")
    /// - 기대 결과: active tab의 anchor가 피커에서 선택한 경로로 변경되고 page가 directory로 전환됨
    func testHomeSelection_openDirectoryPickerSuccess_convertsAnchor() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickDirectory = { .selected("/tmp/test") }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action과
        // HomeSelectionReducer의 picker effect 결과를 방출하므로 최종 anchor 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openDirectory))))
        await store.receive(\.contentTabs)
        await receiveDirectoryNavigation(store, path: "/tmp/test")

        XCTAssertEqual(store.state.content.navigation.currentPath, "/tmp/test")
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(store.state.content.entryViewLayout.currentPath, "/tmp/test")
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: "/tmp/test"))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: 디렉터리 피커 취소 시 Home anchor가 유지됨
    /// VOY-438 AC2b의 openDirectory 피커 취소 → no-op을 검증한다.
    /// - 검증 내용: homePickerClient.pickDirectory → .cancelled 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickDirectory → .cancelled
    /// - 기대 결과: 피커 취소 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openDirectoryPickerCancel_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickDirectory = { .cancelled }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 피커 취소 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openDirectory))))
        await store.receive(\.content.internal.homeDirectoryPickerFinished)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 디렉터리 피커 실패 시 Home anchor가 유지됨
    /// VOY-438 AC2b의 openDirectory 피커 실패 → no-op을 검증한다.
    /// - 검증 내용: homePickerClient.pickDirectory → .failed("error") 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickDirectory → .failed("error")
    /// - 기대 결과: 피커 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openDirectoryPickerFailure_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickDirectory = { .failed("error") }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 피커 실패 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openDirectory))))
        await store.receive(\.content.internal.homeDirectoryPickerFinished)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: hydrated 컬렉션 열기 성공 시 anchor가 .collectionFile로 변환됨
    /// VOY-438 AC3a의 openCollection 피커 성공 → hydration 성공 후 ContentTabPageAnchor.collectionFile(url:) 변환을 검증한다.
    /// - 검증 내용: homePickerClient.pickCollectionFile → .selected(URL) 반환 후 hydrated navigation 적용 뒤 tab.anchor ==
    /// .collectionFile(url:)
    /// - 사전 조건: homePickerClient.pickCollectionFile → .selected(URL(fileURLWithPath: "/tmp/test.voycoll"))
    /// - 기대 결과: active tab의 anchor가 컬렉션 파일 URL로 변경되고 page가 collection으로 전환됨
    func testHomeSelection_openCollectionPickerSuccess_convertsAnchor() async throws {
        let collectionURL = URL(fileURLWithPath: "/tmp/test.voycoll")
        let loadedFile = VoyagerCollectionFile(
            id: "ctm-open-collection",
            name: "test",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "kind:document",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: CollectionPersistedSnapshot(items: [
                .string("/tmp/document.md"),
            ]),
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(file: VoyagerCollectionFile(
                    id: "ctm-open-collection",
                    name: "test",
                    createdAt: .distantPast,
                    updatedAt: .distantFuture,
                    query: "kind:document",
                    scopes: ["/tmp"],
                    conditions: [],
                    snapshot: CollectionPersistedSnapshot(items: [
                        .string("/tmp/document.md"),
                    ]),
                    snapshotMeta: nil,
                    appVersion: nil,
                )),
                capturedAt: Date(timeIntervalSince1970: 1_234_567_890),
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        )
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .selected(collectionURL) }
            $0.collectionFileClient.load = { _ in
                VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
                    file: loadedFile,
                    containerFormat: .package,
                    sourceSchemaVersion: CollectionFileSchemaVersion.current,
                    warning: nil,
                    usedDefinitionFallback: false,
                )
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = ImmediateClock()
        }
        // 비포괄적: picker/load/open flow가 여러 child action을 방출하므로
        // 최종 anchor 확정 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openCollection))))
        await store.receive(\.content.internal.homeCollectionPickerFinished)
        await store.receive(\.navigation.view.openCollectionFile)
        await store.receive(\.navigation.internal.collectionFileLoaded)
        await store.receive(\.content.internal.applyNavigationState)
        await store.receive(\.contentTabs)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .collectionFile(url: collectionURL))
        XCTAssertEqual(tab.page, .collection)
    }

    /// CTM-001-home_selection_page_conversion: 컬렉션 피커 취소 시 Home anchor가 유지됨
    /// VOY-438 AC3b의 openCollection 피커 취소 → no-op을 검증한다.
    /// - 검증 내용: homePickerClient.pickCollectionFile → .cancelled 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickCollectionFile → .cancelled
    /// - 기대 결과: 피커 취소 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openCollectionPickerCancel_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .cancelled }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 컬렉션 피커 취소 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openCollection))))
        await store.receive(\.content.internal.homeCollectionPickerFinished)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 컬렉션 파일 load 실패 시 Home anchor가 유지됨
    /// 컬렉션 anchor는 파일 open 성공 후 확정되어야 하며, load 실패만으로 tab metadata를 collection으로 바꾸지 않는다.
    /// - 검증 내용: picker는 URL을 반환하지만 collectionFileClient.load 실패 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickCollectionFile → .selected(URL), collectionFileClient.load throws
    /// - 기대 결과: open 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openCollectionLoadFailure_preservesHome() async throws {
        enum TestError: Error {
            case loadFailed
        }
        let collectionURL = URL(fileURLWithPath: "/tmp/missing.voycoll")
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .selected(collectionURL) }
            $0.collectionFileClient.load = { _ in throw TestError.loadFailed }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: 실패 경로의 alert/rollback child action보다 tab anchor 보존을 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openCollection))))
        await store.receive(\.content.internal.homeCollectionPickerFinished)
        await store.receive(\.navigation.view.openCollectionFile)
        await store.receive(\.navigation.internal.collectionFileLoaded)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 컬렉션 검색 실패 시 Home anchor가 유지됨
    /// 컬렉션 anchor는 파일 load 성공만으로 확정하지 않고 검색 성공 후 확정되어야 한다.
    /// - 검증 내용: collection load는 성공하지만 searchClient.search 실패 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickCollectionFile → .selected(URL), collectionFileClient.load success,
    /// searchClient.search throws
    /// - 기대 결과: 검색 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openCollectionSearchFailure_preservesHome() async throws {
        enum TestError: Error {
            case searchFailed
        }
        let collectionURL = URL(fileURLWithPath: "/tmp/search-fail.voycoll")
        let loadedFile = VoyagerCollectionFile(
            id: "ctm-open-collection-search-fail",
            name: "search-fail",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "kind:document",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .selected(collectionURL) }
            $0.collectionFileClient.load = { _ in
                VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
                    file: loadedFile,
                    containerFormat: .package,
                    sourceSchemaVersion: CollectionFileSchemaVersion.current,
                    warning: nil,
                    usedDefinitionFallback: false,
                )
            }
            $0.searchClient.search = { _ in throw TestError.searchFailed }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = ImmediateClock()
        }
        // 비포괄적: 검색 실패 alert/rollback 세부 action보다 tab anchor 보존을 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.openCollection))))
        await store.receive(\.content.internal.homeCollectionPickerFinished)
        await store.receive(\.navigation.view.openCollectionFile)
        await store.receive(\.navigation.internal.collectionFileLoaded)
        await store.receive(\.content.delegate.composerCollectionSearchFailed)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: AI Chat 세션 생성 성공 시 anchor가 .aiChat으로 변환됨
    /// VOY-438 AC4a의 startAiChat 성공 → ContentTabPageAnchor.aiChat(sessionID:) 변환을 검증한다.
    /// - 검증 내용: homeAiChatClient.createSession → .selected("session-123") 반환 후 tab.anchor == .aiChat(sessionID:
    /// "session-123"),
    ///   tab.page == .aiChat
    /// - 사전 조건: homeAiChatClient.createSession → .selected("session-123")
    /// - 기대 결과: active tab의 anchor가 AI Chat 세션 ID로 변경되고 page가 aiChat으로 전환됨
    func testHomeSelection_startAiChatSuccess_convertsAnchor() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .selected("session-123") }
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action과
        // HomeSelectionReducer의 session 생성 effect 결과를 방출하므로 최종 anchor 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.startAiChat))))
        await store.receive(\.contentTabs)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .aiChat(sessionID: "session-123"))
        XCTAssertEqual(tab.page, .aiChat)
    }

    /// CTM-001-home_selection_page_conversion: AI Chat 세션 생성 실패 시 Home anchor가 유지됨
    /// VOY-438 AC4b의 startAiChat 실패 → no-op을 검증한다.
    /// - 검증 내용: homeAiChatClient.createSession → .failed("error") 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homeAiChatClient.createSession → .failed("error")
    /// - 기대 결과: 세션 생성 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_startAiChatFailure_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .failed("error") }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 세션 생성 실패 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.startAiChat))))
        await store.receive(\.content.internal.homeAiChatSessionCreated)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: non-Home active tab에서 Home 선택은 no-op
    /// 사용자가 Directory tab에서 Home 선택 항목을 보낼 수 없지만(non-Home은 HomePageView 미표시),
    /// 안전장치로 anchor 변경이 발생하지 않음을 검증한다.
    /// - 검증 내용: active tab이 Directory("/tmp")인 상태에서 Desktop 선택 후 anchor, page 불변
    /// - 사전 조건: active tab anchor == .directory(path: "/tmp"), page == .directory
    /// - 기대 결과: routing guard가 active tab이 .homeDefault가 아님을 감지하여 no-op 처리
    func testHomeSelection_whenActiveTabIsNotHome_isNoOp() async throws {
        var state = FileManagerFeature.State()
        state.contentTabs.tabs[0].anchor = .directory(path: "/tmp")
        state.contentTabs.tabs[0].page = .directory
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { FileManager.default.urls(for: $0, in: $1) }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // routing guard no-op 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count
        let beforeActiveID = store.state.contentTabs.activeTabID

        await store.send(.content(.view(.homeSelectionTapped(.fixedDirectory(.desktop)))))

        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount)
        XCTAssertEqual(store.state.contentTabs.activeTabID, beforeActiveID)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: "/tmp"))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: activeTabID가 nil이면 Home 선택이 no-op임
    /// VOY-438 AC5의 edge case를 검증한다. activeTabID가 없으면 FileManagerWindowCommandRoutingReducer가
    /// delegate action을 무시하고 .none을 반환함.
    /// - 검증 내용: activeTabID == nil인 상태에서 Desktop 선택 후 tabs, anchor 불변
    /// - 사전 조건: contentTabs.activeTabID == nil, anchor == .homeDefault
    /// - 기대 결과: state가 전혀 변경되지 않음
    func testHomeSelection_whenNoActiveTabID_isNoOp() async throws {
        var state = FileManagerFeature.State()
        state.contentTabs.activeTabID = nil
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // activeTabID nil no-op 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count

        await store.send(.content(.view(.homeSelectionTapped(.fixedDirectory(.desktop)))))

        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    // MARK: - CTM-001-home_selection_page_conversion: ContentPane AI Chat setup

    /// Home Start AI Chat 선택 시 ContentPane AI Chat이 sessionID로 초기화되고 Inspector Chat은 닫힘
    /// VOY-509 Task 2: 홈 화면 Start AI Chat 버튼 탭 시 ContentPane AI Chat state가 .setup과 .providerConnectionsUpdated를
    /// 수신하고, 기존 Inspector Chat은 닫히는지 검증한다.
    /// - 검증 내용: tab count 불변, active tab anchor/page가 .aiChat(sessionID:)로 전환,
    ///   content.aiChat.restoreSessionID가 sessionID로 설정됨,
    ///   열린 Inspector Chat을 닫고 inspector.aiChat 세션 상태는 오염시키지 않음
    /// - 사전 조건: homeAiChatClient.createSession → .selected("session-123"),
    ///   aiConnectionsFileClient.load → .empty()
    /// - 기대 결과: 새로운 tab 생성 없이 active tab이 AI Chat anchor로 변환되고 ContentPane AI Chat이 초기화되며 Inspector Chat은 닫힘
    func testHomeSelection_startAiChat_initializesContentPaneAiChat() async throws {
        let sessionID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        var initialState = FileManagerFeature.State()
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .selected(sessionID) }
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        // 비포괄적: FileManagerFeature.onAppear 및 다중 async effect가 여러 action을 방출하므로
        // ContentPane AI Chat 초기화 검증에 집중한다.
        store.exhaustivity = .off

        let initialTabCount = store.state.contentTabs.tabs.count

        await store.send(.content(.view(.homeSelectionTapped(.startAiChat))))
        // Home AI Chat 전환은 same-tab handoff에서도 Inspector Chat을 먼저 닫고,
        // active tab anchor와 navigation route를 고정한 뒤 provider load만 tab-scoped async로 처리한다.
        await store.receive { action in
            guard case .inspector(.closeChat) = action else { return false }
            return true
        } assert: { state in
            state.inspector.inspectorVisible = false
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(_, .aiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .internal(.aiChatTabTitleUpdated(receivedSessionID, title)) = action else {
                return false
            }
            return receivedSessionID.rawValue.uuidString == sessionID && title == "New Chat"
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case .content(.aiChat(.setup)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action
            else { return false }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action
            else { return false }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case .content(.aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        let expectedSessionUUID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())

        // Tab count invariance — no new tab created
        XCTAssertEqual(store.state.contentTabs.tabs.count, initialTabCount, "tab count must not change")

        // Active tab anchor/page converted to .aiChat
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(tab.page, .aiChat)
        XCTAssertEqual(tab.title, "New Chat")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, "New Chat")

        // ContentPane AI Chat은 .setup 수신 후 즉시 채팅 모드로 열리고 navigation history에 기록된다
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(sessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertTrue(store.state.content.navigation.canGoBack)
        XCTAssertFalse(store.state.content.navigation.canGoForward)
        XCTAssertEqual(
            store.state.content.aiChat.mode,
            .chat,
            "Start AI Chat must open the chat input screen before history",
        )
        XCTAssertEqual(
            store.state.content.aiChat.sessionID,
            expectedSessionUUID,
            "ContentPane aiChat must keep the fresh Start AI Chat sessionID",
        )
        XCTAssertNil(
            store.state.content.aiChat.restoreSessionID,
            "Fresh ContentPane AI Chat must skip restore to avoid first-frame layout jump",
        )
        XCTAssertEqual(
            store.state.content.aiChat.sessionStatus,
            .idle,
            "Fresh ContentPane AI Chat must remain idle instead of entering restore",
        )

        // Inspector Chat은 ContentPane AI Chat과 동시에 남지 않도록 닫힌다.
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertNil(
            store.state.inspector.aiChat.restoreSessionID,
            "Inspector aiChat restoreSessionID must remain nil",
        )
        XCTAssertNil(
            store.state.inspector.aiChat.sessionID,
            "Inspector aiChat sessionID must remain nil",
        )
    }

    private func closeReconciliationTabs(
        tabA: ContentTabID,
        tabB: ContentTabID,
        tabC: ContentTabID,
    ) -> IdentifiedArrayOf<ContentTabItem> {
        [
            ContentTabItem(
                id: tabA,
                page: .directory,
                anchor: .directory(path: "/A"),
                isPinned: false,
                title: "A",
                iconName: "folder",
            ),
            ContentTabItem(
                id: tabB,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            ),
            ContentTabItem(
                id: tabC,
                page: .directory,
                anchor: .directory(path: "/C"),
                isPinned: false,
                title: "C",
                iconName: "folder",
            ),
        ]
    }

    // MARK: - CTM-001-external_tab_reservation

    /// CTM-001-external_tab_reservation: 외부 file reservation은 caller가 제공한 identity와 pending selection을 사용한다.
    /// 시스템 open 배치가 일반 파일을 기존 window의 새 Content Tab으로 예약하는 계약의 RED 기준을 검증한다.
    /// - 검증 내용: 외부 예약 후 active tab ID와 active content pending selection이 caller 입력과 일치한다.
    /// - 사전 조건: seed Directory tab이 active이고 caller가 tab ID, parent Directory anchor, file selection ID를 제공한다.
    /// - 기대 결과: 새 tab은 caller ID로 active가 되고 파일 selection은 첫 load 전에 content snapshot에 존재한다.
    func testExternalTabReservation_usesCallerIdentityAndPendingSelection() async throws {
        let callerTabID = ContentTabID(rawValue: "external-file-tab")
        let selectedSiblingID = ContentTabID(rawValue: "external-selected-sibling")
        let pendingSelection = "/tmp/report.txt"
        var state = FileManagerWindowState.makeInitial(path: "/seed")
        let originalActiveID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.contentTabs.tabs.append(ContentTabItem(
            id: selectedSiblingID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Selected Sibling",
            iconName: "house",
        ))
        state.contentTabs.selectedTabIDs = [originalActiveID, selectedSiblingID]
        state.contentTabs.selectionAnchorID = selectedSiblingID
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: 기존 open 경로의 내부 handoff보다 결여된 external reservation 계약 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs([
            ExternalContentTabReservation(
                id: callerTabID,
                anchor: .directory(path: "/tmp"),
                pendingSelectEntryID: pendingSelection,
            ),
        ]))
        await store.receive(\.contentTabs.setCurrent, callerTabID)

        XCTAssertEqual(store.state.contentTabs.activeTabID, callerTabID)
        XCTAssertEqual(
            store.state.contentTabs.selectedTabIDs,
            Set([originalActiveID, selectedSiblingID]),
        )
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, selectedSiblingID)
        XCTAssertEqual(store.state.menuCommandProjection.selectedContentTabCount, 2)
        XCTAssertTrue(store.state.menuCommandProjection.canDuplicateSelectedContentTabs)
        XCTAssertEqual(store.state.content.pendingSelectEntryID, pendingSelection)
        XCTAssertEqual(store.state.tabContentStates[callerTabID]?.pendingSelectEntryID, pendingSelection)
    }

    /// CTM-001-external_tab_reservation: 기존 window에 ordered reservation을 원자 적용한다.
    /// active Directory와 pinned inactive tab이 있는 window에 Directory, Collection, regular-file tab을 배치한다.
    /// - 검증 내용: 기존 active snapshot 저장, ordered append, active/previous ID, content/inspector snapshot 원자 갱신이다.
    /// - 사전 조건: 기존 active content/inspector와 pinned inactive metadata가 있고 Collection reservation은 inactive가 된다.
    /// - 기대 결과: 기존 metadata는 유지되고 모든 snapshot이 생성되며 regular-file pending selection은 active load 전에 존재한다.
    func testExternalTabReservation_appliesOrderedSnapshotsAtomically() async throws {
        let scenario = try ExternalTabReservationTestFixture.makeAtomicScenario()
        let store = TestStore(initialState: scenario.initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: append 이후 canonical handoff의 navigation child action은 별도 owner가 검증한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs(scenario.reservations))
        await store.receive(\.contentTabs.setCurrent, scenario.fileID)
        await store.skipReceivedActions()
        await store.finish()

        scenario.assertResult(store.state)
    }

    /// CTM-001-external_tab_reservation: 기존 Directory load를 취소한 뒤 예약 Directory를 한 번 load한다.
    /// external reservation activation이 일반 tab handoff cancellation과 reload 경로를 재사용하는지 검증한다.
    /// - 검증 내용: 이전 load cancellation 1회와 destination loadItems 1회다.
    /// - 사전 조건: seed Directory load가 대기 중이고 새 Directory reservation 하나가 append된다.
    /// - 기대 결과: setCurrent handoff가 이전 load를 취소하고 새 경로만 한 번 load한다.
    func testExternalTabReservation_cancelsOutgoingLoadBeforeLoadingDestination() async {
        let tabID = ContentTabID(rawValue: "external-directory-cancellation")
        let oldLoadStarted = expectation(description: "outgoing load started")
        let oldLoadCancelled = expectation(description: "outgoing load cancelled")
        let oldLoadGate = AsyncStream<Void>.makeStream()
        let cancellationCount = LockIsolated(0)
        let loadPaths = LockIsolated<[String]>([])
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/seed")) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                guard url.path == "/seed" else { return [] }
                oldLoadStarted.fulfill()
                return await withTaskCancellationHandler {
                    for await _ in oldLoadGate.stream {}
                    return []
                } onCancel: {
                    cancellationCount.withValue { $0 += 1 }
                    oldLoadGate.continuation.finish()
                    oldLoadCancelled.fulfill()
                }
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: cancellation과 경로별 load 호출 외 navigation child action은 별도 owner가 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .loadItems(path: "/seed", showHidden: false),
        )))))
        await fulfillment(of: [oldLoadStarted], timeout: 1)
        await store.send(.reserveExternalContentTabs([
            .init(id: tabID, anchor: .directory(path: "/external")),
        ]))
        await store.receive(\.contentTabs.setCurrent, tabID)
        await fulfillment(of: [oldLoadCancelled], timeout: 1)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(loadPaths.value, ["/seed", "/external"])
    }

    /// CTM-001-external_tab_reservation: Collection reservation은 canonical open 경로를 정확히 한 번 사용한다.
    /// Directory reload와 Collection open이 중복 실행되지 않는 handoff 분기를 검증한다.
    /// - 검증 내용: openCollectionFile load 1회와 directory loadItems 0회다.
    /// - 사전 조건: seed Directory가 active이고 Collection file reservation 하나가 append된다.
    /// - 기대 결과: setCurrent 후 Collection file open만 한 번 실행된다.
    func testExternalTabReservation_opensCollectionExactlyOnceWithoutDirectoryLoad() async {
        enum TestError: Error {
            case loadFailed
        }
        let tabID = ContentTabID(rawValue: "external-collection-open")
        let collectionURL = URL(fileURLWithPath: "/tmp/external-once.voycoll")
        let openedURLs = LockIsolated<[URL]>([])
        let directoryLoads = LockIsolated(0)
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/seed")) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.collectionFileClient.load = { url in
                openedURLs.withValue { $0.append(url) }
                throw TestError.loadFailed
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.entryLoadingClient.loadItems = { _, _ in
                directoryLoads.withValue { $0 += 1 }
                return []
            }
        }
        // store.exhaustivity = .off: 실패 alert 세부 action보다 reservation의 canonical Collection open 횟수를 검증한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs([
            .init(id: tabID, anchor: .collectionFile(url: collectionURL)),
        ]))
        await store.receive(\.contentTabs.setCurrent, tabID)
        await store.receive(\.navigation.view.openCollectionFile, collectionURL)
        await store.receive(\.navigation.internal.collectionFileLoaded)
        await store.finish()

        XCTAssertEqual(openedURLs.value, [collectionURL])
        XCTAssertEqual(directoryLoads.value, 0)
    }

    /// CTM-001-external_tab_reservation: explicit Collection resync는 active Directory를 다시 load하지 않는다.
    /// live window onAppear가 이미 적용한 Directory navigation을 후속 resync가 중복 실행하지 않는지 검증한다.
    /// - 검증 내용: package-owned resync action 이후 directory loadItems 호출 0회다.
    /// - 사전 조건: Home 없는 external window에서 Directory reservation이 active다.
    /// - 기대 결과: Collection 전용 resync가 Directory navigation을 변경하거나 reload하지 않는다.
    func testExternalTabReservation_collectionResyncSkipsActiveDirectory() async throws {
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "external-directory-resync")
        let initialState = try XCTUnwrap(FileManagerWindowState.makeExternalInitial(
            reservations: [.init(id: tabID, anchor: .directory(path: "/external"))],
            windowID: windowID,
        ))
        let directoryLoads = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in
                directoryLoads.withValue { $0 += 1 }
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: child navigation action보다 Collection resync의 Directory no-op 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.resyncActiveCollectionNavigation)

        XCTAssertEqual(directoryLoads.value, 0)
    }

    /// CTM-001-external_tab_reservation: invalid reservation set은 전체를 fail-closed 처리한다.
    /// duplicate ID, capacity 초과, external-incompatible anchor가 기존 window를 부분 변경하지 않는지 검증한다.
    /// - 검증 내용: 각 invalid batch 처리 후 FileManagerWindowState 전체 equality가 유지된다.
    /// - 사전 조건: 기존 Directory window와 duplicate/capacity/home/Collection-pending invalid 입력이다.
    /// - 기대 결과: tabs, active/previous IDs, content, tab/inspector snapshots mutation이 모두 0회다.
    func testExternalTabReservation_invalidSetsDoNotMutateState() async {
        let initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let existingID = initialState.contentTabs.activeTabID ?? ContentTabID(rawValue: "missing-active")
        let invalidSets = ExternalTabReservationTestFixture.makeInvalidSets(existingID: existingID)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        for reservations in invalidSets {
            await store.send(.reserveExternalContentTabs(reservations))
            XCTAssertEqual(store.state, initialState)
        }
        XCTAssertEqual(ContentTabConstants.maxTabs, 20)
    }

    /// CTM-001-external_tab_reservation: pending tab-close 중 external reservation은 fail-closed 처리된다.
    /// 미저장 Collection close transaction이 진행 중일 때 active content 교체를 막는 window invariant를 검증한다.
    /// - 검증 내용: valid reservation action 이후에도 전체 FileManagerWindowState가 동일하다.
    /// - 사전 조건: active Directory tab을 대상으로 pending close transaction이 설정되어 있다.
    /// - 기대 결과: reservation append와 active/content/snapshot mutation이 모두 0회다.
    func testExternalTabReservation_pendingCloseDoesNotMutateState() async throws {
        var initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let activeID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.pendingContentTabClose = PendingContentTabClose(
            tabID: activeID,
            previousActiveTabID: nil,
            previousActiveContent: nil,
            targetContent: initialState.content,
            previousActiveInspector: nil,
            targetInspector: initialState.inspector,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.reserveExternalContentTabs([
            ExternalContentTabReservation(
                id: ContentTabID(rawValue: "blocked-by-pending-close"),
                anchor: .directory(path: "/blocked"),
            ),
        ]))
        XCTAssertEqual(store.state, initialState)
    }

    /// CTM-001-external_tab_reservation: external initial factory는 Home 없이 reservation만으로 window state를 만든다.
    /// overflow window가 bootstrap Home을 만들지 않고 첫 reservation부터 deterministic tab state를 소유하는지 검증한다.
    /// - 검증 내용: ordered tab IDs, active/previous ID, per-tab content/inspector snapshot과 Home 부재다.
    /// - 사전 조건: Directory regular-file reservation과 Collection reservation 두 개다.
    /// - 기대 결과: 정확히 두 reservation tab만 존재하고 마지막 Collection이 active이며 load effect 없이 snapshot만 생성된다.
    func testExternalTabReservation_makeInitialContainsReservationsWithoutHome() throws {
        let fileID = ContentTabID(rawValue: "overflow-file")
        let collectionID = ContentTabID(rawValue: "overflow-collection")
        let collectionURL = URL(fileURLWithPath: "/tmp/overflow.voycoll")
        let state = try XCTUnwrap(FileManagerWindowState.makeExternalInitial(
            reservations: [
                ExternalContentTabReservation(
                    id: fileID,
                    anchor: .directory(path: "/tmp"),
                    pendingSelectEntryID: "/tmp/file.txt",
                ),
                ExternalContentTabReservation(id: collectionID, anchor: .collectionFile(url: collectionURL)),
            ],
        ))

        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [fileID, collectionID])
        XCTAssertFalse(state.contentTabs.tabs.contains(where: { $0.anchor == .homeDefault }))
        XCTAssertEqual(state.contentTabs.activeTabID, collectionID)
        XCTAssertEqual(state.contentTabs.previousActiveTabID, fileID)
        XCTAssertEqual(state.tabContentStates[fileID]?.pendingSelectEntryID, "/tmp/file.txt")
        XCTAssertEqual(state.content, state.tabContentStates[collectionID])
        XCTAssertEqual(Set(state.tabContentStates.keys), Set([fileID, collectionID]))
        XCTAssertEqual(Set(state.tabInspectorStates.keys), Set([fileID, collectionID]))
        XCTAssertNil(FileManagerWindowState.makeExternalInitial(reservations: []))
    }
}

private enum ExternalTabReservationTestFixture {
    struct AtomicScenario {
        let initialState: FileManagerWindowState
        let reservations: [ExternalContentTabReservation]
        let originalActiveID: ContentTabID
        let pinnedID: ContentTabID
        let pinnedTab: ContentTabItem
        let pinnedContent: FileManagerContentState
        let pinnedRecord: ContentTabPinnedRecord
        let directoryID: ContentTabID
        let collectionID: ContentTabID
        let fileID: ContentTabID
        let collectionURL: URL
        let pendingSelection: String
        let expectedOriginalContent: FileManagerContentState
        let expectedOriginalInspector: FileManagerInspectorFeature.State

        func assertResult(_ state: FileManagerWindowState) {
            XCTAssertEqual(
                state.contentTabs.tabs.map(\.id),
                [pinnedID, originalActiveID, directoryID, collectionID, fileID],
            )
            XCTAssertEqual(state.contentTabs.activeTabID, fileID)
            XCTAssertEqual(state.contentTabs.previousActiveTabID, originalActiveID)
            XCTAssertEqual(state.tabContentStates[originalActiveID], expectedOriginalContent)
            XCTAssertEqual(state.tabInspectorStates[originalActiveID], expectedOriginalInspector)
            XCTAssertEqual(state.contentTabs.tabs[id: pinnedID], pinnedTab)
            XCTAssertEqual(state.contentTabs.pinnedRecords[pinnedID], pinnedRecord)
            XCTAssertEqual(state.tabContentStates[pinnedID], pinnedContent)
            XCTAssertEqual(state.tabContentStates[fileID]?.pendingSelectEntryID, pendingSelection)
            XCTAssertEqual(state.content.pendingSelectEntryID, pendingSelection)
            XCTAssertEqual(state.content.navigation.currentPath, "/tmp")
            XCTAssertNotNil(state.tabInspectorStates[directoryID])
            XCTAssertNotNil(state.tabInspectorStates[collectionID])
            XCTAssertNotNil(state.tabInspectorStates[fileID])
            for reservation in reservations {
                XCTAssertTrue(state.tabContentStates[reservation.id]?.entryViewLayout.showHiddenFiles ?? false)
                XCTAssertEqual(state.tabContentStates[reservation.id]?.entryViewLayout.gridIconSize, 73)
            }
            guard case let .collection(navigation) = state.tabContentStates[collectionID]?.navigation.navigationState
            else {
                return XCTFail("inactive Collection reservation must own an effect-free collection snapshot")
            }
            XCTAssertEqual(navigation.kind, .file(url: collectionURL, name: "ordered"))
        }
    }

    private struct PinnedState {
        let id: ContentTabID
        let tab: ContentTabItem
        let content: FileManagerContentState
        let record: ContentTabPinnedRecord
    }

    static func makeInvalidSets(existingID: ContentTabID) -> [[ExternalContentTabReservation]] {
        [
            [ExternalContentTabReservation(id: existingID, anchor: .directory(path: "/existing"))],
            duplicateReservationSet(),
            overCapacityReservationSet(),
            [ExternalContentTabReservation(id: ContentTabID(rawValue: "home"), anchor: .homeDefault)],
            [relativeDirectoryReservation()],
            [relativeSelectionReservation()],
            [foreignSelectionReservation()],
            [collectionSelectionReservation()],
        ]
    }

    static func makeAtomicScenario() throws -> AtomicScenario {
        var initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let originalActiveID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.content.pendingSelectEntryID = "/seed/current.txt"
        initialState.content.entryViewLayout.showHiddenFiles = true
        initialState.content.entryViewLayout.gridIconSize = 73
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        let expectedOriginalContent = initialState.content
        let expectedOriginalInspector = initialState.inspector.tabSnapshot()
        let pinned = makePinnedTabState()
        initialState.contentTabs.tabs.insert(pinned.tab, at: 0)
        initialState.tabContentStates[pinned.id] = pinned.content
        initialState.contentTabs.pinnedRecords[pinned.id] = pinned.record

        let directoryID = ContentTabID(rawValue: "external-directory")
        let collectionID = ContentTabID(rawValue: "external-collection")
        let fileID = ContentTabID(rawValue: "external-file")
        let collectionURL = URL(fileURLWithPath: "/tmp/ordered.voycoll")
        let pendingSelection = "/tmp/report.txt"
        let reservations = [
            ExternalContentTabReservation(id: directoryID, anchor: .directory(path: "/external")),
            ExternalContentTabReservation(id: collectionID, anchor: .collectionFile(url: collectionURL)),
            ExternalContentTabReservation(
                id: fileID,
                anchor: .directory(path: "/tmp"),
                pendingSelectEntryID: pendingSelection,
            ),
        ]
        return AtomicScenario(
            initialState: initialState,
            reservations: reservations,
            originalActiveID: originalActiveID,
            pinnedID: pinned.id,
            pinnedTab: pinned.tab,
            pinnedContent: pinned.content,
            pinnedRecord: pinned.record,
            directoryID: directoryID,
            collectionID: collectionID,
            fileID: fileID,
            collectionURL: collectionURL,
            pendingSelection: pendingSelection,
            expectedOriginalContent: expectedOriginalContent,
            expectedOriginalInspector: expectedOriginalInspector,
        )
    }

    private static func relativeDirectoryReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "relative-directory"),
            anchor: .directory(path: "relative"),
        )
    }

    private static func relativeSelectionReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "relative-selection"),
            anchor: .directory(path: "/tmp"),
            pendingSelectEntryID: "relative.txt",
        )
    }

    private static func foreignSelectionReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "foreign-selection"),
            anchor: .directory(path: "/tmp"),
            pendingSelectEntryID: "/other/report.txt",
        )
    }

    private static func collectionSelectionReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "collection-selection"),
            anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/a.voycoll")),
            pendingSelectEntryID: "/tmp/a.voycoll",
        )
    }

    private static func duplicateReservationSet() -> [ExternalContentTabReservation] {
        let id = ContentTabID(rawValue: "duplicate")
        return [
            ExternalContentTabReservation(id: id, anchor: .directory(path: "/one")),
            ExternalContentTabReservation(id: id, anchor: .directory(path: "/two")),
        ]
    }

    private static func overCapacityReservationSet() -> [ExternalContentTabReservation] {
        (0 ..< ContentTabConstants.maxTabs).map {
            ExternalContentTabReservation(
                id: ContentTabID(rawValue: "capacity-\($0)"),
                anchor: .directory(path: "/capacity/\($0)"),
            )
        }
    }

    private static func makePinnedTabState() -> PinnedState {
        let id = ContentTabID(rawValue: "existing-pinned")
        let tab = ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: "/pinned"),
            isPinned: true,
            title: "Pinned",
            iconName: "pin",
        )
        var content = FileManagerContentState.initialContent(for: tab.anchor)
        content.pendingSelectEntryID = "/pinned/keep.txt"
        let record = ContentTabPinnedRecord(
            id: id.rawValue,
            page: tab.page,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
            pinnedAt: Date(timeIntervalSince1970: 100),
        )
        return PinnedState(id: id, tab: tab, content: content, record: record)
    }
}
