import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@Reducer
struct EntryArchiveOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .archive(.compressItems(paths)):
                let itemURLs = paths.map { URL(fileURLWithPath: $0) }
                guard let firstPath = paths.first else { return .none }
                let parentPath = URL(fileURLWithPath: firstPath).deletingLastPathComponent().path

                return .run { [entryFileOpsClient] send in
                    await send(.lifecycle(.operationStarted(parentPath, .compress)))
                    var succeededCount = 0
                    var failedCount = 0

                    do {
                        let archiveURL = try await entryFileOpsClient.compressItems(itemURLs)
                        succeededCount = 1
                        await send(.lifecycle(.operationFinished(parentPath, .compress, .success(()))))
                        entryFileOpsClient.postFileSystemChanged([archiveURL.path])
                    } catch {
                        failedCount = 1
                        await send(.lifecycle(.operationFinished(parentPath, .compress, .failure(error.fileOpError))))
                    }

                    // 수용된 압축 명령은 성공 여부와 무관하게 정확히 한 건의 terminal로 마무리한다.
                    await send(.lifecycle(.entryActionCompleted(
                        EntryActionRecord(
                            operationKind: .compress,
                            targets: [],
                            failedCount: failedCount,
                            succeededCount: succeededCount,
                        ),
                    )))
                }

            case let .archive(.extractCompressedFile(path)):
                let zipURL = URL(fileURLWithPath: path)
                let parentPath = zipURL.deletingLastPathComponent().path

                return .run { [entryFileOpsClient] send in
                    await send(.lifecycle(.operationStarted(parentPath, .extract)))
                    var succeededCount = 0
                    var failedCount = 0

                    do {
                        try await entryFileOpsClient.extractCompressedFile(zipURL)
                        succeededCount = 1
                        await send(.lifecycle(.operationFinished(parentPath, .extract, .success(()))))
                        entryFileOpsClient.postFileSystemChanged([parentPath])
                    } catch {
                        failedCount = 1
                        await send(.lifecycle(.operationFinished(parentPath, .extract, .failure(error.fileOpError))))
                    }

                    // 수용된 압축 해제 명령도 정확히 한 건의 terminal로 마무리한다.
                    await send(.lifecycle(.entryActionCompleted(
                        EntryActionRecord(
                            operationKind: .extract,
                            targets: [],
                            failedCount: failedCount,
                            succeededCount: succeededCount,
                        ),
                    )))
                }

            default:
                return .none
            }
        }
    }
}
