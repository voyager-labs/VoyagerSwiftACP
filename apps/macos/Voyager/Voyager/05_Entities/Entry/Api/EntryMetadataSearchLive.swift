import Foundation

private final class MetadataQueryCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var hasCompleted = false

    nonisolated func setCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasCompleted {
            return false
        }
        hasCompleted = true
        return true
    }
}

private final class MetadataQueryWrapper: @unchecked Sendable {
    nonisolated(unsafe) let query: NSMetadataQuery

    init(_ query: NSMetadataQuery) {
        self.query = query
    }
}

private final class MetadataObserverWrapper: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(_ observer: NSObjectProtocol?) {
        self.observer = observer
    }

    nonisolated func setObserver(_ observer: NSObjectProtocol?) {
        lock.lock()
        defer { lock.unlock() }
        if let oldObserver = self.observer {
            NotificationCenter.default.removeObserver(oldObserver)
        }
        self.observer = observer
    }

    nonisolated func remove() {
        lock.lock()
        defer { lock.unlock() }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}

enum EntryMetadataSearchLive {
    nonisolated static func loadRecentItems(
        showHidden: Bool,
        workspaceClient: WorkspaceClient,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
    ) async -> [EntryModel] {
        let entryLoadingClient = EntryLoadingClient.liveValue
        let predicate = NSPredicate(format: "kMDItemLastUsedDate > %@", Date.distantPast as NSDate)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let recentFiles = await searchFiles(
            predicate: predicate,
            fileExistsAtPath: fileExistsAtPath,
            sortDescriptors: sortDescriptors,
            filterFiles: true,
        )

        let items = recentFiles.compactMap { url in
            EntryModelConverterLive.convertURLToEntry(
                url,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            )
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    nonisolated static func loadFilesWithTag(
        tag: String,
        showHidden: Bool,
        workspaceClient: WorkspaceClient,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
    ) async -> [EntryModel] {
        let entryLoadingClient = EntryLoadingClient.liveValue
        let predicate = NSPredicate(format: "kMDItemUserTags CONTAINS %@", tag)
        let sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]

        let taggedFiles = await searchFiles(
            predicate: predicate,
            fileExistsAtPath: fileExistsAtPath,
            sortDescriptors: sortDescriptors,
        )

        let items: [EntryModel] = taggedFiles.compactMap { url in
            guard let item = EntryModelConverterLive.convertURLToEntry(
                url,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            ) else {
                return nil
            }

            let hasTags = item.tags?.contains(where: { $0.name == tag }) ?? false
            return hasTags ? item : nil
        }
        return showHidden ? items : items.filter { !$0.isHidden }
    }

    @MainActor
    private static func searchFiles(
        predicate: NSPredicate,
        fileExistsAtPath: @escaping @Sendable (String, UnsafeMutablePointer<ObjCBool>?) -> Bool,
        sortDescriptors: [NSSortDescriptor] = [],
        timeout: TimeInterval = 5,
        filterFiles: Bool = false,
    ) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = []
                query.predicate = predicate
                query.sortDescriptors = sortDescriptors

                let completionState = MetadataQueryCompletionState()
                let queryWrapper = MetadataQueryWrapper(query)
                let observerWrapper = MetadataObserverWrapper(nil)

                let observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: queryWrapper.query,
                    queue: .main,
                ) { _ in
                    let capturedQuery = queryWrapper.query
                    Task { @MainActor in
                        guard completionState.setCompleted() else { return }
                        capturedQuery.stop()

                        let urls: [URL] = Array(capturedQuery.results
                            .compactMap { $0 as? NSMetadataItem }
                            .compactMap { item -> URL? in
                                guard let path = item.value(forAttribute: "kMDItemPath") as? String
                                else { return nil }

                                if filterFiles {
                                    var isDirectory: ObjCBool = false
                                    if fileExistsAtPath(path, &isDirectory), isDirectory.boolValue {
                                        return nil
                                    }
                                }

                                return URL(fileURLWithPath: path)
                            }
                            .prefix(100))

                        continuation.resume(returning: urls)
                        observerWrapper.remove()
                    }
                }

                observerWrapper.setObserver(observer)
                query.start()

                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    let capturedQuery = queryWrapper.query
                    Task { @MainActor in
                        guard completionState.setCompleted() else { return }
                        capturedQuery.stop()
                        continuation.resume(returning: [])
                        observerWrapper.remove()
                    }
                }
            }
        }
    }
}
