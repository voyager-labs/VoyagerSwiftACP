import AppKit
import ComposableArchitecture
import Foundation
import QuickLookUI
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
extension FMW001FileManagerWindowTests {
    /// FMW-001-key_command_focus: background window은 process-global Quick Look panel을 제어하지 않는다.
    /// - 검증 내용: 선택 항목이 남아 있더라도 `isFocused == false`인 coordinator는 panel control을 거절하고 handler를 attach하지 않는다.
    /// - 사전 조건: active selection을 가진 background FileManager window와 panel-control recording client
    /// - 기대 결과: accepts가 false이고 begin callback은 호출되지 않는다.
    func testQuickLookPanelControlRejectsBackgroundWindow() throws {
        _ = NSApplication.shared
        let beginCount = LockIsolated(0)
        let quickLookClient = EntryQuickLookClient(
            quickLook: { _, _ in },
            acceptsPreviewPanelControl: { true },
            beginPreviewPanelControl: { _, _ in beginCount.withValue { $0 += 1 } },
        )
        let registry = FileOperationUndoManagerRegistry()
        let store = Store(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = quickLookClient
            $0.fileOperationUndoManagerClient = .live(registry: registry)
        }
        let coordinator = withDependencies {
            $0.entryQuickLookClient = quickLookClient
        } operation: {
            FileManagerWindowCoordinator(
                windowID: UUID(),
                store: store,
                fileOperationUndoManagerRegistry: registry,
                makeContentViewController: { _, _ in NSViewController() },
            )
        }
        defer { coordinator.close() }
        let panel = try XCTUnwrap(QLPreviewPanel.shared())

        XCTAssertFalse(coordinator.acceptsPreviewPanelControl(panel))
        coordinator.beginPreviewPanelControl(panel)

        XCTAssertEqual(beginCount.value, 0)
    }

    /// FMW-001-key_command_focus: 선택 없는 focused window도 이전 창의 global preview를 탈취하지 않는다.
    /// - 검증 내용: `isFocused == true`여도 canonical selection이 비어 있으면 control을 거절하고 handler를 attach하지 않는다.
    /// - 사전 조건: 이전 창에서 남은 preview-ready client와 selection 없는 새 active FileManager window
    /// - 기대 결과: accepts가 false이고 begin callback은 호출되지 않는다.
    func testQuickLookPanelControlRejectsFocusedWindowWithoutSelection() throws {
        _ = NSApplication.shared
        let beginCount = LockIsolated(0)
        let quickLookClient = EntryQuickLookClient(
            quickLook: { _, _ in },
            acceptsPreviewPanelControl: { true },
            beginPreviewPanelControl: { _, _ in beginCount.withValue { $0 += 1 } },
        )
        let registry = FileOperationUndoManagerRegistry()
        var state = FileManagerFeature.State()
        state.isFocused = true
        let store = Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = quickLookClient
            $0.fileOperationUndoManagerClient = .live(registry: registry)
        }
        let coordinator = withDependencies {
            $0.entryQuickLookClient = quickLookClient
        } operation: {
            FileManagerWindowCoordinator(
                windowID: UUID(),
                store: store,
                fileOperationUndoManagerRegistry: registry,
                makeContentViewController: { _, _ in NSViewController() },
            )
        }
        defer { coordinator.close() }
        let panel = try XCTUnwrap(QLPreviewPanel.shared())

        XCTAssertFalse(coordinator.acceptsPreviewPanelControl(panel))
        coordinator.beginPreviewPanelControl(panel)

        XCTAssertEqual(beginCount.value, 0)
    }
}
