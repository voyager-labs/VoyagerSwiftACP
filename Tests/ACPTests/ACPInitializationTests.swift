//
//  ACPInitializationTests.swift
//  ACPTests
//
//  T5: initialization negotiation, capability gating, and terminal failure states.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPInitializationTests: XCTestCase {
    #if os(macOS)
    func testZeroArgumentInitializerFunctionReference() async {
        let factory: () -> Client = Client.init
        let client = factory()
        let state = await client.state
        XCTAssertEqual(state, .idle)
        _ = await client.shutdown()
    }
    #endif

    private static let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true,
    )

    private static func requestIDValue(_ id: RequestId) -> Int {
        if case let .number(value) = id {
            return value
        }
        return -1
    }

    private func requestID(_ id: RequestId) -> Int {
        if case let .number(value) = id {
            return value
        }
        return -1
    }

    @discardableResult
    private func respondToNextRequest(
        _ transport: ScriptedTransport,
        result: @autoclosure () throws -> String,
    ) async throws -> RequestId {
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        try await transport.pushJSON(TestFrames.response(id: requestID(request.id), result: result()))
        return request.id
    }

    private func makeReadyClient(
        _ transport: ScriptedTransport,
        capabilities: ClientCapabilities? = nil,
        initResult: String = TestFrames.initializeResult(version: 1),
    ) async throws -> Client {
        let client = Client(transport: transport)
        try await client.start()
        let initTask = spawnInitializeTask(client, capabilities: capabilities ?? Self.capabilities)
        _ = try await respondToNextRequest(transport, result: initResult)
        _ = try await initTask.value
        return client
    }

    /// I01
    func testInitializeSucceeds() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let state = await client.state
        XCTAssertEqual(state, .ready)
        let initialization = await client.initialization
        XCTAssertEqual(initialization?.protocolVersion, 1)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// I02
    func testAgentNegotiatesSupportedVersion() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(
            transport,
            initResult: #"{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"A","version":"1"}}"#,
        )

        let initialization = await client.initialization
        XCTAssertEqual(initialization?.protocolVersion, 1)
        XCTAssertEqual(initialization?.agentInfo?.name, "A")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// I03
    func testUnsupportedVersionClosesClient() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: TestFrames.initializeResult(version: 2))

        do {
            _ = try await initTask.value
            XCTFail("expected unsupported version failure")
        } catch let error as ClientError {
            guard case let .unsupportedProtocolVersion(version) = error else {
                return XCTFail("expected unsupportedProtocolVersion, got \(error)")
            }
            XCTAssertEqual(version, 2)
        }

        let state = await client.state
        XCTAssertEqual(state, .failed)

        // Session operations are rejected on the failed (terminal) connection.
        do {
            _ = try await client.newSession(workingDirectory: "/tmp", timeout: 5)
            XCTFail("expected terminal connection")
        } catch {
            // expected
        }
        // No session request was written to the wire (only initialize).
        let sent = transport.allSentFrames().count
        XCTAssertEqual(sent, 1)

        _ = await client.shutdown()
    }

    /// I04
    func testInvalidCapabilitiesFailInitialization() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(
            transport,
            result: #"{"protocolVersion":1,"agentCapabilities":{"loadSession":"yes"}}"#,
        )

        do {
            _ = try await initTask.value
            XCTFail("expected invalid capabilities rejection")
        } catch let error as ClientError {
            guard case .protocolViolation = error else {
                return XCTFail("expected protocolViolation, got \(error)")
            }
        }

        let state = await client.state
        XCTAssertEqual(state, .failed)

        _ = await client.shutdown()
    }

    /// I05
    func testSessionRequestBeforeInitializeRejected() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        do {
            _ = try await client.newSession(workingDirectory: "/tmp", timeout: 5)
            XCTFail("expected notInitialized")
        } catch let error as ClientError {
            guard case .notInitialized = error else {
                return XCTFail("expected notInitialized, got \(error)")
            }
        }

        let sent = transport.allSentFrames().count
        XCTAssertEqual(sent, 0)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// I06
    func testConcurrentInitializeRejected() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        let first = spawnInitializeTask(client, capabilities: Self.capabilities)
        let firstFrame = try await transport.nextSentFrame()
        let firstRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: firstFrame)

        do {
            _ = try await client.initialize(capabilities: Self.capabilities, timeout: 5)
            XCTFail("expected initializationInProgress")
        } catch let error as ClientError {
            guard case .initializationInProgress = error else {
                return XCTFail("expected initializationInProgress, got \(error)")
            }
        }

        try await transport.pushJSON(TestFrames.response(
            id: requestID(firstRequest.id),
            result: TestFrames.initializeResult(version: 1),
        ))
        _ = try await first.value

        await transport.finish()
        _ = await client.shutdown()
    }

    /// I07
    func testDuplicateInitializeRejected() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        do {
            _ = try await client.initialize(capabilities: Self.capabilities, timeout: 5)
            XCTFail("expected alreadyInitialized")
        } catch let error as ClientError {
            guard case .alreadyInitialized = error else {
                return XCTFail("expected alreadyInitialized, got \(error)")
            }
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    /// I08
    func testInitializeFailureIsTerminal() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        try await transport.pushJSON(TestFrames.responseError(
            id: Self.requestIDValue(request.id),
            code: -32000,
            message: "nope",
        ))

        do {
            _ = try await initTask.value
            XCTFail("expected agent error")
        } catch let error as ClientError {
            guard case .agentError = error else {
                return XCTFail("expected agentError, got \(error)")
            }
        }

        // The failed initialization makes the connection terminal.
        do {
            _ = try await client.initialize(capabilities: Self.capabilities, timeout: 5)
            XCTFail("expected terminal failure")
        } catch let error as ClientError {
            guard case .initializationFailed = error else {
                return XCTFail("expected initializationFailed, got \(error)")
            }
        }

        _ = await client.shutdown()
    }

    /// I09
    func testMissingCapabilitiesMeanUnsupported() async throws {
        let transport = ScriptedTransport()
        // The agent advertises no promptCapabilities.
        let client = try await makeReadyClient(transport, initResult: TestFrames.initializeResult(version: 1))

        // Register a session first.
        let sessionTask = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await respondToNextRequest(transport, result: #"{"sessionId":"s1"}"#)
        let session = try await sessionTask.value

        // A rich content block is rejected locally before any wire write.
        do {
            _ = try await client.sendPrompt(
                sessionId: session.sessionId,
                content: [.image(ImageContent(data: "aGk=", mimeType: "image/png"))],
                timeout: 5,
            )
            XCTFail("expected unsupported capability")
        } catch let error as ClientError {
            guard case .unsupportedCapability = error else {
                return XCTFail("expected unsupportedCapability, got \(error)")
            }
        }

        // Only initialize + session/new were written.
        XCTAssertEqual(transport.allSentFrames().count, 2)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// I10
    func testBufferedCallbackAfterProtocolFailureIsIgnored() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        let delegate = RecordingClientDelegate()
        await client.setDelegate(delegate)
        // Buffer both before starting so transport closure cannot prevent the
        // callback from already being queued behind the invalid envelope.
        try await transport.pushJSON("not-json")
        try await transport.pushJSON(TestFrames.request(
            id: 900,
            method: "session/request_permission",
            params: #"{"sessionId":"s1","options":[{"kind":"allow_once","name":"Allow","optionId":"allow"}],"toolCall":{"toolCallId":"tc-1","status":"pending","title":"t"}}"#,
        ))
        try await client.start()
        let notifications = await client.notifications
        for await _ in notifications {}
        try await Task.sleep(nanoseconds: 20_000_000)
        let events = await delegate.events
        XCTAssertFalse(events.contains("permission:s1"))
        await delegate.resolvePermission(RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true)))
        _ = await client.shutdown()
    }

    func testDelegateInstalledBeforeFirstCallback() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        let delegate = RecordingClientDelegate()
        await client.setDelegate(delegate)
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: TestFrames.initializeResult(version: 1))
        _ = try await initTask.value

        // An inbound permission request arrives right after initialization; the
        // pre-installed delegate must receive it without loss.
        try await transport.pushJSON(TestFrames.request(
            id: 900,
            method: "session/request_permission",
            params: #"{"sessionId":"s1","options":[{"kind":"allow_once","name":"Allow","optionId":"allow"}],"toolCall":{"toolCallId":"tc-1","status":"pending","title":"t"}}"#,
        ))
        await delegate.waitUntilPermissionRequested()
        await delegate.resolvePermission(RequestPermissionResponse(outcome: PermissionOutcome(optionId: "allow")))

        let events = await delegate.events
        XCTAssertTrue(events.contains("permission:s1"))

        await transport.finish()
        _ = await client.shutdown()
    }
}
