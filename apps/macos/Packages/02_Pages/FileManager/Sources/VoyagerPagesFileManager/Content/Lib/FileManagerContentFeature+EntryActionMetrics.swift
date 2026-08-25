import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared

extension FileManagerContentFeature {
    private struct EntryActionPayload {
        let actionKind: DAUEntryActionKind
        let entryKind: DAUEntryKind
    }

    static func logEntryActionMetricIfNeeded(for action: EntryOperationsAction, metricsClient: MetricsClient) {
        _ = action
        _ = metricsClient
    }

    private static func dauEntryActionPayload(for action: EntryOperationsAction) -> EntryActionPayload? {
        payloadForOpenActions(action)
            ?? payloadForOpenWithActions(action)
            ?? payloadForCreateActions(action)
            ?? payloadForTrashActions(action)
            ?? payloadForArchiveActions(action)
            ?? payloadForTagActions(action)
    }

    private static func payloadForOpenActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        guard case let .open(openAction) = action else {
            return nil
        }
        return payloadForOpenAction(openAction)
    }

    private static func payloadForOpenWithActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
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

    private static func payloadForCreateActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        payloadForEditCreateActions(action) ?? payloadForClipboardCreateActions(action)
    }

    private static func payloadForTrashActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
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

    private static func payloadForArchiveActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
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

    private static func payloadForTagActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case let .tagging(.requestTagMutation(request: request)):
            guard let entryKind = entryKind(for: request.paths) else { return nil }
            return EntryActionPayload(actionKind: .setTags, entryKind: entryKind)

        default:
            return nil
        }
    }

    private static func entryKind(for entries: [EntryModel]) -> DAUEntryKind? {
        guard !entries.isEmpty else { return nil }
        let kinds = Set(entries.map(entryKind(for:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private static func entryKind(for entry: EntryModel) -> DAUEntryKind {
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return .collection
        }
        return entry.isFolder ? .directory : .file
    }

    private static func entryKind(for paths: [String]) -> DAUEntryKind? {
        guard !paths.isEmpty else { return nil }
        let kinds = Set(paths.map(entryKind(forPath:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private static func entryKind(forPath path: String) -> DAUEntryKind {
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if pathExtension == CollectionConstants.fileExtension {
            return .collection
        }
        return .file
    }

    private static func dauActionKind(for operationKind: OperationKind) -> DAUEntryActionKind? {
        guard operationKind.isUndoable else { return nil }
        return dauActionKindMap[operationKind]
    }

    private static func payloadForOpenAction(_ action: EntryOperationsAction.Open) -> EntryActionPayload? {
        guard let (actionKind, paths) = openMetricInputs(for: action) else {
            return nil
        }
        return payload(actionKind: actionKind, paths: paths)
    }

    private static func payloadForEditCreateActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case .edit(.createNewFolder):
            return EntryActionPayload(actionKind: .createFolder, entryKind: .directory)
        case let .edit(.createAliases(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .createAlias, entryKind: entryKind)
        case let .edit(.renameItem(oldPath: oldPath, newPath: _)):
            guard let entryKind = entryKind(for: [oldPath]) else { return nil }
            return EntryActionPayload(actionKind: .rename, entryKind: entryKind)
        default:
            return nil
        }
    }

    private static func payloadForClipboardCreateActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
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
        default:
            return nil
        }
    }

    private static func openMetricInputs(for action: EntryOperationsAction.Open) -> (DAUEntryActionKind, [String])? {
        switch action {
        case let .openFiles(paths):
            (.openDefault, paths)
        case let .quickLookFiles(paths):
            (.quickLook, paths)
        case let .openFinderInfo(paths):
            (.getInfo, paths)
        case let .shareItems(paths, _):
            (.share, paths)
        case let .performService(paths, _):
            (.performService, paths)
        case let .revealInFinder(paths):
            (.revealInFinder, paths)
        }
    }

    private static func payload(
        actionKind: DAUEntryActionKind,
        paths: [String],
    ) -> EntryActionPayload? {
        guard let entryKind = entryKind(for: paths) else { return nil }
        return EntryActionPayload(actionKind: actionKind, entryKind: entryKind)
    }

    private static let dauActionKindMap: [OperationKind: DAUEntryActionKind] = [
        .rename: .rename,
        .pasteFileMove: .move,
        .pasteFileDuplicate: .duplicate,
        .pasteFileCopy: .paste,
        .createFolder: .createFolder,
        .createAlias: .createAlias,
        .moveToTrash: .moveToTrash,
        .putBack: .putBack,
        .setTags: .setTags,
    ]
}
