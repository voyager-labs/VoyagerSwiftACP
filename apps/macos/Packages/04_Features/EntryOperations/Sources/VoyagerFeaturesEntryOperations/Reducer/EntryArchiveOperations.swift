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

                    do {
                        let archiveURL = try await entryFileOpsClient.compressItems(itemURLs)
                        await send(.lifecycle(.operationFinished(parentPath, .compress, .success(()))))
                        entryFileOpsClient.postFileSystemChanged([archiveURL.path])
                    } catch {
                        await send(.lifecycle(.operationFinished(parentPath, .compress, .failure(error.fileOpError))))
                    }
                }

            case let .archive(.extractCompressedFile(path)):
                let zipURL = URL(fileURLWithPath: path)
                let parentPath = zipURL.deletingLastPathComponent().path

                return .run { [entryFileOpsClient] send in
                    await send(.lifecycle(.operationStarted(parentPath, .extract)))

                    do {
                        try await entryFileOpsClient.extractCompressedFile(zipURL)
                        await send(.lifecycle(.operationFinished(parentPath, .extract, .success(()))))
                        entryFileOpsClient.postFileSystemChanged([parentPath])
                    } catch {
                        await send(.lifecycle(.operationFinished(parentPath, .extract, .failure(error.fileOpError))))
                    }
                }

            default:
                return .none
            }
        }
    }
}
