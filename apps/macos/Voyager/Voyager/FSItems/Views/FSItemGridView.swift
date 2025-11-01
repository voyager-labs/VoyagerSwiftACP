import AppKit
import SwiftUI

struct FSItemGridView: View {
    let item: FSItem
    let isSelected: Bool
    let isCut: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(item: item, displaySize: 64)
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                .frame(width: 64, height: 64)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.gray.opacity(0.2) : Color.clear)
                )

            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 80, height: 28, alignment: .top)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    onSelect()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    if item.isDirectory {
                        onOpen()
                    }
                }
        )
    }
}
