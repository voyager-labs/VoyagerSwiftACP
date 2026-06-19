import ComposableArchitecture
import Foundation
import VoyagerShared

// MARK: - Open Router Status

/// open_router_contract.toml의 상태 어휘를 Swift enum으로 1:1 매핑
enum OpenRouterStatus: Equatable {
    /// Open Router가 외부에서 file URL을 수신한 상태
    case pathReceived // contract: path_received
    /// 수신된 URL이 파일 시스템 경로로 정규화된 상태
    case pathNormalized // contract: path_normalized
    /// 정규화된 경로가 새 File Manager Window에 전달되어 열린 상태
    case windowRouted // contract: window_routed
    /// 파일 경로의 부모 폴더가 열리고 해당 파일이 선택된 상태
    case parentFolderOpened // contract: parent_folder_opened
    /// 열린 부모 폴더에서 대상 파일이 선택 focus된 상태
    case entrySelected // contract: entry_selected
    /// 수신된 경로가 파일 시스템에 존재하지 않아 오류가 표시된 상태
    case invalidPathError // contract: invalid_path_error
    /// 수신된 경로에 접근 권한이 없어 오류가 표시되고 권한 요청이 유도된 상태
    case permissionDeniedError // contract: permission_denied_error
    /// Deep Link URL 형식이 유효하지 않아 오류가 표시된 상태
    case urlValidationError // contract: url_validation_error
}

// MARK: - Route Source

/// 경로 수신 출처
enum RouteSource: Equatable {
    /// 외부 Deep Link URL (`voyager://open`), FMW-003-handle_deep_link
    case deepLink
    // TODO: 후속 이슈 — systemOpenEvent (FMW-003-open_external_path, R2)
    // TODO: 후속 이슈 — nsservices (FMW-003-open_external_path, R2)
}

// MARK: - Open Router Request

/// Open Router가 처리 중인 단일 경로 요청 정보
struct OpenRouterRequest: Equatable {
    /// 원본 URL (Deep Link의 `voyager://open?url=...` 또는 시스템 이벤트 URL)
    let originalURL: URL
    /// 파일 시스템 경로 (URL 정규화 후 채워짐)
    var resolvedPath: String?
    /// 디렉토리 여부 (path probe 후 채워짐)
    var isDirectory: Bool?
    /// 경로 수신 출처
    let source: RouteSource
    /// Deep Link mode (open / reveal)
    let mode: DeepLinkMode
}

// MARK: - Open Router Error

/// Open Router 처리 중 발생 가능한 오류
enum OpenRouterError: Error, Equatable {
    /// 유효하지 않은 경로
    case invalidPath(String)
    /// 접근 권한 없음
    case permissionDenied(String)
    /// URL 형식/인코딩 오류
    case urlValidationError(URL)
    /// 기타 알 수 없는 오류
    case unknown(String)
}

// MARK: - Open Router Action

@CasePathable
enum OpenRouterAction: CasePathable {
    /// 외부에서 경로 수신 (deep link URL, system open event, nsservices)
    case receive(URL)
    /// URL 정규화 완료 (pathReceived → pathNormalized)
    case normalizeCompleted(path: String, isDirectory: Bool)
    /// 라우팅 완료 (windowRouted / parentFolderOpened / entrySelected)
    case routeCompleted(OpenRouterStatus)
    /// 오류 발생
    case failed(OpenRouterError)
    /// 부모 reducer로 위임
    case delegate(Delegate)

    @CasePathable
    enum Delegate: CasePathable {
        /// windowManager로 폴더 열기 위임 (windowRouted)
        case openFolder(path: String)
        /// 파일의 부모 폴더 열기 위임 (parentFolderOpened)
        case openParentFolder(path: String)
        /// ACC로 auth/callback 전달 (auth callback 우회)
        case routeToAuthCallback(URL)
        // TODO: R2 — selectFocus (entrySelected, reveal mode)
    }
}

// MARK: - Open Router State

@ObservableState
struct OpenRouterState: Equatable {
    /// 현재 상태 (nil = 미실행)
    var currentStatus: OpenRouterStatus?
    /// 현재 처리 중인 요청 정보
    var currentRequest: OpenRouterRequest?
}
