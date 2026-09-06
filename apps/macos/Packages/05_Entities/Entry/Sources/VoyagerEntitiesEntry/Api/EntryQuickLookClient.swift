import AppKit
import ComposableArchitecture
import Foundation
import QuickLookUI

@MainActor
public protocol EntryQuickLookPanelEventHandling: AnyObject {
    func handleQuickLookPanelEvent(_ event: NSEvent) -> Bool
}

public struct EntryQuickLookClient: Sendable {
    public var quickLook: @Sendable (_ urls: [URL], _ initialIndex: Int) async throws -> Void
    public var syncQuickLookSelection: @Sendable (_ urls: [URL], _ selectedIndex: Int) async -> Void
    public var acceptsPreviewPanelControl: @MainActor @Sendable () -> Bool
    public var beginPreviewPanelControl: @MainActor @Sendable (
        _ panel: QLPreviewPanel,
        _ eventHandler: any EntryQuickLookPanelEventHandling,
    ) -> Void
    public var endPreviewPanelControl: @MainActor @Sendable (
        _ panel: QLPreviewPanel,
        _ eventHandler: any EntryQuickLookPanelEventHandling,
    ) -> Void

    nonisolated public init(
        quickLook: @escaping @Sendable (_ urls: [URL], _ initialIndex: Int) async throws -> Void,
        syncQuickLookSelection: @escaping @Sendable (_ urls: [URL], _ selectedIndex: Int) async -> Void = { _, _ in },
        acceptsPreviewPanelControl: @escaping @MainActor @Sendable () -> Bool = { false },
        beginPreviewPanelControl: @escaping @MainActor @Sendable (
            _ panel: QLPreviewPanel,
            _ eventHandler: any EntryQuickLookPanelEventHandling,
        ) -> Void = { _, _ in },
        endPreviewPanelControl: @escaping @MainActor @Sendable (
            _ panel: QLPreviewPanel,
            _ eventHandler: any EntryQuickLookPanelEventHandling,
        ) -> Void = { _, _ in },
    ) {
        self.quickLook = quickLook
        self.syncQuickLookSelection = syncQuickLookSelection
        self.acceptsPreviewPanelControl = acceptsPreviewPanelControl
        self.beginPreviewPanelControl = beginPreviewPanelControl
        self.endPreviewPanelControl = endPreviewPanelControl
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
            acceptsPreviewPanelControl: {
                coordinator.acceptsPreviewPanelControl
            },
            beginPreviewPanelControl: { panel, eventHandler in
                coordinator.attach(to: panel, eventHandler: eventHandler)
            },
            endPreviewPanelControl: { panel, eventHandler in
                coordinator.detach(from: panel, eventHandler: eventHandler)
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
    /// 표시·동기화·responder-chain control을 같은 coordinator에 연결한 뒤
    /// client와 coordinator를 함께 반환한다.
    @MainActor
    static func makeLiveClient(
        panelProvider: @escaping @Sendable () -> (any EntryQuickLookPanelUpdating)?,
        boundary: any SecurityScopedAccessBoundary = RealSecurityScopedAccessBoundary(),
    ) -> (client: EntryQuickLookClient, coordinator: EntryQuickLookPanelCoordinator) {
        let coordinator = EntryQuickLookPanelCoordinator(
            panelProvider: panelProvider,
            boundary: boundary,
        )
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
            acceptsPreviewPanelControl: {
                coordinator.acceptsPreviewPanelControl
            },
            beginPreviewPanelControl: { panel, eventHandler in
                coordinator.attach(to: panel, eventHandler: eventHandler)
            },
            endPreviewPanelControl: { panel, eventHandler in
                coordinator.detach(from: panel, eventHandler: eventHandler)
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
    func makeKeyAndOrderFront()
    func orderOut()
}

extension QLPreviewPanel: @preconcurrency EntryQuickLookPanelUpdating {
    func makeKeyAndOrderFront() {
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }
}

@MainActor
final class EntryQuickLookPanelCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource,
    @preconcurrency QLPreviewPanelDelegate
{
    private let panelProvider: () -> (any EntryQuickLookPanelUpdating)?
    private let boundary: any SecurityScopedAccessBoundary
    private weak var eventHandler: (any EntryQuickLookPanelEventHandling)?
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

    var acceptsPreviewPanelControl: Bool {
        !currentURLs.isEmpty
    }

    func attach(
        to panel: QLPreviewPanel,
        eventHandler: any EntryQuickLookPanelEventHandling,
    ) {
        self.eventHandler = eventHandler
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
    }

    func detach(
        from panel: QLPreviewPanel,
        eventHandler: any EntryQuickLookPanelEventHandling,
    ) {
        guard self.eventHandler === eventHandler else { return }
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
        self.eventHandler = nil
    }

    func present(urls: [URL], initialIndex: Int) {
        guard !urls.isEmpty else { return }
        // 패널이 이미 보이는 동안의 재요청은 토글/동기화로 해석한다.
        // 같은 선택이면 패널을 닫고(Finder의 Space 토글), 다른 선택이면 미리보기 대상만 갱신한다.
        if !currentURLs.isEmpty, let panel = panelProvider(), panel.isVisible {
            if currentURLs == urls {
                panel.orderOut()
                Task { @MainActor in
                    scopeTokens.forEach { $0.invalidate() }
                    scopeTokens = []
                    currentURLs = []
                    currentIndex = 0
                }
                return
            }
            syncQuickLookSelection(urls: urls, selectedIndex: initialIndex)
            return
        }
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

        guard let panel = panelProvider() else {
            scopeTokens.forEach { $0.invalidate() }
            self.scopeTokens = []
            currentURLs = []
            currentIndex = 0
            return
        }

        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
        panel.makeKeyAndOrderFront()
    }

    func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        currentURLs.count
    }

    func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard !currentURLs.isEmpty else { return nil }
        let safeIndex = max(0, min(index, currentURLs.count - 1))
        return currentURLs[safeIndex] as NSURL
    }

    func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event else { return false }
        return eventHandler?.handleQuickLookPanelEvent(event) ?? false
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
