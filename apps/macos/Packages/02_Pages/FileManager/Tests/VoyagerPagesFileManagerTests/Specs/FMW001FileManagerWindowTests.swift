import AppKit
import ComposableArchitecture
import Foundation
import PerceptionCore
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

private actor FMW001SearchCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var wasCancelled = false

    func wait() async throws -> SearchResponsePayload {
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let waiters = startWaiters
                startWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            throw CancellationError()
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func cancellationObserved() -> Bool {
        wasCancelled
    }

    private func cancel() {
        wasCancelled = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class FMW001FileManagerWindowTests: XCTestCase {
    private func makeStore(
        initialState: FileManagerWindowState = FileManagerWindowState(),
    ) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
        TestStore(
            initialState: initialState,
        ) {
            FileManagerWindowCommandRoutingReducer()
        }
    }

    private func makeSelectedState(
        isLoading: Bool,
        isCollectionMode: Bool,
    ) -> FileManagerWindowState {
        var state = FileManagerWindowState()
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        state.content.entryViewLayout.entryOperations.isLoading = isLoading
        state.content.entryViewLayout.isCollectionMode = isCollectionMode
        state.content.navigation.navigationState = .folder("/tmp")
        return state
    }

    private var entryCommands: [FileManagerWindowAction.WindowCommand] {
        [
            .newFolder,
            .openSelectedItem,
            .quickLookSelectedItem,
            .cut,
            .copy,
            .paste,
            .duplicate,
            .makeAlias,
            .selectAll,
            .copyAbsolutePaths,
            .copyURLs,
            .getInfo,
        ]
    }

    // MARK: - FMW-001-close_file_manager_window

    /// FMW-001-close_file_manager_window: window teardown은 모든 child operation을 정확히 한 번 terminalize한다.
    /// canonical child cleanup을 모든 content, inspector, tab snapshot, background AI owner에 적용한다.
    /// - 검증 내용: unique operation별 cancelled terminal, alias dedupe, correlation 소비, 반복 teardown과 late response no-op.
    /// - 사전 조건: accepted AiChat operation과 active Composer query/apply가 모든 합법적 window-owned 저장소에 존재한다.
    /// - 기대 결과: unique operation마다 terminal이 1회 기록되고 모든 owner state가 idle이 된다.
    func testOnDisappearTerminalizesEveryUniqueWindowOwnedChildOperationOnce() async throws {
        let aiMetrics = LockIsolated<[AiChatProductMetric]>([])
        let composerMetrics = LockIsolated<[ComposerProductMetric]>([])
        let activeTabID = try XCTUnwrap(FileManagerWindowState().contentTabs.activeTabID)
        let inactiveTabID = ContentTabID(rawValue: "teardown-inactive")
        let aiOperationIDs = (0 ..< 6).map { _ in UUID() }
        let queryOperationID = UUID()
        let applyOperationID = UUID()

        let activeAiChat = makeAcceptedAiChatState(operationID: aiOperationIDs[0], surface: .aiChatContent)
        let inspectorAiChat = makeAcceptedAiChatState(operationID: aiOperationIDs[1], surface: .aiChatInspector)
        let inactiveAiChat = makeAcceptedAiChatState(operationID: aiOperationIDs[2], surface: .aiChatContent)
        let inactiveInspectorAiChat = makeAcceptedAiChatState(
            operationID: aiOperationIDs[3],
            surface: .aiChatInspector,
        )
        let backgroundAiChat = makeAcceptedAiChatState(operationID: aiOperationIDs[4], surface: .aiChatContent)
        let backgroundInspectorAiChat = makeAcceptedAiChatState(
            operationID: aiOperationIDs[5],
            surface: .aiChatInspector,
        )

        var state = FileManagerWindowState()
        state.contentTabs.tabs.append(ContentTabItem(
            id: inactiveTabID,
            page: .directory,
            anchor: .directory(path: "/tmp/inactive"),
            isPinned: false,
            title: "Inactive",
            iconName: "folder",
        ))
        state.content.aiChat = activeAiChat.state
        state.content.composer = makeActiveComposerQuery(operationID: queryOperationID)
        state.tabContentStates[activeTabID] = state.content

        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat = inactiveAiChat.state
        inactiveContent.composer = makeActiveComposerApply(operationID: applyOperationID)
        state.tabContentStates[inactiveTabID] = inactiveContent

        state.inspector.aiChat = inspectorAiChat.state
        state.tabInspectorStates[activeTabID] = state.inspector.tabSnapshot()
        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat = inactiveInspectorAiChat.state
        state.tabInspectorStates[inactiveTabID] = inactiveInspector.tabSnapshot()

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat = backgroundAiChat.state
        let backgroundSessionID = try XCTUnwrap(backgroundAiChat.state.sessionID)
        state.backgroundAiChatStates[backgroundSessionID] = backgroundContent
        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.aiChat = backgroundInspectorAiChat.state
        let backgroundInspectorSessionID = try XCTUnwrap(backgroundInspectorAiChat.state.sessionID)
        state.backgroundInspectorAiChatStates[backgroundInspectorSessionID] = backgroundInspector

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.aiChatProductMetricsClient = AiChatProductMetricsClient { metric in
                aiMetrics.withValue { $0.append(metric) }
            }
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: { metric in
                composerMetrics.withValue { $0.append(metric) }
            })
        }
        // store.exhaustivity = .off: teardown은 기존 window close cancellation effect 전체를 함께 반환한다.
        store.exhaustivity = .off

        await store.send(.onDisappear)

        XCTAssertEqual(cancelledAiChatOperationIDs(aiMetrics.value), Set(aiOperationIDs))
        XCTAssertEqual(cancelledComposerOperationIDs(composerMetrics.value), [queryOperationID, applyOperationID])
        assertWindowChildCorrelationsConsumed(store.state)

        await store.send(.onDisappear)
        await store.send(.content(.aiChat(.executionEvent(.final(response: AiChatResponse(
            context: activeAiChat.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late"),
            completedAtMs: 1,
        ))))))
        await store.send(.content(.composer(.internal(.searchResponse(
            queryOperationID,
            .success(SearchResponsePayload(itemCount: 1)),
        )))))
        await store.finish()

        XCTAssertEqual(cancelledAiChatOperationIDs(aiMetrics.value), Set(aiOperationIDs))
        XCTAssertEqual(cancelledComposerOperationIDs(composerMetrics.value), [queryOperationID, applyOperationID])
    }

    /// FMW-001-close_file_manager_window: window teardown은 child reducer가 반환한 cancellation effect를 실행한다.
    /// reducer state 정리만으로 끝나지 않고 실제 suspended search task가 취소되는지 검증한다.
    /// - 검증 내용: onDisappear 이후 search dependency cancellation handler 실행.
    /// - 사전 조건: active content Composer에서 accepted query effect가 대기 중이다.
    /// - 기대 결과: teardown effect가 실행되어 suspended query가 취소된다.
    func testOnDisappearExecutesReturnedChildCancellationEffect() async {
        let gate = FMW001SearchCancellationGate()
        var state = FileManagerWindowState()
        state.content.composer.text = "find invoices"
        state.content.composer.scopes = ["/tmp"]
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.searchClient.search = { _ in try await gate.wait() }
        }
        // store.exhaustivity = .off: UUID 기반 query lifecycle보다 실제 cancellation handler 실행을 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.composer(.submit)))
        await gate.waitUntilStarted()
        await store.send(.onDisappear)
        await store.finish()

        let cancellationObserved = await gate.cancellationObserved()
        XCTAssertTrue(cancellationObserved)
    }

    private func makeAcceptedAiChatState(
        operationID: UUID,
        surface: AiChatProductMetricSourceSurface,
    ) -> (state: AiChatFeature.State, context: AiChatRequestContextSnapshot) {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let modelRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
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
            promptSummary: "teardown",
            submittedAtMs: 0,
        )
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: context,
            request: AiChatRequest(
                context: context,
                messages: [AiChatMessage(role: .user, content: "teardown")],
            ),
            selectedModelHandle: modelHandle,
            selectedModelRow: modelRow,
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: nil,
        )
        var state = AiChatFeature.State(sessionID: sessionID, sessionStatus: .active)
        state.executionPhase = .processing(lock)
        state.productMetricSourceSurface = surface
        withDependencies {
            $0.uuid = .constant(operationID)
        } operation: {
            _ = AiChatFeature().reduce(
                into: &state,
                action: .executionEvent(.requestPrepared(context: context)),
            )
        }
        return (state, context)
    }

    private func makeActiveComposerQuery(operationID: UUID) -> ComposerFeature.State {
        var state = ComposerFeature.State()
        state.isLoadingSearch = true
        state.activeSearchRequestID = operationID
        state.lastAcceptedSearchRequestID = operationID
        state.searchStartedAt = Date(timeIntervalSince1970: 1)
        state.queryRenderPhase = .searching
        return state
    }

    private func makeActiveComposerApply(operationID: UUID) -> ComposerFeature.State {
        var state = ComposerFeature.State()
        state.isLoadingFilters = true
        state.isFilteringInFlight = true
        state.activeFiltersRequestID = operationID
        state.lastAcceptedFiltersRequestID = operationID
        state.filtersStartedAt = Date(timeIntervalSince1970: 1)
        return state
    }

    private func cancelledAiChatOperationIDs(_ metrics: [AiChatProductMetric]) -> Set<UUID> {
        Set(metrics.compactMap { metric in
            guard case let .turnResult(operationID, _, result, _) = metric,
                  result == .cancelled
            else { return nil }
            return operationID
        })
    }

    private func cancelledComposerOperationIDs(_ metrics: [ComposerProductMetric]) -> Set<UUID> {
        Set(metrics.compactMap { metric in
            switch metric {
            case let .queryResult(operationID, result, _) where result == .cancelled:
                operationID
            case let .applyResult(operationID, result, _) where result == .cancelled:
                operationID
            default:
                nil
            }
        })
    }

    private func assertWindowChildCorrelationsConsumed(
        _ state: FileManagerWindowState,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let contentStates = [state.content] + Array(state.tabContentStates.values)
            + Array(state.backgroundAiChatStates.values)
        for content in contentStates {
            XCTAssertTrue(content.aiChat.productMetricOperations.isEmpty, file: file, line: line)
            XCTAssertEqual(content.aiChat.executionPhase, .idle, file: file, line: line)
        }
        for content in [state.content] + Array(state.tabContentStates.values) {
            XCTAssertNil(content.composer.activeSearchRequestID, file: file, line: line)
            XCTAssertNil(content.composer.activeFiltersRequestID, file: file, line: line)
        }
        let inspectorStates = [state.inspector] + Array(state.tabInspectorStates.values)
            + Array(state.backgroundInspectorAiChatStates.values)
        for inspector in inspectorStates {
            XCTAssertTrue(inspector.aiChat.productMetricOperations.isEmpty, file: file, line: line)
            XCTAssertEqual(inspector.aiChat.executionPhase, .idle, file: file, line: line)
        }
    }

    // MARK: - VOY-578-entry_commands

    // MARK: - VOY-150-context_menu_loading_capability

    /// VOY-150-context_menu_loading_capability: AppKit 빈 영역 메뉴는 loading capability를 New Folder와 Empty Trash에 적용한다.
    /// 일반 Directory loading 중 stale 메뉴 command가 실행되지 않도록 두 항목의 실제 AppKit enablement가 projection과 일치해야 한다.
    /// - 검증 내용: normal/loading 및 Trash/non-Trash configuration에서 메뉴 항목의 isEnabled 상태.
    /// - 사전 조건: ContentPaneContextMenuBuilder에 ordinary Directory와 Trash의 loading capability configuration을 각각 전달한다.
    /// - 기대 결과: ordinary Directory loading만 New Folder와 Empty Trash가 비활성화되고, normal 상태는 활성 상태를 유지한다.
    func testAppKitBlankAreaMenuAppliesLoadingCapabilityToNewFolderAndEmptyTrash() {
        assertPrimaryMenuItem(title: "New Folder", isTrashFolder: false, canPerformEntryCommands: true, isEnabled: true)
        assertPrimaryMenuItem(title: "Empty Trash", isTrashFolder: true, canPerformEntryCommands: true, isEnabled: true)
        assertPrimaryMenuItem(
            title: "New Folder",
            isTrashFolder: false,
            canPerformEntryCommands: false,
            isEnabled: false,
        )
        assertPrimaryMenuItem(
            title: "Empty Trash",
            isTrashFolder: true,
            canPerformEntryCommands: false,
            isEnabled: false,
        )
    }

    /// FMW-001-entry_commands: 빈 영역 메뉴는 loading 중 Paste와 Select All을 비활성화한다.
    /// 빈 영역 메뉴도 app menu 및 키 입력과 같은 capability projection을 사용해 stale clipboard나 selection 동작을 노출하지 않아야 한다.
    /// - 검증 내용: context menu configuration의 capability와 item count가 Paste, Select All, Sort, Group 활성 정책에 반영된다.
    /// - 사전 조건: 일반 Directory loading 중이고 clipboard에는 항목이 있으나 표시 항목은 없다.
    /// - 기대 결과: Paste, Select All, Sort, Group mutation은 모두 비활성화된다.
    func testEmptyAreaMenuUsesLoadingCapabilityForPasteAndSelectAll() {
        let configuration = ContentPaneContextMenuBuilder.Configuration(
            isTrashFolder: false,
            viewLayout: .list,
            sortKey: .name,
            sortOrder: .ascending,
            groupKey: .none,
            canPaste: true,
            itemCount: 0,
            canPerformEntryCommands: false,
        )

        XCTAssertFalse(configuration.canPasteItems)
        XCTAssertFalse(configuration.canSelectAll)
        XCTAssertFalse(configuration.canChangeSort)
        XCTAssertFalse(configuration.canChangeGroup)
    }

    /// VOY-578-entry_commands: 일반 Directory loading 중 모든 전역 entry 명령 차단
    /// stale 선택이 유지되어도 menu capability와 최종 routing이 함께 명령 실행을 막는지 검증한다.
    /// - 검증 내용: capability false 및 12개 entry command의 하위 action 미방출
    /// - 사전 조건: 일반 Directory mode, entry loading 중, stale 선택 ID 유지
    /// - 기대 결과: 모든 entry command가 no-op으로 종료
    func testOrdinaryDirectoryLoadingDisablesAndBlocksAllEntryCommands() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: false)
        XCTAssertFalse(state.menuCommandProjection.canPerformEntryCommands)
        let store = makeStore(initialState: state)

        for command in entryCommands {
            await store.send(.request(command))
        }
        await store.finish()
    }

    /// VOY-578-entry_commands: 일반 Directory 정상 상태의 전역 entry 명령 유지
    /// loading이 아닐 때 기존 entry 명령 routing이 모두 보존되는지 검증한다.
    /// - 검증 내용: capability true 및 12개 entry command의 기존 하위 action 전달
    /// - 사전 조건: 일반 Directory mode, entry loading 아님, 선택 ID 존재
    /// - 기대 결과: 모든 entry command가 대응하는 하위 reducer로 전달
    func testNormalDirectoryAllowsAllEntryCommands() async {
        var state = makeSelectedState(isLoading: false, isCollectionMode: false)
        let selectedEntry = EntryModel.temporaryFolder(id: "/tmp/selected-entry", name: "selected-entry")
        state.content.entryViewLayout.selectedIds = [selectedEntry.id]
        state.content.entryViewLayout.entryOperations.items = [selectedEntry]
        XCTAssertTrue(state.menuCommandProjection.canPerformEntryCommands)

        for command in entryCommands {
            await assertEntryCommand(command, routesFrom: state)
        }
    }

    /// VOY-578-entry_commands: Collection loading의 전역 entry 명령 정책 유지
    /// Collection loading은 ordinary Directory loading guard에 포함되지 않는지 검증한다.
    /// - 검증 내용: capability true 및 12개 entry command의 기존 하위 action 전달
    /// - 사전 조건: Collection mode, entry loading 중, 선택 ID 존재
    /// - 기대 결과: 모든 entry command가 대응하는 하위 reducer로 전달
    func testCollectionLoadingAllowsAllEntryCommands() async {
        var state = makeSelectedState(isLoading: true, isCollectionMode: true)
        let selectedEntry = EntryModel.temporaryFolder(id: "/tmp/selected-entry", name: "selected-entry")
        state.content.entryViewLayout.selectedIds = [selectedEntry.id]
        state.content.entryViewLayout.collectionItems = [selectedEntry]
        XCTAssertTrue(state.menuCommandProjection.canPerformEntryCommands)

        for command in entryCommands {
            await assertEntryCommand(command, routesFrom: state)
        }
    }

    // MARK: - FMW-001-get_info

    /// FMW-001-get_info: 선택 항목이 없으면 현재 폴더를 Get Info 대상으로 라우팅한다.
    /// App menu Get Info가 focused FileManager window의 active folder를 기존 navigation command로 전달하는지 검증한다.
    /// - 검증 내용: request(.getInfo)가 navigation.getInfoForPath delegate command를 한 번 방출한다.
    /// - 사전 조건: 일반 Directory 상태이며 선택 항목이 없고 현재 경로가 /tmp다.
    /// - 기대 결과: navigation.getInfoForPath가 한 번 수신되고 추가 action은 없다.
    func testGetInfoWithoutSelectionRoutesActiveFolderPath() async {
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .folder("/tmp")
        let store = makeStore(initialState: state)

        await store.send(.request(.getInfo))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.getInfoForPath",
                source: .menuCommand,
            )))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-get_info: stale selectedIds만 있으면 현재 폴더를 Get Info 대상으로 라우팅한다.
    /// 표시 항목과 일치하지 않는 선택 상태가 남아도 유효한 active folder fallback을 사용하는지 검증한다.
    /// - 검증 내용: stale selectedIds에서 navigation.getInfoForPath delegate command를 정확히 한 번 방출한다.
    /// - 사전 조건: /tmp folder route에 표시 entry는 있지만 선택 ID는 표시 목록에 없는 stale ID다.
    /// - 기대 결과: navigation.getInfoForPath가 한 번 수신되고 추가 action은 없다.
    func testGetInfoWithOnlyStaleSelectionRoutesActiveFolderPath() async {
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entryOperations.items = [
            EntryModel.temporaryFolder(id: "/tmp/displayed", name: "displayed"),
        ]
        state.content.entryViewLayout.selectedIds = ["/tmp/stale"]
        let store = makeStore(initialState: state)

        await store.send(.request(.getInfo))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.getInfoForPath",
                source: .menuCommand,
            )))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-get_info: expanded hierarchy의 visible child만 선택해도 selected-items Get Info를 실행한다.
    /// Entry bridge와 동일한 visible selection projection이 child entry를 selected-items 대상으로 포함하는지 검증한다.
    /// - 검증 내용: visible child 선택에서 navigation.getInfoForSelectedItems delegate command를 정확히 한 번 방출한다.
    /// - 사전 조건: list/non-collection/no-grouping 상태에서 /root/root가 expanded되고 visible child가 존재한다.
    /// - 기대 결과: navigation.getInfoForSelectedItems가 한 번 수신되고 추가 action은 없다.
    func testGetInfoWithVisibleHierarchyChildSelectionRoutesSelectedItems() async {
        let rootEntry = EntryModel.temporaryFolder(id: "/root/root", name: "root")
        let childEntry = EntryModel.temporaryFolder(id: "/root/root/child", name: "child")
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .folder("/root")
        state.content.entryViewLayout.mode = .list
        state.content.entryViewLayout.isCollectionMode = false
        state.content.entryViewLayout.entryArrangements.groupKey = .none
        state.content.entryViewLayout.entries = [rootEntry]
        state.content.entryViewLayout.entryOperations.items = [rootEntry]
        state.content.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.content.entryViewLayout.hierarchy.nodesByID[rootEntry.id] = .init(
            children: [childEntry],
            loadPhase: .loaded,
            generation: 0,
        )
        state.content.entryViewLayout.hierarchy.setExpandedIDs([rootEntry.id])
        state.content.entryViewLayout.selectedIds = [childEntry.id]
        XCTAssertTrue(state.content.entryViewLayout.hierarchyProjectionIsActive)
        XCTAssertEqual(
            state.content.entryViewLayout.visibleSelectableEntries(isNormalDirectoryPage: true).map(\.id),
            [rootEntry.id, childEntry.id],
        )
        let store = makeStore(initialState: state)

        await store.send(.request(.getInfo))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.getInfoForSelectedItems",
                source: .menuCommand,
            )))) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-get_info: root와 visible busy child를 함께 선택하면 Get Info를 실행하지 않는다.
    /// 계층 projection에 포함된 child의 busy 상태가 전체 selected-items 요청을 차단하는지 검증한다.
    /// - 검증 내용: root와 busy child mixed selection에서 navigation.getInfoForSelectedItems를 방출하지 않는 no-op 경로.
    /// - 사전 조건: list/non-collection/no-grouping 상태에서 /root/root가 expanded되고 child만 busy다.
    /// - 기대 결과: Get Info delegate action 없이 종료한다.
    func testGetInfoWithVisibleHierarchyBusyChildSelectionIsNoOp() async {
        let rootEntry = EntryModel.temporaryFolder(id: "/root/root", name: "root")
        let childEntry = EntryModel.temporaryFolder(id: "/root/root/child", name: "child")
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .folder("/root")
        state.content.entryViewLayout.mode = .list
        state.content.entryViewLayout.isCollectionMode = false
        state.content.entryViewLayout.entryArrangements.groupKey = .none
        state.content.entryViewLayout.entries = [rootEntry]
        state.content.entryViewLayout.entryOperations.items = [rootEntry]
        state.content.entryViewLayout.hierarchy = .init(rootPath: "/root")
        state.content.entryViewLayout.hierarchy.nodesByID[rootEntry.id] = .init(
            children: [childEntry],
            loadPhase: .loaded,
            generation: 0,
        )
        state.content.entryViewLayout.hierarchy.setExpandedIDs([rootEntry.id])
        state.content.entryViewLayout.selectedIds = [rootEntry.id, childEntry.id]
        state.content.entryViewLayout.entryOperations.itemStates[childEntry.id] = .init(isBusy: true)
        XCTAssertTrue(state.content.entryViewLayout.hierarchyProjectionIsActive)
        XCTAssertEqual(
            state.content.entryViewLayout.visibleSelectableEntries(isNormalDirectoryPage: true).map(\.id),
            [rootEntry.id, childEntry.id],
        )
        let store = makeStore(initialState: state)

        await store.send(.request(.getInfo))
        await store.finish()
    }

    /// FMW-001-get_info: 선택 항목 중 하나라도 busy이면 Get Info를 실행하지 않는다.
    /// Entry context menu와 동일하게 mixed selection의 busy entry가 전체 Finder 정보 요청을 차단하는지 검증한다.
    /// - 검증 내용: 선택된 두 ID 중 하나가 busy일 때 request(.getInfo)가 navigation.getInfoForSelectedItems를 방출하지 않는 no-op 경로.
    /// - 사전 조건: /tmp/selected와 /tmp/busy가 선택되고 /tmp/busy의 itemStates가 busy다.
    /// - 기대 결과: navigation.getInfoForSelectedItems action 없이 종료한다.
    func testGetInfoWithAnySelectedBusyEntryIsNoOp() async {
        let selectedEntry = EntryModel.temporaryFolder(id: "/tmp/selected", name: "selected")
        let busyEntry = EntryModel.temporaryFolder(id: "/tmp/busy", name: "busy")
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entryOperations.items = [selectedEntry, busyEntry]
        state.content.entryViewLayout.selectedIds = [selectedEntry.id, busyEntry.id]
        state.content.entryViewLayout.entryOperations.itemStates[busyEntry.id] = .init(isBusy: true)
        let store = makeStore(initialState: state)

        await store.send(.request(.getInfo))
        await store.finish()
    }

    /// FMW-001-get_info: 현재 폴더가 busy이면 선택 항목 없는 Get Info를 실행하지 않는다.
    /// Entry context menu와 동일하게 current-path operation busy 상태가 Finder 정보 요청을 차단하는지 검증한다.
    /// - 검증 내용: busy current path에서 request(.getInfo)가 navigation.getInfoForPath를 방출하지 않는 no-op 경로.
    /// - 사전 조건: 선택 항목이 없고 /tmp Directory route의 itemStates["/tmp"].isBusy가 true다.
    /// - 기대 결과: navigation.getInfoForPath action 없이 종료한다.
    func testGetInfoWithoutSelectionIsNoOpWhenCurrentPathIsBusy() async {
        var state = FileManagerWindowState()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entryOperations.itemStates["/tmp"] = .init(isBusy: true)
        let store = makeStore(initialState: state)

        await store.send(.request(.getInfo))
        await store.finish()
    }

    /// FMW-001-get_info: 유효한 active folder가 없으면 무선택 Get Info를 실행하지 않는다.
    /// Home과 같은 비파일시스템 route에서 Cmd-I가 Finder 정보 effect를 만들지 않는지 검증한다.
    /// - 검증 내용: request(.getInfo)가 navigation command를 방출하지 않는 no-op 경로.
    /// - 사전 조건: focused FileManager window가 기본 Home route이고 선택 항목이 없다.
    /// - 기대 결과: 하위 navigation action 없이 종료한다.
    func testGetInfoWithoutSelectionIsNoOpOutsideActiveFolder() async {
        let store = makeStore()

        await store.send(.request(.getInfo))
        await store.finish()
    }

    /// VOY-578-entry_commands: 일반 Directory loading 중 비-entry 명령 보존
    /// entry command guard가 hidden files, undo/redo, navigation, layout, tab, composer 명령까지 막지 않는지 검증한다.
    /// - 검증 내용: undo/redo unavailable no-op, 기존 하위 action 방출, 새 tab routing 뒤 명시 selection 보존
    /// - 사전 조건: 일반 Directory mode, entry loading 중, active tab의 명시 selection/anchor 유지
    /// - 기대 결과: 명령 범주별 기존 routing을 유지하고 새 tab open이 기존 selection을 축소하지 않음
    func testOrdinaryDirectoryLoadingPreservesNonEntryCommands() async throws {
        var state = makeSelectedState(isLoading: true, isCollectionMode: false)
        state.content.entryViewLayout.entryOperations.undoRecords = [makeUndoRedoRecord("loading-undo")]
        state.content.entryViewLayout.entryOperations.redoRecords = [makeUndoRedoRecord("loading-redo")]
        let selectedTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.contentTabs.selectedTabIDs = [selectedTabID]
        state.contentTabs.selectionAnchorID = selectedTabID
        let store = makeStore(initialState: state)

        await store.send(.request(.toggleShowHiddenFiles))
        await store.receive(\.content.view.toggleShowHiddenFilesAndReload)
        await store.send(.request(.requestUndo))
        await store.send(.request(.requestRedo))
        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.send(.request(.setViewLayout(.grid)))
        await store.receive(\.content.view.changeLayout)
        await store.send(.request(.openNewContentTab(source: .contentTabBar)))
        await store.receive(\.contentTabs.open, .homeDefault)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [selectedTabID])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, selectedTabID)
        await store.send(.request(.toggleComposer))
        await store.receive(\.content.composer.view.setPresented)
        await store.finish()
    }

    // MARK: - FMW-001-toggle_sidebar

    /// FMW-001-toggle_sidebar: 사이드바 토글 명령 라우팅
    /// toggleSidebar 요청이 sidebar 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.toggleSidebar) 전송 시 sidebar.view.setSidebarVisible 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: sidebar.view.setSidebarVisible 액션 수신
    func test_sidebarToggleRequest_forwardsToSidebarReducer() async {
        let store = makeStore()

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)
        await store.finish()
    }

    /// FMW-001-toggle_sidebar: 반복 토글 멱등성
    /// 연속 toggleSidebar 요청이 매번 올바르게 sidebar 리듀서로 전달되는지 검증.
    /// - 검증 내용: 두 번 연속 toggleSidebar 전송 시 각각 setSidebarVisible 수신
    /// - 사전 조건: sidebarVisible == true 상태
    /// - 기대 결과: 두 번 모두 sidebar.view.setSidebarVisible 수신
    func test_sidebarToggleRequest_repeatedToggle_isIdempotent() async {
        var initialState = FileManagerWindowState()
        initialState.sidebar.sidebarVisible = true

        let store = makeStore(initialState: initialState)

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)
        await store.finish()
    }

    /// FMW-001-toggle_sidebar: 명령 라우팅 시 관련 없는 윈도우 상태 불변
    /// toggleSidebar 라우팅이 inspector 등 관련 없는 상태를 변경하지 않고 불변을 유지하는지 검증.
    /// - 검증 내용: toggleSidebar 전송 후 inspectorVisible 상태 보존
    /// - 사전 조건: inspectorVisible == true
    /// - 기대 결과: inspector 상태 변화 없이 setSidebarVisible만 수신
    func test_commandRouting_doesNotMutateUnrelatedWindowState_sidebarToggle() async {
        var initialState = FileManagerWindowState()
        initialState.inspector.inspectorVisible = true

        let store = makeStore(initialState: initialState)

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)
        await store.finish()
    }

    // MARK: - FMW-001-go_back

    /// FMW-001-go_back: 뒤로 가기 명령 라우팅
    /// goBack 요청이 navigation 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.goBack) 전송 시 navigation.view.goBack 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: navigation.view.goBack 액션 수신
    func test_navigationRequest_goBack_forwardsToNavigationReducer() async {
        let store = makeStore()

        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.finish()
    }

    /// FMW-001-go_back: 명령 라우팅 시 관련 없는 윈도우 상태 불변
    /// goBack 라우팅이 sidebar, inspector 등 관련 없는 상태를 변경하지 않고 불변을 유지하는지 검증.
    /// - 검증 내용: goBack 전송 후 sidebarVisible, sidebarWidth 상태 보존
    /// - 사전 조건: sidebarVisible=true, sidebarWidth=250=true
    /// - 기대 결과: 관련 없는 상태 필드 변화 없이 goBack만 수신
    func test_commandRouting_doesNotMutateUnrelatedWindowState_navigation() async {
        var initialState = FileManagerWindowState()
        initialState.sidebar.sidebarVisible = true
        initialState.sidebar.sidebarWidth = 250

        let store = makeStore(initialState: initialState)

        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.finish()
    }

    // MARK: - FMW-001-go_forward

    /// FMW-001-go_forward: 앞으로 가기 명령 라우팅
    /// goForward 요청이 navigation 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.goForward) 전송 시 navigation.view.goForward 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: navigation.view.goForward 액션 수신
    func test_navigationRequest_goForward_forwardsToNavigationReducer() async {
        let store = makeStore()

        await store.send(.request(.goForward))
        await store.receive(\.navigation.view.goForward)
        await store.finish()
    }

    // MARK: - FMW-001-go_to_enclosing_directory

    /// FMW-001-go_to_enclosing_directory: 상위 디렉토리 이동 명령 라우팅
    /// goToEnclosingDirectory 요청이 navigation 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.goToEnclosingDirectory) 전송 시 navigation.view.goToEnclosingDirectory 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: navigation.view.goToEnclosingDirectory 액션 수신
    func test_navigationRequest_goToEnclosingDirectory_forwardsToNavigationReducer() async {
        let store = makeStore()

        await store.send(.request(.goToEnclosingDirectory))
        await store.receive(\.navigation.view.goToEnclosingDirectory)
        await store.finish()
    }

    // MARK: - FMW-001-open_selected_item

    /// FMW-001-open_selected_item: 선택 항목 없을 때 openSelectedItem no-op
    /// 선택 항목이 없을 때 openSelectedItem 요청이 하위 리듀서로 전달되지 않고 no-op인지 검증.
    /// - 검증 내용: request(.openSelectedItem) 전송 후 하위 리듀서 수신 없음
    /// - 사전 조건: 기본 상태, 선택 항목 없음
    /// - 기대 결과: 하위 리듀서로의 라우팅 없이 finish
    func test_commandWithNoSelection_openSelectedItem_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.openSelectedItem))
        await store.finish()
    }

    /// FMW-001-open_selected_item: 일반 Directory loading 중 Open 비활성 및 no-op
    /// 이전 Directory 선택이 남아 있어도 새 Directory 로딩 중에는 전역 Open이 실행되지 않는지 검증한다.
    /// - 검증 내용: menu projection 비활성 및 request(.openSelectedItem) 최종 routing 차단
    /// - 사전 조건: 일반 Directory mode, entry loading 중, stale 선택 ID 유지
    /// - 기대 결과: canOpen false이고 하위 reducer action 없이 종료
    func testOrdinaryDirectoryLoadingDisablesAndBlocksOpenSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: false)
        XCTAssertFalse(state.menuCommandProjection.canOpen)
        let store = makeStore(initialState: state)

        await store.send(.request(.openSelectedItem))
        await store.finish()
    }

    /// FMW-001-open_selected_item: 일반 상태에서 Open 허용 및 routing
    /// 로딩 중이 아닌 기존 선택 항목의 전역 Open 동작이 유지되는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.openSelectedItem) 하위 routing
    /// - 사전 조건: 일반 Directory mode, entry loading 아님, 선택 ID 존재
    /// - 기대 결과: canOpen true이고 openSelectedItem command가 entry view layout으로 전달됨
    func testNormalDirectoryAllowsOpenSelectedItem() async {
        let state = makeSelectedState(isLoading: false, isCollectionMode: false)
        XCTAssertTrue(state.menuCommandProjection.canOpen)
        let store = makeStore(initialState: state)

        await store.send(.request(.openSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.openSelectedItem",
                source: .menuCommand,
            )))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-open_selected_item: Collection loading 중 Open 정책 유지
    /// Collection loading은 ordinary Directory loading 차단 정책에 포함되지 않는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.openSelectedItem) 하위 routing
    /// - 사전 조건: Collection mode, entry loading 중, 선택 ID 존재
    /// - 기대 결과: canOpen true이고 openSelectedItem command가 entry view layout으로 전달됨
    func testCollectionLoadingAllowsOpenSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: true)
        XCTAssertTrue(state.menuCommandProjection.canOpen)
        let store = makeStore(initialState: state)

        await store.send(.request(.openSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.openSelectedItem",
                source: .menuCommand,
            )))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - FMW-001-quick_look_selected_item

    /// FMW-001-quick_look_selected_item: 선택 항목 없을 때 quickLookSelectedItem no-op
    /// 선택 항목이 없을 때 quickLookSelectedItem 요청이 하위 리듀서로 전달되지 않고 no-op인지 검증.
    /// - 검증 내용: request(.quickLookSelectedItem) 전송 후 하위 리듀서 수신 없음
    /// - 사전 조건: 기본 상태, 선택 항목 없음
    /// - 기대 결과: 하위 리듀서로의 라우팅 없이 finish
    func test_commandWithNoSelection_quickLookSelectedItem_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.quickLookSelectedItem))
        await store.finish()
    }

    /// FMW-001-quick_look_selected_item: 일반 Directory loading 중 Quick Look 비활성 및 no-op
    /// 이전 Directory 선택이 남아 있어도 새 Directory 로딩 중에는 전역 Quick Look이 실행되지 않는지 검증한다.
    /// - 검증 내용: menu projection 비활성 및 request(.quickLookSelectedItem) 최종 routing 차단
    /// - 사전 조건: 일반 Directory mode, entry loading 중, stale 선택 ID 유지
    /// - 기대 결과: canQuickLook false이고 하위 reducer action 없이 종료
    func testOrdinaryDirectoryLoadingDisablesAndBlocksQuickLookSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: false)
        XCTAssertFalse(state.menuCommandProjection.canQuickLook)
        let store = makeStore(initialState: state)

        await store.send(.request(.quickLookSelectedItem))
        await store.finish()
    }

    /// FMW-001-quick_look_selected_item: 일반 상태에서 Quick Look 허용 및 routing
    /// 로딩 중이 아닌 기존 선택 항목의 전역 Quick Look 동작이 유지되는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.quickLookSelectedItem) 하위 routing
    /// - 사전 조건: 일반 Directory mode, entry loading 아님, 선택 ID 존재
    /// - 기대 결과: canQuickLook true이고 quickLookSelectedItem command가 entry view layout으로 전달됨
    func testNormalDirectoryAllowsQuickLookSelectedItem() async {
        let state = makeSelectedState(isLoading: false, isCollectionMode: false)
        XCTAssertTrue(state.menuCommandProjection.canQuickLook)
        let store = makeStore(initialState: state)

        await store.send(.request(.quickLookSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.quickLookSelectedItem",
                source: .menuCommand,
            )))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-quick_look_selected_item: Collection loading 중 Quick Look 정책 유지
    /// Collection loading은 ordinary Directory loading 차단 정책에 포함되지 않는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.quickLookSelectedItem) 하위 routing
    /// - 사전 조건: Collection mode, entry loading 중, 선택 ID 존재
    /// - 기대 결과: canQuickLook true이고 quickLookSelectedItem command가 entry view layout으로 전달됨
    func testCollectionLoadingAllowsQuickLookSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: true)
        XCTAssertTrue(state.menuCommandProjection.canQuickLook)
        let store = makeStore(initialState: state)

        await store.send(.request(.quickLookSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.quickLookSelectedItem",
                source: .menuCommand,
            )))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - FMW-001-request_undo

    /// FMW-001-request_undo: undo 명령 라우팅
    /// requestUndo 요청이 entryOperations undoRedo 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.requestUndo) 전송 시 content.entryViewLayout.entryOperations.undoRedo.requestUndo 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: undoRedo.requestUndo 액션 수신
    func test_undoRedoRequest_undo_forwardsToEntryOperations() async throws {
        let (store, activeTabID) = try makeWindowCommandStore(request: .undo)
        await store.send(.request(.requestUndo)) {
            $0.undoRedoPhase = .invoking(requestID: windowCommandRequestID, direction: .undo)
        }
        await store.receive(\.internal.undoManagerInvocationFinished) {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = .init()
        }
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeTabID)
        await store.finish()
    }

    /// FMW-001-request_undo: root availability가 없으면 undo 명령은 no-op
    /// - 검증 내용: requestUndo가 child local stack을 선택하거나 action을 전달하지 않음
    /// - 사전 조건: 기본 root availability canUndo=false
    /// - 기대 결과: shared UndoManager 호출 및 child action 없이 종료
    func test_undoRedoRequest_undoUnavailable_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.requestUndo))
        await store.finish()
    }

    /// FMW-001-request_undo: 표시 중인 Composer는 file Undo/Redo menu capability를 숨긴다.
    /// Text responder가 없는 상태에서도 Composer가 file-operation history보다 우선하는 menu projection을 검증한다.
    /// - 검증 내용: file undo/redo record가 각각 있어도 Composer 표시 중 projection의 canUndo/canRedo가 false인지 확인한다.
    /// - 사전 조건: active Content tab에 undo/redo history가 있고 Collection Filter Composer가 표시 중이다.
    /// - 기대 결과: isComposerPresented는 true이며 file Undo와 Redo menu capability는 모두 false다.
    func testComposerPresentedSuppressesFileUndoRedoMenuProjection() {
        var state = FileManagerWindowState()
        state.content.entryViewLayout.entryOperations.undoRecords = [makeUndoRedoRecord("composer-undo")]
        state.content.entryViewLayout.entryOperations.redoRecords = [makeUndoRedoRecord("composer-redo")]
        state.content.composer.isPresented = true

        let projection = state.menuCommandProjection

        XCTAssertTrue(projection.isComposerPresented)
        XCTAssertFalse(projection.canUndo)
        XCTAssertFalse(projection.canRedo)
    }

    /// FMW-001-request_undo: 표시 중인 Collection Filter Composer가 Cmd-Z 파일 작업 fallback을 차단
    /// Composer가 로컬 undo/redo 이력을 소유할 때 FileManager key-command 경계가 이를 침범하지 않는지 검증한다.
    /// - 검증 내용: handleKeyCommand(Cmd-Z)의 EntryOperations requestUndo 미방출과 Composer 이력 불변
    /// - 사전 조건: Composer가 표시 중이고 history와 redoHistory가 각각 1건 존재
    /// - 기대 결과: 하위 file-operation action 없이 기존 history와 redoHistory가 그대로 유지됨
    func testUndoKeyCommandWhenComposerPresentedBlocksEntryOperationsAndPreservesHistory() async {
        var state = FileManagerContentState()
        withDependencies {
            $0.entryLoadingClient = .testValue
            $0.searchClient = .testValue
            $0.registryClient = .testValue
        } operation: {
            _ = FileManagerContentFeature().reduce(
                into: &state,
                action: .composer(.addScope(path: "/VoyagerFixtures/Documents")),
            )
            _ = FileManagerContentFeature().reduce(
                into: &state,
                action: .composer(.addScope(path: "/VoyagerFixtures/Notes")),
            )
            _ = FileManagerContentFeature().reduce(into: &state, action: .composer(.undo))
        }
        state.composer.isPresented = true
        let history = state.composer.history
        let redoHistory = state.composer.redoHistory
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(redoHistory.count, 1)

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        }
        let command = makeUndoKeyCommand()

        await store.send(.view(.handleKeyCommand(command)))

        XCTAssertEqual(store.state.composer.history, history)
        XCTAssertEqual(store.state.composer.redoHistory, redoHistory)
        await store.finish()
    }

    /// FMW-001-request_undo: text first-responder의 local history가 비어도 file Undo로 fallback하지 않는다.
    /// 사용자가 빈 편집 이력을 가진 text field에서 Cmd-Z를 눌러도 현재 탭의 file-operation history를 소비하지 않는지 검증한다.
    /// - 검증 내용: text responder가 존재하는 동안 `handleKeyCommand(Cmd-Z)`가 EntryOperations requestUndo를 방출하지 않는다.
    /// - 사전 조건: key window의 first responder가 undo 가능한 action이 없는 NSTextView이고 Composer는 표시되지 않는다.
    /// - 기대 결과: 하위 file-operation action 없이 text responder precedence가 유지된다.
    func testUndoKeyCommandWithEmptyTextResponderHistoryDoesNotFallbackToEntryOperations() async {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.undoManager?.removeAllActions()
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)

        let command = makeUndoKeyCommand()
        let store = TestStore(initialState: FileManagerContentState()) {
            Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                guard case let .view(.handleKeyCommand(command)) = action else { return .none }
                return FileManagerContentKeyCommandHandler.effect(
                    for: command,
                    state: state,
                    textResponderIsEditing: true,
                )
            }
        }

        await store.send(.view(.handleKeyCommand(command)))
        await store.finish()
    }

    // MARK: - FMW-001-request_redo

    /// FMW-001-request_redo: redo 명령 라우팅
    /// requestRedo 요청이 entryOperations undoRedo 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.requestRedo) 전송 시 content.entryViewLayout.entryOperations.undoRedo.requestRedo 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: undoRedo.requestRedo 액션 수신
    func test_undoRedoRequest_redo_forwardsToEntryOperations() async throws {
        let (store, activeTabID) = try makeWindowCommandStore(request: .redo)
        await store.send(.request(.requestRedo)) {
            $0.undoRedoPhase = .invoking(requestID: windowCommandRequestID, direction: .redo)
        }
        await store.receive(\.internal.undoManagerInvocationFinished) {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = .init()
        }
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeTabID)
        await store.finish()
    }

    /// FMW-001-request_redo: root availability가 없으면 redo 명령은 no-op
    /// - 검증 내용: requestRedo가 child local stack을 선택하거나 action을 전달하지 않음
    /// - 사전 조건: 기본 root availability canRedo=false
    /// - 기대 결과: shared UndoManager 호출 및 child action 없이 종료
    func test_undoRedoRequest_redoUnavailable_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.requestRedo))
        await store.finish()
    }

    /// FMW-001-request_undo: Window responder는 활성 탭 registry manager를 사용하고 foreign manager와 격리된다.
    /// 활성 scope의 file-operation undo가 별도 responder history를 소비하지 않는지 검증한다.
    /// - 검증 내용: coordinator/registry manager identity, undo 적용과 redo 생성, foreign action 미호출과 history 보존
    /// - 사전 조건: 활성 탭 scope에 file-operation record를 등록하고 별도 foreign manager에 action을 등록한다.
    /// - 기대 결과: file-operation undo만 적용되어 redo가 생기고 foreign action은 undo 가능한 상태로 남는다.
    func testEntryUndoManager_isolatedFromForeignResponderAction() throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let windowID = UUID()
        let coordinator = makeCoordinator(
            windowID: windowID,
            fileOperationUndoManagerRegistry: registry,
            fileOperationUndoManagerClient: client,
        )
        let foreignUndoManager = UndoManager()
        defer {
            coordinator.close()
            registry.deactivateAll(windowID: windowID)
            foreignUndoManager.removeAllActions()
        }

        let activeTabID = try XCTUnwrap(coordinator.store.withState(\.contentTabs.activeTabID))
        let scope = UndoManagerScope(windowID: windowID, contentTabID: activeTabID.rawValue)
        let generation = try XCTUnwrap(client.generation(scope))
        let registryUndoManager = try XCTUnwrap(registry.undoManager(for: scope))
        let window = try XCTUnwrap(coordinator.window)
        let coordinatorUndoManager = try XCTUnwrap(coordinator.windowWillReturnUndoManager(window))
        XCTAssertIdentical(coordinatorUndoManager, registryUndoManager)

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/entry/old", afterPath: "/entry/new")],
        )
        XCTAssertTrue(client.registerUndo(scope, generation, record))

        let foreignTarget = ForeignUndoTarget()
        foreignUndoManager.beginUndoGrouping()
        foreignUndoManager.registerUndo(withTarget: foreignTarget) { target in
            target.invocationCount += 1
        }
        foreignUndoManager.endUndoGrouping()

        let outcome = client.performUndoRedo(scope, generation, .undo, record.id)

        XCTAssertEqual(outcome, .applied)
        XCTAssertTrue(registryUndoManager.canRedo)
        XCTAssertEqual(foreignTarget.invocationCount, 0)
        XCTAssertTrue(foreignUndoManager.canUndo)
    }

    /// FMW-001-request_undo: 등록되지 않은 Window ID의 Entry manager resolver는 fail-closed 처리한다.
    /// native key window나 first responder manager로 fallback하지 않는 factory 계약을 검증한다.
    /// - 검증 내용: undo/redo 모두 didInvoke=false이고 availability가 비어 있다.
    /// - 사전 조건: registry에 존재하지 않는 임의 Window ID와 expected target
    /// - 기대 결과: 어떤 native manager도 호출하지 않고 no-op으로 종료한다.
    func testFileManagerUndoManagerClient_missingWindowResolverIsNoOp() async {
        let client = UndoManagerClient.live(resolveUndoManager: { _ in nil })
        let missingWindowID = UUID()
        let target = UndoManagerRecordIdentity(ownerID: UUID(), recordID: UUID())

        let undoResult = await client.undo(missingWindowID, expectedTarget: target)
        let redoResult = await client.redo(missingWindowID, expectedTarget: target)
        let availability = await client.availability(missingWindowID)

        XCTAssertFalse(undoResult.didInvoke)
        XCTAssertFalse(redoResult.didInvoke)
        XCTAssertEqual(undoResult.availability, UndoManagerAvailability())
        XCTAssertEqual(redoResult.availability, UndoManagerAvailability())
        XCTAssertEqual(availability, UndoManagerAvailability())
    }

    /// FMW-001-request_undo: terminal이 invocation result보다 먼저 도착해도 late result는 무시됨
    /// - 검증 내용: invoking 중 content terminal success가 request-scoped refresh를 거쳐 뒤늦은 invocation result를 무시함
    /// - 사전 조건: undo client가 invocation result 반환 직전에 controllable gate에서 대기함
    /// - 기대 결과: terminal 직후 refreshing, matching availability 반영 후 idle, late result 수신 후에도 idle 유지
    func testUndoReplay_fastTerminalBeforeInvocationResult_ignoresLateResult() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000572"))
        let gate = FileManagerUndoInvocationGate()
        let calls = LockIsolated(0)
        let terminalAvailability = UndoManagerAvailability(canUndo: false, canRedo: true)
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/source/old", afterPath: "/source/new")],
        )
        var state = FileManagerWindowState()
        let ownerID = state.content.entryViewLayout.entryOperations.undoOwnerID
        let expectedTarget = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.syncActiveTabContentState()
        state.undoManagerAvailability = .init(
            canUndo: true,
            canRedo: false,
            undoTarget: expectedTarget,
        )
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, receivedTarget in
                XCTAssertEqual(receivedTarget, expectedTarget)
                calls.withValue { $0 += 1 }
                await gate.suspend()
                return .init(didInvoke: true, availability: terminalAvailability)
            },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            availability: { _ in terminalAvailability },
        )
        let store = TestStore(initialState: state) {
            CombineReducers {
                FileManagerWindowCommandRoutingReducer()
                FileManagerWindowRoutingReducer()
            }
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .constant(requestID)
        }

        await store.send(.request(.requestUndo)) {
            $0.undoRedoPhase = .invoking(requestID: requestID, direction: .undo)
        }
        await gate.waitUntilSuspended()
        XCTAssertFalse(store.state.menuCommandProjection.canUndo)
        XCTAssertFalse(store.state.menuCommandProjection.canRedo)

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(direction: .undo, terminal: .success(record)),
        ))))) {
            $0.undoRedoPhase = .refreshing(requestID: requestID)
        }
        await store.receive(\.internal.undoManagerReplayAvailabilityChanged) {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = terminalAvailability
        }
        await gate.resume()
        await store.receive(\.internal.undoManagerInvocationFinished)

        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(store.state.undoRedoPhase, .idle)
        XCTAssertEqual(store.state.undoManagerAvailability, terminalAvailability)
        await store.finish()
    }

    /// FMW-001-request_undo: replay availability completion은 matching request만 반영한다.
    /// - 검증 내용: stale request completion을 무시하고 matching completion에서 availability와 idle을 함께 commit한다.
    /// - 사전 조건: request-scoped refreshing phase와 서로 다른 stale requestID
    /// - 기대 결과: stale completion 상태 불변, matching completion 후 idle 및 최신 availability 반영
    func testUndoReplay_availabilityRefreshIgnoresStaleRequest() async {
        let requestID = UUID()
        let staleRequestID = UUID()
        let availability = UndoManagerAvailability(canUndo: false, canRedo: true)
        var state = FileManagerWindowState()
        state.undoRedoPhase = .refreshing(requestID: requestID)
        state.undoManagerAvailability = .init(canUndo: true, canRedo: false)
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        }

        await store.send(.internal(.undoManagerReplayAvailabilityChanged(
            requestID: staleRequestID,
            availability: .init(canUndo: true, canRedo: true),
        )))
        await store.send(.internal(.undoManagerReplayAvailabilityChanged(
            requestID: requestID,
            availability: availability,
        ))) {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = availability
        }
        await store.finish()
    }

    /// FMW-001-request_undo: owner mismatch와 busy terminal은 Window를 desynchronized로 잠금
    /// - 검증 내용: 두 ownership failure 모두 menu command와 후속 shared-manager invocation을 차단함
    /// - 사전 조건: replaying phase이며 root availability는 undo/redo 모두 true
    /// - 기대 결과: desynchronized 유지, canUndo/canRedo false, 후속 request에도 client call 0회
    func testUndoReplay_ownerMismatchAndBusy_desynchronizeAndBlockFurtherCommands() async {
        for reason in [EntryActionReplayFailureReason.ownerRecordMismatch, .ownerBusy] {
            let requestID = UUID()
            let calls = LockIsolated(0)
            let client = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in
                    calls.withValue { $0 += 1 }
                    return .init(didInvoke: true, availability: .init())
                },
                redo: { _, _ in
                    calls.withValue { $0 += 1 }
                    return .init(didInvoke: true, availability: .init())
                },
                availability: { _ in .init(canUndo: true, canRedo: true) },
            )
            var state = FileManagerWindowState()
            state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
            state.undoRedoPhase = .replaying(requestID: requestID, direction: .undo)
            let store = TestStore(initialState: state) {
                CombineReducers {
                    FileManagerWindowCommandRoutingReducer()
                    FileManagerWindowRoutingReducer()
                }
            } withDependencies: {
                $0.undoManagerClient = client
            }

            await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
                .entryActionReplayFinished(
                    direction: .undo,
                    terminal: .failure(reason: reason, appliedTargets: []),
                ),
            ))))) {
                $0.undoRedoPhase = .desynchronized
                $0.undoManagerAvailability = .init()
            }
            XCTAssertFalse(store.state.menuCommandProjection.canUndo)
            XCTAssertFalse(store.state.menuCommandProjection.canRedo)

            await store.send(.request(.requestUndo))
            await store.send(.request(.requestRedo))
            XCTAssertEqual(calls.value, 0)
            XCTAssertEqual(store.state.undoRedoPhase, .desynchronized)
            await store.finish()
        }
    }

    /// FMW-001-request_undo: missing owner와 direction mismatch event는 desynchronized로 잠금
    func testUndoManagerEvent_missingOwnerAndDirectionMismatch_desynchronize() async {
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/source/old", afterPath: "/source/new")],
        )

        var missingOwnerState = FileManagerWindowState()
        missingOwnerState.undoRedoPhase = .invoking(requestID: UUID(), direction: .undo)
        let missingOwnerStore = TestStore(initialState: missingOwnerState) {
            FileManagerWindowRoutingReducer()
        }
        await missingOwnerStore.send(.internal(.undoManagerEventReceived(.init(
            ownerID: UUID(),
            record: record,
            direction: .undo,
        )))) {
            $0.undoRedoPhase = .desynchronized
        }
        await missingOwnerStore.finish()

        var directionMismatchState = FileManagerWindowState()
        directionMismatchState.undoRedoPhase = .invoking(requestID: UUID(), direction: .undo)
        let activeOwnerID = directionMismatchState.content.entryViewLayout.entryOperations.undoOwnerID
        let directionMismatchStore = TestStore(initialState: directionMismatchState) {
            FileManagerWindowRoutingReducer()
        }
        await directionMismatchStore.send(.internal(.undoManagerEventReceived(.init(
            ownerID: activeOwnerID,
            record: record,
            direction: .redo,
        )))) {
            $0.undoRedoPhase = .desynchronized
        }
        await directionMismatchStore.finish()
    }

    /// FMW-001-request_undo: 비텍스트 Cmd-Z/Cmd-Shift-Z는 Content delegate를 거쳐 Window request로 변환된다.
    /// - 검증 내용: keyboard action이 child EntryOperations request를 직접 만들지 않고 typed delegate와 Window request를 순서대로 방출한다.
    /// - 사전 조건: native editable text responder가 없는 기본 Content 상태
    /// - 기대 결과: undo/redo 각각 requestUndoRedo delegate와 requestUndo/requestRedo Window action이 대응한다.
    func testKeyboardUndoRedo_routesThroughContentDelegateAndWindowRequest() async {
        for (modifiers, direction) in [
            (KeyModifiers.command, EntryActionDirection.undo),
            (KeyModifiers.command.union(.shift), EntryActionDirection.redo),
        ] {
            let command = KeyCommand(
                keyCode: 6,
                modifiers: modifiers,
                characters: modifiers.contains(.shift) ? "Z" : "z",
                charactersIgnoringModifiers: "z",
            )
            let contentStore = TestStore(initialState: FileManagerContentState()) {
                FileManagerContentKeyCommandReducer()
            }
            await contentStore.send(.view(.handleKeyCommand(command)))
            await contentStore.receive { action in
                guard case let .delegate(.requestUndoRedo(receivedDirection)) = action else { return false }
                return receivedDirection == direction
            }
            await contentStore.finish()

            let windowStore = makeStore()
            await windowStore.send(.content(.delegate(.requestUndoRedo(direction))))
            await windowStore.receive { action in
                switch (direction, action) {
                case (.undo, .request(.requestUndo)), (.redo, .request(.requestRedo)):
                    true
                default:
                    false
                }
            }
            await windowStore.finish()
        }
    }

    /// FMW-001-request_undo: editable text responder가 처리 가능한 Cmd-Z/Cmd-Shift-Z는 native responder가 먼저 소비한다.
    /// Menu/keyboard가 responder 전용 manager를 우선하고 Window Entry request를 만들지 않는 계약을 검증한다.
    /// - 검증 내용: direction별 native closure가 true일 때 Content delegate가 방출되지 않는다.
    /// - 사전 조건: undo/redo 가능한 editable text responder를 나타내는 deterministic native seam
    /// - 기대 결과: native undo/redo 각각 1회 호출, FileManager delegate 없음
    func testKeyboardUndoRedo_nativeEditableTextResponderHasPriority() async {
        for direction in [EntryActionDirection.undo, .redo] {
            let nativeCalls = LockIsolated(0)
            let store = TestStore(initialState: FileManagerContentState()) {
                Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                    guard case let .view(.handleKeyCommand(command)) = action else { return .none }
                    return FileManagerContentKeyCommandHandler.effect(
                        for: command,
                        state: state,
                        consumeNativeUndo: {
                            guard direction == .undo else { return false }
                            nativeCalls.withValue { $0 += 1 }
                            return true
                        },
                        consumeNativeRedo: {
                            guard direction == .redo else { return false }
                            nativeCalls.withValue { $0 += 1 }
                            return true
                        },
                    )
                }
            }
            let modifiers: KeyModifiers = direction == .undo ? .command : [.command, .shift]

            await store.send(.view(.handleKeyCommand(KeyCommand(
                keyCode: 6,
                modifiers: modifiers,
                characters: direction == .undo ? "z" : "Z",
                charactersIgnoringModifiers: "z",
            ))))
            await store.finish()

            XCTAssertEqual(nativeCalls.value, 1)
        }
    }

    /// FMW-001-request_undo: sidebar replay recovery는 dedicated owner만 회전한다.
    /// - 검증 내용: sidebar owner/history 회전과 active content owner 불변
    /// - 사전 조건: sidebar owner를 대상으로 성공한 invalidation completion
    /// - 기대 결과: sidebar에 새 owner와 빈 history, idle availability 반영
    func testUndoReplay_sidebarRecoveryRotatesOnlyDedicatedOwner() async {
        let requestID = UUID()
        let ownerID = UUID()
        let newOwnerID = UUID()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/sidebar/old", afterPath: "/sidebar/new")],
        )
        var state = FileManagerWindowState()
        state.undoRedoPhase = .recovering(requestID: requestID, direction: .undo, ownerID: ownerID)
        state.sidebarEntryDropOperations.undoOwnerID = ownerID
        state.sidebarEntryDropOperations.undoRecords = [record]
        state.sidebarEntryDropOperations.redoRecords = [record]
        let activeOperations = state.content.entryViewLayout.entryOperations
        let availability = UndoManagerAvailability(canUndo: false, canRedo: true)
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = .constant(newOwnerID)
        }

        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: ownerID,
            result: .init(succeeded: true, availability: availability),
        ))) {
            $0.sidebarEntryDropOperations.rotateUndoOwner(to: newOwnerID)
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = availability
        }

        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations, activeOperations)
        await store.finish()
    }

    /// FMW-001-request_undo: operation failure recovery는 owner invalidation 성공 때만 idle로 복귀한다.
    /// - 검증 내용: replay failure가 recovering으로 잠근 뒤 typed availability를 반영하고 stale completion은 무시한다.
    /// - 사전 조건: replaying request/owner/window와 성공 invalidation 결과
    /// - 기대 결과: 성공 completion은 idle, stale request completion은 상태 불변
    func testUndoReplay_operationFailureRecoversOnlyForMatchingInvalidation() async throws {
        let requestID = UUID()
        let staleRequestID = UUID()
        let windowID = UUID()
        let gate = FileManagerUndoInvocationGate()
        var state = FileManagerWindowState()
        state.windowID = windowID
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        state.undoRedoPhase = .replaying(requestID: requestID, direction: .undo)
        let ownerID = state.content.entryViewLayout.entryOperations.undoOwnerID
        let newOwnerID = UUID()
        let uuidCalls = LockIsolated(0)
        let replayRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/active/old", afterPath: "/active/new")],
        )
        state.content.entryViewLayout.entryOperations.undoRecords = [replayRecord]
        state.content.entryViewLayout.entryOperations.redoRecords = [replayRecord]
        state.syncActiveTabContentState()
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        let recoveredAvailability = UndoManagerAvailability(canUndo: false, canRedo: true)
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { receivedWindowID, receivedOwnerID in
                XCTAssertEqual(receivedWindowID, windowID)
                XCTAssertEqual(receivedOwnerID, ownerID)
                await gate.suspend()
                return .init(succeeded: true, availability: recoveredAvailability)
            },
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return newOwnerID
            }
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(
                direction: .undo,
                terminal: .failure(reason: .operationFailed, appliedTargets: []),
            ),
        ))))) {
            $0.undoRedoPhase = .recovering(requestID: requestID, direction: .undo, ownerID: ownerID)
            $0.undoManagerAvailability = .init()
        }
        await gate.waitUntilSuspended()
        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: staleRequestID,
            ownerID: ownerID,
            result: .init(succeeded: true, availability: .init(canUndo: true, canRedo: true)),
        )))
        XCTAssertEqual(uuidCalls.value, 0)
        await gate.resume()
        await store.receive { action in
            guard case let .internal(.undoManagerOwnerInvalidationFinished(
                receivedRequestID,
                receivedOwnerID,
                result,
            )) = action else { return false }
            return receivedRequestID == requestID
                && receivedOwnerID == ownerID
                && result == .init(succeeded: true, availability: recoveredAvailability)
        } assert: {
            $0.content.entryViewLayout.entryOperations.rotateUndoOwner(to: newOwnerID)
            $0.syncActiveTabContentState()
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = recoveredAvailability
        }
        XCTAssertEqual(uuidCalls.value, 1)
        XCTAssertEqual(
            store.state.tabContentStates[activeTabID]?.entryViewLayout.entryOperations,
            store.state.content.entryViewLayout.entryOperations,
        )
        await store.finish()
    }

    /// FMW-001-request_undo: recovery 대상 누락과 inactive owner 중복은 fail-closed 처리된다.
    /// - 검증 내용: missing/ambiguous completion이 UUID를 소비하지 않고 availability를 비움
    /// - 사전 조건: 현재 owner가 없거나 inactive cache 두 곳에 같은 owner가 존재함
    /// - 기대 결과: desynchronized, owner 불변, UUID 호출 0회
    func testUndoReplay_missingOrAmbiguousRecoveryTargetFailsClosedWithoutUUIDConsumption() async {
        let uuidCalls = LockIsolated(0)
        let missingRequestID = UUID()
        let missingOwnerID = UUID()
        var missingState = FileManagerWindowState()
        missingState.undoRedoPhase = .recovering(
            requestID: missingRequestID,
            direction: .undo,
            ownerID: missingOwnerID,
        )
        let missingStore = TestStore(initialState: missingState) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return UUID()
            }
        }

        await missingStore.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: missingRequestID,
            ownerID: missingOwnerID,
            result: .init(succeeded: true, availability: .init(canUndo: true, canRedo: true)),
        ))) {
            $0.undoRedoPhase = .desynchronized
        }
        await missingStore.finish()

        let ambiguousRequestID = UUID()
        let ambiguousOwnerID = UUID()
        let firstTabID = ContentTabID(rawValue: "ambiguous-first")
        let secondTabID = ContentTabID(rawValue: "ambiguous-second")
        var ambiguousState = FileManagerWindowState()
        ambiguousState.undoRedoPhase = .recovering(
            requestID: ambiguousRequestID,
            direction: .redo,
            ownerID: ambiguousOwnerID,
        )
        var firstContent = FileManagerContentFeature.State()
        firstContent.entryViewLayout.entryOperations.undoOwnerID = ambiguousOwnerID
        var secondContent = FileManagerContentFeature.State()
        secondContent.entryViewLayout.entryOperations.undoOwnerID = ambiguousOwnerID
        ambiguousState.tabContentStates[firstTabID] = firstContent
        ambiguousState.tabContentStates[secondTabID] = secondContent
        let ambiguousStore = TestStore(initialState: ambiguousState) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return UUID()
            }
        }

        await ambiguousStore.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: ambiguousRequestID,
            ownerID: ambiguousOwnerID,
            result: .init(succeeded: true, availability: .init(canUndo: true, canRedo: true)),
        ))) {
            $0.undoRedoPhase = .desynchronized
        }
        await ambiguousStore.finish()
        XCTAssertEqual(uuidCalls.value, 0)
    }

    /// FMW-001-request_undo: 회전된 active owner는 다음 native undo 등록에 사용된다.
    /// - 검증 내용: recovery 직후 entryActionCompleted가 새 owner로 registerUndo를 호출함
    /// - 사전 조건: active owner invalidation 성공과 deterministic replacement owner
    /// - 기대 결과: 새 owner로 1회 등록되고 local undo history에 record가 추가됨
    func testUndoReplay_activeRecoveryAllowsRegistrationWithRotatedOwner() async {
        let requestID = UUID()
        let windowID = UUID()
        let oldOwnerID = UUID()
        let newOwnerID = UUID()
        let registerOwnerIDs = LockIsolated<[UUID]>([])
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/active/old", afterPath: "/active/new")],
        )
        var state = FileManagerWindowState()
        state.windowID = windowID
        state.undoRedoPhase = .recovering(requestID: requestID, direction: .undo, ownerID: oldOwnerID)
        state.content.entryViewLayout.entryOperations.windowID = windowID
        state.content.entryViewLayout.entryOperations.undoOwnerID = oldOwnerID
        state.syncActiveTabContentState()
        let client = UndoManagerClient(
            registerUndo: { _, ownerID, _ in registerOwnerIDs.withValue { $0.append(ownerID) } },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
        )
        let store = TestStore(initialState: state) {
            CombineReducers {
                FileManagerWindowRoutingReducer()
                Scope(
                    state: \.content.entryViewLayout.entryOperations,
                    action: \.content.entryViewLayout.entryOperations,
                ) {
                    EntryOperationsFeature()
                }
            }
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .constant(newOwnerID)
        }

        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: oldOwnerID,
            result: .init(succeeded: true, availability: .init()),
        ))) {
            $0.content.entryViewLayout.entryOperations.rotateUndoOwner(to: newOwnerID)
            $0.syncActiveTabContentState()
            $0.undoRedoPhase = .idle
        }
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))) {
            $0.content.entryViewLayout.entryOperations.undoRecords = [record]
        }
        await store.receive(\.content.entryViewLayout.entryOperations.outcome.undoManagerAvailabilityChanged)
        await store.finish()

        XCTAssertEqual(registerOwnerIDs.value, [newOwnerID])
    }

    /// FMW-001-request_undo: owner invalidation 실패는 desynchronized fail-closed 상태를 유지한다.
    /// - 검증 내용: resolver/cleanup 실패 결과가 undo/redo availability를 비우고 command를 계속 잠근다.
    /// - 사전 조건: replaying operation failure와 실패 invalidation client
    /// - 기대 결과: desynchronized, canUndo/canRedo false
    func testUndoReplay_invalidationFailureDesynchronizesAndDisablesMenu() async {
        let requestID = UUID()
        let uuidCalls = LockIsolated(0)
        var state = FileManagerWindowState()
        state.windowID = UUID()
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        state.undoRedoPhase = .replaying(requestID: requestID, direction: .redo)
        let ownerID = state.content.entryViewLayout.entryOperations.undoOwnerID
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { _, _ in .init(succeeded: false, availability: .init(canUndo: true, canRedo: true)) },
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return UUID()
            }
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(
                direction: .redo,
                terminal: .failure(reason: .operationFailed, appliedTargets: []),
            ),
        ))))) {
            $0.undoRedoPhase = .recovering(requestID: requestID, direction: .redo, ownerID: ownerID)
            $0.undoManagerAvailability = .init()
        }
        await store.receive(\.internal.undoManagerOwnerInvalidationFinished) {
            $0.undoRedoPhase = .desynchronized
        }
        XCTAssertFalse(store.state.menuCommandProjection.canUndo)
        XCTAssertFalse(store.state.menuCommandProjection.canRedo)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations.undoOwnerID, ownerID)
        XCTAssertEqual(uuidCalls.value, 0)
        await store.finish()
    }

    /// FMW-001-request_undo: busy owner는 shared manager 호출을 막고 idle snapshot에서만 허용한다.
    /// sidebar, active, inactive owner 모두 같은 owner-aware preflight를 사용하는지 undo/redo 양방향으로 검증한다.
    /// - 검증 내용: busy에서는 menu disabled/client 0회/UUID 0회이고 idle에서는 expected target으로 정확히 1회 호출한다.
    /// - 사전 조건: manager top identity와 local latest record가 일치하며 동일 record target의 busy 상태만 전환한다.
    /// - 기대 결과: 여섯 owner-direction 조합 모두 busy no-op 후 idle invocation이 성립한다.
    func testUndoRedoBusyOwnerBlocksInvocationUntilIdleAcrossAllOwnerLocations() async {
        for location in UndoOwnerLocation.allCases {
            for direction in [EntryActionDirection.undo, .redo] {
                let ownerID = UUID()
                let record = EntryActionRecord(
                    operationKind: .rename,
                    targets: [.init(
                        beforePath: "/\(location.rawValue)/old",
                        afterPath: "/\(location.rawValue)/new",
                    )],
                )
                let target = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
                let calls = LockIsolated(0)
                let receivedTargets = LockIsolated<[UndoManagerRecordIdentity?]>([])
                let uuidCalls = LockIsolated(0)
                let requestID = UUID()

                let busyState = makeUndoRedoState(
                    location: location,
                    direction: direction,
                    ownerID: ownerID,
                    record: record,
                    isBusy: true,
                )
                let busyAvailability = busyState.undoManagerAvailability
                let client = UndoManagerClient(
                    registerUndo: { _, _, _ in },
                    undo: { _, receivedTarget in
                        calls.withValue { $0 += 1 }
                        receivedTargets.withValue { $0.append(receivedTarget) }
                        return .init(didInvoke: false, availability: busyAvailability)
                    },
                    redo: { _, receivedTarget in
                        calls.withValue { $0 += 1 }
                        receivedTargets.withValue { $0.append(receivedTarget) }
                        return .init(didInvoke: false, availability: busyAvailability)
                    },
                )
                let makeUUID = UUIDGenerator {
                    uuidCalls.withValue { $0 += 1 }
                    return requestID
                }
                let busyStore = makeStore(initialState: busyState)
                busyStore.dependencies.undoManagerClient = client
                busyStore.dependencies.uuid = makeUUID

                XCTAssertFalse(canInvoke(direction, projection: busyStore.state.menuCommandProjection))
                await busyStore.send(.request(command(for: direction)))
                XCTAssertEqual(busyStore.state.undoRedoPhase, .idle)
                XCTAssertEqual(calls.value, 0)
                XCTAssertEqual(uuidCalls.value, 0)
                await busyStore.finish()

                let idleState = makeUndoRedoState(
                    location: location,
                    direction: direction,
                    ownerID: ownerID,
                    record: record,
                    isBusy: false,
                )
                let idleStore = makeStore(initialState: idleState)
                idleStore.dependencies.undoManagerClient = client
                idleStore.dependencies.uuid = makeUUID

                XCTAssertTrue(canInvoke(direction, projection: idleStore.state.menuCommandProjection))
                await idleStore.send(.request(command(for: direction))) {
                    $0.undoRedoPhase = .invoking(requestID: requestID, direction: direction)
                }
                await idleStore.receive(\.internal.undoManagerInvocationFinished) {
                    $0.undoRedoPhase = .idle
                    $0.undoManagerAvailability = busyAvailability
                }
                XCTAssertEqual(calls.value, 1, location.rawValue)
                XCTAssertEqual(receivedTargets.value, [target], location.rawValue)
                XCTAssertEqual(uuidCalls.value, 1, location.rawValue)
                await idleStore.finish()
            }
        }
    }

    /// FMW-001-request_undo: 검증 불가능한 top identity는 fail-closed no-op 처리한다.
    /// native availability가 true여도 owner/record를 유일하게 증명하지 못하면 Window가 호출하지 않는지 검증한다.
    /// - 검증 내용: unknown, missing, duplicate, record mismatch에서 menu disabled/client 0회/UUID 0회이다.
    /// - 사전 조건: undo와 redo 각각 manager target metadata 또는 local owner 구성이 불완전하다.
    /// - 기대 결과: phase는 idle을 유지하고 shared manager 호출이나 request ID 소비가 없다.
    func testUndoRedoUnknownMissingDuplicateAndMismatchFailClosedWithoutInvocation() async {
        for direction in [EntryActionDirection.undo, .redo] {
            let ownerID = UUID()
            let record = EntryActionRecord(
                operationKind: .rename,
                targets: [.init(beforePath: "/validation/old", afterPath: "/validation/new")],
            )
            let baseState = makeUndoRedoState(
                location: .active,
                direction: direction,
                ownerID: ownerID,
                record: record,
                isBusy: false,
            )

            var unknownState = baseState
            setManagerTarget(nil, direction: direction, state: &unknownState)

            var missingState = baseState
            setManagerTarget(
                .init(ownerID: UUID(), recordID: record.id),
                direction: direction,
                state: &missingState,
            )

            var duplicateState = baseState
            duplicateState.sidebarEntryDropOperations = duplicateState.content.entryViewLayout.entryOperations

            var mismatchState = baseState
            setManagerTarget(
                .init(ownerID: ownerID, recordID: UUID()),
                direction: direction,
                state: &mismatchState,
            )

            for (name, state) in [
                ("unknown", unknownState),
                ("missing", missingState),
                ("duplicate", duplicateState),
                ("mismatch", mismatchState),
            ] {
                let calls = LockIsolated(0)
                let uuidCalls = LockIsolated(0)
                let client = UndoManagerClient(
                    registerUndo: { _, _, _ in },
                    undo: { _, _ in
                        calls.withValue { $0 += 1 }
                        return .init(didInvoke: true, availability: .init())
                    },
                    redo: { _, _ in
                        calls.withValue { $0 += 1 }
                        return .init(didInvoke: true, availability: .init())
                    },
                )
                let store = makeStore(initialState: state)
                store.dependencies.undoManagerClient = client
                store.dependencies.uuid = UUIDGenerator {
                    uuidCalls.withValue { $0 += 1 }
                    return UUID()
                }

                XCTAssertFalse(canInvoke(direction, projection: store.state.menuCommandProjection), name)
                await store.send(.request(command(for: direction)))
                XCTAssertEqual(store.state.undoRedoPhase, .idle, name)
                XCTAssertEqual(calls.value, 0, name)
                XCTAssertEqual(uuidCalls.value, 0, name)
                await store.finish()
            }
        }
    }

    private enum UndoOwnerLocation: String, CaseIterable {
        case sidebar
        case active
        case inactive
    }

    private func makeUndoRedoState(
        location: UndoOwnerLocation,
        direction: EntryActionDirection,
        ownerID: UUID,
        record: EntryActionRecord,
        isBusy: Bool,
    ) -> FileManagerWindowState {
        var state = FileManagerWindowState()
        state.windowID = UUID()
        var operations = EntryOperationsState(undoOwnerID: ownerID)
        switch direction {
        case .undo:
            operations.undoRecords = [record]
        case .redo:
            operations.redoRecords = [record]
        }
        if let busyPath = record.targets.first?.beforePath {
            operations.itemStates[busyPath] = .init(isBusy: isBusy)
        }

        switch location {
        case .sidebar:
            state.sidebarEntryDropOperations = operations
        case .active:
            state.content.entryViewLayout.entryOperations = operations
            state.syncActiveTabContentState()
        case .inactive:
            var inactiveContent = FileManagerContentFeature.State()
            inactiveContent.entryViewLayout.entryOperations = operations
            state.tabContentStates[ContentTabID(rawValue: "owner-aware-inactive")] = inactiveContent
        }

        let target = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        setManagerTarget(target, direction: direction, state: &state)
        return state
    }

    private func setManagerTarget(
        _ target: UndoManagerRecordIdentity?,
        direction: EntryActionDirection,
        state: inout FileManagerWindowState,
    ) {
        switch direction {
        case .undo:
            state.undoManagerAvailability = .init(canUndo: true, undoTarget: target)
        case .redo:
            state.undoManagerAvailability = .init(canRedo: true, redoTarget: target)
        }
    }

    private func command(for direction: EntryActionDirection) -> FileManagerWindowAction.WindowCommand {
        direction == .undo ? .requestUndo : .requestRedo
    }

    private func canInvoke(
        _ direction: EntryActionDirection,
        projection: FileManagerWindowMenuCommandProjection,
    ) -> Bool {
        direction == .undo ? projection.canUndo : projection.canRedo
    }

    // MARK: - FMW-001-toggle_composer

    /// FMW-001-toggle_composer: 컴포저 토글 명령 라우팅
    /// toggleComposer 요청이 content.composer 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.toggleComposer) 전송 시 content.composer.view.setPresented 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: content.composer.view.setPresented 액션 수신
    func test_composerRequest_toggleComposer_forwardsToContentComposer() async {
        let store = makeStore()

        await store.send(.request(.toggleComposer))
        await store.receive(\.content.composer.view.setPresented)
        await store.finish()
    }

    // MARK: - VOY-637-transcript_search_command

    /// VOY-637-transcript_search_command: `.chat` mode의 focused AiChat이 transcript search action을 단독 처리한다.
    /// FileManager window command router가 empty New Chat에도 session/history 조건 없이 local search를 연다.
    /// - 검증 내용: `.request(.find)`가 AiChat `.transcriptSearchOpened` 하나만 방출하는지 확인
    /// - 사전 조건: inspector AiChat이 표시 중이고 mode가 `.chat`이며 transcript는 비어 있음
    /// - 기대 결과: local transcript search action 1회, composer fallback action 0회
    func testFindRequestInChatRoutesTranscriptSearchWithoutFallback() async {
        var state = FileManagerWindowState.makeInitial(path: "/Users/test/Documents")
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.mode = .chat
        let store = makeStore(initialState: state)

        await store.send(.request(.find))
        await store.receive(\.inspector.aiChat.transcriptSearchOpened)
        await store.finish()
    }

    /// VOY-637-transcript_search_command: active AiChat content tab의 `.chat` mode가 transcript search를 단독 처리한다.
    /// inspector가 표시되지 않을 때 active content-tab command route가 local search action을 전달한다.
    /// - 검증 내용: `.request(.find)`가 active tab ID의 `.tabContent(... .transcriptSearchOpened)` 하나만 방출하는지 확인
    /// - 사전 조건: active content tab anchor가 `.aiChat`이고 content AiChat mode가 `.chat`임
    /// - 기대 결과: content-tab transcript search action 1회, composer fallback action 0회
    func testFindRequestInActiveAiChatContentTabRoutesTranscriptSearchWithoutFallback() async {
        var state = FileManagerWindowState.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = state.contentTabs.activeTabID else {
            XCTFail("Expected an active content tab")
            return
        }
        state.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(
            sessionID: "00000000-0000-0000-0000-000000000637",
        )
        state.content.aiChat.mode = .chat
        let store = makeStore(initialState: state)

        await store.send(.request(.find))
        await store.receive { action in
            guard case let .tabContent(tabID: tabID, action: .aiChat(.transcriptSearchOpened)) = action else {
                return false
            }
            return tabID == activeTabID
        }
        await store.finish()
    }

    /// VOY-637-transcript_search_command: `.sessions` mode의 AiChat은 기존 Collection Filter Composer로 fallback한다.
    /// transcript가 표시되지 않는 session list에서는 FileManager의 기존 composer route를 그대로 재사용한다.
    /// - 검증 내용: `.request(.find)`가 `.request(.toggleComposer)`와 composer presentation action을 각 1회 방출
    /// - 사전 조건: inspector AiChat이 표시 중이고 mode가 `.sessions`임
    /// - 기대 결과: transcript open 없이 composer fallback이 정확히 한 번 실행됨
    func testFindRequestInSessionsRoutesComposerFallbackOnce() async {
        var state = FileManagerWindowState.makeInitial(path: "/Users/test/Documents")
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.mode = .sessions
        let store = makeStore(initialState: state)

        await store.send(.request(.find))
        await store.receive(\.request.toggleComposer)
        await store.receive(\.content.composer.view.setPresented)
        await store.finish()
    }

    // MARK: - FMW-001-open_new_file_manager_window

    /// FMW-001-open_new_file_manager_window: makeInitial 기본 상태의 windowID 없음
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: FileManagerWindowState.makeInitial이 entry operation windowID를 비운 상태로 시작하는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testMakeInitialCreatesStateWithoutWindowID() {
        let state = FileManagerWindowState.makeInitial(path: nil)

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: makeInitial path seed와 entry operation state 분리
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: 초기 path seed가 entry operation windowID를 오염시키지 않는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testMakeInitialSeedsPathThroughNavigationState() {
        let path = "/Users/test/Documents"
        let state = FileManagerWindowState.makeInitial(path: path)

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: FileManagerWindowState 기본 collection mode 비활성
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: 기본 window state가 collection mode와 entry operation windowID를 갖지 않는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testWindowDefaultStateHasNoCollectionMode() {
        let state = FileManagerWindowState()

        XCTAssertFalse(state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: entry operations reset 시 windowID 제거
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: content entryOperations state reset이 windowID를 제거하는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testContentEntryOperationsResetClearsWindowID() {
        let windowID = UUID()
        var state = FileManagerWindowState.makeInitial(path: nil)
        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)

        state.content.entryViewLayout.entryOperations = EntryOperationsState()
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)

        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
    }

    /// FMW-001-open_new_file_manager_window: FileManager feature 기본 navigation slice 구성
    /// FileManagerFeature.State가 별도 path seed 없이도 기본 탐색 경로와 sidebar 표시 상태를 갖는지 검증한다.
    /// - 검증 내용: content navigation 기본 경로와 sidebar visibility 확인
    /// - 사전 조건: fresh FileManagerFeature.State 생성
    /// - 기대 결과: currentPath는 Home 기본 경로이고 sidebar는 표시 상태임
    func testFeatureInitialStateContainsDefaultNavigationSlices() {
        let state = FileManagerFeature.State()

        XCTAssertEqual(state.content.navigation.currentPath, "Home")
        XCTAssertTrue(state.sidebar.sidebarVisible)
    }

    /// FMW-001-open_new_file_manager_window: onAppear 이후 기본 navigation path 보존
    /// FileManagerFeature onAppear가 초기 window 구성을 깨지 않고 기본 navigation path를 유지하는지 검증한다.
    /// - 검증 내용: onAppear 전송 후 content navigation currentPath 확인
    /// - 사전 조건: 테스트 UserDefaults/date dependency를 주입한 fresh FileManagerFeature.State
    /// - 기대 결과: currentPath가 Home 기본 경로로 유지됨
    func testFeatureOnAppearPreservesDefaultNavigationPath() async {
        let requestID = UUID()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .constant(requestID)
        }
        // 비포괄적: onAppear는 여러 초기화 child action을 방출하므로 FMW-001 초기 path 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        XCTAssertEqual(store.state.content.navigation.currentPath, "Home")
    }

    /// FMW-001-open_file_manager_window: 제공된 초기 창 크기가 저장된 autosave frame보다 우선 적용된다.
    /// 실행 중 새 File Manager Window를 열 때 이전 autosave frame이 현재 요청 크기를 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: applyInitialFrame이 initialWindowSizeProvider 값을 window frame에 적용하는지 확인
    /// - 사전 조건: NSWindow autosave frame이 저장되어 있고 initialWindowSizeProvider가 1180x720을 반환
    /// - 기대 결과: window.frame 크기가 1180x720으로 설정됨
    func testApplyInitialFramePrefersProvidedWindowSizeOverAutosave() {
        let autosaveName = FileManagerWindowChrome.frameAutosaveName
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let storedWindow = NSWindow(contentViewController: NSViewController())
        storedWindow.setFrame(NSRect(x: 0, y: 0, width: 960, height: 510), display: false)
        storedWindow.saveFrame(usingName: autosaveName)

        let window = NSWindow(contentViewController: NSViewController())
        FileManagerWindowChrome.configureWindowStyle(window)

        FileManagerWindowChrome.applyInitialFrame(
            window,
            initialWindowSizeProvider: { NSSize(width: 1180, height: 720) },
            reservesSidebarWidth: false,
        )

        XCTAssertEqual(window.frame.width, 1180, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, 720, accuracy: 0.5)
    }

    private func assertEntryCommand(
        _ command: FileManagerWindowAction.WindowCommand,
        routesFrom state: FileManagerWindowState,
    ) async {
        let store = makeStore(initialState: state)

        await store.send(.request(command))
        await store.receive { action in
            matchesEntryCommandAction(command, action) || matchesAdditionalEntryCommandAction(command, action)
        }
        await store.finish()
    }

    private func assertPrimaryMenuItem(
        title: String,
        isTrashFolder: Bool,
        canPerformEntryCommands: Bool,
        isEnabled: Bool,
    ) {
        let configuration = ContentPaneContextMenuBuilder.Configuration(
            isTrashFolder: isTrashFolder,
            viewLayout: .list,
            sortKey: .name,
            sortOrder: .ascending,
            groupKey: .none,
            canPaste: true,
            itemCount: 1,
            canPerformEntryCommands: canPerformEntryCommands,
        )
        let item = ContentPaneContextMenuBuilder.makePrimaryMenuItem(configuration: configuration, target: self)

        XCTAssertEqual(item.title, title)
        XCTAssertEqual(item.isEnabled, isEnabled)
    }

    private func matchesEntryCommandAction(
        _ command: FileManagerWindowAction.WindowCommand,
        _ action: FileManagerWindowAction,
    ) -> Bool {
        switch (command, action) {
        case (
            .newFolder,
            .content(.entryViewLayout(.delegate(.executeCommand("mutation.createNewFolder", source: .menuCommand)))),
        ),
        (
            .openSelectedItem,
            .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.openSelectedItem",
                source: .menuCommand,
            )))),
        ),
        (
            .quickLookSelectedItem,
            .content(.entryViewLayout(.delegate(.executeCommand(
                "navigation.quickLookSelectedItem",
                source: .menuCommand,
            )))),
        ),
        (.cut, .content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.cutSelectedItems",
            source: .menuCommand,
        ))))),
        (.copy, .content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.copySelectedItems",
            source: .menuCommand,
        ))))),
        (.paste, .content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.pasteItems",
            source: .menuCommand,
        ))))):
            true

        default:
            false
        }
    }

    private func matchesAdditionalEntryCommandAction(
        _ command: FileManagerWindowAction.WindowCommand,
        _ action: FileManagerWindowAction,
    ) -> Bool {
        switch (command, action) {
        case (.duplicate, .content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.duplicateSelectedItems",
            source: .menuCommand,
        ))))),
        (
            .makeAlias,
            .content(.entryViewLayout(.delegate(.executeCommand(
                "mutation.createAliasForSelectedItems",
                source: .menuCommand,
            )))),
        ),
        (.selectAll, .content(.view(.selectAllEntries))),
        (
            .copyAbsolutePaths,
            .content(.entryViewLayout(.delegate(.executeCommand(
                "clipboard.copySelectedAbsolutePaths",
                source: .menuCommand,
            )))),
        ),
        (.copyURLs, .content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.copySelectedURLs",
            source: .menuCommand,
        ))))),
        (.getInfo, .content(.entryViewLayout(.delegate(.executeCommand(
            "navigation.getInfoForSelectedItems",
            source: .menuCommand,
        ))))):
            true

        default:
            false
        }
    }

    /// FMW-001-open_file_manager_window: provider가 없으면 저장된 autosave frame을 복원한다.
    /// 앱 재실행 후 첫 File Manager Window가 이전에 저장한 창 크기를 복원하는지 검증한다.
    /// - 검증 내용: applyInitialFrame이 provider nil 상태에서 autosave frame을 window frame으로 복원하는지 확인
    /// - 사전 조건: NSWindow autosave frame이 1240x760으로 저장되어 있고 initialWindowSizeProvider는 nil
    /// - 기대 결과: window.frame 크기가 1240x760으로 설정됨
    func testApplyInitialFrameRestoresAutosavedFrameWhenProviderMissing() {
        let autosaveName = FileManagerWindowChrome.frameAutosaveName
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let storedWindow = NSWindow(contentViewController: NSViewController())
        storedWindow.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 760), display: false)
        FileManagerWindowChrome.saveFrame(storedWindow)

        let window = NSWindow(contentViewController: NSViewController())
        FileManagerWindowChrome.configureWindowStyle(window)

        FileManagerWindowChrome.applyInitialFrame(
            window,
            initialWindowSizeProvider: nil,
            reservesSidebarWidth: false,
        )

        XCTAssertEqual(window.frame.width, 1240, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, 760, accuracy: 0.5)
    }

    private func makeCoordinator(
        windowID: UUID,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        fileOperationUndoManagerClient: FileOperationUndoManagerClient,
    ) -> FileManagerWindowCoordinator {
        let store = Store(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileOperationUndoManagerClient = fileOperationUndoManagerClient
        }
        return FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            makeContentViewController: { _, _ in NSViewController() },
        )
    }

    // MARK: - EVM-001-view_current_page_title

    /// EVM-001-view_current_page_title: Home 초기 상태의 창 제목은 "Home"
    /// legacy defaultTabPath 페이로드가 유지되더라도 초기 route(.home)에 바인딩된 창 제목은 "Home"이어야 한다.
    /// - 검증 내용: makeInitial(path: nil) 상태에서 navigationState == .home, titlePath == "Home", makeTitle 결과 == "Home"
    /// - 사전 조건: path 없이 생성한 FileManagerWindowState
    /// - 기대 결과: 창 제목 계산 결과가 legacy 홈 디렉터리 경로가 아닌 "Home"
    func testWindowTitleForHomeInitialStateShowsHome() {
        let state = FileManagerWindowState.makeInitial(path: nil)

        XCTAssertEqual(state.content.navigation.navigationState, .home)
        XCTAssertEqual(state.content.navigation.titlePath, "Home")

        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: nil,
            isCollectionMode: false,
            titlePath: state.content.navigation.titlePath,
            makeWindowTitle: { $0 },
        )
        XCTAssertEqual(title, "Home")
    }

    /// EVM-001-view_current_page_title: Directory seed 상태의 창 제목은 경로 유지
    /// seedInitialFolderPath로 시작한 Directory route의 창 제목은 해당 경로 그대로여야 한다.
    /// - 검증 내용: makeInitial(path:) 상태에서 titlePath와 makeTitle 결과가 시드 경로와 일치
    /// - 사전 조건: path "/tmp/voyager-directory"로 생성한 FileManagerWindowState
    /// - 기대 결과: Directory route의 제목은 경로 식별자 그대로 유지
    func testWindowTitleForDirectorySeedKeepsPath() {
        let state = FileManagerWindowState.makeInitial(path: "/tmp/voyager-directory")

        XCTAssertEqual(state.content.navigation.navigationState, .folder("/tmp/voyager-directory"))
        XCTAssertEqual(state.content.navigation.titlePath, "/tmp/voyager-directory")

        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: nil,
            isCollectionMode: false,
            titlePath: state.content.navigation.titlePath,
            makeWindowTitle: { $0 },
        )
        XCTAssertEqual(title, "/tmp/voyager-directory")
    }
}

private final class ForeignUndoTarget {
    var invocationCount = 0
}

private actor FileManagerUndoInvocationGate {
    private var suspension: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspension = continuation
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard suspension == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        suspension?.resume()
        suspension = nil
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-open_file_manager_window

    /// FMW-001-open_file_manager_window: File Manager toolbar가 고정된 icon-only 표현을 유지한다.
    /// toolbar의 display mode contextual menu가 앱 전용 메뉴 뒤에 노출되지 않도록 창 스타일 계약을 검증한다.
    /// - 검증 내용: icon-only mode, 사용자 customization, configuration autosave, display mode customization 설정
    /// - 사전 조건: 새 NSWindow에 FileManagerWindowChrome 스타일 적용
    /// - 기대 결과: toolbar 표현과 customization 경로가 모두 고정됨
    func testConfigureWindowStyleDisablesToolbarDisplayModeCustomization() throws {
        let window = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.configureWindowStyle(window)

        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertEqual(toolbar.displayMode, .iconOnly)
        XCTAssertFalse(toolbar.allowsUserCustomization)
        XCTAssertFalse(toolbar.autosavesConfiguration)
        if #available(macOS 15.0, *) {
            XCTAssertFalse(toolbar.allowsDisplayModeCustomization)
        }
    }

    /// FMW-001-open_file_manager_window: Sidebar 외 배경은 기존 window movement를 유지한다.
    /// Sidebar hosting surface의 국소 override가 window 전역 이동 설정을 약화하지 않는지 검증한다.
    /// - 검증 내용: configureWindowStyle 이후 isMovableByWindowBackground true.
    /// - 사전 조건: 새 NSWindow에 FileManagerWindowChrome 스타일을 적용한다.
    /// - 기대 결과: File Manager window의 background movement가 계속 활성화된다.
    func testConfigureWindowStyleKeepsBackgroundWindowMovementEnabled() {
        let window = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.configureWindowStyle(window)

        XCTAssertTrue(window.isMovableByWindowBackground)
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-toolbar_shortcuts

    /// FMW-001-toolbar_shortcuts: New Chat toolbar context menu는 Show Chat History shortcut을 표시한다.
    /// 실제 ToolbarView를 AppKit hosting surface에 올려 context menu의 presentation metadata를 검증한다.
    /// - 검증 내용: Show Chat History NSMenuItem의 keyEquivalent와 keyEquivalentModifierMask
    /// - 사전 조건: contextual AI chat이 표시되지 않는 실제 ToolbarView와 New Chat toolbar button
    /// - 기대 결과: Show Chat History가 Cmd-Shift-L을 표시하고 다른 toolbar 동작은 변경하지 않는다.
    func testNewChatToolbarContextMenuPresentsShowChatHistoryShortcut() throws {
        let fixture = makeNewChatToolbarFixture()
        let menu = try XCTUnwrap(findHistoryMenu(in: fixture.hostingView, window: fixture.window))
        let historyItem = try XCTUnwrap(menu.items.first { $0.title == "Show Chat History" })

        XCTAssertEqual(historyItem.keyEquivalent, "l")
        XCTAssertEqual(historyItem.keyEquivalentModifierMask, [.command, .shift])
    }

    private func makeNewChatToolbarFixture() -> (
        window: NSWindow,
        hostingView: NSHostingView<AnyView>,
    ) {
        _ = NSApplication.shared
        let store = Store(initialState: FileManagerContentState()) {
            FileManagerContentFeature()
        }
        let chromeProps = FileManagerContentChromeProps(
            computerName: "Computer",
            breadcrumbRoots: FileManagerBreadcrumbRoots(homePath: NSHomeDirectory(), trashPath: nil),
            pathDisplayNames: [:],
            specialDirectoryIconNames: [:],
            isContextualAiChatPresented: false,
            activeTabID: nil,
            activePageAnchor: .directory(path: "/tmp"),
        )
        let hostingView = NSHostingView(rootView: AnyView(ToolbarView(
            store: store,
            chromeProps: chromeProps,
            onNavigationAction: { _ in },
        ).frame(width: 400, height: 40)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()
        return (window: window, hostingView: hostingView)
    }

    private func findHistoryMenu(in view: NSView, window: NSWindow) -> NSMenu? {
        if view.window != nil,
           let eventLocation = view.window.map({ _ in
               view.convert(
                   NSPoint(x: view.bounds.midX, y: view.bounds.midY),
                   to: nil,
               )
           }),
           let event = NSEvent.mouseEvent(
               with: .rightMouseDown,
               location: eventLocation,
               modifierFlags: [],
               timestamp: 0,
               windowNumber: window.windowNumber,
               context: nil,
               eventNumber: 1,
               clickCount: 1,
               pressure: 1,
           ),
           let menu = view.menu(for: event),
           menu.items.contains(where: { $0.title == "Show Chat History" })
        {
            return menu
        }

        for subview in view.subviews {
            if let menu = findHistoryMenu(in: subview, window: window) {
                return menu
            }
        }
        return nil
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-entry_commands

    /// FMW-001-entry_commands: blank-area AppKit menu container disables automatic item validation.
    /// loading capability가 false인 item을 responder chain이 다시 활성화하면 stale callback guard가 우회될 수 있다.
    /// - 검증 내용: root와 nested builder가 공유하는 container의 autoenablesItems 상태.
    /// - 사전 조건: menu item registry resource를 초기화하지 않는 bare menu container다.
    /// - 기대 결과: container가 false를 반환해 명시적 capability를 보존한다.
    func testBlankAreaMenuContainerDisablesAutomaticValidation() {
        // RED: menu containers inherited AppKit auto-enablement.
        let menu = ContentPaneContextMenuBuilder.makeMenuContainer()

        // GREEN: root and nested builders share an explicit non-auto-enabling container.
        XCTAssertFalse(menu.autoenablesItems)
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-key_command_focus

    /// FMW-001-key_command_focus: 비동기 focus 복원이 편집 중인 NSTextView를 교체하지 않는다.
    /// Inspector 등에서 직접 NSTextView를 편집하는 동안 background focus 요청이 입력 대상을 빼앗지 않는지 검증한다.
    /// - 검증 내용: requestFocus 이후 main queue drain 시 firstResponder identity
    /// - 사전 조건: editable NSTextView가 File Manager window의 first responder
    /// - 기대 결과: NSTextView가 first responder로 유지됨
    func testRequestFocusPreservesActiveEditableTextView() async {
        let keyCommandView = KeyCommandHostingView()
        let textView = NSTextView()
        textView.isEditable = true
        let window = makeFocusWindow(containing: [keyCommandView, textView])
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        coordinator.register(keyCommandView)
        XCTAssertTrue(window.makeFirstResponder(textView))

        coordinator.requestFocus()
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, textView)
    }

    /// FMW-001-key_command_focus: 비동기 focus 복원이 활성 field editor를 교체하지 않는다.
    /// NSTextField가 사용하는 field-editor NSTextView도 일반 편집 responder와 동일하게 보호되는지 검증한다.
    /// - 검증 내용: requestFocus 이후 main queue drain 시 field editor firstResponder identity
    /// - 사전 조건: isFieldEditor와 isEditable이 true인 NSTextView가 first responder
    /// - 기대 결과: field editor가 first responder로 유지됨
    func testRequestFocusPreservesActiveFieldEditorTextView() async {
        let keyCommandView = KeyCommandHostingView()
        let fieldEditor = NSTextView()
        fieldEditor.isFieldEditor = true
        fieldEditor.isEditable = true
        let window = makeFocusWindow(containing: [keyCommandView, fieldEditor])
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        coordinator.register(keyCommandView)
        XCTAssertTrue(window.makeFirstResponder(fieldEditor))

        coordinator.requestFocus()
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, fieldEditor)
    }

    /// FMW-001-key_command_focus: 비텍스트 responder에서는 key command focus를 복원한다.
    /// 텍스트 편집이 아닌 기존 responder가 있을 때 File Manager 키 명령 target 복원 동작을 보존한다.
    /// - 검증 내용: requestFocus 이후 KeyCommandHostingView로의 firstResponder 전환
    /// - 사전 조건: 다른 KeyCommandHostingView가 first responder
    /// - 기대 결과: 등록된 KeyCommandHostingView가 first responder가 됨
    func testRequestFocusReplacesNonTextResponderWithRegisteredKeyCommandView() async {
        let keyCommandView = KeyCommandHostingView()
        let nonTextResponder = KeyCommandHostingView()
        let window = makeFocusWindow(containing: [keyCommandView, nonTextResponder])
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        coordinator.register(keyCommandView)
        XCTAssertTrue(window.makeFirstResponder(nonTextResponder))

        coordinator.requestFocus()
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, keyCommandView)
    }

    /// FMW-001-key_command_focus: first responder가 없어도 key command focus를 복원한다.
    /// 텍스트 입력이 활성화되지 않은 background 상태의 기존 키 명령 복원 동작을 검증한다.
    /// - 검증 내용: nil firstResponder에서 requestFocus 이후 등록 view로의 전환
    /// - 사전 조건: window에 first responder가 없음
    /// - 기대 결과: 등록된 KeyCommandHostingView가 first responder가 됨
    func testRequestFocusRestoresRegisteredKeyCommandViewWhenResponderIsNil() async {
        let keyCommandView = KeyCommandHostingView()
        let window = makeFocusWindow(containing: [keyCommandView])
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        coordinator.register(keyCommandView)
        XCTAssertTrue(window.makeFirstResponder(nil))

        coordinator.requestFocus()
        await drainMainQueue()

        XCTAssertIdentical(window.firstResponder, keyCommandView)
    }

    /// FMW-001-key_command_focus: Quick Look 방향키는 Window view action을 거쳐 canonical selection을 갱신한다.
    /// - 검증 내용: responder-chain control begin 후 down-arrow를 전달하면 FileManager reducer가 다음 entry를 선택하고 Quick Look sync를
    /// 요청한다.
    /// - 사전 조건: 첫 entry가 선택된 focused window와 panel-control recording client
    /// - 기대 결과: begin/end가 호출되고 선택과 Quick Look sync 대상이 두 번째 entry로 이동한다.
    func testQuickLookPanelControlRoutesArrowThroughWindowViewAction() async throws {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var state = FileManagerFeature.State()
        state.isFocused = true
        state.content.navigation.seedInitialFolderPath("/root")
        state.content.entryViewLayout.entries = [first, second]
        state.content.entryViewLayout.selectedIds = [first.id]
        state.content.entryViewLayout.lastSelectedId = first.id
        state.content.entryViewLayout.rangeAnchorId = first.id
        state.syncActiveTabContentState()

        let beginCount = LockIsolated(0)
        let endCount = LockIsolated(0)
        let syncCalls = LockIsolated<[[String]]>([])
        let syncCalled = expectation(description: "Quick Look selection synchronized")
        let quickLookClient = EntryQuickLookClient(
            quickLook: { _, _ in },
            syncQuickLookSelection: { urls, _ in
                syncCalls.withValue { $0.append(urls.map(\.path)) }
                syncCalled.fulfill()
            },
            acceptsPreviewPanelControl: { true },
            beginPreviewPanelControl: { _, _ in beginCount.withValue { $0 += 1 } },
            endPreviewPanelControl: { _, _ in endCount.withValue { $0 += 1 } },
        )
        let registry = FileOperationUndoManagerRegistry()
        let undoClient = FileOperationUndoManagerClient.live(registry: registry)
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = quickLookClient
            $0.fileOperationUndoManagerClient = undoClient
        }
        let coordinator = withDependencies {
            $0.entryQuickLookClient = quickLookClient
        } operation: {
            FileManagerWindowCoordinator(
                windowID: UUID(),
                store: store,
                fileOperationUndoManagerRegistry: registry,
                makeContentViewController: { _, _ in NSViewController() },
            )
        }
        defer { coordinator.close() }
        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        let event = try makeDownArrowEvent(windowNumber: panel.windowNumber)

        XCTAssertTrue(coordinator.acceptsPreviewPanelControl(panel))
        coordinator.beginPreviewPanelControl(panel)
        XCTAssertTrue(coordinator.handleQuickLookPanelEvent(event))
        for _ in 0 ..< 100 where store.withState({ $0.content.entryViewLayout.selectedIds }) != [second.id] {
            await Task.yield()
        }
        await fulfillment(of: [syncCalled], timeout: 2)
        coordinator.endPreviewPanelControl(panel)

        XCTAssertEqual(beginCount.value, 1)
        XCTAssertEqual(endCount.value, 1)
        XCTAssertEqual(store.withState { $0.content.entryViewLayout.selectedIds }, [second.id])
        XCTAssertEqual(syncCalls.value, [[second.fullPath]])
    }

    /// FMW-001-key_command_focus: Space와 Escape는 Voyager가 삼키지 않고 Quick Look에 남긴다.
    func testQuickLookPanelEventHandlerRejectsNonArrowKeys() throws {
        let registry = FileOperationUndoManagerRegistry()
        let coordinator = makeCoordinator(
            windowID: UUID(),
            fileOperationUndoManagerRegistry: registry,
            fileOperationUndoManagerClient: .live(registry: registry),
        )
        defer { coordinator.close() }

        for keyCode in [UInt16(49), UInt16(53)] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: keyCode == 49 ? " " : "\u{1B}",
                charactersIgnoringModifiers: keyCode == 49 ? " " : "\u{1B}",
                isARepeat: false,
                keyCode: keyCode,
            ))
            XCTAssertFalse(coordinator.handleQuickLookPanelEvent(event))
        }
    }

    /// FMW-001-key_command_focus: QL이 key이고 document가 main이면 논리적 window ownership을 유지한다.
    func testQuickLookKeyTransitionRetainsLogicalDocumentFocusOnlyForMainWindow() throws {
        _ = NSApplication.shared
        let panel = try XCTUnwrap(QLPreviewPanel.shared())

        XCTAssertTrue(FileManagerWindowCoordinator.shouldRetainLogicalFocus(
            documentIsMain: true,
            keyWindow: panel,
        ))
        XCTAssertFalse(FileManagerWindowCoordinator.shouldRetainLogicalFocus(
            documentIsMain: false,
            keyWindow: panel,
        ))
        XCTAssertFalse(FileManagerWindowCoordinator.shouldRetainLogicalFocus(
            documentIsMain: true,
            keyWindow: NSWindow(),
        ))
    }

    /// FMW-001-key_command_focus: 제어 종료 후 document가 key로 돌아오지 않으면 보류된 resign을 정산한다.
    /// Quick Look이 key를 비-FileManager window에 넘기거나 앱이 비활성화되면 document는 두 번째
    /// resignKey를 받지 못하므로 panel control 종료 시점에 정산해야 한다.
    /// - 검증 내용: begin으로 logical focus를 유지한 뒤 document가 non-key인 채 control을 끝내면
    ///   `onResignedKey`가 windowID로 한 번 호출되는지 확인한다.
    /// - 사전 조건: panel-control recording client와 onResignedKey recorder를 단 coordinator
    /// - 기대 결과: endPreviewPanelControl에서 resign이 정산된다.
    func testEndPreviewPanelControlSettlesRetainedResignKeyWhenDocumentNotKeyAgain() throws {
        _ = NSApplication.shared
        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        let windowID = UUID()
        let beginCount = LockIsolated(0)
        let endCount = LockIsolated(0)
        let resignedWindowIDs = LockIsolated<[UUID]>([])
        let quickLookClient = EntryQuickLookClient(
            quickLook: { _, _ in },
            acceptsPreviewPanelControl: { true },
            beginPreviewPanelControl: { _, _ in beginCount.withValue { $0 += 1 } },
            endPreviewPanelControl: { _, _ in endCount.withValue { $0 += 1 } },
        )
        let entry = EntryModel.temporaryFolder(id: "/root/preview", name: "preview")
        var state = FileManagerFeature.State()
        state.isFocused = true
        state.content.entryViewLayout.entries = [entry]
        state.content.entryViewLayout.selectedIds = [entry.id]
        state.syncActiveTabContentState()

        let registry = FileOperationUndoManagerRegistry()
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = quickLookClient
            $0.fileOperationUndoManagerClient = .live(registry: registry)
        }
        let coordinator = withDependencies {
            $0.entryQuickLookClient = quickLookClient
        } operation: {
            FileManagerWindowCoordinator(
                windowID: windowID,
                store: store,
                fileOperationUndoManagerRegistry: registry,
                onResignedKey: { id in resignedWindowIDs.withValue { $0.append(id) } },
                makeContentViewController: { _, _ in NSViewController() },
            )
        }
        defer { coordinator.close() }

        coordinator.beginPreviewPanelControl(panel)
        coordinator.endPreviewPanelControl(panel)

        XCTAssertEqual(beginCount.value, 1)
        XCTAssertEqual(endCount.value, 1)
        XCTAssertEqual(resignedWindowIDs.value, [windowID])
    }

    /// FMW-001-key_command_focus: resign 정산은 document가 key로 돌아왔거나 유지 조건이 성립할 때 생략한다.
    func testShouldSettleRetainedResignKeyOnlyWhenDocumentNotKeyAndNotRetained() throws {
        _ = NSApplication.shared
        let panel = try XCTUnwrap(QLPreviewPanel.shared())

        XCTAssertFalse(FileManagerWindowCoordinator.shouldSettleRetainedResignKey(
            documentIsKey: true,
            documentIsMain: false,
            keyWindow: nil,
        ))
        XCTAssertFalse(FileManagerWindowCoordinator.shouldSettleRetainedResignKey(
            documentIsKey: false,
            documentIsMain: true,
            keyWindow: panel,
        ))
        XCTAssertTrue(FileManagerWindowCoordinator.shouldSettleRetainedResignKey(
            documentIsKey: false,
            documentIsMain: true,
            keyWindow: NSWindow(),
        ))
        XCTAssertTrue(FileManagerWindowCoordinator.shouldSettleRetainedResignKey(
            documentIsKey: false,
            documentIsMain: false,
            keyWindow: nil,
        ))
    }

    /// FMW-001-key_command_focus: mounted ContentPage restore가 편집 중인 NSTextView를 교체하지 않는다.
    /// selectedIds 변경으로 실제 ContentPage restore caller가 실행되어도 Inspector 텍스트 입력이 유지되는지 검증한다.
    /// - 검증 내용: mounted ContentPage의 selectedIds onChange 이후 firstResponder identity
    /// - 사전 조건: editable NSTextView가 hosting window의 first responder
    /// - 기대 결과: editable NSTextView가 first responder로 유지됨
    func testMountedContentPageRestorePreservesEditableTextView() async {
        let perceptionCheckingWasEnabled = disablePerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let fixture = await makeMountedContentPageFixture()
        let textView = NSTextView()
        textView.isEditable = true
        fixture.window.contentView?.addSubview(textView)
        XCTAssertTrue(fixture.window.makeFirstResponder(textView))

        fixture.store.send(.view(.selectAllEntries))
        await drainMountedFocusUpdates()

        XCTAssertIdentical(fixture.window.firstResponder, textView)
    }

    /// FMW-001-key_command_focus: mounted ContentPage restore가 활성 field editor를 교체하지 않는다.
    /// NSTextField 계열의 field-editor responder도 실제 selectedIds restore caller에서 보호되는지 검증한다.
    /// - 검증 내용: mounted ContentPage의 selectedIds onChange 이후 field editor firstResponder identity
    /// - 사전 조건: editable field-editor NSTextView가 hosting window의 first responder
    /// - 기대 결과: field editor가 first responder로 유지됨
    func testMountedContentPageRestorePreservesFieldEditor() async {
        let perceptionCheckingWasEnabled = disablePerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let fixture = await makeMountedContentPageFixture()
        let fieldEditor = NSTextView()
        fieldEditor.isFieldEditor = true
        fieldEditor.isEditable = true
        fixture.window.contentView?.addSubview(fieldEditor)
        XCTAssertTrue(fixture.window.makeFirstResponder(fieldEditor))

        fixture.store.send(.view(.selectAllEntries))
        await drainMountedFocusUpdates()

        XCTAssertIdentical(fixture.window.firstResponder, fieldEditor)
    }

    /// FMW-001-key_command_focus: mounted ContentPage restore가 비텍스트 responder에서 key command focus를 복원한다.
    /// selectedIds 변경으로 실행되는 실제 caller가 텍스트 편집 외 상황의 기존 키 명령 capture를 유지하는지 검증한다.
    /// - 검증 내용: mounted ContentPage의 selectedIds onChange 이후 KeyCommandHostingView firstResponder 전환
    /// - 사전 조건: 비텍스트 responder가 hosting window의 first responder
    /// - 기대 결과: ContentPage의 KeyCommandHostingView가 first responder가 됨
    func testMountedContentPageRestoreReclaimsNonTextResponder() async {
        let perceptionCheckingWasEnabled = disablePerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let fixture = await makeMountedContentPageFixture()
        let nonTextResponder = KeyCommandHostingView()
        fixture.window.contentView?.addSubview(nonTextResponder)
        XCTAssertTrue(fixture.window.makeFirstResponder(nonTextResponder))

        fixture.store.send(.view(.selectAllEntries))
        await drainMountedFocusUpdates()

        XCTAssertTrue(fixture.window.firstResponder is KeyCommandHostingView)
        XCTAssertNotIdentical(fixture.window.firstResponder, nonTextResponder)
    }

    // MARK: - FMW-001-type_scroll_mounted_content_page

    /// FMW-001-type_scroll_mounted_content_page: requestFocus가 비텍스트 responder를 등록된 KeyCommandHostingView로 교체한다.
    /// 실제 mounted ContentPage에서 list/grid를 대표하는 비텍스트 responder가 키 입력 소유자인 host로 대체되는지 검증한다.
    /// - 검증 내용: requestFocus 이후 window firstResponder가 KeyCommandHostingView인지
    /// - 사전 조건: mounted ContentPage window에 비텍스트 KeyCommandHostingView가 first responder
    /// - 기대 결과: 등록된 host가 first responder가 되고 기존 비텍스트 responder는 아님
    func testMountedContentPageRequestFocusReplacesNonTextResponderWithHost() async {
        let perceptionCheckingWasEnabled = disablePerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let fixture = await makeMountedContentPageFixture()
        let nonTextResponder = KeyCommandHostingView()
        fixture.window.contentView?.addSubview(nonTextResponder)
        XCTAssertTrue(fixture.window.makeFirstResponder(nonTextResponder))

        fixture.store.send(.view(.selectAllEntries))
        await drainMountedFocusUpdates()

        XCTAssertTrue(fixture.window.firstResponder is KeyCommandHostingView)
        XCTAssertNotIdentical(fixture.window.firstResponder, nonTextResponder)
    }

    /// FMW-001-type_scroll_mounted_content_page: requestFocus가 editable NSTextView responder를 교체하지 않는다.
    /// list/grid 스크롤과 달리 검색·이름 변경 같은 텍스트 입력은 host로 빼앗기지 않고 유지되는지 검증한다.
    /// - 검증 내용: requestFocus 이후 editable NSTextView가 first responder로 유지되는지
    /// - 사전 조건: mounted ContentPage window에 editable NSTextView가 first responder
    /// - 기대 결과: NSTextView가 first responder로 유지됨
    func testMountedContentPageRequestFocusPreservesEditableTextView() async {
        let perceptionCheckingWasEnabled = disablePerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let fixture = await makeMountedContentPageFixture()
        let textView = NSTextView()
        textView.isEditable = true
        fixture.window.contentView?.addSubview(textView)
        XCTAssertTrue(fixture.window.makeFirstResponder(textView))

        fixture.store.send(.view(.selectAllEntries))
        await drainMountedFocusUpdates()

        XCTAssertIdentical(fixture.window.firstResponder, textView)
    }

    /// FMW-001-type_scroll_mounted_content_page: mounted host의 insertText가 handleTextInput으로 라우팅돼
    /// target 단일 선택과 pending reveal을 설정한다.
    /// 실제 mounted ContentPage의 KeyCommandHostingView에 한 글자를 커밋하면 host→handleTextInput→typeScrollEffect→
    /// selectTypeScrollTarget 체인으로 selection tuple과 pendingTypeScrollTargetId가 첫 매칭 id로 설정되는지 검증한다.
    /// (list/grid 소비·reset은 위젯 테스트가 소유하므로 여기서는 host→action→state 체인만 검증한다.)
    /// - 검증 내용: host.insertText("가") 후 entryViewLayout.pendingTypeScrollTargetId와
    ///   selectedIds/lastSelectedId/rangeAnchorId가 모두 첫 매칭 id가 된다.
    /// - 사전 조건: /root 폴더 페이지에 "가나다" 엔트리가 있고 host가 first responder
    /// - 기대 결과: pending target과 selection tuple이 "가"로 시작하는 첫 엔트리 id로 설정됨
    func testMountedContentPageHostInsertTextSelectsTypeScrollTarget() async {
        let perceptionCheckingWasEnabled = disablePerceptionChecking()
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        let target = EntryModel.temporaryFolder(id: "/root/가나다", name: "가나다")
        let fixture = await makeMountedTypeScrollContentPageFixture(entries: [target])
        let nonTextResponder = KeyCommandHostingView()
        fixture.window.contentView?.addSubview(nonTextResponder)
        XCTAssertTrue(fixture.window.makeFirstResponder(nonTextResponder))

        // selectedIds 변경이 실제 requestFocus caller를 실행해 비텍스트 responder를 등록된 host로 교체한다.
        fixture.store.send(.view(.selectAllEntries))
        await drainMountedFocusUpdates()
        guard let host = fixture.window.firstResponder as? KeyCommandHostingView,
              host !== nonTextResponder
        else {
            return XCTFail("Expected registered KeyCommandHostingView as first responder")
        }

        host.insertText("가", replacementRange: NSRange(location: 0, length: 0))
        await waitForMountedTypeScrollTarget(target.id, in: fixture.store)
        XCTAssertEqual(fixture.store.state.entryViewLayout.pendingTypeScrollTargetId, target.id)
        XCTAssertEqual(fixture.store.state.entryViewLayout.selectedIds, [target.id])
        XCTAssertEqual(fixture.store.state.entryViewLayout.lastSelectedId, target.id)
        XCTAssertEqual(fixture.store.state.entryViewLayout.rangeAnchorId, target.id)
    }

    private func makeMountedTypeScrollContentPageFixture(
        entries: [EntryModel],
    ) async -> (window: NSWindow, store: Store<FileManagerContentState, FileManagerContentAction>) {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/root")
        initialState.entryViewLayout.entries = entries
        let store: Store<FileManagerContentState, FileManagerContentAction> = Store(
            initialState: initialState,
        ) {
            Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                guard case .view(.selectAllEntries) = action else { return .none }
                state.entryViewLayout.selectedIds = Set(entries.map(\.id))
                return .none
            }
            FileManagerContentKeyCommandReducer()
            Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
                EntryViewLayoutFeature()
            }
        }
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        let hostingController = NSHostingController(
            rootView: ContentPageView(store: store)
                .environment(\.fileManagerKeyCommandFocusCoordinator, coordinator),
        )
        let containerController = NSViewController()
        containerController.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        containerController.addChild(hostingController)
        hostingController.view.frame = containerController.view.bounds
        containerController.view.addSubview(hostingController.view)
        let window = NSWindow(contentViewController: containerController)
        window.makeKey()
        await drainMountedFocusUpdates()
        return (window, store)
    }

    private func waitForMountedTypeScrollTarget(
        _ expectedTargetID: EntryModel.ID,
        in store: Store<FileManagerContentState, FileManagerContentAction>,
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while store.state.entryViewLayout.pendingTypeScrollTargetId != expectedTargetID,
              clock.now < deadline
        {
            await drainMountedFocusUpdates()
            try? await clock.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(store.state.entryViewLayout.pendingTypeScrollTargetId, expectedTargetID)
    }

    private func disablePerceptionChecking() -> Bool {
        let wasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        return wasEnabled
    }

    private func makeMountedContentPageFixture() async -> (
        window: NSWindow,
        store: Store<FileManagerContentState, FileManagerContentAction>,
    ) {
        var initialState = FileManagerContentState()
        initialState.entryViewLayout.isCollectionContentLoading = true
        let store: Store<FileManagerContentState, FileManagerContentAction> = Store(
            initialState: initialState,
        ) {
            Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                guard case .view(.selectAllEntries) = action else { return .none }
                state.entryViewLayout.selectedIds = ["mounted-focus-trigger"]
                return .none
            }
        }
        let coordinator = FileManagerKeyCommandFocusCoordinator()
        let hostingController = NSHostingController(
            rootView: ContentPageView(store: store)
                .environment(\.fileManagerKeyCommandFocusCoordinator, coordinator),
        )
        let containerController = NSViewController()
        containerController.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        containerController.addChild(hostingController)
        hostingController.view.frame = containerController.view.bounds
        containerController.view.addSubview(hostingController.view)
        let window = NSWindow(contentViewController: containerController)
        window.makeKey()
        await drainMountedFocusUpdates()
        return (window, store)
    }

    private func drainMountedFocusUpdates() async {
        for _ in 0 ..< 8 {
            await drainMainQueue()
            await Task.yield()
        }
    }

    private func makeDownArrowEvent(windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: 125,
        ))
    }

    private func makeFocusWindow(containing views: [NSView]) -> NSWindow {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        for view in views {
            contentView.addSubview(view)
        }
        let window = NSWindow(contentViewController: NSViewController(nibName: nil, bundle: nil))
        window.contentView = contentView
        return window
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - VOY-619-ai_chat_command_availability

    /// VOY-619-ai_chat_command_availability: 활성 탭의 Inspector capability를 메뉴 projection에 반영한다.
    /// 메뉴가 실행 불가능한 Home/AiChat 탭에서 활성 상태로 노출되지 않도록 canonical anchor capability를 검증한다.
    /// - 검증 내용: Home/AiChat과 Directory/Collection anchor별 canUseAiChatInspector 값
    /// - 사전 조건: 동일한 active tab의 anchor를 지원·미지원 유형으로 전환
    /// - 기대 결과: Inspector 지원 anchor에서만 AiChat 메뉴 명령이 활성화됨
    func testMenuCommandProjectionReflectsActiveTabInspectorCapability() throws {
        var state = FileManagerWindowState.makeInitial(path: "/Users/test/Documents")
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)

        XCTAssertFalse(state.menuCommandProjection.isNewChatPresented)
        XCTAssertFalse(state.menuCommandProjection.isChatHistoryPresented)

        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.mode = .sessions
        XCTAssertFalse(state.menuCommandProjection.isNewChatPresented)
        XCTAssertTrue(state.menuCommandProjection.isChatHistoryPresented)

        state.inspector.aiChat.mode = .chat
        XCTAssertTrue(state.menuCommandProjection.isNewChatPresented)
        XCTAssertFalse(state.menuCommandProjection.isChatHistoryPresented)

        state.inspector.inspectorPaneExists = false
        XCTAssertFalse(state.menuCommandProjection.isNewChatPresented)
        XCTAssertFalse(state.menuCommandProjection.isChatHistoryPresented)

        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .homeDefault
        XCTAssertFalse(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(sessionID: "projection-test")
        XCTAssertFalse(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .directory(path: "/Users/test/Documents")
        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .collectionFile(
            url: URL(fileURLWithPath: "/Users/test/Test.voycoll"),
        )
        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .virtualCollection(id: "Favorite")
        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)
    }
}

private enum UndoRedoRequestKind {
    case undo
    case redo
}

private func matchesTargetedUndoRedoRequest(
    _ action: FileManagerWindowAction,
    tabID: ContentTabID,
    request: UndoRedoRequestKind,
) -> Bool {
    switch (request, action) {
    case let (.undo, .tabContent(tabID: targetID, action: .entryViewLayout(.entryOperations(.undoRedo(.requestUndo))))),
         let (.redo, .tabContent(tabID: targetID, action: .entryViewLayout(.entryOperations(.undoRedo(.requestRedo))))):
        targetID == tabID
    default:
        false
    }
}

private func makeUndoKeyCommand() -> KeyCommand {
    KeyCommand(
        keyCode: 6,
        modifiers: [.command],
        characters: "z",
        charactersIgnoringModifiers: "z",
    )
}

private let windowCommandRequestID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99))

@MainActor
private func makeWindowCommandStore(
    request: UndoRedoRequestKind,
) throws -> (
    TestStore<FileManagerWindowState, FileManagerWindowAction>,
    ContentTabID,
) {
    var state = FileManagerWindowState()
    state.windowID = UUID()
    let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
    let record = makeUndoRedoRecord(request == .undo ? "undo" : "redo")
    if request == .undo {
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.undoManagerAvailability = .init(
            canUndo: true,
            undoTarget: .init(
                ownerID: state.content.entryViewLayout.entryOperations.undoOwnerID,
                recordID: record.id,
            ),
        )
    } else {
        state.content.entryViewLayout.entryOperations.redoRecords = [record]
        state.undoManagerAvailability = .init(
            canRedo: true,
            redoTarget: .init(
                ownerID: state.content.entryViewLayout.entryOperations.undoOwnerID,
                recordID: record.id,
            ),
        )
    }
    let store = TestStore(initialState: state) {
        FileManagerWindowCommandRoutingReducer()
    } withDependencies: {
        $0.uuid = .constant(windowCommandRequestID)
        $0.undoManagerClient = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            availability: { _ in .init() },
        )
    }
    return (store, activeTabID)
}

private func makeUndoRedoRecord(_ name: String) -> EntryActionRecord {
    EntryActionRecord(
        operationKind: .rename,
        targets: [.init(beforePath: "/tmp/\(name)-old", afterPath: "/tmp/\(name)-new")],
    )
}

@MainActor
private func makeFileManagerContentStore() -> TestStore<FileManagerContentState, FileManagerContentAction> {
    TestStore(initialState: FileManagerContentState()) {
        FileManagerContentFeature()
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-move_content_tab_to_window

    /// FMW-001-move_content_tab_to_window: Move menu는 선택 동결 presentation과 semantic action wiring을 소유한다.
    /// 우클릭 메뉴를 연 시점의 선택 순서가 이후 live selection 변경과 분리되는 source wiring 계약을 검증한다.
    /// - 검증 내용: 순수 Move presentation 생성, ordered batch projection, presentation title과 frozen callback 연결
    /// - 사전 조건: package checkout의 canonical SidebarView.swift source를 읽을 수 있다.
    /// - 기대 결과: Move menu가 clicked row 기준 presentation과 ordered IDs를 사용하고 callback snapshot을 보존한다.
    func testContentTabMoveSidebarWiresFrozenMenuPresentation() throws {
        let source = try loadFMWSidebarUISources()

        XCTAssertTrue(source.contains("struct ContentTabMoveMenuPresentation"))
        XCTAssertTrue(source.contains("orderedTabIDs: movePresentation.orderedTabIDs"))
        XCTAssertTrue(source.contains("moveTitle: movePresentation.title"))
        XCTAssertTrue(source.contains("let frozenOnMove = onMove"))
    }

    /// FMW-001-move_content_tab_to_window: 선택된 clicked row는 display order의 전체 valid selection을 동결한다.
    /// 여러 Content Tab을 선택한 상태에서 selection member를 우클릭하는 menu presentation 계약을 검증한다.
    /// - 검증 내용: bulk title, clicked-row identifier, frozen ordered IDs, semantic menu batch action
    /// - 사전 조건: display order `[C, B, A]`, valid selection `{A, C}`, clicked row A와 고정 target ID가 있다.
    /// - 기대 결과: `Move 2 Tabs to Window`와 initiating A, ordered `[C, A]`가 batch view action에 보존된다.
    func testContentTabMoveMenuPresentationFreezesSelectedRowsInDisplayOrder() throws {
        let tabA = ContentTabID(rawValue: "move-menu-a")
        let tabB = ContentTabID(rawValue: "move-menu-b")
        let tabC = ContentTabID(rawValue: "move-menu-c")
        let targetWindowID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000390"),
        )
        let presentation = ContentTabMoveMenuPresentation(
            clickedTabID: tabA,
            validSelectedTabIDs: [tabA, tabC],
            displayedOrderedTabIDs: [tabC, tabB, tabA],
        )

        XCTAssertEqual(presentation.title, "Move 2 Tabs to Window")
        XCTAssertEqual(presentation.accessibilityIdentifier, ContentTabMoveProjection.menuIdentifier(tabID: tabA))
        XCTAssertEqual(presentation.orderedTabIDs, [tabC, tabA])
        guard case let .moveSelectedContentTabs(initiatingTabID, orderedTabIDs) = presentation.command else {
            return XCTFail("selected clicked row should project the semantic menu batch command")
        }
        XCTAssertEqual(initiatingTabID, tabA)
        XCTAssertEqual(orderedTabIDs, [tabC, tabA])
        guard case let .moveSelectedContentTabs(actionInitiatingID, actionOrderedIDs, actionTargetID) =
            presentation.viewAction(targetWindowID: targetWindowID)
        else {
            return XCTFail("menu batch command should map to the dedicated Sidebar view action")
        }
        XCTAssertEqual(actionInitiatingID, tabA)
        XCTAssertEqual(actionOrderedIDs, [tabC, tabA])
        XCTAssertEqual(actionTargetID, targetWindowID)
    }

    /// FMW-001-move_content_tab_to_window: selection 밖 clicked row와 단일 selection은 기존 singleton route를 유지한다.
    /// bulk selection이 있어도 다른 row를 우클릭하면 clicked row 하나만 이동하는 VOY-450 호환 계약을 검증한다.
    /// - 검증 내용: singleton title, `[clicked]` projection, 기존 `.moveContentTab` view action
    /// - 사전 조건: valid selection `{A, C}`, display order `[C, B, A]`, clicked row B와 단일 selected row A가 있다.
    /// - 기대 결과: 두 presentation 모두 `Move to Window`이며 각 clicked ID의 singleton action을 만든다.
    func testContentTabMoveMenuPresentationKeepsUnselectedAndSingleSelectionSingleton() throws {
        let tabA = ContentTabID(rawValue: "move-menu-single-a")
        let tabB = ContentTabID(rawValue: "move-menu-single-b")
        let tabC = ContentTabID(rawValue: "move-menu-single-c")
        let targetWindowID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000391"),
        )
        let presentations = [
            ContentTabMoveMenuPresentation(
                clickedTabID: tabB,
                validSelectedTabIDs: [tabA, tabC],
                displayedOrderedTabIDs: [tabC, tabB, tabA],
            ),
            ContentTabMoveMenuPresentation(
                clickedTabID: tabA,
                validSelectedTabIDs: [tabA],
                displayedOrderedTabIDs: [tabC, tabB, tabA],
            ),
        ]

        XCTAssertEqual(presentations.map(\.title), ["Move to Window", "Move to Window"])
        XCTAssertEqual(presentations.map(\.orderedTabIDs), [[tabB], [tabA]])
        for (presentation, expectedTabID) in zip(presentations, [tabB, tabA]) {
            guard case let .moveContentTab(commandTabID) = presentation.command else {
                return XCTFail("non-bulk presentation should keep the singleton command")
            }
            XCTAssertEqual(commandTabID, expectedTabID)
            guard case let .moveContentTab(actionTabID, actionTargetID) =
                presentation.viewAction(targetWindowID: targetWindowID)
            else {
                return XCTFail("singleton command should map to the existing Sidebar action")
            }
            XCTAssertEqual(actionTabID, expectedTabID)
            XCTAssertEqual(actionTargetID, targetWindowID)
        }
    }

    /// FMW-001-move_content_tab_to_window: pending batch의 모든 tab이 동일한 pending 상태로 투영된다.
    /// initiating row에만 국한하지 않고 exact request의 전체 ordered IDs가 menu/progress disable 상태를 공유하는지 검증한다.
    /// - 검증 내용: initiating 및 non-initiating tab pending true, unrelated tab과 nil request false
    /// - 사전 조건: exact ordered IDs `[A, B]`를 가진 pending batch request가 있다.
    /// - 기대 결과: A/B 모두 pending이고 C 및 pending request가 없는 경우는 pending이 아니다.
    func testContentTabMovePendingProjectionIncludesEveryBatchTab() throws {
        let tabA = ContentTabID(rawValue: "move-pending-a")
        let tabB = ContentTabID(rawValue: "move-pending-b")
        let tabC = ContentTabID(rawValue: "move-pending-c")
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000406"))
        let request = ContentTabMoveRequest(
            operationID: requestID,
            requestID: requestID,
            sourceWindowID: UUID(),
            initiatingTabID: tabA,
            orderedTabIDs: [tabA, tabB],
            targetWindowID: UUID(),
        )

        XCTAssertTrue(ContentTabMovePendingProjection.isPending(tabID: tabA, request: request))
        XCTAssertTrue(ContentTabMovePendingProjection.isPending(tabID: tabB, request: request))
        XCTAssertFalse(ContentTabMovePendingProjection.isPending(tabID: tabC, request: request))
        XCTAssertFalse(ContentTabMovePendingProjection.isPending(tabID: tabA, request: nil))
    }

    /// FMW-001-move_content_tab_to_window: menu batch action은 한 UUID로 exact request를 만들고 기존 delegate path를 탄다.
    /// drag payload 없이 clicked row와 이미 동결된 ordered IDs가 window/app atomic transaction 경계까지 유지되는지 검증한다.
    /// - 검증 내용: request operation/request identity, initiating/ordered/source/target, Sidebar와 Window delegate equality
    /// - 사전 조건: source에 A/B tab, ordered `[B, A]`, initiating A, batch capacity 2 target과 고정 UUID가 있다.
    /// - 기대 결과: 하나의 exact request가 Sidebar pending과 Window pending을 거쳐 두 delegate 계층에 동일하게 전달된다.
    func testContentTabMoveMenuBatchCreatesExactRequestAndPreservesDelegateIdentity() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000392"))
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000393"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000394"))
        let fixture = try makeContentTabMoveMenuBatchFixture(
            sourceWindowID: sourceWindowID,
            targetWindowID: targetWindowID,
            tabB: ContentTabID(rawValue: "move-menu-batch-b"),
            availableSlots: 2,
        )
        let orderedTabIDs = [fixture.tabB, fixture.tabA]
        let request = ContentTabMoveRequest(
            operationID: requestID,
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            initiatingTabID: fixture.tabA,
            orderedTabIDs: orderedTabIDs,
            targetWindowID: targetWindowID,
        )
        let store = TestStore(initialState: fixture.state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.sidebar(.view(.moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: orderedTabIDs,
            targetWindowID: targetWindowID,
        )))) {
            $0.sidebar.pendingContentTabMoveRequest = request
            $0.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
        }
        await store.receive(\.sidebar.delegate.requestContentTabMove, request) {
            $0.pendingContentTabMove?.lifecycle = .inFlight
        }
        await store.receive(\.delegate.requestContentTabMove, request)
        await store.send(.sidebar(.view(.moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: orderedTabIDs,
            targetWindowID: targetWindowID,
        ))))
    }

    /// FMW-001-move_content_tab_to_window: stale 비개시 ID 제거 후 하나만 남으면 singleton request로 축약한다.
    /// menu-open 시점의 frozen 순서는 유지하되 실행 시점 source membership만 정규화하는 계약을 검증한다.
    /// - 검증 내용: stale ID 제거, initiating identity 보존, 기존 singleton-compatible request/delegate identity
    /// - 사전 조건: frozen `[stale, A]`, 현재 source `{A, B}`, initiating A와 고정 target/UUID가 있다.
    /// - 기대 결과: exact ordered IDs `[A]`인 singleton request가 기존 pending/window/app delegate 경로로 전달된다.
    func testContentTabMoveMenuBatchCollapsesStaleSelectionToSingletonRequest() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000398"))
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000399"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000400"))
        let fixture = try makeContentTabMoveMenuBatchFixture(
            sourceWindowID: sourceWindowID,
            targetWindowID: targetWindowID,
            tabB: ContentTabID(rawValue: "move-menu-collapse-b"),
            availableSlots: 1,
        )
        let staleTabID = ContentTabID(rawValue: "move-menu-collapse-stale")
        let request = ContentTabMoveRequest(
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            tabID: fixture.tabA,
            targetWindowID: targetWindowID,
        )
        let store = TestStore(initialState: fixture.state) { FileManagerFeature() } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.sidebar(.view(.moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: [staleTabID, fixture.tabA],
            targetWindowID: targetWindowID,
        )))) {
            $0.sidebar.pendingContentTabMoveRequest = request
            $0.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
        }
        await store.receive(\.sidebar.delegate.requestContentTabMove, request) {
            $0.pendingContentTabMove?.lifecycle = .inFlight
        }
        await store.receive(\.delegate.requestContentTabMove, request)
    }

    /// FMW-001-move_content_tab_to_window: stale 비개시 ID 제거 후 둘 이상 남으면 frozen 순서의 batch를 유지한다.
    /// source membership 정규화가 surviving IDs를 재정렬하거나 live selection으로 대체하지 않는지 검증한다.
    /// - 검증 내용: middle stale ID 제거, surviving `[B, A]` 순서, initiating A, exact batch request identity
    /// - 사전 조건: frozen `[B, stale, A]`, 현재 source `{A, B}`, batch capacity 2 target과 고정 UUID가 있다.
    /// - 기대 결과: exact ordered IDs `[B, A]`인 semantic batch request가 기존 delegate 경로로 전달된다.
    func testContentTabMoveMenuBatchDropsStaleSelectionAndPreservesSurvivingOrder() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000401"))
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000402"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000403"))
        let fixture = try makeContentTabMoveMenuBatchFixture(
            sourceWindowID: sourceWindowID,
            targetWindowID: targetWindowID,
            tabB: ContentTabID(rawValue: "move-menu-surviving-b"),
            availableSlots: 2,
        )
        let staleTabID = ContentTabID(rawValue: "move-menu-surviving-stale")
        let normalizedOrderedTabIDs = [fixture.tabB, fixture.tabA]
        let request = ContentTabMoveRequest(
            operationID: requestID,
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            initiatingTabID: fixture.tabA,
            orderedTabIDs: normalizedOrderedTabIDs,
            targetWindowID: targetWindowID,
        )
        let store = TestStore(initialState: fixture.state) { FileManagerFeature() } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.sidebar(.view(.moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: [fixture.tabB, staleTabID, fixture.tabA],
            targetWindowID: targetWindowID,
        )))) {
            $0.sidebar.pendingContentTabMoveRequest = request
            $0.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
        }
        await store.receive(\.sidebar.delegate.requestContentTabMove, request) {
            $0.pendingContentTabMove?.lifecycle = .inFlight
        }
        await store.receive(\.delegate.requestContentTabMove, request)
    }

    /// FMW-001-move_content_tab_to_window: frozen initiating tab이 source에서 사라졌으면 menu batch는 no-op이다.
    /// 비개시 surviving ID가 있어도 clicked identity가 사라진 intent를 다른 tab 이동으로 변환하지 않는지 검증한다.
    /// - 검증 내용: initiating source membership 누락 시 UUID/request/pending/delegate zero mutation
    /// - 사전 조건: frozen `[B, stale initiating]`, 현재 source `{A, B}`, target은 batch를 수용한다.
    /// - 기대 결과: surviving B가 있어도 request를 만들지 않고 state가 그대로 유지된다.
    func testContentTabMoveMenuBatchIsNoOpWhenInitiatingTabIsMissing() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000404"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000405"))
        let fixture = try makeContentTabMoveMenuBatchFixture(
            sourceWindowID: sourceWindowID,
            targetWindowID: targetWindowID,
            tabB: ContentTabID(rawValue: "move-menu-missing-b"),
            availableSlots: 2,
        )
        let missingInitiatingTabID = ContentTabID(rawValue: "move-menu-missing-initiating")
        let store = TestStore(initialState: fixture.state) { FileManagerFeature() }

        await store.send(.sidebar(.view(.moveSelectedContentTabs(
            initiatingTabID: missingInitiatingTabID,
            orderedTabIDs: [fixture.tabB, missingInitiatingTabID],
            targetWindowID: targetWindowID,
        ))))
        XCTAssertEqual(store.state, fixture.state)
    }

    /// FMW-001-move_content_tab_to_window: menu batch reducer는 malformed identity와 full-batch capacity 부족을 거부한다.
    /// reducer가 live selection을 재구성하지 않고 action에 동결된 값 자체만 검증하는 방어 계약을 확인한다.
    /// - 검증 내용: empty/duplicate/missing initiating/unknown ID/capacity 부족 action의 zero mutation과 zero delegate
    /// - 사전 조건: source A/B tab과 한 slot만 허용하는 target이 있고 pending request는 없다.
    /// - 기대 결과: 모든 invalid action 뒤 state가 동일하고 UUID/request/delegate가 생성되지 않는다.
    func testContentTabMoveMenuBatchRejectsMalformedIDsAndInsufficientCapacity() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000395"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000396"))
        let fixture = try makeContentTabMoveMenuBatchFixture(
            sourceWindowID: sourceWindowID,
            targetWindowID: targetWindowID,
            tabB: ContentTabID(rawValue: "move-menu-invalid-b"),
            availableSlots: 1,
        )
        let store = TestStore(initialState: fixture.state) { FileManagerFeature() }
        let invalidActions = contentTabMoveInvalidMenuBatchActions(
            fixture: fixture,
            targetWindowID: targetWindowID,
        )

        for action in invalidActions {
            await store.send(.sidebar(.view(action)))
            XCTAssertEqual(store.state, fixture.state)
        }
    }

    /// FMW-001-move_content_tab_to_window: native menu target은 menu 생성 당시 callback을 동결한다.
    /// menu가 열린 뒤 row update가 발생해도 이미 표시된 target action이 새로운 live selection callback으로 바뀌지 않는지 검증한다.
    /// - 검증 내용: bulk menu title/identifier, target callback snapshot, 최신 callback과의 격리
    /// - 사전 조건: clicked tab ID, 하나의 target, 첫 callback으로 만든 menu와 이후 두 번째 callback update가 있다.
    /// - 기대 결과: 기존 target item 실행은 첫 callback만 호출하고 clicked-row accessibility identifier를 유지한다.
    func testContentTabMoveNativeMenuFreezesPresentedCallback() throws {
        _ = NSApplication.shared
        let tabID = ContentTabID(rawValue: "move-menu-native")
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000397"))
        let target = ContentTabMoveTarget(
            windowID: targetWindowID,
            displayTitle: "Target",
            availableSlots: 2,
        )
        let button = ContentTabSidebarButton(frame: .zero)
        var firstCallbackIDs: [UUID] = []
        var latestCallbackIDs: [UUID] = []
        func updateButton(moveTitle: String, onMove: @escaping (UUID) -> Void) {
            button.update(configuration: .init(
                rootView: AnyView(EmptyView()),
                accessibilityLabel: "Content Tab",
                accessibilityValue: "Selected",
                tabID: tabID,
                duplicateAccessibilityIdentifier: "duplicate-content-tab-\(tabID)",
                isPinned: false,
                isEnabled: true,
                reorderDragSource: nil,
                moveTargets: [target],
                moveTitle: moveTitle,
                onActivate: {},
                onToggleSelection: {},
                onSelectRange: {},
                onDuplicate: {},
                onPin: {},
                onUnpin: {},
                onClose: {},
                onMove: onMove,
            ))
        }

        updateButton(moveTitle: "Move 2 Tabs to Window") { firstCallbackIDs.append($0) }
        let presentedMoveItem = try XCTUnwrap(button.menu?.items.last)
        let presentedTargetItem = try XCTUnwrap(presentedMoveItem.submenu?.items.first)
        XCTAssertEqual(presentedMoveItem.title, "Move 2 Tabs to Window")
        XCTAssertEqual(
            presentedMoveItem.identifier?.rawValue,
            ContentTabMoveProjection.menuIdentifier(tabID: tabID),
        )

        updateButton(moveTitle: "Move to Window") { latestCallbackIDs.append($0) }
        let action = try XCTUnwrap(presentedTargetItem.action)
        XCTAssertTrue(NSApp.sendAction(action, to: presentedTargetItem.target, from: presentedTargetItem))
        XCTAssertEqual(firstCallbackIDs, [targetWindowID])
        XCTAssertTrue(latestCallbackIDs.isEmpty)
    }

    /// FMW-001-move_content_tab_to_window: 유효한 batch 요청은 app delegate로 정확히 한 번 전달한다.
    /// 동일 request가 재생되어도 이미 시작한 transfer를 중복 위임하지 않는 lifecycle 계약을 검증한다.
    /// - 검증 내용: 최초 request delegate 1회와 duplicate request delegate 0회
    /// - 사전 조건: frozen batch identity를 가진 pending request가 source window에 있다.
    /// - 기대 결과: 최초 요청만 전달되고 재생 요청은 추가 effect 없이 종료된다.
    func testContentTabMoveRequestDelegatesExactlyOnce() async {
        let request = makeTask7ContentTabMoveRequest()
        let state = makeTask7ContentTabMoveState(request: request)
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.sidebar(.delegate(.requestContentTabMove(request)))) {
            $0.pendingContentTabMove?.lifecycle = .inFlight
        }
        await store.receive(\.delegate.requestContentTabMove, request)
        await store.send(.sidebar(.delegate(.requestContentTabMove(request))))
        await store.send(.contentTabMoveSucceeded(
            request: replacingTask7Request(request, operationID: UUID()),
        ))
        await store.send(.contentTabMoveSucceeded(request: request)) {
            $0.pendingContentTabMove = nil
            $0.sidebar.pendingContentTabMoveRequest = nil
        }
        await store.send(.contentTabMoveSucceeded(request: request))
        await store.finish()
    }

    /// FMW-001-move_content_tab_to_window: 교차 correlation 요청은 현재 pending을 변경하거나 위임하지 않는다.
    /// operation/request/source/target 중 하나만 다른 replay가 frozen request identity를 탈취하지 못하는지 검증한다.
    /// - 검증 내용: same operation/new request, same request/other operation, source/target mismatch no-op
    /// - 사전 조건: 하나의 batch request가 source window의 pending으로 준비되어 있다.
    /// - 기대 결과: 모든 foreign request 뒤에도 기존 pending이 유지되고 app delegate effect는 없다.
    func testContentTabMoveCrossCorrelatedRequestsAreNoOps() async {
        let request = makeTask7ContentTabMoveRequest()
        let state = makeTask7ContentTabMoveState(request: request)
        let store = TestStore(initialState: state) { FileManagerFeature() }
        let foreignRequests = [
            replacingTask7Request(request, requestID: UUID()),
            replacingTask7Request(request, operationID: UUID()),
            replacingTask7Request(request, sourceWindowID: UUID()),
            replacingTask7Request(request, targetWindowID: UUID()),
        ]

        for foreignRequest in foreignRequests {
            await store.send(.sidebar(.delegate(.requestContentTabMove(foreignRequest))))
            XCTAssertEqual(store.state.sidebar.pendingContentTabMoveRequest, request)
        }
        await store.finish()
    }

    /// FMW-001-move_content_tab_to_window: package busy family는 app delegate 전에 batch 요청을 거절한다.
    /// move topology, pin persistence, close/teardown, Undo 진행 중에는 transfer가 시작되지 않는지 검증한다.
    /// - 검증 내용: 각 busy state에서 request delegate 0회
    /// - 사전 조건: source window에 matching pending request와 busy family 하나가 설정되어 있다.
    /// - 기대 결과: 요청은 package 경계에서 종료되고 app delegate effect가 발생하지 않는다.
    func testContentTabMoveBusyFamiliesRejectBeforeDelegate() async {
        let request = makeTask7ContentTabMoveRequest()
        var topologyBusy = makeTask7ContentTabMoveState(request: request)
        let overlappingRequest = replacingTask7Request(request, operationID: UUID())
        topologyBusy.pendingContentTabMove = FileManagerWindowContentTabMovePending(
            request: overlappingRequest,
            lifecycle: .inFlight,
        )
        topologyBusy.sidebar.pendingContentTabMoveRequest = overlappingRequest
        let topologyStore = TestStore(initialState: topologyBusy) { FileManagerFeature() }
        await topologyStore.send(.sidebar(.delegate(.requestContentTabMove(request))))
        await topologyStore.finish()

        var pinPersistenceBusy = makeTask7ContentTabMoveState(request: request)
        pinPersistenceBusy.contentTabs.pendingPinnedRecordIDs.insert(request.initiatingTabID)

        var closingBusy = makeTask7ContentTabMoveState(request: request)
        closingBusy.isClosing = true

        var teardownBusy = makeTask7ContentTabMoveState(request: request)
        teardownBusy.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: UUID(),
            tabID: request.initiatingTabID,
            ownerID: UUID(),
        )

        var undoBusy = makeTask7ContentTabMoveState(request: request)
        undoBusy.undoRedoPhase = .invoking(requestID: UUID(), direction: .undo)

        for state in [pinPersistenceBusy, closingBusy, teardownBusy, undoBusy] {
            let store = TestStore(initialState: state) { FileManagerFeature() }
            await store.send(.sidebar(.delegate(.requestContentTabMove(request)))) {
                $0.pendingContentTabMove = nil
                $0.sidebar.pendingContentTabMoveRequest = nil
                $0.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
                    requestID: request.requestID,
                    category: .busy,
                )
            }
            await store.finish()
        }
    }

    /// FMW-001-move_content_tab_to_window: batch target은 free slot과 passive replacement의 순용량으로 판정한다.
    /// 일부 충돌 tab을 passive pinned replacement로 제거할 수 있을 때 나머지 삽입 수만 free slot을 소비하는 계약을 검증한다.
    /// - 검증 내용: ordered batch acceptance, passive replacement 합산, 부족한 net capacity 거부
    /// - 사전 조건: 세 tab batch와 free slot/replacement 조합이 다른 세 target이 있다.
    /// - 기대 결과: 순필요 slot을 충족하는 두 target만 주입 순서로 남는다.
    func testContentTabMoveProjectionUsesNetCapacityAndPassiveReplacement() throws {
        let currentWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000370"))
        let freeWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000371"))
        let passiveWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000372"))
        let insufficientWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000373"))
        let tabA = ContentTabID(rawValue: "projection-batch-a")
        let tabB = ContentTabID(rawValue: "projection-batch-b")
        let tabC = ContentTabID(rawValue: "projection-batch-c")
        let orderedTabIDs = [tabA, tabB, tabC]
        let free = ContentTabMoveTarget(
            windowID: freeWindowID,
            displayTitle: "Free",
            availableSlots: 3,
        )
        let passive = ContentTabMoveTarget(
            windowID: passiveWindowID,
            displayTitle: "Passive",
            availableSlots: 1,
            replaceablePinnedTabIDs: [tabA, tabB],
        )
        let insufficient = ContentTabMoveTarget(
            windowID: insufficientWindowID,
            displayTitle: "Insufficient",
            availableSlots: 1,
            replaceablePinnedTabIDs: [tabA],
        )

        XCTAssertEqual(
            ContentTabMoveProjection.availableTargets(
                [free, passive, insufficient],
                currentWindowID: currentWindowID,
                orderedTabIDs: orderedTabIDs,
            ),
            [free, passive],
        )
        XCTAssertTrue(passive.accepts(orderedTabIDs: orderedTabIDs))
        XCTAssertFalse(insufficient.accepts(orderedTabIDs: orderedTabIDs))
    }

    /// FMW-001-move_content_tab_to_window: replacement projection은 실제 passive pinned collision만 집계한다.
    /// target의 빈 용량 때문에 non-colliding source ID를 replaceable로 오분류하지 않는 policy 경계를 검증한다.
    /// - 검증 내용: free-capacity acceptance와 passive collision replacement predicate의 분리
    /// - 사전 조건: 빈 용량이 있는 target, 존재하지 않는 source ID, 실제 passive pinned home projection이 있다.
    /// - 기대 결과: non-collision은 replaceable이 아니고 actual passive collision만 replaceable이며 net capacity가 정확하다.
    func testContentTabMoveReplacementPolicyExcludesFreeCapacityWithoutCollision() throws {
        var target = FileManagerWindowState()
        let collisionID = try XCTUnwrap(target.contentTabs.activeTabID)
        let nonCollisionID = ContentTabID(rawValue: "free-capacity-non-collision")
        var collisionItem = try XCTUnwrap(target.contentTabs.tabs[id: collisionID])
        collisionItem.isPinned = true
        target.contentTabs.tabs[id: collisionID] = collisionItem
        let collisionRecord = ContentTabPinnedRecord(
            id: collisionID.rawValue,
            page: collisionItem.page,
            anchor: collisionItem.anchor,
            title: collisionItem.title,
            iconName: collisionItem.iconName,
            pinnedAt: Date(timeIntervalSince1970: 1),
        )
        target.contentTabs.pinnedRecords[collisionID] = collisionRecord
        target.tabContentStates[collisionID] = target.content

        XCTAssertTrue(target.canAcceptContentTabMove(tabID: nonCollisionID, sourcePinnedRecord: nil))
        XCTAssertFalse(target.canReplacePassivePinnedContentTab(
            tabID: nonCollisionID,
            sourcePinnedRecord: nil,
        ))
        XCTAssertTrue(target.canReplacePassivePinnedContentTab(
            tabID: collisionID,
            sourcePinnedRecord: collisionRecord,
        ))

        let withoutCollision = ContentTabMoveTarget(
            windowID: UUID(),
            displayTitle: "Free only",
            availableSlots: 1,
        )
        let withCollision = ContentTabMoveTarget(
            windowID: UUID(),
            displayTitle: "Free plus replacement",
            availableSlots: 1,
            replaceablePinnedTabIDs: [collisionID],
        )
        let orderedTabIDs = [collisionID, nonCollisionID]
        XCTAssertFalse(withoutCollision.accepts(orderedTabIDs: orderedTabIDs))
        XCTAssertTrue(withCollision.accepts(orderedTabIDs: orderedTabIDs))
    }

    /// FMW-001-move_content_tab_to_window: drag terminal 뒤 도착한 payload도 frozen batch identity로 요청을 만든다.
    /// async payload load보다 native terminal이 먼저 와도 exact payload만 한 번 소비하는 계약을 검증한다.
    /// - 검증 내용: terminal-before-payload, exact request 생성, snapshot 소비, replay와 superseded payload zero mutation
    /// - 사전 조건: inFlight `[A, B]` snapshot, 변경된 live order `[B]`, batch를 허용하는 target이 있다.
    /// - 기대 결과: matching payload는 `[A, B]` request 하나를 만들고 replay/superseded payload는 state/effect를 변경하지 않는다.
    func testContentTabDropConsumesFrozenPayloadAfterDragTerminal() async throws {
        let fixture = try makeTerminalContentTabDropFixture()
        let store = TestStore(initialState: fixture.state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(fixture.request.requestID)
        }

        await store.send(.sidebar(.view(.contentTabDragTerminal(
            operationID: fixture.snapshot.operationID,
        )))) {
            $0.sidebar.contentTabDragSnapshot?.lifecycle = .awaitingPayload
        }
        await store.send(.sidebar(.view(.moveContentTabs(
            payload: fixture.snapshot.payload,
            targetWindowID: fixture.request.targetWindowID,
        )))) {
            $0.sidebar.contentTabDragSnapshot = nil
            $0.sidebar.pendingContentTabMoveRequest = fixture.request
            $0.pendingContentTabMove = FileManagerWindowContentTabMovePending(
                request: fixture.request,
                metricSource: .dragAndDrop,
            )
        }
        await store.receive(\.sidebar.delegate.requestContentTabMove, fixture.request) {
            $0.pendingContentTabMove?.lifecycle = .inFlight
        }
        await store.receive(\.delegate.requestContentTabMove, fixture.request)
        let stateAfterRequest = store.state
        await store.send(.sidebar(.view(.moveContentTabs(
            payload: fixture.snapshot.payload,
            targetWindowID: fixture.request.targetWindowID,
        ))))
        XCTAssertEqual(store.state, stateAfterRequest)
        await assertSupersededContentTabDropIsNoOp(
            state: fixture.state,
            snapshot: fixture.snapshot,
            supersedingOperationID: fixture.supersedingOperationID,
            targetWindowID: fixture.request.targetWindowID,
            tabID: fixture.snapshot.initiatingTabID,
        )
    }

    /// FMW-001-move_content_tab_to_window: legacy v1 payload는 source-owned drag intent 없이 mutation을 만들지 않는다.
    /// wire decode 호환 payload의 반복 실행과 같은 tab의 현재 v2 snapshot 기생을 source mutation 경계에서 차단한다.
    /// - 검증 내용: no-snapshot v1 두 번과 same-tab current-v2-snapshot v1의 UUID, pending, delegate, full state mutation 0회
    /// - 사전 조건: source/target/tab이 유효하고 두 번째 state에는 같은 source/tab의 inFlight v2 singleton snapshot이 있다.
    /// - 기대 결과: 모든 v1 action이 zero mutation이며 현재 v2 snapshot도 그대로 보존된다.
    func testLegacyContentTabDropRejectsReplayAndCurrentSnapshotForgeryWithoutMutation() async throws {
        let fixture = try makeLegacyContentTabDropFixture()
        let uuidCalls = LockIsolated(0)
        let generatedRequestID = fixture.generatedRequestID
        let replayStore = TestStore(initialState: fixture.state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return generatedRequestID
            }
        }
        let beforeReplay = replayStore.state

        for _ in 0 ..< 2 {
            await replayStore.send(.sidebar(.view(.moveContentTabs(
                payload: fixture.payload,
                targetWindowID: fixture.targetWindowID,
            ))))
            XCTAssertEqual(replayStore.state, beforeReplay)
        }
        XCTAssertEqual(uuidCalls.value, 0)
        await replayStore.finish()

        var snapshotState = fixture.state
        snapshotState.sidebar.contentTabDragSnapshot = ContentTabDragSnapshot(
            operationID: fixture.operationID,
            sourceWindowID: fixture.payload.sourceWindowID,
            initiatingTabID: fixture.payload.initiatingTabID,
            orderedTabIDs: fixture.payload.orderedTabIDs,
            lifecycle: .inFlight,
        )
        let forgeryStore = TestStore(initialState: snapshotState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return generatedRequestID
            }
        }
        let beforeForgery = forgeryStore.state

        await forgeryStore.send(.sidebar(.view(.moveContentTabs(
            payload: fixture.payload,
            targetWindowID: fixture.targetWindowID,
        ))))
        XCTAssertEqual(forgeryStore.state, beforeForgery)
        XCTAssertEqual(uuidCalls.value, 0)
        await forgeryStore.finish()
    }

    /// FMW-001-move_content_tab_to_window: batch terminal은 현재 pending의 전체 semantic identity와 일치해야 한다.
    /// 같은 request ID를 재사용한 foreign operation이 새로운 pending batch를 지우지 않는 계약을 검증한다.
    /// - 검증 내용: operation/request/source/target/ordered mismatch no-op과 exact success cleanup
    /// - 사전 조건: batch pending request와 같은 request ID지만 다른 operation/ordered IDs를 가진 stale request가 있다.
    /// - 기대 결과: stale terminal은 zero mutation이고 exact terminal만 pending을 정리한다.
    func testContentTabMoveTerminalRequiresExactPendingIdentity() async throws {
        let request = try ContentTabMoveRequest(
            operationID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000379")),
            requestID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000380")),
            sourceWindowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000381")),
            initiatingTabID: ContentTabID(rawValue: "terminal-b"),
            orderedTabIDs: [ContentTabID(rawValue: "terminal-a"), ContentTabID(rawValue: "terminal-b")],
            targetWindowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000382")),
        )
        let staleRequest = try ContentTabMoveRequest(
            operationID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000383")),
            requestID: request.requestID,
            sourceWindowID: request.sourceWindowID,
            initiatingTabID: request.initiatingTabID,
            orderedTabIDs: [request.initiatingTabID],
            targetWindowID: request.targetWindowID,
        )
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(
            request: request,
            lifecycle: .inFlight,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.contentTabMoveSucceeded(request: staleRequest))
        XCTAssertEqual(store.state.sidebar.pendingContentTabMoveRequest, request)
        await store.send(.contentTabMoveSucceeded(request: request)) {
            $0.sidebar.pendingContentTabMoveRequest = nil
            $0.pendingContentTabMove = nil
        }
    }

    /// FMW-001-move_content_tab_to_window: target 선택은 request UUID를 한 번 생성해 모든 delegate 계층에 보존한다.
    /// 사용자가 같은 target을 반복 선택해도 pending tab에는 하나의 요청만 전달되는 계약을 검증한다.
    /// - 검증 내용: Sidebar pending state, Sidebar delegate, Window delegate의 request identity와 중복 억제.
    /// - 사전 조건: source window ID, active tab, 두 target projection, 고정 UUID dependency가 있다.
    /// - 기대 결과: 첫 선택만 동일 request를 두 delegate 계층에 전달하고 두 번째 선택은 no-op이다.
    func testContentTabMoveSelectionCreatesOneRequestAndPreservesDelegateIdentity() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301"))
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000302"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000303"))
        var state = FileManagerWindowState()
        let tabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.sidebar.currentWindowID = sourceWindowID
        state.sidebar.contentTabMoveTargets = [
            ContentTabMoveTarget(windowID: targetWindowID, displayTitle: "Research"),
        ]
        let request = ContentTabMoveRequest(
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
            targetWindowID: targetWindowID,
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.sidebar(.view(.moveContentTab(tabID: tabID, targetWindowID: targetWindowID)))) {
            $0.sidebar.pendingContentTabMoveRequest = request
            $0.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
        }
        await store.receive(\.sidebar.delegate.requestContentTabMove, request) {
            $0.pendingContentTabMove?.lifecycle = .inFlight
        }
        await store.receive(\.delegate.requestContentTabMove, request)

        await store.send(.sidebar(.view(.moveContentTab(tabID: tabID, targetWindowID: targetWindowID))))
    }

    /// FMW-001-move_content_tab_to_window: matching success만 pending 요청을 종료한다.
    /// manager terminal이 현재 request와 정확히 일치할 때만 진행 표시가 사라지는 stale-safe 계약을 검증한다.
    /// - 검증 내용: stale success no-op과 matching success의 pending clear.
    /// - 사전 조건: source tab에 pending move request가 있고 stale request ID가 별도로 있다.
    /// - 기대 결과: stale terminal은 불변이고 matching terminal만 pending을 nil로 만든다.
    func testContentTabMoveSuccessClearsOnlyMatchingPendingRequest() async throws {
        let request = try makeContentTabMoveRequest()
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(
            request: request,
            lifecycle: .inFlight,
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        let staleRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: request.sourceWindowID,
            tabID: request.tabID,
            targetWindowID: request.targetWindowID,
        )
        await store.send(.contentTabMoveSucceeded(request: staleRequest))
        await store.send(.contentTabMoveSucceeded(request: request)) {
            $0.sidebar.pendingContentTabMoveRequest = nil
            $0.pendingContentTabMove = nil
        }
    }

    /// FMW-001-move_content_tab_to_window: matching rejection은 네 사용자 범주만 window presentation으로 매핑한다.
    /// 내부 transfer 세부 정보 대신 고정된 사용자 의미만 source window에 표시하는 계약을 검증한다.
    /// - 검증 내용: unavailable/capacity/busy/generic terminal의 pending clear와 typed presentation 설정.
    /// - 사전 조건: 각 범주마다 matching pending request가 설정되어 있다.
    /// - 기대 결과: presentation은 request ID와 네 범주 중 하나만 보존한다.
    func testContentTabMoveRejectionMapsAllUserFacingCategories() async throws {
        for category in ContentTabMoveFailurePresentation.Category.allCases {
            let request = try makeContentTabMoveRequest()
            var state = FileManagerWindowState()
            state.sidebar.pendingContentTabMoveRequest = request
            state.pendingContentTabMove = FileManagerWindowContentTabMovePending(
                request: request,
                lifecycle: .inFlight,
            )
            let store = TestStore(initialState: state) {
                FileManagerFeature()
            }

            await store.send(.contentTabMoveRejected(request: request, category: category)) {
                $0.sidebar.pendingContentTabMoveRequest = nil
                $0.pendingContentTabMove = nil
                $0.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
                    requestID: request.requestID,
                    category: category,
                )
            }
        }
    }

    /// FMW-001-move_content_tab_to_window: stale rejection과 stale dismiss는 현재 presentation을 변경하지 않는다.
    /// 늦게 도착한 manager/UI action이 새로운 failure ownership을 지우지 않는 계약을 검증한다.
    /// - 검증 내용: request ID mismatch terminal과 dismiss의 no-op.
    /// - 사전 조건: matching pending request와 다른 request ID의 기존 presentation이 있다.
    /// - 기대 결과: stale rejection은 pending을, stale dismiss는 presentation을 그대로 유지한다.
    func testContentTabMoveStaleTerminalAndDismissAreNoOps() async throws {
        let request = try makeContentTabMoveRequest()
        let presentation = ContentTabMoveFailurePresentation(requestID: UUID(), category: .busy)
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        state.pendingContentTabMove = FileManagerWindowContentTabMovePending(
            request: request,
            lifecycle: .inFlight,
        )
        state.contentTabMoveFailurePresentation = presentation
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        let staleRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: request.sourceWindowID,
            tabID: request.tabID,
            targetWindowID: request.targetWindowID,
        )
        await store.send(.contentTabMoveRejected(request: staleRequest, category: .generic))
        await store.send(.view(.dismissContentTabMoveFailure(requestID: UUID())))
    }

    /// FMW-001-move_content_tab_to_window: failure dismiss는 presentation 외 transfer semantic state를 변경하지 않는다.
    /// 사용자가 오류를 닫아도 target projection과 pending/ContentTab 상태가 보존되는 계약을 검증한다.
    /// - 검증 내용: matching dismiss의 presentation-only mutation.
    /// - 사전 조건: failure presentation, target projection, content tab state가 설정되어 있다.
    /// - 기대 결과: presentation만 nil이고 target과 ContentTab 상태는 동일하다.
    func testContentTabMoveFailureDismissPreservesTransferSemanticState() async throws {
        let request = try makeContentTabMoveRequest()
        let target = ContentTabMoveTarget(windowID: request.targetWindowID, displayTitle: "Research")
        var state = FileManagerWindowState()
        state.sidebar.contentTabMoveTargets = [target]
        state.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
            requestID: request.requestID,
            category: .unavailable,
        )
        let contentTabs = state.contentTabs
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.view(.dismissContentTabMoveFailure(requestID: request.requestID))) {
            $0.contentTabMoveFailurePresentation = nil
        }

        XCTAssertEqual(store.state.sidebar.contentTabMoveTargets, [target])
        XCTAssertEqual(store.state.contentTabs, contentTabs)
        XCTAssertNil(store.state.sidebar.pendingContentTabMoveRequest)
    }

    /// FMW-001-move_content_tab_to_window: 빈 projection과 current window target은 move command를 만들지 않는다.
    /// app projection이 비었거나 방어적으로 제거된 경우 Sidebar가 registry fallback 없이 no-op인지 검증한다.
    /// - 검증 내용: target filtering 순서와 유효하지 않은 target action의 delegate 미방출.
    /// - 사전 조건: current window와 동일한 target만 주입되거나 projection이 비어 있다.
    /// - 기대 결과: available target은 비고 move action은 pending/delegate를 만들지 않는다.
    func testContentTabMoveProjectionExcludesCurrentWindowAndEmptySelectionIsNoOp() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000310"))
        var state = FileManagerWindowState()
        let tabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.sidebar.currentWindowID = sourceWindowID
        state.sidebar.contentTabMoveTargets = [
            ContentTabMoveTarget(windowID: sourceWindowID, displayTitle: "Current"),
        ]
        XCTAssertTrue(ContentTabMoveProjection.availableTargets(
            state.sidebar.contentTabMoveTargets,
            currentWindowID: sourceWindowID,
        ).isEmpty)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.view(.moveContentTab(tabID: tabID, targetWindowID: UUID()))))
    }

    /// FMW-001-move_content_tab_to_window: target projection은 주입 순서를 보존한다.
    /// Sidebar menu가 display title이나 window ID로 재정렬하지 않는 순수 projection 계약을 검증한다.
    /// - 검증 내용: current window defensive filtering 이후 target 순서.
    /// - 사전 조건: current window를 사이에 포함한 세 target이 고정 순서로 주입된다.
    /// - 기대 결과: current window만 제거되고 나머지 두 target 순서는 그대로다.
    func testContentTabMoveProjectionPreservesInjectedTargetOrder() throws {
        let currentWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000320"))
        let first = try ContentTabMoveTarget(
            windowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000321")),
            displayTitle: "Zeta",
        )
        let second = try ContentTabMoveTarget(
            windowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000322")),
            displayTitle: "Alpha",
        )
        let current = ContentTabMoveTarget(windowID: currentWindowID, displayTitle: "Current")

        XCTAssertEqual(
            ContentTabMoveProjection.availableTargets([first, current, second], currentWindowID: currentWindowID),
            [first, second],
        )
    }

    /// FMW-001-move_content_tab_to_window: row/menu/target/progress identifier는 stable typed ID만 사용한다.
    /// display title 변경이 UI automation identifier를 바꾸지 않는 추적 계약을 검증한다.
    /// - 검증 내용: 네 identifier의 정확한 문자열 형식.
    /// - 사전 조건: 고정 ContentTabID와 target window UUID가 있다.
    /// - 기대 결과: 요구된 prefix와 raw typed ID로 정확한 identifier가 생성된다.
    func testContentTabMoveAccessibilityIdentifiersAreStable() throws {
        let tabID = ContentTabID(rawValue: "tab-identifier")
        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000330"))

        XCTAssertEqual(ContentTabMoveProjection.rowIdentifier(tabID: tabID), "content-tab-tab-identifier")
        XCTAssertEqual(ContentTabMoveProjection.menuIdentifier(tabID: tabID), "content-tab-move-menu-tab-identifier")
        XCTAssertEqual(
            ContentTabMoveProjection.targetIdentifier(tabID: tabID, windowID: windowID),
            "content-tab-move-target-tab-identifier-00000000-0000-0000-0000-000000000330",
        )
        XCTAssertEqual(
            ContentTabMoveProjection.progressIdentifier(tabID: tabID),
            "content-tab-move-progress-tab-identifier",
        )
    }

    /// FMW-001-move_content_tab_to_window: Sidebar view는 projection과 stable identifier를 실제 context menu에 연결한다.
    /// 실행 가능한 SwiftUI inspection이 없는 패키지 환경에서 source-level wiring 계약을 고정한다.
    /// - 검증 내용: non-empty menu guard, injected-order ForEach, move-only disabled, row/menu/target/progress identifier
    /// 적용.
    /// - 사전 조건: package checkout의 canonical SidebarView.swift source를 읽을 수 있다.
    /// - 기대 결과: 요구된 wiring token이 모두 있고 view-side target sorting은 없다.
    func testContentTabMoveSidebarViewWiresMenuOrderPendingControlsAndIdentifiers() throws {
        let source = try loadFMWSidebarUISources()

        XCTAssertTrue(source.contains("if !moveTargets.isEmpty"))
        XCTAssertTrue(source.contains("NSMenuItem(title: moveTitle"))
        XCTAssertTrue(source.contains("for target in moveTargets"))
        XCTAssertFalse(source.contains("moveTargets.sorted"))
        XCTAssertTrue(source.contains("moveItem.isEnabled = !isMovePending"))
        XCTAssertTrue(source.contains("targetItem.isEnabled = !isMovePending"))
        XCTAssertTrue(source.contains("setAccessibilityIdentifier(ContentTabMoveProjection.rowIdentifier"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.menuIdentifier(tabID: moveTargetsTabID)"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.targetIdentifier("))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.progressIdentifier(tabID: item.id)"))
    }

    /// FMW-001-move_content_tab_to_window: 이동 실패 alert는 live main container가 단독 소유한다.
    /// 실행 가능한 SwiftUI inspection이 없는 패키지 환경에서 source-level alert hosting 계약을 고정한다.
    /// - 검증 내용: MainContainer의 alert/binding/dismiss/message mapping과 legacy WindowView alert 부재
    /// - 사전 조건: package checkout의 두 canonical window view source를 읽을 수 있다.
    /// - 기대 결과: live split layout 경로에만 content-tab move failure alert가 존재한다.
    func testContentTabMoveFailureAlertIsOwnedOnlyByLiveMainContainer() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainContainerSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerWindowMainContainerView.swift",
            ),
            encoding: .utf8,
        )
        let legacyWindowSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerWindowView.swift",
            ),
            encoding: .utf8,
        )

        XCTAssertTrue(mainContainerSource.contains(#".alert("#))
        XCTAssertTrue(mainContainerSource.contains("contentTabMoveFailureIsPresented"))
        XCTAssertTrue(mainContainerSource.contains("dismissContentTabMoveFailure"))
        XCTAssertTrue(mainContainerSource.contains("contentTabMoveFailureMessage"))
        XCTAssertTrue(mainContainerSource.contains(".view(.dismissContentTabMoveFailure(requestID: requestID))"))
        XCTAssertFalse(legacyWindowSource.contains(#".alert("#))
        XCTAssertFalse(legacyWindowSource.contains("contentTabMoveFailureIsPresented"))
    }

    /// FMW-001-move_content_tab_to_window: pending move는 다른 tab 선택 routing을 차단하지 않는다.
    /// 진행 중인 tab의 move control만 제한하고 일반 row navigation은 유지하는 계약을 검증한다.
    /// - 검증 내용: pending request가 있어도 다른 tab select delegate가 window selection, setCurrent, selection collapse로 전달된다.
    /// - 사전 조건: 한 tab에 pending move가 있고 별도의 target tab이 존재한다.
    /// - 기대 결과: 다른 tab의 selectContentTab, setCurrent, collapseSelectionToActive action이 순서대로 방출된다.
    func testContentTabMovePendingPreservesUnrelatedTabSelection() async throws {
        let request = try makeContentTabMoveRequest()
        let otherTabID = ContentTabID(rawValue: "unrelated-tab")
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        state.contentTabs.tabs.append(ContentTabItem(
            id: otherTabID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Other",
            iconName: "house",
        ))
        state.tabContentStates[otherTabID] = FileManagerContentFeature.State.initialContent(
            for: .homeDefault,
            inheritingWindowContextFrom: state.content,
        )
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.selectContentTab(otherTabID))))
        await store.receive { action in
            guard case let .selectContentTab(id) = action else { return false }
            return id == otherTabID
        }
        await store.receive(\.contentTabs.setCurrent, otherTabID)
        await store.receive(\.contentTabs.collapseSelectionToActive)
    }

    /// FMW-001-move_content_tab_to_window: legacy v1 drag payload는 version/source/tab locator만 round-trip한다.
    /// 기존 외부 drop payload가 v2 correlation 필드나 live selection으로 확장되지 않는 호환 계약을 검증한다.
    /// - 검증 내용: legacy Codable round-trip의 exact field 보존과 top-level encoded key allowlist.
    /// - 사전 조건: legacy schema version, source window UUID, ContentTabID가 있다.
    /// - 기대 결과: 세 값만 복원되고 operation/target/request/state 관련 key는 존재하지 않는다.
    func testContentTabDragPayloadRoundTripUsesMinimalVersionedLocatorKeys() throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000351"))
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.legacySchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: ContentTabID(rawValue: "drag-payload-tab"),
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ContentTabDragPayload.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.schemaVersion, ContentTabDragPayload.legacySchemaVersion)
        XCTAssertEqual(decoded.sourceWindowID, sourceWindowID)
        XCTAssertEqual(decoded.tabID, ContentTabID(rawValue: "drag-payload-tab"))
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "sourceWindowID", "tabID"])
        XCTAssertTrue(ContentTabDragPayload.isSupported(schemaVersion: decoded.schemaVersion))
        XCTAssertFalse(ContentTabDragPayload.isSupported(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion + 1,
        ))
        for forbiddenKey in [
            "operationID", "initiatingTabID", "orderedTabIDs", "targetWindowID", "requestID",
            "title", "path", "anchor", "state", "workUnit",
        ] {
            XCTAssertNil(object[forbiddenKey])
        }
    }

    /// FMW-001-move_content_tab_to_window: drag UTI는 안정적인 identifier와 JSON conformance를 함께 선언한다.
    /// Swift Transferable representation과 app bundle exported declaration이 공유할 code-side 계약을 검증한다.
    /// - 검증 내용: contentType identifier와 public.json conformance.
    /// - 사전 조건: ContentTabDragPayload의 custom exported UTType이 있다.
    /// - 기대 결과: identifier가 고정되고 UTType.json에 conform한다.
    func testContentTabDragContentTypeUsesExportedJSONContract() throws {
        XCTAssertEqual(
            ContentTabDragPayload.contentType.identifier,
            "com.voyager.app.content-tab-drag-payload",
        )

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerPagesFileManager/Sidebar/Model/ContentTabMove.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("conformingTo: .json"))
    }

    /// FMW-001-move_content_tab_to_window: native drag writer는 generalized reorder와 cross-window move payload를 함께 광고한다.
    /// phase의 top-navigation reorder와 VOY-450 cross-window move가 하나의 AppKit drag session을 공유하는 계약을 검증한다.
    /// - 검증 내용: combined/reorder-only writable type과 두 JSON payload identity, local token ownership.
    /// - 사전 조건: 고정 reorder scope와 cross-window locator, Sidebar-local session store가 있다.
    /// - 기대 결과: Content Tab source는 세 type을, Location source는 reorder type만 광고한다.
    func testContentTabNativeDragWriterCombinesReorderAndCrossWindowMovePayloads() throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000356"))
        let tabID = ContentTabID(rawValue: "combined-drag-tab")
        let reorderPayload = try FileManagerTopNavigationReorderDragPayload(
            sourceID: .contentTab(tabID),
            dragScopeID: FileManagerTopNavigationReorderDragScopeID(
                rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000357")),
            ),
        )
        let movePayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        )
        let sessionStore = FileManagerTopNavigationReorderLocalSessionStore(nowNanoseconds: { 100 })
        let pasteboard = NSPasteboard(name: .init("fm.voyager.tests.combined-content-tab-drag"))
        defer { pasteboard.clearContents() }

        let combinedWriter = try FileManagerTopNavigationReorderPasteboardWriter(
            configuration: .init(
                payload: reorderPayload,
                sessionStore: sessionStore,
                movePayload: movePayload,
            ),
        )
        defer { combinedWriter.cleanupOwnedToken() }
        let expectedTypes: Set<NSPasteboard.PasteboardType> = [
            .fileManagerTopNavigationReorder,
            .fileManagerTopNavigationReorderLocal,
            .contentTabMove,
        ]
        XCTAssertEqual(Set(combinedWriter.writableTypes(for: pasteboard)), expectedTypes)
        let reorderData = try XCTUnwrap(combinedWriter.pasteboardPropertyList(
            forType: NSPasteboard.PasteboardType.fileManagerTopNavigationReorder,
        ) as? Data)
        let moveData = try XCTUnwrap(combinedWriter.pasteboardPropertyList(
            forType: NSPasteboard.PasteboardType.contentTabMove,
        ) as? Data)
        XCTAssertEqual(
            try JSONDecoder().decode(FileManagerTopNavigationReorderDragPayload.self, from: reorderData),
            reorderPayload,
        )
        XCTAssertEqual(try JSONDecoder().decode(ContentTabDragPayload.self, from: moveData), movePayload)

        let locationPayload = try FileManagerTopNavigationReorderDragPayload(
            sourceID: .location("home"),
            dragScopeID: FileManagerTopNavigationReorderDragScopeID(
                rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000360")),
                boundaryOwner: .topNavigation,
            ),
        )
        let reorderOnlyWriter = try FileManagerTopNavigationReorderPasteboardWriter(
            configuration: .init(payload: locationPayload, sessionStore: sessionStore),
        )
        defer { reorderOnlyWriter.cleanupOwnedToken() }
        XCTAssertEqual(
            Set(reorderOnlyWriter.writableTypes(for: pasteboard)),
            Set<NSPasteboard.PasteboardType>([
                .fileManagerTopNavigationReorder,
                .fileManagerTopNavigationReorderLocal,
            ]),
        )
    }

    /// FMW-001-move_content_tab_to_window: foreign-window combined drag는 same-window reorder slot이 가로채지 않는다.
    /// generalized reorder payload의 scope를 preview하여 target window의 viewport drop handler에 cross-window payload를 위임한다.
    /// - 검증 내용: same scope move 승인과 foreign scope 거부, move UTI가 reorder shape 검증을 깨지 않음.
    /// - 사전 조건: 동일 type set을 가진 same/foreign scope payload가 있다.
    /// - 기대 결과: same scope만 reorder boundary를 활성화하고 foreign scope는 빈 operation을 반환한다.
    func testContentTabReorderDestinationRejectsForeignCombinedDragScope() throws {
        let localScope = try FileManagerTopNavigationReorderDragScopeID(
            rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000358")),
        )
        let foreignScope = try FileManagerTopNavigationReorderDragScopeID(
            rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000359")),
        )
        let sourceID = FileManagerTopNavigationItemID.contentTab(.init(rawValue: "source"))
        let targetID = FileManagerTopNavigationItemID.contentTab(.init(rawValue: "target"))
        var activeBoundaryID: Int?
        let sessionStore = FileManagerTopNavigationReorderLocalSessionStore(nowNanoseconds: { 100 })
        let localPayload = FileManagerTopNavigationReorderDragPayload(
            sourceID: sourceID,
            dragScopeID: localScope,
        )
        let foreignPayload = FileManagerTopNavigationReorderDragPayload(
            sourceID: sourceID,
            dragScopeID: foreignScope,
        )
        sessionStore.begin(payload: localPayload)
        let view = FileManagerTopNavigationReorderDropDestinationView(configuration: .init(
            activeBoundaryID: Binding(
                get: { activeBoundaryID },
                set: { activeBoundaryID = $0 },
            ),
            boundary: .init(
                id: 1,
                owner: .unpinnedContentTabs,
                anchorID: targetID,
                placement: .before,
            ),
            dragScopeID: localScope,
            sessionStore: sessionStore,
            boundaryOwnerForItem: { _ in .unpinnedContentTabs },
            onReorder: { _ in },
            onDropValidationCompleted: { _ in },
        ))
        let types: Set<NSPasteboard.PasteboardType> = [
            .fileManagerTopNavigationReorder,
            .fileManagerTopNavigationReorderLocal,
            .contentTabMove,
        ]
        func item(payload: FileManagerTopNavigationReorderDragPayload) throws
            -> FileManagerTopNavigationReorderPasteboardItem
        {
            let data = try JSONEncoder().encode(payload)
            return FileManagerTopNavigationReorderPasteboardItem(types: types) { type in
                type == .fileManagerTopNavigationReorder ? data : nil
            }
        }

        XCTAssertEqual(try view.draggingEntered(pasteboardItems: [item(payload: localPayload)]), .move)
        XCTAssertEqual(activeBoundaryID, 1)
        view.draggingExited()
        sessionStore.begin(payload: foreignPayload)
        XCTAssertEqual(try view.draggingEntered(pasteboardItems: [item(payload: foreignPayload)]), [])
        XCTAssertNil(activeBoundaryID)
    }

    /// FMW-001-move_content_tab_to_window: target Sidebar는 unsupported/no-current/self/pending drop을 위임하지 않는다.
    /// decoded locator를 source-owned move pipeline에 넣기 전 target-local guard가 fail-safe인지 검증한다.
    /// - 검증 내용: 네 invalid state에서 state mutation과 delegate action이 모두 없다.
    /// - 사전 조건: unsupported payload, currentWindowID 없음, self payload, 기존 pending request를 각각 구성한다.
    /// - 기대 결과: 모든 action이 no-op으로 끝난다.
    func testContentTabDropRejectsUnsupportedMissingCurrentSelfAndPending() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000352"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000353"))
        let tabID = ContentTabID(rawValue: "drag-rejection-tab")
        let validPayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        )
        let unsupportedPayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion + 1,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        )

        func assertRejected(
            _ payload: ContentTabDragPayload,
            state: FileManagerSidebarState,
        ) async {
            let store = TestStore(initialState: state) {
                FileManagerSidebarFeature()
            }
            await store.send(.view(.receiveContentTabDrag(payload)))
            await store.finish()
        }

        var unsupportedState = FileManagerSidebarState()
        unsupportedState.currentWindowID = targetWindowID
        await assertRejected(unsupportedPayload, state: unsupportedState)

        await assertRejected(validPayload, state: FileManagerSidebarState())

        var selfDropState = FileManagerSidebarState()
        selfDropState.currentWindowID = sourceWindowID
        await assertRejected(validPayload, state: selfDropState)

        var pendingState = FileManagerSidebarState()
        pendingState.currentWindowID = targetWindowID
        pendingState.pendingContentTabMoveRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: targetWindowID,
            tabID: ContentTabID(rawValue: "other-pending-tab"),
            targetWindowID: sourceWindowID,
        )
        await assertRejected(validPayload, state: pendingState)
    }

    /// FMW-001-move_content_tab_to_window: valid drop locator는 Sidebar와 FileManager delegate를 그대로 통과한다.
    /// target 계층이 request UUID나 target ID를 만들지 않고 untrusted locator를 상위 manager로 전달하는지 검증한다.
    /// - 검증 내용: Sidebar delegate와 FileManagerWindow delegate의 payload identity.
    /// - 사전 조건: source와 다른 current target window, 지원 schema payload, pending 없음.
    /// - 기대 결과: 두 delegate가 입력 payload와 정확히 같은 값을 한 번씩 방출한다.
    func testContentTabDropRoutesPayloadUnchangedThroughSidebarAndWindowDelegates() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000354"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000355"))
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: ContentTabID(rawValue: "drag-routing-tab"),
        )
        var state = FileManagerWindowState()
        state.sidebar.currentWindowID = targetWindowID
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.view(.receiveContentTabDrag(payload))))
        await store.receive(\.sidebar.delegate.receiveContentTabDrag, payload)
        await store.receive(\.delegate.receiveContentTabDrag, payload)
        await store.finish()
    }

    /// FMW-001-move_content_tab_to_window: Sidebar source는 row drag와 move drop wiring을 함께 보존한다.
    /// source-level UI inspection 관례로 typed payload, move proposal, stable identifier와 menu fallback을 고정한다.
    /// - 검증 내용: conditional draggable, viewport onDrop, move/forbidden proposal, typed loadTransferable, 기존 menu/IDs.
    /// - 사전 조건: package checkout의 canonical SidebarView.swift source를 읽을 수 있다.
    /// - 기대 결과: move cursor용 DropDelegate wiring과 기존 Move to Window menu/pending control이 함께 유지된다.
    func testContentTabDragDropSidebarViewWiringPreservesMoveMenu() throws {
        let source = try loadFMWSidebarUISources()

        XCTAssertTrue(source.contains("sidebarStore.pendingContentTabMoveRequest == nil"))
        XCTAssertTrue(source.contains("FileManagerTopNavigationReorderDragSourceConfiguration("))
        XCTAssertTrue(source.contains("prepareMovePayload: {"))
        XCTAssertTrue(source.contains("private var contentTabsViewport: some View"))
        XCTAssertTrue(source.contains("GeometryReader"))
        XCTAssertTrue(source.contains("minHeight: proxy.size.height"))
        XCTAssertTrue(source.contains(".onDrop("))
        XCTAssertTrue(source.contains("of: [ContentTabDragPayload.contentType]"))
        XCTAssertTrue(source.contains("hasItemsConforming(to: [ContentTabDragPayload.contentType])"))
        XCTAssertTrue(source.contains("DropProposal(operation: .move)"))
        XCTAssertTrue(source.contains("DropProposal(operation: .forbidden)"))
        XCTAssertTrue(source.contains("loadTransferable(type: ContentTabDragPayload.self)"))
        XCTAssertFalse(source.contains(".dropDestination(for: ContentTabDragPayload.self)"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.dropZoneIdentifier"))
        XCTAssertEqual(ContentTabMoveProjection.dropZoneIdentifier, "content-tabs-drop-zone")
        XCTAssertTrue(source.contains("NSMenuItem(title: moveTitle"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.menuIdentifier(tabID: moveTargetsTabID)"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.targetIdentifier("))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.progressIdentifier(tabID: item.id)"))
        XCTAssertTrue(source.contains("moveItem.isEnabled = !isMovePending"))
        XCTAssertTrue(source.contains("targetItem.isEnabled = !isMovePending"))
    }
}

private struct LegacyContentTabDropFixture {
    let state: FileManagerWindowState
    let payload: ContentTabDragPayload
    let targetWindowID: UUID
    let operationID: UUID
    let generatedRequestID: UUID
}

private func fmwSidebarUIPackageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/VoyagerPagesFileManager/Sidebar/Ui")
}

private func loadFMWSidebarUISource(named fileName: String) throws -> String {
    try String(
        contentsOf: fmwSidebarUIPackageRootURL().appendingPathComponent(fileName),
        encoding: .utf8,
    )
}

private func loadFMWSidebarUISources() throws -> String {
    try [
        "SidebarView.swift",
        "ContentTabSidebarViewSupport.swift",
        "FixedLocationSidebarViewSupport.swift",
        "ContentTabSidebarPresentations.swift",
    ]
    .map { try loadFMWSidebarUISource(named: $0) }
    .joined(separator: "\n")
}

private func makeLegacyContentTabDropFixture() throws -> LegacyContentTabDropFixture {
    let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000411"))
    let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000412"))
    var state = FileManagerWindowState.makeInitial(path: nil, windowID: sourceWindowID)
    let tabID = try XCTUnwrap(state.contentTabs.activeTabID)
    state.sidebar.currentWindowID = sourceWindowID
    state.sidebar.contentTabMoveTargets = [
        ContentTabMoveTarget(windowID: targetWindowID, displayTitle: "Target"),
    ]
    state.syncContentTabSidebarItems()
    return try LegacyContentTabDropFixture(
        state: state,
        payload: ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.legacySchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        ),
        targetWindowID: targetWindowID,
        operationID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000413")),
        generatedRequestID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000414")),
    )
}

private struct ContentTabMoveMenuBatchFixture {
    let state: FileManagerWindowState
    let tabA: ContentTabID
    let tabB: ContentTabID
}

private func makeContentTabMoveMenuBatchFixture(
    sourceWindowID: UUID,
    targetWindowID: UUID,
    tabB: ContentTabID,
    availableSlots: Int,
) throws -> ContentTabMoveMenuBatchFixture {
    var state = FileManagerWindowState()
    let tabA = try XCTUnwrap(state.contentTabs.activeTabID)
    state.contentTabs.tabs.append(ContentTabItem(
        id: tabB,
        page: .home,
        anchor: .homeDefault,
        isPinned: false,
        title: "B",
        iconName: "house",
    ))
    state.syncContentTabSidebarItems()
    state.sidebar.currentWindowID = sourceWindowID
    state.sidebar.contentTabMoveTargets = [
        ContentTabMoveTarget(
            windowID: targetWindowID,
            displayTitle: "Target",
            availableSlots: availableSlots,
        ),
    ]
    return ContentTabMoveMenuBatchFixture(state: state, tabA: tabA, tabB: tabB)
}

private func contentTabMoveInvalidMenuBatchActions(
    fixture: ContentTabMoveMenuBatchFixture,
    targetWindowID: UUID,
) -> [FileManagerSidebarAction.View] {
    let unknownTabID = ContentTabID(rawValue: "move-menu-unknown")
    return [
        .moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: [],
            targetWindowID: targetWindowID,
        ),
        .moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: [fixture.tabA, fixture.tabA],
            targetWindowID: targetWindowID,
        ),
        .moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: [fixture.tabB],
            targetWindowID: targetWindowID,
        ),
        .moveSelectedContentTabs(
            initiatingTabID: unknownTabID,
            orderedTabIDs: [fixture.tabA, unknownTabID],
            targetWindowID: targetWindowID,
        ),
        .moveSelectedContentTabs(
            initiatingTabID: fixture.tabA,
            orderedTabIDs: [fixture.tabB, fixture.tabA],
            targetWindowID: targetWindowID,
        ),
    ]
}

private struct TerminalContentTabDropFixture {
    let state: FileManagerWindowState
    let snapshot: ContentTabDragSnapshot
    let request: ContentTabMoveRequest
    let supersedingOperationID: UUID
}

private func makeTerminalContentTabDropFixture() throws -> TerminalContentTabDropFixture {
    let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000374"))
    let supersedingOperationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000375"))
    let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000376"))
    let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000377"))
    let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000378"))
    let frozen = try makeFrozenContentTabDropState(
        sourceWindowID: sourceWindowID,
        targetWindowID: targetWindowID,
    )
    let snapshot = ContentTabDragSnapshot(
        operationID: operationID,
        sourceWindowID: sourceWindowID,
        initiatingTabID: frozen.tabB,
        orderedTabIDs: [frozen.tabA, frozen.tabB],
        lifecycle: .inFlight,
    )
    var state = frozen.state
    state.sidebar.contentTabDragSnapshot = snapshot
    return TerminalContentTabDropFixture(
        state: state,
        snapshot: snapshot,
        request: ContentTabMoveRequest(
            operationID: operationID,
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            initiatingTabID: frozen.tabB,
            orderedTabIDs: snapshot.orderedTabIDs,
            targetWindowID: targetWindowID,
        ),
        supersedingOperationID: supersedingOperationID,
    )
}

private struct FrozenContentTabDropState {
    let state: FileManagerWindowState
    let tabA: ContentTabID
    let tabB: ContentTabID
}

private func makeFrozenContentTabDropState(
    sourceWindowID: UUID,
    targetWindowID: UUID,
) throws -> FrozenContentTabDropState {
    var state = FileManagerWindowState()
    let tabA = try XCTUnwrap(state.contentTabs.activeTabID)
    let tabB = ContentTabID(rawValue: "frozen-drop-b")
    state.contentTabs.tabs.append(ContentTabItem(
        id: tabB,
        page: .home,
        anchor: .homeDefault,
        isPinned: false,
        title: "B",
        iconName: "house",
    ))
    state.tabContentStates[tabB] = FileManagerContentFeature.State.initialContent(
        for: .homeDefault,
        inheritingWindowContextFrom: state.content,
    )
    state.syncContentTabSidebarItems()
    state.sidebar.currentWindowID = sourceWindowID
    state.sidebar.contentTabSelectionOrderedIDs = [tabB]
    state.sidebar.contentTabMoveTargets = [
        ContentTabMoveTarget(
            windowID: targetWindowID,
            displayTitle: "Target",
            availableSlots: 2,
        ),
    ]
    return FrozenContentTabDropState(
        state: state,
        tabA: tabA,
        tabB: tabB,
    )
}

@MainActor
private func assertSupersededContentTabDropIsNoOp(
    state: FileManagerWindowState,
    snapshot: ContentTabDragSnapshot,
    supersedingOperationID: UUID,
    targetWindowID: UUID,
    tabID: ContentTabID,
) async {
    var staleState = state
    staleState.sidebar.contentTabDragSnapshot = ContentTabDragSnapshot(
        operationID: supersedingOperationID,
        sourceWindowID: snapshot.sourceWindowID,
        initiatingTabID: tabID,
        orderedTabIDs: [tabID],
        lifecycle: .inFlight,
    )
    let staleStore = TestStore(initialState: staleState) { FileManagerFeature() }
    let beforeReplay = staleStore.state
    await staleStore.send(.sidebar(.view(.moveContentTabs(
        payload: snapshot.payload,
        targetWindowID: targetWindowID,
    ))))
    XCTAssertEqual(staleStore.state, beforeReplay)
    await staleStore.finish()
}

private func makeTask7ContentTabMoveRequest() -> ContentTabMoveRequest {
    let initiatingTabID = ContentTabID(rawValue: "task-7-b")
    return ContentTabMoveRequest(
        operationID: UUID(),
        requestID: UUID(),
        sourceWindowID: UUID(),
        initiatingTabID: initiatingTabID,
        orderedTabIDs: [ContentTabID(rawValue: "task-7-a"), initiatingTabID],
        targetWindowID: UUID(),
    )
}

private func makeTask7ContentTabMoveState(
    request: ContentTabMoveRequest,
) -> FileManagerWindowState {
    var state = FileManagerWindowState.makeInitial(path: nil, windowID: request.sourceWindowID)
    state.sidebar.currentWindowID = request.sourceWindowID
    state.sidebar.pendingContentTabMoveRequest = request
    state.pendingContentTabMove = FileManagerWindowContentTabMovePending(request: request)
    return state
}

private func replacingTask7Request(
    _ request: ContentTabMoveRequest,
    operationID: UUID? = nil,
    requestID: UUID? = nil,
    sourceWindowID: UUID? = nil,
    targetWindowID: UUID? = nil,
) -> ContentTabMoveRequest {
    ContentTabMoveRequest(
        operationID: operationID ?? request.operationID,
        requestID: requestID ?? request.requestID,
        sourceWindowID: sourceWindowID ?? request.sourceWindowID,
        initiatingTabID: request.initiatingTabID,
        orderedTabIDs: request.orderedTabIDs,
        targetWindowID: targetWindowID ?? request.targetWindowID,
    )
}

private func makeContentTabMoveRequest() throws -> ContentTabMoveRequest {
    try ContentTabMoveRequest(
        requestID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000340")),
        sourceWindowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000341")),
        tabID: ContentTabID(rawValue: "pending-tab"),
        targetWindowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000342")),
    )
}
