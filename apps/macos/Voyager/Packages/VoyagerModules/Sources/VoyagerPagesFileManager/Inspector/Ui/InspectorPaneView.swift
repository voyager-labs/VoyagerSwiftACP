import AppKit
import ComposableArchitecture
import SwiftUI

public struct InspectorPaneView: View {
    public let store: StoreOf<FileManagerInspectorFeature>
    @State private var chatInput: String = ""
    @Environment(\.colorScheme)
    var colorScheme

    public init(store: StoreOf<FileManagerInspectorFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    // TODO: 메뉴 기능 구현
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

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
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var chatInputArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $chatInput)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(minHeight: singleLineHeight, maxHeight: maxHeight)
                    .fixedSize(horizontal: false, vertical: !chatInput.isEmpty)

                if chatInput.isEmpty {
                    Text("Ask anything...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                        .padding(.leading, 4)
                }
            }
            .frame(height: chatInput.isEmpty ? singleLineHeight : nil)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Spacer()
                submitButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(chatInputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1),
                ),
        )
        .padding(.horizontal, 8)
    }

    private var submitButton: some View {
        Button(action: submitMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color(red: 215 / 255.0, green: 182 / 255.0, blue: 82 / 255.0)),
                )
        }
        .buttonStyle(.plain)
        .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submitMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        print("Submitting message: \(chatInput)")
        chatInput = ""
    }

    private var chatInputBackground: Color {
        colorScheme == .dark
            ? Color(red: 44 / 255.0, green: 43 / 255.0, blue: 40 / 255.0)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var singleLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let lineHeight = font.ascender - font.descender + font.leading
        return ceil(lineHeight)
    }

    private var maxHeight: CGFloat {
        singleLineHeight * 7
    }
}
