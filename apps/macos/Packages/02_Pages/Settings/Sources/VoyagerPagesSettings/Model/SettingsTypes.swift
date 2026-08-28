import Foundation
import VoyagerEntitiesAppPreferences

/// 설정 화면의 섹션 구분
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case ai
    case account

    public static var visibleCases: [Self] {
        allCases.filter { $0 != .account }
    }

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        case .ai:
            "AI"
        case .account:
            "Account"
        }
    }

    public var iconName: String {
        switch self {
        case .general:
            "gear"
        case .appearance:
            "paintbrush"
        case .ai:
            "sparkle"
        case .account:
            "person.crop.circle"
        }
    }
}

public enum DirectoryOption: Equatable, Hashable, Identifiable, Sendable {
    case home
    case root
    case desktop
    case documents
    case downloads
    case custom(String)
    case other

    public static var standardOptions: [DirectoryOption] {
        [.home, .root, .desktop, .documents, .downloads]
    }

    public var id: String {
        switch self {
        case .home: "home"
        case .root: "root"
        case .desktop: "desktop"
        case .documents: "documents"
        case .downloads: "downloads"
        case let .custom(path): "custom:\(path)"
        case .other: "other"
        }
    }

    public var iconName: String {
        switch self {
        case .home:
            "house.fill"
        case .root:
            "internaldrive.fill"
        case .desktop:
            "desktopcomputer"
        case .documents:
            "doc.text.fill"
        case .downloads:
            "arrow.down.circle.fill"
        case .custom, .other:
            "folder.fill"
        }
    }

    public static func from(path: String, using directories: StandardDirectories) -> DirectoryOption {
        if path == directories.homePath {
            .home
        } else if path == "/" {
            .root
        } else if path == directories.desktopPath {
            .desktop
        } else if path == directories.documentsPath {
            .documents
        } else if path == directories.downloadsPath {
            .downloads
        } else {
            .custom(path)
        }
    }

    public func displayName(using directories: StandardDirectories) -> String {
        switch self {
        case .home:
            directories.homeDisplayName
        case .root:
            "Macintosh HD"
        case .desktop:
            "Desktop"
        case .documents:
            "Documents"
        case .downloads:
            "Downloads"
        case let .custom(path):
            URL(fileURLWithPath: path).lastPathComponent
        case .other:
            "Other..."
        }
    }

    public func path(using directories: StandardDirectories) -> String? {
        switch self {
        case .home:
            directories.homePath
        case .root:
            "/"
        case .desktop:
            directories.desktopPath
        case .documents:
            directories.documentsPath
        case .downloads:
            directories.downloadsPath
        case let .custom(path):
            path
        case .other:
            nil
        }
    }
}

public enum StartPageOption: Equatable, Hashable, Identifiable, Sendable {
    case home
    case homeDirectory
    case desktop
    case documents
    case downloads
    case custom(String)
    case other

    /// `.custom`은 저장값 재투영 전용 — 메뉴 항목(allCases)에서는 제외된다.
    public static let allCases: [Self] = [.home, .homeDirectory, .desktop, .documents, .downloads, .other]

    public var id: String {
        switch self {
        case .home: "home"
        case .homeDirectory: "homeDirectory"
        case .desktop: "desktop"
        case .documents: "documents"
        case .downloads: "downloads"
        case let .custom(path): "custom:\(path)"
        case .other: "other"
        }
    }

    public var iconName: String {
        switch self {
        case .home, .homeDirectory: "house.fill"
        case .desktop: "desktopcomputer"
        case .documents: "doc.text.fill"
        case .downloads: "arrow.down.circle.fill"
        case .custom, .other: "folder.fill"
        }
    }

    public static func from(_ startPage: StartPage, using directories: StandardDirectories) -> Self {
        switch startPage {
        case .home:
            return home
        case let .directory(path):
            if path == directories.homePath { return .homeDirectory }
            if path == directories.desktopPath { return .desktop }
            if path == directories.documentsPath { return .documents }
            if path == directories.downloadsPath { return .downloads }
            return .custom(path)
        }
    }

    public func displayName(using directories: StandardDirectories) -> String {
        switch self {
        case .home: "Home"
        case .homeDirectory: directories.homeDisplayName
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case let .custom(path): URL(fileURLWithPath: path).lastPathComponent
        case .other: "Other…"
        }
    }

    public func startPage(using directories: StandardDirectories) -> StartPage? {
        switch self {
        case .home:
            .home
        case .homeDirectory:
            .directory(directories.homePath)
        case .desktop:
            directories.desktopPath.map(StartPage.directory)
        case .documents:
            directories.documentsPath.map(StartPage.directory)
        case .downloads:
            directories.downloadsPath.map(StartPage.directory)
        case let .custom(path):
            .directory(path)
        case .other:
            nil
        }
    }
}
