import AppKit
import ComposableArchitecture
import SwiftUI
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class FMW002SidebarSurfaceTests: XCTestCase {
    // MARK: - FMW-002-adjust_sidebar_width

    /// FMW-002-adjust_sidebar_width: 실제 Sidebar hosting surface는 background window drag를 거부한다.
    /// split layout이 hit-tested hosting view를 첫 arranged subview와 sidebarSurface로 함께 소유하는지 검증한다.
    /// - 검증 내용: SidebarHostingView 타입, mouseDownCanMoveWindow false, arranged/sidebar identity.
    /// - 사전 조건: 기본 FileManager store와 실제 FileManagerWindowSplitLayout 조립 경로가 있다.
    /// - 기대 결과: Sidebar만 window background movement에서 제외되고 동일 surface가 width sync 기준으로 유지된다.
    func testSidebarHostingSurfaceOwnsHitTestingAndRejectsBackgroundWindowMovement() {
        let store = Store(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        }
        let focusCoordinator = FileManagerKeyCommandFocusCoordinator()
        let components = FileManagerWindowSplitLayout.build(
            store: store,
            workspaceClient: .testValue,
            keyCommandFocusCoordinator: focusCoordinator,
            mainContainerRootView: FileManagerWindowMainContainerView(
                store: store,
                isDark: false,
                materialOverride: nil,
                keyCommandFocusCoordinator: focusCoordinator,
            ),
            materialOverride: nil,
            contentVerticalMargin: 4,
            isSidebarVisible: true,
        )

        XCTAssertIdentical(components.sidebarSurface, components.sidebarHosting.view)
        XCTAssertIdentical(components.splitView.arrangedSubviews.first, components.sidebarSurface)
        XCTAssertTrue(components.sidebarSurface is SidebarHostingView)
        XCTAssertFalse(components.sidebarSurface.mouseDownCanMoveWindow)
    }

    /// FMW-002-adjust_sidebar_width: 투명 surface가 실제 Sidebar pane의 visibility 기준이다.
    /// hosted content는 arranged subview가 아니므로 collapse 판정 대상으로 허용하지 않는다.
    func test_sidebarSurfaceIsClearVisibilityTarget() {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarSurface = NSView()
        sidebarSurface.wantsLayer = true
        sidebarSurface.layer?.backgroundColor = NSColor.clear.cgColor
        let hostedContent = NSView()
        hostedContent.frame = NSRect(x: 0, y: 0, width: 250, height: 400)
        sidebarSurface.addSubview(hostedContent)
        splitView.addArrangedSubview(sidebarSurface)
        splitView.addArrangedSubview(NSView())
        splitView.setPosition(250, ofDividerAt: 0)
        splitView.adjustSubviews()

        XCTAssertFalse(sidebarSurface is NSVisualEffectView)
        XCTAssertEqual(sidebarSurface.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertTrue(FileManagerSidebarSync.isSidebarEffectivelyVisible(
            splitView: splitView,
            sidebarView: sidebarSurface,
        ))
        XCTAssertFalse(FileManagerSidebarSync.isSidebarEffectivelyVisible(
            splitView: splitView,
            sidebarView: hostedContent,
        ))
    }

    func test_rootShellOwnsWindowMaterialAndContentRemainsClear() {
        let shellBackground = VoyagerDS.SurfaceMaterialRole.windowShell.makeBackgroundView()
        XCTAssertEqual(shellBackground.material, .headerView)
        XCTAssertEqual(shellBackground.blendingMode, .behindWindow)
        XCTAssertEqual(shellBackground.state, .followsWindowActiveState)
        XCTAssertEqual(shellBackground.alphaValue, 1.0)

        let components = FileManagerWindowMainContainerLayout.build(
            contentRootView: AnyView(EmptyView()),
        )
        XCTAssertFalse(components.containerView is NSVisualEffectView)
        XCTAssertEqual(components.containerView.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertEqual(components.containerView.layer?.cornerRadius, VoyagerDS.Radius.contentPane)
        XCTAssertEqual(components.containerView.layer?.masksToBounds, true)

        FileManagerWindowMainContainerLayout.applyAppearance(
            splitView: components.splitView,
            containerView: components.containerView,
            contentView: components.contentHosting.view,
            inspectorView: nil,
            isDark: true,
        )
        XCTAssertEqual(components.containerView.layer?.backgroundColor, NSColor.clear.cgColor)
    }
}
