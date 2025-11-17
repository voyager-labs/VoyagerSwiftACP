import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum ThumbnailGeneratorUtils {
    static func canGenerateThumbnail(for item: FSItem) -> Bool {
        guard !item.isDirectory else { return false }

        guard let utType = UTType(filenameExtension: item.fileExtension) else {
            return false
        }

        return utType.conforms(to: .image) ||
            utType.conforms(to: .pdf) ||
            utType.conforms(to: .movie) ||
            utType.conforms(to: .video)
    }

    static func generateThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat = 2.0
    ) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return representation?.nsImage
    }

    static func prefetchThumbnails(
        for items: [FSItem],
        size: CGSize,
        scale: CGFloat = 2.0
    ) async {
        let thumbnailItems = items.filter { canGenerateThumbnail(for: $0) }

        await withTaskGroup(of: (String, NSImage?).self) { group in
            for item in thumbnailItems {
                if FSItemIconUtils.getThumbnail(for: item.fullPath) != nil {
                    continue
                }

                group.addTask(priority: .background) {
                    let url = URL(fileURLWithPath: item.fullPath)
                    let image = await generateThumbnail(for: url, size: size, scale: scale)
                    return (item.fullPath, image)
                }
            }

            for await (path, image) in group {
                if let image = image {
                    FSItemIconUtils.saveThumbnail(image, for: path)
                }
            }
        }
    }
}
