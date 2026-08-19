import Foundation

public struct ProductAnalyticsEventName: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ProductAnalyticsEventVersion: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ProductAnalyticsPropertyValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = try .string(container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        }
    }
}

public struct ProductAnalyticsEvent: Codable, Equatable, Sendable {
    public let eventName: ProductAnalyticsEventName
    public let eventVersion: ProductAnalyticsEventVersion
    public let occurredAtUTC: Date
    public let environment: String
    public let distinctID: String?
    public let appVersion: String
    public let platform: String
    public let source: String
    public let properties: [String: ProductAnalyticsPropertyValue]

    public init(
        eventName: ProductAnalyticsEventName,
        occurredAtUTC: Date,
        environment: String,
        distinctID: String?,
        appVersion: String,
        platform: String,
        source: String,
        properties: [String: ProductAnalyticsPropertyValue],
        eventVersion: ProductAnalyticsEventVersion = .init(rawValue: "1"),
    ) {
        self.eventName = eventName
        self.eventVersion = eventVersion
        self.occurredAtUTC = occurredAtUTC
        self.environment = environment
        self.distinctID = distinctID
        self.appVersion = appVersion
        self.platform = platform
        self.source = source
        self.properties = properties
    }
}

public enum ProductAnalyticsIdentity: Equatable, Sendable {
    case device(String?)
    case anonymous
    case none
}

public struct ProductAnalyticsCaptureRequest: Equatable, Sendable {
    public let event: ProductAnalyticsEvent

    public init(event: ProductAnalyticsEvent) {
        self.event = event
    }
}

public struct ProductAnalyticsEventContext: Equatable, Sendable {
    public let occurredAtUTC: Date
    public let environment: String
    public let appVersion: String
    public let platform: String
    public let source: String

    public init(
        occurredAtUTC: Date,
        environment: String,
        appVersion: String,
        platform: String,
        source: String,
    ) {
        self.occurredAtUTC = occurredAtUTC
        self.environment = environment
        self.appVersion = appVersion
        self.platform = platform
        self.source = source
    }
}
