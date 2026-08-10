import Foundation
@testable import VoyagerHelper
import XCTest

@MainActor
final class HelperStateBroadcasterTests: XCTestCase {
    func testStartStopAndDoubleStopLifecycle() async {
        let center = DistributedNotificationCenter.default()
        let notificationSuffix = UUID().uuidString
        let requestName = Notification.Name("voyagerHelperStateRequest.\(notificationSuffix)")
        let responseName = Notification.Name("voyagerHelperStateDidUpdate.\(notificationSuffix)")
        let broadcaster = HelperStateBroadcaster(
            requestNotificationName: requestName,
            stateDidUpdateNotificationName: responseName,
        )
        defer {
            broadcaster.stopObservingRequests()
        }

        let startedResponse = expectation(description: "Helper state response after start")
        startedResponse.assertForOverFulfill = true
        let startedResponseObserver = center.addObserver(
            forName: responseName,
            object: nil,
            queue: .main,
        ) { _ in
            startedResponse.fulfill()
        }
        broadcaster.startObservingRequests()
        center.post(name: requestName, object: nil)
        await fulfillment(of: [startedResponse], timeout: 1)
        center.removeObserver(startedResponseObserver)

        broadcaster.stopObservingRequests()
        let stoppedResponse = expectation(description: "No helper state response after stop")
        stoppedResponse.isInverted = true
        let stoppedResponseObserver = center.addObserver(
            forName: responseName,
            object: nil,
            queue: .main,
        ) { _ in
            stoppedResponse.fulfill()
        }
        center.post(name: requestName, object: nil)
        await fulfillment(of: [stoppedResponse], timeout: 0.2)
        center.removeObserver(stoppedResponseObserver)

        broadcaster.stopObservingRequests()
        broadcaster.stopObservingRequests()
        let restartedResponse = expectation(description: "Helper state response after double stop")
        restartedResponse.assertForOverFulfill = true
        let restartedResponseObserver = center.addObserver(
            forName: responseName,
            object: nil,
            queue: .main,
        ) { _ in
            restartedResponse.fulfill()
        }
        broadcaster.startObservingRequests()
        center.post(name: requestName, object: nil)
        await fulfillment(of: [restartedResponse], timeout: 1)
        center.removeObserver(restartedResponseObserver)
    }
}
