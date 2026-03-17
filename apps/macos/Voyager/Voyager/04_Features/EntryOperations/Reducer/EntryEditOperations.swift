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
        Reduce { state, action in
            switch action {
            case let .createNewFolder(parentPath):
                let name = defaultNewFolderName(entries: Array(state.displayItems))
                let parentURL = URL(fileURLWithPath: parentPath)
                let targetPath = parentURL.appendingPathComponent(name).path

                return .run { send in
                    await send(.operationStarted(targetPath, .createFolder))
                    do {
                        try await entryFileOpsClient.createFolder(parentURL, name)
                        await send(.operationFinished(targetPath, .createFolder, .success(())))
                        let record = EntryActionRecord(
                            operationKind: .createFolder,
                            targets: [.init(beforePath: nil, afterPath: targetPath)],
                        )
                        await send(.entryActionCompleted(record))
                    } catch {
                        await send(.operationFinished(targetPath, .createFolder, .failure(error.fileOpError)))
                    }
                }

            case let .createAliases(paths):
                return .run { [entryFileOpsClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for path in paths {
                        let sourceURL = URL(fileURLWithPath: path)
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

                        await send(.operationStarted(path, .createAlias))
                        do {
                            try await entryFileOpsClient.createAlias(sourceURL, aliasURL)
                            await send(.operationFinished(path, .createAlias, .success(())))
                            targets.append(.init(beforePath: path, afterPath: aliasURL.path))
                            entryFileOpsClient.postFileSystemChanged([aliasURL.path])
                        } catch {
                            await send(.operationFinished(path, .createAlias, .failure(error.fileOpError)))
                        }
                    }

                    guard !targets.isEmpty else { return }
                    let record = EntryActionRecord(operationKind: .createAlias, targets: targets)
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
                            operationKind: .rename,
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

            case let .startRename(id, text):
                guard state.displayItems[id: id] != nil else { return .none }
                state.renamingItemId = id
                state.renamingText = text
                return .none

            case let .updateRenamingText(text):
                guard state.renamingItemId != nil else { return .none }
                state.renamingText = text
                return .none

            case .commitRename:
                guard let itemId = state.renamingItemId,
                      let item = state.displayItems[id: itemId]
                else {
                    state.renamingItemId = nil
                    state.renamingText = ""
                    return .none
                }

                let trimmed = state.renamingText.trimmingCharacters(in: .whitespaces)
                state.renamingItemId = nil
                state.renamingText = ""

                guard !trimmed.isEmpty, trimmed != item.name else {
                    return .none
                }

                let parentPath = URL(fileURLWithPath: item.fullPath).deletingLastPathComponent().path
                let newPath = URL(fileURLWithPath: parentPath).appendingPathComponent(trimmed).path
                return .send(.renameItem(oldPath: item.fullPath, newPath: newPath))

            case .cancelRename:
                state.renamingItemId = nil
                state.renamingText = ""
                return .none

            default:
                return .none
            }
        }
    }

    private func defaultNewFolderName(entries: [EntryModel]) -> String {
        var folderName = "untitled folder"
        var counter = 2

        while entries.contains(where: { $0.name == folderName }) {
            folderName = "untitled folder \(counter)"
            counter += 1
        }

        return folderName
    }
}
