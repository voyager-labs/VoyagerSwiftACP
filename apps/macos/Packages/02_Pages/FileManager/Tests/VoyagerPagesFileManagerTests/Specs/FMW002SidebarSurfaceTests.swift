import AppKit
import SwiftUI
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class FMW002SidebarSurfaceTests: XCTestCase {
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
        XCTAssertEqual(shellBackground.material, .underWindowBackground)
        XCTAssertEqual(shellBackground.blendingMode, .behindWindow)
        XCTAssertEqual(shellBackground.state, .followsWindowActiveState)
        XCTAssertEqual(shellBackground.alphaValue, 0.82)

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

    func test_fixedLocationIconRequiresNonZeroDimensions() {
        XCTAssertFalse(isValidFixedLocationIcon(NSImage(size: .zero)))
        XCTAssertFalse(isValidFixedLocationIcon(NSImage(size: NSSize(width: 1, height: 0))))
        XCTAssertTrue(isValidFixedLocationIcon(NSImage(size: NSSize(width: 1, height: 1))))
    }
}
