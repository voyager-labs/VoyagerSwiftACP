import Foundation
import VoyagerEntryCoreClient
import XCTest

final class EntryCorePropertyPublicContractFlowTests: XCTestCase {
    func testPropertyNamespaceHasExactlyTwelveSendableOperations() {
        let propertyMethods = EntryCoreMethod.allCases.filter { $0.rawValue.hasPrefix("property.") }
        XCTAssertEqual(propertyMethods.count, 12)
        XCTAssertEqual(propertyMethods.last, .propertyConditionQuery)
        requireSendable(EntryCorePropertyClient.live)
    }

    func testValidatedIDsAndConditionOperatorsFailClosed() {
        XCTAssertThrowsError(try PropertyID(rawValue: "not-an-id"))
        XCTAssertThrowsError(try PropertyConditionOperator(rawValue: "future"))
        XCTAssertEqual(PropertyConditionOperator.canonicalValues.count, 20)
    }

    func testEntryIDRejectsStandardBase64Alphabet() {
        XCTAssertThrowsError(
            try EntryCoreEntryID(rawValue: "ent:+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/v7+/s"),
        )
    }

    func testSharedGoFixtureMatchesSwiftInventory() throws {
        let fixtureURL = try repositoryRoot().appendingPathComponent(
            "apps/entry-core/shared/entry_core_property_wire_cases.json",
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any],
        )
        XCTAssertEqual(object["methods"] as? [String], EntryCoreMethod.allCases.dropFirst(3).map(\.rawValue))
        XCTAssertEqual(object["operators"] as? [String], PropertyConditionOperator.canonicalValues)
        XCTAssertEqual((object["relations"] as? [String])?.count, 42)
        XCTAssertEqual((object["stable_errors"] as? [String])?.count, 6)
    }

    private func requireSendable(_: some Sendable) {}

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 12 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw EntryCoreClientError.protocolMismatch
    }
}
