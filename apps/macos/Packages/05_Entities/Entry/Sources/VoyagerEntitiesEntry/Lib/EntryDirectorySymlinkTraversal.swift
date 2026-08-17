import Foundation

struct EntryDirectoryURLCandidate {
    let sourceURL: URL
    let lexicalURL: URL
}

enum EntryDirectorySymlinkTraversal {
    static func resolve(_ lexicalURL: URL) -> URL {
        lexicalURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func candidates(_ urls: [URL], lexicalRoot: URL) -> [EntryDirectoryURLCandidate] {
        urls.map { sourceURL in
            EntryDirectoryURLCandidate(
                sourceURL: sourceURL,
                lexicalURL: lexicalRoot.appendingPathComponent(sourceURL.lastPathComponent),
            )
        }
    }

    static func resolveRoot(
        _ lexicalRoot: URL,
        ancestors: [URL],
        resolver: @Sendable (URL) -> URL,
    ) throws -> URL {
        let resolvedRoot = resolver(lexicalRoot.absoluteURL.standardizedFileURL)
        let comparisonRoot = resolvedRoot.absoluteURL.standardizedFileURL
        let resolvedAncestors = ancestors.map {
            resolver($0.absoluteURL.standardizedFileURL).absoluteURL.standardizedFileURL
        }
        if resolvedAncestors.contains(comparisonRoot) {
            throw EntryDirectorySymlinkTraversalError.ancestorCycle
        }
        return resolvedRoot
    }
}

enum EntryDirectorySymlinkTraversalError: Error {
    case ancestorCycle
}
