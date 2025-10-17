import AppKit
import QuickLookUI

final class FSItemQuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = FSItemQuickLookCoordinator()

    private var currentURL: URL?
    private var scopeToken: SecurityScopedURLToken?

    @MainActor
    func present(url: URL, scopeToken: SecurityScopedURLToken) {
        self.scopeToken?.invalidate()
        self.scopeToken = scopeToken
        currentURL = url

        guard let panel = QLPreviewPanel.shared() else {
            scopeToken.invalidate()
            self.scopeToken = nil
            currentURL = nil
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        currentURL == nil ? 0 : 1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt _: Int) -> QLPreviewItem! {
        currentURL.map { $0 as NSURL }
    }

    nonisolated func previewPanelWillClose(_: QLPreviewPanel!) {
        Task { @MainActor in
            scopeToken?.invalidate()
            scopeToken = nil
            currentURL = nil
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
        invalidate()
    }

    func invalidate() {
        guard isAccessing else { return }
        if Thread.isMainThread {
            url.stopAccessingSecurityScopedResource()
        } else {
            DispatchQueue.main.async {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
