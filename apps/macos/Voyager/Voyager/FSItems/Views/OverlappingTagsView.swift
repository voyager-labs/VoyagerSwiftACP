import SwiftUI

struct OverlappingTagsView: View {
    let tags: [FileTag]
    let isSelected: Bool
    let showBorderWhenUnselected: Bool

    private let tagSize: CGFloat = 8
    private let overlapOffset: CGFloat = -4

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(tags.prefix(3).enumerated()), id: \.element.self) { index, tag in
                Circle()
                    .fill(FSItemTagUtils.getTagColor(colorCode: tag.colorCode))
                    .frame(width: tagSize, height: tagSize)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: 0.5),
                    )
                    .offset(x: CGFloat(index) * overlapOffset)
            }
        }
        .frame(width: calculateTotalWidth(), height: tagSize)
    }

    private var borderColor: Color {
        if isSelected {
            .white
        } else if showBorderWhenUnselected {
            .black.opacity(0.3)
        } else {
            .clear
        }
    }

    private func calculateTotalWidth() -> CGFloat {
        let tagCount = min(tags.count, 3)
        guard tagCount > 0 else { return 0 }

        return tagSize + CGFloat(tagCount - 1) * abs(overlapOffset)
    }
}
