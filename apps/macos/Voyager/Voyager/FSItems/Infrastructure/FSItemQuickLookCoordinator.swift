import AppKit
import QuickLookUI

@MainActor
final class FSItemQuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = FSItemQuickLookCoordinator()

    private var currentURL: URL?
    private var currentURLs: [URL] = []
    private var currentIndex: Int = 0
    private var scopeToken: SecurityScopedURLToken?
    private var scopeTokens: [SecurityScopedURLToken] = []

    @MainActor
    func present(url: URL, scopeToken: SecurityScopedURLToken) {
        self.scopeToken?.invalidate()
        scopeTokens.forEach { $0.invalidate() }
        scopeTokens = []
        self.scopeToken = scopeToken
        currentURL = url
        currentURLs = [url]
        currentIndex = 0

        guard let panel = QLPreviewPanel.shared() else {
            scopeToken.invalidate()
            self.scopeToken = nil
            currentURL = nil
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
    }

    @MainActor
    func present(urls: [URL], scopeTokens: [SecurityScopedURLToken], initialIndex: Int) {
        scopeToken?.invalidate()
        self.scopeTokens.forEach { $0.invalidate() }
        scopeToken = nil
        self.scopeTokens = scopeTokens
        currentURLs = urls
        currentURL = urls.first
        currentIndex = max(0, min(initialIndex, max(urls.count - 1, 0)))

        guard let panel = QLPreviewPanel.shared() else {
            scopeTokens.forEach { $0.invalidate() }
            self.scopeTokens = []
            currentURLs = []
            currentURL = nil
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
            currentURL = swiftURL
        }
    }

    func previewPanelWillClose(_: QLPreviewPanel!) {
        Task { @MainActor in
            scopeToken?.invalidate()
            scopeToken = nil
            scopeTokens.forEach { $0.invalidate() }
            scopeTokens = []
            currentURL = nil
            currentURLs = []
            currentIndex = 0
        }
    }
}

final class SecurityScopedURLToken {
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
