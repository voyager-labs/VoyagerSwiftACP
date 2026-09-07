import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

@Reducer
struct EntryOpenOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.entryQuickLookClient)
    var entryQuickLookClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.workspaceClient)
    var workspaceClient

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .open(.openFiles(paths)):
                guard !paths.isEmpty else {
                    return .none
                }

                let entryOpenClient = entryOpenClient
                let workspaceClient = workspaceClient
                return .run { [entryOpenClient, workspaceClient] (send: Send<Action>) in
                    let rejectedPaths: [String] = await MainActor.run {
                        guard let trashPath = entryOpenClient.trashDirectoryPath(), !trashPath.isEmpty else {
                            return []
                        }
                        return paths.filter { $0.starts(with: trashPath + "/") }
                    }

                    if !rejectedPaths.isEmpty {
                        for (index, path) in rejectedPaths.enumerated() {
                            let hasMoreFiles = index < rejectedPaths.count - 1
                            _ = await alertClient.showTrashFileAlert(
                                URL(fileURLWithPath: path).lastPathComponent,
                                hasMoreFiles,
                            )
                        }
                        await send(.lifecycle(.entryActionCompleted(EntryActionRecord(
                            operationKind: .openDefault,
                            targets: [],
                            failedCount: 0,
                            cancelledCount: paths.count,
                            succeededCount: 0,
                            id: UUID(),
                            timestamp: Date(),
                        ))))
                        return
                    }

                    var groupedPaths: [String: [String]] = [:]
                    for path in paths {
                        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                        groupedPaths[ext, default: []].append(path)
                    }

                    var failedCount = 0
                    var cancelledCount = 0
                    for (_, groupPaths) in groupedPaths {
                        let urls = groupPaths.map { URL(fileURLWithPath: $0) }
                        guard let firstURL = urls.first else { continue }

                        let appURL = workspaceClient.urlForApplicationToOpen(firstURL)
                        guard let appURL else {
                            for filePath in groupPaths {
                                let url = URL(fileURLWithPath: filePath)
                                await send(.lifecycle(.operationStarted(filePath, .openDefault)))
                                do {
                                    try await entryOpenClient.open(url, .defaultApp)
                                    await send(.lifecycle(.operationFinished(filePath, .openDefault, .success(()))))
                                } catch {
                                    let failure = error.fileOpError
                                    if failure == .cancelled {
                                        cancelledCount += 1
                                    } else {
                                        failedCount += 1
                                    }
                                    await send(.lifecycle(.operationFinished(
                                        filePath,
                                        .openDefault,
                                        .failure(failure),
                                    )))
                                }
                            }
                            continue
                        }

                        for filePath in groupPaths {
                            await send(.lifecycle(.operationStarted(filePath, .openDefault)))
                        }

                        do {
                            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
                            defer {
                                for (url, isScoped) in zip(urls, scoped) where isScoped {
                                    url.stopAccessingSecurityScopedResource()
                                }
                            }
                            try await workspaceClient.openURLsWithApplication(urls, appURL, false, nil)
                            for filePath in groupPaths {
                                await send(
                                    .lifecycle(.operationFinished(filePath, .openDefault, .success(()))),
                                )
                            }
                        } catch {
                            let failure = error.fileOpError
                            if failure == .cancelled {
                                cancelledCount += groupPaths.count
                            } else {
                                failedCount += groupPaths.count
                            }
                            for filePath in groupPaths {
                                await send(.lifecycle(.operationFinished(
                                    filePath,
                                    .openDefault,
                                    .failure(failure),
                                )))
                            }
                        }
                    }

                    await send(.lifecycle(.entryActionCompleted(
                        EntryActionRecord(
                            operationKind: .openDefault,
                            targets: [],
                            failedCount: failedCount,
                            cancelledCount: cancelledCount,
                            succeededCount: paths.count - failedCount - cancelledCount,
                            id: UUID(),
                            timestamp: Date(),
                        ),
                    )))
                }

            case let .open(.quickLookFiles(paths)):
                guard !paths.isEmpty else { return .none }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                guard let keyPath = paths.first else { return .none }
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .quickLook) {
                    try await entryQuickLookClient.quickLook(urls, 0)
                }

            case let .open(.openFinderInfo(paths)):
                guard !paths.isEmpty else { return .none }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                guard let keyPath = paths.first else { return .none }
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .getInfo) {
                    try await entryOpenClient.openFinderInfo(urls)
                }

            case let .open(.shareItems(paths, anchor)):
                guard !paths.isEmpty else { return .none }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                guard let keyPath = paths.first else { return .none }
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .share) {
                    try await entryOpenClient.shareItems(urls, anchor)
                }

            case let .open(.performService(paths, name)):
                guard !paths.isEmpty else { return .none }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                guard let keyPath = paths.first else { return .none }
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .performService(name)) {
                    try await entryOpenClient.performService(name, urls)
                }

            case let .open(.revealInFinder(paths)):
                guard !paths.isEmpty else { return .none }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                guard let keyPath = paths.first else { return .none }
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .revealInFinder) {
                    try await entryOpenClient.revealInFinder(urls)
                }

            case let .open(.syncQuickLookSelection(paths, selectedIndex)):
                guard !paths.isEmpty else { return .none }
                let urls = paths.map { URL(fileURLWithPath: $0) }
                let entryQuickLookClient = entryQuickLookClient
                return .run { _ in
                    await entryQuickLookClient.syncQuickLookSelection(urls, selectedIndex)
                }

            default:
                return .none
            }
        }
    }
}
