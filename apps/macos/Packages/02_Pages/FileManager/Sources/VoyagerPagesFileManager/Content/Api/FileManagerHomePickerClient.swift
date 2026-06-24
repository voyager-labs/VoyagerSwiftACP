import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

public struct FileManagerHomePickerClient: Sendable {
    public var pickDirectory: @Sendable () async -> FileManagerHomePickerResult<String>
    public var pickCollectionFile: @Sendable () async -> FileManagerHomePickerResult<URL>

    public init(
        pickDirectory: @escaping @Sendable () async -> FileManagerHomePickerResult<String>,
        pickCollectionFile: @escaping @Sendable () async -> FileManagerHomePickerResult<URL>,
    ) {
        self.pickDirectory = pickDirectory
        self.pickCollectionFile = pickCollectionFile
    }
}

extension FileManagerHomePickerClient: DependencyKey {
    nonisolated public static var liveValue: FileManagerHomePickerClient {
        FileManagerHomePickerClient(
            pickDirectory: {
                await MainActor.run {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.title = "Select Home Directory"

                    let response = panel.runModal()
                    if response == .OK, let url = panel.url {
                        return .selected(url.path)
                    }
                    return .cancelled
                }
            },
            pickCollectionFile: {
                await MainActor.run {
                    let panel = NSOpenPanel()
                    let delegate = CollectionOpenPanelDelegate()
                    panel.delegate = delegate
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.treatsFilePackagesAsDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    if let voycollType = UTType(filenameExtension: "voycoll") {
                        panel.allowedContentTypes = [voycollType]
                    }
                    panel.title = "Select Collection File"

                    let response = panel.runModal()
                    if response == .OK, let url = panel.url {
                        guard url.pathExtension.lowercased() == "voycoll" else {
                            return .failed("invalid_collection_file")
                        }
                        return .selected(url)
                    }
                    return .cancelled
                }
            },
        )
    }

    nonisolated public static var testValue: FileManagerHomePickerClient {
        FileManagerHomePickerClient(
            pickDirectory: { .cancelled },
            pickCollectionFile: { .cancelled },
        )
    }
}

public extension DependencyValues {
    var homePickerClient: FileManagerHomePickerClient {
        get { self[FileManagerHomePickerClient.self] }
        set { self[FileManagerHomePickerClient.self] = newValue }
    }
}

private final class CollectionOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_: Any, shouldEnable url: URL) -> Bool {
        if url.pathExtension.lowercased() == "voycoll" {
            return true
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }
}
