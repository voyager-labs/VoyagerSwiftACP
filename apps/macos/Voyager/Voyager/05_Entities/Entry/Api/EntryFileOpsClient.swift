import ComposableArchitecture
import Foundation

public struct EntryFileOpsClient: Sendable {
    public var createFolder: @Sendable (URL, String) async throws -> Void
    public var pasteFile: @Sendable (URL, URL) async throws -> Void
    public var moveFile: @Sendable (URL, URL) async throws -> Void
    public var renameFile: @Sendable (URL, URL) async throws -> Void
    public var createAlias: @Sendable (URL, URL) async throws -> Void
    public var moveToTrashAndReturnURL: @Sendable (URL) async throws -> URL
    public var deleteImmediately: @Sendable (URL) async throws -> Void
    public var putBackFromTrash: @Sendable (URL, String) async throws -> Void
    public var compressItems: @Sendable ([URL]) async throws -> URL
    public var extractCompressedFile: @Sendable (URL) async throws -> Void
    public var getTags: @Sendable (URL) async throws -> [String]
    public var setTags: @Sendable (URL, [String]) async throws -> Void
    public var toggleTag: @Sendable (URL, String) async throws -> Void
    public var fileExists: @Sendable (String) -> Bool
    public var saveDragPaths: @Sendable ([String]) -> Void
    public var loadDragPaths: @Sendable () -> [String]
    public var saveDragWithOption: @Sendable (Bool) -> Void
    public var loadDragWithOption: @Sendable () -> Bool
    public var loadClipboardPaths: @Sendable () -> ([String], ClipboardOperation)
    public var postFileSystemChanged: @Sendable ([String]) -> Void

    public nonisolated init(
        createFolder: @escaping @Sendable (URL, String) async throws -> Void,
        pasteFile: @escaping @Sendable (URL, URL) async throws -> Void,
        moveFile: @escaping @Sendable (URL, URL) async throws -> Void,
        renameFile: @escaping @Sendable (URL, URL) async throws -> Void,
        createAlias: @escaping @Sendable (URL, URL) async throws -> Void,
        moveToTrashAndReturnURL: @escaping @Sendable (URL) async throws -> URL,
        deleteImmediately: @escaping @Sendable (URL) async throws -> Void,
        putBackFromTrash: @escaping @Sendable (URL, String) async throws -> Void,
        compressItems: @escaping @Sendable ([URL]) async throws -> URL,
        extractCompressedFile: @escaping @Sendable (URL) async throws -> Void,
        getTags: @escaping @Sendable (URL) async throws -> [String],
        setTags: @escaping @Sendable (URL, [String]) async throws -> Void,
        toggleTag: @escaping @Sendable (URL, String) async throws -> Void,
        fileExists: @escaping @Sendable (String) -> Bool,
        saveDragPaths: @escaping @Sendable ([String]) -> Void,
        loadDragPaths: @escaping @Sendable () -> [String],
        saveDragWithOption: @escaping @Sendable (Bool) -> Void,
        loadDragWithOption: @escaping @Sendable () -> Bool,
        loadClipboardPaths: @escaping @Sendable () -> ([String], ClipboardOperation),
        postFileSystemChanged: @escaping @Sendable ([String]) -> Void,
    ) {
        self.createFolder = createFolder
        self.pasteFile = pasteFile
        self.moveFile = moveFile
        self.renameFile = renameFile
        self.createAlias = createAlias
        self.moveToTrashAndReturnURL = moveToTrashAndReturnURL
        self.deleteImmediately = deleteImmediately
        self.putBackFromTrash = putBackFromTrash
        self.compressItems = compressItems
        self.extractCompressedFile = extractCompressedFile
        self.getTags = getTags
        self.setTags = setTags
        self.toggleTag = toggleTag
        self.fileExists = fileExists
        self.saveDragPaths = saveDragPaths
        self.loadDragPaths = loadDragPaths
        self.saveDragWithOption = saveDragWithOption
        self.loadDragWithOption = loadDragWithOption
        self.loadClipboardPaths = loadClipboardPaths
        self.postFileSystemChanged = postFileSystemChanged
    }
}

extension EntryFileOpsClient: DependencyKey {
    public nonisolated static var liveValue: EntryFileOpsClient {
        EntryFileOpsClient(
            createFolder: EntrySystemPrimitives.liveCreateFolder,
            pasteFile: EntrySystemPrimitives.livePasteFile,
            moveFile: EntrySystemPrimitives.liveMoveFile,
            renameFile: EntrySystemPrimitives.liveRenameFile,
            createAlias: EntrySystemPrimitives.liveCreateAlias,
            moveToTrashAndReturnURL: EntrySystemPrimitives.liveMoveToTrashAndReturnURL,
            deleteImmediately: EntrySystemPrimitives.liveDeleteImmediately,
            putBackFromTrash: EntrySystemPrimitives.livePutBackFromTrash,
            compressItems: EntrySystemPrimitives.liveCompressItems,
            extractCompressedFile: EntrySystemPrimitives.liveExtractCompressedFile,
            getTags: EntrySystemPrimitives.liveGetTags,
            setTags: EntrySystemPrimitives.liveSetTags,
            toggleTag: EntrySystemPrimitives.liveToggleTag,
            fileExists: EntrySystemPrimitives.liveFileExists,
            saveDragPaths: EntrySystemPrimitives.liveSaveDragPaths,
            loadDragPaths: EntrySystemPrimitives.liveLoadDragPaths,
            saveDragWithOption: EntrySystemPrimitives.liveSaveDragWithOption,
            loadDragWithOption: EntrySystemPrimitives.liveLoadDragWithOption,
            loadClipboardPaths: EntrySystemPrimitives.liveLoadClipboardPaths,
            postFileSystemChanged: EntrySystemPrimitives.livePostFileSystemChanged,
        )
    }

    public nonisolated static var testValue: EntryFileOpsClient {
        let unimplemented = { @Sendable (_: Any...) -> Never in
            fatalError("EntryFileOpsClient test dependency not set.")
        }
        return EntryFileOpsClient(
            createFolder: { _, _ in unimplemented() },
            pasteFile: { _, _ in unimplemented() },
            moveFile: { _, _ in unimplemented() },
            renameFile: { _, _ in unimplemented() },
            createAlias: { _, _ in unimplemented() },
            moveToTrashAndReturnURL: { _ in unimplemented() },
            deleteImmediately: { _ in unimplemented() },
            putBackFromTrash: { _, _ in unimplemented() },
            compressItems: { _ in unimplemented() },
            extractCompressedFile: { _ in unimplemented() },
            getTags: { _ in unimplemented() },
            setTags: { _, _ in unimplemented() },
            toggleTag: { _, _ in unimplemented() },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
        )
    }

    public nonisolated static var previewValue: EntryFileOpsClient {
        EntryFileOpsClient(
            createFolder: { _, _ in },
            pasteFile: { _, _ in },
            moveFile: { _, _ in },
            renameFile: { _, _ in },
            createAlias: { _, _ in },
            moveToTrashAndReturnURL: { _ in URL(fileURLWithPath: "/tmp/.Trash/test") },
            deleteImmediately: { _ in },
            putBackFromTrash: { _, _ in },
            compressItems: { _ in URL(fileURLWithPath: "/tmp/Archive.zip") },
            extractCompressedFile: { _ in },
            getTags: { _ in [] },
            setTags: { _, _ in },
            toggleTag: { _, _ in },
            fileExists: { _ in false },
            saveDragPaths: { _ in },
            loadDragPaths: { [] },
            saveDragWithOption: { _ in },
            loadDragWithOption: { false },
            loadClipboardPaths: { ([], .copy) },
            postFileSystemChanged: { _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var entryFileOpsClient: EntryFileOpsClient {
        get { self[EntryFileOpsClient.self] }
        set { self[EntryFileOpsClient.self] = newValue }
    }
}
