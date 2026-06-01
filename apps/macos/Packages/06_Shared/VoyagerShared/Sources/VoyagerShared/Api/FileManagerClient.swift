import ComposableArchitecture
import Foundation

/// FileManager 관련 primitive 기능을 제공하는 Client
/// Domain semantics (예: trashDirectoryPath, displayName)는 포함하지 않고
/// 순수 파일시스템 primitive만 노출합니다.
public struct FileManagerClient: Sendable {
    // MARK: - Directory Operations

    public var contentsOfDirectory:
        @Sendable (URL, [URLResourceKey]?, FileManager.DirectoryEnumerationOptions) throws -> [URL]
    public var createDirectory:
        @Sendable (URL, Bool, [FileAttributeKey: Any]?) throws -> Void
    public var mountedVolumeURLs:
        @Sendable ([URLResourceKey]?, FileManager.VolumeEnumerationOptions) -> [URL]?
    public var urlsForDirectory:
        @Sendable (FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask) -> [URL]

    // MARK: - File Operations

    public var copyItem: @Sendable (URL, URL) throws -> Void
    public var moveItem: @Sendable (URL, URL) throws -> Void
    public var removeItem: @Sendable (URL) throws -> Void
    public var trashItem: @Sendable (URL) throws -> URL

    // MARK: - File Existence & Attributes

    public var fileExists: @Sendable (String) -> Bool
    public var fileExistsWithIsDirectory:
        @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool
    public var attributesOfItem: @Sendable (String) throws -> [FileAttributeKey: Any]

    // MARK: - Display & Special Paths

    public var displayName: @Sendable (String) -> String
    public var temporaryDirectory: @Sendable () -> URL
    public var currentDirectoryPath: @Sendable () -> String

    nonisolated public init(
        contentsOfDirectory:
        @escaping @Sendable (URL, [URLResourceKey]?, FileManager.DirectoryEnumerationOptions) throws -> [URL],
        createDirectory:
        @escaping @Sendable (URL, Bool, [FileAttributeKey: Any]?) throws -> Void,
        mountedVolumeURLs:
        @escaping @Sendable ([URLResourceKey]?, FileManager.VolumeEnumerationOptions) -> [URL]?,
        urlsForDirectory:
        @escaping @Sendable (FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask) -> [URL],
        copyItem: @escaping @Sendable (URL, URL) throws -> Void,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void,
        removeItem: @escaping @Sendable (URL) throws -> Void,
        trashItem: @escaping @Sendable (URL) throws -> URL,
        fileExists: @escaping @Sendable (String) -> Bool,
        fileExistsWithIsDirectory:
        @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
        attributesOfItem: @escaping @Sendable (String) throws -> [FileAttributeKey: Any],
        displayName: @escaping @Sendable (String) -> String,
        temporaryDirectory: @escaping @Sendable () -> URL,
        currentDirectoryPath: @escaping @Sendable () -> String,
    ) {
        self.contentsOfDirectory = contentsOfDirectory
        self.createDirectory = createDirectory
        self.mountedVolumeURLs = mountedVolumeURLs
        self.urlsForDirectory = urlsForDirectory
        self.copyItem = copyItem
        self.moveItem = moveItem
        self.removeItem = removeItem
        self.trashItem = trashItem
        self.fileExists = fileExists
        self.fileExistsWithIsDirectory = fileExistsWithIsDirectory
        self.attributesOfItem = attributesOfItem
        self.displayName = displayName
        self.temporaryDirectory = temporaryDirectory
        self.currentDirectoryPath = currentDirectoryPath
    }
}

extension FileManagerClient: DependencyKey {
    nonisolated public static var liveValue: FileManagerClient {
        nonisolated(unsafe) let fileManager = FileManager.default
        return FileManagerClient(
            contentsOfDirectory: { url, keys, options in
                try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: options,
                )
            },
            createDirectory: { url, createIntermediates, attributes in
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: createIntermediates,
                    attributes: attributes,
                )
            },
            mountedVolumeURLs: { keys, options in
                fileManager.mountedVolumeURLs(
                    includingResourceValuesForKeys: keys,
                    options: options,
                )
            },
            urlsForDirectory: { directory, domain in
                fileManager.urls(for: directory, in: domain)
            },
            copyItem: { sourceURL, destinationURL in
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            },
            moveItem: { sourceURL, destinationURL in
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            },
            removeItem: { url in
                try fileManager.removeItem(at: url)
            },
            trashItem: { url in
                var result: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &result)
                guard let trashURL = result as URL? else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return trashURL
            },
            fileExists: { path in
                fileManager.fileExists(atPath: path)
            },
            fileExistsWithIsDirectory: { path, isDirectory in
                fileManager.fileExists(atPath: path, isDirectory: isDirectory)
            },
            attributesOfItem: { path in
                try fileManager.attributesOfItem(atPath: path)
            },
            displayName: { path in
                fileManager.displayName(atPath: path)
            },
            temporaryDirectory: {
                fileManager.temporaryDirectory
            },
            currentDirectoryPath: {
                fileManager.currentDirectoryPath
            },
        )
    }

    nonisolated public static var testValue: FileManagerClient {
        FileManagerClient(
            contentsOfDirectory: { _, _, _ in [] },
            createDirectory: { _, _, _ in },
            mountedVolumeURLs: { _, _ in nil },
            urlsForDirectory: { _, _ in [] },
            copyItem: { _, _ in },
            moveItem: { _, _ in },
            removeItem: { _ in },
            trashItem: { _ in URL(fileURLWithPath: "/tmp/.Trash/test") },
            fileExists: { _ in false },
            fileExistsWithIsDirectory: { _, _ in false },
            attributesOfItem: { _ in [:] },
            displayName: { path in path },
            temporaryDirectory: { URL(fileURLWithPath: "/tmp") },
            currentDirectoryPath: { "/" },
        )
    }

    nonisolated public static var previewValue: FileManagerClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var fileManagerClient: FileManagerClient {
        get { self[FileManagerClient.self] }
        set { self[FileManagerClient.self] = newValue }
    }
}
