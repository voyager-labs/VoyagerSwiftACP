import AppKit
import ComposableArchitecture

struct FileManagerWindowClient: Sendable {
    var openWindow: @Sendable (String) async -> Bool
    var focusWindow: @Sendable (String) async -> Void

    nonisolated init(
        openWindow: @escaping @Sendable (String) async -> Bool,
        focusWindow: @escaping @Sendable (String) async -> Void,
    ) {
        self.openWindow = openWindow
        self.focusWindow = focusWindow
    }
}

extension FileManagerWindowClient: DependencyKey {
    nonisolated static var liveValue: FileManagerWindowClient {
        FileManagerWindowClient(
            openWindow: { path in
                await MainActor.run {
                    FileManagerWindowCoordinator.shared.createNewWindow(path: path) != nil
                }
            },
            focusWindow: { path in
                await MainActor.run {
                    FileManagerWindowCoordinator.shared.focusWindow(path: path)
                }
            },
        )
    }

    nonisolated static var testValue: FileManagerWindowClient {
        FileManagerWindowClient(openWindow: { _ in false }, focusWindow: { _ in })
    }

    nonisolated static var previewValue: FileManagerWindowClient {
        FileManagerWindowClient(openWindow: { _ in false }, focusWindow: { _ in })
    }
}

extension DependencyValues {
    nonisolated var fileManagerWindowClient: FileManagerWindowClient {
        get { self[FileManagerWindowClient.self] }
        set { self[FileManagerWindowClient.self] = newValue }
    }
}
