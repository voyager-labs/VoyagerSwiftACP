import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryOperationsExecutionSupportTests: XCTestCase {
    /// 단일 작업 실행이 시작/종료 라이프사이클 액션을 순서대로 내보내는지 검증
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

    /// 작업 중 오류가 나면 failure를 담은 종료 액션으로 매핑되는지 검증
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

    /// 병렬 실행이 각 경로에 대해 시작/종료 순서를 유지하는지 검증
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

    /// targets가 있는 병렬 rename이 entryActionCompleted까지 이어지는지 검증
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
                )
                .map { action in
                    switch action {
                    case let .lifecycle(lifecycle): .lifecycle(lifecycle)
                    default: .lifecycle(.emptyTrashCompleted)
                    }
                }

            case let .triggerRunParallel(paths, kind):
                EntryOperationsExecutionSupport.runParallel(
                    paths: paths,
                    kind: kind,
                    operation: { _ in },
                )
                .map { action in
                    switch action {
                    case let .lifecycle(lifecycle): .lifecycle(lifecycle)
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
                )
                .map { action in
                    switch action {
                    case let .lifecycle(lifecycle): .lifecycle(lifecycle)
                    default: .lifecycle(.emptyTrashCompleted)
                    }
                }

            case .lifecycle:
                .none
            }
        }
    }
}
