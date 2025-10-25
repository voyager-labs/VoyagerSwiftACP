import SwiftUI

struct FSItemRowView: View {
    let item: FSItemModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 아이콘
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(item.isDirectory ? .blue : .gray)
                .frame(width: 20)

            // 이름
            Text(item.name)
                .font(.system(size: 13))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onOpen()
        }
    }
}
