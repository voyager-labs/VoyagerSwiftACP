import ComposableArchitecture
import Foundation

public struct FileSystemCapabilities: Equatable, Sendable {
    public var supportsDefaultAppManagement: Bool

    public init(supportsDefaultAppManagement: Bool = true) {
        self.supportsDefaultAppManagement = supportsDefaultAppManagement
    }
}

extension FileSystemCapabilities: DependencyKey {
    public static var liveValue: FileSystemCapabilities { FileSystemCapabilities() }
    public static var testValue: FileSystemCapabilities { FileSystemCapabilities() }
    public static var previewValue: FileSystemCapabilities { FileSystemCapabilities() }
}

public extension DependencyValues {
    var fileSystemCapabilities: FileSystemCapabilities {
        get { self[FileSystemCapabilities.self] }
        set { self[FileSystemCapabilities.self] = newValue }
    }
}
