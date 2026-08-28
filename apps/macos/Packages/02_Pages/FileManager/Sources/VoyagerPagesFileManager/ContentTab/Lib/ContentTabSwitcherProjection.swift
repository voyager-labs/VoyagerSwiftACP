import Foundation

enum ContentTabSwitcherProjection {
    enum Output: Equatable {
        case candidates([Candidate])
        case invalidActiveTabIdentity
    }

    struct Candidate: Equatable, Identifiable {
        let id: ContentTabID
        let title: String
        let iconName: String
        let pageLabel: String
        let anchorSummary: String
        let isCurrent: Bool
        let accessibilityIdentifier: String
        let accessibilityLabel: String
        let accessibilityValue: String
    }

    static let maximumCandidateCount = 10

    static func project(from state: ContentTabState) -> Output {
        guard let activeTabID = state.activeTabID else {
            return state.tabs.isEmpty ? .candidates([]) : .invalidActiveTabIdentity
        }
        guard state.tabs[id: activeTabID] != nil else {
            return .invalidActiveTabIdentity
        }

        let liveTabIDs = Set(state.tabs.ids)
        var seenTabIDs = Set<ContentTabID>()
        let mruTabIDs = state.recentlyUsedTabIDs.filter {
            liveTabIDs.contains($0) && seenTabIDs.insert($0).inserted
        }

        return .candidates(mruTabIDs.prefix(maximumCandidateCount).compactMap { tabID in
            state.tabs[id: tabID].map { candidate(from: $0, activeTabID: activeTabID) }
        })
    }

    private static func candidate(from tab: ContentTabItem, activeTabID: ContentTabID) -> Candidate {
        let title = normalized(tab.title, fallback: "Untitled")
        let iconName = iconName(for: tab)
        let pageLabel = pageLabel(for: tab.page)
        let anchorSummary = anchorSummary(for: tab.anchor)
        let isCurrent = tab.id == activeTabID
        let accessibilityValue = "\(pageLabel); \(anchorSummary)" + (isCurrent ? "; Current" : "")
        return Candidate(
            id: tab.id,
            title: title,
            iconName: iconName,
            pageLabel: pageLabel,
            anchorSummary: anchorSummary,
            isCurrent: isCurrent,
            accessibilityIdentifier: "file-manager.content-tab-switcher.row.\(tab.id.rawValue)",
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue,
        )
    }

    private static func normalized(_ value: String?, fallback: String) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? fallback : normalized
    }

    private static func iconName(for tab: ContentTabItem) -> String {
        switch tab.anchor {
        case .collectionFile:
            "rectangle.stack"
        case let .virtualCollection(id):
            id == "Recents" ? "clock" : "folder"
        default:
            normalized(tab.iconName, fallback: "doc")
        }
    }

    private static func pageLabel(for page: ContentTabPage) -> String {
        switch page {
        case .home:
            "Home"
        case .directory:
            "Directory"
        case .collection:
            "Collection"
        case .aiChat:
            "AI Chat"
        }
    }

    private static func anchorSummary(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "Home"
        case let .directory(path):
            directorySummary(for: path)
        case let .collectionFile(url):
            collectionSummary(for: url)
        case .virtualCollection:
            "Virtual Collection"
        case .aiChat:
            "AI Chat"
        }
    }

    private static func directorySummary(for path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "Directory" }

        let url = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        if url.path == "/" {
            return "/"
        }
        return normalized(url.lastPathComponent, fallback: "Directory")
    }

    private static func collectionSummary(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.path != "/" else { return "Collection" }
        return normalized(standardizedURL.lastPathComponent, fallback: "Collection")
    }
}
