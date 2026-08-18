public struct FileManagerContentTabSwitcherPresentation: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case automatic
        case loading
        case error(message: String)
    }

    public let source: Source

    public init(source: Source) {
        self.source = source
    }
}

enum ContentTabSwitcherViewState: Equatable {
    case loading(Status)
    case content([Row])
    case empty(Status)
    case error(Status)

    struct Row: Equatable, Identifiable {
        let id: ContentTabID
        let title: String
        let iconName: String
        let pageLabel: String
        let anchorSummary: String
        let isCurrent: Bool
        let accessibilityIdentifier: String
        let accessibilityLabel: String
        let accessibilityValue: String
        let isIconAccessibilityHidden: Bool

        init(_ candidate: ContentTabSwitcherProjection.Candidate) {
            id = candidate.id
            title = candidate.title
            iconName = candidate.iconName
            pageLabel = candidate.pageLabel
            anchorSummary = candidate.anchorSummary
            isCurrent = candidate.isCurrent
            accessibilityIdentifier = candidate.accessibilityIdentifier
            accessibilityLabel = candidate.accessibilityLabel
            accessibilityValue = candidate.accessibilityValue
            isIconAccessibilityHidden = true
        }
    }

    struct Status: Equatable {
        let message: String
        let accessibilityLabel: String
    }

    static func make(
        source: FileManagerContentTabSwitcherPresentation.Source,
        contentTabs: ContentTabState,
    ) -> Self {
        switch source {
        case .automatic:
            switch ContentTabSwitcherProjection.project(from: contentTabs) {
            case let .candidates(candidates):
                guard !candidates.isEmpty else {
                    return .empty(.init(message: "No recent tabs", accessibilityLabel: "No recent tabs"))
                }
                return .content(candidates.map(Row.init))

            case .invalidActiveTabIdentity:
                return error(message: "Unable to load recent tabs.")
            }

        case .loading:
            return .loading(.init(
                message: "Loading recent tabs",
                accessibilityLabel: "Loading recent tabs",
            ))

        case let .error(message):
            return error(message: message)
        }
    }

    private static func error(message: String) -> Self {
        .error(.init(message: message, accessibilityLabel: message))
    }
}
