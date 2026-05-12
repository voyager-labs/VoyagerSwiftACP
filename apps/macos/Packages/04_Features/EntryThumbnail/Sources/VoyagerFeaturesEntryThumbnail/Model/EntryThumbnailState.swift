import Foundation

public struct EntryThumbnailState: Equatable, Sendable {
    public var requestsInFlight: Set<String> = []
    public var readyPaths: Set<String> = []
    public var failedPaths: Set<String> = []
    public var renderVersion: Int = 0

    public init(
        requestsInFlight: Set<String> = [],
        readyPaths: Set<String> = [],
        failedPaths: Set<String> = [],
        renderVersion: Int = 0
    ) {
        self.requestsInFlight = requestsInFlight
        self.readyPaths = readyPaths
        self.failedPaths = failedPaths
        self.renderVersion = renderVersion
    }
}
