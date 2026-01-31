import AppKit
import ComposableArchitecture

@MainActor
struct FileManagerWindowClient: Sendable {
    var openWindow: @Sendable (String) async -> Bool
    var focusWindow: @Sendable (String) async -> Void
    var updateFocusHistory: @MainActor (NSWindow?) -> Void
    var updateMenuState: @MainActor (StoreOf<FileManagerFeature>?) -> Void
    var windowWillClose: @MainActor (FileManagerWindowController) -> Void
    var existingWindowSize: @MainActor () -> NSSize?

    init(
        openWindow: @escaping @Sendable (String) async -> Bool,
        focusWindow: @escaping @Sendable (String) async -> Void,
        updateFocusHistory: @escaping @MainActor (NSWindow?) -> Void,
        updateMenuState: @escaping @MainActor (StoreOf<FileManagerFeature>?) -> Void,
        windowWillClose: @escaping @MainActor (FileManagerWindowController) -> Void,
        existingWindowSize: @escaping @MainActor () -> NSSize?,
    ) {
        self.openWindow = openWindow
        self.focusWindow = focusWindow
        self.updateFocusHistory = updateFocusHistory
        self.updateMenuState = updateMenuState
        self.windowWillClose = windowWillClose
        self.existingWindowSize = existingWindowSize
    }
}

extension FileManagerWindowClient: DependencyKey {
    static var liveValue: FileManagerWindowClient {
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

    static var testValue: FileManagerWindowClient {
        FileManagerWindowClient(
            openWindow: { _ in false },
            focusWindow: { _ in },
            updateFocusHistory: { _ in },
            updateMenuState: { _ in },
            windowWillClose: { _ in },
            existingWindowSize: { nil },
        )
    }

    static var previewValue: FileManagerWindowClient {
        FileManagerWindowClient(
            openWindow: { _ in false },
            focusWindow: { _ in },
            updateFocusHistory: { _ in },
            updateMenuState: { _ in },
            windowWillClose: { _ in },
            existingWindowSize: { nil },
        )
    }
}

extension DependencyValues {
    var fileManagerWindowClient: FileManagerWindowClient {
        get { self[FileManagerWindowClient.self] }
        set { self[FileManagerWindowClient.self] = newValue }
    }
}
