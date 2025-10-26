import AppKit
import Foundation
import UniformTypeIdentifiers

enum FSItemsIconUtils {
    static func icon(for item: FSItem) -> NSImage {
        if item.isDirectory {
            return NSWorkspace.shared.icon(forFile: item.fullPath)
        }

        // 파일 타입별 아이콘 가져오기
        if let type = UTType(filenameExtension: item.fileExtension) {
            return NSWorkspace.shared.icon(for: type)
        }

        return NSWorkspace.shared.icon(forFile: item.fullPath)
    }
}
