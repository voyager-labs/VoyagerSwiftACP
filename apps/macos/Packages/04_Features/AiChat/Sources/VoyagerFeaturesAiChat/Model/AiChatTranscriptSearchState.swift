import Foundation

public enum AiChatTranscriptSearchStatus: Equatable, Sendable {
    case matches
    case noResults
}

public struct AiChatTranscriptSearchMatchCountProjection: Equatable, Sendable {
    public var query: String
    public var matchCount: Int

    public init(query: String, matchCount: Int) {
        self.query = query
        self.matchCount = max(0, matchCount)
    }
}

public struct AiChatTranscriptSearchState: Equatable, Sendable {
    public var isPresented: Bool
    public var query: String
    public var matchCount: Int?
    public var currentMatchOrdinal: Int?
    public var status: AiChatTranscriptSearchStatus?
    public var navigationRevision: UInt64

    public init(
        isPresented: Bool = false,
        query: String = "",
        matchCount: Int? = nil,
        currentMatchOrdinal: Int? = nil,
        status: AiChatTranscriptSearchStatus? = nil,
        navigationRevision: UInt64 = 0,
    ) {
        self.isPresented = isPresented
        self.query = query
        self.matchCount = matchCount
        self.currentMatchOrdinal = currentMatchOrdinal
        self.status = status
        self.navigationRevision = navigationRevision
    }

    mutating func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        clearResults()
    }

    mutating func updateMatchCount(_ projection: AiChatTranscriptSearchMatchCountProjection) {
        guard !query.isEmpty, projection.query == query else { return }

        matchCount = projection.matchCount
        guard projection.matchCount > 0 else {
            currentMatchOrdinal = 0
            status = .noResults
            return
        }

        currentMatchOrdinal = min(max(currentMatchOrdinal ?? 1, 1), projection.matchCount)
        status = .matches
    }

    mutating func selectNextMatch() {
        guard status == .matches, let matchCount, matchCount > 0 else { return }
        let currentOrdinal = min(max(currentMatchOrdinal ?? 1, 1), matchCount)
        currentMatchOrdinal = currentOrdinal == matchCount ? 1 : currentOrdinal + 1
        navigationRevision &+= 1
    }

    mutating func selectPreviousMatch() {
        guard status == .matches, let matchCount, matchCount > 0 else { return }
        let currentOrdinal = min(max(currentMatchOrdinal ?? 1, 1), matchCount)
        currentMatchOrdinal = currentOrdinal == 1 ? matchCount : currentOrdinal - 1
        navigationRevision &+= 1
    }

    mutating func reset() {
        self = .init()
    }

    private mutating func clearResults() {
        matchCount = nil
        currentMatchOrdinal = nil
        status = nil
    }
}
