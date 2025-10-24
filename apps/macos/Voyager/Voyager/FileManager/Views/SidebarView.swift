import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundColor(store.selectedSidebarItem == "Recents" ? .blue : .primary)
                    .frame(width: 16)
                Text("Recents")
                    .foregroundColor(store.selectedSidebarItem == "Recents" ? .blue : .primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                store.selectedSidebarItem == "Recents" ?
                    RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)) :
                    RoundedRectangle(cornerRadius: 6).fill(Color.clear)
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .onTapGesture {
                store.send(.showRecents)
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(store.selectedSidebarItem == "Shared" ? .blue : .primary)
                    .frame(width: 16)
                Text("Shared")
                    .foregroundColor(store.selectedSidebarItem == "Shared" ? .blue : .primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                store.selectedSidebarItem == "Shared" ?
                    RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)) :
                    RoundedRectangle(cornerRadius: 6).fill(Color.clear)
            )
            .padding(.horizontal, 8)
            .onTapGesture {
                store.send(.showShared)
            }

            Spacer()
                .frame(height: 8)

            if !store.locations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(store.locations, id: \.url) { location in
                        HStack(spacing: 8) {
                            Image(systemName: location.iconName)
                                .foregroundColor(store.selectedSidebarItem == location.name ? .blue : .primary)
                                .frame(width: 16)
                            Text(location.name)
                                .foregroundColor(store.selectedSidebarItem == location.name ? .blue : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            store.selectedSidebarItem == location.name ?
                                RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)) :
                                RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                        )
                        .padding(.horizontal, 8)
                        .onTapGesture {
                            store.send(.openLocation(location))
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(minWidth: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
