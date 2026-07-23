import CryptoKit
import Foundation

enum SigningError: Error {
    case missingPrivateKey
}

func privateKey() throws -> Curve25519.Signing.PrivateKey {
    guard let encoded = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
          let decoded = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          decoded.count == 32 || decoded.count == 64
    else {
        throw SigningError.missingPrivateKey
    }

    return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(decoded.prefix(32)))
}

let payload = FileHandle.standardInput.readDataToEndOfFile()
let signature = try privateKey().signature(for: payload)
print(signature.base64EncodedString())
