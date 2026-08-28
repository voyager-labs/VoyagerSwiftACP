import CryptoKit
import Foundation

public struct RuntimeStoredContext: Codable, Hashable, Sendable {
    public let branchReference: String
    public let authorizationGeneration: UInt64
    public let localCorrelation: String
    public let executionContextFingerprint: String

    public init(contextPolicy: RuntimeContextPolicy) {
        branchReference = contextPolicy.branchReference
        authorizationGeneration = contextPolicy.authorizationGeneration
        localCorrelation = contextPolicy.localCorrelation
        executionContextFingerprint = Self.makeExecutionContextFingerprint(
            workingDirectory: contextPolicy.workingDirectory,
            allowedRoots: contextPolicy.allowedRoots,
            requestContext: contextPolicy.requestContext,
        )
    }

    enum CodingKeys: String, CodingKey {
        case branchReference = "branch_reference"
        case authorizationGeneration = "authorization_generation"
        case localCorrelation = "local_correlation"
        case executionContextFingerprint = "execution_context_fingerprint"
    }

    static func makeExecutionContextFingerprint(
        workingDirectory: String?,
        allowedRoots: [String],
        requestContext: String?,
    ) -> String {
        var data = Data()
        append(workingDirectory, to: &data)
        allowedRoots.forEach { append($0, to: &data) }
        append(nil, to: &data)
        append(requestContext, to: &data)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ value: String?, to data: inout Data) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}
