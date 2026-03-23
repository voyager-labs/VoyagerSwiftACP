import ComposableArchitecture
import Foundation

@Reducer
struct EntryOperationsMetricsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    private struct EntryActionPayload {
        let actionKind: DAUEntryActionKind
        let entryKind: DAUEntryKind
    }

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard let payload = dauEntryActionPayload(for: action) else {
                return .none
            }

            VoyagerSentryMetricLogger.logDAUEntryAction(
                actionKind: payload.actionKind,
                entryKind: payload.entryKind,
            )
            return .none
        }
    }

    private func dauEntryActionPayload(for action: Action) -> EntryActionPayload? {
        payloadForOpenActions(action)
            ?? payloadForAppActions(action)
            ?? payloadForCreateActions(action)
            ?? payloadForTrashActions(action)
            ?? payloadForArchiveActions(action)
            ?? payloadForTagActions(action)
    }

    private func payloadForOpenActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .open(.openFiles(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .openDefault, entryKind: entryKind)

        case let .open(.quickLookFiles(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .quickLook, entryKind: entryKind)

        case let .open(.openFinderInfo(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .getInfo, entryKind: entryKind)

        case let .open(.shareItems(paths, anchor: _)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .share, entryKind: entryKind)

        case let .open(.performService(paths, name: _)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .performService, entryKind: entryKind)

        case let .open(.revealInFinder(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .revealInFinder, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForAppActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .openWith(.openFileWithApp(file)):
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind(for: file))

        case let .openWith(.openFileWithAppBundleID(filePath, bundleID: _, url: _)):
            guard let entryKind = entryKind(for: [filePath]) else { return nil }
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind)

        case let .openWith(.setDefaultAppForFile(type: _, bundleID: _, file: file)):
            return EntryActionPayload(actionKind: .setDefaultApp, entryKind: entryKind(for: file))

        case let .openWith(.setDefaultAppWithOther(file)):
            return EntryActionPayload(actionKind: .setDefaultApp, entryKind: entryKind(for: file))

        case let .openWith(.openFilesWithAppFromOther(files, shouldSetAsDefault: _)):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForCreateActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case .edit(.createNewFolder(name: _, parentPath: _)):
            return EntryActionPayload(actionKind: .createFolder, entryKind: .directory)

        case let .edit(.createAliases(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .createAlias, entryKind: entryKind)

        case let .clipboard(.copySelectedItems(files)):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .copy, entryKind: entryKind)

        case let .clipboard(.pasteItems(
            sourcePaths: sourcePaths,
            destinationPath: _,
            operation: _,
            operationKind: operationKind,
        )):
            guard let entryKind = entryKind(for: sourcePaths) else { return nil }
            guard let actionKind = dauActionKind(for: operationKind) else { return nil }
            return EntryActionPayload(actionKind: actionKind, entryKind: entryKind)

        case let .edit(.renameItem(oldPath: oldPath, newPath: _)):
            guard let entryKind = entryKind(for: [oldPath]) else { return nil }
            return EntryActionPayload(actionKind: .rename, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForTrashActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .trash(.moveToTrash(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .moveToTrash, entryKind: entryKind)

        case let .trash(.deleteImmediatelyConfirmed(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .deleteImmediately, entryKind: entryKind)

        case let .trash(.putBackFromTrash(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .putBack, entryKind: entryKind)

        case let .trash(.emptyTrashConfirmed(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .emptyTrash, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForArchiveActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .archive(.compressItems(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .compress, entryKind: entryKind)

        case let .archive(.extractCompressedFile(path)):
            return EntryActionPayload(actionKind: .extract, entryKind: entryKind(forPath: path))

        default:
            return nil
        }
    }

    private func payloadForTagActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .tagging(.requestTagMutation(request: request)):
            guard let entryKind = entryKind(for: request.paths) else { return nil }
            return EntryActionPayload(actionKind: .setTags, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func entryKind(for entries: [EntryModel]) -> DAUEntryKind? {
        guard !entries.isEmpty else { return nil }
        let kinds = Set(entries.map(entryKind(for:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private func entryKind(for entry: EntryModel) -> DAUEntryKind {
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return .collection
        }
        return entry.isFolder ? .directory : .file
    }

    private func entryKind(for paths: [String]) -> DAUEntryKind? {
        guard !paths.isEmpty else { return nil }
        let kinds = Set(paths.map(entryKind(forPath:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private func entryKind(forPath path: String) -> DAUEntryKind {
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if pathExtension == CollectionConstants.fileExtension {
            return .collection
        }
        return .file
    }

    private func dauActionKind(for operationKind: OperationKind) -> DAUEntryActionKind? {
        guard operationKind.isUndoable else { return nil }

        switch operationKind {
        case .rename:
            return .rename
        case .pasteFileMove:
            return .move
        case .pasteFileDuplicate:
            return .duplicate
        case .pasteFileCopy:
            return .paste
        case .createFolder:
            return .createFolder
        case .createAlias:
            return .createAlias
        case .moveToTrash:
            return .moveToTrash
        case .putBack:
            return .putBack
        case .setTags:
            return .setTags
        case .openDefault,
             .openWithApp,
             .setDefaultApp,
             .quickLook,
             .getInfo,
             .share,
             .performService,
             .revealInFinder,
             .deleteImmediately,
             .compress,
             .extract:
            return nil
        }
    }
}
