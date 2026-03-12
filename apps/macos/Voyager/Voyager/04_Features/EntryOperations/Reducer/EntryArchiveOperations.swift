import ComposableArchitecture
import Foundation

@Reducer
struct EntryArchiveOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .compressItems(paths):
                let itemURLs = paths.map { URL(fileURLWithPath: $0) }
                guard let firstPath = paths.first else { return .none }
                let parentPath = URL(fileURLWithPath: firstPath).deletingLastPathComponent().path

                return .run { [entryFileOpsClient] send in
                    await send(.operationStarted(parentPath, .compress))

                    do {
                        let archiveURL = try await entryFileOpsClient.compressItems(itemURLs)
                        await send(.operationFinished(parentPath, .compress, .success(())))
                        entryFileOpsClient.postFileSystemChanged([archiveURL.path])
                    } catch {
                        await send(.operationFinished(parentPath, .compress, .failure(error.fileOpError)))
                    }
                }

            case let .extractCompressedFile(path):
                let zipURL = URL(fileURLWithPath: path)
                let parentPath = zipURL.deletingLastPathComponent().path

                return .run { [entryFileOpsClient] send in
                    await send(.operationStarted(parentPath, .extract))

                    do {
                        try await entryFileOpsClient.extractCompressedFile(zipURL)
                        await send(.operationFinished(parentPath, .extract, .success(())))
                        entryFileOpsClient.postFileSystemChanged([parentPath])
                    } catch {
                        await send(.operationFinished(parentPath, .extract, .failure(error.fileOpError)))
                    }
                }

            default:
                return .none
            }
        }
    }
}
