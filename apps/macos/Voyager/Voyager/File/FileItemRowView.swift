import AppKit
import SwiftUI

/// 파일 아이템 행 뷰
struct FileItemRowView: View {
    let item: FileItemModel
    let onTap: () -> Void

    var body: some View {
        HStack {
            // 아이콘
            Image(systemName: item.isDirectory ? "folder.fill" : getFileIcon())
                .foregroundColor(item.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            // 이름
            Text(item.name)
                .foregroundColor(.primary)

            Spacer()

            // 크기 (파일인 경우)
            if !item.isDirectory {
                Text(getFileSize())
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
                NSWorkspace.shared.selectFile(item.fullPath, inFileViewerRootedAtPath: "")
            }

            if !item.isDirectory {
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.fullPath))
                }
            }
        }
    }

    private func getFileIcon() -> String {
        let pathExtension = (item.name as NSString).pathExtension.lowercased()

        switch pathExtension {
        case "txt", "md":
            return "doc.text.fill"
        case "pdf":
            return "doc.fill"
        case "jpg", "jpeg", "png", "gif":
            return "photo.fill"
        case "mp4", "mov", "avi":
            return "video.fill"
        case "mp3", "wav", "m4a":
            return "music.note"
        case "zip", "rar", "7z":
            return "archivebox.fill"
        default:
            return "doc.fill"
        }
    }

    private func getFileSize() -> String {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfItem(atPath: item.fullPath)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            return ""
        }
        return ""
    }
}
