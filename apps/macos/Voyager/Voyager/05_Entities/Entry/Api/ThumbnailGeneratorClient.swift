// TODO(sunset VOY-273): Temporary compatibility adapter — app-layer TCA client.
import AppKit
import ComposableArchitecture
import Foundation
import QuickLookThumbnailing

struct ThumbnailGeneratorClient: Sendable {
    var generateThumbnail: @Sendable (_ url: URL, _ size: CGSize, _ scale: CGFloat) async -> NSImage?

    nonisolated init(
        generateThumbnail: @escaping @Sendable (_ url: URL, _ size: CGSize, _ scale: CGFloat) async -> NSImage?,
    ) {
        self.generateThumbnail = generateThumbnail
    }

    func generateThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat = 2.0,
    ) async -> NSImage? {
        await generateThumbnail(url, size, scale)
    }
}

extension ThumbnailGeneratorClient: DependencyKey {
    nonisolated static var liveValue: ThumbnailGeneratorClient {
        .init(
            generateThumbnail: { url, size, scale in
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: size,
                    scale: scale,
                    representationTypes: .thumbnail,
                )

                let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                return representation?.nsImage
            },
        )
    }

    nonisolated static var testValue: ThumbnailGeneratorClient {
        .init(generateThumbnail: { _, _, _ in nil })
    }

    nonisolated static var previewValue: ThumbnailGeneratorClient { testValue }
}

extension DependencyValues {
    nonisolated var thumbnailGeneratorClient: ThumbnailGeneratorClient {
        get { self[ThumbnailGeneratorClient.self] }
        set { self[ThumbnailGeneratorClient.self] = newValue }
    }
}
