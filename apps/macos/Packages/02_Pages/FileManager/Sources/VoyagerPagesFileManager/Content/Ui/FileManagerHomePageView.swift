import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerShared

struct FileManagerHomePageView: View {
    let store: StoreOf<FileManagerContentFeature>

    private let quickAccessItems: [QuickAccessItem] = [
        QuickAccessItem(
            title: "Applications",
            directory: .applications,
            symbolName: "folder.fill",
            badgeSymbolName: "appstore",
            tint: Color(nsColor: .systemBlue),
        ),
        QuickAccessItem(
            title: "Desktop",
            directory: .desktop,
            symbolName: "folder.fill",
            badgeSymbolName: "desktopcomputer",
            tint: Color(nsColor: .systemBlue),
        ),
        QuickAccessItem(
            title: "Documents",
            directory: .documents,
            symbolName: "folder.fill",
            badgeSymbolName: "doc.fill",
            tint: Color(nsColor: .systemBlue),
        ),
        QuickAccessItem(
            title: "Downloads",
            directory: .downloads,
            symbolName: "folder.fill",
            badgeSymbolName: "arrow.down.circle.fill",
            tint: Color(nsColor: .systemBlue),
        ),
    ]

    private let getStartedItems: [GetStartedItem] = [
        GetStartedItem(
            title: "Open Directory",
            subtitle: "Browse and manage folders on your device.",
            symbolName: "folder",
            assetName: nil,
            tint: Color(nsColor: .systemPurple),
            selection: .openDirectory,
        ),
        GetStartedItem(
            title: "Open Collection",
            subtitle: "Open a .voycoll collection file.",
            symbolName: nil,
            assetName: CollectionConstants.fileIconName,
            tint: Color(nsColor: .systemGreen),
            selection: .openCollection,
        ),
        GetStartedItem(
            title: "Start AI Chat",
            subtitle: "Ask anything and get help from Voyager AI.",
            symbolName: "sparkles",
            assetName: nil,
            tint: Color(nsColor: .systemBlue),
            selection: .startAiChat,
        ),
    ]

    private var quickAccessColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 18, alignment: .top), count: 4)
    }

    private var getStartedColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 18, alignment: .top), count: 3)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    quickAccessSection
                    getStartedSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 52)
                .padding(.vertical, 44)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
        }
        .background(homeBackground)
        .task {
            store.send(.view(.homeAppeared))
        }
    }

    private var quickAccessSection: some View {
        HomeSection(title: "Quick Access") {
            LazyVGrid(columns: quickAccessColumns, alignment: .leading, spacing: 18) {
                ForEach(quickAccessItems) { item in
                    QuickAccessCard(
                        item: item,
                        itemCount: store.homeDirectoryItemCounts[item.directory],
                    ) {
                        store.send(.view(.homeSelectionTapped(.fixedDirectory(item.directory))))
                    }
                }
            }
        }
    }

    private var getStartedSection: some View {
        HomeSection(title: "Get Started") {
            LazyVGrid(columns: getStartedColumns, alignment: .leading, spacing: 18) {
                ForEach(getStartedItems) { item in
                    GetStartedCard(item: item) {
                        store.send(.view(.homeSelectionTapped(item.selection)))
                    }
                }
            }
        }
    }

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

private struct HomeSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            content
        }
    }
}

private struct QuickAccessItem: Identifiable {
    var id: String {
        title
    }

    let title: String
    let directory: FileManagerHomeDirectory
    let symbolName: String
    let badgeSymbolName: String
    let tint: Color
}

private struct GetStartedItem: Identifiable {
    var id: String {
        title
    }

    let title: String
    let subtitle: String
    let symbolName: String?
    let assetName: String?
    let tint: Color
    let selection: FileManagerHomeSelection
}

private struct QuickAccessCard: View {
    let item: QuickAccessItem
    let itemCount: Int?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 22) {
                FolderSymbol(
                    symbolName: item.symbolName,
                    badgeSymbolName: item.badgeSymbolName,
                    tint: item.tint,
                )

                VStack(alignment: .center, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    HStack(spacing: 4) {
                        Text("Items")
                        if let itemCount {
                            Text("\(itemCount)")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .center)
            .padding(22)
            .background(cardBackground)
            .scaleEffect(isHovered ? 1.012 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.34 : 0.18), lineWidth: 1),
            )
            .shadow(color: .black.opacity(isHovered ? 0.12 : 0.07), radius: isHovered ? 14 : 10, y: 5)
    }
}

private struct GetStartedCard: View {
    let item: GetStartedItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ActionIcon(symbolName: item.symbolName, assetName: item.assetName, tint: item.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Text(item.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(x: isHovered ? 2 : 0)
                    .animation(.easeOut(duration: 0.14), value: isHovered)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(cardBackground)
            .scaleEffect(isHovered ? 1.008 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.34 : 0.18), lineWidth: 1),
            )
            .shadow(color: .black.opacity(isHovered ? 0.11 : 0.06), radius: isHovered ? 13 : 9, y: 4)
    }
}

private struct FolderSymbol: View {
    let symbolName: String
    let badgeSymbolName: String
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: 52, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.22), radius: 8, y: 3)

            badgeImage
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.gradient))
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .offset(x: 4, y: 1)
        }
        .frame(width: 72, height: 58, alignment: .leading)
    }

    @ViewBuilder
    private var badgeImage: some View {
        if badgeSymbolName == "appstore", let appIcon = applicationsSidebarIcon() {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(5)
        } else {
            Image(systemName: badgeSymbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
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
}

private struct ActionIcon: View {
    let symbolName: String?
    let assetName: String?
    let tint: Color

    var body: some View {
        icon
            .frame(width: 58, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.13)),
            )
    }

    @ViewBuilder
    private var icon: some View {
        if let assetName, let image = NSImage(named: assetName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        } else if let symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
    }
}
