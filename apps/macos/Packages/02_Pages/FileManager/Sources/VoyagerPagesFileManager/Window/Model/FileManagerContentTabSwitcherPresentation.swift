public enum ContentTabSwitcherFocusDirection: Equatable, Sendable {
    case next
    case previous
}

public struct FileManagerContentTabSwitcherPresentation: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case automatic
        case keyboardShortcut
        case loading
        case error(message: String)

        var isInteractive: Bool {
            switch self {
            case .automatic, .keyboardShortcut:
                true
            case .loading, .error:
                false
            }
        }
    }

    public let source: Source
    public let candidateIDs: [ContentTabID]
    public let focusedCandidateID: ContentTabID?

    public init(
        source: Source,
        candidateIDs: [ContentTabID] = [],
        focusedCandidateID: ContentTabID? = nil,
    ) {
        self.source = source
        self.candidateIDs = candidateIDs
        self.focusedCandidateID = focusedCandidateID
    }

    public init(source: Source, contentTabs: ContentTabState) {
        self.init(
            source: source,
            candidateIDs: Self.candidateIDs(source: source, contentTabs: contentTabs),
            focusedCandidateID: Self.initialFocus(source: source, contentTabs: contentTabs),
        )
    }

    private static func candidateIDs(
        source: Source,
        contentTabs: ContentTabState,
    ) -> [ContentTabID] {
        guard source.isInteractive,
              case let .candidates(candidates) = ContentTabSwitcherProjection.project(from: contentTabs)
        else { return [] }
        return candidates.map(\.id)
    }

    private static func initialFocus(
        source: Source,
        contentTabs: ContentTabState,
    ) -> ContentTabID? {
        guard source.isInteractive,
              case let .candidates(candidates) = ContentTabSwitcherProjection.project(from: contentTabs)
        else { return nil }
        return candidates.first(where: { $0.isCurrent })?.id ?? candidates.first?.id
    }
}

func reconcileContentTabSwitcherPresentation(state: inout FileManagerWindowState) {
    guard let presentation = state.contentTabSwitcherPresentation,
          presentation.source.isInteractive
    else { return }

    let liveIDs: [ContentTabID] = switch ContentTabSwitcherProjection.project(from: state.contentTabs) {
    case let .candidates(candidates): candidates.map(\.id)
    case .invalidActiveTabIdentity: []
    }
    let focusedCandidateID: ContentTabID? = if liveIDs.isEmpty {
        nil
    } else if let focusedID = presentation.focusedCandidateID,
              liveIDs.contains(focusedID)
    {
        focusedID
    } else if let focusedID = presentation.focusedCandidateID,
              let oldIndex = presentation.candidateIDs.firstIndex(of: focusedID)
    {
        liveIDs[min(oldIndex, liveIDs.count - 1)]
    } else {
        liveIDs.first
    }

    let reconciled = FileManagerContentTabSwitcherPresentation(
        source: presentation.source,
        candidateIDs: liveIDs,
        focusedCandidateID: focusedCandidateID,
    )
    if reconciled != presentation {
        state.contentTabSwitcherPresentation = reconciled
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
        let isFocused: Bool

        init(
            _ candidate: ContentTabSwitcherProjection.Candidate,
            focusedCandidateID: ContentTabID?,
        ) {
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
            isFocused = candidate.id == focusedCandidateID
        }
    }

    struct Status: Equatable {
        let message: String
        let accessibilityLabel: String
    }

    static func make(
        source: FileManagerContentTabSwitcherPresentation.Source,
        contentTabs: ContentTabState,
        focusedCandidateID: ContentTabID? = nil,
    ) -> Self {
        switch source {
        case .automatic, .keyboardShortcut:
            switch ContentTabSwitcherProjection.project(from: contentTabs) {
            case let .candidates(candidates):
                guard !candidates.isEmpty else {
                    return .empty(.init(message: "No recent tabs", accessibilityLabel: "No recent tabs"))
                }
                return .content(candidates.map {
                    Row($0, focusedCandidateID: focusedCandidateID)
                })

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
