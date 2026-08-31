import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
extension CTM004ContentTabSidebarTests {
    func testClassifierAcceptsFileURLOnlySession() {
        let firstProvider = fileProvider(path: "/first.txt")
        let secondProvider = fileProvider(path: "/second.txt")
        let request = FileManagerSidebarEntryDropRequest(
            target: .fixedLocation("desktop"),
            providers: [firstProvider, secondProvider],
            isOptionDrag: true,
        )

        XCTAssertTrue(FileManagerSidebarEntryDropClassifier.accepts(request.providers))
        XCTAssertEqual(request.target, .fixedLocation("desktop"))
        XCTAssertEqual(request.providers.count, 2)
        XCTAssertIdentical(request.providers[0], firstProvider)
        XCTAssertIdentical(request.providers[1], secondProvider)
        XCTAssertTrue(request.isOptionDrag)
    }

    func testRequestPreservesContentTabIdentity() {
        let contentTabID = ContentTabID()
        let request = FileManagerSidebarEntryDropRequest(
            target: .contentTab(contentTabID),
            providers: [],
            isOptionDrag: false,
        )

        XCTAssertEqual(request.target, .contentTab(contentTabID))
        XCTAssertTrue(request.providers.isEmpty)
        XCTAssertFalse(request.isOptionDrag)
    }

    func testClassifierRejectsEmptyNonFileURLAndMixedSessions() {
        let fileProvider = fileProvider(path: "/file.txt")
        let textProvider = textProvider()

        XCTAssertFalse(FileManagerSidebarEntryDropClassifier.accepts([]))
        XCTAssertFalse(FileManagerSidebarEntryDropClassifier.accepts([textProvider]))
        XCTAssertFalse(FileManagerSidebarEntryDropClassifier.accepts([fileProvider, textProvider]))
    }

    func testContentTabDropTargetUsesDirectoryPageTypeOnly() {
        let directoryID = ContentTabID(rawValue: "directory")
        let collectionID = ContentTabID(rawValue: "collection")
        let directory = ContentTabProjection.ContentTabSidebarItem(
            id: directoryID,
            title: "Directory",
            iconName: "folder",
            targetURL: nil,
            tagColorCode: nil,
            pageType: .directory,
            isActive: false,
            isPinned: false,
        )
        let collection = ContentTabProjection.ContentTabSidebarItem(
            id: collectionID,
            title: "Collection",
            iconName: "rectangle.stack",
            targetURL: URL(fileURLWithPath: "/collection.voycoll"),
            tagColorCode: nil,
            pageType: .collection,
            isActive: false,
            isPinned: false,
        )
        let home = ContentTabProjection.ContentTabSidebarItem(
            id: ContentTabID(rawValue: "home"),
            title: "Home",
            iconName: "house",
            targetURL: nil,
            tagColorCode: nil,
            pageType: .home,
            isActive: false,
            isPinned: false,
        )
        let aiChat = ContentTabProjection.ContentTabSidebarItem(
            id: ContentTabID(rawValue: "ai-chat"),
            title: "Chat",
            iconName: "bubble",
            targetURL: nil,
            tagColorCode: nil,
            pageType: .aiChat,
            isActive: false,
            isPinned: false,
        )

        XCTAssertEqual(
            FileManagerSidebarEntryDropDelegate.target(for: directory),
            .contentTab(directoryID),
        )
        XCTAssertNil(FileManagerSidebarEntryDropDelegate.target(for: collection))
        XCTAssertNil(FileManagerSidebarEntryDropDelegate.target(for: home))
        XCTAssertNil(FileManagerSidebarEntryDropDelegate.target(for: aiChat))
    }

    /// fileURL-only preflight는 provider를 추출하지 않고 hover와 Option proposal을 유지한다.
    func testPreflightUsesConformanceOnlyAndPreservesMoveCopyProposals() {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("desktop")
        let dropTarget = FileManagerSidebarEntryDropTargetBox()
        let delegate = makeDelegate(target: target, dropTarget: dropTarget)
        let info = FileManagerSidebarEntryDropPreflightInfoSpy(
            hasFileURLItems: true,
            hasReorderItems: false,
        )

        XCTAssertTrue(delegate.validateDrop(dropInfo: info))
        delegate.dropEntered(dropInfo: info)
        XCTAssertEqual(dropTarget.value, target)
        XCTAssertEqual(delegate.dropUpdated(dropInfo: info, isOptionDrag: false)?.operation, .move)
        XCTAssertEqual(delegate.dropUpdated(dropInfo: info, isOptionDrag: true)?.operation, .copy)
        XCTAssertEqual(delegate.dropUpdated(dropInfo: info, isOptionDrag: false)?.operation, .move)
        XCTAssertEqual(info.providerExtractionCount, 0)

        delegate.dropExited()
        XCTAssertNil(dropTarget.value)
    }

    /// 복사를 허용하지 않는 휴지통은 Option 입력과 무관하게 move를 제안한다.
    func testTrashPreflightAlwaysProposesMoveEvenWithOption() {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("trash")
        let delegate = makeDelegate(
            target: target,
            dropTarget: FileManagerSidebarEntryDropTargetBox(),
            allowsCopy: false,
        )
        let info = FileManagerSidebarEntryDropPreflightInfoSpy(
            hasFileURLItems: true,
            hasReorderItems: false,
        )

        XCTAssertEqual(
            delegate.dropUpdated(dropInfo: info, isOptionDrag: false)?.operation,
            .move,
        )
        XCTAssertEqual(
            delegate.dropUpdated(dropInfo: info, isOptionDrag: true)?.operation,
            .move,
        )
    }

    /// reorder와 fileURL conformance가 함께 보이는 preflight는 own highlight만 정리한다.
    func testRejectedPreflightClearsHighlightWithoutProviderExtraction() {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("desktop")
        let otherTarget = FileManagerSidebarEntryDropTarget.fixedLocation("downloads")
        let dropTarget = FileManagerSidebarEntryDropTargetBox(target)
        let delegate = makeDelegate(target: target, dropTarget: dropTarget)
        let invalidInfos = [
            FileManagerSidebarEntryDropPreflightInfoSpy(
                hasFileURLItems: false,
                hasReorderItems: false,
            ),
            FileManagerSidebarEntryDropPreflightInfoSpy(
                hasFileURLItems: true,
                hasReorderItems: true,
            ),
        ]

        for info in invalidInfos {
            dropTarget.value = target
            XCTAssertFalse(delegate.validateDrop(dropInfo: info))
            XCTAssertNil(dropTarget.value)

            dropTarget.value = target
            delegate.dropEntered(dropInfo: info)
            XCTAssertNil(dropTarget.value)

            dropTarget.value = target
            XCTAssertEqual(delegate.dropUpdated(dropInfo: info, isOptionDrag: false)?.operation, .forbidden)
            XCTAssertNil(dropTarget.value)
            XCTAssertEqual(info.providerExtractionCount, 0)
        }

        dropTarget.value = otherTarget
        XCTAssertFalse(delegate.validateDrop(dropInfo: invalidInfos[0]))
        XCTAssertEqual(dropTarget.value, otherTarget)
    }

    func testPerformDropQueriesCompleteSessionOnceAndAcceptsNSURLFileProvider() throws {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("desktop")
        let fileProvider = fileProvider(path: "/file.txt")
        let dropTarget = FileManagerSidebarEntryDropTargetBox(target)
        var requests: [FileManagerSidebarEntryDropRequest] = []
        let delegate = makeDelegate(
            target: target,
            dropTarget: dropTarget,
            onDrop: { requests.append($0) },
        )
        let info = FileManagerSidebarEntryDropPerformInfoSpy(providers: [fileProvider])

        XCTAssertTrue(delegate.performDrop(dropInfo: info, isOptionDrag: true))
        XCTAssertNil(dropTarget.value)
        XCTAssertEqual(info.providerExtractionCount, 1)

        info.providers.append(textProvider())
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.target, target)
        XCTAssertEqual(request.providers.count, 1)
        XCTAssertIdentical(request.providers[0], fileProvider)
        XCTAssertTrue(request.isOptionDrag)
    }

    func testPerformDropRejectsEmptyAndNonFileURLSessionsWithoutRequest() {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("desktop")
        let textProvider = textProvider()
        let dropTarget = FileManagerSidebarEntryDropTargetBox()
        var requests: [FileManagerSidebarEntryDropRequest] = []
        let delegate = makeDelegate(
            target: target,
            dropTarget: dropTarget,
            onDrop: { requests.append($0) },
        )
        let invalidSessions = [
            [NSItemProvider](),
            [textProvider],
        ]

        for providers in invalidSessions {
            dropTarget.value = target
            let info = FileManagerSidebarEntryDropPerformInfoSpy(providers: providers)

            XCTAssertFalse(delegate.performDrop(dropInfo: info, isOptionDrag: false))
            XCTAssertNil(dropTarget.value)
            XCTAssertEqual(info.providerExtractionCount, 1)
        }

        XCTAssertTrue(requests.isEmpty)
    }

    func testPerformDropRejectsMixedFileURLAndUnrelatedProviderSession() {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("desktop")
        let fileProvider = fileProvider(path: "/file.txt")
        let textProvider = textProvider()
        var requests: [FileManagerSidebarEntryDropRequest] = []
        let delegate = makeDelegate(
            target: target,
            dropTarget: FileManagerSidebarEntryDropTargetBox(target),
            onDrop: { requests.append($0) },
        )
        let info = FileManagerSidebarEntryDropPerformInfoSpy(
            providers: [fileProvider, textProvider],
        )

        XCTAssertFalse(delegate.performDrop(dropInfo: info, isOptionDrag: false))
        XCTAssertEqual(info.providerExtractionCount, 1)
        XCTAssertTrue(requests.isEmpty)
    }

    func testLifecyclePreservesAnotherEntryHighlight() {
        let target = FileManagerSidebarEntryDropTarget.fixedLocation("desktop")
        let otherTarget = FileManagerSidebarEntryDropTarget.fixedLocation("downloads")
        let dropTarget = FileManagerSidebarEntryDropTargetBox(otherTarget)
        let delegate = makeDelegate(target: target, dropTarget: dropTarget)
        let rejectedInfo = FileManagerSidebarEntryDropPreflightInfoSpy(
            hasFileURLItems: false,
            hasReorderItems: false,
        )

        XCTAssertFalse(delegate.validateDrop(dropInfo: rejectedInfo))
        XCTAssertEqual(dropTarget.value, otherTarget)
        delegate.dropEntered(dropInfo: rejectedInfo)
        XCTAssertEqual(dropTarget.value, otherTarget)
        XCTAssertEqual(
            delegate.dropUpdated(dropInfo: rejectedInfo, isOptionDrag: false)?.operation,
            .forbidden,
        )
        XCTAssertEqual(dropTarget.value, otherTarget)
        delegate.dropExited()
        XCTAssertEqual(dropTarget.value, otherTarget)

        let acceptedInfo = FileManagerSidebarEntryDropPerformInfoSpy(
            providers: [fileProvider(path: "/file.txt")],
        )
        XCTAssertTrue(delegate.performDrop(dropInfo: acceptedInfo, isOptionDrag: false))
        XCTAssertEqual(dropTarget.value, otherTarget)
    }

    func testSidebarReducerPromotesEntryDropRequestExactlyOnce() async {
        let provider = fileProvider(path: "/file.txt")
        let request = FileManagerSidebarEntryDropRequest(
            target: .contentTab(ContentTabID(rawValue: "directory")),
            providers: [provider],
            isOptionDrag: false,
        )
        let store = TestStore(initialState: FileManagerSidebarState()) {
            FileManagerSidebarFeature()
        }

        await store.send(.view(.entryDropRequested(request)))
        await store.receive { action in
            guard case let .delegate(.entryDropRequested(receivedRequest)) = action else {
                return false
            }
            return receivedRequest.target == request.target
                && receivedRequest.providers.count == 1
                && receivedRequest.providers[0] === provider
                && !receivedRequest.isOptionDrag
        }
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: Window는 수용한 copy/move/trash drop에 유한 metadata를 한 번 부여한다.
    /// Sidebar drop의 Product 상관관계가 Content bridge를 우회해도 보존되는지 검증한다.
    /// - 검증 내용: interaction/source/operation ID와 provider 순서, 수용당 ID 1회, invalid target ID 0회
    /// - 사전 조건: visible 일반 위치와 Trash 위치, Option copy와 move 요청, 존재하지 않는 위치 요청
    /// - 기대 결과: 세 수용 route만 `.acceptedCommand`로 감싸지고 모두 `.dragAndDrop` source를 사용함
    func testWindowAcceptedEntryDropsAttachFiniteMetadataOnce() async throws {
        let copyID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000401"))
        let moveID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000402"))
        let trashID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000403"))
        let operationIDs = LockIsolated([copyID, moveID, trashID])
        let fixture = AcceptedEntryDropFixture()
        let providers = [NSItemProvider(), NSItemProvider()]
        let store = TestStore(initialState: fixture.state) {
            FileManagerWindowCommandRoutingReducer()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                record: { _ in },
                makeOperationID: { operationIDs.withValue { $0.removeFirst() } },
            )
        }

        let scenarios = [
            AcceptedEntryDropScenario(fixture.desktop.id, true, copyID, .copyEntries),
            AcceptedEntryDropScenario(fixture.desktop.id, false, moveID, .moveEntries),
            AcceptedEntryDropScenario(fixture.trash.id, true, trashID, .moveEntriesToTrash),
        ]
        for scenario in scenarios {
            await store.send(.sidebar(.delegate(.entryDropRequested(.init(
                target: scenario.target,
                providers: providers,
                isOptionDrag: scenario.isOptionDrag,
            )))))
            await store.receive { action in
                matchesAcceptedDrop(action, scenario: scenario, providers: providers, fixture: fixture)
            }
        }

        await store.send(.sidebar(.delegate(.entryDropRequested(.init(
            target: .fixedLocation("missing"),
            providers: providers,
            isOptionDrag: false,
        )))))
        XCTAssertTrue(operationIDs.value.isEmpty)
        await store.finish()
    }

    /// CTM-004-sidebar_entry_drop_routing: Window-owned Sidebar terminal은 완료 순서대로 정확히 한 번 기록된다.
    /// 수용 역순 완료와 중복 delivery에서도 result/aggregate 상관관계가 흔들리지 않는지 검증한다.
    /// - 검증 내용: success/partial/failure 집계, 역순 operation ID, duplicate terminal 억제
    /// - 사전 조건: copy/move/trash metadata를 가진 세 terminal과 move terminal 중복 delivery
    /// - 기대 결과: Product metric은 trash→move→copy 순서로 각 operation ID당 정확히 하나만 기록됨
    func testWindowSidebarTerminalsRecordReverseOrderAndSuppressDuplicates() async throws {
        let copy = try makeEntryDropCommand("00000000-0000-0000-0000-000000000411", .copyEntries)
        let move = try makeEntryDropCommand("00000000-0000-0000-0000-000000000412", .moveEntries)
        let trash = try makeEntryDropCommand("00000000-0000-0000-0000-000000000413", .moveEntriesToTrash)
        let copyFailure = makeEntryDropRecord(copy, .pasteFileCopy, succeeded: 0, failed: 2)
        let movePartial = makeEntryDropRecord(move, .pasteFileMove, succeeded: 1, failed: 1)
        let trashSuccess = makeEntryDropRecord(trash, .moveToTrash, succeeded: 2, failed: 0)
        let recorder = FileManagerProductMetricRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
        }

        var recordedCommandIDs: Set<UUID> = []
        for record in [trashSuccess, movePartial, copyFailure, movePartial] {
            let inserted = recordedCommandIDs.insert(record.id).inserted
            if inserted {
                await store.send(.internal(.sidebarEntryDrop(.lifecycle(.entryActionCompleted(record))))) {
                    $0.recordedSidebarEntryCommandIDs = recordedCommandIDs
                }
            } else {
                await store.send(.internal(.sidebarEntryDrop(.lifecycle(.entryActionCompleted(record)))))
            }
        }
        await store.finish()

        XCTAssertEqual(recorder.metrics(), [
            entryDropMetric(trash, .success, succeeded: 2, failed: 0),
            entryDropMetric(move, .partial, succeeded: 1, failed: 1),
            entryDropMetric(copy, .failure, succeeded: 0, failed: 2),
        ])
    }

    private struct AcceptedEntryDropScenario {
        let target: FileManagerSidebarEntryDropTarget
        let isOptionDrag: Bool
        let operationID: UUID
        let interaction: EntryInteractionIdentity

        init(_ locationID: String, _ isOptionDrag: Bool, _ operationID: UUID, _ interaction: EntryInteractionIdentity) {
            target = .fixedLocation(locationID)
            self.isOptionDrag = isOptionDrag
            self.operationID = operationID
            self.interaction = interaction
        }
    }

    private struct AcceptedEntryDropFixture {
        let desktop = FileManagerFixedLocationItem(
            id: "desktop",
            title: "Desktop",
            path: "/Desktop",
            iconName: "folder",
            accessibilityLabel: "Desktop",
        )
        let trash = FileManagerFixedLocationItem(
            id: "trash",
            title: "Trash",
            path: "/Trash",
            iconName: "trash",
            accessibilityLabel: "Trash",
            kind: .trash,
        )
        var state: FileManagerFeature.State {
            var state = FileManagerFeature.State()
            state.sidebar.setFixedLocationItems([desktop, trash])
            return state
        }
    }

    private func matchesAcceptedDrop(
        _ action: FileManagerFeature.Action,
        scenario: AcceptedEntryDropScenario,
        providers: [NSItemProvider],
        fixture: AcceptedEntryDropFixture,
    ) -> Bool {
        guard case let .internal(.sidebarEntryDrop(.acceptedCommand(metadata, nestedAction))) = action,
              metadata.id == scenario.operationID,
              metadata.interaction == scenario.interaction,
              metadata.source == .dragAndDrop
        else { return false }
        switch (scenario.interaction, nestedAction) {
        case let (.moveEntriesToTrash, .routing(.handleDropToTrash(receivedProviders))):
            return receivedProviders.elementsEqual(providers, by: { $0 === $1 })
        case let (_, .routing(.handleDrop(receivedProviders, destinationPath, isOptionDrag))):
            return receivedProviders.elementsEqual(providers, by: { $0 === $1 })
                && destinationPath == fixture.desktop.path
                && isOptionDrag == scenario.isOptionDrag
        default:
            return false
        }
    }

    private func makeEntryDropCommand(
        _ id: String,
        _ interaction: EntryInteractionIdentity,
    ) throws -> EntryCommandMetadata {
        try .init(id: XCTUnwrap(UUID(uuidString: id)), interaction: interaction, source: .dragAndDrop)
    }

    private func makeEntryDropRecord(
        _ command: EntryCommandMetadata,
        _ operationKind: OperationKind,
        succeeded: Int,
        failed: Int,
    ) -> EntryActionRecord {
        EntryActionRecord(
            operationKind: operationKind,
            targets: [],
            failedCount: failed,
            cancelledCount: 0,
            succeededCount: succeeded,
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_234_567_890),
        ).attaching(command: command)
    }

    private func entryDropMetric(
        _ command: EntryCommandMetadata,
        _ result: EntryActionResult,
        succeeded: Int,
        failed: Int,
    ) -> FileManagerProductMetric {
        .entryAction(
            result: result,
            identity: command.interaction,
            source: command.source,
            operationID: command.id,
            aggregate: .init(attempted: succeeded + failed, succeeded: succeeded, failed: failed, cancelled: 0),
        )
    }

    private func makeDelegate(
        target: FileManagerSidebarEntryDropTarget,
        dropTarget: FileManagerSidebarEntryDropTargetBox,
        allowsCopy: Bool = true,
        onDrop: @escaping (FileManagerSidebarEntryDropRequest) -> Void = { _ in },
    ) -> FileManagerSidebarEntryDropDelegate {
        FileManagerSidebarEntryDropDelegate(
            dropTarget: Binding(
                get: { dropTarget.value },
                set: { dropTarget.value = $0 },
            ),
            target: target,
            allowsCopy: allowsCopy,
            onDrop: onDrop,
        )
    }

    private func fileProvider(path: String) -> NSItemProvider {
        NSItemProvider(
            item: URL(fileURLWithPath: path) as NSURL,
            typeIdentifier: UTType.fileURL.identifier,
        )
    }

    private func textProvider() -> NSItemProvider {
        NSItemProvider(
            item: "text" as NSString,
            typeIdentifier: UTType.plainText.identifier,
        )
    }
}

private final class FileManagerSidebarEntryDropPreflightInfoSpy: FileManagerSidebarDropPreflightInfo {
    private let conformingTypeIdentifiers: Set<String>
    private(set) var providerExtractionCount = 0

    init(hasFileURLItems: Bool, hasReorderItems: Bool) {
        conformingTypeIdentifiers = Set([
            hasFileURLItems ? UTType.fileURL.identifier : nil,
            hasReorderItems ? UTType.fileManagerTopNavigationReorder.identifier : nil,
        ].compactMap(\.self))
    }

    func hasItemsConforming(to contentTypes: [UTType]) -> Bool {
        contentTypes.contains { conformingTypeIdentifiers.contains($0.identifier) }
    }
}

private final class FileManagerSidebarEntryDropPerformInfoSpy: FileManagerSidebarDropPerformInfo {
    var providers: [NSItemProvider]
    private(set) var providerExtractionCount = 0

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }

    func itemProviders(for _: [UTType]) -> [NSItemProvider] {
        providerExtractionCount += 1
        return providers
    }
}

private final class FileManagerSidebarEntryDropTargetBox {
    var value: FileManagerSidebarEntryDropTarget?

    init(_ value: FileManagerSidebarEntryDropTarget? = nil) {
        self.value = value
    }
}
