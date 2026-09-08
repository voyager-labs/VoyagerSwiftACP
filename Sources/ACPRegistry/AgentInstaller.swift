import Foundation

// MARK: - Agent Installer

public actor AgentInstaller {
    private let session: URLSession
    private let installDirectory: URL

    // MARK: - Initialization

    public init(
        session: URLSession = .shared,
        installDirectory: URL? = nil,
    ) {
        self.session = session
        self.installDirectory = installDirectory ?? Self.defaultInstallDirectory
    }

    private static var defaultInstallDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ACPAgents", isDirectory: true)
    }

    // MARK: - Public API

    /// Installs an agent from the registry
    public func install(_ agent: RegistryAgent, platform: Platform = .current) async throws -> InstalledAgent {
        guard let method = agent.distribution.preferred(for: platform) else {
            throw RegistryError.unsupportedPlatform
        }

        switch method {
        case let .binary(target):
            return try await installBinary(agent: agent, target: target)
        case let .npx(pkg):
            // `Process.executableURL` needs a real path, so bare launcher
            // names go through /usr/bin/env with the launcher as argv[0].
            return InstalledAgent(
                id: agent.id,
                name: agent.name,
                version: agent.version,
                executablePath: "/usr/bin/env",
                arguments: ["npx", pkg.package] + (pkg.args ?? []),
                environment: pkg.env ?? [:],
            )
        case let .uvx(pkg):
            return InstalledAgent(
                id: agent.id,
                name: agent.name,
                version: agent.version,
                executablePath: "/usr/bin/env",
                arguments: ["uvx", pkg.package] + (pkg.args ?? []),
                environment: pkg.env ?? [:],
            )
        }
    }

    /// Checks if an agent is already installed
    public func isInstalled(_ agent: RegistryAgent) -> Bool {
        guard let agentDir = try? containedAgentDirectory(agent.id) else {
            return false
        }
        return FileManager.default.fileExists(atPath: agentDir.path)
    }

    /// Returns the installed agent info if available
    public func installedAgent(_ agentId: String) -> InstalledAgent? {
        guard let agentDir = try? containedAgentDirectory(agentId) else {
            return nil
        }
        let metadataFile = agentDir.appendingPathComponent("metadata.json")

        guard let data = try? Data(contentsOf: metadataFile),
              let installed = try? JSONDecoder().decode(InstalledAgent.self, from: data)
        else {
            return nil
        }

        return installed
    }

    /// Lists all installed agents
    public func installedAgents() -> [InstalledAgent] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: nil,
        ) else {
            return []
        }

        return contents.compactMap { dir in
            let metadataFile = dir.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataFile),
                  let installed = try? JSONDecoder().decode(InstalledAgent.self, from: data)
            else {
                return nil
            }
            return installed
        }
    }

    /// Uninstalls an agent
    public func uninstall(_ agentId: String) throws {
        let agentDir = try containedAgentDirectory(agentId)
        try FileManager.default.removeItem(at: agentDir)
    }

    // MARK: - Path Containment

    /// Registry values and public-API arguments are peer-supplied, so every file
    /// operation resolves through a containment check before touching disk.
    private func containedAgentDirectory(_ agentId: String) throws -> URL {
        try containedPath(agentId, inside: installDirectory)
    }

    private func containedPath(_ component: String, inside root: URL) throws -> URL {
        let rootPath = root.standardizedFileURL.path
        let resolvedPath = root
            .appendingPathComponent(component)
            .standardizedFileURL.path

        guard !component.isEmpty,
              resolvedPath != rootPath,
              resolvedPath.hasPrefix(rootPath + "/")
        else {
            throw RegistryError.invalidIdentifier(component)
        }
        return root.appendingPathComponent(component)
    }

    // MARK: - Private Methods

    enum BinaryArchiveKind: Equatable {
        case zip
        case tarGzip
        case tarBzip2
        case rawBinary
    }

    private func installBinary(agent: RegistryAgent, target: BinaryTarget) async throws -> InstalledAgent {
        guard let archiveURL = target.archiveURL else {
            throw RegistryError.downloadFailed(URLError(.badURL))
        }

        // Validate the final live layout up front (id and cmd containment).
        let agentDir = try containedAgentDirectory(agent.id)
        let executablePath = try containedPath(target.cmd, inside: agentDir).path

        // Stage beside the live install so a failed download, extraction, or
        // metadata write can never destroy an existing installation.
        let stagingDir = try containedPath(".staging-\(UUID().uuidString)", inside: installDirectory)
        let stagedExecutablePath = try containedPath(target.cmd, inside: stagingDir).path

        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            // Download archive
            let (tempURL, response) = try await session.download(from: archiveURL)

            // A completed download is not a successful download: only a 2xx
            // HTTP response may be promoted to an executable payload.
            guard let httpResponse = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: tempURL)
                throw RegistryError.invalidResponse
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw RegistryError.httpError(statusCode: httpResponse.statusCode)
            }

            // Extract archive or install raw binary directly.
            try await installBinaryPayload(
                from: tempURL,
                to: stagingDir,
                executablePath: stagedExecutablePath,
                archiveURL: archiveURL,
            )

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            // Make executable and remove quarantine
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: stagedExecutablePath,
            )
            removeQuarantineAttribute(from: stagedExecutablePath)

            let installed = InstalledAgent(
                id: agent.id,
                name: agent.name,
                version: agent.version,
                executablePath: executablePath,
                arguments: target.args ?? [],
                environment: target.env ?? [:],
            )

            // Save metadata into staging so the promoted directory is complete.
            let stagedMetadataFile = stagingDir.appendingPathComponent("metadata.json")
            let data = try JSONEncoder().encode(installed)
            try data.write(to: stagedMetadataFile)

            // Promote through a backup so a failure between the two renames
            // can restore the previous installation instead of losing both.
            let backupDir = try containedPath(".backup-\(UUID().uuidString)", inside: installDirectory)
            var backedUp = false
            if FileManager.default.fileExists(atPath: agentDir.path) {
                try FileManager.default.moveItem(at: agentDir, to: backupDir)
                backedUp = true
            }
            do {
                try FileManager.default.moveItem(at: stagingDir, to: agentDir)
            } catch {
                // The staging rename failed with the live directory moved
                // aside: put the previous installation back before failing.
                if backedUp, !FileManager.default.fileExists(atPath: agentDir.path) {
                    try? FileManager.default.moveItem(at: backupDir, to: agentDir)
                }
                throw error
            }
            if backedUp {
                try? FileManager.default.removeItem(at: backupDir)
            }

            return installed
        } catch {
            // Only staging is cleaned here: a leftover backup may be the last
            // remaining copy of the previous installation.
            try? FileManager.default.removeItem(at: stagingDir)
            throw error
        }
    }

    private func installBinaryPayload(
        from source: URL,
        to destination: URL,
        executablePath: String,
        archiveURL: URL,
    ) async throws {
        switch Self.binaryArchiveKind(for: archiveURL) {
        case .rawBinary:
            let executableURL = URL(fileURLWithPath: executablePath)
            let executableDirectory = executableURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: executableURL.path) {
                try FileManager.default.removeItem(at: executableURL)
            }
            try FileManager.default.moveItem(at: source, to: executableURL)
        case .zip, .tarGzip, .tarBzip2:
            try await extractArchive(from: source, to: destination, archiveURL: archiveURL)
        }
    }

    private func extractArchive(from source: URL, to destination: URL, archiveURL: URL) async throws {
        let archiveKind = Self.binaryArchiveKind(for: archiveURL)

        let process = Process()
        let pipe = Pipe()
        process.standardError = pipe

        switch archiveKind {
        case .zip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", source.path, "-d", destination.path]
        case .tarGzip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", source.path, "-C", destination.path]
        case .tarBzip2:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xjf", source.path, "-C", destination.path]
        case .rawBinary:
            throw RegistryError.extractionFailed(NSError(
                domain: "ACPRegistry",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Raw binaries should not be extracted"],
            ))
        }

        try process.run()

        // Drain stderr concurrently and bound the wait: an extractor that
        // writes more than the pipe capacity must not deadlock this actor,
        // and a hung extractor must not block it forever.
        let diagnostics = CappedBuffer(capacity: Self.extractorDiagnosticByteLimit)
        let drainStatus = DrainStatus()
        drain(pipe: pipe, into: diagnostics, status: drainStatus)

        let exited = await waitForExit(process, timeout: Self.extractionTimeoutSeconds)
        if !exited {
            process.terminate()
            let terminatedAfterTerm = await waitForExit(process, timeout: Self.termGraceSeconds)
            if !terminatedAfterTerm {
                if process.processIdentifier > 0 {
                    kill(process.processIdentifier, SIGKILL)
                }
                _ = await waitForExit(process, timeout: Self.killGraceSeconds)
            }
        }
        // Process death closes the write end, so the drain completes; give it
        // a bounded window to finish collecting the last diagnostics.
        let drainDeadline = Date().addingTimeInterval(Self.drainGraceSeconds)
        while !drainStatus.isFinished, Date() < drainDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? pipe.fileHandleForReading.close()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: diagnostics.data, encoding: .utf8) ?? "Unknown error"
            throw RegistryError.extractionFailed(NSError(
                domain: "ACPRegistry",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMessage],
            ))
        }
    }

    private static let extractionTimeoutSeconds: TimeInterval = 120.0
    private static let termGraceSeconds: TimeInterval = 2.0
    private static let killGraceSeconds: TimeInterval = 1.0
    private static let drainGraceSeconds: TimeInterval = 2.0
    private static let extractorDiagnosticByteLimit = 65536

    private func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return !process.isRunning
    }

    private func drain(pipe: Pipe, into buffer: CappedBuffer, status: DrainStatus) {
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = try? handle.read(upToCount: 65536)
                guard let chunk, !chunk.isEmpty else { break }
                buffer.append(chunk)
            }
            status.finish()
        }
    }

    /// Completion flag for a background drain worker.
    private final class DrainStatus: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false

        func finish() {
            lock.withLock { finished = true }
        }

        var isFinished: Bool {
            lock.withLock { finished }
        }
    }

    /// Thread-safe byte buffer that retains at most `capacity` bytes and
    /// discards the rest, so chatty subprocess output cannot grow unbounded.
    private final class CappedBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        private let capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
        }

        var data: Data {
            lock.withLock { storage }
        }

        func append(_ value: Data) {
            lock.lock()
            defer { lock.unlock() }
            guard storage.count < capacity else { return }
            storage.append(value.prefix(capacity - storage.count))
        }
    }

    static func binaryArchiveKind(for archiveURL: URL) -> BinaryArchiveKind {
        // Detect from the percent-decoded URL path only: query strings and
        // fragments (signed CDN URLs like `agent.zip?token=…`) must not make a
        // real archive fall through to raw-binary execution.
        let path = archiveURL.path.lowercased()

        if path.hasSuffix(".zip") {
            return .zip
        }

        if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") {
            return .tarGzip
        }

        if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") {
            return .tarBzip2
        }

        return .rawBinary
    }

    /// Remove macOS quarantine attribute to avoid security prompts
    private func removeQuarantineAttribute(from path: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        #endif
    }
}

// MARK: - Installed Agent

public struct InstalledAgent: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        id: String,
        name: String,
        version: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }
}
