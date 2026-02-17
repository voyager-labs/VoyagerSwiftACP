import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct EntryOpenOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOpenClient)
    var entryOpenClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .openFiles(files):
                guard !files.isEmpty else {
                    return .none
                }

                let entryOpenClient = entryOpenClient
                return .run { [entryOpenClient] (send: Send<Action>) in
                    guard let firstFile = files.first else { return }
                    let firstFilePath = firstFile.fullPath
                    let isTrash = await MainActor.run {
                        guard let trashPath = entryOpenClient.trashDirectoryPath(), !trashPath.isEmpty else {
                            return false
                        }
                        return firstFilePath.starts(with: trashPath + "/")
                    }

                    if isTrash {
                        for (index, file) in files.enumerated() {
                            let hasMoreFiles = index < files.count - 1
                            _ = await alertClient.showTrashFileAlert(file.name, hasMoreFiles)
                        }
                        return
                    }

                    var groupedFiles: [String: [(EntryModel, Int)]] = [:]
                    for (index, file) in files.enumerated() {
                        let ext = file.fileExtension.lowercased()
                        groupedFiles[ext, default: []].append((file, index))
                    }

                    for (_, groupFiles) in groupedFiles {
                        let urls = groupFiles.map { URL(fileURLWithPath: $0.0.fullPath) }
                        guard let firstURL = urls.first else { continue }

                        let appURL = await Task { @MainActor in
                            let workspace = NSWorkspace.shared
                            return workspace.urlForApplication(toOpen: firstURL)
                        }.value
                        guard let appURL else {
                            for (file, _) in groupFiles {
                                let filePath = file.fullPath
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

                        for (file, _) in groupFiles {
                            let filePath = file.fullPath
                            await send(.operationStarted(filePath, .openDefault))
                        }

                        do {
                            let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
                            defer {
                                for (url, isScoped) in zip(urls, scoped) where isScoped {
                                    url.stopAccessingSecurityScopedResource()
                                }
                            }
                            try await Task { @MainActor in
                                let workspace = NSWorkspace.shared
                                let configuration = NSWorkspace.OpenConfiguration()
                                configuration.createsNewApplicationInstance = false
                                try await workspace.open(
                                    urls,
                                    withApplicationAt: appURL,
                                    configuration: configuration,
                                )
                            }.value
                            for (file, _) in groupFiles {
                                let filePath = file.fullPath
                                await send(
                                    .operationFinished(filePath, .openDefault, .success(())),
                                )
                            }
                        } catch {
                            for (file, _) in groupFiles {
                                let filePath = file.fullPath
                                await send(.operationFinished(filePath, .openDefault, .failure(error.fileOpError)))
                            }
                        }
                    }
                }

            case let .quickLookFile(file):
                let filePath = file.fullPath
                let url = URL(fileURLWithPath: filePath)
                return EntryOperationsExecutionSupport.run(for: filePath, kind: .quickLook) {
                    try await entryOpenClient.quickLook(url)
                }

            case let .quickLookFiles(files):
                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                let keyPath = files.first?.fullPath ?? "quicklook"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .quickLook) {
                    try await entryOpenClient.quickLookFiles(urls)
                }

            case let .openFinderInfo(items):
                let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
                let keyPath = items.first?.fullPath ?? "getinfo"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .getInfo) {
                    try await entryOpenClient.openFinderInfo(urls)
                }

            case let .shareItems(items, anchor):
                let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
                let keyPath = items.first?.fullPath ?? "share"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .share) {
                    try await entryOpenClient.shareItems(urls, anchor)
                }

            case let .performService(items, name):
                let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
                let keyPath = items.first?.fullPath ?? "service"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .performService(name)) {
                    try await entryOpenClient.performService(name, urls)
                }

            case let .revealInFinder(items):
                let urls = items.map { URL(fileURLWithPath: $0.fullPath) }
                let keyPath = items.first?.fullPath ?? "reveal"
                return EntryOperationsExecutionSupport.run(for: keyPath, kind: .revealInFinder) {
                    try await entryOpenClient.revealInFinder(urls)
                }

            default:
                return .none
            }
        }
    }
}
