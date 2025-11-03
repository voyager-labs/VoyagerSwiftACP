import ComposableArchitecture
import SwiftUI

struct SidebarItemView: View {
    let iconName: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @ViewBuilder private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(isSelected ? .blue : .primary)
                .frame(width: 16)
            Text(title)
                .foregroundColor(isSelected ? .blue : .primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .onTapGesture {
            action()
        }
    }
}

struct TagItemView: View {
    let tag: SidebarUtils.TagItem
    let isSelected: Bool
    let action: () -> Void

    @ViewBuilder private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tag.color)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .foregroundColor(isSelected ? .blue : .primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .onTapGesture {
            action()
        }
    }
}

struct SidebarView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarItemView(
                    iconName: "clock",
                    title: "Recents",
                    isSelected: store.selectedSidebarItem == "Recents"
                ) {
                    store.send(.showRecents)
                }
                .padding(.top, 8)

                SidebarItemView(
                    iconName: "folder",
                    title: "Shared",
                    isSelected: store.selectedSidebarItem == "Shared"
                ) {
                    store.send(.showShared)
                }

                Spacer()
                    .frame(height: 8)

                locationsSection

                Spacer()
                    .frame(height: 8)

                tagsSection

                Spacer()
            }
        }
        .frame(minWidth: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var locationsSection: some View {
        Group {
            if !store.locations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(store.locations, id: \.url) { location in
                        SidebarItemView(
                            iconName: location.iconName,
                            title: location.name,
                            isSelected: store.selectedSidebarItem == location.name
                        ) {
                            store.send(.openLocation(location))
                        }
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        Group {
            if !store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(store.tags, id: \.name) { tag in
                        TagItemView(
                            tag: tag,
                            isSelected: store.selectedSidebarItem == tag.name
                        ) {
                            store.send(.showTag(tag))
                        }
                    }
                }
            }
        }
    }
}
