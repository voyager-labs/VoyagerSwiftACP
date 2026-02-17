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
            case let .requestTagMutation(request):
                applyTagMutation(request)

            default:
                .none
            }
        }
    }

    private func applyTagMutation(_ request: TagMutationRequest) -> Effect<Action> {
        .run { [entryFileOpsClient] send in
            var completedTargets: [EntryActionRecord.Target] = []
            var seenPaths: Set<String> = []

            for filePath in request.paths where seenPaths.insert(filePath).inserted {
                let url = URL(fileURLWithPath: filePath)

                await send(.operationStarted(filePath, .setTags))
                do {
                    let beforeTags = try await entryFileOpsClient.getTags(url)
                    let afterTags = Self.makeAfterTags(
                        mode: request.mode,
                        tagName: request.tagName,
                        beforeTags: beforeTags,
                    )
                    guard beforeTags != afterTags else {
                        await send(.operationFinished(filePath, .setTags, .success(())))
                        continue
                    }

                    try await entryFileOpsClient.setTags(url, afterTags)
                    await send(.operationFinished(filePath, .setTags, .success(())))
                    completedTargets.append(EntryActionRecord.Target(
                        beforePath: filePath,
                        afterPath: filePath,
                        beforeTags: beforeTags,
                        afterTags: afterTags,
                    ))
                } catch {
                    await send(.operationFinished(filePath, .setTags, .failure(error.fileOpError)))
                }
            }

            guard !completedTargets.isEmpty else { return }
            let record = EntryActionRecord(actionKind: .setTags, targets: completedTargets)
            await send(.entryActionCompleted(record))
        }
    }

    private nonisolated static func makeAfterTags(
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
