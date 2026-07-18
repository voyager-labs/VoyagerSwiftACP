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

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: FileManagerHomeMetrics.sectionSpacing) {
                    favoritesSection
                    locationsSection
                    recentChatsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FileManagerHomeMetrics.horizontalContentPadding)
                .padding(.vertical, FileManagerHomeMetrics.verticalContentPadding)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
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
                    .font(VoyagerDS.Typography.body)
                    .foregroundStyle(VoyagerDS.SystemColor.tertiaryLabel)
                    .padding(.vertical, FileManagerHomeMetrics.emptyStateVerticalPadding)
            }
        } else {
            HomeSection(title: "Favorites") {
                NavigationGrid(
                    items: favorites,
                ) { item in
                    QuickNavigationItem(
                        systemName: item.iconName ?? "pin.fill",
                        title: item.title ?? "Untitled",
                    ) {
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
                NavigationGrid(
                    items: locations,
                ) { item in
                    QuickNavigationItem(
                        systemName: item.iconName,
                        title: item.title,
                    ) {
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
                    .font(VoyagerDS.Typography.body)
                    .foregroundStyle(VoyagerDS.SystemColor.tertiaryLabel)
                    .padding(.vertical, FileManagerHomeMetrics.emptyStateVerticalPadding)
            } else {
                VStack(alignment: .leading, spacing: FileManagerHomeMetrics.chatHistorySpacing) {
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
        .contentShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer, style: .continuous))
        .help("Start New Chat")
        .accessibilityLabel("Start New Chat")
    }
}

// MARK: - Navigation Grid

private struct NavigationGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: FileManagerHomeMetrics.navigationItemWidth,
                        maximum: FileManagerHomeMetrics.navigationItemWidth,
                    ),
                    spacing: FileManagerHomeMetrics.navigationGridSpacing,
                    alignment: .top,
                ),
            ],
            alignment: .leading,
            spacing: FileManagerHomeMetrics.navigationGridSpacing,
        ) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

// MARK: - Home Section

private struct HomeSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FileManagerHomeMetrics.sectionContentSpacing) {
            HStack(alignment: .center) {
                Text(title)
                    .font(VoyagerDS.Typography.title)
                    .foregroundStyle(VoyagerDS.SystemColor.label)
                Spacer(minLength: FileManagerHomeMetrics.sectionHeaderMinimumSpacing)
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

// MARK: - Quick Navigation

private enum FileManagerHomeMetrics {
    static let sectionSpacing: CGFloat = 28
    static let sectionContentSpacing: CGFloat = 12
    static let sectionHeaderMinimumSpacing: CGFloat = 8
    static let horizontalContentPadding: CGFloat = 36
    static let verticalContentPadding: CGFloat = 32
    static let emptyStateVerticalPadding: CGFloat = 12
    static let chatHistorySpacing: CGFloat = 8

    static let navigationItemWidth: CGFloat = 120
    static let navigationItemHeight: CGFloat = 88
    static let navigationGridSpacing: CGFloat = 12
    static let navigationIconFrameSize: CGFloat = 32
    static let navigationIconSymbolSize: CGFloat = 24
    static let navigationIconLabelSpacing: CGFloat = 6
    static let hoverAnimationDuration: Double = 0.14

    static let chatHistoryRowContentSpacing: CGFloat = 12
    static let chatHistoryRowPadding: CGFloat = 10
    static let chatHistoryTitleDetailSpacing: CGFloat = 2
    static let chatHistoryRowSpacerMinimumLength: CGFloat = 4
    static let assistantChatGlyphSize: CGFloat = 32
    static let assistantChatGlyphIconSize: CGFloat = 16
}

private struct SymbolIconTile: View {
    let systemName: String
    let size: CGFloat
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

private struct QuickNavigationItem: View {
    let systemName: String
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: FileManagerHomeMetrics.navigationIconLabelSpacing) {
                SymbolIconTile(
                    systemName: systemName,
                    size: FileManagerHomeMetrics.navigationIconFrameSize,
                    iconSize: FileManagerHomeMetrics.navigationIconSymbolSize,
                )

                Text(title)
                    .font(VoyagerDS.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(VoyagerDS.SystemColor.label)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
            }
            .frame(
                width: FileManagerHomeMetrics.navigationItemWidth,
                height: FileManagerHomeMetrics.navigationItemHeight,
            )
            .background(navigationBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var navigationBackground: some View {
        RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
            .fill(isHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear)
            .animation(.easeOut(duration: FileManagerHomeMetrics.hoverAnimationDuration), value: isHovered)
    }
}

// MARK: - ChatHistoryRow

private struct ChatHistoryRow: View {
    let item: FileManagerHomeChatHistoryItem
    let action: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: FileManagerHomeMetrics.chatHistoryRowContentSpacing) {
                AssistantChatGlyph(
                    size: FileManagerHomeMetrics.assistantChatGlyphSize,
                    iconSize: FileManagerHomeMetrics.assistantChatGlyphIconSize,
                )

                VStack(alignment: .leading, spacing: FileManagerHomeMetrics.chatHistoryTitleDetailSpacing) {
                    Text(item.title ?? "Untitled Chat")
                        .font(VoyagerDS.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(VoyagerDS.SystemColor.label)
                        .lineLimit(1)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(VoyagerDS.Typography.caption)
                            .foregroundStyle(VoyagerDS.SystemColor.secondaryLabel)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: FileManagerHomeMetrics.chatHistoryRowSpacerMinimumLength)

                Text(relativeTimestamp(from: item.updatedAtMs))
                    .font(VoyagerDS.Typography.chip)
                    .foregroundStyle(VoyagerDS.SystemColor.tertiaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FileManagerHomeMetrics.chatHistoryRowPadding)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
            .fill(isHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear)
            .animation(.easeOut(duration: FileManagerHomeMetrics.hoverAnimationDuration), value: isHovered)
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

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
            .fill(VoyagerDS.Surface.inputBackground(for: colorScheme))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "bubble.right")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(VoyagerDS.SystemColor.label)
                    .accessibilityHidden(true),
            )
    }
}
