import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations

// MARK: - Passthrough Client

/// 모든 operation을 live client에 위임하는 passthrough client.
/// 테스트에서 clipboard/pasteboard 동작을 제어할 때 사용한다.
func makePassthroughFileOpsClient(live: EntryFileOpsClient = .liveValue) -> EntryFileOpsClient {
    EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { url in try await live.moveToTrashAndReturnURL(url) },
        deleteImmediately: { url in try await live.deleteImmediately(url) },
        putBackFromTrash: { trashURL, originalPath in
            try await live.putBackFromTrash(trashURL, originalPath)
        },
        compressItems: { urls in try await live.compressItems(urls) },
        extractCompressedFile: { url in try await live.extractCompressedFile(url) },
        getTags: { url in try await live.getTags(url) },
        setTags: { url, tags in try await live.setTags(url, tags) },
        toggleTag: { url, tag in try await live.toggleTag(url, tag) },
        fileExists: { path in live.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { live.clipboardChangeCount() },
        loadClipboardCutSessionId: { live.loadClipboardCutSessionId() },
        saveClipboardCutSessionId: { sessionID in live.saveClipboardCutSessionId(sessionID) },
        loadClipboardPaths: { live.loadClipboardPaths() },
        postFileSystemChanged: { _ in },
    )
}

// MARK: - Trash Helper

/// trashRoot가 제공되면 FileManager로 직접 trash 폴더에 이동, 아니면 live trash 사용.
/// 이동 후 recorder에 기록한다.
func performTrash(
    sourceURL: URL,
    trashRoot: URL?,
    base: EntryFileOpsClient,
    recorder: FileOpsRecorder,
) async throws -> URL {
    if let trashRoot {
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let trashURL = trashRoot.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: trashURL.path) {
            try FileManager.default.removeItem(at: trashURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: trashURL)
        recorder.recordTrash(path: trashURL)
        return trashURL
    }
    let trashURL = try await base.moveToTrashAndReturnURL(sourceURL)
    recorder.recordTrash(path: trashURL)
    return trashURL
}

// MARK: - Recorded Client

/// 모든 파일 operation을 기록하는 comprehensive EntryFileOpsClient.
/// copy, move, rename, trash, delete, putBack을 recorder에 기록한다.
/// trashRoot를 제공하면 trash 동작이 custom 디렉터리로 라우팅된다.
func makeRecordedFileOpsClient(recorder: FileOpsRecorder, trashRoot: URL? = nil) -> EntryFileOpsClient {
    let base = makePassthroughFileOpsClient(live: EntryFileOpsClient.liveValue)

    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await base.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in
            try await base.pasteFile(sourceURL, destinationURL)
            recorder.recordCopy(source: sourceURL, destination: destinationURL)
        },
        moveFile: { sourceURL, destinationURL in
            try await base.moveFile(sourceURL, destinationURL)
            recorder.recordMove(source: sourceURL, destination: destinationURL)
        },
        renameFile: { sourceURL, destinationURL in
            try await base.renameFile(sourceURL, destinationURL)
            recorder.recordRename(source: sourceURL, destination: destinationURL)
        },
        createAlias: { sourceURL, aliasURL in
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw FileOpError.notFound
            }
            try await base.createAlias(sourceURL, aliasURL)
        },
        moveToTrashAndReturnURL: { sourceURL in
            try await performTrash(sourceURL: sourceURL, trashRoot: trashRoot, base: base, recorder: recorder)
        },
        deleteImmediately: { url in
            try await base.deleteImmediately(url)
            recorder.recordDelete(path: url)
        },
        putBackFromTrash: { trashURL, originalPath in
            try await base.putBackFromTrash(trashURL, originalPath)
            recorder.recordMove(source: trashURL, destination: URL(fileURLWithPath: originalPath))
        },
        compressItems: { urls in try await base.compressItems(urls) },
        extractCompressedFile: { url in try await base.extractCompressedFile(url) },
        getTags: { url in try await base.getTags(url) },
        setTags: { url, tags in try await base.setTags(url, tags) },
        toggleTag: { url, tag in try await base.toggleTag(url, tag) },
        fileExists: { path in base.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { base.clipboardChangeCount() },
        loadClipboardCutSessionId: { base.loadClipboardCutSessionId() },
        saveClipboardCutSessionId: { sessionID in base.saveClipboardCutSessionId(sessionID) },
        loadClipboardPaths: { base.loadClipboardPaths() },
        postFileSystemChanged: { _ in },
    )
}
