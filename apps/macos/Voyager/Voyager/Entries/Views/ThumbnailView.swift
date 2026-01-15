import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailView: View {
    let item: Entry
    let displaySize: CGFloat
    let isReady: Bool

    @Dependency(\.workspaceClient)
    private var workspaceClient

    var body: some View {
        Image(nsImage: displayIcon)
            .resizable()
            .scaledToFit()
            .scaleEffect(item.fileExtension.lowercased() == "voycoll" ? 0.88 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .id("\(item.fullPath)-\(isReady)")
    }

    private var displayIcon: NSImage {
        if let cached = EntryIconUtils.getThumbnail(for: item.fullPath) {
            return cached
        }

        // 아이콘 캐싱 키 생성
        let cacheKey: String = if item.fullPath == "/" {
            "root:/"
        } else if item.fileExtension.lowercased() == "voycoll" {
            "asset:\(EntryIconUtils.voycollIconName)"
        } else if item.isDirectory {
            "dir:\(item.fullPath)"
        } else {
            UTType(filenameExtension: item.fileExtension)
                .map { "type:\($0.identifier)" }
                ?? "generic:file"
        }

        // 캐시 확인
        if let cached = EntryIconUtils.getCachedIcon(for: cacheKey) {
            return cached
        }

        // 아이콘 가져오기
        let icon: NSImage = if item.fullPath == "/" {
            workspaceClient.iconForFile("/")
        } else if item.fileExtension.lowercased() == "voycoll" {
            if let voycollIcon = NSImage(named: EntryIconUtils.voycollIconName) {
                voycollIcon
            } else {
                workspaceClient.iconForType(.data)
            }
        } else if item.isDirectory {
            workspaceClient.iconForFile(item.fullPath)
        } else {
            if let utType = UTType(filenameExtension: item.fileExtension) {
                workspaceClient.iconForType(utType)
            } else {
                workspaceClient.iconForType(.data)
            }
        }

        // 캐시 저장
        EntryIconUtils.setCachedIcon(icon, for: cacheKey)
        return icon
    }
}
