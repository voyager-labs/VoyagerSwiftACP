@testable import ACP
import ACPModel
import Foundation

@discardableResult
nonisolated func spawnInitializeTask(
    _ client: Client,
    capabilities: ClientCapabilities,
    timeout: TimeInterval = 5,
) -> Task<InitializeResponse, Error> {
    Task { try await client.initialize(capabilities: capabilities, timeout: timeout) }
}

@discardableResult
nonisolated func spawnNewSessionTask(
    _ client: Client,
    cwd: String,
    timeout: TimeInterval = 5,
) -> Task<NewSessionResponse, Error> {
    Task { try await client.newSession(workingDirectory: cwd, timeout: timeout) }
}

nonisolated func spawnListSessionsTask(_ client: Client, cwd: String) -> Task<Void, Never> {
    Task {
        _ = try? await client.sendRequest(method: "session/list", params: ListSessionsRequest(cwd: cwd), timeout: nil)
    }
}

nonisolated func spawnPushJSON(_ transport: ScriptedTransport, json: String) -> Task<Void, Error> {
    Task { try await transport.pushJSON(json) }
}
