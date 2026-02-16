// swiftlint:disable cyclomatic_complexity
import ComposableArchitecture
import Foundation

@Reducer
struct EntryOperationsMetricsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

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

    private struct EntryActionPayload {
        let actionKind: DAUEntryActionKind
        let entryKind: DAUEntryKind
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
        case let .openFiles(files):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .openDefault, entryKind: entryKind)

        case let .quickLookFile(file):
            return EntryActionPayload(actionKind: .quickLook, entryKind: entryKind(for: file))

        case let .quickLookFiles(files):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .quickLook, entryKind: entryKind)

        case let .openFinderInfo(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .getInfo, entryKind: entryKind)

        case let .shareItems(items, _):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .share, entryKind: entryKind)

        case let .performService(items, _):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .performService, entryKind: entryKind)

        case let .revealInFinder(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .revealInFinder, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForAppActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .openFileWithApp(file):
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind(for: file))

        case let .openFileWithAppBundleID(filePath, _, _):
            guard let entryKind = entryKind(for: [filePath]) else { return nil }
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind)

        case let .setDefaultAppForFile(_, _, file):
            return EntryActionPayload(actionKind: .setDefaultApp, entryKind: entryKind(for: file))

        case let .setDefaultAppWithOther(file):
            return EntryActionPayload(actionKind: .setDefaultApp, entryKind: entryKind(for: file))

        case let .openFilesWithAppFromOther(files, _):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForCreateActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case .createNewFolder:
            return EntryActionPayload(actionKind: .createFolder, entryKind: .directory)

        case let .createAliases(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .createAlias, entryKind: entryKind)

        case let .copySelectedItems(files):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .copy, entryKind: entryKind)

        case let .pasteItems(sourcePaths, _, _, actionKind):
            guard let entryKind = entryKind(for: sourcePaths) else { return nil }
            return EntryActionPayload(actionKind: dauActionKind(for: actionKind), entryKind: entryKind)

        case let .renameItem(oldPath, _):
            guard let entryKind = entryKind(for: [oldPath]) else { return nil }
            return EntryActionPayload(actionKind: .rename, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForTrashActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .moveToTrash(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .moveToTrash, entryKind: entryKind)

        case let .deleteImmediatelyConfirmed(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .deleteImmediately, entryKind: entryKind)

        case let .putBackFromTrash(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .putBack, entryKind: entryKind)

        case let .emptyTrashConfirmed(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .emptyTrash, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForArchiveActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .compressItems(items):
            guard let entryKind = entryKind(for: items) else { return nil }
            return EntryActionPayload(actionKind: .compress, entryKind: entryKind)

        case let .extractCompressedFile(file):
            return EntryActionPayload(actionKind: .extract, entryKind: entryKind(for: file))

        default:
            return nil
        }
    }

    private func payloadForTagActions(_ action: Action) -> EntryActionPayload? {
        switch action {
        case let .setTagsForItems(targets):
            guard let entryKind = entryKind(for: targets) else { return nil }
            return EntryActionPayload(actionKind: .setTags, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func entryKind(for entries: [Entry]) -> DAUEntryKind? {
        guard !entries.isEmpty else { return nil }
        let kinds = Set(entries.map(entryKind(for:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private func entryKind(for entry: Entry) -> DAUEntryKind {
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return .collection
        }
        return entry.isDirectory ? .directory : .file
    }

    private func entryKind(for targets: [TagChangeTarget]) -> DAUEntryKind? {
        entryKind(for: targets.map(\.file))
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

    private func dauActionKind(for actionKind: EntryActionRecord.ActionKind) -> DAUEntryActionKind {
        switch actionKind {
        case .rename:
            .rename
        case .move:
            .move
        case .duplicate:
            .duplicate
        case .paste:
            .paste
        case .createFolder:
            .createFolder
        case .createAlias:
            .createAlias
        case .moveToTrash:
            .moveToTrash
        case .putBack:
            .putBack
        case .setTags:
            .setTags
        }
    }
}

// swiftlint:enable cyclomatic_complexity
