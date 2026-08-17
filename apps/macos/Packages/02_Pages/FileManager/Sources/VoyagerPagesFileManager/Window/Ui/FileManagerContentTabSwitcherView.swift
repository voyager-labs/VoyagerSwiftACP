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
    private let onDismiss: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    init(
        viewState: ContentTabSwitcherViewState,
        onDismiss: @escaping () -> Void,
    ) {
        self.viewState = viewState
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switcherSurface(availableWidth: geometry.size.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum Metrics {
        static let statusSurfaceWidth: CGFloat = 420
        static let cardHeight: CGFloat = 132
        static let previewHeight: CGFloat = 76
        static let statusHeight: CGFloat = 48
        static let verticalPadding: CGFloat = 12
        static let cardPadding: CGFloat = 8
        static let textSpacing: CGFloat = 4
        static let iconSize: CGFloat = 28
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
                        SwitcherRow(row: item)
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
            VStack(alignment: .leading, spacing: Metrics.textSpacing) {
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

                HStack(spacing: Metrics.textSpacing) {
                    Text(row.pageLabel)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(row.anchorSummary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(VoyagerDS.Typography.caption)
                .foregroundStyle(VoyagerDS.SystemColor.secondaryLabel)
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
            .contentShape(Rectangle())
            .focusable()
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(row.accessibilityIdentifier)
            .accessibilityLabel(Text(row.accessibilityLabel))
            .accessibilityValue(Text(row.accessibilityValue))
        }
    }
}
