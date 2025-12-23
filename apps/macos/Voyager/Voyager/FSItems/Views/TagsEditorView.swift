import SwiftUI

/// 태그 편집 팝오버 뷰
struct TagsEditorView: View {
    let fileName: String
    let currentTags: [FileTag]
    let onToggleTag: (String) -> Void

    private let tagNames = FSItemTagUtils.getFavoriteTagNames().filter { !$0.isEmpty }
    private let nameToColorCode = FSItemTagUtils.getTagNameToColorCodeMapping()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Assign tags to \"\(fileName)\"")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(tagNames.enumerated()), id: \.offset) { _, tag in
                    let colorCode = nameToColorCode[tag] ?? 0
                    let tagColor = FSItemTagUtils.getTagColor(colorCode: colorCode)
                    let isTagged = currentTags.contains(where: { $0.name == tag })

                    Button {
                        onToggleTag(tag)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tagColor)
                                .frame(width: 10, height: 10)

                            Text(tag)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)

                            if isTagged {
                                Text("✓")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TagButtonStyle())
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct TagButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.5)
                    : Color.clear,
            )
    }
}
