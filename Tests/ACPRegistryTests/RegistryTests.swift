@testable import ACPRegistry
import XCTest

final class RegistryTests: XCTestCase {
    // MARK: - Type Tests

    func testRegistryAgentDecoding() throws {
        let json = """
        {
            "id": "claude-acp",
            "name": "Claude Agent",
            "version": "0.21.0",
            "description": "ACP wrapper for Anthropic's Claude",
            "repository": "https://github.com/zed-industries/claude-agent-acp",
            "authors": ["Anthropic"],
            "license": "proprietary",
            "distribution": {
                "npx": {
                    "package": "@zed-industries/claude-agent-acp@0.21.0"
                }
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let agent = try JSONDecoder().decode(RegistryAgent.self, from: data)

        XCTAssertEqual(agent.id, "claude-acp")
        XCTAssertEqual(agent.name, "Claude Agent")
        XCTAssertEqual(agent.version, "0.21.0")
        XCTAssertEqual(agent.authors, ["Anthropic"])
        XCTAssertEqual(agent.license, "proprietary")
        XCTAssertNotNil(agent.distribution.npx)
        XCTAssertEqual(agent.distribution.npx?.package, "@zed-industries/claude-agent-acp@0.21.0")
    }

    func testBinaryDistributionDecoding() throws {
        let json = """
        {
            "id": "test-agent",
            "name": "Test Agent",
            "version": "1.0.0",
            "description": "Test",
            "distribution": {
                "binary": {
                    "darwin-aarch64": {
                        "archive": "https://example.com/agent-darwin-arm64.tar.gz",
                        "cmd": "./agent",
                        "args": ["serve"],
                        "env": {"API_KEY": "test"}
                    }
                }
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let agent = try JSONDecoder().decode(RegistryAgent.self, from: data)

        XCTAssertNotNil(agent.distribution.binary)
        let darwinTarget = agent.distribution.binary?["darwin-aarch64"]
        XCTAssertNotNil(darwinTarget)
        XCTAssertEqual(darwinTarget?.archive, "https://example.com/agent-darwin-arm64.tar.gz")
        XCTAssertEqual(darwinTarget?.cmd, "./agent")
        XCTAssertEqual(darwinTarget?.args, ["serve"])
        XCTAssertEqual(darwinTarget?.env?["API_KEY"], "test")
    }

    func testBinaryArchiveKindDetection() throws {
        XCTAssertEqual(
            try AgentInstaller.binaryArchiveKind(for: XCTUnwrap(URL(string: "https://example.com/agent.zip"))),
            .zip,
        )
        XCTAssertEqual(
            try AgentInstaller.binaryArchiveKind(for: XCTUnwrap(URL(string: "https://example.com/agent.tar.gz"))),
            .tarGzip,
        )
        XCTAssertEqual(
            try AgentInstaller.binaryArchiveKind(for: XCTUnwrap(URL(string: "https://example.com/agent.tgz"))),
            .tarGzip,
        )
        XCTAssertEqual(
            try AgentInstaller.binaryArchiveKind(for: XCTUnwrap(URL(string: "https://example.com/agent.tar.bz2"))),
            .tarBzip2,
        )
        XCTAssertEqual(
            try AgentInstaller.binaryArchiveKind(for: XCTUnwrap(URL(string: "https://example.com/agent.tbz2"))),
            .tarBzip2,
        )
        XCTAssertEqual(
            try AgentInstaller.binaryArchiveKind(for: XCTUnwrap(URL(string: "https://example.com/agent"))),
            .rawBinary,
        )
    }

    func testRegistryDecoding() throws {
        let json = """
        {
            "version": "1.0.0",
            "agents": [
                {
                    "id": "agent1",
                    "name": "Agent 1",
                    "version": "1.0.0",
                    "description": "First agent",
                    "distribution": {
                        "npx": {"package": "agent1"}
                    }
                },
                {
                    "id": "agent2",
                    "name": "Agent 2",
                    "version": "2.0.0",
                    "description": "Second agent",
                    "distribution": {
                        "uvx": {"package": "agent2"}
                    }
                }
            ],
            "extensions": []
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let registry = try JSONDecoder().decode(Registry.self, from: data)

        XCTAssertEqual(registry.version, "1.0.0")
        XCTAssertEqual(registry.agents.count, 2)
        XCTAssertEqual(registry.agents[0].id, "agent1")
        XCTAssertEqual(registry.agents[1].id, "agent2")
        XCTAssertTrue(registry.extensions.isEmpty)
    }

    // MARK: - Platform Tests

    func testPlatformIdentifier() {
        let darwin = Platform(os: .darwin, arch: .aarch64)
        XCTAssertEqual(darwin.identifier, "darwin-aarch64")

        let linux = Platform(os: .linux, arch: .x86_64)
        XCTAssertEqual(linux.identifier, "linux-x86_64")

        let windows = Platform(os: .windows, arch: .aarch64)
        XCTAssertEqual(windows.identifier, "windows-aarch64")
    }

    func testCurrentPlatform() {
        let current = Platform.current
        #if os(macOS)
        XCTAssertEqual(current.os, .darwin)
        #elseif os(Linux)
        XCTAssertEqual(current.os, .linux)
        #endif

        #if arch(arm64)
        XCTAssertEqual(current.arch, .aarch64)
        #elseif arch(x86_64)
        XCTAssertEqual(current.arch, .x86_64)
        #endif
    }

    // MARK: - Distribution Preference Tests

    func testDistributionPrefersBinary() {
        let distribution = Distribution(
            binary: ["darwin-aarch64": BinaryTarget(archive: "https://example.com/a.tar.gz", cmd: "./a")],
            npx: PackageDistribution(package: "test"),
        )

        let platform = Platform(os: .darwin, arch: .aarch64)
        if case let .binary(target) = distribution.preferred(for: platform) {
            XCTAssertEqual(target.cmd, "./a")
        } else {
            XCTFail("Expected binary distribution")
        }
    }

    func testDistributionFallsBackToNpx() {
        let distribution = Distribution(
            binary: ["linux-x86_64": BinaryTarget(archive: "https://example.com/a.tar.gz", cmd: "./a")],
            npx: PackageDistribution(package: "test-pkg"),
        )

        let platform = Platform(os: .darwin, arch: .aarch64)
        if case let .npx(pkg) = distribution.preferred(for: platform) {
            XCTAssertEqual(pkg.package, "test-pkg")
        } else {
            XCTFail("Expected npx distribution")
        }
    }

    func testDistributionFallsBackToUvx() {
        let distribution = Distribution(
            uvx: PackageDistribution(package: "python-agent"),
        )

        let platform = Platform(os: .darwin, arch: .aarch64)
        if case let .uvx(pkg) = distribution.preferred(for: platform) {
            XCTAssertEqual(pkg.package, "python-agent")
        } else {
            XCTFail("Expected uvx distribution")
        }
    }

    func testDistributionReturnsNilWhenUnsupported() {
        let distribution = Distribution(
            binary: ["windows-x86_64": BinaryTarget(archive: "https://example.com/a.zip", cmd: "a.exe")],
        )

        let platform = Platform(os: .darwin, arch: .aarch64)
        XCTAssertNil(distribution.preferred(for: platform))
    }

    // MARK: - Installed Agent Tests

    func testInstalledAgentEncoding() throws {
        let installed = InstalledAgent(
            id: "test",
            name: "Test",
            version: "1.0.0",
            executablePath: "/usr/local/bin/test",
            arguments: ["--acp"],
            environment: ["KEY": "value"],
        )

        let data = try JSONEncoder().encode(installed)
        let decoded = try JSONDecoder().decode(InstalledAgent.self, from: data)

        XCTAssertEqual(decoded.id, "test")
        XCTAssertEqual(decoded.executablePath, "/usr/local/bin/test")
        XCTAssertEqual(decoded.arguments, ["--acp"])
        XCTAssertEqual(decoded.environment["KEY"], "value")
    }

    // MARK: - Registry Client Tests (offline)

    private func makeOfflineRegistryClient() -> RegistryClient {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-886-registry-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.removeItem(at: tempDirectory)
            }
            RegistryURLProtocol.reset()
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryURLProtocol.self]
        return RegistryClient(
            session: URLSession(configuration: configuration),
            cacheDirectory: tempDirectory,
        )
    }

    private func installHandler() {
        let payload = """
        {"version":"1.0.0","agents":[{"id":"fixture-agent","name":"Fixture Agent","version":"1.0.0","description":"offline fixture","distribution":{"npx":{"package":"fixture"}}}],"extensions":[]}
        """
        RegistryURLProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"],
            ))
            return (response, Data(payload.utf8))
        }
    }

    /// Replaced network-dependent `testRegistryClientFetchFromNetwork`: the
    /// required suite must run without external network access.
    func testRegistryClientFetchOffline() async throws {
        installHandler()
        let client = makeOfflineRegistryClient()

        let registry = try await client.fetch()

        XCTAssertEqual(registry.version, "1.0.0")
        XCTAssertFalse(registry.agents.isEmpty)
        XCTAssertEqual(registry.agents[0].id, "fixture-agent")
        XCTAssertEqual(registry.agents[0].name, "Fixture Agent")
    }

    /// Replaced network-dependent `testRegistryClientAgentLookup`.
    func testRegistryClientAgentLookupOffline() async throws {
        installHandler()
        let client = makeOfflineRegistryClient()
        let registry = try await client.fetch()
        let knownAgent = try XCTUnwrap(registry.agents.first)

        let agent = try await client.agent(id: knownAgent.id)
        XCTAssertNotNil(agent)
        XCTAssertEqual(agent?.id, knownAgent.id)
        XCTAssertEqual(agent?.name, knownAgent.name)

        let notFound = try await client.agent(id: "non-existent-agent")
        XCTAssertNil(notFound)
    }

    /// Replaced network-dependent `testRegistryClientCaching`; also proves the
    /// disk cache stays inside the injected, test-local cache directory.
    func testRegistryClientCachingIsTestLocal() async throws {
        installHandler()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-886-registry-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.removeItem(at: tempDirectory)
            }
            RegistryURLProtocol.reset()
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryURLProtocol.self]
        let client = RegistryClient(
            session: URLSession(configuration: configuration),
            cacheDirectory: tempDirectory,
        )

        let registry1 = try await client.fetch()
        let registry2 = try await client.fetch()

        XCTAssertEqual(registry1.version, registry2.version)
        XCTAssertEqual(registry1.agents.count, registry2.agents.count)

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertFalse(contents.isEmpty, "cache must live in the injected test-local directory")
    }

    /// Replaced network-dependent `testRegistryClientForceRefresh`.
    func testRegistryClientForceRefreshOffline() async throws {
        installHandler()
        let client = makeOfflineRegistryClient()

        _ = try await client.fetch()
        let registry = try await client.fetch(forceRefresh: true)

        XCTAssertEqual(registry.agents.first?.id, "fixture-agent")
    }
}
