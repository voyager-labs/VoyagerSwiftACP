import SwiftUI

struct ColumnHeaderView: View {
    let availableWidth: CGFloat

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
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20, height: 1)

                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(width: columnWidths.name, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.leading, 8)

            Divider()
                .frame(height: 20)

            Text("Date Modified")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: columnWidths.date, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.leading, 8)

            Divider()
                .frame(height: 20)

            Text("Size")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: columnWidths.size, alignment: .trailing)
                .padding(.vertical, 6)
                .padding(.trailing, 8)

            Divider()
                .frame(height: 20)

            Text("Kind")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: columnWidths.kind, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.leading, 8)
        }
        .background(Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }
}

#Preview {
    ColumnHeaderView(availableWidth: 800)
        .frame(height: 30)
}
