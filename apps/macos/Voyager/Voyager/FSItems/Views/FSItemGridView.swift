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
            Image(nsImage: FSItemsIconUtils.icon(for: item))
                .resizable()
                .scaledToFit()
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                .frame(width: 64, height: 64)

            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80, height: 28, alignment: .top)
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
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
