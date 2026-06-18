import Foundation
@testable import VoyagerEntitiesAi
import XCTest

func decodeOpenAIRequestBody(_ request: URLRequest) throws -> PayloadCapturedOpenAIRequestBody {
    let body = try XCTUnwrap(request.httpBody)
    return try JSONDecoder().decode(PayloadCapturedOpenAIRequestBody.self, from: body)
}

func decodeAnthropicRequestBody(_ request: URLRequest) throws -> PayloadCapturedAnthropicRequestBody {
    let body = try XCTUnwrap(request.httpBody)
    return try JSONDecoder().decode(PayloadCapturedAnthropicRequestBody.self, from: body)
}

struct PayloadCapturedOpenAIRequestBody: Decodable {
    let input: [PayloadCapturedOpenAIInputItem]
    let reasoning: PayloadCapturedOpenAIReasoning?
}

struct PayloadCapturedOpenAIInputItem: Decodable {
    let type: String?
    let role: String
    let content: PayloadCapturedOpenAIContent
}

enum PayloadCapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([PayloadCapturedOpenAIContentItem])

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [PayloadCapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .parts(container.decode([PayloadCapturedOpenAIContentItem].self))
    }
}

struct PayloadCapturedOpenAIContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let detail: String?
    let imageURL: String?
    let fileData: String?
    let filename: String?

    init(
        type: String,
        text: String? = nil,
        detail: String? = nil,
        imageURL: String? = nil,
        fileData: String? = nil,
        filename: String? = nil,
    ) {
        self.type = type
        self.text = text
        self.detail = detail
        self.imageURL = imageURL
        self.fileData = fileData
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case detail
        case imageURL = "image_url"
        case fileData = "file_data"
        case filename
    }
}

struct PayloadCapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

struct PayloadCapturedAnthropicRequestBody: Decodable {
    let messages: [PayloadCapturedAnthropicMessage]
    let system: String?
}

struct PayloadCapturedAnthropicMessage: Decodable {
    let role: String
    let content: [PayloadCapturedAnthropicContentItem]
}

struct PayloadCapturedAnthropicContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let source: PayloadCapturedAnthropicSource?
    let title: String?

    static func text(_ value: String) -> Self {
        .init(type: "text", text: value, source: nil, title: nil)
    }

    static func image(mediaType: String, data: String) -> Self {
        .init(
            type: "image",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: nil,
        )
    }

    static func document(mediaType: String, data: String, title: String) -> Self {
        .init(
            type: "document",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: title,
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }
}

struct PayloadCapturedAnthropicSource: Decodable, Equatable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}
