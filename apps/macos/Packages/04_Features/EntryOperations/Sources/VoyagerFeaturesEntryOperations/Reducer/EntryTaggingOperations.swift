import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@Reducer
struct EntryTaggingOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .tagging(.requestTagMutation(request)):
                let paths = Self.uniquePaths(in: request.paths)
                guard !paths.isEmpty, !paths.contains(where: { state.itemStates[$0]?.isBusy == true }) else {
                    return .none
                }
                for path in paths {
                    state.itemStates[path] = ItemOperationState(isBusy: true, lastError: nil)
                }
                return applyTagMutation(request, paths: paths)

            default:
                return .none
            }
        }
    }

    private func applyTagMutation(_ request: TagMutationRequest, paths: [String]) -> Effect<Action> {
        .run { [alertClient, entryFileOpsClient] send in
            var completedTargets: [EntryActionRecord.Target] = []
            var failures: [TagMutationFailure] = []

            for filePath in paths {
                let url = URL(fileURLWithPath: filePath)

                do {
                    let beforeTags = try await entryFileOpsClient.getTags(url)
                    let afterTags = Self.makeAfterTags(
                        mode: request.mode,
                        tagName: request.tagName,
                        beforeTags: beforeTags,
                    )
                    guard beforeTags != afterTags else {
                        await send(.lifecycle(.operationFinished(filePath, .setTags, .success(()))))
                        continue
                    }

                    try await entryFileOpsClient.setTags(url, afterTags)
                    await send(.lifecycle(.operationFinished(filePath, .setTags, .success(()))))
                    completedTargets.append(EntryActionRecord.Target(
                        beforePath: filePath,
                        afterPath: filePath,
                        beforeTags: beforeTags,
                        afterTags: afterTags,
                    ))
                } catch {
                    let fileOpError = error.fileOpError
                    await send(.lifecycle(.operationFinished(filePath, .setTags, .failure(fileOpError))))
                    failures.append(TagMutationFailure(
                        fileName: url.lastPathComponent,
                        reason: fileOpError.message,
                    ))
                }
            }

            if !completedTargets.isEmpty {
                let record = EntryActionRecord(operationKind: .setTags, targets: completedTargets)
                await send(.lifecycle(.entryActionCompleted(record)))
            }
            if !failures.isEmpty {
                await alertClient.showTagMutationFailureAlert(failures)
            }
        }
    }

    nonisolated private static func uniquePaths(in paths: [String]) -> [String] {
        var seenPaths: Set<String> = []
        return paths.filter { seenPaths.insert($0).inserted }
    }

    nonisolated private static func makeAfterTags(
        mode: TagMutationRequest.Mode,
        tagName: String,
        beforeTags: [String],
    ) -> [String] {
        var tags = beforeTags
        let hasTag = tags.contains(tagName)

        switch mode {
        case .toggle:
            if hasTag {
                tags.removeAll { $0 == tagName }
            } else {
                tags.append(tagName)
            }
        case .add:
            if !hasTag {
                tags.append(tagName)
            }
        case .remove:
            if hasTag {
                tags.removeAll { $0 == tagName }
            }
        }

        return tags
    }
}
