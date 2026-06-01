import AppKit
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FMW001WindowFrameAutosaveTests: XCTestCase {
    /// 저장된 autosave frame이 있어도 실행 중 새 창은 현재 File Manager Window 크기를 우선 적용해야 함을 검증.
    func testApplyInitialFramePrefersProvidedWindowSizeOverAutosave() {
        let autosaveName = NSWindow.FrameAutosaveName("VoyagerMainWindow")
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let storedWindow = NSWindow(contentViewController: NSViewController())
        storedWindow.setFrame(NSRect(x: 0, y: 0, width: 960, height: 510), display: false)
        storedWindow.saveFrame(usingName: autosaveName)

        let window = NSWindow(contentViewController: NSViewController())
        FileManagerWindowChrome.configureWindowStyle(window)

        FileManagerWindowChrome.applyInitialFrame(
            window,
            initialWindowSizeProvider: { NSSize(width: 1180, height: 720) },
            reservesSidebarWidth: false,
        )

        XCTAssertEqual(window.frame.width, 1180, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, 720, accuracy: 0.5)
    }
}
