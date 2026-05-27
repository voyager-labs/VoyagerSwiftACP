import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccess
import VoyagerPagesOnboarding
import XCTest

@MainActor
final class AppLifecycleFeatureTests: XCTestCase {
    // MARK: - Termination

    func testStartTerminationCleanupDoesNotStopHelperOnNormalQuit() async {
        await VoyagerTerminationCoordinator.shared.end()
        let attemptID = UUID()
        let clock = TestClock()

        let state = TestState()

        let store = TestStore(
            initialState: AppLifecycleState(
                didStartHelper: true,
                terminationAttemptID: attemptID,
            ),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.stop = { @MainActor in
                state.didStopHelper = true
            }
            $0.appTerminationReplyClient.reply = { @MainActor reply in
                state.repliedValues.append(reply)
            }
            $0.uuid = .incrementing
            $0.continuousClock = clock
        }

        await store.send(AppLifecycleAction.termination(.startTerminationCleanup(attemptID: attemptID)))
        await store.receive(AppLifecycleAction.termination(.willTerminate))
        await store.receive(AppLifecycleAction.termination(.completeTerminationAttempt(
            attemptID: attemptID,
            shouldTerminate: true,
        ))) {
            $0.terminationAttemptID = nil
        }
        await store.finish()

        XCTAssertFalse(state.didStopHelper)
        XCTAssertEqual(state.repliedValues, [true])
        await VoyagerTerminationCoordinator.shared.end()
    }

    // MARK: - Access Gate

    // swiftlint:disable:next function_body_length
    func testActiveAccessOpensMainAndStartsHelper() async {
        nonisolated(unsafe) var savedSnapshots: [AccessStatusSnapshot] = []
        nonisolated(unsafe) var didShowUnlock = false
        nonisolated(unsafe) var helperStartCount = 0
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = .mock
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { snapshot in savedSnapshots.append(snapshot) },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: { didShowUnlock = true },
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.helperAppClient = HelperAppClient(
                start: { helperStartCount += 1 },
                stop: {},
                isRunning: { true },
                terminationEvents: { AsyncStream { $0.finish() } },
                ensureRunning: {},
            )
            $0.helperStateClient = HelperStateClient(
                resolve: { nil },
                observe: { AsyncStream { $0.finish() } },
            )
            $0.date = .constant(testDate)
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        await store.receive(.accessGate(.checkAccessStatus)) {
            $0.isCheckingAccess = true
        }

        await store.receive(.accessGate(.accessStatusResponse(.success(
            AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]),
        )))) {
            $0.isCheckingAccess = false
            $0.lastAccessStatus = .coreLicenseActive
            $0.accessGateResolved = true
        }

        await store.receive(.accessGate(.accessGranted(snapshot: AccessStatusSnapshot(
            status: .coreLicenseActive,
            entitlements: [.coreLicense],
            fetchedAt: testDate,
        )))) {
            $0.didStartHelper = true
        }

        await store.receive(.delegate(.openInitialWindowIfNeeded))
        await store.finish()

        XCTAssertFalse(didShowUnlock)
        XCTAssertEqual(savedSnapshots.count, 1)
        XCTAssertEqual(savedSnapshots.first?.status, .coreLicenseActive)
        XCTAssertGreaterThanOrEqual(helperStartCount, 1)
    }

    // swiftlint:disable:next function_body_length
    func testInactiveAccessShowsUnlockSurface() async {
        nonisolated(unsafe) var didShowUnlock = false

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: {
                    AccessStatusResponse(status: .revoked, entitlements: [])
                },
                signOut: {},
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: { didShowUnlock = true },
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        await store.receive(.accessGate(.checkAccessStatus)) {
            $0.isCheckingAccess = true
        }

        await store.receive(.accessGate(.accessStatusResponse(.success(
            AccessStatusResponse(status: .revoked, entitlements: []),
        )))) {
            $0.isCheckingAccess = false
            $0.lastAccessStatus = .revoked
            $0.accessGateResolved = true
        }

        await store.receive(.accessGate(.showUnlockSurface))
        await store.finish()

        XCTAssertTrue(didShowUnlock)
    }

    func testOnboardingRequiredSkipsAccessCheck() async {
        nonisolated(unsafe) var accessCheckCalled = false

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: {
                    accessCheckCalled = true
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                signOut: {},
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { true },
                showIfNeeded: { true },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        XCTAssertFalse(accessCheckCalled)
    }

    // swiftlint:disable:next function_body_length
    func testNetworkFailureWithValidCacheGrantsAccess() async {
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            entitlements: [.coreLicense],
            fetchedAt: testDate.addingTimeInterval(-3600),
        )
        nonisolated(unsafe) var savedSnapshots: [AccessStatusSnapshot] = []
        nonisolated(unsafe) var didShowUnlock = false
        nonisolated(unsafe) var helperStartCount = 0

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: {
                    throw AccessError.networkFailure
                },
                signOut: {},
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { cachedSnapshot },
                save: { snapshot in savedSnapshots.append(snapshot) },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: { didShowUnlock = true },
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.helperAppClient = HelperAppClient(
                start: { helperStartCount += 1 },
                stop: {},
                isRunning: { true },
                terminationEvents: { AsyncStream { $0.finish() } },
                ensureRunning: {},
            )
            $0.helperStateClient = HelperStateClient(
                resolve: { nil },
                observe: { AsyncStream { $0.finish() } },
            )
            $0.date = .constant(testDate)
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        await store.receive(.accessGate(.checkAccessStatus)) {
            $0.isCheckingAccess = true
        }

        await store.receive(.accessGate(.accessStatusResponse(.failure(AccessError.networkFailure))))

        await store.receive(.accessGate(.accessGranted(snapshot: cachedSnapshot))) {
            $0.didStartHelper = true
            $0.isCheckingAccess = false
            $0.lastAccessStatus = .coreLicenseActive
            $0.accessGateResolved = true
        }

        await store.receive(.delegate(.openInitialWindowIfNeeded))
        await store.finish()

        XCTAssertFalse(didShowUnlock)
        XCTAssertEqual(savedSnapshots, [cachedSnapshot])
        XCTAssertGreaterThanOrEqual(helperStartCount, 1)
    }

    // swiftlint:disable:next function_body_length
    func testNonNetworkFailureWithValidCacheShowsUnlock() async {
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let cachedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            entitlements: [.coreLicense],
            fetchedAt: testDate.addingTimeInterval(-3600),
        )
        nonisolated(unsafe) var savedSnapshots: [AccessStatusSnapshot] = []
        nonisolated(unsafe) var didShowUnlock = false
        nonisolated(unsafe) var helperStartCount = 0

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: {
                    throw AccessError.notConfigured
                },
                signOut: {},
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { cachedSnapshot },
                save: { snapshot in savedSnapshots.append(snapshot) },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: { didShowUnlock = true },
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.helperAppClient = HelperAppClient(
                start: { helperStartCount += 1 },
                stop: {},
                isRunning: { true },
                terminationEvents: { AsyncStream { $0.finish() } },
                ensureRunning: {},
            )
            $0.helperStateClient = HelperStateClient(
                resolve: { nil },
                observe: { AsyncStream { $0.finish() } },
            )
            $0.date = .constant(testDate)
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        await store.receive(.accessGate(.checkAccessStatus)) {
            $0.isCheckingAccess = true
        }

        await store.receive(.accessGate(.accessStatusResponse(.failure(AccessError.notConfigured))))

        await store.receive(.accessGate(.showUnlockSurface)) {
            $0.isCheckingAccess = false
            $0.accessGateResolved = true
        }
        await store.finish()

        XCTAssertTrue(didShowUnlock)
        XCTAssertTrue(savedSnapshots.isEmpty)
        XCTAssertEqual(helperStartCount, 0)
    }

    // swiftlint:disable:next function_body_length
    func testNetworkFailureWithoutCacheShowsUnlock() async {
        nonisolated(unsafe) var didShowUnlock = false
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: {
                    throw AccessError.networkFailure
                },
                signOut: {},
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: { didShowUnlock = true },
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.date = .constant(testDate)
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        await store.receive(.accessGate(.checkAccessStatus)) {
            $0.isCheckingAccess = true
        }

        await store.receive(.accessGate(.accessStatusResponse(.failure(AccessError.networkFailure))))

        await store.receive(.accessGate(.showUnlockSurface)) {
            $0.isCheckingAccess = false
            $0.accessGateResolved = true
        }
        await store.finish()

        XCTAssertTrue(didShowUnlock)
    }

    // swiftlint:disable:next function_body_length
    func testNetworkFailureWithExpiredCacheShowsUnlock() async {
        nonisolated(unsafe) var didShowUnlock = false
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredSnapshot = AccessStatusSnapshot(
            status: .betaTrialActive,
            expiresAt: testDate.addingTimeInterval(-1),
            entitlements: [.betaTrial],
            fetchedAt: testDate.addingTimeInterval(-3600),
        )

        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accessClient = AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: {
                    throw AccessError.networkFailure
                },
                signOut: {},
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { expiredSnapshot },
                save: { _ in },
                remove: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: { didShowUnlock = true },
                closeWindow: {},
                openMainWindow: { _ in true },
            )
            $0.date = .constant(testDate)
            $0.appearanceSettingsClient.loadTheme = { .system }
            $0.appearanceSettingsClient.applyThemeSync = { _ in }
        }

        await store.send(.launch(.didFinishLaunching))

        await store.receive(.accessGate(.checkAccessStatus)) {
            $0.isCheckingAccess = true
        }

        await store.receive(.accessGate(.accessStatusResponse(.failure(AccessError.networkFailure))))

        await store.receive(.accessGate(.showUnlockSurface)) {
            $0.isCheckingAccess = false
            $0.accessGateResolved = true
        }
        await store.finish()

        XCTAssertTrue(didShowUnlock)
    }

    func testAppReopenBeforeGateResolvedDoesNothing() async {
        let store = TestStore(
            initialState: AppLifecycleState(),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
        }

        await store.send(.launch(.appReopen(hasVisibleWindows: false)))
    }

    func testAppReopenAfterGateResolvedSendsDelegate() async {
        let store = TestStore(
            initialState: AppLifecycleState(
                lastAccessStatus: .coreLicenseActive,
                accessGateResolved: true,
            ),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
        }

        await store.send(.launch(.appReopen(hasVisibleWindows: true)))
        await store.receive(.delegate(.reopenWindowIfNeeded(hasVisibleWindows: true)))
    }

    func testAppReopenAfterLockedGateDoesNothing() async {
        let store = TestStore(
            initialState: AppLifecycleState(
                lastAccessStatus: .revoked,
                accessGateResolved: true,
            ),
        ) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                resetStoredProgress: {},
            )
        }

        await store.send(.launch(.appReopen(hasVisibleWindows: false)))
    }

    // MARK: - Test Helpers

    @MainActor
    private final class TestState: @unchecked Sendable {
        var didStopHelper = false
        var repliedValues: [Bool] = []
    }
}
