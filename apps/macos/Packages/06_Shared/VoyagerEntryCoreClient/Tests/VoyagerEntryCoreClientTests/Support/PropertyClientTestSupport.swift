import Foundation
import os
@testable import VoyagerEntryCoreClient

func propertyJSON(_ fragments: String...) -> String {
    fragments.joined()
}

final class PropertyTransportRecorder: Sendable {
    private struct State {
        var creationCount = 0
        var requests: [Data] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let response: Data

    init(response: Data) {
        self.response = response
    }

    var creationCount: Int {
        state.withLock(\.creationCount)
    }

    var requests: [Data] {
        state.withLock(\.requests)
    }

    func makeTransport() -> EntryCoreTransportRequest {
        state.withLock { $0.creationCount += 1 }
        return { request, _ in
            self.state.withLock { $0.requests.append(request) }
            return self.response
        }
    }
}
