import AppKit
import ComposableArchitecture
import Foundation
import PerceptionCore
import SwiftUI
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

final class CTM004SwitchContentTabWithUsedContentTabsSwitcherTests: XCTestCase {
    // MARK: - CTM-004-switch_content_tab_via_used_content_tabs_switcher

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 최근 사용한 live tab만 MRU 순서로 표시한다.
    /// 한 번도 사용하지 않은 열린 탭이 최근 사용 전환기에 섞이지 않는 대표 경로를 검증한다.
    /// - 검증 내용: live MRU 순서, non-MRU 제외, 최대 열 개, 후보 수별 균형 layout, 최소 창 폭 대응, 입력 불변성
    /// - 사전 조건: live `[A, B, C, D]`와 열두 개 MRU 후보를 각각 projection한다.
    /// - 기대 결과: non-MRU는 제외되고 긴 MRU는 첫 열 개만 1~5열의 한 행 또는 균형 잡힌 두 행에 표시한다.
    func testProjectsOnlyLiveRecentlyUsedTabsWithoutMutation() throws {
        let state = makeState(
            tabs: [tab("A"), tab("B"), tab("C"), tab("D")],
            active: "A",
            mru: ["C", "B"],
        )

        let projectedCandidates = try candidates(projecting: state)

        XCTAssertEqual(projectedCandidates.map(\.id), ids("C", "B"))
        XCTAssertFalse(projectedCandidates.contains(where: \.isCurrent))

        let rawIDs = (1 ... 12).map { String(format: "T%02d", $0) }
        let capped = try candidates(projecting: makeState(
            tabs: rawIDs.map { tab($0) }, active: "T01", mru: rawIDs,
        ))
        XCTAssertEqual(capped.map(\.id.rawValue), Array(rawIDs.prefix(10)))
        XCTAssertEqual(ContentTabSwitcherProjection.maximumCandidateCount, 10)
        XCTAssertEqual([ContentTabSwitcherLayout.maximumColumnCount, ContentTabSwitcherLayout.maximumRowCount], [5, 2])
        XCTAssertEqual(
            (1 ... 10).map(ContentTabSwitcherLayout.rowCounts(for:)),
            [[1], [2], [3], [4], [5], [3, 3], [4, 3], [4, 4], [5, 4], [5, 5]],
        )
        let minimumWindowGeometry = ContentTabSwitcherLayout.constrainedGeometry(
            candidateCount: 10,
            availableWidth: 600,
        )
        XCTAssertEqual(minimumWindowGeometry, .init(surfaceWidth: 568, cardWidth: 100.8))
        let defaultWindowGeometry = ContentTabSwitcherLayout.constrainedGeometry(
            candidateCount: 10,
            availableWidth: 960,
        )
        XCTAssertEqual(defaultWindowGeometry, .init(surfaceWidth: 704, cardWidth: 128))
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: stale·missing·duplicate MRU를 제거하고 fallback을 적용한다.
    /// 오래된 MRU가 남고 탭 metadata가 해소되지 않은 상태에서도 live row identity가 안정적인지 검증한다.
    /// - 검증 내용: stale 제거, 중복 제거, non-MRU 제외, title/icon trim fallback, 접근성 metadata
    /// - 사전 조건: MRU `[missing, C, C]`, blank metadata인 `C`, active `A`
    /// - 기대 결과: 후보가 `[C]`이고 `C`는 `Untitled`/`doc` fallback을 사용한다.
    func testDropsStaleAndDuplicateMRUAndResolvesFallbackMetadata() throws {
        let state = makeState(
            tabs: [
                tab("A", title: "  Active  ", icon: "  house  "),
                tab("B"),
                tab("C", title: " \n ", icon: "\t"),
            ],
            active: "A",
            mru: ["missing", "C", "C"],
        )

        let candidates = try candidates(projecting: state)
        let fallback = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidates.map(\.id), ids("C"))
        XCTAssertEqual(fallback.title, "Untitled")
        XCTAssertEqual(fallback.iconName, "doc")
        XCTAssertEqual(fallback.accessibilityIdentifier, "file-manager.content-tab-switcher.row.C")
        XCTAssertEqual(fallback.accessibilityLabel, "Untitled")
        XCTAssertEqual(fallback.accessibilityValue, "Home; Home")
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: Collection row는 저장된 icon metadata가 없어도 collection
    /// symbol을 표시한다.
    /// 복원된 collection tab의 누락된 iconName이 일반 문서 아이콘으로 떨어지지 않는지 검증한다.
    /// - 검증 내용: collection file 및 virtual collection icon fallback
    /// - 사전 조건: 두 collection tab의 iconName이 nil이다.
    /// - 기대 결과: collection file은 stack symbol, virtual collection은 folder symbol을 사용한다.
    func testCollectionRowsDeriveCollectionIconsWhenMetadataIsMissing() throws {
        let state = makeState(
            tabs: [
                tab(
                    "file",
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/Research.voycoll")),
                ),
                tab("virtual", page: .collection, anchor: .virtualCollection(id: "Tags")),
            ],
            active: "file",
            mru: ["file", "virtual"],
        )

        let candidates = try candidates(projecting: state)

        XCTAssertEqual(candidates.map(\.iconName), ["rectangle.stack", "folder"])
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: active가 MRU에 중복돼도 정확히 한 번 표시한다.
    /// 손상된 MRU 중복이 현재 탭 row와 Current 접근성 값을 복제하지 않는지 검증한다.
    /// - 검증 내용: active identity deduplication, current row 개수, Current suffix
    /// - 사전 조건: live `[A, C]`, MRU `[A, A, C]`, active `A`
    /// - 기대 결과: 후보가 `[A, C]`이고 current row가 하나이며 `A` 값만 `; Current`로 끝난다.
    func testIncludesDuplicatedActiveMRUIdentityExactlyOnce() throws {
        let state = makeState(tabs: [tab("A"), tab("C")], active: "A", mru: ["A", "A", "C"])

        let candidates = try candidates(projecting: state)

        XCTAssertEqual(candidates.map(\.id), ids("A", "C"))
        XCTAssertEqual(candidates.filter(\.isCurrent).count, 1)
        XCTAssertEqual(candidates[0].accessibilityValue, "Home; Home; Current")
        XCTAssertEqual(candidates[1].accessibilityValue, "Home; Home")
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 모든 Page와 anchor를 정확한 문자열로 요약한다.
    /// 전환기 row가 내부 식별자를 노출하지 않고 사용자용 Page/위치 metadata만 제공하는지 검증한다.
    /// - 검증 내용: 네 Page label과 다섯 anchor summary, collection filename, virtual/session ID 비노출
    /// - 사전 조건: Home, Directory, Collection file, Virtual Collection, AI Chat 탭
    /// - 기대 결과: 계획에 고정된 label/summary와 접근성 값이 그대로 반환된다.
    func testProjectsEveryPageAndAnchorSummary() throws {
        let state = makeState(
            tabs: [
                tab("home", page: .home, anchor: .homeDefault),
                tab("directory", page: .directory, anchor: .directory(path: " /tmp/Parent/../Directory \n")),
                tab(
                    "collection",
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/Folder/../Research.voycoll")),
                ),
                tab("collection-fallback", page: .collection, anchor: .collectionFile(url: URL(fileURLWithPath: "/"))),
                tab("virtual", page: .collection, anchor: .virtualCollection(id: "secret-collection-id")),
                tab("chat", page: .aiChat, anchor: .aiChat(sessionID: "secret-session-id")),
            ],
            active: "home",
            mru: ["home", "directory", "collection", "collection-fallback", "virtual", "chat"],
        )

        let candidates = try candidates(projecting: state)

        XCTAssertEqual(
            candidates.map(\.pageLabel),
            ["Home", "Directory", "Collection", "Collection", "Collection", "AI Chat"],
        )
        XCTAssertEqual(
            candidates.map(\.anchorSummary),
            ["Home", "Directory", "Research.voycoll", "Collection", "Virtual Collection", "AI Chat"],
        )
        XCTAssertEqual(candidates[1].accessibilityValue, "Directory; Directory")
        XCTAssertEqual(candidates[2].accessibilityValue, "Collection; Research.voycoll")
        XCTAssertFalse(candidates.map(\.accessibilityValue).joined().contains("secret"))
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 빈 Directory path는 CWD를 노출하지 않는다.
    /// 해소되지 않은 빈 경로가 실행 worktree 이름으로 변환되는 회귀를 검증한다.
    /// - 검증 내용: empty와 whitespace-only directory path의 고정 fallback
    /// - 사전 조건: path `""`와 `" \n\t "`인 두 Directory 탭
    /// - 기대 결과: 두 anchor summary 모두 정확히 `Directory`이다.
    func testEmptyDirectoryPathsUseDeterministicFallback() throws {
        let state = makeState(
            tabs: [
                tab("empty", page: .directory, anchor: .directory(path: "")),
                tab("whitespace", page: .directory, anchor: .directory(path: " \n\t ")),
            ],
            active: "empty",
            mru: ["empty", "whitespace"],
        )

        let candidates = try candidates(projecting: state)

        XCTAssertEqual(candidates.map(\.anchorSummary), ["Directory", "Directory"])
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: root Directory는 `/`로 요약한다.
    /// 표준화된 root URL의 빈 lastPathComponent가 일반 fallback으로 손실되지 않는지 검증한다.
    /// - 검증 내용: root path 전용 anchor summary
    /// - 사전 조건: `/` Directory 탭 하나가 active이다.
    /// - 기대 결과: anchor summary가 `/`이고 접근성 값은 `Directory; /; Current`이다.
    func testRootDirectoryUsesSlashSummary() throws {
        let state = makeState(
            tabs: [tab("root", page: .directory, anchor: .directory(path: "/"))],
            active: "root",
            mru: ["root"],
        )

        let candidate = try XCTUnwrap(candidates(projecting: state).first)

        XCTAssertEqual(candidate.anchorSummary, "/")
        XCTAssertEqual(candidate.accessibilityValue, "Directory; /; Current")
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: live tab이 없고 active도 없으면 empty 후보를 반환한다.
    /// stale-only MRU가 빈 화면을 오류나 가짜 row로 바꾸지 않는지 검증한다.
    /// - 검증 내용: zero live tabs, stale-only MRU, 입력 불변성
    /// - 사전 조건: tabs `[]`, active nil, MRU `[stale]`
    /// - 기대 결과: 유효한 빈 candidate 배열이다.
    func testEmptyLiveTabsIgnoreStaleOnlyMRU() throws {
        let state = makeState(tabs: [], active: nil, mru: ["stale"])

        XCTAssertTrue(try candidates(projecting: state).isEmpty)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 잘못된 active topology는 명시적 오류를 반환한다.
    /// 전환기가 active row를 합성하지 않고 세 가지 malformed state를 동일하게 거부하는지 검증한다.
    /// - 검증 내용: empty+nonnil active, nonempty+nil active, nonempty+missing active
    /// - 사전 조건: 각 malformed `ContentTabState`를 독립적으로 projection한다.
    /// - 기대 결과: 각 결과가 `.invalidActiveTabIdentity`이고 tabs/MRU는 변하지 않는다.
    func testRejectsEveryInvalidActiveTopology() {
        let states = [
            makeState(tabs: [], active: "missing", mru: []),
            makeState(tabs: [tab("A")], active: nil, mru: []),
            makeState(tabs: [tab("A")], active: "missing", mru: ["A"]),
        ]

        for state in states {
            let tabsBefore = state.tabs
            let mruBefore = state.recentlyUsedTabIDs

            XCTAssertEqual(ContentTabSwitcherProjection.project(from: state), .invalidActiveTabIdentity)
            XCTAssertEqual(state.tabs, tabsBefore)
            XCTAssertEqual(state.recentlyUsedTabIDs, mruBefore)
        }
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 표시 source와 현재 탭 topology를 결정적 view state로 변환한다.
    /// 네 화면 상태와 row metadata가 상호작용 상태 없이 현재 ContentTabState에서 매번 재계산되는지 검증한다.
    /// - 검증 내용: content/empty/loading/error, malformed/stale topology, fallback, stable ID, Current/accessibility 문자열
    /// - 사전 조건: 네 Page row, stale MRU, 빈/손상 topology, 명시적 loading/error source
    /// - 기대 결과: 정확한 상태와 접근성 props를 반환하고 입력 tabs/MRU를 변경하지 않는다.
    func testViewStatesAndAccessibilityMetadata() throws {
        try assertAutomaticContentViewState()
        try assertAutomaticFallbackAndRecomputation()
        assertAutomaticEmptyAndMalformedViewStates()
        assertExplicitStatusViewStates()
        let evidence = [
            "content", "empty", "loading", "error", "malformed", "stale",
            "fallback", "stable-id", "current", "accessibility", "recompute",
        ]
        print("VIEW_STATE_MATRIX \(evidence.joined(separator: " ")) PASS")
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 전환기 화면 생성 자체는 후보를 활성화하지 않는다.
    /// 사용자의 명시적 후보 선택 없이 화면 렌더링만으로 해제나 탭 활성화가 발생하지 않는 계약을 검증한다.
    /// - 검증 내용: immutable view state와 explicit-ID activation callback, 네 화면 상태의 body 렌더링, activation·dismiss 무호출
    /// - 사전 조건: content/loading/empty/error view state와 호출 횟수를 기록하는 activation/dismiss closure
    /// - 기대 결과: 모든 상태의 화면 body가 생성되고 activation과 dismiss closure 호출 횟수는 0이다.
    @MainActor
    func testSwitcherScreenRenderingDoesNotActivateCandidate() {
        let contentTabs = makeState(tabs: [tab("current")], active: "current", mru: ["current"])
        let viewStates = [
            ContentTabSwitcherViewState.make(source: .automatic, contentTabs: contentTabs),
            ContentTabSwitcherViewState.make(source: .loading, contentTabs: contentTabs),
            ContentTabSwitcherViewState.make(
                source: .automatic,
                contentTabs: makeState(tabs: [], active: nil, mru: []),
            ),
            ContentTabSwitcherViewState.make(source: .error(message: "Host failure"), contentTabs: contentTabs),
        ]
        var activationCallCount = 0
        var dismissCallCount = 0

        for viewState in viewStates {
            let view = FileManagerContentTabSwitcherView(
                viewState: viewState,
                onActivate: { _ in activationCallCount += 1 },
                onDismiss: { dismissCallCount += 1 },
            )
            _ = view.body
        }

        XCTAssertEqual(activationCallCount, 0)
        XCTAssertEqual(dismissCallCount, 0)
    }

    /// CTM-004-present_content_tab_switcher_from_host: FileManagerHost의 content preset이 전환기를 표시한다.
    /// 실제 host fixture가 결정적인 Content Tab topology를 만들고 semantic helper가 automatic presentation을 보태는지 검증한다.
    /// - 검증 내용: seven-row content preset, presentation nil before helper, automatic source after helper
    /// - 사전 조건: `.contentTabSwitcherContent` preset으로 생성한 FileManagerHost coordinator
    /// - 기대 결과: helper 전 presentation은 nil이고 helper 후 automatic presentation이다.
    @MainActor
    func testFileManagerHostContentScenarioPresentsSwitcher() async {
        let perceptionCheckingWasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        _ = NSApplication.shared
        let coordinator = withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        } operation: {
            FileManagerHostFixture.makeWindowController(preset: .contentTabSwitcherContent)
        }
        XCTAssertEqual(coordinator.store.contentTabs.tabs.count, 10)
        XCTAssertEqual(
            try? candidates(projecting: coordinator.store.contentTabs).count,
            10,
        )
        XCTAssertNil(coordinator.store.contentTabSwitcherPresentation)

        FileManagerHostFixture.presentSwitcherIfNeeded(
            for: .contentTabSwitcherContent,
            in: coordinator.store,
        )

        XCTAssertEqual(
            coordinator.store.contentTabSwitcherPresentation,
            .init(source: .automatic, contentTabs: coordinator.store.contentTabs),
        )
        await tearDownHostFixture(coordinator)
    }

    /// CTM-004-host_scenario_fixture_matrix: FileManagerHost의 모든 전환기 fixture와 appearance 입력을 결정적으로 해석한다.
    /// 사용자가 다섯 화면 상태와 system/light/dark appearance를 직접 launch할 수 있도록 preset과 semantic source 매핑을 검증한다.
    /// - 검증 내용: content/fallback/empty/loading/error fixture, presentation nil 선행, fallback identity/metadata,
    /// appearance resolver
    /// - 사전 조건: deterministic UUID/date dependency와 각 FileManagerHost preset
    /// - 기대 결과: helper 전 presentation nil, helper 후 exact source, invalid appearance는 명시적 invalid 결과이다.
    @MainActor
    func testFileManagerHostAdditionalScenarioFixtures() async {
        let perceptionCheckingWasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        _ = NSApplication.shared

        let expectedWindowID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 1))
        let expectedDate = Date(timeIntervalSince1970: 1_234_567_890)
        let scenarios = [
            FileManagerHostScenario(
                preset: .contentTabSwitcherContent,
                expectedTabCount: 10,
                expectedSource: .automatic,
                expectsUnresolvedMetadata: false,
            ),
            FileManagerHostScenario(
                preset: .contentTabSwitcherFallback,
                expectedTabCount: 10,
                expectedSource: .automatic,
                expectsUnresolvedMetadata: true,
            ),
            FileManagerHostScenario(
                preset: .contentTabSwitcherEmpty,
                expectedTabCount: 0,
                expectedSource: .automatic,
                expectsUnresolvedMetadata: false,
            ),
            FileManagerHostScenario(
                preset: .contentTabSwitcherLoading,
                expectedTabCount: 10,
                expectedSource: .loading,
                expectsUnresolvedMetadata: false,
            ),
            FileManagerHostScenario(
                preset: .contentTabSwitcherError,
                expectedTabCount: 10,
                expectedSource: .error(message: "Unable to load recent tabs."),
                expectsUnresolvedMetadata: false,
            ),
        ]
        var contentSnapshot: ContentTabState?

        for scenario in scenarios {
            do {
                let coordinator = withDependencies {
                    $0.uuid = .constant(expectedWindowID)
                    $0.date = .constant(expectedDate)
                } operation: {
                    FileManagerHostFixture.makeWindowController(preset: scenario.preset)
                }
                XCTAssertEqual(coordinator.windowID, expectedWindowID)
                XCTAssertEqual(coordinator.store.contentTabs.tabs.count, scenario.expectedTabCount)
                XCTAssertNil(coordinator.store.contentTabSwitcherPresentation)

                if scenario.preset == .contentTabSwitcherContent {
                    contentSnapshot = coordinator.store.contentTabs
                }
                if scenario.expectsUnresolvedMetadata, let contentSnapshot {
                    XCTAssertEqual(coordinator.store.contentTabs.tabs.map(\.id), contentSnapshot.tabs.map(\.id))
                    XCTAssertEqual(coordinator.store.contentTabs.tabs.map(\.page), contentSnapshot.tabs.map(\.page))
                    XCTAssertEqual(coordinator.store.contentTabs.tabs.map(\.anchor), contentSnapshot.tabs.map(\.anchor))
                    XCTAssertTrue(coordinator.store.contentTabs.tabs
                        .allSatisfy { $0.title == nil && $0.iconName == nil })
                }

                FileManagerHostFixture.presentSwitcherIfNeeded(
                    for: scenario.preset,
                    in: coordinator.store,
                )
                XCTAssertEqual(coordinator.store.contentTabSwitcherPresentation?.source, scenario.expectedSource)
                print("SCENARIO_SUBCASE \(scenario.preset.rawValue) PASS")
                await tearDownHostFixture(coordinator)
            }
        }

        let appearanceCases: [(rawValue: String?, expected: FileManagerHostAppearance)] = [
            (nil, .system),
            ("system", .system),
            ("light", .light),
            ("dark", .dark),
            ("sepia", .invalid("sepia")),
        ]
        for appearanceCase in appearanceCases {
            XCTAssertEqual(
                FileManagerHostAppearance.resolve(rawValue: appearanceCase.rawValue),
                appearanceCase.expected,
            )
            print("APPEARANCE_SUBCASE \(appearanceCase.rawValue ?? "system") PASS")
        }
    }

    private func candidates(projecting state: ContentTabState) throws -> [ContentTabSwitcherProjection.Candidate] {
        let tabsBefore = state.tabs
        let mruBefore = state.recentlyUsedTabIDs
        let result = ContentTabSwitcherProjection.project(from: state)
        XCTAssertEqual(state.tabs, tabsBefore)
        XCTAssertEqual(state.recentlyUsedTabIDs, mruBefore)
        guard case let .candidates(candidates) = result else {
            XCTFail("Expected candidates, received \(result)")
            return []
        }
        return candidates
    }

    @MainActor
    func tearDownHostFixture(_ coordinator: FileManagerWindowCoordinator) async {
        coordinator.window?.contentViewController = nil
        coordinator.close()
        await drainMainQueue()
        await drainMainQueue()
    }

    @MainActor
    func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

struct ContentTabSemanticSnapshot: Equatable {
    let content: FileManagerContentFeature.State
    let tabContentStates: [ContentTabID: FileManagerContentFeature.State]
    let activeTabID: ContentTabID?
    let recentlyUsedTabIDs: [ContentTabID]
    let selectedTabIDs: Set<ContentTabID>
    let selectionAnchorID: ContentTabID?
    let orderedTabIDs: [ContentTabID]
    let pages: [ContentTabPage]
    let anchors: [ContentTabPageAnchor]
    let sidebarVisible: Bool
    let sidebarWidth: CGFloat
    let inspectorVisible: Bool
    let inspectorPaneExists: Bool
    let inspectorWidth: CGFloat
    let inspectorMode: FileManagerInspectorMode

    init(_ state: FileManagerWindowState) {
        content = state.content
        tabContentStates = state.tabContentStates
        activeTabID = state.contentTabs.activeTabID
        recentlyUsedTabIDs = state.contentTabs.recentlyUsedTabIDs
        selectedTabIDs = state.contentTabs.selectedTabIDs
        selectionAnchorID = state.contentTabs.selectionAnchorID
        orderedTabIDs = Array(state.contentTabs.tabs.ids)
        pages = state.contentTabs.tabs.map(\.page)
        anchors = state.contentTabs.tabs.map(\.anchor)
        sidebarVisible = state.sidebar.sidebarVisible
        sidebarWidth = state.sidebar.sidebarWidth
        inspectorVisible = state.inspector.inspectorVisible
        inspectorPaneExists = state.inspector.inspectorPaneExists
        inspectorWidth = state.inspector.inspectorWidth
        inspectorMode = state.inspector.activeMode
    }
}

private func assertAutomaticContentViewState() throws {
    let state = makeState(
        tabs: [
            tab("home", page: .home, anchor: .homeDefault, title: "Home Tab", icon: "house"),
            tab(
                "directory",
                page: .directory,
                anchor: .directory(path: "/tmp/Projects"),
                title: "Projects",
                icon: "folder",
            ),
            tab(
                "collection",
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/Research.voycoll")),
                title: "Research",
                icon: "tray.full",
            ),
            tab("chat", page: .aiChat, anchor: .aiChat(sessionID: "session"), title: "Assistant", icon: "sparkles"),
        ],
        active: "home",
        mru: ["chat", "collection", "directory", "home"],
    )
    let tabsBefore = state.tabs
    let mruBefore = state.recentlyUsedTabIDs

    guard case let .content(rows) = ContentTabSwitcherViewState.make(source: .automatic, contentTabs: state) else {
        return XCTFail("Expected automatic content state")
    }

    XCTAssertEqual(rows.map(\.id), ids("chat", "collection", "directory", "home"))
    XCTAssertEqual(rows.map(\.title), ["Assistant", "Research", "Projects", "Home Tab"])
    XCTAssertEqual(rows.map(\.iconName), ["sparkles", "rectangle.stack", "folder", "house"])
    XCTAssertEqual(rows.map(\.pageLabel), ["AI Chat", "Collection", "Directory", "Home"])
    XCTAssertEqual(rows.map(\.anchorSummary), ["AI Chat", "Research.voycoll", "Projects", "Home"])
    XCTAssertEqual(rows.map(\.accessibilityIdentifier), ids("chat", "collection", "directory", "home").map {
        "file-manager.content-tab-switcher.row.\($0.rawValue)"
    })
    XCTAssertEqual(rows.map(\.accessibilityLabel), ["Assistant", "Research", "Projects", "Home Tab"])
    XCTAssertEqual(rows.map(\.accessibilityValue), [
        "AI Chat; AI Chat",
        "Collection; Research.voycoll",
        "Directory; Projects",
        "Home; Home; Current",
    ])
    XCTAssertEqual(rows.filter(\.isCurrent).map(\.id), ids("home"))
    XCTAssertTrue(rows.allSatisfy(\.isIconAccessibilityHidden))
    XCTAssertEqual(state.tabs, tabsBefore)
    XCTAssertEqual(state.recentlyUsedTabIDs, mruBefore)
}

private func assertAutomaticFallbackAndRecomputation() throws {
    var state = makeState(
        tabs: [
            tab("active", page: .home, anchor: .homeDefault, title: "Active", icon: "house"),
            tab("fallback", page: .directory, anchor: .directory(path: ""), title: " \n ", icon: nil),
        ],
        active: "active",
        mru: ["stale", "fallback", "active"],
    )
    guard case let .content(initialRows) = ContentTabSwitcherViewState.make(source: .automatic, contentTabs: state)
    else {
        return XCTFail("Expected content with stale MRU ignored")
    }
    let fallback = try XCTUnwrap(initialRows.first)
    XCTAssertEqual(fallback.id, id("fallback"))
    XCTAssertEqual(fallback.title, "Untitled")
    XCTAssertEqual(fallback.iconName, "doc")
    XCTAssertEqual(fallback.accessibilityIdentifier, "file-manager.content-tab-switcher.row.fallback")
    XCTAssertEqual(fallback.accessibilityLabel, "Untitled")
    XCTAssertEqual(fallback.accessibilityValue, "Directory; Directory")
    XCTAssertTrue(fallback.isIconAccessibilityHidden)

    state.tabs[id: id("fallback")]?.title = "Resolved"
    state.tabs[id: id("fallback")]?.iconName = "folder"
    guard case let .content(resolvedRows) = ContentTabSwitcherViewState.make(source: .automatic, contentTabs: state)
    else {
        return XCTFail("Expected resolved content")
    }
    XCTAssertEqual(resolvedRows.first?.id, fallback.id)
    XCTAssertEqual(resolvedRows.first?.accessibilityIdentifier, fallback.accessibilityIdentifier)

    state.tabs = .init(uniqueElements: state.tabs.filter { $0.id != id("fallback") })
    let mruBefore = state.recentlyUsedTabIDs
    guard case let .content(recomputedRows) = ContentTabSwitcherViewState.make(source: .automatic, contentTabs: state)
    else {
        return XCTFail("Expected recomputed content")
    }
    XCTAssertEqual(recomputedRows.map(\.id), ids("active"))
    XCTAssertEqual(state.recentlyUsedTabIDs, mruBefore)
}

private func assertAutomaticEmptyAndMalformedViewStates() {
    let empty = makeState(tabs: [], active: nil, mru: ["stale"])
    XCTAssertEqual(
        ContentTabSwitcherViewState.make(source: .automatic, contentTabs: empty),
        .empty(.init(message: "No recent tabs", accessibilityLabel: "No recent tabs")),
    )
    let malformed = [
        makeState(tabs: [], active: "missing", mru: []),
        makeState(tabs: [tab("A")], active: nil, mru: ["stale"]),
        makeState(tabs: [tab("A")], active: "missing", mru: ["A"]),
    ]
    for state in malformed {
        XCTAssertEqual(
            ContentTabSwitcherViewState.make(source: .automatic, contentTabs: state),
            .error(.init(
                message: "Unable to load recent tabs.",
                accessibilityLabel: "Unable to load recent tabs.",
            )),
        )
    }
}

private func assertExplicitStatusViewStates() {
    let contentTabs = makeState(tabs: [tab("A")], active: "A", mru: [])
    XCTAssertEqual(
        ContentTabSwitcherViewState.make(source: .loading, contentTabs: contentTabs),
        .loading(.init(message: "Loading recent tabs", accessibilityLabel: "Loading recent tabs")),
    )
    XCTAssertEqual(
        ContentTabSwitcherViewState.make(source: .error(message: "Host failure"), contentTabs: contentTabs),
        .error(.init(message: "Host failure", accessibilityLabel: "Host failure")),
    )
}

typealias BusyPresentationSubcase = (String, (inout FileManagerWindowState) -> Void)

func busyCloseAndPinSubcases(
    tabID: ContentTabID,
    requestID: UUID,
    ownerID: UUID,
) -> [BusyPresentationSubcase] {
    [
        ("is-closing", { $0.isClosing = true }),
        ("pending-selected-close", {
            $0.pendingSelectedContentTabClose = .init(
                operationID: requestID,
                orderedTargetIDs: [tabID],
                originalActiveTabID: tabID,
                preferredFallbackIDs: [],
            )
        }),
        ("pending-single-close", { $0.pendingContentTabClose = .init(tabID: tabID) }),
        ("pending-teardown", {
            $0.pendingContentTabTeardown = .init(requestID: requestID, tabID: tabID, ownerID: ownerID)
        }),
        ("pending-selected-pin-mutation", {
            $0.pendingSelectedContentTabPinMutation = .init(
                operationID: requestID,
                target: .pinned,
                orderedTargetIDs: [tabID],
            )
        }),
    ]
}

private struct FileManagerHostScenario {
    let preset: FileManagerHostPreset
    let expectedTabCount: Int
    let expectedSource: FileManagerContentTabSwitcherPresentation.Source
    let expectsUnresolvedMetadata: Bool
}

func busyTopologySubcases(
    tabID: ContentTabID,
    requestID: UUID,
    ownerID: UUID,
) -> [BusyPresentationSubcase] {
    let moveRequest = ContentTabMoveRequest(
        requestID: requestID,
        sourceWindowID: ownerID,
        tabID: tabID,
        targetWindowID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 68)),
    )
    return [
        ("pending-move-prepared", {
            $0.pendingContentTabMove = .init(request: moveRequest, lifecycle: .prepared)
        }),
        ("pending-move-in-flight", {
            $0.pendingContentTabMove = .init(request: moveRequest, lifecycle: .inFlight)
        }),
        ("move-participant", { $0.contentTabMoveParticipantRequestID = requestID }),
        ("pending-top-navigation", {
            $0.pendingTopNavigationIntents = [
                .init(token: .init(value: requestID), intent: .close(tabID)),
            ]
        }),
        ("pending-pinned-record", { $0.contentTabs.pendingPinnedRecordIDs = [tabID] }),
        ("undo-tearing-down-tab", {
            $0.undoRedoPhase = .tearingDownTab(requestID: requestID, ownerID: ownerID)
        }),
    ]
}

func id(_ rawValue: String) -> ContentTabID {
    ContentTabID(rawValue: rawValue)
}

func ids(_ rawValues: String...) -> [ContentTabID] {
    rawValues.map(id)
}

func tab(
    _ rawID: String,
    page: ContentTabPage = .home,
    anchor: ContentTabPageAnchor = .homeDefault,
    title: String? = nil,
    icon: String? = nil,
) -> ContentTabItem {
    ContentTabItem(
        id: id(rawID),
        page: page,
        anchor: anchor,
        isPinned: false,
        title: title,
        iconName: icon,
    )
}

func makeState(
    tabs: [ContentTabItem],
    active: String?,
    mru: [String],
) -> ContentTabState {
    ContentTabState(
        tabs: .init(uniqueElements: tabs),
        activeTabID: active.map(id),
        recentlyUsedTabIDs: mru.map(id),
    )
}

func makeSwitcherWindowState(prefix: String) -> FileManagerWindowState {
    let firstID = ContentTabID(rawValue: "\(prefix)-A")
    let secondID = ContentTabID(rawValue: "\(prefix)-B")
    var state = FileManagerWindowState()
    state.contentTabs = ContentTabState(
        tabs: [
            tab(firstID.rawValue, page: .directory, anchor: .directory(path: "/\(prefix)/A")),
            tab(secondID.rawValue, page: .collection, anchor: .virtualCollection(id: "\(prefix)-collection")),
        ],
        activeTabID: secondID,
        recentlyUsedTabIDs: [secondID, firstID],
    )
    state.contentTabs.selectedTabIDs = [firstID, secondID]
    state.contentTabs.selectionAnchorID = firstID
    state.sidebar.sidebarVisible = false
    state.sidebar.sidebarWidth = 275
    state.inspector.inspectorVisible = true
    state.inspector.inspectorPaneExists = true
    state.inspector.inspectorWidth = 333
    return state
}
