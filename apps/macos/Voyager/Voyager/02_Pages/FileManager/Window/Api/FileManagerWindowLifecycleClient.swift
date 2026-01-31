import AppKit
import ComposableArchitecture

@MainActor
struct FileManagerWindowLifecycleClient: Sendable {
    var updateFocusHistory: @MainActor (NSWindow?) -> Void
    var updateMenuState: @MainActor (StoreOf<FileManagerFeature>?) -> Void
    var windowWillClose: @MainActor (FileManagerWindowController) -> Void
    var existingWindowSize: @MainActor () -> NSSize?

    init(
        updateFocusHistory: @escaping @MainActor (NSWindow?) -> Void,
        updateMenuState: @escaping @MainActor (StoreOf<FileManagerFeature>?) -> Void,
        windowWillClose: @escaping @MainActor (FileManagerWindowController) -> Void,
        existingWindowSize: @escaping @MainActor () -> NSSize?,
    ) {
        self.updateFocusHistory = updateFocusHistory
        self.updateMenuState = updateMenuState
        self.windowWillClose = windowWillClose
        self.existingWindowSize = existingWindowSize
    }
}

extension FileManagerWindowLifecycleClient: DependencyKey {
    static var liveValue: FileManagerWindowLifecycleClient {
        FileManagerWindowLifecycleClient(
            updateFocusHistory: { window in
                FileManagerWindowCoordinator.shared.updateFocusHistory(window: window)
            },
            updateMenuState: { store in
                FileManagerWindowCoordinator.shared.updateMenuState(store: store)
            },
            windowWillClose: { controller in
                FileManagerWindowCoordinator.shared.windowWillClose(controller: controller)
            },
            existingWindowSize: {
                FileManagerWindowCoordinator.shared.windowControllers.first?.window?.frame.size
            },
        )
    }

    static var testValue: FileManagerWindowLifecycleClient {
        FileManagerWindowLifecycleClient(
            updateFocusHistory: { _ in },
            updateMenuState: { _ in },
            windowWillClose: { _ in },
            existingWindowSize: { nil },
        )
    }

    static var previewValue: FileManagerWindowLifecycleClient {
        FileManagerWindowLifecycleClient(
            updateFocusHistory: { _ in },
            updateMenuState: { _ in },
            windowWillClose: { _ in },
            existingWindowSize: { nil },
        )
    }
}

extension DependencyValues {
    var fileManagerWindowLifecycleClient: FileManagerWindowLifecycleClient {
        get { self[FileManagerWindowLifecycleClient.self] }
        set { self[FileManagerWindowLifecycleClient.self] = newValue }
    }
}
