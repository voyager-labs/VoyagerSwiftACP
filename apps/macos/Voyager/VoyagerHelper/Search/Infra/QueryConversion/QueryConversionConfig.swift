import VoyagerEntitiesAi
import VoyagerShared

enum QueryConversionConfig {
    static let coreKeys: Set<String> = [
        "name_full",
        "extension",
        "content_type_tree",
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

    static let responseContract = AiChatProviderResponseContract(
        name: "search_conditions_output",
        schema: outputSchema,
        strict: true,
    )

    private static let outputSchema: [String: JSONValue] = [
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([.string("conditions"), .string("scopes"), .string("error")]),
        "properties": .object([
            "conditions": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("propertyKey"), .string("operator"), .string("value")]),
                    "properties": .object([
                        "propertyKey": .object(["type": .string("string")]),
                        "operator": .object(["type": .string("string")]),
                        "value": .object([
                            "anyOf": .array([
                                .object(["type": .string("string")]),
                                .object(["type": .string("number")]),
                                .object(["type": .string("boolean")]),
                                .object([
                                    "type": .string("array"),
                                    "items": .object([
                                        "anyOf": .array([
                                            .object(["type": .string("string")]),
                                            .object(["type": .string("number")]),
                                            .object(["type": .string("boolean")]),
                                        ]),
                                    ]),
                                ]),
                                .object(["type": .string("null")]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            "scopes": .object([
                "anyOf": .array([
                    .object(["type": .string("null")]),
                    .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
            ]),
            "error": .object([
                "anyOf": .array([
                    .object(["type": .string("null")]),
                    .object(["type": .string("string")]),
                ]),
            ]),
        ]),
    ]
}
