import ComposableArchitecture
import Foundation

struct FullDiskAccessClient: Sendable {
    var status: @Sendable () -> FullDiskAccessStatus

    nonisolated init(status: @escaping @Sendable () -> FullDiskAccessStatus) {
        self.status = status
    }
}

extension FullDiskAccessClient: DependencyKey {
    nonisolated static var liveValue: FullDiskAccessClient {
        FullDiskAccessClient(status: {
            let fileManager = FileManager.default
            let protectedPaths = [
                "/Library/Application Support/com.apple.TCC/TCC.db",
                "\(NSHomeDirectory())/Library/Safari/Bookmarks.plist",
            ]

            for path in protectedPaths where fileManager.fileExists(atPath: path) {
                return fileManager.isReadableFile(atPath: path) ? .granted : .needsAction
            }

            return .unknown
        })
    }

    nonisolated static var testValue: FullDiskAccessClient {
        FullDiskAccessClient(status: { .unknown })
    }

    nonisolated static var previewValue: FullDiskAccessClient {
        FullDiskAccessClient(status: { .unknown })
    }
}

extension DependencyValues {
    nonisolated var fullDiskAccessClient: FullDiskAccessClient {
        get { self[FullDiskAccessClient.self] }
        set { self[FullDiskAccessClient.self] = newValue }
    }
}
