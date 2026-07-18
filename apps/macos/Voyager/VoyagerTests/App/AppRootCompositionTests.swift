import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class AppRootCompositionTests: XCTestCase {
    /// Task 3: terminating 상태에서는 unlocked delegate를 거부한다.
    func testLifecycleUnlockedRejectedWhenTerminating() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.unlocked(snapshot))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    // MARK: - Task 4: session-end and termination child routing

    /// Task 4: termination(.willTerminate)는 child appWillTerminate를 보낸다.
    /// RED: 현재 코드는 보내지 않으므로 이 receive가 실패한다.
    func testTerminationWillTerminateSendsChildAppWillTerminate() async {
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.termination(.willTerminate)) {
            $0.accessGatePhase = .terminating
        }

        // Task 4가 적용되면 child가 appWillTerminate를 수신한다.
        await store.receive(\.accountAccess.appWillTerminate)
        await store.finish()
    }

    /// Task 4: terminating 상태에서는 recoveryRequired delegate를 거부한다.
    func testLifecycleRecoveryRequiredRejectedWhenTerminating() async {
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 4 QA: terminating phase는 nil attemptID에서도 unlocked delegate를 거부한다.
    func testLifecycleUnlockedRejectedWhenTerminatingPhaseOnly() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .terminating
        // terminationAttemptID는 nil — completeTerminationAttempt 이후 상태 시뮬레이션

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.unlocked(snapshot))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 4 QA: terminating phase는 nil attemptID에서도 recoveryRequired delegate를 거부한다.
    func testLifecycleRecoveryRequiredRejectedWhenTerminatingPhaseOnly() async {
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired))))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    /// Task 4 QA: terminating phase는 nil attemptID에서도 signedOut delegate를 거부한다.
    func testLifecycleSignedOutRejectedWhenTerminatingPhaseOnly() async {
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .terminating

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        }
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.signedOut)))

        XCTAssertEqual(store.state.accessGatePhase, .terminating)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    // MARK: - VOY-521 Auth callback canonical routing

    func testAppDelegateIgnoresUnsupportedURLsAndRoutesVoyagerDeepLinks() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager" // Prod identity for test focus

        try appDelegate.application(NSApp, open: [XCTUnwrap(URL(string: "https://example.com"))])
        appDelegate.application(NSApp, open: [])

        XCTAssertTrue(box.actions.isEmpty)

        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    // MARK: - Scheme acceptance (Dev/Prod)

    /// Dev callbackScheme에서 voyager-dev:// auth/callback이 routeAuthCallback으로 라우팅되는지 검증
    func testAppDelegateWithDevSchemeAcceptsVoyagerDevCallback() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let url = try XCTUnwrap(URL(string: "voyager-dev://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [url])

        let routed = box.actions.contains { action in
            if case let .receiveAuthCallbackURL(received) = action {
                return received == url
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    /// Dev callbackScheme에서 voyager:// URL은 무시되는지 검증 (cross-scheme rejection)
    func testAppDelegateWithDevSchemeRejectsVoyagerURL() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let voyagerURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [voyagerURL])

        let anyExternalAction = box.actions.contains { action in
            if case .receiveExternalURL = action { return true }
            if case .receiveAuthCallbackURL = action { return true }
            return false
        }
        XCTAssertFalse(anyExternalAction)
    }

    /// Prod callbackScheme에서 voyager-dev:// URL은 무시되는지 검증 (cross-scheme rejection)
    func testAppDelegateWithProdSchemeRejectsVoyagerDevURL() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager"

        let devURL = try XCTUnwrap(URL(string: "voyager-dev://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [devURL])

        let anyExternalAction = box.actions.contains { action in
            if case .receiveExternalURL = action { return true }
            if case .receiveAuthCallbackURL = action { return true }
            return false
        }
        XCTAssertFalse(anyExternalAction)
    }

    /// Prod callbackScheme에서 voyager:// deep link는 정상 라우팅되는지 검증
    func testAppDelegateWithProdSchemeAcceptsVoyagerDeepLink() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager"

        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    /// Dev callbackScheme에서 voyager-dev:// deep link는 정상 라우팅되는지 검증
    func testAppDelegateWithDevSchemeAcceptsVoyagerDevDeepLink() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let deepLink = try XCTUnwrap(URL(string: "voyager-dev://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    // MARK: - System open callback batch ingress

    func testAppDelegateOpenURLsSendsOneOrderedFileBatch() throws {
        let box = ActionBox<AppRootAction>()
        let appDelegate = makeRecordingAppDelegate(box: box)
        appDelegate.callbackScheme = "voyager"
        let before = try XCTUnwrap(URL(string: "voyager://before"))
        let unsupported = try XCTUnwrap(URL(string: "https://example.com"))
        let after = try XCTUnwrap(URL(string: "voyager://after"))
        let folder = URL(fileURLWithPath: "/tmp/folder")
        let file = URL(fileURLWithPath: "/tmp/file.txt")
        let collection = URL(fileURLWithPath: "/tmp/saved.voycoll")

        appDelegate.application(NSApp, open: [before, folder, unsupported, file, collection, file, after])
        appDelegate.application(NSApp, open: [folder])

        XCTAssertEqual(box.externalFileBatches, [
            [folder, file, collection, file],
            [folder],
        ])
        XCTAssertEqual(box.externalFileBatchSources, [.systemOpenEvent, .systemOpenEvent])
        XCTAssertEqual(box.externalFileBatchModes, [.open, .open])
        XCTAssertEqual(box.actions.count, 4)
        guard case let .receiveExternalURL(receivedBefore) = box.actions[0] else {
            return XCTFail("첫 file batch 이전 deep link가 먼저 라우팅되어야 합니다.")
        }
        guard case .receiveExternalFileBatch = box.actions[1] else {
            return XCTFail("file batch는 첫 file URL 위치에서 라우팅되어야 합니다.")
        }
        guard case let .receiveExternalURL(receivedAfter) = box.actions[2] else {
            return XCTFail("file batch 이후 deep link가 뒤이어 라우팅되어야 합니다.")
        }
        guard case .receiveExternalFileBatch = box.actions[3] else {
            return XCTFail("별도 callback은 별도 batch를 생성해야 합니다.")
        }
        XCTAssertEqual(receivedBefore, before)
        XCTAssertEqual(receivedAfter, after)
    }

    func testAppDelegateOpenFileSendsSingletonBatch() {
        let box = ActionBox<AppRootAction>()
        let appDelegate = makeRecordingAppDelegate(box: box)
        let path = "/tmp/single.txt"

        XCTAssertTrue(appDelegate.application(NSApp, openFile: path))

        XCTAssertEqual(box.externalFileBatches, [[URL(fileURLWithPath: path)]])
        XCTAssertEqual(box.actions.count, 1)
    }

    func testAppDelegateOpenFilesRepliesOnceAfterBatchEnqueue() {
        let box = ActionBox<AppRootAction>()
        let appDelegate = ReplyRecordingAppDelegate()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        appDelegate.configure(appRootStore: store)
        appDelegate.actionCount = { box.actions.count }
        let paths = ["/tmp/folder", "/tmp/file.txt", "/tmp/saved.voycoll"]

        appDelegate.application(NSApp, openFiles: paths)

        XCTAssertEqual(box.externalFileBatches, [paths.map(URL.init(fileURLWithPath:))])
        XCTAssertEqual(box.actions.count, 1)
        XCTAssertEqual(appDelegate.replies, [.success])
        XCTAssertEqual(appDelegate.actionCountsAtReply, [1])
    }

    func testAppDelegateEmptyFileCallbacksSendNoBatch() {
        let box = ActionBox<AppRootAction>()
        let appDelegate = ReplyRecordingAppDelegate()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        appDelegate.configure(appRootStore: store)
        appDelegate.actionCount = { box.actions.count }

        appDelegate.application(NSApp, open: [])
        appDelegate.application(NSApp, openFiles: [])

        XCTAssertTrue(box.actions.isEmpty)
        XCTAssertEqual(appDelegate.replies, [.success])
        XCTAssertEqual(appDelegate.actionCountsAtReply, [0])
    }

    private func makeRecordingAppDelegate(box: ActionBox<AppRootAction>) -> AppDelegate {
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        return appDelegate
    }

    // MARK: - External open batch FIFO orchestration

    /// 겹친 batch를 enqueue해도 첫 batch만 active이고 다음 batch는 FIFO queue에 남는다.
    func testExternalOpenBatchesExecuteOneAtATimeInFIFOOrder() async throws {
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/first"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/second"))
        let firstRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(10),
            items: [
                .init(
                    itemID: UUID(11),
                    index: 0,
                    url: firstURL,
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.receiveExternalFileBatch(
            [secondURL],
            source: .systemOpenEvent,
            mode: .open,
        )) {
            $0.externalOpenBatchQueue = [AppRootExternalOpenBatch(
                request: .init(
                    batchID: UUID(0),
                    items: [
                        .init(
                            itemID: UUID(1),
                            index: 0,
                            url: secondURL,
                            source: .systemOpenEvent,
                            mode: .open,
                        ),
                    ],
                ),
                requiresInitialWindowFallback: true,
            )]
            $0.isInitialWindowFallbackPending = true
            $0.isExternalURLRouteInFlightWithoutWindow = true
        }

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request, firstRequest)
    }

    /// normalized 결과는 성공만 placement로 보내고 실패는 원래 index 순서로 보존한다.
    func testBatchNormalizedPlansSuccessesAndKeepsOrderedFailures() async throws {
        let batchID = UUID(100)
        let successID = UUID(101)
        let firstFailureID = UUID(102)
        let secondFailureID = UUID(103)
        let successURL = try XCTUnwrap(URL(string: "file:///tmp/folder"))
        let firstFailureURL = try XCTUnwrap(URL(string: "file:///tmp/missing"))
        let secondFailureURL = try XCTUnwrap(URL(string: "file:///tmp/private"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: successID, index: 0, url: successURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: firstFailureID, index: 1, url: firstFailureURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: secondFailureID, index: 2, url: secondFailureURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: successID,
                    index: 0,
                    url: successURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .success(.directory(path: "/tmp/folder", revealPath: nil)),
                ),
                .init(
                    itemID: firstFailureID,
                    index: 1,
                    url: firstFailureURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.invalidPath("/tmp/missing")),
                ),
                .init(
                    itemID: secondFailureID,
                    index: 2,
                    url: secondFailureURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.permissionDenied("/tmp/private")),
                ),
            ],
        )
        let events = LockIsolated<[String]>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in
                events.withValue { $0.append("alert") }
            }
            $0.fileManagerWindowClient.activate = { _ in
                events.withValue { $0.append("activate") }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: placement의 child mechanics는 WindowManager owner가 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result)))) {
            $0.activeExternalOpenBatch?.normalizedItems = result.items
            $0.activeExternalOpenBatch?.orderedFailures = Array(result.items.dropFirst())
            $0.activeExternalOpenBatch?.phase = .planning
        }
        XCTAssertEqual(store.state.activeExternalOpenBatch?.phase, .planning)
        await store.finish()
        XCTAssertEqual(events.value, ["alert", "alert", "activate"])
    }

    /// mixed normalization의 successful anchor는 여러 window에서도 valid input subsequence와 동일하다.
    func testMixedBatchAppliesSuccessfulAnchorsAcrossWindowsInInputOrder() async {
        let batchID = UUID(150)
        let collectionURL = URL(fileURLWithPath: "/tmp/ordered.voycoll")
        var inputs: [(URL, ExternalFileRouterBatchOutcome)] = [
            (URL(fileURLWithPath: "/tmp/missing"), .failure(.invalidPath("/tmp/missing"))),
            (URL(fileURLWithPath: "/tmp/folder"), .success(.directory(path: "/tmp/folder", revealPath: nil))),
            (URL(fileURLWithPath: "/tmp/report.txt"), .success(.directory(
                path: "/tmp",
                revealPath: "/tmp/report.txt",
            ))),
            (URL(fileURLWithPath: "/tmp/private"), .failure(.permissionDenied("/tmp/private"))),
            (collectionURL, .success(.collection(path: collectionURL.path))),
        ]
        inputs.append(contentsOf: (0 ..< 18).map { index in
            let path = "/tmp/overflow/\(index)"
            return (URL(fileURLWithPath: path), .success(.directory(path: path, revealPath: nil)))
        })
        inputs.append((URL(fileURLWithPath: "/tmp/missing-last"), .failure(.invalidPath("/tmp/missing-last"))))
        let items = inputs.enumerated().map { index, input in
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(1000 + index),
                index: index,
                url: input.0,
                source: .systemOpenEvent,
                mode: .open,
            )
        }
        let request = ExternalFileRouterBatchRequest(batchID: batchID, items: items)
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: zip(items, inputs).map { item, input in
                ExternalFileRouterBatchItemResult(
                    itemID: item.itemID,
                    index: item.index,
                    url: item.url,
                    source: item.source,
                    mode: item.mode,
                    outcome: input.1,
                )
            },
        )
        let expectedAnchors: [ContentTabPageAnchor] = [
            .directory(path: "/tmp/folder"),
            .directory(path: "/tmp"),
            .collectionFile(url: collectionURL),
        ] + (0 ..< 18).map { .directory(path: "/tmp/overflow/\($0)") }
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.fileManagerWindowClient.activate = { _ in .becameKey }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: layer별 mechanics 대신 AppRoot의 valid-subsequence composition만 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive { action in
            guard case let .windowManager(.placement(.apply(plan, reservationsByItemID))) = action else {
                return false
            }
            let appliedAnchors = plan.windows.flatMap { window in
                window.items.compactMap { reservationsByItemID[$0.itemID]?.anchor }
            }
            return appliedAnchors == expectedAnchors
        }
        await store.finish()
    }

    /// access gate가 닫히면 normalizing batch를 새 identity로 queue front에 되돌리고 Router batch를 취소한다.
    /// duplicate 항목의 identity와 FIFO 순서를 그대로 보존하는지 함께 검증한다.
    func testGateClosureRequeuesActiveNormalizationAtFront() async throws {
        let batchID = UUID(200)
        let retryBatchID = UUID(205)
        let url = try XCTUnwrap(URL(string: "file:///tmp/retry"))
        let items = [
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(201),
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
            ),
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(202),
                index: 1,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
            ),
        ]
        let request = ExternalFileRouterBatchRequest(batchID: batchID, items: items)
        let laterRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(203),
            items: [
                .init(itemID: UUID(204), index: 0, url: url, source: .deepLink, mode: .reveal),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.externalFileRouter.activeBatchID = batchID
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [UUID(206)],
        )
        initialState.externalOpenBatchQueue = [
            .init(request: laterRequest, requiresInitialWindowFallback: false),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(retryBatchID)
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [
            .init(batchID: retryBatchID, items: items),
            laterRequest,
        ])

        await store.receive(\.externalFileRouter.cancelBatch, batchID)
        XCTAssertNil(store.state.externalFileRouter.activeBatchID)
    }

    /// planning 중 gate가 닫히면 입력 identity를 보존한 새 batch로 재큐하고 old placement completion을 무시한다.
    func testGateClosureRequeuesPlanningWithFreshIdentityAndIgnoresOldCompletion() async throws {
        let batchID = UUID(210)
        let retryBatchID = UUID(211)
        let duplicateURL = try XCTUnwrap(URL(string: "file:///tmp/planning-duplicate"))
        let items = [
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(212),
                index: 0,
                url: duplicateURL,
                source: .systemOpenEvent,
                mode: .open,
            ),
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(213),
                index: 1,
                url: duplicateURL,
                source: .systemOpenEvent,
                mode: .open,
            ),
        ]
        let request = ExternalFileRouterBatchRequest(batchID: batchID, items: items)
        let laterRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(214),
            items: [
                .init(
                    itemID: UUID(215),
                    index: 0,
                    url: URL(fileURLWithPath: "/tmp/later"),
                    source: .deepLink,
                    mode: .reveal,
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [UUID(216)],
        )
        active.normalizedItems = items.map { item in
            .init(
                itemID: item.itemID,
                index: item.index,
                url: item.url,
                source: item.source,
                mode: item.mode,
                outcome: .success(.directory(path: "/tmp", revealPath: item.url.path)),
            )
        }
        active.phase = .planning
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: laterRequest, requiresInitialWindowFallback: false),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(retryBatchID)
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [
            .init(batchID: retryBatchID, items: items),
            laterRequest,
        ])

        let stalePlan = ExternalOpenPlacementPlan(batchID: batchID, windows: [])
        await store.send(.windowManager(.delegate(.externalOpenPlacementCompleted(.init(
            batchID: batchID,
            result: .success(stalePlan),
        )))))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [retryBatchID, laterRequest.batchID])
    }

    /// placement completion 직후 gate가 닫히면 이미 예약된 apply가 window를 변경하지 않고 다음 batch를 동결한다.
    func testGateClosureRevokesQueuedPlacementApplication() async throws {
        let batchID = UUID(217)
        let itemID = UUID(218)
        let windowID = UUID(219)
        let nextBatchID = UUID(220)
        let tabID = ContentTabID(rawValue: "revoked-queued-apply")
        let url = try XCTUnwrap(URL(string: "file:///tmp/revoked-queued-apply"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let nextRequest = ExternalFileRouterBatchRequest(
            batchID: nextBatchID,
            items: [
                .init(
                    itemID: UUID(221),
                    index: 0,
                    url: URL(fileURLWithPath: "/tmp/frozen-next"),
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(itemID: itemID, tabID: tabID)],
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: itemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: url.path, revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: true),
        ]
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        let openedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.open = { id in
                openedWindowIDs.withValue { $0.append(id) }
            }
        }
        // store.exhaustivity = .off: gate action을 queued apply보다 먼저 보내는 composition race만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)

        await store.send(.windowManager(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: url.path)),
            ],
        ))))
        await store.finish()

        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
        XCTAssertTrue(openedWindowIDs.value.isEmpty)
    }

    /// applying 중 gate가 닫히면 committed batch를 재큐하지 않고 old completion을 무시하며 다음 FIFO를 동결한다.
    func testGateClosureDropsApplyingBatchAndFreezesNextQueue() async throws {
        let batchID = UUID(220)
        let nextBatchID = UUID(221)
        let itemID = UUID(222)
        let nextItemID = UUID(223)
        let url = try XCTUnwrap(URL(string: "file:///tmp/applying"))
        let nextURL = try XCTUnwrap(URL(string: "file:///tmp/next-frozen"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let nextRequest = ExternalFileRouterBatchRequest(
            batchID: nextBatchID,
            items: [
                .init(itemID: nextItemID, index: 0, url: nextURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(batchID: batchID, windows: [])
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: true),
        ]
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.isExternalURLFlushDelegateScheduled = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [nextRequest])
        XCTAssertTrue(store.state.isInitialWindowFallbackPending)
        XCTAssertTrue(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertTrue(store.state.isExternalURLFlushDelegateScheduled)

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: batchID,
            result: .success(plan),
        )))))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
    }

    /// terminal phase의 마지막 batch를 drop하면 no-window bookkeeping만 정리하고 gate 뒤 창을 열지 않는다.
    func testGateClosureDropsLastApplyingBatchWithoutOpeningFallbackWindow() async throws {
        let batchID = UUID(230)
        let itemID = UUID(231)
        let url = try XCTUnwrap(URL(string: "file:///tmp/applying-last"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.placementPlan = .init(batchID: batchID, windows: [])
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.isExternalURLFlushDelegateScheduled = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        XCTAssertFalse(store.state.isInitialWindowFallbackPending)
        XCTAssertFalse(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertFalse(store.state.isExternalURLFlushDelegateScheduled)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        await store.finish()
    }

    /// stale continuation과 올바른 batch의 너무 이른 advance는 active transaction을 변경하지 않는다.
    func testStaleExternalOpenContinuationsAreNoOps() async throws {
        let batchID = UUID(300)
        let staleBatchID = UUID(399)
        let url = try XCTUnwrap(URL(string: "file:///tmp/stale"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: UUID(301), index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let failure = ExternalFileRouterBatchItemResult(
            itemID: UUID(301),
            index: 0,
            url: url,
            source: .systemOpenEvent,
            mode: .open,
            outcome: .failure(.invalidPath("/tmp/stale")),
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [failure]
        active.orderedFailures = [failure]
        active.phase = .alerting
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = active

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        let stalePlan = ExternalOpenPlacementPlan(batchID: staleBatchID, windows: [])
        let staleResult = ExternalFileRouterBatchResult(batchID: staleBatchID, items: [])

        await store.send(.externalFileRouter(.delegate(.batchNormalized(staleResult))))
        await store.send(.windowManager(.delegate(.externalOpenPlacementCompleted(.init(
            batchID: staleBatchID,
            result: .success(stalePlan),
        )))))
        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: staleBatchID,
            result: .success(stalePlan),
        )))))
        await store.send(.externalOpenAlertCompleted(.init(batchID: staleBatchID, failureIndex: 0)))
        await store.send(.windowManager(.delegate(.externalOpenActivationCompleted(
            batchID: staleBatchID,
        ))))
        await store.send(.externalOpenAdvanceToNextBatch(batchID: batchID))

        XCTAssertEqual(store.state.activeExternalOpenBatch, active)
    }

    /// 이전 batch의 placement failure는 현재 planning batch를 변경하지 않는다.
    func testStalePlacementFailureDoesNotMutateCurrentPlanningBatch() async throws {
        let staleBatchID = UUID(650)
        let currentBatchID = UUID(651)
        let currentItemID = UUID(652)
        let url = try XCTUnwrap(URL(string: "file:///tmp/current"))
        let request = ExternalFileRouterBatchRequest(
            batchID: currentBatchID,
            items: [
                .init(itemID: currentItemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: currentItemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: "/tmp/current", revealPath: nil)),
            ),
        ]
        active.phase = .planning
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.windowManager.authorizedExternalOpenBatchID = currentBatchID
        initialState.activeExternalOpenBatch = active
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.windowManager(.delegate(.externalOpenPlacementCompleted(.init(
            batchID: staleBatchID,
            result: .failure(.duplicateItemID(UUID(653))),
        )))))

        XCTAssertEqual(store.state.activeExternalOpenBatch, active)
    }

    /// matching apply failure는 current batch를 종료하고 다음 FIFO batch를 시작한다.
    func testPlacementApplyFailureAdvancesToNextBatch() async throws {
        let firstBatchID = UUID(660)
        let secondBatchID = UUID(661)
        let firstItemID = UUID(662)
        let secondItemID = UUID(663)
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/apply-failed"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/next"))
        let firstRequest = ExternalFileRouterBatchRequest(
            batchID: firstBatchID,
            items: [
                .init(itemID: firstItemID, index: 0, url: firstURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let secondRequest = ExternalFileRouterBatchRequest(
            batchID: secondBatchID,
            items: [
                .init(itemID: secondItemID, index: 0, url: secondURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(batchID: firstBatchID, windows: [])
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.windowManager.authorizedExternalOpenBatchID = firstBatchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: secondRequest, requiresInitialWindowFallback: false),
        ]
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: firstBatchID,
            result: .failure(.validationFailed),
        )))))
        await store.receive(\.externalOpenAdvanceToNextBatch, firstBatchID)

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, secondBatchID)
        await store.finish()
    }

    /// 이전 batch의 apply failure는 현재 applying batch를 변경하지 않는다.
    func testStalePlacementApplyFailureDoesNotMutateCurrentBatch() async throws {
        let staleBatchID = UUID(670)
        let currentBatchID = UUID(671)
        let itemID = UUID(672)
        let url = try XCTUnwrap(URL(string: "file:///tmp/current-apply"))
        let request = ExternalFileRouterBatchRequest(
            batchID: currentBatchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(batchID: currentBatchID, windows: [])
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = active
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: staleBatchID,
            result: .failure(.validationFailed),
        )))))

        XCTAssertEqual(store.state.activeExternalOpenBatch, active)
    }

    /// native activation이 끝나기 전에는 다음 batch를 시작하지 않는다.
    func testDelayedNativeActivationBlocksNextBatchStart() async throws {
        let firstBatchID = UUID(700)
        let secondBatchID = UUID(701)
        let firstItemID = UUID(702)
        let secondItemID = UUID(703)
        let windowID = UUID(704)
        let tabID = ContentTabID(rawValue: "activation-tab")
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/first"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/second"))
        let firstRequest = ExternalFileRouterBatchRequest(
            batchID: firstBatchID,
            items: [
                .init(itemID: firstItemID, index: 0, url: firstURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let secondRequest = ExternalFileRouterBatchRequest(
            batchID: secondBatchID,
            items: [
                .init(itemID: secondItemID, index: 0, url: secondURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: firstBatchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: firstItemID, tabID: tabID)],
                ),
            ],
        )
        let reservation = ExternalContentTabReservation(
            id: tabID,
            anchor: .directory(path: "/tmp/first"),
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [reservation],
        ))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: firstItemID,
                index: 0,
                url: firstURL,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: "/tmp/first", revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.authorizedExternalOpenBatchID = firstBatchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: secondRequest, requiresInitialWindowFallback: false),
        ]

        let activationStarted = expectation(description: "native activation started")
        let activationGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                for await _ in activationGate.stream {
                    break
                }
                return .becameKey
            }
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: child placement mechanics를 건너뛰고 activation terminal 순서만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: firstBatchID,
            result: .success(plan),
        ))))) {
            $0.activeExternalOpenBatch?.phase = .activating
        }
        await store.receive(\.windowManager.placement.activate, plan)
        await fulfillment(of: [activationStarted], timeout: 1)

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, firstBatchID)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [secondBatchID])

        activationGate.continuation.yield(())
        activationGate.continuation.finish()
        await store.receive(\.windowManager.delegate.externalOpenActivationCompleted, firstBatchID)
        await store.receive(\.externalOpenAdvanceToNextBatch, firstBatchID)

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, secondBatchID)
        await store.finish()
    }

    /// activating native effect가 지연된 동안 gate가 닫히면 late completion이 다음 batch를 시작하지 않는다.
    func testGateClosureDuringDelayedActivationDropsBatchAndFreezesNextQueue() async throws {
        let batchID = UUID(710)
        let nextBatchID = UUID(711)
        let itemID = UUID(712)
        let nextItemID = UUID(713)
        let windowID = UUID(714)
        let tabID = ContentTabID(rawValue: "gate-closure-activation-tab")
        let url = try XCTUnwrap(URL(string: "file:///tmp/activation-gate"))
        let nextURL = try XCTUnwrap(URL(string: "file:///tmp/activation-next"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let nextRequest = ExternalFileRouterBatchRequest(
            batchID: nextBatchID,
            items: [
                .init(itemID: nextItemID, index: 0, url: nextURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: itemID, tabID: tabID)],
                ),
            ],
        )
        let reservation = ExternalContentTabReservation(
            id: tabID,
            anchor: .directory(path: "/tmp/activation-gate"),
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [reservation],
        ))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: itemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: "/tmp/activation-gate", revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: false),
        ]

        let activationStarted = expectation(description: "gate closure activation started")
        let activationGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                for await _ in activationGate.stream {
                    break
                }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: child activation mechanics 대신 gate closure 이후 terminal 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: batchID,
            result: .success(plan),
        ))))) {
            $0.activeExternalOpenBatch?.phase = .activating
        }
        await store.receive(\.windowManager.placement.activate, plan)
        await fulfillment(of: [activationStarted], timeout: 1)
        let activationAttempt = try XCTUnwrap(store.state.windowManager.externalOpenActivationAttempt)

        await store.send(.lifecycle(.accountAccess(.delegate(.signedOut))))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])

        activationGate.continuation.yield(())
        activationGate.continuation.finish()
        await store.receive { action in
            guard case let .windowManager(.externalOpenActivationResult(attempt, result)) = action else {
                return false
            }
            return attempt == activationAttempt && result == .becameKey
        }

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
        await store.finish()
    }

    /// warm all-invalid batch는 ordered alerts를 끝낸 뒤 window mutation 없이 종료한다.
    func testWarmAllInvalidShowsOrderedAlertsAndMutatesNoWindows() async throws {
        let batchID = UUID(400)
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/missing"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/private"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: UUID(401), index: 0, url: firstURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: UUID(402), index: 1, url: secondURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: UUID(401),
                    index: 0,
                    url: firstURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.invalidPath("/tmp/missing")),
                ),
                .init(
                    itemID: UUID(402),
                    index: 1,
                    url: secondURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.permissionDenied("/tmp/private")),
                ),
            ],
        )
        let alerts = LockIsolated<[String]>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, message in
                alerts.withValue { $0.append(message) }
            }
        }
        // store.exhaustivity = .off: ordered terminal actions의 state 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive(
            \.externalOpenAlertCompleted,
            ExternalOpenAlertCompletion(batchID: batchID, failureIndex: 0),
        )
        await store.receive(
            \.externalOpenAlertCompleted,
            ExternalOpenAlertCompletion(batchID: batchID, failureIndex: 1),
        )
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertEqual(alerts.value.count, 2)
        XCTAssertFalse(alerts.value[0].contains("/tmp/private"))
        XCTAssertTrue(alerts.value[1].contains("/tmp/private"))
    }

    /// cold all-invalid batch는 queue drain 뒤 ordinary initial-window fallback을 정확히 한 번 재개한다.
    func testColdAllInvalidResumesInitialWindowAfterQueueDrain() async throws {
        let batchID = UUID(500)
        let url = try XCTUnwrap(URL(string: "file:///tmp/missing"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: UUID(501), index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: UUID(501),
                    index: 0,
                    url: url,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.invalidPath("/tmp/missing")),
                ),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: ordinary Home window 생성의 세부 mechanics는 WindowManager owner가 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive(
            \.externalOpenAlertCompleted,
            ExternalOpenAlertCompletion(batchID: batchID, failureIndex: 0),
        )
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertFalse(store.state.isInitialWindowFallbackPending)
        await store.finish()
    }

    /// alert 처리 중 도착한 batch는 active를 교체하지 않고 FIFO queue에 대기한다.
    func testBatchQueuedDuringAlertDoesNotReplaceActiveBatch() async throws {
        let activeURL = try XCTUnwrap(URL(string: "file:///tmp/active"))
        let queuedURL = try XCTUnwrap(URL(string: "file:///tmp/queued"))
        let activeRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(600),
            items: [
                .init(itemID: UUID(601), index: 0, url: activeURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: activeRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.phase = .alerting
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.activeExternalOpenBatch = active

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        // store.exhaustivity = .off: generated queue identity는 URL order로 검증함.
        store.exhaustivity = .off

        await store.send(.receiveExternalFileBatch(
            [queuedURL],
            source: .systemOpenEvent,
            mode: .open,
        ))

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request, activeRequest)
        XCTAssertEqual(store.state.externalOpenBatchQueue.flatMap { $0.request.items.map(\.url) }, [queuedURL])
    }
}

// MARK: - VOY-521 Task 1 test support

private final class ActionBox<T>: @unchecked Sendable {
    var actions: [T] = []
}

private extension ActionBox where T == AppRootAction {
    var externalFileBatches: [[URL]] {
        actions.compactMap { action in
            guard case let .receiveExternalFileBatch(urls, _, _) = action else { return nil }
            return urls
        }
    }

    var externalFileBatchSources: [RouteSource] {
        actions.compactMap { action in
            guard case let .receiveExternalFileBatch(_, source, _) = action else { return nil }
            return source
        }
    }

    var externalFileBatchModes: [DeepLinkMode] {
        actions.compactMap { action in
            guard case let .receiveExternalFileBatch(_, _, mode) = action else { return nil }
            return mode
        }
    }
}

private final class ReplyRecordingAppDelegate: AppDelegate {
    var actionCount: () -> Int = { 0 }
    var replies: [NSApplication.DelegateReply] = []
    var actionCountsAtReply: [Int] = []

    override func reply(
        toOpenOrPrint reply: NSApplication.DelegateReply,
        sender _: NSApplication,
    ) {
        replies.append(reply)
        actionCountsAtReply.append(actionCount())
    }
}

private struct _ActionRecordingAppRoot: Reducer {
    typealias State = AppRootState
    typealias Action = AppRootAction

    let box: ActionBox<AppRootAction>

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            box.actions.append(action)
            return .none
        }
    }
}
