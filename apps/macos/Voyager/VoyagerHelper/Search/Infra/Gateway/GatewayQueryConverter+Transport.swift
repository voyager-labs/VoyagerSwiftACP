import Foundation
import SwiftDotenv

extension GatewayQueryConverter {
    func requestGateway(systemPrompt: String, userPrompt: String) async throws -> String {
        let baseURL = try resolveGatewayURL()
        let endpoint = baseURL.appendingPathComponent("gateway/openai/v1/chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = GatewayQueryConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(GatewayQueryConfig.gatewayToken)", forHTTPHeaderField: "Authorization")

        let payload = GatewayChatRequest(
            model: GatewayQueryConfig.modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt),
            ],
            responseFormat: .init(
                type: "json_schema",
                jsonSchema: .init(
                    name: "search_conditions_output",
                    schema: GatewayQueryConfig.outputSchema,
                    strict: true,
                ),
            ),
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw GatewayQueryError.gatewayRequestEncodingFailed(error.localizedDescription)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayQueryError.gatewayResponseInvalid(statusCode: nil, details: nil)
        }
        guard 200 ..< 300 ~= http.statusCode else {
            let details = extractGatewayErrorMessage(from: data)
            throw GatewayQueryError.gatewayResponseInvalid(statusCode: http.statusCode, details: details)
        }

        return try extractMessageContent(from: data)
    }

    func resolveGatewayURL() throws -> URL {
        let raw = Dotenv["PUBLIC_GATEWAY_URL"]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw else {
            throw GatewayQueryError.gatewayURLMissing
        }
        guard raw.isEmpty == false else {
            throw GatewayQueryError.gatewayURLMissing
        }
        guard let url = URL(string: raw) else {
            throw GatewayQueryError.gatewayURLInvalid(raw)
        }
        return url
    }

    func extractGatewayErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let errorObject = root["error"] as? [String: Any]
        else {
            return nil
        }

        if let message = errorObject["message"] as? String {
            return message
        }
        return nil
    }

    func extractMessageContent(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            throw GatewayQueryError.gatewayResponseInvalid(statusCode: nil, details: nil)
        }

        guard let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any]
        else {
            throw GatewayQueryError.gatewayOutputMissing
        }

        if let content = message["content"] as? String,
           content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return content
        }

        if let contents = message["content"] as? [[String: Any]] {
            let merged = contents.compactMap { item -> String? in
                if let text = item["text"] as? String {
                    return text
                }
                return nil
            }
            .joined()
            if merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return merged
            }
        }

        throw GatewayQueryError.gatewayOutputMissing
    }

    func decodeGatewayOutput(from content: String) throws -> GatewayOutput {
        let normalized = stripCodeFence(content)
        guard let data = normalized.data(using: .utf8) else {
            throw GatewayQueryError.gatewayDecodeFailed("invalid utf8 content")
        }
        do {
            return try JSONDecoder().decode(GatewayOutput.self, from: data)
        } catch {
            throw GatewayQueryError.gatewayDecodeFailed(error.localizedDescription)
        }
    }

    func stripCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return trimmed }
        var mutable = lines
        mutable.removeFirst()
        if mutable.last?.hasPrefix("```") == true {
            mutable.removeLast()
        }
        return mutable.joined(separator: "\n")
    }
}

private struct GatewayChatRequest: Encodable {
    let model: String
    let messages: [GatewayChatMessage]
    let responseFormat: GatewayResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
    }
}

private struct GatewayResponseFormat: Encodable {
    let type: String
    let jsonSchema: GatewayJSONSchema

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct GatewayJSONSchema: Encodable {
    let name: String
    let schema: [String: JSONValue]
    let strict: Bool
}

private struct GatewayChatMessage: Encodable {
    let role: String
    let content: String
}

struct GatewayOutput: Decodable {
    let conditions: [SearchConditionPayload]?
    let scopes: [String]?
    let error: String?
}

struct GatewayQueryResult: Sendable {
    let conditions: [SearchConditionPayload]
    let scopes: [String]?
    let error: String?
}

enum GatewayQueryError: Error {
    case registryUnavailable
    case promptTemplateMissing(String)
    case promptTemplateLoadFailed(String)
    case promptTemplateInvalid(String)
    case gatewayURLMissing
    case gatewayURLInvalid(String)
    case gatewayRequestEncodingFailed(String)
    case gatewayResponseInvalid(statusCode: Int?, details: String?)
    case gatewayOutputMissing
    case gatewayDecodeFailed(String)
}
