import AppKit
import Foundation
import UniformTypeIdentifiers

func resolveEntryDroppedPaths(from providers: [NSItemProvider]) async -> [String] {
    var paths: [String] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        if let path = await resolveEntryDroppedPath(from: provider) {
            paths.append(path)
        }
    }
    return paths
}

private func resolveEntryDroppedPath(from provider: NSItemProvider) async -> String? {
    await withCheckedContinuation { continuation in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                continuation.resume(returning: url.path)
                return
            }

            if let data = item as? Data {
                if let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString)
                {
                    continuation.resume(returning: url.path)
                    return
                }

                if let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url.path)
                    return
                }

                continuation.resume(returning: nil)
                return
            }

            if let urlString = item as? String,
               let url = URL(string: urlString)
            {
                continuation.resume(returning: url.path)
                return
            }

            continuation.resume(returning: nil)
        }
    }
}
