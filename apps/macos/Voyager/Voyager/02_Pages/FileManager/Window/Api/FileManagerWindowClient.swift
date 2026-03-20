import AppKit
import ComposableArchitecture
import Foundation

struct FileManagerWindowClient: Sendable {
    var open: @Sendable (_ id: UUID) async -> Void
    var openTab: @Sendable (_ id: UUID) async -> Void
    var close: @Sendable (_ id: UUID) async -> Void
    var closeAll: @Sendable () async -> Void
    var focusPath: @Sendable (_ path: String) async -> Void

    nonisolated init(
        open: @escaping @Sendable (_ id: UUID) async -> Void,
        openTab: @escaping @Sendable (_ id: UUID) async -> Void,
        close: @escaping @Sendable (_ id: UUID) async -> Void,
        closeAll: @escaping @Sendable () async -> Void,
        focusPath: @escaping @Sendable (_ path: String) async -> Void,
    ) {
        self.open = open
        self.openTab = openTab
        self.close = close
        self.closeAll = closeAll
        self.focusPath = focusPath
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

@MainActor private var fileManagerWindowRequestNewWindow: ((String?) -> Void)?
@MainActor private var fileManagerWindowRequestNewTab: ((String?) -> Void)?
@MainActor private var fileManagerWindowResolveStore: ((UUID) -> StoreOf<FileManagerFeature>?)?
@MainActor private var fileManagerWindowOnBecameKey: ((UUID) -> Void)?
@MainActor private var fileManagerWindowOnResignedKey: ((UUID) -> Void)?
@MainActor private var fileManagerWindowOnClosed: ((UUID) -> Void)?

@MainActor private var fileManagerWindowControllersByID: [UUID: FileManagerWindowCoordinator] = [:]
@MainActor private var fileManagerWindowControllers: [FileManagerWindowCoordinator] = []

@MainActor
func resolveFileManagerUndoManager(windowID: UUID?) -> UndoManager? {
    if let windowID, let controller = fileManagerWindowControllersByID[windowID] {
        return controller.windowUndoManager
    }

    if let keyWindow = NSApp.keyWindow,
       let controller = fileManagerWindowControllers.first(where: { $0.window === keyWindow })
    {
        return controller.windowUndoManager
    }

    return (NSApp.keyWindow?.firstResponder as? NSResponder)?.undoManager
}

@MainActor
func makeFileManagerWindowClientLive() -> FileManagerWindowClient {
    .init(
        open: { id in
            await MainActor.run {
                fileManagerWindowOpen(windowID: id)
            }
        },
        openTab: { id in
            await MainActor.run {
                fileManagerWindowOpenTab(windowID: id)
            }
        },
        close: { id in
            await MainActor.run {
                fileManagerWindowClose(windowID: id)
            }
        },
        closeAll: {
            await MainActor.run {
                fileManagerWindowCloseAll()
            }
        },
        focusPath: { path in
            await MainActor.run {
                fileManagerWindowFocus(path: path)
            }
        },
    )
}

@MainActor
func configureFileManagerWindowClientLive(
    requestNewWindow: @escaping (String?) -> Void,
    requestNewTab: @escaping (String?) -> Void,
    resolveFileManagerStore: @escaping (UUID) -> StoreOf<FileManagerFeature>?,
    onWindowBecameKey: @escaping (UUID) -> Void,
    onWindowResignedKey: @escaping (UUID) -> Void,
    onWindowClosed: @escaping (UUID) -> Void,
) {
    fileManagerWindowRequestNewWindow = requestNewWindow
    fileManagerWindowRequestNewTab = requestNewTab
    fileManagerWindowResolveStore = resolveFileManagerStore
    fileManagerWindowOnBecameKey = onWindowBecameKey
    fileManagerWindowOnResignedKey = onWindowResignedKey
    fileManagerWindowOnClosed = onWindowClosed
}

@MainActor
func requestFileManagerNewWindow(path: String?) {
    fileManagerWindowRequestNewWindow?(path)
}

@MainActor
func requestFileManagerNewTab(path: String?) {
    fileManagerWindowRequestNewTab?(path)
}

@MainActor
private func fileManagerWindowOpen(windowID: UUID) {
    if let existing = fileManagerWindowControllersByID[windowID] {
        existing.window?.makeKeyAndOrderFront(nil)
        return
    }

    guard let fileManagerStore = fileManagerWindowResolveStore?(windowID) else {
        assertionFailure("windowID에 해당하는 file manager store가 없습니다.")
        return
    }

    let undoManager = UndoManager()
    let controller = makeManagedWindowController(
        windowID: windowID,
        fileManagerStore: fileManagerStore,
        undoManager: undoManager,
        tabbingMode: .disallowed,
    )
    registerFileManagerWindowController(controller)
    controller.showWindow(nil as Any?)
}

@MainActor
private func fileManagerWindowOpenTab(windowID: UUID) {
    if let existing = fileManagerWindowControllersByID[windowID] {
        existing.window?.makeKeyAndOrderFront(nil)
        return
    }

    guard let keyWindow = NSApp.keyWindow,
          fileManagerWindowControllers.contains(where: { $0.window === keyWindow })
    else {
        fileManagerWindowOpen(windowID: windowID)
        return
    }

    guard let fileManagerStore = fileManagerWindowResolveStore?(windowID) else {
        assertionFailure("windowID에 해당하는 file manager store가 없습니다.")
        return
    }

    let undoManager = UndoManager()
    let controller = makeManagedWindowController(
        windowID: windowID,
        fileManagerStore: fileManagerStore,
        undoManager: undoManager,
        tabbingMode: .preferred,
    )
    registerFileManagerWindowController(controller)

    if let newWindow = controller.window {
        keyWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil as Any?)
    } else {
        controller.showWindow(nil as Any?)
    }
}

@MainActor
private func fileManagerWindowClose(windowID: UUID) {
    fileManagerWindowControllersByID[windowID]?.window?.close()
}

@MainActor
private func fileManagerWindowCloseAll() {
    let controllers = fileManagerWindowControllers
    controllers.forEach { $0.window?.close() }
}

@MainActor
private func fileManagerWindowFocus(path: String) {
    let targetController = fileManagerWindowControllers.first { controller in
        controller.store.state.content.navigation.currentPath == path
    }
    targetController?.window?.makeKeyAndOrderFront(nil)
}

@MainActor
private func registerFileManagerWindowController(_ controller: FileManagerWindowCoordinator) {
    fileManagerWindowControllers.append(controller)
    fileManagerWindowControllersByID[controller.windowID] = controller
}

@MainActor
private func unregisterFileManagerWindowController(windowID: UUID) {
    fileManagerWindowControllersByID.removeValue(forKey: windowID)
    fileManagerWindowControllers.removeAll { $0.windowID == windowID }
}

@MainActor
private func makeManagedWindowController(
    windowID: UUID,
    fileManagerStore: StoreOf<FileManagerFeature>,
    undoManager: UndoManager,
    tabbingMode: NSWindow.TabbingMode,
) -> FileManagerWindowCoordinator {
    FileManagerWindowCoordinator(
        windowID: windowID,
        store: fileManagerStore,
        windowUndoManager: undoManager,
        path: nil,
        tabbingMode: tabbingMode,
        onBecameKey: { id in
            fileManagerWindowOnBecameKey?(id)
        },
        onResignedKey: { id in
            fileManagerWindowOnResignedKey?(id)
        },
        onWillClose: { id in
            unregisterFileManagerWindowController(windowID: id)
            fileManagerWindowOnClosed?(id)
        },
        initialWindowSizeProvider: {
            fileManagerWindowControllers.first?.window?.frame.size
        },
    )
}
