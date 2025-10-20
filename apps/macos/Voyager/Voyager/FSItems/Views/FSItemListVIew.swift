import SwiftUI

struct FSItemListView: View {
    let item: FSItemModel
    let isSelected: Bool
    let availableWidth: CGFloat
    let onSelect: () -> Void
    let onOpen: () -> Void

    private struct ColumnWidths {
        let name: CGFloat
        let date: CGFloat
        let size: CGFloat
        let kind: CGFloat
    }

    private var columnWidths: ColumnWidths {
        let totalPadding = 16.0
        let dividerWidth = 3.0 * 1.0
        let availableForColumns = availableWidth - totalPadding - dividerWidth

        return ColumnWidths(
            name: availableForColumns * 0.4,
            date: availableForColumns * 0.35,
            size: availableForColumns * 0.1,
            kind: availableForColumns * 0.15
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(item.isDirectory ? .blue : .gray)
                    .opacity(item.isHidden ? 0.5 : 1.0)
                    .frame(width: 20)

                Text(item.name)
                    .font(.system(size: 13))
                    .opacity(item.isHidden ? 0.5 : 1.0)
                    .lineLimit(1)
            }
            .frame(width: columnWidths.name, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.leading, 8)

            Text(dateText(item.modifiedDate))
                .font(.system(size: 12))
                .opacity(item.isHidden ? 0.5 : 1.0)
            .frame(width: columnWidths.date, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.leading, 8)

            Text(sizeText(item))
                .font(.system(size: 12))
                .opacity(item.isHidden ? 0.5 : 1.0)
            .frame(width: columnWidths.size, alignment: .trailing)
            .padding(.vertical, 6)
            .padding(.trailing, 8)

            Text(kindText(item))
                .font(.system(size: 12))
                .opacity(item.isHidden ? 0.5 : 1.0)
            .frame(width: columnWidths.kind, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.leading, 8)
        }
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
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

    private func sizeText(_ item: FSItemModel) -> String {
        if item.isDirectory { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: item.size)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func kindText(_ item: FSItemModel) -> String {
        if item.isDirectory {
            return "Folder"
        }
        return item.fileExtension.isEmpty ? "File" : item.fileExtension.capitalized
    }
}
