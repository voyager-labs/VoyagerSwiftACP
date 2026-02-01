import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class SendableImage: @unchecked Sendable {
    let image: NSImage?

    nonisolated init(_ image: NSImage?) {
        self.image = image
    }
}

enum ThumbnailGeneratorUtils {
    static func canGenerateThumbnail(for item: Entry) -> Bool {
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
        scale: CGFloat = 2.0,
    ) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail,
        )

        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return representation?.nsImage
    }

    static func prefetchThumbnails(
        for items: [Entry],
        size: CGSize,
        scale: CGFloat = 2.0,
    ) async {
        let thumbnailItems = items.filter { canGenerateThumbnail(for: $0) }

        await withTaskGroup(of: (String, SendableImage).self) { group in
            for item in thumbnailItems {
                if EntryIconUtils.getThumbnail(for: item.fullPath) != nil {
                    continue
                }

                group.addTask(priority: .background) {
                    let url = URL(fileURLWithPath: item.fullPath)
                    let image = await generateThumbnail(for: url, size: size, scale: scale)
                    let sendableImage = SendableImage(image)
                    return (item.fullPath, sendableImage)
                }
            }

            for await (path, sendableImage) in group {
                if let image = sendableImage.image {
                    EntryIconUtils.saveThumbnail(image, for: path)
                }
            }
        }
    }
}
