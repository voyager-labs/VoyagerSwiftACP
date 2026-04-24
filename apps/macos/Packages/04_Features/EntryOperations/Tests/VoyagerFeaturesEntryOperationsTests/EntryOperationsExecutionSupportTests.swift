import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryOperationsExecutionSupportTests: XCTestCase {
    func testRunEmitsOperationStartedThenFinished() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            ExecutionSupportTestHarness()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.triggerRun("/tmp/test.txt", OperationKind.rename, nil))

        await store.receive(\.lifecycle.operationStarted)

        await store.receive(\.lifecycle.operationFinished)

        await store.finish()
    }

    func testRunEmitsOperationFinishedWithFailureOnError() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            ExecutionSupportTestHarness()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.triggerRun(
            "/tmp/missing.txt",
            OperationKind.rename,
            FileOpError.notFound,
        ))

        await store.receive(\.lifecycle.operationStarted)

        await store.receive { action in
            if case .lifecycle(.operationFinished(
                "/tmp/missing.txt",
                OperationKind.rename,
                .failure(.notFound),
            )) = action {
                return true
            }
            return false
        }

        await store.finish()
    }

    func testRunParallelEmitsCorrectOrdering() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            ExecutionSupportTestHarness()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.triggerRunParallel(
            ["/tmp/a.txt", "/tmp/b.txt"],
            OperationKind.moveToTrash,
        ))

        await store.receive(\.lifecycle.operationStarted)
        await store.receive(\.lifecycle.operationStarted)
        await store.receive(\.lifecycle.operationFinished)
        await store.receive(\.lifecycle.operationFinished)

        await store.finish()
    }

    func testRunParallelWithTargetsEmitsEntryActionCompleted() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            ExecutionSupportTestHarness()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.triggerRunParallelWithTargets(
            ["/tmp/old.txt"],
            OperationKind.rename,
            OperationKind.rename,
        ))

        await store.receive(\.lifecycle.operationStarted)
        await store.receive(\.lifecycle.pathsMutated)
        await store.receive(\.lifecycle.operationFinished)
        await store.receive(\.lifecycle.entryActionCompleted)

        await store.finish()
    }
}

@Reducer
private struct ExecutionSupportTestHarness {
    typealias State = EntryOperationsState

    @CasePathable
    enum Action: CasePathable, Sendable {
        case triggerRun(String, OperationKind, FileOpError?)
        case triggerRunParallel([String], OperationKind)
        case triggerRunParallelWithTargets([String], OperationKind, OperationKind)
        case lifecycle(EntryOperationsAction.Lifecycle)
    }

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .triggerRun(path, kind, error):
                EntryOperationsExecutionSupport.run(
                    for: path,
                    kind: kind,
                    operation: {
                        if let error { throw error }
                    },
                ).map { action in
                    switch action {
                    case let .lifecycle(l): .lifecycle(l)
                    default: .lifecycle(.emptyTrashCompleted)
                    }
                }

            case let .triggerRunParallel(paths, kind):
                EntryOperationsExecutionSupport.runParallel(
                    paths: paths,
                    kind: kind,
                    operation: { _ in },
                ).map { action in
                    switch action {
                    case let .lifecycle(l): .lifecycle(l)
                    default: .lifecycle(.emptyTrashCompleted)
                    }
                }

            case let .triggerRunParallelWithTargets(paths, kind, operationKind):
                EntryOperationsExecutionSupport.runParallelWithTargets(
                    paths: paths,
                    kind: kind,
                    operationKind: operationKind,
                    operation: { url in
                        EntryActionRecord.Target(
                            beforePath: url.path,
                            afterPath: url.path + "_renamed",
                        )
                    },
                ).map { action in
                    switch action {
                    case let .lifecycle(l): .lifecycle(l)
                    default: .lifecycle(.emptyTrashCompleted)
                    }
                }

            case .lifecycle:
                .none
            }
        }
    }
}
