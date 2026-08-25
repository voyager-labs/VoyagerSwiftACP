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
    func testRevealEntriesInFinder_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let fileURL = sandbox.fileURL
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

        // 비-undo 명령도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

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
    func testShowServices_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let fileURL = sandbox.fileURL
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

        // 비-undo 명령도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

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

    /// EOP-007-show_services: navigation Services command는 선택 URL과 exact service name을 open action으로 계획한다.
    /// context menu coordinator가 전달한 서비스 제목이 planner에서 변경되지 않아야 한다.
    /// - 검증 내용: 선택된 display item의 경로 순서와 서비스 이름이 `.performService(paths:name:)`에 보존되는지 확인한다.
    /// - 사전 조건: 선택된 두 파일과 exact native service title을 가진 command context가 있다.
    /// - 기대 결과: planner가 선택 경로와 서비스 이름을 담은 단일 entry operation output을 반환한다.
    func testShowServices_plansSelectedPathsAndExactName() {
        let first = EntryModelFixtures.makeFileEntry(id: "/tmp/first.txt", name: "first.txt")
        let second = EntryModelFixtures.makeFileEntry(id: "/tmp/second.txt", name: "second.txt")
        let context = EntryOperationsCommandContext(
            selectedIds: [first.id, second.id],
            displayItems: [first, second],
            currentPath: "/tmp",
        )
        let serviceName = "Mail/Compose"

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .navigation(.performService(serviceName: serviceName)),
            context: context,
        )

        guard case let .entryOperations(.open(.performService(paths, name)))? = outputs.first else {
            XCTFail("Expected a single performService entry operation output")
            return
        }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(paths, [first.fullPath, second.fullPath])
        XCTAssertEqual(name, serviceName)
    }

    /// EOP-007-show_services: 선택 경로가 없으면 navigation Services command는 no-op이다.
    /// 빈 target에서 서비스 실행 경로가 downstream OS service 호출로 이어지면 안 된다.
    /// - 검증 내용: 선택 항목이 없는 planner context에서 output이 비어 있는지 확인한다.
    /// - 사전 조건: display item은 있으나 selectedIds가 빈 command context가 있다.
    /// - 기대 결과: planner가 어떤 output도 반환하지 않는다.
    func testShowServices_emptySelection_noOp() {
        let entry = EntryModelFixtures.makeFileEntry(id: "/tmp/entry.txt", name: "entry.txt")
        let context = EntryOperationsCommandContext(
            selectedIds: [],
            displayItems: [entry],
            currentPath: "/tmp",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .navigation(.performService(serviceName: "Mail/Compose")),
            context: context,
        )

        XCTAssertTrue(outputs.isEmpty)
    }

    // MARK: - EOP-007-share_entries_via_system_share_sheet

    /// EOP-007-share_entries_via_system_share_sheet: 시스템 공유 시트로 엔트리 공유
    /// - 검증 내용: 공유 action이 선택 항목 URL과 anchor 좌표를 share 의존성에 전달하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.shareItems mock으로 교체, 호출 기록 준비
    /// - 기대 결과: 리듀서가 올바른 URL과 anchor로 EntryOpenClient.shareItems를 호출
    func testShareEntriesViaSystemShareSheet_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/images/jpeg/hopper.jpg")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
        let fileURL = sandbox.fileURL
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

        // 비-undo 명령도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

        XCTAssertEqual(shareCalls.recorded.count, 1)
        XCTAssertEqual(shareCalls.recorded[0].0, [fileURL])
        XCTAssertEqual(shareCalls.recorded[0].1, anchor)
    }

    /// EOP-007-share_entries_via_system_share_sheet: anchor가 nil일 때도 공유 동작 수행
    /// - 검증 내용: anchor가 없는 공유 action도 URL 목록과 nil anchor로 share 의존성을 호출하는지 확인합니다.
    /// - 사전 조건: EntryOpenClient.shareItems mock, anchor = nil
    /// - 기대 결과: URL과 nil anchor로 호출되고 실제 공유 UI는 실행되지 않음
    func testShareEntriesViaSystemShareSheet_nilAnchor() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/documents/pdf/pdf-test.pdf")
        defer { sandbox.cleanup() }
        let filePath = sandbox.fileURL.path
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

        // 비-undo 명령도 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

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

    // MARK: - EOP-007-open_in_new_tab

    /// EOP-007-open_in_new_tab: 선택된 폴더 경로를 display 순서대로 delegate로 전달한다
    /// folder context menu의 Open in New Tab 명령이 선택 폴더만 요청 경로 순서대로 위로 전달해야 한다.
    /// - 검증 내용: display 순서와 일치하는 선택 폴더 경로가 .delegate(.openInNewTab)으로 방출된다.
    /// - 사전 조건: display 순서 [b, a, c]의 세 폴더가 모두 선택되어 있다.
    /// - 기대 결과: 요청 경로와 선택 폴더의 교집합이 display 순서 그대로 delegate로 전달된다.
    func testOpenInNewTab_delegatesOrderedFolderPaths() {
        let folderB = EntryModelFixtures.makeEntry(path: "/tmp/b", isFolder: true)
        let folderA = EntryModelFixtures.makeEntry(path: "/tmp/a", isFolder: true)
        let folderC = EntryModelFixtures.makeEntry(path: "/tmp/c", isFolder: true)
        let context = EntryOperationsCommandContext(
            selectedIds: [folderA.id, folderB.id, folderC.id],
            displayItems: [folderB, folderA, folderC],
            currentPath: "/tmp",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .navigation(.openInNewTab(paths: [folderB.fullPath, folderA.fullPath, folderC.fullPath])),
            context: context,
        )

        guard case let .delegate(.openInNewTab(paths))? = outputs.first else {
            XCTFail("Expected a single openInNewTab delegate output")
            return
        }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(paths, [folderB.fullPath, folderA.fullPath, folderC.fullPath])
    }

    /// EOP-007-open_in_new_tab: 요청 경로 중 파일이거나 미선택 폴더는 delegate에서 제외한다
    /// planner는 요청 경로와 현재 선택된 폴더의 교집합만 위로 전달하고 그 외 경로는 버려야 한다.
    /// - 검증 내용: 파일 경로와 미선택 폴더 경로가 교집합에서 제외된다.
    /// - 사전 조건: 선택 폴더 [a]와 요청 경로 [a, 파일, 미선택 폴더]가 있다.
    /// - 기대 결과: delegate로 선택 폴더 a만 전달된다.
    func testOpenInNewTab_rejectsFileAndUnselectedPaths() {
        let folderA = EntryModelFixtures.makeEntry(path: "/tmp/a", isFolder: true)
        let fileB = EntryModelFixtures.makeFileEntry(id: "/tmp/b.txt", name: "b.txt")
        let unselectedFolder = EntryModelFixtures.makeEntry(path: "/tmp/c", isFolder: true)
        let context = EntryOperationsCommandContext(
            selectedIds: [folderA.id],
            displayItems: [folderA, fileB, unselectedFolder],
            currentPath: "/tmp",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .navigation(.openInNewTab(paths: [
                folderA.fullPath,
                fileB.fullPath,
                unselectedFolder.fullPath,
            ])),
            context: context,
        )

        guard case let .delegate(.openInNewTab(paths))? = outputs.first else {
            XCTFail("Expected a single openInNewTab delegate output")
            return
        }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(paths, [folderA.fullPath])
    }

    /// EOP-007-open_in_new_tab: 빈 요청 경로는 아무 output도 만들지 않는다
    /// 유효한 선택 폴더가 있더라도 요청 경로가 비어 있으면 planner는 no-op이어야 한다.
    /// - 검증 내용: 빈 paths 입력에서 output 배열이 비어 있다.
    /// - 사전 조건: 선택 폴더가 있으나 요청 paths가 []다.
    /// - 기대 결과: 출력이 없어 어떤 delegate/action도 방출되지 않는다.
    func testOpenInNewTab_emptyPathsNoOp() {
        let folderA = EntryModelFixtures.makeEntry(path: "/tmp/a", isFolder: true)
        let context = EntryOperationsCommandContext(
            selectedIds: [folderA.id],
            displayItems: [folderA],
            currentPath: "/tmp",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .navigation(.openInNewTab(paths: [])),
            context: context,
        )

        XCTAssertTrue(outputs.isEmpty)
    }
}
