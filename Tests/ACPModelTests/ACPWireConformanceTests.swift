//
//  ACPWireConformanceTests.swift
//  ACPModelTests
//
//  W-series: JSON-RPC envelope and ACP v1 wire-model contracts.
//  Fixture files live in Tests/ACPModelTests/Fixtures.
//

@testable import ACPModel
import XCTest

final class ACPWireConformanceTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name)",
        )
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, fixture name: String) throws -> T {
        try JSONDecoder().decode(type, from: fixture(name))
    }

    // MARK: W01-W03

    func testValidRequestDecode() throws {
        let message = try decode(Message.self, fixture: "valid_request")
        guard case let .request(request) = message else {
            return XCTFail("expected request")
        }
        XCTAssertEqual(request.id, .number(1))
        XCTAssertEqual(request.method, "session/new")
    }

    func testValidResponseDecode() throws {
        let message = try decode(Message.self, fixture: "valid_response")
        guard case let .response(response) = message else {
            return XCTFail("expected response")
        }
        XCTAssertEqual(response.id, .number(1))
        XCTAssertNotNil(response.result)
        XCTAssertNil(response.error)
    }

    func testValidNotificationDecode() throws {
        let message = try decode(Message.self, fixture: "valid_notification")
        guard case let .notification(notification) = message else {
            return XCTFail("expected notification")
        }
        XCTAssertEqual(notification.method, "session/cancel")
    }

    // MARK: W04-W05

    func testUnknownFieldsAreIgnored() throws {
        let message = try decode(Message.self, fixture: "request_with_unknown_fields")
        guard case let .request(request) = message else {
            return XCTFail("expected request")
        }
        XCTAssertEqual(request.id, .number(7))
        XCTAssertEqual(request.method, "initialize")
    }

    func testMissingRequiredFieldsRejected() throws {
        // request without method
        XCTAssertThrowsError(try decode(Message.self, fixture: "missing_method_request"))
        // notification params missing sessionId
        XCTAssertThrowsError(try decode(SessionUpdateNotification.self, fixture: "missing_session_id_update"))
        // prompt response missing stopReason
        XCTAssertThrowsError(try decode(SessionPromptResponse.self, fixture: "missing_stop_reason_prompt"))
    }

    // MARK: W06

    func testUnknownTypedEnumRejected() throws {
        XCTAssertThrowsError(try decode(ContentBlock.self, fixture: "unknown_content_type"))
        XCTAssertThrowsError(try decode(SessionPromptResponse.self, fixture: "unknown_stop_reason"))
    }

    // MARK: W07

    func testMalformedJSONRejected() throws {
        XCTAssertThrowsError(try decode(Message.self, fixture: "malformed_json"))
    }

    // MARK: W08

    func testInvalidJSONRPCVersionRejected() throws {
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_version_missing"))
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_version_1_0"))
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_version_number"))
    }

    // MARK: W09-W10

    func testInvalidRequestIDRejected() throws {
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_id_bool"))
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_id_object"))
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_id_array"))
        XCTAssertThrowsError(try decode(Message.self, fixture: "invalid_id_fraction"))
    }

    func testNullIDRemainsRequest() throws {
        let message = try decode(Message.self, fixture: "null_id_request")
        guard case let .request(request) = message else {
            return XCTFail("null id must remain a request")
        }
        XCTAssertEqual(request.id, .null)
    }

    // MARK: W11

    func testErrorObjectRoundTrip() throws {
        let response = try decode(JSONRPCResponse.self, fixture: "error_object")
        let error = try XCTUnwrap(response.error)
        XCTAssertEqual(error.code, -32000)
        XCTAssertEqual(error.message, "boom")
        let data = try XCTUnwrap(error.data)
        let nested = try XCTUnwrap((data.value as? [String: any Sendable])?["nested"] as? [String: any Sendable])
        XCTAssertEqual(nested["k"] as? String, "v")

        let encoded = try JSONEncoder().encode(response)
        let roundTripped = try JSONDecoder().decode(JSONRPCResponse.self, from: encoded)
        XCTAssertEqual(roundTripped.error?.code, -32000)
        XCTAssertEqual(roundTripped.error?.message, "boom")
    }

    // MARK: W12

    func testNullResultRoundTrip() throws {
        let response = try decode(JSONRPCResponse.self, fixture: "null_result")
        // `result: null` is a present key: distinct from a missing key.
        XCTAssertNotNil(response.result)
        XCTAssertTrue(response.result?.value is NSNull)

        let encoded = try JSONEncoder().encode(response)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertTrue(json.keys.contains("result"))
        XCTAssertTrue(json["result"] is NSNull)

        let roundTripped = try JSONDecoder().decode(JSONRPCResponse.self, from: encoded)
        XCTAssertTrue(roundTripped.result?.value is NSNull)
    }

    // MARK: W13

    func testResponseRequiresExactlyOneOutcome() throws {
        XCTAssertThrowsError(try decode(JSONRPCResponse.self, fixture: "response_no_outcome"))

        // Both present is also invalid.
        let bothJSON = """
        {"jsonrpc":"2.0","id":1,"result":{},"error":{"code":-1,"message":"m"}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(
            JSONRPCResponse.self,
            from: XCTUnwrap(bothJSON.data(using: .utf8)),
        ))

        // The API allows constructing invalid combinations, but encoding rejects them.
        let both = JSONRPCResponse(
            id: .number(1),
            result: AnyCodable([String: any Sendable]()),
            error: JSONRPCError(code: -1, message: "m", data: nil),
        )
        XCTAssertThrowsError(try JSONEncoder().encode(both))

        let neither = JSONRPCResponse(id: .number(1), result: nil, error: nil)
        XCTAssertThrowsError(try JSONEncoder().encode(neither))
    }

    // MARK: W14

    func testProtocolVersionRequiresInteger() throws {
        XCTAssertThrowsError(try decode(InitializeResponse.self, fixture: "version_string"))
        XCTAssertThrowsError(try decode(InitializeResponse.self, fixture: "version_null"))
        XCTAssertThrowsError(try decode(InitializeResponse.self, fixture: "version_bool"))

        let outOfRange = """
        {"protocolVersion":65536,"agentCapabilities":{}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(
            InitializeResponse.self,
            from: XCTUnwrap(outOfRange.data(using: .utf8)),
        ))

        let valid = """
        {"protocolVersion":65535,"agentCapabilities":{}}
        """
        let response = try JSONDecoder().decode(InitializeResponse.self, from: XCTUnwrap(valid.data(using: .utf8)))
        XCTAssertEqual(response.protocolVersion, 65535)
    }

    // MARK: W15

    func testCapabilityDefaultsAndTypes() throws {
        // Omitted capabilities default to "not supported".
        let omitted = try decode(ClientCapabilities.self, fixture: "capabilities_omitted")
        XCTAssertFalse(omitted.terminal)
        XCTAssertFalse(omitted.fs.readTextFile)
        XCTAssertFalse(omitted.fs.writeTextFile)

        // An empty capabilities object decodes with defaults.
        let empty = try JSONDecoder().decode(ClientCapabilities.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.terminal)

        // Wrong-typed booleans are rejected.
        XCTAssertThrowsError(try decode(ClientCapabilities.self, fixture: "capabilities_invalid_boolean"))
    }

    // MARK: W16

    func testMetaRoundTrip() throws {
        let message = try decode(Message.self, fixture: "meta_nested")
        guard case let .request(request) = message else {
            return XCTFail("expected request")
        }
        let params = try XCTUnwrap(request.params)
        let meta = try XCTUnwrap((params.value as? [String: any Sendable])?["_meta"] as? [String: any Sendable])
        let a = try XCTUnwrap(meta["a"] as? [String: any Sendable])
        XCTAssertNotNil(a["b"])
    }

    // MARK: W17

    func testUnsupportedAnyCodableValueFailsEncoding() {
        struct NotJSON: Sendable {}
        let value = AnyCodable(NotJSON())
        XCTAssertThrowsError(try JSONEncoder().encode(value)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("expected EncodingError, got \(error)")
            }
        }
    }

    // MARK: ID distinctions

    func testNumericAndStringIDsRemainDistinct() throws {
        let number = try JSONDecoder().decode(RequestId.self, from: Data("1".utf8))
        let string = try JSONDecoder().decode(RequestId.self, from: Data(#""1""#.utf8))
        XCTAssertEqual(number, .number(1))
        XCTAssertEqual(string, .string("1"))
        XCTAssertNotEqual(number, string)
    }

    func testNotificationMustNotCarryID() throws {
        let json = """
        {"jsonrpc":"2.0","method":"m","params":{},"id":1}
        """
        let message = try JSONDecoder().decode(Message.self, from: XCTUnwrap(json.data(using: .utf8)))
        guard case .request = message else {
            return XCTFail("method+id must decode as request, never notification")
        }
    }
}
