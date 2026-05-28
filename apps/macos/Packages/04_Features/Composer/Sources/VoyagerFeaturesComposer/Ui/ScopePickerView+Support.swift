import AppKit
import ComposableArchitecture
import CoreGraphics
import Foundation

enum ScopePickerPresentationMetrics {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 520
}

enum ScopePickerAccessibilityID {
    static let surface = "scopeEditor.surface"
    static let searchField = "scopeEditor.searchField"
    static let currentSummary = "scopeEditor.currentSummary"
    static let treeSection = "scopeEditor.treeSection"
    static let noResults = "scopeEditor.noResults"
    static let feedbackBanner = "scopeEditor.feedbackBanner"

    static func treeRow(path: String) -> String {
        "scopeEditor.tree.row.\(slug(for: path))"
    }

    static func treeAction(_ action: ComposerScopeTreeRowAvailableAction, path: String) -> String {
        "scopeEditor.tree.action.\(actionSlug(action)).\(slug(for: path))"
    }

    private static func actionSlug(_ action: ComposerScopeTreeRowAvailableAction) -> String {
        switch action {
        case .include:
            "include"
        case .exclude:
            "exclude"
        case .clearDirectRule:
            "clearDirectRule"
        }
    }

    private static func slug(for path: String) -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        let mapped = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(mapped).replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

enum ScopePickerAssets {
    static let cachedApplicationsIcon: NSImage? = {
        let appIcon = NSImage(contentsOfFile: applicationsIconPath)
        appIcon?.isTemplate = true
        return appIcon
    }()

    private static let applicationsIconPath =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns"
}

extension ComposerScopeEditorListState {
    var noResultsQuery: String? {
        if case let .noResults(query) = self {
            return query
        }
        return nil
    }
}
