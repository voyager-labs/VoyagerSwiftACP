import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

public enum FileManagerWindowActivationResult: Sendable, Equatable {
    case becameKey
    case discarded
}

public struct FileManagerWindowClient: Sendable {
    public var open: @Sendable (_ id: UUID) async -> Void
    public var openTab: @Sendable (_ id: UUID) async -> Void
    public var activate: @Sendable (_ id: UUID) async -> FileManagerWindowActivationResult
    public var close: @Sendable (_ id: UUID) async -> Void
    public var closeAll: @Sendable () async -> Void
    public var focusPath: @Sendable (_ path: String) async -> Void

    nonisolated public init(
        open: @escaping @Sendable (_ id: UUID) async -> Void,
        openTab: @escaping @Sendable (_ id: UUID) async -> Void,
        activate: @escaping @Sendable (_ id: UUID) async -> FileManagerWindowActivationResult,
        close: @escaping @Sendable (_ id: UUID) async -> Void,
        closeAll: @escaping @Sendable () async -> Void,
        focusPath: @escaping @Sendable (_ path: String) async -> Void,
    ) {
        self.open = open
        self.openTab = openTab
        self.activate = activate
        self.close = close
        self.closeAll = closeAll
        self.focusPath = focusPath
    }
}

extension FileManagerWindowClient: DependencyKey {
    nonisolated public static var liveValue: FileManagerWindowClient {
        .init(
            open: { _ in
                fatalError("fileManagerWindowClient.open live dependency is not configured")
            },
            openTab: { _ in
                fatalError("fileManagerWindowClient.openTab live dependency is not configured")
            },
            activate: { _ in
                fatalError("fileManagerWindowClient.activate live dependency is not configured")
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

    nonisolated public static var testValue: FileManagerWindowClient {
        .init(
            open: { _ in
                fatalError("fileManagerWindowClient.open test dependency is not configured")
            },
            openTab: { _ in
                fatalError("fileManagerWindowClient.openTab test dependency is not configured")
            },
            activate: { _ in
                fatalError("fileManagerWindowClient.activate test dependency is not configured")
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

    nonisolated public static var previewValue: FileManagerWindowClient {
        testValue
    }
}

public extension DependencyValues {
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

@MainActor
final class FileManagerWindowActivationTracker {
    static let discardedWindowLimit = 256

    private struct Waiter {
        let requestID: UUID
        let continuation: CheckedContinuation<FileManagerWindowActivationResult, Never>
    }

    private var waitersByWindowID: [UUID: [Waiter]] = [:]
    private var activationRequestedWindowIDs: Set<UUID> = []
    private var discardedWindowIDOrder: [UUID] = []
    private(set) var discardedWindowIDs: Set<UUID> = []
    private(set) var pendingWindowIDs: [UUID] = []

    func request(
        _ windowID: UUID,
        activate: (() -> Void)? = nil,
    ) async -> FileManagerWindowActivationResult {
        let requestID = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .discarded }
            guard !consumeDiscardedLifecycle(for: windowID) else { return .discarded }
            return await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .discarded)
                    return
                }
                let isFirstWaiter = waitersByWindowID[windowID] == nil
                if isFirstWaiter {
                    pendingWindowIDs.append(windowID)
                }
                waitersByWindowID[windowID, default: []].append(.init(
                    requestID: requestID,
                    continuation: continuation,
                ))
                if isFirstWaiter, let activate {
                    activationRequestedWindowIDs.insert(windowID)
                    activate()
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel(requestID: requestID, windowID: windowID)
            }
        }
    }

    func consumeRegistration(
        for windowID: UUID,
        activate: () -> Void,
    ) {
        clearDiscardedLifecycle(for: windowID)
        guard waitersByWindowID[windowID]?.isEmpty == false,
              activationRequestedWindowIDs.insert(windowID).inserted
        else { return }
        activate()
    }

    func discard(_ windowID: UUID) {
        recordDiscardedLifecycle(for: windowID)
        complete(windowID, result: .discarded)
    }

    func discardAll(_ windowIDs: [UUID] = []) {
        let pendingWindowIDs = pendingWindowIDs
        (windowIDs + pendingWindowIDs).forEach { recordDiscardedLifecycle(for: $0) }
        let waiters = pendingWindowIDs.flatMap { takeWaiters(for: $0) }
        waiters.forEach { $0.continuation.resume(returning: .discarded) }
    }

    func complete(_ windowID: UUID, result: FileManagerWindowActivationResult) {
        takeWaiters(for: windowID).forEach { $0.continuation.resume(returning: result) }
    }

    private func cancel(requestID: UUID, windowID: UUID) {
        guard var waiters = waitersByWindowID[windowID],
              let index = waiters.firstIndex(where: { $0.requestID == requestID })
        else { return }
        let waiter = waiters.remove(at: index)
        if waiters.isEmpty {
            waitersByWindowID[windowID] = nil
            activationRequestedWindowIDs.remove(windowID)
            pendingWindowIDs.removeAll { $0 == windowID }
        } else {
            waitersByWindowID[windowID] = waiters
        }
        waiter.continuation.resume(returning: .discarded)
    }

    private func takeWaiters(for windowID: UUID) -> [Waiter] {
        pendingWindowIDs.removeAll { $0 == windowID }
        activationRequestedWindowIDs.remove(windowID)
        return waitersByWindowID.removeValue(forKey: windowID) ?? []
    }

    private func recordDiscardedLifecycle(for windowID: UUID) {
        guard discardedWindowIDs.insert(windowID).inserted else { return }
        discardedWindowIDOrder.append(windowID)
        while discardedWindowIDOrder.count > Self.discardedWindowLimit {
            discardedWindowIDs.remove(discardedWindowIDOrder.removeFirst())
        }
    }

    private func consumeDiscardedLifecycle(for windowID: UUID) -> Bool {
        guard discardedWindowIDs.remove(windowID) != nil else { return false }
        discardedWindowIDOrder.removeAll { $0 == windowID }
        return true
    }

    private func clearDiscardedLifecycle(for windowID: UUID) {
        _ = consumeDiscardedLifecycle(for: windowID)
    }
}

@MainActor private var fileManagerWindowControllersByID: [UUID: FileManagerWindowCoordinator] = [:]
@MainActor private var fileManagerWindowControllers: [FileManagerWindowCoordinator] = []
@MainActor private var fileManagerWindowActivationTracker = FileManagerWindowActivationTracker()
@MainActor private var didConfigureAutomaticWindowTabbing = false

@MainActor
private func configureFileManagerWindowTabbingPolicyIfNeeded() {
    guard !didConfigureAutomaticWindowTabbing else { return }
    NSWindow.allowsAutomaticWindowTabbing = false
    didConfigureAutomaticWindowTabbing = true
}

@MainActor
public func makeFileManagerWindowClientLive(
    fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
) -> FileManagerWindowClient {
    .init(
        open: { id in
            await MainActor.run {
                fileManagerWindowOpen(
                    windowID: id,
                    fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
                )
            }
        },
        openTab: { id in
            await MainActor.run {
                fileManagerWindowOpenTab(
                    windowID: id,
                    fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
                )
            }
        },
        activate: { id in
            await fileManagerWindowActivate(windowID: id)
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

public struct FileManagerWindowKeyCallbacks {
    public let onBecameKey: @MainActor (UUID) -> Void
    public let onResignedKey: @MainActor (UUID) -> Void
    public let onClosed: @MainActor (UUID) -> Void

    public init(
        onBecameKey: @MainActor @escaping (UUID) -> Void,
        onResignedKey: @MainActor @escaping (UUID) -> Void,
        onClosed: @MainActor @escaping (UUID) -> Void,
    ) {
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onClosed = onClosed
    }
}

@MainActor
public func configureFileManagerWindowClientLive(
    requestNewWindow: @escaping (String?) -> Void,
    requestNewTab: @escaping (String?) -> Void,
    resolveFileManagerStore: @escaping (UUID) -> StoreOf<FileManagerFeature>?,
    windowKeyCallbacks: FileManagerWindowKeyCallbacks,
) {
    fileManagerWindowRequestNewWindow = requestNewWindow
    fileManagerWindowRequestNewTab = requestNewTab
    fileManagerWindowResolveStore = resolveFileManagerStore
    fileManagerWindowOnBecameKey = windowKeyCallbacks.onBecameKey
    fileManagerWindowOnResignedKey = windowKeyCallbacks.onResignedKey
    fileManagerWindowOnClosed = windowKeyCallbacks.onClosed
}

@MainActor
public func requestFileManagerNewWindow(path: String?) {
    fileManagerWindowRequestNewWindow?(path)
}

@MainActor
public func requestFileManagerNewTab(path: String?) {
    fileManagerWindowRequestNewTab?(path)
}

@MainActor
private func fileManagerWindowOpen(
    windowID: UUID,
    fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
) {
    configureFileManagerWindowTabbingPolicyIfNeeded()

    if let existing = fileManagerWindowControllersByID[windowID] {
        existing.window?.makeKeyAndOrderFront(nil)
        return
    }

    guard let fileManagerStore = fileManagerWindowResolveStore?(windowID) else {
        assertionFailure("windowID에 해당하는 file manager store가 없습니다.")
        return
    }

    let controller = makeManagedWindowController(
        windowID: windowID,
        fileManagerStore: fileManagerStore,
        fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
    )
    registerFileManagerWindowController(controller)
    controller.showWindow(nil as Any?)
}

@MainActor
private func fileManagerWindowOpenTab(
    windowID: UUID,
    fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
) {
    configureFileManagerWindowTabbingPolicyIfNeeded()

    if let existing = fileManagerWindowControllersByID[windowID] {
        existing.window?.makeKeyAndOrderFront(nil)
        return
    }

    guard let keyWindow = NSApp.keyWindow,
          fileManagerWindowControllers.contains(where: { $0.window === keyWindow })
    else {
        fileManagerWindowOpen(
            windowID: windowID,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
        )
        return
    }

    guard let fileManagerStore = fileManagerWindowResolveStore?(windowID) else {
        assertionFailure("windowID에 해당하는 file manager store가 없습니다.")
        return
    }

    let controller = makeManagedWindowController(
        windowID: windowID,
        fileManagerStore: fileManagerStore,
        fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
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
private func fileManagerWindowActivate(windowID: UUID) async -> FileManagerWindowActivationResult {
    guard let controller = fileManagerWindowControllersByID[windowID] else {
        return await fileManagerWindowActivationTracker.request(windowID)
    }
    guard controller.window?.isKeyWindow != true else { return .becameKey }
    return await fileManagerWindowActivationTracker.request(windowID) {
        activateFileManagerWindowController(controller)
    }
}

@MainActor
private func activateFileManagerWindowController(_ controller: FileManagerWindowCoordinator) {
    NSApp.activate(ignoringOtherApps: true)
    controller.window?.makeKeyAndOrderFront(nil)
}

@MainActor
private func fileManagerWindowClose(windowID: UUID) {
    fileManagerWindowActivationTracker.discard(windowID)
    fileManagerWindowControllersByID[windowID]?.window?.close()
}

@MainActor
private func fileManagerWindowCloseAll() {
    let controllers = fileManagerWindowControllers
    fileManagerWindowActivationTracker.discardAll(controllers.map(\.windowID))
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
    fileManagerWindowActivationTracker.consumeRegistration(for: controller.windowID) {
        activateFileManagerWindowController(controller)
    }
}

@MainActor
private func unregisterFileManagerWindowController(windowID: UUID) {
    fileManagerWindowActivationTracker.discard(windowID)
    fileManagerWindowControllersByID.removeValue(forKey: windowID)
    fileManagerWindowControllers.removeAll { $0.windowID == windowID }
}

@MainActor
private func currentFileManagerWindowSize() -> NSSize? {
    if let keyWindow = NSApp.keyWindow,
       let controller = fileManagerWindowControllers.first(where: { $0.window === keyWindow })
    {
        return controller.window?.frame.size
    }

    return fileManagerWindowControllers.first?.window?.frame.size
}

@MainActor
private func makeManagedWindowController(
    windowID: UUID,
    fileManagerStore: StoreOf<FileManagerFeature>,
    fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
) -> FileManagerWindowCoordinator {
    FileManagerWindowCoordinator(
        windowID: windowID,
        store: fileManagerStore,
        fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
        path: nil,
        onBecameKey: { id in
            fileManagerWindowActivationTracker.complete(id, result: .becameKey)
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
            currentFileManagerWindowSize()
        },
    )
}
