import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

//
// WindowManagerFeature의 윈도우 라이프사이클/포커스/라우팅을 검증하는
// app-scoped 결정론적 TCA TestStore 테스트 모음.
//
// AC Map 대상:
// - FMW-001-open_new_file_manager_window → focused automated test, app-scoped
// - FMW-001-close_file_manager_window → focused automated test, app-scoped
// - FMW-001-quit_voyager → focused automated test, app-scoped
//
// 시각적 동작(full screen, minimize, fronting, keep-on-top)은 수동 QA/follow-up
// 대상이므로 이 파일에서 단언하지 않는다.

@MainActor
final class FileManagerWindowManagerTests: XCTestCase {
    private typealias Spec = WindowManagerTestSupport.Spec

    private func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        onboardingRequired: Bool = false,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        WindowManagerTestSupport.makeStore(
            initialState: initialState,
            uuid: uuid,
            onboardingRequired: onboardingRequired,
            configureDependencies: configureDependencies,
        )
    }

    private func makeState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
    ) -> WindowManagerFeature.State {
        WindowManagerTestSupport.makeState(
            focusedID: focusedID,
            windows: windows,
        )
    }

    /// openInitialWindowIfNeeded는 기존 FileManager window가 있으면 중복 생성하지 않는다.
    func test_openInitialWindowIfNeeded_doesNotDuplicateExistingFileManagerWindow() async {
        let existingID = UUID()
        let openCallCount = LockIsolated(0)

        let store = makeStore(initialState: makeState(
            focusedID: existingID,
            windows: [(existingID, Spec.firstPath)],
        )) {
            $0.fileManagerWindowClient.open = { _ in
                openCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.lifecycle(.openInitialWindowIfNeeded))
        await store.send(.lifecycle(.openInitialWindowIfNeeded))

        XCTAssertEqual(openCallCount.value, 0, "기존 window가 있으면 openInitialWindowIfNeeded는 open client를 다시 호출하지 않아야 한다")
    }

    // MARK: - FMW-001-open_new_file_manager_window

    /// FMW-001-open_new_file_manager_window: 새 윈도우 생성 및 활성 윈도우 추적
    /// newWindow 액션이 새 윈도우 세션을 생성하고 focusedWindowID를 갱신하는지 검증.
    /// windowIDChanged 및 applyAppPreferences child action이 newID로 방출되는지,
    /// fileManagerWindowClient.open(newID)가 정확히 한 번 호출되는지도 함께 검증.
    /// (open_window_creates_new_workspace_session = true)
    /// - 검증 내용: newWindow 전송 후 windows 배열에 새 항목 추가, focusedWindowID 갱신,
    ///   windowIDChanged child action 수신, applyAppPreferences child action 수신,
    ///   client.open 호출 횟수 및 전달된 ID
    /// - 사전 조건: 빈 윈도우 상태, 온보딩 불필요, UUID 고정
    /// - 기대 결과: windows.count == 1, focusedWindowID == newID,
    ///   windowIDChanged 수신, applyAppPreferences 수신, openCallCount == 1, openedID == newID
    func test_openNewFileManagerWindow_createsWindowAndSetsActive() async {
        let newID = UUID()
        let openedIDs = LockIsolated<[UUID]>([])

        let store = makeStore(uuid: newID) {
            $0.fileManagerWindowClient.open = { id in
                openedIDs.withValue { $0.append(id) }
            }
        }

        // store.exhaustivity = .off: 새 윈도우 생성은 downstream 초기화 액션까지 이어져 핵심 app-scoped 수신만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }

        // windowIDChanged child action이 newID로 방출되었는지 수신 확인
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(receivedID)))))),
            )) = action else {
                return false
            }
            return id == newID && receivedID == newID
        }

        // applyAppPreferences child action이 newID로 방출되었는지 수신 확인
        let defaultPackagePrefs = AppPreferencesState().toPackageState()
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == newID && preferences == defaultPackagePrefs
        }

        // 나머지 파생 이펙트(arrangements 정렬/그룹 갱신)는 package-scoped 테스트가 검증
        await store.finish()

        XCTAssertEqual(openedIDs.value.count, 1, "fileManagerWindowClient.open은 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(openedIDs.value.first, newID, "open에 전달된 ID는 생성된 윈도우 ID와 일치해야 한다")
    }

    // MARK: - FMW-001-close_file_manager_window

    /// FMW-001-close_file_manager_window: focused 윈도우 닫기 시 포커스 이전
    /// windowClosed 이벤트가 focused 윈도우를 제거하고 다음 윈도우로 포커스를 이전하는지 검증.
    /// 나머지 윈도우 상태는 보존된다.
    /// (close_window_preserves_other_windows = true)
    /// - 검증 내용: focused 윈도우 제거 후 나머지 윈도우 보존, focusedWindowID 이전
    /// - 사전 조건: 2개 윈도우(first=focused, second=background) 존재
    /// - 기대 결과: windows에서 firstID 제거, focusedWindowID == secondID
    func test_closeFocusedWindow_removesWindowAndPreservesOthers() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = makeState(
            focusedID: firstID,
            windows: [(firstID, Spec.firstPath), (secondID, Spec.secondPath)],
        )
        initialState.lastUsedWindowIDs = [firstID, secondID]
        let store = makeStore(initialState: initialState)

        await store.send(.event(.windowClosed(firstID))) {
            $0.windows.remove(id: firstID)
            $0.focusedWindowID = secondID
            $0.lastUsedWindowIDs = [secondID]
        }
    }

    /// FMW-001-close_file_manager_window: focused 윈도우 없을 때 closeFocusedWindow no-op
    /// focused 윈도우가 없을 때 closeFocusedWindow 액션이 no-op인지 검증.
    /// - 검증 내용: focusedWindowID == nil일 때 closeFocusedWindow 액션 전송 후 상태 변화 없음
    /// - 사전 조건: 윈도우 없는 빈 상태
    /// - 기대 결과: 상태 변화 없음, no-op
    func test_closeFocusedWindow_noOpWhenNoFocusedWindow() async {
        let store = makeStore()

        await store.send(.window(.closeFocusedWindow))
    }

    /// FMW-001-close_file_manager_window: closeFocusedWindow 액션의 client.close 호출 검증
    /// window(.closeFocusedWindow) 액션이 fileManagerWindowClient.close를
    /// focusedID 인자로 정확히 한 번 호출하는지 검증.
    /// - 검증 내용: closeFocusedWindow 전송 시 client.close 호출 횟수 및 전달된 ID
    /// - 사전 조건: focusedID에 해당하는 윈도우 1개 존재
    /// - 기대 결과: closeCallCount == 1, closedID == focusedID
    func test_closeFocusedWindowAction_invokesClientClose() async {
        let focusedID = UUID()
        let closedIDs = LockIsolated<[UUID]>([])

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.tempPath)],
        )) {
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
            }
        }

        await store.send(.window(.closeFocusedWindow))

        XCTAssertEqual(closedIDs.value.count, 1, "fileManagerWindowClient.close는 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(closedIDs.value.first, focusedID, "close에 전달된 ID는 focusedWindowID와 일치해야 한다")
    }

    /// FMW-001-close_file_manager_window: unfocused 윈도우 닫기 시 focused 유지
    /// focused가 아닌 윈도우가 닫혀도 focused 윈도우가 유지되는지 검증.
    /// - 검증 내용: windowClosed(otherID) 전송 후 focusedID 윈도우 상태 보존
    /// - 사전 조건: 2개 윈도우(focusedID=focused, otherID=background) 존재
    /// - 기대 결과: otherID만 windows에서 제거, focusedWindowID 유지
    func test_closeUnfocusedWindow_preservesFocusedWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))

        await store.send(.event(.windowClosed(otherID))) {
            $0.windows.remove(id: otherID)
        }
    }

    // MARK: - FMW-001-quit_voyager

    /// FMW-001-quit_voyager: 모든 윈도우 종료
    /// closeAllWindows 액션이 모든 윈도우를 제거하고 focusedWindowID를 nil로 만드는지 검증.
    /// fileManagerWindowClient.closeAll이 정확히 한 번 호출되는지도 함께 검증.
    /// (quit_terminates_all_windows = true)
    /// - 검증 내용: closeAllWindows 전송 후 windows 배열 비움, focusedWindowID nil, closeAll 호출 횟수
    /// - 사전 조건: 2개 윈도우(first, second) 존재, second가 focused
    /// - 기대 결과: windows.isEmpty == true, focusedWindowID == nil, closeAllCallCount == 1
    func test_closeAllOrQuitSurrogate_terminatesAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()
        let closeAllCallCount = LockIsolated(0)

        let store = makeStore(initialState: makeState(
            focusedID: secondID,
            windows: [(firstID, Spec.firstPath), (secondID, Spec.secondPath)],
        )) {
            $0.fileManagerWindowClient.closeAll = {
                closeAllCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.window(.closeAllWindows)) {
            $0.windows.removeAll()
            $0.focusedWindowID = nil
        }

        XCTAssertEqual(closeAllCallCount.value, 1, "fileManagerWindowClient.closeAll은 정확히 한 번 호출되어야 한다")
    }

    /// CTM-001-open_new_content_tab: focused FileManager window로 새 Content Tab command 라우팅.
    /// File menu의 New Content Tab 입력은 native NSWindow tab이 아니라 focused FMW의 openNewContentTab request로 전달되어야 한다.
    func test_newTabCommand_routesToFocusedFileManagerWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))
        store.exhaustivity = .off

        await store.send(.file(.newTab))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.openNewContentTab)))) = action else {
                return false
            }
            return id == focusedID
        }
    }

    /// CTM-001-open_new_content_tab: focused window가 없으면 새 Content Tab 입력은 no-op.
    func test_newTabCommand_noOpWhenNoFocusedWindow() async {
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: nil,
            windows: [(otherID, Spec.backgroundPath)],
        ))

        await store.send(.file(.newTab))
    }

    // MARK: - FMW-001-request_undo

    /// FMW-001-request_undo: focused 윈도우로 명령 라우팅
    /// focused 윈도우가 있을 때 edit 명령이 focused 윈도우로만 라우팅되는지 검증.
    /// (window_commands_apply_to_active_window = true)
    /// - 검증 내용: edit(.requestUndo) 전송 시 focusedID로만 `.windows(.element(... .request(.requestUndo)))` 방출
    /// - 사전 조건: 2개 윈도우(focusedID, otherID) 존재
    /// - 기대 결과: 명령이 focusedID 윈도우로만 라우팅, otherID 상태 불변
    func test_focusedWindowCommandForwarding_routesToActiveWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))

        // store.exhaustivity = .off: 라우팅 목적 테스트라 child reducer 내부 수신 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // edit(.requestUndo)는 sendCommandToFocusedWindow을 통해 focusedID로만 전달
        await store.send(.edit(.requestUndo))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.requestUndo)))) = action else {
                return false
            }
            return id == focusedID
        }
    }

    /// FMW-001-request_undo: focused 윈도우 없을 때 명령 no-op
    /// focused 윈도우가 없을 때 edit 명령이 no-op인지 검증.
    /// - 검증 내용: focusedWindowID == nil일 때 edit(.requestUndo) 전송 후 상태 변화 없음
    /// - 사전 조건: 윈도우 1개(otherID) 존재하지만 focused 없음
    /// - 기대 결과: 상태 변화 없음, sendCommandToFocusedWindow이 .none 반환
    func test_noFocusedWindow_commandIsNoOp() async {
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: nil,
            windows: [(otherID, Spec.backgroundPath)],
        ))

        // focusedWindowID가 nil이면 sendCommandToFocusedWindow이 .none 반환
        await store.send(.edit(.requestUndo))
    }

    // MARK: - FMW-001-request_redo

    /// FMW-001-request_redo: 멀티 윈도우 명령 격리성
    /// 명령이 focused 윈도우에만 적용되고 다른 윈도우 상태는 불변인지 검증.
    /// - 검증 내용: edit(.requestRedo) 전송 시 `.windows(.element(... .request(.requestRedo)))` 방출
    /// - 사전 조건: 2개 윈도우(focusedID=focused, backgroundID=background) 존재
    /// - 기대 결과: focusedID로만 명령 전달, backgroundID 상태 변화 없음
    func test_multiWindowTargetIsolation_commandAffectsOnlyActiveWindow() async {
        let focusedID = UUID()
        let backgroundID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (backgroundID, Spec.backgroundPath)],
        ))

        // store.exhaustivity = .off: 라우팅 목적 테스트라 child reducer 내부 수신 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // 명령 전송 후 상태 변화 없음 (라우팅만 발생, 불변 상태)
        await store.send(.edit(.requestRedo))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.requestRedo)))) = action else {
                return false
            }
            return id == focusedID
        }
    }

    /// 두 window의 explicit Chat 선택은 각 window의 다음 New Chat에만 적용된다.
    /// - 검증 내용: A의 OpenAI/high와 B의 Anthropic/none 선택 및 focused New Chat 결과
    /// - 사전 조건: 두 window의 inspector Chat catalog에 두 모델이 로드되어 있다.
    /// - 기대 결과: 각 New Chat은 자기 window의 마지막 explicit pair를 사용하고 다른 window 선택을 변경하지 않는다.
    func test_multiWindowExplicitChatSelectionsApplyOnlyToEachNextNewChat() async {
        let openAIModel = Self.makeChatModel(
            provider: .openai,
            rawValue: "gpt-5",
            supportsThinkingNone: false,
        )
        let anthropicModel = Self.makeChatModel(
            provider: .anthropic,
            rawValue: "claude-sonnet",
            supportsThinkingNone: true,
        )
        let firstID = UUID()
        let secondID = UUID()
        var firstWindow = FileManagerWindowFeature.State.makeInitial(path: Spec.firstPath)
        Self.prepareChatInspector(&firstWindow, models: [openAIModel, anthropicModel])
        var secondWindow = FileManagerWindowFeature.State.makeInitial(path: Spec.secondPath)
        Self.prepareChatInspector(&secondWindow, models: [openAIModel, anthropicModel])
        var initialState = WindowManagerFeature.State()
        initialState.windows = .init(uniqueElements: [
            WindowSessionState(id: firstID, window: firstWindow),
            WindowSessionState(id: secondID, window: secondWindow),
        ])
        initialState.focusedWindowID = firstID
        let store = makeStore(initialState: initialState) {
            $0.uuid = .incrementing
            $0.aiChatDefaultSettingsClient.load = { .default }
        }
        // store.exhaustivity = .off: WindowManager와 두 FileManager child의 production routing 결과만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.windows(.element(
            id: firstID,
            action: .window(.inspector(.aiChat(.selectedModelChanged(openAIModel.id)))),
        )))
        await store.send(.windows(.element(
            id: firstID,
            action: .window(.inspector(.aiChat(.selectedThinkingChanged(.effort(.high))))),
        )))
        await store.send(.windows(.element(
            id: secondID,
            action: .window(.inspector(.aiChat(.selectedModelChanged(anthropicModel.id)))),
        )))
        await store.send(.windows(.element(
            id: secondID,
            action: .window(.inspector(.aiChat(.selectedThinkingChanged(AiThinkingSelection.none)))),
        )))

        XCTAssertEqual(
            store.state.windows[id: firstID]?.window.lastExplicitAiChatSelection,
            FileManagerAiChatSelection(modelHandle: openAIModel.id, thinking: .effort(.high)),
        )
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.lastExplicitAiChatSelection,
            FileManagerAiChatSelection(modelHandle: anthropicModel.id, thinking: AiThinkingSelection.none),
        )

        await store.send(.edit(.newChat))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.internal(.applyInspectorNewChatSeed(application))),
            )) = action else { return false }
            return id == firstID
                && application.seed == AiChatNewChatSelectionSeed(
                    modelHandle: openAIModel.id,
                    selectedThinking: .effort(.high),
                )
        }
        await store.finish()

        XCTAssertEqual(store.state.windows[id: firstID]?.window.inspector.aiChat.selectedModelHandle, openAIModel.id)
        XCTAssertEqual(store.state.windows[id: firstID]?.window.inspector.aiChat.selectedThinking, .effort(.high))
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.inspector.aiChat.selectedModelHandle,
            anthropicModel.id,
        )
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.inspector.aiChat.selectedThinking,
            AiThinkingSelection.none,
        )

        await store.send(.event(.windowBecameKey(secondID)))
        await store.send(.edit(.newChat))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.internal(.applyInspectorNewChatSeed(application))),
            )) = action else { return false }
            return id == secondID
                && application.seed == AiChatNewChatSelectionSeed(
                    modelHandle: anthropicModel.id,
                    selectedThinking: AiThinkingSelection.none,
                )
        }
        await store.finish()

        XCTAssertEqual(store.state.windows[id: firstID]?.window.inspector.aiChat.selectedModelHandle, openAIModel.id)
        XCTAssertEqual(store.state.windows[id: firstID]?.window.inspector.aiChat.selectedThinking, .effort(.high))
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.inspector.aiChat.selectedModelHandle,
            anthropicModel.id,
        )
        XCTAssertEqual(
            store.state.windows[id: secondID]?.window.inspector.aiChat.selectedThinking,
            AiThinkingSelection.none,
        )
    }

    /// window state를 재생성하면 window-last는 사라지고 persisted Chat default가 다음 New Chat에 적용된다.
    /// - 검증 내용: 재생성 전후 lastExplicitAiChatSelection lifetime과 persisted fallback 결과
    /// - 사전 조건: 이전 window에는 OpenAI/high가 있었고 persisted default는 Anthropic/none이다.
    /// - 기대 결과: 새 window의 window-last는 nil이며 다음 New Chat은 Anthropic/none으로 시작한다.
    func test_recreatedWindowClearsLastChatSelectionAndUsesPersistedDefault() async {
        let previousModel = Self.makeChatModel(
            provider: .openai,
            rawValue: "gpt-5",
            supportsThinkingNone: false,
        )
        let persistedModel = Self.makeChatModel(
            provider: .anthropic,
            rawValue: "claude-sonnet",
            supportsThinkingNone: true,
        )
        var previousWindow = FileManagerWindowFeature.State.makeInitial(path: Spec.firstPath)
        previousWindow.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: previousModel.id,
            thinking: .effort(.high),
        )
        XCTAssertNotNil(previousWindow.lastExplicitAiChatSelection)

        let recreatedID = UUID()
        var recreatedWindow = FileManagerWindowFeature.State.makeInitial(path: Spec.firstPath)
        Self.prepareChatInspector(&recreatedWindow, models: [previousModel, persistedModel])
        var initialState = WindowManagerFeature.State()
        initialState.windows = .init(uniqueElements: [
            WindowSessionState(id: recreatedID, window: recreatedWindow),
        ])
        initialState.focusedWindowID = recreatedID
        let persistedSettings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: AiProvider.anthropic.rawValue),
            model: PersistedAIModelSelection(
                providerRawValue: AiProvider.anthropic.rawValue,
                modelRawValue: persistedModel.rawModelID,
            ),
            thinking: .none,
        )
        let store = makeStore(initialState: initialState) {
            $0.uuid = .incrementing
            $0.aiChatDefaultSettingsClient.load = { persistedSettings }
        }
        // store.exhaustivity = .off: 재생성된 window lifetime과 persisted fallback의 최종 selection만 검증한다.
        store.exhaustivity = .off

        XCTAssertNil(store.state.windows[id: recreatedID]?.window.lastExplicitAiChatSelection)

        await store.send(.edit(.newChat))
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.internal(.applyInspectorNewChatSeed(application))),
            )) = action else { return false }
            return id == recreatedID
                && application.seed == AiChatNewChatSelectionSeed(
                    modelHandle: persistedModel.id,
                    selectedThinking: AiThinkingSelection.none,
                )
        }
        await store.finish()

        XCTAssertEqual(
            store.state.windows[id: recreatedID]?.window.inspector.aiChat.selectedModelHandle,
            persistedModel.id,
        )
        XCTAssertEqual(
            store.state.windows[id: recreatedID]?.window.inspector.aiChat.selectedThinking,
            AiThinkingSelection.none,
        )
        XCTAssertNil(store.state.windows[id: recreatedID]?.window.lastExplicitAiChatSelection)
    }

    /// 등록은 native activation을 한 번 요청하지만 didBecomeKey 전에는 waiter를 완료하지 않는다.
    func test_activationTrackerWaitsForDidBecomeKeyAfterRegistration() async {
        let windowID = UUID()
        let tracker = FileManagerWindowActivationTracker()
        let requestStarted = expectation(description: "activation requests started")
        requestStarted.expectedFulfillmentCount = 2
        var activationCount = 0

        let firstRequest = Task { @MainActor in
            requestStarted.fulfill()
            return await tracker.request(windowID)
        }
        let secondRequest = Task { @MainActor in
            requestStarted.fulfill()
            return await tracker.request(windowID)
        }
        await fulfillment(of: [requestStarted], timeout: 1)

        XCTAssertEqual(tracker.pendingWindowIDs, [windowID])
        tracker.consumeRegistration(for: windowID) {
            activationCount += 1
        }
        tracker.consumeRegistration(for: windowID) {
            activationCount += 1
        }

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(tracker.pendingWindowIDs, [windowID], "didBecomeKey 전에는 waiter가 pending이어야 한다")

        tracker.complete(windowID, result: .becameKey)
        let results = await (firstRequest.value, secondRequest.value)

        XCTAssertEqual(results.0, .becameKey)
        XCTAssertEqual(results.1, .becameKey)
        XCTAssertTrue(tracker.pendingWindowIDs.isEmpty)
    }

    /// waiter 설치 중 동기 didBecomeKey가 발생해도 요청은 정확히 한 번 완료된다.
    func test_activationTrackerInstallsWaiterBeforeSynchronousActivationCallback() async {
        let windowID = UUID()
        let tracker = FileManagerWindowActivationTracker()
        var activationCount = 0

        let result = await tracker.request(windowID) {
            activationCount += 1
            tracker.complete(windowID, result: .becameKey)
        }

        XCTAssertEqual(result, .becameKey)
        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(tracker.pendingWindowIDs.isEmpty)
    }

    /// request가 MainActor에 도착하기 전에 discard되면 다음 request가 tombstone을 소비하고 즉시 종료한다.
    func test_activationTrackerConsumesPreDiscardOnNextRequest() async {
        let windowID = UUID()
        let tracker = FileManagerWindowActivationTracker()
        let requestCompleted = expectation(description: "pre-discarded request completed")
        let result = LockIsolated<FileManagerWindowActivationResult?>(nil)
        var activationCount = 0

        tracker.discard(windowID)
        let request = Task { @MainActor in
            let activationResult = await tracker.request(windowID) {
                activationCount += 1
            }
            result.setValue(activationResult)
            requestCompleted.fulfill()
        }

        await fulfillment(of: [requestCompleted], timeout: 1)
        if result.value == nil {
            request.cancel()
        }
        await request.value

        XCTAssertEqual(result.value, .discarded)
        XCTAssertEqual(activationCount, 0)
        XCTAssertTrue(tracker.pendingWindowIDs.isEmpty)
        XCTAssertTrue(tracker.discardedWindowIDs.isEmpty)
    }

    /// discardAll이 사이에 실행돼도 이전 pre-discard tombstone은 후속 request까지 보존한다.
    func test_activationTrackerPreservesPreDiscardAcrossDiscardAll() async {
        let preDiscardedWindowID = UUID()
        let closeAllWindowID = UUID()
        let tracker = FileManagerWindowActivationTracker()

        tracker.discard(preDiscardedWindowID)
        tracker.discardAll([closeAllWindowID])

        let result = await tracker.request(preDiscardedWindowID)

        XCTAssertEqual(result, .discarded)
        XCTAssertEqual(tracker.discardedWindowIDs, [closeAllWindowID])
        XCTAssertTrue(tracker.pendingWindowIDs.isEmpty)
    }

    /// tombstone은 새 등록과 request 소비로 제거되고 closeAll 및 상한으로 누적을 제한한다.
    func test_activationTrackerCleansDiscardedLifecycleTombstones() {
        let staleWindowID = UUID()
        let registeredWindowID = UUID()
        let closeAllWindowID = UUID()
        let tracker = FileManagerWindowActivationTracker()

        tracker.discard(staleWindowID)
        tracker.discard(registeredWindowID)
        tracker.consumeRegistration(for: registeredWindowID) {}

        XCTAssertEqual(tracker.discardedWindowIDs, [staleWindowID])

        tracker.discardAll([closeAllWindowID])

        XCTAssertEqual(tracker.discardedWindowIDs, [staleWindowID, closeAllWindowID])

        for _ in 0 ... FileManagerWindowActivationTracker.discardedWindowLimit {
            tracker.discard(UUID())
        }

        XCTAssertEqual(tracker.discardedWindowIDs.count, FileManagerWindowActivationTracker.discardedWindowLimit)
    }

    /// close 계열 discard와 task cancellation은 pending activation을 discarded로 완료한다.
    func test_activationTrackerReturnsDiscardedOnDiscardAndCancellation() async {
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let tracker = FileManagerWindowActivationTracker()
        let requestStarted = expectation(description: "discard requests started")
        requestStarted.expectedFulfillmentCount = 2

        let firstRequest = Task { @MainActor in
            requestStarted.fulfill()
            return await tracker.request(firstWindowID)
        }
        let secondRequest = Task { @MainActor in
            requestStarted.fulfill()
            return await tracker.request(secondWindowID)
        }
        await fulfillment(of: [requestStarted], timeout: 1)

        XCTAssertEqual(Set(tracker.pendingWindowIDs), Set([firstWindowID, secondWindowID]))

        tracker.discard(firstWindowID)
        tracker.discardAll()
        let discardedResults = await (firstRequest.value, secondRequest.value)

        XCTAssertEqual(discardedResults.0, .discarded)
        XCTAssertEqual(discardedResults.1, .discarded)
        XCTAssertTrue(tracker.pendingWindowIDs.isEmpty)

        let cancelledWindowID = UUID()
        let cancellationStarted = expectation(description: "cancelled request started")
        let cancellationCompletionCount = LockIsolated(0)
        let cancelledRequest = Task { @MainActor in
            cancellationStarted.fulfill()
            let result = await tracker.request(cancelledWindowID)
            cancellationCompletionCount.withValue { $0 += 1 }
            return result
        }
        await fulfillment(of: [cancellationStarted], timeout: 1)
        XCTAssertEqual(tracker.pendingWindowIDs, [cancelledWindowID])
        cancelledRequest.cancel()

        let cancelledResult = await cancelledRequest.value
        tracker.complete(cancelledWindowID, result: .becameKey)

        XCTAssertEqual(cancelledResult, .discarded)
        XCTAssertEqual(cancellationCompletionCount.value, 1)
        XCTAssertTrue(tracker.pendingWindowIDs.isEmpty)
    }
}

private extension FileManagerWindowManagerTests {
    static func makeChatModel(
        provider: AiProvider,
        rawValue: String,
        supportsThinkingNone: Bool,
    ) -> AiProviderModel {
        AiProviderModel(
            id: .init(provider: provider, rawValue: rawValue),
            provider: provider,
            rawModelID: rawValue,
            displayName: rawValue,
            providerDisplayName: provider.rawValue,
            thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
            supportsThinkingNone: supportsThinkingNone,
        )
    }

    static func prepareChatInspector(
        _ state: inout FileManagerWindowFeature.State,
        models: [AiProviderModel],
    ) {
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loaded(models),
        )
    }
}

// WindowManagerTests 공용 테스트 서포트.

enum WindowManagerTestSupport {
    enum Spec {
        static let focusedPath = "/focused"
        static let backgroundPath = "/background"
        static let firstPath = "/a"
        static let secondPath = "/b"
        static let tempPath = "/tmp"
    }

    @MainActor
    static func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        onboardingRequired: Bool = false,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            if let uuid {
                $0.uuid = .constant(uuid)
            }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { onboardingRequired }
            configureDependencies?(&$0)
        }
    }

    @MainActor
    static func makeState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
    ) -> WindowManagerFeature.State {
        var state = WindowManagerFeature.State()
        state.windows = .init(uniqueElements: windows.map { id, path in
            WindowSessionState(id: id, window: .makeInitial(path: path))
        })
        state.focusedWindowID = focusedID
        return state
    }
}
