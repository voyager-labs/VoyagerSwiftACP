import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
extension FileManagerHostFixturePhaseNotificationTests {
    func testPresetAxesAndStateDataAreDeterministic() {
        XCTAssertEqual(FileManagerHostPreset.allCases.count, 15)
        XCTAssertEqual(FileManagerHostPreset.delayedRootNavigation.scenario.delayedNavigation, .rootNavigation)
        XCTAssertEqual(FileManagerHostPreset.delayedTabSwitch.scenario.delayedNavigation, .tabSwitch)
        XCTAssertEqual(FileManagerHostPreset.permissionDenied.scenario.permission, .denied)
        XCTAssertEqual(FileManagerHostPreset.permissionRetry.scenario.permission, .retry)
        XCTAssertEqual(FileManagerHostPreset.collectionDirectory.scenario.collection, .directory)
        XCTAssertEqual(FileManagerHostPreset.largeFolder1000.scenario.largeFolder, .oneThousand)
        XCTAssertEqual(FileManagerHostPreset.concurrentLargeFolders.scenario.largeFolder, .concurrent)

        let permissionState = FileManagerHostFixture.makeState(preset: .permissionDenied, windowID: UUID())
        XCTAssertEqual(permissionState.content.entryViewLayout.entries.map(\.name), ["Restricted", "Sibling"])

        let collectionState = FileManagerHostFixture.makeState(preset: .collectionDirectory, windowID: UUID())
        XCTAssertTrue(collectionState.content.entryViewLayout.isCollectionMode)
        XCTAssertEqual(collectionState.content.entryViewLayout.collectionItems.count, 3)
        XCTAssertTrue(collectionState.content.entryViewLayout.hierarchy.rootPath.isEmpty)

        let largeState = FileManagerHostFixture.makeState(preset: .largeFolder1000, windowID: UUID())
        XCTAssertEqual(largeState.content.entryViewLayout.entries.map(\.name), ["Large Folder"])
    }

    func testPhaseNotificationDecodesOptionalQAFieldsAndLegacyInitializer() {
        let windowID = UUID()
        let requestID = UUID()
        let notification = Notification(
            name: FileManagerHostFixture.phaseDidChange,
            userInfo: [
                FileManagerHostFixture.phaseUserInfoKey: "coreFinished",
                FileManagerHostFixture.phaseWindowIDUserInfoKey: windowID,
                FileManagerHostFixture.phasePresetUserInfoKey: FileManagerHostPreset.largeFolder1000.rawValue,
                FileManagerHostFixture.phaseRequestIDUserInfoKey: requestID,
                FileManagerHostFixture.phaseErrorCodeUserInfoKey: 0,
                FileManagerHostFixture.phaseRowCountUserInfoKey: 1000,
            ],
        )

        XCTAssertEqual(
            FileManagerHostFixture.phaseNotification(from: notification),
            .init(
                phase: "coreFinished",
                windowID: windowID,
                preset: FileManagerHostPreset.largeFolder1000.rawValue,
                requestID: requestID,
                errorCode: 0,
                rowCount: 1000,
            ),
        )
        XCTAssertEqual(
            FileManagerHostFixture.PhaseNotification(phase: "waiting", windowID: windowID),
            .init(phase: "waiting", windowID: windowID),
        )
    }

    func testLargeFolderFixtureClientEmitsExactlyOneThousandRowsInThirtyTwoBatches() async throws {
        let client = FileManagerHostFixture.makeEntryLoadingClient(preset: .largeFolder1000, windowID: UUID())
        var events: [EntryLoadEvent] = []
        for try await event in client.loadItems(
            URL(fileURLWithPath: "/Fixture/FileManager/Large Folder"),
            false,
            .none,
        ) {
            events.append(event)
        }

        let batches = events.compactMap { event -> (Int, Int)? in
            guard case let .coreBatch(items, batchIndex) = event else { return nil }
            return (items.count, batchIndex)
        }
        XCTAssertEqual(batches.map(\.0).reduce(0, +), 1000)
        XCTAssertEqual(batches.map(\.1), Array(0 ..< 32))
        XCTAssertEqual(events.compactMap { event -> Int? in
            guard case let .coreFinished(batchCount) = event else { return nil }
            return batchCount
        }, [32])
    }

    func testPermissionAndLargeFolderPresetsPreserveRootExpansionEntries() async throws {
        for (preset, expectedNames) in [
            (FileManagerHostPreset.permissionDenied, ["Restricted", "Sibling"]),
            (FileManagerHostPreset.largeFolder1000, ["Large Folder"]),
        ] {
            let client = FileManagerHostFixture.makeEntryLoadingClient(preset: preset, windowID: UUID())
            let events = try await Self.collect(client.loadItems(
                URL(fileURLWithPath: "/Fixture/FileManager"),
                false,
                .none,
            ))

            XCTAssertEqual(events.rowNames, expectedNames)
            XCTAssertEqual(events.coreFinishedBatchCounts, [1])
        }
    }

    func testPermissionDeniedFixtureEmitsCocoaPermissionErrorAndRetrySucceeds() async throws {
        let client = FileManagerHostFixture.makeEntryLoadingClient(preset: .permissionRetry, windowID: UUID())
        let folderURL = URL(fileURLWithPath: "/Fixture/FileManager/Restricted")

        do {
            for try await _ in client.loadItems(folderURL, false, .none) {}
            XCTFail("Expected first permission request to fail")
        } catch {
            XCTAssertEqual((error as NSError).code, NSFileReadNoPermissionError)
        }

        var retryEvents: [EntryLoadEvent] = []
        for try await event in client.loadItems(folderURL, false, .none) {
            retryEvents.append(event)
        }
        XCTAssertEqual(retryEvents.compactMap { event -> Int? in
            guard case let .coreBatch(items, _) = event else { return nil }
            return items.count
        }, [1])
        XCTAssertEqual(retryEvents.compactMap { event -> Int? in
            guard case let .coreFinished(batchCount) = event else { return nil }
            return batchCount
        }, [1])
    }

    func testPermissionDeniedPresetEmitsObservableErrorPhaseMetadata() async throws {
        let windowID = UUID()
        let client = FileManagerHostFixture.makeEntryLoadingClient(preset: .permissionDenied, windowID: windowID)
        let recorder = PhaseRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: FileManagerHostFixture.phaseDidChange,
            object: nil,
            queue: nil,
        ) { notification in
            if let phase = FileManagerHostFixture.phaseNotification(from: notification) {
                recorder.append(phase)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            for try await _ in client.loadItems(
                URL(fileURLWithPath: "/Fixture/FileManager/Restricted"),
                false,
                .none,
            ) {}
            XCTFail("Expected permission-denied preset to fail")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, NSCocoaErrorDomain)
            XCTAssertEqual(error.code, NSFileReadNoPermissionError)
        }

        let phase = try XCTUnwrap(recorder.values().first { $0.phase == "permissionDenied" })
        XCTAssertEqual(phase.windowID, windowID)
        XCTAssertEqual(phase.preset, FileManagerHostPreset.permissionDenied.rawValue)
        XCTAssertEqual(phase.errorCode, NSFileReadNoPermissionError)
        XCTAssertNil(phase.rowCount)
    }

    func testProgressiveFailurePresetStopsAfterFirstBatchAndEmitsFailurePhase() async throws {
        let windowID = UUID()
        let client = FileManagerHostFixture.makeEntryLoadingClient(
            preset: .progressiveEntryLoadingFailure,
            windowID: windowID,
        )
        let recorder = PhaseRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: FileManagerHostFixture.phaseDidChange,
            object: nil,
            queue: nil,
        ) { notification in
            if let phase = FileManagerHostFixture.phaseNotification(from: notification) {
                recorder.append(phase)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        var events: [EntryLoadEvent] = []
        do {
            for try await event in client.loadItems(
                URL(fileURLWithPath: "/Fixture/FileManager/Projects"),
                false,
                .none,
            ) {
                events.append(event)
            }
            XCTFail("Expected progressive failure preset to fail")
        } catch {}

        XCTAssertEqual(events.rowCount, 32)
        XCTAssertFalse(events.contains { if case .coreFinished = $0 { true } else { false } })
        let phase = try XCTUnwrap(recorder.values().first { $0.phase == "partialFailure" })
        XCTAssertEqual(phase.windowID, windowID)
        XCTAssertEqual(phase.preset, FileManagerHostPreset.progressiveEntryLoadingFailure.rawValue)
        XCTAssertEqual(phase.rowCount, 32)
    }

    func testCollectionPresetEmitsStartAndFinishPhaseMetadata() {
        let windowID = UUID()
        let recorder = PhaseRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: FileManagerHostFixture.phaseDidChange,
            object: nil,
            queue: nil,
        ) { notification in
            if let phase = FileManagerHostFixture.phaseNotification(from: notification) {
                recorder.append(phase)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        FileManagerHostFixture.startCollectionScenarioIfNeeded(for: .collectionDirectory, windowID: windowID)

        let phases = recorder.values().filter { $0.windowID == windowID }
        XCTAssertEqual(phases.map(\.phase), ["collectionStarted", "collectionFinished"])
        XCTAssertTrue(phases.allSatisfy { $0.preset == FileManagerHostPreset.collectionDirectory.rawValue })
        XCTAssertEqual(phases.compactMap(\.rowCount), [3, 3])
    }

    func testDelayedNavigationPresetsCancelStaleRequestBeforeFinishingReplacementRequest() async throws {
        for preset in [FileManagerHostPreset.delayedRootNavigation, .delayedTabSwitch] {
            let windowID = UUID()
            let client = FileManagerHostFixture.makeEntryLoadingClient(preset: preset, windowID: windowID)
            let recorder = PhaseRecorder()
            let observer = NotificationCenter.default.addObserver(
                forName: FileManagerHostFixture.phaseDidChange,
                object: nil,
                queue: nil,
            ) { notification in
                if let phase = FileManagerHostFixture.phaseNotification(from: notification) {
                    recorder.append(phase)
                }
            }

            let first = Task {
                try await Self.collect(client.loadItems(
                    URL(fileURLWithPath: "/Fixture/FileManager/Delayed Root"),
                    false,
                    .none,
                ))
            }
            try await Task.sleep(for: .milliseconds(450))
            let second = Task {
                try await Self.collect(client.loadItems(
                    URL(fileURLWithPath: "/Fixture/FileManager/Replacement Root"),
                    false,
                    .none,
                ))
            }
            _ = try await second.value
            _ = try? await first.value
            NotificationCenter.default.removeObserver(observer)

            let phases = recorder.values().filter { $0.preset == preset.rawValue }
            XCTAssertTrue(phases.contains { $0.phase == FileManagerHostFixturePhase.cancelled.rawValue })
            XCTAssertTrue(phases.contains { $0.phase == FileManagerHostFixturePhase.streamFinished.rawValue })
            XCTAssertGreaterThanOrEqual(Set(phases.compactMap(\.requestID)).count, 2)
        }
    }

    func testConcurrentLargeFolderClientsKeepDistinctWindowAndRequestIdentities() async throws {
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstClient = FileManagerHostFixture.makeEntryLoadingClient(
            preset: .concurrentLargeFolders,
            windowID: firstWindowID,
        )
        let secondClient = FileManagerHostFixture.makeEntryLoadingClient(
            preset: .concurrentLargeFolders,
            windowID: secondWindowID,
        )

        let recorder = PhaseRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: FileManagerHostFixture.phaseDidChange,
            object: nil,
            queue: nil,
        ) { notification in
            if let phase = FileManagerHostFixture.phaseNotification(from: notification) {
                recorder.append(phase)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        async let firstEvents = Self.collect(
            firstClient.loadItems(URL(fileURLWithPath: "/Fixture/FileManager/Large Folder"), false, .none),
        )
        async let secondEvents = Self.collect(
            secondClient.loadItems(URL(fileURLWithPath: "/Fixture/FileManager/Large Folder"), false, .none),
        )
        let (first, second) = try await (firstEvents, secondEvents)
        let phases = recorder.values()
        let firstRequestIDs = Set(phases.filter { $0.windowID == firstWindowID }.compactMap(\.requestID))
        let secondRequestIDs = Set(phases.filter { $0.windowID == secondWindowID }.compactMap(\.requestID))

        XCTAssertEqual(first.rowCount, 1000)
        XCTAssertEqual(second.rowCount, 1000)
        XCTAssertNotEqual(firstWindowID, secondWindowID)
        XCTAssertEqual(firstRequestIDs.count, 1)
        XCTAssertEqual(secondRequestIDs.count, 1)
        XCTAssertNotEqual(firstRequestIDs.first, secondRequestIDs.first)
    }

    nonisolated private static func collect(
        _ stream: AsyncThrowingStream<EntryLoadEvent, Error>,
    ) async throws -> [EntryLoadEvent] {
        var events: [EntryLoadEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private extension [EntryLoadEvent] {
    var rowCount: Int {
        reduce(0) { total, event in
            guard case let .coreBatch(items, _) = event else { return total }
            return total + items.count
        }
    }

    var rowNames: [String] {
        flatMap { event -> [String] in
            guard case let .coreBatch(items, _) = event else { return [] }
            return items.map(\.name)
        }
    }

    var coreFinishedBatchCounts: [Int] {
        compactMap { event -> Int? in
            guard case let .coreFinished(batchCount) = event else { return nil }
            return batchCount
        }
    }
}

private final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [FileManagerHostFixture.PhaseNotification] = []

    func append(_ phase: FileManagerHostFixture.PhaseNotification) {
        lock.lock()
        phases.append(phase)
        lock.unlock()
    }

    func values() -> [FileManagerHostFixture.PhaseNotification] {
        lock.lock()
        defer { lock.unlock() }
        return phases
    }
}
