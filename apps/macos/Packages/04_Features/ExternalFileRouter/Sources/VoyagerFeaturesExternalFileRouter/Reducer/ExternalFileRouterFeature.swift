import ComposableArchitecture
import Foundation

// MARK: - ExternalFileRouterFeature

/// external_file_router_contract.toml의 상태 기계를 구현하는 TCA Reducer.
///
/// 전환 흐름: path_received → path_normalized → {window_routed | parent_folder_opened | invalid_path_error |
/// url_validation_error}
///
/// - 중요한 설계 결정:
///   - window open side-effect는 직접 호출하지 않고 delegate action으로 windowManager에 위임
///   - PathProbeClient mock을 통해 filesystem 접근 없이 테스트 가능
///   - mode=reveal의 select focus(entrySelected)는 R2 TODO
///   - permissionDeniedError는 PathProbeClient가 권한을 지원하면 활성화 (현재 TODO)
@Reducer
public struct ExternalFileRouterFeature {
    public typealias State = ExternalFileRouterState
    public typealias Action = ExternalFileRouterAction

    public init() {}

    @Dependency(\.pathProbeClient)
    private var pathProbeClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .receive(url):
                return handleReceive(url: url, state: &state)

            case let .normalizeCompleted(path, isDirectory):
                return handleNormalizeCompleted(path: path, isDirectory: isDirectory, state: &state)

            case let .routeCompleted(status):
                state.currentStatus = status
                return .none

            case let .failed(error):
                return handleFailed(error: error, state: &state)

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - Action Handlers

private extension ExternalFileRouterFeature {
    /// 외부 URL을 수신하여 파싱하고 상태를 전환한다.
    ///
    /// 1. ExternalFileURLParser로 voyager:// URL 파싱
    /// 2. auth/callback → delegate로 우회 (FMW-003 비간섭)
    /// 3. 파싱 오류 → urlValidationError로 전환
    /// 4. 정상 요청 → pathReceived 상태로 전환 + path 정규화/존재 확인 effect 발행
    func handleReceive(url: URL, state: inout State) -> Effect<Action> {
        let result = ExternalFileURLParser.parse(url)

        switch result {
        case .authCallback:
            // ACC-001 소유의 OAuth callback route, FMW-003가 가로채지 않음
            return .send(.delegate(.routeToAuthCallback(url)))

        case .error:
            // 모든 파싱 오류는 urlValidationError terminal로 전환
            return .send(.failed(.urlValidationError(url)))

        case let .request(request):
            state.currentStatus = .pathReceived
            state.currentRequest = ExternalFileRouterRequest(
                originalURL: request.url,
                resolvedPath: nil,
                isDirectory: nil,
                source: .deepLink,
                mode: request.mode,
            )

            // file URL의 path를 정규화하고 파일시스템 존재 확인
            let fileURL = request.url
            return .run { [pathProbeClient, fileURL] send in
                let normalizedPath = FilePathNormalizer.normalize(fileURL.path)
                let result = pathProbeClient.probeExistence(normalizedPath)
                if result.exists {
                    await send(.normalizeCompleted(path: normalizedPath, isDirectory: result.isDirectory))
                } else {
                    await send(.failed(.invalidPath(normalizedPath)))
                }
            }
        }
    }

    /// path 정규화 완료 후 라우팅을 결정한다.
    ///
    /// path_normalized 상태로 전환 후:
    /// - isDirectory == true (폴더) → windowRouted + delegate .openFolder
    /// - isDirectory == false (파일) → parentFolderOpened + delegate .openParentFolder
    ///
    /// R2 TODO: mode=reveal 시 entrySelected(select focus) 구현
    func handleNormalizeCompleted(path: String, isDirectory: Bool, state: inout State) -> Effect<Action> {
        state.currentStatus = .pathNormalized
        state.currentRequest?.resolvedPath = path
        state.currentRequest?.isDirectory = isDirectory

        if isDirectory {
            // mode=open/mode=reveal 모두 동일하게 폴더 열기 (R2까지 select focus 미구현)
            state.currentStatus = .windowRouted
            return .send(.delegate(.openFolder(path: path)))
        } else {
            // 파일 — 부모 폴더 열기 (R2까지 select focus 미구현)
            state.currentStatus = .parentFolderOpened
            let parentPath = (path as NSString).deletingLastPathComponent
            return .send(.delegate(.openParentFolder(path: parentPath)))
        }
    }

    /// 오류를 상태로 매핑한다.
    ///
    /// - invalidPath → invalidPathError terminal
    /// - permissionDenied → permissionDeniedError terminal (TODO: PathProbeClient 권한 지원 시 활성화)
    /// - urlValidationError → urlValidationError terminal
    /// - unknown → invalidPathError fallback
    func handleFailed(error: ExternalFileRouterError, state: inout State) -> Effect<Action> {
        switch error {
        case .invalidPath:
            state.currentStatus = .invalidPathError
        case .permissionDenied:
            // TODO: PathProbeClient가 권한을 지원하면 permissionDeniedError 분기 구현
            // 현재 PathProbeClient.probeExistence는 exists/isDirectory만 반환
            state.currentStatus = .permissionDeniedError
        case .urlValidationError:
            state.currentStatus = .urlValidationError
        case .unknown:
            state.currentStatus = .invalidPathError
        }
        return .none
    }
}
