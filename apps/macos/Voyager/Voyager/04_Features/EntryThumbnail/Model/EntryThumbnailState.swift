import Foundation

struct EntryThumbnailState: Equatable, Sendable {
    var requestsInFlight: Set<String> = []
    var readyPaths: Set<String> = []
    var failedPaths: Set<String> = []
    var renderVersion: Int = 0
}
