import ComposableArchitecture
import Foundation

@Reducer
struct EntryEditOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .createNewFolder(name, parentPath):
                let parentURL = URL(fileURLWithPath: parentPath)
                let targetPath = parentURL.appendingPathComponent(name).path

                return .run { send in
                    await send(.operationStarted(targetPath, .createFolder))
                    do {
                        try await entryFileOpsClient.createFolder(parentURL, name)
                        await send(.operationFinished(targetPath, .createFolder, .success(())))
                        let record = EntryActionRecord(
                            actionKind: .createFolder,
                            targets: [.init(beforePath: nil, afterPath: targetPath)],
                        )
                        await send(.entryActionCompleted(record))
                    } catch {
                        await send(.operationFinished(targetPath, .createFolder, .failure(error.fileOpError)))
                    }
                }

            case let .createAliases(items):
                return .run { [entryFileOpsClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for item in items {
                        let sourceURL = URL(fileURLWithPath: item.fullPath)
                        let parentURL = sourceURL.deletingLastPathComponent()
                        let baseName = sourceURL.lastPathComponent

                        var aliasName = "\(baseName) alias"
                        var aliasURL = parentURL.appendingPathComponent(aliasName)
                        var counter = 2

                        while entryFileOpsClient.fileExists(aliasURL.path) {
                            aliasName = "\(baseName) alias \(counter)"
                            aliasURL = parentURL.appendingPathComponent(aliasName)
                            counter += 1
                        }

                        await send(.operationStarted(item.fullPath, .createAlias))
                        do {
                            try await entryFileOpsClient.createAlias(sourceURL, aliasURL)
                            await send(.operationFinished(item.fullPath, .createAlias, .success(())))
                            targets.append(.init(beforePath: item.fullPath, afterPath: aliasURL.path))
                            entryFileOpsClient.postFileSystemChanged([aliasURL.path])
                        } catch {
                            await send(.operationFinished(item.fullPath, .createAlias, .failure(error.fileOpError)))
                        }
                    }

                    guard !targets.isEmpty else { return }
                    let record = EntryActionRecord(actionKind: .createAlias, targets: targets)
                    await send(.entryActionCompleted(record))
                }

            case let .renameItem(oldPath, newPath):
                let sourceURL = URL(fileURLWithPath: oldPath)
                let destURL = URL(fileURLWithPath: newPath)

                return .run { send in
                    await send(.operationStarted(oldPath, .rename))
                    do {
                        try await entryFileOpsClient.renameFile(sourceURL, destURL)
                        await send(.operationFinished(oldPath, .rename, .success(())))
                        let record = EntryActionRecord(
                            actionKind: .rename,
                            targets: [.init(beforePath: oldPath, afterPath: newPath)],
                        )
                        await send(.entryActionCompleted(record))
                    } catch let error as FileOpError where error.isFileExists {
                        guard let itemName = error.itemName else {
                            await send(.operationFinished(oldPath, .rename, .failure(error)))
                            return
                        }
                        await alertClient.showRenameConflictAlert(itemName)
                        await send(.operationFinished(oldPath, .rename, .failure(error)))
                    } catch {
                        await send(.operationFinished(oldPath, .rename, .failure(error.fileOpError)))
                    }
                }

            default:
                return .none
            }
        }
    }
}
