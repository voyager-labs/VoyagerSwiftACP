import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerShared

public struct CollectionSavePanelClient: Sendable {
    public var presentSavePanel: @Sendable (_ initialDirectory: URL?) async -> URL?
    public var defaultSaveDirectory: @Sendable (_ preferredScopes: [String]) async -> URL?

    public init(
        presentSavePanel: @escaping @Sendable (_ initialDirectory: URL?) async -> URL?,
        defaultSaveDirectory: @escaping @Sendable (_ preferredScopes: [String]) async -> URL?
    ) {
        self.presentSavePanel = presentSavePanel
        self.defaultSaveDirectory = defaultSaveDirectory
    }
}

extension CollectionSavePanelClient: DependencyKey {
    public nonisolated static var liveValue: CollectionSavePanelClient {
        CollectionSavePanelClient(
            presentSavePanel: { initialDirectory in
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.title = "Save Collection"
                    panel.prompt = "Save"
                    panel.canCreateDirectories = true
                    panel.allowsOtherFileTypes = false
                    panel.allowedContentTypes = [
                        UTType("fm.voyager.collection")
                            ?? UTType(filenameExtension: CollectionConstants.fileExtension)
                            ?? .data,
                    ]
                    panel.isExtensionHidden = false
                    panel.nameFieldStringValue = ""
                    panel.directoryURL = initialDirectory

                    let response = panel.runModal()
                    guard response == .OK else { return nil }

                    guard let url = panel.url else { return nil }
                    return ensureCollectionFileExtension(url)
                }
            },
            defaultSaveDirectory: { preferredScopes in
                await MainActor.run {
                    let userDefaultsClient = UserDefaultsClient.liveValue
                    let fileManager = FileManager.default

                    if preferredScopes.count == 1,
                       let scope = preferredScopes.first,
                       let url = validDirectoryURL(scope, fileManager: fileManager)
                    {
                        return url
                    }

                    if let saved = userDefaultsClient.string(CollectionKeys.lastCollectionSaveDirectory),
                       let url = validDirectoryURL(saved, fileManager: fileManager)
                    {
                        return url
                    }

                    return URL(fileURLWithPath: NSHomeDirectory())
                }
            }
        )
    }

    public nonisolated(unsafe) static var testValue: CollectionSavePanelClient {
        CollectionSavePanelClient(
            presentSavePanel: { _ in nil },
            defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") }
        )
    }

    public nonisolated static var previewValue: CollectionSavePanelClient {
        CollectionSavePanelClient(
            presentSavePanel: { _ in nil },
            defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") }
        )
    }
}

public extension DependencyValues {
    nonisolated var collectionSavePanelClient: CollectionSavePanelClient {
        get { self[CollectionSavePanelClient.self] }
        set { self[CollectionSavePanelClient.self] = newValue }
    }
}

// MARK: - Private Helpers

private func validDirectoryURL(_ path: String, fileManager: FileManager) -> URL? {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return nil
    }
    return URL(fileURLWithPath: path)
}

private func ensureCollectionFileExtension(_ url: URL) -> URL {
    if url.pathExtension.lowercased() == CollectionConstants.fileExtension {
        return url
    }
    return url.deletingPathExtension().appendingPathExtension(CollectionConstants.fileExtension)
}
