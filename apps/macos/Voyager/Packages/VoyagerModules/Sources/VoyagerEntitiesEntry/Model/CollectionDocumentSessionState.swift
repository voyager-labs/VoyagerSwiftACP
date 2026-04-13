import Foundation
import VoyagerShared

public struct CollectionDocumentSessionState: Equatable, Sendable {
    public var isOpening: Bool = false
    public var isStale: Bool = false
    public var openedURL: URL?
    public var openedName: String?
    public var originURL: URL?
    public var baseline: CollectionBaseline?

    public init(
        isOpening: Bool = false,
        isStale: Bool = false,
        openedURL: URL? = nil,
        openedName: String? = nil,
        originURL: URL? = nil,
        baseline: CollectionBaseline? = nil,
    ) {
        self.isOpening = isOpening
        self.isStale = isStale
        self.openedURL = openedURL
        self.openedName = openedName
        self.originURL = originURL
        self.baseline = baseline
    }
}

public struct CollectionBaseline: Equatable, Sendable {
    public var context: CollectionContext
    public var timestamp: Date

    public init(context: CollectionContext, timestamp: Date = Date()) {
        self.context = context
        self.timestamp = timestamp
    }
}
