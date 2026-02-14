import ComposableArchitecture
import Foundation

@Reducer
struct EntryTaggingOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .setTagsForItems(targets):
                .run { [entryFileOpsClient] send in
                    var completedTargets: [EntryActionRecord.Target] = []

                    for target in targets {
                        let filePath = target.file.fullPath
                        let url = URL(fileURLWithPath: filePath)

                        await send(.operationStarted(filePath, .setTags))
                        do {
                            try await entryFileOpsClient.setTags(url, target.afterTags)
                            await send(.operationFinished(filePath, .setTags, .success(())))
                            completedTargets.append(EntryActionRecord.Target(
                                beforePath: filePath,
                                afterPath: filePath,
                                beforeTags: target.beforeTags,
                                afterTags: target.afterTags,
                            ))
                        } catch {
                            await send(.operationFinished(filePath, .setTags, .failure(error.fileOpError)))
                        }
                    }

                    guard !completedTargets.isEmpty else { return }
                    let record = EntryActionRecord(actionKind: .setTags, targets: completedTargets)
                    await send(.entryActionCompleted(record))
                }

            case let .toggleTagForDroppedPaths(paths, tagName):
                .run { [entryFileOpsClient] send in
                    for path in paths {
                        let url = URL(fileURLWithPath: path)
                        await send(.operationStarted(path, .setTags))
                        do {
                            let currentTags = try await entryFileOpsClient.getTags(url)
                            if !currentTags.contains(tagName) {
                                try await entryFileOpsClient.toggleTag(url, tagName)
                            }
                            await send(.operationFinished(path, .setTags, .success(())))
                        } catch {
                            await send(.operationFinished(path, .setTags, .failure(error.fileOpError)))
                        }
                    }
                }

            default:
                .none
            }
        }
    }
}
