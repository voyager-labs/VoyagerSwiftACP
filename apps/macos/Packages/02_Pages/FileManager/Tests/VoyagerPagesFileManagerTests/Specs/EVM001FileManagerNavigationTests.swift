import ComposableArchitecture
import CoreServices
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM001FileManagerNavigationTests: XCTestCase {
    // MARK: - EVM-001-route_navigation_reveal_lifecycle

    /// EVM-001-route_navigation_reveal_lifecycle: navigation-origin reveal installs an atomic destination pair.
    /// Navigation-origin selection must carry its destination so later routes cannot consume it accidentally.
    /// - 검증 내용: entry ID와 destination guard가 하나의 internal action으로 함께 설치된다.
    /// - 사전 조건: FileManager content state가 비어 있다.
    /// - 기대 결과: pendingSelectEntryID와 pendingSelectEntryDestinationPath가 각각 전달된 값으로 설정된다.
    func testNavigationRevealInstallsEntryAndDestinationAtomically() async {
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentFeature()
        }

        await store.send(.internal(.setPendingEntrySelection(
            entryID: "/a/b",
            destinationPath: "/a",
        ))) {
            $0.pendingSelectEntryID = "/a/b"
            $0.pendingSelectEntryDestinationPath = "/a"
        }

        await store.send(.internal(.setPendingEntrySelection(
            entryID: "/a/c",
            destinationPath: "/a",
        ))) {
            $0.pendingSelectEntryID = "/a/c"
            $0.pendingSelectEntryDestinationPath = "/a"
        }

        await store.send(.internal(.setPendingEntrySelection(
            entryID: "/a/external.txt",
            destinationPath: nil,
        ))) {
            $0.pendingSelectEntryID = "/a/external.txt"
            $0.pendingSelectEntryDestinationPath = nil
        }
    }

    /// EVM-001-route_navigation_reveal_lifecycle: matching folder route retains the pending pair.
    /// A committed route for the guarded destination must leave the pair available for later loading.
    /// - 검증 내용: matching folder applyNavigationState가 ID와 guard를 유지한다.
    /// - 사전 조건: pending pair destination이 /a이고 현재 route가 folder(/old)다.
    /// - 기대 결과: folder(/a) 적용 뒤 pending pair가 그대로 남는다.
    func testMatchingFolderRouteRetainsNavigationRevealPair() async {
        var state = FileManagerContentState()
        state.pendingSelectEntryID = "/a/b"
        state.pendingSelectEntryDestinationPath = "/a"
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder("/a"))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.pendingSelectEntryID, "/a/b")
        XCTAssertEqual(store.state.pendingSelectEntryDestinationPath, "/a")
    }

    /// EVM-001-route_navigation_reveal_lifecycle: mismatched and non-folder routes clear both fields.
    /// A superseding route must invalidate only navigation-origin pending state while preserving external nil-guard
    /// behavior.
    /// - 검증 내용: 다른 folder와 non-folder route가 ID와 guard를 함께 clear한다.
    /// - 사전 조건: navigation-origin pending pair가 설치돼 있다.
    /// - 기대 결과: 각 superseding route 적용 뒤 두 필드가 모두 nil이다.
    func testSupersedingRoutesClearNavigationRevealPair() async {
        for route in [
            ContentPageNavigationRoute.folder("/other"),
            .home,
        ] {
            var state = FileManagerContentState()
            state.pendingSelectEntryID = "/a/b"
            state.pendingSelectEntryDestinationPath = "/a"
            let store = TestStore(initialState: state) {
                FileManagerContentFeature()
            } withDependencies: {
                $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            }
            store.exhaustivity = .off

            await store.send(.internal(.applyNavigationState(route)))
            await store.skipReceivedActions(strict: false)

            XCTAssertNil(store.state.pendingSelectEntryID)
            XCTAssertNil(store.state.pendingSelectEntryDestinationPath)
        }
    }

    /// EVM-001-route_navigation_reveal_lifecycle: external selection keeps a nil destination guard.
    /// External reservation selection remains destination-unscoped and therefore retains its existing retry contract.
    /// - 검증 내용: external reservation snapshot sets only pendingSelectEntryID.
    /// - 사전 조건: valid directory reservation with a pending file path.
    /// - 기대 결과: reserved content has the external ID and a nil destination guard.
    func testExternalReservationSelectionHasNoDestinationGuard() {
        let tabID = ContentTabID(rawValue: "external")
        let reservation = ExternalContentTabReservation(
            id: tabID,
            anchor: .directory(path: "/a"),
            pendingSelectEntryID: "/a/file.txt",
        )
        let secondTabID = ContentTabID(rawValue: "external-2")
        let secondReservation = ExternalContentTabReservation(
            id: secondTabID,
            anchor: .directory(path: "/b"),
            pendingSelectEntryID: "/b/file.txt",
        )
        var state = FileManagerWindowState()

        XCTAssertTrue(state.reserveExternalContentTabs([reservation, secondReservation]))
        XCTAssertEqual(state.tabContentStates[tabID]?.pendingSelectEntryID, "/a/file.txt")
        XCTAssertNil(state.tabContentStates[tabID]?.pendingSelectEntryDestinationPath)
        XCTAssertEqual(state.tabContentStates[secondTabID]?.pendingSelectEntryID, "/b/file.txt")
        XCTAssertNil(state.tabContentStates[secondTabID]?.pendingSelectEntryDestinationPath)
    }

    /// EVM-001-route_navigation_reveal_lifecycle: window navigation delegate reaches active content.
    /// The composer boundary must translate the committed navigation delegate into the content-local internal action.
    /// - 검증 내용: revealEntryAfterNavigation is forwarded with both payload paths unchanged.
    /// - 사전 조건: FileManager window has its default active content tab.
    /// - 기대 결과: active content receives one atomic pending-selection action.
    func testNavigationRevealDelegateRoutesToActiveContent() async {
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.fileManagerClient.displayName = { _ in "Mac" }
        }

        await store.send(.navigation(.delegate(.revealEntryAfterNavigation(
            destinationPath: "/a",
            entryPath: "/a/b",
        ))))
        await store.receive { action in
            guard case let .content(.internal(.setPendingEntrySelection(entryID, destinationPath))) = action else {
                return false
            }
            return entryID == "/a/b" && destinationPath == "/a"
        }
    }

    // MARK: - EVM-001-dau_navigation_metrics

    /// EVM-001-dau_navigation_metrics: content-row directory open does not emit legacy DAU
    /// 실제 Open Selected Item 경로가 폐기된 legacy DAU callback을 다시 호출하지 않는지 검증.
    /// - 검증 내용: FileManagerFeature → EntryViewLayout command → navigation delegate 이후 legacy callback count
    /// - 사전 조건: ordinary folder entry가 선택된 FileManagerFeature 상태
    /// - 기대 결과: legacy DAU metric 0회
    func testContentRowFolderOpenDoesNotEmitLegacyDAU() async {
        let folderPath = "/tmp/voyager-content-row-folder"
        let folder = EntryModel.temporaryFolder(id: folderPath, name: "folder")
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entries = [folder]
        state.content.entryViewLayout.selectedIds = [folder.id]

        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.metricsClient = MetricsClient(
                logMetric: { _, _, _ in },
                logDAUNavigation: { kind in metrics.withValue { $0.append(kind) } },
                logDAUEntryAction: { _, _ in },
            )
        }
        // store.exhaustivity = .off: 전체 FileManager routing의 부수적인 loading effect보다 metric count를 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.delegate(.executeCommand(
            "navigation.openSelectedItem",
            source: .fileManagerContent,
        )))))
        await store.skipInFlightEffects()

        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-dau_navigation_metrics: direct fixed-location folder selection does not emit legacy DAU
    /// FileManager window의 직접 folder selection이 폐기된 legacy callback을 호출하지 않는지 검증.
    /// - 검증 내용: navigation view action 이후 legacy callback count
    /// - 사전 조건: Home route의 FileManagerFeature
    /// - 기대 결과: legacy DAU metric 0회
    func testDirectFolderSelectionDoesNotEmitLegacyDAU() async {
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics)

        await store.send(.navigation(.view(.navigateToPath("/tmp/voyager-fixed-location"))))
        await store.skipInFlightEffects()

        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-dau_navigation_metrics: same folder selection is a metric no-op
    /// 동일 route 재선택이 navigation metric을 중복 기록하지 않는지 검증.
    /// - 검증 내용: current folder와 동일한 navigation 입력의 metric count
    /// - 사전 조건: 현재 route가 지정 folder인 FileManagerFeature
    /// - 기대 결과: metric 0회
    func testSameFolderSelectionDoesNotLogNavigation() async {
        let path = "/tmp/voyager-same-folder"
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder(path)
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics, initialState: state)

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipInFlightEffects()

        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-dau_navigation_metrics: collection open does not emit legacy DAU
    /// collection open 실패에서도 폐기된 legacy callback이 호출되지 않는지 검증.
    /// - 검증 내용: collection file open 실패 이후 legacy callback count
    /// - 사전 조건: ordinary folder route와 throwing collection loader
    /// - 기대 결과: legacy DAU metric 0회
    func testCollectionOpenDoesNotEmitLegacyDAU() async {
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let url = URL(fileURLWithPath: "/tmp/voyager-metrics.voycoll")
        let store = makeMetricsStore(metrics: metrics) { dependencies in
            dependencies.collectionFileClient.load = { _ in
                throw NSError(domain: "metrics-test", code: 1)
            }
        }

        await store.send(.navigation(.view(.openCollectionFile(url))))

        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-dau_navigation_metrics: sidebar fixed-location selection does not emit legacy DAU
    /// 실제 Sidebar delegate action이 폐기된 legacy callback을 호출하지 않는지 검증.
    /// - 검증 내용: `.sidebar(.delegate(.selectFixedLocation(id)))` 이후 anchor transition과 callback count
    /// - 사전 조건: active Home tab과 다른 ordinary fixed location이 있는 FileManagerFeature 상태
    /// - 기대 결과: directory anchor로 전환되고 legacy DAU metric은 0회
    func testSidebarFixedLocationSelectionDoesNotEmitLegacyDAU() async throws {
        let location = FileManagerFixedLocationItem(
            id: "location-documents",
            title: "Documents",
            path: "/Users/test/Documents",
            iconName: "folder",
            accessibilityLabel: "Documents",
        )
        var state = FileManagerFeature.State()
        state.sidebar.fixedLocationItems = [location]
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics, initialState: state)

        await store.send(.sidebar(.delegate(.selectFixedLocation(location.id))))
        await store.receive(\.contentTabs)

        let activeTabID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertEqual(
            store.state.contentTabs.tabs[id: activeTabID]?.anchor,
            .directory(path: location.path),
        )
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-dau_navigation_metrics: sidebar fixed-location re-selection is a metric no-op
    /// 같은 Sidebar fixed location을 다시 누를 때 route와 metric이 중복 처리되지 않는지 검증.
    /// - 검증 내용: 동일 location ID에 대한 실제 sidebar delegate action의 anchor와 metric count
    /// - 사전 조건: active tab과 content route가 같은 fixed location path를 가리키는 상태
    /// - 기대 결과: anchor는 유지되고 navigation metric은 0회이며 collection metric도 없음
    func testSidebarSameFixedLocationSelectionDoesNotLogNavigation() async throws {
        let path = "/Users/test/Documents"
        let location = FileManagerFixedLocationItem(
            id: "location-documents",
            title: "Documents",
            path: path,
            iconName: "folder",
            accessibilityLabel: "Documents",
        )
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder(path)
        state.sidebar.fixedLocationItems = [location]
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.contentTabs.tabs[id: activeTabID]?.anchor = .directory(path: path)
        let metrics = LockIsolated<[DAUNavigationKind]>([])
        let store = makeMetricsStore(metrics: metrics, initialState: state)

        await store.send(.sidebar(.delegate(.selectFixedLocation(location.id))))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .directory(path: path))
        XCTAssertTrue(metrics.value.isEmpty)
    }

    private func makeMetricsStore(
        metrics: LockIsolated<[DAUNavigationKind]>,
        initialState: FileManagerFeature.State = .init(),
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: { dependencies in
            dependencies.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            dependencies.uuid = .incrementing
            dependencies.metricsClient = MetricsClient(
                logMetric: { _, _, _ in },
                logDAUNavigation: { kind in metrics.withValue { $0.append(kind) } },
                logDAUEntryAction: { _, _ in },
            )
            configure(&dependencies)
        }
        store.exhaustivity = .off
        return store
    }

    // MARK: - EVM-001-content_browsing_correlation

    nonisolated private static let typedBrowsingOperationIDs = [
        UUID(uuidString: "E0010000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "E0010000-0000-0000-0000-000000000002")!,
    ]

    /// 로더를 의도적으로 응답 없이 유지해 테스트가 주입하는 단말 외에는
    /// 경쟁하는 loading 단맀이 correlation을 소비하지 않도록 만든다.
    private static let suspendedLoadItems: @Sendable (URL, Bool) async throws -> [EntryModel] = { _, _ in
        try await Task.sleep(nanoseconds: 3_000_000_000)
        return []
    }

    private func makeTypedBrowsingStore(
        metrics: LockIsolated<[FileManagerProductMetric]>,
        initialState: FileManagerFeature.State = .init(),
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let operationIDIndex = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: { dependencies in
            dependencies.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            dependencies.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                record: { metric in metrics.withValue { $0.append(metric) } },
                makeOperationID: {
                    let index = operationIDIndex.withValue { current -> Int in
                        defer { current += 1 }
                        return current
                    }
                    return Self.typedBrowsingOperationIDs[index % Self.typedBrowsingOperationIDs.count]
                },
            )
            configure(&dependencies)
        }
        // store.exhaustivity = .off: 전체 window routing의 부수 effect보다 typed terminal count를 검증한다.
        store.exhaustivity = .off
        return store
    }

    /// EVM-001-navigate_pages: 수락 전 content 탐색 intent는 operation을 만들지 않는다.
    /// 실제 route 전환 delegate 전에는 browsing terminal과 연결할 제품 operation이 없어야 한다.
    /// - 검증 내용: content requestNavigation 직후 operation ID와 active correlation 부재
    /// - 사전 조건: 다른 folder로 이동 가능한 기본 FileManager 상태
    /// - 기대 결과: metric 0회, operation ID nil
    func testContentNavigationIntentDoesNotCreateOperationBeforeAcceptance() async {
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics)

        await store.send(.content(.internal(.requestNavigation(
            .view(.navigateToPath("/tmp/voyager-evm001-pending-intent")),
        ))))

        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-navigate_pages: unsaved Cancel은 browsing intent를 폐기한다.
    /// 취소 뒤 도착한 reload terminal이 취소된 사용자 탐색으로 오귀속되지 않는지 검증한다.
    /// - 검증 내용: Cancel 뒤 pending intent와 operation 부재, itemsLoaded 무이벤트
    /// - 사전 조건: content-originated back intent와 unsaved alert Cancel 응답
    /// - 기대 결과: metric 0회, 모든 browsing correlation nil
    func testUnsavedNavigationCancelCannotLeakIntoLaterReload() async {
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        var state = FileManagerFeature.State()
        state.content.navigation.backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/tmp/voyager-evm001-target")),
        ]
        let store = makeTypedBrowsingStore(metrics: metrics, initialState: state)

        await store.send(.content(.internal(.requestNavigation(.view(.goBack)))))
        await store.send(.navigation(.internal(.unsavedNavigationAlertResponse(.back, .cancel))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [],
        ))))))

        XCTAssertNil(store.state.content.pendingProductBrowsingSource)
        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertNil(store.state.content.productBrowsingIdentity)
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-go_page_history_back: Discard와 Save는 accepted transition에서만 operation을 만든다.
    /// unsaved 응답 이후에도 실제 route 전환 delegate 전까지 pending intent와 operation을 분리한다.
    /// - 검증 내용: Discard/Save 응답 직후 operation nil, accepted back delegate 뒤 exact identity/source
    /// - 사전 조건: content-originated back intent와 각 수락 응답
    /// - 기대 결과: 응답별 첫 operation ID, back identity, file_manager_content source
    func testUnsavedNavigationDiscardAndSaveAllocateOnlyAfterAcceptedTransition() async {
        for choice in [CollectionNavigationChoice.discard, .save] {
            var state = FileManagerWindowState()
            state.content.pendingProductBrowsingSource = .fileManagerContent
            let store = TestStore(initialState: state) {
                FileManagerNavigationActionReducer()
            } withDependencies: {
                $0.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                    record: { _ in },
                    makeOperationID: { Self.typedBrowsingOperationIDs[0] },
                )
            }

            await store.send(.navigation(.internal(.unsavedNavigationAlertResponse(.back, choice)))) {
                $0.content.resetComposerOnNextDirectoryNavigation = true
            }
            switch choice {
            case .discard:
                await store.receive(\.content.view.discardCollectionChanges)
                await store.receive(\.navigation.internal.performNavigation)
                await store.receive(\.content.internal.resetComposerAfterDirectoryNavigation)
            case .save:
                await store.receive(\.navigation.internal.setPendingNavigation)
                await store.receive { action in
                    guard case .content(.composer) = action else { return false }
                    return true
                }
            case .cancel:
                XCTFail("Cancel is covered by testUnsavedNavigationCancelCannotLeakIntoLaterReload")
            }

            XCTAssertNil(store.state.content.productBrowsingOperationID)
            XCTAssertEqual(store.state.content.pendingProductBrowsingSource, .fileManagerContent)

            await store.send(.navigation(.delegate(.logDAUNavigation(
                previous: .folder("/tmp/voyager-evm001-current"),
                next: .folder("/tmp/voyager-evm001-target"),
                identity: .back,
            )))) {
                $0.content.productBrowsingOperationID = Self.typedBrowsingOperationIDs[0]
                $0.content.productBrowsingIdentity = .back
                $0.content.productBrowsingSource = .fileManagerContent
                $0.content.productBrowsingContent = .folder
                $0.content.pendingProductBrowsingSource = nil
            }

            XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[0])
            XCTAssertEqual(store.state.content.productBrowsingIdentity, .back)
            XCTAssertEqual(store.state.content.productBrowsingSource, .fileManagerContent)
            XCTAssertNil(store.state.content.pendingProductBrowsingSource)
        }
    }

    /// EVM-001-content_browsing_correlation: navigation delegate establishes window browsing correlation
    /// 실제 navigation reducer의 delegate seam이 typed browsing correlation을 성립시키는지 검증.
    /// - 검증 내용: folder route의 logDAUNavigation delegate 처리 결과
    /// - 사전 조건: correlation이 없는 기본 FileManagerFeature 상태
    /// - 기대 결과: 주입된 operation ID와 sidebar source가 상태에 저장됨
    func testNavigationDelegateEstablishesWindowBrowsingCorrelation() async {
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics)

        await store.send(.navigation(.delegate(.logDAUNavigation(
            previous: .home,
            next: .folder("/tmp/voyager-evm001-delegate"),
            identity: .direct,
        ))))

        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[0])
        XCTAssertEqual(store.state.content.productBrowsingSource, .fileManagerSidebar)
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-content_browsing_correlation: window command folder navigation emits one typed browsing success event
    /// Window/Sidebar 명령이 수렴하는 navigation view 경로가 콘텐츠 로딩 단말과 상관되어
    /// typed metric을 정확히 한 번 기록하는지 검증.
    /// - 검증 내용: navigateToPath → correlation 성립 → itemsLoaded 이후 `.contentBrowsing(success)` 1회
    /// - 사전 조건: 응답 없는 directory stub loader와 기본 FileManagerFeature 상태
    /// - 기대 결과: 첫 operation ID, file_manager_sidebar source로 event 1회
    func testWindowFolderNavigationEmitsTypedBrowsingSuccessOnce() async {
        let path = "/tmp/voyager-evm001-window-folder"
        let entry = EntryModel.temporaryFolder(id: path + "/child", name: "child")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .itemsLoaded(
                generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
                items: [entry],
            ),
        )))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .success,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[0],
            )],
            "window/sidebar navigation must correlate with the loading terminal exactly once",
        )
    }

    /// EVM-001-content_browsing_correlation: window folder navigation with empty listing emits one empty event
    /// Window 명령 경로의 folder navigation이 빈 목록 로딩에서 `.empty` 단말을 한 번 기록하는지 검증.
    /// - 검증 내용: navigateToPath → itemsLoaded([]) 이후 `.contentBrowsing(empty)` 1회
    /// - 사전 조건: 빈 배열을 반환하는 directory stub loader
    /// - 기대 결과: `.empty` 1회, sidebar source 유지
    func testWindowFolderNavigationEmitsTypedBrowsingEmptyOnce() async {
        let path = "/tmp/voyager-evm001-empty-folder"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [],
        ))))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .empty,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[0],
            )],
        )
    }

    /// EVM-001-content_browsing_correlation: child folder failure preserves root browsing correlation
    /// outline 하위 폴더 실패가 진행 중인 root browsing terminal을 대신 소비하지 않는지 검증.
    /// - 검증 내용: root navigation 중 child folderLoadFailed(permissionDenied)를 전달한다.
    /// - 사전 조건: 응답 없는 root loader와 별도 child folder load request가 있다.
    /// - 기대 결과: metric 없이 root browsing correlation이 유지된다.
    func testChildFolderLoadFailureDoesNotConsumeRootBrowsingCorrelation() async {
        let path = "/tmp/voyager-evm001-root-folder"
        let childPath = "\(path)/child"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))

        let request = EntryFolderLoadRequest(
            rootContextGeneration: 0,
            folderID: childPath,
            folderGeneration: 0,
            path: childPath,
            showHidden: false,
            priority: .none,
        )
        await store.send(.content(.entryViewLayout(.entryOperations(.delegate(
            .folderLoadFailed(request: request, failure: .permissionDenied),
        )))))

        XCTAssertTrue(metrics.value.isEmpty)
        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[0])
        XCTAssertEqual(store.state.content.productBrowsingIdentity, .direct)
        XCTAssertEqual(store.state.content.productBrowsingSource, .fileManagerSidebar)
        XCTAssertEqual(store.state.content.productBrowsingContent, .folder)
    }

    /// EVM-001-content_browsing_correlation: same-route window navigation stays silent
    /// 동일 route 재선택이 correlation 없이 metric 없이 무음인지 검증.
    /// - 검증 내용: 현재 route와 같은 navigateToPath 이후 correlation과 metric 부재
    /// - 사전 조건: navigationState가 이미 대상 folder인 FileManagerFeature
    /// - 기대 결과: correlation nil, metric 0회
    func testSameRouteWindowNavigationStaysSilent() async {
        let path = "/tmp/voyager-evm001-same-folder"
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder(path)
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics, initialState: state) {
            $0.entryLoadingClient.loadItems = { _, _ in [] }
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipInFlightEffects()

        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-content_browsing_correlation: history and parent navigation emit one browsing event
    /// back, forward, history index, enclosing-folder 사용자 경로가 동일한 typed terminal 계약으로 수렴하는지 검증.
    /// - 검증 내용: 각 수락 경로 뒤 itemsLoaded가 `.contentBrowsing(success)`를 한 번 기록함
    /// - 사전 조건: 각 경로가 실제로 수락될 history 또는 enclosing folder 상태
    /// - 기대 결과: 경로별 sidebar source event 1회, operation correlation 완전 소비
    func testAcceptedHistoryAndParentRoutesEmitTypedBrowsingOnce() async {
        let targetPath = "/tmp/voyager-evm001-history-target"
        let target = ContentPageNavigationHistorySnapshot(navigationState: .folder(targetPath))
        let currentPath = "/tmp/voyager-evm001/current/child"
        let entry = EntryModel.temporaryFolder(id: targetPath + "/entry", name: "entry")
        let scenarios: [(
            ContentPageNavigationAction.View,
            ContentPageNavigationInteractionIdentity,
            (inout FileManagerFeature.State) -> Void,
        )] = [
            (.goBack, .back, { $0.content.navigation.backHistory = [target] }),
            (.goForward, .forward, { $0.content.navigation.forwardHistory = [target] }),
            (.goToHistoryIndex(0, isBackHistory: true), .history, {
                $0.content.navigation.backHistory = [target]
            }),
            (.goToEnclosingDirectory, .enclosingDirectory, {
                $0.content.navigation.navigationState = .folder(currentPath)
            }),
        ]

        for (action, expectedIdentity, configureState) in scenarios {
            var state = FileManagerFeature.State()
            configureState(&state)
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let store = makeTypedBrowsingStore(metrics: metrics, initialState: state) {
                $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
            }

            await store.send(.navigation(.view(action)))
            await store.skipReceivedActions()
            await store.send(.content(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(
                generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
                items: [entry],
            ))))))

            XCTAssertEqual(metrics.value.count, 1, "\(action) must emit one browsing terminal")
            guard case let .contentBrowsing(result, content, identity, source, operationID) = metrics.value.first else {
                XCTFail("\(action) must emit contentBrowsing")
                continue
            }
            XCTAssertEqual(result, .success)
            XCTAssertEqual(content, .folder)
            XCTAssertEqual(identity, expectedIdentity)
            XCTAssertEqual(source, .fileManagerSidebar)
            XCTAssertEqual(operationID, Self.typedBrowsingOperationIDs[0])
            XCTAssertNil(store.state.content.productBrowsingOperationID)
        }
    }

    /// EVM-001-content_browsing_correlation: streaming folder load emits one typed success event
    /// 실제 로딩 스트림(coreBatch→coreFinished→streamFinished)이 correlation과 상관되어
    /// typed success 단말을 정확히 한 번 기록하는지 검증.
    /// - 검증 내용: 현재 generation 스트림 완료 뒤 `.contentBrowsing(success)` 1회와 correlation 해제
    /// - 사전 조건: 응답 없는 directory stub loader로 시작된 loading stream
    /// - 기대 결과: event 1회, productBrowsing 상관 완전 소비
    func testStreamingFolderLoadEmitsTypedBrowsingSuccessOnce() async throws {
        let path = "/tmp/voyager-evm001-stream-folder"
        let entry = EntryModel.temporaryFolder(id: path + "/child", name: "child")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()
        let generation = store.state.content.entryViewLayout.entryOperations.loadingContext.generation
        try XCTSkipUnless(generation > 0, "navigation must begin a loading stream")

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamEvent(EntryLoadingStreamEvent(
                generation: generation,
                event: .coreBatch(items: [entry], batchIndex: 0),
            )),
        )))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamEvent(EntryLoadingStreamEvent(
                generation: generation,
                event: .coreFinished(batchCount: 1),
            )),
        )))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFinished(generation: generation),
        )))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .success,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[0],
            )],
            "streaming folder completion must correlate with the browsing terminal exactly once",
        )
        XCTAssertNil(store.state.content.productBrowsingOperationID)
    }

    /// EVM-001-content_browsing_correlation: streaming empty folder emits one typed empty event
    /// 빈 스트림(coreFinished batchCount 0 → streamFinished)이 `.empty` 단말을 한 번 기록하는지 검증.
    /// - 검증 내용: 항목 없는 현재 generation 스트림 완료 뒤 `.contentBrowsing(empty)` 1회
    /// - 사전 조건: 응답 없는 directory stub loader로 시작된 loading stream
    /// - 기대 결과: `.empty` 1회, correlation 해제
    func testStreamingFolderLoadEmitsTypedBrowsingEmptyOnce() async throws {
        let path = "/tmp/voyager-evm001-stream-empty"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()
        let generation = store.state.content.entryViewLayout.entryOperations.loadingContext.generation
        try XCTSkipUnless(generation > 0, "navigation must begin a loading stream")

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamEvent(EntryLoadingStreamEvent(
                generation: generation,
                event: .coreFinished(batchCount: 0),
            )),
        )))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFinished(generation: generation),
        )))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .empty,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[0],
            )],
        )
        XCTAssertNil(store.state.content.productBrowsingOperationID)
    }

    /// EVM-001-content_browsing_correlation: streaming folder failure emits one typed unavailable event
    /// 현재 generation의 streamFailed가 correlation을 소비해 `.unavailable` 단말을 한 번 기록하는지 검증.
    /// - 검증 내용: coreBatch 없이 실패한 스트림 뒤 `.contentBrowsing(unavailable)` 1회
    /// - 사전 조건: 응답 없는 directory stub loader로 시작된 loading stream
    /// - 기대 결과: `.unavailable` 1회, correlation 해제
    func testStreamingFolderLoadFailureEmitsTypedBrowsingUnavailableOnce() async throws {
        let path = "/tmp/voyager-evm001-stream-failed"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()
        let generation = store.state.content.entryViewLayout.entryOperations.loadingContext.generation
        try XCTSkipUnless(generation > 0, "navigation must begin a loading stream")

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFailed(generation: generation),
        )))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .unavailable,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[0],
            )],
        )
        XCTAssertNil(store.state.content.productBrowsingOperationID)
    }

    /// EVM-001-content_browsing_correlation: window teardown terminates accepted browsing exactly once.
    /// 수락된 탐색의 로딩 중 window가 사라지면 원래 상관 정보로 unavailable 단말을 기록하고 늦은 단말을 무시한다.
    /// - 검증 내용: 첫 onDisappear의 typed terminal과 상관 해제, 반복 teardown 및 late stream terminal 무이벤트
    /// - 사전 조건: 응답 없는 directory loader로 실제 folder navigation이 수락되어 correlation이 성립돼 있다.
    /// - 기대 결과: 원 operation ID·content·identity·source의 unavailable 1회와 모든 browsing correlation nil
    func testWindowDisappearTerminatesAcceptedBrowsingExactlyOnce() async {
        let path = "/tmp/voyager-evm001-window-teardown"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()
        let generation = store.state.content.entryViewLayout.entryOperations.loadingContext.generation

        await store.send(.onDisappear)

        let expectedMetrics: [FileManagerProductMetric] = [
            .contentBrowsing(
                result: .unavailable,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[0],
            ),
        ]
        XCTAssertEqual(metrics.value, expectedMetrics)
        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertNil(store.state.content.productBrowsingIdentity)
        XCTAssertNil(store.state.content.productBrowsingSource)
        XCTAssertNil(store.state.content.productBrowsingContent)
        XCTAssertNil(store.state.content.pendingProductBrowsingSource)

        await store.send(.onDisappear)
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFailed(generation: generation),
        )))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFinished(generation: generation),
        )))))

        XCTAssertEqual(metrics.value, expectedMetrics)
        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertNil(store.state.content.productBrowsingIdentity)
        XCTAssertNil(store.state.content.productBrowsingSource)
        XCTAssertNil(store.state.content.productBrowsingContent)
        XCTAssertNil(store.state.content.pendingProductBrowsingSource)
    }

    /// EVM-001-content_browsing_correlation: stale stream terminal does not consume browsing correlation
    /// 구 generation 터미널은 correlation을 소비하지 않고, 이후 현재 generation 터미널이 정확히 한 번 기록하는지 검증.
    /// - 검증 내용: 미래 generation streamFinished 무음·상관 유지, 이어진 현재 streamFailed 1회
    /// - 사전 조건: 응답 없는 directory stub loader로 시작된 loading stream
    /// - 기대 결과: stale 무이벤트 후 `.unavailable` 1회
    func testStaleStreamTerminalDoesNotConsumeBrowsingCorrelation() async throws {
        let path = "/tmp/voyager-evm001-stream-stale"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.navigation(.view(.navigateToPath(path))))
        await store.skipReceivedActions()
        let generation = store.state.content.entryViewLayout.entryOperations.loadingContext.generation
        try XCTSkipUnless(generation > 0, "navigation must begin a loading stream")

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFinished(generation: generation + 1),
        )))))

        XCTAssertTrue(metrics.value.isEmpty, "stale generation terminal must not emit")
        XCTAssertNotNil(store.state.content.productBrowsingOperationID, "stale terminal must preserve correlation")

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFailed(generation: generation),
        )))))

        XCTAssertEqual(metrics.value.count, 1, "current terminal must emit exactly once")
        guard case let .contentBrowsing(result, _, _, _, operationID) = metrics.value.first else {
            return XCTFail("current terminal must emit contentBrowsing")
        }
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(operationID, Self.typedBrowsingOperationIDs[0])
        XCTAssertNil(store.state.content.productBrowsingOperationID)
    }

    /// EVM-001-content_browsing_correlation: 이전 Computer 결과는 새 폴더의 browsing correlation을 소비하지 않는다.
    /// Computer A 뒤 시작된 폴더 B가 현재 operation을 소유할 때 늦은 A와 현재 B terminal을 순서대로 검증한다.
    /// - 검증 내용: stale A는 metric/state no-op이고 current B는 typed terminal을 정확히 한 번 기록한다.
    /// - 사전 조건: generation 2 폴더 B에 두 번째 operation ID와 sidebar browsing metadata가 설정돼 있다.
    /// - 기대 결과: stale A 이후 B correlation이 유지되고 current B success metric만 한 건 기록된다.
    func testStaleComputerItemsLoadedCannotConsumeNewerFolderBrowsingCorrelation() async {
        let entryB = EntryModel.temporaryFolder(id: "/folder-b/child", name: "child")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        var state = FileManagerFeature.State()
        state.content.entryViewLayout.entryOperations.loadingContext.generation = 2
        state.content.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.content.entryViewLayout.entryOperations.isLoading = true
        state.content.productBrowsingOperationID = Self.typedBrowsingOperationIDs[1]
        state.content.productBrowsingIdentity = .direct
        state.content.productBrowsingSource = .fileManagerSidebar
        state.content.productBrowsingContent = .folder
        let store = makeTypedBrowsingStore(metrics: metrics, initialState: state)

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(generation: 1, items: [
            EntryModel.temporaryFolder(id: "/computer-a", name: "computer-a"),
        ]))))))

        XCTAssertTrue(metrics.value.isEmpty)
        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[1])
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.isLoading)

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(
            generation: 2,
            items: [entryB],
        ))))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .success,
                content: .folder,
                identity: .direct,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[1],
            )],
        )
        XCTAssertNil(store.state.content.productBrowsingOperationID)
    }

    /// EVM-001-content_browsing_correlation: rejected history and parent navigation stay silent
    /// 수락되지 않은 history/parent 명령이 correlation을 남겨 후속 로딩을 오귀속하지 않는지 검증.
    /// - 검증 내용: empty back/forward, invalid history index, parent 없는 root 경로 처리
    /// - 사전 조건: 각 명령의 수락 조건이 충족되지 않은 상태
    /// - 기대 결과: correlation nil, metric 0회
    func testRejectedHistoryAndParentRoutesDoNotCreateBrowsingCorrelation() async {
        let scenarios: [(ContentPageNavigationAction.View, (inout FileManagerFeature.State) -> Void)] = [
            (.goBack, { _ in }),
            (.goForward, { _ in }),
            (.goToHistoryIndex(0, isBackHistory: true), { _ in }),
            (.goToEnclosingDirectory, { $0.content.navigation.navigationState = .folder("/") }),
        ]

        for (action, configureState) in scenarios {
            var state = FileManagerFeature.State()
            configureState(&state)
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let store = makeTypedBrowsingStore(metrics: metrics, initialState: state)

            await store.send(.content(.internal(.requestNavigation(.view(action)))))

            XCTAssertNil(store.state.content.productBrowsingOperationID, "\(action) must not create correlation")
            XCTAssertNil(store.state.content.productBrowsingSource)
            XCTAssertNil(store.state.content.productBrowsingContent)
            XCTAssertTrue(metrics.value.isEmpty)
        }
    }

    /// EVM-001-content_browsing_correlation: superseded navigation cannot consume the current correlation.
    /// 서로 다른 A/B 탐색이 겹칠 때 B가 새 상관을 소유하고 A의 stale 단말은 무음인지 검증한다.
    /// - 검증 내용: A/B의 ID·identity·source 구분, stale A 무이벤트, current B exactly-once
    /// - 사전 조건: A back/content 로딩 중 B forward/sidebar 탐색을 수락한 응답 없는 loader
    /// - 기대 결과: B의 operation ID와 metadata를 가진 success terminal 한 건만 기록됨
    func testOverlappingWindowNavigationsEmitExactlyOneEvent() async {
        let currentPath = "/tmp/voyager-evm001-current-folder"
        let pathA = "/tmp/voyager-evm001-folder-a"
        let entryB = EntryModel.temporaryFolder(id: currentPath + "/entry-b", name: "entry-b")
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder(currentPath)
        state.content.navigation.backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .folder(pathA)),
        ]
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics, initialState: state) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.content(.internal(.requestNavigation(.view(.goBack)))))
        await store.send(.navigation(.view(.goBack)))
        await store.skipReceivedActions()
        let generationA = store.state.content.entryViewLayout.entryOperations.loadingContext.generation
        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[0])
        XCTAssertEqual(store.state.content.productBrowsingIdentity, .back)
        XCTAssertEqual(store.state.content.productBrowsingSource, .fileManagerContent)

        await store.send(.navigation(.view(.goForward)))
        await store.skipReceivedActions()
        let generationB = store.state.content.entryViewLayout.entryOperations.loadingContext.generation
        XCTAssertGreaterThan(generationB, generationA)
        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[1])
        XCTAssertEqual(store.state.content.productBrowsingIdentity, .forward)
        XCTAssertEqual(store.state.content.productBrowsingSource, .fileManagerSidebar)

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFailed(generation: generationA),
        )))))
        XCTAssertTrue(metrics.value.isEmpty, "superseded A must not emit a synthetic terminal")
        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[1])

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamEvent(EntryLoadingStreamEvent(
                generation: generationB,
                event: .coreBatch(items: [entryB], batchIndex: 0),
            )),
        )))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamEvent(EntryLoadingStreamEvent(
                generation: generationB,
                event: .coreFinished(batchCount: 1),
            )),
        )))))
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .streamFinished(generation: generationB),
        )))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .success,
                content: .folder,
                identity: .forward,
                source: .fileManagerSidebar,
                operationID: Self.typedBrowsingOperationIDs[1],
            )],
            "only current B may emit exactly one browsing event",
        )
    }

    /// EVM-001-content_browsing_correlation: content-originated correlation survives window navigation
    /// 콘텐츠 기원 correlation(`.fileManagerContent`)이 window navigation 상관 설정에 덮어쓰이지 않는지 검증.
    /// - 검증 내용: content requestNavigation으로 성립한 correlation이 window navigateToPath 이후에도 유지되는지
    /// - 사전 조건: content seam으로 선성립된 correlation과 directory stub loader
    /// - 기대 결과: event 1회, source file_manager_content, 첫 operation ID
    func testContentOriginatedCorrelationSurvivesWindowNavigation() async {
        let originPath = "/tmp/voyager-evm001-content-origin"
        let targetPath = "/tmp/voyager-evm001-window-target"
        let entry = EntryModel.temporaryFolder(id: "/tmp/voyager-evm001-entry", name: "entry")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.content(.internal(.requestNavigation(
            .view(.navigateToPath(originPath)),
        ))))
        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertEqual(store.state.content.pendingProductBrowsingSource, .fileManagerContent)

        await store.send(.navigation(.view(.navigateToPath(targetPath))))
        await store.skipReceivedActions()

        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .itemsLoaded(
                generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
                items: [entry],
            ),
        )))))

        XCTAssertEqual(
            metrics.value,
            [.contentBrowsing(
                result: .success,
                content: .folder,
                identity: .direct,
                source: .fileManagerContent,
                operationID: Self.typedBrowsingOperationIDs[0],
            )],
        )
    }

    /// EVM-001-content_browsing_correlation: non-loading route clears pending correlation
    /// 비로딩 route 전환이 미완료 correlation을 정리해 stale 단말을 막는지 검증.
    /// - 검증 내용: AI Chat 전환 후 correlation 해제와 metric 무음
    /// - 사전 조건: content seam으로 선성립된 correlation
    /// - 기대 결과: correlation nil, metric 0회
    func testNonLoadingRouteClearsPendingCorrelation() async {
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadRecentItems = { _, _ in [] }
        }

        await store.send(.content(.internal(.requestNavigation(
            .view(.navigateToPath("/tmp/voyager-evm001-pending")),
        ))))
        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertEqual(store.state.content.pendingProductBrowsingSource, .fileManagerContent)

        await store.send(.navigation(.delegate(.logDAUNavigation(
            previous: .folder("/tmp/voyager-evm001-pending"),
            next: .aiChat("evm001-chat"),
            identity: .direct,
        ))))

        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertNil(store.state.content.productBrowsingSource)
        XCTAssertTrue(metrics.value.isEmpty)
    }

    /// EVM-001-content_browsing_correlation: internal route change creates no correlation or event
    /// bootstrap/internal route 설정은 사용자 탐색 단말을 만들지 않는지 검증.
    /// - 검증 내용: setNavigationState 후 correlation 부재와 수동 itemsLoaded 무음
    /// - 사전 조건: 기본 FileManagerFeature 상태
    /// - 기대 결과: correlation nil, metric 0회
    func testInternalRouteChangeCreatesNoCorrelationOrEvent() async {
        let entry = EntryModel.temporaryFolder(id: "/tmp/voyager-evm001-entry", name: "entry")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = { _, _ in [entry] }
        }

        await store.send(.navigation(.internal(.setNavigationState(
            .folder("/tmp/voyager-evm001-bootstrap"),
        ))))

        XCTAssertNil(store.state.content.productBrowsingOperationID)
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(
            .itemsLoaded(
                generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
                items: [entry],
            ),
        )))))
        XCTAssertTrue(metrics.value.isEmpty)
    }

    // MARK: - EVM-001-route_entry_selection_commands

    /// EVM-001-route_entry_selection_commands: Select All은 hierarchy visible preorder를 layout reducer로 전달한다.
    /// normal directory list에서 collapsed descendant와 synthetic row를 제외한 visible entries만 선택 명령으로 전달되는지 검증한다.
    /// - 검증 내용: selectAllEntries routing이 visible selectable ID 순서를 유지한다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 loaded이며 /root/b는 root sibling이다.
    /// - 기대 결과: applySelectAll의 ordered IDs는 [/root/a, /root/a/child, /root/b]다.
    func testSelectAllRoutesVisibleOutlineOrder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder, sibling]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }

        await store.send(.view(.selectAllEntries))
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applySelectAll(orderedItemIds))) = action else {
                return false
            }
            return orderedItemIds == [folder.id, child.id, sibling.id]
        }
    }

    /// EVM-001-route_entry_selection_commands: arrow navigation은 hierarchy visible preorder를 layout reducer로 전달한다.
    /// normal directory list에서 현재 selection 다음 항목이 expanded child여야 하는지 검증한다.
    /// - 검증 내용: down-arrow routing이 applySelectionOffset에 visible selectable IDs를 보낸다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 loaded이며 current focus는 /root/a다.
    /// - 기대 결과: ordered IDs는 [/root/a, /root/a/child, /root/b]이고 offset은 1이다.
    func testArrowNavigationRoutesVisibleOutlineOrder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder, sibling]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 125,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applySelectionOffset(offset, isShiftPressed, orderedItemIds))) =
                action
            else {
                return false
            }
            return offset == 1
                && !isShiftPressed
                && orderedItemIds == [folder.id, child.id, sibling.id]
        }
    }

    /// EVM-001-route_entry_selection_commands: nested selection의 Delete와 Return은 visible entry를 해석한다.
    /// 키보드 이동으로 선택된 expanded child가 root entries에 없어도 mutation과 rename 명령이 동작하는지 검증한다.
    /// - 검증 내용: Cmd+Delete의 child path와 Return의 child rename item routing
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 선택돼 있다.
    /// - 기대 결과: child moveToTrash command와 startRename action이 각각 전달된다.
    func testNestedSelectionDeleteAndRenameResolveVisibleEntry() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.selectedIds = [child.id]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 51,
            modifiers: [.command],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case .entryViewLayout(.delegate(.executeCommand(
                "mutation.moveSelectedItemsToTrash",
                source: .keyboardShortcut,
            ))) = action
            else {
                return false
            }
            return true
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 36,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.startRename(item, text, _))) = action else {
                return false
            }
            return item == child && text == child.name
        }
    }

    /// EVM-001-route_entry_selection_commands: Cmd-Return은 Rename을 시작하지 않고 plain Return만 시작한다.
    /// Return의 responder-scoped rename과 modifier가 있는 Return의 no-op 경계를 함께 검증한다.
    /// - 검증 내용: Cmd-Return에는 startRename action이 없고 plain Return에는 선택 entry의 startRename action이 한 번 방출된다.
    /// - 사전 조건: /root Directory list에서 entry 하나가 선택돼 있다.
    /// - 기대 결과: Cmd-Return은 no-op이고 plain Return은 선택 entry 이름을 가진 startRename action을 방출한다.
    func testCommandReturnDoesNotStartRenameButPlainReturnDoes() async {
        let entry = EntryModel.temporaryFolder(id: "/root/entry", name: "entry")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [entry]
        state.entryViewLayout.selectedIds = [entry.id]
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 36,
            modifiers: [.command],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 36,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.startRename(item, text, _))) = action else {
                return false
            }
            return item == entry && text == entry.name
        }
    }

    /// EVM-001-route_entry_selection_commands: directory symlink Open preserves lexical navigation identity.
    /// The open delegate must route the requested alias string without resolving it to its destination path.
    /// - 검증 내용: navigateToPath bridge payload가 lexical alias path와 동일하다.
    /// - 사전 조건: directory symlink fixture와 alias folder entry가 준비돼 있다.
    /// - 기대 결과: internal requestNavigation이 alias path를 그대로 전달한다.
    func testDirectorySymlinkOpenRoutesLexicalPath() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain",
        )
        defer { sandbox.cleanup() }

        let aliasPath = sandbox.symlinkedFileURL.deletingLastPathComponent().path
        let store = TestStore(initialState: FileManagerContentState()) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.entryOperations(.delegate(.navigateToPath(aliasPath)))))
        await store.receive { action in
            guard case let .internal(.requestNavigation(.view(.navigateToPath(path)))) = action else {
                return false
            }
            return path == aliasPath
        }
    }

    // MARK: - EVM-001-route_empty_trash_command

    /// EVM-001-route_empty_trash_command: Empty Trash는 hierarchy descendant 없이 root entry만 command context로 전달한다.
    /// expanded hierarchy의 child가 Trash root 항목처럼 처리되지 않도록 Empty Trash command context를 검증한다.
    /// - 검증 내용: emptyTrash executeCommand의 displayItems가 root entries 순서만 유지한다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/child가 loaded이며 /root/b는 root sibling이다.
    /// - 기대 결과: command context displayItems는 [/root/a, /root/b]다.
    func testEmptyTrashRoutesOnlyRootEntriesAsCommandContext() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel.temporaryFolder(id: "/root/a/child", name: "child")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder, sibling]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "mutation.emptyTrash",
            source: .fileManagerContent,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(command, context, _)))) = action
            else {
                return false
            }
            guard case .mutation(.emptyTrash) = command else {
                return false
            }
            return context.displayItems == [folder, sibling]
        }
    }

    // MARK: - EVM-001-reload_directory_page_on_external_change

    /// EVM-001-reload_directory_page_on_external_change: folder 내부 child path 변경 시 reload
    /// 현재 folder 경로 하위의 file 또는 nested child path가 외부에서 변경되면 현재 폴더를 reload하는지 검증.
    /// - 검증 내용: folder route에서 child path 변경을 event path와 affected parent로 전달하고 loadItems 수신
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain), showHiddenFiles == true
    /// - 기대 결과: removed prefix 없이 hierarchy invalidation 후 entryOperations.loading.loadItems 수신
    func testExternalFolderChildChangeReloadsCurrentFolder() async {
        let folderPath = Self.fixtureDir("texts/plain")
        let changedPath = "\(folderPath)/11.txt"
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalChangedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.resolvingSymlinksInPath().path
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        state.entryViewLayout.showHiddenFiles = true
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == [canonicalChangedPath, canonicalFolderPath] && removedPrefixes.isEmpty
        }
        await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)
    }

    /// EVM-001-reload_directory_page_on_external_change: expanded folder 자체 변경 시 child cache reload
    /// folder path 자체에 modified/rescan event가 발생해도 해당 folder hierarchy cache를 갱신하는지 검증한다.
    /// - 검증 내용: changed folder path와 parent path를 hierarchy invalidation에 함께 전달
    /// - 사전 조건: 현재 directory 아래 expanded folder path에 non-deletion event가 발생함
    /// - 기대 결과: removed prefix 없이 folder path와 parent path가 affectedPaths에 포함됨
    func testExternalExpandedFolderChangeInvalidatesFolderAndParent() async {
        let folderPath = Self.fixtureDir("texts")
        let changedFolderPath = Self.fixtureDir("texts/plain")
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalChangedFolderPath = URL(fileURLWithPath: changedFolderPath).standardizedFileURL
            .resolvingSymlinksInPath().path
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedFolderPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == [canonicalChangedFolderPath, canonicalFolderPath] && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: coarse rescan flag는 hierarchy cache 전체 reload로 전달된다.
    /// ancestor path 하나만 포함한 dropped event가 expanded descendant cache를 남기지 않는지 검증한다.
    /// - 검증 내용: MustScanSubDirs event가 coarseHierarchyInvalidated action을 생성함
    /// - 사전 조건: 현재 folder 아래 expanded hierarchy가 있고 root path에 coarse event가 도착함
    /// - 기대 결과: removed prefix 없이 coarse hierarchy invalidation 후 root load가 이어짐
    func testCoarseExternalChangeRequestsCachedHierarchyReload() async {
        let folderPath = Self.fixtureDir("texts")
        let expandedFolderPath = Self.fixtureDir("texts/plain")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        state.entryViewLayout.hierarchy.setExpandedIDs([expandedFolderPath])
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents(
            [folderPath],
            flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs),
        )))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.coarseHierarchyInvalidated(removedPrefixes))) = action
            else { return false }
            return removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: expanded folder 외부 삭제·rename 시 hierarchy identity 제거
    /// watcher의 remove·rename event가 parent reload뿐 아니라 사라진 folder cache prefix도 전달하는지 검증한다.
    /// - 검증 내용: identity 변경 path의 parent affected path와 removed prefix 분리
    /// - 사전 조건: 현재 directory 아래 expanded folder에 remove 또는 rename event가 발생함
    /// - 기대 결과: 두 event 모두 folder path를 removedPrefixes로 전달함
    func testExternalExpandedFolderRemovalOrRenameEvictsHierarchyPrefix() async {
        let folderPath = Self.fixtureDir("texts")
        let removedFolderPath = Self.fixtureDir("texts/plain")
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalRemovedPath = URL(fileURLWithPath: removedFolderPath).standardizedFileURL.resolvingSymlinksInPath()
            .path
        let identityChangeFlags = [
            UInt32(kFSEventStreamEventFlagItemRemoved),
            UInt32(kFSEventStreamEventFlagItemRenamed),
        ]

        for flags in identityChangeFlags {
            var state = FileManagerContentState()
            state.navigation.navigationState = .folder(folderPath)
            let store = makeStore(initialState: state)

            await store.send(.externalFileSystemChanged(Self.externalChangeEvents([removedFolderPath], flags: flags)))
            await store.receive { action in
                guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) =
                    action
                else { return false }
                return affectedPaths == [canonicalRemovedPath, canonicalFolderPath]
                    && removedPrefixes == [canonicalRemovedPath]
            }
            await store.receive { action in
                guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
                return true
            }
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder file create는 canonical affected path와 parent를 한 번
    /// reload한다.
    /// 현재 folder의 route와 history를 유지하면서 새 파일과 그 parent hierarchy를 invalidate하는지 검증한다.
    /// - 검증 내용: created file의 canonical path와 parent, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder file create event가 도착함
    /// - 기대 결과: removed prefix 없이 affected path와 parent를 전달하고 route/history는 유지됨
    func testExternalFinderFileCreateInvalidatesAffectedPathAndParentOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/new-file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile),
            removesSource: false,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder delete는 canonical affected path와 removed prefix를 한 번
    /// reload한다.
    /// 삭제된 entry의 원래 subtree cache를 제거하면서 현재 folder route와 history를 유지하는지 검증한다.
    /// - 검증 내용: removed file의 canonical path, parent, removed prefix, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder file delete event가 도착함
    /// - 기대 결과: affected path와 parent 및 removed prefix를 전달하고 route/history는 유지됨
    func testExternalFinderFileDeleteInvalidatesAffectedPathAndRemovedPrefixOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/deleted-file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemIsFile),
            removesSource: true,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder rename은 canonical affected path와 removed prefix를 한 번
    /// reload한다.
    /// rename 이전 entry의 stale subtree cache를 제거하면서 현재 folder route와 history를 유지하는지 검증한다.
    /// - 검증 내용: renamed file의 canonical path, parent, removed prefix, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder file rename event가 도착함
    /// - 기대 결과: affected path와 parent 및 removed prefix를 전달하고 route/history는 유지됨
    func testExternalFinderFileRenameInvalidatesAffectedPathAndRemovedPrefixOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/renamed-file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemIsFile),
            removesSource: true,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: Finder subfolder create는 canonical affected path와 parent를 한 번
    /// reload한다.
    /// 새 하위 폴더의 hierarchy와 현재 folder parent를 invalidate하면서 route와 history를 유지하는지 검증한다.
    /// - 검증 내용: created subfolder의 canonical path와 parent, 단일 loadItems transaction
    /// - 사전 조건: folder route에 back/forward history가 있고 Finder directory create event가 도착함
    /// - 기대 결과: removed prefix 없이 affected path와 parent를 전달하고 route/history는 유지됨
    func testExternalFinderSubfolderCreateInvalidatesAffectedPathAndParentOnce() async {
        await assertExternalFinderMutation(
            path: "/tmp/voyager/current/../current/new-folder",
            flags: UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir),
            removesSource: false,
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: 관련 없는 folder 외부 변경 시 reload 안 함
    /// 현재 폴더와 관련 없는 경로의 외부 변경은 reload를 트리거하지 않는지 검증.
    /// - 검증 내용: sibling 경로 변경 시 어떤 load 액션도 수신하지 않음
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain)
    /// - 기대 결과: externalFileSystemChanged 전송 후 수신 액션 없음
    func testExternalSiblingChangeDoesNotReloadCurrentFolder() async {
        let folderPath = Self.fixtureDir("texts/plain")
        let unrelatedPath = Self.fixturePath("images/jpeg/hopper.jpg")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath])))
    }

    /// EVM-001-reload_directory_page_on_external_change: metadata-only event는 folder reload로 전달되지 않는다.
    /// filesystem metadata 변화가 stale-worthy path event가 아니므로 current folder reload를 만들지 않는지 검증한다.
    /// - 검증 내용: metadata-only gateway event의 FileManager relevance 결과
    /// - 사전 조건: visible folder interest와 xattr-only event가 존재함
    /// - 기대 결과: gateway event가 제거되어 hierarchy invalidation과 reload가 발생하지 않음
    func testMetadataOnlyFolderEventDoesNotReloadCurrentFolder() {
        let interest = FileChangeWatchInterest(
            id: "visible-folder",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/tmp/voyager/current"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/tmp/voyager/current/metadata-only.txt",
            flags: UInt32(kFSEventStreamEventFlagItemXattrMod),
        )

        XCTAssertTrue(gatewayRelevantChangedEvents([event], interest: interest, openedURL: nil).isEmpty)
    }

    /// EVM-001-reload_directory_page_on_external_change: Recents route에서 route loader refresh
    /// Recents route에서 외부 변경 감지 시 recents 전용 loader만 refresh하는지 검증.
    /// - 검증 내용: recents route에서 externalFileSystemChanged 전송 시 loadRecentItems 수신
    /// - 사전 조건: navigationState == .recents, showHiddenFiles == true
    /// - 기대 결과: entryOperations.loading.loadRecentItems 액션 수신
    func testExternalChangeReloadsRecentsRoute() async {
        let changedPath = Self.fixturePath("texts/plain/11.txt")
        var state = FileManagerContentState()
        state.navigation.navigationState = .recents
        state.entryViewLayout.showHiddenFiles = true
        state.entryViewLayout.entryArrangements.sortKey = .kind
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden, priority)))) =
                action else { return false }
            return showHidden && priority == .active([.spotlight])
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route에서 route loader refresh
    /// Tags route에서 외부 변경 감지 시 tags 전용 loader만 refresh하는지 검증.
    /// - 검증 내용: tags route에서 externalFileSystemChanged 전송 시 loadTagItems 수신
    /// - 사전 조건: navigationState == .tags("Work")
    /// - 기대 결과: entryOperations.loading.loadTagItems 액션 수신
    func testExternalChangeReloadsTagsRoute() async {
        let changedPath = Self.fixturePath("texts/plain/11.txt")
        var state = FileManagerContentState()
        state.navigation.navigationState = .tags("Work")
        state.entryViewLayout.entryArrangements.groupKey = .tags
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadTagItems(
                tagName,
                showHidden,
                priority,
            )))) = action else { return false }
            return tagName == "Work" && !showHidden && priority == .active([.tags])
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Collection route에서 directory reload로 contents 대체하지 않음
    /// Collection route에서 collection document path의 외부 변경이 directory reload로 collection contents를 대체하지 않는지 검증.
    /// - 검증 내용: collection route에서 collectionURL path 및 metadata.json path 변경 시 어떤 load 액션도 수신하지 않음
    /// - 사전 조건: navigationState == .collection, collectionSession.document 설정됨
    /// - 기대 결과: externalFileSystemChanged 전송 후 수신 액션 없음
    func testExternalChangeIgnoresOpenedCollectionDocumentPath() async {
        let collectionURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-config-\(UUID().uuidString).voycoll", isDirectory: true)
        var state = FileManagerContentState()
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: collectionURL, name: "sample-config"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.collection.collectionSession.document = .init(url: collectionURL, name: "sample-config")
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([
            collectionURL.path,
            collectionURL.appendingPathComponent("metadata.json").path,
        ])))
    }

    /// EVM-001-reload_directory_page_on_external_change: folder 이동 시 watcher 시작 및 외부 변경 전달
    /// folder navigation 시 directory watcher가 시작되고, 외부 변경 사항이 externalFileSystemChanged로 전달되는지 검증.
    /// - 검증 내용: applyNavigationState(.folder) 전송 시 watcher 시작, clearCollectionPresentation, loadItems,
    /// externalFileSystemChanged 수신
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain), custom fileChangeGatewayClient
    /// - 기대 결과: watcher가 changedPath를 yield하고 externalFileSystemChanged로 전달
    func testFolderNavigationStartsWatcherAndForwardsExternalChanges() async {
        let currentPath = Self.fixtureDir("texts/plain")
        let changedPath = "\(currentPath)/11.txt"
        let changedEvents = Self.externalChangeEvents(
            [changedPath],
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(currentPath)
        let interestUpdated = expectation(description: "Folder interest forwarded promptly")
        let effectOrder = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                effectOrder.withValue { $0.append("interest") }
                XCTAssertEqual(interests.map(\.roots), [[currentPath]])
                XCTAssertEqual(interests.map(\.purpose), [.visibleFolderReload])
                interestUpdated.fulfill()
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(currentPath))))
        await fulfillment(of: [interestUpdated], timeout: 1)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            XCTAssertEqual(effectOrder.value, ["interest"])
            return true
        }
        eventContinuation.value?.yield(.init(events: changedEvents))
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == changedEvents && deliveryChainToken == nil
        }
        eventContinuation.value?.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: queued batches retain their own delivery-chain token.
    /// observer가 두 batch를 먼저 enqueue해도 bridge action이 batch별 token을 그대로 전달하는지 검증한다.
    /// - 검증 내용: first와 second externalFileSystemChanged action이 각각 원래 batch token을 보존한다.
    /// - 사전 조건: 같은 folder observer에 서로 다른 token의 relevant event batch 두 개가 queue된다.
    /// - 기대 결과: 첫 action에는 first token, 둘째 action에는 second token이 전달된다.
    func testGatewayDeliveryChainTokensRemainBoundToBatches() async {
        let folderPath = "/tmp/voyager"
        let firstBatch = FileChangeGatewayEventBatch(
            events: [FileChangeGatewayEvent(
                path: "\(folderPath)/first.txt",
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
                emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
            )],
            deliveryChainToken: "00000000-0000-0000-0000-000000000001",
        )
        let secondBatch = FileChangeGatewayEventBatch(
            events: [FileChangeGatewayEvent(
                path: "\(folderPath)/second.txt",
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
                emittedAt: Date(timeIntervalSince1970: 1_700_000_001),
            )],
            deliveryChainToken: "00000000-0000-0000-0000-000000000002",
        )
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        let streamStarted = expectation(description: "Gateway observation stream started")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                    streamStarted.fulfill()
                }
            }
        }
        // store.exhaustivity = .off: delivery token forwarding만 검증하고 navigation 내부 action은 기존 테스트가 소유한다.
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(folderPath))))
        await fulfillment(of: [streamStarted], timeout: 1)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }

        eventContinuation.value?.yield(firstBatch)
        eventContinuation.value?.yield(secondBatch)
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == firstBatch.events && deliveryChainToken == firstBatch.deliveryChainToken
        }
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == secondBatch.events && deliveryChainToken == secondBatch.deliveryChainToken
        }
        eventContinuation.value?.finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: exact gateway batch retransmission is not forwarded twice.
    /// 동일 observer lifetime에서 직전 accepted batch의 exact retransmission이 중복 invalidation을 만들지 않는지 검증한다.
    /// - 검증 내용: 동일 event count, normalized path set, flags, emittedAt set을 가진 두 번째 batch의 외부 변경 전달 여부
    /// - 사전 조건: folder watcher가 실제 observation effect를 실행하고 하나의 batch를 수신한다.
    /// - 기대 결과: 첫 batch만 `externalFileSystemChanged`로 전달되고 exact retransmission은 무시된다.
    func testExactGatewayBatchRetransmissionForwardsOnlyOnce() async {
        let folderPath = "/tmp/voyager"
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        let streamStarted = expectation(description: "Gateway observation stream started")
        let observedChangeCount = LockIsolated(0)
        let event = FileChangeGatewayEvent(
            path: "\(folderPath)/created.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var state = GatewayObservationHarness.State()
        state.content.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            GatewayObservationHarness { count in
                observedChangeCount.setValue(count)
            }
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                    streamStarted.fulfill()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [streamStarted], timeout: 1)

        eventContinuation.value?.yield(.init(events: [event]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [event] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 1
        })

        eventContinuation.value?.yield(.init(events: [event]))
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(observedChangeCount.value, 1)
        eventContinuation.value?.finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: changed gateway batches remain accepted after dedup.
    /// exact retransmission만 억제하고 emittedAt, path, count가 달라진 batch는 계속 전달하는지 검증한다.
    /// - 검증 내용: previous accepted batch와 fingerprint가 다른 세 batch의 전달 횟수
    /// - 사전 조건: folder watcher가 실제 observation effect를 실행하고 첫 batch를 수신한다.
    /// - 기대 결과: exact retransmission은 무시되고 emittedAt/path/count 변경 batch는 각각 전달된다.
    func testChangedGatewayBatchesRemainAcceptedAfterExactDeduplication() async {
        let folderPath = "/tmp/voyager"
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        let streamStarted = expectation(description: "Gateway observation stream started")
        let firstEvent = FileChangeGatewayEvent(
            path: "\(folderPath)/created.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let emittedAtChanged = FileChangeGatewayEvent(
            path: firstEvent.path,
            flags: firstEvent.flags,
            emittedAt: firstEvent.emittedAt.addingTimeInterval(1),
        )
        let pathChanged = FileChangeGatewayEvent(
            path: "\(folderPath)/renamed.txt",
            flags: firstEvent.flags,
            emittedAt: emittedAtChanged.emittedAt,
        )
        let countChanged = [pathChanged, FileChangeGatewayEvent(
            path: "\(folderPath)/second.txt",
            flags: firstEvent.flags,
            emittedAt: pathChanged.emittedAt.addingTimeInterval(1),
        )]
        var state = GatewayObservationHarness.State()
        state.content.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            GatewayObservationHarness { _ in }
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    eventContinuation.setValue(continuation)
                    streamStarted.fulfill()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [streamStarted], timeout: 1)

        eventContinuation.value?.yield(.init(events: [firstEvent]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [firstEvent] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 1
        })
        eventContinuation.value?.yield(.init(events: [firstEvent]))
        eventContinuation.value?.yield(.init(events: [emittedAtChanged]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [emittedAtChanged] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 2
        })
        eventContinuation.value?.yield(.init(events: [pathChanged]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [pathChanged] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 3
        })
        eventContinuation.value?.yield(.init(events: countChanged))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == countChanged && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 4
        })
        eventContinuation.value?.finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: cancellation and restart clear the previous batch fingerprint.
    /// watcher cancellation 뒤 새 observer lifetime에서 같은 batch가 다시 전달되는지 검증한다.
    /// - 검증 내용: folder watcher cancel/restart 이후 동일 event의 전달 횟수
    /// - 사전 조건: 첫 folder observer가 batch를 수신한 뒤 home route로 cancellation된다.
    /// - 기대 결과: 재시작된 observer는 이전 lifetime의 fingerprint에 영향받지 않는다.
    func testGatewayBatchDeduplicationResetsAfterWatcherRestart() async {
        let folderPath = "/tmp/voyager"
        let event = FileChangeGatewayEvent(
            path: "\(folderPath)/created.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
            emittedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let continuations = LockIsolated<[AsyncStream<FileChangeGatewayEventBatch>.Continuation]>([])
        let firstStreamStarted = expectation(description: "First gateway observation stream started")
        let secondStreamStarted = expectation(description: "Second gateway observation stream started")
        let streamCount = LockIsolated(0)
        var state = GatewayObservationHarness.State()
        state.content.navigation.navigationState = .folder(folderPath)
        let store = TestStore(initialState: state) {
            GatewayObservationHarness { _ in }
        } withDependencies: {
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuations.withValue { $0.append(continuation) }
                    streamCount.withValue { count in
                        count += 1
                        (count == 1 ? firstStreamStarted : secondStreamStarted).fulfill()
                    }
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [firstStreamStarted], timeout: 1)
        continuations.value[0].yield(.init(events: [event]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [event] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 1
        })

        await store.send(.content(.internal(.applyNavigationState(.home))))
        continuations.value[0].finish()
        await store.send(.content(.internal(.applyNavigationState(.folder(folderPath)))))
        await fulfillment(of: [secondStreamStarted], timeout: 1)
        continuations.value[1].yield(.init(events: [event]))
        await store.receive({ action in
            guard case let .content(.externalFileSystemChanged(events, deliveryChainToken)) = action else {
                return false
            }
            return events == [event] && deliveryChainToken == nil
        }, assert: {
            $0.externalChangeCount = 2
        })
        continuations.value[1].finish()
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: symlink-resolved gateway event 보존
    /// lexical watch root와 canonical event path가 달라도 sync reducer까지 event가 전달되는지 검증한다.
    /// - 검증 내용: `/var` interest에 대한 `/private/var` child event의 relevance 결과
    /// - 사전 조건: includeSubfolders가 활성화된 visible-folder interest
    /// - 기대 결과: 원본 FileChangeGatewayEvent가 필터에서 제거되지 않음
    func testGatewayRelevancePreservesCanonicalSymlinkEvent() {
        let interest = FileChangeWatchInterest(
            id: "visible-folder",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/var/tmp"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/private/var/tmp/voyager-changed.txt",
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        )

        XCTAssertEqual(
            gatewayRelevantChangedEvents([event], interest: interest, openedURL: nil),
            [event],
        )
    }

    /// EVM-001-reload_directory_page_on_external_change: collection 이동 시 scope watcher 시작 및 외부 변경 전달
    /// Collection route 진입 시 `.voycoll` 위치가 아닌 collection scope 절대경로만 감시하고 변경을 전달하는지 검증.
    /// - 검증 내용: applyNavigationState(.collection) 전송 시 FileChangeGateway interest 등록, externalFileSystemChanged 수신
    /// - 사전 조건: collectionContext.scopes에 중복/상대 경로가 섞여 있음
    /// - 기대 결과: canonical absolute scope만 감시하고 changedPath를 전달
    func testCollectionScopeRootsChangedSinceSnapshotDetectsNewerRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-scope-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: root.path,
        )
        let file = VoyagerCollectionFile(
            id: UUID().uuidString,
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            query: "",
            scopes: [root.path],
            conditions: [],
            snapshot: nil,
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: "fingerprint",
                capturedAt: Date(timeIntervalSince1970: 100),
                itemCount: 0,
                relevanceRoots: [root.path],
            ),
            appVersion: nil,
        )

        XCTAssertTrue(collectionScopeRootsChangedSinceSnapshot(file))
    }

    func testCollectionScopeRootsChangedSinceSnapshotIgnoresMissingSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-scope-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = VoyagerCollectionFile(
            id: UUID().uuidString,
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            query: "",
            scopes: [root.path],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        XCTAssertFalse(collectionScopeRootsChangedSinceSnapshot(file))
    }

    func testCollectionNavigationStartsScopeWatcherAndForwardsExternalChanges() async {
        let firstScope = "/tmp/voyager/scope-a"
        let secondScope = "/tmp/voyager/scope-b/../scope-b"
        let changedPath = "/tmp/voyager/scope-a/changed.txt"
        let changedEvents = Self.externalChangeEvents(
            [changedPath],
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/demo.voycoll")
        let context = CollectionContext(
            query: "",
            scopes: [firstScope, "relative", secondScope, firstScope],
            conditions: [],
        )
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "demo"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.collection.collectionContext = context
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [["/tmp/voyager/scope-a", "/tmp/voyager/scope-b"]])
                XCTAssertEqual(interests.map(\.purpose), [.collectionStale])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield(.init(events: changedEvents))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = "collection:\(collectionURL.standardizedFileURL.path)"
        }
        await store.receive { action in
            guard case let .externalFileSystemChanged(events, deliveryChainToken) = action else {
                return false
            }
            return events == changedEvents && deliveryChainToken == nil
        }
    }

    func testCollectionNavigationIgnoresMetadataOnlyScopeEvents() async {
        let scope = "/tmp/voyager/scope-a"
        let changedPath = "/tmp/voyager/scope-a/opened.txt"
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/demo.voycoll")
        let context = CollectionContext(query: "", scopes: [scope], conditions: [])
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "demo"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.collection.collectionContext = context
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [[scope]])
                XCTAssertEqual(interests.map(\.purpose), [.collectionStale])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield(.init(events: [
                        FileChangeGatewayEvent(
                            path: changedPath,
                            flags: UInt32(kFSEventStreamEventFlagItemXattrMod),
                        ),
                    ]))
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = "collection:\(collectionURL.standardizedFileURL.path)"
        }
    }

    /// EVM-001-navigate_pages: collection navigation도 scroll position key를 저장/복원
    /// Collection route 진입 시 saved collection URL 기반 key로 currentPath와 savedScrollOffset을 주입하는지 검증.
    /// - 검증 내용: applyNavigationState(.collection(.file)) 전송 시 entryViewLayout.currentPath와 savedScrollOffset 동기화
    /// - 사전 조건: scrollPositions에 saved collection URL 기반 key가 저장됨
    /// - 기대 결과: collection 진입 후 list/grid coordinator가 같은 key로 scroll offset을 복원할 수 있음
    func testCollectionNavigationRestoresSavedScrollOffset() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/saved.voycoll")
        let scrollKey = "collection:\(collectionURL.standardizedFileURL.path)"
        let savedOffset = CGPoint(x: 0, y: 240)
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "saved"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.navigation.scrollPositions[scrollKey] = savedOffset

        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = scrollKey
            $0.entryViewLayout.savedScrollOffset = savedOffset
        }
    }

    /// EVM-001-navigate_pages: collection scroll offset 저장은 현재 collection key에 즉시 반영
    /// EntryViewLayout delegate가 저장한 collection scroll offset이 현재 route의 savedScrollOffset과 scrollPositions에 동기화되는지 검증.
    /// - 검증 내용: saveScrollOffset(offset, forPath: collectionKey) 전송 시 scrollPositions와 savedScrollOffset 갱신
    /// - 사전 조건: navigationState == .collection(.file), entryViewLayout.currentPath == collection URL 기반 key
    /// - 기대 결과: collection에서 다른 route로 이동 후 돌아왔을 때 같은 offset을 복원할 수 있음
    func testCollectionNavigationSavesScrollOffsetForCurrentCollectionKey() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/saved.voycoll")
        let scrollKey = "collection:\(collectionURL.standardizedFileURL.path)"
        let savedOffset = CGPoint(x: 0, y: 480)
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "saved"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.entryViewLayout.currentPath = scrollKey

        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }

        await store.send(.internal(.saveScrollOffset(savedOffset, forPath: scrollKey))) {
            $0.navigation.scrollPositions[scrollKey] = savedOffset
            $0.entryViewLayout.savedScrollOffset = savedOffset
        }
    }

    /// EVM-001-home_navigation_clears_hidden_entries: Home route 적용 시 숨은 folder selection 정리
    /// Home 화면 진입 후에도 이전 folder entry/selection이 메뉴 command projection에 남지 않도록 검증.
    /// - 검증 내용: applyNavigationState(.home)이 selection·entry list를 비우고 이전 generation batch를 무시함
    /// - 사전 조건: generation 1의 folder load와 선택된 entry가 남아 있는 상태
    /// - 기대 결과: generation을 무효화하고 Home 전환 뒤 도착한 generation 1 batch를 반영하지 않음
    func testHomeNavigationClearsHiddenEntrySelectionAndItems() async {
        let previousEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-hidden-selection",
            name: "voyager-hidden-selection",
        )
        let staleEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-stale-root-batch",
            name: "voyager-stale-root-batch",
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entries = [previousEntry]
        state.entryViewLayout.selectedIds = [previousEntry.id]
        state.entryViewLayout.lastSelectedId = previousEntry.id
        state.entryViewLayout.rangeAnchorId = previousEntry.id
        state.entryViewLayout.entryOperations.loadingContext.items = [previousEntry]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.entryViewLayout.entryOperations.isLoading = true

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.home)))
        await store.receive(\.entryViewLayout.entryOperations.loading.cancelAndClearItems)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.internal.applyClearSelection)
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.finish()

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [staleEntry], batchIndex: 0),
        ))))))

        XCTAssertEqual(store.state.entryViewLayout.currentPath, "Home")
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entries.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.items.isEmpty)
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.loadingContext.generation, 2)
        XCTAssertNil(store.state.entryViewLayout.entryOperations.loadingContext.sourceKind)
    }

    /// EVM-001-ai_chat_navigation_clears_hidden_entries: AI Chat route 적용 시 숨은 folder selection 정리
    /// AI Chat 화면 진입 후에도 이전 folder entry/selection이 command projection에 남지 않도록 검증.
    func testAiChatNavigationClearsHiddenEntrySelectionAndItems() async {
        await assertAiChatNavigationClearsHiddenEntrySelectionAndItems(.aiChat(Self.aiChatRouteSessionID))
    }

    /// EVM-001-ai_chat_sessions_navigation_clears_hidden_entries: AI Chat History route 적용 시 숨은 folder selection 정리
    /// AI Chat History 화면도 파일 command와 분리되어야 하므로 이전 entry projection을 비움.
    func testAiChatSessionsNavigationClearsHiddenEntrySelectionAndItems() async {
        await assertAiChatNavigationClearsHiddenEntrySelectionAndItems(.aiChatSessions(Self.aiChatRouteSessionID))
    }

    private static let aiChatRouteSessionID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

    private func assertAiChatNavigationClearsHiddenEntrySelectionAndItems(
        _ navigationState: ContentPageNavigationRoute,
    ) async {
        let previousEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-ai-chat-hidden-selection",
            name: "voyager-ai-chat-hidden-selection",
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entries = [previousEntry]
        state.entryViewLayout.selectedIds = [previousEntry.id]
        state.entryViewLayout.lastSelectedId = previousEntry.id
        state.entryViewLayout.rangeAnchorId = previousEntry.id
        state.entryViewLayout.entryOperations.loadingContext.items = [previousEntry]

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState)))
        await store.receive(\.entryViewLayout.entryOperations.loading.cancelAndClearItems)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.internal.applyClearSelection)
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.finish()

        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entries.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.items.isEmpty)
    }

    private func makeStore(initialState: FileManagerContentState)
        -> TestStore<FileManagerContentState, FileManagerContentAction>
    {
        TestStore(initialState: initialState) {
            FileManagerContentSyncReducer()
        }
    }

    private func assertExternalFinderMutation(
        path: String,
        flags: UInt32,
        removesSource: Bool,
    ) async {
        let currentPath = "/tmp/voyager/current"
        let backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        let forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/tmp/forward"))]
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(currentPath)
        state.navigation.backHistory = backHistory
        state.navigation.forwardHistory = forwardHistory
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([path], flags: flags)))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            ))) = action else { return false }
            let canonicalPath = Self.canonicalPath(path)
            let expectedParent = URL(fileURLWithPath: canonicalPath).deletingLastPathComponent().path
            let expectedRemovedPrefixes = removesSource ? [canonicalPath] : []
            return affectedPaths == [canonicalPath, expectedParent]
                && removedPrefixes == expectedRemovedPrefixes
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden, priority)))) =
                action
            else {
                return false
            }
            return path == currentPath && !showHidden && priority == .none
        }

        XCTAssertEqual(store.state.navigation.navigationState, .folder(currentPath))
        XCTAssertEqual(store.state.navigation.backHistory, backHistory)
        XCTAssertEqual(store.state.navigation.forwardHistory, forwardHistory)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // Fixture path helpers

    /// `fixtures/fixtures/` 하위 디렉토리의 절대 경로를 반환.
    private static func fixtureDir(_ subpath: String) -> String {
        guard let root = try? resolveRepoRoot() else {
            XCTFail("Repository fixture root could not be resolved")
            return FileManager.default.temporaryDirectory.path
        }
        return root.appendingPathComponent("fixtures/fixtures")
            .appendingPathComponent(subpath).path
    }

    private static func externalChangeEvents(
        _ paths: [String],
        flags: UInt32 = UInt32(kFSEventStreamEventFlagItemModified),
    ) -> [FileChangeGatewayEvent] {
        paths.map { FileChangeGatewayEvent(path: $0, flags: flags, emittedAt: .distantPast) }
    }

    /// `fixtures/fixtures/` 하위 파일의 절대 경로를 반환.
    private static func fixturePath(_ subpath: String) -> String {
        guard let root = try? resolveRepoRoot() else {
            XCTFail("Repository fixture root could not be resolved")
            return FileManager.default.temporaryDirectory.appendingPathComponent(subpath).path
        }
        return root.appendingPathComponent("fixtures/fixtures")
            .appendingPathComponent(subpath).path
    }

    /// CWD에서 위로 올라가며 repo root(`.git` 또는 `Package.swift`)를 찾고
    /// `fixtures/fixtures/` 존재를 교차 검증한다.
    /// `FixtureSandbox.resolveRepoRoot`와 동일한 탐지 정책을 사용한다.
    private static func resolveRepoRoot() throws -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)
        for _ in 0 ..< 10 {
            let hasRepoMarker = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            if hasRepoMarker,
               FileManager.default.fileExists(atPath: url.appendingPathComponent("fixtures/fixtures").path)
            {
                return url
            }
            guard let parent = url.pathComponents.count > 1 ? url.deletingLastPathComponent() : nil else { break }
            url = parent
        }
        throw FixturePathError.repoRootNotFound(searchFrom: cwd)
    }

    // MARK: - EVM-001-reload_directory_page_on_external_change

    private let reducer = FileManagerContentFeature()

    struct LifecycleBridgeHarness: @MainActor Reducer {
        // swiftlint:disable:next nesting
        struct State: Equatable {
            var content: FileManagerContentState
        }

        // swiftlint:disable:next nesting
        enum Action {
            case bridge(EntryOperationsAction)
            case forwarded(FileManagerContentAction)
        }

        var body: some Reducer<State, Action> {
            Reduce { state, action in
                switch action {
                case let .bridge(entryAction):
                    FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                        entryAction,
                        state: &state.content,
                    )
                    .map(Action.forwarded)
                case .forwarded:
                    .none
                }
            }
        }
    }

    @Reducer
    struct GatewayObservationHarness {
        let onExternalChange: @Sendable (Int) -> Void

        struct State: Equatable {
            var content = FileManagerContentState()
            var externalChangeCount = 0
        }

        enum Action {
            case content(FileManagerContentAction)
        }

        var body: some Reducer<State, Action> {
            Scope(state: \.content, action: \.content) {
                FileManagerContentNavigationBridgeReducer()
            }
            Reduce { state, action in
                guard case let .content(.externalFileSystemChanged(events, _)) = action else {
                    return .none
                }
                state.externalChangeCount += events.isEmpty ? 0 : 1
                onExternalChange(state.externalChangeCount)
                return .none
            }
        }
    }

    private func makeInitialState() -> LifecycleBridgeHarness.State {
        LifecycleBridgeHarness.State(content: FileManagerContentState())
    }

    private func makeInitialState(folderPath: String) -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    /// EVM-001-reload_directory_page_on_external_change: folder route entry operation 완료 시 directory reload forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: folder route에서 entry operation 완료 액션이 현재 folder loader로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedTriggersContentReload() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let folderPath = sandbox.fileURL.deletingLastPathComponent().path
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            sandbox.fileURL.path,
            .rename,
            .success(()),
        ))))

        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 즉시 삭제 성공 시 hierarchy 제거 prefix 전달
    /// undo record가 없는 deleteImmediately도 삭제된 folder cache를 제거하는지 검증한다.
    /// - 검증 내용: operationFinished 성공 path가 parent invalidation과 removedPrefixes에 함께 전달됨
    /// - 사전 조건: folder route에서 중첩 folder 즉시 삭제가 성공함
    /// - 기대 결과: affectedPaths는 parent, removedPrefixes는 삭제된 folder path를 포함함
    func testDeleteImmediatelySuccessInvalidatesRemovedHierarchyPrefix() async {
        let folderPath = "/tmp/voyager"
        let deletedPath = "/tmp/voyager/deleted"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            deletedPath,
            .deleteImmediately,
            .success(()),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath] && removedPrefixes == [deletedPath]
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: recents route entry operation 완료 시 recents reload forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: recents route에서 entry operation 완료 액션이 recents loader로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedTriggersContentReloadForRecents() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .recents

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .moveToTrash,
            .success(()),
        ))))

        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(
                showHidden: false,
                priority: .none,
            ))))) =
                action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 개별 setTags 완료는 최종 record 전에는 reload하지 않는다.
    func testSetTagsOperationFinishedDoesNotReloadBeforeFinalRecord() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .tags("Work")

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .setTags,
            .success(()),
        ))))

        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: setTags의 최종 성공 record는 일반 folder를 한 번 reload한다.
    func testSetTagsEntryActionCompletedReloadsFolderOnce() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let folderPath = sandbox.fileURL.deletingLastPathComponent().path
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [.init(beforePath: sandbox.fileURL.path, afterPath: sandbox.fileURL.path)],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false && priority == .none
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection setTags 최종 record는 성공 target만 stale 처리 후 refresh한다.
    func testSetTagsEntryActionCompletedRefreshesOnlySuccessfulCollectionTargets() async {
        let store = TestStore(initialState: makeCollectionInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [
                .init(beforePath: "/tmp/a.txt", afterPath: "/tmp/a.txt"),
                .init(beforePath: "/tmp/b.txt", afterPath: "/tmp/b.txt"),
            ],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .forwarded(.collection(.externalPathsChanged(paths))) = action else { return false }
            return paths == ["/tmp/a.txt", "/tmp/b.txt"]
        }
        await store.receive { action in
            guard case .forwarded(.view(.refreshStaleCollection)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection setTags undo/redo도 최종 성공 target만 같은 refresh seam으로
    /// 전달한다.
    func testSetTagsUndoAndRedoRefreshOnlySuccessfulCollectionTargets() async {
        let store = TestStore(initialState: makeCollectionInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/a.txt")],
        )

        for direction in [EntryActionDirection.undo, .redo] {
            await store.send(.bridge(.undoRedo(.replaySucceeded(
                direction: direction,
                sourceRecordID: record.id,
                updatedRecord: record,
            ))))
            await store.receive { action in
                guard case let .forwarded(.collection(.externalPathsChanged(paths))) = action else { return false }
                return paths == ["/tmp/a.txt"]
            }
            await store.receive { action in
                guard case .forwarded(.view(.refreshStaleCollection)) = action else { return false }
                return true
            }
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route entry operation 완료 시 directory reload 차단
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 entry operation 완료가 directory loader로 전달되지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedOnCollectionNavigationReturnsNone() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        ))))
        await store.finish()
    }

    private func makeCollectionInitialState() -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        state.content.entryViewLayout.isCollectionMode = true
        return state
    }

    /// EVM-001-reload_directory_page_on_external_change: empty trash 완료 시 window close delegate forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: empty trash 완료 lifecycle이 FileManager closeWindow delegate로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testEmptyTrashCompletedTriggersCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.emptyTrashCompleted)))

        await store.receive { action in
            guard case .forwarded(.delegate(.closeWindow)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: entry action completed metrics-only lifecycle no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: entryActionCompleted lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testEntryActionCompletedReturnsNoneWithoutReload() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: source-preserving 완료 레코드는 parent만 무효화한다.
    /// 복사, 복제, 별칭, 태그, 생성은 원본을 현재 위치에서 제거하지 않으므로 expanded subtree를 제거하면 안 된다.
    /// - 검증 내용: before/after parent가 affectedPaths에 포함되고 removedPrefixes는 비어 있다.
    /// - 사전 조건: navigationState == .folder(/tmp/voyager), source-preserving EntryActionRecord 완료.
    /// - 기대 결과: hierarchyInvalidated가 parent refresh만 요청한다.
    func testSourcePreservingEntryActionCompletedInvalidatesParentsWithoutRemovedPrefixes() async {
        let folderPath = "/tmp/voyager"
        let records = [
            EntryActionRecord(
                operationKind: .createFolder,
                targets: [.init(beforePath: nil, afterPath: "\(folderPath)/new-folder")],
            ),
            EntryActionRecord(
                operationKind: .createAlias,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/source alias")],
            ),
            EntryActionRecord(
                operationKind: .pasteFileCopy,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/copy.txt")],
            ),
            EntryActionRecord(
                operationKind: .pasteFileDuplicate,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/duplicate.txt")],
            ),
            EntryActionRecord(
                operationKind: .setTags,
                targets: [.init(beforePath: "\(folderPath)/source.txt", afterPath: "\(folderPath)/source.txt")],
            ),
        ]

        for record in records {
            let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
                LifecycleBridgeHarness()
            }

            await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
            await store.receive { action in
                guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                    affectedPaths,
                    removedPrefixes,
                )))) = action else { return false }
                return affectedPaths.allSatisfy { $0 == folderPath } && removedPrefixes.isEmpty
            }
            if record.operationKind == .setTags {
                await store.receive { action in
                    guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                        path,
                        showHidden,
                        priority,
                    ))))) = action else { return false }
                    return path == folderPath && showHidden == false && priority == .none
                }
            }
            await store.finish()
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: source-relocating 완료 레코드는 원래 subtree를 제거한다.
    /// 이동, 이름변경, 휴지통 이동, 복원은 원본 경로를 더 이상 유지하지 않으므로 stale expanded subtree를 제거해야 한다.
    /// - 검증 내용: before/after parent가 affectedPaths에 포함되고 beforePath가 removedPrefixes에 포함된다.
    /// - 사전 조건: navigationState == .folder(/tmp/voyager), source-relocating EntryActionRecord 완료.
    /// - 기대 결과: hierarchyInvalidated가 parent refresh와 원본 subtree 제거를 함께 요청한다.
    func testSourceRelocatingEntryActionCompletedInvalidatesParentsAndRemovedPrefixes() async {
        let folderPath = "/tmp/voyager"
        let sourcePath = "\(folderPath)/source.txt"
        let destinationPath = "/tmp/destination/source.txt"
        let records = [
            EntryActionRecord(
                operationKind: .pasteFileMove,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
            EntryActionRecord(
                operationKind: .rename,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
            EntryActionRecord(
                operationKind: .moveToTrash,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
            EntryActionRecord(
                operationKind: .putBack,
                targets: [.init(beforePath: sourcePath, afterPath: destinationPath)],
            ),
        ]

        for record in records {
            let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
                LifecycleBridgeHarness()
            }

            await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
            await store.receive { action in
                guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                    affectedPaths,
                    removedPrefixes,
                )))) = action else { return false }
                return affectedPaths == [folderPath, "/tmp/destination"]
                    && removedPrefixes == [sourcePath]
            }
            await store.finish()
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route put back 완료 시 collection presentation restore
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 putBack 완료 후 collection presentation 복구 액션이 생성되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testPutBackEntryActionCompletedOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let restoredRecord = EntryActionRecord(
            operationKind: .putBack,
            targets: [EntryActionRecord.Target(beforePath: "/Users/me/.Trash/a.txt", afterPath: "/tmp/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.entryActionCompleted(restoredRecord))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route move-to-trash undo 시 collection presentation
    /// restore
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 moveToTrash undo 후 collection presentation 복구 액션이 생성되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testUndoAppliedMoveToTrashOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let trashedRecord = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/Users/me/.Trash/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.undoRedo(.replaySucceeded(
            direction: .undo,
            sourceRecordID: trashedRecord.id,
            updatedRecord: trashedRecord,
        ))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: loading 결과 액션 bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: itemsLoaded 액션이 FileManager content lifecycle bridge side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testLoadingItemsLoadedReturnsNone() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(generation: 0, items: []))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: windowIDChanged lifecycle bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: windowIDChanged lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testWindowIDChangedDoesNotTriggerReloadOrCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.windowIDChanged(UUID()))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: raw pathsMutated는 원본과 대상 부모를 refresh하고 hierarchy를 제거하지 않는다.
    /// Copy, duplicate, drop-copy가 typed completion 전에 내보내는 원시 경로도 폴더 트리의 확장 상태를 유지하는지 검증한다.
    /// - 검증 내용: source와 destination의 parent가 affectedPaths에 순서대로 포함되고 removedPrefixes가 비어 있다.
    /// - 사전 조건: folder route와 source/destination raw mutation path를 가진 lifecycle bridge harness 구성.
    /// - 기대 결과: hierarchyInvalidated가 두 parent refresh만 요청하며 subtree prune을 요청하지 않는다.
    func testPathsMutatedInvalidatesParentsWithoutRemovedPrefixes() async {
        await assertPathsMutatedInvalidatesParentsWithoutRemovedPrefixes()
    }
}

private extension EVM001FileManagerNavigationTests {
    func assertPathsMutatedInvalidatesParentsWithoutRemovedPrefixes() async {
        let folderPath = "/tmp/voyager"
        let sourcePath = "\(folderPath)/source-folder/child.txt"
        let destinationPath = "/tmp/voyager-destination/copied-folder/child.txt"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }

        await store.send(.bridge(.lifecycle(.pathsMutated([sourcePath, destinationPath]))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == ["\(folderPath)/source-folder", "/tmp/voyager-destination/copied-folder"]
                && removedPrefixes.isEmpty
        }
        await store.finish()
    }
}

extension EVM001FileManagerNavigationTests {
    // MARK: - EVM-001-product_navigation_contract

    /// EVM-001-product_navigation_contract: browsing failure categories map to finite terminal results.
    /// typed permission failures must remain distinguishable from unavailable infrastructure.
    /// - 검증 내용: permissionDenied → failure, unavailable → unavailable
    /// - 사전 조건: typed browsing failure categories
    /// - 기대 결과: raw error payload 없이 mutually exclusive terminal result
    func testBrowsingFailureCategoriesMapToFiniteTerminalResults() {
        XCTAssertEqual(
            FileManagerProductMetricsProducer.browsingFailure(.permissionDenied),
            .failure,
        )
        XCTAssertEqual(
            FileManagerProductMetricsProducer.browsingFailure(.unavailable),
            .unavailable,
        )
    }

    // MARK: - EVM-001-product_terminal_metrics

    /// EVM-001-product_terminal_metrics: empty navigation emits the empty terminal only.
    /// accepted navigation은 accumulated entry count가 0일 때 empty terminal 한 건만 만든다.
    /// - 검증 내용: success/empty/failure/unavailable terminal mutual exclusion
    /// - 사전 조건: opaque operation ID와 빈 directory load 결과
    /// - 기대 결과: `.empty` browsing event 1건, raw path 없음
    func testEmptyBrowsingTerminalEmitsEmptyOnly() {
        let operationID = UUID()
        let metric = FileManagerProductMetricsProducer.browsingTerminal(
            operationID: operationID,
            content: .folder,
            identity: .direct,
            source: .fileManagerContent,
            entryCount: 0,
            failure: nil,
        )

        XCTAssertEqual(metric, .contentBrowsing(
            result: .empty,
            content: .folder,
            identity: .direct,
            source: .fileManagerContent,
            operationID: operationID,
        ))
    }

    /// EVM-001-product_terminal_metrics: 현재 Computer 실패는 unavailable terminal을 정확히 한 번 기록한다.
    /// 실제 Computer 로드 오류가 empty 성공으로 축소되지 않고 browsing 실패로 종결되는 경로를 검증한다.
    /// - 검증 내용: 동일 current 실패를 두 번 전달해도 unavailable metric과 correlation 소비는 한 번뿐이다.
    /// - 사전 조건: generation 7의 Computer load와 완전한 browsing correlation이 활성 상태다.
    /// - 기대 결과: unavailable metric 한 건만 기록되고 correlation 필드는 모두 nil이다.
    func testCurrentComputerItemsLoadFailureRecordsUnavailableExactlyOnce() async {
        let operationID = UUID()
        let recorder = FileManagerProductMetricRecorder()
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.isLoading = true
        state.productBrowsingOperationID = operationID
        state.productBrowsingIdentity = .direct
        state.productBrowsingSource = .fileManagerContent
        state.productBrowsingContent = .folder
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: 통합 projection보다 browsing terminal exactly-once 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.computerItemsLoadFailed(generation: 7)))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.computerItemsLoadFailed(generation: 7)))))

        XCTAssertEqual(recorder.metrics(), [
            .contentBrowsing(
                result: .unavailable,
                content: .folder,
                identity: .direct,
                source: .fileManagerContent,
                operationID: operationID,
            ),
        ])
        XCTAssertNil(store.state.productBrowsingOperationID)
        XCTAssertNil(store.state.productBrowsingIdentity)
        XCTAssertNil(store.state.productBrowsingSource)
        XCTAssertNil(store.state.productBrowsingContent)
    }

    /// EVM-001-product_terminal_metrics: stale Computer 실패는 browsing B 상태 전체에서 no-op이다.
    /// 이전 Computer 요청의 오류가 새 폴더 상태나 현재 browsing correlation을 소비하지 않는지 검증한다.
    /// - 검증 내용: stale 실패 전후 FileManagerContentState 동등성과 metric 미기록을 비교한다.
    /// - 사전 조건: generation 8의 폴더 항목, 선택, pending selection, browsing correlation이 유지 중이다.
    /// - 기대 결과: 모든 상태와 correlation이 보존되고 metric은 0건이다.
    func testStaleComputerItemsLoadFailurePreservesBrowsingStateAndCorrelation() async {
        let preservedEntry = EntryModel.temporaryFolder(id: "/folder-b", name: "folder-b")
        var state = FileManagerContentState()
        state.entryViewLayout.entryOperations.loadingContext.generation = 8
        state.entryViewLayout.entryOperations.loadingContext.items = [preservedEntry]
        state.entryViewLayout.entries = [preservedEntry]
        state.entryViewLayout.selectedIds = [preservedEntry.id]
        state.setPendingEntrySelection(entryID: "/folder-b/target", destinationPath: "/folder-b", generation: 8)
        state.productBrowsingOperationID = UUID()
        state.productBrowsingIdentity = .direct
        state.productBrowsingSource = .fileManagerContent
        state.productBrowsingContent = .folder
        let originalState = state
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
        }
        // store.exhaustivity = .off: stale terminal이 통합 B 상태 전체를 보존하는지만 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.computerItemsLoadFailed(generation: 7)))))

        XCTAssertEqual(store.state, originalState)
        XCTAssertTrue(recorder.metrics().isEmpty)
    }

    /// EVM-001-reload_directory_page_on_external_change: dot-segment watch root의 canonical event 보존
    /// 표준화되지 않은 route root도 Shared canonical seam을 통해 FSEvent path와 같은 scope로 비교되는지 검증한다.
    /// - 검증 내용: `/var/tmp/../tmp` interest에 대한 `/private/var/tmp` child event relevance
    /// - 사전 조건: symlink와 parent dot-segment가 함께 포함된 visible-folder interest
    /// - 기대 결과: 원본 FileChangeGatewayEvent가 필터에서 제거되지 않음
    func testGatewayRelevanceStandardizesDotSegmentWatchRoot() {
        let interest = FileChangeWatchInterest(
            id: "visible-folder",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/var/tmp/../tmp"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/private/var/tmp/voyager-changed.txt",
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        )

        XCTAssertEqual(
            gatewayRelevantChangedEvents([event], interest: interest, openedURL: nil),
            [event],
        )
    }
}

// MARK: - Entry Command Product Metrics

extension EVM001FileManagerNavigationTests {
    // MARK: - evm-001-entry_command_product_metrics

    /// EVM-001-entry_command_product_metrics: 겹친 명령의 완료는 각자의 record로 상관된다.
    /// paste 수용 뒤 quickLook이 수용되어 단일 슬롯이 덮어써져도, 완료 순서가 뒤바뀌면 각 record의 id/kind로
    /// 정확히 두 건의 terminal이 기록되어야 한다.
    /// - 검증 내용: 첫 완료(quickLook)와 늦은 완료(paste)가 각각 자신의 record.id와 kind로 기록된다.
    /// - 사전 조건: paste → quickLook 순서로 두 명령을 수용하고 완료는 quickLook → paste 순으로 도착
    /// - 기대 결과: recorder에 entryAction 메트릭 2건(quickLook success, move success)이 순서대로 기록됨
    func testOverlappingCompletionsCorrelateToTheirOwnRecords() async {
        let injectedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x42))
        let recorder = FileManagerProductMetricRecorder(makeOperationID: { injectedID })
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.entryFileOpsClient.loadClipboardPaths = { ([], .copy) }
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 상관 계약에 집중하고 라우팅 부수 효과 수신은 생략함
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.pasteItems",
            source: .fileManagerContent,
        )))))
        await store.send(.content(.entryViewLayout(.delegate(.executeCommand(
            "navigation.quickLookSelectedItem",
            source: .fileManagerContent,
        )))))

        let latePasteRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/src/a.txt", afterPath: "/dest/a.txt")],
        ).attaching(command: .init(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x43)),
            interaction: .pasteEntries,
            source: .contextMenu,
        ))
        let earlyQuickLookRecord = EntryActionRecord(
            operationKind: .quickLook,
            targets: [],
            succeededCount: 1,
        ).attaching(command: .init(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x44)),
            interaction: .quickLookEntry,
            source: .keyboardShortcut,
        ))

        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            earlyQuickLookRecord,
        ))))))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            latePasteRecord,
        ))))))

        XCTAssertEqual(recorder.metrics(), [
            .entryAction(
                result: .success,
                identity: .quickLookEntry,
                source: .keyboardShortcut,
                operationID: earlyQuickLookRecord.id,
                aggregate: .init(attempted: 1, succeeded: 1, failed: 0),
            ),
            .entryAction(
                result: .success,
                identity: .pasteEntries,
                source: .contextMenu,
                operationID: latePasteRecord.id,
                aggregate: .init(attempted: 1, succeeded: 1, failed: 0),
            ),
        ])
    }

    /// EVM-001-entry_command_product_metrics: 전체 실패 배치는 .failure result로 기록된다.
    /// succeeded=0, failed>0인 record는 partial이 아니라 failure로 truthfully 매핑되어야 한다.
    /// - 검증 내용: result가 .failure이고 aggregate가 attempted 2, succeeded 0, failed 2이다.
    /// - 사전 조건: paste 명령 수용 후 targets가 비고 failedCount 2인 record 도착
    /// - 기대 결과: entryAction(.failure, .move) 메트릭 1건 기록
    func testAllFailedBatchMapsToFailureResult() async {
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.entryFileOpsClient.loadClipboardPaths = { ([], .copy) }
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 truth table 계약에 집중함
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.pasteItems",
            source: .fileManagerContent,
        )))))

        let allFailedRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [],
            failedCount: 2,
        ).attaching(command: .init(
            id: UUID(),
            interaction: .pasteEntries,
            source: .fileManagerContent,
        ))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            allFailedRecord,
        ))))))

        XCTAssertEqual(recorder.metrics(), [
            .entryAction(
                result: .failure,
                identity: .pasteEntries,
                source: .fileManagerContent,
                operationID: allFailedRecord.id,
                aggregate: .init(attempted: 2, succeeded: 0, failed: 2),
            ),
        ])
    }

    /// EVM-001-entry_command_product_metrics: 성공 없는 failure+cancel 혼합은 failure로 결정된다.
    /// 일부 대상 취소가 실제 실패를 가리지 않고 aggregate 및 exactly-once를 유지하는지 검증한다.
    /// - 검증 내용: 동일 terminal 중복 전달 뒤 result와 failed/cancelled aggregate를 비교한다.
    /// - 사전 조건: 성공 0, 실패 1, 취소 1인 command-owned record가 두 번 도착한다.
    /// - 기대 결과: failure metric 한 건과 aggregate 2/0/1/1이 기록된다.
    func testFailureAndCancellationWithoutSuccessMapsToSingleFailure() async {
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: terminal truth table과 duplicate suppression만 검증함
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .putBack,
            targets: [],
            failedCount: 1,
            cancelledCount: 1,
            succeededCount: 0,
            id: UUID(),
            timestamp: Date(),
        ).attaching(command: .init(
            id: UUID(),
            interaction: .putDeletedEntriesBack,
            source: .contextMenu,
        ))

        for _ in 0 ..< 2 {
            await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
                record,
            ))))))
        }

        XCTAssertEqual(recorder.metrics(), [
            .entryAction(
                result: .failure,
                identity: .putDeletedEntriesBack,
                source: .contextMenu,
                operationID: record.id,
                aggregate: .init(attempted: 2, succeeded: 0, failed: 1, cancelled: 1),
            ),
        ])
    }

    /// EVM-001-entry_command_product_metrics: 성공/부분 성공 배치는 truth table대로 기록된다.
    /// succeeded>0 failed=0은 success, succeeded>0 failed>0은 partial로 매핑되는지 검증한다.
    /// - 검증 내용: 연속된 두 배치가 각각 success/partial result와 정확한 aggregate로 기록된다.
    /// - 사전 조건: paste 명령을 두 번 수용하고 각각 성공/부분 성공 record가 도착
    /// - 기대 결과: entryAction 메트릭 2건(success 1/1/0, partial 2/1/1)이 순서대로 기록됨
    func testSuccessAndPartialBatchesMapTruthfully() async {
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.entryFileOpsClient.loadClipboardPaths = { ([], .copy) }
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 truth table 계약에 집중함
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.pasteItems",
            source: .fileManagerContent,
        )))))
        let successRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/src/a.txt", afterPath: "/dest/a.txt")],
        ).attaching(command: .init(id: UUID(), interaction: .pasteEntries, source: .fileManagerContent))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            successRecord,
        ))))))

        await store.send(.content(.entryViewLayout(.delegate(.executeCommand(
            "clipboard.pasteItems",
            source: .fileManagerContent,
        )))))
        let partialRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/src/b.txt", afterPath: "/dest/b.txt")],
            failedCount: 1,
        ).attaching(command: .init(id: UUID(), interaction: .pasteEntries, source: .fileManagerContent))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            partialRecord,
        ))))))

        // pasteFileCopy는 실제 연산대로 .copy로 분류된다(단일 .move 회귀 수정).
        XCTAssertEqual(recorder.metrics(), [
            .entryAction(
                result: .success,
                identity: .pasteEntries,
                source: .fileManagerContent,
                operationID: successRecord.id,
                aggregate: .init(attempted: 1, succeeded: 1, failed: 0),
            ),
            .entryAction(
                result: .partial,
                identity: .pasteEntries,
                source: .fileManagerContent,
                operationID: partialRecord.id,
                aggregate: .init(attempted: 2, succeeded: 1, failed: 1),
            ),
        ])
    }

    /// EVM-001-entry_command_product_metrics: content effect에서 방출된 비-undo terminal도 제품 메트릭으로 정확히 한 번 기록된다.
    /// routeContentEffectAction이 비-undo record를 .internal 경로로 돌려 drop하는 P0 회귀를 검증한다.
    /// - 검증 내용: copyPath 명령의 실제 effect terminal이 window 라우팅을 통과해 메트릭 1건으로 기록된다.
    /// - 사전 조건: 선택 항목 1개와 pasteboard 성공 mock, 실제 FileManagerFeature 라우팅 사용
    /// - 기대 결과: entryAction(.copyPath, aggregate 1/1/0) 메트릭 정확히 1건 기록
    func testNonUndoEffectTerminalRecordsSingleProductEvent() async {
        let folderPath = "/tmp/voyager-nonundo-terminal"
        let folder = EntryModel.temporaryFolder(id: folderPath, name: "folder")
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entries = [folder]
        state.content.entryViewLayout.selectedIds = [folder.id]

        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date())
            $0.pasteboardClient = PasteboardClient(
                changeCount: { 0 },
                clearContents: {},
                writeObjects: { _ in true },
                readObjects: { _, _ in nil },
                setString: { _, _ in true },
                string: { _ in nil },
            )
        }
        // store.exhaustivity = .off: window 라우팅 부수 effect보다 메트릭 exactly-once를 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.delegate(
            .executeCommand("clipboard.copySelectedAbsolutePaths", source: .fileManagerContent),
        ))))
        await store.finish()

        XCTAssertEqual(recorder.metrics().count, 1)
        guard case let .entryAction(metric)? = recorder.metrics().first else {
            return XCTFail("Expected one entryAction metric")
        }
        XCTAssertEqual(metric.result, .success)
        XCTAssertEqual(metric.identity, .copyAbsolutePaths)
        XCTAssertEqual(metric.aggregate, .init(attempted: 1, succeeded: 1, failed: 0))
    }

    /// EVM-001-entry_command_product_metrics: paste 계열 record는 실제 연산별 metric kind로 매핑된다.
    /// 복사·복제는 .copy, 이동은 .move로 분류되어야 한다(이전 단일 .move 회귀 수정).
    /// - 검증 내용: pasteFileCopy→.copy, pasteFileDuplicate→.copy, pasteFileMove→.move
    /// - 사전 조건: 성공 target 1개씩을 가진 세 record를 직접 전달
    /// - 기대 결과: entryAction 메트릭 3건이 각각 .copy/.copy/.move로 기록됨
    func testPasteRecordKindsMapToCopyAndMoveActions() async {
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: kind 매핑 계약에 집중함
        store.exhaustivity = .off

        let copyRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/src/a.txt", afterPath: "/dest/a.txt")],
        ).attaching(command: .init(id: UUID(), interaction: .copyEntries, source: .fileManagerContent))
        let duplicateRecord = EntryActionRecord(
            operationKind: .pasteFileDuplicate,
            targets: [.init(beforePath: "/src/b.txt", afterPath: "/dest/b.txt")],
        ).attaching(command: .init(id: UUID(), interaction: .duplicateEntries, source: .fileManagerContent))
        let moveRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: "/src/c.txt", afterPath: "/dest/c.txt")],
        ).attaching(command: .init(id: UUID(), interaction: .pasteEntries, source: .fileManagerContent))
        for record in [copyRecord, duplicateRecord, moveRecord] {
            await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
                record,
            ))))))
        }

        let identities = recorder.metrics().compactMap { metric -> EntryInteractionIdentity? in
            guard case let .entryAction(payload) = metric else { return nil }
            return payload.identity
        }
        XCTAssertEqual(identities, [.copyEntries, .duplicateEntries, .pasteEntries])
    }

    /// EVM-001-entry_command_product_metrics: 압축/해제 record는 이전 fallback인 .copy를 유지한다.
    /// - 검증 내용: compress record의 metric action이 .copy다
    /// - 사전 조건: compress record 1건을 직접 전달
    /// - 기대 결과: entryAction 메트릭 1건이 .copy로 기록됨
    func testCompressRecordMapsToCopyFallback() async {
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: fallback 매핑 계약에 집중함
        store.exhaustivity = .off

        let compressRecord = EntryActionRecord(
            operationKind: .compress,
            targets: [],
        ).attaching(command: .init(id: UUID(), interaction: .compressEntries, source: .contextMenu))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            compressRecord,
        ))))))

        let identities = recorder.metrics().compactMap { metric -> EntryInteractionIdentity? in
            guard case let .entryAction(payload) = metric else { return nil }
            return payload.identity
        }
        XCTAssertEqual(identities, [.compressEntries])
    }

    /// EVM-001-entry_command_product_metrics: 비-undo record도 kind별 메트릭으로 매핑된다.
    /// quickLook/deleteImmediately record가 수용 슬롯 없이도 자체 kind로 terminal이 되는지 검증한다.
    /// - 검증 내용: quickLook은 .quickLook으로, deleteImmediately는 .trash로 매핑되어 2건 기록된다.
    /// - 사전 조건: 명령 수용 없이 비-undo record 두 개를 직접 전달
    /// - 기대 결과: entryAction 메트릭 2건(quickLook success, trash success)이 순서대로 기록됨
    func testNonUndoRecordsMapMetricKinds() async {
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 kind 매핑 계약에 집중함
        store.exhaustivity = .off

        // 성공 1회 시도는 succeededCount로 전달되어 aggregate에 그대로 반영된다.
        let quickLookRecord = EntryActionRecord(operationKind: .quickLook, targets: [], succeededCount: 1)
        // 시도 없는 완료(0/0)는 no-attempt success로 기록된다.
        let deleteRecord = EntryActionRecord(operationKind: .deleteImmediately, targets: [])
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            quickLookRecord,
        ))))))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            deleteRecord,
        ))))))

        XCTAssertTrue(recorder.metrics().isEmpty)
    }

    /// EVM-001-entry_command_product_metrics: keyboard 명령 terminal은 실제 source와 command UUID를 보존한다.
    /// Quick Look key command의 수용 surface가 비동기 terminal까지 command-owned metadata로 전달되는지 검증한다.
    /// - 검증 내용: 실제 key routing과 Quick Look effect를 거친 metric의 source 및 operation ID를 비교한다.
    /// - 사전 조건: 선택 entry 1개, 고정 operation ID, 성공 Quick Look client가 있다.
    /// - 기대 결과: terminal 한 건의 source는 keyboardShortcut이고 operationID는 수용 시 생성한 UUID다.
    func testKeyboardQuickLookPreservesAcceptedCommandSourceAndID() async {
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x71))
        let entry = EntryModel.temporaryFolder(id: "/tmp/keyboard-source", name: "keyboard-source")
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder("/tmp")
        state.content.entryViewLayout.entries = [entry]
        state.content.entryViewLayout.selectedIds = [entry.id]
        let recorder = FileManagerProductMetricRecorder(makeOperationID: { operationID })
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.entryQuickLookClient = EntryQuickLookClient(quickLook: { _, _ in })
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 실제 window/content/EOP routing의 terminal metadata만 검증함
        store.exhaustivity = .off

        await store.send(.content(.view(.handleKeyCommand(.init(
            keyCode: 49,
            modifiers: [],
            characters: " ",
            charactersIgnoringModifiers: " ",
        )))))
        await store.finish()

        guard case let .entryAction(metric)? = recorder.metrics().first else {
            return XCTFail("Expected one entryAction metric")
        }
        XCTAssertEqual(recorder.metrics().count, 1)
        XCTAssertEqual(metric.source, .keyboardShortcut)
        XCTAssertEqual(metric.operationID, operationID)
    }
}

private enum FixturePathError: Error, CustomStringConvertible {
    case repoRootNotFound(searchFrom: String)

    var description: String {
        switch self {
        case let .repoRootNotFound(searchFrom):
            "repo root not found while searching from \(searchFrom)"
        }
    }
}
