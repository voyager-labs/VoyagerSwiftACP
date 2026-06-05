import Foundation
@testable import VoyagerEntitiesAi
import XCTest

/// Value-type contract tests recovered from old AIConnectionClientContractTests (9d3be186).
/// Tests equatability and case coverage for store errors, mutation results,
/// verification results, connection results, and connection errors.
final class AiContractValueTests: XCTestCase {
    // MARK: - AiConnectionStoreError equality

    func testStoreError_fileSystemError_isEquatable() {
        let error1 = AiConnectionStoreError.fileSystemError("test")
        let error2 = AiConnectionStoreError.fileSystemError("test")
        let error3 = AiConnectionStoreError.fileSystemError("other")
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testStoreError_lockContention_isEquatable() {
        XCTAssertEqual(AiConnectionStoreError.lockContention, .lockContention)
        XCTAssertNotEqual(AiConnectionStoreError.lockContention, .quarantineRecovery)
    }

    // MARK: - AiConnectionMutationResult cases

    func testMutationResult_success() {
        let file = AIConnectionsFile.empty()
        let result = AiConnectionMutationResult.success(file)
        if case let .success(returned) = result {
            XCTAssertEqual(returned, file)
        } else {
            XCTFail("Expected success")
        }
    }

    func testMutationResult_partialSuccess() {
        let file = AIConnectionsFile.empty()
        let result = AiConnectionMutationResult.partialSuccess(file, failedProviders: [.openai])
        if case let .partialSuccess(returned, failed) = result {
            XCTAssertEqual(returned, file)
            XCTAssertEqual(failed, [.openai])
        } else {
            XCTFail("Expected partialSuccess")
        }
    }

    func testMutationResult_fileSystemError() {
        let result = AiConnectionMutationResult.fileSystemError(.lockContention)
        if case let .fileSystemError(error) = result {
            XCTAssertEqual(error, .lockContention)
        } else {
            XCTFail("Expected fileSystemError")
        }
    }

    // MARK: - AiProviderVerificationResult cases

    func testVerificationResult_valid() {
        let result = AiProviderVerificationResult.valid
        if case .valid = result {
        } else {
            XCTFail("Expected valid")
        }
    }

    func testVerificationResult_invalid() {
        let result = AiProviderVerificationResult.invalid(.expired)
        if case let .invalid(reason) = result {
            XCTAssertEqual(reason, .expired)
        } else {
            XCTFail("Expected invalid")
        }
    }

    func testVerificationResult_unsupportedProvider() {
        let result = AiProviderVerificationResult.unsupportedProvider
        if case .unsupportedProvider = result {
        } else {
            XCTFail("Expected unsupportedProvider")
        }
    }

    func testVerificationResult_networkError() {
        let result = AiProviderVerificationResult.networkError
        if case .networkError = result {
        } else {
            XCTFail("Expected networkError")
        }
    }

    // MARK: - AiProviderConnectionResult init

    func testConnectionResult_init() {
        let result = AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .none,
            updatedFile: AIConnectionsFile.empty()
        )
        XCTAssertEqual(result.provider, .openai)
        XCTAssertEqual(result.state, .connected)
        XCTAssertEqual(result.reason, .none)
    }

    // MARK: - AiProviderConnectionError cases

    func testConnectionError_unsupportedProvider() {
        let error = AiProviderConnectionError.unsupportedProvider
        XCTAssertEqual(error, .unsupportedProvider)
    }

    func testConnectionError_invalidCredential() {
        let error = AiProviderConnectionError.invalidCredential
        XCTAssertEqual(error, .invalidCredential)
    }

    func testConnectionError_storeError() {
        let error = AiProviderConnectionError.storeError(.lockContention)
        if case let .storeError(storeError) = error {
            XCTAssertEqual(storeError, .lockContention)
        } else {
            XCTFail("Expected storeError")
        }
    }

    func testConnectionError_verificationFailed() {
        let error = AiProviderConnectionError.verificationFailed(.oauthRejected)
        if case let .verificationFailed(reason) = error {
            XCTAssertEqual(reason, .oauthRejected)
        } else {
            XCTFail("Expected verificationFailed")
        }
    }
}
