import AppKit
import SwiftUI

struct FileItemRowView: View {
    let item: FileItemModel
    let onTap: () -> Void

    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : FileItemManager.shared.getFileIcon(for: item.name))
                .foregroundColor(item.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            Text(item.name)
                .foregroundColor(.primary)

            Spacer()

            // 크기 (파일인 경우)
            if !item.isDirectory {
                Text(FileItemManager.shared.getFileSize(for: item.fullPath))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Show in Finder") {
                FileItemManager.shared.showInFinder(filePath: item.fullPath)
            }

            if !item.isDirectory {
                Button("Open") {
                    FileItemManager.shared.openFile(filePath: item.fullPath)
                }
            }
        }
    }
}
