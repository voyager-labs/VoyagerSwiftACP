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
            statusFromProtectedReadProbe()
        })
    }

    private nonisolated static func statusFromProtectedReadProbe() -> FullDiskAccessStatus {
        let fileManager = FileManager.default
        let homeDirectory = NSHomeDirectory()

        let probePaths: [String] = [
            homeDirectory + "/Library/Messages",
            homeDirectory + "/Library/Mail",
            homeDirectory + "/Library/Safari",
        ]

        var foundPermissionError = false

        for path in probePaths {
            do {
                _ = try fileManager.contentsOfDirectory(atPath: path)
                return .granted
            } catch {
                if isMissingFileOrDirectoryError(error) {
                    continue
                }
                if isPermissionDeniedError(error) {
                    foundPermissionError = true
                    continue
                }
                foundPermissionError = true
            }
        }

        if foundPermissionError {
            return .needsAction
        }

        return .needsAction
    }

    private nonisolated static func isMissingFileOrDirectoryError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == ENOENT {
            return true
        }
        return false
    }

    private nonisolated static func isPermissionDeniedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == EACCES || nsError.code == EPERM {
            return true
        }
        return false
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
