import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

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
                    var succeededCount = 0
                    var failedCount = 0
                    do {
                        try await entryFileOpsClient.createFolder(parentURL, name)
                        succeededCount = 1
                        await send(.lifecycle(.pathsMutated([targetPath])))
                        await send(.lifecycle(.operationFinished(targetPath, .createFolder, .success(()))))
                    } catch {
                        failedCount = 1
                        await send(.lifecycle(.operationFinished(
                            targetPath,
                            .createFolder,
                            .failure(error.fileOpError),
                        )))
                    }
                    // 수용된 생성 명령은 성공 여부와 무관하게 정확히 한 건의 terminal로 마무리한다.
                    await send(.lifecycle(.entryActionCompleted(
                        EntryActionRecord(
                            operationKind: .createFolder,
                            targets: succeededCount == 1
                                ? [.init(beforePath: nil, afterPath: targetPath)]
                                : [],
                            failedCount: failedCount,
                            succeededCount: succeededCount,
                        ),
                    )))
                }

            case let .edit(.createAliases(paths)):
                return .run { [entryFileOpsClient] send in
                    var targets: [EntryActionRecord.Target] = []
                    var failedCount = 0

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
                            failedCount += 1
                            await send(.lifecycle(.operationFinished(path, .createAlias, .failure(error.fileOpError))))
                        }
                    }

                    // 전체 실패 배치도 실패 aggregate를 담은 terminal로 마무리한다.
                    let record = EntryActionRecord(
                        operationKind: .createAlias,
                        targets: targets,
                        failedCount: failedCount,
                    )
                    await send(.lifecycle(.entryActionCompleted(record)))
                }

            case let .edit(.renameItem(oldPath, newPath)):
                let sourceURL = URL(fileURLWithPath: oldPath)
                let destURL = URL(fileURLWithPath: newPath)

                return .run { [entryFileOpsClient, alertClient] send in
                    await send(.lifecycle(.operationStarted(oldPath, .rename)))
                    var succeededCount = 0
                    var failedCount = 0
                    do {
                        try await entryFileOpsClient.renameFile(sourceURL, destURL)
                        succeededCount = 1
                        await send(.lifecycle(.pathsMutated([oldPath, newPath])))
                        await send(.lifecycle(.operationFinished(oldPath, .rename, .success(()))))
                    } catch let error as FileOpError where error.isFileExists {
                        failedCount = 1
                        guard let itemName = error.itemName else {
                            await send(.lifecycle(.operationFinished(oldPath, .rename, .failure(error))))
                            await finishRenameTerminal(
                                oldPath: oldPath,
                                newPath: newPath,
                                succeededCount: succeededCount,
                                failedCount: failedCount,
                                send: send,
                            )
                            return
                        }
                        await alertClient.showRenameConflictAlert(itemName)
                        await send(.lifecycle(.operationFinished(oldPath, .rename, .failure(error))))
                    } catch {
                        failedCount = 1
                        await send(.lifecycle(.operationFinished(oldPath, .rename, .failure(error.fileOpError))))
                    }
                    // 수용된 rename 명령은 성공 여부와 무관하게 정확히 한 건의 terminal로 마무리한다.
                    await finishRenameTerminal(
                        oldPath: oldPath,
                        newPath: newPath,
                        succeededCount: succeededCount,
                        failedCount: failedCount,
                        send: send,
                    )
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
                      let item = state.renamingItem ?? state.items[id: itemId]
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
                    } else {
                        await send(.lifecycle(.entryActionCompleted(EntryActionRecord(
                            operationKind: .rename,
                            targets: [],
                            failedCount: 0,
                            cancelledCount: 1,
                            succeededCount: 0,
                            id: UUID(),
                            timestamp: Date(),
                        ))))
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

/// rename terminal은 성공 시에만 semantic target을 가진다.
private func finishRenameTerminal(
    oldPath: String,
    newPath: String,
    succeededCount: Int,
    failedCount: Int,
    send: Send<EntryOperationsAction>,
) async {
    let record = EntryActionRecord(
        operationKind: .rename,
        targets: succeededCount == 1 ? [.init(beforePath: oldPath, afterPath: newPath)] : [],
        failedCount: failedCount,
        succeededCount: succeededCount,
    )
    await send(.lifecycle(.entryActionCompleted(record)))
}
