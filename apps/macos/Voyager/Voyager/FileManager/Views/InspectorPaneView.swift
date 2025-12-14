import AppKit
import ComposableArchitecture
import SwiftUI

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var chatInput: String = ""
    @Environment(\.colorScheme)
    var colorScheme

    var body: some View {
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
                folderScopeChip
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
                .fill(chatInputBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
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
                        .fill(Color(red: 0.843, green: 0.714, blue: 0.322))
                )
        }
        .buttonStyle(.plain)
        .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                .font(.system(size: 11))
            Text(folderDisplayName)
                .font(.system(size: 12, weight: .light))
        }
        .foregroundColor(folderChipTextColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(folderChipBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(folderChipBorderColor, lineWidth: 1)
                )
        )
    }

    private var folderDisplayName: String {
        FileManagerFeature.makeWindowTitle(for: store.currentPath)
    }

    private var singleLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let lineHeight = font.ascender - font.descender + font.leading
        return ceil(lineHeight)
    }

    private var maxHeight: CGFloat {
        singleLineHeight * 7
    }

    private var chatInputBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 44 / 255.0, green: 43 / 255.0, blue: 40 / 255.0)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var folderChipBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0x37 / 255.0, green: 0x34 / 255.0, blue: 0x30 / 255.0)
        } else {
            return Color(red: 0xFB / 255.0, green: 0xFB / 255.0, blue: 0xFB / 255.0)
        }
    }

    private var folderChipBorderColor: Color {
        if colorScheme == .dark {
            return Color(red: 0x4D / 255.0, green: 0x49 / 255.0, blue: 0x43 / 255.0)
        } else {
            return Color.black.opacity(0.06)
        }
    }

    private var folderChipTextColor: Color {
        if colorScheme == .dark {
            return Color(red: 218 / 255.0, green: 215 / 255.0, blue: 210 / 255.0)
        } else {
            return Color(red: 50 / 255.0, green: 50 / 255.0, blue: 50 / 255.0)
        }
    }
}
