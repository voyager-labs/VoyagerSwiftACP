import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import UniformTypeIdentifiers
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
