import AppKit
import ComposableArchitecture
import Foundation

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
                    guard let firstFilePath = paths.first else { return }
                    let isTrash = await MainActor.run {
                        guard let trashPath = entryOpenClient.trashDirectoryPath(), !trashPath.isEmpty else {
                            return false
                        }
                        return firstFilePath.starts(with: trashPath + "/")
                    }

                    if isTrash {
                        for (index, path) in paths.enumerated() {
                            let hasMoreFiles = index < paths.count - 1
                            _ = await alertClient.showTrashFileAlert(
                                URL(fileURLWithPath: path).lastPathComponent,
                                hasMoreFiles,
                            )
                        }
                        return
                    }

                    var groupedPaths: [String: [String]] = [:]
                    for path in paths {
                        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                        groupedPaths[ext, default: []].append(path)
                    }

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
                                    await send(.lifecycle(.operationFinished(
                                        filePath,
                                        .openDefault,
                                        .failure(error.fileOpError),
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
                            for filePath in groupPaths {
                                await send(.lifecycle(.operationFinished(
                                    filePath,
                                    .openDefault,
                                    .failure(error.fileOpError),
                                )))
                            }
                        }
                    }
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

            default:
                return .none
            }
        }
    }
}
