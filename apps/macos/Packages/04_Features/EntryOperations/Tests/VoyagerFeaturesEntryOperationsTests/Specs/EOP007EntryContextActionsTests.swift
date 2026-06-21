import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

// MARK: - EOP-007-entry_context_actions

@MainActor
final class EOP007EntryContextActionsTests: XCTestCase {
    // MARK: - EOP-007-reveal_entries_in_finder

    /// EOP-007-reveal_entries_in_finder: Finder에서 엔트리 위치 표시
    /// - 검증 내용: Finder 표시 action이 선택 항목 URL을 reveal 의존성에 전달하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.revealInFinder mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 URL로 EntryOpenClient.revealInFinder를 호출
    func testRevealEntriesInFinder_success() async {
        let filePath = "/Users/test/document.txt"
        let fileURL = URL(fileURLWithPath: filePath)
        let revealCalls = CallRecorder<[URL]>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.revealInFinder = { urls in
                revealCalls.record(urls)
            }
        }

        await store.send(.open(.revealInFinder(paths: [filePath])))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        XCTAssertEqual(revealCalls.recorded.count, 1)
        XCTAssertEqual(revealCalls.recorded[0], [fileURL])
    }

    /// EOP-007-reveal_entries_in_finder: 빈 경로 목록 전달 시 아무 동작도 수행하지 않음
    /// - 검증 내용: 빈 경로 입력에서 Finder 표시 의존성이 호출되지 않는지 확인합니다.
    /// - 사전 조건: 초기 상태, 의존성 mock 설정
    /// - 기대 결과: EntryOpenClient.revealInFinder가 호출되지 않음
    func testRevealEntriesInFinder_emptyPaths_noOp() async {
        let revealCalls = CallRecorder<[URL]>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.revealInFinder = { urls in
                revealCalls.record(urls)
            }
        }

        await store.send(.open(.revealInFinder(paths: [])))

        XCTAssertTrue(revealCalls.recorded.isEmpty)
    }

    // MARK: - EOP-007-show_services

    /// EOP-007-show_services: 시스템 서비스 호출
    /// - 검증 내용: Services action이 서비스 이름과 선택 항목 URL을 performService 의존성에 전달하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.performService mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 서비스 이름과 URL로 EntryOpenClient.performService를 호출
    func testShowServices_success() async {
        let filePath = "/Users/test/document.txt"
        let fileURL = URL(fileURLWithPath: filePath)
        let serviceName = "Mail/Compose"
        let performServiceCalls = CallRecorder<(String, [URL])>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.performService = { name, urls in
                performServiceCalls.record((name, urls))
            }
        }

        await store.send(.open(.performService(paths: [filePath], name: serviceName)))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        XCTAssertEqual(performServiceCalls.recorded.count, 1)
        XCTAssertEqual(performServiceCalls.recorded[0].0, serviceName)
        XCTAssertEqual(performServiceCalls.recorded[0].1, [fileURL])
    }

    /// EOP-007-show_services: 빈 경로 목록 전달 시 아무 동작도 수행하지 않음
    /// - 검증 내용: 빈 경로 입력에서 Services 의존성이 호출되지 않는지 확인합니다.
    /// - 사전 조건: 초기 상태, 의존성 mock 설정
    /// - 기대 결과: EntryOpenClient.performService가 호출되지 않음
    func testShowServices_emptyPaths_noOp() async {
        let performServiceCalls = CallRecorder<(String, [URL])>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.performService = { name, urls in
                performServiceCalls.record((name, urls))
            }
        }

        await store.send(.open(.performService(paths: [], name: "Mail/Compose")))

        XCTAssertTrue(performServiceCalls.recorded.isEmpty)
    }

    // MARK: - EOP-007-share_entries_via_system_share_sheet

    /// EOP-007-share_entries_via_system_share_sheet: 시스템 공유 시트로 엔트리 공유
    /// - 검증 내용: 공유 action이 선택 항목 URL과 anchor 좌표를 share 의존성에 전달하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.shareItems mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 URL과 anchor로 EntryOpenClient.shareItems를 호출
    func testShareEntriesViaSystemShareSheet_success() async {
        let filePath = "/Users/test/photo.jpg"
        let fileURL = URL(fileURLWithPath: filePath)
        let anchor = CGPoint(x: 100, y: 200)
        let shareCalls = CallRecorder<([URL], CGPoint?)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.shareItems = { urls, anchorPoint in
                shareCalls.record((urls, anchorPoint))
            }
        }

        await store.send(.open(.shareItems(paths: [filePath], anchor: anchor)))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        XCTAssertEqual(shareCalls.recorded.count, 1)
        XCTAssertEqual(shareCalls.recorded[0].0, [fileURL])
        XCTAssertEqual(shareCalls.recorded[0].1, anchor)
    }

    /// EOP-007-share_entries_via_system_share_sheet: anchor가 nil일 때도 공유 동작 수행
    /// - 검증 내용: anchor가 없는 공유 action도 URL 목록과 nil anchor로 share 의존성을 호출하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.shareItems mock, anchor = nil
    /// - 기대 결과: URL과 nil anchor로 호출되고 실제 공유 UI는 실행되지 않음
    func testShareEntriesViaSystemShareSheet_nilAnchor() async {
        let filePath = "/Users/test/document.pdf"
        let shareCalls = CallRecorder<([URL], CGPoint?)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.shareItems = { urls, anchorPoint in
                shareCalls.record((urls, anchorPoint))
            }
        }

        await store.send(.open(.shareItems(paths: [filePath], anchor: nil)))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[filePath] = ItemOperationState(isBusy: false)
        }

        XCTAssertEqual(shareCalls.recorded.count, 1)
        XCTAssertNil(shareCalls.recorded[0].1)
    }

    /// EOP-007-share_entries_via_system_share_sheet: 빈 경로 목록 전달 시 아무 동작도 수행하지 않음
    /// - 검증 내용: 빈 경로 입력에서 공유 의존성이 호출되지 않는지 확인합니다.
    /// - 사전 조건: 초기 상태, 의존성 mock 설정
    /// - 기대 결과: EntryOpenClient.shareItems가 호출되지 않음
    func testShareEntriesViaSystemShareSheet_emptyPaths_noOp() async {
        let shareCalls = CallRecorder<([URL], CGPoint?)>()

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryOpenClient.shareItems = { urls, anchorPoint in
                shareCalls.record((urls, anchorPoint))
            }
        }

        await store.send(.open(.shareItems(paths: [], anchor: nil)))

        XCTAssertTrue(shareCalls.recorded.isEmpty)
    }
}
