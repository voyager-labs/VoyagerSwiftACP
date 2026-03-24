import AppKit
import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryThumbnailFeatureTests: XCTestCase {
    func testRequestThumbnailsDedupesReadyAndInFlightPaths() async {
        let image = NSImage(size: NSSize(width: 1, height: 1))

        let store = TestStore(initialState: {
            var state = EntryThumbnailFeature.State()
            state.readyPaths = ["/ready"]
            state.requestsInFlight = ["/inflight"]
            return state
        }()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.thumbnailGeneratorClient.generateThumbnail = { _, _, _ in image }
        }

        await store.send(.requestThumbnails(paths: ["/ready", "/inflight", "/new", "/new"])) {
            $0.requestsInFlight = ["/inflight", "/new"]
        }
        await store.receive(\.thumbnailsReady) {
            $0.requestsInFlight = ["/inflight"]
            $0.readyPaths = ["/ready", "/new"]
            $0.renderVersion = 1
        }
        await store.finish()
    }

    func testRequestThumbnailsUsesCacheHitWithoutGeneratorCall() async {
        let cachedImage = NSImage(size: NSSize(width: 1, height: 1))
        let generatorCalls = CallCounter()

        let store = TestStore(initialState: EntryThumbnailFeature.State()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.entryThumbnailCacheClient.getThumbnail = { path in
                path == "/cached" ? cachedImage : nil
            }
            $0.thumbnailGeneratorClient.generateThumbnail = { _, _, _ in
                await generatorCalls.increment()
                return nil
            }
        }

        await store.send(.requestThumbnails(paths: ["/cached"])) {
            $0.readyPaths = ["/cached"]
            $0.renderVersion = 1
        }
        await store.finish()

        let callCount = await generatorCalls.value()
        XCTAssertEqual(callCount, 0)
    }

    func testThumbnailGenerationFailureMarksFailedAndClearsInFlight() async {
        let store = TestStore(initialState: EntryThumbnailFeature.State()) {
            EntryThumbnailFeature()
        } withDependencies: {
            $0.thumbnailGeneratorClient.generateThumbnail = { _, _, _ in nil }
        }

        await store.send(.requestThumbnails(paths: ["/broken"])) {
            $0.requestsInFlight = ["/broken"]
        }
        await store.receive(\.thumbnailRequestFailed) {
            $0.requestsInFlight = []
            $0.failedPaths = ["/broken"]
            $0.renderVersion = 1
        }
        await store.finish()
    }
}

private actor CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
