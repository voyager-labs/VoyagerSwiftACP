import AppKit
import ComposableArchitecture
import Foundation

struct FileManagerWindowClient: Sendable {
    var open: @Sendable (_ id: UUID) async -> Void
    var openTab: @Sendable (_ id: UUID) async -> Void
    var close: @Sendable (_ id: UUID) async -> Void
    var closeAll: @Sendable () async -> Void
    var focusPath: @Sendable (_ path: String) async -> Void
    var openPathInNewWindow: @Sendable (_ path: String) async -> Void
    var openPathInNewTab: @Sendable (_ path: String) async -> Void

    nonisolated init(
        open: @escaping @Sendable (_ id: UUID) async -> Void,
        openTab: @escaping @Sendable (_ id: UUID) async -> Void,
        close: @escaping @Sendable (_ id: UUID) async -> Void,
        closeAll: @escaping @Sendable () async -> Void,
        focusPath: @escaping @Sendable (_ path: String) async -> Void,
        openPathInNewWindow: @escaping @Sendable (_ path: String) async -> Void,
        openPathInNewTab: @escaping @Sendable (_ path: String) async -> Void,
    ) {
        self.open = open
        self.openTab = openTab
        self.close = close
        self.closeAll = closeAll
        self.focusPath = focusPath
        self.openPathInNewWindow = openPathInNewWindow
        self.openPathInNewTab = openPathInNewTab
    }
}

extension FileManagerWindowClient: DependencyKey {
    nonisolated static var liveValue: FileManagerWindowClient {
        .init(
            open: { _ in
                fatalError("fileManagerWindowClient.open live dependency is not configured")
            },
            openTab: { _ in
                fatalError("fileManagerWindowClient.openTab live dependency is not configured")
            },
            close: { _ in
                fatalError("fileManagerWindowClient.close live dependency is not configured")
            },
            closeAll: {
                fatalError("fileManagerWindowClient.closeAll live dependency is not configured")
            },
            focusPath: { _ in
                fatalError("fileManagerWindowClient.focusPath live dependency is not configured")
            },
            openPathInNewWindow: { _ in
                fatalError("fileManagerWindowClient.openPathInNewWindow live dependency is not configured")
            },
            openPathInNewTab: { _ in
                fatalError("fileManagerWindowClient.openPathInNewTab live dependency is not configured")
            },
        )
    }

    nonisolated static var testValue: FileManagerWindowClient {
        .init(
            open: { _ in
                fatalError("fileManagerWindowClient.open test dependency is not configured")
            },
            openTab: { _ in
                fatalError("fileManagerWindowClient.openTab test dependency is not configured")
            },
            close: { _ in
                fatalError("fileManagerWindowClient.close test dependency is not configured")
            },
            closeAll: {
                fatalError("fileManagerWindowClient.closeAll test dependency is not configured")
            },
            focusPath: { _ in
                fatalError("fileManagerWindowClient.focusPath test dependency is not configured")
            },
            openPathInNewWindow: { _ in
                fatalError("fileManagerWindowClient.openPathInNewWindow test dependency is not configured")
            },
            openPathInNewTab: { _ in
                fatalError("fileManagerWindowClient.openPathInNewTab test dependency is not configured")
            },
        )
    }

    nonisolated static var previewValue: FileManagerWindowClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var fileManagerWindowClient: FileManagerWindowClient {
        get { self[FileManagerWindowClient.self] }
        set { self[FileManagerWindowClient.self] = newValue }
    }
}

@MainActor
final class FileManagerWindowClientLiveContext {
    private var appStore: StoreOf<AppRootFeature>?
    private var windowControllersByID: [UUID: FileManagerWindowCoordinator] = [:]
    private var windowControllers: [FileManagerWindowCoordinator] = []

    var client: FileManagerWindowClient {
        .init(
            open: { [weak self] id in
                await MainActor.run {
                    self?.open(windowID: id)
                }
            },
            openTab: { [weak self] id in
                await MainActor.run {
                    self?.openTab(windowID: id)
                }
            },
            close: { [weak self] id in
                await MainActor.run {
                    self?.close(windowID: id)
                }
            },
            closeAll: { [weak self] in
                await MainActor.run {
                    self?.closeAll()
                }
            },
            focusPath: { [weak self] path in
                await MainActor.run {
                    self?.focusWindow(path: path)
                }
            },
            openPathInNewWindow: { [weak self] path in
                await MainActor.run {
                    self?.sendNewWindow(path: path)
                }
            },
            openPathInNewTab: { [weak self] path in
                await MainActor.run {
                    self?.sendNewTab(path: path)
                }
            },
        )
    }

    func bind(appStore: StoreOf<AppRootFeature>) {
        self.appStore = appStore
    }

    func sendNewWindow(path: String?) {
        appStore?.send(.windowManager(.newWindow(path: path)))
    }

    func sendNewTab(path: String?) {
        appStore?.send(.windowManager(.newTab(path: path)))
    }

    private func open(windowID: UUID) {
        if let existing = windowControllersByID[windowID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        guard let sessionStore = sessionStore(windowID: windowID) else {
            assertionFailure("windowID에 해당하는 session store가 없습니다.")
            return
        }

        let fileManagerStore = sessionStore.scope(state: \.window, action: \.window)
        let undoManager = UndoManager()

        let controller = makeManagedWindowController(
            windowID: windowID,
            fileManagerStore: fileManagerStore,
            undoManager: undoManager,
        )
        registerWindowController(controller)
        controller.showWindow(nil as Any?)
    }

    private func openTab(windowID: UUID) {
        if let existing = windowControllersByID[windowID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        guard let keyWindow = NSApp.keyWindow,
              windowControllers.contains(where: { $0.window === keyWindow })
        else {
            open(windowID: windowID)
            return
        }

        guard let sessionStore = sessionStore(windowID: windowID) else {
            assertionFailure("windowID에 해당하는 session store가 없습니다.")
            return
        }

        let fileManagerStore = sessionStore.scope(state: \.window, action: \.window)
        let undoManager = UndoManager()

        let controller = makeManagedWindowController(
            windowID: windowID,
            fileManagerStore: fileManagerStore,
            undoManager: undoManager,
        )
        registerWindowController(controller)

        if let newWindow = controller.window {
            keyWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil as Any?)
        } else {
            controller.showWindow(nil as Any?)
        }
    }

    private func close(windowID: UUID) {
        windowControllersByID[windowID]?.window?.close()
    }

    private func closeAll() {
        let controllers = windowControllers
        controllers.forEach { $0.window?.close() }
    }

    private func focusWindow(path: String) {
        let targetController = windowControllers.first { controller in
            controller.store.state.content.navigation.currentPath == path
        }
        targetController?.window?.makeKeyAndOrderFront(nil)
    }

    private func registerWindowController(_ controller: FileManagerWindowCoordinator) {
        windowControllers.append(controller)
        windowControllersByID[controller.windowID] = controller
    }

    private func unregisterWindowController(windowID: UUID) {
        windowControllersByID.removeValue(forKey: windowID)
        windowControllers.removeAll { $0.windowID == windowID }
    }

    private func sessionStore(windowID: UUID) -> Store<WindowSessionFeature.State, WindowSessionFeature.Action>? {
        guard let appStore else { return nil }
        let sessionStores = Array(
            appStore.scope(state: \.windowManager.windows, action: \.windowManager.windows),
        )
        return sessionStores.first(where: { $0.state.id == windowID })
    }

    private func makeManagedWindowController(
        windowID: UUID,
        fileManagerStore: StoreOf<FileManagerFeature>,
        undoManager: UndoManager,
    ) -> FileManagerWindowCoordinator {
        FileManagerWindowCoordinator(
            windowID: windowID,
            store: fileManagerStore,
            windowUndoManager: undoManager,
            path: nil,
            onBecameKey: { [weak self] id in
                self?.appStore?.send(.windowManager(.windowBecameKey(id)))
            },
            onResignedKey: { [weak self] id in
                self?.appStore?.send(.windowManager(.windowResignedKey(id)))
            },
            onWillClose: { [weak self] id in
                self?.unregisterWindowController(windowID: id)
                self?.appStore?.send(.windowManager(.windowClosed(id)))
            },
            initialWindowSizeProvider: { [weak self] in
                self?.windowControllers.first?.window?.frame.size
            },
        )
    }
}
