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
        private var failures = 0
        private var successes = 0

        func append(_ target: EntryActionRecord.Target) {
            storage.append(target)
        }

        var targets: [EntryActionRecord.Target] {
            storage
        }

        func recordSuccess() {
            successes += 1
        }

        func recordFailure() {
            failures += 1
        }

        var failedCount: Int {
            failures
        }

        var succeededCount: Int {
            successes
        }
    }

    static func run(
        for filePath: String,
        kind: OperationKind,
        operation: @escaping @Sendable () async throws -> Void,
    ) -> Effect<EntryOperationsAction> {
        .run { send in
            await send(.lifecycle(.operationStarted(filePath, kind)))
            var succeededCount = 0
            var failedCount = 0
            do {
                try await operation()
                succeededCount = 1
                await send(.lifecycle(.operationFinished(filePath, kind, .success(()))))
            } catch {
                failedCount = 1
                await send(.lifecycle(.operationFinished(filePath, kind, .failure(error.fileOpError))))
            }
            // 비-undo 단일 명령도 정확히 한 건의 command-level terminal로 마무리한다.
            await send(.lifecycle(.entryActionCompleted(
                EntryActionRecord(
                    operationKind: kind,
                    targets: [],
                    failedCount: failedCount,
                    succeededCount: succeededCount,
                ),
            )))
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
            let accumulator = EntryActionTargetAccumulator()

            await withTaskGroup(of: Void.self) { group in
                for path in paths {
                    group.addTask {
                        await send(.lifecycle(.operationStarted(path, kind)))

                        do {
                            let url = URL(fileURLWithPath: path)
                            try await operation(url)
                            await accumulator.recordSuccess()
                            if let pathsMutated {
                                await send(.lifecycle(.pathsMutated(pathsMutated(url))))
                            }
                            await send(.lifecycle(.operationFinished(path, kind, .success(()))))
                        } catch {
                            await accumulator.recordFailure()
                            await send(.lifecycle(.operationFinished(
                                path,
                                kind,
                                .failure(error.fileOpError),
                            )))
                        }
                    }
                }
            }

            // 전체 실패 배치도 실패 aggregate를 담은 terminal로 마무리한다.
            let failedCount = await accumulator.failedCount
            let succeededCount = await accumulator.succeededCount
            await send(.lifecycle(.entryActionCompleted(
                EntryActionRecord(
                    operationKind: kind,
                    targets: [],
                    failedCount: failedCount,
                    succeededCount: succeededCount,
                ),
            )))

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
                            await accumulator.recordFailure()
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
            let failedCount = await accumulator.failedCount
            // 성공 여부와 무관하게 수용된 배치는 정확히 한 건의 terminal로 마무리한다.
            // undo 등록은 소비자가 successful targets 존재로 게이트한다.
            let record = EntryActionRecord(
                operationKind: operationKind,
                targets: targets,
                failedCount: failedCount,
            )
            await send(.lifecycle(.entryActionCompleted(record)))
        }
    }

    static func finalizeApplicationList(_ apps: [ApplicationInfo]) -> [ApplicationInfo] {
        var result = apps.filter { $0.bundleID != nil }
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
