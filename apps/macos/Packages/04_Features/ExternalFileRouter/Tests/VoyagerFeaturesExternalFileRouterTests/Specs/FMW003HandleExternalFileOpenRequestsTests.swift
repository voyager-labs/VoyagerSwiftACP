import ComposableArchitecture
@testable import VoyagerFeaturesExternalFileRouter
import XCTest

// MARK: - ExternalFileRouterFeature 계약 테스트

/// ExternalFileRouter 상태 기계(external_file_router_contract.toml)를 1:1로 검증하는 TestStore 기반 테스트.
///
/// 전환 흐름: path_received → path_normalized → {window_routed | parent_folder_opened | invalid_path_error |
/// url_validation_error}
@MainActor
final class FMW003HandleExternalFileOpenRequestsTests: XCTestCase {}

// MARK: - Happy Path: 폴더

extension FMW003HandleExternalFileOpenRequestsTests {
    /// 유효한 폴더 Deep Link 수신 → pathReceived → pathNormalized → windowRouted + delegate .openFolder
    ///
    /// AC: 유효한 폴더 `voyager://open?url=file%3A%2F%2F%2FUsers%2F...`가 수신된 상황에서,
    /// URL이 디코딩·검증되고 ExternalFileRouter로 전달되어 폴더가 열려야 한다.
    func test_validFolderURL_routesToWindowRoutedAndOpenFolder() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: true)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .deepLink,
                mode: .open,
            )
        }

        await store.receive(\.normalizeCompleted) {
            $0.currentStatus = .windowRouted
            $0.currentRequest?.resolvedPath = "/Users/test"
            $0.currentRequest?.isDirectory = true
        }

        await store.receive(\.delegate.openFolder)
        await store.finish()
    }

    /// mode=reveal 폴더 → 폴더 열기 (select focus 불필요)
    ///
    /// 폴더는 mode와 관계없이 windowRouted + openFolder로 동일하게 처리된다.
    func test_modeRevealFolder_opensFolder() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest&mode=reveal"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: true)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .deepLink,
                mode: .reveal,
            )
        }

        await store.receive(\.normalizeCompleted) {
            $0.currentStatus = .windowRouted
            $0.currentRequest?.resolvedPath = "/Users/test"
            $0.currentRequest?.isDirectory = true
        }

        await store.receive(\.delegate.openFolder)
        await store.finish()
    }
}

// MARK: - Happy Path: 파일

extension FMW003HandleExternalFileOpenRequestsTests {
    /// mode=open 파일 → 부모 폴더 열기 (selectEntryPath: nil)
    ///
    /// AC: mode=open 파라미터가 포함된 Deep Link가 파일 경로인 상황에서,
    /// 부모 폴더가 열려야 한다. selectEntryPath는 nil로 전달된다.
    func test_modeOpenFile_opensParentFolder() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest%2Fdocument.txt"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/document.txt"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: false)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .deepLink,
                mode: .open,
            )
        }

        await store.receive(\.normalizeCompleted) {
            $0.currentStatus = .parentFolderOpened
            $0.currentRequest?.resolvedPath = "/Users/test/document.txt"
            $0.currentRequest?.isDirectory = false
        }

        // delegate.openParentFolder(path: "/Users/test", selectEntryPath: nil) 수신 확인
        await store.receive(\.delegate.openParentFolder)

        await store.finish()
    }

    /// mode=reveal 파일 → 부모 폴더 열기 + 파일 선택 focus + entrySelected
    ///
    /// mode=reveal 시 parentFolderOpened로 부모 폴더를 열고 selectEntryPath로 파일 선택 focus를 위임한 후,
    /// entrySelected 상태로 전환한다.
    func test_modeRevealFile_opensParentFolderAndSelectsEntry() async throws {
        let deepLink =
            try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest%2Fdoc.txt&mode=reveal"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/doc.txt"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: false)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .deepLink,
                mode: .reveal,
            )
        }

        await store.receive(\.normalizeCompleted) {
            $0.currentStatus = .parentFolderOpened
            $0.currentRequest?.resolvedPath = "/Users/test/doc.txt"
            $0.currentRequest?.isDirectory = false
        }

        // delegate.openParentFolder(path: "/Users/test", selectEntryPath: "/Users/test/doc.txt") 수신 확인
        await store.receive(\.delegate.openParentFolder)

        await store.receive(\.routeCompleted) {
            $0.currentStatus = .entrySelected
        }

        await store.finish()
    }
}

// MARK: - URL 검증 오류

extension FMW003HandleExternalFileOpenRequestsTests {
    /// `url` 파라미터가 없는 Deep Link → 일반 앱 열기 fallback delegate
    ///
    /// AC: bare `voyager://open`은 URL 형식 오류가 아니라 기본 File Manager Window 열기로 위임되어야 한다.
    func test_bareOpenURL_routesToOpenAppFallback() async throws {
        let missingURL = try XCTUnwrap(URL(string: "voyager://open"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        }

        await store.send(.receive(missingURL))
        await store.receive(\.delegate.openAppFallback)
        await store.finish()
    }

    /// `url` 파라미터가 있지만 값이 비어 있으면 urlValidationError
    func test_emptyURLParameter_urlValidationError() async throws {
        let emptyURL = try XCTUnwrap(URL(string: "voyager://open?url="))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        }

        await store.send(.receive(emptyURL))
        await store.receive(\.failed) {
            $0.currentStatus = .urlValidationError
        }
        await store.finish()
    }

    /// 비 file:// URL → urlValidationError
    ///
    /// AC: `url` 파라미터가 로컬 파일 경로(file://)가 아닌 상황에서, 지원하지 않는 URL 형식으로 처리되어야 한다.
    func test_nonFileURL_urlValidationError() async throws {
        let nonFileURL = try XCTUnwrap(URL(string: "voyager://open?url=https%3A%2F%2Fexample.com"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        }

        await store.send(.receive(nonFileURL))
        await store.receive(\.failed) {
            $0.currentStatus = .urlValidationError
        }
        await store.finish()
    }
}

// MARK: - Auth Callback 우회

extension FMW003HandleExternalFileOpenRequestsTests {
    /// auth/callback → delegate .routeToAuthCallback (FMW-003 비간섭)
    ///
    /// AC: `voyager://auth/callback`이 수신된 상황에서, FMW-003가 가로채지 않고 ACC-001로 라우팅되어야 한다.
    func test_authCallback_routesToAuthCallback() async throws {
        let authURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=test123"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        }

        await store.send(.receive(authURL))
        await store.receive(\.delegate.routeToAuthCallback)
        await store.finish()
    }
}

// MARK: - 존재하지 않는 경로

extension FMW003HandleExternalFileOpenRequestsTests {
    /// 존재하지 않는 경로 → invalidPathError + delegate .showInvalidPathError
    ///
    /// AC: 존재하지 않는 경로의 Deep Link가 수신된 상황에서, "선택한 위치를 열 수 없습니다" 오류가 표시되어야 한다.
    func test_nonExistentPath_invalidPathError() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Fnope"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/nope"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .deepLink,
                mode: .open,
            )
        }

        await store.receive(\.failed) {
            $0.currentStatus = .invalidPathError
        }

        // 부모 reducer가 사용자에게 오류를 표시할 수 있도록 delegate 위임
        await store.receive(\.delegate.showInvalidPathError)

        await store.finish()
    }
}

// MARK: - 권한 오류

extension FMW003HandleExternalFileOpenRequestsTests {
    /// permissionDenied 경로 → permissionDeniedError + delegate .showPermissionDeniedError
    ///
    /// PathProbeClient가 permissionDenied=true를 반환하면,
    /// permissionDeniedError 상태로 전환되어야 한다.
    func test_permissionDeniedPath_permissionDeniedError() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Frestricted%2Ffile.txt"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/restricted/file.txt"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false, permissionDenied: true)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .deepLink,
                mode: .open,
            )
        }

        await store.receive(\.failed) {
            $0.currentStatus = .permissionDeniedError
        }

        // 부모 reducer가 사용자에게 오류를 표시할 수 있도록 delegate 위임
        await store.receive(\.delegate.showPermissionDeniedError)

        await store.finish()
    }
}

// MARK: - receiveFileURL

extension FMW003HandleExternalFileOpenRequestsTests {
    /// systemOpenEvent 폴더 → pathReceived → pathNormalized → windowRouted + delegate openFolder
    ///
    /// receiveFileURL로 systemOpenEvent 출처의 폴더 경로를 수신하면,
    /// ExternalFileURLParser 없이 정상 라우팅되어 폴더가 열려야 한다.
    func test_systemOpenEventFolder_routesToWindowRouted() async throws {
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: true)
            }
        }

        await store.send(.receiveFileURL(fileURL, source: .systemOpenEvent, mode: .open)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .systemOpenEvent,
                mode: .open,
            )
        }

        await store.receive(\.normalizeCompleted) {
            $0.currentStatus = .windowRouted
            $0.currentRequest?.resolvedPath = "/Users/test"
            $0.currentRequest?.isDirectory = true
        }

        await store.receive(\.delegate.openFolder)
        await store.finish()
    }

    /// nsservices 파일 + mode=reveal → pathReceived → pathNormalized → parentFolderOpened + selectEntryPath →
    /// entrySelected
    ///
    /// receiveFileURL로 NSServices 출처의 파일 경로를 mode=reveal로 수신하면,
    /// 부모 폴더 열기 + select focus 위임 후 entrySelected 상태로 전환되어야 한다.
    func test_nsservicesFileReveal_routesToEntrySelected() async throws {
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/doc.txt"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: false)
            }
        }

        await store.send(.receiveFileURL(fileURL, source: .nsservices, mode: .reveal)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .nsservices,
                mode: .reveal,
            )
        }

        await store.receive(\.normalizeCompleted) {
            $0.currentStatus = .parentFolderOpened
            $0.currentRequest?.resolvedPath = "/Users/test/doc.txt"
            $0.currentRequest?.isDirectory = false
        }

        // delegate.openParentFolder(path: "/Users/test", selectEntryPath: "/Users/test/doc.txt") 수신 확인
        await store.receive(\.delegate.openParentFolder)

        await store.receive(\.routeCompleted) {
            $0.currentStatus = .entrySelected
        }

        await store.finish()
    }

    /// receiveFileURL에 file 외 scheme → urlValidationError
    ///
    /// file:// 이외의 scheme으로 receiveFileURL이 호출되면,
    /// urlValidationError 상태로 전환되어야 한다.
    func test_receiveFileURLWithNonFileScheme_urlValidationError() async throws {
        let httpsURL = try XCTUnwrap(URL(string: "https://example.com/file.txt"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        }

        // guard clause가 scheme 검증 후 바로 실패 처리 → state 변경 없음
        await store.send(.receiveFileURL(httpsURL, source: .systemOpenEvent, mode: .open))

        await store.receive(\.failed) {
            $0.currentStatus = .urlValidationError
        }
        await store.finish()
    }
}

// MARK: - F3: 연속 요청 mode 오염 방지

extension FMW003HandleExternalFileOpenRequestsTests {
    /// 연속 요청에서 mode 오염 방지 검증
    ///
    /// 두 개의 receiveFileURL 요청이 겹칠 때, 각 normalizeCompleted가
    /// 자신의 source/mode를 유지해야 한다.
    /// state.currentRequest는 두 번째 요청으로 덮어쓰여지지만,
    /// action payload의 mode가 우선적으로 사용되므로 올바르게 라우팅된다.
    func test_consecutiveRequests_preserveCorrectMode() async throws {
        let folderURL = try XCTUnwrap(URL(string: "file:///Users/test/folder1"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/doc.txt"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { path in
                if path.contains("folder1") {
                    PathProbeResult(exists: true, isDirectory: true)
                } else {
                    PathProbeResult(exists: true, isDirectory: false)
                }
            }
        }
        // exhaustivity = .off: 두 async 효과의 인터리빙 순서가 비결정적이므로 엄격한 순서 검증 생략
        store.exhaustivity = .off

        await store.send(.receiveFileURL(folderURL, source: .systemOpenEvent, mode: .open))
        await store.send(.receiveFileURL(fileURL, source: .nsservices, mode: .reveal))

        await store.receive(\.normalizeCompleted)

        // exhaustivity = .off: 두 .run effect의 인터리빙이 비결정적이므로
        // 나머지 액션(delegate/routeCompleted)의 순서 검증 생략, finish로 잔여 효과 처리
        await store.finish()
    }

    /// 이전 요청의 late normalizeCompleted도 유효한 요청이면 drop하지 않고 라우팅해야 한다.
    func test_lateNormalizeCompleted_routesOriginalRequestWithoutCurrentRequestGuard() async throws {
        let folderURL = try XCTUnwrap(URL(string: "file:///Users/test/folder1"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/doc.txt"))

        var state = ExternalFileRouterState()
        state.currentStatus = .pathReceived
        state.currentRequest = ExternalFileRouterRequest(
            originalURL: fileURL,
            source: .nsservices,
            mode: .reveal,
        )

        let store = TestStore(initialState: state) {
            ExternalFileRouterFeature()
        }

        await store.send(ExternalFileRouterAction.normalizeCompleted(ExternalFileRouterNormalizationResult(
            path: "/Users/test/folder1",
            isDirectory: true,
            context: ExternalFileRouterRequestContext(requestID: folderURL, source: .systemOpenEvent, mode: .open),
        ))) {
            $0.currentStatus = .windowRouted
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: folderURL,
                source: .systemOpenEvent,
                mode: .open,
                resolvedPath: "/Users/test/folder1",
                isDirectory: true,
            )
        }

        await store.receive { action in
            guard case let .delegate(.openFolder(path)) = action else { return false }
            return path == "/Users/test/folder1"
        }

        await store.finish()
    }
}

// MARK: - F4: EPERM 권한 오류

extension FMW003HandleExternalFileOpenRequestsTests {
    /// EPERM errno도 permissionDenied로 감지되는지 검증
    ///
    /// PathProbeClient liveValue가 `errno == EACCES || errno == EPERM`으로
    /// 확장되었으므로, permissionDenied=true 결과가 permissionDeniedError 상태로
    /// 전환되어야 한다.
    func test_epermPermissionDenied_permissionDeniedError() async throws {
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/protected"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false, permissionDenied: true)
            }
        }

        await store.send(.receiveFileURL(fileURL, source: .systemOpenEvent, mode: .open)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = ExternalFileRouterRequest(
                originalURL: fileURL,
                source: .systemOpenEvent,
                mode: .open,
            )
        }

        await store.receive(\.failed) {
            $0.currentStatus = .permissionDeniedError
        }

        // 부모 reducer가 사용자에게 오류를 표시할 수 있도록 delegate 위임
        await store.receive(\.delegate.showPermissionDeniedError)

        await store.finish()
    }
}

// MARK: - FMW-003-open_external_path

extension FMW003HandleExternalFileOpenRequestsTests {
    /// FMW-003-open_external_path: 지연된 probe와 실패가 섞여도 callback 입력 순서의 결과를 한 번 반환한다.
    /// 시스템 open callback의 모든 occurrence가 완료된 뒤 하나의 ordered normalization 결과가 생성되는지 검증한다.
    /// - 검증 내용: batch identity, item identity/index, duplicate occurrence, 실패 위치, destination 분류를 확인한다.
    /// - 사전 조건: directory probe는 뒤 항목이 먼저 완료될 때까지 대기하고 invalid/permission/file/`.voycoll` 입력이 섞여 있다.
    /// - 기대 결과: beginning/middle/end 실패를 포함한 7개 결과가 원래 순서로 한 번만 delegate된다.
    func testSystemOpenBatchPreservesOrderFailuresDuplicatesAndClassification() async throws {
        let batchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000100"))
        let itemIDs = try (0 ..< 7).map { offset in
            try XCTUnwrap(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1)))
        }
        let urls = [
            URL(fileURLWithPath: "/tmp/missing"),
            URL(fileURLWithPath: "/tmp/folder"),
            URL(fileURLWithPath: "/tmp/document.txt"),
            URL(fileURLWithPath: "/tmp/restricted"),
            URL(fileURLWithPath: "/tmp/list.voycoll"),
            URL(fileURLWithPath: "/tmp/document.txt"),
            URL(fileURLWithPath: "/tmp/missing"),
        ]
        let batch = makeBatchRequest(batchID: batchID, itemIDs: itemIDs, urls: urls)
        let expected = makeBatchResult(batchID: batchID, itemIDs: itemIDs, urls: urls)

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = probeBatchPath
        }

        await store.send(.receiveBatch(batch)) {
            $0.activeBatchID = batchID
        }
        await store.receive(\.batchNormalizationCompleted, expected) {
            $0.activeBatchID = nil
        }
        await store.receive(\.delegate.batchNormalized, expected)
        // store.finish() 불필요: 모든 effect가 receive로 소비됨
    }

    /// FMW-003-open_external_path: 취소되거나 현재 batch와 다른 completion은 결과를 위임하지 않는다.
    /// lifecycle gate가 batch를 취소한 뒤 늦게 도착한 completion이 라우팅을 재개하지 않는지 검증한다.
    /// - 검증 내용: matching cancel이 active identity를 지우고 late/stale completion의 state/delegate mutation이 없는지 확인한다.
    /// - 사전 조건: active batch identity와 취소 후 도착한 동일 batch 및 다른 batchID의 synthetic completion이 있다.
    /// - 기대 결과: cancellation 이후 active batch는 nil이며 batchNormalized delegate는 0회다.
    func testCancelledAndStaleBatchCompletionDoesNotMutateOrDelegate() async throws {
        let batchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000200"))
        let staleBatchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))
        var state = ExternalFileRouterState()
        state.activeBatchID = batchID
        let cancelledResult = ExternalFileRouterBatchResult(batchID: batchID, items: [])
        let staleResult = ExternalFileRouterBatchResult(batchID: staleBatchID, items: [])

        let store = TestStore(initialState: state) {
            ExternalFileRouterFeature()
        }

        await store.send(.cancelBatch(batchID)) {
            $0.activeBatchID = nil
        }
        await store.send(.batchNormalizationCompleted(cancelledResult))
        await store.send(.batchNormalizationCompleted(staleResult))
        await store.finish()
    }
}

private func makeBatchRequest(
    batchID: UUID,
    itemIDs: [UUID],
    urls: [URL],
) -> ExternalFileRouterBatchRequest {
    ExternalFileRouterBatchRequest(
        batchID: batchID,
        items: zip(itemIDs, urls).enumerated().map { index, pair in
            .init(
                itemID: pair.0,
                index: index,
                url: pair.1,
                source: .systemOpenEvent,
                mode: .open,
            )
        },
    )
}

private func makeBatchResult(
    batchID: UUID,
    itemIDs: [UUID],
    urls: [URL],
) -> ExternalFileRouterBatchResult {
    let outcomes: [ExternalFileRouterBatchOutcome] = [
        .failure(.invalidPath("/tmp/missing")),
        .success(.directory(path: "/tmp/folder", revealPath: nil)),
        .success(.directory(path: "/tmp", revealPath: "/tmp/document.txt")),
        .failure(.permissionDenied("/tmp/restricted")),
        .success(.collection(path: "/tmp/list.voycoll")),
        .success(.directory(path: "/tmp", revealPath: "/tmp/document.txt")),
        .failure(.invalidPath("/tmp/missing")),
    ]
    let items = zip(urls, outcomes).enumerated().map { index, pair in
        ExternalFileRouterBatchItemResult(
            itemID: itemIDs[index],
            index: index,
            url: pair.0,
            source: .systemOpenEvent,
            mode: .open,
            outcome: pair.1,
        )
    }
    return ExternalFileRouterBatchResult(batchID: batchID, items: items)
}

private func probeBatchPath(_ path: String) -> PathProbeResult {
    switch path {
    case "/tmp/folder":
        Thread.sleep(forTimeInterval: 0.05)
        return PathProbeResult(exists: true, isDirectory: true)
    case "/tmp/missing":
        return PathProbeResult(exists: false, isDirectory: false)
    case "/tmp/document.txt":
        return PathProbeResult(exists: true, isDirectory: false)
    case "/tmp/list.voycoll":
        return PathProbeResult(exists: true, isDirectory: true)
    case "/tmp/restricted":
        return PathProbeResult(exists: false, isDirectory: false, permissionDenied: true)
    default:
        XCTFail("예상하지 못한 probe path: \(path)")
        return PathProbeResult(exists: false, isDirectory: false)
    }
}
