import AppKit
import ComposableArchitecture
import Foundation
import QuickLookUI

public struct EntryQuickLookClient: Sendable {
    public var quickLook: @Sendable (_ urls: [URL], _ initialIndex: Int) async throws -> Void
    public var syncQuickLookSelection: @Sendable (_ urls: [URL], _ selectedIndex: Int) async -> Void

    nonisolated public init(
        quickLook: @escaping @Sendable (_ urls: [URL], _ initialIndex: Int) async throws -> Void,
        syncQuickLookSelection: @escaping @Sendable (_ urls: [URL], _ selectedIndex: Int) async -> Void = { _, _ in },
    ) {
        self.quickLook = quickLook
        self.syncQuickLookSelection = syncQuickLookSelection
    }
}

extension EntryQuickLookClient: DependencyKey {
    @MainActor private static let coordinator = EntryQuickLookPanelCoordinator()

    nonisolated public static var liveValue: EntryQuickLookClient {
        EntryQuickLookClient(
            quickLook: { urls, initialIndex in
                await MainActor.run {
                    coordinator.present(urls: urls, initialIndex: initialIndex)
                }
            },
            syncQuickLookSelection: { urls, selectedIndex in
                await MainActor.run {
                    coordinator.syncQuickLookSelection(urls: urls, selectedIndex: selectedIndex)
                }
            },
        )
    }

    nonisolated public static var testValue: EntryQuickLookClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryQuickLookClient test dependency not set.")
        }

        return EntryQuickLookClient(
            quickLook: { _, _ in unimplemented() },
            syncQuickLookSelection: { _, _ in unimplemented() },
        )
    }

    nonisolated public static var previewValue: EntryQuickLookClient {
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

/// 보안 범위 리소스 접근을 추상화하는 경계.
/// 테스트에서 실제 `startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource` 호출을
/// 대체하고 호출 횟수를 세기 위해 분리한다. 프로덕션에서는 실제 URL API를 그대로 호출한다.
protocol SecurityScopedAccessBoundary: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// 프로덕션 기본 경계: 실제 URL의 보안 범위 접근 API를 호출한다.
struct RealSecurityScopedAccessBoundary: SecurityScopedAccessBoundary {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

extension EntryQuickLookClient {
    /// 테스트용 live client를 만든다. 주입된 panel provider로 coordinator를 구성하고,
    /// 두 클로저(quickLook/syncQuickLookSelection)를 같은 coordinator에 연결한 뒤
    /// client와 coordinator를 함께 반환한다.
    @MainActor
    static func makeLiveClient(
        panelProvider: @escaping @Sendable () -> (any EntryQuickLookPanelUpdating)?,
        boundary: any SecurityScopedAccessBoundary = RealSecurityScopedAccessBoundary(),
    ) -> (client: EntryQuickLookClient, coordinator: EntryQuickLookPanelCoordinator) {
        let coordinator = EntryQuickLookPanelCoordinator(panelProvider: panelProvider, boundary: boundary)
        let client = EntryQuickLookClient(
            quickLook: { urls, initialIndex in
                await MainActor.run {
                    coordinator.present(urls: urls, initialIndex: initialIndex)
                }
            },
            syncQuickLookSelection: { urls, selectedIndex in
                await MainActor.run {
                    coordinator.syncQuickLookSelection(urls: urls, selectedIndex: selectedIndex)
                }
            },
        )
        return (client, coordinator)
    }
}

/// Quick Look 패널의 가시 상태와 미리보기 대상 갱신을 추상화한다.
/// 테스트에서 실제 `QLPreviewPanel` 대신 fake panel로 대체하기 위해 분리한다.
protocol EntryQuickLookPanelUpdating: AnyObject {
    var isVisible: Bool { get }
    var currentPreviewItemIndex: Int { get set }
    func reloadData()
}

extension QLPreviewPanel: @preconcurrency EntryQuickLookPanelUpdating {}

@MainActor
final class EntryQuickLookPanelCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource,
    QLPreviewPanelDelegate
{
    private let panelProvider: () -> (any EntryQuickLookPanelUpdating)?
    private let boundary: any SecurityScopedAccessBoundary
    private var currentURLs: [URL] = []
    private var currentIndex: Int = 0
    private var scopeTokens: [EntryQuickLookSecurityScopedURLToken] = []

    init(
        panelProvider: @escaping () -> (any EntryQuickLookPanelUpdating)? = { QLPreviewPanel.shared() },
        boundary: any SecurityScopedAccessBoundary = RealSecurityScopedAccessBoundary(),
    ) {
        self.panelProvider = panelProvider
        self.boundary = boundary
        super.init()
    }

    func present(urls: [URL], initialIndex: Int) {
        guard !urls.isEmpty else { return }
        let tokens = urls.map { EntryQuickLookSecurityScopedURLToken(url: $0, boundary: boundary) }
        present(urls: urls, scopeTokens: tokens, initialIndex: initialIndex)
    }

    func syncQuickLookSelection(urls: [URL], selectedIndex: Int) {
        guard !urls.isEmpty else { return }
        guard let panel = panelProvider(), panel.isVisible else { return }

        let tokens = urls.map { EntryQuickLookSecurityScopedURLToken(url: $0, boundary: boundary) }
        scopeTokens.forEach { $0.invalidate() }
        scopeTokens = tokens
        currentURLs = urls
        currentIndex = max(0, min(selectedIndex, urls.count - 1))
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
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

final class EntryQuickLookSecurityScopedURLToken {
    private let url: URL
    private let boundary: any SecurityScopedAccessBoundary
    private var isAccessing: Bool

    init(url: URL, boundary: any SecurityScopedAccessBoundary = RealSecurityScopedAccessBoundary()) {
        self.url = url
        self.boundary = boundary
        if Thread.isMainThread {
            isAccessing = boundary.startAccessing(url)
        } else {
            var access = false
            DispatchQueue.main.sync {
                access = boundary.startAccessing(url)
            }
            isAccessing = access
        }
    }

    deinit {
        if isAccessing {
            boundary.stopAccessing(url)
        }
    }

    func invalidate() {
        guard isAccessing else { return }
        isAccessing = false
        if Thread.isMainThread {
            boundary.stopAccessing(url)
        } else {
            let boundary = boundary
            let url = url
            DispatchQueue.main.async {
                boundary.stopAccessing(url)
            }
        }
    }
}

@MainActor
extension EntryQuickLookSecurityScopedURLToken: @unchecked Sendable {}
