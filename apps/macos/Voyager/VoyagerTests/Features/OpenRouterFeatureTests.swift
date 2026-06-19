import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

// MARK: - OpenRouterFeature 계약 테스트

/// Open Router 상태 기계(open_router_contract.toml)를 1:1로 검증하는 TestStore 기반 테스트.
///
/// 전환 흐름: path_received → path_normalized → {window_routed | parent_folder_opened | invalid_path_error |
/// url_validation_error}
@MainActor
final class OpenRouterFeatureTests: XCTestCase {}

// MARK: - Happy Path: 폴더

extension OpenRouterFeatureTests {
    /// 유효한 폴더 Deep Link 수신 → pathReceived → pathNormalized → windowRouted + delegate .openFolder
    ///
    /// AC: 유효한 폴더 `voyager://open?url=file%3A%2F%2F%2FUsers%2F...`가 수신된 상황에서,
    /// URL이 디코딩·검증되고 Open Router로 전달되어 폴더가 열려야 한다.
    func test_validFolderURL_routesToWindowRoutedAndOpenFolder() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: true)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = OpenRouterRequest(
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

    /// mode=reveal 폴더 → 폴더 열기 (select focus 없음, R2 TODO)
    ///
    /// R2에서 entrySelected(select focus)가 구현될 때까지 mode=reveal 폴더도 mode=open과 동일하게 폴더를 연다.
    func test_modeRevealFolder_opensFolderWithoutSelect() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest&mode=reveal"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: true)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = OpenRouterRequest(
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

extension OpenRouterFeatureTests {
    /// mode=open 파일 → 부모 폴더 열기 (select focus 없음, R2 TODO)
    ///
    /// AC: mode=open 파라미터가 포함된 Deep Link가 파일 경로인 상황에서,
    /// 부모 폴더가 열려야 한다. R2까지 select focus는 구현하지 않는다.
    func test_modeOpenFile_opensParentFolder() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest%2Fdocument.txt"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/document.txt"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: false)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = OpenRouterRequest(
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

        await store.receive(\.delegate.openParentFolder)
        await store.finish()
    }

    /// mode=reveal 파일 → 부모 폴더 열기 (select focus 없음, R2 TODO)
    ///
    /// R2에서 entrySelected(select focus)가 구현될 때까지 mode=reveal 파일도 mode=open과 동일하게 부모 폴더를 연다.
    func test_modeRevealFile_opensParentFolderWithoutSelect() async throws {
        let deepLink =
            try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest%2Fdoc.txt&mode=reveal"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/test/doc.txt"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: true, isDirectory: false)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = OpenRouterRequest(
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

        await store.receive(\.delegate.openParentFolder)
        await store.finish()
    }
}

// MARK: - URL 검증 오류

extension OpenRouterFeatureTests {
    /// `url` 파라미터가 누락된 Deep Link → urlValidationError
    ///
    /// AC: `url` 파라미터가 누락된 상황에서, URL 형식 오류가 표시되어야 한다.
    func test_missingURLParameter_urlValidationError() async throws {
        let missingURL = try XCTUnwrap(URL(string: "voyager://open"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
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

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        }

        await store.send(.receive(nonFileURL))
        await store.receive(\.failed) {
            $0.currentStatus = .urlValidationError
        }
        await store.finish()
    }
}

// MARK: - Auth Callback 우회

extension OpenRouterFeatureTests {
    /// auth/callback → delegate .routeToAuthCallback (FMW-003 비간섭)
    ///
    /// AC: `voyager://auth/callback`이 수신된 상황에서, FMW-003가 가로채지 않고 ACC-001로 라우팅되어야 한다.
    func test_authCallback_routesToAuthCallback() async throws {
        let authURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=test123"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        }

        await store.send(.receive(authURL))
        await store.receive(\.delegate.routeToAuthCallback)
        await store.finish()
    }
}

// MARK: - 존재하지 않는 경로

extension OpenRouterFeatureTests {
    /// 존재하지 않는 경로 → invalidPathError
    ///
    /// AC: 존재하지 않는 경로의 Deep Link가 수신된 상황에서, "선택한 위치를 열 수 없습니다" 오류가 표시되어야 한다.
    func test_nonExistentPath_invalidPathError() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Fnope"))
        let fileURL = try XCTUnwrap(URL(string: "file:///Users/nope"))

        let store = TestStore(initialState: OpenRouterState()) {
            OpenRouterFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }

        await store.send(.receive(deepLink)) {
            $0.currentStatus = .pathReceived
            $0.currentRequest = OpenRouterRequest(
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

// MARK: - 미구현 분기 (TODO)

extension OpenRouterFeatureTests {
    /// permissionDeniedError — PathProbeClient가 권한 미지원 → TODO 주석만 존재
    ///
    /// PathProbeClient에 권한 확인 기능이 아직 구현되지 않았으므로,
    /// permissionDeniedError 분기는 reducer에 TODO 주석으로만 작성되어 있다.
    /// PathProbeClient가 권한을 지원하면 이 테스트를 구현해야 한다.
    func test_permissionDeniedError_isNotYetImplemented() {
        // TODO: PathProbeClient가 권한을 지원하면 permissionDeniedError 분기 구현
        // 현재 PathProbeClient.probeExistence는 exists/isDirectory만 반환
        // permissionDeniedError는 PathProbeClient 확장 시 활성화 예정
    }
}
