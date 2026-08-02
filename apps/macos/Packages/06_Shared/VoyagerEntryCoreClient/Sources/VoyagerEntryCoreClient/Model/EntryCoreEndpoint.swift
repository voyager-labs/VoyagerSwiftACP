import Darwin

nonisolated public struct EntryCoreEndpoint: Equatable, Sendable {
    public let path: String

    public init(path: String) throws {
        let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard
            !path.isEmpty,
            path.first == "/",
            !path.contains("\0"),
            path.utf8.count + 1 <= sunPathCapacity
        else {
            throw EntryCoreClientError.invalidEndpoint
        }

        self.path = path
    }
}
