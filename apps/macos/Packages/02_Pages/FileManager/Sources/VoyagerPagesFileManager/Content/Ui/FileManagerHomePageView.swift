import AppKit
import ComposableArchitecture
import HotSwiftUI
import SwiftUI
import VoyagerEntitiesAi
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

struct FileManagerHomePageView: View {
    let store: StoreOf<FileManagerContentFeature>

    @ObserveInjection var redraw

    private let dashboardCardWidth: CGFloat = 160
    private let dashboardCardHeight: CGFloat = 48
    private let dashboardCardMinimumSpacing: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    favoritesSection
                    locationsSection
                    recentChatsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.vertical, 42)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
        .background(homeBackground)
        .task {
            store.send(.view(.homeAppeared))
        }
        .enableInjection()
    }

    // MARK: - Favorites

    @ViewBuilder
    private var favoritesSection: some View {
        let favorites = store.homeFavoriteItems
        if favorites.isEmpty {
            HomeSection(title: "Favorites") {
                Text("No pinned favorites")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            }
        } else {
            HomeSection(title: "Favorites") {
                DashboardFlowGrid(
                    items: favorites,
                    itemWidth: dashboardCardWidth,
                    minimumSpacing: dashboardCardMinimumSpacing,
                ) { item in
                    FavoriteCard(item: item, height: dashboardCardHeight) {
                        store.send(.view(.homeSelectionTapped(.pageAnchor(item.anchor))))
                    }
                }
            }
        }
    }

    // MARK: - Locations

    @ViewBuilder
    private var locationsSection: some View {
        let locations = store.homeLocationItems
        if !locations.isEmpty {
            HomeSection(title: "Locations") {
                DashboardFlowGrid(
                    items: locations,
                    itemWidth: dashboardCardWidth,
                    minimumSpacing: dashboardCardMinimumSpacing,
                ) { item in
                    LocationCard(item: item, height: dashboardCardHeight) {
                        store.send(.view(.homeSelectionTapped(.pageAnchor(.directory(path: item.path)))))
                    }
                }
            }
        }
    }

    // MARK: - Recent Chats

    @ViewBuilder
    private var recentChatsSection: some View {
        let chats = store.homeChatHistoryItems
        HomeSection(title: "Recent Chats", trailing: { newChatButton }) {
            if chats.isEmpty {
                Text("No recent chats")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(chats.prefix(5)), id: \.sessionID) { item in
                        ChatHistoryRow(item: item) {
                            guard let uuid = UUID(uuidString: item.sessionID) else { return }
                            let sessionID = AiChatSessionID(rawValue: uuid)
                            store.send(.view(.homeSelectionTapped(.chatHistory(sessionID))))
                        }
                    }
                }
            }
        }
    }

    private var newChatButton: some View {
        Button {
            store.send(.view(.homeSelectionTapped(.startAiChat)))
        } label: {
            ToolbarHoverPillButtonLabel(title: "New Chat", isEnabled: true)
        }
        .buttonStyle(.borderless)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help("Start New Chat")
        .accessibilityLabel("Start New Chat")
    }

    // MARK: - Background

    private var homeBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.72),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .ignoresSafeArea()
    }
}

// MARK: - Dashboard Flow Grid

private struct DashboardFlowGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let minimumSpacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        DashboardFlowLayout(itemWidth: itemWidth, minimumSpacing: minimumSpacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

private struct DashboardFlowLayout: Layout {
    let itemWidth: CGFloat
    let minimumSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void,
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let proposedWidth = proposal.width ?? itemWidth
        let metrics = metrics(for: proposedWidth, itemCount: subviews.count)
        let rowHeights = rowHeights(for: subviews, columnCount: metrics.columnCount)
        let totalHeight = rowHeights.reduce(0, +)
            + CGFloat(max(0, rowHeights.count - 1)) * minimumSpacing

        return CGSize(width: proposedWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void,
    ) {
        guard !subviews.isEmpty else { return }

        let metrics = metrics(for: bounds.width, itemCount: subviews.count)
        let rowHeights = rowHeights(for: subviews, columnCount: metrics.columnCount)
        var y = bounds.minY

        for rowIndex in 0 ..< rowHeights.count {
            let start = rowIndex * metrics.columnCount
            let end = min(start + metrics.columnCount, subviews.count)
            var x = bounds.minX

            for index in start ..< end {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: itemWidth, height: rowHeights[rowIndex]),
                )
                x += itemWidth + metrics.spacing
            }

            y += rowHeights[rowIndex] + minimumSpacing
        }
    }

    private func metrics(for width: CGFloat, itemCount: Int) -> Metrics {
        let availableWidth = max(itemWidth, width)
        let maximumColumns = max(
            1,
            Int((availableWidth + minimumSpacing) / (itemWidth + minimumSpacing)),
        )
        let columnCount = max(1, min(itemCount, maximumColumns))
        let usedItemWidth = CGFloat(columnCount) * itemWidth
        let remainingWidth = max(0, availableWidth - usedItemWidth)
        let spacing = columnCount > 1
            ? max(minimumSpacing, remainingWidth / CGFloat(columnCount - 1))
            : minimumSpacing

        return Metrics(columnCount: columnCount, spacing: spacing)
    }

    private func rowHeights(for subviews: Subviews, columnCount: Int) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columnCount).map { start in
            let end = min(start + columnCount, subviews.count)
            return subviews[start ..< end]
                .map { subview in
                    subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
                }
                .max() ?? 0
        }
    }

    private struct Metrics {
        let columnCount: Int
        let spacing: CGFloat
    }
}

// MARK: - Home Section

private struct HomeSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                trailing
            }
            content
        }
    }
}

extension HomeSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        trailing = EmptyView()
        self.content = content()
    }
}

private func applicationsSidebarIcon() -> NSImage? {
    let appIcon = NSImage(
        contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle"
            + "/Contents/Resources/SidebarApplicationsFolder.icns",
    )
    appIcon?.isTemplate = true
    return appIcon
}

// MARK: - LocationCard

private struct SymbolIconTile: View {
    let systemName: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Group {
            if isApplicationsIcon, let appIcon = applicationsSidebarIcon() {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize + 4, height: iconSize + 4)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var isApplicationsIcon: Bool {
        systemName == "appstore" || systemName == "folder.badge.gearshape"
    }
}

private struct LocationCard: View {
    let item: FileManagerFixedLocationItem
    let height: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolIconTile(systemName: item.iconName, size: 31, cornerRadius: 8, iconSize: 16)

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(8)
            .background(cardBackground)
            .scaleEffect(isHovered ? 1.006 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.34 : 0.18), lineWidth: 1),
            )
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 5, y: 2)
    }
}

// MARK: - FavoriteCard

private struct FavoriteCard: View {
    let item: FileManagerHomeFavoriteItem
    let height: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolIconTile(
                    systemName: item.iconName ?? "pin.fill",
                    size: 31,
                    cornerRadius: 8,
                    iconSize: 16,
                )

                Text(item.title ?? "Untitled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(8)
            .background(cardBackground)
            .scaleEffect(isHovered ? 1.006 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.34 : 0.18), lineWidth: 1),
            )
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 5, y: 2)
    }
}

// MARK: - ChatHistoryRow

private struct ChatHistoryRow: View {
    let item: FileManagerHomeChatHistoryItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AssistantChatGlyph(size: 40, iconSize: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Untitled Chat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Text(relativeTimestamp(from: item.updatedAtMs))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(rowBackground)
            .scaleEffect(isHovered ? 1.006 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.4) : .clear)
    }

    private func relativeTimestamp(from ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        case ..<604_800: return "\(Int(interval / 86400))d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Assistant Chat Glyph

private struct AssistantChatGlyph: View {
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true),
            )
    }
}

// MARK: - FolderSymbol

private struct FolderSymbol: View {
    let symbolName: String
    let badgeSymbolName: String
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.18), radius: 6, y: 2)

            badgeImage
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.gradient))
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .offset(x: 2, y: 1)
        }
        .frame(width: 44, height: 38, alignment: .leading)
    }

    @ViewBuilder
    private var badgeImage: some View {
        if badgeSymbolName == "appstore", let appIcon = applicationsSidebarIcon() {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(4)
        } else {
            Image(systemName: badgeSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
