import AppKit
import ComposableArchitecture
import Foundation
import PerceptionCore
@testable import VoyagerPagesFileManager
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

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 전환기 화면은 row 활성화 입력 없이 렌더링한다.
    /// 사용자가 전환기 내용을 탐색해도 화면 생성과 렌더링만으로 해제나 탭 활성화가 발생하지 않는 계약을 검증한다.
    /// - 검증 내용: immutable view state와 dismiss closure만 받는 화면 API, 네 화면 상태의 body 렌더링, dismiss 무호출
    /// - 사전 조건: content/loading/empty/error view state와 호출 횟수를 기록하는 dismiss closure
    /// - 기대 결과: 모든 상태의 화면 body가 생성되고 dismiss closure 호출 횟수는 0이다.
    @MainActor
    func testSwitcherScreenUsesNonActivatingRowContract() {
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
        var dismissCallCount = 0

        for viewState in viewStates {
            let view = FileManagerContentTabSwitcherView(
                viewState: viewState,
                onDismiss: { dismissCallCount += 1 },
            )
            _ = view.body
        }

        XCTAssertEqual(dismissCallCount, 0)
    }

    /// CTM-004-present_content_tab_switcher_from_host: FileManagerHost의 content preset이 전환기를 표시한다.
    /// 실제 host fixture가 결정적인 Content Tab topology를 만들고 semantic helper가 automatic presentation을 보태는지 검증한다.
    /// - 검증 내용: seven-row content preset, presentation nil before helper, automatic source after helper
    /// - 사전 조건: `.contentTabSwitcherContent` preset으로 생성한 FileManagerHost coordinator
    /// - 기대 결과: helper 전 presentation은 nil이고 helper 후 automatic presentation이다.
    @MainActor
    func testFileManagerHostContentScenarioPresentsSwitcher() {
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
        defer { coordinator.close() }

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
    }

    /// CTM-004-host_scenario_fixture_matrix: FileManagerHost의 모든 전환기 fixture와 appearance 입력을 결정적으로 해석한다.
    /// 사용자가 다섯 화면 상태와 system/light/dark appearance를 직접 launch할 수 있도록 preset과 semantic source 매핑을 검증한다.
    /// - 검증 내용: content/fallback/empty/loading/error fixture, presentation nil 선행, fallback identity/metadata,
    /// appearance resolver
    /// - 사전 조건: deterministic UUID/date dependency와 각 FileManagerHost preset
    /// - 기대 결과: helper 전 presentation nil, helper 후 exact source, invalid appearance는 명시적 invalid 결과이다.
    @MainActor
    func testFileManagerHostAdditionalScenarioFixtures() {
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
                defer { coordinator.close() }

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

    /// CTM-004-dismiss_content_tab_switcher_without_mutation: mounted overlay의 dismiss wiring이 Content Tab을 보존한다.
    /// package에서 검증 가능한 reducer action과 whole-window source wiring이 같은 view dismiss 경로를 사용하는지 고정한다.
    /// - 검증 내용: switcher shell 중앙 배치와 focus 확보, Escape dismiss action, semantic snapshot
    /// - 사전 조건: two-tab window에 presentation을 표시한 상태와 canonical main-container source
    /// - 기대 결과: overlay dismiss 후 presentation만 nil이 되고 Content Tab semantic snapshot은 byte-equivalent이다.
    @MainActor
    func testMountedSwitcherFocusAndDismissPreserveContentTabs() async throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let switcherSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerContentTabSwitcherView.swift",
            ),
            encoding: .utf8,
        )

        XCTAssertTrue(switcherSource.contains(".focusSection()"))
        XCTAssertFalse(switcherSource.contains("@FocusState private var isSwitcherFocused"))
        XCTAssertFalse(switcherSource.contains(".focused($isSwitcherFocused)"))
        XCTAssertTrue(switcherSource.contains(".onAppear(perform: synchronizeFocus)"))
        XCTAssertTrue(switcherSource.contains(".onExitCommand(perform: onDismiss)"))
        XCTAssertTrue(switcherSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)"))

        let initialState = makeSwitcherWindowState(prefix: "mounted")
        let snapshot = ContentTabSemanticSnapshot(initialState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic, contentTabs: $0.contentTabs)
        }
        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }

        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), snapshot)
        XCTAssertNil(store.state.contentTabSwitcherPresentation)
    }

    // MARK: - CTM-004-present_focused_candidate

    /// CTM-004-present_focused_candidate: focus된 non-current card가 Current와 독립된 시각·접근성 상태를 유지한다.
    /// reducer가 선택한 ContentTabID가 실제 SwiftUI row focus와 분리된 Current metadata를 구동하는 계약을 검증한다.
    /// - 검증 내용: reducer focus identity 매핑, row focus ring, native FocusState, 기존 accessibility metadata 보존
    /// - 사전 조건: current card와 별도의 focused candidate가 있는 automatic switcher, deterministic FileManagerHost fixture
    /// - 기대 결과: focused non-current와 Current가 동시에 구분되고 activation/tap callback 없이 동일한 row identifier/label/value를 사용한다.
    @MainActor
    func testFocusedCandidateVisualAndAccessibilityRemainDistinctFromCurrent() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let presentationSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Model/FileManagerContentTabSwitcherPresentation.swift",
            ),
            encoding: .utf8,
        )
        let viewSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerContentTabSwitcherView.swift",
            ),
            encoding: .utf8,
        )
        let state = makeState(
            tabs: [
                tab("current", title: "Current Tab", icon: "house"),
                tab("candidate", title: "Focused Candidate", icon: "folder"),
            ],
            active: "current",
            mru: ["candidate", "current"],
        )
        let contentTabsBeforeFocus = state
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: state,
            focusedCandidateID: id("candidate"),
        ) else {
            return XCTFail("Expected focused candidate content rows")
        }
        guard case let .content(focusedCurrentRows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: state,
            focusedCandidateID: id("current"),
        ) else {
            return XCTFail("Expected focused-current content rows")
        }
        try assertFocusedCandidateViewContract(
            presentationSource: presentationSource,
            viewSource: viewSource,
            rows: rows,
            focusedCurrentRows: focusedCurrentRows,
            contentTabs: state,
            contentTabsBeforeFocus: contentTabsBeforeFocus,
        )
    }

    /// CTM-004-present_focused_candidate: FileManagerHost content fixture가 1·5·6·10 card focus layout을 결정적으로 노출한다.
    /// 실제 host state를 후보 수별로 축약해 adaptive row geometry와 reducer focus의 manual observable을 검증한다.
    /// - 검증 내용: host fixture source/state, 1·5·6·10 후보 수, 균형 행 수, 단일 focused ContentTabID
    /// - 사전 조건: deterministic UUID/date dependency와 `.contentTabSwitcherContent` FileManagerHost fixture
    /// - 기대 결과: 각 card 수가 projection/view state에 그대로 반영되고 하나의 focus identity가 metadata를 바꾸지 않는다.
    @MainActor
    func testFileManagerHostContentFixtureExposesFocusCardLayoutCases() {
        let perceptionCheckingWasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        _ = NSApplication.shared

        let coordinator = withDependencies {
            $0.uuid = .constant(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 1)))
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        } operation: {
            FileManagerHostFixture.makeWindowController(preset: .contentTabSwitcherContent)
        }
        defer { coordinator.close() }

        for cardCount in [1, 5, 6, 10] {
            var fixtureState = coordinator.store.contentTabs
            fixtureState.recentlyUsedTabIDs = Array(fixtureState.recentlyUsedTabIDs.prefix(cardCount))
            let presentation = FileManagerContentTabSwitcherPresentation(
                source: .automatic,
                contentTabs: fixtureState,
            )

            guard case let .content(rows) = ContentTabSwitcherViewState.make(
                source: presentation.source,
                contentTabs: fixtureState,
                focusedCandidateID: presentation.focusedCandidateID,
            ) else {
                return XCTFail("Expected content rows for card count \(cardCount)")
            }

            XCTAssertEqual(rows.count, cardCount)
            let expectedRowCounts = ContentTabSwitcherLayout.rowCounts(for: cardCount)
            XCTAssertEqual(
                ContentTabSwitcherLayout.rowCounts(for: rows.count),
                expectedRowCounts,
            )
            let balancedRows = ContentTabSwitcherLayout.balancedRows(from: rows)
            XCTAssertEqual(balancedRows.map(\.count), expectedRowCounts)
            XCTAssertEqual(balancedRows.flatMap(\.self).map(\.id), rows.map(\.id))
            let geometry = ContentTabSwitcherLayout.constrainedGeometry(
                candidateCount: cardCount,
                availableWidth: 960,
            )
            XCTAssertEqual(geometry.cardWidth, ContentTabSwitcherLayout.idealCardWidth)
            XCTAssertEqual(rows.filter(\.isFocused).count, 1)
            print(
                "FOCUS_FIXTURE_SUBCASE cards=\(cardCount) rows=\(ContentTabSwitcherLayout.rowCounts(for: rows.count)) "
                    + "focused=\(rows.first(where: { $0.isFocused })?.id.rawValue ?? "nil") PASS",
            )
        }
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 전환기 표시와 해제가 Content Tab 의미 상태를 보존한다.
    /// window-local 표시 수명주기와 Escape·backdrop 공용 해제 action의 멱등성을 검증한다.
    /// - 검증 내용: 표시 source, 명시적 해제, 반복 표시/해제, Escape/backdrop 해제, 다른 window 불변성
    /// - 사전 조건: 선택과 MRU가 있는 독립된 두 개의 two-tab window
    /// - 기대 결과: 대상 window의 presentation만 변경되고 두 window의 Content Tab 의미 상태는 유지된다.
    @MainActor
    func testPresentationLifecyclePreservesContentTabState() async {
        let initialState = makeSwitcherWindowState(prefix: "focused")
        let unfocusedState = makeSwitcherWindowState(prefix: "unfocused")
        let initialSnapshot = ContentTabSemanticSnapshot(initialState)
        let unfocusedSnapshot = ContentTabSemanticSnapshot(unfocusedState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic, contentTabs: $0.contentTabs)
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        XCTAssertEqual(ContentTabSemanticSnapshot(unfocusedState), unfocusedSnapshot)
        print("LIFECYCLE_SUBCASE present PASS")

        await store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE repeated-present PASS")

        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE explicit-dismiss PASS")

        await store.send(.view(.dismissContentTabSwitcher))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE repeated-dismiss PASS")

        await store.send(.request(.presentContentTabSwitcher(source: .loading))) {
            $0.contentTabSwitcherPresentation = .init(source: .loading)
        }
        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE escape-equivalent-dismiss PASS")

        await store.send(.request(.presentContentTabSwitcher(source: .error(message: "Unable to load recent tabs.")))) {
            $0.contentTabSwitcherPresentation = .init(source: .error(message: "Unable to load recent tabs."))
        }
        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        XCTAssertEqual(ContentTabSemanticSnapshot(unfocusedState), unfocusedSnapshot)
        print("LIFECYCLE_SUBCASE backdrop-equivalent-dismiss PASS")
        print("LIFECYCLE_SUBCASE focused-window-locality PASS")
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 전환기 focus는 current와 독립적으로 후보를 wrap한다.
    /// next가 stable ContentTabID만 변경하고 Content Tab 의미 상태를 변경하지 않는지 검증한다.
    /// - 검증 내용: initial current focus, forward wrap, Current/focus 분리
    /// - 사전 조건: active B와 MRU `[B, A]`인 two-tab window
    /// - 기대 결과: focus만 B↔A로 이동하고 active/MRU/selection/page/pane snapshot은 완전히 동일하다.
    @MainActor
    func testFocusNavigationWrapsWithoutMutatingContentTabState() async {
        let initialState = makeSwitcherWindowState(prefix: "focus")
        let semanticSnapshot = ContentTabSemanticSnapshot(initialState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                contentTabs: $0.contentTabs,
            )
        }
        XCTAssertEqual(
            store.state.contentTabSwitcherPresentation?.candidateIDs,
            ids("focus-B", "focus-A"),
        )
        XCTAssertEqual(store.state.contentTabSwitcherPresentation?.focusedCandidateID, id("focus-B"))
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: store.state.contentTabs,
        ) else {
            return XCTFail("Expected content rows")
        }
        XCTAssertEqual(rows.first(where: { $0.isCurrent })?.id, id("focus-B"))

        await store.send(.request(.moveContentTabSwitcherFocus(direction: .next))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("focus-B", "focus-A"),
                focusedCandidateID: id("focus-A"),
            )
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)

        await store.send(.request(.moveContentTabSwitcherFocus(direction: .next))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("focus-B", "focus-A"),
                focusedCandidateID: id("focus-B"),
            )
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 이전 방향 focus도 후보 ID 기준으로 wrap한다.
    /// previous가 첫 후보에서 마지막 후보로 이동하고 Content Tab 의미 상태를 보존하는지 검증한다.
    /// - 검증 내용: reverse wrap과 Current/focus 분리
    /// - 사전 조건: active B와 MRU `[B, A]`인 two-tab window
    /// - 기대 결과: focus만 B↔A로 이동하고 active/MRU/selection/page/pane snapshot은 동일하다.
    @MainActor
    func testPreviousFocusNavigationWrapsWithoutMutatingContentTabState() async {
        let initialState = makeSwitcherWindowState(prefix: "reverse")
        let semanticSnapshot = ContentTabSemanticSnapshot(initialState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic, contentTabs: $0.contentTabs)
        }
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .previous))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("reverse-B", "reverse-A"),
                focusedCandidateID: id("reverse-A"),
            )
        }
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .previous))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("reverse-B", "reverse-A"),
                focusedCandidateID: id("reverse-B"),
            )
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 단일 후보와 status presentation은 focus를 이동하지 않는다.
    /// zero/one 후보와 loading/error presentation이 안정적인 no-op 경계를 지키는지 검증한다.
    /// - 검증 내용: single candidate, loading, error focus nil
    /// - 사전 조건: one live candidate 또는 status presentation
    /// - 기대 결과: presentation이 바뀌지 않고 focus가 nil로 유지된다.
    @MainActor
    func testFocusNavigationNoOpForSingleAndStatusPresentations() async throws {
        let emptyPresentation = FileManagerContentTabSwitcherPresentation(
            source: .automatic,
            contentTabs: makeState(tabs: [], active: nil, mru: ["stale"]),
        )
        XCTAssertEqual(emptyPresentation.candidateIDs, [])
        XCTAssertNil(emptyPresentation.focusedCandidateID)

        var singleWindowState = makeSwitcherWindowState(prefix: "single-window")
        singleWindowState.contentTabs = makeState(
            tabs: [tab("single")],
            active: "single",
            mru: ["single"],
        )
        let singleStore = TestStore(initialState: singleWindowState) {
            FileManagerFeature()
        }
        await singleStore.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                contentTabs: $0.contentTabs,
            )
        }
        let singlePresentation = try XCTUnwrap(singleStore.state.contentTabSwitcherPresentation)
        await singleStore.send(.request(.moveContentTabSwitcherFocus(direction: .next)))
        XCTAssertEqual(singleStore.state.contentTabSwitcherPresentation, singlePresentation)

        await singleStore.send(.request(.presentContentTabSwitcher(source: .error(message: "Failure")))) {
            $0.contentTabSwitcherPresentation = .init(source: .error(message: "Failure"))
        }
        XCTAssertNil(singleStore.state.contentTabSwitcherPresentation?.focusedCandidateID)

        let loadingWindowState = makeSwitcherWindowState(prefix: "loading")
        let loadingStore = TestStore(initialState: loadingWindowState) {
            FileManagerFeature()
        }
        await loadingStore.send(.request(.presentContentTabSwitcher(source: .loading))) {
            $0.contentTabSwitcherPresentation = .init(source: .loading)
        }
        let loadingPresentation = try XCTUnwrap(loadingStore.state.contentTabSwitcherPresentation)
        await loadingStore.send(.request(.moveContentTabSwitcherFocus(direction: .next)))
        XCTAssertEqual(loadingStore.state.contentTabSwitcherPresentation, loadingPresentation)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: live 후보 갱신은 삭제된 focus를 이전 위치로 복구한다.
    /// child close가 presentation snapshot과 focus를 함께 최신 projection으로 수렴시키는지 검증한다.
    /// - 검증 내용: 중간 삭제 successor, 끝 삭제 last candidate, empty projection, semantic snapshot 불변
    /// - 사전 조건: `[A, B, C]` candidate snapshot에서 B 또는 C를 닫는 두 개의 독립 window
    /// - 기대 결과: B 삭제는 C, C 삭제는 B, 마지막 후보 삭제는 nil focus와 empty surface이다.
    @MainActor
    func testLiveCandidateRefreshRepairsRemovedFocusByPriorPosition() async {
        var middleState = makeSwitcherWindowState(prefix: "repair-middle")
        let middleC = id("repair-middle-C")
        middleState.contentTabs.activeTabID = id("repair-middle-A")
        middleState.contentTabs.tabs.append(tab(middleC.rawValue))
        middleState.contentTabs.recentlyUsedTabIDs = ids("repair-middle-A", "repair-middle-B", "repair-middle-C")
        middleState.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("repair-middle-A", "repair-middle-B", "repair-middle-C"),
            focusedCandidateID: id("repair-middle-B"),
        )
        let middleStore = TestStore(initialState: middleState) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        middleStore.exhaustivity = .off // child close lifecycle action은 focus reconciliation 범위 밖이다.

        await middleStore.send(.contentTabs(.commitClose(id("repair-middle-B"))))
        await middleStore.finish()

        XCTAssertEqual(
            middleStore.state.contentTabSwitcherPresentation,
            .init(
                source: .automatic,
                candidateIDs: ids("repair-middle-A", "repair-middle-C"),
                focusedCandidateID: middleC,
            ),
        )
        XCTAssertEqual(middleStore.state.contentTabs.activeTabID, id("repair-middle-A"))
        XCTAssertEqual(
            middleStore.state.contentTabs.recentlyUsedTabIDs,
            ids("repair-middle-A", "repair-middle-B", "repair-middle-C"),
        )
        let middleSemanticBeforeReconciliation = ContentTabSemanticSnapshot(middleStore.state)
        await middleStore.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(
            ContentTabSemanticSnapshot(middleStore.state),
            middleSemanticBeforeReconciliation,
        )

        var endState = makeSwitcherWindowState(prefix: "repair-end")
        let endC = id("repair-end-C")
        endState.contentTabs.tabs.append(tab(endC.rawValue))
        endState.contentTabs.recentlyUsedTabIDs = ids("repair-end-A", "repair-end-B", "repair-end-C")
        endState.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("repair-end-A", "repair-end-B", "repair-end-C"),
            focusedCandidateID: endC,
        )
        let endStore = TestStore(initialState: endState) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        endStore.exhaustivity = .off // child close lifecycle action은 focus reconciliation 범위 밖이다.

        await endStore.send(.contentTabs(.commitClose(endC)))
        await endStore.finish()

        XCTAssertEqual(
            endStore.state.contentTabSwitcherPresentation,
            .init(
                source: .automatic,
                candidateIDs: ids("repair-end-A", "repair-end-B"),
                focusedCandidateID: id("repair-end-B"),
            ),
        )
        let endSemanticBeforeReconciliation = ContentTabSemanticSnapshot(endStore.state)
        await endStore.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(endStore.state), endSemanticBeforeReconciliation)

        var emptyWindowState = FileManagerWindowState()
        emptyWindowState.contentTabs = makeState(tabs: [], active: nil, mru: ["stale"])
        emptyWindowState.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("repair-empty-A"),
            focusedCandidateID: id("repair-empty-A"),
        )
        let emptyStore = TestStore(initialState: emptyWindowState) {
            FileManagerFeature()
        }
        await emptyStore.send(.contentTabs(.toggleSelection(id("repair-empty-A")))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic)
        }
        XCTAssertEqual(emptyStore.state.contentTabSwitcherPresentation, .init(source: .automatic))
        XCTAssertEqual(
            ContentTabSwitcherViewState.make(source: .automatic, contentTabs: emptyStore.state.contentTabs),
            .empty(.init(message: "No recent tabs", accessibilityLabel: "No recent tabs")),
        )
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: live identity와 metadata/MRU 변화가 focus를 점프시키지 않는다.
    /// 최신 projection 순서가 바뀌어도 살아 있는 focused ID와 전체 semantic snapshot을 보존하는지 검증한다.
    /// - 검증 내용: metadata update, MRU reorder, focus identity retention
    /// - 사전 조건: focus C인 `[A, B, C]` snapshot과 active A
    /// - 기대 결과: metadata/MRU 변경 후에도 focus C가 유지되고 reconciliation이 semantic state를 추가 변경하지 않는다.
    @MainActor
    func testLiveCandidateRefreshRetainsIdentityAcrossMetadataAndMRUReorder() async {
        var state = makeSwitcherWindowState(prefix: "retain")
        let tabC = id("retain-C")
        state.contentTabs.tabs.append(tab(tabC.rawValue))
        state.contentTabs.recentlyUsedTabIDs = ids("retain-A", "retain-B", "retain-C")
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("retain-A", "retain-B", "retain-C"),
            focusedCandidateID: tabC,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off // anchor 변경의 부수 effect는 focus reconciliation 범위 밖이다.

        await store.send(.contentTabs(.updateRuntimePageAnchor(
            id("retain-B"),
            .directory(path: "/retain/updated"),
        )))
        await store.finish()

        XCTAssertEqual(store.state.contentTabSwitcherPresentation?.focusedCandidateID, tabC)
        XCTAssertEqual(
            store.state.contentTabSwitcherPresentation?.candidateIDs,
            ids("retain-A", "retain-B", "retain-C"),
        )
        XCTAssertEqual(store.state.contentTabs.activeTabID, id("retain-B"))
        XCTAssertEqual(store.state.contentTabs.recentlyUsedTabIDs, ids("retain-A", "retain-B", "retain-C"))
        XCTAssertEqual(store.state.contentTabSwitcherPresentation?.candidateIDs.contains(tabC), true)
        let semanticBeforeReconciliation = ContentTabSemanticSnapshot(store.state)
        await store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticBeforeReconciliation)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: stale focus navigation은 old snapshot 방향의 live
    /// neighbor를 고른다.
    /// 제거된 B가 남은 `[A, C]` 사이에서 next는 C, previous는 A를 선택하는지 검증한다.
    /// - 검증 내용: stale focus next/previous, wrong-neighbor adversarial distinction, atomic snapshot update
    /// - 사전 조건: old `[A, B, C]`, stale focus B, live `[A, C]`
    /// - 기대 결과: next/previous가 각각 방향에 맞는 neighbor를 선택하고 focus는 live IDs 안에 있다.
    @MainActor
    func testStaleFocusNavigationUsesDirectionCorrectLiveNeighbor() async {
        for (direction, expectedFocus) in [
            (ContentTabSwitcherFocusDirection.next, id("stale-C")),
            (.previous, id("stale-D")),
        ] {
            var state = makeSwitcherWindowState(prefix: "stale")
            state.contentTabs.tabs.append(contentsOf: [tab("stale-D"), tab("stale-C")])
            state.contentTabs.recentlyUsedTabIDs = ids("stale-A", "stale-D", "stale-C")
            state.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("stale-A", "stale-D", "stale-B", "stale-C"),
                focusedCandidateID: id("stale-B"),
            )
            let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
                $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            }
            store.exhaustivity = .off // focus command는 semantic effect를 내지 않는다.

            await store.send(.request(.moveContentTabSwitcherFocus(direction: direction)))

            XCTAssertEqual(
                store.state.contentTabSwitcherPresentation?.candidateIDs,
                ids("stale-A", "stale-D", "stale-C"),
            )
            XCTAssertEqual(store.state.contentTabSwitcherPresentation?.focusedCandidateID, expectedFocus)
            XCTAssertEqual(store.state.contentTabSwitcherPresentation?.candidateIDs.contains(expectedFocus), true)
        }
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: rapid close/reorder/navigation은 focus를 항상 live 범위로
    /// 유지한다.
    /// 연속 child mutation과 양방향 navigation 사이에서 presentation snapshot과 focus의 원자적 수렴을 검증한다.
    /// - 검증 내용: close, reorder, next, previous, close-to-empty sequence
    /// - 사전 조건: 네 개의 live candidate와 첫 후보 focus
    /// - 기대 결과: 각 transition 뒤 focus가 nil 또는 최신 candidateIDs 내부이며 sequence가 deterministic이다.
    @MainActor
    func testRapidCandidateRefreshSequenceRemainsDeterministicAndInBounds() async {
        var state = makeSwitcherWindowState(prefix: "rapid")
        state.contentTabs.tabs.append(contentsOf: [tab("rapid-C"), tab("rapid-D")])
        state.contentTabs.recentlyUsedTabIDs = ids("rapid-A", "rapid-B", "rapid-C", "rapid-D")
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("rapid-A", "rapid-B", "rapid-C", "rapid-D"),
            focusedCandidateID: id("rapid-B"),
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off // sequence의 close lifecycle effect는 focus 범위 밖이다.

        await store.send(.contentTabs(.close(id("rapid-B"))))
        await store.send(.contentTabs(.reorder(
            sourceID: id("rapid-D"),
            targetID: id("rapid-A"),
            placement: .before,
        )))
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .next)))
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .previous)))
        await store.finish()

        let presentation = store.state.contentTabSwitcherPresentation
        XCTAssertEqual(presentation?.candidateIDs, ids("rapid-C", "rapid-A", "rapid-D"))
        XCTAssertEqual(presentation.map { $0.candidateIDs.contains($0.focusedCandidateID ?? id("missing")) }, true)
        let semanticBeforeReconciliation = ContentTabSemanticSnapshot(store.state)
        await store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticBeforeReconciliation)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 모든 recent-tab transaction busy 상태에서 표시를 차단한다.
    /// VOY-464 admission 경계를 공유해 topology transaction 중 presentation도 끼어들지 않는지 검증한다.
    /// - 검증 내용: 열한 busy guard 각각의 whole-window no-op과 action/effect/feedback 부재
    /// - 사전 조건: two-tab window에 각 busy sentinel을 하나씩 독립 적용
    /// - 기대 결과: 모든 subcase에서 presentation을 포함한 전체 window state가 동일하다.
    @MainActor
    func testPresentationIsBlockedByEveryRecentTabTransaction() async {
        let tabID = ContentTabID(rawValue: "busy-B")
        let requestID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 66))
        let ownerID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 67))
        let subcases = busyCloseAndPinSubcases(tabID: tabID, requestID: requestID, ownerID: ownerID)
            + busyTopologySubcases(tabID: tabID, requestID: requestID, ownerID: ownerID)

        for (name, applyBusyState) in subcases {
            var state = makeSwitcherWindowState(prefix: "busy")
            applyBusyState(&state)
            let alerts = LockIsolated(0)
            let store = TestStore(initialState: state) {
                FileManagerFeature()
            } withDependencies: {
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in
                    alerts.withValue { $0 += 1 }
                }
            }

            await store.send(.request(.presentContentTabSwitcher(source: .automatic)))

            XCTAssertEqual(store.state, state, name)
            XCTAssertEqual(alerts.value, 0, name)
            print("BUSY_SUBCASE \(name) PASS")
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
}

private func assertFocusedCandidateViewContract(
    presentationSource: String,
    viewSource: String,
    rows: [ContentTabSwitcherViewState.Row],
    focusedCurrentRows: [ContentTabSwitcherViewState.Row],
    contentTabs: ContentTabState,
    contentTabsBeforeFocus: ContentTabState,
) throws {
    let focusedRow = try XCTUnwrap(rows.first(where: { $0.id == id("candidate") }))
    let currentRow = try XCTUnwrap(rows.first(where: { $0.id == id("current") }))
    let focusedCurrentRow = try XCTUnwrap(focusedCurrentRows.first(where: { $0.id == id("current") }))
    let nonCurrentRow = try XCTUnwrap(focusedCurrentRows.first(where: { $0.id == id("candidate") }))

    XCTAssertTrue(presentationSource.contains("let isFocused: Bool"))
    XCTAssertTrue(viewSource.contains("@FocusState private var focusedRowID: ContentTabID?"))
    XCTAssertTrue(viewSource.contains(".focused(focusedRowID, equals: row.id)"))
    XCTAssertTrue(viewSource.contains("focusEffectDisabled()"))
    XCTAssertTrue(viewSource.contains(".focusSection()"))
    XCTAssertTrue(viewSource.contains("VStack(alignment: .center"))
    XCTAssertTrue(viewSource.contains("multilineTextAlignment(.center)"))
    XCTAssertFalse(viewSource.contains("row.pageLabel"))
    XCTAssertFalse(viewSource.contains("row.anchorSummary"))
    XCTAssertTrue(viewSource.contains(".onChange(of: focusRenderState)"))
    XCTAssertTrue(viewSource.contains("rowIDs: rowIDs"))
    XCTAssertFalse(viewSource.contains(".onChange(of: focusedRowID)"))
    XCTAssertFalse(viewSource.contains("@FocusState private var isSwitcherFocused"))
    XCTAssertTrue(viewSource.contains("row.isFocused"))
    XCTAssertTrue(viewSource.contains("VoyagerDS.BrandPrimaryColor.c500"))
    XCTAssertTrue(focusedRow.isFocused && !focusedRow.isCurrent)
    XCTAssertTrue(!currentRow.isFocused && currentRow.isCurrent)
    XCTAssertEqual(focusedRow.accessibilityIdentifier, "file-manager.content-tab-switcher.row.candidate")
    XCTAssertEqual(focusedRow.accessibilityLabel, "Focused Candidate")
    XCTAssertEqual(focusedRow.accessibilityValue, "Home; Home")
    XCTAssertEqual(currentRow.accessibilityIdentifier, "file-manager.content-tab-switcher.row.current")
    XCTAssertEqual(currentRow.accessibilityLabel, "Current Tab")
    XCTAssertEqual(currentRow.accessibilityValue, "Home; Home; Current")
    XCTAssertTrue(rows.allSatisfy(\.isIconAccessibilityHidden))

    XCTAssertTrue(focusedCurrentRow.isFocused && focusedCurrentRow.isCurrent)
    XCTAssertFalse(nonCurrentRow.isFocused || nonCurrentRow.isCurrent)
    XCTAssertEqual(
        [focusedCurrentRow.accessibilityIdentifier, focusedCurrentRow.accessibilityLabel,
         focusedCurrentRow.accessibilityValue],
        [currentRow.accessibilityIdentifier, currentRow.accessibilityLabel, currentRow.accessibilityValue],
    )
    XCTAssertNotEqual(rows.map(\.isFocused), focusedCurrentRows.map(\.isFocused))
    XCTAssertEqual(rows.map(\.id), focusedCurrentRows.map(\.id))
    XCTAssertEqual(rows.map(\.title), focusedCurrentRows.map(\.title))
    XCTAssertEqual(rows.map(\.accessibilityValue), focusedCurrentRows.map(\.accessibilityValue))
    XCTAssertEqual(contentTabs.tabs, contentTabsBeforeFocus.tabs)
    XCTAssertEqual(contentTabs.activeTabID, contentTabsBeforeFocus.activeTabID)
    XCTAssertEqual(contentTabs.recentlyUsedTabIDs, contentTabsBeforeFocus.recentlyUsedTabIDs)
    XCTAssertEqual(contentTabs.selectedTabIDs, contentTabsBeforeFocus.selectedTabIDs)

    let statusStates = [
        ContentTabSwitcherViewState.make(source: .loading, contentTabs: contentTabs),
        ContentTabSwitcherViewState.make(source: .error(message: "Host failure"), contentTabs: contentTabs),
        ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: makeState(tabs: [], active: nil, mru: []),
        ),
    ]
    XCTAssertFalse(statusStates.contains { state in
        if case .content = state { return true }
        return false
    })

    let rowSource = viewSource.components(separatedBy: "private struct SwitcherRow: View").last ?? ""
    for forbiddenToken in ["Button(", ".onTapGesture", ".onHover", "onActivate", "selection"] {
        XCTAssertFalse(rowSource.contains(forbiddenToken), forbiddenToken)
    }
    for forbiddenToken in ["setCurrent", "moveContentTabSwitcherFocus", ".send("] {
        XCTAssertFalse(viewSource.contains(forbiddenToken), forbiddenToken)
    }
}

private struct ContentTabSemanticSnapshot: Equatable {
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

private typealias BusyPresentationSubcase = (String, (inout FileManagerWindowState) -> Void)

private func busyCloseAndPinSubcases(
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

private func busyTopologySubcases(
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

private func id(_ rawValue: String) -> ContentTabID {
    ContentTabID(rawValue: rawValue)
}

private func ids(_ rawValues: String...) -> [ContentTabID] {
    rawValues.map(id)
}

private func tab(
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

private func makeState(
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

private func makeSwitcherWindowState(prefix: String) -> FileManagerWindowState {
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
