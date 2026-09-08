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

    // MARK: - Agent Installer Tests (offline)

    private func makeOfflineInstaller() -> (installer: AgentInstaller, installDirectory: URL) {
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-886-install-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: installDirectory.path) {
                try? FileManager.default.removeItem(at: installDirectory)
            }
            RegistryURLProtocol.reset()
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryURLProtocol.self]
        let installer = AgentInstaller(
            session: URLSession(configuration: configuration),
            installDirectory: installDirectory,
        )
        return (installer, installDirectory)
    }

    private func makeBinaryInstallAgent(archive: String, cmd: String = "agent") -> RegistryAgent {
        RegistryAgent(
            id: "binary-agent",
            name: "Binary Agent",
            version: "1.0.0",
            description: "offline binary fixture",
            distribution: Distribution(
                binary: [Platform.current.identifier: BinaryTarget(archive: archive, cmd: cmd)],
            ),
        )
    }

    /// A peer-supplied agent id that escapes the install root must be rejected
    /// before any file operation, not resolved into a deletable path outside it.
    func testUninstallRejectsPathTraversal() async throws {
        let context = makeOfflineInstaller()
        let victimDirectory = context.installDirectory.deletingLastPathComponent()
            .appendingPathComponent("voy-886-victim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: victimDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: victimDirectory.path) {
                try? FileManager.default.removeItem(at: victimDirectory)
            }
        }

        do {
            try await context.installer.uninstall("../\(victimDirectory.lastPathComponent)")
            XCTFail("Expected invalidIdentifier for a traversal agent id")
        } catch let error as RegistryError {
            guard case .invalidIdentifier = error else {
                return XCTFail("Unexpected RegistryError: \(error)")
            }
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: victimDirectory.path),
            "the directory targeted through ../ must remain untouched",
        )
    }

    /// A completed download is not a successful install: non-2xx responses must
    /// fail before their body can be promoted to an executable.
    func testInstallBinaryRejectsHTTPErrorStatus() async throws {
        RegistryURLProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"],
            ))
            return (response, Data("<html>not found</html>".utf8))
        }
        let context = makeOfflineInstaller()
        let agent = makeBinaryInstallAgent(archive: "https://registry.fixture/agent.zip")

        do {
            _ = try await context.installer.install(agent)
            XCTFail("Expected httpError for a 404 download")
        } catch let error as RegistryError {
            guard case let .httpError(statusCode) = error else {
                return XCTFail("Unexpected RegistryError: \(error)")
            }
            XCTAssertEqual(statusCode, 404)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: context.installDirectory.appendingPathComponent(agent.id).path,
            ),
            "a failed install must not leave a staging directory behind",
        )
    }

    /// Lookup helpers treat escaping ids as absent instead of resolving them
    /// outside the install root.
    func testInstalledAgentLookupRejectsPathTraversal() async {
        let context = makeOfflineInstaller()

        let installed = await context.installer.installedAgent("../../outside")
        XCTAssertNil(installed)

        let traversalAgent = makeBinaryInstallAgent(archive: "https://registry.fixture/agent.zip")
        let agentWithTraversalId = RegistryAgent(
            id: "../../outside",
            name: traversalAgent.name,
            version: traversalAgent.version,
            description: traversalAgent.description,
            distribution: traversalAgent.distribution,
        )
        let isInstalled = await context.installer.isInstalled(agentWithTraversalId)
        XCTAssertFalse(isInstalled)
    }

    /// An update that fails mid-flight (404 download) must leave the existing
    /// installation untouched: staging happens outside the live directory.
    func testFailedUpdatePreservesLiveInstall() async throws {
        let context = makeOfflineInstaller()
        let agent = makeBinaryInstallAgent(archive: "https://registry.fixture/agent")
        let installDirectory = context.installDirectory
        let liveAgentDir = installDirectory.appendingPathComponent(agent.id)
        let liveExecutable = liveAgentDir.appendingPathComponent("agent")
        let liveMetadata = liveAgentDir.appendingPathComponent("metadata.json")

        var downloadCount = 0
        RegistryURLProtocol.handler = { request in
            downloadCount += 1
            let statusCode = downloadCount == 1 ? 200 : 404
            let body = downloadCount == 1 ? Data("#!/bin/sh\necho live\n".utf8) : Data("<html>not found</html>".utf8)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/octet-stream"],
            ))
            return (response, body)
        }

        // First install succeeds (raw binary: the URL has no archive suffix).
        _ = try await context.installer.install(agent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveExecutable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveMetadata.path))

        // Second install (update) fails at download; the live copy must survive.
        do {
            _ = try await context.installer.install(agent)
            XCTFail("expected httpError for the 404 update")
        } catch let error as RegistryError {
            guard case .httpError = error else {
                return XCTFail("Unexpected RegistryError: \(error)")
            }
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: liveExecutable.path),
            "the failed update must not delete the live installation",
        )
        let liveData = try Data(contentsOf: liveExecutable)
        XCTAssertEqual(String(data: liveData, encoding: .utf8), "#!/bin/sh\necho live\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveMetadata.path))

        let entries = try FileManager.default.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: nil,
        )
        XCTAssertEqual(entries.count, 1, "no staging directory may remain after a failed update")
    }

    /// Archive detection uses the URL path only: signed CDN URLs with query
    /// strings must still classify as archives, not raw binaries.
    func testArchiveKindIgnoresQueryAndFragment() throws {
        let zipWithURL = try XCTUnwrap(URL(string: "https://cdn.example.com/agent.zip?token=abc&expires=1"))
        XCTAssertEqual(AgentInstaller.binaryArchiveKind(for: zipWithURL), .zip)

        let tarWithURL = try XCTUnwrap(URL(string: "https://cdn.example.com/agent.tar.gz?sig=ff"))
        XCTAssertEqual(AgentInstaller.binaryArchiveKind(for: tarWithURL), .tarGzip)

        let rawWithURL = try XCTUnwrap(URL(string: "https://cdn.example.com/agent?token=abc"))
        XCTAssertEqual(AgentInstaller.binaryArchiveKind(for: rawWithURL), .rawBinary)
    }
}
