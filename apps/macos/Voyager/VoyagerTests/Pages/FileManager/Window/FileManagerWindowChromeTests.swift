import AppKit
@preconcurrency import Combine
import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import XCTest

/// FileManagerWindowChrome — 윈도우 크롬(타이틀바, 트래픽 라이트, 사이드바 폭) 설정이
/// Coordinator 전달과 일관되게 동작하는지 검증하는 테스트 모음.
/// 윈도우 외관 설정이 깨지면 사용자에게 즉시 노출되므로 회귀 방지가 중요하다.
@MainActor
final class FileManagerWindowChromeTests: XCTestCase {
    /// 기본 윈도우 스타일 적용 후 닫기/최소화/확대 버튼이 숨겨지지 않았는지 확인.
    func testTrafficLightsNotHiddenAfterBaseConfiguration() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        XCTAssertFalse(window.standardWindowButton(.closeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
    }

    /// 사이드바가 보일 때 트래픽 라이트가 항상 표시되어야 함을 검증.
    func testTrafficLightsVisibleWhenSidebarVisible() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        FileManagerWindowCoordinator.applyTrafficLightVisibility(to: window, isSidebarVisible: true)
        XCTAssertFalse(window.standardWindowButton(.closeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
    }

    /// 사이드바가 숨겨지면 트래픽 라이트도 함께 숨겨야 함을 검증.
    func testTrafficLightsHiddenWhenSidebarHidden() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        FileManagerWindowCoordinator.applyTrafficLightVisibility(to: window, isSidebarVisible: false)
        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden ?? false)
    }

    /// 타이틀 가시성이 hidden, titlebarAppearsTransparent가 true로 설정되었는지 확인.
    func testTitleBarStyleIsConfiguredCorrectly() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
    }

    // MARK: - FileManagerWindowChrome 직접 전달

    /// FileManagerWindowChrome이 Coordinator와 동일한 스타일 설정(styleMask, minSize 등)을 생성하는지 검증.
    func testChromeConfigureWindowStyleMatchesCoordinatorForwarding() {
        let window1 = NSWindow(contentViewController: NSViewController())
        let window2 = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.configureWindowStyle(window1)
        FileManagerWindowCoordinator.configureWindowStyle(window2)

        XCTAssertEqual(window1.styleMask, window2.styleMask)
        XCTAssertEqual(window1.minSize, window2.minSize)
        XCTAssertEqual(window1.titleVisibility, window2.titleVisibility)
        XCTAssertEqual(window1.titlebarAppearsTransparent, window2.titlebarAppearsTransparent)
        XCTAssertEqual(window1.isMovableByWindowBackground, window2.isMovableByWindowBackground)
        XCTAssertEqual(window1.tabbingIdentifier, window2.tabbingIdentifier)
    }

    /// FileManagerWindowChrome의 트래픽 라이트 가시성 설정이 Coordinator 결과와 동일한지 검증.
    func testChromeApplyTrafficLightVisibilityMatchesCoordinatorForwarding() {
        let window1 = NSWindow(contentViewController: NSViewController())
        let window2 = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.applyTrafficLightVisibility(to: window1, isSidebarVisible: false)
        FileManagerWindowCoordinator.applyTrafficLightVisibility(to: window2, isSidebarVisible: false)

        XCTAssertEqual(
            window1.standardWindowButton(.closeButton)?.isHidden,
            window2.standardWindowButton(.closeButton)?.isHidden,
        )
        XCTAssertEqual(
            window1.standardWindowButton(.miniaturizeButton)?.isHidden,
            window2.standardWindowButton(.miniaturizeButton)?.isHidden,
        )
        XCTAssertEqual(
            window1.standardWindowButton(.zoomButton)?.isHidden,
            window2.standardWindowButton(.zoomButton)?.isHidden,
        )
    }

    /// visible sidebar로 시작하는 창은 초기 프레임에 sidebar 최소 폭을 추가로 확보해야 함을 검증.
    func testChromeMinimumInitialWidthReservesVisibleSidebarWidth() {
        XCTAssertEqual(
            FileManagerWindowChrome.minimumInitialWidth(reservesSidebarWidth: true),
            600 + FileManagerSidebarSync.sidebarMinWidth,
        )
        XCTAssertEqual(FileManagerWindowChrome.minimumInitialWidth(reservesSidebarWidth: false), 600)
    }

    /// 저장된/제공된 초기 창 크기가 sidebar 포함 최소 폭보다 작으면 보정되는지 검증.
    func testChromeConstrainedInitialSizeIncludesSidebarMinimumWidth() {
        let constrainedSize = FileManagerWindowChrome.constrainedInitialSize(
            NSSize(width: 600, height: 300),
            minimumWidth: FileManagerWindowChrome.minimumInitialWidth(reservesSidebarWidth: true),
            minimumHeight: 350,
        )

        XCTAssertEqual(constrainedSize.width, 600 + FileManagerSidebarSync.sidebarMinWidth)
        XCTAssertEqual(constrainedSize.height, 350)
    }

    /// 실제 초기 프레임 적용 시 sidebar visible 상태면 창 폭이 sidebar 최소 폭만큼 확보되는지 검증.
    func testChromeApplyInitialFrameReservesVisibleSidebarWidth() {
        let window = NSWindow(contentViewController: NSViewController())
        FileManagerWindowChrome.configureWindowStyle(window)

        FileManagerWindowChrome.applyInitialFrame(
            window,
            initialWindowSizeProvider: { NSSize(width: 600, height: 300) },
            reservesSidebarWidth: true,
        )

        XCTAssertGreaterThanOrEqual(
            window.frame.width,
            FileManagerWindowChrome.minimumInitialWidth(reservesSidebarWidth: true) - 0.5,
        )
        XCTAssertGreaterThanOrEqual(window.frame.height, window.minSize.height)
    }

    // MARK: - FileManagerWindowChrome.makeTitle

    /// 컬렉션 이름이 존재하면 makeTitle이 해당 이름을 반환하는지 검증.
    func testChromeMakeTitleReturnsCollectionNameWhenPresent() {
        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: "My Collection",
            isCollectionMode: false,
            titlePath: "/Users/test",
            makeWindowTitle: { $0 },
        )
        XCTAssertEqual(title, "My Collection")
    }

    /// 컬렉션 모드에서 열린 컬렉션이 없으면 "New Collection"을 반환하는지 검증.
    func testChromeMakeTitleReturnsNewCollectionWhenCollectionMode() {
        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: nil,
            isCollectionMode: true,
            titlePath: "/Users/test",
            makeWindowTitle: { $0 },
        )
        XCTAssertEqual(title, "New Collection")
    }

    /// 일반 폴더 경로에서 makeWindowTitle 클로저를 통해 윈도우 제목이 생성되는지 검증.
    func testChromeMakeTitleReturnsWindowTitleForFolderPath() {
        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: nil,
            isCollectionMode: false,
            titlePath: "/Users/test/Documents",
            makeWindowTitle: { "Display: \($0)" },
        )
        XCTAssertEqual(title, "Display: /Users/test/Documents")
    }

    // MARK: - FileManagerContentChromePropsBuilder

    /// 콘텐츠 크롬 속성 빌더가 컴퓨터 이름을 비어있지 않은 문자열로 생성하는지 확인.
    func testContentChromePropsBuilderProducesComputerName() {
        let state = FileManagerFeature.State()
        let props = FileManagerContentChromePropsBuilder.makeContentChromeProps(
            from: state,
            fileManagerClient: .previewValue,
        )
        XCTAssertFalse(props.computerName.isEmpty)
    }

    /// Composer가 표시 중일 때 오버레이 속성이 이를 반영하는지 검증.
    func testContentOverlayPropsBuilderReflectsComposerState() {
        var state = FileManagerFeature.State()
        state.content.composer.isPresented = true
        let props = FileManagerContentChromePropsBuilder.makeContentOverlayProps(from: state)
        XCTAssertTrue(props.isComposerPresented)
    }

    /// 기본 상태에서는 오버레이 속성이 Composer 미표시를 반영하는지 검증.
    func testContentOverlayPropsBuilderDefaultNoComposer() {
        let state = FileManagerFeature.State()
        let props = FileManagerContentChromePropsBuilder.makeContentOverlayProps(from: state)
        XCTAssertFalse(props.isComposerPresented)
    }

    // MARK: - FileManagerSidebarSync

    /// 사이드바 초기 폭이 상한을 초과하면 clamping되는지 검증.
    func testSidebarSyncClampsInitialWidth() {
        let sync = FileManagerSidebarSync(storeSidebarWidth: 500)
        XCTAssertLessThanOrEqual(sync.currentSidebarWidth, FileManagerSidebarSync.sidebarMaxWidth)
    }

    /// 사이드바 폭이 하한 미만이면 최소값으로 clamping되는지 검증.
    func testSidebarSyncClampsBelowMinWidth() {
        let sync = FileManagerSidebarSync(storeSidebarWidth: 10)
        XCTAssertGreaterThanOrEqual(sync.currentSidebarWidth, FileManagerSidebarSync.sidebarMinWidth)
    }

    /// visible 상태에서 잘못 저장된 0 폭을 초기 레이아웃 최소 폭으로 보정하는지 검증.
    func testSidebarSyncInitialLayoutClampsInvalidStoredWidthToMinimum() {
        var sync = FileManagerSidebarSync(storeSidebarWidth: 0)
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarView = NSView()
        let contentView = NSView()
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        var trafficLightUpdates: [Bool] = []
        sync.applyInitialLayoutIfNeeded(
            sidebarVisible: true,
            sidebarWidth: 0,
            splitView: splitView,
            mainContainerLeading: nil,
            contentVerticalMargin: 4,
        ) { isSidebarVisible in
            trafficLightUpdates.append(isSidebarVisible)
        }

        XCTAssertGreaterThanOrEqual(sidebarView.frame.width, FileManagerSidebarSync.sidebarMinWidth - 0.5)
        XCTAssertTrue(FileManagerSidebarSync.isSidebarEffectivelyVisible(
            splitView: splitView,
            sidebarView: sidebarView,
        ))
        XCTAssertTrue(sync.currentSidebarVisible ?? false)
        XCTAssertEqual(trafficLightUpdates, [true])
    }

    /// 초기화/자동 resize 중 sidebar가 최소 폭 미만이면 false 저장 대신 복구 요청을 반환하는지 검증.
    func testSidebarSyncAutomaticResizeBelowMinimumRequestsRestoreWithoutHiding() {
        var sync = FileManagerSidebarSync(storeSidebarWidth: 220)
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarView = NSView()
        let contentView = NSView()
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        sync.applyInitialLayoutIfNeeded(
            sidebarVisible: true,
            sidebarWidth: 220,
            splitView: splitView,
            mainContainerLeading: nil,
            contentVerticalMargin: 4,
        ) { _ in }

        splitView.setPosition(FileManagerSidebarSync.sidebarMinWidth - 1, ofDividerAt: 0)
        splitView.adjustSubviews()

        var syncedWidths: [CGFloat] = []
        let decision = sync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: true,
            isUserInitiatedCollapse: false,
        ) { width in
            syncedWidths.append(width)
        }

        XCTAssertEqual(decision, .restoreSidebar)
        XCTAssertTrue(syncedWidths.isEmpty)
    }

    /// 사용자가 최소 폭 아래로 사이드바를 접으면 폭을 0으로 저장하지 않고 숨김 전환을 요청하는지 검증.
    func testSidebarSyncUserResizeBelowMinimumRequestsHideWithoutStoringZeroWidth() {
        var sync = FileManagerSidebarSync(storeSidebarWidth: 220)
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarView = NSView()
        let contentView = NSView()
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        sync.applyInitialLayoutIfNeeded(
            sidebarVisible: true,
            sidebarWidth: 220,
            splitView: splitView,
            mainContainerLeading: nil,
            contentVerticalMargin: 4,
        ) { _ in }

        splitView.setPosition(FileManagerSidebarSync.sidebarMinWidth - 1, ofDividerAt: 0)
        splitView.adjustSubviews()

        var syncedWidths: [CGFloat] = []
        let decision = sync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: true,
            isUserInitiatedCollapse: true,
        ) { width in
            syncedWidths.append(width)
        }

        XCTAssertEqual(decision, .hideSidebar)
        XCTAssertTrue(syncedWidths.isEmpty)
        XCTAssertFalse(FileManagerSidebarSync.isSidebarEffectivelyVisible(
            splitView: splitView,
            sidebarView: sidebarView,
        ))
    }
}
