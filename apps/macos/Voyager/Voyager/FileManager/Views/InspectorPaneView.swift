import ComposableArchitecture
import SwiftUI

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerFeature>

    private var scopeText: String {
        let total = store.fsItems.items.count
        let selected = store.fsItems.selectedIds.count

        if selected == 0 {
            return "Chat with \(total) items"
        } else {
            return "Chat with selected \(selected) \(selected == 1 ? "item" : "items")"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    store.send(.toggleInspector)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Spacer()

            chatInputArea
        }
        .frame(width: 300)
        .background(Color.black)
    }

    private var chatInputArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.22, green: 0.24, blue: 0.27))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

            HStack(spacing: 6) {
                folderScopeChip
                itemCountChip
            }
            .padding(10)
        }
        .frame(height: 120)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var folderScopeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 9))
            Text(folderDisplayName)
                .font(.system(size: 10))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.15))
        )
    }

    private var itemCountChip: some View {
        Text(scopeText)
            .font(.system(size: 11))
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )
    }

    private var folderDisplayName: String {
        FileManagerFeature.makeWindowTitle(for: store.currentPath)
    }
}
