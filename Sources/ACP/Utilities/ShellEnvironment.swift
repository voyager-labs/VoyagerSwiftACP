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
            while state.cachedEnvironment == nil {
                state.condition.wait()
            }
            let env = state.cachedEnvironment!
            state.condition.unlock()
            return env
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

        var shellEnv: [String: String] = [:]

        do {
            try process.run()
            process.waitUntilExit()

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    if let equalsIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalsIndex])
                        let value = String(line[line.index(after: equalsIndex)...])
                        shellEnv[key] = value
                    }
                }
            }
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            return ProcessInfo.processInfo.environment
        }

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }
}
#endif
