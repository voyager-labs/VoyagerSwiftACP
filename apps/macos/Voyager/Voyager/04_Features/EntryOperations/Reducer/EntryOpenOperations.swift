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
            case let .openFiles(paths):
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
                                await send(.operationStarted(filePath, .openDefault))
                                do {
                                    try await entryOpenClient.open(url, .defaultApp)
                                    await send(.operationFinished(filePath, .openDefault, .success(())))
                                } catch {
                                    await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                                }
                            }
                            continue
                        }

                        for filePath in groupPaths {
                            await send(.operationStarted(filePath, .openDefault))
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
                                    .operationFinished(filePath, .openDefault, .success(())),
                                )
                            }
                        } catch {
                            for filePath in groupPaths {
                                await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                            }
                        }
                    }
                }

            case let .quickLookFile(path):
                let filePath = path
                let url = URL(fileURLWithPath: filePath)
                return EntryOperationsExecutionSupport.run(for: filePath, kind: .quickLook) {
                    try await entryQuickLookClient.quickLook([url], 0)
                }

            // TODO: quickLook 액션을 단일 엔트리 포인트로 통합하고 quickLookFiles 분기를 제거한다.

            case let .quickLookFiles(paths):
                let urls = paths.map { URL(fileURLWithPath: $0) }
                let keyPath = paths.first ?? "quicklook"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .quickLook) {
                    try await entryQuickLookClient.quickLook(urls, 0)
                }

            case let .openFinderInfo(paths):
                let urls = paths.map { URL(fileURLWithPath: $0) }
                let keyPath = paths.first ?? "getinfo"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .getInfo) {
                    try await entryOpenClient.openFinderInfo(urls)
                }

            case let .shareItems(paths, anchor):
                let urls = paths.map { URL(fileURLWithPath: $0) }
                let keyPath = paths.first ?? "share"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .share) {
                    try await entryOpenClient.shareItems(urls, anchor)
                }

            case let .performService(paths, name):
                let urls = paths.map { URL(fileURLWithPath: $0) }
                let keyPath = paths.first ?? "service"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .performService(name)) {
                    try await entryOpenClient.performService(name, urls)
                }

            case let .revealInFinder(paths):
                let urls = paths.map { URL(fileURLWithPath: $0) }
                let keyPath = paths.first ?? "reveal"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .revealInFinder) {
                    try await entryOpenClient.revealInFinder(urls)
                }

            default:
                return .none
            }
        }
    }
}
