import SwiftUI

struct ComposerScopeComboBoxView: View {
    @Binding var isPresented: Bool
    let oldPath: String?
    let onSelect: (String) -> Void
    let favorites: [SidebarUtils.FavoriteItem]
    let backHistory: [String]

    @State private var searchText: String = ""
    @State private var searchResults: [ComposerScopeUtils.DirectoryItem] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme)
    private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            listContent
        }
        .frame(width: 200)
        .frame(maxHeight: 400)
        .background(comboBoxBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(comboBoxBorderColor, lineWidth: 1),
        )
        .shadow(color: comboBoxShadowColor, radius: 8, y: 4)
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
            .background(searchFieldBackgroundColor)

            separatorColor
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

    @ViewBuilder
    private func directoryRow(item: ComposerScopeUtils.DirectoryItem) -> some View {
        Button {
            onSelect(item.path)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

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
        }
        .buttonStyle(.plain)
    }

    private var comboBoxBackgroundColor: Color {
        if isDark {
            Color(red: 0.19, green: 0.19, blue: 0.19)
        } else {
            Color.white
        }
    }

    private var comboBoxBorderColor: Color {
        if isDark {
            Color.white.opacity(0.1)
        } else {
            Color.black.opacity(0.12)
        }
    }

    private var comboBoxShadowColor: Color {
        if isDark {
            Color.black.opacity(0.4)
        } else {
            Color.black.opacity(0.15)
        }
    }

    private var searchFieldBackgroundColor: Color {
        if isDark {
            Color.white.opacity(0.05)
        } else {
            Color.black.opacity(0.03)
        }
    }

    private var separatorColor: Color {
        if isDark {
            Color.white.opacity(0.1)
        } else {
            Color.black.opacity(0.1)
        }
    }
}
