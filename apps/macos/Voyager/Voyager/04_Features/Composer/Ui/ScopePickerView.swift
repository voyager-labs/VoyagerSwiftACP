import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesEntry
import VoyagerShared

struct ScopePickerView: View {
    let oldPath: String?
    let onSelect: (String) -> Void
    let favorites: [ScopeFavoriteItem]
    let backHistory: [String]

    @State private var searchText: String = ""
    @State private var hoveredPath: String?
    @StateObject private var searchCoordinator: ScopePickerSearchCoordinator
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme)
    private var colorScheme

    @Binding var isPresented: Bool

    init(
        isPresented: Binding<Bool>,
        oldPath: String?,
        onSelect: @escaping (String) -> Void,
        favorites: [ScopeFavoriteItem],
        backHistory: [String],
        entryLoadingClient: EntryLoadingClient,
    ) {
        _isPresented = isPresented
        self.oldPath = oldPath
        self.onSelect = onSelect
        self.favorites = favorites
        self.backHistory = backHistory
        _searchCoordinator = StateObject(
            wrappedValue: ScopePickerSearchCoordinator(
                entryLoadingClient: entryLoadingClient,
                favorites: favorites,
                backHistory: backHistory,
            ),
        )
    }

    private var searchField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search directories...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(VoyagerDS.Surface.popoverSearchFieldBackground(for: colorScheme))

            VoyagerDS.SystemColor.separator
                .frame(height: 1)
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch searchCoordinator.listState {
                case let .defaultList(items), let .searchResults(items):
                    ForEach(items) { item in
                        directoryRow(item: item)
                    }
                case .noResults:
                    Text("No directories found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            listContent
        }
        .frame(width: 200)
        .frame(maxHeight: 400)
        .background(VoyagerDS.Surface.popoverBackground(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
        )
        .shadow(
            color: VoyagerDS.Shadow.popoverColor(for: colorScheme),
            radius: VoyagerDS.Shadow.popoverRadius,
            y: VoyagerDS.Shadow.popoverYOffset,
        )
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) { _ in
            searchCoordinator.update(query: searchText)
        }
        .onDisappear {
            searchCoordinator.stop()
        }
    }

    @ViewBuilder
    private func directoryRow(item: ComposerScopeUtils.DirectoryItem) -> some View {
        Button {
            onSelect(item.path)
            isPresented = false
        } label: {
            let isHovering = hoveredPath == item.path
            HStack(spacing: 8) {
                if item.path == "/Applications", let appIcon = applicationsIcon() {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }

                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPath = hovering ? item.path : nil
        }
    }

    private func applicationsIcon() -> NSImage? {
        let appIcon = NSImage(
            contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns",
        )
        appIcon?.isTemplate = true
        return appIcon
    }
}
