import Foundation

/// Resolves the base directory under which `.voyager/` will be created
/// for AI connection persistence.
///
/// Resolution order:
/// 1. `VOYAGER_PROJECT_ROOT` environment variable (if set and non-empty)
/// 2. Inferred project root by walking up from the app bundle
/// 3. Fallback to `FileManager.default.homeDirectoryForCurrentUser`
public enum AiConnectionRootResolver {
    public static func resolveBaseRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
    ) -> URL {
        if let envRoot = environment["VOYAGER_PROJECT_ROOT"], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot)
        }

        if let inferred = inferProjectRoot(from: bundle.bundleURL) {
            return inferred
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func inferProjectRoot(from start: URL) -> URL? {
        let fm = FileManager.default
        var current = start
        let rootPath = current.pathComponents.first ?? "/"

        while true {
            let macosPath = current.appendingPathComponent("apps/macos/Voyager")
            let xcodeprojPath = current.appendingPathComponent(
                "apps/macos/Voyager/Voyager.xcodeproj",
            )
            if fm.fileExists(atPath: macosPath.path),
               fm.fileExists(atPath: xcodeprojPath.path)
            {
                return current
            }

            if current.path == rootPath {
                return nil
            }
            current.deleteLastPathComponent()
        }
    }
}
