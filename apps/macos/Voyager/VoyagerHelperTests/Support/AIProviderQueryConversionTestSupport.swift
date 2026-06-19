import Foundation
import VoyagerEntitiesAi
@testable import VoyagerHelper
import VoyagerShared
import XCTest

final class ConnectionFileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AIConnectionsFile

    init(_ file: AIConnectionsFile) {
        self.file = file
    }

    var client: AIConnectionsFileClient {
        AIConnectionsFileClient(
            load: { [self] in get() },
            save: { .success($0) },
            deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
        )
    }

    func set(_ file: AIConnectionsFile) {
        lock.lock()
        self.file = file
        lock.unlock()
    }

    private func get() -> AIConnectionsFile {
        lock.lock()
        let file = file
        lock.unlock()
        return file
    }
}

final class ModelLoadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [[AiProvider: [AiProviderModel]]]
    private var counts: [AiProvider: Int] = [:]

    init(responses: [AiProvider: [AiProviderModel]]) {
        self.responses = [responses]
    }

    init(sequence: [[AiProvider: [AiProviderModel]]]) {
        responses = sequence
    }

    var client: AiProviderModelListClient {
        AiProviderModelListClient(loadModels: { [self] provider, _ in
            loadModels(for: provider)
        })
    }

    func loadCount(for provider: AiProvider) -> Int {
        lock.lock()
        let count = counts[provider, default: 0]
        lock.unlock()
        return count
    }

    private func loadModels(for provider: AiProvider) -> [AiProviderModel] {
        lock.lock()
        let count = counts[provider, default: 0]
        counts[provider] = count + 1
        let responseIndex = min(count, max(responses.count - 1, 0))
        let models = responses[responseIndex][provider, default: []]
        lock.unlock()
        return models
    }
}

extension Result {
    var successValue: Success? {
        if case let .success(value) = self { return value }
        return nil
    }
}

final class AiChatRequestCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequest: AiChatRequest?

    var request: AiChatRequest? {
        lock.lock()
        let request = capturedRequest
        lock.unlock()
        return request
    }

    func store(_ request: AiChatRequest) {
        lock.lock()
        capturedRequest = request
        lock.unlock()
    }
}
