import AppKit
import Foundation

final class CloudStorageApplicationIconIndex: @unchecked Sendable {
    private struct ApplicationCandidate {
        let aliases: Set<String>
        let url: URL
    }

    private let fileManager: FileManager
    private let workspace: NSWorkspace
    private let lock = NSLock()
    private var applicationCandidates: [ApplicationCandidate]?
    private var cachedIcons: [String: NSImage] = [:]

    init(fileManager: FileManager, workspace: NSWorkspace) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func icon(forProviderRoot url: URL) -> NSImage? {
        guard url.deletingLastPathComponent().lastPathComponent == "CloudStorage" else {
            return nil
        }

        let providerName = Self.normalizedName(url.lastPathComponent)
        guard providerName.count >= 5 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let cachedIcon = cachedIcons[providerName] {
            return cachedIcon
        }

        if applicationCandidates == nil {
            applicationCandidates = loadApplicationCandidates()
        }

        var bestMatch: (url: URL, aliasLength: Int)?
        for candidate in applicationCandidates ?? [] {
            for alias in candidate.aliases where providerName.hasPrefix(alias) {
                if alias.count > (bestMatch?.aliasLength ?? 0) {
                    bestMatch = (candidate.url, alias.count)
                }
            }
        }

        guard let applicationURL = bestMatch?.url else { return nil }
        let icon = workspace.icon(forFile: applicationURL.path)
        icon.isTemplate = false
        cachedIcons[providerName] = icon
        return icon
    }

    private func loadApplicationCandidates() -> [ApplicationCandidate] {
        let domains: FileManager.SearchPathDomainMask = [
            .localDomainMask,
            .userDomainMask,
            .systemDomainMask,
        ]
        let applicationDirectories = fileManager.urls(for: .applicationDirectory, in: domains)
        var candidates: [ApplicationCandidate] = []

        for directory in applicationDirectories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
            ) else { continue }

            for case let applicationURL as URL in enumerator {
                guard applicationURL.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()

                let bundle = Bundle(url: applicationURL)
                let names = [
                    bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                    bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                    applicationURL.deletingPathExtension().lastPathComponent,
                ].compactMap(\.self)
                let aliases = Set(names.map(Self.normalizedName))
                    .filter { $0.count >= 5 }

                guard !aliases.isEmpty else { continue }
                candidates.append(ApplicationCandidate(aliases: aliases, url: applicationURL))
            }
        }

        return candidates
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX"),
            )
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
