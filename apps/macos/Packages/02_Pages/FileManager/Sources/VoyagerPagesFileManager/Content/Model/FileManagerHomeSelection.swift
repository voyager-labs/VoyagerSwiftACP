import Foundation

public enum FileManagerHomeSelection: Equatable, Hashable, Sendable {
    case fixedDirectory(FileManagerHomeDirectory)
    case openDirectory
    case openCollection
    case startAiChat
}

public enum FileManagerHomeDirectory: Equatable, Hashable, Sendable, CaseIterable {
    case desktop
    case documents
    case downloads
    case applications
}
