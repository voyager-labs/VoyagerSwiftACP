import Foundation

struct EntryThumbnailState: Equatable {
    var requestsInFlight: Set<String> = []
    var readyPaths: Set<String> = []
    var failedPaths: Set<String> = []
    var renderVersion: Int = 0
}
