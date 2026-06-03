import ComposableArchitecture
import Foundation
import VoyagerShared

public struct CollectionFileClient: Sendable {
    public var save: @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void
    public var load: @Sendable (_ url: URL) async throws -> CollectionFileLoadResult

    public init(
        save: @escaping @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void,
        load: @escaping @Sendable (_ url: URL) async throws -> CollectionFileLoadResult,
    ) {
        self.save = save
        self.load = load
    }
}

extension CollectionFileClient: DependencyKey {
    /// `.voycoll`은 Finder에서 패키지(디렉터리)로 보이도록 저장한다.
    /// 기존에 단일 바이너리 파일로 저장된 레거시(.voycoll 파일)도 읽기 호환을 유지한다.
    public static let liveValue: CollectionFileClient = .init(
        save: { file, url in
            let packagePayloadFilename = "collection.plist"
            let data = try await MainActor.run {
                try VoyagerCollectionFileCompatibilityOwner.encodeCurrent(file)
            }
            let fileManagerClient = FileManagerClient.liveValue

            var isDirectory: ObjCBool = false
            let exists = fileManagerClient.fileExistsWithIsDirectory(url.path, &isDirectory)
            if exists, !isDirectory.boolValue {
                // 동일 경로에 파일이 있으면 패키지 디렉터리로 교체한다.
                try fileManagerClient.removeItem(url)
            }

            if !exists || !isDirectory.boolValue {
                try fileManagerClient.createDirectory(url, false, nil)
            }

            let payloadURL = url.appendingPathComponent(packagePayloadFilename)
            try data.write(to: payloadURL, options: [.atomic])
        },
        load: { url in
            let packagePayloadFilename = "collection.plist"
            let fileManagerClient = FileManagerClient.liveValue

            var isDirectory: ObjCBool = false
            if fileManagerClient.fileExistsWithIsDirectory(url.path, &isDirectory), isDirectory.boolValue {
                let payloadURL = url.appendingPathComponent(packagePayloadFilename)
                let payloadExists = fileManagerClient.fileExists(payloadURL.path)
                guard payloadExists else {
                    throw CollectionFileCompatibilityError.missingPackagePayload
                }
                let data = try Data(contentsOf: payloadURL)
                return try await MainActor.run {
                    try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)
                }
            }

            // 레거시: 단일 파일로 저장된 `.voycoll`도 열 수 있도록 유지
            let data = try Data(contentsOf: url)
            return try await MainActor.run {
                try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .legacySingleFile)
            }
        },
    )

    nonisolated(unsafe) public static var testValue: CollectionFileClient = .init(
        save: { _, _ in },
        load: { _ in
            VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
                file: VoyagerCollectionFile(
                    id: "",
                    name: "",
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    query: "",
                    scopes: [],
                    conditions: [],
                    snapshot: nil,
                    snapshotMeta: nil,
                    appVersion: nil,
                ),
                containerFormat: .package,
                sourceSchemaVersion: CollectionFileSchemaVersion.current,
                warning: nil,
                usedDefinitionFallback: false,
            )
        },
    )
}

public extension DependencyValues {
    nonisolated var collectionFileClient: CollectionFileClient {
        get { self[CollectionFileClient.self] }
        set { self[CollectionFileClient.self] = newValue }
    }
}
