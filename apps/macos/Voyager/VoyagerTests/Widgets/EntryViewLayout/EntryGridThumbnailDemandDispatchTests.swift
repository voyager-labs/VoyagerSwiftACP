import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryThumbnail
import XCTest

@MainActor
final class EntryGridThumbnailDemandDispatchTests: XCTestCase {
    func testGridVisibleRangeDispatchesThumbnailRequest() {
        var state = EntryViewLayoutState()
        state.entries = [
            makeEntry(path: "/tmp/a.txt"),
            makeEntry(path: "/tmp/b.txt"),
        ]

        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                if case let .entryThumbnail(.requestThumbnails(paths)) = action {
                    state.entryThumbnail.requestsInFlight = Set(paths)
                }
                return .none
            }
        }

        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        view.scrollView.frame = view.bounds
        view.collectionView.frame = NSRect(x: 0, y: 0, width: 640, height: 960)
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        coordinator.rebuildSectionsAndReload()

        coordinator.requestThumbnailsForVisibleArea()

        XCTAssertEqual(store.state.entryThumbnail.requestsInFlight, ["/tmp/a.txt", "/tmp/b.txt"])
    }
}

private func makeEntry(path: String) -> EntryModel {
    let url = URL(fileURLWithPath: path)
    return EntryModel(
        name: url.lastPathComponent,
        fullPath: path,
        isFolder: false,
        isHidden: false,
        size: 1,
        modifiedDate: Date(timeIntervalSince1970: 0),
        fileExtension: url.pathExtension,
        facets: EntryFacets(
            createdDate: Date(timeIntervalSince1970: 0),
            addedDate: Date(timeIntervalSince1970: 0),
            lastOpenedDate: nil,
            kind: "Document",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        ),
    )
}
