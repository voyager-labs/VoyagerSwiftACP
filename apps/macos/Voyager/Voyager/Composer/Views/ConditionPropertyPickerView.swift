import ComposableArchitecture
import SwiftUI

struct ConditionPropertyPickerView: View {
    let store: StoreOf<ConditionPropertyPickerFeature>
    @Environment(\.colorScheme)
    private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var hoveredPropertyKey: String?
    @State private var hoveredCategoryKey: String?

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(spacing: 0) {
                searchField(viewStore)
                if let message = viewStore.duplicateMessage {
                    duplicateWarning(message)
                    separatorColor
                        .frame(height: 1)
                }
                content(viewStore)
            }
            .frame(width: 200, height: 320)
            .background(comboBoxBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(comboBoxBorderColor, lineWidth: 1),
            )
            .shadow(color: comboBoxShadowColor, radius: 8, y: 4)
            .onAppear {
                viewStore.send(.onAppear)
            }
        })
    }

    private func searchField(_ viewStore: ViewStoreOf<ConditionPropertyPickerFeature>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                ZStack(alignment: .leading) {
                    if viewStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Search attributes")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                            .padding(.leading, 2)
                    }

                    FocusedTextField(
                        text: viewStore.binding(
                            get: \.searchText,
                            send: ConditionPropertyPickerFeature.Action.searchTextChanged,
                        ),
                        isFirstResponder: Binding(
                            get: { isSearchFocused },
                            set: { isSearchFocused = $0 },
                        ),
                    )
                    .font(.system(size: 13))
                }

                if !viewStore.searchText.isEmpty {
                    Button {
                        viewStore.send(.searchTextChanged(""))
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
            .onAppear {
                isSearchFocused = true
            }

            separatorColor
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func content(_ viewStore: ViewStoreOf<ConditionPropertyPickerFeature>) -> some View {
        switch viewStore.mode {
        case .root:
            rootContent(viewStore)

        case let .category(categoryKey):
            categoryContent(viewStore, categoryKey: categoryKey)
        }
    }

    private func rootContent(_ viewStore: ViewStoreOf<ConditionPropertyPickerFeature>) -> some View {
        let filtered = filteredProperties(viewStore)
        let recommended = filtered.filter(\.isDefault)
        let grouped = Dictionary(grouping: filtered, by: { $0.category })
        let hasRecommended = !recommended.isEmpty

        return ScrollView {
            VStack(spacing: 0) {
                recommendedSection(recommended, viewStore: viewStore)
                categorySection(grouped, hasRecommended: hasRecommended, viewStore: viewStore)
                emptyStateIfNeeded(filtered: filtered, query: viewStore.searchText)
            }
        }
    }

    private func categoryContent(
        _ viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
        categoryKey: String,
    ) -> some View {
        let filtered = filteredProperties(viewStore)
        let items = filtered.filter { $0.category == categoryKey }

        return VStack(spacing: 0) {
            HStack {
                Button {
                    viewStore.send(.backFromCategory)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(categoryTitle(for: categoryKey))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if !items.isEmpty {
                        ForEach(items) { property in
                            propertyRow(property, viewStore: viewStore, showIcon: false)
                        }
                    } else if !viewStore.searchText.isEmpty {
                        Text("No properties found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recommendedSection(
        _ recommended: [MDItemProperty],
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> some View {
        if !recommended.isEmpty {
            ForEach(recommended) { property in
                propertyRow(property, viewStore: viewStore, showIcon: false)
            }
        }
    }

    @ViewBuilder
    private func categorySection(
        _ grouped: [String: [MDItemProperty]],
        hasRecommended: Bool,
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> some View {
        if !grouped.isEmpty {
            if hasRecommended {
                separatorColor
                    .frame(height: 1)
            }

            ForEach(grouped.keys.sorted(), id: \.self) { key in
                categoryRow(
                    categoryKey: key,
                    items: grouped[key] ?? [],
                    viewStore: viewStore,
                )
            }
        }
    }

    @ViewBuilder
    private func emptyStateIfNeeded(filtered: [MDItemProperty], query: String) -> some View {
        if filtered.isEmpty, !query.isEmpty {
            Text("No properties found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.vertical, 16)
        }
    }

    private func categoryRow(
        categoryKey: String,
        items: [MDItemProperty],
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> some View {
        Button {
            viewStore.send(.categoryTapped(categoryKey))
        } label: {
            let isHovering = hoveredCategoryKey == categoryKey
            HStack(spacing: 8) {
                Text(categoryTitle(for: categoryKey))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? rowHoverFillColor : Color.clear),
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCategoryKey = hovering ? categoryKey : nil
        }
    }

    private func filteredProperties(
        _ viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> [MDItemProperty] {
        let existingKeys = viewStore.existingKeys
        let editingKey = viewStore.editingConditionKey
        let props = viewStore.properties.filter { property in
            if existingKeys.contains(property.key), property.key != editingKey {
                return false
            }
            return true
        }
        let query = viewStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return props }

        return props.filter { property in
            property.label.localizedCaseInsensitiveContains(query)
        }
    }

    private func propertyRow(
        _ property: MDItemProperty,
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
        showIcon: Bool = true,
    ) -> some View {
        Button {
            viewStore.send(.propertyTapped(property))
        } label: {
            let isHovering = hoveredPropertyKey == property.key
            HStack(spacing: 8) {
                if showIcon {
                    Image(systemName: iconName(for: property.category))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }

                Text(property.label)
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
                    .fill(isHovering ? rowHoverFillColor : Color.clear),
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPropertyKey = hovering ? property.key : nil
        }
    }

    private func categoryTitle(for key: String) -> String {
        switch key {
        case "filesystem": "System Metadata"
        case "image": "Image"
        case "video": "Video"
        case "audio": "Audio"
        case "document": "Document"
        case "download": "Download"
        case "content": "Content"
        case "location": "Location"
        default: key
        }
    }

    private func iconName(for category: String) -> String {
        switch category {
        case "filesystem": "gearshape"
        case "image": "photo"
        case "video": "video"
        case "audio": "speaker.wave.2"
        case "document": "doc.text"
        case "download": "arrow.down.circle"
        case "content": "square.stack.3d.down.right"
        case "location": "mappin.and.ellipse"
        default: "questionmark.circle"
        }
    }
}

// MARK: - Style Helpers

private extension ConditionPropertyPickerView {
    var comboBoxBackgroundColor: Color {
        if isDark {
            Color(red: 0.19, green: 0.19, blue: 0.19)
        } else {
            Color.white
        }
    }

    var comboBoxBorderColor: Color {
        if isDark {
            Color.white.opacity(0.1)
        } else {
            Color.black.opacity(0.12)
        }
    }

    var comboBoxShadowColor: Color {
        if isDark {
            Color.black.opacity(0.4)
        } else {
            Color.black.opacity(0.15)
        }
    }

    var searchFieldBackgroundColor: Color {
        if isDark {
            Color.white.opacity(0.05)
        } else {
            Color.black.opacity(0.03)
        }
    }

    var separatorColor: Color {
        if isDark {
            Color.white.opacity(0.1)
        } else {
            Color.black.opacity(0.1)
        }
    }

    var rowHoverFillColor: Color {
        if isDark {
            Color.white.opacity(0.08)
        } else {
            Color.black.opacity(0.06)
        }
    }

    func duplicateWarning(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.primary)
            Spacer()
            Button {
                store.send(.clearDuplicateMessage)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
    }
}
