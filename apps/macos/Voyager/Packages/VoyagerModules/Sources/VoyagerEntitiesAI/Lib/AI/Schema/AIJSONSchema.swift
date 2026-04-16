// Portions adapted from Swift AI SDK (Apache-2.0).
// Original: Sources/AISDKJSONSchema/

import Foundation

public enum AIJSONSchema {
    public static func generate(for type: (some Codable & Sendable).Type) -> [String: Any] {
        guard let sample = try? DefaultValueFactory.make(type) else {
            return ["type": "object", "additionalProperties": true]
        }
        return buildSchema(from: sample)
    }

    private static func buildSchema(from value: Any) -> [String: Any] {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .struct || mirror.displayStyle == .class else {
            return inferTypeSchema(from: value)
        }

        var properties: [String: Any] = [:]
        var required: [String] = []

        for child in mirror.children {
            guard let label = child.label else { continue }
            properties[label] = inferTypeSchema(from: child.value)
            if !isOptional(child.value) {
                required.append(label)
            }
        }

        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    private static func inferTypeSchema(from value: Any) -> [String: Any] {
        if let optional = value as? AnyOptional, let wrapped = optional.wrappedValue {
            return inferTypeSchema(from: wrapped)
        }

        if value is String { return ["type": "string"] }
        if value is Bool { return ["type": "boolean"] }
        if value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64
            || value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64
        { return ["type": "integer"] }
        if value is Double || value is Float || value is Decimal { return ["type": "number"] }
        if value is Date { return ["type": "string", "format": "date-time"] }
        if value is URL { return ["type": "string", "format": "uri"] }

        if let caseIterable = type(of: value) as? any CaseIterable.Type {
            return buildEnumSchema(for: caseIterable, value: value)
        }

        if let array = value as? [Any], let first = array.first {
            return ["type": "array", "items": inferTypeSchema(from: first)]
        }

        return buildSchema(from: value)
    }

    private static func buildEnumSchema(for enumType: any CaseIterable.Type, value: Any) -> [String: Any] {
        let mirror = Mirror(reflecting: enumType.allCases)
        let cases = mirror.children.compactMap { child -> Any? in
            if let rawRep = child.value as? any RawRepresentable<String> { return rawRep.rawValue }
            return String(describing: child.value)
        }

        let baseType = if value is any RawRepresentable<String> { "string" }
        else if value is any RawRepresentable<Int> { "integer" }
        else { "string" }

        return ["type": baseType, "enum": cases]
    }

    private static func isOptional(_ value: Any) -> Bool {
        Mirror(reflecting: value).displayStyle == .optional
    }
}

private protocol AnyOptional {
    var wrappedValue: Any? { get }
}

extension Optional: AnyOptional {
    var wrappedValue: Any? {
        switch self {
        case let .some(value): value
        case .none: nil
        }
    }
}

private enum DefaultValueFactory {
    static func make<T: Decodable>(_ type: T.Type) throws -> T {
        if let value: T = makeKnown(type) { return value }
        return try T(from: PlaceholderDecoder())
    }

    private static func makeKnown<T: Decodable>(_ type: T.Type) -> T? {
        switch type {
        case is String.Type: return "" as? T
        case is Bool.Type: return false as? T
        case is Double.Type: return 0 as? T
        case is Float.Type: return 0 as? T
        case is Int.Type: return 0 as? T
        case is Int8.Type: return 0 as? T
        case is Int16.Type: return 0 as? T
        case is Int32.Type: return 0 as? T
        case is Int64.Type: return 0 as? T
        case is UInt.Type: return 0 as? T
        case is UInt8.Type: return 0 as? T
        case is UInt16.Type: return 0 as? T
        case is UInt32.Type: return 0 as? T
        case is UInt64.Type: return 0 as? T
        case is Date.Type: return Date(timeIntervalSince1970: 0) as? T
        case is URL.Type: return URL(string: "https://example.com") as? T
        default:
            if let array = type as? any AnyArray.Type { return try? array.sample() as? T }
            return nil
        }
    }
}

private protocol AnyArray {
    static func sample() throws -> Any
}

extension Array: AnyArray where Element: Decodable {
    static func sample() throws -> Any {
        try [DefaultValueFactory.make(Element.self)]
    }
}

private final class PlaceholderDecoder: @unchecked Sendable, Decoder {
    let codingPath: [CodingKey] = []
    let userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(PlaceholderKeyedContainer<Key>())
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        PlaceholderUnkeyedContainer()
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        PlaceholderSingleValueContainer()
    }
}

private struct PlaceholderKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let codingPath: [CodingKey] = []
    let allKeys: [Key] = []
    func contains(_: Key) -> Bool { true }
    func decodeNil(forKey _: Key) -> Bool { true }
    func decode(_: Bool.Type, forKey _: Key) -> Bool { false }
    func decode(_: String.Type, forKey _: Key) -> String { "" }
    func decode(_: Double.Type, forKey _: Key) -> Double { 0 }
    func decode(_: Float.Type, forKey _: Key) -> Float { 0 }
    func decode(_: Int.Type, forKey _: Key) -> Int { 0 }
    func decode(_: Int8.Type, forKey _: Key) -> Int8 { 0 }
    func decode(_: Int16.Type, forKey _: Key) -> Int16 { 0 }
    func decode(_: Int32.Type, forKey _: Key) -> Int32 { 0 }
    func decode(_: Int64.Type, forKey _: Key) -> Int64 { 0 }
    func decode(_: UInt.Type, forKey _: Key) -> UInt { 0 }
    func decode(_: UInt8.Type, forKey _: Key) -> UInt8 { 0 }
    func decode(_: UInt16.Type, forKey _: Key) -> UInt16 { 0 }
    func decode(_: UInt32.Type, forKey _: Key) -> UInt32 { 0 }
    func decode(_: UInt64.Type, forKey _: Key) -> UInt64 { 0 }
    func decode<T: Decodable>(_ type: T.Type, forKey _: Key) -> T {
        (try? DefaultValueFactory.make(type)) ?? unsafeBitCast(0, to: T.self)
    }

    func decodeIfPresent(_: Bool.Type, forKey _: Key) -> Bool? { nil }
    func decodeIfPresent(_: String.Type, forKey _: Key) -> String? { nil }
    func decodeIfPresent(_: Double.Type, forKey _: Key) -> Double? { nil }
    func decodeIfPresent(_: Int.Type, forKey _: Key) -> Int? { nil }
    func decodeIfPresent<T: Decodable>(_: T.Type, forKey _: Key) -> T? { nil }
    func nestedContainer<NestedKey: CodingKey>(keyedBy _: NestedKey.Type,
                                               forKey _: Key) throws
        -> KeyedDecodingContainer<NestedKey> { KeyedDecodingContainer(PlaceholderKeyedContainer<NestedKey>()) }
    func nestedUnkeyedContainer(forKey _: Key) throws -> UnkeyedDecodingContainer { PlaceholderUnkeyedContainer() }
    func superDecoder() throws -> Decoder { PlaceholderDecoder() }
    func superDecoder(forKey _: Key) throws -> Decoder { PlaceholderDecoder() }
}

private struct PlaceholderUnkeyedContainer: UnkeyedDecodingContainer {
    let codingPath: [CodingKey] = []
    let count: Int? = 1
    private var consumed = false
    var isAtEnd: Bool { consumed }
    var currentIndex: Int { consumed ? 1 : 0 }
    mutating func decodeNil() throws -> Bool { consumed = true
        return false
    }

    mutating func decode(_: Bool.Type) throws -> Bool { consumed = true
        return false
    }

    mutating func decode(_: String.Type) throws -> String { consumed = true
        return ""
    }

    mutating func decode(_: Double.Type) throws -> Double { consumed = true
        return 0
    }

    mutating func decode(_: Float.Type) throws -> Float { consumed = true
        return 0
    }

    mutating func decode(_: Int.Type) throws -> Int { consumed = true
        return 0
    }

    mutating func decode(_: Int8.Type) throws -> Int8 { consumed = true
        return 0
    }

    mutating func decode(_: Int16.Type) throws -> Int16 { consumed = true
        return 0
    }

    mutating func decode(_: Int32.Type) throws -> Int32 { consumed = true
        return 0
    }

    mutating func decode(_: Int64.Type) throws -> Int64 { consumed = true
        return 0
    }

    mutating func decode(_: UInt.Type) throws -> UInt { consumed = true
        return 0
    }

    mutating func decode(_: UInt8.Type) throws -> UInt8 { consumed = true
        return 0
    }

    mutating func decode(_: UInt16.Type) throws -> UInt16 { consumed = true
        return 0
    }

    mutating func decode(_: UInt32.Type) throws -> UInt32 { consumed = true
        return 0
    }

    mutating func decode(_: UInt64.Type) throws -> UInt64 { consumed = true
        return 0
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        consumed = true
        return (try? DefaultValueFactory.make(type)) ?? unsafeBitCast(0, to: T.self)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy _: NestedKey
        .Type) throws -> KeyedDecodingContainer<NestedKey>
    {
        KeyedDecodingContainer(PlaceholderKeyedContainer<NestedKey>())
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        PlaceholderUnkeyedContainer()
    }

    func superDecoder() throws -> Decoder { PlaceholderDecoder() }
}

private struct PlaceholderSingleValueContainer: SingleValueDecodingContainer {
    let codingPath: [CodingKey] = []
    func decodeNil() -> Bool { true }
    func decode(_: Bool.Type) -> Bool { false }
    func decode(_: String.Type) -> String { "" }
    func decode(_: Double.Type) -> Double { 0 }
    func decode(_: Int.Type) -> Int { 0 }
    func decode<T: Decodable>(_ type: T.Type) -> T {
        (try? DefaultValueFactory.make(type)) ?? unsafeBitCast(0, to: T.self)
    }
}
