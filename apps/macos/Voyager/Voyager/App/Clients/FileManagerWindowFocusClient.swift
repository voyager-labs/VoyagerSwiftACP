import AppKit
import ComposableArchitecture

struct FileManagerWindowFocusClient: Sendable {
    var focusWindow: @Sendable (String) async -> Void

    nonisolated init(focusWindow: @escaping @Sendable (String) async -> Void) {
        self.focusWindow = focusWindow
    }
}

extension FileManagerWindowFocusClient: DependencyKey {
    nonisolated static var liveValue: FileManagerWindowFocusClient {
        FileManagerWindowFocusClient(focusWindow: { path in
            await MainActor.run {
                guard let appDelegate = AppDelegate.shared else { return }
                let targetController = appDelegate.windowControllers.first { controller in
                    controller.store.currentPath == path
                }
                targetController?.window?.makeKeyAndOrderFront(nil)
            }
        })
    }

    nonisolated static var testValue: FileManagerWindowFocusClient {
        FileManagerWindowFocusClient(focusWindow: { _ in })
    }

    nonisolated static var previewValue: FileManagerWindowFocusClient {
        FileManagerWindowFocusClient(focusWindow: { _ in })
    }
}

extension DependencyValues {
    nonisolated var fileManagerWindowFocusClient: FileManagerWindowFocusClient {
        get { self[FileManagerWindowFocusClient.self] }
        set { self[FileManagerWindowFocusClient.self] = newValue }
    }
}
