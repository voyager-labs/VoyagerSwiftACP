import AppKit
import ComposableArchitecture

struct FileManagerWindowClient: Sendable {
    var openWindow: @Sendable (String) async -> Bool

    nonisolated init(openWindow: @escaping @Sendable (String) async -> Bool) {
        self.openWindow = openWindow
    }
}

extension FileManagerWindowClient: DependencyKey {
    nonisolated static var liveValue: FileManagerWindowClient {
        FileManagerWindowClient(openWindow: { path in
            await MainActor.run {
                guard let delegate = AppDelegate.shared else { return false }
                delegate.createNewWindow(path: path)
                return true
            }
        })
    }

    nonisolated static var testValue: FileManagerWindowClient {
        FileManagerWindowClient(openWindow: { _ in false })
    }

    nonisolated static var previewValue: FileManagerWindowClient {
        FileManagerWindowClient(openWindow: { _ in false })
    }
}

extension DependencyValues {
    nonisolated var fileManagerWindowClient: FileManagerWindowClient {
        get { self[FileManagerWindowClient.self] }
        set { self[FileManagerWindowClient.self] = newValue }
    }
}
