import ComposableArchitecture
import SwiftUI

struct ConditionPropertyPickerView: View {
    let store: StoreOf<ConditionPropertyPickerFeature>
    @Environment(\.colorScheme)
    private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var hoveredPropertyKey: String?
    @State private var hoveredCategoryKey: String?

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(spacing: 0) {
                searchField(viewStore)
                if let message = viewStore.duplicateMessage {
                    duplicateWarning(message)
                    VoyagerDS.SystemColor.separator
                        .frame(height: 1)
                }
                content(viewStore)
            }
            .frame(width: 200, height: 320)
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
            .background(VoyagerDS.Surface.popoverSearchFieldBackground(for: colorScheme))
            .onAppear {
                isSearchFocused = true
            }

            VoyagerDS.SystemColor.separator
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
        let filtered = ConditionPropertyPickerDisplayUtils.filteredProperties(
            properties: viewStore.properties,
            existingKeys: viewStore.existingKeys,
            editingKey: viewStore.editingConditionKey,
            searchText: viewStore.searchText,
            labels: viewStore.propertyLabels,
        )
        let recommended = ConditionPropertyPickerDisplayUtils.recommendedProperties(
            from: filtered,
            defaults: viewStore.propertyDefaults,
        )
        let grouped = ConditionPropertyPickerDisplayUtils.groupedByCategory(
            filtered,
            categories: viewStore.propertyCategories,
        )
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
        let filtered = ConditionPropertyPickerDisplayUtils.filteredProperties(
            properties: viewStore.properties,
            existingKeys: viewStore.existingKeys,
            editingKey: viewStore.editingConditionKey,
            searchText: viewStore.searchText,
            labels: viewStore.propertyLabels,
        )
        let items = filtered.filter { viewStore.propertyCategories[$0] == categoryKey }

        return VStack(spacing: 0) {
            HStack {
                Button {
                    viewStore.send(.backFromCategory)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(ConditionPropertyPickerDisplayUtils.categoryTitle(for: categoryKey))
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
                        ForEach(items, id: \.self) { key in
                            propertyRow(key, viewStore: viewStore, showIcon: true)
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
        _ recommended: [String],
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> some View {
        if !recommended.isEmpty {
            ForEach(recommended, id: \.self) { key in
                propertyRow(key, viewStore: viewStore, showIcon: true)
            }
        }
    }

    @ViewBuilder
    private func categorySection(
        _ grouped: [String: [String]],
        hasRecommended: Bool,
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> some View {
        if !grouped.isEmpty {
            if hasRecommended {
                VoyagerDS.SystemColor.separator
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
    private func emptyStateIfNeeded(filtered: [String], query: String) -> some View {
        if filtered.isEmpty, !query.isEmpty {
            Text("No properties found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.vertical, 16)
        }
    }

    private func categoryRow(
        categoryKey: String,
        items: [String],
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
    ) -> some View {
        Button {
            viewStore.send(.categoryTapped(categoryKey))
        } label: {
            let isHovering = hoveredCategoryKey == categoryKey
            HStack(spacing: 8) {
                Image(systemName: ConditionPropertyIconUtils.iconName(forCategory: categoryKey))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(ConditionPropertyPickerDisplayUtils.categoryTitle(for: categoryKey))
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
                    .fill(isHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCategoryKey = hovering ? categoryKey : nil
        }
    }

    private func propertyRow(
        _ propertyKey: String,
        viewStore: ViewStoreOf<ConditionPropertyPickerFeature>,
        showIcon: Bool = true,
    ) -> some View {
        Button {
            viewStore.send(.propertyTapped(propertyKey))
        } label: {
            let isHovering = hoveredPropertyKey == propertyKey
            let label = viewStore.propertyLabels[propertyKey] ?? propertyKey
            let category = viewStore.propertyCategories[propertyKey]
            let type = viewStore.propertyTypes[propertyKey]
            HStack(spacing: 8) {
                if showIcon {
                    Image(
                        systemName: ConditionPropertyIconUtils.iconName(
                            forKey: propertyKey,
                            category: category,
                            type: type,
                        ),
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                }

                Text(label)
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
            hoveredPropertyKey = hovering ? propertyKey : nil
        }
    }
}

private extension ConditionPropertyPickerView {
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
        .background(VoyagerDS.Surface.popoverSearchFieldBackground(for: colorScheme))
    }
}
