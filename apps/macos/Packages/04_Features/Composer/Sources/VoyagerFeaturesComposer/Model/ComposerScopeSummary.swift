import Foundation

enum ComposerScopeSummaryPrimary: Equatable, Hashable {
    case rootOnly
    case singleExplicit(path: String)
    case multiExplicit(count: Int)
}

enum ComposerScopeSummarySecondary: Equatable, Hashable {
    case includeSubfolders
    case onlySelectedFolder
    case onlySelectedFolders
}

enum ComposerScopeSummaryBadge: Equatable, Hashable {
    case exceptionCount(Int)
}

struct ComposerScopeSummary: Equatable, Hashable {
    let primary: ComposerScopeSummaryPrimary
    let secondaryItems: [ComposerScopeSummarySecondary]
    let badges: [ComposerScopeSummaryBadge]

    var primaryText: String {
        switch primary {
        case .rootOnly:
            "This Mac"
        case let .singleExplicit(path):
            Self.displayName(for: path)
        case let .multiExplicit(count):
            count == 1 ? "1 Scope" : "\(count) Scopes"
        }
    }

    var secondaryText: String? {
        let text = secondaryItems.map(\.text).joined(separator: " • ")
        return text.isEmpty ? nil : text
    }

    var badgeText: String? {
        guard exceptionCount > 0 else { return nil }
        return exceptionCount == 1 ? "1 exception" : "\(exceptionCount) exceptions"
    }

    var accessibilityText: String {
        [accessibilityPrimaryText, secondaryText, badgeText]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    var exceptionCount: Int {
        badges.reduce(into: 0) { partialResult, item in
            guard case let .exceptionCount(count) = item else { return }
            partialResult += count
        }
    }

    private var accessibilityPrimaryText: String {
        switch primary {
        case .rootOnly, .multiExplicit:
            return primaryText
        case let .singleExplicit(path):
            let displayName = Self.displayName(for: path)
            return displayName == path ? displayName : "\(displayName), \(path)"
        }
    }

    private static func displayName(for path: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let displayName = URL(fileURLWithPath: normalizedPath).lastPathComponent
        return displayName.isEmpty ? normalizedPath : displayName
    }
}

private extension ComposerScopeSummarySecondary {
    var text: String {
        switch self {
        case .includeSubfolders:
            "Include subfolders"
        case .onlySelectedFolder:
            "Only selected folder"
        case .onlySelectedFolders:
            "Only selected folders"
        }
    }
}
