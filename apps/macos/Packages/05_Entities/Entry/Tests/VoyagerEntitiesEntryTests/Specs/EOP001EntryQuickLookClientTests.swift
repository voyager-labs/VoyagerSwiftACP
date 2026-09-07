import Foundation
import QuickLookUI
@testable import VoyagerEntitiesEntry
import XCTest

/// Quick Look 패널이 보이는 동안 앱의 entry 선택이 바뀌면 미리보기 대상을 동기화하는
/// `EntryQuickLookClient.syncQuickLookSelection` 계약을 검증한다.
///
/// `makeLiveClient(panelProvider:)`를 통해 실제 coordinator와 주입된 fake panel로
/// live 구현을 그대로 검증한다. 데이터 소스 노출을 통해 coordinator 내부 상태(URL 목록,
/// 현재 인덱스)가 패널 갱신과 일치하는지도 함께 확인한다.
@MainActor
final class EOP001EntryQuickLookClientTests: XCTestCase {
    /// 테스트용 fake panel. coordinator가 주입한 provider를 통해 실제로 사용된다.
    /// MainActor에서만 접근하므로 `@unchecked Sendable`로 표시한다.
    private final class FakeQuickLookPanel: EntryQuickLookPanelUpdating, @unchecked Sendable {
        var isVisible = true
        var currentPreviewItemIndex = 0
        private(set) var reloadDataCallCount = 0
        private(set) var makeKeyAndOrderFrontCallCount = 0
        private(set) var orderOutCallCount = 0

        func reloadData() {
            reloadDataCallCount += 1
        }

        func makeKeyAndOrderFront() {
            makeKeyAndOrderFrontCallCount += 1
            isVisible = true
        }

        func orderOut() {
            orderOutCallCount += 1
        }
    }

    private final class RecordingQuickLookEventHandler: EntryQuickLookPanelEventHandling {
        private(set) var events: [NSEvent] = []

        func handleQuickLookPanelEvent(_ event: NSEvent) -> Bool {
            events.append(event)
            return true
        }
    }

    // MARK: - EOP-001-quick_look_selection_sync

    /// 보안 범위 리소스 접근의 시작/중지 호출 횟수를 세는 테스트용 경계.
    /// 실제 URL API를 호출하지 않고 대신 호출을 기록해 double-stop 회귀를 검증한다.
    private final class CountingSecurityScopedBoundary: SecurityScopedAccessBoundary, @unchecked Sendable {
        private let lock = NSLock()
        private var _startCount = 0
        private var _stopCount = 0

        var startCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _startCount
        }

        var stopCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _stopCount
        }

        func startAccessing(_: URL) -> Bool {
            lock.lock()
            _startCount += 1
            lock.unlock()
            return true
        }

        func stopAccessing(_: URL) {
            lock.lock()
            _stopCount += 1
            lock.unlock()
        }
    }

    /// EOP-001-quick_look_selection_sync: sync로 토큰을 교체하면 이전 토큰이 정확히 한 번 중지된다.
    /// - 검증 내용: 2개 URL present 후 2개 다른 URL로 sync 교체하면 이전 2개 토큰이 정확히 한 번씩 중지되고
    ///   (deinit에서의 중복 중지 없음), 새 2개 토큰은 계속 활성 상태를 유지한다.
    /// - 사전 조건: fake panel이 visible이고 counting boundary가 주입되어 있다.
    /// - 기대 결과: `startCount == 4`, `stopCount == 2` (이전 토큰만 1회씩 중지).
    func testSyncReplacementStopsOldTokensExactlyOnce() async throws {
        let fake = FakeQuickLookPanel()
        let boundary = CountingSecurityScopedBoundary()
        let (client, _) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake }, boundary: boundary)
        let url1 = URL(fileURLWithPath: "/tmp/a.txt")
        let url2 = URL(fileURLWithPath: "/tmp/b.txt")
        let url3 = URL(fileURLWithPath: "/tmp/c.txt")
        let url4 = URL(fileURLWithPath: "/tmp/d.txt")

        try await client.quickLook([url1, url2], 0)
        await client.syncQuickLookSelection([url3, url4], 0)

        XCTAssertEqual(boundary.startCount, 4)
        XCTAssertEqual(boundary.stopCount, 2)
    }

    /// EOP-001-quick_look_selection_sync: 패널 close 시 활성 토큰이 정확히 한 번 중지된다.
    /// - 검증 내용: 3개 URL present 후 `previewPanelWillClose` 호출 시 3회 시작/3회 중지 (double-stop 없음).
    /// - 사전 조건: fake panel이 visible이고 counting boundary가 주입되어 있다.
    /// - 기대 결과: `startCount == stopCount == 3`.
    func testPanelCloseStopsTokensExactlyOnce() async throws {
        let fake = FakeQuickLookPanel()
        let boundary = CountingSecurityScopedBoundary()
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake }, boundary: boundary)
        let urls = [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
            URL(fileURLWithPath: "/tmp/c.txt"),
        ]

        try await client.quickLook(urls, 0)
        coordinator.previewPanelWillClose(nil)
        // previewPanelWillClose 내부의 MainActor Task가 완료(토큰 중지)될 때까지 양보하며 대기한다.
        for _ in 0 ..< 100 where coordinator.numberOfPreviewItems(in: nil) != 0 {
            await Task.yield()
        }

        XCTAssertEqual(boundary.startCount, 3)
        XCTAssertEqual(boundary.stopCount, 3)
    }

    /// EOP-001-quick_look_selection_sync: 시작된 토큰을 invalidate() 두 번 호출해도 정확히 한 번 중지된다.
    /// - 검증 내용: 시작된 토큰에 `invalidate()`를 두 번 호출하고 참조를 해제(deinit)해도 stop이 1회뿐이다.
    /// - 사전 조건: counting boundary로 생성된 토큰이 시작되어 있다.
    /// - 기대 결과: `startCount == 1`, `stopCount == 1`.
    func testInvalidateTwiceStopsExactlyOnce() {
        let boundary = CountingSecurityScopedBoundary()
        var token: EntryQuickLookSecurityScopedURLToken? = EntryQuickLookSecurityScopedURLToken(
            url: URL(fileURLWithPath: "/tmp/a.txt"),
            boundary: boundary,
        )

        token?.invalidate()
        token?.invalidate()
        token = nil

        XCTAssertEqual(boundary.startCount, 1)
        XCTAssertEqual(boundary.stopCount, 1)
    }

    /// EOP-001-quick_look_selection_sync: 보이는 패널에 선택 동기화를 적용하면 미리보기 대상이 갱신된다.
    /// - 검증 내용: 가시 패널에서 세 개 URL과 index 1로 동기화하면 현재 인덱스가 1이 되고, reload가 1회 발생하며,
    ///   coordinator 데이터 소스가 순서 있는 URL 목록을 노출한다.
    /// - 사전 조건: fake panel이 visible이고 coordinator에 주입되어 있다.
    /// - 기대 결과: `currentPreviewItemIndex == 1`, `reloadDataCallCount == 1`,
    ///   `numberOfPreviewItems == 3`, `previewItem(at: 1) == url2`.
    func testVisibleSyncUpdatesPreviewTarget() async {
        let fake = FakeQuickLookPanel()
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })
        let url1 = URL(fileURLWithPath: "/tmp/a.txt")
        let url2 = URL(fileURLWithPath: "/tmp/b.txt")
        let url3 = URL(fileURLWithPath: "/tmp/c.txt")

        await client.syncQuickLookSelection([url1, url2, url3], 1)

        XCTAssertEqual(fake.currentPreviewItemIndex, 1)
        XCTAssertEqual(fake.reloadDataCallCount, 1)
        XCTAssertEqual(coordinator.numberOfPreviewItems(in: nil), 3)
        XCTAssertEqual(coordinator.previewPanel(nil, previewItemAt: 1) as? URL, url2)
    }

    /// EOP-001-quick_look_selection_sync: 선택 인덱스가 범위를 벗어나면 유효 범위로 clamp된다.
    /// - 검증 내용: 두 개 URL과 index 99로 동기화하면 마지막 유효 인덱스(1)로 clamp된다.
    /// - 사전 조건: fake panel이 visible이고 두 개 URL이 주입되어 있다.
    /// - 기대 결과: `currentPreviewItemIndex == 1`.
    func testVisibleSyncClampsOutOfRangeIndex() async {
        let fake = FakeQuickLookPanel()
        let (client, _) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })
        let url1 = URL(fileURLWithPath: "/tmp/a.txt")
        let url2 = URL(fileURLWithPath: "/tmp/b.txt")

        await client.syncQuickLookSelection([url1, url2], 99)

        XCTAssertEqual(fake.currentPreviewItemIndex, 1)
    }

    /// EOP-001-quick_look_selection_sync: 패널이 숨겨져 있으면 선택 동기화가 no-op이다.
    /// - 검증 내용: 숨겨진 패널에서 비어 있지 않은 URL 목록으로 동기화해도 reload와 인덱스 변경이 없다.
    /// - 사전 조건: fake panel `isVisible == false`.
    /// - 기대 결과: `reloadDataCallCount == 0`, `currentPreviewItemIndex == 0`,
    ///   coordinator 데이터 소스는 여전히 비어 있다.
    func testHiddenPanelSyncIsNoOp() async {
        let fake = FakeQuickLookPanel()
        fake.isVisible = false
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })

        await client.syncQuickLookSelection([URL(fileURLWithPath: "/tmp/a.txt")], 0)

        XCTAssertEqual(fake.reloadDataCallCount, 0)
        XCTAssertEqual(fake.currentPreviewItemIndex, 0)
        XCTAssertEqual(coordinator.numberOfPreviewItems(in: nil), 0)
    }

    /// EOP-001-quick_look_selection_sync: 빈 URL 목록 동기화는 no-op이다.
    /// - 검증 내용: 가시 패널에서 빈 목록으로 동기화해도 reload와 인덱스 변경이 없다.
    /// - 사전 조건: fake panel이 visible이고 동기화 전 상태를 유지한다.
    /// - 기대 결과: `reloadDataCallCount == 0`, `currentPreviewItemIndex == 0`,
    ///   coordinator 데이터 소스는 비어 있다.
    func testEmptyURLsSyncIsNoOp() async {
        let fake = FakeQuickLookPanel()
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })

        await client.syncQuickLookSelection([], 0)

        XCTAssertEqual(fake.reloadDataCallCount, 0)
        XCTAssertEqual(fake.currentPreviewItemIndex, 0)
        XCTAssertEqual(coordinator.numberOfPreviewItems(in: nil), 0)
    }

    // MARK: - EOP-001-quick_look_panel_focus

    /// EOP-001-quick_look_panel_focus: 최초 표시는 AppKit의 canonical key-panel 경로를 사용한다.
    /// - 검증 내용: hidden panel에 quickLook을 요청하면 makeKeyAndOrderFront가 호출된다.
    /// - 사전 조건: hidden fake panel과 단일 URL
    /// - 기대 결과: makeKeyAndOrderFront가 정확히 한 번 호출된다.
    func testPresentMakesPreviewPanelKeyAndFront() async throws {
        let fake = FakeQuickLookPanel()
        fake.isVisible = false
        let (client, _) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })

        try await client.quickLook([URL(fileURLWithPath: "/tmp/a.txt")], 0)

        XCTAssertEqual(fake.makeKeyAndOrderFrontCallCount, 1)
    }

    /// EOP-001-quick_look_panel_focus: responder-chain control은 data source/delegate와 event sink를 함께 연결한다.
    /// - 검증 내용: begin control 후 panel delegate로 들어온 방향키가 등록된 handler에 전달된다.
    /// - 사전 조건: URL이 준비된 coordinator, shared QL panel, recording event handler
    /// - 기대 결과: coordinator가 panel data source/delegate이고 handler가 이벤트를 한 번 받는다.
    func testBeginPreviewPanelControlRoutesUnhandledEvent() async throws {
        _ = NSApplication.shared
        let fake = FakeQuickLookPanel()
        fake.isVisible = false
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })
        try await client.quickLook([
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
        ], 1)
        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        panel.currentPreviewItemIndex = 0
        let handler = RecordingQuickLookEventHandler()
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: 125,
        ))

        coordinator.attach(to: panel, eventHandler: handler)
        let handled = coordinator.previewPanel(panel, handle: event)

        XCTAssertIdentical(panel.dataSource, coordinator)
        XCTAssertIdentical(panel.delegate, coordinator)
        XCTAssertEqual(panel.currentPreviewItemIndex, 1)
        XCTAssertTrue(handled)
        XCTAssertEqual(handler.events, [event])

        coordinator.detach(from: panel, eventHandler: handler)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    /// EOP-001-quick_look_panel_focus: 이전 window의 stale end는 최신 panel owner를 해제하지 않는다.
    func testStaleEndPreviewPanelControlPreservesLatestOwner() async throws {
        _ = NSApplication.shared
        let fake = FakeQuickLookPanel()
        fake.isVisible = false
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })
        try await client.quickLook([URL(fileURLWithPath: "/tmp/a.txt")], 0)
        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        let firstHandler = RecordingQuickLookEventHandler()
        let latestHandler = RecordingQuickLookEventHandler()
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}",
            isARepeat: false,
            keyCode: 125,
        ))

        coordinator.attach(to: panel, eventHandler: firstHandler)
        coordinator.attach(to: panel, eventHandler: latestHandler)
        coordinator.detach(from: panel, eventHandler: firstHandler)

        XCTAssertIdentical(panel.dataSource, coordinator)
        XCTAssertIdentical(panel.delegate, coordinator)
        XCTAssertTrue(coordinator.previewPanel(panel, handle: event))
        XCTAssertTrue(firstHandler.events.isEmpty)
        XCTAssertEqual(latestHandler.events, [event])

        coordinator.detach(from: panel, eventHandler: latestHandler)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    /// EOP-001-quick_look_panel_focus: 가시 패널에 같은 선택으로 Space를 누르면 패널을 닫는다.
    /// 이미 패널이 보이는 상태에서 같은 선택으로 다시 열기를 요청하면 토글로 닫히는지 검증한다.
    /// - 검증 내용: 같은 URL 목록으로 두 번째 quickLook 호출 시 orderOut이 호출되고 상태가 정리된다.
    /// - 사전 조건: 가시 fake panel에 [url1]이 표시되어 있다.
    /// - 기대 결과: `orderOutCallCount == 1`이고 coordinator 데이터 소스는 비워진다.
    func testPresentSameSelectionTogglesVisiblePanelClosed() async throws {
        let fake = FakeQuickLookPanel()
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })
        let url1 = URL(fileURLWithPath: "/tmp/a.txt")

        try await client.quickLook([url1], 0)
        try await client.quickLook([url1], 0)
        for _ in 0 ..< 100 where coordinator.numberOfPreviewItems(in: nil) != 0 {
            await Task.yield()
        }

        XCTAssertEqual(fake.orderOutCallCount, 1)
        XCTAssertEqual(coordinator.numberOfPreviewItems(in: nil), 0)
    }

    /// EOP-001-quick_look_panel_focus: 가시 패널에 다른 선택으로 열기를 요청하면 닫지 않고 동기화한다.
    /// 패널이 보이는 동안 선택이 바뀐 상태로 quickLook을 호출하면 재표시가 아니라 동기화인지 검증한다.
    /// - 검증 내용: [url1] 표시 중 [url2]로 quickLook 호출 시 orderOut 없이 reload와 인덱스 갱신만 수행한다.
    /// - 사전 조건: 가시 fake panel에 [url1]이 표시되어 있다.
    /// - 기대 결과: `orderOutCallCount == 0`, `currentPreviewItemIndex == 0`, reload는 추가 1회.
    func testPresentDifferentSelectionWhileVisibleSyncsInsteadOfReopening() async throws {
        let fake = FakeQuickLookPanel()
        let (client, coordinator) = EntryQuickLookClient.makeLiveClient(panelProvider: { fake })
        let url1 = URL(fileURLWithPath: "/tmp/a.txt")
        let url2 = URL(fileURLWithPath: "/tmp/b.txt")

        try await client.quickLook([url1], 0)
        let reloadCountAfterFirst = fake.reloadDataCallCount
        try await client.quickLook([url2], 0)

        XCTAssertEqual(fake.orderOutCallCount, 0)
        XCTAssertEqual(fake.currentPreviewItemIndex, 0)
        XCTAssertEqual(fake.reloadDataCallCount - reloadCountAfterFirst, 1)
        XCTAssertEqual(coordinator.numberOfPreviewItems(in: nil), 1)
    }
}
