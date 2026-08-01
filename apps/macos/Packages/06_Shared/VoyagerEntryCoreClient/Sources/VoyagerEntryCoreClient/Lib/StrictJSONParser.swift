import Foundation

indirect enum StrictJSONValue: Equatable {
    case object([StrictJSONMember])
    case array([StrictJSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    func field(named name: String) -> StrictJSONValue? {
        guard case let .object(members) = self else {
            return nil
        }
        return members.first { $0.name.utf8.elementsEqual(name.utf8) }?.value
    }

    func objectFields(exactly names: Set<String>) -> [String: StrictJSONValue]? {
        guard case let .object(members) = self, members.count == names.count else {
            return nil
        }

        var fields: [String: StrictJSONValue] = [:]
        for member in members {
            guard let exactName = names.first(where: { member.name.utf8.elementsEqual($0.utf8) }) else {
                return nil
            }
            fields[exactName] = member.value
        }
        return fields.count == names.count ? fields : nil
    }
}

struct StrictJSONMember: Equatable {
    let name: String
    let value: StrictJSONValue
}

enum StrictJSONParser {
    static let maximumWireBytes = 65536
    static let maximumDepth = 512

    static func parse(_ raw: [UInt8]) throws -> StrictJSONValue {
        guard raw.count <= maximumWireBytes else {
            throw ParseError.invalidJSON
        }
        var parser = Parser(raw: raw)
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw ParseError.invalidJSON
        }
        return value
    }
}

private extension StrictJSONParser {
    enum ParseError: Error {
        case invalidJSON
    }

    struct Parser {
        let raw: [UInt8]
        var index = 0

        var isAtEnd: Bool {
            index == raw.count
        }

        mutating func parseValue(depth: Int) throws -> StrictJSONValue {
            guard depth <= StrictJSONParser.maximumDepth, index < raw.count else {
                throw ParseError.invalidJSON
            }

            switch raw[index] {
            case CharacterByte.leftBrace:
                return try parseObject(depth: depth)
            case CharacterByte.leftBracket:
                return try parseArray(depth: depth)
            case CharacterByte.quote:
                return try .string(parseString())
            case CharacterByte.lowerT:
                try consumeLiteral([
                    CharacterByte.lowerT,
                    CharacterByte.r,
                    CharacterByte.lowerU,
                    CharacterByte.e,
                ])
                return .bool(true)
            case CharacterByte.lowerF:
                try consumeLiteral([
                    CharacterByte.lowerF,
                    CharacterByte.a,
                    CharacterByte.lowerL,
                    CharacterByte.lowerS,
                    CharacterByte.e,
                ])
                return .bool(false)
            case CharacterByte.lowerN:
                try consumeLiteral([
                    CharacterByte.lowerN,
                    CharacterByte.lowerU,
                    CharacterByte.lowerL,
                    CharacterByte.lowerL,
                ])
                return .null
            case CharacterByte.minus, CharacterByte.zero ... CharacterByte.nine:
                return try .number(parseNumber())
            default:
                throw ParseError.invalidJSON
            }
        }

        mutating func parseObject(depth: Int) throws -> StrictJSONValue {
            index += 1
            skipWhitespace()
            var members: [StrictJSONMember] = []
            var names: Set<[UInt8]> = []
            if consume(CharacterByte.rightBrace) {
                return .object(members)
            }

            while true {
                guard currentByte == CharacterByte.quote else {
                    throw ParseError.invalidJSON
                }
                let name = try parseString()
                guard names.insert(Array(name.utf8)).inserted else {
                    throw ParseError.invalidJSON
                }
                skipWhitespace()
                guard consume(CharacterByte.colon) else {
                    throw ParseError.invalidJSON
                }
                skipWhitespace()
                let value = try parseValue(depth: depth + 1)
                members.append(StrictJSONMember(name: name, value: value))
                skipWhitespace()
                if consume(CharacterByte.rightBrace) {
                    return .object(members)
                }
                guard consume(CharacterByte.comma) else {
                    throw ParseError.invalidJSON
                }
                skipWhitespace()
            }
        }

        mutating func parseArray(depth: Int) throws -> StrictJSONValue {
            index += 1
            skipWhitespace()
            var items: [StrictJSONValue] = []
            if consume(CharacterByte.rightBracket) {
                return .array(items)
            }

            while true {
                try items.append(parseValue(depth: depth + 1))
                skipWhitespace()
                if consume(CharacterByte.rightBracket) {
                    return .array(items)
                }
                guard consume(CharacterByte.comma) else {
                    throw ParseError.invalidJSON
                }
                skipWhitespace()
            }
        }

        mutating func parseString() throws -> String {
            index += 1
            var decoded: [UInt8] = []

            while index < raw.count {
                let byte = raw[index]
                switch byte {
                case CharacterByte.quote:
                    index += 1
                    guard let value = String(bytes: decoded, encoding: .utf8) else {
                        throw ParseError.invalidJSON
                    }
                    return value
                case CharacterByte.backslash:
                    index += 1
                    try parseEscape(into: &decoded)
                case 0x00 ... 0x1F:
                    throw ParseError.invalidJSON
                default:
                    decoded.append(byte)
                    index += 1
                }
            }
            throw ParseError.invalidJSON
        }

        mutating func parseEscape(into decoded: inout [UInt8]) throws {
            guard index < raw.count else {
                throw ParseError.invalidJSON
            }

            let escaped = raw[index]
            index += 1
            switch escaped {
            case CharacterByte.quote, CharacterByte.backslash, CharacterByte.slash:
                decoded.append(escaped)
            case CharacterByte.b:
                decoded.append(0x08)
            case CharacterByte.lowerF:
                decoded.append(0x0C)
            case CharacterByte.lowerN:
                decoded.append(0x0A)
            case CharacterByte.r:
                decoded.append(0x0D)
            case CharacterByte.lowerT:
                decoded.append(0x09)
            case CharacterByte.lowerU:
                try parseUnicodeEscape(into: &decoded)
            default:
                throw ParseError.invalidJSON
            }
        }

        mutating func parseUnicodeEscape(into decoded: inout [UInt8]) throws {
            let first = try parseHexCodeUnit()
            let scalarValue: UInt32
            if (0xD800 ... 0xDBFF).contains(first) {
                guard consume(CharacterByte.backslash), consume(CharacterByte.lowerU) else {
                    throw ParseError.invalidJSON
                }
                let second = try parseHexCodeUnit()
                guard (0xDC00 ... 0xDFFF).contains(second) else {
                    throw ParseError.invalidJSON
                }
                scalarValue = 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
            } else {
                guard !(0xDC00 ... 0xDFFF).contains(first) else {
                    throw ParseError.invalidJSON
                }
                scalarValue = UInt32(first)
            }
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw ParseError.invalidJSON
            }
            decoded.append(contentsOf: String(scalar).utf8)
        }

        mutating func parseHexCodeUnit() throws -> UInt16 {
            guard index + 4 <= raw.count else {
                throw ParseError.invalidJSON
            }
            var value: UInt16 = 0
            for _ in 0 ..< 4 {
                guard let digit = hexValue(raw[index]) else {
                    throw ParseError.invalidJSON
                }
                value = value * 16 + UInt16(digit)
                index += 1
            }
            return value
        }

        mutating func parseNumber() throws -> String {
            let start = index
            _ = consume(CharacterByte.minus)
            guard index < raw.count else {
                throw ParseError.invalidJSON
            }

            if consume(CharacterByte.zero) {
                guard currentByte.map({ !isDigit($0) }) ?? true else {
                    throw ParseError.invalidJSON
                }
            } else {
                guard currentByte.map(isDigitOneToNine) == true else {
                    throw ParseError.invalidJSON
                }
                consumeDigits()
            }

            if consume(CharacterByte.period) {
                guard currentByte.map(isDigit) == true else {
                    throw ParseError.invalidJSON
                }
                consumeDigits()
            }

            if currentByte == CharacterByte.lowerE || currentByte == CharacterByte.upperE {
                index += 1
                if currentByte == CharacterByte.plus || currentByte == CharacterByte.minus {
                    index += 1
                }
                guard currentByte.map(isDigit) == true else {
                    throw ParseError.invalidJSON
                }
                consumeDigits()
            }

            guard let number = String(bytes: raw[start ..< index], encoding: .utf8) else {
                throw ParseError.invalidJSON
            }
            return number
        }

        mutating func consumeDigits() {
            while currentByte.map(isDigit) == true {
                index += 1
            }
        }

        mutating func consumeLiteral(_ literal: [UInt8]) throws {
            guard raw[index...].starts(with: literal) else {
                throw ParseError.invalidJSON
            }
            index += literal.count
        }

        mutating func skipWhitespace() {
            while let byte = currentByte, CharacterByte.whitespace.contains(byte) {
                index += 1
            }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard currentByte == byte else {
                return false
            }
            index += 1
            return true
        }

        var currentByte: UInt8? {
            index < raw.count ? raw[index] : nil
        }

        func isDigit(_ byte: UInt8) -> Bool {
            (CharacterByte.zero ... CharacterByte.nine).contains(byte)
        }

        func isDigitOneToNine(_ byte: UInt8) -> Bool {
            (CharacterByte.one ... CharacterByte.nine).contains(byte)
        }

        func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case CharacterByte.zero ... CharacterByte.nine:
                byte - CharacterByte.zero
            case CharacterByte.a ... CharacterByte.lowerF:
                byte - CharacterByte.a + 10
            case CharacterByte.upperA ... CharacterByte.upperF:
                byte - CharacterByte.upperA + 10
            default:
                nil
            }
        }
    }

    enum CharacterByte {
        static let whitespace: Set<UInt8> = [space, tab, lineFeed, carriageReturn]
        static let tab: UInt8 = 0x09
        static let lineFeed: UInt8 = 0x0A
        static let carriageReturn: UInt8 = 0x0D
        static let space: UInt8 = 0x20
        static let quote: UInt8 = 0x22
        static let plus: UInt8 = 0x2B
        static let comma: UInt8 = 0x2C
        static let minus: UInt8 = 0x2D
        static let period: UInt8 = 0x2E
        static let slash: UInt8 = 0x2F
        static let zero: UInt8 = 0x30
        static let one: UInt8 = 0x31
        static let nine: UInt8 = 0x39
        static let colon: UInt8 = 0x3A
        static let upperA: UInt8 = 0x41
        static let upperE: UInt8 = 0x45
        static let lowerE: UInt8 = 0x65
        static let upperF: UInt8 = 0x46
        static let leftBracket: UInt8 = 0x5B
        static let backslash: UInt8 = 0x5C
        static let rightBracket: UInt8 = 0x5D
        static let a: UInt8 = 0x61
        static let b: UInt8 = 0x62
        static let e: UInt8 = 0x65
        static let lowerF: UInt8 = 0x66
        static let lowerL: UInt8 = 0x6C
        static let lowerN: UInt8 = 0x6E
        static let r: UInt8 = 0x72
        static let lowerS: UInt8 = 0x73
        static let lowerT: UInt8 = 0x74
        static let lowerU: UInt8 = 0x75
        static let rightBrace: UInt8 = 0x7D
        static let leftBrace: UInt8 = 0x7B
    }
}
