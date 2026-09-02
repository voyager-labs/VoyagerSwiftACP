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

private struct ExpandedChildTransitionFixture {
    let state: FileManagerContentState
    let folder: EntryModel
    let before: EntryModel
    let after: EntryModel
}

private struct CrossFolderMoveFixture {
    let state: FileManagerContentState
    let source: EntryModel
    let destination: EntryModel
    let before: EntryModel
    let after: EntryModel
}

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
        allocations: LockIsolated<Int>? = nil,
        initialState: FileManagerFeature.State = .init(),
        configure: (inout DependencyValues) -> Void = { _ in },
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let operationIDIndex = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: { dependencies in
            dependencies.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            dependencies.uuid = .incrementing
            dependencies.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                record: { metric in metrics.withValue { $0.append(metric) } },
                makeOperationID: {
                    allocations?.withValue { $0 += 1 }
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

    private func assertBrowsingSilent(
        _ store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        metrics: LockIsolated<[FileManagerProductMetric]>,
        allocations: LockIsolated<Int>,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(allocations.value, 0, file: file, line: line)
        XCTAssertTrue(metrics.value.isEmpty, file: file, line: line)
        XCTAssertNil(store.state.content.pendingProductBrowsingSource, file: file, line: line)
        XCTAssertNil(store.state.content.productBrowsingOperationID, file: file, line: line)
    }

    private func assertHomeDirectoryBrowsing(
        selection: FileManagerHomeSelection,
        path: String,
        configure: (inout DependencyValues) -> Void = { _ in },
    ) async {
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let allocations = LockIsolated(0)
        let entry = EntryModel.temporaryFolder(id: path + "/child", name: "child")
        let store = makeTypedBrowsingStore(metrics: metrics, allocations: allocations) { dependencies in
            dependencies.entryLoadingClient.loadItems = Self.suspendedLoadItems
            configure(&dependencies)
        }

        await store.sendTabContent(.view(.homeSelectionTapped(selection)))
        await store.skipReceivedActions()
        await store.send(.content(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [entry],
        ))))))

        XCTAssertEqual(allocations.value, 1)
        XCTAssertEqual(metrics.value, [
            .contentBrowsing(
                result: .success,
                content: .folder,
                identity: .direct,
                source: .fileManagerContent,
                operationID: Self.typedBrowsingOperationIDs[0],
            ),
        ])
    }

    /// EVM-001-navigate_pages: Home Favorite preserves content browsing source.
    /// Home Favorites의 directory pageAnchor가 content-origin browsing 계약으로 수렴하는지 검증한다.
    /// - 검증 내용: 실제 FileManager composition에서 선택부터 loading terminal까지 source, operation ID, 단일 event를 검증한다.
    /// - 사전 조건: active Home tab과 directory Favorite, deterministic operation ID가 있다.
    /// - 기대 결과: fileManagerContent source의 success metric을 정확히 한 번 기록하고 ID를 한 번 할당한다.
    func testHomeFavoritePreservesContentBrowsingSource() async {
        let path = "/tmp/voyager-evm001-home-favorite"
        await assertHomeDirectoryBrowsing(selection: .pageAnchor(.directory(path: path)), path: path)
    }

    /// EVM-001-navigate_pages: Home Location preserves content browsing source.
    /// Home Locations의 fixedDirectory가 content-origin browsing 계약으로 수렴하는지 검증한다.
    /// - 검증 내용: 실제 FileManager composition에서 선택부터 loading terminal까지 source, operation ID, 단일 event를 검증한다.
    /// - 사전 조건: active Home tab과 deterministic Documents location, operation ID가 있다.
    /// - 기대 결과: fileManagerContent source의 success metric을 정확히 한 번 기록하고 ID를 한 번 할당한다.
    func testHomeLocationPreservesContentBrowsingSource() async {
        let path = "/tmp/voyager-evm001-home-location"
        await assertHomeDirectoryBrowsing(selection: .fixedDirectory(.documents), path: path) {
            $0.fileManagerClient.urlsForDirectory = { _, _ in [URL(fileURLWithPath: path)] }
        }
    }

    /// EVM-001-navigate_pages: Home Open Directory preserves content browsing source.
    /// Home picker의 selected directory가 content-origin browsing 계약으로 수렴하는지 검증한다.
    /// - 검증 내용: 실제 FileManager composition에서 선택부터 loading terminal까지 source, operation ID, 단일 event를 검증한다.
    /// - 사전 조건: active Home tab과 selected picker result, deterministic operation ID가 있다.
    /// - 기대 결과: fileManagerContent source의 success metric을 정확히 한 번 기록하고 ID를 한 번 할당한다.
    func testHomeOpenDirectoryPreservesContentBrowsingSource() async {
        let path = "/tmp/voyager-evm001-home-picker"
        await assertHomeDirectoryBrowsing(selection: .openDirectory, path: path) {
            $0.homePickerClient.pickDirectory = { .selected(path) }
        }
    }

    /// EVM-001-navigate_pages: rejected Home directory routes stay browsing silent.
    /// 누락 tab, non-Home tab, same route가 Home content browsing correlation을 만들지 않는지 검증한다.
    /// - 검증 내용: 실제 FileManager composition에서 guard와 same-route 처리 후 allocation, pending source, metric을 검증한다.
    /// - 사전 조건: 각 거부 조건에 맞는 tab 및 navigation state가 있다.
    /// - 기대 결과: 모든 경로가 operation ID를 할당하지 않고 correlation과 metric을 남기지 않는다.
    func testRejectedHomeDirectoryRoutesStayBrowsingSilent() async throws {
        do {
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let allocations = LockIsolated(0)
            let store = makeTypedBrowsingStore(metrics: metrics, allocations: allocations)

            await store.send(.tabContent(
                tabID: ContentTabID(rawValue: "missing-home-tab"),
                action: .delegate(.homePageAnchorSelected(.directory(path: "/tmp/missing"))),
            ))

            assertBrowsingSilent(store, metrics: metrics, allocations: allocations)
        }

        do {
            var state = FileManagerFeature.State()
            let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
            state.contentTabs.tabs[id: activeTabID]?.anchor = .directory(path: "/tmp/current")
            state.contentTabs.tabs[id: activeTabID]?.page = .directory
            state.content.navigation.navigationState = .folder("/tmp/current")
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let allocations = LockIsolated(0)
            let store = makeTypedBrowsingStore(
                metrics: metrics,
                allocations: allocations,
                initialState: state,
            )

            await store.send(.tabContent(
                tabID: activeTabID,
                action: .delegate(.homePageAnchorSelected(.directory(path: "/tmp/other"))),
            ))

            assertBrowsingSilent(store, metrics: metrics, allocations: allocations)
        }

        do {
            let path = "/tmp/voyager-evm001-home-same-route"
            var state = FileManagerFeature.State()
            state.content.navigation.navigationState = .folder(path)
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let allocations = LockIsolated(0)
            let store = makeTypedBrowsingStore(
                metrics: metrics,
                allocations: allocations,
                initialState: state,
            )

            await store.sendTabContent(.view(.homeSelectionTapped(.pageAnchor(.directory(path: path)))))
            await store.skipReceivedActions()

            assertBrowsingSilent(store, metrics: metrics, allocations: allocations)
        }
    }

    /// EVM-001-navigate_pages: non-directory Home outcomes stay browsing silent.
    /// picker 취소·실패와 Collection·AI 선택이 directory browsing source나 operation을 만들지 않는지 검증한다.
    /// - 검증 내용: 실제 FileManager composition의 각 완료 경로 뒤 allocation, pending source, metric을 검증한다.
    /// - 사전 조건: active Home tab과 deterministic picker, collection, AI dependency 결과가 있다.
    /// - 기대 결과: 모든 경로가 operation ID를 할당하지 않고 correlation과 metric을 남기지 않는다.
    func testNonDirectoryHomeOutcomesStayBrowsingSilent() async {
        for result in [
            FileManagerHomePickerResult<String>.cancelled,
            .failed("picker failed"),
        ] {
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let allocations = LockIsolated(0)
            let store = makeTypedBrowsingStore(metrics: metrics, allocations: allocations) {
                $0.homePickerClient.pickDirectory = { result }
            }

            await store.sendTabContent(.view(.homeSelectionTapped(.openDirectory)))
            await store.skipReceivedActions()

            assertBrowsingSilent(store, metrics: metrics, allocations: allocations)
        }

        do {
            struct CollectionLoadFailure: Error {}
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let allocations = LockIsolated(0)
            let store = makeTypedBrowsingStore(metrics: metrics, allocations: allocations) {
                $0.homePickerClient.pickCollectionFile = {
                    .selected(URL(fileURLWithPath: "/tmp/voyager-evm001-home.voycoll"))
                }
                $0.collectionFileClient.load = { _ in throw CollectionLoadFailure() }
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            }

            await store.sendTabContent(.view(.homeSelectionTapped(.openCollection)))
            await store.skipReceivedActions()

            assertBrowsingSilent(store, metrics: metrics, allocations: allocations)
        }

        do {
            let sessionID = "E0010000-0000-0000-0000-0000000000A1"
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let allocations = LockIsolated(0)
            let store = makeTypedBrowsingStore(metrics: metrics, allocations: allocations) {
                $0.homeAiChatClient.createSession = { .selected(sessionID) }
                $0.aiConnectionsFileClient.load = { .empty() }
                $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            }

            await store.sendTabContent(.view(.homeSelectionTapped(.startAiChat)))
            await store.skipReceivedActions()

            assertBrowsingSilent(store, metrics: metrics, allocations: allocations)
        }
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

    /// EVM-001-navigate_pages: content chrome keeps accepted navigation in the content browsing domain.
    /// Toolbar, history, swipe, and breadcrumb callbacks must preserve their content ownership at the window bridge.
    /// - 검증 내용: accepted chrome routes allocate content browsing source, rejected and same-route inputs stay silent.
    /// - 사전 조건: each accepted route has its required history or parent state; rejected routes do not.
    /// - 기대 결과: accepted routes use fileManagerContent, rejected and same-route routes allocate no operation.
    func testContentChromeNavigationMatrixPreservesContentBrowsingSource() async throws {
        let accepted: [(
            ContentPageNavigationAction.View,
            ContentPageNavigationInteractionIdentity,
            (inout FileManagerFeature.State) -> Void,
        )] = [
            (.goBack, .back, { $0.content.navigation.backHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/tmp/content-back")),
            ] }),
            (.goForward, .forward, { $0.content.navigation.forwardHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/tmp/content-forward")),
            ] }),
            (.goToHistoryIndex(0, isBackHistory: true), .history, { $0.content.navigation.backHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/tmp/content-history")),
            ] }),
            (
                .goToEnclosingDirectory,
                .enclosingDirectory,
                { $0.content.navigation.navigationState = .folder("/tmp/content-parent/child") },
            ),
            (
                .navigateToPath("/tmp/content-breadcrumb"),
                .direct,
                { $0.content.navigation.navigationState = .folder("/tmp/content-current") },
            ),
        ]

        for (action, identity, configureState) in accepted {
            var state = FileManagerFeature.State()
            configureState(&state)
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let store = makeTypedBrowsingStore(metrics: metrics, initialState: state)

            let activeTabID = try XCTUnwrap(store.state.contentTabs.activeTabID)
            await store.send(.tabContent(
                tabID: activeTabID,
                action: .internal(.requestNavigation(.view(action))),
            ))
            await store.skipReceivedActions()

            XCTAssertEqual(metrics.value, [
                .contentBrowsing(
                    result: .empty,
                    content: .folder,
                    identity: identity,
                    source: .fileManagerContent,
                    operationID: Self.typedBrowsingOperationIDs[0],
                ),
            ], "\(action)")
        }

        let silent: [(ContentPageNavigationAction.View, (inout FileManagerFeature.State) -> Void)] = [
            (.goBack, { _ in }),
            (.goForward, { _ in }),
            (.goToHistoryIndex(0, isBackHistory: true), { _ in }),
            (.goToEnclosingDirectory, { $0.content.navigation.navigationState = .folder("/") }),
            (
                .navigateToPath("/tmp/content-same"),
                { $0.content.navigation.navigationState = .folder("/tmp/content-same") },
            ),
        ]

        for (action, configureState) in silent {
            var state = FileManagerFeature.State()
            configureState(&state)
            let metrics = LockIsolated<[FileManagerProductMetric]>([])
            let store = makeTypedBrowsingStore(metrics: metrics, initialState: state)

            let activeTabID = try XCTUnwrap(store.state.contentTabs.activeTabID)
            await store.send(.tabContent(
                tabID: activeTabID,
                action: .internal(.requestNavigation(.view(action))),
            ))

            XCTAssertNil(store.state.content.productBrowsingOperationID, "\(action)")
            XCTAssertTrue(metrics.value.isEmpty, "\(action)")
        }
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
            .streamFailed(generation: generation, failure: .unavailable(description: "test")),
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
            .streamFailed(generation: generation, failure: .unavailable(description: "test")),
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
            .streamFailed(generation: generation, failure: .unavailable(description: "test")),
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

    /// EVM-001-content_browsing_correlation: superseded navigation terminalizes A before B starts.
    /// 서로 다른 A/B 탐색이 겹칠 때 A를 unavailable로 종결하고 B가 새 상관을 소유하는지 검증한다.
    /// - 검증 내용: A/B의 ID·identity·source 구분, stale·duplicate A 무이벤트, current B exactly-once
    /// - 사전 조건: A back/content 로딩 중 B forward/sidebar 탐색을 수락한 응답 없는 loader
    /// - 기대 결과: A unavailable 뒤 B의 operation ID와 metadata를 가진 success가 순서대로 기록됨
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

        let expectedUnavailableA = FileManagerProductMetric.contentBrowsing(
            result: .unavailable,
            content: .folder,
            identity: .back,
            source: .fileManagerContent,
            operationID: Self.typedBrowsingOperationIDs[0],
        )
        XCTAssertEqual(metrics.value, [expectedUnavailableA])

        for _ in 0 ..< 2 {
            await store.send(.content(.entryViewLayout(.entryOperations(.loading(
                .streamFailed(generation: generationA, failure: .unavailable(description: "test")),
            )))))
        }
        XCTAssertEqual(metrics.value, [expectedUnavailableA], "stale or duplicate A must stay silent")
        XCTAssertEqual(store.state.content.productBrowsingOperationID, Self.typedBrowsingOperationIDs[1])
        XCTAssertEqual(store.state.content.productBrowsingIdentity, .forward)
        XCTAssertEqual(store.state.content.productBrowsingSource, .fileManagerSidebar)
        XCTAssertEqual(store.state.content.productBrowsingContent, .folder)

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
            [
                expectedUnavailableA,
                .contentBrowsing(
                    result: .success,
                    content: .folder,
                    identity: .forward,
                    source: .fileManagerSidebar,
                    operationID: Self.typedBrowsingOperationIDs[1],
                ),
            ],
            "A must terminalize before current B emits exactly once",
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

    /// EVM-001-content_browsing_correlation: non-loading transition terminalizes accepted browsing.
    /// 수락된 A 탐색 로딩 중 AI route로 전환하면 원래 상관 정보로 unavailable 단말을 기록한다.
    /// - 검증 내용: accepted A 뒤 AI delegate 전환의 typed terminal과 전체 correlation 해제
    /// - 사전 조건: content-originated folder A가 수락되어 응답 없는 loader에서 로딩 중이다.
    /// - 기대 결과: A operation ID·content·identity·source의 unavailable 한 건과 correlation nil
    func testNonLoadingRouteTerminalizesAcceptedBrowsing() async {
        let pathA = "/tmp/voyager-evm001-accepted-before-ai"
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeTypedBrowsingStore(metrics: metrics) {
            $0.entryLoadingClient.loadItems = Self.suspendedLoadItems
        }

        await store.send(.content(.internal(.requestNavigation(.view(.navigateToPath(pathA))))))
        await store.send(.navigation(.view(.navigateToPath(pathA))))
        await store.skipReceivedActions()

        await store.send(.navigation(.delegate(.logDAUNavigation(
            previous: .folder(pathA),
            next: .aiChat("evm001-chat"),
            identity: .direct,
        ))))

        XCTAssertEqual(metrics.value, [
            .contentBrowsing(
                result: .unavailable,
                content: .folder,
                identity: .direct,
                source: .fileManagerContent,
                operationID: Self.typedBrowsingOperationIDs[0],
            ),
        ])
        XCTAssertNil(store.state.content.productBrowsingOperationID)
        XCTAssertNil(store.state.content.productBrowsingIdentity)
        XCTAssertNil(store.state.content.productBrowsingSource)
        XCTAssertNil(store.state.content.productBrowsingContent)
        XCTAssertNil(store.state.content.pendingProductBrowsingSource)
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
            guard case let .entryViewLayout(.hierarchy(.coarseHierarchyInvalidated(
                removedPrefixes: removedPrefixes,
                _,
            ))) = action
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

    private func makeCorrelationEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: .distantPast,
            fileExtension: "",
            facets: EntryFacets(
                createdDate: .distantPast,
                addedDate: .distantPast,
                lastOpenedDate: nil,
                kind: "",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    private func makeCorrelationState(folderPath: String) -> CommandExternalRefreshHarness.State {
        var state = CommandExternalRefreshHarness.State()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    /// EVM-001-reload_directory_page_on_external_change: replacement 선택 보존은 lexical after identity로 판정한다.
    /// - 검증 내용: canonical after와 같은 target이 선택·projection에 있어도 lexical after 미도착을 구분한다.
    /// - 사전 조건: before symlink와 실제 target이 함께 선택되고 target row만 로드된 대기 전이.
    /// - 기대 결과: before lexical ID가 replacement batch 선택 보존 대상으로 기록된다.
    func testReplacementSelectionMarkingIgnoresSelectedCanonicalAfterAlias() throws {
        let folderURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voyager-identity-boundary-\(UUID().uuidString)")
        let targetURL = folderURL.appendingPathComponent("target")
        let linkURL = folderURL.appendingPathComponent("renamed-link")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: targetURL.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let oldPath = folderURL.appendingPathComponent("old-link").path
        let targetRow = makeCorrelationEntry(id: targetURL.path, name: "target")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(folderURL.path)
        state.navigation.navigationState = .folder(folderURL.path)
        state.entryViewLayout.selectedIds = [oldPath, targetURL.path]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.items = [targetRow]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: targetURL.path,
            rootPath: Self.canonicalPath(folderURL.path),
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: nil,
            afterLexicalPath: linkURL.path,
        )

        FileManagerContentIdentityTransitionCoordinator.markReplacementSelection(
            on: .entryViewLayout(.entryOperations(.loading(.itemsLoaded(
                generation: state.entryViewLayout.entryOperations.loadingContext.generation,
                items: [targetRow],
            )))),
            state: &state,
        )

        XCTAssertEqual(state.pendingIdentityTransition?.preserveSelectionForReplacementBatch, true)
        XCTAssertEqual(state.pendingIdentityTransition?.preservedLexicalBeforeID, oldPath)
    }

    /// EVM-001-command_external_refresh_correlation: source projection hold는 lexical owner만 보류한다.
    /// canonical target이 같은 expanded symlink alias가 동시에 존재해도 다른 alias의 batch를
    /// source hold로 오인하지 않아야 한다.
    /// - 검증 내용: canonical-equivalent alias B에는 hold를 만들지 않고 lexical owner A에만 생성
    /// - 사전 조건: preservationOwner가 alias A인 대기 identity transition
    /// - 기대 결과: alias B 호출은 no-op, alias A 호출은 migration hold를 설치
    func testSourceProjectionHoldsUseLexicalOwnerIdentity() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a")
        let aliasBURL = rootURL.appendingPathComponent("alias-b")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var state = FileManagerContentState()
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: rootURL.appendingPathComponent("before").path,
            afterPath: rootURL.appendingPathComponent("after").path,
            rootPath: rootURL.path,
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            preservationOwner: .folder(id: aliasAURL.path, generation: 2),
            afterLexicalPath: rootURL.appendingPathComponent("after").path,
        )

        FileManagerContentIdentityTransitionCoordinator.beginDeferredFolderReplacementIfNeeded(
            folderID: aliasBURL.path,
            items: [],
            state: &state,
        )
        XCTAssertNil(state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: aliasBURL.path))

        FileManagerContentIdentityTransitionCoordinator.beginDeferredFolderReplacementIfNeeded(
            folderID: aliasAURL.path,
            items: [],
            state: &state,
        )
        XCTAssertEqual(
            state.entryViewLayout.hierarchy.deferredFolderReplacement(folderID: aliasAURL.path)?.holdsUntilMigration,
            true,
        )
    }

    /// EVM-001-command_external_refresh_correlation: identity migration은 lexical batch owner를 요구한다.
    /// canonical-equivalent alias의 batch가 다른 lexical folder transition의 selection을 소비하지 않아야 한다.
    /// - 검증 내용: alias B batch를 alias A owner transition에 적용해도 선택·전이가 유지되는지 검증
    /// - 사전 조건: alias A가 projection owner인 대기 transition과 before/after row가 있다.
    /// - 기대 결과: alias B batch는 migration하지 않고 before 선택을 유지
    func testIdentityMigrationRejectsCanonicalAliasOwner() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a")
        let aliasBURL = rootURL.appendingPathComponent("alias-b")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let beforePath = rootURL.appendingPathComponent("before").path
        let afterPath = aliasAURL.appendingPathComponent("after").path
        let after = makeCorrelationEntry(id: afterPath, name: "after")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootURL.path)
        state.navigation.navigationState = .folder(rootURL.path)
        state.entryViewLayout.selectedIds = [beforePath]
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: beforePath,
            afterPath: afterPath,
            rootPath: rootURL.path,
            refreshGeneration: 1,
            projectionOwner: .folder(id: aliasAURL.path, generation: 2),
            preservationOwner: nil,
            afterLexicalPath: afterPath,
        )

        let didMigrate = FileManagerContentIdentityTransitionCoordinator.migrateSelection(
            entries: [after],
            projectionOwner: .folder(id: aliasBURL.path, generation: 2),
            state: &state,
        )

        XCTAssertFalse(didMigrate)
        XCTAssertEqual(state.entryViewLayout.selectedIds, [beforePath])
        XCTAssertNotNil(state.pendingIdentityTransition)
    }

    private func makeExpandedChildTransitionFixture() -> ExpandedChildTransitionFixture {
        let rootPath = "/tmp/voyager-correlation"
        let folder = EntryModel.temporaryFolder(id: "\(rootPath)/folder", name: "folder")
        let before = makeCorrelationEntry(id: "\(folder.id)/before.txt", name: "before.txt")
        let after = makeCorrelationEntry(id: "\(folder.id)/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.entryOperations.items = [folder]
        state.entryViewLayout.entryOperations.loadingContext.items = [folder]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[folder.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )
        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.generation = 2
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.loadPhase = .loadingCore
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.coreFinished = false
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.expectedBatchIndex = 0
        state.entryViewLayout.hierarchy.nodesByID[folder.id]?.folder.hasAppliedContentBatch = false
        return ExpandedChildTransitionFixture(state: state, folder: folder, before: before, after: after)
    }

    private func makeCrossFolderMoveFixture() -> CrossFolderMoveFixture {
        let rootPath = "/tmp/voyager-cross-move"
        let source = EntryModel.temporaryFolder(id: "\(rootPath)/src", name: "src")
        let destination = EntryModel.temporaryFolder(id: "\(rootPath)/dst", name: "dst")
        let before = makeCorrelationEntry(id: "\(source.id)/before.txt", name: "before.txt")
        let after = makeCorrelationEntry(id: "\(destination.id)/after.txt", name: "after.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source, destination]
        state.entryViewLayout.entryOperations.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.items = [source, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 1
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )
        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)
        for id in [source.id, destination.id] {
            state.entryViewLayout.hierarchy.nodesByID[id]?.generation = 2
            state.entryViewLayout.hierarchy.nodesByID[id]?.loadPhase = .loadingCore
            state.entryViewLayout.hierarchy.nodesByID[id]?.folder.coreFinished = false
            state.entryViewLayout.hierarchy.nodesByID[id]?.folder.expectedBatchIndex = 0
            state.entryViewLayout.hierarchy.nodesByID[id]?.folder.hasAppliedContentBatch = false
        }
        return CrossFolderMoveFixture(
            state: state,
            source: source,
            destination: destination,
            before: before,
            after: after,
        )
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

    /// EVM-001-reload_directory_page_on_external_change: paste 실패도 교체 선삭제 이후라면 reload한다.
    /// replace-existing 파이프라인은 목적지를 먼저 삭제한 뒤 move/copy하므로,
    /// 취소 아닌 실패는 이미 파일시스템이 변경됐을 수 있다.
    /// - 검증 내용: pasteFileMove system 실패 수신 시 현재 folder loader로 reload 전달
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: loadItems forwarding이 발생해 삭제된 목적지 항목이 화면에서 정리된다
    func testPasteMoveFailureReloadsContentForDestructivePreStep() async {
        let folderPath = "/tmp/voyager-paste-failure"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/source.txt",
            .pasteFileMove,
            .failure(.system(message: "post-delete failure")),
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

    /// EVM-001-reload_directory_page_on_external_change: 취소된 paste 실패는 mutation 전이므로 reload하지 않는다.
    /// - 검증 내용: pasteFileMove cancelled 실패 수신 시 forwarding 없음
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: reload effect 미발생
    func testCancelledPasteFailureDoesNotReloadContent() async {
        let folderPath = "/tmp/voyager-paste-cancel"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/source.txt",
            .pasteFileMove,
            .failure(.cancelled),
        ))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: drop 실패도 교체 선삭제 이후라면 reload한다.
    /// drop은 성공 시 entriesMutated impact로 갱신되지만, 전체 실패 배치는 impact가 없어
    /// operationFinished와 같은 destructive pre-step 분류로 보완한다.
    /// - 검증 내용: dropOperationFinished pasteFileMove system 실패 수신 시 reload 전달
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: loadItems forwarding이 발생한다
    func testDropMoveFailureReloadsContentForDestructivePreStep() async {
        let folderPath = "/tmp/voyager-drop-failure"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.dropOperationFinished(
            "\(folderPath)/source.txt",
            .pasteFileMove,
            .failure(.system(message: "post-delete failure")),
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

    /// EVM-001-reload_directory_page_on_external_change: 취소된 drop 실패는 reload하지 않는다.
    /// - 검증 내용: dropOperationFinished pasteFileCopy cancelled 실패 수신 시 forwarding 없음
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: reload effect 미발생
    func testCancelledDropFailureDoesNotReloadContent() async {
        let folderPath = "/tmp/voyager-drop-cancel"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.dropOperationFinished(
            "\(folderPath)/source.txt",
            .pasteFileCopy,
            .failure(.cancelled),
        ))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 압축 해제 부분 실패도 mutation 전이므로 reload한다.
    /// extract는 대상 폴더 생성 후 항목을 하나씩 옮기므로 중간 실패 시 일부 결과가 남는다.
    /// - 검증 내용: operationFinished .extract system 실패 수신 시 reload 전달
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: loadItems forwarding이 발생한다
    func testExtractFailureReloadsContentForPartialMutation() async {
        let folderPath = "/tmp/voyager-extract-failure"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/archive.zip",
            .extract,
            .failure(.system(message: "mid-extract move failure")),
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

    /// EVM-001-reload_directory_page_on_external_change: 취소된 extract 실패는 reload하지 않는다.
    /// - 검증 내용: operationFinished .extract cancelled 수신 시 forwarding 없음
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: reload effect 미발생
    func testCancelledExtractFailureDoesNotReloadContent() async {
        let folderPath = "/tmp/voyager-extract-cancel"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "\(folderPath)/archive.zip",
            .extract,
            .failure(.cancelled),
        ))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: undo/redo rename도 folder route에서 root reload를 유지한다.
    /// replaySucceeded는 entryActionCompleted 없이 도착하므로 operationFinished에서 보류한
    /// reload를 이 경로가 대신 수행하지 않으면 목록이 이전 identity에 머문다.
    /// - 검증 내용: folder route replaySucceeded rename record가 loadItems forwarding을 내는지 검증
    /// - 사전 조건: folder route의 LifecycleBridgeHarness
    /// - 기대 결과: hierarchyInvalidated와 loadItems forwarding이 발생한다
    func testUndoRedoReplayKeepsRootReloadForIdentityOperations() async {
        let folderPath = "/tmp/voyager-undo-rename"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.undoRedo(.replaySucceeded(
            direction: .undo,
            sourceRecordID: UUID(),
            updatedRecord: EntryActionRecord(
                operationKind: .rename,
                targets: [
                    // 프로덕션 계약: updatedRecord는 원래(old→new) target을 유지하고
                    // 실행만 after→before로 뒤집힌다.
                    .init(beforePath: "\(folderPath)/old.txt", afterPath: "\(folderPath)/new.txt"),
                ],
            ),
        ))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == ["\(folderPath)/new.txt"]
        }
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

    /// EVM-001-command_external_refresh_correlation: symlink 이동의 선택은 lexical after 행으로 옮겨진다.
    /// 대상 폴더에 symlink target 실체가 함께 있어도 resolved 경로 매칭이 그 행을 먼저 고르지 않아야 한다.
    /// - 검증 내용: afterLexicalPath 우선 매칭이 renamed symlink 행을 선택하는지 검증
    /// - 사전 조건: canonical after가 target을 가리키는 전이와 link/target 두 row
    /// - 기대 결과: selectedIds가 lexical link 행으로 이동하고 전이 소비
    func testSymlinkAfterPathPrefersLexicalRowOverResolvedTarget() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let linkPath = "\(folderPath)/dst/link"
        let targetPath = "/outside/target"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath(linkPath),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: .root(
                generation: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            ),
            preservationOwner: nil,
            afterLexicalPath: linkPath,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let linkRow = makeCorrelationEntry(id: linkPath, name: "link")
        let targetRow = makeCorrelationEntry(id: targetPath, name: "target")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [targetRow, linkRow],
        ))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [linkPath],
            "resolved target이 아니라 renamed symlink lexical 행이 선택된다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: 폴더 무효화는 해당 폴더 소유자 세대를 재기준화한다.
    /// 확장 폴더 안 파일의 ItemModified가 startLoad 재시작으로 노드 세대를 올리면,
    /// 그 폴더를 소유자로 저장한 대기 전이도 새 세대로 이동해야 후속 batch에서 살아남는다.
    /// - 검증 내용: 소유자 폴더 내부 수정 이벤트 뒤 projectionOwner 세대 +1 검증
    /// - 사전 조건: src 확장 폴더(세대 3 완료)를 소유자로 가진 대기 전이
    /// - 기대 결과: projectionOwner가 .folder(src, 4)로 갱신
    func testHierarchyInvalidationRebasesFolderOwnerGeneration() async {
        let folderPath = "/tmp/voyager-correlation"
        let srcPath = "\(folderPath)/src"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.hierarchy.nodesByID[srcPath] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        initialState.content.entryViewLayout.hierarchy.setExpandedIDs([srcPath])
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: .folder(id: srcPath, generation: 3),
            preservationOwner: nil,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents(
            ["\(srcPath)/inner.txt"],
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        ))))
        XCTAssertEqual(
            store.state.content.pendingIdentityTransition?.projectionOwner,
            .folder(id: srcPath, generation: 4),
            "재시작된 소유자 폴더의 세대로 전이가 재기준화된다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: symlink after 행 도착 전 target fallback으로 선택하지 않는다.
    /// 대상 실체 파일이 더 이른 batch에 먼저 와도 resolved 매칭 fallback이 이를
    /// 가져가지 않고, renamed symlink lexical 행이 올 때까지 전이를 유지한다.
    /// - 검증 내용: target 선행 batch에서 선택·전이 보존, link batch에서 migration 검증
    /// - 사전 조건: canonical after가 target을 가리키는 대기 전이
    /// - 기대 결과: 1차 batch 무변화, 2차 batch에서 lexical link 행 선택 + 전이 소비
    func testSymlinkMigrationWaitsForLexicalAfterRowAcrossBatches() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let linkPath = "\(folderPath)/dst/link"
        let targetPath = "/outside/target"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath(linkPath),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: .root(
                generation: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            ),
            preservationOwner: nil,
            afterLexicalPath: linkPath,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let targetRow = makeCorrelationEntry(id: targetPath, name: "target")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [targetRow],
        ))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [oldPath],
            "resolved target 행이 lexical after보다 먼저 와도 선택을 옮기지 않는다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        let linkRow = makeCorrelationEntry(id: linkPath, name: "link")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [targetRow, linkRow],
        ))))
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, [linkPath])
        XCTAssertNil(store.state.content.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: coarse 무효화도 폴더 소유자 세대를 재기준화한다.
    /// MustScanSubDirs 재스캔은 모든 확장 폴더를 되감으므로 그 소유자로 저장된 전이도
    /// 새 세대로 이동해야 후속 folder batch에서 selection migration이 살아남는다.
    /// - 검증 내용: coarse 이벤트 뒤 projectionOwner 세대 +1 검증
    /// - 사전 조건: src 확장 폴더(세대 3 완료)를 소유자로 가진 대기 전이
    /// - 기대 결과: projectionOwner가 .folder(src, 4)로 갱신
    func testCoarseInvalidationRebasesFolderOwnerGeneration() async {
        let folderPath = "/tmp/voyager-correlation"
        let srcPath = "\(folderPath)/src"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.hierarchy.nodesByID[srcPath] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        initialState.content.entryViewLayout.hierarchy.setExpandedIDs([srcPath])
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: .folder(id: srcPath, generation: 3),
            preservationOwner: nil,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents(
            [folderPath],
            flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs),
        ))))
        XCTAssertEqual(
            store.state.content.pendingIdentityTransition?.projectionOwner,
            .folder(id: srcPath, generation: 4),
            "coarse 재시작 대상 폴더의 세대로 전이가 재기준화된다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: coarse 무효화는 모든 확장 폴더를 targeted로 재시작한다.
    /// 소유자 폴더 외의 loaded 확장 폴더도 stale로 남지 않게 hierarchyInvalidated가
    /// 전체 expanded 폴더를 포함하는지 검증한다.
    /// - 검증 내용: coarse 이벤트가 src/dst 두 확장 폴더 모두를 affectedPaths로 보내는지 검증
    /// - 사전 조건: 소유자 폴더와 별도 loaded 확장 폴더가 공존
    /// - 기대 결과: forwarded hierarchyInvalidated의 affectedPaths가 [src, dst] parent 집합과 일치
    func testCoarseDowngradeStillRestartsAllExpandedFolders() async {
        let folderPath = "/tmp/voyager-correlation"
        let srcPath = "\(folderPath)/src"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.hierarchy.nodesByID[srcPath] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 3,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        initialState.content.entryViewLayout.hierarchy.setExpandedIDs([srcPath])
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            projectionOwner: .folder(id: srcPath, generation: 3),
            preservationOwner: nil,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents(
            [folderPath],
            flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs),
        ))))
        let invalidations = store.state.content.entryViewLayout.hierarchy.nodesByID.values
        XCTAssertFalse(invalidations.isEmpty)
        XCTAssertEqual(
            store.state.content.pendingIdentityTransition?.projectionOwner,
            .folder(id: srcPath, generation: 4),
            "모든 확장 폴더 targeted 재시작 후에도 소유자 세대가 재기준화된다",
        )
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
            store.exhaustivity = .off

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
            store.exhaustivity = .off

            await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
            await store.receive { (action: LifecycleBridgeHarness.Action) in
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

    // MARK: - EVM-001-command_external_refresh_correlation

    /// EVM-001-command_external_refresh_correlation: 명령 완료 후 일치하는 외부 rename 이벤트가 중복 refresh를 예약한다(현행 고정).
    /// rename 명령 완료가 예약한 계층 무효화와 동일 identity 변경의 외부 이벤트 무효화가
    /// 현재는 별도의 visible refresh로 중복 예약되는 현행 동작을 고정한다.
    /// - 검증 내용: hierarchyInvalidation 총 2회(명령 1 + 외부 1)와 외부 root reload 1회 예약 수
    /// - 사전 조건: folder 라우트에서 old.txt 선택 후 rename 완료 기록, 같은 경로의 외부 renamed 이벤트
    /// - 기대 결과: 계층 무효화 2회, 외부 loadItems 1회로 중복 refresh 의도가 관측됨
    func testCommandCompletionThenMatchingExternalEventSchedulesDuplicateRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let store = TestStore(initialState: makeCorrelationState(folderPath: folderPath)) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([oldPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(oldPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(oldPath)]
        }
        await store.receive { action in
            guard case let .content(.entryViewLayout(.entryOperations(.loading(.loadItems(path, _, _))))) =
                action else { return false }
            return path == folderPath
        }

        XCTAssertEqual(store.state.hierarchyInvalidations.count, 2, "명령과 외부 이벤트가 각각 계층 무효화를 예약한다")
        XCTAssertEqual(store.state.rootReloadCount, 2, "외부 이벤트가 root reload를 추가로 예약한다")
    }

    /// EVM-001-command_external_refresh_correlation: 일치하는 외부 rename 이벤트는 명령 refresh에 병합된다.
    /// consume-once 경로 전이가 있으면 동일 identity 변경의 외부 이벤트를 보류 scope로 저장하고,
    /// 뒤이은 무관한 이벤트의 refresh 경계에 함께 병합하는지 검증한다.
    /// - 검증 내용: 무관한 후속 이벤트 처리까지 마친 뒤 hierarchyInvalidation 총 2회, loadItems 총 1회
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 일치 이벤트는 즉시 refresh하지 않지만 scope를 잃지 않고 무관한 refresh에 병합된다
    func testCorrelatedExternalRenameMergesIntoCommandRefreshWithoutDuplicate() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents(
                [oldPath, newPath],
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
            ),
            deliveryChainToken: nil,
        )))
        // 큐를 배출할 후속 무관한 이벤트. 이것의 출력 수신이 끝났는데도 앞선 일치 이벤트의
        // 출력이 없었다면 병합(중복 억제)이 확정된다.
        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath]))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return Set(affectedPaths) == Set([
                Self.canonicalPath(unrelatedPath),
                Self.canonicalPath(folderPath),
                Self.canonicalPath(oldPath),
                Self.canonicalPath(newPath),
            ])
                && removedPrefixes == [Self.canonicalPath(oldPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "일치하는 외부 이벤트는 계층 무효화를 추가하지 않고 무관한 이벤트만 추가한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "일치하는 외부 이벤트는 중복 root reload를 예약하지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 독립적인 수정 이벤트는 명령 refresh로 병합되지 않는다.
    /// 대기 전이 경로와 겹쳐도 ItemModified는 명령 snapshot 이후 변경일 수 있으므로
    /// 기존 refresh 경로로 통과해 표시가 stale해지지 않게 한다.
    /// - 검증 내용: after-path ItemModified 이벤트가 계층 무효화와 reload를 예약하는지 검증
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중
    /// - 기대 결과: hierarchyInvalidated 1회와 loadItems forwarding이 발생한다
    func testCorrelatedModifiedEventStillSchedulesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([newPath], flags: UInt32(kFSEventStreamEventFlagItemModified)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(newPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "독립 수정 이벤트는 계층 무효화를 예약해야 한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "독립 수정 이벤트는 root reload를 예약해야 한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "수정 이벤트는 전이를 소비하지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: rename+modification 결합 이벤트는 순수 rename echo로 보지 않는다.
    /// Helper gateway가 같은 경로의 플래그를 `existingEvent.flags | event.flags`로 병합하면
    /// rename과 후속 modification이 하나의 delivery로 합쳐질 수 있다. 이때 ItemRenamed 비트만
    /// 보고 전체를 command echo로 제거하면 독립 수정을 유실한다.
    /// - 검증 내용: ItemRenamed|ItemModified 결합 이벤트가 계층 무효화와 reload를 예약하는지 검증
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중
    /// - 기대 결과: hierarchyInvalidated 1회와 loadItems forwarding이 발생하고 전이는 소비되지 않는다
    func testCorrelatedCoalescedRenameModifiedEventStillSchedulesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated))) = action else {
                return false
            }
            return true
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        let coalescedFlags = UInt32(kFSEventStreamEventFlagItemRenamed)
            | UInt32(kFSEventStreamEventFlagItemModified)
        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([newPath], flags: coalescedFlags),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(newPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(newPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "결합 이벤트의 독립 수정은 계층 무효화를 예약해야 한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "결합 이벤트는 root reload를 예약해야 한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "결합 이벤트는 전이를 소비하지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: rename+xattr 결합 이벤트도 순수 rename echo로 보지 않는다.
    /// Helper gateway가 rename 직후 xattr·권한·Finder 정보 변경을 같은 경로 플래그에 OR 병합하면
    /// ItemRenamed 외의 의미 있는 비트만으로 독립 변경을 인식해야 메타데이터 유실이 없다.
    /// - 검증 내용: ItemRenamed|ItemXattrMod 결합 이벤트가 계층 무효화와 reload를 예약하는지 검증
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중
    /// - 기대 결과: hierarchyInvalidated 1회와 loadItems forwarding이 발생하고 전이는 소비되지 않는다
    func testCorrelatedCoalescedRenameXattrEventStillSchedulesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated))) = action else {
                return false
            }
            return true
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        let coalescedFlags = UInt32(kFSEventStreamEventFlagItemRenamed)
            | UInt32(kFSEventStreamEventFlagItemXattrMod)
        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([newPath], flags: coalescedFlags),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(newPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(newPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "결합 이벤트의 독립 변경은 계층 무효화를 예약해야 한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "결합 이벤트는 root reload를 예약해야 한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "결합 이벤트는 전이를 소비하지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: rename+create 결합 이벤트도 순수 rename echo로 보지 않는다.
    /// - 검증 내용: ItemRenamed|ItemCreated 결합 이벤트가 계층 무효화와 reload를 예약하는지 검증
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중
    /// - 기대 결과: hierarchyInvalidated 1회와 loadItems forwarding이 발생하고 전이는 소비되지 않는다
    func testCorrelatedCoalescedRenameCreatedEventStillSchedulesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated))) = action else {
                return false
            }
            return true
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        let coalescedFlags = UInt32(kFSEventStreamEventFlagItemRenamed)
            | UInt32(kFSEventStreamEventFlagItemCreated)
        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([newPath], flags: coalescedFlags),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(newPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(newPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "rename+create 결합 이벤트의 독립 생성은 계층 무효화를 예약해야 한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "rename+create 결합 이벤트는 root reload를 예약해야 한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "결합 이벤트는 전이를 소비하지 않는다")
    }

    /// EVM-001-command_external_refresh_correlation: 사용자가 before 선택을 포기하면 전이를 소비한다.
    /// 소유자 세대가 일치하는 batch에서 before 선택이 없으면 migration 대상이 없으므로
    /// 전이를 남겨두면 같은 경로의 실제 rename echo가 병합돼 목록 갱신이 누락된다.
    /// - 검증 내용: before 미선택 상태의 owning batch가 전이를 소비하고 사용자 선택을 유지하는지 검증
    /// - 사전 조건: 대기 전이와 무관한 행 선택
    /// - 기대 결과: 전이 nil, selectedIds는 사용자 선택 유지
    func testAbandonedBeforeSelectionConsumesPendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath(newPath),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
        )
        initialState.content.entryViewLayout.selectedIds = [otherPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [
                makeCorrelationEntry(id: newPath, name: "new.txt"),
            ],
        ))))
        XCTAssertNil(
            store.state.content.pendingIdentityTransition,
            "사용자가 before 선택을 포기했다면 owning batch에서 전이를 소비한다",
        )
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [otherPath],
            "사용자 선택은 대체 batch에 의해 되돌려지지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 상관 배치의 추가 경로는 같은 refresh 창에서 계속 전달된다.
    /// 전이와 겹치는 경로와 무관한 경로가 한 배치에 섞이면 무관한 경로만 기존 라우트 동작으로
    /// refresh를 예약하고 겹치는 경로는 명령 refresh에 병합되는지 검증한다.
    /// - 검증 내용: 혼합 배치 처리 후 마지막 무효화가 [other, root]만 포함하고 reload는 1회
    /// - 사전 조건: 대기 전이가 있고 외부 배치가 renamed old.txt와 modified other.txt를 함께 담음
    /// - 기대 결과: 계층 무효화 총 2회, root reload 1회, 무관한 경로의 이벤트는 폐기되지 않음
    func testCorrelatedExternalBatchKeepsUnrelatedPathRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        let mixedEvents = [
            FileChangeGatewayEvent(
                path: oldPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: newPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: otherPath,
                flags: UInt32(kFSEventStreamEventFlagItemModified),
                emittedAt: .distantPast,
            ),
        ]
        await store.send(.content(.externalFileSystemChanged(mixedEvents, deliveryChainToken: nil)))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(otherPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "무관한 경로의 refresh는 유지된다",
        )
        XCTAssertEqual(
            store.state.hierarchyInvalidations.last,
            [Self.canonicalPath(otherPath), Self.canonicalPath(folderPath)],
            "병합된 refresh에는 무관한 경로와 그 parent만 남는다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "무관한 경로의 root reload는 한 번 예약된다",
        )
    }

    // EVM-001-command_external_refresh_correlation: 일치 외부 이벤트는 전이를 소비하지 않고 중복 refresh를 억제한다.
    // 명령 완료가 예약한 reload 이후에 도달한 일치 이벤트는 그 refresh로 병합되어
    // selection migration을 위한 전이가 보존되는지 검증한다.
    // - 검증 내용: 일치 이벤트 뒤 pendingIdentityTransition 유지 + root reload 미예약
    // - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 기록과 그 reload 실행
    // - 기대 결과: 일치 이벤트는 전이를 보존하고 중복 refresh를 예약하지 않는다
    func testCorrelatedExternalEventRetainsPendingTransitionAndSuppressesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.recordID, record.id)
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.beforePath, Self.canonicalPath(oldPath))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.afterPath, Self.canonicalPath(newPath))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.rootPath, Self.canonicalPath(folderPath))

        let matchingEvents = Self.externalChangeEvents(
            [oldPath, newPath],
            flags: UInt32(kFSEventStreamEventFlagItemRenamed),
        )
        await store.send(.content(.externalFileSystemChanged(matchingEvents, deliveryChainToken: nil)))

        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "일치 이벤트는 전이를 소비하지 않고 보존한다",
        )
        XCTAssertNotNil(
            store.state.content.pendingExternalRefresh,
            "원인을 증명할 수 없는 rename pair는 trailing refresh scope로 보존한다",
        )
        XCTAssertEqual(
            store.state.content.pendingExternalRefresh?.removedPrefixes,
            [Self.canonicalPath(oldPath)],
            "after identity는 최종 reload 전까지 제거 힌트에서 제외한다",
        )
        XCTAssertEqual(store.state.hierarchyInvalidations.count, 1, "일치 이벤트는 계층 무효화를 추가하지 않는다")
        XCTAssertEqual(store.state.rootReloadCount, 1, "명령 완료가 예약한 reload만 남는다")

        // after-path projection이 도착하면 선택을 옮기고 전이를 소비한다.
        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [renamedEntry],
        ))))
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, [newPath])
        XCTAssertNil(store.state.content.pendingIdentityTransition, "after-path projection이 전이를 소비한다")
    }

    /// EVM-001-reload_directory_page_on_external_change: 억제된 외부 rename도 transition 종료 뒤 trailing refresh로 수렴한다.
    /// command echo와 구분할 correlation 정보가 없는 동안 외부 scope를 저장했다가, identity transition이 종료되면
    /// 동일 root의 hierarchy와 entries를 한 번 다시 읽어 최신 filesystem 상태를 반영해야 한다.
    /// - 검증 내용: pending external scope를 비우고 hierarchy invalidation 및 root load action을 순서대로 발행한다.
    /// - 사전 조건: current folder에 외부 rename scope가 보류된 상태.
    /// - 기대 결과: flush 후 pending scope가 없고, 기존 external refresh 경로가 재사용된다.
    func testSuppressedExternalRenameFlushesTrailingRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath(folderPath)
        initialState.navigation.navigationState = .folder(folderPath)
        initialState.pendingExternalRefresh = .init(
            rootPath: folderPath,
            affectedPaths: ["\(folderPath)/new.txt", folderPath],
            removedPrefixes: ["\(folderPath)/old.txt"],
            requiresCoarseHierarchyReload: false,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.internal(.flushPendingExternalRefresh))
        XCTAssertNil(store.state.pendingExternalRefresh)
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == ["\(folderPath)/new.txt", folderPath]
                && removedPrefixes == ["\(folderPath)/old.txt"]
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, _, _)))) = action else {
                return false
            }
            return path == folderPath
        }
    }

    /// EVM-001-command_external_refresh_correlation: 단독 순수 rename은 command echo로 확정하지 않는다.
    /// command 전이와 경로가 겹쳐도 동일 delivery에 before·after 쌍이 없으면 외부 변경으로 reload해야 하는지 검증한다.
    /// - 검증 내용: 단일 ItemRenamed event가 기존 hierarchy invalidation과 root reload를 예약한다.
    /// - 사전 조건: old→new rename 전이와 command reload가 이미 대기 중이고 new path 단독 rename event가 도착한다.
    /// - 기대 결과: 단독 event는 suppress되지 않고 refresh를 예약하며 pending transition은 보존된다.
    func testSingleExternalRenameOverlappingTransitionStillSchedulesRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([newPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(newPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(newPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(store.state.hierarchyInvalidations.count, baselineInvalidations + 1)
        XCTAssertEqual(store.state.rootReloadCount, baselineReloads + 1)
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: coarse 외부 이벤트는 대기 전이와 겹쳐도 억제하지 않는다.
    /// 유실 복구 플래그가 붙은 event가 command refresh 병합으로 사라지지 않는지 검증한다.
    /// - 검증 내용: MustScanSubDirs/UserDropped/KernelDropped 각각 coarse hierarchy invalidation과 root reload를 생성
    /// - 사전 조건: 현재 root에서 old→new rename 전이가 같은 generation으로 대기 중이다.
    /// - 기대 결과: coarse event는 전이를 보존하면서 coarseHierarchyInvalidated와 loadItems를 실행한다.
    func testCorrelatedCoarseExternalEventsStillReloadCachedHierarchy() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let coarseFlags = [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
        ].map(UInt32.init)
        let eventPaths = [folderPath, URL(fileURLWithPath: folderPath).deletingLastPathComponent().path]

        for (eventPath, flags) in eventPaths.flatMap({ path in coarseFlags.map { (path, $0) } }) {
            var initialState = makeCorrelationState(folderPath: folderPath)
            initialState.content.pendingIdentityTransition = .init(
                recordID: UUID(),
                beforePath: Self.canonicalPath(oldPath),
                afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
                rootPath: Self.canonicalPath(folderPath),
                refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
            )
            let store = TestStore(initialState: initialState) {
                CommandExternalRefreshHarness()
            }
            store.exhaustivity = .off

            await store.send(.content(.externalFileSystemChanged(
                Self.externalChangeEvents([eventPath], flags: flags),
                deliveryChainToken: nil,
            )))
            await store.receive { action in
                guard case let .content(.entryViewLayout(.hierarchy(.coarseHierarchyInvalidated(
                    removedPrefixes: removedPrefixes,
                    _,
                )))) =
                    action
                else { return false }
                return removedPrefixes.isEmpty
            }
            await store.receive { action in
                guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                    return false
                }
                return true
            }

            XCTAssertNotNil(store.state.content.pendingIdentityTransition)
        }
    }

    /// EVM-001-command_external_refresh_correlation: 명령 → 일치 이벤트 → 무관/빈 첫 배치 → after-path 배치가
    /// 하나의 correlated refresh로 수렴하고, after-path가 나타날 때까지 선택을 유지한 뒤
    /// 정확히 한 번 migration하고 전이를 소비한다.
    /// - 검증 내용: 일치 이벤트 후 refresh 미예약, 무관 첫 배치에서 선택·전이 보존, after-path 배치에서 1회 migration
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 + reload 실행 + 일치 이벤트
    /// - 기대 결과: reload 총 1회, after-path 도착 전 선택 유지, 도착 후 selectedIds == [newPath] + 전이 nil
    func testCommandMatchingEventEarlyBatchThenAfterPathMigratesOnce() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.lastSelectedId = oldPath
        initialState.content.entryViewLayout.rangeAnchorId = oldPath
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        // 일치 외부 이벤트: 명령 refresh로 병합되어 중복 refresh를 예약하지 않고 전이를 보존한다.
        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents(
                [oldPath, newPath],
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
            ),
            deliveryChainToken: nil,
        )))
        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations,
            "일치 이벤트는 refresh를 예약하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, baselineReloads, "명령 완료가 예약한 reload만 남는다")
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        // 무관한 첫 projection batch: after-path가 없으므로 선택과 전이를 유지한다.
        let unrelatedEntry = makeCorrelationEntry(id: unrelatedPath, name: "unrelated.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [unrelatedEntry],
        ))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [oldPath],
            "after-path가 도착하기 전까지 선택을 유지한다",
        )
        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "무관 첫 배치는 전이를 소비하지 않는다")

        // after-path projection batch: 선택을 정확히 한 번 옮기고 전이를 소비한다.
        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [unrelatedEntry, renamedEntry],
        ))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "선택은 after-path로 정확히 한 번 옮긴다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition, "전이는 소비된다")
        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations,
            "correlated refresh는 명령 완료의 하나만 존재한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 무관한 외부 이벤트는 대기 전이를 유지한다.
    /// 전이와 겹치지 않는 경로의 이벤트가 기존 refresh를 예약하면서도 전이를 소비하지 않는지 검증한다.
    /// - 검증 내용: 무관한 경로 이벤트 처리 후에도 pendingIdentityTransition이 남아 있음
    /// - 사전 조건: rename 완료 기록으로 생성된 대기 전이와 무관한 경로의 modified 이벤트
    /// - 기대 결과: 정상 refresh와 함께 전이 보존
    func testUnrelatedExternalEventDoesNotConsumePendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath]))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(unrelatedPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertNotNil(store.state.content.pendingIdentityTransition, "무관한 이벤트는 전이를 소비하지 않는다")
        XCTAssertEqual(store.state.hierarchyInvalidations.count, 2)
        XCTAssertEqual(store.state.rootReloadCount, 2)
    }

    /// EVM-001-command_external_refresh_correlation: 무관 이벤트가 예약한 reload 뒤의 batch에서도 선택 migration이 산다.
    /// 예약된 root reload가 세대를 하나 올리므로 전이 root 소유자가 재기준화되지 않으면
    /// 후속 batch에서 세대 불일치로 전이가 만료되고 기존 선택이 해제된다.
    /// - 검증 내용: 무관 modified 이벤트 reload 후 after-path batch가 선택을 옮기는지 검증
    /// - 사전 조건: rename 완료 대기 전이와 무관 경로의 modified 이벤트
    /// - 기대 결과: 후속 itemsLoaded에서 selectedIds가 after-path로 이동하고 전이 소비
    func testUnrelatedEventReloadKeepsMigrationAliveThroughNextBatch() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))

        await store.send(.content(.externalFileSystemChanged(Self.externalChangeEvents(
            [unrelatedPath],
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        ))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(unrelatedPath), Self.canonicalPath(folderPath)]
                && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [renamedEntry],
        ))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "reload이 올린 새 세대에서도 after-path 선택 migration이 유지된다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: 실패한 명령도 대기 전이를 만료시키지 않는다.
    /// operationFinished는 record identity가 없어 이 실패가 전이의 원인 명령인지 확정할 수 없다.
    /// 경로·종류를 추측해 만료하면 무관한 실패가 성공한 전이를 파괴하므로, 같은 경로·종류의
    /// 실패라도 전이를 유지한다.
    /// - 검증 내용: rename 실패 수신 뒤에도 pendingIdentityTransition 유지 + reload 미발행
    /// - 사전 조건: rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 실패 시점에 전이가 유지되고 reload가 예약되지 않는다
    func testFailedOperationKeepsPendingTransitionWithoutReload() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: "\(folderPath)/new.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .failure(.system(message: "forced failure")),
        ))))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "실패는 record identity가 없어 전이를 만료시키지 않는다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            1,
            "record가 온 뒤 한 번의 reload만 있고 실패 이벤트는 reload를 추가하지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 부분 변경 operation reload 전 pending owner를 재기준화한다.
    /// 대기 중인 rename 전이가 있을 때 extract의 부분 실패 reload가 새 root 세대에서도 selection migration을 유지하는지 검증한다.
    /// - 검증 내용: operationFinished reload 직전 root projection owner를 다음 세대로 올리고 after 선택을 적용한다.
    /// - 사전 조건: root 세대 1의 before 선택과 pending identity transition, extract system 실패가 있다.
    /// - 기대 결과: reload는 세대 2를 사용하고 after 경로 선택과 transition 소비가 완료된다.
    @MainActor
    func testOperationFailureRebasesPendingIdentityTransitionBeforeReload() {
        let folderPath = "/tmp/voyager-operation-rebase"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var state = makeCorrelationState(folderPath: folderPath).content
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.selectedIds = [oldPath]
        state.entryViewLayout.lastSelectedId = oldPath
        state.entryViewLayout.rangeAnchorId = oldPath
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            afterLexicalPath: newPath,
            beforeLexicalPath: oldPath,
        )
        _ = FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            .lifecycle(.operationFinished(
                "\(folderPath)/archive.zip",
                .extract,
                .failure(.system(message: "partial extract failure")),
            )),
            state: &state,
        )
        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .root(generation: 2),
        )

        state.entryViewLayout.entryOperations.loadingContext.generation = 2
        _ = FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            .loading(.itemsLoaded(
                generation: state.entryViewLayout.entryOperations.loadingContext.generation,
                items: [
                    makeCorrelationEntry(id: newPath, name: "new.txt"),
                ],
            )),
            state: &state,
        )
        XCTAssertEqual(state.entryViewLayout.selectedIds, [newPath])
        XCTAssertEqual(state.entryViewLayout.lastSelectedId, newPath)
        XCTAssertEqual(state.entryViewLayout.rangeAnchorId, newPath)
        XCTAssertNil(state.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: drop 부분 실패 reload 전 pending owner를 재기준화한다.
    /// 대기 중인 rename 전이가 있을 때 drop copy의 선삭제 후 실패 reload가 selection migration을 보존하는지 검증한다.
    /// - 검증 내용: dropOperationFinished reload 직전 root projection owner를 다음 세대로 올리고 after 선택을 적용한다.
    /// - 사전 조건: root 세대 1의 before 선택과 pending identity transition, pasteFileCopy system 실패가 있다.
    /// - 기대 결과: reload는 세대 2를 사용하고 after 경로 선택과 transition 소비가 완료된다.
    @MainActor
    func testDropFailureRebasesPendingIdentityTransitionBeforeReload() {
        let folderPath = "/tmp/voyager-drop-rebase"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var state = makeCorrelationState(folderPath: folderPath).content
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.selectedIds = [oldPath]
        state.entryViewLayout.lastSelectedId = oldPath
        state.entryViewLayout.rangeAnchorId = oldPath
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: 1,
            projectionOwner: .root(generation: 1),
            afterLexicalPath: newPath,
            beforeLexicalPath: oldPath,
        )
        _ = FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            .lifecycle(.dropOperationFinished(
                "\(folderPath)/source.txt",
                .pasteFileCopy,
                .failure(.system(message: "post-delete copy failure")),
            )),
            state: &state,
        )
        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .root(generation: 2),
        )

        state.entryViewLayout.entryOperations.loadingContext.generation = 2
        _ = FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            .loading(.itemsLoaded(
                generation: state.entryViewLayout.entryOperations.loadingContext.generation,
                items: [
                    makeCorrelationEntry(id: newPath, name: "new.txt"),
                ],
            )),
            state: &state,
        )
        XCTAssertEqual(state.entryViewLayout.selectedIds, [newPath])
        XCTAssertEqual(state.entryViewLayout.lastSelectedId, newPath)
        XCTAssertEqual(state.entryViewLayout.rangeAnchorId, newPath)
        XCTAssertNil(state.pendingIdentityTransition)
    }

    /// EVM-001-command_external_refresh_correlation: 취소된 rename은 완료된 대기 전이를 만료하지 않는다.
    /// cancelRename은 이미 성공해 기록된 identity 연산과 무관한 편집 취소이므로
    /// 대기 전이를 파괴하지 않는지 검증한다.
    /// - 검증 내용: cancelRename 수신 뒤에도 pendingIdentityTransition 유지
    /// - 사전 조건: rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 취소 시점에 전이가 유지됨
    func testCanceledRenameKeepsUnrelatedPendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: "\(folderPath)/new.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        await store.send(.bridge(.edit(.cancelRename)))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "cancelRename은 완료된 identity 연산과 무관해 전이를 유지한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: itemsLoaded 시점에 경로 전이가 선택을 이후 경로로 옮기고 소비한다.
    /// rename/move 최종 데이터 도착 시 선택이 새 identity로 이어지는지 검증한다.
    /// - 검증 내용: 이전 경로가 선택된 상태에서 이후 경로가 포함된 itemsLoaded가 선택을 교체하고 전이를 소비한다.
    /// - 사전 조건: before→after 대기 전이와 before가 선택된 상태.
    /// - 기대 결과: selectedIds는 after만 포함하고 pendingIdentityTransition은 nil이다.
    func testItemsLoadedMigratesSelectionAlongIdentityTransitionAndConsumesIt() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.lastSelectedId = oldPath
        initialState.content.entryViewLayout.rangeAnchorId = oldPath
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: folderPath,
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        let otherEntry = makeCorrelationEntry(id: "\(folderPath)/other.txt", name: "other.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [renamedEntry, otherEntry],
        ))))

        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "선택은 이후 경로로 이동한다",
        )
        XCTAssertEqual(store.state.content.entryViewLayout.lastSelectedId, newPath)
        XCTAssertNil(store.state.content.pendingIdentityTransition, "전이는 소비된다")
    }

    /// EVM-001-command_external_refresh_correlation: 이후 경로가 아직 도착하지 않으면 선택을 유지하고 전이를 보존한다.
    /// 실패·미도착 시 기존 stale-selection 정리가 이기는지 검증한다.
    /// - 검증 내용: after-path가 없는 itemsLoaded는 선택과 전이를 그대로 둔다.
    /// - 사전 조건: 대기 전이와 before 선택.
    /// - 기대 결과: selectedIds는 before 유지, 전이 미소비.
    func testItemsLoadedWithoutAfterPathKeepsSelectionAndTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let transition = FileManagerContentState.EntryIdentityTransition(
            recordID: UUID(),
            beforePath: oldPath,
            afterPath: newPath,
            rootPath: folderPath,
            refreshGeneration: initialState.content.entryViewLayout.entryOperations.loadingContext.generation,
        )
        initialState.content.pendingIdentityTransition = transition
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let otherEntry = makeCorrelationEntry(id: "\(folderPath)/other.txt", name: "other.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [otherEntry],
        ))))

        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, [oldPath])
        XCTAssertEqual(store.state.content.pendingIdentityTransition, transition)
    }

    /// EVM-001-command_external_refresh_correlation: 새 성공 기록은 대기 전이를 대체(supersede)한다.
    /// 두 번째 rename 완료 기록이 첫 번째 전이를 교체하는지 검증한다.
    /// - 검증 내용: 두 기록 전송 뒤 pendingIdentityTransition.recordID == 두 번째 기록 id
    /// - 사전 조건: 서로 다른 원본을 순차 rename한 두 완료 기록
    /// - 기대 결과: 슬롯은 하나이며 최신 기록으로 대체됨
    func testSupersedingRecordReplacesPendingTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let firstOldPath = "\(folderPath)/first-old.txt"
        let secondOldPath = "\(folderPath)/second-old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [firstOldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let firstRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: firstOldPath, afterPath: "\(folderPath)/first-new.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(firstRecord))))
        XCTAssertEqual(store.state.content.pendingIdentityTransition?.recordID, firstRecord.id)

        await store.send(.select(secondOldPath)) {
            $0.content.entryViewLayout.selectedIds = [secondOldPath]
        }
        let secondRecord = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: secondOldPath, afterPath: "\(folderPath)/moved/second-old.txt")],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(secondRecord))))
        XCTAssertEqual(
            store.state.content.pendingIdentityTransition?.recordID,
            secondRecord.id,
            "새 성공 기록이 이전 전이를 대체한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 세대가 어긋난 전이는 만료되고 정상 refresh로 처리한다.
    /// 로딩 세대 불일치 시 겹치는 이벤트라도 중복 억제하지 않는지 검증한다.
    /// - 검증 내용: stale 세대 전이 상태에서 일치 모양 이벤트가 무효화+reload를 예약하고 전이를 만료
    /// - 사전 조건: refreshGeneration이 현재 로딩 세대보다 오래된 대기 전이
    /// - 기대 결과: 기존 라우트 동작 그대로 처리, 전이 소비
    func testGenerationSupersededTransitionExpiresWithNormalRefresh() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.entryOperations.loadingContext.generation = 7
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath("\(folderPath)/new.txt"),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: 5,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        await store.send(.content(.externalFileSystemChanged(
            Self.externalChangeEvents([oldPath], flags: UInt32(kFSEventStreamEventFlagItemRenamed)),
            deliveryChainToken: nil,
        )))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [Self.canonicalPath(oldPath), Self.canonicalPath(folderPath)]
                && removedPrefixes == [Self.canonicalPath(oldPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertNil(store.state.content.pendingIdentityTransition, "세대 불일치 전이는 만료된다")
        XCTAssertEqual(store.state.hierarchyInvalidations.count, 1, "stale 전이는 중복 억제하지 않는다")
        XCTAssertEqual(store.state.rootReloadCount, 1)
    }

    /// EVM-001-command_external_refresh_correlation: 상관 증거가 없는 root 경로 rename은 외부 refresh로 통과한다.
    /// FSEvents가 변경 파일 대신 폴더 경로를 보고해도 단독 순수 rename을 command echo로 확정하지 않는지 검증한다.
    /// - 검증 내용: root 경로 rename과 무관 경로가 모두 계층 무효화·reload에 반영된다.
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 전이와 그 reload 실행
    /// - 기대 결과: 증명되지 않은 root rename과 무관 경로의 refresh가 예약되고 전이는 유지된다.
    func testCorrelatedParentRootEventMergesWithoutHidingUnrelatedPaths() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "\(folderPath)/unrelated.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        // 프로덕션 순서: operationFinished가 먼저 reload를 예약·실행해 세대를 연다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            oldPath,
            .rename,
            .success(()),
        ))))
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        // 혼합 배치: 현재 root 경로 이벤트(renamed) + 무관한 sibling 이벤트(modified).
        let mixedEvents = [
            FileChangeGatewayEvent(
                path: folderPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: unrelatedPath,
                flags: UInt32(kFSEventStreamEventFlagItemModified),
                emittedAt: .distantPast,
            ),
        ]
        await store.send(.content(.externalFileSystemChanged(mixedEvents, deliveryChainToken: nil)))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [
                Self.canonicalPath(folderPath),
                Self.canonicalPath(unrelatedPath),
                Self.canonicalPath(URL(fileURLWithPath: folderPath).deletingLastPathComponent().path),
            ] && removedPrefixes == [Self.canonicalPath(folderPath)]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "상관 증거가 없는 root rename과 무관 경로가 모두 계층 무효화를 예약한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "상관 증거가 없는 root rename도 외부 reload를 예약한다",
        )
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "root 경로 외부 refresh 뒤 전이는 보존된다",
        )
        // 참고: 무관 경로 remainder가 예약한 reload는 세대를 연다. 그 세대 불일치로 전이가
        // 만료되는 것은 의도된 V20-P1-2 동작이며 testGenerationMismatchExpiresTransitionAtMigration에서
        // 별도로 검증한다.
    }

    /// EVM-001-command_external_refresh_correlation: 무관한 명령 실패·취소는 대기 전이를 파괴하지 않는다.
    /// 성공한 rename 전이가 있을 때 다른 경로·종류의 operationFinished 실패와 cancelRename이
    /// 전이를 유지하는지 검증한다.
    /// - 검증 내용: 무관 실패·취소 뒤에도 pendingIdentityTransition 유지
    /// - 사전 조건: 선택된 old.txt의 rename 완료 기록으로 생성된 대기 전이
    /// - 기대 결과: 전이는 유지되어 이후 동일 세대 projection에서 동작할 수 있다
    func testUnrelatedFailureAndCancelKeepPendingIdentityTransition() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        // 무관한 경로·종류의 압축 실패: 전이와 무관하므로 만료하지 않고 reload도 예약하지 않는다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            otherPath,
            .compress,
            .failure(.system(message: "forced failure")),
        ))))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "무관한 종류·경로의 실패는 전이를 만료하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 1, "무관한 실패는 reload를 추가하지 않는다")

        // 같은 rename 종류라도 다른 경로의 실패는 전이와 무관하다.
        await store.send(.bridge(.lifecycle(.operationFinished(
            otherPath,
            .rename,
            .failure(.system(message: "forced failure")),
        ))))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "다른 경로의 rename 실패는 전이를 만료하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 1, "무관한 rename 실패는 reload를 추가하지 않는다")

        // rename 편집 취소도 완료된 identity 연산과 무관하므로 전이를 유지한다.
        await store.send(.bridge(.edit(.cancelRename)))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "cancelRename은 완료된 전이를 만료하지 않는다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 세대가 어긋난 전이는 migration 시점에 만료된다.
    /// 같은 root라도 로딩 세대가 전이 생성 세대와 다르면 선택을 옮기지 않고 만료하는지 검증한다.
    /// - 검증 내용: after-path가 포함된 itemsLoaded에도 selectedIds 유지 + pendingIdentityTransition == nil
    /// - 사전 조건: refreshGeneration 3, 현재 loadingContext.generation 7인 대기 전이와 before 선택
    /// - 기대 결과: migration 미발생(선택 유지), 세대 불일치 전이 만료
    func testGenerationMismatchExpiresTransitionAtMigration() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.entryOperations.loadingContext.generation = 7
        initialState.content.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: Self.canonicalPath(oldPath),
            afterPath: Self.canonicalPath(newPath),
            rootPath: Self.canonicalPath(folderPath),
            refreshGeneration: 3,
        )
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [renamedEntry],
        ))))

        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [oldPath],
            "세대가 어긋난 전이는 선택을 옮기지 않는다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition, "세대 불일치 전이는 만료된다")
    }

    /// EVM-001-command_external_refresh_correlation: expanded child 전이는 root 완료보다 owning folder 응답을 기다린다.
    /// root coreFinished가 먼저 투영되어도 child rename 선택과 전이가 조기 소비되지 않는지 검증한다.
    /// - 검증 내용: root 완료 projection 뒤 before 선택·전이 유지, matching folder batch 뒤 after로 1회 migration
    /// - 사전 조건: generation 1의 expanded folder child가 선택되고 root generation 7에서 rename 완료 전이가 기록된다.
    /// - 기대 결과: root 완료는 child 전이를 generation 3으로 넘기고 해당 folder 응답만 선택을 옮기고 소비한다.
    func testExpandedChildTransitionWaitsForOwningFolderResponseAfterRootCompletion() async {
        let fixture = makeExpandedChildTransitionFixture()
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 7,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.receive { action in
            guard case .entryViewLayout(.view(.applyContentProjection)) = action else { return false }
            return true
        }
        await store.receive(\.entryViewLayout.hierarchy.rootSnapshotCompleted)

        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.folder.id, generation: 3),
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])

        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.expandRequested(id))) = action else { return false }
            return id == fixture.folder.id
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadFolderItems(request)))) = action
            else { return false }
            return request.id.folderID == fixture.folder.id && request.folderGeneration == 3
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.folderStreamFinished(request)))) = action
            else { return false }
            return request.id.folderID == fixture.folder.id && request.folderGeneration == 3
        }
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))

        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition, "after projection 뒤 folder terminal까지 전이를 유지한다")

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertNil(store.state.pendingIdentityTransition, "owning folder terminal이 전이를 소비한다")
    }

    /// EVM-001-reload_directory_page_on_external_change: content-tab transfer의 folder restart가 pending owner를 재기준화한다.
    /// transfer가 unfinished expanded folder의 generation을 올릴 때 identity transition도 같은 경계에서 다음 generation을 소유해야 한다.
    /// - 검증 내용: restart 전후 folder node와 transition projection owner generation의 일치.
    /// - 사전 조건: generation 2 folder owner를 가진 expanded child identity transition.
    /// - 기대 결과: restart 후 node와 transition owner가 모두 generation 3이 된다.
    func testIdentityTransitionRebasesBeforeUnfinishedFolderRestart() {
        let fixture = makeExpandedChildTransitionFixture()
        var state = fixture.state
        let feature = FileManagerContentFeature()

        _ = feature.reduce(
            into: &state,
            action: .entryViewLayout(.hierarchy(.restartUnfinishedExpandedFolderLoads)),
        )

        XCTAssertEqual(
            state.entryViewLayout.hierarchy.nodesByID[fixture.folder.id]?.generation,
            3,
        )
        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.folder.id, generation: 3),
        )
    }

    /// EVM-001-command_external_refresh_correlation: owning folder 중간 batch가 before 선택을 보존한다.
    /// - 검증 내용: after-path 없는 batch 0 뒤 선택·전이 유지, batch 1에서 after로 단 한 번 migration
    /// - 사전 조건: expanded folder generation 2가 rename 전이를 소유하고 두 core batch를 순차 수신한다.
    /// - 기대 결과: stale generation은 무시되고 terminal 뒤에도 after 선택과 소비된 전이가 유지된다.
    func testExpandedChildTransitionSurvivesIntermediateOwningFolderBatch() async {
        let fixture = makeExpandedChildTransitionFixture()
        let unrelated = makeCorrelationEntry(id: "\(fixture.folder.id)/unrelated.txt", name: "unrelated.txt")
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 1,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreBatch(items: [unrelated], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition, "중간 owning batch는 전이를 소비하지 않는다")

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreBatch(items: [fixture.after], batchIndex: 1)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition, "after projection 뒤 terminal까지 전이를 유지한다")

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreFinished(batchCount: 2)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition, "folder terminal은 소비된 전이를 되살리지 않는다")
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[fixture.folder.id]?.folder.children.map(\.id),
            [unrelated.id, fixture.after.id],
            "after-path migration 전 staged batch까지 최종 folder snapshot에 유지한다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 거부된 folder terminal은 전이와 staged batch를 보존한다.
    /// - 검증 내용: cursor보다 작은 batchCount terminal 뒤 전이 유지, 후속 batch와 정상 terminal에서 전체 snapshot commit
    /// - 사전 조건: expanded folder replacement가 batch 0을 staged하고 expectedBatchIndex가 1이다.
    /// - 기대 결과: 잘못된 terminal은 no-op이며 정상 완료 뒤 batch 0과 after-path batch 1이 모두 남는다.
    func testExpandedChildTransitionRejectsMismatchedTerminalWithoutDiscardingStagedBatch() async {
        let fixture = makeExpandedChildTransitionFixture()
        let unrelated = makeCorrelationEntry(id: "\(fixture.folder.id)/unrelated.txt", name: "unrelated.txt")
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreBatch(items: [unrelated], batchIndex: 0)),
        ))))
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreFinished(batchCount: 0)),
        ))))

        XCTAssertNotNil(store.state.pendingIdentityTransition, "거부된 terminal은 전이를 소비하지 않는다")

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreBatch(items: [fixture.after], batchIndex: 1)),
        ))))
        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: store.state.entryViewLayout.hierarchy.rootContextGeneration,
            folderID: fixture.folder.id,
            folderGeneration: 2,
            .event(.coreFinished(batchCount: 2)),
        ))))

        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[fixture.folder.id]?.folder.children.map(\.id),
            [unrelated.id, fixture.after.id],
        )
    }

    /// EVM-001-command_external_refresh_correlation: 교차 폴더 move는 소스 폴더 배치에서 before 선택을 보존한다.
    /// - 검증 내용: 소스 폴더 replacement batch가 before 선택을 지우기 전 보존, 목적지 batch에서 1회 migration,
    ///   이후 terminal·stale sibling 이벤트가 전이를 되살리지 않음
    /// - 사전 조건: 두 expanded folder가 rename 전이를 source(보존)·destination(migration) 소유로 나눠 갖는다.
    /// - 기대 결과: 소스 배치 뒤에도 선택·전이 유지, 목적지 배치 뒤 after 선택과 소비 확정
    func testCrossFolderMoveSurvivesSourceFolderBatchBeforeDestinationMigration() async {
        let fixture = makeCrossFolderMoveFixture()
        let kept = makeCorrelationEntry(id: "\(fixture.source.id)/kept.txt", name: "kept.txt")
        let store = TestStore(initialState: fixture.state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryOpenClient = .testValue
            $0.entryQuickLookClient = .previewValue
            // root 완료 재시작의 자동 폴더 재로드가 실제 파일시스템(픽스처 경로 미존재)을
            // 읽지 않게 한다. 실패 스트림은 dst terminal(.failed) 브리지로 이어져 소유자
            // 세대 종료로 전이를 조기 만료시킨다. 배치는 본문의 수동 주입으로만 공급한다.
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in AsyncThrowingStream { $0.finish() } }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off
        let rootContextGeneration = fixture.state.entryViewLayout.hierarchy.rootContextGeneration

        await store.send(.entryViewLayout(.hierarchy(.rootSnapshotCompleted(
            rootContextGeneration: rootContextGeneration,
            rootFolders: [fixture.source, fixture.destination],
        ))))
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.destination.id, generation: 3),
        )
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.preservationOwner,
            .folder(id: fixture.source.id, generation: 3),
        )
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.before.id])

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.source.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [kept], batchIndex: 0)),
        ))))
        XCTAssertEqual(
            store.state.entryViewLayout.selectedIds,
            [fixture.before.id],
            "소스 폴더 replacement batch는 before 선택을 보존해야 한다",
        )
        XCTAssertEqual(
            store.state.pendingIdentityTransition?.projectionOwner,
            .folder(id: fixture.destination.id, generation: 3),
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNotNil(
            store.state.pendingIdentityTransition,
            "destination after projection 뒤 source terminal까지 전이를 유지한다",
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.destination.id,
            folderGeneration: 3,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        // migration이 소스 staging을 커밋했으므로 소스 terminal은 정상 항목을 유지한다.
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[fixture.source.id]?.folder.children,
            [kept],
            "migration 시점에 소스 staging이 커밋되어 terminal 이후에도 유지된다",
        )
        XCTAssertEqual(
            store.state.entryViewLayout.hierarchy.nodesByID[fixture.source.id]?.folder.hasAppliedContentBatch,
            true,
        )

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.destination.id,
            folderGeneration: 3,
            .event(.coreFinished(batchCount: 1)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
            rootContextGeneration: rootContextGeneration,
            folderID: fixture.source.id,
            folderGeneration: 5,
            .event(.coreBatch(items: [fixture.after], batchIndex: 0)),
        ))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [fixture.after.id])
        XCTAssertNil(store.state.pendingIdentityTransition, "stale sibling은 전이를 되살리거나 다시 소비하지 않는다")
    }

    /// EVM-001-reload_directory_page_on_external_change: symlink 이동의 projection owner는 lexical 부모로 판정한다.
    /// 완료 시점 afterPath는 존재하는 symlink라 canonical 해석 시 root 밖으로 빠질 수 있으므로
    /// destination folder가 expanded 상태면 해당 폴더 소유자가 유지되어야 한다.
    /// - 검증 내용: replace 대상이 symlink인 pasteFileMove 기록의 owner가 dst folder로 계산되는지 검증
    /// - 사전 조건: src/dst 확장 폴더와 dst/moved.txt symlink(outside 지시) 실제 생성
    /// - 기대 결과: projectionOwner = .folder(dst), preservationOwner = .folder(src)
    func testSymlinkMoveKeepsFolderProjectionOwnerFromLexicalParent() throws {
        let base = NSTemporaryDirectory().appending("voyager-symlink-owner-\(UUID().uuidString)")
        let rootPath = base + "root"
        let srcPath = rootPath + "/src"
        let dstPath = rootPath + "/dst"
        let aliasPath = rootPath + "/alias"
        let outsidePath = base + "outside/target"
        let fm = FileManager.default
        try fm.createDirectory(atPath: srcPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: outsidePath, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: aliasPath, withDestinationPath: dstPath)
        try fm.createSymbolicLink(atPath: dstPath + "/moved.txt", withDestinationPath: outsidePath)
        defer { try? fm.removeItem(atPath: base) }

        let source = EntryModel.temporaryFolder(id: srcPath, name: "src")
        let destination = EntryModel.temporaryFolder(id: dstPath, name: "dst")
        let alias = EntryModel.temporaryFolder(id: aliasPath, name: "alias")
        let before = makeCorrelationEntry(id: "\(srcPath)/moved.txt", name: "moved.txt")
        let after = makeCorrelationEntry(id: "\(dstPath)/moved.txt", name: "moved.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.entries = [source, alias, destination]
        state.entryViewLayout.entryOperations.items = [source, alias, destination]
        state.entryViewLayout.entryOperations.loadingContext.items = [source, alias, destination]
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[source.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        // canonical-equivalent alias가 실제 lexical destination보다 먼저 삽입되어도
        // destination owner는 lexical 경계를 우선해야 한다.
        state.entryViewLayout.hierarchy.nodesByID[alias.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 9,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.nodesByID[destination.id] = .init(
            children: [],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 0,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([source.id, alias.id, destination.id])
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id

        let record = EntryActionRecord(
            operationKind: .pasteFileMove,
            targets: [.init(beforePath: before.id, afterPath: after.id)],
        )
        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(record, state: &state)

        XCTAssertEqual(
            state.pendingIdentityTransition?.projectionOwner,
            .folder(id: destination.id, generation: 2),
            "symlink after-path가 canonical 해석으로 벗어나도 lexical 부모의 folder 소유자를 유지한다",
        )
        XCTAssertEqual(
            state.pendingIdentityTransition?.preservationOwner,
            .folder(id: source.id, generation: 2),
        )
    }

    /// EVM-001-command_external_refresh_correlation: symlink source는 lexical root 범위에 포함된다.
    /// root 밖 target을 가리키는 root 내부 symlink의 child를 이동해도 source transition을 기록해야
    /// source hold와 before→after selection migration이 생략되지 않는다.
    /// - 검증 내용: canonical source가 root 밖이어도 lexical before path로 전이가 등록되는지 검증
    /// - 사전 조건: root 내부 alias folder가 root 밖 directory를 가리키고 alias child가 선택됨
    /// - 기대 결과: pending transition과 alias preservation owner가 생성됨
    func testSymlinkSourceWithinLexicalRootRecordsTransition() throws {
        let base = NSTemporaryDirectory().appending("voyager-symlink-source-\(UUID().uuidString)")
        let rootPath = base + "/root"
        let aliasPath = rootPath + "/alias"
        let outsidePath = base + "/outside"
        let beforePath = aliasPath + "/before.txt"
        let afterPath = rootPath + "/after.txt"
        let fm = FileManager.default
        try fm.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: outsidePath, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: aliasPath, withDestinationPath: outsidePath)
        defer { try? fm.removeItem(atPath: base) }

        let alias = EntryModel.temporaryFolder(id: aliasPath, name: "alias")
        let before = makeCorrelationEntry(id: beforePath, name: "before.txt")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.navigation.navigationState = .folder(rootPath)
        state.entryViewLayout.entries = [alias]
        state.entryViewLayout.entryOperations.items = [alias]
        state.entryViewLayout.hierarchy = .init(rootPath: rootPath)
        state.entryViewLayout.hierarchy.nodesByID[alias.id] = .init(
            children: [before],
            loadPhase: .loaded,
            generation: 1,
            coreFinished: true,
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([alias.id])
        state.entryViewLayout.selectedIds = [beforePath]

        _ = FileManagerContentIdentityTransitionCoordinator.recordIfEligible(
            .init(operationKind: .rename, targets: [.init(beforePath: beforePath, afterPath: afterPath)]),
            state: &state,
        )

        XCTAssertEqual(state.pendingIdentityTransition?.beforeLexicalPath, beforePath)
        XCTAssertEqual(
            state.pendingIdentityTransition?.preservationOwner,
            .folder(id: aliasPath, generation: 2),
        )
    }

    /// EVM-001-command_external_refresh_correlation: 상관 증거가 없는 조상 경로 rename은 외부 refresh로 통과한다.
    /// FSEvents가 변경 파일 대신 current root의 조상 경로를 보고해도 단독 순수 rename을 버리지 않는지 검증한다.
    /// - 검증 내용: 조상 경로 rename과 무관 경로가 모두 계층 무효화·reload에 반영된다.
    /// - 사전 조건: folder 라우트에서 선택된 old.txt의 rename 완료 대기 전이
    /// - 기대 결과: 증명되지 않은 조상 rename과 무관 경로의 refresh가 예약되고 전이는 유지된다.
    func testCorrelatedContainingParentEventMergesWithoutHidingUnrelatedPaths() async {
        let folderPath = "/tmp/voyager-correlation"
        let parentPath = "/tmp"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let unrelatedPath = "/tmp/voyager-other/unrelated.txt"
        let canonicalUnrelated = Self.canonicalPath(unrelatedPath)
        let unrelatedParent = URL(fileURLWithPath: canonicalUnrelated).deletingLastPathComponent().path
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [folderPath, folderPath] && removedPrefixes == [oldPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)
        let baselineInvalidations = store.state.hierarchyInvalidations.count
        let baselineReloads = store.state.rootReloadCount

        // 혼합 배치: root의 조상(포함 디렉터리) renamed 이벤트 + 무관한 sibling modified 이벤트.
        let mixedEvents = [
            FileChangeGatewayEvent(
                path: parentPath,
                flags: UInt32(kFSEventStreamEventFlagItemRenamed),
                emittedAt: .distantPast,
            ),
            FileChangeGatewayEvent(
                path: unrelatedPath,
                flags: UInt32(kFSEventStreamEventFlagItemModified),
                emittedAt: .distantPast,
            ),
        ]
        await store.send(.content(.externalFileSystemChanged(mixedEvents, deliveryChainToken: nil)))
        await store.receive { action in
            guard case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths,
                removedPrefixes,
            )))) = action else { return false }
            return affectedPaths == [parentPath, canonicalUnrelated, "/", unrelatedParent]
                && removedPrefixes == [parentPath]
        }
        await store.receive { action in
            guard case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))) = action else {
                return false
            }
            return true
        }

        XCTAssertEqual(
            store.state.hierarchyInvalidations.count,
            baselineInvalidations + 1,
            "상관 증거가 없는 조상 rename과 무관 경로가 모두 계층 무효화를 예약한다",
        )
        XCTAssertEqual(
            store.state.rootReloadCount,
            baselineReloads + 1,
            "상관 증거가 없는 조상 rename도 외부 reload를 예약한다",
        )
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "조상 경로 외부 refresh 뒤 전이는 보존된다",
        )
    }

    /// EVM-001-command_external_refresh_correlation: 성공한 rename 뒤 무관한 실패·취소가 와도
    /// 전이가 보존되고, 이후 같은 세대의 after-path projection에서 선택 migration이 완료된다.
    /// 무관 실패·취소가 직접(만료) 또는 간접(reload 세대 상승)으로 전이를 파괴하지 않는지 검증한다.
    /// - 검증 내용: 무관 실패·취소 뒤 전이 보존 + reload 미예약, after-path projection에서 1회 migration
    /// - 사전 조건: 선택된 old.txt의 rename 완료 전이와 동일 세대
    /// - 기대 결과: after-path 배치 도착 시 selectedIds == [newPath] + 전이 소비
    func testUnrelatedFailureAndCancelThenAfterPathMigratesOnce() async {
        let folderPath = "/tmp/voyager-correlation"
        let oldPath = "\(folderPath)/old.txt"
        let newPath = "\(folderPath)/new.txt"
        let otherPath = "\(folderPath)/other.txt"
        var initialState = makeCorrelationState(folderPath: folderPath)
        initialState.content.entryViewLayout.selectedIds = [oldPath]
        initialState.content.entryViewLayout.lastSelectedId = oldPath
        initialState.content.entryViewLayout.rangeAnchorId = oldPath
        let store = TestStore(initialState: initialState) {
            CommandExternalRefreshHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: oldPath, afterPath: newPath)],
        )
        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        XCTAssertNotNil(store.state.content.pendingIdentityTransition)

        // 무관한 경로·종류의 실패와 취소.
        await store.send(.bridge(.lifecycle(.operationFinished(
            otherPath,
            .rename,
            .failure(.system(message: "forced failure")),
        ))))
        await store.send(.bridge(.edit(.cancelRename)))
        XCTAssertNotNil(
            store.state.content.pendingIdentityTransition,
            "무관 실패·취소는 전이를 만료하지 않는다",
        )
        XCTAssertEqual(store.state.rootReloadCount, 1, "무관 실패·취소는 reload를 추가하지 않는다")

        // after-path projection: 같은 세대에서 선택을 옮기고 전이를 소비한다.
        let renamedEntry = makeCorrelationEntry(id: newPath, name: "new.txt")
        await store.send(.bridge(.loading(.itemsLoaded(
            generation: store.state.content.entryViewLayout.entryOperations.loadingContext.generation,
            items: [renamedEntry],
        ))))
        XCTAssertEqual(
            store.state.content.entryViewLayout.selectedIds,
            [newPath],
            "무관 실패·취소 후에도 선택은 after-path로 이동한다",
        )
        XCTAssertNil(store.state.content.pendingIdentityTransition, "전이는 소비된다")
    }
}

/// 명령 완료(coordinator)와 외부 변경(sync reducer)을 한 Store에서 이어 붙이고
/// 예약된 visible refresh 의도를 세는 harness. 상단 파일 레벨 선언으로 nesting lint를 피한다.
@Reducer
private struct CommandExternalRefreshHarness {
    struct State: Equatable {
        var content = FileManagerContentState()
        /// hierarchyInvalidated에 전달된 affectedPaths 기록 (명령/외부 refresh 의도 수집)
        var hierarchyInvalidations: [[String]] = []
        /// 외부 경로 root reload(loadItems) 예약 횟수
        var rootReloadCount = 0
    }

    enum Action {
        case bridge(EntryOperationsAction)
        case content(FileManagerContentAction)
        case select(String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .bridge(entryAction):
                return FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                    entryAction,
                    state: &state.content,
                )
                .map(Action.content)
            case let .select(path):
                state.content.entryViewLayout.selectedIds = [path]
                return .none
            case .content:
                return .none
            }
        }
        Scope(state: \.content, action: \.content) {
            FileManagerContentSyncReducer()
        }
        Reduce { state, action in
            switch action {
            case let .content(.entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, _)))):
                state.hierarchyInvalidations.append(affectedPaths)
                return .none
            case .content(.entryViewLayout(.entryOperations(.loading(.loadItems)))):
                state.rootReloadCount += 1
                // 명령 완료가 예약한 reload가 실행되면 실제 LoadingReducer가 세대를 +1 올린다.
                // 일치 이벤트가 그 이후에 도달해도 같은 세대로 판정되도록 여기서 세대를 맞춘다.
                state.content.entryViewLayout.entryOperations.loadingContext.generation &+= 1
                return .none
            default:
                return .none
            }
        }
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
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 상관 계약에 집중하고 라우팅 부수 효과 수신은 생략함
        store.exhaustivity = .off

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
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 truth table 계약에 집중함
        store.exhaustivity = .off

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
            $0.date = .constant(Date())
        }
        // store.exhaustivity = .off: 메트릭 truth table 계약에 집중함
        store.exhaustivity = .off

        let successRecord = EntryActionRecord(
            operationKind: .pasteFileCopy,
            targets: [.init(beforePath: "/src/a.txt", afterPath: "/dest/a.txt")],
        ).attaching(command: .init(id: UUID(), interaction: .pasteEntries, source: .fileManagerContent))
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(
            successRecord,
        ))))))

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
