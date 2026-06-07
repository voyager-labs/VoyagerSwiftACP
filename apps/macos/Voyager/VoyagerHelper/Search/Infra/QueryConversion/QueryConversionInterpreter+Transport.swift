import Foundation
import VoyagerShared

extension QueryConversionInterpreter {
    func decodeQueryConversionOutput(from content: String) throws -> QueryConversionOutput {
        let normalized = stripCodeFence(content)
        guard let data = normalized.data(using: .utf8) else {
            throw QueryConversionError.outputDecodeFailed("invalid utf8 content")
        }
        do {
            return try JSONDecoder().decode(QueryConversionOutput.self, from: data)
        } catch {
            throw QueryConversionError.outputDecodeFailed(error.localizedDescription)
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

struct QueryConversionOutput: Decodable {
    let conditions: [SearchConditionPayload]?
    let scopes: [String]?
    let error: String?
}

struct QueryConversionPromptPayload: Equatable {
    let systemPrompt: String
    let userPrompt: String
}

enum QueryConversionResultOutcome: Equatable {
    case generatedChangeSet
    case unchangedResult
    case fallbackReuse
    case providerNotConfigured
    case invalidCredential
    case providerUnavailable
    case networkFailure
    case conversionFailure
}

struct QueryConversionResult: Equatable {
    let conditions: [SearchConditionPayload]
    let scopes: [String]?
    let error: String?
    let outcome: QueryConversionResultOutcome
    let providerId: String?
    let errorCode: String?
    let reason: String?

    init(
        conditions: [SearchConditionPayload],
        scopes: [String]?,
        error: String?,
        outcome: QueryConversionResultOutcome,
        providerId: String? = nil,
        errorCode: String? = nil,
        reason: String? = nil,
    ) {
        self.conditions = conditions
        self.scopes = scopes
        self.error = error
        self.outcome = outcome
        self.providerId = providerId
        self.errorCode = errorCode
        self.reason = reason
    }
}

enum QueryConversionError: Error {
    case registryUnavailable
    case promptTemplateMissing(String)
    case promptTemplateLoadFailed(String)
    case promptTemplateInvalid(String)
    case outputDecodeFailed(String)
}
