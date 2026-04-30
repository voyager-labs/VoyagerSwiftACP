// TODO(sunset VOY-273): Temporary compatibility adapter — app-layer TCA client.
import AppKit
import ComposableArchitecture
import Foundation
import QuickLookUI

public struct EntryQuickLookClient: Sendable {
    public var quickLook: @Sendable (_ urls: [URL], _ initialIndex: Int) async throws -> Void

    public nonisolated init(
        quickLook: @escaping @Sendable (_ urls: [URL], _ initialIndex: Int) async throws -> Void,
    ) {
        self.quickLook = quickLook
    }
}

extension EntryQuickLookClient: DependencyKey {
    @MainActor private static let coordinator = EntryQuickLookPanelCoordinator()

    public nonisolated static var liveValue: EntryQuickLookClient {
        EntryQuickLookClient(
            quickLook: { urls, initialIndex in
                await MainActor.run {
                    coordinator.present(urls: urls, initialIndex: initialIndex)
                }
            },
        )
    }

    public nonisolated static var testValue: EntryQuickLookClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryQuickLookClient test dependency not set.")
        }

        return EntryQuickLookClient(
            quickLook: { _, _ in unimplemented() },
        )
    }

    public nonisolated static var previewValue: EntryQuickLookClient {
        EntryQuickLookClient(
            quickLook: { _, _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryQuickLookClient: EntryQuickLookClient {
        get { self[EntryQuickLookClient.self] }
        set { self[EntryQuickLookClient.self] = newValue }
    }
}

@MainActor
private final class EntryQuickLookPanelCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var currentURLs: [URL] = []
    private var currentIndex: Int = 0
    private var scopeTokens: [EntryQuickLookSecurityScopedURLToken] = []

    func present(urls: [URL], initialIndex: Int) {
        guard !urls.isEmpty else { return }
        let tokens = urls.map(EntryQuickLookSecurityScopedURLToken.init)
        present(urls: urls, scopeTokens: tokens, initialIndex: initialIndex)
    }

    private func present(urls: [URL], scopeTokens: [EntryQuickLookSecurityScopedURLToken], initialIndex: Int) {
        self.scopeTokens.forEach { $0.invalidate() }
        self.scopeTokens = scopeTokens
        currentURLs = urls
        currentIndex = max(0, min(initialIndex, max(urls.count - 1, 0)))

        guard let panel = QLPreviewPanel.shared() else {
            scopeTokens.forEach { $0.invalidate() }
            self.scopeTokens = []
            currentURLs = []
            currentIndex = 0
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
    }

    func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        currentURLs.count
    }

    func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard !currentURLs.isEmpty else { return nil }
        let safeIndex = max(0, min(index, currentURLs.count - 1))
        return currentURLs[safeIndex] as NSURL
    }

    func previewPanel(_: QLPreviewPanel!, didChangeTo item: QLPreviewItem!) {
        guard let url = item as? NSURL else { return }
        let swiftURL = url as URL
        if let index = currentURLs.firstIndex(of: swiftURL) {
            currentIndex = index
        }
    }

    func previewPanelWillClose(_: QLPreviewPanel!) {
        Task { @MainActor in
            scopeTokens.forEach { $0.invalidate() }
            scopeTokens = []
            currentURLs = []
            currentIndex = 0
        }
    }
}

private final class EntryQuickLookSecurityScopedURLToken {
    private let url: URL
    private let isAccessing: Bool

    init(url: URL) {
        self.url = url
        if Thread.isMainThread {
            isAccessing = url.startAccessingSecurityScopedResource()
        } else {
            var access = false
            DispatchQueue.main.sync {
                access = url.startAccessingSecurityScopedResource()
            }
            isAccessing = access
        }
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func invalidate() {
        guard isAccessing else { return }
        if Thread.isMainThread {
            url.stopAccessingSecurityScopedResource()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
