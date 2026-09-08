#if os(macOS)
import Foundation
import os.log

public enum ShellEnvironment: Sendable {
    private final class ShellCacheState: @unchecked Sendable {
        /// Invariant: `condition` guards `cachedEnvironment` and `isLoading`;
        /// every read and write happens while holding the condition's lock.
        let condition = NSCondition()
        var cachedEnvironment: [String: String]?
        var isLoading = false
    }

    /// Thread-safe byte buffer that retains at most `capacity` bytes and
    /// discards anything beyond, so a chatty login shell cannot grow the
    /// process memory without bound while it is being drained.
    private final class DataBox: @unchecked Sendable {
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

    private static let shellLoadTimeoutSeconds: TimeInterval = 10.0
    private static let termGraceSeconds: TimeInterval = 2.0
    private static let killGraceSeconds: TimeInterval = 1.0
    private static let drainGraceSeconds: TimeInterval = 2.0
    private static let retainedOutputByteLimit = 1_000_000

    private static let state = ShellCacheState()

    /// Get user's shell environment (cached after first load)
    /// Warning: On main thread, returns immediately with potentially incomplete environment.
    /// Use `loadUserShellEnvironmentAsync()` for guaranteed complete environment.
    public static func loadUserShellEnvironment() -> [String: String] {
        if Thread.isMainThread {
            DispatchQueue.global(qos: .utility).async {
                _ = loadUserShellEnvironmentBlocking()
            }
            return ProcessInfo.processInfo.environment
        }
        return loadUserShellEnvironmentBlocking()
    }

    /// Async version that guarantees the full user shell environment is loaded.
    /// Safe to call from any context (main thread, actors, etc.)
    public static func loadUserShellEnvironmentAsync() async -> [String: String] {
        if let cached = cachedSnapshot() {
            return cached
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let env = loadUserShellEnvironmentBlocking()
                continuation.resume(returning: env)
            }
        }
    }

    /// Blocking version that waits for environment to be loaded.
    /// Do NOT call from main thread - use loadUserShellEnvironmentAsync() instead.
    public static func loadUserShellEnvironmentBlocking() -> [String: String] {
        state.condition.lock()

        if let cached = state.cachedEnvironment {
            state.condition.unlock()
            return cached
        }

        if state.isLoading {
            while true {
                if let environment = state.cachedEnvironment {
                    state.condition.unlock()
                    return environment
                }
                state.condition.wait()
            }
        }

        state.isLoading = true
        state.condition.unlock()

        let env = loadEnvironmentFromShell()

        state.condition.lock()
        state.cachedEnvironment = env
        state.isLoading = false
        state.condition.broadcast()
        state.condition.unlock()

        return env
    }

    /// Preload environment in background (call at app launch)
    public static func preloadEnvironment() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = loadUserShellEnvironmentBlocking()
        }
    }

    /// Force reload of environment (e.g., after user changes shell config)
    public static func reloadEnvironment() {
        state.condition.lock()
        state.cachedEnvironment = nil
        state.condition.unlock()
        preloadEnvironment()
    }

    private static func cachedSnapshot() -> [String: String]? {
        state.condition.lock()
        defer { state.condition.unlock() }
        return state.cachedEnvironment
    }

    private static func loadEnvironmentFromShell() -> [String: String] {
        let shell = getLoginShell()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        let shellName = (shell as NSString).lastPathComponent
        let arguments: [String] = switch shellName {
        case "fish":
            ["-l", "-c", "env"]
        case "zsh", "bash":
            ["-l", "-i", "-c", "env"]
        case "sh":
            ["-l", "-c", "env"]
        default:
            ["-c", "env"]
        }

        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Drain both pipes concurrently while the shell runs: waiting for exit
        // before reading deadlocks on any login shell whose rc prints more
        // than the pipe capacity. Retention is capped so a chatty rc cannot
        // grow the process memory without bound; stderr is never retained.
        let outputBox = DataBox(capacity: Self.retainedOutputByteLimit)
        let drainGroup = DispatchGroup()
        drain(pipe: pipe, into: outputBox, group: drainGroup)
        drain(pipe: errorPipe, into: DataBox(capacity: 0), group: drainGroup)

        do {
            try process.run()
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            return ProcessInfo.processInfo.environment
        }

        // A hung login shell is bounded: TERM, then KILL, then give up.
        let deadline = Date().addingTimeInterval(Self.shellLoadTimeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            if !waitForExit(process, timeout: Self.termGraceSeconds) {
                if process.processIdentifier > 0 {
                    kill(process.processIdentifier, SIGKILL)
                }
                _ = waitForExit(process, timeout: Self.killGraceSeconds)
            }
        }
        // Process death (or kill) closes the write ends, so the drains finish.
        _ = drainGroup.wait(timeout: .now() + Self.drainGraceSeconds)
        try? pipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        let shellEnv = Self.parseEnvironmentOutput(outputBox.data)
        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    private static func parseEnvironmentOutput(_ output: Data) -> [String: String] {
        var shellEnv: [String: String] = [:]
        guard let text = String(data: output, encoding: .utf8) else {
            return shellEnv
        }
        for line in text.split(separator: "\n") {
            if let equalsIndex = line.firstIndex(of: "=") {
                let key = String(line[..<equalsIndex])
                let value = String(line[line.index(after: equalsIndex)...])
                shellEnv[key] = value
            }
        }
        return shellEnv
    }

    private static func drain(pipe: Pipe, into box: DataBox, group: DispatchGroup) {
        let handle = pipe.fileHandleForReading
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            // Chunked until EOF — the shell's exit (bounded above) closes the
            // write end, so this always completes — with the box enforcing the
            // retention cap beyond which bytes are discarded.
            while true {
                let chunk = try? handle.read(upToCount: 65536)
                guard let chunk, !chunk.isEmpty else { break }
                box.append(chunk)
            }
            group.leave()
        }
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !process.isRunning
    }

    private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }
}
#endif
