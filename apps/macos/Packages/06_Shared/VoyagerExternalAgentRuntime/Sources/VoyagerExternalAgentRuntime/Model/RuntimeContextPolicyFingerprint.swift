import CryptoKit
import Foundation

extension RuntimeContextPolicy {
    func hasSameExecutionContext(as other: Self) -> Bool {
        hasSameRestartIdentity(as: other)
            && executionContextFingerprint == other.executionContextFingerprint
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
