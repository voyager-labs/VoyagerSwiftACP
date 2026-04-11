import ComposableArchitecture
import Foundation

import VoyagerEntitiesEntry

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
            case let .edit(.createNewFolder(parentPath, siblingNames)):
                let name = defaultNewFolderName(siblingNames: siblingNames)
                let parentURL = URL(fileURLWithPath: parentPath)
                let targetPath = parentURL.appendingPathComponent(name).path

                return .run { send in
                    await send(.lifecycle(.operationStarted(targetPath, .createFolder)))
                    do {
                        try await entryFileOpsClient.createFolder(parentURL, name)
                        await send(.lifecycle(.operationFinished(targetPath, .createFolder, .success(()))))
                        let record = EntryActionRecord(
                            operationKind: .createFolder,
                            targets: [.init(beforePath: nil, afterPath: targetPath)],
                        )
                        await send(.lifecycle(.entryActionCompleted(record)))
                    } catch {
                        await send(.lifecycle(.operationFinished(
                            targetPath,
                            .createFolder,
                            .failure(error.fileOpError),
                        )))
                    }
                }

            case let .edit(.createAliases(paths)):
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

                        await send(.lifecycle(.operationStarted(path, .createAlias)))
                        do {
                            try await entryFileOpsClient.createAlias(sourceURL, aliasURL)
                            await send(.lifecycle(.operationFinished(path, .createAlias, .success(()))))
                            targets.append(.init(beforePath: path, afterPath: aliasURL.path))
                            entryFileOpsClient.postFileSystemChanged([aliasURL.path])
                        } catch {
                            await send(.lifecycle(.operationFinished(path, .createAlias, .failure(error.fileOpError))))
                        }
                    }

                    guard !targets.isEmpty else { return }
                    let record = EntryActionRecord(operationKind: .createAlias, targets: targets)
                    await send(.lifecycle(.entryActionCompleted(record)))
                }

            case let .edit(.renameItem(oldPath, newPath)):
                let sourceURL = URL(fileURLWithPath: oldPath)
                let destURL = URL(fileURLWithPath: newPath)

                return .run { [entryFileOpsClient, alertClient] send in
                    await send(.lifecycle(.operationStarted(oldPath, .rename)))
                    do {
                        try await entryFileOpsClient.renameFile(sourceURL, destURL)
                        await send(.lifecycle(.pathsMutated([oldPath, newPath])))
                        await send(.lifecycle(.operationFinished(oldPath, .rename, .success(()))))
                        let record = EntryActionRecord(
                            operationKind: .rename,
                            targets: [.init(beforePath: oldPath, afterPath: newPath)],
                        )
                        await send(.lifecycle(.entryActionCompleted(record)))
                    } catch let error as FileOpError where error.isFileExists {
                        guard let itemName = error.itemName else {
                            await send(.lifecycle(.operationFinished(oldPath, .rename, .failure(error))))
                            return
                        }
                        await alertClient.showRenameConflictAlert(itemName)
                        await send(.lifecycle(.operationFinished(oldPath, .rename, .failure(error))))
                    } catch {
                        await send(.lifecycle(.operationFinished(oldPath, .rename, .failure(error.fileOpError))))
                    }
                }

            case let .edit(.startRename(item, text)):
                state.renamingItemId = item.id
                state.renamingText = text
                state.renamingItem = item
                return .none

            case let .edit(.updateRenamingText(text)):
                guard state.renamingItemId != nil else { return .none }
                state.renamingText = text
                return .none

            case .edit(.commitRename):
                guard let itemId = state.renamingItemId,
                      let item = state.renamingItem ?? state.displayItems[id: itemId]
                else {
                    state.renamingItemId = nil
                    state.renamingText = ""
                    state.renamingItem = nil
                    return .none
                }

                let trimmed = state.renamingText.trimmingCharacters(in: .whitespaces)

                guard !trimmed.isEmpty, trimmed != item.name else {
                    state.renamingItemId = nil
                    state.renamingText = ""
                    state.renamingItem = nil
                    return .none
                }

                state.renamingText = trimmed
                let parentPath = URL(fileURLWithPath: item.fullPath).deletingLastPathComponent().path
                let newPath = URL(fileURLWithPath: parentPath).appendingPathComponent(trimmed).path

                let transition = EntryRenameExtensionPolicy.extensionTransition(
                    from: item.name,
                    to: trimmed,
                    isFolder: item.isFolder,
                )

                if transition == .none {
                    return .send(.edit(.renameItem(oldPath: item.fullPath, newPath: newPath)))
                }

                return .run { [alertClient] send in
                    let confirmed = await alertClient.showRenameExtensionChangeAlert(item.name, trimmed)
                    if confirmed {
                        await send(.edit(.renameItem(oldPath: item.fullPath, newPath: newPath)))
                    }
                }

            case .edit(.cancelRename):
                state.renamingItemId = nil
                state.renamingText = ""
                state.renamingItem = nil
                return .none

            default:
                return .none
            }
        }
    }

    private func defaultNewFolderName(siblingNames: [String]) -> String {
        var folderName = "untitled folder"
        var counter = 2

        while siblingNames.contains(folderName) {
            folderName = "untitled folder \(counter)"
            counter += 1
        }

        return folderName
    }
}
