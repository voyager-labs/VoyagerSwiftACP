import Clocks
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntryCoreClient
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesEntryOperations
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
    func testLiveUndoManagerClientUsesCanonicalRegistryStackForSequentialUndo() async throws {
        let windowID = UUID()
        let ownerID = UUID()
        let registry = FileOperationUndoManagerRegistry()
        let window = FileManagerWindowState.makeInitial(path: "/active")
        let activeTabID = try XCTUnwrap(window.contentTabs.activeTabID)
        let scope = UndoManagerScope(windowID: windowID, contentTabID: activeTabID.rawValue)
        let nativeUndoManager = registry.activate(scope)
        let generation = try XCTUnwrap(registry.generation(for: scope))
        let client = VoyagerApp.makeUndoManagerClient(
            fileOperationUndoManagerRegistry: registry,
            resolveScope: { requestedWindowID in
                requestedWindowID == windowID ? scope : nil
            },
        )
        let firstRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/first-old", afterPath: "/first-new")],
        )
        let secondRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/second-old", afterPath: "/second-new")],
        )
        var events = client.events(windowID).makeAsyncIterator()

        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: firstRecord))
        await client.registerUndo(windowID, ownerID, firstRecord)
        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: secondRecord))
        await client.registerUndo(windowID, ownerID, secondRecord)

        let secondIdentity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: secondRecord.id)
        let firstUndo = await client.undo(windowID, expectedTarget: secondIdentity)
        let firstEvent = await events.next()
        let firstIdentity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: firstRecord.id)
        let secondUndo = await client.undo(windowID, expectedTarget: firstIdentity)
        let secondEvent = await events.next()

        XCTAssertIdentical(registry.undoManager(for: scope), nativeUndoManager)
        XCTAssertTrue(firstUndo.didInvoke)
        XCTAssertTrue(secondUndo.didInvoke)
        XCTAssertEqual(firstEvent, UndoManagerEvent(ownerID: ownerID, record: secondRecord, direction: .undo))
        XCTAssertEqual(secondEvent, UndoManagerEvent(ownerID: ownerID, record: firstRecord, direction: .undo))
        XCTAssertFalse(secondUndo.availability.canUndo)
        XCTAssertTrue(secondUndo.availability.canRedo)
        XCTAssertFalse(nativeUndoManager.canUndo)
        XCTAssertTrue(nativeUndoManager.canRedo)
        XCTAssertEqual(registry.generation(for: scope), generation)
    }

    func testSignedOutLaunchDefersInitialWindowUntilRuntimeAndWindowCompletion() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        XCTAssertFalse(store.state.lifecycle.isShellReady)
        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
        XCTAssertFalse(store.state.lifecycle.didCreateInitialWindow)

        await store.receive { action in
            guard case .windowManager(.file(.newWindow)) = action else { return false }
            return true
        }
        await store.receive(\.lifecycle.accountAccess.onAppear)

        XCTAssertTrue(store.state.lifecycle.didCreateInitialWindow)
        XCTAssertTrue(store.state.lifecycle.isShellReady)
        XCTAssertEqual(store.state.windowManager.windows.count, 1)
        await store.skipInFlightEffects()
    }

    func testExternalRouteStaysDeferredUntilActualInitialWindowCompletion() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.receiveExternalURL(url))
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        XCTAssertTrue(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertFalse(store.state.lifecycle.isShellReady)

        await store.receive(\.lifecycle.delegate.openInitialWindowIfNeeded)
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)

        await store.receive { action in
            guard case .windowManager(.file(.newWindow)) = action else { return false }
            return true
        }
        await store.receive(\.lifecycle.accountAccess.onAppear)
        XCTAssertTrue(store.state.lifecycle.didCreateInitialWindow)
        XCTAssertTrue(store.state.lifecycle.isShellReady)
        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
        await store.skipInFlightEffects()
    }

    // MARK: - Entry Core direct health probe

    func testEntryCoreHealthProbeRunsExactlyOnceAndPreservesHelperMonitoring() async {
        let probeStarted = expectation(description: "Entry Core health probe started")
        let helperStartCount = LockIsolated(0)
        let healthCalls = LockIsolated<[EntryCoreEndpoint]>([])
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryCoreEndpointClient = .live(environment: {
                [EntryCoreEndpointClient.environmentKey: "/tmp/voyager-entry-core.sock"]
            })
            $0.entryCoreClient = makeEntryCoreClient { endpoint in
                healthCalls.withValue { $0.append(endpoint) }
                probeStarted.fulfill()
                for await _ in gate.stream {
                    break
                }
                return EntryCoreHealthResult()
            }
            $0.helperAppClient = helperAppClient(startCount: helperStartCount)
            $0.helperStateClient = readyHelperStateClient
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        store.exhaustivity = .off
        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
            $0.didStartHelper = true
            $0.didStartEntryCoreHealthProbe = true
        }
        await fulfillment(of: [probeStarted], timeout: 1)
        XCTAssertEqual(healthCalls.value.map(\.path), ["/tmp/voyager-entry-core.sock"])

        gate.continuation.yield(())
        gate.continuation.finish()
        await store.receive { action in
            guard case let .entryCoreHealthProbeCompleted(result) = action else { return false }
            return result.outcome == .healthy && result.phase == .response && result.duration == .zero
        }

        XCTAssertEqual(healthCalls.value.map(\.path), ["/tmp/voyager-entry-core.sock"])
        XCTAssertGreaterThanOrEqual(helperStartCount.value, 1)
        XCTAssertTrue(store.state.didFinishLaunching)
        XCTAssertTrue(store.state.didCompleteEntryCoreHealthProbe)
        await store.finish()
    }

    func testEntryCoreHealthProbeUnavailableEnvironmentDoesNotCallHealth() async {
        let environments = [
            [String: String](),
            [EntryCoreEndpointClient.environmentKey: "relative.sock"],
        ]
        let healthCallCount = LockIsolated(0)

        for environment in environments {
            var initialState = AppLifecycleFeature.State()
            initialState.didFinishLaunching = true
            initialState.didStartHelper = true
            let store = TestStore(initialState: initialState) {
                AppLifecycleFeature()
            } withDependencies: {
                $0.continuousClock = ImmediateClock()
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.entryCoreEndpointClient = .live(environment: { environment })
                $0.entryCoreClient = makeEntryCoreClient { _ in
                    healthCallCount.withValue { $0 += 1 }
                    return EntryCoreHealthResult()
                }
                $0.onboardingWindowClient.showIfNeeded = { false }
            }
            store.exhaustivity = .off

            await store.send(.launch(.didFinishLaunching)) {
                $0.didFinishLaunching = true
                $0.didStartHelper = true
                $0.didStartEntryCoreHealthProbe = true
            }
            await store.receive { action in
                guard case let .entryCoreHealthProbeCompleted(result) = action else { return false }
                return result.outcome == .unavailable
                    && result.phase == .endpointResolution
                    && result.duration == .zero
            }
            await store.finish()
        }

        XCTAssertEqual(healthCallCount.value, 0)
    }

    func testEntryCoreHealthProbeCancellationPreservesTerminationRouting() async {
        let probeStarted = expectation(description: "Entry Core health probe started")
        let probeCancelled = expectation(description: "Entry Core health probe cancelled")
        let helperMonitorCancelled = expectation(description: "Helper monitor cancelled")
        let helperEvents = AsyncStream<Void>.makeStream()
        helperEvents.continuation.onTermination = { @Sendable _ in
            helperMonitorCancelled.fulfill()
        }
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryCoreEndpointClient = .live(environment: {
                [EntryCoreEndpointClient.environmentKey: "/tmp/voyager-entry-core.sock"]
            })
            $0.entryCoreClient = makeEntryCoreClient { _ in
                probeStarted.fulfill()
                return try await withTaskCancellationHandler {
                    try await Task.sleep(for: .seconds(60))
                    return EntryCoreHealthResult()
                } onCancel: {
                    probeCancelled.fulfill()
                }
            }
            $0.helperAppClient = HelperAppClient(
                start: {},
                stop: {},
                isRunning: { true },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { _ in },
            )
            $0.helperStateClient = readyHelperStateClient
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        store.exhaustivity = .off

        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
            $0.didStartHelper = true
            $0.didStartEntryCoreHealthProbe = true
        }
        await fulfillment(of: [probeStarted], timeout: 1)

        await store.send(.termination(.willTerminate))
        await store.receive(\.accountAccess.appWillTerminate)
        await fulfillment(of: [probeCancelled, helperMonitorCancelled], timeout: 1)
        await store.finish()
    }

    // MARK: - Helper monitoring

    func testHelperMonitorRestartsAfterTerminationEvent() async {
        let restartRequested = expectation(description: "Helper restart requested")
        let restartCount = LockIsolated(0)
        let ensureRequestCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: {},
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    guard await canLaunch() else { return }
                    let requestCount = ensureRequestCount.withValue {
                        $0 += 1
                        return $0
                    }
                    guard requestCount > 1 else { return }
                    restartCount.withValue { $0 += 1 }
                    restartRequested.fulfill()
                },
            ),
            stateClient: readyHelperStateClient,
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await Task.yield()
        helperEvents.continuation.yield(())
        await fulfillment(of: [restartRequested], timeout: 1)

        task.cancel()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(restartCount.value, 1)
    }

    func testHelperMonitorCancellationDuringGraceWindowDoesNotRestart() async {
        let clock = TestClock()
        let restartRequested = expectation(description: "Initial helper restart requested")
        let graceSleepStarted = expectation(description: "Grace window sleep started")
        let restartCount = LockIsolated(0)
        let ensureRequestCount = LockIsolated(0)
        let nowReadCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: {},
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    guard await canLaunch() else { return }
                    let requestCount = ensureRequestCount.withValue {
                        $0 += 1
                        return $0
                    }
                    guard requestCount > 1 else { return }
                    restartCount.withValue { $0 += 1 }
                    restartRequested.fulfill()
                },
            ),
            stateClient: readyHelperStateClient,
            clock: clock,
            now: {
                let count = nowReadCount.withValue {
                    $0 += 1
                    return $0
                }
                if count == 3 {
                    graceSleepStarted.fulfill()
                }
                return Date(timeIntervalSince1970: 0)
            },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await Task.yield()
        helperEvents.continuation.yield(())
        await fulfillment(of: [restartRequested], timeout: 1)

        helperEvents.continuation.yield(())
        await fulfillment(of: [graceSleepStarted], timeout: 1)

        task.cancel()
        await clock.advance(by: .seconds(5))
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(restartCount.value, 1)
    }

    func testHelperMonitorCancellationBeforeLaunchDoesNotRestart() async {
        let restartEntered = expectation(description: "Helper restart boundary entered")
        let restartCount = LockIsolated(0)
        let ensureRequestCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let restartGate = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: {},
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    let requestCount = ensureRequestCount.withValue {
                        $0 += 1
                        return $0
                    }
                    guard requestCount > 1 else { return }
                    restartEntered.fulfill()
                    for await _ in restartGate.stream {
                        break
                    }
                    guard await canLaunch() else { return }
                    restartCount.withValue { $0 += 1 }
                },
            ),
            stateClient: readyHelperStateClient,
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await Task.yield()
        helperEvents.continuation.yield(())
        await fulfillment(of: [restartEntered], timeout: 1)

        task.cancel()
        restartGate.continuation.yield(())
        restartGate.continuation.finish()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(restartCount.value, 0)
    }

    func testHelperMonitorCancellationBeforeInitialLaunchDoesNotStart() async {
        let launchEntered = expectation(description: "Initial helper launch boundary entered")
        let launchCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let launchGate = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: { launchCount.withValue { $0 += 1 } },
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    launchEntered.fulfill()
                    for await _ in launchGate.stream {
                        break
                    }
                    guard await canLaunch() else { return }
                    launchCount.withValue { $0 += 1 }
                },
            ),
            stateClient: readyHelperStateClient,
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await fulfillment(of: [launchEntered], timeout: 1)
        task.cancel()
        launchGate.continuation.yield(())
        launchGate.continuation.finish()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(launchCount.value, 0)
    }

    func testHelperMonitorCancellationDuringInitialAlignmentDoesNotRestart() async {
        let resolveEntered = expectation(description: "Initial helper state resolution entered")
        let startCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let resolveGate = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: { startCount.withValue { $0 += 1 } },
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    guard await canLaunch() else { return }
                    startCount.withValue { $0 += 1 }
                },
            ),
            stateClient: HelperStateClient(
                resolve: {
                    resolveEntered.fulfill()
                    for await _ in resolveGate.stream {
                        return nil
                    }
                    return nil
                },
                observe: { AsyncStream { $0.finish() } },
            ),
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await fulfillment(of: [resolveEntered], timeout: 1)
        XCTAssertEqual(startCount.value, 1)

        task.cancel()
        resolveGate.continuation.yield(())
        resolveGate.continuation.finish()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(startCount.value, 1)
    }

    private var accessSnapshot: AccessStatusSnapshot {
        AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
    }

    private var readyHelperStateClient: HelperStateClient {
        HelperStateClient(
            resolve: { HelperState(helperReady: true, helperBundleVersion: nil) },
            observe: { AsyncStream { $0.finish() } },
        )
    }

    private func helperAppClient(startCount: LockIsolated<Int>? = nil) -> HelperAppClient {
        HelperAppClient(
            start: { startCount?.withValue { $0 += 1 } },
            stop: {},
            isRunning: { true },
            terminationEvents: { AsyncStream { $0.finish() } },
            ensureRunning: { canLaunch in
                guard await canLaunch() else { return }
                startCount?.withValue { $0 += 1 }
            },
        )
    }

    private func makeEntryCoreClient(
        health: @escaping @Sendable (EntryCoreEndpoint) async throws -> EntryCoreHealthResult,
    ) -> EntryCoreClient {
        EntryCoreClient(
            ping: { _ in EntryCorePingResult() },
            health: health,
            version: { _ in try EntryCoreVersionResult(appVersion: "test") },
        )
    }

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

        await store.send(.termination(.willTerminate))

        // Task 4가 적용되면 child가 appWillTerminate를 수신한다.
        await store.receive(\.accountAccess.appWillTerminate)
        await store.finish()
    }

    // MARK: - App host lifecycle

    func testAppDelegateSuppressesAutomaticLifecycleDispatchDuringXCTestHosting() {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.shouldSuppressAutomaticLifecycle = { true }

        appDelegate.applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification),
        )
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification),
        )
        let shouldHandleReopen = appDelegate.applicationShouldHandleReopen(
            NSApp,
            hasVisibleWindows: false,
        )
        let terminationReply = appDelegate.applicationShouldTerminate(NSApp)

        XCTAssertTrue(box.actions.isEmpty)
        XCTAssertTrue(shouldHandleReopen)
        XCTAssertEqual(terminationReply, .terminateNow)
    }

    func testAppDelegateDispatchesDidFinishLaunchingOutsideXCTestHosting() {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.shouldSuppressAutomaticLifecycle = { false }

        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification),
        )

        XCTAssertTrue(box.actions.contains { action in
            if case .lifecycle(.launch(.didFinishLaunching)) = action {
                return true
            }
            return false
        })
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
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
        }
        // store.exhaustivity = .off: fallback window bootstrap보다 active/queued batch FIFO ownership을 검증함.
        store.exhaustivity = .off

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
            $0.isExternalURLFlushDelegateScheduled = true
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
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
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
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
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
            return plan.orderedItems.map(\.anchor) == expectedAnchors
                && reservationsByItemID.count == expectedAnchors.count
        }
        await store.finish()
    }

    /// 동일 directory route의 folder/file 요청은 AppRoot 경계에서도 기존 Content Tab 하나로 수렴한다.
    /// - 검증 내용: normalized item 순서, 기존 tab identity 재사용, 신규 reservation 미생성
    /// - 사전 조건: `/tmp/shared`를 표시하는 live window가 있고 같은 폴더와 그 안의 파일을 연속으로 요청함
    /// - 기대 결과: 두 item이 기존 tab을 공유하고 마지막 파일 reveal을 유지하며 capacity를 소비하지 않음
    func testBatchNormalizationReusesExistingTabAndConvergesDuplicateRoute() async {
        let batchID = UUID(180)
        let folderItemID = UUID(181)
        let fileItemID = UUID(182)
        let windowID = UUID(183)
        let folderURL = URL(fileURLWithPath: "/tmp/shared")
        let fileURL = URL(fileURLWithPath: "/tmp/shared/report.txt")
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: folderItemID, index: 0, url: folderURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: fileItemID, index: 1, url: fileURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: folderItemID,
                    index: 0,
                    url: folderURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .success(.directory(path: folderURL.path, revealPath: nil)),
                ),
                .init(
                    itemID: fileItemID,
                    index: 1,
                    url: fileURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .success(.directory(path: folderURL.path, revealPath: fileURL.path)),
                ),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [
            .init(id: windowID, window: .makeInitial(path: folderURL.path)),
        ]
        initialState.windowManager.focusedWindowID = windowID
        initialState.windowManager.lastUsedWindowIDs = [windowID]
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [windowID],
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerWindowClient.activate = { _ in .becameKey }
        }
        // store.exhaustivity = .off: WindowManager의 native activation 세부 action은 해당 owner suite가 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive { action in
            guard case let .windowManager(.placement(.apply(plan, reservationsByItemID))) = action else {
                return false
            }
            let items = plan.orderedItems
            return items.map(\.itemID) == [folderItemID, fileItemID]
                && Set(items.map(\.tabID)).count == 1
                && items.allSatisfy { !$0.requiresReservation }
                && items.last?.pendingSelectEntryID == fileURL.path
                && reservationsByItemID.isEmpty
        }
        await store.finish()

        XCTAssertEqual(store.state.windowManager.windows.count, 1)
        XCTAssertEqual(store.state.windowManager.windows[id: windowID]?.window.contentTabs.tabs.count, 1)
        XCTAssertEqual(
            store.state.windowManager.windows[id: windowID]?.window.content.pendingSelectEntryID,
            fileURL.path,
        )
    }

    /// termination이 시작되면 normalizing batch를 새 identity로 queue front에 되돌리고 Router batch를 취소한다.
    /// duplicate 항목의 identity와 FIFO 순서를 그대로 보존하는지 함께 검증한다.
    func testTerminationRequeuesActiveNormalizationAtFront() async throws {
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [
            .init(batchID: retryBatchID, items: items),
            laterRequest,
        ])

        await store.receive(\.externalFileRouter.cancelBatch, batchID)
        XCTAssertNil(store.state.externalFileRouter.activeBatchID)
    }

    /// planning 중 termination이 시작되면 입력 identity를 보존한 새 batch로 재큐하고 old placement completion을 무시한다.
    func testTerminationRequeuesPlanningWithFreshIdentityAndIgnoresOldCompletion() async throws {
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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

        await store.send(.lifecycle(.termination(.willTerminate)))
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

    /// placement completion 직후 termination이 시작되면 이미 예약된 apply가 window를 변경하지 않고 다음 batch를 동결한다.
    func testTerminationRevokesQueuedPlacementApplication() async throws {
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
                    items: [.init(
                        itemID: itemID,
                        tabID: tabID,
                        anchor: .directory(path: url.path),
                    )],
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
        // store.exhaustivity = .off: termination action을 queued apply보다 먼저 보내는 composition race만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
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

    /// apply가 commit한 새 window의 native open은 termination 시 batch cancellation으로 중단된다.
    func testTerminationCancelsDelayedPlacementNativeOpen() async {
        let batchID = UUID(222)
        let itemID = UUID(223)
        let windowID = UUID(224)
        let tabID = ContentTabID(rawValue: "cancelled-placement-open")
        let url = URL(fileURLWithPath: "/tmp/cancelled-placement-open")
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(
                        itemID: itemID,
                        tabID: tabID,
                        anchor: .directory(path: url.path),
                    )],
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        let openStarted = expectation(description: "placement native open started")
        let openCancelled = expectation(description: "placement native open cancelled")
        let nativeCloseCalled = expectation(description: "placement native window closed")
        let closedWindowIDs = LockIsolated<[UUID]>([])
        let openGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.uuid = .incrementing
            $0.fileManagerWindowClient.open = { id in
                XCTAssertEqual(id, windowID)
                openStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in openGate.stream {
                        break
                    }
                } onCancel: {
                    openCancelled.fulfill()
                }
            }
            $0.fileManagerWindowClient.close = { id in
                closedWindowIDs.withValue { $0.append(id) }
                nativeCloseCalled.fulfill()
            }
        }
        // store.exhaustivity = .off: child 초기화보다 batch-scoped native open cancellation 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: url.path)),
            ],
        ))))
        await fulfillment(of: [openStarted], timeout: 1)

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [openCancelled, nativeCloseCalled], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        XCTAssertNil(store.state.windowManager.retainedExternalOpenPlacementOwnership)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertTrue(store.state.windowManager.externalWindowBatchIDs.isEmpty)
        XCTAssertEqual(closedWindowIDs.value, [windowID])
        openGate.continuation.finish()
        await store.finish()
    }

    /// applying 중 termination이 시작되면 committed batch를 재큐하지 않고 old completion을 무시하며 다음 FIFO를 동결한다.
    func testTerminationDropsApplyingBatchAndFreezesNextQueue() async throws {
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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

        await store.send(.lifecycle(.termination(.willTerminate)))
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

    /// terminal phase의 마지막 batch를 drop하면 no-window bookkeeping만 정리하고 종료 중 창을 열지 않는다.
    func testTerminationDropsLastApplyingBatchWithoutOpeningFallbackWindow() async throws {
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.isExternalURLFlushDelegateScheduled = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        XCTAssertFalse(store.state.isInitialWindowFallbackPending)
        XCTAssertFalse(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertFalse(store.state.isExternalURLFlushDelegateScheduled)
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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

    /// pending singleton terminal 전에는 다음 queued batch를 active로 만들지 않는다.
    func testPendingURLTerminalBlocksNextQueuedBatchAdmission() throws {
        let activeBatchID = UUID(680)
        let activeItemID = UUID(681)
        let queuedBatchID = UUID(682)
        let queuedItemID = UUID(683)
        let windowID = UUID(684)
        let tabID = ContentTabID(rawValue: "pending-terminal-window-tab")
        let activeURL = try XCTUnwrap(URL(string: "file:///tmp/active"))
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fpending"))
        let queuedURL = try XCTUnwrap(URL(string: "file:///tmp/queued"))
        let activeRequest = ExternalFileRouterBatchRequest(
            batchID: activeBatchID,
            items: [
                .init(itemID: activeItemID, index: 0, url: activeURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let queuedRequest = ExternalFileRouterBatchRequest(
            batchID: queuedBatchID,
            items: [
                .init(itemID: queuedItemID, index: 0, url: queuedURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [
                .init(id: tabID, anchor: .directory(path: "/tmp")),
            ],
        ))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: activeRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.phase = .advancing
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.windowManager.windows = [.init(id: windowID, window: window)]
        state.pendingExternalURLs = [pendingURL]
        state.externalOpenBatchQueue = [
            .init(request: queuedRequest, requiresInitialWindowFallback: false),
        ]
        state.activeExternalOpenBatch = active
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.advanceExternalOpenBatch(batchID: activeBatchID, state: &state)
        }

        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.activePendingExternalURL, .init(requestID: UUID(0), url: pendingURL))
        XCTAssertTrue(state.pendingExternalURLs.isEmpty)
        XCTAssertEqual(state.externalOpenBatchQueue.map(\.request.batchID), [queuedBatchID])

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: UUID(999), state: &state)
        }
        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.externalOpenBatchQueue.map(\.request.batchID), [queuedBatchID])

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: UUID(0), state: &state)
        }
        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertEqual(state.activeExternalOpenBatch?.batch.request.batchID, queuedBatchID)
        XCTAssertTrue(state.externalOpenBatchQueue.isEmpty)
    }

    /// 창이 없는 all-invalid batch 종료도 pending singleton을 먼저 admit하고 terminal 뒤 queued batch를 재개한다.
    func testColdAllInvalidBatchPrioritizesPendingURLBeforeQueuedBatch() throws {
        let activeBatchID = UUID(685)
        let queuedBatchID = UUID(686)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=https%3A%2F%2Fexample.com"))
        let queuedURL = URL(fileURLWithPath: "/tmp/cold-queued")
        let activeRequest = ExternalFileRouterBatchRequest(batchID: activeBatchID, items: [])
        let queuedRequest = ExternalFileRouterBatchRequest(
            batchID: queuedBatchID,
            items: [
                .init(
                    itemID: UUID(687),
                    index: 0,
                    url: queuedURL,
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: activeRequest, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.phase = .advancing
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.activeExternalOpenBatch = active
        state.pendingExternalURLs = [pendingURL]
        state.externalOpenBatchQueue = [
            .init(request: queuedRequest, requiresInitialWindowFallback: true),
        ]
        state.isInitialWindowFallbackPending = true
        state.isExternalURLRouteInFlightWithoutWindow = true
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.advanceExternalOpenBatch(batchID: activeBatchID, state: &state)
        }

        XCTAssertTrue(state.windowManager.windows.isEmpty)
        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.activePendingExternalURL, .init(requestID: UUID(0), url: pendingURL))
        XCTAssertTrue(state.pendingExternalURLs.isEmpty)
        XCTAssertEqual(state.externalOpenBatchQueue.map(\.request.batchID), [queuedBatchID])
        XCTAssertTrue(state.isInitialWindowFallbackPending)

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: UUID(0), state: &state)
        }

        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertEqual(state.activeExternalOpenBatch?.batch.request.batchID, queuedBatchID)
        XCTAssertTrue(state.externalOpenBatchQueue.isEmpty)
        XCTAssertTrue(state.isInitialWindowFallbackPending)
    }

    /// 첫 external window가 열려도 active batch terminal 전에는 pending URL을 flush하지 않는다.
    func testFirstExternalWindowDefersPendingURLFlushUntilBatchAdvance() async throws {
        let batchID = UUID(690)
        let itemID = UUID(691)
        let windowID = UUID(692)
        let tabID = ContentTabID(rawValue: "pending-url-order-tab")
        let fileURL = try XCTUnwrap(URL(string: "file:///tmp/pending-url-order"))
        let pendingURL = try XCTUnwrap(URL(string: "voyager://pending-after-batch"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: fileURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(
                        itemID: itemID,
                        tabID: tabID,
                        anchor: .directory(path: fileURL.path),
                    )],
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
                url: fileURL,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: fileURL.path, revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.pendingExternalURLs = [pendingURL]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active

        let activationStarted = expectation(description: "native activation started")
        let activationGate = AsyncStream<Void>.makeStream()
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                for await _ in activationGate.stream {
                    break
                }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: child window mechanics를 건너뛰고 pending route ordering만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: fileURL.path)),
            ],
        ))))
        await fulfillment(of: [activationStarted], timeout: 1)

        XCTAssertEqual(store.state.pendingExternalURLs, [pendingURL])

        activationGate.continuation.yield(())
        activationGate.continuation.finish()
        await store.receive(\.windowManager.delegate.externalOpenActivationCompleted, batchID)
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)
        await store.receive { action in
            guard case let .externalFileRouter(.receiveTracked(url, requestID: _)) = action else {
                return false
            }
            return url == pendingURL
        }

        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
        await store.finish()
    }

    /// AppRoot가 matching activation failure terminal을 수락할 때 ownership을 release한 뒤 batch를 advance한다.
    /// 이후 같은 batch의 stale cancel은 성공한 window나 persistent marker를 제거하지 않는다.
    func testActivationTerminalAcceptanceReleasesPlacementOwnershipBeforeAdvance() async throws {
        let batchID = UUID()
        let itemID = UUID()
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "terminal-retained-window")
        let url = URL(fileURLWithPath: "/tmp/terminal-retained-window")
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
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
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: tabID, anchor: .directory(path: url.path)),
        ]))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .activating
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.externalWindowBatchIDs = [windowID: batchID]
        initialState.windowManager.retainedExternalOpenPlacementOwnership = .init(
            batchID: batchID,
            newWindowIDs: [windowID],
        )
        let closedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { id in
                closedWindowIDs.withValue { $0.append(id) }
            }
        }
        // store.exhaustivity = .off: AppRoot terminal acceptance와 stale cancel 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenActivationFailed(
            batchID: batchID,
            failure: .recoveryExhausted,
        )))) {
            $0.windowManager.retainedExternalOpenPlacementOwnership = nil
            $0.activeExternalOpenBatch?.phase = .advancing
        }
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)
        await store.send(.windowManager(.placement(.cancel(batchID: batchID))))
        await store.finish()

        XCTAssertEqual(store.state.windowManager.windows.map(\.id), [windowID])
        XCTAssertEqual(store.state.windowManager.externalWindowBatchIDs, [windowID: batchID])
        XCTAssertTrue(closedWindowIDs.value.isEmpty)
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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

    /// activating native effect가 지연된 동안 termination이 시작되면 late completion이 다음 batch를 시작하지 않는다.
    func testTerminationDuringDelayedActivationDropsBatchAndFreezesNextQueue() async throws {
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: false),
        ]

        let activationStarted = expectation(description: "gate closure activation started")
        let activationCancelled = expectation(description: "gate closure activation cancelled")
        let activationGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in activationGate.stream {
                        break
                    }
                } onCancel: {
                    activationCancelled.fulfill()
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
        XCTAssertNotNil(store.state.windowManager.externalOpenActivationAttempt)

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [activationCancelled], timeout: 1)
        await store.skipReceivedActions()
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])

        activationGate.continuation.finish()
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
        await store.finish()
    }

    /// final target discard 뒤 시작한 retry activation도 termination 시 같은 batch cancellation으로 중단된다.
    func testTerminationCancelsDelayedRetryActivation() async throws {
        let batchID = UUID(715)
        let firstWindowID = UUID(716)
        let finalWindowID = UUID(717)
        let firstTabID = ContentTabID(rawValue: "retry-cancel-first")
        let finalTabID = ContentTabID(rawValue: "retry-cancel-final")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(718), tabID: firstTabID)],
                ),
                .init(
                    windowID: finalWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(719), tabID: finalTabID)],
                ),
            ],
        )
        let firstWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: firstTabID, anchor: .directory(path: "/tmp/retry-cancel-first")),
        ]))
        let finalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: finalTabID, anchor: .directory(path: "/tmp/retry-cancel-final")),
        ]))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(
                    itemID: UUID(720),
                    index: 0,
                    url: URL(fileURLWithPath: "/tmp/retry-cancel"),
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .activating
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [
            .init(id: firstWindowID, window: firstWindow),
            .init(id: finalWindowID, window: finalWindow),
        ]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        let retryStarted = expectation(description: "retry activation started")
        let retryCancelled = expectation(description: "retry activation cancelled")
        let retryGate = AsyncStream<Void>.makeStream()
        let activatedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { windowID in
                activatedWindowIDs.withValue { $0.append(windowID) }
                if windowID == finalWindowID {
                    return .discarded
                }
                XCTAssertEqual(windowID, firstWindowID)
                retryStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in retryGate.stream {
                        break
                    }
                } onCancel: {
                    retryCancelled.fulfill()
                }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: retry attempt action보다 batch-scoped cancellation 전파를 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.placement(.activate(plan))))
        await fulfillment(of: [retryStarted], timeout: 1)
        XCTAssertEqual(activatedWindowIDs.value, [finalWindowID, firstWindowID])

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [retryCancelled], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        retryGate.continuation.finish()
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
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
            $0.onboardingWindowClient.isRequired = { false }
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
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
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

    /// tracked singleton이 active이면 새 batch는 queue에 남고 matching terminal 뒤에만 시작한다.
    func testBatchArrivingWhileTrackedSingletonActiveWaitsForMatchingTerminal() throws {
        let requestID = UUID(800)
        let staleRequestID = UUID(801)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fpending"))
        let batchURL = URL(fileURLWithPath: "/tmp/batch-after-singleton")
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.enqueueExternalOpenBatch(
                urls: [batchURL],
                source: .systemOpenEvent,
                mode: .open,
                state: &state,
            )
        }
        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.externalOpenBatchQueue.count, 1)

        _ = feature.consumePendingExternalURLCompletion(requestID: staleRequestID, state: &state)
        XCTAssertEqual(state.activePendingExternalURL?.requestID, requestID)
        XCTAssertNil(state.activeExternalOpenBatch)

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: requestID, state: &state)
        }
        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertNotNil(state.activeExternalOpenBatch)
        XCTAssertTrue(state.externalOpenBatchQueue.isEmpty)
    }

    /// active batch가 있으면 pending singleton은 시작되지 않는다.
    func testPendingSingletonDoesNotStartWhileBatchActive() throws {
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fpending-during-batch"))
        let batchURL = URL(fileURLWithPath: "/tmp/active-batch")
        let batch = ExternalFileRouterBatchRequest(
            batchID: UUID(810),
            items: [.init(itemID: UUID(811), index: 0, url: batchURL, source: .systemOpenEvent, mode: .open)],
        )
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.pendingExternalURLs = [pendingURL]
        state.activeExternalOpenBatch = .init(
            batch: .init(request: batch, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        withDependencies {
            $0.uuid = .incrementing
        } operation: {
            _ = AppRootFeature().startNextPendingExternalURLIfPossible(state: &state)
        }

        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertEqual(state.pendingExternalURLs, [pendingURL])
        XCTAssertEqual(state.activeExternalOpenBatch?.batch.request.batchID, batch.batchID)
    }

    /// idle warm 첫 deep link도 tracked scheduler를 시작해 뒤이은 URL을 직렬화한다.
    func testIdleWarmDeepLinksEnterTrackedSchedulerInFIFOOrder() throws {
        let windowID = UUID(805)
        let firstURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fwarm-first"))
        let secondURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fwarm-second"))
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.enqueueExternalURL(firstURL, state: &state)
            _ = feature.enqueueExternalURL(secondURL, state: &state)
        }

        XCTAssertEqual(state.activePendingExternalURL, .init(requestID: UUID(0), url: firstURL))
        XCTAssertEqual(state.pendingExternalURLs, [secondURL])
    }

    /// warm window의 새 deep link는 active singleton을 우회하지 않고 pending FIFO에 합류한다.
    func testWarmDeepLinkQueuesBehindActiveTrackedSingleton() async throws {
        let requestID = UUID(807)
        let windowID = UUID(808)
        let activeURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Factive"))
        let nextURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fnext"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        initialState.activePendingExternalURL = .init(requestID: requestID, url: activeURL)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        await store.send(.receiveExternalURL(nextURL)) {
            $0.pendingExternalURLs = [nextURL]
        }
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)
        XCTAssertEqual(store.state.windowManager.windows.ids.count, 1)
        await store.finish()
    }

    /// warm window의 새 deep link는 active batch terminal 전 Router singleton으로 진입하지 않는다.
    func testWarmDeepLinkQueuesBehindActiveBatch() async throws {
        let windowID = UUID(809)
        let batchURL = URL(fileURLWithPath: "/tmp/active-batch")
        let nextURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fnext-after-batch"))
        let batch = ExternalFileRouterBatchRequest(
            batchID: UUID(810),
            items: [.init(itemID: UUID(811), index: 0, url: batchURL, source: .systemOpenEvent, mode: .open)],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: batch, requiresInitialWindowFallback: false),
            preferredWindowIDs: [windowID],
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        await store.send(.receiveExternalURL(nextURL)) {
            $0.pendingExternalURLs = [nextURL]
        }
        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, batch.batchID)
        XCTAssertNil(store.state.activePendingExternalURL)
        await store.finish()
    }

    /// termination은 active occurrence를 front에 보존하고 stale route를 거부하며 retry identity를 갱신한다.
    func testTerminationRequeuesTrackedSingletonWithFreshIdentityAndRejectsStaleRoute() async throws {
        let oldRequestID = UUID(812)
        let freshRequestID = UUID(813)
        let duplicateURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fduplicate"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: oldRequestID, url: duplicateURL)
        initialState.pendingExternalURLs = [duplicateURL]
        initialState.externalFileRouter.activeTrackedRequestID = oldRequestID
        initialState.windowManager.authorizedTrackedSingletonRequestID = oldRequestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        // store.exhaustivity = .off: lifecycle presentation effect보다 singleton cancellation/requeue 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertEqual(store.state.pendingExternalURLs, [duplicateURL, duplicateURL])
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)
        await store.receive(\.externalFileRouter.cancelTrackedRequest, oldRequestID)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)

        await store.send(.externalFileRouter(.delegate(.openFolder(
            path: "/tmp/stale",
            trackedRequestID: oldRequestID,
        ))))
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)

        var retryState = store.state
        retryState.lifecycle.didFinishLaunching = true
        retryState.lifecycle.didStartHelper = true
        retryState.lifecycle.didCompleteEntryCoreHealthProbe = true
        retryState.lifecycle.didCreateInitialWindow = true
        withDependencies {
            $0.uuid = .constant(freshRequestID)
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = AppRootFeature().startNextPendingExternalURLIfPossible(state: &retryState)
        }
        XCTAssertEqual(
            retryState.activePendingExternalURL,
            .init(requestID: freshRequestID, url: duplicateURL),
        )
        XCTAssertEqual(retryState.pendingExternalURLs, [duplicateURL])
        XCTAssertNotEqual(oldRequestID, retryState.activePendingExternalURL?.requestID)
        await store.finish()
    }

    /// delayed native open 중 termination은 생성 session을 rollback하고 native window를 close한다.
    func testTerminationDuringDelayedTrackedNativeOpenRollsBackWindowAndRequeues() async throws {
        let requestID = UUID(818)
        let windowID = UUID(819)
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fdelayed-gate"))
        let openStarted = expectation(description: "tracked native open started")
        let closeCompleted = expectation(description: "tracked native close completed")
        let openGate = AsyncStream<Void>.makeStream()
        let closedIDs = LockIsolated<[UUID]>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
                closeCompleted.fulfill()
            }
        }
        // store.exhaustivity = .off: child 초기화 action보다 gate revoke의 rollback/close 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.openFolder(
            path: "/tmp/delayed-gate",
            trackedRequestID: requestID,
        )))) {
            $0.windowManager.authorizedTrackedSingletonRequestID = requestID
        }
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [openStarted], timeout: 1)
        XCTAssertEqual(
            store.state.windowManager.trackedSingletonWindow,
            .init(requestID: requestID, windowID: windowID),
        )
        XCTAssertEqual(store.state.windowManager.windows.ids.count, 1)

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [closeCompleted], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)
        XCTAssertNil(store.state.windowManager.trackedSingletonWindow)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)
        XCTAssertEqual(closedIDs.value, [windowID])
        openGate.continuation.finish()
        await store.finish()
    }

    /// delayed fallback revoke는 native open뿐 아니라 후속 default bootstrap도 취소한다.
    func testTerminationDuringDelayedTrackedFallbackCancelsBootstrapAndRollsBack() async throws {
        let requestID = UUID(820)
        let windowID = UUID(821)
        let url = try XCTUnwrap(URL(string: "voyager://open"))
        let openStarted = expectation(description: "tracked fallback native open started")
        let closeCompleted = expectation(description: "tracked fallback native close completed")
        let openGate = AsyncStream<Void>.makeStream()
        let ensureCount = LockIsolated(0)
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                ensureCount.withValue { $0 += 1 }
                return .init(recents: .failed, allTags: .failed)
            }
            $0.fileManagerWindowClient.open = { _ in
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
            $0.fileManagerWindowClient.close = { _ in closeCompleted.fulfill() }
        }
        // store.exhaustivity = .off: fallback revoke가 native open 이후 bootstrap까지 취소하는 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.openAppFallback(trackedRequestID: requestID)))) {
            $0.windowManager.authorizedTrackedSingletonRequestID = requestID
        }
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [openStarted], timeout: 1)
        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [closeCompleted], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertEqual(ensureCount.value, 0)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        openGate.continuation.finish()
        await store.finish()
    }

    /// native open completion 뒤 parent terminal 전 termination도 retained ownership으로 rollback한다.
    func testTerminationAfterNativeOpenBeforeParentTerminalRollsBackWindow() async throws {
        let requestID = UUID(822)
        let windowID = UUID(823)
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fterminal-gap"))
        let closeCompleted = expectation(description: "terminal-gap native close completed")
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        initialState.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/tmp/terminal-gap"))]
        initialState.windowManager.trackedSingletonWindow = .init(requestID: requestID, windowID: windowID)
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { id in
                XCTAssertEqual(id, windowID)
                closeCompleted.fulfill()
            }
            $0.undoManagerClient.invalidateWindow = { id in
                XCTAssertEqual(id, windowID)
                return .init(succeeded: true, availability: .init())
            }
        }
        // store.exhaustivity = .off: native completion과 queued parent terminal 사이 revoke ownership만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [closeCompleted], timeout: 1)
        await store.skipReceivedActions()
        XCTAssertNotNil(store.state.windowManager.windows[id: windowID])

        await store.send(.windowManager(.event(.windowClosed(windowID))))
        await store.receive(\.windowManager.windowInvalidationFinished)

        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertNil(store.state.windowManager.trackedSingletonWindow)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        await store.finish()
    }

    /// termination gate closure도 active singleton을 front에 되돌리고 Router request를 취소한다.
    func testTerminationRequeuesAndCancelsActiveTrackedSingleton() async throws {
        let requestID = UUID(814)
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Ftermination"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        initialState.windowManager.authorizedTrackedSingletonRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: termination child fanout보다 singleton requeue/cancel 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)
        await store.receive(\.externalFileRouter.cancelTrackedRequest, requestID)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)
        await store.finish()
    }

    /// invalid/permission alert는 await가 끝난 뒤에만 tracked parent를 terminal 처리한다.
    func testTrackedInvalidAlertCompletionWaitsForAlertBoundary() async throws {
        try await assertTrackedAlertCompletionWaitsForBoundary(permissionDenied: false)
    }

    func testTrackedPermissionAlertCompletionWaitsForAlertBoundary() async throws {
        try await assertTrackedAlertCompletionWaitsForBoundary(permissionDenied: true)
    }

    /// tracked auth compatibility는 identity/gate를 검증한 뒤 AccountAccess handoff 수락에서 종료한다.
    func testTrackedAuthCompatibilityTerminatesAtAccountAccessHandoff() async throws {
        let requestID = UUID(815)
        let staleRequestID = UUID(816)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=tracked"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: AccountAccess network lifecycle은 별도 owner이고 handoff terminal만 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.routeToAuthCallback(
            pendingURL,
            trackedRequestID: staleRequestID,
        ))))
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)

        await store.send(.externalFileRouter(.delegate(.routeToAuthCallback(
            pendingURL,
            trackedRequestID: requestID,
        ))))
        await store.receive(\.receiveTrackedAuthCallbackURL)
        await store.receive(\.lifecycle.accountAccess.loginCallbackReceived)
        await store.receive(\.externalFileRouter.singletonRequestCompleted, requestID)
        XCTAssertNil(store.state.activePendingExternalURL)
        await store.finish()
    }

    private func assertTrackedAlertCompletionWaitsForBoundary(permissionDenied: Bool) async throws {
        let requestID = UUID(817)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Falert"))
        let alertStarted = expectation(description: "tracked alert started")
        let alertGate = AsyncStream<Void>.makeStream()
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in
                alertStarted.fulfill()
                for await _ in alertGate.stream {
                    break
                }
            }
        }
        // store.exhaustivity = .off: alert UI boundary와 parent terminal 순서만 검증함.
        store.exhaustivity = .off

        let delegate: ExternalFileRouterAction.Delegate = permissionDenied
            ? .showPermissionDeniedError(path: "/tmp/alert", trackedRequestID: requestID)
            : .showInvalidPathError(path: "/tmp/alert", trackedRequestID: requestID)
        await store.send(.externalFileRouter(.delegate(delegate)))
        await fulfillment(of: [alertStarted], timeout: 1)
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)

        alertGate.continuation.yield(())
        alertGate.continuation.finish()
        await store.receive(\.externalFileRouter.singletonRequestCompleted, requestID)
        XCTAssertNil(store.state.activePendingExternalURL)
        await store.finish()
    }

    /// folder tracked route는 native open 반환 전 다음 batch를 admit하지 않는다.
    func testTrackedFolderNativeOpenBlocksNextBatchAdmission() async throws {
        try await assertTrackedSingletonNativeOpenBlocksBatch(route: .folder)
    }

    /// app fallback tracked route는 native initial-window open 반환 전 다음 batch를 admit하지 않는다.
    func testTrackedFallbackNativeOpenBlocksNextBatchAdmission() async throws {
        try await assertTrackedSingletonNativeOpenBlocksBatch(route: .fallback)
    }

    /// reveal tracked route도 parent window native open 반환 전 다음 batch를 admit하지 않는다.
    func testTrackedRevealNativeOpenBlocksNextBatchAdmission() async throws {
        try await assertTrackedSingletonNativeOpenBlocksBatch(route: .reveal)
    }

    private enum TrackedRouteScenario {
        case folder
        case fallback
        case reveal
    }

    private func assertTrackedSingletonNativeOpenBlocksBatch(route: TrackedRouteScenario) async throws {
        let requestID = UUID(820)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Ftracked"))
        let batchURL = URL(fileURLWithPath: "/tmp/batch-after-native-open")
        let openStarted = expectation(description: "tracked native open started")
        let openGate = AsyncStream<Void>.makeStream()
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.fileManagerWindowClient.open = { id in
                registeredWindowIDs.withValue { $0.insert(id) }
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.pathProbeClient.probeExistence = { _ in PathProbeResult(exists: false, isDirectory: false) }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: child window 초기화보다 native open terminal과 scheduler admission을 검증함.
        store.exhaustivity = .off

        let delegate: ExternalFileRouterAction.Delegate = switch route {
        case .folder:
            .openFolder(path: "/tmp/tracked", trackedRequestID: requestID)
        case .fallback:
            .openAppFallback(trackedRequestID: requestID)
        case .reveal:
            .openParentFolder(
                path: "/tmp",
                selectEntryPath: "/tmp/tracked.txt",
                trackedRequestID: requestID,
            )
        }
        await store.send(.externalFileRouter(.delegate(delegate))) {
            $0.windowManager.authorizedTrackedSingletonRequestID = requestID
        }
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [openStarted], timeout: 1)

        await store.send(.receiveExternalFileBatch([batchURL], source: .systemOpenEvent, mode: .open))
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.count, 1)

        openGate.continuation.yield(())
        openGate.continuation.finish()
        await store.receive(\.windowManager.trackedSingletonNativeOpenCompleted, requestID)
        await store.receive(\.windowManager.delegate.trackedSingletonCompleted, requestID)
        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)
        XCTAssertNil(store.state.windowManager.trackedSingletonWindow)
        XCTAssertNotNil(store.state.activeExternalOpenBatch)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        await store.receive(\.externalFileRouter.receiveBatch)

        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertNotNil(store.state.activeExternalOpenBatch)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        await store.finish()
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
