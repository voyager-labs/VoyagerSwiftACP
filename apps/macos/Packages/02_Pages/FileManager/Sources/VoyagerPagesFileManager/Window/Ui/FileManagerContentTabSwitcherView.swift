import AppKit
import SwiftUI
import VoyagerShared

enum ContentTabSwitcherLayout {
    struct Geometry: Equatable {
        let surfaceWidth: CGFloat
        let cardWidth: CGFloat
    }

    static let maximumColumnCount = 5
    static let maximumRowCount = 2
    static let idealCardWidth: CGFloat = 128
    static let cardSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 16
    static let surfaceMargin: CGFloat = 16

    static func rowCounts(for candidateCount: Int) -> [Int] {
        let count = min(max(candidateCount, 0), maximumColumnCount * maximumRowCount)
        guard count > 0 else { return [] }
        guard count > maximumColumnCount else { return [count] }

        let firstRowCount = (count + 1) / 2
        return [firstRowCount, count - firstRowCount]
    }

    static func balancedRows<Element>(from elements: [Element]) -> [[Element]] {
        var remaining = Array(elements.prefix(maximumColumnCount * maximumRowCount))
        return rowCounts(for: remaining.count).map { rowCount in
            let row = Array(remaining.prefix(rowCount))
            remaining.removeFirst(rowCount)
            return row
        }
    }

    static func constrainedGeometry(candidateCount: Int, availableWidth: CGFloat) -> Geometry {
        let columnCount = rowCounts(for: candidateCount).max() ?? 1
        let idealSurfaceWidth = horizontalPadding * 2
            + CGFloat(columnCount) * idealCardWidth
            + CGFloat(max(columnCount - 1, 0)) * cardSpacing
        let surfaceWidth = min(idealSurfaceWidth, max(availableWidth - surfaceMargin * 2, 0))
        let availableCardWidth = max(
            surfaceWidth - horizontalPadding * 2 - CGFloat(max(columnCount - 1, 0)) * cardSpacing,
            0,
        )
        return Geometry(
            surfaceWidth: surfaceWidth,
            cardWidth: min(idealCardWidth, availableCardWidth / CGFloat(columnCount)),
        )
    }
}

struct FileManagerContentTabSwitcherView: View {
    private let viewState: ContentTabSwitcherViewState
    private let onFocusMove: (ContentTabSwitcherFocusDirection) -> Void
    private let onActivate: (ContentTabID) -> Void
    private let onDismiss: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    init(
        viewState: ContentTabSwitcherViewState,
        onFocusMove: @escaping (ContentTabSwitcherFocusDirection) -> Void = { _ in },
        onActivate: @escaping (ContentTabID) -> Void = { _ in },
        onDismiss: @escaping () -> Void,
    ) {
        self.viewState = viewState
        self.onFocusMove = onFocusMove
        self.onActivate = onActivate
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switcherSurface(availableWidth: geometry.size.width)
                ContentTabSwitcherKeyCommandBridge(
                    onConfirmFocused: confirmFocusedCandidate,
                    onDismiss: onDismiss,
                    onFocusMove: onFocusMove,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum Metrics {
        static let statusSurfaceWidth: CGFloat = 420
        static let cardHeight: CGFloat = 116
        static let previewHeight: CGFloat = 76
        static let statusHeight: CGFloat = 48
        static let verticalPadding: CGFloat = 12
        static let cardPadding: CGFloat = 8
        static let textSpacing: CGFloat = 4
        static let iconSize: CGFloat = 28
        static let focusRingWidth: CGFloat = 2
    }

    /// Return/keypad Enter는 현재 viewState의 focused row ID를 derive해 explicit-ID activation seam을 재사용한다.
    private func confirmFocusedCandidate() {
        guard case let .content(rows) = viewState,
              let focusedRow = rows.first(where: \.isFocused)
        else { return }
        onActivate(focusedRow.id)
    }

    private func switcherSurface(availableWidth: CGFloat) -> some View {
        let geometry = switcherGeometry(availableWidth: availableWidth)
        return VStack(spacing: ContentTabSwitcherLayout.cardSpacing) {
            stateContent(cardWidth: geometry.cardWidth)
        }
        .padding(.horizontal, ContentTabSwitcherLayout.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(width: geometry.surfaceWidth)
        .background {
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .fill(VoyagerDS.Surface.overlayBackground(for: colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .stroke(VoyagerDS.Surface.overlayBorder)
        }
        .shadow(
            color: VoyagerDS.Shadow.overlayColor(for: colorScheme),
            radius: VoyagerDS.Shadow.overlayRadius(for: colorScheme),
            y: VoyagerDS.Shadow.overlayYOffset(for: colorScheme),
        )
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("file-manager.content-tab-switcher")
    }

    @ViewBuilder
    private func stateContent(cardWidth: CGFloat) -> some View {
        switch viewState {
        case let .loading(status):
            statusView(status, identifier: "file-manager.content-tab-switcher.loading")
        case let .content(rows):
            contentView(rows, cardWidth: cardWidth)
        case let .empty(status):
            statusView(status, identifier: "file-manager.content-tab-switcher.empty")
        case let .error(status):
            statusView(status, identifier: "file-manager.content-tab-switcher.error")
        }
    }

    private func contentView(_ rows: [ContentTabSwitcherViewState.Row], cardWidth: CGFloat) -> some View {
        VStack(spacing: ContentTabSwitcherLayout.cardSpacing) {
            ForEach(
                Array(ContentTabSwitcherLayout.balancedRows(from: rows).enumerated()),
                id: \.offset,
            ) { _, row in
                HStack(spacing: ContentTabSwitcherLayout.cardSpacing) {
                    ForEach(row, id: \.id) { item in
                        Button(
                            action: { onActivate(item.id) },
                            label: { SwitcherRow(row: item) },
                        )
                        .buttonStyle(.plain)
                        .frame(width: cardWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func switcherGeometry(availableWidth: CGFloat) -> ContentTabSwitcherLayout.Geometry {
        guard case let .content(rows) = viewState else {
            return .init(
                surfaceWidth: min(
                    Metrics.statusSurfaceWidth,
                    max(availableWidth - ContentTabSwitcherLayout.surfaceMargin * 2, 0),
                ),
                cardWidth: ContentTabSwitcherLayout.idealCardWidth,
            )
        }
        return ContentTabSwitcherLayout.constrainedGeometry(
            candidateCount: rows.count,
            availableWidth: availableWidth,
        )
    }

    private func statusView(
        _ status: ContentTabSwitcherViewState.Status,
        identifier: String,
    ) -> some View {
        Text(status.message)
            .font(VoyagerDS.Typography.body)
            .foregroundStyle(VoyagerDS.SystemColor.secondaryLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.statusHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(Text(status.accessibilityLabel))
    }

    private struct SwitcherRow: View {
        let row: ContentTabSwitcherViewState.Row

        @Environment(\.colorScheme)
        private var colorScheme

        var body: some View {
            VStack(alignment: .center, spacing: Metrics.textSpacing) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                        .fill(VoyagerDS.SystemColor.controlBackground)

                    Image(systemName: row.iconName)
                        .font(.system(size: Metrics.iconSize))
                        .foregroundStyle(VoyagerDS.SystemColor.secondaryLabel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(row.isIconAccessibilityHidden)

                    if row.isCurrent {
                        Text("Current")
                            .font(VoyagerDS.Typography.chip)
                            .foregroundStyle(VoyagerDS.BrandPrimaryColor.c500)
                            .padding(.horizontal, Metrics.textSpacing)
                            .padding(.vertical, 2)
                            .background(
                                VoyagerDS.Surface.chipContainerBackground(for: colorScheme),
                                in: Capsule(),
                            )
                            .padding(Metrics.textSpacing)
                    }
                }
                .frame(height: Metrics.previewHeight)

                Text(row.title)
                    .font(VoyagerDS.Typography.title)
                    .foregroundStyle(VoyagerDS.SystemColor.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Metrics.cardHeight, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                    .fill(row.isCurrent
                        ? VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
                        : Color.clear)
            }
            .overlay {
                if row.isFocused {
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                        .strokeBorder(
                            VoyagerDS.BrandPrimaryColor.c500,
                            lineWidth: Metrics.focusRingWidth,
                        )
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(row.accessibilityIdentifier)
            .accessibilityLabel(Text(row.accessibilityLabel))
            .accessibilityValue(Text(row.accessibilityValue))
        }
    }
}

/// 전환기 overlay의 키 입력을 단일 AppKit responder(`KeyCommandHostingView`)가 소유하는 bridge.
/// Return/keypad Enter/Escape/방향키의 semantic 매핑을 내부에 두고 SwiftUI focus 엔진이나
/// hidden keyboard shortcut과 경쟁하지 않는다.
private struct ContentTabSwitcherKeyCommandBridge: View {
    let onConfirmFocused: () -> Void
    let onDismiss: () -> Void
    let onFocusMove: (ContentTabSwitcherFocusDirection) -> Void

    @StateObject private var activationCoordinator = ActivationCoordinator()

    var body: some View {
        KeyCommandView(
            onViewCreated: activationCoordinator.attach,
            onKeyDown: handleKeyDown,
        )
        .frame(width: 1, height: 1)
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .overlay {
            ContentTabSwitcherWindowKeyProbe(
                onWindowAttached: activationCoordinator.attachWindow,
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .onAppear(perform: activationCoordinator.start)
        .onDisappear(perform: activationCoordinator.stop)
    }

    /// KeyCommandHostingView의 keyDown을 semantic action으로 변환한다.
    /// IME 조합 중에는 입력기가 Return/Escape/방향키를 소유하므로 semantic action을 만들지 않는다.
    /// Tab(48)은 Shift 없으면 forward, Shift만 있으면 backward로 focus를 1회 이동한다.
    private func handleKeyDown(_ event: NSEvent) {
        guard !activationCoordinator.hasMarkedText() else { return }
        guard !event.isARepeat,
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              // Shift는 Tab 탐색 전용 보조키이고 나머지 키에서는 기존처럼 no-op이다.
              event.modifierFlags.isDisjoint(with: [.shift]) || event.keyCode == 48
        else { return }

        switch event.keyCode {
        case 36, 76:
            onConfirmFocused()

        case 53:
            onDismiss()

        case 123, 126:
            onFocusMove(.previous)

        case 124, 125:
            onFocusMove(.next)

        case 48:
            onFocusMove(event.modifierFlags.contains(.shift) ? .previous : .next)

        default:
            break
        }
    }

    /// overlay-local bridge를 window의 first responder로 유지하는 coordinator.
    /// first responder를 되돌려 얻을 뿐, 일단 bridge가 소유하면 다른 responder로 옮기지 않는다.
    @MainActor
    private final class ActivationCoordinator: ObservableObject {
        private weak var keyCommandView: KeyCommandHostingView?
        private weak var observedWindow: NSWindow?
        private var windowObservers: [NSObjectProtocol] = []

        func attach(_ view: KeyCommandHostingView) {
            keyCommandView = view
            activateIfKeyWindow()
            scheduleActivation()
        }

        func attachWindow(_ window: NSWindow) {
            guard observedWindow !== window else {
                activateIfKeyWindow()
                return
            }
            stopObservingKeyWindow()
            observedWindow = window
            for notificationName in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(
                    forName: notificationName,
                    object: window,
                    queue: .main,
                ) { [weak self, weak window] _ in
                    Task { @MainActor [weak self, weak window] in
                        guard let self,
                              let window,
                              window === keyCommandView?.window
                        else { return }
                        activateIfKeyWindow()
                    }
                })
            }
            activateIfKeyWindow()
        }

        func hasMarkedText() -> Bool {
            keyCommandView?.hasMarkedText() == true
        }

        func start() {
            activateIfKeyWindow()
            scheduleActivation()
        }

        func stop() {
            stopObservingKeyWindow()
            keyCommandView = nil
        }

        private func stopObservingKeyWindow() {
            for observer in windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            windowObservers.removeAll()
            observedWindow = nil
        }

        private func scheduleActivation() {
            DispatchQueue.main.async { [weak self] in
                self?.activateIfKeyWindow()
            }
        }

        private func activateIfKeyWindow() {
            guard let keyCommandView,
                  let window = keyCommandView.window,
                  window.isKeyWindow,
                  window.firstResponder !== keyCommandView,
                  // 편집 중인 텍스트 입력 responder는 빼앗지 않는다 (기존 repository pattern).
                  !Self.isEditingText(window.firstResponder)
            else { return }
            window.makeFirstResponder(keyCommandView)
        }

        private static func isEditingText(_ responder: NSResponder?) -> Bool {
            guard let textView = responder as? NSTextView else { return false }
            return textView.isEditable
        }
    }
}

private struct ContentTabSwitcherWindowKeyProbe: NSViewRepresentable {
    let onWindowAttached: (NSWindow) -> Void

    func makeNSView(context _: Context) -> WindowKeyProbeView {
        let view = WindowKeyProbeView()
        view.onWindowAttached = onWindowAttached
        return view
    }

    func updateNSView(_ nsView: WindowKeyProbeView, context _: Context) {
        nsView.onWindowAttached = onWindowAttached
    }

    final class WindowKeyProbeView: NSView {
        var onWindowAttached: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowAttached?(window)
            }
        }
    }
}
