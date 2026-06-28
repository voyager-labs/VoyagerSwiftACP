import ComposableArchitecture
import Foundation

// MARK: - ExternalFileRouterFeature

/// external_file_router_contract.toml의 상태 기계를 구현하는 TCA Reducer.
///
/// 전환 흐름: path_received → path_normalized → {window_routed | parent_folder_opened | invalid_path_error |
/// url_validation_error | permission_denied_error}
///
/// - 중요한 설계 결정:
///   - window open side-effect는 직접 호출하지 않고 delegate action으로 windowManager에 위임
///   - PathProbeClient mock을 통해 filesystem 접근 없이 테스트 가능
///   - mode=reveal 시 entrySelected 상태로 전환하여 파일 선택 focus를 위임
///   - PathProbeClient가 stat() 기반으로 EACCES 권한 오류를 감지
@Reducer
public struct ExternalFileRouterFeature {
    public typealias State = ExternalFileRouterState
    public typealias Action = ExternalFileRouterAction

    public init() {}

    @Dependency(\.pathProbeClient)
    private var pathProbeClient

    private enum CancelID: Hashable {
        case pathProbe(URL)
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .receive(url):
                return handleReceive(url: url, state: &state)

            case let .receiveFileURL(url, source, mode):
                return handleReceiveFileURL(url: url, source: source, mode: mode, state: &state)

            case let .normalizeCompleted(result):
                return handleNormalizeCompleted(result: result, state: &state)

            case let .routeCompleted(status):
                state.currentStatus = status
                return .none

            case let .failed(error, context):
                return handleFailed(error: error, context: context, state: &state)

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
        case .openAppFallback:
            // WEBSITE/Auth의 Return to Voyager fallback: 파일 라우팅 오류가 아니라 기본 앱 열기로 위임
            return .send(.delegate(.openAppFallback))

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
                source: .deepLink,
                mode: request.mode,
            )

            // file URL의 path를 정규화하고 파일시스템 존재 확인
            let fileURL = request.url
            return .run { [pathProbeClient, fileURL, request] send in
                let normalizedPath = FilePathNormalizer.normalize(fileURL.path)
                let context = ExternalFileRouterRequestContext(
                    requestID: fileURL,
                    source: .deepLink,
                    mode: request.mode,
                )
                let result = pathProbeClient.probeExistence(normalizedPath)
                if result.permissionDenied {
                    await send(.failed(.permissionDenied(normalizedPath), context: context))
                } else if result.exists {
                    await send(.normalizeCompleted(.init(
                        path: normalizedPath,
                        isDirectory: result.isDirectory,
                        context: context,
                    )))
                } else {
                    await send(.failed(.invalidPath(normalizedPath), context: context))
                }
            }
            .cancellable(id: CancelID.pathProbe(fileURL), cancelInFlight: false)
        }
    }

    /// 외부 file:// URL을 직접 수신하여 처리한다.
    ///
    /// ExternalFileURLParser를 거치지 않고 바로 pathReceived 상태로 전환한다:
    /// 1. file scheme 검증 (아니면 urlValidationError)
    /// 2. pathReceived 상태로 전환
    /// 3. path 정규화 + 존재 확인 effect 발행 (`handleReceive`와 동일한 probe 로직)
    func handleReceiveFileURL(url: URL, source: RouteSource, mode: DeepLinkMode, state: inout State) -> Effect<Action> {
        guard url.scheme == "file" else {
            return .send(.failed(.urlValidationError(url)))
        }

        state.currentStatus = .pathReceived
        state.currentRequest = ExternalFileRouterRequest(
            originalURL: url,
            source: source,
            mode: mode,
        )

        // file URL의 path를 정규화하고 파일시스템 존재 확인
        return .run { [pathProbeClient, url, source, mode] send in
            let normalizedPath = FilePathNormalizer.normalize(url.path)
            let context = ExternalFileRouterRequestContext(requestID: url, source: source, mode: mode)
            let result = pathProbeClient.probeExistence(normalizedPath)
            if result.permissionDenied {
                await send(.failed(.permissionDenied(normalizedPath), context: context))
            } else if result.exists {
                await send(.normalizeCompleted(.init(
                    path: normalizedPath,
                    isDirectory: result.isDirectory,
                    context: context,
                )))
            } else {
                await send(.failed(.invalidPath(normalizedPath), context: context))
            }
        }
        .cancellable(id: CancelID.pathProbe(url), cancelInFlight: false)
    }

    /// path 정규화 완료 후 라우팅을 결정한다.
    ///
    /// path_normalized 상태로 전환 후:
    /// - isDirectory == true (폴더) → windowRouted + delegate .openFolder
    /// - isDirectory == false (파일, mode=reveal) → parentFolderOpened + delegate .openParentFolder(
    ///   selectEntryPath:) → entrySelected + delegate .selectEntryCompleted
    /// - isDirectory == false (파일, mode=open) → parentFolderOpened + delegate .openParentFolder(
    ///   selectEntryPath: nil)
    func handleNormalizeCompleted(result: ExternalFileRouterNormalizationResult, state: inout State) -> Effect<Action> {
        let path = result.path
        let isDirectory = result.isDirectory
        let context = result.context

        state.currentStatus = .pathNormalized
        state.currentRequest = ExternalFileRouterRequest(
            originalURL: context.requestID,
            source: context.source,
            mode: context.mode,
            resolvedPath: path,
            isDirectory: isDirectory,
        )

        if isDirectory {
            state.currentStatus = .windowRouted
            return .send(.delegate(.openFolder(path: path)))
        } else {
            let parentPath = (path as NSString).deletingLastPathComponent
            if context.mode == .reveal {
                state.currentStatus = .parentFolderOpened
                return .concatenate(
                    .send(.delegate(.openParentFolder(path: parentPath, selectEntryPath: path))),
                    .send(.routeCompleted(.entrySelected)),
                )
            } else {
                state.currentStatus = .parentFolderOpened
                return .send(.delegate(.openParentFolder(path: parentPath, selectEntryPath: nil)))
            }
        }
    }

    /// 오류를 상태로 매핑한다.
    ///
    /// - invalidPath → invalidPathError terminal + delegate .showInvalidPathError
    /// - permissionDenied → permissionDeniedError terminal + delegate .showPermissionDeniedError
    /// - urlValidationError → urlValidationError terminal (delegate 없음, ExternalFileRouter 내부 파싱 문제)
    /// - unknown → invalidPathError fallback (delegate 없음)
    func handleFailed(
        error: ExternalFileRouterError,
        context: ExternalFileRouterRequestContext?,
        state: inout State,
    ) -> Effect<Action> {
        if let context {
            state.currentRequest = ExternalFileRouterRequest(
                originalURL: context.requestID,
                source: context.source,
                mode: context.mode,
            )
        }

        switch error {
        case let .invalidPath(path):
            state.currentStatus = .invalidPathError
            return .send(.delegate(.showInvalidPathError(path: path)))
        case let .permissionDenied(path):
            state.currentStatus = .permissionDeniedError
            return .send(.delegate(.showPermissionDeniedError(path: path)))
        case .urlValidationError:
            state.currentStatus = .urlValidationError
            return .none
        case .unknown:
            state.currentStatus = .invalidPathError
            return .none
        }
    }
}
