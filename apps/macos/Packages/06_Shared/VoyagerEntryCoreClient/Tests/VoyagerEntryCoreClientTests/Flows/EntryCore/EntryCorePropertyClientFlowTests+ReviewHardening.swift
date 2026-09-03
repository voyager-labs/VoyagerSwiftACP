import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

extension EntryCorePropertyClientFlowTests {
    func testPrepareRejectsResponseOutsideRequestChanges() async throws {
        let propertyID1 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyID2 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let propertyID3 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000003")
        let change1 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/a"),
            propertyID: propertyID1,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
        )
        let change2 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/b"),
            propertyID: propertyID2,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
        )
        let request = try PropertyChangeRequest(changes: [change1, change2])
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        for (name, response) in prepareResponseCases(
            propertyID1: propertyID1,
            propertyID2: propertyID2,
            propertyID3: propertyID3,
        ) {
            await assertPrepareResponseRejected(name, request: request, response: response, endpoint: endpoint)
        }
    }
}

private func prepareResponseCases(
    propertyID1: PropertyID,
    propertyID2: PropertyID,
    propertyID3: PropertyID,
) -> [(String, String)] {
    let first = propertyChangePreparedJSON(propertyID: propertyID1.rawValue, target: "/a")
    let second = propertyChangePreparedJSON(propertyID: propertyID2.rawValue, target: "/b")
    let wrongTarget = propertyChangePreparedJSON(propertyID: propertyID1.rawValue, target: "/wrong")
    let wrongProperty = propertyChangePreparedJSON(propertyID: propertyID3.rawValue, target: "/a")
    let wrongDesired = propertyChangePreparedJSON(
        propertyID: propertyID1.rawValue,
        target: "/a",
        afterState: "unknown",
    )
    return [
        (
            "fewer changes",
            propertyChangePrepareResponse(changes: "[\(first)]"),
        ),
        (
            "wrong change order",
            propertyChangePrepareResponse(changes: "[\(second),\(first)]"),
        ),
        (
            "wrong target",
            propertyChangePrepareResponse(changes: "[\(wrongTarget),\(second)]"),
        ),
        (
            "wrong property",
            propertyChangePrepareResponse(changes: "[\(wrongProperty),\(second)]"),
        ),
        (
            "wrong desired state",
            propertyChangePrepareResponse(changes: "[\(wrongDesired),\(second)]"),
        ),
    ]
}

private func propertyChangePreparedJSON(
    propertyID: String,
    target: String,
    afterState: String = "null",
) -> String {
    """
    {
      "target":{"kind":"local_path","local_path":"\(target)"},
      "property_id":"\(propertyID)",
      "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "before":null,
      "after":{"state":"\(afterState)"}
    }
    """
}

private func propertyChangePrepareResponse(changes: String) -> String {
    """
    {
      "request_id":"prepare-id",
      "ok":true,
      "result":{"changes":\(changes),"requires_confirmation":true}
    }
    """
}

private func assertPrepareResponseRejected(
    _ name: String,
    request: PropertyChangeRequest,
    response: String,
    endpoint: EntryCoreEndpoint,
) async {
    let recorder = PropertyTransportRecorder(response: Data(response.utf8))
    let client = EntryCorePropertyClient.makeLive(
        requestID: { "prepare-id" },
        makeTransport: recorder.makeTransport,
    )

    do {
        _ = try await client.changePrepare(endpoint, request)
        XCTFail("\(name) should be rejected")
    } catch {
        XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, name)
    }
    XCTAssertEqual(recorder.creationCount, 1, name)
    XCTAssertEqual(recorder.requests.count, 1, name)
}
