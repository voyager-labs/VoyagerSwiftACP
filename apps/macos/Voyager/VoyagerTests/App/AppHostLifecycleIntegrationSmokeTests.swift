import AppKit
@testable import Voyager
import XCTest

@MainActor
final class AppHostLifecycleIntegrationSmokeTests: XCTestCase {
    func testAutomaticLaunchReachesShellReadinessAndTerminatesOrderly() async throws {
        guard AppHostTestMode.current == .lifecycleIntegration else {
            throw XCTSkip("Runs only from the Voyager-Lifecycle-Smoke scheme")
        }

        let launchEvents = try await waitForEvents([
            .willFinishLaunching,
            .didFinishLaunching,
            .helperStarted,
            .entryCoreHealthChecked,
            .initialWindowOpened,
        ])

        XCTAssertOrdered(.willFinishLaunching, before: .didFinishLaunching, in: launchEvents)
        XCTAssertOrdered(.didFinishLaunching, before: .helperStarted, in: launchEvents)
        XCTAssertOrdered(.didFinishLaunching, before: .entryCoreHealthChecked, in: launchEvents)
        XCTAssertOrdered(.entryCoreHealthChecked, before: .initialWindowOpened, in: launchEvents)

        guard let appDelegate = AppHostLifecycleIntegrationProbe.shared.appDelegate else {
            XCTFail("Voyager AppDelegate is not installed")
            return
        }

        XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateLater)

        let terminationEvents = try await waitForEvents([
            .terminationRequested,
            .terminationReply(true),
        ])
        XCTAssertOrdered(.terminationRequested, before: .terminationReply(true), in: terminationEvents)
    }

    private func waitForEvents(
        _ expected: Set<AppHostLifecycleIntegrationEvent>,
    ) async throws -> [AppHostLifecycleIntegrationEvent] {
        for _ in 0 ..< 500 {
            let events = AppHostLifecycleIntegrationProbe.shared.events
            if expected.isSubset(of: Set(events)) {
                return events
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let events = AppHostLifecycleIntegrationProbe.shared.events
        XCTFail("Timed out waiting for lifecycle integration events. Recorded: \(events)")
        return events
    }

    private func XCTAssertOrdered(
        _ first: AppHostLifecycleIntegrationEvent,
        before second: AppHostLifecycleIntegrationEvent,
        in events: [AppHostLifecycleIntegrationEvent],
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard let firstIndex = events.firstIndex(of: first),
              let secondIndex = events.firstIndex(of: second)
        else {
            XCTFail("Missing ordered events \(first) and/or \(second): \(events)", file: file, line: line)
            return
        }
        XCTAssertLessThan(firstIndex, secondIndex, file: file, line: line)
    }
}
