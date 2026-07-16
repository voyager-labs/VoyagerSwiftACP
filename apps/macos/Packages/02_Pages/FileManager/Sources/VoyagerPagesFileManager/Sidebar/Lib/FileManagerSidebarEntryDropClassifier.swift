import AppKit
import UniformTypeIdentifiers

enum FileManagerSidebarEntryDropClassifier {
    static func accepts(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.allSatisfy { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
    }
}
