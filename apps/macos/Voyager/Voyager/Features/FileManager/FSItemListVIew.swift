import SwiftUI

struct FSItemListView: View {
    let item: FSItemModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(item.isDirectory ? .blue : .gray)
                .opacity(item.isHidden ? 0.5 : 1.0)
                .frame(width: 20)

            Text(item.name)
                .font(.system(size: 13))
                .opacity(item.isHidden ? 0.5 : 1.0)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    onSelect()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onOpen()
                }
        )
    }
}
