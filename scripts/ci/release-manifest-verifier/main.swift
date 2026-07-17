import CryptoKit
import Foundation

enum VerificationError: Error {
    case invalidArguments
    case missingFixturePrivateKey
    case invalidArtifactChecksum
    case invalidArtifactSize
    case invalidArtifactSignature
    case invalidBundleTimestamp
}

guard CommandLine.arguments.count == 6 else {
    throw VerificationError.invalidArguments
}

guard let encodedPrivateKey = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
      let privateKeyData = Data(base64Encoded: encodedPrivateKey),
      privateKeyData.count == 32 || privateKeyData.count == 64
else {
    throw VerificationError.missingFixturePrivateKey
}

let manifestPath = CommandLine.arguments[1]
let zipPath = CommandLine.arguments[2]
let appcastPath = CommandLine.arguments[3]
let artifactURL = CommandLine.arguments[4]
let releasedAt = CommandLine.arguments[5]
let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
let manifest = try JSONDecoder().decode(ReleaseManifest.self, from: manifestData)
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(privateKeyData.prefix(32)))
let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
_ = try manifest.verifiedReleaseIdentity(publicKey: publicKey)

let artifactData = try Data(contentsOf: URL(fileURLWithPath: zipPath))
guard manifest.artifact.sha256 == SHA256.hash(data: artifactData).map({ String(format: "%02x", $0) }).joined() else {
    throw VerificationError.invalidArtifactChecksum
}
guard manifest.artifact.sizeBytes == artifactData.count else {
    throw VerificationError.invalidArtifactSize
}

let appcast = try XMLDocument(contentsOf: URL(fileURLWithPath: appcastPath), options: [])
let matchingEnclosure = try appcast.nodes(forXPath: "//enclosure[@url='\(artifactURL)']").first as? XMLElement
guard matchingEnclosure?.attribute(
    forLocalName: "edSignature",
    uri: "http://www.andymatuschak.org/xml-namespaces/sparkle",
)?.stringValue == manifest.artifact.sparkleEd25519Signature else {
    throw VerificationError.invalidArtifactSignature
}

let unzip = Process()
unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
unzip.arguments = ["-p", zipPath, "Voyager.app/Contents/Info.plist"]
let output = Pipe()
unzip.standardOutput = output
try unzip.run()
unzip.waitUntilExit()
guard unzip.terminationStatus == 0,
      let info = try PropertyListSerialization.propertyList(
          from: output.fileHandleForReading.readDataToEndOfFile(),
          options: [],
          format: nil,
      ) as? [String: Any],
      info["VOYAGER_RELEASED_AT"] as? String == releasedAt,
      manifest.releasedAt == releasedAt
else {
    throw VerificationError.invalidBundleTimestamp
}
