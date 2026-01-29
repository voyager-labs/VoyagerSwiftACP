import ComposableArchitecture
import Foundation

struct CollectionFileClient: Sendable {
    var save: @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void
    var load: @Sendable (_ url: URL) async throws -> VoyagerCollectionFile
}

extension CollectionFileClient: DependencyKey {
    // `.voycoll`은 Finder에서 패키지(디렉터리)로 보이도록 저장한다.
    // 기존에 단일 바이너리 파일로 저장된 레거시(.voycoll 파일)도 읽기 호환을 유지한다.
    static let liveValue: CollectionFileClient = .init(
        save: { file, url in
            let packagePayloadFilename = "collection.plist"
            let data = try await MainActor.run {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                return try encoder.encode(file)
            }
            let fileManager = FileManager.default

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists, !isDirectory.boolValue {
                // 동일 경로에 파일이 있으면 패키지 디렉터리로 교체한다.
                try fileManager.removeItem(at: url)
            }

            if !exists || !isDirectory.boolValue {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            }

            let payloadURL = url.appendingPathComponent(packagePayloadFilename)
            try data.write(to: payloadURL, options: [.atomic])
        },
        load: { url in
            let packagePayloadFilename = "collection.plist"
            let fileManager = FileManager.default

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let payloadURL = url.appendingPathComponent(packagePayloadFilename)
                let payloadExists = fileManager.fileExists(atPath: payloadURL.path, isDirectory: nil)
                guard payloadExists else {
                    throw CocoaError(.fileReadNoSuchFile, userInfo: [
                        NSLocalizedDescriptionKey: "Missing \(packagePayloadFilename) in .voycoll package.",
                    ])
                }
                let data = try Data(contentsOf: payloadURL)
                return try await MainActor.run {
                    let decoder = PropertyListDecoder()
                    return try decoder.decode(VoyagerCollectionFile.self, from: data)
                }
            }

            // 레거시: 단일 파일로 저장된 `.voycoll`도 열 수 있도록 유지
            let data = try Data(contentsOf: url)
            return try await MainActor.run {
                let decoder = PropertyListDecoder()
                return try decoder.decode(VoyagerCollectionFile.self, from: data)
            }
        },
    )

    nonisolated(unsafe) static var testValue: CollectionFileClient = .init(
        save: { _, _ in },
        load: { _ in
            VoyagerCollectionFile(
                schemaVersion: 0,
                id: "",
                name: "",
                createdAt: .distantPast,
                updatedAt: .distantPast,
                query: "",
                scopes: [],
                conditions: [],
                sortKey: nil,
                sortOrder: nil,
                viewLayout: nil,
                appVersion: nil,
            )
        },
    )
}

extension DependencyValues {
    nonisolated var collectionFileClient: CollectionFileClient {
        get { self[CollectionFileClient.self] }
        set { self[CollectionFileClient.self] = newValue }
    }
}
