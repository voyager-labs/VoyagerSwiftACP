import Foundation

extension ComposerScopeUtils {
    static func normalizeScopePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rootScopePath }

        let standardized = (trimmed as NSString).standardizingPath
        guard !standardized.isEmpty, standardized != "." else { return rootScopePath }
        guard standardized != rootScopePath else { return rootScopePath }

        return standardized.hasSuffix(rootScopePath)
            ? String(standardized.dropLast())
            : standardized
    }
}
