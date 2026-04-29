import CryptoKit
import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class PKCETests: XCTestCase {
    func testGenerate_returnsVerifierAndChallenge() {
        let codes = PKCE.generate()
        XCTAssertEqual(codes.verifier.count, 43)
        XCTAssertEqual(codes.challenge.count, 43)
    }

    func testVerifier_isBase64URL() {
        let verifier = PKCE.generateVerifier()
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { validChars.contains($0) })
    }

    func testChallenge_isDeterministic() {
        let verifier = PKCE.generateVerifier()
        let challenge1 = PKCE.generateChallenge(from: verifier)
        let challenge2 = PKCE.generateChallenge(from: verifier)
        XCTAssertEqual(challenge1, challenge2)
    }

    func testChallenge_matchesSHA256Base64URL() {
        let verifier = "test-verifier-value"
        let challenge = PKCE.generateChallenge(from: verifier)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        XCTAssertEqual(challenge, expected)
    }

    func testDifferentVerifiers_produceDifferentChallenges() {
        let codes1 = PKCE.generate()
        let codes2 = PKCE.generate()
        XCTAssertNotEqual(codes1.verifier, codes2.verifier)
        XCTAssertNotEqual(codes1.challenge, codes2.challenge)
    }

    func testGenerateState_returnsRandomString() {
        let state1 = PKCE.generateState()
        let state2 = PKCE.generateState()
        XCTAssertEqual(state1.count, 43)
        XCTAssertNotEqual(state1, state2)
    }

    func testPKCECodes_equality() {
        let codes = PKCE.generate()
        let same = PKCECodes(verifier: codes.verifier, challenge: codes.challenge)
        XCTAssertEqual(codes, same)
    }
}
