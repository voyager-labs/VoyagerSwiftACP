import ComposableArchitecture
import Foundation

@Reducer
struct EntryIntentRenameReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .startRename(id):
                guard let item = state.displayItems.first(where: { $0.id == id }) else {
                    return .none
                }

                state.renamingItemId = id
                state.renamingText = item.name

                return .none

            case let .updateRenamingText(text):
                state.renamingText = text
                return .none

            case let .createNewFolder(currentPath):
                var folderName = "untitled folder"
                var counter = 2
                while state.items.contains(where: { $0.name == folderName }) {
                    folderName = "untitled folder \(counter)"
                    counter += 1
                }

                state.creatingNewFolderId = nil
                state.creatingNewFolderPath = currentPath
                state.creatingNewFolderOriginalName = folderName
                state.renamingItemId = nil
                state.renamingText = ""

                return .send(.delegate(.intent(.createNewFolder(name: folderName, parentPath: currentPath))))

            case let .confirmNewFolder(name, path, _):
                guard let creatingId = state.creatingNewFolderId else { return .none }
                let oldPath = creatingId
                state.clearCreatingFolder()

                let parentURL = URL(fileURLWithPath: path)
                let targetPath = parentURL.appendingPathComponent(name).path
                guard targetPath != oldPath else {
                    return .none
                }

                return .send(.delegate(.intent(.renameItem(oldPath: oldPath, newPath: targetPath))))

            case .commitRename:
                guard let itemId = state.renamingItemId,
                      let item = state.displayItems.first(where: { $0.id == itemId })
                else {
                    return .send(.cancelRename)
                }

                let trimmed = state.renamingText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    return .send(.cancelRename)
                }
                let finalName = trimmed

                if let creatingId = state.creatingNewFolderId,
                   creatingId == itemId,
                   let parentPath = state.creatingNewFolderPath,
                   let originalName = state.creatingNewFolderOriginalName
                {
                    state.clearRenaming()
                    return .send(.confirmNewFolder(name: finalName, path: parentPath, originalName: originalName))
                }

                if finalName == item.name {
                    return .send(.cancelRename)
                }

                let oldPath = item.fullPath
                let parentPath = URL(fileURLWithPath: oldPath).deletingLastPathComponent()
                let newPath = parentPath.appendingPathComponent(finalName).path

                state.clearRenaming()
                state.selectAfterLoadFileNames = [finalName]

                return .send(.delegate(.intent(.renameItem(oldPath: oldPath, newPath: newPath))))

            case .cancelRename:
                if let creatingId = state.creatingNewFolderId, creatingId == state.renamingItemId {
                    state.clearCreatingFolder()
                }
                state.clearRenaming()
                return .none

            default:
                return .none
            }
        }
    }
}
