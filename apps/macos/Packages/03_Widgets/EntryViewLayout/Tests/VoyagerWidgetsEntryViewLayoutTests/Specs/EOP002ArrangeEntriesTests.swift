import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerFeaturesEntryOperations
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

/// acceptDrop이 emit하는 source/destination/operation을 관찰하기 위한 기록 모델.
private struct EmittedDrop: Equatable {
    var sourcePaths: [String]
    var destinationPath: String
    var isOptionDrag: Bool
}

private final class DropRecorder {
    var emitted: [EmittedDrop] = []
}

private struct DropRecordingReducer: Reducer {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    let recorder: DropRecorder
    var inner: EntryViewLayoutFeature

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        if case let .delegate(.dropItems(sourcePaths, destinationPath, isOptionDrag)) = action {
            recorder.emitted.append(EmittedDrop(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                isOptionDrag: isOptionDrag,
            ))
        }
        return inner.reduce(into: &state, action: action)
    }
}

/// `saveDragPaths`/`loadDragPaths`/`loadDragWithOption`가 공유하는 가변 transport 상태.
private final class DragTransport: @unchecked Sendable {
    var paths: [String]
    var option: Bool

    init(paths: [String] = [], option: Bool = false) {
        self.paths = paths
        self.option = option
    }
}

/// 외부 drop 획득 클라이언트의 begin/cancel 호출을 기록하는 테스트 이중.
private final class ExternalDropAcquisitionRecorder: @unchecked Sendable {
    struct BeginCall {
        var receiverCount: Int
        var dataFlavorCount: Int
        var dataFlavors: [ExternalDropDataFlavor]
        var destination: String
        var forcedCopy: Bool
    }

    var beginCalls: [BeginCall] = []
    var legacyCalls: [LegacyCall] = []
    var deferredCalls: [DeferredCall] = []
    var cancelledSessionIDs: [ExternalDropSessionID] = []
    let sessionID = ExternalDropSessionID(rawValue: "deterministic-grid-session")

    struct LegacyCall {
        var stagedPathCount: Int
        var stagingDirectory: String
        var destination: String
        var forcedCopy: Bool
    }

    struct DeferredCall {
        var items: [ExternalDropDeferredFlavor]
        var destination: String
        var forcedCopy: Bool
    }

    var client: ExternalDropAcquisitionClient {
        var client = ExternalDropAcquisitionClient.testValue
        client.begin = { [self] receivers, dataFlavors, destination, forcedCopy, immediateURLPaths in
            beginCalls.append(BeginCall(
                receiverCount: receivers.count,
                dataFlavorCount: dataFlavors.count,
                dataFlavors: dataFlavors,
                destination: destination,
                forcedCopy: forcedCopy,
            ))
            return ExternalDropAcceptedRequest(
                sessionID: sessionID,
                destination: destination,
                orderedPromisedNames: [],
                promisedOrdinals: [],
                forcedCopy: forcedCopy,
                stagingDirectory: "/tmp/grid-staging",
                immediateURLPaths: immediateURLPaths,
            )
        }
        client.beginLegacy = { [self] stagedPaths, stagingDirectory, destination, forcedCopy in
            legacyCalls.append(LegacyCall(
                stagedPathCount: stagedPaths.count,
                stagingDirectory: stagingDirectory,
                destination: destination,
                forcedCopy: forcedCopy,
            ))
            return ExternalDropAcceptedRequest(
                sessionID: sessionID,
                destination: destination,
                orderedPromisedNames: [],
                promisedOrdinals: [],
                forcedCopy: forcedCopy,
                stagingDirectory: stagingDirectory,
            )
        }
        client.cancel = { [self] sessionID in
            cancelledSessionIDs.append(sessionID)
        }
        client.prepareLegacyStaging = { [self] destinationPath in
            let stagingURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
                .appendingPathComponent(".voyager-external-drop-\(sessionID.rawValue)")
            do {
                try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
                return stagingURL.path
            } catch {
                return nil
            }
        }
        client.finalizeLegacyStaging = { [self] names, expectedCount, stagingDirectory in
            let stagingURL = URL(fileURLWithPath: stagingDirectory, isDirectory: true)
            guard !names.isEmpty, names.count == expectedCount else {
                try? FileManager.default.removeItem(at: stagingURL)
                return nil
            }
            let staged = names.compactMap { name -> String? in
                let url = name.hasPrefix("/")
                    ? URL(fileURLWithPath: name).standardizedFileURL
                    : stagingURL.appendingPathComponent(name).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url.path
            }
            guard staged.count == names.count else {
                try? FileManager.default.removeItem(at: stagingURL)
                return nil
            }
            return staged
        }
        client.beginDeferred = { [self] items, destination, forcedCopy in
            deferredCalls.append(DeferredCall(
                items: items,
                destination: destination,
                forcedCopy: forcedCopy,
            ))
            return ExternalDropAcceptedRequest(
                sessionID: sessionID,
                destination: destination,
                orderedPromisedNames: [],
                promisedOrdinals: [],
                forcedCopy: forcedCopy,
                stagingDirectory: "/tmp/grid-staging",
            )
        }
        return client
    }
}

@MainActor
final class EOP002ArrangeEntriesTests: XCTestCase {
    // MARK: - EOP-002-drop_external_entries_on_directory_page (origin classification)

    /// EOP-002: foreign `draggingSource`(layout source가 아님) + stale transport + external pasteboard → external URL만
    /// emit한다.
    func testExternalDropEmitsOnlyActiveExternalURLWithStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/file.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])

        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: NSObject(),
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, false)
    }

    /// EOP-002 (FIX 1 core regression): `draggingSource == nil` + stale transport + external pasteboard
    /// → stored path를 신뢰하지 않고 active external pasteboard만 source로 사용한다 (Grid).
    func testNilSourceExternalDropIgnoresStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/url.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])

        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, false)
        XCTAssertFalse(recorder.emitted.first?.sourcePaths.contains("/stale/internal") ?? true)
    }

    /// EOP-002 (FIX 1 core regression): `draggingSource == nil` + stale transport + external pasteboard
    /// → stored path를 신뢰하지 않고 active external pasteboard만 source로 사용한다 (List).
    func testNilSourceExternalDropIgnoresStaleTransportList() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/list-url.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(list: list, info: info, item: nil, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/current")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, false)
        XCTAssertFalse(recorder.emitted.first?.sourcePaths.contains("/stale/internal") ?? true)
    }

    /// EOP-002: copy-only source mask와 Option 없음은 copy로 resolve한다.
    func testCopyOnlySourceMaskResolvesCopyWithOptionDrag() {
        let transport = DragTransport(paths: ["/source/file.txt"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let collectionView = NSCollectionView()
        let info = DragInfoFixture(
            source: collectionView,
            operationMask: .copy,
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, collectionView: collectionView)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, ["/source/file.txt"])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, true)
    }

    /// EOP-002: source folder를 자신의 descendant destination으로 drop하면 거부한다.
    func testSourceFolderIntoOwnDescendantDestinationIsRejected() {
        let transport = DragTransport(paths: ["/source/folder"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/source/folder/child"

        let collectionView = NSCollectionView()
        let info = DragInfoFixture(
            source: collectionView,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, collectionView: collectionView)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002: move-allowed mask와 Option 없음은 move로 resolve한다.
    func testMoveAllowedMaskResolvesMoveWithoutOptionDrag() {
        let transport = DragTransport(paths: ["/source/file.txt"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let collectionView = NSCollectionView()
        let info = DragInfoFixture(
            source: collectionView,
            operationMask: .move,
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, collectionView: collectionView)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, ["/source/file.txt"])
        XCTAssertEqual(recorder.emitted.first?.destinationPath, "/destination")
        XCTAssertEqual(recorder.emitted.first?.isOptionDrag, false)
    }

    /// EOP-002: supported + unsupported mixed payload는 원자적으로 전체 거절한다.
    func testMixedPayloadIsAtomicallyRejected() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let externalURL = URL(fileURLWithPath: "/external/mixed.txt")
        let pasteboard = DragInfoFixture.makeMixedPasteboard(
            fileURL: externalURL,
            unsupportedText: "unsupported",
        )
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002: empty payload는 no operation이다.
    func testEmptyPayloadProducesNoOperation() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    /// EOP-002: unsupported-only payload는 no operation이다.
    func testUnsupportedOnlyPayloadProducesNoOperation() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let pasteboard = DragInfoFixture.makeUnsupportedOnlyPasteboard(text: "not a file")
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(accepted)
        XCTAssertTrue(recorder.emitted.isEmpty)
    }

    func testNonFileURLPayloadProducesNoOperation() {
        let pasteboard = DragInfoFixture.makeNonFileURLPasteboard()

        XCTAssertTrue(EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard).isEmpty)
    }

    /// EOP-002 (코멘트 #3826760211): `NSFilenamesPboardType`만 제공하는 드롭이 validate 단계에서
    /// `.copy`를 제안한 뒤 accept가 빈 source로 거절되는 불일치를 회귀 검증한다.
    /// - 검증 내용: legacy filename pasteboard에서 sourcePaths(from:)이 경로를 추출하고,
    ///   Grid acceptDrop이 `.copy`로 수락해 `.dropItems`를 emit한다.
    /// - 사전 조건: `NSFilenamesPboardType`만 노출하는 외부 drop.
    /// - 기대 결과: sourcePaths가 [legacy path], accept true, dropItems에 legacy path가 담긴다.
    func testLegacyFilenameOnlyDropExtractsPathAndAccepts() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let legacyPaths = ["/source/legacy.txt"]

        let pasteboard = DragInfoFixture.makeLegacyFilenamePasteboard(paths: legacyPaths)
        XCTAssertEqual(
            EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard),
            legacyPaths,
            "legacy filename을 경로로 추출해야 한다",
        )

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)
        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, legacyPaths)
        XCTAssertEqual(acquisition.beginCalls.count, 0, "legacy filename-only는 acquisition이 아니라 path 복사여야 한다")
    }

    /// EOP-002: accept-reject terminal path는 stale transport를 정리한다.
    func testAcceptRejectClearsStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: DragInfoFixture.makeFileURLPasteboard(urls: []),
        )

        _ = driveGridAccept(grid: grid, info: info, transport: transport)

        XCTAssertFalse(store.state.isDropTargeted)
        XCTAssertTrue(recorder.emitted.isEmpty)
        XCTAssertTrue(transport.paths.isEmpty)
    }

    /// EOP-002: cancel terminal path는 stale transport를 정리한다.
    func testCancelClearsStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let store = makeStore(transport: transport, recorder: DropRecorder())
        let grid = EntryGridCoordinator(store: store)
        store.send(.view(.setDropTargeted(true)))

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            grid.collectionView(NSCollectionView(), draggingSession: .init(), endedAt: .zero, dragOperation: [])
        }

        XCTAssertFalse(store.state.isDropTargeted)
    }

    /// EOP-002 (FIX 7): 외부 session 진입(List validateDrop)은 stale transport를 정리해 다음 session 격리를 보장한다.
    func testExternalEntryClearsStaleTransport() {
        let transport = DragTransport(paths: ["/stale/internal"])
        let store = makeStore(transport: transport, recorder: DropRecorder(), currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let externalURL = URL(fileURLWithPath: "/external/entry.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            _ = list.outlineView(NSOutlineView(), validateDrop: info, proposedItem: nil, proposedChildIndex: 0)
        }

        XCTAssertTrue(
            transport.paths.isEmpty,
            "외부 session 진입 시 stale transport를 무효화해야 한다",
        )
    }

    // MARK: - EOP-002-drop_external_entries_on_directory_page (destination routing + parity)

    /// EOP-002: blank target은 Grid/List 모두 currentPath로 route한다.
    func testBlankDestinationRoutingMatchesGridAndList() throws {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/blank.txt")

        let gridEmit = try driveGridAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: nil,
            externalURL: externalURL,
        )
        let listEmit = try driveListAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: nil,
            externalURL: externalURL,
        )

        XCTAssertEqual(gridEmit.sourcePaths, listEmit.sourcePaths)
        XCTAssertEqual(gridEmit.destinationPath, "/current")
        XCTAssertEqual(gridEmit.destinationPath, listEmit.destinationPath)
        XCTAssertEqual(gridEmit.isOptionDrag, listEmit.isOptionDrag)
    }

    /// EOP-002: Directory Entry target은 Grid/List 모두 entry.fullPath로 route한다.
    func testDirectoryDestinationRoutingMatchesGridAndList() throws {
        let transport = DragTransport(paths: [])
        let externalURL = URL(fileURLWithPath: "/external/folder-drop.txt")

        let gridEmit = try driveGridAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: "/dest/folder",
            externalURL: externalURL,
        )
        let listEmit = try driveListAccept(
            transport: transport,
            currentPath: "/current",
            itemPath: "/dest/folder",
            externalURL: externalURL,
        )

        XCTAssertEqual(gridEmit.sourcePaths, listEmit.sourcePaths)
        XCTAssertEqual(gridEmit.destinationPath, "/dest/folder")
        XCTAssertEqual(gridEmit.destinationPath, listEmit.destinationPath)
        XCTAssertEqual(gridEmit.isOptionDrag, listEmit.isOptionDrag)
    }

    /// EOP-002: package directory는 destination에서 제외해 currentPath로 route한다.
    func testPackageDirectoryIsExcludedFromListDestination() {
        let transport = DragTransport(paths: [])
        let recorder = DropRecorder()
        let externalURL = URL(fileURLWithPath: "/external/pkg.txt")
        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let list = EntryListCoordinator(store: store)

        let folderEntry = makePackageFolder(id: "/pkg.app")
        let outlineItem = EntryListCoordinator.OutlineItem(kind: .entry(folderEntry))
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(list: list, info: info, item: outlineItem, transport: transport)

        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        XCTAssertEqual(recorder.emitted.first?.sourcePaths, [externalURL.path])
        XCTAssertEqual(
            recorder.emitted.first?.destinationPath,
            "/current",
            "package directory는 destination으로 route하지 않아야 한다",
        )
    }

    // MARK: - EOP-002-import_external_objects (promise-first logical-item negotiation)

    /// 검증 내용: promise-only pasteboard는 하나의 promised ordinal을 산출하고 즉시 descriptor가 없다.
    /// 사전 조건: 외부 drag가 file promise만 제공한다.
    /// 기대 결과: negotiation이 `promisedOrdinals == [0]`, descriptor 0개, acceptable logical item 1개를 반환한다.
    func testPromiseOnlyNegotiationYieldsPromisedOrdinal() {
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertEqual(negotiation.promisedOrdinals, [0])
        XCTAssertTrue(negotiation.immediateURLDescriptors.isEmpty)
        XCTAssertEqual(negotiation.acceptableLogicalItemCount, 1)
    }

    /// 검증 내용: URL-only pasteboard는 즉시 descriptor를 순서대로 보존하고 promised ordinal이 없다.
    /// 사전 조건: 외부 drag가 즉시 file URL만 제공한다.
    /// 기대 결과: 기존 `sourcePaths(from:)` 순서/dedup 계약대로 descriptor가 보존된다.
    func testURLOnlyNegotiationPreservesImmediateDescriptors() {
        let first = URL(fileURLWithPath: "/external/a.txt")
        let second = URL(fileURLWithPath: "/external/b.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [first, second])

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertEqual(
            negotiation.immediateURLDescriptors.map(\.path),
            [first.standardizedFileURL.path, second.standardizedFileURL.path],
        )
        XCTAssertTrue(negotiation.promisedOrdinals.isEmpty)
        XCTAssertEqual(negotiation.acceptableLogicalItemCount, 2)
    }

    /// 검증 내용: 같은 logical item이 promise와 file URL을 함께 제공하면 promise가 선택되고 중복하지 않는다.
    /// 사전 조건: pasteboard item 하나에 promise type과 file URL이 함께 있다 (cloud 파일 재현).
    /// 기대 결과: promise가 우선해 promised ordinal 1개만 있고 즉시 descriptor는 없다.
    func testPromisePlusURLSameItemChoosesPromiseWithoutDuplicate() {
        let fileURL = URL(fileURLWithPath: "/external/cloud.txt")
        let pasteboard = DragInfoFixture.makePromiseFileURLSameItemPasteboard(fileURL: fileURL)

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertEqual(negotiation.promisedOrdinals, [0])
        XCTAssertTrue(negotiation.immediateURLDescriptors.isEmpty)
        XCTAssertEqual(negotiation.acceptableLogicalItemCount, 1)
    }

    /// 검증 내용: URL과 promise가 섞인 distinct ordered batch의 순서가 보존된다.
    /// 사전 조건: [URL-A, Promise-B, URL-C] 순서의 external pasteboard.
    /// 기대 결과: descriptor 순서 [A, C], promised ordinal [1]로 logical 순서 A,B,C가 보존된다.
    func testURLPromiseDistinctBatchPreservesOrderOnGridAndList() {
        let urlA = URL(fileURLWithPath: "/external/a.txt")
        let urlC = URL(fileURLWithPath: "/external/c.txt")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-batch-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([urlA as NSURL])
        pasteboard.writeObjects([
            NSFilePromiseProvider(
                fileType: UTType.plainText.identifier,
                delegate: FilePromiseProviderFixtureDelegate(filename: "b.txt"),
            ),
        ])
        pasteboard.writeObjects([urlC as NSURL])

        // Grid/List가 공유하는 stateless adapter negotiation을 두 경로 모두에 대해 검증한다.
        let gridNegotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )
        let listNegotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertEqual(gridNegotiation, listNegotiation)
        XCTAssertEqual(gridNegotiation.immediateURLDescriptors.map(\.path), [
            urlA.standardizedFileURL.path,
            urlC.standardizedFileURL.path,
        ])
        XCTAssertEqual(gridNegotiation.promisedOrdinals, [1])
    }

    /// 검증 내용: 지원 항목 사이에 unsupported item이 섞이면 전체를 원자적으로 거절한다.
    /// 사전 조건: [fileURL, unsupported text] mixed pasteboard.
    /// 기대 결과: negotiation이 즉시 descriptor도 promised ordinal도 산출하지 않는다.
    func testUnsupportedAmongSupportedIsAtomicallyRejected() {
        let externalURL = URL(fileURLWithPath: "/external/ok.txt")
        let pasteboard = DragInfoFixture.makeMixedPasteboard(fileURL: externalURL, unsupportedText: "unsupported")

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertTrue(negotiation.immediateURLDescriptors.isEmpty)
        XCTAssertTrue(negotiation.promisedOrdinals.isEmpty)
        XCTAssertEqual(negotiation.acceptableLogicalItemCount, 0)
    }

    // MARK: - EOP-002-import_external_objects (universal data-flavor materialization)

    /// 검증 내용: 형식 하드코딩 없이 임의의 UTI(data-flavor)를 가진 외부 drop item이 data 표현으로 수용된다.
    /// 사전 조건: promise/file URL/legacy filename이 없고, 흔치 않은 UTI(public.json, public.vcard)와
    /// 동적 `dyn.` UTI만 노출하는 data-only pasteboard.
    /// 기대 결과: inspection이 각 item을 `.dataFlavor(uti:)`로 수용하고 negotiation이 dataFlavor를 산출한다.
    func testInspectionAcceptsArbitraryUncommonUTIs() {
        let pasteboard = makeDataOnlyPasteboard([
            (uti: "public.json", data: Data(#"{"k":1}"#.utf8)),
            (uti: "public.vcard", data: Data("BEGIN:VCARD".utf8)),
            (uti: "dyn.a8f9b1c2d3e4f5a6b7c8d9e0", data: Data("raw".utf8)),
        ])

        let representations = VoyagerFeaturesEntryOperations.ExternalDropNegotiation
            .inspectExternalDropItems(from: pasteboard)

        XCTAssertNotNil(representations)
        XCTAssertEqual(
            representations?.compactMap { rep -> String? in
                guard case let .dataFlavor(uti) = rep else { return nil }
                return uti
            },
            ["public.json", "public.vcard", "dyn.a8f9b1c2d3e4f5a6b7c8d9e0"],
        )
        XCTAssertTrue(
            VoyagerFeaturesEntryOperations.ExternalDropNegotiation.hasSupportedExternalRepresentation(in: pasteboard),
            "data-only drag는 형식 목록 없이 지원 표현으로 수용되어야 한다",
        )

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )
        XCTAssertEqual(negotiation.dataFlavors.map(\.uti), [
            "public.json",
            "public.vcard",
            "dyn.a8f9b1c2d3e4f5a6b7c8d9e0",
        ])
        XCTAssertEqual(negotiation.dataFlavors.map(\.ordinal), [0, 1, 2])
        XCTAssertEqual(negotiation.acceptableLogicalItemCount, 3)
    }

    /// 검증 내용: promise item과 data-flavor item이 섞여도 inspection이 두 표현을 모두 수용한다.
    /// 사전 조건: [promise, data(json)] 순서의 pasteboard.
    /// 기대 결과: inspection이 `.promisedFile`과 `.dataFlavor`를 순서대로 반환하고
    /// negotiation이 promised ordinal과 dataFlavor를 함께 산출한다.
    func testInspectionMixedPromiseAndDataMaterializesBoth() {
        let pasteboard = makePromiseDataMixedPasteboard(
            promiseCount: 1,
            dataFlavors: [(uti: "public.json", data: Data(#"{"k":2}"#.utf8))],
        )

        let representations = VoyagerFeaturesEntryOperations.ExternalDropNegotiation
            .inspectExternalDropItems(from: pasteboard)

        XCTAssertEqual(representations?.count, 2)
        XCTAssertEqual(representations?.first, .promisedFile)
        guard case let .dataFlavor(uti) = representations?[1] else {
            XCTFail("두 번째 item은 dataFlavor여야 한다")
            return
        }
        XCTAssertEqual(uti, "public.json")

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )
        XCTAssertEqual(negotiation.promisedOrdinals, [0])
        XCTAssertEqual(negotiation.dataFlavors.map(\.ordinal), [1])
        XCTAssertEqual(negotiation.acceptableLogicalItemCount, 2)
    }

    /// 검증 내용: 중복 즉시 경로는 `sourcePaths(from:)` dedup 계약을 유지해 제거한다.
    /// 사전 조건: 같은 경로의 file URL이 pasteboard에 두 번 들어 있다.
    /// 기대 결과: descriptor는 하나만 산출된다.
    func testDuplicateImmediatePathsAreDeduped() {
        let sameURL = URL(fileURLWithPath: "/external/dup.txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [sameURL, sameURL])

        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertEqual(negotiation.immediateURLDescriptors.count, 1)
        XCTAssertEqual(negotiation.immediateURLDescriptors.first?.path, sameURL.standardizedFileURL.path)
    }

    /// 검증 내용: Grid/List view는 `.fileURL` + promise readable types + legacy filenames를 중복 없이
    /// 결정적 순서로 등록한다.
    /// 사전 조건: Grid/List view가 생성된다.
    /// 기대 결과: adapter의 shared list가 결정적 순서·무중복이고, view가 같은 type 집합을 등록하며 `.fileURL`을 유지한다.
    func testGridAndListViewRegisterDraggedTypes() {
        let grid = EntryGridView()
        let list = EntryListView()

        let expected = EntryViewLayoutDropValidationAdapter.registeredDraggedTypes
        // adapter는 결정적 순서·무중복 계약을 보장한다.
        XCTAssertEqual(expected.count, Set(expected).count, "dragged types에 중복이 없어야 한다")
        XCTAssertEqual(expected.first, .fileURL, "`.fileURL`이 첫 번째여야 한다")
        for promiseType in NSFilePromiseReceiver.readableDraggedTypes {
            XCTAssertTrue(
                expected.contains(NSPasteboard.PasteboardType(promiseType)),
                "promise type \(promiseType)을 등록해야 한다",
            )
        }
        XCTAssertTrue(
            expected.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")),
            "legacy filenames type을 등록해야 한다",
        )
        // 데이터 전용 표면(UTType.data + 콘크리트 표준 타입)이 등록되어 있어야 한다.
        XCTAssertTrue(
            expected.contains(NSPasteboard.PasteboardType(UTType.data.identifier)),
            "데이터 전용 드래그를 위해 UTType.data 표면을 등록해야 한다",
        )
        for concrete in [NSPasteboard.PasteboardType.string, .html, .rtf, .tiff, .png, .pdf] {
            XCTAssertTrue(expected.contains(concrete), "데이터 전용 표면 \(concrete.rawValue)을 등록해야 한다")
        }

        // AppKit은 view가 받은 dragged types를 내부 순서로 재정렬하므로 집합 동일성으로 검증한다.
        XCTAssertEqual(Set(grid.collectionView.registeredDraggedTypes), Set(expected))
        XCTAssertEqual(Set(list.tableView.registeredDraggedTypes), Set(expected))
        XCTAssertTrue(grid.collectionView.registeredDraggedTypes.contains(.fileURL))
        XCTAssertTrue(list.tableView.registeredDraggedTypes.contains(.fileURL))
    }

    // MARK: - EOP-002-import_external_objects (validateDrop promise survival)

    /// 검증 내용: promise-only 외부 drag가 Grid `validateDrop`을 통과해 `.copy`를 제안한다.
    /// 사전 조건: 외부 drag가 file promise만 제공한다 (source path 없음).
    /// 기대 결과: validateDrop이 `.copy`를 반환해 acceptDrop이 획득 세션을 시작할 수 있다.
    func testPromiseOnlyGridValidateProposesCopy() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let grid = EntryGridCoordinator(store: store)
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let operation = driveGridValidate(grid: grid, info: info, transport: transport, currentPath: "/current")

        XCTAssertEqual(operation, .copy)
    }

    /// 검증 내용: promise-only 외부 drag가 List `validateDrop`을 통과해 `.copy`를 제안한다.
    /// 사전 조건: 외부 drag가 file promise만 제공한다 (source path 없음).
    /// 기대 결과: validateDrop이 `.copy`를 반환해 acceptDrop이 획득 세션을 시작할 수 있다.
    func testPromiseOnlyListValidateProposesCopy() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current")
        let list = EntryListCoordinator(store: store)
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let operation = driveListValidate(list: list, info: info, transport: transport, currentPath: "/current")

        XCTAssertEqual(operation, .copy)
    }

    /// 검증 내용 (VOY-736 Photos 회귀): 단일 item에 file URL과 promise 표현이 공존하는
    /// 외부 drag(Photos)는 sourcePaths가 비지 않아도 Grid/List `validateDrop`이 획득 경로로
    /// `.copy`를 제안한다.
    /// 사전 조건: 하나의 pasteboard item이 실존 file URL과 promised-file-content-type을 함께 노출한다.
    /// 기대 결과: Grid/List 모두 `.copy`를 반환한다 (path 검증만 거치면 조용히 거부된다).
    @MainActor
    func testFileURLAndPromiseSameItemValidateProposesCopyOnGridAndList() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerPhotosSameItem-\(UUID().uuidString).jpeg")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data("j".utf8)))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-photos-same-item-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(
            fileURL.absoluteString,
            forType: NSPasteboard.PasteboardType("public.file-url"),
        )
        item.setString(
            UTType.jpeg.identifier,
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        pasteboard.writeObjects([item])
        // 사전 조건 검증: sourcePaths가 비지 않아야 한다 (Photos 공존 형태).
        XCTAssertFalse(EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard).isEmpty)

        let info = DragInfoFixture(source: nil, operationMask: [.copy], pasteboard: pasteboard)

        let gridOperation = driveGridValidate(
            grid: EntryGridCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: info,
            transport: DragTransport(),
            currentPath: "/current",
        )
        let listOperation = driveListValidate(
            list: EntryListCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: info,
            transport: DragTransport(),
            currentPath: "/current",
        )

        XCTAssertEqual(gridOperation, .copy)
        XCTAssertEqual(listOperation, .copy)
    }

    // MARK: - EOP-002-import_external_objects (single validate decision entry point)

    /// 검증 내용 (VOY-736): 단일 item에 file URL과 promise 표현이 공존하는 외부 drag(Photos)는
    /// sourcePaths가 비지 않아도 promise 획득 경로가 우선해 `.copy`를 판정한다.
    /// 사전 조건: pasteboard가 실존 file URL과 promised-file-content-type을 함께 노출하고,
    /// `sourcePaths`가 비지 않은 채 `resolveExternalDropOperation`을 호출한다.
    /// 기대 결과: 판정 결과가 `.copy`다.
    @MainActor
    func testResolveExternalDropOperationPrefersPromiseForFileURLCoexistence() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerPhotosEntryPoint-\(UUID().uuidString).jpeg")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data("j".utf8)))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-entrypoint-coexist-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: NSPasteboard.PasteboardType("public.file-url"))
        item.setString(
            UTType.jpeg.identifier,
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        pasteboard.writeObjects([item])
        // 사전 조건 검증: Photos 공존 형태에서 sourcePaths는 비지 않아야 한다.
        XCTAssertFalse(EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard).isEmpty)

        let info = DragInfoFixture(source: nil, operationMask: [.copy], pasteboard: pasteboard)
        let verdict = EntryViewLayoutDropValidationAdapter.resolveExternalDropOperation(
            draggingInfo: info,
            isInternalDrag: false,
            sourcePaths: EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard),
            destinationPath: "/current",
            allowedOperations: info.draggingSourceOperationMask,
            prefersCopy: true,
        )

        XCTAssertEqual(verdict, .copy)
    }

    /// 검증 내용 (VOY-736): 순수 file URL 드래그(Finder)는 promise 표현이 없어 path/operation
    /// 검증을 탄다. option 미사용(move 허용)이면 `.move`로 판정한다.
    /// 사전 조건: 외부 drag가 file URL만 제공하고 `allowedOperations=[.copy,.move]`, `prefersCopy=false`.
    /// 기대 결과: 판정 결과가 `.move`다.
    @MainActor
    func testResolveExternalDropOperationResolvesPureFileURL() {
        let url = URL(fileURLWithPath: "/external/entry-\(UUID().uuidString).txt")
        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [url])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let verdict = EntryViewLayoutDropValidationAdapter.resolveExternalDropOperation(
            draggingInfo: info,
            isInternalDrag: false,
            sourcePaths: EntryViewLayoutDropValidationAdapter.sourcePaths(from: pasteboard),
            destinationPath: "/current",
            allowedOperations: info.draggingSourceOperationMask,
            prefersCopy: false,
        )

        XCTAssertEqual(verdict, .move)
    }

    /// 검증 내용 (VOY-736): 지원하지 않는 항목만 있는 외부 drag는 어떤 표현으로도 수용되지
    /// 않아 `.none`으로 거절한다.
    /// 사전 조건: 외부 drag가 file-url 타입만 노출하되 유효한 파일 URL이 아닌 item만 제공한다.
    /// 기대 결과: 판정 결과가 `.none`이다.
    @MainActor
    func testResolveExternalDropOperationRejectsUnsupportedRepresentation() {
        let pasteboard = DragInfoFixture.makeUnsupportedOnlyPasteboard(text: "not a file")
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let verdict = EntryViewLayoutDropValidationAdapter.resolveExternalDropOperation(
            draggingInfo: info,
            isInternalDrag: false,
            sourcePaths: [],
            destinationPath: "/current",
            allowedOperations: info.draggingSourceOperationMask,
            prefersCopy: false,
        )

        XCTAssertEqual(verdict, .none)
    }

    /// 검증 내용: promise + file URL이 섞인 동일 외부 drag가 Grid/List `validateDrop`을 통과해 `.copy`를 제안한다.
    /// 사전 조건: 외부 drag가 [fileURL, promise] 순서로 제공한다 (promise item 때문에 source path는 비어 있다).
    /// 기대 결과: Grid/List 모두 `.copy`를 반환한다.
    func testPromiseMixedGridAndListValidateProposesCopy() {
        let url = URL(fileURLWithPath: "/external/a.txt")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-mixed-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.writeObjects([
            NSFilePromiseProvider(
                fileType: UTType.plainText.identifier,
                delegate: FilePromiseProviderFixtureDelegate(filename: "b.txt"),
            ),
        ])

        let gridOperation = driveGridValidate(
            grid: EntryGridCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )
        let listOperation = driveListValidate(
            list: EntryListCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )

        XCTAssertEqual(gridOperation, .copy)
        XCTAssertEqual(listOperation, .copy)
    }

    /// 검증 내용: 지원하지 않는 항목만 있는 외부 drag는 Grid/List `validateDrop`에서 여전히 거절된다.
    /// 사전 조건: 외부 drag가 일반 문자열만 제공한다 (지원 표현 없음).
    /// 기대 결과: Grid/List 모두 빈 operation을 반환한다 (negative boundary 고정).
    func testUnsupportedOnlyExternalDragStillRejectedOnGridAndList() {
        let pasteboard = DragInfoFixture.makeUnsupportedOnlyPasteboard(text: "not a file")

        let gridOperation = driveGridValidate(
            grid: EntryGridCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )
        let listOperation = driveListValidate(
            list: EntryListCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )

        XCTAssertTrue(gridOperation.isEmpty)
        XCTAssertTrue(listOperation.isEmpty)
    }

    // MARK: - EOP-002-import_external_objects (validateDrop data-only surface)

    /// 검증 내용: 텍스트 플레이버만 노출하는 데이터 전용 외부 drag가 Grid/List `validateDrop`을 통과해 `.copy`를 제안한다.
    /// 사전 조건: 외부 drag가 `public.utf8-plain-text`만 제공한다 (promise/file URL 없음).
    /// 기대 결과: Grid/List 모두 `.copy`를 반환해 acceptDrop이 materialization을 시작할 수 있다.
    func testDataOnlyTextGridAndListValidateProposesCopy() {
        let pasteboard = makeDataOnlyPasteboard([(uti: "public.utf8-plain-text", data: Data("cell value".utf8))])

        let gridOperation = driveGridValidate(
            grid: EntryGridCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )
        let listOperation = driveListValidate(
            list: EntryListCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )

        XCTAssertEqual(gridOperation, .copy)
        XCTAssertEqual(listOperation, .copy)
    }

    /// 검증 내용: Numbers 셀 드래그 조합(텍스트 + iWork 네이티브 UTI)이 Grid/List `validateDrop`을 통과해 `.copy`를 제안한다.
    /// 사전 조건: 외부 drag가 `public.utf8-plain-text`(셀 값)와 `com.apple.iWork.TSPNativeData`를 같은 item으로 노출한다.
    /// 기대 결과: Grid/List 모두 `.copy`를 반환하고, text 계열 flavor가 materialization 후보로 우선된다.
    func testNumbersCellDataOnlyGridAndListValidateProposesCopy() {
        let pasteboard = makeDataOnlyPasteboard([
            (
                uti: "com.apple.iWork.TSPNativeData",
                data: Data([0x01, 0x02, 0x03]),
            ),
            (
                uti: "public.utf8-plain-text",
                data: Data("2024-06-12 08:00:000".utf8),
            ),
        ])

        let gridOperation = driveGridValidate(
            grid: EntryGridCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )
        let listOperation = driveListValidate(
            list: EntryListCoordinator(store: makeStore(
                transport: DragTransport(),
                recorder: DropRecorder(),
                currentPath: "/current",
            )),
            info: DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard),
            transport: DragTransport(),
            currentPath: "/current",
        )

        XCTAssertEqual(gridOperation, .copy)
        XCTAssertEqual(listOperation, .copy)
    }

    // MARK: - EOP-002-import_external_objects (Grid promise/mixed acquisition wiring)

    /// 검증 내용: promise-only Grid acceptDrop이 begin으로 획득 세션을 시작하고, path 기반 move를 내지 않으며
    /// pending 세션을 설정한다.
    /// 사전 조건: 외부 drag가 promise만 제공한다.
    /// 기대 결과: accepted가 true이고 begin 1회, dropItems 0회, 외부 drop 세션이 설정된다.
    func testPromiseOnlyGridAcceptStartsAcquisitionSession() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.receiverCount, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.destination, "/destination")
        XCTAssertEqual(acquisition.beginCalls.first?.forcedCopy, true)
        XCTAssertEqual(recorder.emitted.count, 0, "promise 세션은 path 기반 dropItems를 내지 않아야 한다")
        XCTAssertEqual(grid.externalDropSessionController.activeSessionID, acquisition.sessionID)
    }

    /// 검증 내용: data-only 외부 drag의 Grid acceptDrop이 begin으로 data flavor를 넘겨 획득 세션을 시작한다.
    /// 사전 조건: promise/file URL 없이 임의 UTI(data-flavor)만 노출하는 pasteboard.
    /// 기대 결과: accepted가 true이고 begin 1회에 dataFlavorCount가 1이며 receiverCount 0이다.
    func testDataOnlyGridAcceptStartsAcquisitionSession() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = makeDataOnlyPasteboard([(uti: "public.json", data: Data(#"{"k":1}"#.utf8))])

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.dataFlavorCount, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.receiverCount, 0)
        XCTAssertEqual(acquisition.beginCalls.first?.destination, "/destination")
        XCTAssertEqual(acquisition.beginCalls.first?.forcedCopy, true)
        XCTAssertEqual(recorder.emitted.count, 0, "data 세션은 path 기반 dropItems를 내지 않아야 한다")
        XCTAssertEqual(grid.externalDropSessionController.activeSessionID, acquisition.sessionID)
    }

    /// 검증 내용: Numbers 셀 드래그 조합(단일 item에 iWork 네이티브 UTI + 텍스트 플레이버)의
    /// Grid acceptDrop이 begin으로 data flavor를 넘겨 Task 11 materialization으로 흐른다.
    /// 사전 조건: promise/file URL 없이 iWork 네이티브 + 텍스트만 노출하는 Numbers 조합 item.
    /// 기대 결과: accepted가 true이고 begin 1회에 dataFlavorCount가 1이며 receiverCount 0이다.
    func testNumbersCellGridAcceptFlowsThroughDataMaterialization() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = makeNumbersCellPasteboard()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.dataFlavorCount, 1, "Numbers 셀 값(text)이 data flavor로 물리화돼야 한다")
        XCTAssertEqual(acquisition.beginCalls.first?.receiverCount, 0)
        XCTAssertEqual(acquisition.beginCalls.first?.destination, "/destination")
        XCTAssertEqual(acquisition.beginCalls.first?.forcedCopy, true)
        XCTAssertEqual(recorder.emitted.count, 0, "data 세션은 path 기반 dropItems를 내지 않아야 한다")
        XCTAssertEqual(grid.externalDropSessionController.activeSessionID, acquisition.sessionID)
    }

    /// Mail load 클로저 호출을 기록하는 테스트 이중 (Swift 6 Sendable 제약용 클래스).
    private final class MailLoadRecorder: @unchecked Sendable {
        var numericIDs: [Int?] = []
        var messageIDs: [String] = []
    }

    /// Mail message drop의 arrange/act 공통부: recorder client를 주입해
    /// beginExternalDropAcquisition까지 구동하고 관찰 결과를 모은다.
    private struct MailDeferredDrive {
        var info: DragInfoFixture
        var acquisition: ExternalDropAcquisitionRecorder
        var loads: MailLoadRecorder
        var acceptedRequests: [ExternalDropAcceptedRequest]
        var activeSessionID: ExternalDropSessionID?
        var clearCount: Int
        var accepted: Bool
    }

    private func driveMailMessageDeferredAcquisition(
        pasteboard: NSPasteboard,
        source: Data,
        loads: MailLoadRecorder,
        acquisition: ExternalDropAcquisitionRecorder,
    ) -> MailDeferredDrive {
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )
        var activeSessionID: ExternalDropSessionID?
        var acceptedRequests: [ExternalDropAcceptedRequest] = []
        var clearCount = 0
        var client = acquisition.client
        client.loadMailSource = { lookup in
            loads.numericIDs.append(lookup.numericID)
            loads.messageIDs.append(lookup.messageID ?? "")
            return source
        }
        let accepted = EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeSessionID,
            context: .init(
                client: client,
                sendAccepted: { acceptedRequests.append($0) },
                clearDropState: { clearCount += 1 },
            ),
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: "/destination",
        )
        return MailDeferredDrive(
            info: info,
            acquisition: acquisition,
            loads: loads,
            acceptedRequests: acceptedRequests,
            activeSessionID: activeSessionID,
            clearCount: clearCount,
            accepted: accepted,
        )
    }

    /// VOY-736: Mail `message:` drop은 acceptDrop 동기 경로에서 원문을 로드하지 않고
    /// 지연 획득(beginDeferred)으로 넘겨 main thread를 차단하지 않는다.
    func testMailMessageURLMaterializesSourceBeforeBrokenPromise() {
        let acquisition = ExternalDropAcquisitionRecorder()
        let loads = MailLoadRecorder()
        let source = Data("Message-ID: <message-id@example.com>\r\n\r\nBody".utf8)

        let drive = driveMailMessageDeferredAcquisition(
            pasteboard: DragInfoFixture.makeMailMessageURLPromisePasteboard(),
            source: source,
            loads: loads,
            acquisition: acquisition,
        )

        XCTAssertTrue(drive.accepted)
        XCTAssertTrue(loads.numericIDs.isEmpty, "accept 시점에는 원문을 로드하지 않는다")
        XCTAssertEqual(drive.info.enumerateDraggingItemsCallCount, 0)
        XCTAssertEqual(acquisition.legacyCalls.count, 0)
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertEqual(acquisition.deferredCalls.count, 1)
        XCTAssertEqual(acquisition.deferredCalls.first?.destination, "/destination")
        XCTAssertEqual(acquisition.deferredCalls.first?.forcedCopy, true)
        let items = acquisition.deferredCalls.first?.items ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.uti, "com.apple.mail.email")
        XCTAssertEqual(items.first?.filename, "Fwd- hello.eml")
        XCTAssertEqual(URL(fileURLWithPath: items.first?.filename ?? "").pathExtension, "eml")
        XCTAssertEqual(drive.acceptedRequests.count, 1)
        XCTAssertEqual(drive.activeSessionID, acquisition.sessionID)
        XCTAssertEqual(drive.clearCount, 1)

        // 세션 큐에서 실행될 load 클로저가 Mail identity로 원문을 로드한다.
        XCTAssertEqual(items.first?.load(), source)
        XCTAssertEqual(loads.numericIDs, [42])
        XCTAssertEqual(loads.messageIDs, [""])
    }

    /// VOY-736: Automator payload 없는 Mail 메시지 드래그는 `message:` URL의
    /// RFC Message-ID 조회로 폴백되고 파일명은 `public.url-name` 제목으로 파생된다.
    /// - 검증 내용: URL-only pasteboard가 deferred 세션으로 흐르고 조회 키가 messageID-only다.
    /// - 사전 조건: Automator type 없이 `public.url`(message:) + `public.url-name` + promise marker.
    /// - 기대 결과: beginLegacy/begin 없이 beginDeferred 1회, load가 messageID로 원문을 반환하며
    ///   파일명이 url-name 제목 기반 `Fwd- hello.eml`이다.
    func testMailMessageURLOnlyFallsBackToMessageIDLookupAndURLNameSubject() {
        let acquisition = ExternalDropAcquisitionRecorder()
        let loads = MailLoadRecorder()
        let source = Data("Message-ID: <message-id@example.com>\r\n\r\nBody".utf8)

        let drive = driveMailMessageDeferredAcquisition(
            pasteboard: DragInfoFixture.makeMailMessageURLOnlyPasteboard(),
            source: source,
            loads: loads,
            acquisition: acquisition,
        )

        XCTAssertTrue(drive.accepted)
        XCTAssertTrue(loads.numericIDs.isEmpty, "accept 시점에는 원문을 로드하지 않는다")
        XCTAssertEqual(acquisition.legacyCalls.count, 0)
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertEqual(acquisition.deferredCalls.count, 1)
        let items = acquisition.deferredCalls.first?.items ?? []
        XCTAssertEqual(items.first?.filename, "Fwd- hello.eml")

        XCTAssertEqual(items.first?.load(), source)
        XCTAssertEqual(loads.numericIDs, [nil])
        XCTAssertEqual(loads.messageIDs, ["message-id@example.com"])
        XCTAssertEqual(drive.acceptedRequests.count, 1)
        XCTAssertEqual(drive.activeSessionID, acquisition.sessionID)
    }

    /// 검증 내용 (VOY-736 회귀): legacy promise marker가 있고 modern receiver가 열거되지
    /// 않으면 source가 선언한 `namesOfPromisedFilesDropped` 계약으로 직접 물질화한다.
    /// 사전 조건: legacy marker를 노출하지만 receiver 열거 결과가 비고 legacy 호출이 파일을 쓴다.
    /// 기대 결과: 폴백 판정을 위한 receiver 열거 1회 후 beginLegacy만 호출되고 source-owned 파일이 전달된다.
    func testLegacyPromiseWithoutModernReceiversMaterializesViaLegacyContract() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makeLegacyPromiseMailPasteboard()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerLegacyDestination-\(UUID().uuidString)")
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true))
        defer { try? FileManager.default.removeItem(at: destination) }

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = destination.path

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
            namesOfPromisedFiles: { destination in
                let message = destination.appendingPathComponent("message.eml")
                guard FileManager.default.createFile(atPath: message.path, contents: Data("message".utf8)) else {
                    return nil
                }
                return [message.lastPathComponent]
            },
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)

        XCTAssertTrue(accepted)
        XCTAssertEqual(info.enumerateDraggingItemsCallCount, 1, "legacy 폴백 판정을 위해 receiver 열거는 정확히 1회만 한다")
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertEqual(acquisition.legacyCalls.count, 1)
        XCTAssertEqual(acquisition.legacyCalls.first?.stagedPathCount, 1)
        let stagingDirectory = URL(fileURLWithPath: acquisition.legacyCalls.first?.stagingDirectory ?? "")
        XCTAssertEqual(stagingDirectory.deletingLastPathComponent().path, destination.path)
        XCTAssertEqual(acquisition.legacyCalls.first?.destination, destination.path)
        XCTAssertEqual(acquisition.legacyCalls.first?.forcedCopy, true)
        XCTAssertEqual(recorder.emitted.count, 0, "promise 세션은 path 기반 dropItems를 내지 않아야 한다")
        XCTAssertEqual(grid.externalDropSessionController.activeSessionID, acquisition.sessionID)
    }

    /// 검증 내용 (VOY-736 회귀): legacy promise 드롭에 file URL이 섞여 있으면 즉시 URL도
    /// accepted request의 ordered placement plan에 포함된다.
    /// 사전 조건: 즉시 file URL item과 legacy promise marker item이 함께 노출되고 legacy
    /// 호출이 파일을 쓴다.
    /// 기대 결과: beginLegacy만 호출되고 sendAccepted로 전달된 request의 `immediateURLPaths`에
    /// 즉시 file URL이 담긴다.
    @MainActor
    func testLegacyPromiseMixedDropIncludesImmediateURLs() throws {
        let acquisition = ExternalDropAcquisitionRecorder()
        let immediateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerLegacyImmediate-\(UUID().uuidString).txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: immediateURL.path, contents: Data("a".utf8)))
        defer { try? FileManager.default.removeItem(at: immediateURL) }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerLegacyMixedDest-\(UUID().uuidString)")
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true))
        defer { try? FileManager.default.removeItem(at: destination) }

        let pasteboard = DragInfoFixture.makeLegacyMixedPasteboard(fileURL: immediateURL)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: true,
        )
        XCTAssertEqual(negotiation.immediateURLDescriptors.count, 1)
        XCTAssertEqual(negotiation.promisedOrdinals.count, 1)

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy],
            pasteboard: pasteboard,
            namesOfPromisedFiles: { staging in
                let message = staging.appendingPathComponent("message.eml")
                guard FileManager.default.createFile(atPath: message.path, contents: Data("m".utf8)) else {
                    return nil
                }
                return [message.lastPathComponent]
            },
        )

        var acceptedRequests: [ExternalDropAcceptedRequest] = []
        var activeSessionID: ExternalDropSessionID?
        let accepted = EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeSessionID,
            context: .init(
                client: acquisition.client,
                sendAccepted: { acceptedRequests.append($0) },
                clearDropState: {},
            ),
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: destination.path,
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertEqual(acquisition.legacyCalls.count, 1)
        XCTAssertEqual(acceptedRequests.count, 1)
        XCTAssertEqual(acceptedRequests.first?.immediateURLPaths, [immediateURL.path])
    }

    /// 검증 내용 (VOY-736 리뷰): legacy promised-file 폴백에서 source가 negotiated promised
    /// item 수보다 많은 이름을 반환해도 거절한다. negotiation이 확정한 cardinality와
    /// 반환 수가 일치해야 하며, 초과 반환은 일부 항목 누락 징후로 간주해 staging을
    /// 정리하고 drop 전체를 거절한다.
    /// 사전 조건: legacy pasteboard(promised item 1개)에서 namesOfPromisedFiles가 파일
    /// 2개를 staging에 쓰고 이름 2개를 반환한다.
    /// 기대 결과: accepted == false, legacy begin 호출 없음, staging 제거됨.
    @MainActor
    func testLegacyPromiseOverReportedNamesRejectsEntireDrop() {
        let acquisition = ExternalDropAcquisitionRecorder()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerLegacyOverReport-\(UUID().uuidString)")
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true))
        defer { try? FileManager.default.removeItem(at: destination) }

        let pasteboard = DragInfoFixture.makeLegacyMixedPasteboard(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerLegacyImmediate-\(UUID().uuidString).txt"))
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: true,
        )
        XCTAssertEqual(negotiation.promisedOrdinals.count, 1)

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy],
            pasteboard: pasteboard,
            namesOfPromisedFiles: { staging in
                let first = staging.appendingPathComponent("first.eml")
                let second = staging.appendingPathComponent("second.eml")
                guard FileManager.default.createFile(atPath: first.path, contents: Data("1".utf8)),
                      FileManager.default.createFile(atPath: second.path, contents: Data("2".utf8))
                else {
                    return nil
                }
                return ["first.eml", "second.eml"]
            },
        )

        var acceptedRequests: [ExternalDropAcceptedRequest] = []
        var activeSessionID: ExternalDropSessionID?
        let accepted = EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeSessionID,
            context: .init(
                client: acquisition.client,
                sendAccepted: { acceptedRequests.append($0) },
                clearDropState: {},
            ),
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: destination.path,
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(acquisition.legacyCalls.count, 0)
        XCTAssertTrue(acceptedRequests.isEmpty)
        XCTAssertNil(activeSessionID)
    }

    /// 검증 내용 (VOY-736 회귀): 혼합 drop의 즉시 file URL이 canonical 검증을 통과하지
    /// 못하면(예: destination 자체를 복사하려는 경우) drop 전체를 거절한다.
    /// 사전 조건: promise item과 destination 디렉터리 자체를 가리키는 즉시 file URL item.
    /// 기대 결과: 드롭이 거절되고 어떤 acquisition 세션도 시작되지 않는다.
    @MainActor
    func testMixedDropImmediateURLFailingContainmentRejectsEntireDrop() {
        let acquisition = ExternalDropAcquisitionRecorder()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerMixedContainment-\(UUID().uuidString)")
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true))
        defer { try? FileManager.default.removeItem(at: destination) }

        // 즉시 URL이 destination 자체 → 자기 하위 복사가 되므로 resolver가 거절한다.
        let pasteboard = DragInfoFixture.makePromisePlusFileURLPasteboard(fileURL: destination)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: true,
        )
        XCTAssertEqual(negotiation.promisedOrdinals.count, 1)
        XCTAssertEqual(negotiation.immediateURLDescriptors.count, 1)

        let info = DragInfoFixture(source: nil, operationMask: [.copy], pasteboard: pasteboard)
        var acceptedRequests: [ExternalDropAcceptedRequest] = []
        var activeSessionID: ExternalDropSessionID?
        let accepted = EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeSessionID,
            context: .init(
                client: acquisition.client,
                sendAccepted: { acceptedRequests.append($0) },
                clearDropState: {},
            ),
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: destination.path,
        )

        XCTAssertFalse(accepted)
        XCTAssertNil(activeSessionID)
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertTrue(acceptedRequests.isEmpty)
    }

    /// 검증 내용 (VOY-736 회귀): legacy promise가 promised 이름 중 일부만 물리화하면
    /// 나머지로 세션을 성공시키지 않고 staging을 정리한 뒤 전체 drop을 거절한다.
    /// 사전 조건: namesOfPromisedFilesDropped가 이름 2개를 반환하지만 파일 1개만 쓴다.
    /// 기대 결과: 드롭이 거절되고 beginLegacy/accepted 세션은 시작되지 않는다.
    @MainActor
    func testLegacyPromisePartialMaterializationRejectsEntireDrop() {
        let acquisition = ExternalDropAcquisitionRecorder()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerLegacyPartial-\(UUID().uuidString)")
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true))
        defer { try? FileManager.default.removeItem(at: destination) }

        let pasteboard = DragInfoFixture.makeLegacyPromiseMailPasteboard()
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: true,
        )
        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy],
            pasteboard: pasteboard,
            namesOfPromisedFiles: { staging in
                let message = staging.appendingPathComponent("message.eml")
                guard FileManager.default.createFile(atPath: message.path, contents: Data("m".utf8)) else {
                    return nil
                }
                // promised 2개 중 1개만 실제로 쓴다.
                return [message.lastPathComponent, "missing.eml"]
            },
        )

        var acceptedRequests: [ExternalDropAcceptedRequest] = []
        var activeSessionID: ExternalDropSessionID?
        let accepted = EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeSessionID,
            context: .init(
                client: acquisition.client,
                sendAccepted: { acceptedRequests.append($0) },
                clearDropState: {},
            ),
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: destination.path,
        )

        XCTAssertFalse(accepted)
        XCTAssertNil(activeSessionID)
        XCTAssertEqual(acquisition.legacyCalls.count, 0)
        XCTAssertTrue(acceptedRequests.isEmpty)
        // 부분 물리화로 남은 staging도 정리된다.
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil,
        )) ?? []
        XCTAssertTrue(leftovers.isEmpty, "거절 시 staging 디렉터리가 남으면 안 된다")
    }

    /// 검증 내용 (VOY-736 Photos 회귀): legacy HFS marker를 함께 선언한 modern promise
    /// 드래그(Photos 등)는 receiver가 열거되면 modern 획득 경로로 라우팅된다.
    /// 사전 조건: legacy marker + modern promise type을 노출하고 receiver 열거가 1건 반환한다.
    /// 기대 결과: beginLegacy 없이 begin(modern)만 호출된다.
    func testLegacyMarkerWithEnumeratedReceiverRoutesToModernPromise() {
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makeLegacyPromiseMailPasteboard()
        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
        )
        info.enumeratedReceivers = [NSFilePromiseReceiver()]

        var activeSessionID: ExternalDropSessionID?
        var acceptedRequests: [ExternalDropAcceptedRequest] = []
        var clearCount = 0
        let accepted = EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeSessionID,
            context: .init(
                client: acquisition.client,
                sendAccepted: { acceptedRequests.append($0) },
                clearDropState: { clearCount += 1 },
            ),
            draggingInfo: info,
            negotiation: VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
                from: pasteboard,
                wantsCopy: false,
            ),
            destinationPath: "/destination",
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.legacyCalls.count, 0, "receiver가 열거되면 legacy 폴백으로 가면 안 된다")
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.receiverCount, 1)
        XCTAssertEqual(acceptedRequests.count, 1)
        XCTAssertEqual(activeSessionID, acquisition.sessionID)
        XCTAssertEqual(clearCount, 1)
    }

    /// VOY-736: legacy promise 이행 실패를 잔여 data representation 성공으로 강등하지 않는다.
    /// 사전 조건: legacy marker + `.string`이 있고 receiver는 열거되지 않으며 source가 파일을 쓰지 않는다.
    /// 기대 결과: 드롭이 거절되고 modern/data acquisition 세션은 시작되지 않는다.
    func testLegacyPromiseFailureDoesNotDegradeToResidualData() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makeLegacyPromiseMailPasteboard()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)

        XCTAssertFalse(accepted)
        XCTAssertEqual(info.enumerateDraggingItemsCallCount, 1, "legacy 폴백 판정을 위한 receiver 열거는 정확히 1회만 한다")
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertEqual(acquisition.legacyCalls.count, 0)
        XCTAssertNil(grid.externalDropSessionController.activeSessionID)
    }

    /// 검증 내용: modern receiver가 없는 legacy promise도 이행 실패 시 residual data로 강등하지 않는다.
    /// 사전 조건: receiver 0개 + legacy marker + `.string`이 있고 source가 파일을 쓰지 않는다.
    /// 기대 결과: 드롭이 거절되고 acquisition 세션은 시작되지 않는다.
    func testZeroReceiverLegacyPromiseFailureIsRejected() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makeZeroReceiverLegacyDataPasteboard()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(
            source: nil,
            operationMask: [.copy, .move],
            pasteboard: pasteboard,
            namesOfPromisedFiles: { _ in nil },
        )

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client)

        XCTAssertFalse(accepted)
        XCTAssertEqual(acquisition.legacyCalls.count, 0)
        XCTAssertEqual(acquisition.beginCalls.count, 0)
        XCTAssertEqual(recorder.emitted.count, 0)
        XCTAssertNil(grid.externalDropSessionController.activeSessionID)
    }

    /// 사전 조건: 이미 활성 외부 세션이 있다.
    /// 기대 결과: 두 번째 accept가 false이고 begin은 한 번만 호출된다.
    func testGridPromiseAcceptRejectsDuplicateWhilePending() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))
        XCTAssertEqual(acquisition.beginCalls.count, 1)

        XCTAssertFalse(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))
        XCTAssertEqual(acquisition.beginCalls.count, 1, "pending 동안 중복 accept는 거절되어야 한다")
    }

    /// 검증 내용: teardown이 활성 세션만 정확히 취소한다.
    /// 사전 조건: promise 세션이 시작되어 활성 외부 drop 세션이 설정되어 있다.
    /// 기대 결과: cancel이 해당 sessionID로 정확히 한 번 호출되고 pending이 해제된다.
    func testGridTeardownCancelsOnlyActiveSession() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))

        withDependencies {
            $0.externalDropAcquisitionClient = acquisition.client
        } operation: {
            grid.externalDropSessionController.cancel()
        }

        XCTAssertEqual(acquisition.cancelledSessionIDs, [acquisition.sessionID])
        XCTAssertNil(grid.externalDropSessionController.activeSessionID)
    }

    // MARK: - EOP-002-import_external_objects (List promise/mixed acquisition wiring, parity with Grid)

    /// 검증 내용: promise-only List acceptDrop이 begin으로 획득 세션을 시작하고, path 기반 move를 내지 않으며
    /// pending 세션을 설정한다.
    /// 사전 조건: 외부 drag가 promise만 제공한다.
    /// 기대 결과: accepted가 true이고 begin 1회, dropItems 0회, 외부 drop 세션이 설정된다.
    func testPromiseOnlyListAcceptStartsAcquisitionSession() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let list = EntryListCoordinator(store: store)

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.receiverCount, 1)
        XCTAssertEqual(acquisition.beginCalls.first?.destination, "/current")
        XCTAssertEqual(acquisition.beginCalls.first?.forcedCopy, true)
        XCTAssertEqual(recorder.emitted.count, 0, "promise 세션은 path 기반 dropItems를 내지 않아야 한다")
        XCTAssertEqual(list.externalDropSessionController.activeSessionID, acquisition.sessionID)
    }

    /// 검증 내용: promise/mixed 세션이 pending인 동안 두 번째 List acceptDrop을 거절한다.
    /// 사전 조건: 이미 활성 외부 세션이 있다.
    /// 기대 결과: 두 번째 accept가 false이고 begin은 한 번만 호출된다.
    func testListPromiseAcceptRejectsDuplicateWhilePending() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let list = EntryListCoordinator(store: store)

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 1)

        XCTAssertFalse(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 1, "pending 동안 중복 accept는 거절되어야 한다")
    }

    /// 검증 내용: teardown(current-path change)이 List의 활성 세션만 정확히 취소한다.
    /// 사전 조건: promise 세션이 시작되어 활성 외부 drop 세션이 설정되어 있다.
    /// 기대 결과: cancel이 해당 sessionID로 정확히 한 번 호출되고 pending이 해제된다.
    func testListTeardownCancelsOnlyActiveSession() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let list = EntryListCoordinator(store: store)

        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))

        withDependencies {
            $0.externalDropAcquisitionClient = acquisition.client
        } operation: {
            list.externalDropSessionController.cancel()
        }

        XCTAssertEqual(acquisition.cancelledSessionIDs, [acquisition.sessionID])
        XCTAssertNil(list.externalDropSessionController.activeSessionID)
    }

    /// 검증 내용: promise-only List accept가 Grid와 동일한 획득 요청 형태(강제 copy, destination)를 산출한다.
    /// 사전 조건: blank 및 folder 대상에 대해 같은 promise fixture를 Grid와 List에 각각 드롭한다.
    /// 기대 결과: 두 경로의 begin이 동일한 destination과 forcedCopy를 가진다.
    func testPromiseListAcquisitionMatchesGridForBlankAndFolderTargets() {
        let cases: [(name: String, destination: String)] = [
            ("blank", "/current"),
            ("folder", "/dest/folder"),
        ]

        for testCase in cases {
            let transport = DragTransport()
            let recorder = DropRecorder()
            let acquisition = ExternalDropAcquisitionRecorder()
            let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

            let gridStore = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
                $0.externalDropAcquisitionClient = acquisition.client
            }
            let grid = EntryGridCoordinator(store: gridStore)
            grid.validatedDropDestinationPath = testCase.destination
            let gridInfo = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

            let listStore = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
                $0.externalDropAcquisitionClient = acquisition.client
            }
            let list = EntryListCoordinator(store: listStore)
            let listInfo = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)
            let listItem: Any? = testCase.destination == "/current" ? nil : EntryListCoordinator.OutlineItem(
                kind: .entry(EntryModel.temporaryFolder(id: testCase.destination, name: "folder")),
            )

            XCTAssertTrue(driveGridAccept(
                grid: grid,
                info: gridInfo,
                transport: transport,
                acquisition: acquisition.client,
            ))
            XCTAssertTrue(driveListAccept(
                list: list,
                info: listInfo,
                item: listItem,
                transport: transport,
                acquisition: acquisition.client,
            ))

            XCTAssertEqual(acquisition.beginCalls.count, 2, "\(testCase.name) 대상 begin 2회")
            let gridCall = acquisition.beginCalls[0]
            let listCall = acquisition.beginCalls[1]
            XCTAssertEqual(gridCall.destination, listCall.destination, "\(testCase.name) destination parity")
            XCTAssertEqual(gridCall.destination, testCase.destination)
            XCTAssertEqual(gridCall.forcedCopy, listCall.forcedCopy, "\(testCase.name) forcedCopy parity")
            XCTAssertTrue(gridCall.forcedCopy, "\(testCase.name) 대상은 강제 copy여야 한다")
        }
    }

    /// 검증 내용: promise-only List accept가 package directory 대상이면 currentPath로 fallback한다.
    /// 사전 조건: promise drag를 package directory entry에 drop한다.
    /// 기대 결과: begin destination이 currentPath이고 forcedCopy가 true다.
    func testListPromisePackageTargetFallsBackToCurrentPath() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let list = EntryListCoordinator(store: store)

        let pkgEntry = makePackageFolder(id: "/pkg.app")
        let outlineItem = EntryListCoordinator.OutlineItem(kind: .entry(pkgEntry))
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(
            list: list,
            info: info,
            item: outlineItem,
            transport: transport,
            acquisition: acquisition.client,
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(
            acquisition.beginCalls.first?.destination,
            "/current",
            "package directory는 destination으로 route하지 않아야 한다",
        )
        XCTAssertEqual(acquisition.beginCalls.first?.forcedCopy, true)
    }

    // MARK: - EOP-002-import_external_objects (repeated-drop after terminal)

    /// 검증 내용: Grid에서 성공 종단 후 같은 폴더의 다음 promise drop이 다시 수락된다 (F2 P0).
    /// 사전 조건: promise 세션이 성공(.succeeded)으로 종료된다.
    /// 기대 결과: 활성 세션이 해제되고 두 번째 accept가 true이며 begin이 2회다.
    func testGridRepeatedPromiseDropAcceptedAfterTerminalSuccess() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(grid.externalDropSessionController.activeSessionID, acquisition.sessionID)

        // reducer로 종단 성공을 구동하면 activeExternalDrop이 nil이 된다.
        let previousActive = store.state.entryOperations.activeExternalDrop
        XCTAssertNotNil(previousActive)
        store.send(.entryOperations(.externalDrop(.event(.succeeded(acquisition.sessionID)))))
        XCTAssertNil(store.state.entryOperations.activeExternalDrop)

        // coordinator render-loop 전이 관찰: 세션 ID 해제.
        grid.externalDropSessionController.handleSessionTerminal(
            previousActive: previousActive,
            currentActive: store.state.entryOperations.activeExternalDrop,
        )
        XCTAssertNil(grid.externalDropSessionController.activeSessionID)

        XCTAssertTrue(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))
        XCTAssertEqual(acquisition.beginCalls.count, 2, "종단 후 두 번째 accept는 다시 수락되어야 한다")
    }

    /// 검증 내용: Grid에서 실패 종단 후 같은 폴더의 다음 promise drop이 다시 수락된다 (F2 P0).
    /// 사전 조건: promise 세션이 실패(.failed)로 종료된다.
    /// 기대 결과: 활성 세션이 해제되고 두 번째 accept가 true다.
    func testGridRepeatedPromiseDropAcceptedAfterTerminalFailure() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = "/destination"
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))
        let previousActive = store.state.entryOperations.activeExternalDrop
        XCTAssertNotNil(previousActive)

        store.send(.entryOperations(.externalDrop(.event(.failed(acquisition.sessionID, .callbackError)))))
        XCTAssertNil(store.state.entryOperations.activeExternalDrop)

        grid.externalDropSessionController.handleSessionTerminal(
            previousActive: previousActive,
            currentActive: store.state.entryOperations.activeExternalDrop,
        )
        XCTAssertNil(grid.externalDropSessionController.activeSessionID)

        XCTAssertTrue(driveGridAccept(grid: grid, info: info, transport: transport, acquisition: acquisition.client))
        XCTAssertEqual(acquisition.beginCalls.count, 2, "실패 종단 후 두 번째 accept는 다시 수락되어야 한다")
    }

    /// 검증 내용: List에서 성공 종단 후 같은 폴더의 다음 promise drop이 다시 수락된다 (F2 P0).
    /// 사전 조건: promise 세션이 성공(.succeeded)으로 종료된다.
    /// 기대 결과: 활성 세션이 해제되고 두 번째 accept가 true다.
    func testListRepeatedPromiseDropAcceptedAfterTerminalSuccess() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let list = EntryListCoordinator(store: store)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertEqual(list.externalDropSessionController.activeSessionID, acquisition.sessionID)

        let previousActive = store.state.entryOperations.activeExternalDrop
        XCTAssertNotNil(previousActive)
        store.send(.entryOperations(.externalDrop(.event(.succeeded(acquisition.sessionID)))))
        XCTAssertNil(store.state.entryOperations.activeExternalDrop)

        list.externalDropSessionController.handleSessionTerminal(
            previousActive: previousActive,
            currentActive: store.state.entryOperations.activeExternalDrop,
        )
        XCTAssertNil(list.externalDropSessionController.activeSessionID)

        XCTAssertTrue(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 2, "종단 후 두 번째 accept는 다시 수락되어야 한다")
    }

    /// 검증 내용: List에서 실패 종단 후 같은 폴더의 다음 promise drop이 다시 수락된다 (F2 P0).
    /// 사전 조건: promise 세션이 실패(.failed)로 종료된다.
    /// 기대 결과: 활성 세션이 해제되고 두 번째 accept가 true다.
    func testListRepeatedPromiseDropAcceptedAfterTerminalFailure() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()
        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)

        let store = makeStore(transport: transport, recorder: recorder, currentPath: "/current") {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let list = EntryListCoordinator(store: store)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        XCTAssertTrue(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))
        let previousActive = store.state.entryOperations.activeExternalDrop
        XCTAssertNotNil(previousActive)

        store.send(.entryOperations(.externalDrop(.event(.failed(acquisition.sessionID, .callbackError)))))
        XCTAssertNil(store.state.entryOperations.activeExternalDrop)

        list.externalDropSessionController.handleSessionTerminal(
            previousActive: previousActive,
            currentActive: store.state.entryOperations.activeExternalDrop,
        )
        XCTAssertNil(list.externalDropSessionController.activeSessionID)

        XCTAssertTrue(driveListAccept(
            list: list,
            info: info,
            item: nil,
            transport: transport,
            acquisition: acquisition.client,
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 2, "실패 종단 후 두 번째 accept는 다시 수락되어야 한다")
    }

    // MARK: - EOP-002-import_external_objects (ExternalDropSessionController local lifecycle)

    /// EOP-002-import_external_objects: 종단 전이(non-nil → nil) 후 controller의 local 세션 ID가 해제된다.
    /// controller가 소유한 activeSessionID는 terminal transition 관찰로 nil이 되어야 한다.
    /// - 검증 내용: begin 후 activeSessionID가 설정되고, reducer 종단 후 handleSessionTerminal이 local ID를 nil로 만든다.
    /// - 사전 조건: promise 세션이 시작되어 activeExternalDrop과 controller local ID가 모두 설정되어 있다.
    /// - 기대 결과: handleSessionTerminal 후 controller.activeSessionID가 nil이다.
    func testExternalDropSessionControllerClearsActiveSessionAfterTerminal() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let controller = ExternalDropSessionController(
            store: store,
            clientProvider: { acquisition.client },
            clearDropState: {},
        )

        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertTrue(controller.beginAcquisition(
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: "/destination",
        ))
        XCTAssertEqual(controller.activeSessionID, acquisition.sessionID)

        let previousActive = store.state.entryOperations.activeExternalDrop
        XCTAssertNotNil(previousActive)
        store.send(.entryOperations(.externalDrop(.event(.succeeded(acquisition.sessionID)))))
        XCTAssertNil(store.state.entryOperations.activeExternalDrop)

        controller.handleSessionTerminal(
            previousActive: previousActive,
            currentActive: store.state.entryOperations.activeExternalDrop,
        )
        XCTAssertNil(controller.activeSessionID, "종단 전이 후 local 세션 ID는 해제되어야 한다")
    }

    /// EOP-002-import_external_objects: cancel이 소유한 세션 ID를 정확히 한 번 취소한다.
    /// controller는 자신이 시작한 세션만 취소하고 local ID를 해제해야 한다.
    /// - 검증 내용: cancel recorder가 owned ID를 정확히 1회 수신하고 local ID가 nil이 된다.
    /// - 사전 조건: promise 세션이 시작되어 controller가 세션 ID를 소유한다.
    /// - 기대 결과: cancelledSessionIDs가 [sessionID]이고 activeSessionID가 nil이다.
    func testExternalDropSessionControllerCancelsOwnedSession() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let controller = ExternalDropSessionController(
            store: store,
            clientProvider: { acquisition.client },
            clearDropState: {},
        )

        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertTrue(controller.beginAcquisition(
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: "/destination",
        ))
        XCTAssertEqual(controller.activeSessionID, acquisition.sessionID)

        controller.cancel()

        XCTAssertEqual(acquisition.cancelledSessionIDs, [acquisition.sessionID], "owned 세션은 정확히 1회 취소되어야 한다")
        XCTAssertNil(controller.activeSessionID)
    }

    /// EOP-002-import_external_objects: 같은 store를 보는 두 controller에서 두 번째 begin이 shared state로 차단된다.
    /// shared TCA `activeExternalDrop`이 cross-Grid/List 직렬화의 유일한 owner이므로 두 번째 controller는
    /// adapter/client 호출 전에 false를 반환해야 한다.
    /// - 검증 내용: controller A begin 성공 후 controller B begin이 false이고 acquisition client begin count가 1로 유지된다.
    /// - 사전 조건: 두 controller가 같은 TestStore(store)를 공유한다.
    /// - 기대 결과: controller B의 begin이 client 호출 없이 false이며 activeSessionID가 nil이다.
    func testExternalDropSessionControllerRejectsSecondBeginFromSharedActiveState() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        let controllerA = ExternalDropSessionController(
            store: store,
            clientProvider: { acquisition.client },
            clearDropState: {},
        )
        let controllerB = ExternalDropSessionController(
            store: store,
            clientProvider: { acquisition.client },
            clearDropState: {},
        )

        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertTrue(controllerA.beginAcquisition(
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: "/destination",
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 1)
        XCTAssertNotNil(store.state.entryOperations.activeExternalDrop, "첫 begin이 shared state를 채워야 한다")

        XCTAssertFalse(controllerB.beginAcquisition(
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: "/destination",
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 1, "두 번째 begin은 shared state 차단으로 client 호출 없이 false여야 한다")
        XCTAssertNil(controllerB.activeSessionID)
    }

    /// 검증 내용: placement(획득 후 destination 복사)가 진행 중이면 두 번째 외부 드롭을
    /// accept 단계에서 거절한다. 복사 중인 세션은 activeExternalDrop이 이미 nil이라
    /// shared-active 가드로 막히지 않으므로(코멘트 #3826514660) 별도 가드가 필요하다.
    /// 사전 조건: activeExternalDrop은 nil이고 externalDropImportPlacement는 non-nil이다.
    /// 기대 결과: beginAcquisition이 false를 반환하고 client 호출이 없어야 한다.
    func testExternalDropSessionControllerRejectsSecondBeginDuringPlacement() {
        let transport = DragTransport()
        let recorder = DropRecorder()
        let acquisition = ExternalDropAcquisitionRecorder()

        let store = makeStore(transport: transport, recorder: recorder) {
            $0.externalDropAcquisitionClient = acquisition.client
        }
        // reducer를 통해 placement(복사) 진행 중 상태를 만든다. `.succeeded`가 activeExternalDrop을
        // nil로 만들고, `.applyImport`가 externalDropImportPlacement를 세팅한다.
        let sessionID = ExternalDropSessionID(rawValue: "placement-in-flight")
        store.send(.entryOperations(.externalDrop(.event(.succeeded(sessionID)))))
        store.send(.entryOperations(.externalDrop(.applyImport(ExternalDropImportPlan(
            sessionID: sessionID,
            destination: "/destination",
            forcedCopy: false,
            orderedPromisedNames: ["a.txt"],
            promisedOrdinals: [0],
            receivedFiles: [
                ExternalDropReceivedFile(
                    sessionID: sessionID,
                    itemOrdinal: 1,
                    callbackOrdinal: 1,
                    stagedPath: "/staging/a.txt",
                ),
            ],
            immediateURLPaths: [],
        )))))

        let controller = ExternalDropSessionController(
            store: store,
            clientProvider: { acquisition.client },
            clearDropState: {},
        )

        let pasteboard = DragInfoFixture.makePromiseOnlyPasteboard(count: 1)
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)
        let negotiation = VoyagerFeaturesEntryOperations.ExternalDropNegotiation.negotiateExternalDrop(
            from: pasteboard,
            wantsCopy: false,
        )

        XCTAssertFalse(controller.beginAcquisition(
            draggingInfo: info,
            negotiation: negotiation,
            destinationPath: "/destination",
        ))
        XCTAssertEqual(acquisition.beginCalls.count, 0, "placement 진행 중이면 client 호출 없이 거절해야 한다")
        XCTAssertNil(controller.activeSessionID)
    }
}

// MARK: - Support

@MainActor
private extension EOP002ArrangeEntriesTests {
    func makeStore(
        transport: DragTransport,
        recorder: DropRecorder,
        currentPath: String = "/current",
        additionalDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> StoreOf<EntryViewLayoutFeature> {
        var state = EntryViewLayoutState()
        state.currentPath = currentPath
        return Store(initialState: state) {
            DropRecordingReducer(recorder: recorder, inner: EntryViewLayoutFeature())
        } withDependencies: {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
            $0.entryLoadingClient = EntryLoadingClient.testValue
            additionalDependencies?(&$0)
        }
    }

    func makeFileOpsClient(transport: DragTransport) -> EntryFileOpsClient {
        var client = EntryFileOpsClient.testValue
        client.saveDragPaths = { transport.paths = $0 }
        client.loadDragPaths = { transport.paths }
        client.saveDragWithOption = { transport.option = $0 }
        client.loadDragWithOption = { transport.option }
        // dropItems가 내부로 전파되어 실제 파일 작업을 실행하지 않도록 no-op으로 둔다.
        client.pasteFile = { _, _ in }
        client.moveFile = { _, _ in }
        return client
    }

    func makePackageFolder(id: String) -> EntryModel {
        EntryModel(
            name: URL(fileURLWithPath: id).lastPathComponent,
            fullPath: id,
            isFolder: true,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "app",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Application",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
            isPackage: true,
        )
    }

    @discardableResult
    func driveGridAccept(
        grid: EntryGridCoordinator,
        info: any NSDraggingInfo,
        transport: DragTransport,
        acquisition: ExternalDropAcquisitionClient? = nil,
        collectionView: NSCollectionView = NSCollectionView(),
    ) -> Bool {
        var accepted = false
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
            if let acquisition {
                $0.externalDropAcquisitionClient = acquisition
            }
        } operation: {
            accepted = grid.collectionView(
                collectionView,
                acceptDrop: info,
                indexPath: IndexPath(item: 0, section: 0),
                dropOperation: .on,
            )
        }
        return accepted
    }

    @discardableResult
    func driveListAccept(
        list: EntryListCoordinator,
        info: any NSDraggingInfo,
        item: Any?,
        transport: DragTransport,
        acquisition: ExternalDropAcquisitionClient? = nil,
    ) -> Bool {
        var accepted = false
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
            if let acquisition {
                $0.externalDropAcquisitionClient = acquisition
            }
        } operation: {
            accepted = list.outlineView(NSOutlineView(), acceptDrop: info, item: item, childIndex: 0)
        }
        return accepted
    }

    /// Grid `validateDrop`를 직접 구동해 제안된 drop operation을 반환한다.
    /// 외부 promise drag의 검증 통과 여부(`.copy`)를 확인하는 데 사용한다.
    /// `validateDrop` 내부가 bound `collectionView`(빈 view)를 사용하므로 view를 바인딩한다.
    func driveGridValidate(
        grid: EntryGridCoordinator,
        info: any NSDraggingInfo,
        transport: DragTransport,
        currentPath _: String,
    ) -> NSDragOperation {
        let collectionView = NSCollectionView()
        let boundView = EntryGridView() // weak `grid.view`가 살아 있도록 강한 참조 유지
        grid.view = boundView
        var proposedIndexPath: NSIndexPath? = IndexPath(item: 0, section: 0) as NSIndexPath
        var proposedOperation = NSCollectionView.DropOperation.before
        var result: NSDragOperation = []
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            result = withUnsafeMutablePointer(to: &proposedIndexPath) { indexPathPtr in
                withUnsafeMutablePointer(to: &proposedOperation) { opPtr in
                    grid.collectionView(
                        collectionView,
                        validateDrop: info,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer(indexPathPtr),
                        dropOperation: opPtr,
                    )
                }
            }
        }
        return result
    }

    /// List `validateDrop`를 직접 구동해 제안된 drop operation을 반환한다.
    /// 외부 promise drag의 검증 통과 여부(`.copy`)를 확인하는 데 사용한다.
    func driveListValidate(
        list: EntryListCoordinator,
        info: any NSDraggingInfo,
        transport: DragTransport,
        currentPath _: String,
    ) -> NSDragOperation {
        var result: NSDragOperation = []
        withDependencies {
            $0.entryFileOpsClient = self.makeFileOpsClient(transport: transport)
        } operation: {
            result = list.outlineView(NSOutlineView(), validateDrop: info, proposedItem: nil, proposedChildIndex: 0)
        }
        return result
    }

    func driveGridAccept(
        transport: DragTransport,
        currentPath: String,
        itemPath: String?,
        externalURL: URL,
    ) throws -> EmittedDrop {
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: currentPath)
        let grid = EntryGridCoordinator(store: store)
        grid.validatedDropDestinationPath = itemPath

        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveGridAccept(grid: grid, info: info, transport: transport)
        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        return try XCTUnwrap(recorder.emitted.first)
    }

    func driveListAccept(
        transport: DragTransport,
        currentPath: String,
        itemPath: String?,
        externalURL: URL,
    ) throws -> EmittedDrop {
        let recorder = DropRecorder()
        let store = makeStore(transport: transport, recorder: recorder, currentPath: currentPath)
        let list = EntryListCoordinator(store: store)

        let outlineItem: EntryListCoordinator.OutlineItem?
        if let itemPath {
            let folderEntry = EntryModel.temporaryFolder(id: itemPath, name: (itemPath as NSString).lastPathComponent)
            outlineItem = EntryListCoordinator.OutlineItem(kind: .entry(folderEntry))
        } else {
            outlineItem = nil
        }

        let pasteboard = DragInfoFixture.makeFileURLPasteboard(urls: [externalURL])
        let info = DragInfoFixture(source: nil, operationMask: [.copy, .move], pasteboard: pasteboard)

        let accepted = driveListAccept(list: list, info: info, item: outlineItem, transport: transport)
        XCTAssertTrue(accepted)
        XCTAssertEqual(recorder.emitted.count, 1)
        return try XCTUnwrap(recorder.emitted.first)
    }
}

@MainActor
private extension DragInfoFixture {
    static func makeFileURLPasteboard(urls: [URL]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-\(UUID().uuidString)"))
        pasteboard.clearContents()
        if !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
        }
        return pasteboard
    }

    static func makeMixedPasteboard(fileURL: URL, unsupportedText: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-mixed-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        // `unsupportedText`는 file-url 타입만 노출하되 유효한 파일 URL이 아닌 item으로 만든다.
        // 구조적 타입뿐이므로 data-flavor로도 파일 URL로도 수용되지 않아 원자적 거절을 검증한다.
        let unsupported = NSPasteboardItem()
        unsupported.setData(
            Data(unsupportedText.utf8),
            forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        )
        pasteboard.writeObjects([unsupported])
        return pasteboard
    }

    static func makeUnsupportedOnlyPasteboard(text: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-unsupported-\(UUID().uuidString)"))
        pasteboard.clearContents()
        // file-url 타입만 노출하되 유효한 파일 URL이 아닌 item → 어떤 표현으로도 수용되지 않는다.
        let item = NSPasteboardItem()
        item.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier))
        pasteboard.writeObjects([item])
        return pasteboard
    }

    /// `count`개의 file promise 항목만 가진 pasteboard (실제 파일은 쓰지 않는다).
    static func makePromiseOnlyPasteboard(count: Int) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-promise-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let providers = (0 ..< count).map { index in
            NSFilePromiseProvider(
                fileType: UTType.plainText.identifier,
                delegate: FilePromiseProviderFixtureDelegate(filename: "promise-\(index).txt"),
            )
        }
        pasteboard.writeObjects(providers)
        return pasteboard
    }

    /// promise type과 file URL을 같은 logical item(pasteboard item 하나)에 함께 넣은 pasteboard.
    /// 이는 cloud 파일처럼 promise와 즉시 URL을 동시에 제공하는 item을 재현한다.
    static func makePromiseFileURLSameItemPasteboard(fileURL: URL) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-sameitem-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(
            "promise.txt",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-name"),
        )
        item.setString(
            UTType.plainText.identifier,
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        pasteboard.writeObjects([item])
        return pasteboard
    }

    /// Mail 메시지 드래그의 promise 조합을 재현한다 (probe 실측 타입 문자열 그대로).
    /// `com.apple.pasteboard.promised-file-url` + `promised-file-content-type`을 선언해
    /// `readObjects(forClasses:)`가 NSFilePromiseReceiver 1개(fileNames 빈)를 반환한다
    /// (현대 Mail: receiver는 주되 파일명 메타데이터가 비어 있음, VOY-736).
    static func makeLegacyPromiseMailPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-legacy-mail-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(
            "message.eml",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        )
        item.setString(
            UTType.plainText.identifier,
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        item.setString("Fwd: hello", forType: .string)
        pasteboard.writeObjects([item])
        return pasteboard
    }

    /// 즉시 file URL item과 legacy promise marker item이 섞인 pasteboard.
    /// `[URL-A, legacy-promise-B]` 혼합 드롭을 재현한다 (VOY-736).
    static func makeLegacyMixedPasteboard(fileURL: URL) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-legacy-mixed-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let legacy = NSPasteboardItem()
        legacy.setString(
            "message.eml",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        )
        legacy.setString(
            UTType.plainText.identifier,
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        pasteboard.writeObjects([legacy])
        return pasteboard
    }

    /// promise item과 즉시 file URL item이 섞인 pasteboard.
    /// `[promise-A, URL-B]` 혼합 드롭을 재현한다 (VOY-736).
    static func makePromisePlusFileURLPasteboard(fileURL: URL) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-promise-url-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let provider = NSFilePromiseProvider(
            fileType: UTType.plainText.identifier,
            delegate: FilePromiseProviderFixtureDelegate(filename: "promise-0.txt"),
        )
        pasteboard.writeObjects([provider, fileURL as NSURL])
        return pasteboard
    }

    static func makeMailMessageURLPromisePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-message-url-mail-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(
            "message://%3Cmessage-id@example.com%3E",
            forType: NSPasteboard.PasteboardType("public.url"),
        )
        item.setString("Fwd: hello", forType: NSPasteboard.PasteboardType("public.url-name"))
        if let automatorData = try? PropertyListSerialization.data(
            fromPropertyList: [["id": 42, "subject": "Fwd: hello"]],
            format: .binary,
            options: 0,
        ) {
            item.setData(automatorData, forType: NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeAutomator"))
        }
        item.setString(
            "message.eml",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        )
        item.setString(
            "public.email-message",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        pasteboard.writeObjects([item])
        return pasteboard
    }

    /// Automator payload 없는 Mail 메시지 드래그를 재현한다. `message:` URL identity만
    /// 노출하므로 조회 키가 RFC Message-ID로 폴백되고 파일명은 `public.url-name`에서
    /// 파생된다 (구형 Mail/타 source 대응, VOY-736).
    static func makeMailMessageURLOnlyPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-message-url-only-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(
            "message://%3Cmessage-id@example.com%3E",
            forType: NSPasteboard.PasteboardType("public.url"),
        )
        item.setString("Fwd: hello", forType: NSPasteboard.PasteboardType("public.url-name"))
        item.setString(
            "message.eml",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        )
        item.setString(
            "public.email-message",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        )
        pasteboard.writeObjects([item])
        return pasteboard
    }

    /// receiver 0개 레거시 promised-file 드래그를 재현한다. `promised-file-url`은 선언하되
    /// 값이 파일 promise로 이행되지 않아 `readObjects(forClasses:)`가 0개를 반환하고,
    /// 잔여 `.string` 플레이버만 남긴다. 레거시 data 폴백(receiver 0개)의 사전 조건이다.
    static func makeZeroReceiverLegacyDataPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-zero-recv-legacy-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(
            "not-a-real-promise-url",
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        )
        item.setString("Fwd: hello body", forType: .string)
        pasteboard.writeObjects([item])
        return pasteboard
    }

    static func makeNonFileURLPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-non-file-url-\(UUID().uuidString)"))
        let item = NSPasteboardItem()
        item.setString("https://example.com/not-a-file", forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard
    }

    /// `NSFilenamesPboardType`만 노출하는 legacy filename 드롭 pasteboard를 만든다.
    /// file URL/promise/data flavor는 노출하지 않아 sourcePaths(from:)이 legacy filename
    /// 문자열을 경로로 추출하는지 검증하는 데 쓴다 (코멘트 #3826760211).
    static func makeLegacyFilenamePasteboard(paths: [String]) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-legacy-filename-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setPropertyList(paths, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        return pasteboard
    }
}
