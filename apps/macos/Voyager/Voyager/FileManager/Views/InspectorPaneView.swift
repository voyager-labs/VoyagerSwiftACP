import ComposableArchitecture
import SwiftUI

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var chatInput: String = ""

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
        VStack(alignment: .leading, spacing: 0) {
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
        .frame(width: 300, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    private var chatInputArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                folderScopeChip
                itemCountChip
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            TextField("Ask anything ...", text: $chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1...)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .onSubmit {
                    submitMessage()
                }
        }
        .frame(height: 120, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.22, green: 0.24, blue: 0.27))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func submitMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // TODO: 메시지 전송 로직 구현
        print("Submitting message: \(chatInput)")
        chatInput = ""
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
            .font(.system(size: 10))
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
            )
    }

    private var folderDisplayName: String {
        FileManagerFeature.makeWindowTitle(for: store.currentPath)
    }
}
