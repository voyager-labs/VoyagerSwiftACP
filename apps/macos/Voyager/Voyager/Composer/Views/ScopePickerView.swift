import AppKit
import SwiftUI

struct ScopePickerView: View {
    @Binding var isPresented: Bool
    let oldPath: String?
    let onSelect: (String) -> Void
    let favorites: [SidebarUtils.FavoriteItem]
    let backHistory: [String]

    @State private var searchText: String = ""
    @State private var searchResults: [ComposerScopeUtils.DirectoryItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var hoveredPath: String?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme)
    private var colorScheme

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
            searchTask?.cancel()

            if searchText.isEmpty {
                searchResults = []
            } else {
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

                    guard !Task.isCancelled else { return }

                    let results = try? await Task.detached(priority: .userInitiated) {
                        try await ComposerScopeUtils.searchDirectories(
                            query: searchText,
                            maxResults: 50,
                            initialMaxDepth: 2,
                            timeout: 2.0,
                        )
                    }.value

                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        searchResults = results ?? []
                    }
                }
            }
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
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
                if !searchResults.isEmpty {
                    ForEach(searchResults) { item in
                        directoryRow(item: item)
                    }
                } else if searchText.isEmpty {
                    let combinedList = ComposerScopeUtils.buildCombinedList(
                        history: backHistory,
                        favorites: favorites,
                        maxCount: 10,
                    )

                    ForEach(combinedList) { item in
                        directoryRow(item: item)
                    }
                } else {
                    Text("No directories found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private func applicationsIcon() -> NSImage? {
        var appIcon = NSImage(
            contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns",
        )
        appIcon?.isTemplate = true
        return appIcon
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
}
