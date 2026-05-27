import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

enum EntryOperationsExecutionSupport {
    struct FileInfo {
        let file: EntryModel
        let fileType: UTType
        let url: URL
    }

    private actor EntryActionTargetAccumulator {
        private var storage: [EntryActionRecord.Target] = []

        func append(_ target: EntryActionRecord.Target) {
            storage.append(target)
        }

        var targets: [EntryActionRecord.Target] {
            storage
        }
    }

    static func run(
        for filePath: String,
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            await send(.lifecycle(.operationStarted(filePath, kind)))
            do {
                try await operation()
                await send(.lifecycle(.operationFinished(filePath, kind, .success(()))))
            } catch {
                await send(.lifecycle(.operationFinished(filePath, kind, .failure(error.fileOpError))))
            }
        }
    }

    static func runParallel(
        paths: [String],
        kind: OperationKind,
        operation: @escaping @Sendable (URL) async throws -> Void,
        pathsMutated: (@Sendable (URL) -> [String])? = nil,
        onComplete: (@Sendable () async -> Void)? = nil,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            await withTaskGroup(of: Void.self) { group in
                for path in paths {
                    group.addTask {
                        await send(.lifecycle(.operationStarted(path, kind)))

                        do {
                            let url = URL(fileURLWithPath: path)
                            try await operation(url)
                            if let pathsMutated {
                                await send(.lifecycle(.pathsMutated(pathsMutated(url))))
                            }
                            await send(.lifecycle(.operationFinished(path, kind, .success(()))))
                        } catch {
                            await send(.lifecycle(.operationFinished(
                                path,
                                kind,
                                .failure(error.fileOpError),
                            )))
                        }
                    }
                }
            }

            await onComplete?()
        }
    }

    static func runParallelWithTargets(
        paths: [String],
        kind: OperationKind,
        operationKind: OperationKind,
        operation: @escaping @Sendable (URL) async throws -> EntryActionRecord.Target?,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            let accumulator = EntryActionTargetAccumulator()

            await withTaskGroup(of: Void.self) { group in
                for path in paths {
                    group.addTask {
                        await send(.lifecycle(.operationStarted(path, kind)))

                        do {
                            let url = URL(fileURLWithPath: path)
                            let target = try await operation(url)
                            if let target {
                                await accumulator.append(target)
                                await send(.lifecycle(.pathsMutated([target.beforePath, target.afterPath]
                                        .compactMap(\.self))))
                            }
                            await send(.lifecycle(.operationFinished(path, kind, .success(()))))
                        } catch {
                            await send(.lifecycle(.operationFinished(
                                path,
                                kind,
                                .failure(error.fileOpError),
                            )))
                        }
                    }
                }
            }

            let targets = await accumulator.targets
            guard !targets.isEmpty, operationKind.isUndoable else { return }
            let record = EntryActionRecord(operationKind: operationKind, targets: targets)
            await send(.lifecycle(.entryActionCompleted(record)))
        }
    }

    static func finalizeApplicationList(_ apps: [ApplicationInfo]) -> [ApplicationInfo] {
        var result = apps
        result.append(ApplicationInfo(
            id: "other",
            name: "Other…",
            bundleID: nil,
            isDefault: false,
        ))
        result.sort { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name < rhs.name
        }
        return result
    }
}

extension Error {
    var fileOpError: FileOpError {
        if let error = self as? FileOpError { return error }
        if let nsError = self as NSError?, nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .notFound
            case NSUserCancelledError:
                return .cancelled
            default:
                return .system(message: nsError.localizedDescription)
            }
        }
        return .system(message: localizedDescription)
    }
}
