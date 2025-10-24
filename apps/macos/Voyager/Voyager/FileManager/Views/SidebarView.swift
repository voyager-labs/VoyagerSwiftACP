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
        }
        .frame(minWidth: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
