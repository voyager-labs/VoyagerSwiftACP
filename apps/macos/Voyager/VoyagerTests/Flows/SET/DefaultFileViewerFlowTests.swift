// FLOW-ID: set.default_file_viewer
import ComposableArchitecture
import Dependencies
import VoyagerEntitiesEntry
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class DefaultFileViewerFlowTests: XCTestCase {
    // FLOW-PATH: display_status_set_voyager_as_default

    /// set.default_file_viewer: display_status + set_voyager_as_default
    func testGeneralSectionDiagnosesFinderThenSetsVoyagerAndRefreshesStatus() async {
        let calls = LockIsolated<[DefaultFileViewerBoundaryCall]>([])
        let store = makeStore(
            statuses: [.finderIsDefault, .voyagerIsDefault],
            calls: calls,
        )

        await store.send(.general(.defaultFileViewerSectionAppeared))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)
        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .finderIsDefault)

        await store.send(.general(.setAsDefaultFileViewerTapped))
        await store.receive(\.general.setAsDefaultFileViewerSucceeded)
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .voyagerIsDefault)
        XCTAssertEqual(calls.withValue { $0 }, [.diagnose, .setVoyager, .diagnose])
        await store.finish()
    }

    // FLOW-PATH: restore_finder_as_default

    /// set.default_file_viewer: restore_finder_as_default
    func testGeneralSectionRestoresFinderAndRefreshesStatus() async {
        let calls = LockIsolated<[DefaultFileViewerBoundaryCall]>([])
        let store = makeStore(
            statuses: [.voyagerIsDefault, .finderIsDefault],
            calls: calls,
        )

        await store.send(.general(.defaultFileViewerSectionAppeared))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        await store.send(.general(.restoreDefaultFileViewerTapped))
        await store.receive(\.general.restoreDefaultFileViewerSucceeded)
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .finderIsDefault)
        XCTAssertEqual(calls.withValue { $0 }, [.diagnose, .restoreFinder, .diagnose])
        await store.finish()
    }

    // FLOW-PATH: other_app_to_voyager

    /// set.default_file_viewer: other_app_to_voyager
    func testOtherAppStatusSwitchesToVoyagerThroughBoundary() async {
        let calls = LockIsolated<[DefaultFileViewerBoundaryCall]>([])
        let otherApp = DefaultFileViewerStatus.otherIsDefault(
            appBundleID: "com.example.ForkLift",
            appDisplayName: "ForkLift",
        )
        let store = makeStore(statuses: [otherApp, .voyagerIsDefault], calls: calls)

        await store.send(.general(.defaultFileViewerSectionAppeared))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        await store.send(.general(.setAsDefaultFileViewerTapped))
        await store.receive(\.general.setAsDefaultFileViewerSucceeded)
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .voyagerIsDefault)
        XCTAssertEqual(calls.withValue { $0 }, [.diagnose, .setVoyager, .diagnose])
        await store.finish()
    }

    // FLOW-PATH: unknown_recheck

    /// set.default_file_viewer: unknown_recheck
    func testUnknownStatusRecheckRepeatsDiagnosisWithoutMutation() async {
        let calls = LockIsolated<[DefaultFileViewerBoundaryCall]>([])
        let store = makeStore(statuses: [.unknown, .unknown], calls: calls)

        await store.send(.general(.defaultFileViewerSectionAppeared))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        await store.send(.general(.defaultFileViewerDiagnoseRequested(.manual)))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .unknown)
        XCTAssertEqual(calls.withValue { $0 }, [.diagnose, .diagnose])
        await store.finish()
    }

    // FLOW-PATH: registration_failure

    /// set.default_file_viewer: registration_failure
    func testRegistrationFailurePreservesStatusAndRetryAction() async {
        let calls = LockIsolated<[DefaultFileViewerBoundaryCall]>([])
        let store = makeStore(
            statuses: [.finderIsDefault, .finderIsDefault],
            calls: calls,
            setError: .system(message: "Registration failed"),
        )

        await store.send(.general(.defaultFileViewerSectionAppeared))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        await store.send(.general(.setAsDefaultFileViewerTapped))
        await store.receive(\.general.setAsDefaultFileViewerFailed)
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .finderIsDefault)
        XCTAssertEqual(store.state.generalSettings.defaultFileViewerErrorMessage, "Registration failed")
        XCTAssertFalse(store.state.generalSettings.isSettingDefaultFileViewer)
        XCTAssertEqual(calls.withValue { $0 }, [.diagnose, .setVoyager, .diagnose])
        await store.finish()
    }

    // FLOW-PATH: permission_issue

    /// set.default_file_viewer: permission_issue
    func testPermissionFailureMapsToUnknownAndKeepsRecoveryAvailable() async {
        let calls = LockIsolated<[DefaultFileViewerBoundaryCall]>([])
        let store = makeStore(
            statuses: [.finderIsDefault, .unknown],
            calls: calls,
            setError: .system(message: "Permission denied"),
        )

        await store.send(.general(.defaultFileViewerSectionAppeared))
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        await store.send(.general(.setAsDefaultFileViewerTapped))
        await store.receive(\.general.setAsDefaultFileViewerFailed)
        await store.receive(\.general.defaultFileViewerDiagnosisCompleted)

        XCTAssertEqual(store.state.generalSettings.defaultFileViewerStatus, .unknown)
        XCTAssertEqual(store.state.generalSettings.defaultFileViewerErrorMessage, "Permission denied")
        XCTAssertFalse(store.state.generalSettings.isSettingDefaultFileViewer)
        XCTAssertEqual(calls.withValue { $0 }, [.diagnose, .setVoyager, .diagnose])
        await store.finish()
    }

    private func makeStore(
        statuses: [DefaultFileViewerStatus],
        calls: LockIsolated<[DefaultFileViewerBoundaryCall]>,
        setError: FileOpError? = nil,
        restoreError: FileOpError? = nil,
    ) -> TestStore<SettingsFeature.State, SettingsFeature.Action> {
        let remainingStatuses = LockIsolated(statuses)
        let client = DefaultFileViewerClient(
            appBundleID: DefaultFileViewerClient.voyagerBundleID,
            diagnose: {
                calls.withValue { $0.append(.diagnose) }
                return remainingStatuses.withValue { statuses in
                    statuses.isEmpty ? .unknown : statuses.removeFirst()
                }
            },
            setVoyagerAsDefault: {
                calls.withValue { $0.append(.setVoyager) }
                if let setError {
                    throw setError
                }
            },
            restoreFinder: {
                calls.withValue { $0.append(.restoreFinder) }
                if let restoreError {
                    throw restoreError
                }
            },
        )
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.defaultFileViewerClient = client
        }
        // 부모-자식 reducer 흐름에서 기본 파일 뷰어의 경계 순서와 완료 상태만 검증한다.
        store.exhaustivity = .off
        return store
    }
}

private enum DefaultFileViewerBoundaryCall: Equatable {
    case diagnose
    case setVoyager
    case restoreFinder
}
