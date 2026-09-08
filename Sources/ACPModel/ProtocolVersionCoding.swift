import Foundation

enum ProtocolVersionCoding {
    /// ACP v1 protocolVersion values on the wire are integers in `0...65535`.
    /// Strings, null, booleans, and fractional numbers are rejected instead of
    /// being coerced into a supported version.
    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
    ) throws -> Int {
        guard container.contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: container.codingPath + [key],
                    debugDescription: "Missing protocolVersion",
                ),
            )
        }

        let rawValue = try container.decode(Int.self, forKey: key)
        guard (0 ... 65535).contains(rawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "protocolVersion \(rawValue) is outside the supported 0...65535 range",
            )
        }
        return rawValue
    }
}
