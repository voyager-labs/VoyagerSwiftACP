import ComposableArchitecture
import Foundation

// MARK: - ExternalFileRouter Status

/// external_file_router_contract.toml의 상태 어휘를 Swift enum으로 1:1 매핑
public enum ExternalFileRouterStatus: Equatable {
    /// ExternalFileRouter가 외부에서 file URL을 수신한 상태
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
public enum RouteSource: Equatable, Sendable {
    /// 외부 Deep Link URL (`voyager://open`), FMW-003-handle_deep_link
    case deepLink
    /// 시스템 Open Event (`application(_:open:))`
    case systemOpenEvent
    /// NSServices (`NSApplication.shared.servicesProvider`)
    case nsservices
}

// MARK: - ExternalFileRouter Request

/// ExternalFileRouter가 처리 중인 단일 경로 요청 정보
public struct ExternalFileRouterRequest: Equatable, Sendable {
    /// 원본 URL (Deep Link의 `voyager://open?url=...` 또는 시스템 이벤트 URL)
    public let originalURL: URL
    /// 파일 시스템 경로 (URL 정규화 후 채워짐)
    public var resolvedPath: String?
    /// 디렉토리 여부 (path probe 후 채워짐)
    public var isDirectory: Bool?
    /// 경로 수신 출처
    public let source: RouteSource
    /// Deep Link mode (open / reveal)
    public let mode: DeepLinkMode

    public init(
        originalURL: URL,
        source: RouteSource,
        mode: DeepLinkMode,
        resolvedPath: String? = nil,
        isDirectory: Bool? = nil,
    ) {
        self.originalURL = originalURL
        self.resolvedPath = resolvedPath
        self.isDirectory = isDirectory
        self.source = source
        self.mode = mode
    }
}

/// 비동기 path probe 결과가 어떤 외부 요청에 속하는지 식별하는 context
public struct ExternalFileRouterRequestContext: Equatable, Sendable {
    public let requestID: URL
    public let source: RouteSource
    public let mode: DeepLinkMode

    public init(requestID: URL, source: RouteSource, mode: DeepLinkMode) {
        self.requestID = requestID
        self.source = source
        self.mode = mode
    }
}

/// 정규화된 path probe 성공 결과
public struct ExternalFileRouterNormalizationResult: Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public let context: ExternalFileRouterRequestContext

    public init(path: String, isDirectory: Bool, context: ExternalFileRouterRequestContext) {
        self.path = path
        self.isDirectory = isDirectory
        self.context = context
    }
}

// MARK: - ExternalFileRouter Error

/// ExternalFileRouter 처리 중 발생 가능한 오류
public enum ExternalFileRouterError: Error, Equatable, Sendable {
    /// 유효하지 않은 경로
    case invalidPath(String)
    /// 접근 권한 없음
    case permissionDenied(String)
    /// URL 형식/인코딩 오류
    case urlValidationError(URL)
    /// 기타 알 수 없는 오류
    case unknown(String)
}

// MARK: - ExternalFileRouter Action

@CasePathable
public enum ExternalFileRouterAction: CasePathable {
    /// 외부에서 경로 수신 (deep link URL, system open event, nsservices)
    case receive(URL)
    /// 외부 file:// URL 직접 수신 (system open event, NSServices).
    /// ExternalFileURLParser를 거치지 않고 직접 요청을 생성한다.
    case receiveFileURL(URL, source: RouteSource, mode: DeepLinkMode)
    /// URL 정규화 완료 (pathReceived → pathNormalized)
    /// 동시 요청 겹침 시 state pollution 방지를 위해 요청 context를 payload로 전달
    case normalizeCompleted(ExternalFileRouterNormalizationResult)
    /// 라우팅 완료 (windowRouted / parentFolderOpened / entrySelected)
    case routeCompleted(ExternalFileRouterStatus)
    /// 오류 발생
    /// 동시 요청 겹침 시 오류도 해당 요청의 source/mode를 유지한다.
    case failed(ExternalFileRouterError, context: ExternalFileRouterRequestContext? = nil)
    /// 부모 reducer로 위임
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable {
        /// 일반 앱 열기 fallback (`voyager://open`, url 파라미터 없음)
        case openAppFallback
        /// windowManager로 폴더 열기 위임 (windowRouted)
        case openFolder(path: String)
        /// 파일의 부모 폴더 열기 위임 (parentFolderOpened)
        /// selectEntryPath가 nil이 아니면 해당 파일을 선택 focus 한다.
        case openParentFolder(path: String, selectEntryPath: String?)
        /// ACC로 auth/callback 전달 (auth callback 우회)
        case routeToAuthCallback(URL)
        /// mode=reveal에서 파일 선택 focus 완료 (entrySelected)
        case selectEntryCompleted(path: String)
        /// P1 fix: 오류 표시 delegate — 부모 reducer가 사용자에게 오류 알림을 띄울 수 있도록 위임
        /// 유효하지 않은 경로 오류를 부모 reducer에 위임 (invalidPathError)
        case showInvalidPathError(path: String)
        /// 접근 권한 거부 오류를 부모 reducer에 위임 (permissionDeniedError)
        case showPermissionDeniedError(path: String)
    }
}

// MARK: - ExternalFileRouter State

@ObservableState
public struct ExternalFileRouterState: Equatable {
    /// 현재 상태 (nil = 미실행)
    public var currentStatus: ExternalFileRouterStatus?
    /// 현재 처리 중인 요청 정보
    public var currentRequest: ExternalFileRouterRequest?

    public init(currentStatus: ExternalFileRouterStatus? = nil, currentRequest: ExternalFileRouterRequest? = nil) {
        self.currentStatus = currentStatus
        self.currentRequest = currentRequest
    }
}
