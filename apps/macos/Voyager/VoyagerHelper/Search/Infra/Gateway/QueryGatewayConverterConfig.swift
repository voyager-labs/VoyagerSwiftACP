import Foundation

enum QueryGatewayConverterConfig {
    static let requestTimeout: TimeInterval = 20
    static let modelName = "gpt-5-mini-2025-08-07"
    static let gatewayToken = "gateway"

    static let coreKeys: Set<String> = [
        "name_full",
        "extension",
        "content_type_tree",
        "file_allocated_size",
        "size",
        "downloaded_date",
        "modification_date",
        "creation_date",
        "path",
    ]

    static let scopePatterns: [(pattern: String, suffix: String)] = [
        ("\\bdownloads?\\b", "Downloads"),
        ("\\bdocuments?\\b", "Documents"),
        ("\\bdesktop\\b", "Desktop"),
        ("\\bhome folder\\b|\\bhome directory\\b", ""),
    ]

    static let outputSchema: [String: JSONValue] = {
        let conditionValueSchema = JSONValue.object([
            "anyOf": .array([
                .object(["type": .string("string")]),
                .object(["type": .string("number")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("number")]),
                ]),
                .object(["type": .string("null")]),
            ]),
        ])

        let conditionSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "propertyKey": .object(["type": .string("string")]),
                "operator": .object(["type": .string("string")]),
                "value": conditionValueSchema,
            ]),
            "required": .array([
                .string("propertyKey"),
                .string("operator"),
                .string("value"),
            ]),
            "additionalProperties": .bool(false),
        ])

        return [
            "type": .string("object"),
            "properties": .object([
                "conditions": .object([
                    "type": .string("array"),
                    "items": conditionSchema,
                ]),
                "scopes": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                        ]),
                        .object(["type": .string("null")]),
                    ]),
                ]),
                "error": .object([
                    "anyOf": .array([
                        .object(["type": .string("string")]),
                        .object(["type": .string("null")]),
                    ]),
                ]),
            ]),
            "required": .array([
                .string("conditions"),
                .string("scopes"),
                .string("error"),
            ]),
            "additionalProperties": .bool(false),
        ]
    }()
}
