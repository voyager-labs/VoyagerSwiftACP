import Clocks
import Dependencies
import XCTest

private final class VoyagerTestDependencyObserver: NSObject, XCTestObservation {
    func testCaseWillStart(_: XCTestCase) {
        prepareDependencies {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 0) }
            $0.uuid = UUIDGenerator.incrementing
            $0.continuousClock = ImmediateClock()
        }
    }
}

private let kObserverRegistration: Void = {
    XCTestObservationCenter.shared.addTestObserver(VoyagerTestDependencyObserver())
}()

private let kObserverBootstrap: Void = kObserverRegistration
