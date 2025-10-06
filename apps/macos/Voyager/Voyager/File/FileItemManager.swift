import AppKit
import Foundation

class FileItemManager {
    static let shared = FileItemManager()

    private init() {}

    func getFileIcon(for fileName: String) -> String {
        let pathExtension = (fileName as NSString).pathExtension.lowercased()

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

    func getFileSize(for filePath: String) -> String {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            return ""
        }
        return ""
    }

    func showInFinder(filePath: String) {
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
    }

    func openFile(filePath: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
    }

    func getFolderContents(at path: String) -> [FileItemModel] {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles]
            )

            let items = contents.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileItemModel(
                    name: url.lastPathComponent,
                    fullPath: url.path,
                    isDirectory: isDirectory
                )
            }

            // 폴더를 먼저, 파일을 나중에 표시
            return items.sorted { first, second in
                if first.isDirectory != second.isDirectory {
                    return first.isDirectory
                }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
        } catch {
            return []
        }
    }
}
