import ComposableArchitecture
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryDropValidationContractTests: XCTestCase {
    /// 동일 부모 내부 이동은 추가 파일 작업 없이 무시되는지 검증
    func testValidateDropReturnsNoOpForSameParentInternalMove() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        let context = EntryDropValidationContext(
            sourcePaths: ["/tmp/voyager/source.txt"],
            destinationPath: "/tmp/voyager",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = .init(
                destinationPath: "/tmp/voyager",
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()
    }

    /// 하위 경로로 드롭하는 내부 이동도 무시되어 순환 이동을 막는지 검증
    func testValidateDropReturnsNoOpForDescendantInternalMove() async {
        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }

        let context = EntryDropValidationContext(
            sourcePaths: ["/tmp/voyager/folder"],
            destinationPath: "/tmp/voyager/folder/child",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = .init(
                destinationPath: "/tmp/voyager/folder/child",
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()
    }

    // MARK: - 버그 2: 드래그 Option 상태가 세션에 기록되지 않는 문제

    func testDragOptionIsCapturedAtSessionStart() async {
        // 드래그 세션 시작 시 Option-key 상태를 캡처해야 드롭 정책을 일관되게 재현할 수 있다.
        // 저장되지 않으면 이후 로드 시 오래되거나 빈 값이 들어와 분기 판단이 흔들린다.
        let recorder = DragOptionRecorder()

        let store = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.saveDragPaths = { _ in }
            $0.entryFileOpsClient.loadDragPaths = { ["/tmp/file.txt"] }
            $0.entryFileOpsClient.saveDragWithOption = { [recorder] isOption in
                recorder.record(isOption)
            }
            $0.entryFileOpsClient.loadDragWithOption = { false }
        }

        await store.send(.routing(.saveDragPaths(["/tmp/file.txt"])))
        await store.finish()

        XCTAssertEqual(
            recorder.savedOptions.count,
            1,
            "saveDragWithOption should be called when a drag session begins",
        )
        XCTAssertFalse(
            recorder.savedOptions.first ?? true,
            "Option-key state should be captured as false (not pressed)",
        )
    }

    func testDragOptionDoesNotLeakBetweenSessions() async {
        // 각 드래그 세션은 자기 Option 상태를 따로 저장해야 이전 세션 값이 섞이지 않는다.
        let recorder = DragOptionRecorder()

        let store1 = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.saveDragPaths = { _ in }
            $0.entryFileOpsClient.loadDragPaths = { ["/tmp/file1.txt"] }
            $0.entryFileOpsClient.saveDragWithOption = { [recorder] isOption in
                recorder.record(isOption)
            }
            $0.entryFileOpsClient.loadDragWithOption = { false }
        }

        await store1.send(.routing(.saveDragPaths(["/tmp/file1.txt"])))
        await store1.finish()

        let store2 = TestStore(initialState: EntryOperationsFeature.State()) {
            EntryOperationsFeature()
        } withDependencies: {
            $0.entryFileOpsClient.saveDragPaths = { _ in }
            $0.entryFileOpsClient.loadDragPaths = { ["/tmp/file2.txt"] }
            $0.entryFileOpsClient.saveDragWithOption = { [recorder] isOption in
                recorder.record(isOption)
            }
            $0.entryFileOpsClient.loadDragWithOption = { true }
        }

        await store2.send(.routing(.saveDragPaths(["/tmp/file2.txt"])))
        await store2.finish()

        XCTAssertEqual(
            recorder.savedOptions.count,
            2,
            "Each drag session should independently call saveDragWithOption",
        )
        XCTAssertTrue(
            recorder.savedOptions.last ?? false,
            "Second session should capture its own option state, not inherit from first",
        )
    }
}

private final class DragOptionRecorder: @unchecked Sendable {
    private(set) var savedOptions: [Bool] = []
    func record(_ isOption: Bool) {
        savedOptions.append(isOption)
    }
}
