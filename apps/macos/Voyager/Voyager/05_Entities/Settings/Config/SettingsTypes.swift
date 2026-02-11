import CoreGraphics
import Foundation

/// 앱 테마 설정 (라이트/다크/시스템)
public enum AppTheme: String, CaseIterable, Equatable, Sendable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:
            "Light"
        case .dark:
            "Dark"
        case .system:
            "Auto"
        }
    }
}

/// 설정 화면의 섹션 구분
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            "gear"
        case .appearance:
            "paintbrush"
        }
    }
}

enum DirectoryOption: Equatable, Hashable, Identifiable {
    case home
    case root
    case desktop
    case documents
    case downloads
    case custom(String)
    case other

    var id: String {
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

    var displayName: String {
        switch self {
        case .home:
            FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
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

    var iconName: String {
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

    var path: String? {
        switch self {
        case .home:
            FileManager.default.homeDirectoryForCurrentUser.path
        case .root:
            "/"
        case .desktop:
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
        case .documents:
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        case .downloads:
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        case let .custom(path):
            path
        case .other:
            nil
        }
    }

    static func from(path: String) -> DirectoryOption {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let rootPath = "/"

        if path == homePath {
            return .home
        } else if path == rootPath {
            return .root
        } else if let desktopPath = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask)
            .first?.path,
            path == desktopPath
        {
            return .desktop
        } else if let documentsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?.path,
            path == documentsPath
        {
            return .documents
        } else if let downloadsPath = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?.path,
            path == downloadsPath
        {
            return .downloads
        } else {
            return .custom(path)
        }
    }

    static var standardOptions: [DirectoryOption] {
        [.home, .root, .desktop, .documents, .downloads]
    }
}

enum AppearanceSettingsDefaults {
    static let listIconSize: CGFloat = 20
    static let gridIconSize: CGFloat = 64
    static let listTextSize: CGFloat = 13
    static let gridTextSize: CGFloat = 12
}
