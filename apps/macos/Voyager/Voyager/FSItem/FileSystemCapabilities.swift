import ComposableArchitecture
import Foundation

public struct FileSystemCapabilities: Equatable, Sendable {
    public var supportsDefaultAppManagement: Bool

    public nonisolated init(supportsDefaultAppManagement: Bool = true) {
        self.supportsDefaultAppManagement = supportsDefaultAppManagement
    }
}

extension FileSystemCapabilities: DependencyKey {
    public nonisolated static var liveValue: FileSystemCapabilities { FileSystemCapabilities() }
    public nonisolated static var testValue: FileSystemCapabilities { FileSystemCapabilities() }
    public nonisolated static var previewValue: FileSystemCapabilities { FileSystemCapabilities() }
}

public extension DependencyValues {
    nonisolated var fileSystemCapabilities: FileSystemCapabilities {
        get { self[FileSystemCapabilities.self] }
        set { self[FileSystemCapabilities.self] = newValue }
    }
}
