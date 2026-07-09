import ComposableArchitecture
import Foundation

// MARK: - PathProbeResult

/// 파일 존재 여부, 디렉토리 여부, 권한 오류 여부를 포함하는 조회 결과
public struct PathProbeResult: Equatable, Sendable {
    public let exists: Bool
    public let isDirectory: Bool
    public let permissionDenied: Bool

    public init(exists: Bool, isDirectory: Bool, permissionDenied: Bool = false) {
        self.exists = exists
        self.isDirectory = isDirectory
        self.permissionDenied = permissionDenied
    }
}

// MARK: - PathProbeClient

/// 파일시스템 경로 존재 및 타입 확인을 추상화하는 TCA Dependency
public struct PathProbeClient: Sendable {
    public var probeExistence: @Sendable (String) -> PathProbeResult

    nonisolated public init(
        probeExistence: @escaping @Sendable (String) -> PathProbeResult,
    ) {
        self.probeExistence = probeExistence
    }
}

extension PathProbeClient: DependencyKey {
    nonisolated public static var liveValue: PathProbeClient {
        PathProbeClient(probeExistence: { path in
            var statBuffer = stat()
            let statResult = stat(path, &statBuffer)
            if statResult == 0 {
                return PathProbeResult(
                    exists: true,
                    isDirectory: (statBuffer.st_mode & S_IFMT) == S_IFDIR,
                    permissionDenied: false,
                )
            } else {
                let isPermissionDenied = errno == EACCES || errno == EPERM
                return PathProbeResult(
                    exists: false,
                    isDirectory: false,
                    permissionDenied: isPermissionDenied,
                )
            }
        })
    }

    nonisolated public static var testValue: PathProbeClient {
        PathProbeClient(probeExistence: { _ in
            fatalError("PathProbeClient is unimplemented")
        })
    }

    nonisolated public static var previewValue: PathProbeClient {
        PathProbeClient(probeExistence: { path in
            var statBuffer = stat()
            let statResult = stat(path, &statBuffer)
            if statResult == 0 {
                return PathProbeResult(
                    exists: true,
                    isDirectory: (statBuffer.st_mode & S_IFMT) == S_IFDIR,
                    permissionDenied: false,
                )
            } else {
                let isPermissionDenied = errno == EACCES || errno == EPERM
                return PathProbeResult(
                    exists: false,
                    isDirectory: false,
                    permissionDenied: isPermissionDenied,
                )
            }
        })
    }
}

public extension DependencyValues {
    nonisolated var pathProbeClient: PathProbeClient {
        get { self[PathProbeClient.self] }
        set { self[PathProbeClient.self] = newValue }
    }
}
