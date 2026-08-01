@testable import VoyagerEntryCoreClient
import XCTest

final class EntryCoreProtocolTests: XCTestCase {
    private let requestID = "request-1"

    func testDecodesExactProtocolV1SuccessResponses() throws {
        let ping = try decode(success(result: #"{"message":"pong"}"#), method: .ping)
        XCTAssertEqual(ping, .ping(EntryCorePingResult()))

        let health = try decode(
            success(result: #"{"status":"healthy","state":"running"}"#),
            method: .health,
        )
        XCTAssertEqual(health, .health(EntryCoreHealthResult()))

        let versionResult = #"{"app_version":"2026.7.31-custom","protocol_version":1}"#
        let version = try decode(success(result: versionResult), method: .version)
        let expectedVersion = try EntryCoreVersionResult(appVersion: "2026.7.31-custom")
        XCTAssertEqual(version, .version(expectedVersion))
    }

    func testMapsEveryKnownServerErrorWithoutExposingMessageAsEqualityContract() {
        for code in EntryCoreServerErrorCode.allCases {
            let error = #"{"code":"\#(code.rawValue)","message":"server-selected detail"}"#
            assertError(.server(code), wire: failure(error: error), method: .ping)
        }
    }

    func testAcceptsOnlyRFCWhitespaceAroundExactlyOneDocument() throws {
        let wire = " \t\n\r" + pingSuccess + "\r\n\t "
        XCTAssertEqual(try decode(wire, method: .ping), .ping(EntryCorePingResult()))

        assertError(.malformedResponse, wire: pingSuccess + " {}", method: .ping)
        assertError(.malformedResponse, wire: pingSuccess + " trailing", method: .ping)
        assertError(.malformedResponse, wire: "\u{00A0}" + pingSuccess, method: .ping)
    }

    func testRejectsMalformedRawBytesAndAlternateEncodings() {
        var invalidUTF8 = Array(
            #"{"request_id":"request-1","protocol_version":1,"ok":true,"result":{"message":""#.utf8,
        )
        invalidUTF8.append(0xFF)
        invalidUTF8.append(contentsOf: Array(#""}}"#.utf8))

        assertError(.malformedResponse, raw: invalidUTF8, method: .ping)
        assertError(
            .malformedResponse,
            raw: [0xEF, 0xBB, 0xBF] + Array(pingSuccess.utf8),
            method: .ping,
        )
        assertError(
            .malformedResponse,
            raw: [0xFF, 0xFE] + utf16LittleEndianBytes(pingSuccess),
            method: .ping,
        )
        assertError(
            .malformedResponse,
            raw: [0x00, 0x00, 0xFE, 0xFF] + Array(pingSuccess.utf8),
            method: .ping,
        )
    }

    func testRejectsInvalidStringsEscapesControlsAndSurrogates() throws {
        let pairedResult = #"{"app_version":"rocket-\uD83D\uDE80","protocol_version":1}"#
        let paired = try decode(success(result: pairedResult), method: .version)
        let expected = try EntryCoreVersionResult(appVersion: "rocket-🚀")
        XCTAssertEqual(paired, .version(expected))

        let malformedResults = [
            #"{"message":"\uD800"}"#,
            #"{"message":"\uDC00"}"#,
            #"{"message":"\uD800\u0041"}"#,
            #"{"message":"\x"}"#,
            #"{"message":"\u12G4"}"#,
            #"{"message":"unterminated}"#,
        ]
        for result in malformedResults {
            assertError(.malformedResponse, wire: success(result: result), method: .ping)
        }

        var unescapedControl = Array(
            #"{"request_id":"request-1","protocol_version":1,"ok":true,"result":{"message":"po"#.utf8,
        )
        unescapedControl.append(0x0A)
        unescapedControl.append(contentsOf: Array(#"ng"}}"#.utf8))
        assertError(.malformedResponse, raw: unescapedControl, method: .ping)
    }

    func testRejectsDuplicateDecodedKeysAtEveryObjectScope() {
        let duplicateTopLevel = json(
            #"{"request_id":"request-1","request_id":"request-1","#,
            #""protocol_version":1,"ok":true,"result":{"message":"pong"}}"#,
        )
        let duplicateResult = success(result: #"{"message":"pong","message":"pong"}"#)
        let duplicateDecodedErrorKey = failure(
            error: #"{"code":"internal_error","\u0063ode":"internal_error","message":"detail"}"#,
        )
        let nestedDuplicate = success(
            result: #"{"message":"pong","nested":{"x":1,"x":2}}"#,
        )

        for wire in [duplicateTopLevel, duplicateResult, duplicateDecodedErrorKey, nestedDuplicate] {
            assertError(.malformedResponse, wire: wire, method: .ping)
        }
    }

    func testRejectsCommentsTrailingCommasAndPermissiveExtensions() {
        let malformed = [
            success(result: #"{"message":"pong",}"#),
            json(
                #"{"request_id":"request-1","protocol_version":1,"ok":true,"#,
                #""result":{"message":"pong"},}"#,
            ),
            pingSuccess + " // comment",
            #"{/* comment */"request_id":"request-1"}"#,
            #"{'request_id':'request-1'}"#,
            pingSuccess(protocolVersion: "+1"),
        ]
        for wire in malformed {
            assertError(.malformedResponse, wire: wire, method: .ping)
        }
    }

    func testEnforcesRFCNumberGrammarAndProtocolLexicalIntegers() {
        for number in ["01", "-01", "1.", "1e", "1e+", "--1"] {
            assertError(.malformedResponse, wire: pingSuccess(protocolVersion: number), method: .ping)
        }

        for number in ["1.0", "1e0", "1E+0", "-1", "9223372036854775808"] {
            assertError(.protocolMismatch, wire: pingSuccess(protocolVersion: number), method: .ping)
        }
        assertError(
            .protocolMismatch,
            wire: versionSuccess(resultProtocolVersion: "1.0"),
            method: .version,
        )
        assertError(
            .protocolMismatch,
            wire: versionSuccess(resultProtocolVersion: "1e0"),
            method: .version,
        )
        assertError(
            .protocolMismatch,
            wire: versionSuccess(resultProtocolVersion: "9223372036854775808"),
            method: .version,
        )
    }

    func testMapsValidJSONEnvelopeMismatchesToProtocolMismatch() {
        let missingResult = #"{"request_id":"request-1","protocol_version":1,"ok":true}"#
        let unknownField = json(
            #"{"request_id":"request-1","protocol_version":1,"ok":true,"#,
            #""result":{"message":"pong"},"extra":true}"#,
        )
        let successWithError = json(
            #"{"request_id":"request-1","protocol_version":1,"ok":true,"#,
            #""result":{"message":"pong"},"#,
            #""error":{"code":"internal_error","message":"detail"}}"#,
        )
        let failureWithResult = json(
            #"{"request_id":"request-1","protocol_version":1,"ok":false,"#,
            #""result":{"message":"pong"},"#,
            #""error":{"code":"internal_error","message":"detail"}}"#,
        )
        let wrongOKType = json(
            #"{"request_id":"request-1","protocol_version":1,"ok":1,"#,
            #""result":{"message":"pong"}}"#,
        )
        let mismatches = [
            "[]",
            missingResult,
            unknownField,
            successWithError,
            failureWithResult,
            pingSuccess(protocolVersion: "2"),
            pingSuccess(protocolVersion: #""1""#),
            wrongOKType,
        ]
        for wire in mismatches {
            assertError(.protocolMismatch, wire: wire, method: .ping)
        }
    }

    func testValidatesExactMethodSpecificResultShapes() {
        let cases: [(String, EntryCoreMethod)] = [
            (success(result: #"{"message":"nope"}"#), .ping),
            (success(result: #"{"message":"pong","extra":true}"#), .ping),
            (success(result: #"{"status":"degraded","state":"running"}"#), .health),
            (success(result: #"{"status":"healthy","state":"stopped"}"#), .health),
            (success(result: #"{"state":"running"}"#), .health),
            (success(result: #"{"app_version":"","protocol_version":1}"#), .version),
            (success(result: #"{"app_version":"dev","protocol_version":2}"#), .version),
            (success(result: #"{"app_version":"dev","protocol_version":1,"extra":true}"#), .version),
            (pingSuccess, .health),
        ]
        for (wire, method) in cases {
            assertError(.protocolMismatch, wire: wire, method: method)
        }
    }

    func testValidatesExactErrorShapeKnownCodeAndNonemptyMessage() {
        let mismatches = [
            #"{"request_id":"request-1","protocol_version":1,"ok":false}"#,
            failure(error: #"{"code":"future_error","message":"detail"}"#),
            failure(error: #"{"code":"internal_error","message":""}"#),
            failure(error: #"{"code":"internal_error"}"#),
            failure(error: #"{"code":"internal_error","message":"detail","extra":true}"#),
            failure(error: "null"),
        ]
        for wire in mismatches {
            assertError(.protocolMismatch, wire: wire, method: .ping)
        }
    }

    func testActiveRequestIDMismatchPrecedesResultOrKnownServerError() {
        assertError(.requestIDMismatch, wire: success(id: "", result: pingResult), method: .ping)
        assertError(.requestIDMismatch, wire: success(id: "other", result: pingResult), method: .ping)

        let error = #"{"code":"internal_error","message":"detail"}"#
        assertError(.requestIDMismatch, wire: failure(id: "", error: error), method: .ping)
        assertError(.requestIDMismatch, wire: failure(id: "other", error: error), method: .ping)
        assertError(
            .protocolMismatch,
            wire: success(id: String(repeating: "x", count: 129), result: pingResult),
            method: .ping,
        )
    }

    func testMaximumWireBytesMatchesGoDecoderAt65536And65537() throws {
        let paddingCount = StrictJSONParser.maximumWireBytes - pingSuccess.utf8.count
        let atLimit = pingSuccess + String(repeating: " ", count: paddingCount)
        XCTAssertEqual(try decode(atLimit, method: .ping), .ping(EntryCorePingResult()))

        assertError(.malformedResponse, wire: atLimit + " ", method: .ping)
    }

    func testUsesByteExactDecodedKeysAndRequestIDsLikeGo() throws {
        let canonicallyEquivalentKeys = json(
            #"{"request_id":"request-1","protocol_version":1,"ok":true,"#,
            #""result":{"message":"pong"},"\u00E9":1,"e\u0301":2}"#,
        )
        XCTAssertNoThrow(try StrictJSONParser.parse(Array(canonicallyEquivalentKeys.utf8)))
        assertError(.protocolMismatch, wire: canonicallyEquivalentKeys, method: .ping)

        let composed = "é"
        let decomposed = "e\u{0301}"
        XCTAssertEqual(composed, decomposed)
        assertError(
            .requestIDMismatch,
            wire: success(id: composed, result: pingResult),
            method: .ping,
            expectedRequestID: decomposed,
        )
    }

    func testResponseIDUsesUTF8ByteBoundaries() throws {
        let ascii128 = String(repeating: "a", count: 128)
        let unicode128 = String(repeating: "🚀", count: 32)

        XCTAssertEqual(
            try decode(success(id: ascii128, result: pingResult), method: .ping, expectedRequestID: ascii128),
            .ping(EntryCorePingResult()),
        )
        XCTAssertEqual(
            try decode(success(id: unicode128, result: pingResult), method: .ping, expectedRequestID: unicode128),
            .ping(EntryCorePingResult()),
        )
    }

    func testMaximumDepthMatchesGoParserAt511512And513() {
        for acceptedDepth in [511, 512] {
            let raw = nestedArray(depth: acceptedDepth)
            XCTAssertNoThrow(try StrictJSONParser.parse(raw))
            assertError(.protocolMismatch, raw: raw, method: .ping)
        }

        let rejected = nestedArray(depth: 513)
        XCTAssertThrowsError(try StrictJSONParser.parse(rejected))
        assertError(.malformedResponse, raw: rejected, method: .ping)
    }

    private var pingResult: String {
        #"{"message":"pong"}"#
    }

    private var pingSuccess: String {
        success(result: pingResult)
    }

    private func pingSuccess(protocolVersion: String) -> String {
        success(protocolVersion: protocolVersion, result: pingResult)
    }

    private func success(
        id: String = "request-1",
        protocolVersion: String = "1",
        result: String,
    ) -> String {
        json(
            #"{"request_id":"\#(id)","protocol_version":\#(protocolVersion),"#,
            #""ok":true,"result":\#(result)}"#,
        )
    }

    private func failure(id: String = "request-1", error: String) -> String {
        json(
            #"{"request_id":"\#(id)","protocol_version":1,"ok":false,"#,
            #""error":\#(error)}"#,
        )
    }

    private func versionSuccess(resultProtocolVersion: String) -> String {
        let result = #"{"app_version":"dev","protocol_version":\#(resultProtocolVersion)}"#
        return success(result: result)
    }

    private func nestedArray(depth: Int) -> [UInt8] {
        let value = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
        return Array(value.utf8)
    }

    private func utf16LittleEndianBytes(_ value: String) -> [UInt8] {
        value.utf16.flatMap { codeUnit in
            [UInt8(truncatingIfNeeded: codeUnit), UInt8(truncatingIfNeeded: codeUnit >> 8)]
        }
    }

    private func json(_ fragments: String...) -> String {
        fragments.joined()
    }

    private func decode(
        _ wire: String,
        method: EntryCoreMethod,
        expectedRequestID: String? = nil,
    ) throws -> EntryCoreDecodedResponse {
        try EntryCoreResponseDecoder.decode(
            Array(wire.utf8),
            method: method,
            expectedRequestID: expectedRequestID ?? requestID,
        )
    }

    private func assertError(
        _ expected: EntryCoreClientError,
        wire: String,
        method: EntryCoreMethod,
        expectedRequestID: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        assertError(
            expected,
            raw: Array(wire.utf8),
            method: method,
            expectedRequestID: expectedRequestID,
            file: file,
            line: line,
        )
    }

    private func assertError(
        _ expected: EntryCoreClientError,
        raw: [UInt8],
        method: EntryCoreMethod,
        expectedRequestID: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertThrowsError(
            try EntryCoreResponseDecoder.decode(
                raw,
                method: method,
                expectedRequestID: expectedRequestID ?? requestID,
            ),
            file: file,
            line: line,
        ) { error in
            XCTAssertEqual(error as? EntryCoreClientError, expected, file: file, line: line)
        }
    }
}
