import Foundation

public enum BuiltInCollectionIdentity: String, CaseIterable, Sendable {
    case recents
    case allTags = "all_tags"

    public var packageFilename: String {
        switch self {
        case .recents:
            "recents.voycoll"
        case .allTags:
            "all-tags.voycoll"
        }
    }

    public var collectionName: String {
        switch self {
        case .recents:
            "Recents"
        case .allTags:
            "All Tags"
        }
    }

    public static func canonicalRootURL(applicationSupportURL: URL) -> URL {
        applicationSupportURL
            .appendingPathComponent("Voyager", isDirectory: true)
            .appendingPathComponent("Collections", isDirectory: true)
            .appendingPathComponent("BuiltIn", isDirectory: true)
    }

    public static func classify(
        packageURL: URL,
        applicationSupportURL: URL,
    ) -> Self? {
        let packagePath = packageURL.standardizedFileURL.path

        return allCases.first { identity in
            identity.canonicalPackageURL(applicationSupportURL: applicationSupportURL)
                .standardizedFileURL.path == packagePath
        }
    }

    public func canonicalPackageURL(applicationSupportURL: URL) -> URL {
        Self.canonicalRootURL(applicationSupportURL: applicationSupportURL)
            .appendingPathComponent(packageFilename, isDirectory: true)
    }
}
