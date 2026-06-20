import ComposableArchitecture
@testable import VoyagerFeaturesExternalFileRouter
import XCTest

// MARK: - ExternalFileRouterFeature 계약 테스트

/// ExternalFileRouter 상태 기계(open_router_contract.toml)를 1:1로 검증하는 TestStore 기반 테스트.
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
                resolvedPath: nil,
                isDirectory: nil,
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
                resolvedPath: nil,
                isDirectory: nil,
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
                resolvedPath: nil,
                isDirectory: nil,
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
                resolvedPath: nil,
                isDirectory: nil,
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
    /// `url` 파라미터가 누락된 Deep Link → urlValidationError
    ///
    /// AC: `url` 파라미터가 누락된 상황에서, URL 형식 오류가 표시되어야 한다.
    func test_missingURLParameter_urlValidationError() async throws {
        let missingURL = try XCTUnwrap(URL(string: "voyager://open"))

        let store = TestStore(initialState: ExternalFileRouterState()) {
            ExternalFileRouterFeature()
        }

        await store.send(.receive(missingURL))
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
    /// 존재하지 않는 경로 → invalidPathError
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
                resolvedPath: nil,
                isDirectory: nil,
                source: .deepLink,
                mode: .open,
            )
        }

        await store.receive(\.failed) {
            $0.currentStatus = .invalidPathError
        }
        await store.finish()
    }
}

// MARK: - 권한 오류

extension FMW003HandleExternalFileOpenRequestsTests {
    /// permissionDenied 경로 → permissionDeniedError
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
                resolvedPath: nil,
                isDirectory: nil,
                source: .deepLink,
                mode: .open,
            )
        }

        await store.receive(\.failed) {
            $0.currentStatus = .permissionDeniedError
        }
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
                resolvedPath: nil,
                isDirectory: nil,
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
                resolvedPath: nil,
                isDirectory: nil,
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
