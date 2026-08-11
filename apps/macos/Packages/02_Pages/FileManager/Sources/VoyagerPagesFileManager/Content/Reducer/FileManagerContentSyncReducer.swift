import ComposableArchitecture
import CoreServices
import Foundation
import os
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@Reducer
struct FileManagerContentSyncReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .externalFileSystemChanged(events, deliveryChainToken):
                let paths = events.map(\.path)
                switch state.navigation.navigationState {
                case .collection:
                    let affectsCollection = collectionPathsAffectCurrentContext(paths, state: state)
                    guard affectsCollection else {
                        return .none
                    }
                    logFileManagerReloadRequest(events, deliveryChainToken: deliveryChainToken)
                    return .send(.collection(.externalPathsChanged(paths)))

                case let .folder(path):
                    guard pathsAffectCurrentFolder(paths, currentPath: path) else {
                        return .none
                    }
                    logFileManagerReloadRequest(events, deliveryChainToken: deliveryChainToken)
                    let normalizedPaths = paths.map(normalizedPath(for:))
                    let affectedPaths = hierarchyAffectedPaths(for: normalizedPaths)
                    let removedPrefixes = removedPrefixes(for: events)
                    let hierarchyAction: EntryListHierarchyAction = events
                        .contains(where: requiresCoarseHierarchyReload)
                        ? .coarseHierarchyInvalidated(removedPrefixes: removedPrefixes)
                        : .hierarchyInvalidated(
                            affectedPaths: affectedPaths,
                            removedPrefixes: removedPrefixes,
                        )
                    return .concatenate(
                        .send(.entryViewLayout(.hierarchy(hierarchyAction))),
                        FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state),
                    )

                case .recents, .tags, .computer:
                    logFileManagerReloadRequest(events, deliveryChainToken: deliveryChainToken)
                    return FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(state: state)

                case .home, .aiChat, .aiChatSessions:
                    return .none
                }

            default:
                return .none
            }
        }
    }

    private func logFileManagerReloadRequest(
        _ events: [FileChangeGatewayEvent],
        deliveryChainToken: String?,
    ) {
        guard let deliveryChainToken else { return }
        logFileManagerDeliveryMarker(
            "fs_reload_requested",
            events: events,
            chainToken: deliveryChainToken,
            latencyFrom: events.map(\.emittedAt).min(),
        )
    }

    private func pathsAffectCurrentFolder(_ paths: [String], currentPath: String) -> Bool {
        let normalizedCurrentPath = normalizedPath(for: currentPath)

        return paths.contains { path in
            let candidatePath = normalizedPath(for: path)
            if candidatePath == normalizedCurrentPath {
                return true
            }

            return isSameOrDescendant(path: candidatePath, of: normalizedCurrentPath)
        }
    }

    private func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let ancestorComponents = URL(fileURLWithPath: ancestor).pathComponents
        return pathComponents.starts(with: ancestorComponents)
    }

    private func parentPath(for path: String) -> String {
        URL(fileURLWithPath: normalizedPath(for: path)).deletingLastPathComponent().path
    }

    private func hierarchyAffectedPaths(for normalizedPaths: [String]) -> [String] {
        (normalizedPaths + normalizedPaths.map(parentPath(for:))).reduce(into: []) { paths, path in
            if !paths.contains(path) {
                paths.append(path)
            }
        }
    }

    private func normalizedPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func removedPrefixes(for events: [FileChangeGatewayEvent]) -> [String] {
        Array(Set(events.compactMap { event in
            let removesItem = event.flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
            let renamesItem = event.flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
            guard removesItem || renamesItem else { return nil }
            return normalizedPath(for: event.path)
        })).sorted()
    }

    private func requiresCoarseHierarchyReload(_ event: FileChangeGatewayEvent) -> Bool {
        [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
        ].contains { event.flags & UInt32($0) != 0 }
    }

    private func collectionPathsAffectCurrentContext(_ paths: [String], state: State) -> Bool {
        let relevantPaths = paths.filter {
            !isOpenedCollectionDocumentPath($0, openedURL: state.openedCollectionURL)
        }
        guard !relevantPaths.isEmpty else {
            return false
        }
        guard let context = state.collection.collectionContext else {
            return true
        }
        return collectionChangeIsRelevant(
            changedPaths: relevantPaths,
            scopes: context.scopes,
            excludedScopes: context.excludedScopes,
            includeSubfolders: context.includeSubfolders,
        )
    }

    private func isOpenedCollectionDocumentPath(_ path: String, openedURL: URL?) -> Bool {
        guard let openedURL else {
            return false
        }

        let lexicalPath = URL(fileURLWithPath: path).path
        let lexicalOpenedPath = openedURL.path
        let lexicalPackagePrefix = lexicalOpenedPath == "/" ? "/" : lexicalOpenedPath + "/"
        if lexicalPath == lexicalOpenedPath || lexicalPath.hasPrefix(lexicalPackagePrefix) {
            return true
        }

        let candidatePath = normalizedPath(for: path)
        let normalizedOpenedPath = normalizedPath(for: openedURL.path)
        if candidatePath == normalizedOpenedPath {
            return true
        }

        let packagePrefix = normalizedOpenedPath == "/" ? "/" : normalizedOpenedPath + "/"
        return candidatePath.hasPrefix(packagePrefix)
    }
}

private let fileManagerSyncDeliveryLogger = os.Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "fm.voyager.Voyager",
    category: "FileChangeGateway",
)

private func logFileManagerDeliveryMarker(
    _ marker: String,
    events: [FileChangeGatewayEvent],
    chainToken: String,
    latencyFrom: Date?,
    timestamp: Date = Date(),
) {
    let flags = events.reduce(UInt32(0)) { $0 | $1.flags }
    var message = "voyager.fs.delivery marker=\(marker) ts=\(timestamp.timeIntervalSince1970)"
    message += " eventCount=\(events.count) flagsSummary=\(String(format: "0x%llx", UInt64(flags)))"
    let latencyMs = max(0, timestamp.timeIntervalSince(latencyFrom ?? timestamp) * 1000)
    message += " latencyMs=\(latencyMs) chainToken=\(chainToken)"
    fileManagerSyncDeliveryLogger.info("\(message, privacy: .public)")
}
