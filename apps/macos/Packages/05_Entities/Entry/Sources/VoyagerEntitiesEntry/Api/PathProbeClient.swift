import ComposableArchitecture
import Foundation

// MARK: - PathProbeResult

/// 파일 존재 여부와 디렉토리 여부를 포함하는 조회 결과
public struct PathProbeResult: Equatable, Sendable {
    public let exists: Bool
    public let isDirectory: Bool

    public init(exists: Bool, isDirectory: Bool) {
        self.exists = exists
        self.isDirectory = isDirectory
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
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return PathProbeResult(exists: exists, isDirectory: isDirectory.boolValue)
        })
    }

    nonisolated public static var testValue: PathProbeClient {
        PathProbeClient(probeExistence: { _ in
            fatalError("PathProbeClient is unimplemented")
        })
    }

    nonisolated public static var previewValue: PathProbeClient {
        PathProbeClient(probeExistence: { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return PathProbeResult(exists: exists, isDirectory: isDirectory.boolValue)
        })
    }
}

public extension DependencyValues {
    nonisolated var pathProbeClient: PathProbeClient {
        get { self[PathProbeClient.self] }
        set { self[PathProbeClient.self] = newValue }
    }
}
